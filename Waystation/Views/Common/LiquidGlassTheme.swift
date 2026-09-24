import SwiftUI

// MARK: - Liquid Glass Design System (macOS 26/27)
/// Futuristic frosted glass materials, specular rim highlights, and ambient luminance.

public enum LiquidGlassIntensity: Sendable {
    case subtle
    case standard
    case prominent
    case interactive

    var blurMaterial: Material {
        switch self {
        case .subtle: return .thinMaterial
        case .standard: return .ultraThinMaterial
        case .prominent: return .regularMaterial
        case .interactive: return .ultraThinMaterial
        }
    }

    var borderOpacity: Double {
        switch self {
        case .subtle: return 0.12
        case .standard: return 0.20
        case .prominent: return 0.28
        case .interactive: return 0.22
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .subtle: return 6
        case .standard: return 12
        case .prominent: return 18
        case .interactive: return 10
        }
    }
}

public struct LiquidGlassModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let intensity: LiquidGlassIntensity
    public let tintColor: Color?

    public init(cornerRadius: CGFloat = 16, intensity: LiquidGlassIntensity = .standard, tintColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.intensity = intensity
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1. Frosted Material Layer
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(intensity.blurMaterial)

                    // 2. Optional Ambient Tint Glow
                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    }

                    // 3. Specular Light Glaze
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Dual-rim light refraction stroke
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(intensity.borderOpacity), location: 0.0),
                                .init(color: (tintColor ?? Color.white).opacity(intensity.borderOpacity * 0.5), location: 0.3),
                                .init(color: Color.clear, location: 0.7),
                                .init(color: Color.white.opacity(intensity.borderOpacity * 0.3), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.12), radius: intensity.shadowRadius, x: 0, y: 3)
    }
}

public struct LiquidAmbientBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            // Base window tint
            Color(nsColor: .windowBackgroundColor)

            // Deep chromatic orbs that subtly illuminate through the frosted glass
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.12), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.4
                            )
                        )
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.2)
                        .blur(radius: 50)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.purple.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.4
                            )
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.1)
                        .blur(radius: 60)
                }
            }
        }
        .ignoresSafeArea()
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        intensity: LiquidGlassIntensity = .standard,
        tintColor: Color? = nil
    ) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, intensity: intensity, tintColor: tintColor))
    }
}
