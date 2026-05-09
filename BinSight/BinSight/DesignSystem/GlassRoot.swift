import SwiftUI

/// Lightweight wrapper kept for callers that previously used `GlassRoot`.
/// We no longer use `GlassEffectContainer` here because it interfered with
/// hit testing on Buttons inside it. Each glass surface is now self-contained.
struct GlassRoot<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}
