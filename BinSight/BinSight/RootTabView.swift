import SwiftUI

enum RootTab: Hashable { case dashboard, camera, settings }

struct RootTabView: View {
    @State private var selection: RootTab = .camera

    var body: some View {
        GlassRoot {
            ZStack(alignment: .bottom) {
                Group {
                    switch selection {
                    case .dashboard: DashboardView()
                    case .camera:    CameraScreen()
                    case .settings:  SettingsView()
                    }
                }
                .ignoresSafeArea(edges: selection == .camera ? .all : [])

                TabBar(selection: $selection)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct TabBar: View {
    @Binding var selection: RootTab
    @Environment(\.glassNamespace) private var namespace

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.dashboard, system: "chart.bar.fill", label: "Dashboard")
            tabButton(.camera,    system: "camera.fill",    label: "Camera")
            tabButton(.settings,  system: "gearshape.fill", label: "Settings")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassSurface(Capsule(), variant: .regular)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private func tabButton(_ tab: RootTab, system: String, label: String) -> some View {
        Button {
            withAnimation(BinSightTokens.Motion.snap) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selection == tab ? .white : .primary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(alignment: .center) {
                if selection == tab {
                    Capsule()
                        .fill(BinSightTokens.Color.accent)
                        .matchedGeometryEffect(id: "tab-pill", in: namespaceOrFallback)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @Namespace private var fallbackNamespace
    private var namespaceOrFallback: Namespace.ID { namespace ?? fallbackNamespace }
}
