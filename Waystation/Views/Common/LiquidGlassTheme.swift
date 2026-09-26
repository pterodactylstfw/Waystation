import SwiftUI

// MARK: - Liquid Glass Design System
// macOS 26+: Uses Apple's native Glass and .glassEffect() API
// macOS 14-15: Falls back to frosted material simulation with specular highlights

// MARK: - Glass Intensity

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

// MARK: - Unified Glass Modifier

/// Applies native Apple Liquid Glass on macOS 26+ via `.glassEffect()`,
/// falling back to a frosted material simulation on older systems.
public struct LiquidGlassModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let intensity: LiquidGlassIntensity
    public let tintColor: Color?
    public let isInteractive: Bool

    public init(
        cornerRadius: CGFloat = 16,
        intensity: LiquidGlassIntensity = .standard,
        tintColor: Color? = nil,
        isInteractive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.intensity = intensity
        self.tintColor = tintColor
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .modifier(NativeGlassModifier(
                    cornerRadius: cornerRadius,
                    intensity: intensity,
                    tintColor: tintColor,
                    isInteractive: isInteractive
                ))
        } else {
            content
                .modifier(FallbackGlassModifier(
                    cornerRadius: cornerRadius,
                    intensity: intensity,
                    tintColor: tintColor
                ))
        }
    }
}

// MARK: - Native macOS 26+ Liquid Glass

@available(macOS 26, *)
private struct NativeGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let intensity: LiquidGlassIntensity
    let tintColor: Color?
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedGlass: Glass = {
            var glass: Glass = {
                switch intensity {
                case .subtle:
                    return .clear
                case .standard, .prominent:
                    return .regular
                case .interactive:
                    return .regular.interactive()
                }
            }()

            if let tint = tintColor {
                glass = glass.tint(tint)
            }
            if isInteractive && intensity != .interactive {
                glass = glass.interactive()
            }
            return glass
        }()

        return content
            .glassEffect(resolvedGlass, in: shape)
    }
}

// MARK: - Fallback Glass (macOS 14-15)

private struct FallbackGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let intensity: LiquidGlassIntensity
    let tintColor: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(intensity.blurMaterial)

                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    }

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

// MARK: - Glass Container

/// A container that synchronizes liquid glass refraction across child elements on macOS 26+.
/// Uses `GlassEffectContainer` on macOS 26+, or `HStack` on earlier versions.
public struct LiquidGlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Ambient Background

/// Provides subtle chromatic depth behind glass elements.
/// On macOS 26+, kept clean as native `.glassEffect()` handles real optical refraction.
/// On macOS 14-15, provides simulated chromatic orbs that illuminate through frosted materials.
public struct LiquidAmbientBackground: View {
    public init() {}

    public var body: some View {
        if #available(macOS 26, *) {
            // Native glass handles its own refraction with real optical caustic shaders
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        } else {
            // Simulated chromatic orbs for pre-macOS 26
            ZStack {
                Color(nsColor: .windowBackgroundColor)

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
}

// MARK: - View Extension

public extension View {
    /// Applies Liquid Glass styling.
    ///
    /// On macOS 26+, uses Apple's native `.glassEffect()` with real refraction, lensing, and caustics.
    /// On macOS 14-15, falls back to a frosted material simulation with specular highlights.
    ///
    /// - Parameters:
    ///   - cornerRadius: Corner radius of the glass shape.
    ///   - intensity: Visual intensity (`.subtle`, `.standard`, `.prominent`, `.interactive`).
    ///   - tintColor: Optional tint applied to the glass surface.
    ///   - isInteractive: Whether the glass responds to hover/press (macOS 26+ only).
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        intensity: LiquidGlassIntensity = .standard,
        tintColor: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            intensity: intensity,
            tintColor: tintColor,
            isInteractive: isInteractive
        ))
    }
}
