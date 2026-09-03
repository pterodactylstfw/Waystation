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
/// Conforms to Story 1.2 acceptance criteria.
public struct DropZoneView: View {
    @State private var viewModel = DropZoneViewModel()
    @State private var shakeAnimValue: CGFloat = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            if let package = viewModel.ingestedPackage {
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

                Text("Version \(package.version)")
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
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
