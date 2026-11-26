import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum SidebarMode: String { case files, outline }

/// One tab: a viewer that shows one Markdown file at a time and can move
/// between files (with back/forward history), plus its sidebar and find state.
@MainActor
final class DocumentModel: ObservableObject {
    @Published private(set) var fileURL: URL
    @Published private(set) var headings: [MarkdownRenderer.Heading] = []
    @Published private(set) var title: String?

    // Sidebar
    @Published var sidebarMode: SidebarMode { didSet { saveSidebarState() } }
    @Published var columnVisibility: NavigationSplitViewVisibility { didSet { saveSidebarState() } }
    @Published private(set) var rootURL: URL
    @Published private(set) var tree: [FileNode] = []
    @Published var expanded: Set<URL> = []

    // History
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private var backStack: [URL] = [] { didSet { canGoBack = !backStack.isEmpty } }
    private var forwardStack: [URL] = [] { didSet { canGoForward = !forwardStack.isEmpty } }

    // Find
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published private(set) var findCount = 0
    @Published private(set) var findIndex = 0
    /// Bumped to ask the find field to take focus again.
    @Published private(set) var findFocusRequest = 0

    private(set) weak var webView: WKWebView?
    private(set) var isLoadingPage = false
    private var pageLoaded = false
    private var hasFocusedOnce = false

    private var text = ""
    private var html = ""
    private var watcher: FileWatcher?
    private var observers: [NSObjectProtocol] = []
    private var lastStyle = UserDefaults.standard.pageStyle
    private var lastOptions = UserDefaults.standard.renderOptions
    private var scanGeneration = 0

    private static let renderer = MarkdownRenderer()

    /// - Parameters:
    ///   - root: folder for the Files sidebar; defaults to the file's project root.
    ///   - inheriting: tab whose sidebar state the new tab copies.
    init(fileURL: URL, root: URL? = nil, inheriting other: DocumentModel? = nil) {
        let url = fileURL.standardizedFileURL
        self.fileURL = url
        self.rootURL = (root ?? FolderScanner.projectRoot(for: url)).standardizedFileURL
        if let other {
            sidebarMode = other.sidebarMode
            columnVisibility = other.columnVisibility
        } else {
            let d = UserDefaults.standard
            sidebarMode = SidebarMode(rawValue: d.string(forKey: SettingsKey.sidebarMode) ?? "") ?? .files
            columnVisibility = d.bool(forKey: SettingsKey.sidebarVisible) ? .all : .detailOnly
        }
        text = Self.read(url) ?? ""
        render()
        watch()
        expandAncestors(of: url)
        rescan()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var displayName: String { fileURL.lastPathComponent }

    /// Base URL for the page, so relative images and links resolve next to the file.
    var baseURL: URL? {
        guard let path = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(LocalFileSchemeHandler.scheme)://\(path)")
    }

    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Web view

    func attach(_ webView: WKWebView) {
        self.webView = webView
        loadPage()
    }

    private func loadPage() {
        guard let webView else { return }
        pageLoaded = false
        isLoadingPage = true
        webView.loadHTMLString(fullPage(), baseURL: baseURL)
    }

    func pageDidLoad() {
        isLoadingPage = false
        pageLoaded = true
        if !hasFocusedOnce, let webView {
            hasFocusedOnce = true
            webView.window?.makeFirstResponder(webView)
        }
        if findVisible && !findQuery.isEmpty { find(direction: 0) }
    }

    // MARK: Rendering

    private func render() {
        let output = Self.renderer?.render(text, options: UserDefaults.standard.renderOptions)
            ?? MarkdownRenderer.Output(html: "<p>Renderer failed to load.</p>", headings: [], title: nil)
        html = output.html
        headings = output.headings
        title = output.title
        pushContent()
    }

    func fullPage() -> String {
        MarkdownRenderer.page(body: html, title: displayName, style: UserDefaults.standard.pageStyle)
    }

    private func pushContent() {
        guard pageLoaded, let webView else { return }
        webView.callAsyncJavaScript("marky.setContent(html)", arguments: ["html": html],
                                    in: nil, in: .defaultClient) { [weak self] _ in
            guard let self, self.findVisible, !self.findQuery.isEmpty else { return }
            self.find(direction: 0)
        }
    }

    private func settingsChanged() {
        let style = UserDefaults.standard.pageStyle
        let options = UserDefaults.standard.renderOptions
        if style != lastStyle {
            lastStyle = style
            webView?.callAsyncJavaScript("marky.setStyle(css)", arguments: ["css": style.css],
                                         in: nil, in: .defaultClient)
        }
        if options.highlightCode != lastOptions.highlightCode || options.smartTypography != lastOptions.smartTypography {
            lastOptions = options
            render()
        }
    }

    func reloadFromDisk() {
        guard let newText = Self.read(fileURL), newText != text else { return }
        text = newText
        render()
    }

    private func watch() {
        watcher = FileWatcher(url: fileURL) { [weak self] in
            guard UserDefaults.standard.object(forKey: SettingsKey.autoReload) as? Bool ?? true else { return }
            self?.reloadFromDisk()
        }
    }

    // MARK: Moving between files

    /// Shows another file in this tab.
    func navigate(to url: URL, recordHistory: Bool = true) {
        let url = url.standardizedFileURL
        guard url != fileURL else { return }
        guard let newText = Self.read(url) else {
            NSSound.beep()
            return
        }
        if recordHistory {
            backStack.append(fileURL)
            forwardStack.removeAll()
        }
        fileURL = url
        text = newText
        let output = Self.renderer?.render(text, options: UserDefaults.standard.renderOptions)
        html = output?.html ?? ""
        headings = output?.headings ?? []
        title = output?.title
        watch()
        loadPage()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        if !url.path.hasPrefix(rootURL.path + "/") {
            rootURL = FolderScanner.projectRoot(for: url)
            rescan()
        }
        expandAncestors(of: url)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(fileURL)
        navigate(to: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(fileURL)
        navigate(to: next, recordHistory: false)
    }

    // MARK: Sidebar

    func rescan() {
        scanGeneration += 1
        let generation = scanGeneration
        let root = rootURL
        Task.detached(priority: .userInitiated) {
            let nodes = FolderScanner.scan(root: root)
            await MainActor.run { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                if nodes != self.tree { self.tree = nodes }
            }
        }
    }

    private func expandAncestors(of url: URL) {
        var dir = url.deletingLastPathComponent().standardizedFileURL
        while dir.path.hasPrefix(rootURL.path + "/") {
            expanded.insert(dir)
            dir = dir.deletingLastPathComponent().standardizedFileURL
        }
    }

    func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    func show(_ mode: SidebarMode) {
        sidebarMode = mode
        if columnVisibility == .detailOnly { columnVisibility = .all }
    }

    private func saveSidebarState() {
        let d = UserDefaults.standard
        d.set(sidebarMode.rawValue, forKey: SettingsKey.sidebarMode)
        d.set(columnVisibility != .detailOnly, forKey: SettingsKey.sidebarVisible)
    }

    func scrollTo(headingID id: String) {
        webView?.callAsyncJavaScript("marky.scrollToId(id)", arguments: ["id": id], in: nil, in: .defaultClient)
    }

    func scrollToTop() {
        webView?.callAsyncJavaScript("window.scrollTo(0, 0)", in: nil, in: .defaultClient)
    }

    // MARK: Zoom

    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static var storedZoom: CGFloat {
        let z = UserDefaults.standard.double(forKey: SettingsKey.zoom)
        return z > 0 ? z : 1
    }

    func zoomIn() { setZoom(Self.zoomSteps.first { $0 > currentZoom + 0.001 } ?? Self.zoomSteps.last!) }
    func zoomOut() { setZoom(Self.zoomSteps.last { $0 < currentZoom - 0.001 } ?? Self.zoomSteps.first!) }
    func resetZoom() { setZoom(1) }

    private var currentZoom: CGFloat { webView?.pageZoom ?? Self.storedZoom }

    /// Zoom is global: every open tab follows.
    private func setZoom(_ zoom: CGFloat) {
        UserDefaults.standard.set(Double(zoom), forKey: SettingsKey.zoom)
        for model in WindowManager.shared.allModels { model.webView?.pageZoom = zoom }
    }

    // MARK: Find

    func showFind() {
        findVisible = true
        findFocusRequest += 1
        if !findQuery.isEmpty { find(direction: 0) }
    }

    func closeFind() {
        findVisible = false
        findCount = 0
        findIndex = 0
        webView?.callAsyncJavaScript("marky.clearFind()", in: nil, in: .defaultClient)
        if let webView { webView.window?.makeFirstResponder(webView) }
    }

    func findNext() { if !findVisible { showFind() } else { find(direction: 1) } }
    func findPrevious() { if !findVisible { showFind() } else { find(direction: -1) } }

    /// direction 0 = (re)search from the top, 1 = next, -1 = previous.
    func find(direction: Int) {
        guard let webView else { return }
        webView.callAsyncJavaScript(
            "return marky.find(query, direction)", arguments: ["query": findQuery, "direction": direction],
            in: nil, in: .defaultClient
        ) { [weak self] result in
            guard let self, case let .success(value) = result, let dict = value as? [String: Any] else { return }
            self.findCount = (dict["count"] as? NSNumber)?.intValue ?? 0
            self.findIndex = (dict["index"] as? NSNumber)?.intValue ?? 0
        }
    }

    func useSelectionForFind() {
        webView?.callAsyncJavaScript("return window.getSelection().toString()", in: nil, in: .defaultClient) { [weak self] result in
            guard let self, case let .success(value) = result, let s = value as? String,
                  !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.findQuery = String(s.prefix(200))
            self.showFind()
        }
    }

    // MARK: File actions

    func print() {
        guard let webView, let window = webView.window else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        let op = webView.printOperation(with: info)
        op.jobTitle = displayName
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + ".html"
        panel.directoryURL = fileURL.deletingLastPathComponent()
        let page = fullPage()
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try page.write(to: url, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
        }
        if let window = webView?.window { panel.beginSheetModal(for: window, completionHandler: handler) }
        else { handler(panel.runModal()) }
    }

    func revealInFinder(_ url: URL? = nil) {
        NSWorkspace.shared.activateFileViewerSelecting([url ?? fileURL])
    }

    func openInEditor() {
        let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([fileURL], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL.path, forType: .string)
    }

    // MARK: Links

    /// Opens a link clicked in the page: Markdown files in this tab (or a new
    /// tab with ⌘), everything else with its default app or the browser.
    func open(link url: URL, inNewTab: Bool) {
        guard url.scheme == LocalFileSchemeHandler.scheme else {
            NSWorkspace.shared.open(url)
            return
        }
        let file = URL(fileURLWithPath: url.path).standardizedFileURL
        if file == fileURL { scrollToTop(); return }
        if FolderScanner.isMarkdown(file), FileManager.default.fileExists(atPath: file.path) {
            if inNewTab { WindowManager.shared.open(file, nextTo: webView?.window) }
            else { navigate(to: file) }
        } else if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.open(file)
        } else {
            NSSound.beep()
        }
    }
}
