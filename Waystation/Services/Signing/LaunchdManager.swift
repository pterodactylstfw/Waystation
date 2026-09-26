import Foundation

/// Service managing the macOS launchd user agent for silent background re-signing.
/// Conforms to Story 3.2 and maintains `~/Library/LaunchAgents/org.waystation.autoresign.plist`.
public actor LaunchdManager {
    public static let shared = LaunchdManager()

    public static let agentLabel = "org.waystation.autoresign"

    private let fileManager = FileManager.default
    private let processRunner: ProcessRunner

    public init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    /// `~/Library/LaunchAgents/`
    public var launchAgentsDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    /// Destination plist URL: `~/Library/LaunchAgents/org.waystation.autoresign.plist`
    public var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.agentLabel).plist")
    }

    /// `~/Library/Logs/Waystation/`
    public var logsDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Waystation", isDirectory: true)
    }

    /// Checks if the launchd plist file exists on disk.
    public var isAgentInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    /// Synchronizes the background LaunchAgent state with app settings.
    public func syncWithSettings(enabled: Bool, intervalDays: Int = 5) async {
        if enabled {
            _ = await installAgent(intervalDays: intervalDays)
        } else {
            await uninstallAgent()
        }
    }

    /// Installs and loads the launchd agent to automatically re-sign extensions in the background.
    @discardableResult
    public func installAgent(intervalDays: Int = 5) async -> Bool {
        guard let executablePath = Bundle.main.executablePath else { return false }

        do {
            let launchAgentsDir = launchAgentsDirectory
            let logsDir = logsDirectory
            let targetPlistURL = plistURL

            let stdoutLog = logsDir.appendingPathComponent("autoresign.log").path
            let stderrLog = logsDir.appendingPathComponent("autoresign-error.log").path

            // Calculate interval in seconds (default: 5 days = 432,000 seconds)
            let intervalSeconds = max(1, intervalDays) * 86400
            let bundleID = Bundle.main.bundleIdentifier ?? "com.pterodactylstfw.Waystation"

            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Self.agentLabel)</string>
                <key>AssociatedBundleIdentifiers</key>
                <array>
                    <string>\(bundleID)</string>
                </array>
                <key>ProgramArguments</key>
                <array>
                    <string>\(executablePath)</string>
                    <string>--headless-resign</string>
                </array>
                <key>StartInterval</key>
                <integer>\(intervalSeconds)</integer>
                <key>RunAtLoad</key>
                <false/>
                <key>StandardOutPath</key>
                <string>\(stdoutLog)</string>
                <key>StandardErrorPath</key>
                <string>\(stderrLog)</string>
            </dict>
            </plist>
            """

            // Perform disk I/O in detached task off cooperative thread pool
            try await Task.detached {
                let fm = FileManager.default
                try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
                try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
                try plistContent.write(to: targetPlistURL, atomically: true, encoding: .utf8)
            }.value

            // Unload previous instance if present, then load new agent
            _ = try? await processRunner.run(command: "/bin/launchctl", arguments: ["unload", targetPlistURL.path], onOutputLine: nil)
            _ = try? await processRunner.run(command: "/bin/launchctl", arguments: ["load", targetPlistURL.path], onOutputLine: nil)
            return fileManager.fileExists(atPath: targetPlistURL.path)
        } catch {
            return false
        }
    }

    /// Unloads and removes the launchd background agent.
    public func uninstallAgent() async {
        guard fileManager.fileExists(atPath: plistURL.path) else { return }

        _ = try? await processRunner.run(command: "/bin/launchctl", arguments: ["unload", plistURL.path], onOutputLine: nil)
        try? fileManager.removeItem(at: plistURL)
    }
}
