import SwiftUI

@main
struct BinSightApp: App {
    @StateObject private var convex = ConvexService.shared
    @AppStorage("binsight.onboardingDone") private var onboardingDone = false

    var body: some Scene {
        WindowGroup {
            content
                .environmentObject(convex)
                .task { await convex.bootstrap() }
                .preferredColorScheme(.light)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !onboardingDone {
            OnboardingView(onFinish: { onboardingDone = true })
        } else {
            switch convex.authState {
            case .unknown:
                LoadingScreen()
            case .signedOut, .signingIn:
                SignInView()
            case .signedIn:
                RootTabView()
            }
        }
    }
}

private struct LoadingScreen: View {
    var body: some View {
        ZStack {
            DuoBackdrop().ignoresSafeArea()
            VStack(spacing: 14) {
                MascotArtView(mood: .happy, size: 112, accessory: "leaf.fill")
                ProgressView().tint(BinSightTokens.Color.recycle)
            }
        }
    }
}
