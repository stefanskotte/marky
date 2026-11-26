import AppKit
import SwiftUI

enum SettingsKey {
    static let appearance = "appearance"
    static let font = "font"
    static let fontSize = "fontSize"
    static let width = "width"
    static let highlightCode = "highlightCode"
    static let smartTypography = "smartTypography"
    static let autoReload = "autoReload"
    static let openInTabs = "openInTabs"
    static let sidebarMode = "sidebarMode"
    static let showSidebar = "showSidebar"
    static let zoom = "zoom"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "") ?? .auto
    }

    /// Applies to every window, and through it to the web views, whose
    /// `prefers-color-scheme` follows the view's effective appearance.
    func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension UserDefaults {
    var pageStyle: PageStyle {
        PageStyle(
            font: PageStyle.Font(rawValue: string(forKey: SettingsKey.font) ?? "") ?? .system,
            fontSize: object(forKey: SettingsKey.fontSize) as? Double ?? 16,
            width: PageStyle.Width(rawValue: string(forKey: SettingsKey.width) ?? "") ?? .medium
        )
    }

    var renderOptions: MarkdownRenderer.Options {
        MarkdownRenderer.Options(
            highlightCode: object(forKey: SettingsKey.highlightCode) as? Bool ?? true,
            smartTypography: object(forKey: SettingsKey.smartTypography) as? Bool ?? true
        )
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .frame(width: 500, height: 560)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .auto
    @AppStorage(SettingsKey.font) private var font: PageStyle.Font = .system
    @AppStorage(SettingsKey.fontSize) private var fontSize: Double = 16
    @AppStorage(SettingsKey.width) private var width: PageStyle.Width = .medium
    @AppStorage(SettingsKey.highlightCode) private var highlightCode = true
    @AppStorage(SettingsKey.smartTypography) private var smartTypography = true
    @AppStorage(SettingsKey.autoReload) private var autoReload = true
    @AppStorage(SettingsKey.openInTabs) private var openInTabs = true
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, mode in mode.apply() }
            }

            Section("Text") {
                Picker("Font", selection: $font) {
                    ForEach(PageStyle.Font.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $fontSize, in: 12...24, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Line width", selection: $width) {
                    ForEach(PageStyle.Width.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Rendering") {
                Toggle("Syntax highlighting in code blocks", isOn: $highlightCode)
                Toggle("Smart quotes and dashes", isOn: $smartTypography)
            }

            Section("Behaviour") {
                Toggle("Reload automatically when the file changes", isOn: $autoReload)
                Toggle("Open files as tabs in the front window", isOn: $openInTabs)
                Toggle("Show the sidebar in new windows", isOn: $showSidebar)
            }

            Section {
                DefaultAppRow()
                Text("Quick Look previews follow the system appearance and use the default style. Press Space on a Markdown file in Finder to try it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DefaultAppRow: View {
    @State private var isDefault = DefaultApp.isDefault

    var body: some View {
        LabeledContent("Default app for Markdown files") {
            if isDefault {
                Label("Marky", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            } else {
                Button("Use Marky") { DefaultApp.makeDefault { _ in isDefault = DefaultApp.isDefault } }
            }
        }
        .onAppear { isDefault = DefaultApp.isDefault }
    }
}
