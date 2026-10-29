import Foundation

/// Represents the learned cross-axis anatomical coupling coefficients from ear-to-shoulder Roll
/// into Yaw and Pitch angular velocity.
public struct DecouplingMatrix: Sendable, Equatable, Codable {
    public var rollToYawCoupling: Double
    public var rollToPitchCoupling: Double

    public static let identity = DecouplingMatrix(rollToYawCoupling: 0.0, rollToPitchCoupling: 0.0)

    public init(rollToYawCoupling: Double = 0.0, rollToPitchCoupling: Double = 0.0) {
        self.rollToYawCoupling = max(-0.65, min(0.65, rollToYawCoupling))
        self.rollToPitchCoupling = max(-0.65, min(0.65, rollToPitchCoupling))
    }

    /// Removes anatomical Roll-induced bleed from raw Yaw and Pitch angular velocities (deg/s).
    public func decouple(
        yawRateDegPerSec: Double,
        pitchRateDegPerSec: Double,
        rollRateDegPerSec: Double
    ) -> (yawRate: Double, pitchRate: Double) {
        let decoupledYaw = yawRateDegPerSec - rollToYawCoupling * rollRateDegPerSec
        let decoupledPitch = pitchRateDegPerSec - rollToPitchCoupling * rollRateDegPerSec
        return (decoupledYaw, decoupledPitch)
    }

    /// Removes anatomical Roll-induced bleed from relative head orientation angles (deg).
    public func decoupleAngles(_ angles: HeadAngles) -> HeadAngles {
        HeadAngles(
            yawDeg: angles.yawDeg - rollToYawCoupling * angles.rollDeg,
            pitchDeg: angles.pitchDeg - rollToPitchCoupling * angles.rollDeg,
            rollDeg: angles.rollDeg
        )
    }
}

public enum CrossAxisCalibrator {
    /// Computes least-squares Roll -> Yaw and Roll -> Pitch coupling ratios from a series of
    /// ear-to-shoulder Roll tilt samples collected while the user looks at a fixed screen center point.
    public static func calibrateFromRollSamples(_ samples: [IMUSample]) -> DecouplingMatrix {
        var sumRollSq: Double = 0
        var sumRollYaw: Double = 0
        var sumRollPitch: Double = 0

        for s in samples {
            let rates = s.ergonomicRatesDegPerSec
            guard abs(rates.rollRate) >= 8.0 else { continue }
            sumRollSq += rates.rollRate * rates.rollRate
            sumRollYaw += rates.rollRate * rates.yawRate
            sumRollPitch += rates.rollRate * rates.pitchRate
        }

        guard sumRollSq > 10.0 else { return .identity }
        return DecouplingMatrix(
            rollToYawCoupling: sumRollYaw / sumRollSq,
            rollToPitchCoupling: sumRollPitch / sumRollSq
        )
    }
}

