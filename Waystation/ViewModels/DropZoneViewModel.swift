import SwiftUI

/// ViewModel managing state and user actions for the Drop Zone tab.
/// Conforms to Story 1.2, Story 1.3, and Story 1.5 acceptance criteria.
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

    // Story 1.5: Converter state
    public var isConverting: Bool = false
    public var convertedProject: ConvertedProject?
    public var conversionError: WaystationError?
    public var showConversionErrorAlert: Bool = false

    public let logDrawerViewModel: LogDrawerViewModel
    private let extractor: ArchiveExtractor
    private let converterService: ConverterService

    public init(
        extractor: ArchiveExtractor = .shared,
        converterService: ConverterService = .shared,
        logDrawerViewModel: LogDrawerViewModel
    ) {
        self.extractor = extractor
        self.converterService = converterService
        self.logDrawerViewModel = logDrawerViewModel
    }

    public convenience init() {
        self.init(
            extractor: .shared,
            converterService: .shared,
            logDrawerViewModel: .shared
        )
    }

    /// Processes URLs dropped onto the Drop Zone view.
    public func handleDroppedURLs(_ urls: [URL]) async {
        guard let firstURL = urls.first else { return }

        isProcessing = true
        errorMessage = nil
        convertedProject = nil
        conversionError = nil

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

    /// Triggers Safari Web Extension conversion for the current package.
    public func convertCurrentPackage() async {
        guard let package = ingestedPackage else { return }

        isConverting = true
        conversionError = nil
        showConversionErrorAlert = false
        logDrawerViewModel.isStreaming = true
        logDrawerViewModel.append(line: "--- Initiating Conversion Pipeline ---")

        let drawer = self.logDrawerViewModel

        do {
            let project = try await converterService.convert(
                package: package
            ) { line in
                Task { @MainActor in
                    drawer.append(line: line)
                }
            }
            self.convertedProject = project
            self.isConverting = false
            self.logDrawerViewModel.isStreaming = false
        } catch let error as WaystationError {
            self.conversionError = error
            self.showConversionErrorAlert = true
            self.logDrawerViewModel.isExpanded = true
            self.shakeTrigger += 1
            self.isConverting = false
            self.logDrawerViewModel.isStreaming = false
        } catch {
            let wrapped = WaystationError.conversionFailed(reason: error.localizedDescription, exitCode: 1)
            self.conversionError = wrapped
            self.showConversionErrorAlert = true
            self.logDrawerViewModel.isExpanded = true
            self.shakeTrigger += 1
            self.isConverting = false
            self.logDrawerViewModel.isStreaming = false
        }
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
        convertedProject = nil
        conversionError = nil
        errorMessage = nil
    }
}
