import SwiftUI

/// ViewModel managing state and user actions for the Drop Zone tab.
/// Fulfills Story 1.2 and Story 1.3 acceptance criteria.
@Observable
@MainActor
public final class DropZoneViewModel {
    public var isTargeted: Bool = false
    public var isProcessing: Bool = false
    public var ingestedPackage: IngestedPackage?
    public var errorMessage: String?
    public var shakeTrigger: Int = 0

    // Story 1.3: Incompatibility warning state
    public var showIncompatibilitySheet: Bool = false
    public var pendingIncompatiblePackage: IngestedPackage?

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

            switch package.validationResult {
            case .incompatible:
                self.pendingIncompatiblePackage = package
                self.showIncompatibilitySheet = true
            case .valid, .warning:
                self.ingestedPackage = package
            }
        } catch let error as WaystationError {
            self.errorMessage = error.errorDescription
            self.shakeTrigger += 1
        } catch {
            self.errorMessage = error.localizedDescription
            self.shakeTrigger += 1
        }

        isProcessing = false
    }

    /// User confirms proceeding despite incompatible Chrome APIs.
    public func proceedWithIncompatible() {
        if let pending = pendingIncompatiblePackage {
            self.ingestedPackage = pending
        }
        self.pendingIncompatiblePackage = nil
        self.showIncompatibilitySheet = false
    }

    /// User cancels ingestion of incompatible extension.
    public func cancelIncompatible() {
        if let pending = pendingIncompatiblePackage {
            try? FileManager.default.removeItem(at: pending.stagedDirectoryURL)
        }
        self.pendingIncompatiblePackage = nil
        self.showIncompatibilitySheet = false
        reset()
    }

    /// Resets the current package state to allow another drop.
    public func reset() {
        ingestedPackage = nil
        errorMessage = nil
    }
}
