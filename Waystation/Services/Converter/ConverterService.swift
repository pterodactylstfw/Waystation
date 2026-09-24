import Foundation

/// Service coordinating the conversion of WebExtension packages into native Safari Web Extension Xcode projects.
/// Conforms to AD-2, AD-3, AD-4, and Story 1.5 acceptance criteria.
public struct ConverterService: Sendable {
    public nonisolated static let shared = ConverterService()

    private let processRunner: ProcessRunner
    private let fileManager = FileManager.default
    private let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public nonisolated init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    /// Converts an ingested package into a native Xcode project and compiles the container app.
    public func convert(
        package: IngestedPackage,
        destinationURL: URL? = nil,
        bundleIdentifier: String? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ConvertedProject {
        // 1. Prepare unique output directory inside ~/Library/Caches/org.waystation.app/converted/
        let cacheBaseURL = destinationURL ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("org.waystation.app", isDirectory: true)
            .appendingPathComponent("converted", isDirectory: true)

        let projectLocationURL = cacheBaseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: projectLocationURL, withIntermediateDirectories: true)
        } catch {
            throw WaystationError.conversionFailed(
                reason: "Nu s-a putut crea directorul de conversie: \(error.localizedDescription)",
                exitCode: 1
            )
        }

        // 2. Sanitize app name and bundle identifier with matching casing
        let cleanAppName = sanitizeAppName(package.name)
        let resolvedBundleID = bundleIdentifier ?? ("org.waystation.ext." + sanitizeBundleID(cleanAppName))

        onOutputLine?("Starting Safari Web Extension conversion for '\(cleanAppName)'...")
        onOutputLine?("Target location: \(projectLocationURL.path)")
        onOutputLine?("Bundle Identifier: \(resolvedBundleID)")

        // 3. Build headless command arguments conforming strictly to AD-3
        let arguments = [
            "safari-web-extension-converter",
            package.stagedDirectoryURL.path,
            "--project-location", projectLocationURL.path,
            "--app-name", cleanAppName,
            "--bundle-identifier", resolvedBundleID,
            "--swift",
            "--macos-only",
            "--copy-resources",
            "--no-open",
            "--no-prompt",
            "--force"
        ]

        let result = try await processRunner.run(
            command: "/usr/bin/xcrun",
            arguments: arguments,
            onOutputLine: onOutputLine
        )

        guard result.isSuccess else {
            let errorMsg = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw WaystationError.conversionFailed(
                reason: errorMsg.trimmingCharacters(in: .whitespacesAndNewlines),
                exitCode: result.exitCode
            )
        }

        // 4. Locate the generated .xcodeproj file inside projectLocationURL
        guard let xcodeProjURL = findXcodeProject(in: projectLocationURL) else {
            throw WaystationError.conversionFailed(
                reason: "Proiectul .xcodeproj nu a fost găsit în folderul de ieșire după conversie.",
                exitCode: result.exitCode
            )
        }

        onOutputLine?("Conversion succeeded! Xcode project ready at: \(xcodeProjURL.path)")

        // 5. Patch project.pbxproj to fix macOS deployment target and bundle ID mismatch
        patchXcodeProject(at: xcodeProjURL, appName: cleanAppName, bundleID: resolvedBundleID)

        // 6. Build the container .app bundle and copy to ~/Library/Application Support/Waystation/Extensions/
        var containerAppURL: URL?
        do {
            containerAppURL = try await buildAndStageContainerApp(
                projectURL: xcodeProjURL,
                appName: cleanAppName,
                onOutputLine: onOutputLine
            )
        } catch {
            onOutputLine?("[Build] Notice: Automatic container build warning: \(error.localizedDescription)")
        }

        return ConvertedProject(
            appName: cleanAppName,
            bundleIdentifier: resolvedBundleID,
            projectLocationURL: projectLocationURL,
            xcodeProjectURL: xcodeProjURL,
            containerAppURL: containerAppURL,
            sourcePackage: package
        )
    }

    private func patchXcodeProject(at projectURL: URL, appName: String, bundleID: String) {
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        guard let content = try? String(contentsOf: pbxprojURL, encoding: .utf8) else { return }

        var updated = content.replacingOccurrences(
            of: "MACOSX_DEPLOYMENT_TARGET = 10.14;",
            with: "MACOSX_DEPLOYMENT_TARGET = 14.0;"
        )

        // Ensure both host app and extension targets have perfectly aligned bundle identifiers.
        // Apple's safari-web-extension-converter bug: it slugifies app-name with uppercase/hyphens
        // for the parent app target (e.g. org.waystation.ext.Control-Panel-for-YouTube)
        // while the extension target gets bundleID.Extension (org.waystation.ext.controlpanelforyoutube.Extension),
        // causing xcodebuild error: "Embedded binary's bundle identifier is not prefixed with parent app's bundle identifier".
        var lines = updated.components(separatedBy: "\n")
        for i in 0..<lines.count {
            let line = lines[i]
            if line.contains("PRODUCT_BUNDLE_IDENTIFIER =") {
                if line.contains(".Extension") {
                    lines[i] = line.replacingOccurrences(
                        of: #"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;"#,
                        with: "PRODUCT_BUNDLE_IDENTIFIER = \(bundleID).Extension;",
                        options: .regularExpression
                    )
                } else {
                    lines[i] = line.replacingOccurrences(
                        of: #"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;"#,
                        with: "PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);",
                        options: .regularExpression
                    )
                }
            }
        }
        updated = lines.joined(separator: "\n")

        try? updated.write(to: pbxprojURL, atomically: true, encoding: .utf8)
    }

    private func buildAndStageContainerApp(
        projectURL: URL,
        appName: String,
        onOutputLine: (@Sendable (String) -> Void)?
    ) async throws -> URL? {
        onOutputLine?("[Build] Compiling container application for '\(appName)'...")

        let signingIdentity = await SigningManager.shared.detectSigningIdentity(onOutputLine: onOutputLine)

        // Isolated temporary DerivedData directory to avoid polluting global Xcode cache
        // and prevent Safari from discovering duplicate intermediate build artifacts.
        let tempDerivedDataURL = fileManager.temporaryDirectory
            .appendingPathComponent("WaystationBuild-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: tempDerivedDataURL, withIntermediateDirectories: true)

        defer {
            // Clean up temporary build directory when staging finishes
            try? fileManager.removeItem(at: tempDerivedDataURL)
        }

        let buildArgs = [
            "-project", projectURL.path,
            "-scheme", appName,
            "-destination", "platform=macOS",
            "-configuration", "Release",
            "-derivedDataPath", tempDerivedDataURL.path,
            "CODE_SIGN_IDENTITY=\(signingIdentity)",
            "CODE_SIGN_STYLE=Manual",
            "-quiet",
            "build"
        ]

        let buildResult = try await processRunner.run(
            command: "/usr/bin/xcodebuild",
            arguments: buildArgs,
            onOutputLine: onOutputLine
        )

        guard buildResult.isSuccess else {
            onOutputLine?("[Build] xcodebuild compilation failed. Container app can be built directly in Xcode.")
            return nil
        }

        onOutputLine?("[Build] Container app compilation successful! Staging to Application Support...")

        // Destination: ~/Library/Application Support/Waystation/Extensions/<appName>.app
        let baseAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let extensionsDir = baseAppSupport
            .appendingPathComponent("Waystation", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)

        try? fileManager.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
        let destinationAppURL = extensionsDir.appendingPathComponent("\(appName).app")

        // 1. Locate built .app inside the isolated temporary build folder
        let directAppURL = tempDerivedDataURL
            .appendingPathComponent("Build/Products/Release/\(appName).app")

        var foundAppURL: URL? = fileManager.fileExists(atPath: directAppURL.path) ? directAppURL : nil

        if foundAppURL == nil {
            if let enumerator = fileManager.enumerator(at: tempDerivedDataURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" && fileURL.lastPathComponent == "\(appName).app" {
                        foundAppURL = fileURL
                        break
                    }
                }
            }
        }

        // 2. Fallback: also check global DerivedData if something unexpected occurred
        if foundAppURL == nil {
            let derivedDataBase = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            if let enumerator = fileManager.enumerator(at: derivedDataBase, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" && fileURL.lastPathComponent == "\(appName).app" {
                        foundAppURL = fileURL
                        break
                    }
                }
            }
        }

        if let builtApp = foundAppURL {
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                try? fileManager.removeItem(at: destinationAppURL)
            }
            try fileManager.copyItem(at: builtApp, to: destinationAppURL)
            onOutputLine?("[Build] Staged container app to '\(destinationAppURL.path)'.")

            // Re-sign with mandatory app-sandbox entitlement so PlugInKit and Safari accept the plugin
            do {
                try await SigningManager.shared.sign(
                    targetURL: destinationAppURL,
                    identity: signingIdentity,
                    onOutputLine: onOutputLine
                )
            } catch {
                onOutputLine?("[Signing] Warning re-signing container: \(error.localizedDescription)")
            }

            // Unregister the intermediate build copy from LaunchServices so Safari does not show duplicates
            _ = try? await processRunner.run(
                command: lsregisterPath,
                arguments: ["-u", builtApp.path],
                onOutputLine: nil
            )

            // Register the newly staged .app in Application Support with LaunchServices
            _ = try? await processRunner.run(
                command: lsregisterPath,
                arguments: ["-f", destinationAppURL.path],
                onOutputLine: nil
            )

            // Register extension plugin(s) with PlugInKit
            let pluginsDir = destinationAppURL.appendingPathComponent("Contents/PlugIns")
            if let plugins = try? fileManager.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
                for plugin in plugins where plugin.pathExtension == "appex" {
                    _ = try? await processRunner.run(
                        command: "/usr/bin/pluginkit",
                        arguments: ["-a", plugin.path],
                        onOutputLine: nil
                    )
                }
            }

            // Auto-launch Safari once if setting enabled (AD-1)
            let shouldAutoLaunch = await AppSettings.shared.autoOpenSafariOnInstall
            if shouldAutoLaunch {
                onOutputLine?("[Build] Launching Safari...")
                _ = try? await processRunner.run(
                    command: "/usr/bin/open",
                    arguments: ["-a", "Safari"],
                    onOutputLine: nil
                )
            }

            return destinationAppURL
        }

        return nil
    }

    private func findXcodeProject(in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension == "xcodeproj" {
                return fileURL
            }
        }
        return nil
    }

    private func sanitizeAppName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        let clean = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? "Safari Extension" : clean
    }

    private func sanitizeBundleID(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        let clean = String(String.UnicodeScalarView(filtered)).lowercased()
        return clean.isEmpty ? "extension" : clean
    }
}
