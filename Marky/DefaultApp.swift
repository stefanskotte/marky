import AppKit
import UniformTypeIdentifiers

/// Making Marky the default app for Markdown files.
enum DefaultApp {
    private static let askedKey = "askedToBeDefault"

    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: .markdownText) else { return false }
        return Bundle(url: current)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS may show its own confirmation after this.
    static func makeDefault(completion: ((Bool) -> Void)? = nil) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .markdownText) { error in
            DispatchQueue.main.async {
                if let error { NSAlert(error: error).runModal() }
                completion?(error == nil)
            }
        }
    }

    /// Asks once, on the first launch where Marky isn't already the default.
    static func askOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        guard !isDefault else { return }
        let alert = NSAlert()
        alert.messageText = "Open Markdown files with Marky?"
        alert.informativeText = "Makes Marky the default app for .md files, so double-clicking one in Finder opens it here. You can change this later in Settings."
        alert.addButton(withTitle: "Use Marky")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { makeDefault() }
    }
}
