import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.bar.fill") {
                DashboardView()
            }
            Tab("Camera", systemImage: "camera.fill") {
                CameraScreen()
            }
            Tab("Friends", systemImage: "person.2.fill") {
                FriendsView()
            }
            Tab("Map", systemImage: "map.fill") {
                ImpactMapView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}
