import Foundation

/// Represents a successfully generated Safari Web Extension Xcode project.
/// Conforms to Story 1.5, Story 3.1, and AD-3.
public struct ConvertedProject: Identifiable, Sendable, Equatable {
    public nonisolated let id: UUID
    public let appName: String
    public let bundleIdentifier: String
    public let projectLocationURL: URL
    public let xcodeProjectURL: URL
    public let containerAppURL: URL?
    public let sourcePackage: IngestedPackage

    public nonisolated init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        projectLocationURL: URL,
        xcodeProjectURL: URL,
        containerAppURL: URL? = nil,
        sourcePackage: IngestedPackage
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.projectLocationURL = projectLocationURL
        self.xcodeProjectURL = xcodeProjectURL
        self.containerAppURL = containerAppURL
        self.sourcePackage = sourcePackage
    }
}
