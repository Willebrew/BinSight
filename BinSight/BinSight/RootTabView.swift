import SwiftUI

enum RootTab: Hashable { case dashboard, camera, map, settings }

struct RootTabView: View {
    @State private var selection: RootTab = .camera

    var body: some View {
        GlassRoot {
            ZStack(alignment: .bottom) {
                Group {
                    switch selection {
                    case .dashboard: DashboardView()
                    case .camera:    CameraScreen()
                    case .map:       ImpactMapView()
                    case .settings:  SettingsView()
                    }
                }
                .ignoresSafeArea(edges: edgesToIgnore)

                TabBar(selection: $selection)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
    }

    private var edgesToIgnore: Edge.Set {
        switch selection {
        case .camera, .map: return .all
        default:            return []
        }
    }
}

private struct TabBar: View {
    @Binding var selection: RootTab
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 2) {
            tabButton(.dashboard, system: "chart.bar.fill",        label: "Dashboard")
            tabButton(.camera,    system: "camera.fill",           label: "Camera")
            tabButton(.map,       system: "map.fill",              label: "Map")
            tabButton(.settings,  system: "gearshape.fill",        label: "Settings")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassSurface(Capsule(), variant: .regular)
    }

    @ViewBuilder
    private func tabButton(_ tab: RootTab, system: String, label: String) -> some View {
        let isActive = selection == tab
        Button {
            withAnimation(BinSightTokens.Motion.snap) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: system)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? .white : .primary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(alignment: .center) {
                if isActive {
                    Capsule()
                        .fill(BinSightTokens.Color.accent)
                        .matchedGeometryEffect(id: "tab-pill", in: pillNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
