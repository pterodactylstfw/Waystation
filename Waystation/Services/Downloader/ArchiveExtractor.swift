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
    /// Suportă foldere despachetate, arhive .zip și pachete .crx (CRX2/CRX3).
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
            let (archiveURL, isTemp) = try prepareExtractionArchive(from: sourceURL)
            defer {
                if isTemp {
                    try? fileManager.removeItem(at: archiveURL)
                }
            }

            let result = try await processRunner.run(
                command: "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, targetDir.path]
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

    /// Verifică dacă fișierul este un pachet CRX2/CRX3. Dacă da, elimină antetul binar
    /// și creează un fișier temporar .zip ce poate fi extras curat cu ditto.
    private func prepareExtractionArchive(from fileURL: URL) throws -> (archiveURL: URL, isTemporary: Bool) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        guard let magicData = try handle.read(upToCount: 4), magicData.count == 4 else {
            return (fileURL, false)
        }

        let magic = [UInt8](magicData)
        // "Cr24" = [0x43, 0x72, 0x32, 0x34]
        if magic == [0x43, 0x72, 0x32, 0x34] {
            guard let versionData = try handle.read(upToCount: 4), versionData.count == 4 else {
                throw WaystationError.unarchiveFailed(reason: "Header CRX invalid (nu se poate citi versiunea).")
            }
            let version = versionData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }

            var zipOffset: UInt64 = 0
            if version == 2 {
                guard let lengthsData = try handle.read(upToCount: 8), lengthsData.count == 8 else {
                    throw WaystationError.unarchiveFailed(reason: "Header CRX2 invalid.")
                }
                let pubKeyLen = lengthsData.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                let sigLen = lengthsData.suffix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                zipOffset = 16 + UInt64(pubKeyLen) + UInt64(sigLen)
            } else if version == 3 {
                guard let headerLenData = try handle.read(upToCount: 4), headerLenData.count == 4 else {
                    throw WaystationError.unarchiveFailed(reason: "Header CRX3 invalid.")
                }
                let headerLen = headerLenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                zipOffset = 12 + UInt64(headerLen)
            } else {
                throw WaystationError.unarchiveFailed(reason: "Versiune CRX nesuportată: \(version).")
            }

            try handle.seek(toOffset: zipOffset)
            guard let remainingData = try handle.readToEnd(), !remainingData.isEmpty else {
                throw WaystationError.unarchiveFailed(reason: "Pachetul CRX nu conține o arhivă ZIP validă.")
            }

            // Verifică semnătura standard PK\x03\x04
            guard remainingData.count >= 4,
                  remainingData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) else {
                throw WaystationError.unarchiveFailed(reason: "Formatul arhivei ZIP din interiorul CRX este invalid.")
            }

            let tempZipURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            try remainingData.write(to: tempZipURL)
            return (tempZipURL, true)
        }

        return (fileURL, false)
    }
}
