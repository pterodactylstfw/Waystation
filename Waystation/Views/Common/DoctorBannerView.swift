import SwiftUI

/// Warning banner displayed when Xcode Command Line Tools or converter tools are missing.
/// Conforms to Liquid Glass design standards (macOS 26/27).
public struct DoctorBannerView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        if appState.showDoctorWarning, let report = appState.doctorReport {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: report))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description(for: report))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        appState.copyCLTInstallCommand()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appState.copiedCommandToast ? "checkmark" : "doc.on.doc")
                            Text(appState.copiedCommandToast ? "Copied to Clipboard!" : "Copy '\(report.remediationCommand)'")
                        }
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.copiedCommandToast ? .green : .orange)

                    Button {
                        Task {
                            await appState.checkEnvironment()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .help("Re-check system prerequisites")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isCheckingDoctor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .liquidGlass(cornerRadius: 14, intensity: .prominent, tintColor: .orange)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func title(for report: DoctorReport) -> String {
        if !report.isCommandLineToolsInstalled {
            return "Xcode Command Line Tools Missing"
        } else if !report.isConverterAvailable {
            return "Safari Web Extension Converter Missing"
        }
        return "Developer Tools Notice"
    }

    private func description(for report: DoctorReport) -> String {
        if !report.isCommandLineToolsInstalled {
            return "Waystation requires Xcode Command Line Tools to convert and build extensions for Safari."
        } else if !report.isConverterAvailable {
            if report.isXcodeAppPresent {
                return "Xcode is installed, but the active developer directory is not pointing to it. Run the switch command."
            } else {
                return "Full Xcode.app is required for Apple's 'safari-web-extension-converter'. Please install Xcode from Mac App Store."
            }
        }
        return ""
    }
}
