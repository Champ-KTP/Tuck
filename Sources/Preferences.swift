import Foundation

/// Small typed wrapper around UserDefaults for the app's own settings.
enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let autoHideEnabled = "autoHideEnabled"
        static let autoHideSeconds = "autoHideSeconds"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let tuckedApps = "tuckedApps"
        static let keepSettingsReady = "keepSettingsReady"
    }

    /// Keep System Settings running (hidden) so a peek is instant. When off,
    /// the first peek after System Settings was quit takes a couple of seconds.
    static var keepSettingsReady: Bool {
        get { defaults.object(forKey: Key.keepSettingsReady) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.keepSettingsReady) }
    }

    static var autoHideEnabled: Bool {
        get { defaults.object(forKey: Key.autoHideEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoHideEnabled) }
    }

    /// Seconds to wait after showing the tucked icons before hiding them again.
    static var autoHideSeconds: Double {
        get {
            let v = defaults.double(forKey: Key.autoHideSeconds)
            return v > 0 ? v : 10
        }
        set { defaults.set(newValue, forKey: Key.autoHideSeconds) }
    }

    static var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    /// Names of the apps (as System Settings lists them) whose icons Tuck hides.
    static var tuckedApps: [String] {
        get { defaults.stringArray(forKey: Key.tuckedApps) ?? [] }
        set { defaults.set(newValue, forKey: Key.tuckedApps) }
    }
}
