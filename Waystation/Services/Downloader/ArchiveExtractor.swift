import Foundation

public struct IngestedPackage: Sendable, Identifiable, Equatable {
    public nonisolated let id = UUID()
    public let name: String
    public let version: String
    public let stagedDirectoryURL: URL
    public let manifestURL: URL
    public let metadata: ManifestMetadata
    public let validationResult: ManifestValidationResult

    public nonisolated init(
        name: String,
        version: String,
        stagedDirectoryURL: URL,
        manifestURL: URL,
        metadata: ManifestMetadata,
        validationResult: ManifestValidationResult
    ) {
        self.name = name
        self.version = version
        self.stagedDirectoryURL = stagedDirectoryURL
        self.manifestURL = manifestURL
        self.metadata = metadata
        self.validationResult = validationResult
    }
}

public actor ArchiveExtractor {
    public static let shared = ArchiveExtractor()

    private let fileManager = FileManager.default
    private let processRunner: ProcessRunner
    private let manifestParser: ManifestParser

    public init(
        processRunner: ProcessRunner = .shared,
        manifestParser: ManifestParser = .shared
    ) {
        self.processRunner = processRunner
        self.manifestParser = manifestParser
    }

    /// Extrage sau copiază pachetul primit într-un folder de staging din Caches.
    public func extract(sourceURL: URL) async throws -> IngestedPackage {
        let cachesDir = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        let targetDir = cachesDir
            .appendingPathComponent("org.waystation.app")
            .appendingPathComponent("staged")
            .appendingPathComponent(UUID().uuidString)

        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw WaystationError.unarchiveFailed(reason: "Sursa nu există pe disc.")
        }

        if isDir.boolValue {
            let items = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: nil
            )
            for item in items {
                let destURL = targetDir.appendingPathComponent(item.lastPathComponent)
                try fileManager.copyItem(at: item, to: destURL)
            }
        } else {
            let result = try await processRunner.run(
                command: "/usr/bin/ditto",
                arguments: ["-x", "-k", sourceURL.path, targetDir.path]
            )
            guard result.isSuccess else {
                throw WaystationError.unarchiveFailed(reason: "Eșec la dezarhivare: \(result.standardError)")
            }
        }

        // Verifică existența manifest.json și extrage metadata
        let manifestURL = targetDir.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            try? fileManager.removeItem(at: targetDir)
            throw WaystationError.invalidManifest(reason: "Nu a fost găsit niciun manifest.json.")
        }

        let validationResult = try manifestParser.parseAndValidate(manifestURL: manifestURL)
        let metadata = validationResult.metadata

        return IngestedPackage(
            name: metadata.name,
            version: metadata.version,
            stagedDirectoryURL: targetDir,
            manifestURL: manifestURL,
            metadata: metadata,
            validationResult: validationResult
        )
    }
}
