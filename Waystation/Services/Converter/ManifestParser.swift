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

    /// Parses a manifest.json file from disk, resolves Chrome i18n message tokens, and evaluates Safari compatibility.
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

        guard let rawName = json["name"] as? String, !rawName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WaystationError.invalidManifest(reason: "Câmpul obligatoriu 'name' lipsește sau este gol.")
        }

        guard let version = json["version"] as? String, !version.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WaystationError.invalidManifest(reason: "Câmpul obligatoriu 'version' lipsește sau este gol.")
        }

        let defaultLocale = json["default_locale"] as? String
        let name = resolveI18nString(rawName, manifestURL: manifestURL, defaultLocale: defaultLocale)
        let manifestVersion = json["manifest_version"] as? Int ?? 2
        let rawDescription = json["description"] as? String
        let description = rawDescription.map { resolveI18nString($0, manifestURL: manifestURL, defaultLocale: defaultLocale) }
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

    /// Resolves Chrome extension i18n message strings formatted as `__MSG_<message_name>__`.
    /// Reads from `_locales/<default_locale>/messages.json` or fallback locales if present.
    private nonisolated func resolveI18nString(_ raw: String, manifestURL: URL, defaultLocale: String?) -> String {
        guard raw.hasPrefix("__MSG_") && raw.hasSuffix("__") && raw.count > 8 else {
            return raw
        }

        let key = String(raw.dropFirst(6).dropLast(2))
        let extensionDir = manifestURL.deletingLastPathComponent()
        let localesDir = extensionDir.appendingPathComponent("_locales")

        guard FileManager.default.fileExists(atPath: localesDir.path) else {
            return raw
        }

        // Candidate locales: defaultLocale, "en", "en_US", "en_GB", or any locale directory
        var candidateLocales: [String] = []
        if let defaultLocale = defaultLocale, !defaultLocale.isEmpty {
            candidateLocales.append(defaultLocale)
        }
        candidateLocales.append(contentsOf: ["en", "en_US", "en_GB"])

        if let allDirs = try? FileManager.default.contentsOfDirectory(atPath: localesDir.path) {
            for dir in allDirs where !candidateLocales.contains(dir) {
                candidateLocales.append(dir)
            }
        }

        for locale in candidateLocales {
            let messagesURL = localesDir.appendingPathComponent(locale).appendingPathComponent("messages.json")
            guard FileManager.default.fileExists(atPath: messagesURL.path),
                  let data = try? Data(contentsOf: messagesURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = json[key] as? [String: Any],
                  let message = entry["message"] as? String,
                  !message.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            return message.trimmingCharacters(in: .whitespaces)
        }

        return raw
    }
}
