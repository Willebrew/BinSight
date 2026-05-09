import SwiftUI

/// A glass-effect surface that gracefully falls back to an opaque material
/// when Reduce Transparency is enabled. Use for floating cards / pills /
/// circular controls.
struct GlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var variant: Glass

    enum Glass { case regular, clear, identity }

    func body(content: Content) -> some View {
        ContentWrapper(content: content, shape: shape, variant: variant)
    }

    private struct ContentWrapper: View {
        let content: Content
        let shape: S
        let variant: Glass
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            if reduceTransparency {
                content
                    .background(.thinMaterial, in: shape)
                    .overlay(shape.stroke(.white.opacity(0.08)))
            } else {
                switch variant {
                case .regular:  content.glassEffect(.regular, in: shape)
                case .clear:    content.glassEffect(.clear, in: shape)
                case .identity: content.glassEffect(.identity, in: shape)
                }
            }
        }
    }
}

extension View {
    func glassSurface<S: Shape>(_ shape: S, variant: GlassSurface<S>.Glass = .regular) -> some View {
        modifier(GlassSurface(shape: shape, variant: variant))
    }
}
