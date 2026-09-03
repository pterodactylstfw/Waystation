import SwiftUI
import UniformTypeIdentifiers

/// Custom GeometryEffect for horizontal shake animation on drop error.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 4
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// Interactive drop zone view for unpacked extension folders, .zip, and .crx packages.
/// Conforms to Story 1.2, Story 1.3, and Story 1.5 acceptance criteria.
@MainActor
public struct DropZoneView: View {
    @State private var viewModel: DropZoneViewModel
    @State private var shakeAnimValue: CGFloat = 0

    public init(viewModel: DropZoneViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public init() {
        self._viewModel = State(initialValue: DropZoneViewModel())
    }

    public var body: some View {
        VStack(spacing: 24) {
            if let project = viewModel.convertedProject {
                convertedProjectCard(project)
            } else if let package = viewModel.ingestedPackage {
                packageDetailsCard(package)
            } else {
                dropTargetBox
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .modifier(ShakeEffect(animatableData: shakeAnimValue))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.shakeTrigger) { _, _ in
            shakeAnimValue = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.25, blendDuration: 0)) {
                shakeAnimValue = 1
            }
        }
        .sheet(isPresented: $viewModel.showIncompatibilitySheet) {
            if let pending = viewModel.pendingIncompatiblePackage {
                IncompatibilityWarningSheet(
                    extensionName: pending.name,
                    incompatibleAPIs: pending.validationResult.incompatibleAPIs,
                    onProceed: {
                        viewModel.proceedWithIncompatible()
                    },
                    onCancel: {
                        viewModel.cancelIncompatible()
                    }
                )
            }
        }
        .alert("Conversion Failed", isPresented: $viewModel.showConversionErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let err = viewModel.conversionError {
                Text(err.localizedDescription + "\n\n" + (err.recoverySuggestion ?? ""))
            } else {
                Text("An unknown error occurred during conversion.")
            }
        }
    }

    private var dropTargetBox: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(viewModel.isTargeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: viewModel.isProcessing ? "gearshape.arrow.triangle.2.circlepath" : "arrow.down.doc.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(viewModel.isTargeted ? Color.accentColor : Color.secondary)
                    .rotationEffect(viewModel.isProcessing ? .degrees(360) : .zero)
                    .animation(viewModel.isProcessing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isProcessing)
            }

            VStack(spacing: 6) {
                Text(viewModel.isProcessing ? "Ingesting Package..." : "Drag & Drop Chrome Extension Here")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Accepts unpacked extension folders, .zip archives, and .crx packages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectFileWithOpenPanel()
            } label: {
                Label("Browse Files...", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(viewModel.isProcessing)
        }
        .frame(maxWidth: 580, maxHeight: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    viewModel.isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: viewModel.isTargeted ? 3 : 2, dash: [8])
                )
        )
        .modifier(ShakeEffect(animatableData: shakeAnimValue))
        .dropDestination(for: URL.self) { items, _ in
            Task {
                await viewModel.handleDroppedURLs(items)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.isTargeted = targeted
            }
        }
    }

    private func packageDetailsCard(_ package: IngestedPackage) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 4) {
                Text(package.name)
                    .font(.title)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text("Version \(package.version)")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())

                    Text("Manifest v\(package.metadata.manifestVersion)")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if !package.validationResult.incompatibleAPIs.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Contains unsupported Chrome APIs (\(package.validationResult.incompatibleAPIs.joined(separator: ", ")))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Staged Location:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(package.stagedDirectoryURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: 480)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    viewModel.reset()
                } label: {
                    Label("Choose Another", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isConverting)

                Button {
                    Task {
                        await viewModel.convertCurrentPackage()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isConverting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Converting...")
                        } else {
                            Image(systemName: "safari.fill")
                            Text("Convert to Safari Extension")
                        }
                    }
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isConverting)
            }
        }
        .padding(32)
        .frame(maxWidth: 580)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }

    private func convertedProjectCard(_ project: ConvertedProject) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 4) {
                Text("Xcode Project Ready")
                    .font(.title)
                    .fontWeight(.bold)

                Text(project.appName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(project.bundleIdentifier)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Generated Xcode Project:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(project.xcodeProjectURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: 480)

            HStack(spacing: 12) {
                Button {
                    viewModel.reset()
                } label: {
                    Label("Convert Another", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([project.xcodeProjectURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    // Ready for Story 2/3 Build & Install
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                        Text("Ready to Build")
                    }
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: 580)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }

    private func selectFileWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip, UTType(filenameExtension: "crx") ?? .data]
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                Task {
                    await viewModel.handleDroppedURLs([selectedURL])
                }
            }
        }
    }
}
