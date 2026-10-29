import Foundation

public struct TriggeredGesture: Sendable, Equatable {
    public var action: GestureAction
    public var sourceName: String
    public var timestamp: TimeInterval

    public init(action: GestureAction, sourceName: String, timestamp: TimeInterval) {
        self.action = action
        self.sourceName = sourceName
        self.timestamp = timestamp
    }
}

/// Detects intentional head gestures (Roll tilts & linear acceleration impulses)
/// using hysteresis and refractory cooldowns to prevent double-triggering.
public struct GestureDetector: Sendable {
    public private(set) var isRollLeftLatched: Bool = false
    public private(set) var isRollRightLatched: Bool = false
    private var lastTriggerTimestamp: TimeInterval = -100.0

    public init() {}

    public mutating func reset() {
        isRollLeftLatched = false
        isRollRightLatched = false
        lastTriggerTimestamp = -100.0
    }

    public mutating func evaluate(
        sample: IMUSample,
        relativeAngles: HeadAngles,
        config: OrientConfiguration
    ) -> TriggeredGesture? {
        let roll = relativeAngles.rollDeg
        let releaseThreshold = min(config.rollTriggerAngleDeg * 0.75, config.rollReleaseAngleDeg)

        // Release hysteresis latches when head returns toward upright roll
        if isRollLeftLatched && roll > -releaseThreshold {
            isRollLeftLatched = false
        }
        if isRollRightLatched && roll < releaseThreshold {
            isRollRightLatched = false
        }

        let cooldownSec = config.gestureCooldownMs / 1000.0
        guard (sample.timestamp - lastTriggerTimestamp) >= cooldownSec else {
            return nil
        }

        // 1. Check Roll Left / Right tilt gestures
        if config.rollClickEnabled {
            if !isRollLeftLatched && roll <= -config.rollTriggerAngleDeg && config.rollLeftAction != .none {
                isRollLeftLatched = true
                lastTriggerTimestamp = sample.timestamp
                return TriggeredGesture(
                    action: config.rollLeftAction,
                    sourceName: String(format: "Roll Left (%.0f°)", roll),
                    timestamp: sample.timestamp
                )
            }

            if !isRollRightLatched && roll >= config.rollTriggerAngleDeg && config.rollRightAction != .none {
                isRollRightLatched = true
                lastTriggerTimestamp = sample.timestamp
                return TriggeredGesture(
                    action: config.rollRightAction,
                    sourceName: String(format: "Roll Right (+%.0f°)", roll),
                    timestamp: sample.timestamp
                )
            }
        }

        // 2. Check Linear Acceleration Impulses (Forward/Down nod vs Upward jerk)
        if config.impulseClickEnabled {
            let accel = sample.userAcceleration
            let threshold = config.impulseThresholdG

            // Upward sharp impulse (+Z acceleration)
            if accel.z >= threshold * 1.15 && config.upwardImpulseAction != .none {
                lastTriggerTimestamp = sample.timestamp
                return TriggeredGesture(
                    action: config.upwardImpulseAction,
                    sourceName: String(format: "Up Impulse (%.2fG)", accel.z),
                    timestamp: sample.timestamp
                )
            }

            // Forward/Downward sharp impulse (|Y| or -Z acceleration)
            let forwardDownIntensity = max(abs(accel.y), -accel.z)
            if forwardDownIntensity >= threshold && config.forwardImpulseAction != .none {
                lastTriggerTimestamp = sample.timestamp
                return TriggeredGesture(
                    action: config.forwardImpulseAction,
                    sourceName: String(format: "Head Impulse (%.2fG)", forwardDownIntensity),
                    timestamp: sample.timestamp
                )
            }
        }

        return nil
    }
}

