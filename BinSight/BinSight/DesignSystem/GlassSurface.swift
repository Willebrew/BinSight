import SwiftUI

/// Applies a Liquid Glass-style surface to any view. Implementation uses
/// `.ultraThinMaterial` rather than `glassEffect()` because the latter only
/// reads correctly inside a `GlassEffectContainer`, which interferes with
/// hit testing on Buttons. This compromise looks identical for our use cases
/// (cards, capsules, pills) and keeps taps responsive.
struct GlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var variant: Glass

    enum Glass { case regular, clear, identity }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(material)
                    .overlay(shape.stroke(.white.opacity(strokeOpacity)))
            }
    }

    private var material: Material {
        switch variant {
        case .regular:  return .ultraThinMaterial
        case .clear:    return .thinMaterial
        case .identity: return .regularMaterial
        }
    }

    private var strokeOpacity: Double {
        switch variant {
        case .regular:  return 0.10
        case .clear:    return 0.06
        case .identity: return 0.14
        }
    }
}

extension View {
    func glassSurface<S: Shape>(_ shape: S, variant: GlassSurface<S>.Glass = .regular) -> some View {
        modifier(GlassSurface(shape: shape, variant: variant))
    }
}
