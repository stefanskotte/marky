import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Per-window state: the Markdown source, its rendering, the web view and find.
@MainActor
final class DocumentModel: ObservableObject {
    let fileURL: URL?
    @Published private(set) var headings: [MarkdownRenderer.Heading] = []
    @Published private(set) var title: String?

    @Published var findVisible = false
    @Published var findQuery = ""
    @Published private(set) var findCount = 0
    @Published private(set) var findIndex = 0
    /// Bumped to ask the find field to take focus again.
    @Published private(set) var findFocusRequest = 0

    weak var webView: WKWebView?

    private var text: String
    private var html = ""
    private var pageLoaded = false
    private var watcher: FileWatcher?
    private var defaultsObserver: NSObjectProtocol?
    private var lastStyle = UserDefaults.standard.pageStyle
    private var lastOptions = UserDefaults.standard.renderOptions

    private static let renderer = MarkdownRenderer()

    init(text: String, fileURL: URL?) {
        self.text = text
        self.fileURL = fileURL
        render()
        if let fileURL {
            watcher = FileWatcher(url: fileURL) { [weak self] in
                guard UserDefaults.standard.object(forKey: SettingsKey.autoReload) as? Bool ?? true else { return }
                self?.reloadFromDisk()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    var displayName: String { fileURL?.lastPathComponent ?? title ?? "Untitled" }

    /// Base URL for the page, so relative images and links resolve next to the file.
    var baseURL: URL? {
        guard let path = fileURL?.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(LocalFileSchemeHandler.scheme)://\(path)")
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

    func pageDidLoad() {
        pageLoaded = true
        if let webView { webView.window?.makeFirstResponder(webView) }
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
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let newText = MarkdownFileDocument.decode(data)
        guard newText != text else { return }
        text = newText
        render()
    }

    // MARK: Navigation

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

    private func setZoom(_ zoom: CGFloat) {
        webView?.pageZoom = zoom
        UserDefaults.standard.set(Double(zoom), forKey: SettingsKey.zoom)
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
        panel.nameFieldStringValue = ((fileURL?.deletingPathExtension().lastPathComponent) ?? displayName) + ".html"
        if let dir = fileURL?.deletingLastPathComponent() { panel.directoryURL = dir }
        let page = fullPage()
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try page.write(to: url, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
        }
        if let window = webView?.window { panel.beginSheetModal(for: window, completionHandler: handler) }
        else { handler(panel.runModal()) }
    }

    func revealInFinder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func openInEditor() {
        guard let fileURL else { return }
        let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText)
            ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([fileURL], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    func copyPath() {
        guard let fileURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL.path, forType: .string)
    }

    // MARK: Links

    /// Opens a link clicked in the page: Markdown files in Marky, everything else
    /// with its default app or browser.
    func open(link url: URL) {
        if url.scheme == LocalFileSchemeHandler.scheme {
            let file = URL(fileURLWithPath: url.path)
            if file.path == fileURL?.path { scrollToTop(); return }
            if Self.isMarkdown(file) {
                NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
                    if let error { NSAlert(error: error).runModal() }
                }
            } else if FileManager.default.fileExists(atPath: file.path) {
                NSWorkspace.shared.open(file)
            } else {
                NSSound.beep()
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"].contains(url.pathExtension.lowercased())
    }
}
