import Foundation

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

            let output = result.standardOutput
            var identities: [(sha: String, name: String)] = []

            if let regex = Self.identityRegex {
                let nsOutput = output as NSString
                let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let sha = nsOutput.substring(with: match.range(at: 1))
                        let name = nsOutput.substring(with: match.range(at: 2))
                        identities.append((sha, name))
                    }
                }
            }

            // Prioritize Apple Development certificates
            if let dev = identities.first(where: { $0.name.contains("Apple Development") }) {
                onOutputLine?("[Signing] Selected signing identity: \(dev.name)")
                return dev.sha
            }

            // Fallback to any valid identity
            if let first = identities.first {
                onOutputLine?("[Signing] Selected signing identity: \(first.name)")
                return first.sha
            }

            onOutputLine?("[Signing] No Apple Developer identity detected. Using ad-hoc signing ('-').")
            return "-"
        } catch {
            onOutputLine?("[Signing] Error checking identities: \(error.localizedDescription). Using ad-hoc signing.")
            return "-"
        }
    }

    /// Resolves the actual executable `.app` bundle for an extension.
    public func resolveAppBundle(for ext: InstalledExtension) -> URL? {
        let path = ext.containerAppPath
        let url = URL(fileURLWithPath: path)

        // 1. Direct .app check
        if url.pathExtension == "app" && FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // 2. Check ~/Library/Application Support/Waystation/Extensions/<Name>.app
        let baseAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupportTarget = baseAppSupport
            .appendingPathComponent("Waystation", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("\(ext.name).app")

        if FileManager.default.fileExists(atPath: appSupportTarget.path) {
            return appSupportTarget
        }

        // 3. Look in DerivedData
        let derivedDataBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let enumerator = FileManager.default.enumerator(at: derivedDataBase, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "app" && fileURL.lastPathComponent == "\(ext.name).app" {
                    return fileURL
                }
            }
        }

        return nil
    }

    /// Signs a container app bundle using the specified identity (or auto-detected).
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

        let arguments = [
            "--force",
            "--deep",
            "--sign", resolvedIdentity,
            targetURL.path
        ]

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
            onOutputLine?("[Signing] No extensions registered to re-sign.")
            return []
        }

        let total = extensions.count
        onOutputLine?("[Signing] Initiating batch re-signing for \(total) extension\(total == 1 ? "" : "s")...")

        let identity = await detectSigningIdentity(onOutputLine: onOutputLine)

        for (index, ext) in extensions.enumerated() {
            let currentNum = index + 1
            onProgress?(currentNum, total, ext.name)
            onOutputLine?("[Signing] [\(currentNum)/\(total)] Re-signing '\(ext.name)'...")

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
}
