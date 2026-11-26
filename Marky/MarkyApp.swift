import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }

    let text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission) // viewer only
    }

    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()
        // Viewer: no "New" window on launch; show the open panel instead (DocumentGroup default).
        NSWindow.allowsAutomaticWindowTabbing = true
    }
}

@main
struct MarkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownFileDocument.self) { file in
            DocumentView(text: file.document.text, fileURL: file.fileURL)
        }
        .defaultSize(width: 900, height: 1000)
        .commands {
            SidebarCommands()
            MarkyCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct MarkyCommands: Commands {
    @FocusedObject private var model: DocumentModel?

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export as HTML…") { model?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Button("Reveal in Finder") { model?.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model?.fileURL == nil)
            Button("Open in Text Editor") { model?.openInEditor() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(model?.fileURL == nil)
            Button("Copy File Path") { model?.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model?.fileURL == nil)
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
                .disabled(model?.fileURL == nil)
            Divider()
        }
    }
}
