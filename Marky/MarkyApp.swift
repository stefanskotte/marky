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

    private var model: DocumentModel? { manager.active }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { manager.newTab(from: NSApp.keyWindow) }
                .keyboardShortcut("t")
            Button("New Window…") { manager.showOpenPanel(newWindow: true) }
                .keyboardShortcut("n")
            Button("Open…") { manager.showOpenPanel() }
                .keyboardShortcut("o")
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
            Button("Export as HTML…") { model?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Button("Reveal in Finder") { model?.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Open in Text Editor") { model?.openInEditor() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(model == nil)
            Button("Copy File Path") { model?.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { model?.print() }
                .keyboardShortcut("p")
                .disabled(model == nil)
        }

        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { model?.showFind() }
                    .keyboardShortcut("f")
                Button("Find Next") { model?.findNext() }
                    .keyboardShortcut("g")
                Button("Find Previous") { model?.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { model?.useSelectionForFind() }
                    .keyboardShortcut("e")
            }
            .disabled(model == nil)
        }

        CommandGroup(before: .toolbar) {
            Button(model?.columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar") { model?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(model == nil)
            Button("Files") { model?.show(.files) }
                .keyboardShortcut("1", modifiers: [.command, .control])
                .disabled(model == nil)
            Button("Outline") { model?.show(.outline) }
                .keyboardShortcut("2", modifiers: [.command, .control])
                .disabled(model == nil)
            Divider()
            Button("Actual Size") { model?.resetZoom() }
                .keyboardShortcut("0")
                .disabled(model == nil)
            Button("Zoom In") { model?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(model == nil)
            Button("Zoom Out") { model?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(model == nil)
            Divider()
            Button("Reload") { model?.reloadFromDisk() }
                .keyboardShortcut("r")
                .disabled(model == nil)
            Divider()
        }

        CommandMenu("Go") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(model?.canGoBack ?? false))
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(model?.canGoForward ?? false))
            Divider()
            Button("Previous Tab") { manager.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Tab") { manager.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Divider()
            ForEach(1..<10) { n in
                Button(n == 9 ? "Last Tab" : "Tab \(n)") { manager.selectTab(n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")))
            }
        }
    }
}
