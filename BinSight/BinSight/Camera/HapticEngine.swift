import UIKit
import SwiftUI
import CoreHaptics

/// Drop-in tap haptic for any view. Fires a soft click on tap-up
/// without consuming the gesture, so existing Button actions still
/// run and existing styles still render.
extension View {
    func tapHaptic() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { HapticEngine.tap() }
        )
    }
}

/// Centralized haptics. Simple UIKit generators handle quick taps;
/// CoreHaptics drives the richer "thinking pulse" loop and the
/// per-item / completion swells used by the streaming scan flow.
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
    /// Light selection-style click for taps on buttons / tab items.
    static func tap()     {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred(intensity: 0.85)
    }
    /// Selection-change tick — the lightest standard haptic on iOS.
    /// Used for the agent-progress feed so each line whispers under
    /// the bigger item-reveal punches.
    private static let selection: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator(); g.prepare(); return g
    }()
    static func whisper() {
        selection.selectionChanged()
        selection.prepare()
    }
    static func captured(){ shutter.impactOccurred() }
    static func ok()      { success.notificationOccurred(.success) }
    static func failed()  { success.notificationOccurred(.error) }

    // MARK: - CoreHaptics streaming feel

    static func startThinking() { CHEngine.shared.startThinking() }

    /// Fire a click haptic and run the action. Wrap any Button's
    /// closure with this to opt in: `Button { HapticEngine.run { ... } } label:`.
    static func run(_ action: () -> Void) { tap(); action() }
    static func stopThinking()  { CHEngine.shared.stopThinking() }
    static func itemRevealed(decision: String) { CHEngine.shared.itemRevealed(decision: decision) }
    static func scanComplete()  { CHEngine.shared.scanComplete() }
}

/// Wraps a single shared `CHHapticEngine`. We keep one engine alive
/// for the lifetime of the app so playback latency stays under the
/// perceptual threshold (~30ms).
private final class CHEngine {
    static let shared = CHEngine()

    private var engine: CHHapticEngine?
    private var thinkingPlayer: CHHapticAdvancedPatternPlayer?
    private let supports = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {
        guard supports else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak self] in
                try? self?.engine?.start()
                self?.thinkingPlayer = nil
            }
            e.stoppedHandler = { _ in /* will lazily restart */ }
            try e.start()
            self.engine = e
        } catch {
            self.engine = nil
        }
    }

    private func ensureRunning() -> CHHapticEngine? {
        guard let e = engine else { return nil }
        do { try e.start() } catch { /* already running */ }
        return e
    }

    /// Loop a soft, breathing tap pattern. Feels like the device is
    /// "thinking" in the user's hand.
    func startThinking() {
        guard supports, let e = ensureRunning() else { return }
        if thinkingPlayer != nil { return }
        do {
            // 480ms loop: bold heartbeat (double-tap) + a continuous
            // swelling purr. Punchy enough to feel through a case.
            let beat1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 0.7),
                ],
                relativeTime: 0
            )
            let beat2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.85),
                    .init(parameterID: .hapticSharpness, value: 0.6),
                ],
                relativeTime: 0.10
            )
            let purr = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.7),
                    .init(parameterID: .hapticSharpness, value: 0.35),
                ],
                relativeTime: 0.18,
                duration: 0.26
            )
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.18, value: 0.4),
                    .init(relativeTime: 0.30, value: 0.9),
                    .init(relativeTime: 0.44, value: 0.1),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(
                events: [beat1, beat2, purr],
                parameterCurves: [intensityCurve]
            )
            let player = try e.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = 0.48
            try player.start(atTime: CHHapticTimeImmediate)
            thinkingPlayer = player
        } catch {
            thinkingPlayer = nil
        }
    }

    func stopThinking() {
        guard let p = thinkingPlayer else { return }
        try? p.stop(atTime: CHHapticTimeImmediate)
        thinkingPlayer = nil
    }

    /// Strong "an item just landed" tap. Layered: a heavy UIKit impact
    /// fires immediately (always reliable, perceptibly strong even
    /// through a case) while CoreHaptics adds a sharp transient + a
    /// short bass thud that flavors the feel by decision. Also briefly
    /// dips the thinking pulse so the reveal punches through.
    func itemRevealed(decision: String) {
        // Briefly silence the thinking-loop player so the reveal lands
        // on top of silence rather than competing with the purr.
        if let p = thinkingPlayer {
            try? p.sendParameters(
                [.init(parameterID: .hapticIntensityControl, value: 0.0, relativeTime: 0)],
                atTime: CHHapticTimeImmediate
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                try? p.sendParameters(
                    [.init(parameterID: .hapticIntensityControl, value: 1.0, relativeTime: 0)],
                    atTime: CHHapticTimeImmediate
                )
            }
        }

        // Heavy UIKit impact: most reliable strong tap on every device.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)

        guard supports, let e = ensureRunning() else { return }

        let (sharpness, extraPops): (Float, Int) = {
            switch decision {
            case "hazard":  return (0.95, 2)   // three sharp taps, alarm-ish
            case "recycle": return (0.70, 1)   // bright double-tap
            case "compost": return (0.55, 1)   // softer double-tap
            default:        return (0.45, 0)   // single thud
            }
        }()
        do {
            var events: [CHHapticEvent] = []
            // Bass-y body: short continuous thud that gives weight.
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 0.30),
                    .init(parameterID: .attackTime, value: 0.0),
                    .init(parameterID: .decayTime, value: 0.06),
                    .init(parameterID: .sustained, value: 0),
                ],
                relativeTime: 0,
                duration: 0.12
            ))
            // Crisp top-end transient on top of the thud.
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            ))
            // Decision-specific echoes.
            if extraPops > 0 {
                for i in 1...extraPops {
                    events.append(CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            .init(parameterID: .hapticIntensity, value: 0.85),
                            .init(parameterID: .hapticSharpness, value: sharpness),
                        ],
                        relativeTime: 0.10 * Double(i)
                    ))
                }
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try e.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // UIKit fallback already fired above.
        }
    }

    /// Celebratory swell when classification finishes successfully.
    /// A rising continuous note capped by two bright transients.
    func scanComplete() {
        guard supports, let e = ensureRunning() else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        do {
            let swell = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.7),
                    .init(parameterID: .hapticSharpness, value: 0.4),
                ],
                relativeTime: 0,
                duration: 0.35
            )
            let intensityRise = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.00, value: 0.10),
                    .init(relativeTime: 0.25, value: 0.85),
                    .init(relativeTime: 0.35, value: 0.05),
                ],
                relativeTime: 0
            )
            let pop1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.95),
                    .init(parameterID: .hapticSharpness, value: 0.85),
                ],
                relativeTime: 0.32
            )
            let pop2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.7),
                    .init(parameterID: .hapticSharpness, value: 0.6),
                ],
                relativeTime: 0.45
            )
            let pattern = try CHHapticPattern(
                events: [swell, pop1, pop2],
                parameterCurves: [intensityRise]
            )
            let player = try e.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
