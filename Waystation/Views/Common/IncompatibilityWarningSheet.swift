import SwiftUI

/// Warning sheet displayed when an extension uses Chrome APIs unsupported in Safari.
/// Conforms to Story 1.3 acceptance criteria.
public struct IncompatibilityWarningSheet: View {
    public let extensionName: String
    public let incompatibleAPIs: [String]
    public let onProceed: () -> Void
    public let onCancel: () -> Void

    public init(
        extensionName: String,
        incompatibleAPIs: [String],
        onProceed: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.extensionName = extensionName
        self.incompatibleAPIs = incompatibleAPIs
        self.onProceed = onProceed
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("Incompatible Chrome APIs Detected")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("'\(extensionName)' requests APIs that are not supported by Apple Safari. Some capabilities may not function or may be silently ignored.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Unsupported APIs requested:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(incompatibleAPIs, id: \.self) { api in
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)

                                Text(api)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onProceed()
                } label: {
                    Text("Proceed Anyway")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 480)
    }
}
