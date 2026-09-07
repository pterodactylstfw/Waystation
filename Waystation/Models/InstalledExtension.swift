import Foundation
import SwiftUI

/// Status representing the remaining validity of the 7-day personal team signing certificate.
public enum CertificateExpirationStatus: String, Sendable, Codable {
    case valid      // 3 to 7 days remaining (Green)
    case warning    // <= 2 days remaining (Orange)
    case expired    // 0 days or negative (Red)

    public var badgeColor: Color {
        switch self {
        case .valid: return .green
        case .warning: return .orange
        case .expired: return .red
        }
    }

    public var title: String {
        switch self {
        case .valid: return "Valid"
        case .warning: return "Expires Soon"
        case .expired: return "Expired"
        }
    }
}

/// Persistent record of an installed Safari Web Extension container app.
/// Conforms to AD-5 and Story 3.1 acceptance criteria.
public struct InstalledExtension: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var version: String
    public var bundleIdentifier: String
    public var containerAppPath: String
    public var installedDate: Date
    public var lastSignedDate: Date
    public var iconData: Data?

    public init(
        id: String,
        name: String,
        version: String,
        bundleIdentifier: String,
        containerAppPath: String,
        installedDate: Date = Date(),
        lastSignedDate: Date = Date(),
        iconData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.bundleIdentifier = bundleIdentifier
        self.containerAppPath = containerAppPath
        self.installedDate = installedDate
        self.lastSignedDate = lastSignedDate
        self.iconData = iconData
    }

    /// URL to the container `.app` on disk.
    public var containerAppURL: URL {
        URL(fileURLWithPath: containerAppPath)
    }

    /// Whether the `.app` bundle actually exists on disk.
    public var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: containerAppPath)
    }

    /// Number of days remaining before the 7-day personal certificate expires.
    public var daysRemaining: Int {
        let expirationDate = Calendar.current.date(byAdding: .day, value: 7, to: lastSignedDate) ?? lastSignedDate
        let components = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate)
        return components.day ?? 0
    }

    /// Expiration status categorization (Green, Orange, Red).
    public var expirationStatus: CertificateExpirationStatus {
        let days = daysRemaining
        if days >= 3 {
            return .valid
        } else if days > 0 {
            return .warning
        } else {
            return .expired
        }
    }
}
