import Foundation

/// Strongly typed representation of Chrome extension manifest.json.
/// Conforms to AD-7 and Story 1.3.
public struct ManifestMetadata: Sendable, Equatable {
    public let name: String
    public let version: String
    public let manifestVersion: Int
    public let descriptionText: String?
    public let permissions: [String]
    public let optionalPermissions: [String]
    public let hostPermissions: [String]
    public let icons: [String: String]

    public nonisolated var allPermissions: [String] {
        Array(Set(permissions + optionalPermissions))
    }

    public nonisolated init(
        name: String,
        version: String,
        manifestVersion: Int,
        descriptionText: String? = nil,
        permissions: [String] = [],
        optionalPermissions: [String] = [],
        hostPermissions: [String] = [],
        icons: [String: String] = [:]
    ) {
        self.name = name
        self.version = version
        self.manifestVersion = manifestVersion
        self.descriptionText = descriptionText
        self.permissions = permissions
        self.optionalPermissions = optionalPermissions
        self.hostPermissions = hostPermissions
        self.icons = icons
    }
}

/// Pre-flight manifest validation result conforming to AD-7.
public enum ManifestValidationResult: Sendable, Equatable {
    case valid(metadata: ManifestMetadata)
    case warning(metadata: ManifestMetadata, warnings: [String])
    case incompatible(metadata: ManifestMetadata, incompatibleAPIs: [String])

    public nonisolated var metadata: ManifestMetadata {
        switch self {
        case .valid(let meta), .warning(let meta, _), .incompatible(let meta, _):
            return meta
        }
    }

    public nonisolated var isFullyCompatible: Bool {
        switch self {
        case .valid: return true
        default: return false
        }
    }

    public nonisolated var incompatibleAPIs: [String] {
        switch self {
        case .incompatible(_, let apis): return apis
        default: return []
        }
    }

    public nonisolated var warnings: [String] {
        switch self {
        case .warning(_, let msgs): return msgs
        default: return []
        }
    }
}
