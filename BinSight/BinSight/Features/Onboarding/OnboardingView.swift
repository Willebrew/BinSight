import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var index = 0

    private let pages: [Page] = [
        .init(
            symbol: "camera.viewfinder",
            tint: BinSightTokens.Color.accent,
            title: "Snap any waste",
            body: "Trash, recyclables, food scraps — point your camera and tap to capture."
        ),
        .init(
            symbol: "sparkles",
            tint: BinSightTokens.Color.recycle,
            title: "AI sorts it for you",
            body: "BinSight identifies the material, checks the rules in your city, and tells you exactly where it goes."
        ),
        .init(
            symbol: "chart.line.uptrend.xyaxis",
            tint: BinSightTokens.Color.compost,
            title: "Track your impact",
            body: "Build streaks, save CO₂, and watch your community's recycling map grow with every scan."
        ),
    ]

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(pages.indices, id: \.self) { i in
                        OnboardingPage(page: pages[i])
                            .tag(i)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                pageDots
                    .padding(.bottom, 24)
                action
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.16, blue: 0.16),
                Color(red: 0.06, green: 0.34, blue: 0.32),
                Color(red: 0.13, green: 0.55, blue: 0.45),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? .white : .white.opacity(0.3))
                    .frame(width: i == index ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: index)
            }
        }
    }

    private var action: some View {
        Button {
            if index < pages.count - 1 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { index += 1 }
            } else {
                onFinish()
            }
        } label: {
            Text(index < pages.count - 1 ? "Next" : "Start scanning")
                .font(.headline)
                .foregroundStyle(BinSightTokens.Color.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: Capsule())
        }
    }

    struct Page {
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }
}

private struct OnboardingPage: View {
    let page: OnboardingView.Page
    @State private var appear = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 88, weight: .light))
                .foregroundStyle(.white)
                .padding(40)
                .background {
                    Circle()
                        .fill(page.tint.opacity(0.35))
                        .blur(radius: 20)
                }
                .scaleEffect(appear ? 1 : 0.8)
                .opacity(appear ? 1 : 0)
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text(page.body)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            Spacer(); Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) { appear = true }
        }
    }
}
