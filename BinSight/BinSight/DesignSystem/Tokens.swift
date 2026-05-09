import SwiftUI

enum BinSightTokens {
    enum Color {
        static let recycle = SwiftUI.Color(red: 0.20, green: 0.74, blue: 0.49)
        static let trash   = SwiftUI.Color(red: 0.86, green: 0.36, blue: 0.30)
        static let compost = SwiftUI.Color(red: 0.61, green: 0.46, blue: 0.18)
        static let hazard  = SwiftUI.Color(red: 0.95, green: 0.62, blue: 0.16)
        static let accent  = SwiftUI.Color(red: 0.13, green: 0.55, blue: 0.95)
    }

    enum Radius {
        static let card: CGFloat = 24
        static let pill: CGFloat = 22
    }

    enum Motion {
        static let snap: SwiftUI.Animation = .interactiveSpring(response: 0.32, dampingFraction: 0.78)
        static let lift: SwiftUI.Animation = .smooth(duration: 0.45)
    }
}
