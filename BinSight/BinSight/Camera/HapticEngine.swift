import UIKit

enum HapticEngine {
    static let scanTick: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light); g.prepare(); return g
    }()
    static let success: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator(); g.prepare(); return g
    }()
    static let shutter: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .heavy); g.prepare(); return g
    }()

    static func tick()    { scanTick.impactOccurred(intensity: 0.6) }
    static func captured(){ shutter.impactOccurred() }
    static func ok()      { success.notificationOccurred(.success) }
    static func failed()  { success.notificationOccurred(.error) }
}
