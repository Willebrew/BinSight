import SwiftUI

enum DuoButtonKind {
    case primary, secondary, destructive, neutral

    var fill: Color {
        switch self {
        case .primary: return BinSightTokens.Color.recycle
        case .secondary: return BinSightTokens.Color.accent
        case .destructive: return BinSightTokens.Color.trash
        case .neutral: return .white
        }
    }

    var shadow: Color {
        switch self {
        case .primary: return BinSightTokens.Color.recycleDark
        case .secondary: return BinSightTokens.Color.accentDark
        case .destructive: return Color(red: 0.72, green: 0.12, blue: 0.14)
        case .neutral: return BinSightTokens.Color.stroke
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: return BinSightTokens.Color.accent
        default: return .white
        }
    }
}

struct DuoButtonStyle: ButtonStyle {
    var kind: DuoButtonKind = .primary
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.heavy))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(kind.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 10 : 15)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: isCompact ? 14 : 18, style: .continuous)
                    .fill(kind.shadow)
                    .offset(y: configuration.isPressed ? 1 : 5)
                RoundedRectangle(cornerRadius: isCompact ? 14 : 18, style: .continuous)
                    .fill(kind.fill)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: isCompact ? 14 : 18, style: .continuous)
                            .stroke(.white.opacity(kind == .neutral ? 0.9 : 0.25), lineWidth: 1.5)
                    }
            }
            .offset(y: configuration.isPressed ? 4 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct DuoCard<Content: View>: View {
    var fill: Color = BinSightTokens.Color.card
    var stroke: Color = BinSightTokens.Color.stroke
    var radius: CGFloat = BinSightTokens.Radius.card
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .shadow(color: .black.opacity(0.055), radius: 0, x: 0, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 2)
            }
    }
}

struct DuoGlassCard<Content: View>: View {
    var tint: Color = .white
    var radius: CGFloat = BinSightTokens.Radius.card
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.62), tint.opacity(0.18), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.78), lineWidth: 1.5)
            }
    }
}

struct DuoSectionHeader: View {
    let title: String
    var action: String?
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(BinSightTokens.Color.recycle)
            }
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Spacer()
            if let action {
                Text(action)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(BinSightTokens.Color.accent)
                    .tracking(0.8)
            }
        }
    }
}

struct DuoBadge: View {
    let text: String
    var systemImage: String?
    var color: Color = BinSightTokens.Color.recycle
    var filled = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(.system(.caption, design: .rounded).weight(.heavy))
        .foregroundStyle(filled ? .white : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(filled ? color : color.opacity(0.14), in: Capsule())
    }
}

struct DuoProgressBar: View {
    var value: Double
    var total: Double = 1
    var color: Color = BinSightTokens.Color.recycle
    var height: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.72), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1, max(0, value / max(total, 0.001))))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .frame(height: height * 0.36)
                            .padding(.horizontal, 5)
                    }
            }
        }
        .frame(height: height)
    }
}

struct DuoStatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color

    var body: some View {
        DuoCard(radius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
                    .lineLimit(1)
            }
        }
    }
}

struct DuoAvatar: View {
    let seed: String
    var size: CGFloat = 46

    var body: some View {
        let initial = String(seed.prefix(1)).uppercased()
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
                .fill(avatarColor(for: seed))
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.28))
                        .frame(width: size * 0.28)
                        .padding(size * 0.14)
                }
            Text(initial.isEmpty ? "B" : initial)
                .font(.system(size: size * 0.40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.10), radius: 0, x: 0, y: 3)
    }

    private func avatarColor(for seed: String) -> Color {
        let hash = abs(seed.utf8.reduce(0) { $0 + Int($1) })
        let presets: [Color] = [
            BinSightTokens.Color.recycle,
            BinSightTokens.Color.accent,
            Color(red: 0.63, green: 0.40, blue: 0.95),
            BinSightTokens.Color.hazard,
            Color(red: 0.98, green: 0.42, blue: 0.68),
            Color(red: 0.12, green: 0.72, blue: 0.72),
        ]
        return presets[hash % presets.count]
    }
}

struct MascotArtView: View {
    var mood: Mood = .happy
    var size: CGFloat = 120
    var accessory: String? = nil

    enum Mood { case happy, thinking, celebrate, sleepy }

    var body: some View {
        ZStack {
            BlobShape()
                .fill(
                    LinearGradient(
                        colors: [BinSightTokens.Color.recycle, BinSightTokens.Color.recycleDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(BlobShape().stroke(.white.opacity(0.55), lineWidth: size * 0.028))
                .shadow(color: BinSightTokens.Shadow.bright, radius: size * 0.10, x: 0, y: size * 0.08)

            face

            if let accessory {
                Image(systemName: accessory)
                    .font(.system(size: size * 0.20, weight: .heavy))
                    .foregroundStyle(BinSightTokens.Color.xp)
                    .padding(size * 0.09)
                    .background(.white, in: Circle())
                    .offset(x: size * 0.32, y: -size * 0.35)
                    .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var face: some View {
        ZStack {
            HStack(spacing: size * 0.11) {
                eye
                eye
            }
            .offset(y: -size * 0.05)

            mouth
                .stroke(Color(red: 0.18, green: 0.34, blue: 0.14), style: StrokeStyle(lineWidth: size * 0.038, lineCap: .round))
                .frame(width: size * 0.28, height: size * 0.16)
                .offset(y: size * 0.18)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(.white.opacity(0.24))
                .frame(width: size * 0.18, height: size * 0.06)
                .rotationEffect(.degrees(-18))
                .offset(x: -size * 0.23, y: -size * 0.27)
        }
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white).frame(width: size * 0.22, height: size * 0.25)
            Circle().fill(Color(red: 0.14, green: 0.22, blue: 0.12)).frame(width: size * 0.10, height: size * 0.12)
                .offset(x: mood == .thinking ? size * 0.025 : 0)
            Circle().fill(.white).frame(width: size * 0.035, height: size * 0.035)
                .offset(x: -size * 0.025, y: -size * 0.035)
        }
    }

    private var mouth: Path {
        var path = Path()
        switch mood {
        case .happy, .celebrate:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: size * 0.28, y: 0), control: CGPoint(x: size * 0.14, y: size * 0.16))
        case .thinking:
            path.move(to: CGPoint(x: 0, y: size * 0.07))
            path.addLine(to: CGPoint(x: size * 0.22, y: size * 0.03))
        case .sleepy:
            path.move(to: CGPoint(x: 0, y: size * 0.05))
            path.addQuadCurve(to: CGPoint(x: size * 0.24, y: size * 0.05), control: CGPoint(x: size * 0.12, y: -size * 0.03))
        }
        return path
    }
}

private struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04))
        p.addCurve(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.midY),
                   control1: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.20))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.02),
                   control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.10),
                   control2: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY),
                   control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.22))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04),
                   control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16),
                   control2: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY))
        return p
    }
}

struct DuoBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                BinSightTokens.Color.sky,
                BinSightTokens.Color.cream,
                BinSightTokens.Color.mint.opacity(0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(BinSightTokens.Color.xp.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: 70, y: -80)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(BinSightTokens.Color.accent.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 30)
                .offset(x: -95, y: 80)
        }
    }
}

extension View {
    func duoScreenBackground() -> some View {
        background(DuoBackdrop().ignoresSafeArea())
    }
}

func duoDecisionColor(_ decision: String) -> Color {
    switch decision {
    case "recycle": return BinSightTokens.Color.recycle
    case "compost": return BinSightTokens.Color.compost
    case "hazard": return BinSightTokens.Color.hazard
    default: return BinSightTokens.Color.trash
    }
}

func duoDecisionSymbol(_ decision: String) -> String {
    switch decision {
    case "recycle": return "arrow.3.trianglepath"
    case "compost": return "leaf.fill"
    case "hazard": return "exclamationmark.triangle.fill"
    default: return "trash.fill"
    }
}
