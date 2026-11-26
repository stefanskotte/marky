import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A viewer window. Every tab is its own NSWindow in a native tab group.
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let model: DocumentModel

    @MainActor
    init(model: DocumentModel) {
        self.model = model
        let hosting = NSHostingController(rootView: DocumentView(model: model))
        hosting.sceneBridgingOptions = .all
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 900, height: 1000))
        window.minSize = NSSize(width: 420, height: 300)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MarkyViewer"
        window.isRestorable = false
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The "+" button in the tab bar.
    override func newWindowForTab(_ sender: Any?) {
        MainActor.assumeIsolated { WindowManager.shared.newTab(from: window) }
    }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { WindowManager.shared.didClose(self) }
    }
}

@MainActor
final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private var controllers: [ViewerWindowController] = []
    /// The tab in the key window, for menu commands.
    @Published private(set) var active: DocumentModel?
    @Published private(set) var recentsVersion = 0

    private init() {
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow,
                      let c = self.controllers.first(where: { $0.window === window }) else { return }
                self.active = c.model
            }
        }
    }

    var allModels: [DocumentModel] { controllers.map(\.model) }
    var hasWindows: Bool { !controllers.isEmpty }

    private var frontViewerWindow: NSWindow? {
        if let key = NSApp.keyWindow, controllers.contains(where: { $0.window === key }) { return key }
        return NSApp.orderedWindows.first { w in controllers.contains { $0.window === w } }
    }

    // MARK: Opening

    /// Opens a file (or a folder's README) in a tab. Files already open just
    /// get their tab selected. `nextTo` = the window whose tab group to join;
    /// nil = the front window, or a new window if tabs are turned off.
    func open(_ url: URL, nextTo host: NSWindow? = nil, newWindow: Bool = false) {
        var file = url.standardizedFileURL
        var root: URL?
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) else { NSSound.beep(); return }
        if isDir.boolValue {
            guard let found = FolderScanner.defaultFile(in: file) else {
                let alert = NSAlert()
                alert.messageText = "No Markdown files in “\(file.lastPathComponent)”"
                alert.runModal()
                return
            }
            root = file
            file = found.standardizedFileURL
        }

        if let existing = controllers.first(where: { $0.model.fileURL == file }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let preferTabs = UserDefaults.standard.object(forKey: SettingsKey.openInTabs) as? Bool ?? true
        let hostWindow = newWindow ? nil : (host ?? (preferTabs ? frontViewerWindow : nil))
        let hostModel = controllers.first { $0.window === hostWindow }?.model
        // A file inside the host tab's folder keeps that folder in the Files sidebar.
        if root == nil, let hostRoot = hostModel?.rootURL, file.path.hasPrefix(hostRoot.path + "/") {
            root = hostRoot
        }
        show(ViewerWindowController(model: DocumentModel(fileURL: file, root: root, inheriting: hostModel)), joining: hostWindow)
        recentsVersion += 1
    }

    /// ⌘T: a new tab showing the same file, like Finder's new tab.
    func newTab(from window: NSWindow?) {
        guard let source = controllers.first(where: { $0.window === window })?.model ?? active else {
            showOpenPanel()
            return
        }
        let model = DocumentModel(fileURL: source.fileURL, root: source.rootURL, inheriting: source)
        show(ViewerWindowController(model: model), joining: window ?? frontViewerWindow)
    }

    private func show(_ controller: ViewerWindowController, joining host: NSWindow?) {
        controllers.append(controller)
        guard let window = controller.window else { return }
        if let host {
            host.addTabbedWindow(window, ordered: .above)
        } else if let front = frontViewerWindow, front !== window {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        active = controller.model
    }

    func didClose(_ controller: ViewerWindowController) {
        controllers.removeAll { $0 === controller }
        if active === controller.model { active = nil }
    }

    func showOpenPanel(newWindow: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdownText, .plainText, .folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose Markdown files, or a folder to browse"
        if let dir = active?.fileURL.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK else { return }
        for (i, url) in panel.urls.enumerated() { open(url, newWindow: newWindow && i == 0) }
    }

    // MARK: Tabs

    private var keyTabGroup: [NSWindow] {
        guard let key = NSApp.keyWindow else { return [] }
        return key.tabbedWindows ?? [key]
    }

    func selectTab(_ index: Int) {
        let tabs = keyTabGroup
        guard index < tabs.count else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }

    /// ⌘9 is always the last tab, as in Safari.
    func selectLastTab() { keyTabGroup.last?.makeKeyAndOrderFront(nil) }

    func selectNextTab() { NSApp.keyWindow?.selectNextTab(nil) }
    func selectPreviousTab() { NSApp.keyWindow?.selectPreviousTab(nil) }

    // MARK: Session

    private static let sessionKey = "session"

    /// Saves every window's tabs (in order) so the next plain launch restores them.
    func saveSession() {
        var seen = Set<ObjectIdentifier>()
        var groups: [[String]] = []
        for window in NSApp.orderedWindows.reversed() {
            guard controllers.contains(where: { $0.window === window }) else { continue }
            let tabs = window.tabbedWindows ?? [window]
            if tabs.contains(where: { seen.contains(ObjectIdentifier($0)) }) { continue }
            tabs.forEach { seen.insert(ObjectIdentifier($0)) }
            let paths = tabs.compactMap { tab in controllers.first { $0.window === tab }?.model.fileURL.path }
            if !paths.isEmpty { groups.append(paths) }
        }
        UserDefaults.standard.set(groups, forKey: Self.sessionKey)
    }

    func restoreSession() {
        guard let groups = UserDefaults.standard.array(forKey: Self.sessionKey) as? [[String]] else { return }
        for group in groups {
            let urls = group.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard let first = urls.first else { continue }
            open(first, newWindow: true)
            let host = NSApp.keyWindow
            for url in urls.dropFirst() { open(url, nextTo: host) }
            host?.makeKeyAndOrderFront(nil)
        }
    }
}
