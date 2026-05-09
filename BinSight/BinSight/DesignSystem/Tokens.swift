import SwiftUI

enum BinSightTokens {
    enum Color {
        static let recycle = SwiftUI.Color(red: 0.35, green: 0.78, blue: 0.12)
        static let recycleDark = SwiftUI.Color(red: 0.28, green: 0.62, blue: 0.08)
        static let trash = SwiftUI.Color(red: 1.00, green: 0.30, blue: 0.31)
        static let compost = SwiftUI.Color(red: 0.72, green: 0.50, blue: 0.17)
        static let hazard = SwiftUI.Color(red: 1.00, green: 0.63, blue: 0.05)
        static let accent = SwiftUI.Color(red: 0.12, green: 0.63, blue: 0.95)
        static let accentDark = SwiftUI.Color(red: 0.06, green: 0.46, blue: 0.78)
        static let xp = SwiftUI.Color(red: 1.00, green: 0.80, blue: 0.05)
        static let ink = SwiftUI.Color(red: 0.28, green: 0.28, blue: 0.30)
        static let softInk = SwiftUI.Color(red: 0.40, green: 0.42, blue: 0.46)
        static let cream = SwiftUI.Color(red: 0.98, green: 1.00, blue: 0.94)
        static let sky = SwiftUI.Color(red: 0.88, green: 0.96, blue: 1.00)
        static let mint = SwiftUI.Color(red: 0.90, green: 0.98, blue: 0.82)
        static let card = SwiftUI.Color.white
        static let stroke = SwiftUI.Color(red: 0.88, green: 0.90, blue: 0.86)
    }

    enum Radius {
        static let card: CGFloat = 22
        static let compact: CGFloat = 16
        static let pill: CGFloat = 999
    }

    enum Shadow {
        static let raised = SwiftUI.Color.black.opacity(0.10)
        static let bright = SwiftUI.Color(red: 0.28, green: 0.62, blue: 0.08).opacity(0.22)
    }

    enum Motion {
        static let snap: SwiftUI.Animation = .interactiveSpring(response: 0.32, dampingFraction: 0.78)
        static let lift: SwiftUI.Animation = .smooth(duration: 0.45)
        static let bounce: SwiftUI.Animation = .spring(response: 0.34, dampingFraction: 0.62)
    }
}
