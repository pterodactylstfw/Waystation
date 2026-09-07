import Foundation
import AppKit
import ApplicationServices

/// Service managing Safari extension registration, lifecycle launch, and assistive accessibility automation.
/// Conforms to AD-2, HIG, and macOS security sandboxing guidelines.
public actor SafariAutomationService {
    public static let shared = SafariAutomationService()

    private let processRunner: ProcessRunner
    private let registry: ExtensionRegistry

    public init(
        processRunner: ProcessRunner = .shared,
        registry: ExtensionRegistry = .shared
    ) {
        self.processRunner = processRunner
        self.registry = registry
    }

    /// Checks if Waystation currently has macOS Accessibility permissions for GUI automation.
    public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Requests macOS Accessibility permissions by opening the system authorization prompt.
    public func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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

        // 3. Attempt automated toggle if enabled and Accessibility is granted
        if autoToggleDevelopOption {
            if isAccessibilityGranted() {
                onOutputLine?("[Safari] Attempting automated activation of 'Allow Unsigned Extensions'...")
                await attemptDevelopMenuToggle(onOutputLine: onOutputLine)
            } else {
                onOutputLine?("[Safari] Accessibility permission not yet granted for automatic menu clicking.")
                onOutputLine?("[Safari] Tip: Grant permission in System Settings > Privacy & Security > Accessibility.")
            }
        }

        onOutputLine?("[Safari] Ready! In Safari, ensure Develop > 'Allow Unsigned Extensions' is enabled.")
        onOutputLine?("[Safari] Pro-tip: Keep Safari running in the background (close windows with ⌘W, do not ⌘Q) to maintain extensions active indefinitely.")
    }

    /// Executes AppleScript via osascript to toggle the Develop > Allow Unsigned Extensions menu item.
    private func attemptDevelopMenuToggle(onOutputLine: (@Sendable (String) -> Void)?) async {
        let script = """
        tell application "System Events"
            tell process "Safari"
                set frontmost to true
                delay 0.3
                try
                    -- Check if Develop menu exists
                    set devMenu to menu "Develop" of menu bar item "Develop" of menu bar 1
                    set allowItem to menu item "Allow Unsigned Extensions" of devMenu
                    
                    -- Click the item to enable it
                    click allowItem
                    return "Toggled successfully"
                on error errMsg
                    return "Develop menu error: " & errMsg
                end try
            end tell
        end tell
        """

        do {
            let result = try await processRunner.run(
                command: "/usr/bin/osascript",
                arguments: ["-e", script],
                onOutputLine: onOutputLine
            )
            if result.isSuccess {
                onOutputLine?("[Safari] Automated toggle response: \(result.standardOutput)")
            }
        } catch {
            onOutputLine?("[Safari] Could not auto-toggle menu: \(error.localizedDescription)")
        }
    }
}
