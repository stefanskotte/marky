import Foundation

/// Settings both the app and the Quick Look extension read. The app copies them
/// into the App Group container (Release builds, signed with the team ID); the
/// sandboxed extension can't read the app's own defaults.
enum SharedSettings {
    static let groupID = "3WT5WSV6B5.dk.enhance-it.marky"
    static let keys = ["appearance", "style", "font", "fontSize", "width", "highlightCode", "smartTypography"]

    /// nil when the build has no App Group entitlement (Debug).
    static var group: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil else { return nil }
        return UserDefaults(suiteName: groupID)
    }

    /// App side: mirror the shared keys into the group container.
    static func publish(from source: UserDefaults = .standard) {
        guard let group else { return }
        for key in keys {
            let value = source.object(forKey: key)
            if let value {
                if !(group.object(forKey: key) as AnyObject).isEqual(value) { group.set(value, forKey: key) }
            } else if group.object(forKey: key) != nil {
                group.removeObject(forKey: key)
            }
        }
    }

    /// "light", "dark" or nil (follow the system).
    static func theme(in defaults: UserDefaults) -> String? {
        switch defaults.string(forKey: "appearance") {
        case "light": "light"
        case "dark": "dark"
        default: nil
        }
    }
}

extension UserDefaults {
    var pageStyle: PageStyle {
        PageStyle(
            look: PageStyle.Look(rawValue: string(forKey: "style") ?? "") ?? .marky,
            font: PageStyle.Font(rawValue: string(forKey: "font") ?? "") ?? .system,
            fontSize: object(forKey: "fontSize") as? Double ?? 16,
            width: PageStyle.Width(rawValue: string(forKey: "width") ?? "") ?? .medium
        )
    }

    var renderOptions: MarkdownRenderer.Options {
        MarkdownRenderer.Options(
            highlightCode: object(forKey: "highlightCode") as? Bool ?? true,
            smartTypography: object(forKey: "smartTypography") as? Bool ?? true
        )
    }
}
