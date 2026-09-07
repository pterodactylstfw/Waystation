import SwiftUI

/// Card view representing a single installed Safari extension in the Library.
/// Conforms to Story 3.1, Story 3.2, and Story 3.3.
public struct ExtensionRowView: View {
    public let ext: InstalledExtension
    public let onReveal: () -> Void
    public let onUninstall: () -> Void

    public init(
        ext: InstalledExtension,
        onReveal: @escaping () -> Void,
        onUninstall: @escaping () -> Void
    ) {
        self.ext = ext
        self.onReveal = onReveal
        self.onUninstall = onUninstall
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: ext.installedDate)
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Extension Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                if let data = ext.iconData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Extension Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ext.name)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text("v\(ext.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Text(ext.bundleIdentifier)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(formattedDate, systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // 7-day expiration status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ext.expirationStatus.badgeColor)
                            .frame(width: 7, height: 7)

                        Text(badgeText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ext.expirationStatus.badgeColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ext.expirationStatus.badgeColor.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.top, 2)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Reveal container app in Finder")

                Button(role: .destructive) {
                    onUninstall()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Uninstall extension")
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private var badgeText: String {
        let days = ext.daysRemaining
        switch ext.expirationStatus {
        case .valid:
            return "\(days) days remaining"
        case .warning:
            return "\(days) day\(days == 1 ? "" : "s") left"
        case .expired:
            return "Expired"
        }
    }
}
