import SwiftUI
import Observation

/// Unified navigation tabs supported by the application shell.
public enum AppTab: String, CaseIterable, Identifiable {
    case store = "Store"
    case dropZone = "Drop Zone"
    case library = "Library"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .store: return "bag"
        case .dropZone: return "arrow.down.doc"
        case .library: return "square.grid.2x2"
        }
    }
}

public extension Notification.Name {
    static let showHelpGuide = Notification.Name("WaystationShowHelpGuide")
}

/// Central application state coordinator conforming to AD-1.
/// Manages global navigation, environment checks, and child view models.
@Observable
@MainActor
public final class AppState {
    public var selectedTab: AppTab = .store
    public var doctorReport: DoctorReport?
    public var isCheckingDoctor: Bool = false
    public var copiedCommandToast: Bool = false
    public var showHelpGuide: Bool = false

    public var logDrawerViewModel: LogDrawerViewModel
    public var dropZoneViewModel: DropZoneViewModel
    public var libraryViewModel: LibraryViewModel
    public var storeViewModel: StoreViewModel

    /// Whether the warning banner should appear (if Command Line Tools are missing)
    public var showDoctorWarning: Bool {
        guard let report = doctorReport else { return false }
        return !report.isCommandLineToolsInstalled || !report.isConverterAvailable
    }

    private let doctorService: DoctorService

    public init(
        doctorService: DoctorService = .shared,
        logDrawerViewModel: LogDrawerViewModel = .shared,
        dropZoneViewModel: DropZoneViewModel? = nil,
        libraryViewModel: LibraryViewModel? = nil,
        storeViewModel: StoreViewModel? = nil
    ) {
        self.doctorService = doctorService
        self.logDrawerViewModel = logDrawerViewModel
        self.dropZoneViewModel = dropZoneViewModel ?? DropZoneViewModel(logDrawerViewModel: logDrawerViewModel)
        self.libraryViewModel = libraryViewModel ?? LibraryViewModel(logDrawerViewModel: logDrawerViewModel)

        if let storeViewModel = storeViewModel {
            self.storeViewModel = storeViewModel
        } else {
            let store = StoreViewModel(logDrawerViewModel: logDrawerViewModel)
            self.storeViewModel = store
            store.onTriggerPipeline = { [weak self] crxURL in
                await self?.triggerConversionPipeline(for: crxURL)
            }
        }
    }

    /// Verifies system developer prerequisites.
    public func checkEnvironment() async {
        isCheckingDoctor = true
        let report = await doctorService.checkPrerequisites()
        self.doctorReport = report
        self.isCheckingDoctor = false
    }

    /// Copies remediation command to macOS pasteboard as required by Story 1.1.
    public func copyCLTInstallCommand() {
        let command = doctorReport?.remediationCommand ?? "xcode-select --install"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation {
            copiedCommandToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                self.copiedCommandToast = false
            }
        }
    }

    /// Triggers automated pipeline execution from Store tab download (Story 2.3).
    public func triggerConversionPipeline(for crxURL: URL) async {
        selectedTab = .dropZone
        await dropZoneViewModel.handleIngestedFileURL(crxURL)
    }
}
