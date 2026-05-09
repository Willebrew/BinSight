import SwiftUI

struct RootTabView: View {
    @State private var selected: AppTab = .dashboard
    @State private var captureRequests = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selected {
                case .dashboard:
                    DashboardView()
                case .camera:
                    CameraScreen(captureRequests: captureRequests)
                case .friends:
                    FriendsView()
                case .map:
                    ImpactMapView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DuoTabBar(selected: $selected, captureRequests: $captureRequests)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private enum AppTab: String, CaseIterable {
    case dashboard = "Home"
    case friends = "Friends"
    case camera = "Scan"
    case map = "League"
    case settings = "Profile"

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .friends: return "person.2.fill"
        case .camera: return "camera.viewfinder"
        case .map: return "trophy.fill"
        case .settings: return "person.crop.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .dashboard: return BinSightTokens.Color.recycle
        case .friends: return BinSightTokens.Color.accent
        case .camera: return BinSightTokens.Color.recycle
        case .map: return BinSightTokens.Color.xp
        case .settings: return Color(red: 0.64, green: 0.42, blue: 0.95)
        }
    }
}

private struct DuoTabBar: View {
    @Binding var selected: AppTab
    @Binding var captureRequests: Int

    var body: some View {
        HStack(spacing: 7) {
            tabButton(.dashboard)
            tabButton(.friends)
            scanButton
            tabButton(.map)
            tabButton(.settings)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.70))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.13), radius: 24, x: 0, y: 10)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(BinSightTokens.Motion.bounce) { selected = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(selected == tab ? tab.color : BinSightTokens.Color.softInk.opacity(0.75))
                    .frame(width: 46, height: 34)
                    .background {
                        if selected == tab {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(tab.color.opacity(0.14))
                        }
                    }
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected == tab ? tab.color : BinSightTokens.Color.softInk)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    private var scanButton: some View {
        Button {
            if selected == .camera {
                captureRequests += 1
            } else {
                withAnimation(BinSightTokens.Motion.bounce) { selected = .camera }
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(BinSightTokens.Color.recycleDark)
                        .frame(width: 64, height: 64)
                        .offset(y: selected == .camera ? 2 : 6)
                    Circle()
                        .fill(BinSightTokens.Color.recycle)
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                    Image(systemName: AppTab.camera.icon)
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .offset(y: -22)
                .shadow(color: BinSightTokens.Color.recycle.opacity(0.35), radius: 18, x: 0, y: 8)
                Text(AppTab.camera.rawValue)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(BinSightTokens.Color.recycle)
                    .offset(y: -18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected == .camera ? "Take photo" : "Scan")
    }
}
