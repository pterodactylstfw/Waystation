import Foundation

/// Headless conversion service orchestrating Apple's `safari-web-extension-converter`.
/// Conforms to AD-3, FR-6 and Story 1.5 acceptance criteria.
public actor ConverterService {
    public static let shared = ConverterService()

    private let fileManager = FileManager.default
    private let processRunner: ProcessRunner

    public init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    /// Converts an ingested Chrome extension into a native Safari Web Extension Xcode wrapper project.
    public func convert(
        package: IngestedPackage,
        bundleIdentifier: String? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ConvertedProject {
        // 1. Prepare output directory in ~/Library/Caches/org.waystation.app/converted/<UUID>
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let projectLocationURL = cachesDir
            .appendingPathComponent("org.waystation.app")
            .appendingPathComponent("converted")
            .appendingPathComponent(UUID().uuidString)

        try fileManager.createDirectory(at: projectLocationURL, withIntermediateDirectories: true)

        // 2. Sanitize app name and bundle identifier
        let cleanAppName = sanitizeAppName(package.name)
        let resolvedBundleID = bundleIdentifier ?? ("org.waystation.ext." + sanitizeBundleID(cleanAppName))

        onOutputLine?("Starting Safari Web Extension conversion for '\(package.name)'...")
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

        return ConvertedProject(
            appName: cleanAppName,
            bundleIdentifier: resolvedBundleID,
            projectLocationURL: projectLocationURL,
            xcodeProjectURL: xcodeProjURL,
            sourcePackage: package
        )
    }

    private func findXcodeProject(in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
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

    private func sanitizeAppName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        let clean = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? "SafariExtension" : clean
    }

    private func sanitizeBundleID(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let lowercased = raw.lowercased().replacingOccurrences(of: " ", with: "-")
        let filtered = lowercased.unicodeScalars.filter { allowed.contains($0) }
        let clean = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return clean.isEmpty ? "extension" : clean
    }
}
