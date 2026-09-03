import Foundation

/// Decoupled pre-flight manifest parser and compatibility linter.
/// Conforms to AD-7 and Story 1.3 acceptance criteria.
public struct ManifestParser: Sendable {
    public nonisolated static let shared = ManifestParser()

    /// Known Chrome extension APIs that are not supported in Apple Safari Web Extensions.
    public nonisolated static let knownIncompatibleAPIs: Set<String> = [
        "debugger",
        "declarativeContent",
        "desktopCapture",
        "documentScan",
        "enterprise.deviceAttributes",
        "enterprise.hardwarePlatform",
        "enterprise.networkingAttributes",
        "enterprise.platformKeys",
        "fileBrowserHandler",
        "fileSystemProvider",
        "fontSettings",
        "gcm",
        "identity.email",
        "input",
        "loginState",
        "networking.config",
        "platformKeys",
        "processes",
        "proxy",
        "system.cpu",
        "system.display",
        "system.memory",
        "system.storage",
        "tabCapture",
        "tts",
        "ttsEngine",
        "vpnProvider",
        "wallpaper"
    ]

    public nonisolated init() {}

    /// Parses a manifest.json file from disk and evaluates Safari compatibility.
    public nonisolated func parseAndValidate(manifestURL: URL) throws -> ManifestValidationResult {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw WaystationError.invalidManifest(reason: "Fișierul manifest.json nu a fost găsit la calea specificată.")
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw WaystationError.invalidManifest(reason: "Fișierul manifest.json nu a putut fi citit: \(error.localizedDescription)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WaystationError.invalidManifest(reason: "Format JSON nevalid în manifest.json.")
        }

        guard let name = json["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WaystationError.invalidManifest(reason: "Câmpul obligatoriu 'name' lipsește sau este gol.")
        }

        guard let version = json["version"] as? String, !version.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WaystationError.invalidManifest(reason: "Câmpul obligatoriu 'version' lipsește sau este gol.")
        }

        let manifestVersion = json["manifest_version"] as? Int ?? 2
        let description = json["description"] as? String
        let permissions = json["permissions"] as? [String] ?? []
        let optionalPermissions = json["optional_permissions"] as? [String] ?? []
        let hostPermissions = json["host_permissions"] as? [String] ?? []
        let icons = json["icons"] as? [String: String] ?? [:]

        let metadata = ManifestMetadata(
            name: name,
            version: version,
            manifestVersion: manifestVersion,
            descriptionText: description,
            permissions: permissions,
            optionalPermissions: optionalPermissions,
            hostPermissions: hostPermissions,
            icons: icons
        )

        // Check for incompatible APIs
        var detectedIncompatible: [String] = []
        for perm in metadata.allPermissions {
            // Check direct match or prefix match (e.g. chrome.debugger or debugger)
            let cleanPerm = perm.replacingOccurrences(of: "chrome.", with: "")
            if Self.knownIncompatibleAPIs.contains(cleanPerm) {
                detectedIncompatible.append(perm)
            }
        }

        if !detectedIncompatible.isEmpty {
            return .incompatible(metadata: metadata, incompatibleAPIs: detectedIncompatible.sorted())
        }

        // Check non-fatal warnings
        var warnings: [String] = []
        if manifestVersion < 2 || manifestVersion > 3 {
            warnings.append("Versiunea de manifest (\(manifestVersion)) poate necesita ajustări pentru Safari.")
        }

        if !warnings.isEmpty {
            return .warning(metadata: metadata, warnings: warnings)
        }

        return .valid(metadata: metadata)
    }
}
