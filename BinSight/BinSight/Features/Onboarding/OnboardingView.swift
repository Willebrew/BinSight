import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var index = 0

    private let pages: [Page] = [
        .init(
            mood: .happy,
            accessory: "camera.fill",
            tint: BinSightTokens.Color.accent,
            title: "Meet your waste coach",
            body: "Snap a photo and BinSight turns sorting into a tiny lesson."
        ),
        .init(
            mood: .thinking,
            accessory: "sparkles",
            tint: BinSightTokens.Color.recycle,
            title: "Learn where it goes",
            body: "Get local rules, sources, and a clear recycle, compost, trash, or hazard call."
        ),
        .init(
            mood: .celebrate,
            accessory: "flame.fill",
            tint: BinSightTokens.Color.xp,
            title: "Build your impact streak",
            body: "Confirm scans, earn progress, and compare your city league with friends."
        ),
    ]

    var body: some View {
        ZStack {
            DuoBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("BinSight")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(BinSightTokens.Color.ink)
                    Spacer()
                    DuoBadge(text: "\(index + 1)/\(pages.count)", systemImage: "leaf.fill", color: BinSightTokens.Color.recycle)
                }
                .padding(.horizontal, 24)
                .padding(.top, 58)

                TabView(selection: $index) {
                    ForEach(pages.indices, id: \.self) { i in
                        OnboardingPage(page: pages[i])
                            .tag(i)
                            .padding(.horizontal, 24)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                pageDots
                    .padding(.bottom, 22)

                Button {
                    if index < pages.count - 1 {
                        withAnimation(BinSightTokens.Motion.bounce) { index += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Label(index < pages.count - 1 ? "Continue" : "Start Scanning",
                          systemImage: index < pages.count - 1 ? "arrow.right" : "camera.fill")
                }
                .buttonStyle(DuoButtonStyle(kind: .primary))
                .padding(.horizontal, 28)
                .padding(.bottom, 42)
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? BinSightTokens.Color.recycle : BinSightTokens.Color.stroke)
                    .frame(width: i == index ? 28 : 10, height: 10)
                    .animation(BinSightTokens.Motion.bounce, value: index)
            }
        }
    }

    struct Page {
        let mood: MascotArtView.Mood
        let accessory: String
        let tint: Color
        let title: String
        let body: String
    }
}

private struct OnboardingPage: View {
    let page: OnboardingView.Page
    @State private var appear = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.22))
                    .frame(width: 244, height: 244)
                    .offset(y: 18)
                MascotArtView(mood: page.mood, size: 178, accessory: page.accessory)
                    .scaleEffect(appear ? 1 : 0.82)
            }
            .frame(height: 275)

            DuoCard(fill: .white, stroke: BinSightTokens.Color.stroke, radius: 26, padding: 22) {
                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(BinSightTokens.Color.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                    Text(page.body)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 18)

            Spacer(minLength: 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.05)) {
                appear = true
            }
        }
    }
}
