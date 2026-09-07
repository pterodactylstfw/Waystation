import SwiftUI

/// User interface appearance modes.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Central user preferences coordinator for Waystation.
/// Conforms to AD-1 and persists settings in UserDefaults.
@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    private enum Keys {
        static let theme = "app_theme"
        static let autoResignEnabled = "auto_resign_enabled"
        static let autoResignIntervalDays = "auto_resign_interval_days"
        static let customSigningIdentity = "custom_signing_identity"
        static let autoOpenSafariOnInstall = "auto_open_safari_on_install"
        static let autoToggleSafariDevelopOption = "auto_toggle_safari_develop_option"
    }

    public var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    public var autoResignEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoResignEnabled, forKey: Keys.autoResignEnabled)
            Task {
                await updateLaunchdAgent()
            }
        }
    }

    public var autoResignIntervalDays: Int {
        didSet {
            UserDefaults.standard.set(autoResignIntervalDays, forKey: Keys.autoResignIntervalDays)
            Task {
                await updateLaunchdAgent()
            }
        }
    }

    public var customSigningIdentity: String {
        didSet {
            UserDefaults.standard.set(customSigningIdentity, forKey: Keys.customSigningIdentity)
        }
    }

    public var autoOpenSafariOnInstall: Bool {
        didSet {
            UserDefaults.standard.set(autoOpenSafariOnInstall, forKey: Keys.autoOpenSafariOnInstall)
        }
    }

    public var autoToggleSafariDevelopOption: Bool {
        didSet {
            UserDefaults.standard.set(autoToggleSafariDevelopOption, forKey: Keys.autoToggleSafariDevelopOption)
        }
    }

    public init() {
        let savedTheme = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .system

        self.autoResignEnabled = UserDefaults.standard.object(forKey: Keys.autoResignEnabled) as? Bool ?? true
        self.autoResignIntervalDays = UserDefaults.standard.object(forKey: Keys.autoResignIntervalDays) as? Int ?? 5
        self.customSigningIdentity = UserDefaults.standard.string(forKey: Keys.customSigningIdentity) ?? ""
        self.autoOpenSafariOnInstall = UserDefaults.standard.object(forKey: Keys.autoOpenSafariOnInstall) as? Bool ?? true
        self.autoToggleSafariDevelopOption = UserDefaults.standard.object(forKey: Keys.autoToggleSafariDevelopOption) as? Bool ?? false
    }

    private func updateLaunchdAgent() async {
        if autoResignEnabled {
            await LaunchdManager.shared.installAgent(intervalDays: autoResignIntervalDays)
        } else {
            await LaunchdManager.shared.uninstallAgent()
        }
    }
}
