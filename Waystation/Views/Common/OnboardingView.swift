import SwiftUI

/// First-launch onboarding tour introducing Waystation's workflow.
/// Uses a multi-step card carousel with Liquid Glass aesthetics.
/// Appears only once (persisted via UserDefaults).
@MainActor
public struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Int = 0

    private static let hasSeenOnboardingKey = "waystation_has_seen_onboarding"

    /// Whether the onboarding should be presented.
    public static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: hasSeenOnboardingKey)
    }

    /// Marks onboarding as completed so it won't show again.
    public static func markCompleted() {
        UserDefaults.standard.set(true, forKey: hasSeenOnboardingKey)
    }

    /// Resets the onboarding flag (for testing / settings).
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: hasSeenOnboardingKey)
    }

    public init() {}

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "safari.fill",
            iconGradient: [.blue, .cyan],
            title: "Welcome to Waystation",
            subtitle: "Run Chrome Web Store Extensions in Safari",
            description: "Waystation automates the entire process of converting, signing, and installing Chrome extensions for Safari — no terminal commands, no Xcode required.",
            tips: [
                StepTip(icon: "shield.checkered", text: "100% local — your data never leaves your Mac"),
                StepTip(icon: "arrow.down.doc.fill", text: "Direct downloads from Google's official CDN"),
                StepTip(icon: "checkmark.seal.fill", text: "Automatic code-signing with your Apple certificate")
            ]
        ),
        OnboardingStep(
            icon: "wrench.and.screwdriver.fill",
            iconGradient: [.orange, .yellow],
            title: "One-Time Setup",
            subtitle: "Two quick prerequisites before you begin",
            description: "Waystation needs Xcode Command Line Tools and Safari's Developer Mode enabled. The app will check these automatically and guide you if anything is missing.",
            tips: [
                StepTip(icon: "terminal.fill", text: "Xcode CLT — install via: xcode-select --install"),
                StepTip(icon: "gearshape.2.fill", text: "Safari → Settings → Advanced → \"Show features for web developers\""),
                StepTip(icon: "lock.open.fill", text: "Safari → Develop → \"Allow Unsigned Extensions\"")
            ]
        ),
        OnboardingStep(
            icon: "bag.fill",
            iconGradient: [.purple, .pink],
            title: "Browse & Install",
            subtitle: "The Store tab — your extension shop",
            description: "Browse the Chrome Web Store directly inside Waystation. When you find an extension you like, click the native \"Add to Safari\" button — Waystation handles the rest automatically.",
            tips: [
                StepTip(icon: "plus.circle.fill", text: "Click \"Add to Safari\" on any extension page"),
                StepTip(icon: "arrow.down.circle.fill", text: "CRX download + conversion + signing — fully automated"),
                StepTip(icon: "checkmark.circle.fill", text: "Green badge shows extensions already in your Library")
            ]
        ),
        OnboardingStep(
            icon: "arrow.down.doc.fill",
            iconGradient: [.teal, .green],
            title: "Drag & Drop",
            subtitle: "The Drop Zone — for files you already have",
            description: "Already downloaded an extension file? Drag and drop .crx, .zip, or unpacked extension folders directly onto the Drop Zone. Waystation validates, converts, and installs them.",
            tips: [
                StepTip(icon: "doc.zipper", text: "Accepts .crx, .zip, and unpacked folders"),
                StepTip(icon: "exclamationmark.triangle.fill", text: "Pre-flight check warns about unsupported Chrome APIs"),
                StepTip(icon: "folder.fill", text: "Or click \"Browse Files\" to pick from Finder")
            ]
        ),
        OnboardingStep(
            icon: "square.grid.2x2.fill",
            iconGradient: [.green, .mint],
            title: "Your Library",
            subtitle: "Manage all your Safari extensions",
            description: "The Library tab shows every installed extension with real-time signing status. Re-sign, uninstall, or launch Safari directly — all in one place.",
            tips: [
                StepTip(icon: "clock.badge.checkmark.fill", text: "Live countdown badges for certificate expiry"),
                StepTip(icon: "arrow.clockwise.circle.fill", text: "One-click \"Re-sign All\" to renew certificates"),
                StepTip(icon: "gearshape.arrow.triangle.2.circlepath", text: "Background daemon auto-renews before expiry")
            ]
        ),
        OnboardingStep(
            icon: "sparkles",
            iconGradient: [.blue, .purple],
            title: "You're All Set!",
            subtitle: "Start exploring the Chrome Web Store",
            description: "Head to the Store tab and install your first extension. If you ever need help, press ⌘/ or click the Help button in the toolbar.",
            tips: [
                StepTip(icon: "keyboard", text: "⌘W closes Safari windows — extensions stay active"),
                StepTip(icon: "questionmark.circle.fill", text: "Press ⌘/ anytime for the full help guide"),
                StepTip(icon: "heart.fill", text: "Enjoy your Chrome extensions in Safari!")
            ]
        ),
    ]

    public var body: some View {
        ZStack {
            LiquidAmbientBackground()

            VStack(spacing: 0) {
                // Step content
                stepContent(steps[currentStep])
                    .id(currentStep)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                Spacer(minLength: 16)

                // Progress dots + navigation
                bottomBar
            }
            .padding(32)
        }
        .frame(width: 620, height: 520)
        .background(.ultraThinMaterial)
    }

    // MARK: - Step Content

    private func stepContent(_ step: OnboardingStep) -> some View {
        VStack(spacing: 24) {
            // Icon hero
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [step.iconGradient.first!.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 110, height: 110)
                    .blur(radius: 8)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 88, height: 88)

                Image(systemName: step.icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: step.iconGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Title + subtitle
            VStack(spacing: 6) {
                Text(step.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(step.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text(step.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            // Tip rows
            VStack(spacing: 8) {
                ForEach(step.tips) { tip in
                    HStack(spacing: 12) {
                        Image(systemName: tip.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(step.iconGradient.first ?? .blue)
                            .frame(width: 22)

                        Text(tip.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.85))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 440)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Skip button (only on non-last steps)
            if currentStep < steps.count - 1 {
                Button("Skip Tour") {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                Spacer().frame(width: 60)
            }

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == currentStep ? 8 : 6, height: index == currentStep ? 8 : 6)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
            }

            Spacer()

            // Next / Get Started button
            if currentStep < steps.count - 1 {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentStep += 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    finishOnboarding()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Get Started")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 8)
    }

    private func finishOnboarding() {
        Self.markCompleted()
        dismiss()
    }
}

// MARK: - Data Models

private struct OnboardingStep {
    let icon: String
    let iconGradient: [Color]
    let title: String
    let subtitle: String
    let description: String
    let tips: [StepTip]
}

private struct StepTip: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}
