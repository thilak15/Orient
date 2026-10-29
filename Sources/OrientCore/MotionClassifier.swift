import Foundation

public enum MotionKind: String, Sendable, Equatable, Codable, CaseIterable {
    case stationary = "Stationary"
    case pureYaw = "Pure Yaw (Turn Left/Right)"
    case purePitch = "Pure Pitch (Nod Up/Down)"
    case pureRoll = "Pure Roll (Tilt Ear-to-Shoulder)"
    case linearTranslation = "Linear Translation / Impulse"
    case compoundMotion = "Compound Motion"
}

public struct MotionClassification: Sendable, Equatable, Codable {
    public var kind: MotionKind
    public var compensatedLinearAccel: Vector3
    public var inducedRotationalAccel: Vector3
    public var axisPurityPercent: Double
    public var dominantRotationalSpeedDegPerSec: Double

    public static let idle = MotionClassification(
        kind: .stationary,
        compensatedLinearAccel: .zero,
        inducedRotationalAccel: .zero,
        axisPurityPercent: 100.0,
        dominantRotationalSpeedDegPerSec: 0
    )

    public init(
        kind: MotionKind,
        compensatedLinearAccel: Vector3,
        inducedRotationalAccel: Vector3,
        axisPurityPercent: Double,
        dominantRotationalSpeedDegPerSec: Double
    ) {
        self.kind = kind
        self.compensatedLinearAccel = compensatedLinearAccel
        self.inducedRotationalAccel = inducedRotationalAccel
        self.axisPurityPercent = axisPurityPercent
        self.dominantRotationalSpeedDegPerSec = dominantRotationalSpeedDegPerSec
    }
}

/// Classifies 6-DOF head motion into Stationary, Pure Yaw, Pure Pitch, Pure Roll,
/// Linear Translation, or Compound Motion while subtracting neck-pivot lever-arm
/// centripetal and tangential accelerations from `userAcceleration`.
public struct MotionClassifier: Sendable {
    public var leverArmRadiusMeters: Double
    public var rotationalThresholdDegPerSec: Double
    public var linearThresholdG: Double
    public var purityThresholdPercent: Double

    public init(
        leverArmRadiusMeters: Double = 0.085,
        rotationalThresholdDegPerSec: Double = 8.0,
        linearThresholdG: Double = 0.28,
        purityThresholdPercent: Double = 72.0
    ) {
        self.leverArmRadiusMeters = leverArmRadiusMeters
        self.rotationalThresholdDegPerSec = rotationalThresholdDegPerSec
        self.linearThresholdG = linearThresholdG
        self.purityThresholdPercent = purityThresholdPercent
    }

    public func analyze(
        sample: IMUSample,
        previousSample: IMUSample?,
        relativeAngles: HeadAngles
    ) -> MotionClassification {
        let g = 9.80665
        let r = leverArmRadiusMeters
        let omega = sample.rotationRate

        // 1. Estimate angular acceleration alpha = d(omega)/dt
        let alpha: Vector3
        if let prev = previousSample {
            let dt = max(0.002, min(0.15, sample.timestamp - prev.timestamp))
            alpha = Vector3(
                x: (omega.x - prev.rotationRate.x) / dt,
                y: (omega.y - prev.rotationRate.y) / dt,
                z: (omega.z - prev.rotationRate.z) / dt
            )
        } else {
            alpha = .zero
        }

        // 2. Compute rotational lever-arm acceleration at the ear sensor (lateral r_x = r, vertical neck offset r_z = r):
        //    Includes Yaw, Roll, and Pitch tangential (alpha x r) and centripetal (omega x (omega x r)) terms
        let inducedX = -((omega.y * omega.y + omega.z * omega.z) * r) / g
        let inducedY = ((alpha.z + alpha.x) * r) / g
        let inducedZ = -((alpha.y + omega.x * omega.x) * r) / g
        let inducedRotAccel = Vector3(x: inducedX, y: inducedY, z: inducedZ)

        let compensatedLinear = Vector3(
            x: Self.attenuateTowardZero(value: sample.userAcceleration.x, byAmount: abs(inducedRotAccel.x)),
            y: Self.attenuateTowardZero(value: sample.userAcceleration.y, byAmount: abs(inducedRotAccel.y)),
            z: Self.attenuateTowardZero(value: sample.userAcceleration.z, byAmount: abs(inducedRotAccel.z))
        )

        // 3. Rotational rates in deg/s
        let rates = sample.ergonomicRatesDegPerSec
        let absPitchRate = abs(rates.pitchRate)
        let absRollRate = abs(rates.rollRate)
        let absYawRate = abs(rates.yawRate)

        let sumRates = absYawRate + absPitchRate + absRollRate
        let maxRate = max(absYawRate, max(absPitchRate, absRollRate))
        let purity = sumRates > 1e-3 ? (maxRate / sumRates) * 100.0 : 100.0

        let isRotating = maxRate >= rotationalThresholdDegPerSec
        let isTranslating = compensatedLinear.magnitude >= linearThresholdG

        // Also detect sustained static roll tilt (e.g. holding ear-to-shoulder peek)
        let isHoldingStaticRoll = !isRotating && abs(relativeAngles.rollDeg) >= 11.0 && abs(relativeAngles.yawDeg) < 8.0 && abs(relativeAngles.pitchDeg) < 8.0

        let kind: MotionKind
        if isTranslating && !isRotating {
            kind = .linearTranslation
        } else if isTranslating && isRotating {
            kind = .compoundMotion
        } else if isHoldingStaticRoll {
            kind = .pureRoll
        } else if !isRotating {
            kind = .stationary
        } else if purity >= purityThresholdPercent {
            if absYawRate == maxRate {
                kind = .pureYaw
            } else if absPitchRate == maxRate {
                kind = .purePitch
            } else {
                kind = .pureRoll
            }
        } else {
            kind = .compoundMotion
        }

        return MotionClassification(
            kind: kind,
            compensatedLinearAccel: compensatedLinear,
            inducedRotationalAccel: inducedRotAccel,
            axisPurityPercent: purity,
            dominantRotationalSpeedDegPerSec: maxRate
        )
    }

    private static func attenuateTowardZero(value: Double, byAmount amount: Double) -> Double {
        let mag = abs(value)
        guard mag > amount else { return 0.0 }
        return (value >= 0 ? 1.0 : -1.0) * (mag - amount)
    }
}
