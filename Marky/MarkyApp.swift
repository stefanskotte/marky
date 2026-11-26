import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files opened from Finder arrive around launch; only restore the last
        // session (or ask for a file) on a plain launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                DefaultApp.askOnFirstRun()
                let manager = WindowManager.shared
                if !manager.hasWindows { manager.restoreSession() }
                if !manager.hasWindows { manager.showOpenPanel() }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { WindowManager.shared.open(url) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { WindowManager.shared.showOpenPanel() } }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { WindowManager.shared.saveSession() }
    }
}

@main
struct MarkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Viewer windows are AppKit windows managed by WindowManager (native
        // tabs that can each move between files); SwiftUI only provides the
        // menus and the Settings window.
        Settings {
            SettingsView()
        }
        .commands { MarkyCommands() }
    }
}

struct MarkyCommands: Commands {
    @ObservedObject private var manager = WindowManager.shared
    @ObservedObject private var keys = ShortcutStore.shared

    private var model: DocumentModel? { manager.active }

    /// A menu item whose shortcut comes from Settings → Shortcuts.
    private func item(_ action: ShortcutAction, _ title: String? = nil, enabled: Bool = true,
                      perform: @escaping () -> Void) -> some View {
        Button(title ?? action.title, action: perform)
            .keyboardShortcut(keys.keyboardShortcut(action))
            .disabled(!enabled)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item(.newTab) { manager.newTab(from: NSApp.keyWindow) }
            item(.newWindow, "New Window…") { manager.showOpenPanel(newWindow: true) }
            item(.open, "Open…") { manager.showOpenPanel() }
            Menu("Open Recent") {
                let _ = manager.recentsVersion
                ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) { manager.open(url) }
                }
                Divider()
                Button("Clear Menu") { NSDocumentController.shared.clearRecentDocuments(nil) }
            }
        }

        CommandGroup(after: .saveItem) {
            item(.exportHTML, "Export as HTML…", enabled: model != nil) { model?.exportHTML() }
            item(.exportPDF, "Export as PDF…", enabled: model != nil) { model?.exportPDF() }
            Divider()
            item(.revealInFinder, enabled: model != nil) { model?.revealInFinder() }
            item(.openInEditor, enabled: model != nil) { model?.openInEditor() }
            item(.copyPath, enabled: model != nil) { model?.copyPath() }
        }

        CommandGroup(replacing: .printItem) {
            item(.print, "Print…", enabled: model != nil) { model?.print() }
        }

        CommandGroup(after: .textEditing) {
            Menu("Find") {
                item(.find, "Find…") { model?.showFind() }
                item(.findNext) { model?.findNext() }
                item(.findPrevious) { model?.findPrevious() }
                item(.useSelectionForFind) { model?.useSelectionForFind() }
            }
            .disabled(model == nil)
        }

        CommandGroup(before: .toolbar) {
            item(.toggleSidebar, model?.columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar",
                 enabled: model != nil) { model?.toggleSidebar() }
            item(.showFiles, enabled: model != nil) { model?.show(.files) }
            item(.showOutline, enabled: model != nil) { model?.show(.outline) }
            Divider()
            item(.actualSize, enabled: model != nil) { model?.resetZoom() }
            item(.zoomIn, enabled: model != nil) { model?.zoomIn() }
            item(.zoomOut, enabled: model != nil) { model?.zoomOut() }
            Divider()
            item(.reload, enabled: model != nil) { model?.reloadFromDisk() }
            Divider()
        }

        CommandMenu("Go") {
            item(.back, enabled: model?.canGoBack ?? false) { model?.goBack() }
            item(.forward, enabled: model?.canGoForward ?? false) { model?.goForward() }
            Divider()
            item(.previousTab) { manager.selectPreviousTab() }
            item(.nextTab) { manager.selectNextTab() }
            Divider()
            ForEach([ShortcutAction.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8]) { action in
                item(action) { manager.selectTab(action.tabIndex!) }
            }
            item(.lastTab) { manager.selectLastTab() }
        }
    }
}
