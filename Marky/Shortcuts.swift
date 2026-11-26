import AppKit
import SwiftUI

/// A key + modifiers, stored as JSON in UserDefaults.
struct Shortcut: Codable, Equatable, Hashable {
    /// A single lowercase character, or a special key name (see `specialKeys`).
    var key: String
    var command = false
    var control = false
    var option = false
    var shift = false

    static func cmd(_ key: String, shift: Bool = false, option: Bool = false, control: Bool = false) -> Shortcut {
        Shortcut(key: key, command: true, control: control, option: option, shift: shift)
    }

    static func ctrl(_ key: String, shift: Bool = false) -> Shortcut {
        Shortcut(key: key, command: false, control: true, option: false, shift: shift)
    }

    private static let specialKeys: [String: (KeyEquivalent, String, UInt16)] = [
        "tab": (.tab, "⇥", 48), "return": (.return, "↩", 36), "space": (.space, "Space", 49),
        "delete": (.delete, "⌫", 51), "forwarddelete": (.deleteForward, "⌦", 117), "escape": (.escape, "⎋", 53),
        "left": (.leftArrow, "←", 123), "right": (.rightArrow, "→", 124),
        "down": (.downArrow, "↓", 125), "up": (.upArrow, "↑", 126),
        "home": (.home, "↖", 115), "end": (.end, "↘", 119), "pageup": (.pageUp, "⇞", 116), "pagedown": (.pageDown, "⇟", 121),
    ]

    var keyboardShortcut: KeyboardShortcut {
        var mods: EventModifiers = []
        if command { mods.insert(.command) }
        if control { mods.insert(.control) }
        if option { mods.insert(.option) }
        if shift { mods.insert(.shift) }
        let equivalent = Self.specialKeys[key]?.0 ?? KeyEquivalent(Character(key))
        return KeyboardShortcut(equivalent, modifiers: mods)
    }

    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + (Self.specialKeys[key]?.1 ?? key.uppercased())
    }

    /// Builds a shortcut from a key press, or nil if it can't be one (no
    /// ⌘/⌃/⌥, which would steal ordinary typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        command = flags.contains(.command)
        control = flags.contains(.control)
        option = flags.contains(.option)
        shift = flags.contains(.shift)
        guard command || control || option else { return nil }
        if let special = Self.specialKeys.first(where: { $0.value.2 == event.keyCode }) {
            key = special.key
        } else if let chars = event.characters(byApplyingModifiers: []), let c = chars.lowercased().first,
                  !c.isWhitespace, chars.count == 1 {
            key = String(c)
        } else {
            return nil
        }
    }

    init(key: String, command: Bool, control: Bool, option: Bool, shift: Bool) {
        self.key = key; self.command = command; self.control = control; self.option = option; self.shift = shift
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case newTab, newWindow, open, exportHTML, exportPDF, revealInFinder, openInEditor, copyPath, print
    case find, findNext, findPrevious, useSelectionForFind
    case toggleSidebar, showFiles, showOutline, actualSize, zoomIn, zoomOut, reload
    case back, forward, previousTab, nextTab
    case tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8, lastTab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: "New Tab"
        case .newWindow: "New Window"
        case .open: "Open"
        case .exportHTML: "Export as HTML"
        case .exportPDF: "Export as PDF"
        case .revealInFinder: "Reveal in Finder"
        case .openInEditor: "Open in Text Editor"
        case .copyPath: "Copy File Path"
        case .print: "Print"
        case .find: "Find"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .useSelectionForFind: "Use Selection for Find"
        case .toggleSidebar: "Show / Hide Sidebar"
        case .showFiles: "Files"
        case .showOutline: "Outline"
        case .actualSize: "Actual Size"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .reload: "Reload"
        case .back: "Back"
        case .forward: "Forward"
        case .previousTab: "Previous Tab"
        case .nextTab: "Next Tab"
        case .lastTab: "Last Tab"
        default: "Tab \(tabIndex! + 1)"
        }
    }

    var section: String {
        switch self {
        case .newTab, .newWindow, .open, .exportHTML, .exportPDF, .revealInFinder, .openInEditor, .copyPath, .print: "File"
        case .find, .findNext, .findPrevious, .useSelectionForFind: "Find"
        case .toggleSidebar, .showFiles, .showOutline, .actualSize, .zoomIn, .zoomOut, .reload: "View"
        default: "Go"
        }
    }

    /// 0-based tab for ⌘1…⌘8; ⌘9 (lastTab) is always the last tab.
    var tabIndex: Int? {
        switch self {
        case .tab1: 0
        case .tab2: 1
        case .tab3: 2
        case .tab4: 3
        case .tab5: 4
        case .tab6: 5
        case .tab7: 6
        case .tab8: 7
        default: nil
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .newTab: .cmd("t")
        case .newWindow: .cmd("n")
        case .open: .cmd("o")
        case .exportHTML: .cmd("e", shift: true)
        case .exportPDF: .cmd("p", option: true)
        case .revealInFinder: .cmd("r", shift: true)
        case .openInEditor: .cmd("o", option: true)
        case .copyPath: .cmd("c", option: true)
        case .print: .cmd("p")
        case .find: .cmd("f")
        case .findNext: .cmd("g")
        case .findPrevious: .cmd("g", shift: true)
        case .useSelectionForFind: .cmd("e")
        case .toggleSidebar: .cmd("s", control: true)
        case .showFiles: .cmd("1", control: true)
        case .showOutline: .cmd("2", control: true)
        case .actualSize: .cmd("0")
        case .zoomIn: .cmd("+")
        case .zoomOut: .cmd("-")
        case .reload: .cmd("r")
        case .back: .cmd("[")
        case .forward: .cmd("]")
        case .previousTab: .ctrl("tab", shift: true)
        case .nextTab: .ctrl("tab")
        case .lastTab: .cmd("9")
        default: .cmd(String(tabIndex! + 1))
        }
    }
}

/// User-editable shortcuts. Only changes from the defaults are stored.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    private static let defaultsKey = "shortcuts"

    /// action → shortcut, or nil when the user removed the shortcut.
    @Published private var overrides: [String: Shortcut?] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Shortcut?].self, from: data) {
            overrides = decoded
        }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        if let override = overrides[action.rawValue] { return override }
        return action.defaultShortcut
    }

    func keyboardShortcut(_ action: ShortcutAction) -> KeyboardShortcut? {
        shortcut(for: action)?.keyboardShortcut
    }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if shortcut == action.defaultShortcut { overrides.removeValue(forKey: action.rawValue) }
        else { overrides[action.rawValue] = .some(shortcut) }
        save()
    }

    func isCustomized(_ action: ShortcutAction) -> Bool { overrides[action.rawValue] != nil }

    /// Other actions already using this shortcut.
    func conflicts(for action: ShortcutAction) -> [ShortcutAction] {
        guard let mine = shortcut(for: action) else { return [] }
        return ShortcutAction.allCases.filter { $0 != action && shortcut(for: $0) == mine }
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    private func save() {
        if overrides.isEmpty { UserDefaults.standard.removeObject(forKey: Self.defaultsKey) }
        else if let data = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }
}

// MARK: - Settings UI

struct ShortcutsSettingsView: View {
    @ObservedObject private var store = ShortcutStore.shared

    private var sections: [(String, [ShortcutAction])] {
        ["File", "Find", "View", "Go"].map { name in (name, ShortcutAction.allCases.filter { $0.section == name }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(sections, id: \.0) { name, actions in
                    Section(name) {
                        ForEach(actions) { action in
                            LabeledContent(action.title) {
                                HStack(spacing: 6) {
                                    if !store.conflicts(for: action).isEmpty {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                            .help("Also used by " + store.conflicts(for: action).map(\.title).joined(separator: ", "))
                                    }
                                    ShortcutRecorder(action: action)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("Click a shortcut, then press the new keys. ⌫ removes it, ⎋ cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { store.resetAll() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

private struct ShortcutRecorder: View {
    let action: ShortcutAction
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type shortcut…" : (store.shortcut(for: action)?.display ?? "None"))
                .monospacedDigit()
                .foregroundStyle(recording ? Color.accentColor : (store.shortcut(for: action) == nil ? .secondary : .primary))
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .contextMenu {
            Button("Reset to Default (\(action.defaultShortcut?.display ?? "None"))") { store.set(action.defaultShortcut, for: action) }
            Button("Remove Shortcut") { store.set(nil, for: action) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if plain && event.keyCode == 53 {            // Esc: cancel
                stop()
            } else if plain && (event.keyCode == 51 || event.keyCode == 117) { // Delete: remove
                store.set(nil, for: action)
                stop()
            } else if let shortcut = Shortcut(event: event) {
                store.set(shortcut, for: action)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
