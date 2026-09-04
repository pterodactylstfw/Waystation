import Foundation

/// Represents the captured Chrome Web Store extension details transmitted from the injected web script.
public struct StoreExtensionPayload: Identifiable, Sendable, Hashable {
    public var id: String { extensionId }
    public let extensionId: String
    public let title: String
    public let storeURL: URL

    private static let idRegex = try? NSRegularExpression(pattern: "^[a-z]{32}$")

    public init?(extensionId: String, title: String, storeURL: URL) {
        let cleanedId = extensionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let regex = Self.idRegex,
              let _ = regex.firstMatch(in: cleanedId, range: NSRange(location: 0, length: cleanedId.utf16.count)) else {
            return nil
        }

        self.extensionId = cleanedId
        self.title = title.isEmpty ? "Chrome Extension" : title
        self.storeURL = storeURL
    }
}
