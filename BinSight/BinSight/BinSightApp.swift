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
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.16, blue: 0.16),
                    Color(red: 0.06, green: 0.34, blue: 0.32),
                ],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(BinSightTokens.Color.recycle)
                ProgressView().tint(.white.opacity(0.7))
            }
        }
    }
}
