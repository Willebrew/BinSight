import SwiftUI

struct RootTabView: View {
    var body: some View {
        // iOS 26 TabView renders the bottom bar in Liquid Glass automatically
        // and supports swipe-between-tabs (the user can drag).
        TabView {
            Tab("Dashboard", systemImage: "chart.bar.fill") {
                DashboardView()
            }
            Tab("Camera", systemImage: "camera.fill") {
                CameraScreen()
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
