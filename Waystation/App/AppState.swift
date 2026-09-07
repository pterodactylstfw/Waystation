import SwiftUI

/// Top-level tabs available in Waystation.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case store = "Store"
    case dropZone = "Drop Zone"
    case library = "Library"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .store: return "globe"
        case .dropZone: return "arrow.down.doc.fill"
        case .library: return "square.grid.2x2.fill"
        }
    }
}

/// Central application state coordinator conforming to AD-1.
/// Managed on `@MainActor` with `@Observable` macros (no Combine).
@Observable
@MainActor
public final class AppState {
    public var selectedTab: AppTab = .store
    public var doctorReport: DoctorReport?
    public var isCheckingDoctor: Bool = false
    public var copiedCommandToast: Bool = false

    public var logDrawerViewModel: LogDrawerViewModel
    public var dropZoneViewModel: DropZoneViewModel
    public var libraryViewModel: LibraryViewModel

    /// Whether the warning banner should appear (if Command Line Tools are missing)
    public var showDoctorWarning: Bool {
        guard let report = doctorReport else { return false }
        return !report.isCommandLineToolsInstalled || !report.isConverterAvailable
    }

    private let doctorService: DoctorService

    public init(
        doctorService: DoctorService = .shared,
        logDrawerViewModel: LogDrawerViewModel = .shared
    ) {
        self.doctorService = doctorService
        self.logDrawerViewModel = logDrawerViewModel
        self.dropZoneViewModel = DropZoneViewModel(logDrawerViewModel: logDrawerViewModel)
        self.libraryViewModel = LibraryViewModel(logDrawerViewModel: logDrawerViewModel)
    }

    /// Verifies system developer prerequisites.
    public func checkEnvironment() async {
        isCheckingDoctor = true
        let report = await doctorService.checkPrerequisites()
        self.doctorReport = report
        self.isCheckingDoctor = false
    }

    /// Copies 'xcode-select --install' to macOS pasteboard as required by Story 1.1.
    public func copyCLTInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("xcode-select --install", forType: .string)
        withAnimation {
            copiedCommandToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                self.copiedCommandToast = false
            }
        }
    }

    /// Ingests a downloaded package from Store and automatically launches the conversion pipeline.
    public func triggerConversionPipeline(for sourceURL: URL) async {
        selectedTab = .dropZone
        await dropZoneViewModel.handleDroppedURLs([sourceURL])
        if dropZoneViewModel.ingestedPackage != nil && !dropZoneViewModel.showIncompatibilitySheet {
            await dropZoneViewModel.convertCurrentPackage()
        }
    }
}
