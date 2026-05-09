import SwiftUI

@main
struct BinSightApp: App {
    @StateObject private var convex = ConvexService.shared
    @AppStorage("binsight.onboardingDone") private var onboardingDone = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingDone {
                    OnboardingView(onFinish: { onboardingDone = true })
                } else {
                    RootTabView()
                }
            }
            .environmentObject(convex)
            .task { await convex.bootstrap() }
        }
    }
}
