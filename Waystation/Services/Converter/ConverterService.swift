import Foundation

/// Service orchestrating the transformation of an ingested extension package into an Xcode project
/// using Apple's official `safari-web-extension-converter` tool.
/// Conforms strictly to AD-1 (Architecture Spine) and AD-2 (Isolated Process Execution).
public actor ConverterService {
    public static let shared = ConverterService()

    private let processRunner: ProcessRunner
    private let fileManager = FileManager.default

    public init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    /// Converts a validated extension package into an Xcode project.
    ///
    /// - Parameters:
    ///   - package: The validated extension package containing staged files.
    ///   - destinationURL: Optional custom destination directory. Defaults to standard caches.
    ///   - bundleIdentifier: Optional custom bundle identifier. If nil, defaults to `org.waystation.ext.<sanitized-name>`.
    ///   - onOutputLine: Callback streamed line-by-line from the CLI process for the Log Drawer.
    /// - Returns: A `ConvertedProject` value describing the generated project paths.
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
            "--no-open",
            "--no-prompt",
            "--force"
        ]

        // Cooperative asynchronous process execution (AD-2)
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
        try patchXcodeProject(at: xcodeProjURL, appName: cleanAppName, bundleID: resolvedBundleID)

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

    private func patchXcodeProject(at projectURL: URL, appName: String, bundleID: String) throws {
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        let content: String
        do {
            content = try String(contentsOf: pbxprojURL, encoding: .utf8)
        } catch {
            throw WaystationError.conversionFailed(
                reason: "Eșec la citirea project.pbxproj din '\(pbxprojURL.path)': \(error.localizedDescription)",
                exitCode: 1
            )
        }

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

        do {
            try updated.write(to: pbxprojURL, atomically: true, encoding: .utf8)
        } catch {
            throw WaystationError.conversionFailed(
                reason: "Eșec la salvarea modificărilor în project.pbxproj: \(error.localizedDescription)",
                exitCode: 1
            )
        }
    }

    private func buildAndStageContainerApp(
        projectURL: URL,
        appName: String,
        onOutputLine: (@Sendable (String) -> Void)?
    ) async throws -> URL? {
        onOutputLine?("[Build] Compiling container application for '\(appName)'...")

        let signingIdentity = await SigningManager.shared.detectSigningIdentity(onOutputLine: onOutputLine)

        // Discover the actual macOS scheme name. Apple's safari-web-extension-converter
        // generates schemes with platform suffixes like "AppName (macOS)" and "AppName (iOS)"
        // rather than bare "AppName", causing xcodebuild to fail with "does not contain a scheme".
        let schemeName = await discoverMacOSScheme(projectURL: projectURL, appName: appName, onOutputLine: onOutputLine)
        onOutputLine?("[Build] Using scheme: '\(schemeName)'")

        // Isolated temporary DerivedData directory to avoid polluting global Xcode cache
        // and prevent Safari from discovering duplicate intermediate build artifacts.
        let tempDerivedDataURL = fileManager.temporaryDirectory
            .appendingPathComponent("WaystationBuild-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDerivedDataURL, withIntermediateDirectories: true)
        } catch {
            throw WaystationError.projectBuildFailed(reason: "Eșec la crearea folderului temporar de build: \(error.localizedDescription)")
        }

        defer {
            // Clean up temporary build directory when staging finishes
            try? fileManager.removeItem(at: tempDerivedDataURL)
        }

        let buildArgs = [
            "-project", projectURL.path,
            "-scheme", schemeName,
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

        do {
            try fileManager.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
        } catch {
            throw WaystationError.projectBuildFailed(reason: "Eșec la crearea folderului de extensii din Application Support: \(error.localizedDescription)")
        }
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
            let globalDerivedData = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)

            if let enumerator = fileManager.enumerator(at: globalDerivedData, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" && fileURL.lastPathComponent == "\(appName).app" {
                        foundAppURL = fileURL
                        break
                    }
                }
            }
        }

        guard let sourceAppURL = foundAppURL else {
            onOutputLine?("[Build] Note: Could not locate compiled container .app in build directory. Extension can still be launched via Xcode.")
            return nil
        }

        // 3. Stage .app into Application Support/Waystation/Extensions/
        if fileManager.fileExists(atPath: destinationAppURL.path) {
            try? fileManager.removeItem(at: destinationAppURL)
        }

        try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)
        onOutputLine?("[Build] Successfully staged container .app at: \(destinationAppURL.path)")

        // 4. Sign both .appex and .app bundles in place using SigningManager
        do {
            try await SigningManager.shared.sign(targetURL: destinationAppURL, onOutputLine: onOutputLine)
        } catch {
            onOutputLine?("[Build] Warning: Immediate post-build signing failed: \(error.localizedDescription)")
        }

        // 5. Register with macOS LaunchServices so Safari immediately recognizes the extension
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if fileManager.fileExists(atPath: lsregisterPath) {
            _ = try await processRunner.run(
                command: lsregisterPath,
                arguments: ["-f", "-R", destinationAppURL.path],
                onOutputLine: nil
            )
            onOutputLine?("[Build] Registered container app with macOS LaunchServices.")
        }

        return destinationAppURL
    }

    /// Recursively searches for an `.xcodeproj` directory within the given root URL.
    private func findXcodeProject(in rootURL: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "xcodeproj" {
                return fileURL
            }
        }
        return nil
    }

    /// Cleans an app name to ensure safe paths and scheme names.
    private func sanitizeAppName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? "ConvertedExtension" : cleaned
    }

    /// Cleans a bundle identifier slug to strictly conform to reverse-DNS requirements.
    private func sanitizeBundleID(_ name: String) -> String {
        let alphanumeric = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return alphanumeric.isEmpty ? "extension" : alphanumeric
    }

    /// Discovers the actual macOS scheme name from the generated Xcode project.
    ///
    /// Apple's `safari-web-extension-converter` generates schemes with platform suffixes
    /// (e.g. "DarkReader (macOS)", "DarkReader (iOS)") rather than the bare app name.
    /// This function runs `xcodebuild -list` and parses the output to find the correct macOS scheme.
    ///
    /// Falls back to the bare `appName` if scheme discovery fails.
    private func discoverMacOSScheme(
        projectURL: URL,
        appName: String,
        onOutputLine: (@Sendable (String) -> Void)?
    ) async -> String {
        do {
            let listResult = try await processRunner.run(
                command: "/usr/bin/xcodebuild",
                arguments: ["-project", projectURL.path, "-list"],
                onOutputLine: nil
            )

            guard listResult.isSuccess else {
                onOutputLine?("[Build] Warning: Could not list project schemes, falling back to '\(appName)'")
                return appName
            }

            // Parse xcodebuild -list output to extract scheme names
            // The output format is:
            //     Schemes:
            //         DarkReader (iOS)
            //         DarkReader (macOS)
            let output = listResult.standardOutput
            let lines = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

            var inSchemesSection = false
            var schemes: [String] = []

            for line in lines {
                if line.hasPrefix("Schemes:") {
                    inSchemesSection = true
                    continue
                }
                if inSchemesSection {
                    if line.isEmpty || line.hasSuffix(":") {
                        break
                    }
                    schemes.append(line)
                }
            }

            // Priority: prefer "(macOS)" scheme, then any scheme containing the app name, then first available
            if let macOSScheme = schemes.first(where: { $0.contains("(macOS)") }) {
                return macOSScheme
            }
            if let matchingScheme = schemes.first(where: { $0.contains(appName) }) {
                return matchingScheme
            }
            if let firstScheme = schemes.first {
                onOutputLine?("[Build] Warning: No macOS-specific scheme found. Using '\(firstScheme)'")
                return firstScheme
            }
        } catch {
            onOutputLine?("[Build] Warning: Scheme discovery failed: \(error.localizedDescription)")
        }

        return appName
    }
}
