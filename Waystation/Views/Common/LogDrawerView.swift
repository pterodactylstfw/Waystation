import SwiftUI

/// Collapsible bottom drawer displaying live streaming terminal output.
/// Conforms to Story 1.4 and macOS 26/27 Liquid Glass design principles.
@MainActor
public struct LogDrawerView: View {
    @Bindable var viewModel: LogDrawerViewModel

    public init(viewModel: LogDrawerViewModel) {
        self.viewModel = viewModel
    }

    public init() {
        self.viewModel = .shared
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            if viewModel.isExpanded {
                Divider()
                consoleBody
                    .frame(height: 220)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .liquidGlass(cornerRadius: 0, intensity: .standard)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.04), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                ),
            alignment: .top
        )
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleExpanded()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.isStreaming ? Color.green : Color.primary)

                    Text("Process Output")
                        .font(.system(size: 12, weight: .medium))

                    if !viewModel.entries.isEmpty {
                        Text("\(viewModel.entries.count)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    if viewModel.isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if !viewModel.entries.isEmpty {
                Button {
                    viewModel.copyLogs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.copiedToast ? "checkmark" : "doc.on.doc")
                        Text(viewModel.copiedToast ? "Copied!" : "Copy Logs")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(viewModel.copiedToast ? .green : nil)

                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear logs")
            }

            Button {
                viewModel.toggleExpanded()
            } label: {
                Image(systemName: viewModel.isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private var consoleBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(viewModel.entries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.formattedTime)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)

                            Text(entry.text)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(entry.isError ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            .onChange(of: viewModel.entries.count) { _, _ in
                if let last = viewModel.entries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
