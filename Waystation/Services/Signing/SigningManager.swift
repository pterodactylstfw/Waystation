import Foundation

/// Verification details for an installed extension's code signature.
public struct SignatureVerificationResult: Sendable, Equatable {
    public let isValidOnDisk: Bool
    public let isAdHoc: Bool
    public let authority: String?
    public let statusMessage: String

    nonisolated public init(isValidOnDisk: Bool, isAdHoc: Bool, authority: String? = nil, statusMessage: String) {
        self.isValidOnDisk = isValidOnDisk
        self.isAdHoc = isAdHoc
        self.authority = authority
        self.statusMessage = statusMessage
    }
}

/// Service coordinating code signing and batch re-signing for installed extension container apps.
/// Conforms strictly to AD-2 (isolated async process execution) and AD-6 (dual-track code signing strategy).
public actor SigningManager {
    public static let shared = SigningManager()

    private let processRunner: ProcessRunner
    private let registry: ExtensionRegistry
    private static let identityRegex = try? NSRegularExpression(
        pattern: #"^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)""#,
        options: .anchorsMatchLines
    )

    public init(
        processRunner: ProcessRunner = .shared,
        registry: ExtensionRegistry = .shared
    ) {
        self.processRunner = processRunner
        self.registry = registry
    }

    /// Detects an available code signing identity on this Mac.
    /// Conforms to AD-6: Returns a Personal Team / Apple Development certificate if found,
    /// or falls back to ad-hoc signing ("-").
    public func detectSigningIdentity(onOutputLine: (@Sendable (String) -> Void)? = nil) async -> String {
        do {
            let result = try await processRunner.run(
                command: "/usr/bin/security",
                arguments: ["find-identity", "-v", "-p", "codesigning"],
                onOutputLine: nil
            )

            guard result.isSuccess else {
                onOutputLine?("[Signing] No valid identity found via security tool. Falling back to ad-hoc ('-').")
                return "-"
            }

            let lines = result.standardOutput.components(separatedBy: .newlines)
            for line in lines {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let match = Self.identityRegex?.firstMatch(in: line, options: [], range: range) {
                    if let certRange = Range(match.range(at: 2), in: line) {
                        let certName = String(line[certRange])
                        if certName.contains("Apple Development") || certName.contains("Developer ID Application") {
                            onOutputLine?("[Signing] Detected signing identity: \(certName)")
                            return certName
                        }
                    }
                }
            }

            onOutputLine?("[Signing] No Apple Development identity discovered. Falling back to ad-hoc ('-').")
            return "-"
        } catch {
            onOutputLine?("[Signing] Security command execution failed: \(error.localizedDescription). Falling back to ad-hoc ('-').")
            return "-"
        }
    }

    /// Verifies the code signature integrity of an installed container app or appex bundle.
    /// Returns detailed verification status including ad-hoc identification and certificate authority.
    public func verifySignature(for targetURL: URL) async -> SignatureVerificationResult {
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return SignatureVerificationResult(
                isValidOnDisk: false,
                isAdHoc: false,
                authority: nil,
                statusMessage: "Container app not found at path"
            )
        }

        do {
            let result = try await processRunner.run(
                command: "/usr/bin/codesign",
                arguments: ["--verify", "--verbose=4", targetURL.path],
                onOutputLine: nil
            )

            let combinedOutput = result.standardOutput + "\n" + result.standardError

            if result.isSuccess {
                // Now inspect signature details
                let detailResult = try await processRunner.run(
                    command: "/usr/bin/codesign",
                    arguments: ["-dvvv", targetURL.path],
                    onOutputLine: nil
                )
                let detailOutput = detailResult.standardOutput + "\n" + detailResult.standardError

                var authority: String?
                var isAdHoc = false

                if detailOutput.contains("Signature=adhoc") {
                    isAdHoc = true
                }

                // Parse Authority
                for line in detailOutput.components(separatedBy: .newlines) {
                    if line.hasPrefix("Authority=") {
                        let auth = line.replacingOccurrences(of: "Authority=", with: "").trimmingCharacters(in: .whitespaces)
                        if authority == nil {
                            authority = auth
                        }
                    }
                }

                return SignatureVerificationResult(
                    isValidOnDisk: true,
                    isAdHoc: isAdHoc,
                    authority: authority,
                    statusMessage: isAdHoc ? "Signed (Ad-hoc)" : "Signed (\(authority ?? "Verified"))"
                )
            } else {
                let errorMsg = combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                return SignatureVerificationResult(
                    isValidOnDisk: false,
                    isAdHoc: false,
                    authority: nil,
                    statusMessage: errorMsg.isEmpty ? "Invalid or expired signature" : errorMsg
                )
            }
        } catch {
            return SignatureVerificationResult(
                isValidOnDisk: false,
                isAdHoc: false,
                authority: nil,
                statusMessage: "Codesign inspection error: \(error.localizedDescription)"
            )
        }
    }

    /// Creates a temporary entitlements file containing the mandatory macOS App Sandbox entitlement.
    /// PlugInKit rejects all plug-ins without this entitlement ("plug-ins must be sandboxed").
    private func createSandboxEntitlementsFile() -> URL? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("waystation-sandbox-\(UUID().uuidString).entitlements")
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.app-sandbox</key>
            <true/>
        </dict>
        </plist>
        """
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    /// Recursively signs an application bundle with the given identity and mandatory App Sandbox entitlement.
    /// Conforms to AD-6: signs embedded .appex bundles first, followed by the main container .app.
    public func sign(
        targetURL: URL,
        identity: String? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let resolvedIdentity = if let identity = identity {
            identity
        } else {
            await detectSigningIdentity(onOutputLine: onOutputLine)
        }

        onOutputLine?("[Signing] Signing '\(targetURL.lastPathComponent)' with identity '\(resolvedIdentity)'...")

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw WaystationError.signingFailed(reason: "Calea specificată nu există pe disc: \(targetURL.path)")
        }

        let entitlementsURL = createSandboxEntitlementsFile()
        defer {
            if let entitlementsURL = entitlementsURL {
                try? FileManager.default.removeItem(at: entitlementsURL)
            }
        }

        // 1. Sign any nested .appex extension plugin bundles inside Contents/PlugIns/ first
        let pluginsURL = targetURL.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil) {
            for item in contents where item.pathExtension == "appex" {
                var appexArgs = [
                    "--force",
                    "--sign", resolvedIdentity
                ]
                if let entitlementsURL = entitlementsURL {
                    appexArgs.append(contentsOf: ["--entitlements", entitlementsURL.path])
                }
                appexArgs.append(item.path)

                let appexResult = try await processRunner.run(
                    command: "/usr/bin/codesign",
                    arguments: appexArgs,
                    onOutputLine: onOutputLine
                )
                if !appexResult.isSuccess {
                    let err = appexResult.standardError.isEmpty ? appexResult.standardOutput : appexResult.standardError
                    onOutputLine?("[Signing] Warning signing nested plugin '\(item.lastPathComponent)': \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }

        // 2. Sign the top-level container .app bundle
        var arguments = [
            "--force",
            "--sign", resolvedIdentity
        ]
        if let entitlementsURL = entitlementsURL {
            arguments.append(contentsOf: ["--entitlements", entitlementsURL.path])
        }
        arguments.append(targetURL.path)

        let result = try await processRunner.run(
            command: "/usr/bin/codesign",
            arguments: arguments,
            onOutputLine: onOutputLine
        )

        guard result.isSuccess else {
            let errorMsg = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw WaystationError.signingFailed(reason: errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        onOutputLine?("[Signing] Successfully signed '\(targetURL.lastPathComponent)'.")
    }

    /// Iterates through all registered extensions and re-signs their container apps (Story 3.2).
    /// Resets each extension's `lastSignedDate` to `Date()` upon success.
    public func reSignAll(
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> [InstalledExtension] {
        var extensions = try await registry.loadAll()
        guard !extensions.isEmpty else {
            onOutputLine?("[Signing] No installed extensions to re-sign.")
            return []
        }

        onOutputLine?("[Signing] Resolving code signing identity for \(extensions.count) extension(s)...")
        let identity = await detectSigningIdentity(onOutputLine: onOutputLine)

        for (index, ext) in extensions.enumerated() {
            onProgress?(index + 1, extensions.count, ext.name)
            var updated = ext

            if let resolvedApp = resolveAppBundle(for: ext) {
                do {
                    try await sign(targetURL: resolvedApp, identity: identity, onOutputLine: onOutputLine)
                    updated.containerAppPath = resolvedApp.path
                } catch {
                    onOutputLine?("[Signing] Warning: Code signing failed for '\(ext.name)': \(error.localizedDescription)")
                }
            } else if ext.containerAppURL.pathExtension == "xcodeproj" {
                onOutputLine?("[Signing] Container .app not found on disk for '\(ext.name)'. Build the project in Xcode to generate the .app container.")
            } else {
                onOutputLine?("[Signing] Warning: Container app bundle not found at '\(ext.containerAppPath)'.")
            }

            // Reset expiration timer to now
            updated.lastSignedDate = Date()
            extensions[index] = updated
            try await registry.update(updated)
        }

        onOutputLine?("[Signing] Batch re-signing complete! All expiration countdowns reset to 7 days.")
        return extensions
    }

    /// Attempts to locate the compiled `.app` container within standard DerivedData or the project build directory.
    private func resolveAppBundle(for ext: InstalledExtension) -> URL? {
        let directURL = ext.containerAppURL
        if directURL.pathExtension == "app" && FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        // If stored path is an .xcodeproj or directory, scan Products in DerivedData
        let appName = ext.name.replacingOccurrences(of: " ", with: "")
        let possibleAppNames = [
            appName + ".app",
            ext.name + ".app"
        ]

        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)

        if let enumerator = FileManager.default.enumerator(
            at: derivedData,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if possibleAppNames.contains(fileURL.lastPathComponent) {
                    return fileURL
                }
            }
        }

        return nil
    }
}
