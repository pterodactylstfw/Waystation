//
//  ArchiveExtractor.swift
//  Waystation
//
//  Created by Raul Constantin on 03/09/2026.
//

import Foundation

public struct IngestedPackage: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let version: String
    public let stagedDirectoryURL: URL
    public let manifestURL: URL
}

public actor ArchiveExtractor {
    public static let shared = ArchiveExtractor()
    
    private let fileManager = FileManager.default
    private let processRunner: ProcessRunner
    
    public init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
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

        // 2. Verificăm dacă sourceURL este folder sau fișier
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw WaystationError.unarchiveFailed(reason: "Sursa nu există pe disc.")
        }

        // AICI vei scrie tu logica:
        // DACĂ isDir.boolValue == true:
        //    copiază fișierele din sourceURL în targetDir
        // ALTFEL (este arhivă .zip sau .crx):
        //    extrage arhiva în targetDir
        
        if isDir.boolValue {
            let items = try fileManager.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: nil
            )
            for item in items {
                let destURL = targetDir.appendingPathComponent(
                    item.lastPathComponent
                )
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

        // 3. Verifică existența manifest.json și extrage numele/versiunea
        let manifestURL = targetDir.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            // Curățăm targetDir dacă e invalid
            try? fileManager.removeItem(at: targetDir)
            throw WaystationError.invalidManifest(reason: "Nu a fost găsit niciun manifest.json.")
        }

        // 4. Citim name și version din manifest.json
        let (name, version) = try parseBasicManifest(at: manifestURL)

        return IngestedPackage(
            name: name,
            version: version,
            stagedDirectoryURL: targetDir,
            manifestURL: manifestURL
        )
    }

    /// Citește name și version dintr-un manifest.json
    private func parseBasicManifest(at url: URL) throws -> (name: String, version: String) {
        let data = try Data(contentsOf: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WaystationError.invalidManifest(reason: "Fișierul manifest.json nu este un JSON valid.")
        }

        let name = json["name"] as? String ?? "Unnamed Extension"
        let version = json["version"] as? String ?? "1.0.0"

        return (name, version)
    }
    }

