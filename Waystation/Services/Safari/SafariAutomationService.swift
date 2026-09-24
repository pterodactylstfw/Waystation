import Foundation
import AppKit
import ApplicationServices

/// Real-time activation status of Safari's "Allow Unsigned Extensions" developer setting.
public enum SafariUnsignedStatus: Sendable, Equatable {
    case enabled
    case disabled
    case safariNotRunning
    case developMenuMissing
    case accessibilityRequired
    case unknown(String)

    nonisolated public var title: String {
        switch self {
        case .enabled: return "Unsigned Extensions: Active"
        case .disabled: return "Unsigned Extensions: Disabled"
        case .safariNotRunning: return "Safari is closed"
        case .developMenuMissing: return "Develop Menu Disabled in Safari"
        case .accessibilityRequired: return "Accessibility Permission Required"
        case .unknown(let msg): return msg
        }
    }

    nonisolated public var isOperational: Bool {
        self == .enabled
    }

    nonisolated public static func == (lhs: SafariUnsignedStatus, rhs: SafariUnsignedStatus) -> Bool {
        switch (lhs, rhs) {
        case (.enabled, .enabled): return true
        case (.disabled, .disabled): return true
        case (.safariNotRunning, .safariNotRunning): return true
        case (.developMenuMissing, .developMenuMissing): return true
        case (.accessibilityRequired, .accessibilityRequired): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}

/// Comprehensive health status of Safari for running converted web extensions.
public struct SafariHealthStatus: Sendable, Equatable {
    public let isSafariRunning: Bool
    public let unsignedStatus: SafariUnsignedStatus
    public let hasAccessibility: Bool

    nonisolated public init(
        isSafariRunning: Bool,
        unsignedStatus: SafariUnsignedStatus,
        hasAccessibility: Bool
    ) {
        self.isSafariRunning = isSafariRunning
        self.unsignedStatus = unsignedStatus
        self.hasAccessibility = hasAccessibility
    }

    nonisolated public static func == (lhs: SafariHealthStatus, rhs: SafariHealthStatus) -> Bool {
        lhs.isSafariRunning == rhs.isSafariRunning &&
        lhs.unsignedStatus == rhs.unsignedStatus &&
        lhs.hasAccessibility == rhs.hasAccessibility
    }
}

/// Service managing Safari extension registration, lifecycle launch, and assistive accessibility automation.
/// Conforms to AD-2, HIG, and macOS security sandboxing guidelines.
public actor SafariAutomationService {
    public static let shared = SafariAutomationService()

    private let processRunner: ProcessRunner
    private let registry: ExtensionRegistry

    /// Cached session state: remember if enabled for current Safari process without flashing UI windows.
    private var lastKnownSafariPID: pid_t?
    private var cachedUnsignedEnabledForSession: Bool = false

    public init(
        processRunner: ProcessRunner = .shared,
        registry: ExtensionRegistry = .shared
    ) {
        self.processRunner = processRunner
        self.registry = registry
    }

    /// Checks if Waystation currently has macOS Accessibility permissions for GUI automation.
    nonisolated public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Checks if Safari is currently running in memory.
    nonisolated public func isSafariRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty
    }

    /// Returns the PID of the active Safari instance, if running.
    nonisolated public func currentSafariPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier
    }

    /// Requests macOS Accessibility permissions by opening the system authorization prompt.
    nonisolated public func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Silently diagnoses Safari's current runtime status WITHOUT flashing or opening background windows.
    public func checkSafariHealth() async -> SafariHealthStatus {
        guard let currentPID = currentSafariPID() else {
            // Safari is closed: reset session cache
            self.lastKnownSafariPID = nil
            self.cachedUnsignedEnabledForSession = false
            return SafariHealthStatus(isSafariRunning: false, unsignedStatus: .safariNotRunning, hasAccessibility: isAccessibilityGranted())
        }

        // If Safari was restarted (new PID), reset session cache
        if let lastPID = lastKnownSafariPID, lastPID != currentPID {
            self.cachedUnsignedEnabledForSession = false
        }
        self.lastKnownSafariPID = currentPID

        let accessibility = isAccessibilityGranted()
        guard accessibility else {
            return SafariHealthStatus(isSafariRunning: true, unsignedStatus: .accessibilityRequired, hasAccessibility: false)
        }

        // If already verified active during this Safari session, return enabled immediately without touching GUI
        if cachedUnsignedEnabledForSession {
            return SafariHealthStatus(isSafariRunning: true, unsignedStatus: .enabled, hasAccessibility: true)
        }

        // Passive inspection: Never force-open Developer Settings unless the window is already open
        let script = """
        tell application "System Events"
            if not (exists (processes whose bundle identifier is "com.apple.Safari")) then
                return "safari_not_running"
            end if
            tell (first process whose bundle identifier is "com.apple.Safari")
                -- 1. Check if Develop menu bar exists
                if not (exists menu bar item "Develop" of menu bar 1) then
                    return "develop_menu_missing"
                end if

                -- 2. If Developer window is ALREADY open, read it passively without opening or closing
                if exists window "Developer" then
                    tell window "Developer"
                        try
                            set chk to checkbox "Allow unsigned extensions" of group 1 of group 1
                            if value of chk is 1 then
                                return "enabled"
                            else
                                return "disabled"
                            end if
                        end try
                    end tell
                end if

                -- 3. Fallback: Safari 16 legacy Develop menu item check
                try
                    set devMenu to menu "Develop" of menu bar item "Develop" of menu bar 1
                    if exists menu item "Allow Unsigned Extensions" of devMenu then
                        set allowItem to menu item "Allow Unsigned Extensions" of devMenu
                        set isMarked to (value of attribute "AXMenuItemMarkChar" of allowItem is not "")
                        if isMarked then
                            return "enabled"
                        else
                            return "disabled"
                        end if
                    end if
                end try

                -- 4. Develop menu is present, but window "Developer" not open
                return "develop_menu_ready"
            end tell
        end tell
        """

        do {
            let result = try await processRunner.run(command: "/usr/bin/osascript", arguments: ["-e", script], onOutputLine: nil)
            let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)

            let status: SafariUnsignedStatus
            switch trimmed {
            case "enabled":
                self.cachedUnsignedEnabledForSession = true
                status = .enabled
            case "disabled":
                self.cachedUnsignedEnabledForSession = false
                status = .disabled
            case "safari_not_running":
                self.cachedUnsignedEnabledForSession = false
                status = .safariNotRunning
            case "develop_menu_missing":
                status = .developMenuMissing
            case "develop_menu_ready":
                // Apple unchecks "Allow Unsigned Extensions" on every Safari restart/quit.
                // If not yet verified or enabled in this session, it defaults to disabled.
                if self.cachedUnsignedEnabledForSession {
                    status = .enabled
                } else {
                    status = .disabled
                }
            default:
                status = .unknown(trimmed.isEmpty ? "Could not verify" : trimmed)
            }

            return SafariHealthStatus(isSafariRunning: true, unsignedStatus: status, hasAccessibility: true)
        } catch {
            return SafariHealthStatus(isSafariRunning: true, unsignedStatus: .unknown(error.localizedDescription), hasAccessibility: true)
        }
    }

    /// Brings Safari forward and opens Developer Settings pane intentionally on user demand.
    public func openDeveloperSettings(onOutputLine: (@Sendable (String) -> Void)? = nil) async {
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            tell (first process whose bundle identifier is "com.apple.Safari")
                set frontmost to true
                try
                    click menu item "Developer Settings…" of menu "Develop" of menu bar item "Develop" of menu bar 1
                on error errMsg
                    return "Error: " & errMsg
                end try
            end tell
        end tell
        """
        _ = try? await processRunner.run(command: "/usr/bin/osascript", arguments: ["-e", script], onOutputLine: onOutputLine)
    }

    /// Pre-registers all installed extension container apps with macOS LaunchServices.
    public func registerAllContainers(onOutputLine: (@Sendable (String) -> Void)? = nil) async {
        do {
            let extensions = try await registry.loadAll()
            for ext in extensions {
                let path = ext.containerAppPath
                if FileManager.default.fileExists(atPath: path) {
                    onOutputLine?("[Safari] Registering '\(ext.name)' container with macOS LaunchServices...")
                    _ = try? await processRunner.run(command: "/usr/bin/open", arguments: ["-g", path], onOutputLine: nil)
                }
            }
        } catch {
            onOutputLine?("[Safari] Note: Registry check failed: \(error.localizedDescription)")
        }
    }

    /// Prepares extensions, launches Safari, and assists the user in activating unsigned extensions.
    public func launchSafariAndPrepare(
        autoToggleDevelopOption: Bool = false,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async {
        onOutputLine?("[Safari] Preparing installed extensions for Safari session...")

        // 1. Register container apps
        await registerAllContainers(onOutputLine: onOutputLine)

        // 2. Launch or activate Safari
        onOutputLine?("[Safari] Launching Safari...")
        _ = try? await processRunner.run(command: "/usr/bin/open", arguments: ["-a", "Safari"], onOutputLine: onOutputLine)

        // Give Safari a moment to initialize its menu bar
        try? await Task.sleep(nanoseconds: 400_000_000)

        // 3. Attempt automated toggle if enabled and Accessibility is granted
        if autoToggleDevelopOption {
            if isAccessibilityGranted() {
                onOutputLine?("[Safari] Attempting automated activation of 'Allow Unsigned Extensions'...")
                _ = await toggleAllowUnsignedExtensions(onOutputLine: onOutputLine)
            } else {
                onOutputLine?("[Safari] Accessibility permission not yet granted for automatic menu clicking.")
                onOutputLine?("[Safari] Tip: Grant permission in System Settings > Privacy & Security > Accessibility.")
            }
        }

        onOutputLine?("[Safari] Ready! In Safari, ensure Develop > 'Allow Unsigned Extensions' is enabled.")
        onOutputLine?("[Safari] Pro-tip: Keep Safari running in the background (close windows with ⌘W, do not ⌘Q) to maintain extensions active indefinitely.")
    }

    /// Executes AppleScript via osascript to toggle the Allow Unsigned Extensions setting in Safari on user request.
    @discardableResult
    public func toggleAllowUnsignedExtensions(onOutputLine: (@Sendable (String) -> Void)? = nil) async -> Bool {
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            tell (first process whose bundle identifier is "com.apple.Safari")
                set frontmost to true
                delay 0.3
                
                -- Check if Developer window is already open, if not open Developer Settings
                if not (exists window "Developer") then
                    try
                        click menu item "Developer Settings…" of menu "Develop" of menu bar item "Develop" of menu bar 1
                        delay 0.5
                    end try
                end if

                if exists window "Developer" then
                    tell window "Developer"
                        try
                            set chk to checkbox "Allow unsigned extensions" of group 1 of group 1
                            if (value of chk is 0) then
                                click chk
                                delay 0.3
                            end if
                            if (value of chk is 1) then
                                return "Toggled successfully: 1"
                            else
                                return "Prompting authorization"
                            end if
                        on error errMsg
                            return "Error: " & errMsg
                        end try
                    end tell
                end if

                -- Fallback: Safari 16 Develop menu
                try
                    set devMenu to menu "Develop" of menu bar item "Develop" of menu bar 1
                    if exists menu item "Allow Unsigned Extensions" of devMenu then
                        click menu item "Allow Unsigned Extensions" of devMenu
                        return "Toggled successfully: 1"
                    end if
                on error errMsg
                    return "Error: " & errMsg
                end try

                return "Could not find Allow Unsigned Extensions setting"
            end tell
        end tell
        """

        do {
            let result = try await processRunner.run(
                command: "/usr/bin/osascript",
                arguments: ["-e", script],
                onOutputLine: onOutputLine
            )
            let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("Toggled successfully: 1") {
                self.cachedUnsignedEnabledForSession = true
                onOutputLine?("[Safari] Successfully activated 'Allow Unsigned Extensions'.")
                return true
            } else if trimmed.contains("Prompting authorization") {
                self.cachedUnsignedEnabledForSession = true
                onOutputLine?("[Safari] Complete authorization on screen (Touch ID / password) to enable unsigned extensions.")
                return true
            } else {
                onOutputLine?("[Safari] \(trimmed)")
                return false
            }
        } catch {
            onOutputLine?("[Safari] Could not access Safari Developer menu: \(error.localizedDescription)")
            return false
        }
    }
}
