import SwiftUI

/// Wraps content in a single Liquid Glass container so multiple floating glass
/// elements blend correctly. Provides a shared `Namespace` via the environment
/// so morph transitions can pair across views with `.glassEffectID(_, in:)`.
struct GlassRoot<Content: View>: View {
    @Namespace private var glassNamespace
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer {
            content()
        }
        .environment(\.glassNamespace, glassNamespace)
    }
}

private struct GlassNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var glassNamespace: Namespace.ID? {
        get { self[GlassNamespaceKey.self] }
        set { self[GlassNamespaceKey.self] = newValue }
    }
}
