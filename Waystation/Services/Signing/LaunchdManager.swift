import Foundation

/// Service managing macOS background launchd agent for automatic extension re-signing.
/// Conforms to AD-2 (ProcessRunner) and ensures extensions never expire unexpectedly.
public actor LaunchdManager {
    public static let shared = LaunchdManager()

    private let processRunner: ProcessRunner
    private let fileManager = FileManager.default
    public static let agentLabel = "org.waystation.autoresign"

    public init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.agentLabel).plist")
    }

    private var logsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Waystation", isDirectory: true)
    }

    /// Checks if the launchd background agent plist is installed on this Mac.
    public func isAgentInstalled() -> Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    /// Ensures the installed launchd plist points to the current active executable path.
    /// Prevents silent failures if the user moves Waystation.app (e.g. from Downloads to /Applications).
    public func ensureAgentUpToDate() async {
        guard isAgentInstalled(), let executablePath = Bundle.main.executablePath else { return }
        if let content = try? String(contentsOf: plistURL, encoding: .utf8), !content.contains(executablePath) {
            await installAgent()
        }
    }

    /// Installs and loads the launchd agent to automatically re-sign extensions in the background.
    public func installAgent(intervalDays: Int = 5) async {
        guard let executablePath = Bundle.main.executablePath else { return }

        do {
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

            let stdoutLog = logsDirectory.appendingPathComponent("autoresign.log").path
            let stderrLog = logsDirectory.appendingPathComponent("autoresign-error.log").path

            // Calculate interval in seconds (default: 5 days = 432,000 seconds)
            let intervalSeconds = max(1, intervalDays) * 86400

            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Self.agentLabel)</string>
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

            try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

            // Unload previous instance if present, then load new agent
            _ = try? await processRunner.run(command: "/bin/launchctl", arguments: ["unload", plistURL.path], onOutputLine: nil)
            _ = try? await processRunner.run(command: "/bin/launchctl", arguments: ["load", plistURL.path], onOutputLine: nil)
        } catch {
            // Silently handled or logged
        }
    }

    /// Unloads and removes the launchd background agent.
    public func uninstallAgent() async {
        guard fileManager.fileExists(atPath: plistURL.path) else { return }

        _ = try? await processRunner.run(command: "/bin/launchctl", arguments: ["unload", plistURL.path], onOutputLine: nil)
        try? fileManager.removeItem(at: plistURL)
    }
}
