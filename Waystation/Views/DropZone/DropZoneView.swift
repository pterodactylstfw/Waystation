import SwiftUI
import UniformTypeIdentifiers

/// Geometry effect producing a horizontal spring shake animation for invalid inputs.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 3), y: 0))
    }
}

/// Tab 2 View: Interactive drag-and-drop ingestion zone with Liquid Glass portal aesthetics (macOS 26/27).
public struct DropZoneView: View {
    @Bindable var viewModel: DropZoneViewModel
    @State private var shakeAnimValue: CGFloat = 0
    var onGoToLibrary: (() -> Void)?

    public init(viewModel: DropZoneViewModel, onGoToLibrary: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onGoToLibrary = onGoToLibrary
    }

    public var body: some View {
        ZStack {
            LiquidAmbientBackground()

            VStack(spacing: 24) {
                if let converted = viewModel.convertedProject {
                    convertedProjectCard(converted)
                } else if let package = viewModel.ingestedPackage {
                    packageDetailsCard(package)
                } else {
                    dropTargetBox
                }

                // Inline Error Banner with Shake Animation
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 12, intensity: .subtle, tintColor: .red)
                    .modifier(ShakeEffect(animatableData: shakeAnimValue))
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        VStack(spacing: 20) {
            // Concentric Glowing Glass Rings
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (viewModel.isTargeted ? Color.accentColor : Color.blue).opacity(0.18),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 55
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 6)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(viewModel.isTargeted ? 0.4 : 0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 84, height: 84)

                Image(systemName: viewModel.isProcessing ? "gearshape.arrow.triangle.2.circlepath" : (viewModel.isTargeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill"))
                    .font(.system(size: 38))
                    .foregroundStyle(
                        LinearGradient(
                            colors: viewModel.isTargeted ? [Color.blue, Color.purple] : [Color.accentColor, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(viewModel.isProcessing ? .degrees(360) : .zero)
                    .animation(viewModel.isProcessing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isProcessing)
                    .scaleEffect(viewModel.isTargeted ? 1.08 : 1.0)
            }

            VStack(spacing: 6) {
                Text(viewModel.isProcessing ? "Ingesting Package..." : "Drag & Drop Chrome Extension Here")
                    .font(.title2)
                    .fontWeight(.bold)

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

            // Supported format chips
            HStack(spacing: 8) {
                formatChip(".crx")
                formatChip(".zip")
                formatChip("folder")
                formatChip("manifest.json")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 580, minHeight: 330)
        .padding(36)
        .liquidGlass(
            cornerRadius: 24,
            intensity: viewModel.isTargeted ? .prominent : .standard,
            tintColor: viewModel.isTargeted ? Color.accentColor : nil
        )
        .scaleEffect(viewModel.isTargeted ? 1.015 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isTargeted)
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

    private func formatChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())
    }

    private func packageDetailsCard(_ package: IngestedPackage) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 68, height: 68)

                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(package.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text("Version \(package.version)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    Text("Manifest v\(package.metadata.manifestVersion)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Staged Location:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(package.stagedDirectoryURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .liquidGlass(cornerRadius: 20, intensity: .standard)
    }

    private func convertedProjectCard(_ project: ConvertedProject) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 68, height: 68)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text("Xcode Project Ready")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(project.appName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(project.bundleIdentifier)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
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
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

                if let onGoToLibrary {
                    Button {
                        viewModel.reset()
                        onGoToLibrary()
                    } label: {
                        Label("Go to Library", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 580)
        .liquidGlass(cornerRadius: 20, intensity: .standard)
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
