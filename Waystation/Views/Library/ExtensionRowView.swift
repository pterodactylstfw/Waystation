import SwiftUI

/// Card view representing a single installed Safari extension in the Library.
/// Conforms to Story 3.1, Story 3.2, and Story 3.3.
public struct ExtensionRowView: View {
    public let ext: InstalledExtension
    public let signatureStatus: SignatureVerificationResult?
    public let onReveal: () -> Void
    public let onUninstall: () -> Void

    public init(
        ext: InstalledExtension,
        signatureStatus: SignatureVerificationResult? = nil,
        onReveal: @escaping () -> Void,
        onUninstall: @escaping () -> Void
    ) {
        self.ext = ext
        self.signatureStatus = signatureStatus
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

                    if ext.expirationStatus == .expired {
                        // Expired state: Clear and unified indication
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)

                            Text("Certificate Expired")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.orange)

                            Text("Re-sign Required")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .help("The 7-day Apple developer certificate has expired. Click 'Re-sign All' to refresh it.")
                    } else {
                        // Active state: Days remaining
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

                        // Live signature integrity badge
                        if let sig = signatureStatus {
                            HStack(spacing: 4) {
                                Image(systemName: sig.isValidOnDisk ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(sig.isValidOnDisk ? Color.green : Color.red)

                                Text(sig.isAdHoc ? "Ad-hoc" : (sig.isValidOnDisk ? "Verified" : "Corrupt"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(sig.isValidOnDisk ? Color.secondary : Color.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((sig.isValidOnDisk ? Color.secondary : Color.red).opacity(0.08))
                            .clipShape(Capsule())
                            .help(sig.statusMessage)
                        }
                    }
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
            return "Certificate Expired"
        }
    }
}
