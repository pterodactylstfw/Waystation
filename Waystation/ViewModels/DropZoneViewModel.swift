import SwiftUI

/// ViewModel managing state and user actions for the Drop Zone tab.
/// Fulfills Story 1.2 acceptance criteria.
@Observable
@MainActor
public final class DropZoneViewModel {
    public var isTargeted: Bool = false
    public var isProcessing: Bool = false
    public var ingestedPackage: IngestedPackage?
    public var errorMessage: String?
    public var shakeTrigger: Int = 0

    private let extractor: ArchiveExtractor

    public init(extractor: ArchiveExtractor = .shared) {
        self.extractor = extractor
    }

    /// Processes URLs dropped onto the Drop Zone view.
    public func handleDroppedURLs(_ urls: [URL]) async {
        guard let firstURL = urls.first else { return }

        isProcessing = true
        errorMessage = nil

        do {
            let package = try await extractor.extract(sourceURL: firstURL)
            self.ingestedPackage = package
        } catch let error as WaystationError {
            self.errorMessage = error.errorDescription
            self.shakeTrigger += 1
        } catch {
            self.errorMessage = error.localizedDescription
            self.shakeTrigger += 1
        }

        isProcessing = false
    }

    /// Resets the current package state to allow another drop.
    public func reset() {
        ingestedPackage = nil
        errorMessage = nil
    }
}
