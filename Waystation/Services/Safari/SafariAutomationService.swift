import Foundation
import AppKit

/// Status of the Safari "Allow Unsigned Extensions" developer setting.
public enum SafariUnsignedStatus: Sendable, Equatable {
    case enabled
    case disabled
    case safariNotRunning
    case developMenuMissing
    case accessibilityRequired
    case unknown(String)

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
    private let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Persisted set of Safari PIDs that have had unsigned extensions enabled in their current lifecycle.
    private var sessionEnabledPIDs: Set<Int> {
        get {
            let list = UserDefaults.standard.array(forKey: "WaystationEnabledSafariPIDs") as? [Int] ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "WaystationEnabledSafariPIDs")
        }
    }

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

    /// Prompts the macOS system prompt to request Accessibility permissions for Waystation.
    nonisolated public func requestAccessibilityPrompt() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    nonisolated public func requestAccessibilityPermission() {
        requestAccessibilityPrompt()
    }

    /// Cleans up stored PIDs for Safari instances that have quit.
    private func cleanTerminatedPIDs() {
        let runningPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").map { Int($0.processIdentifier) })
        let current = sessionEnabledPIDs.intersection(runningPIDs)
        sessionEnabledPIDs = current
    }

    /// Evaluates current Safari extension readiness and unsigned extensions toggle state.
    public func checkSafariHealth(forceFreshCheck: Bool = false) async -> SafariHealthStatus {
        await checkHealth(forceFreshCheck: forceFreshCheck)
    }

    public func checkHealth(forceFreshCheck: Bool = false) async -> SafariHealthStatus {
        guard isSafariRunning() else {
            cleanTerminatedPIDs()
            return SafariHealthStatus(
                isSafariRunning: false,
                unsignedStatus: .safariNotRunning,
                hasAccessibility: isAccessibilityGranted()
            )
        }

        guard isAccessibilityGranted() else {
            return SafariHealthStatus(
                isSafariRunning: true,
                unsignedStatus: .accessibilityRequired,
                hasAccessibility: false
            )
        }

        cleanTerminatedPIDs()
        let unsignedStatus = await inspectSafariUnsignedSetting()

        return SafariHealthStatus(
            isSafariRunning: true,
            unsignedStatus: unsignedStatus,
            hasAccessibility: true
        )
    }

    /// Queries Safari's UI hierarchy via AppleScript strictly passively (NO windows opened, NO flashing).
    private func inspectSafariUnsignedSetting() async -> SafariUnsignedStatus {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return "NOT_RUNNING"
            tell (first process whose bundle identifier is "com.apple.Safari")
                -- Check if Develop menu exists
                if not (exists menu bar item "Develop" of menu bar 1) then
                    return "DEVELOP_MENU_MISSING"
                end if

                -- 1. Check Develop menu item directly (Safari 16 and older fallback)
                try
                    set devMenu to menu "Develop" of menu bar item "Develop" of menu bar 1
                    if exists menu item "Allow Unsigned Extensions" of devMenu then
                        set mItem to menu item "Allow Unsigned Extensions" of devMenu
                        set mValue to value of attribute "AXMenuItemMarkChar" of mItem
                        if mValue is "✓" or mValue is true or mValue is 1 then
                            return "ENABLED"
                        else
                            return "DISABLED"
                        end if
                    end if
                end try

                -- 2. Passively check Developer settings window IF ALREADY OPEN (never open or close it!)
                if exists window "Developer" then
                    tell window "Developer"
                        try
                            set chk to checkbox "Allow unsigned extensions" of group 1 of group 1
                            if (value of chk is 1) then return "WINDOW_OPEN_ENABLED"
                            return "WINDOW_OPEN_DISABLED"
                        end try
                    end tell
                end if

                return "PASSIVE_UNKNOWN"
            end tell
        end tell
        """

        do {
            let result = try await processRunner.run(
                command: "/usr/bin/osascript",
                arguments: ["-e", script],
                onOutputLine: nil
            )

            let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let currentPID = currentSafariPID() else { return .safariNotRunning }

            switch output {
            case "NOT_RUNNING":
                return .safariNotRunning
            case "DEVELOP_MENU_MISSING":
                return .developMenuMissing
            case "ENABLED":
                var pids = sessionEnabledPIDs
                pids.insert(Int(currentPID))
                sessionEnabledPIDs = pids
                return .enabled
            case "DISABLED":
                var pids = sessionEnabledPIDs
                pids.remove(Int(currentPID))
                sessionEnabledPIDs = pids
                return .disabled
            case "WINDOW_OPEN_ENABLED":
                var pids = sessionEnabledPIDs
                pids.insert(Int(currentPID))
                sessionEnabledPIDs = pids
                return .enabled
            case "WINDOW_OPEN_DISABLED":
                var pids = sessionEnabledPIDs
                pids.remove(Int(currentPID))
                sessionEnabledPIDs = pids
                return .disabled
            default:
                // Passive check: window Developer is closed.
                // Has this specific Safari instance been enabled during its active lifetime?
                if sessionEnabledPIDs.contains(Int(currentPID)) {
                    return .enabled
                } else {
                    return .disabled
                }
            }
        } catch {
            return .disabled
        }
    }

    /// Opens Safari Settings directly to Developer or Extensions tab.
    public func openSafariExtensionSettings(onOutputLine: (@Sendable (String) -> Void)? = nil) async {
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            tell (first process whose bundle identifier is "com.apple.Safari")
                set frontmost to true
                try
                    click menu item "Settings…" of menu "Safari" of menu bar item "Safari" of menu bar 1
                on error
                    try
                        click menu item "Preferences…" of menu "Safari" of menu bar item "Safari" of menu bar 1
                    end try
                end try
            end tell
        end tell
        """
        _ = try? await processRunner.run(command: "/usr/bin/osascript", arguments: ["-e", script], onOutputLine: onOutputLine)
    }

    /// Opens Safari Developer Settings specifically to toggle Allow Unsigned Extensions.
    public func openSafariDeveloperSettings(onOutputLine: (@Sendable (String) -> Void)? = nil) async {
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

    public func openDeveloperSettings(onOutputLine: (@Sendable (String) -> Void)? = nil) async {
        await openSafariDeveloperSettings(onOutputLine: onOutputLine)
    }

    /// Registers all installed container apps with macOS LaunchServices and PlugInKit so Safari extension manager detects them without opening any app windows.
    public func registerAllContainers(onOutputLine: (@Sendable (String) -> Void)? = nil) async {
        do {
            let extensions = try await registry.loadAll()
            for ext in extensions {
                let appURL = ext.containerAppURL
                guard FileManager.default.fileExists(atPath: appURL.path) else { continue }

                // 1. Register silently with LaunchServices database
                let args = ["-f", appURL.path]
                _ = try? await processRunner.run(command: lsregisterPath, arguments: args, onOutputLine: nil)

                // 2. Register extension plugin(s) directly with PlugInKit
                let pluginsDir = appURL.appendingPathComponent("Contents/PlugIns")
                if let plugins = try? FileManager.default.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                    for plugin in plugins where plugin.pathExtension == "appex" {
                        _ = try? await processRunner.run(
                            command: "/usr/bin/pluginkit",
                            arguments: ["-a", plugin.path],
                            onOutputLine: nil
                        )
                    }
                }

                onOutputLine?("[Safari] Registered extension bundle: '\(ext.name)'")
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

        // 1. Register container apps silently via LaunchServices & PlugInKit (no windows)
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
                if let pid = currentSafariPID() {
                    var pids = self.sessionEnabledPIDs
                    pids.insert(Int(pid))
                    self.sessionEnabledPIDs = pids
                }
                onOutputLine?("[Safari] Successfully activated 'Allow Unsigned Extensions'.")
                return true
            } else if trimmed.contains("Prompting authorization") {
                if let pid = currentSafariPID() {
                    var pids = self.sessionEnabledPIDs
                    pids.insert(Int(pid))
                    self.sessionEnabledPIDs = pids
                }
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
