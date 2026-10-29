import Foundation

/// 3D Vector for angular velocity (rad/s) and linear acceleration (G).
public struct Vector3: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}

/// Unit quaternion representing 3D orientation without gimbal lock.
public struct Quaternion: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public var conjugate: Quaternion {
        Quaternion(x: -x, y: -y, z: -z, w: w)
    }

    public var normalized: Quaternion {
        let norm = (x * x + y * y + z * z + w * w).squareRoot()
        guard norm > 1e-12 else { return .identity }
        return Quaternion(x: x / norm, y: y / norm, z: z / norm, w: w / norm)
    }

    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        Quaternion(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    /// Computes relative orientation from `reference` to `self`: q_rel = q_ref^* * q_self
    public func relative(to reference: Quaternion) -> Quaternion {
        (reference.conjugate * self).normalized
    }

    /// Converts CoreMotion attitude quaternion (where Z is yaw, X is pitch, Y is roll in head frame)
    /// into ergonomic head angles in degrees:
    /// - yawDeg: positive = looking right, negative = looking left
    /// - pitchDeg: positive = looking up, negative = looking down
    /// - rollDeg: positive = tilting right ear to right shoulder, negative = left ear to left shoulder
    public func toHeadAnglesDegrees() -> HeadAngles {
        let q = self.normalized

        // Pitch (rotation around X-axis: nodding up/down)
        let sinP = 2.0 * (q.w * q.x + q.y * q.z)
        let cosP = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
        let pitchRad = atan2(sinP, cosP)

        // Roll (rotation around Y-axis: ear-to-shoulder tilt)
        let sinR = max(-1.0, min(1.0, 2.0 * (q.w * q.y - q.z * q.x)))
        let rollRad = asin(sinR)

        // Yaw (rotation around Z-axis: turning head left/right; in CoreMotion +Z is counter-clockwise/left, so negate for right = +)
        let sinY = 2.0 * (q.w * q.z + q.x * q.y)
        let cosY = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
        let yawRad = -atan2(sinY, cosY)

        let rad2deg = 180.0 / Double.pi
        return HeadAngles(
            yawDeg: yawRad * rad2deg,
            pitchDeg: pitchRad * rad2deg,
            rollDeg: rollRad * rad2deg
        )
    }

    public static func fromHeadAnglesDegrees(yawDeg: Double, pitchDeg: Double, rollDeg: Double) -> Quaternion {
        let deg2rad = Double.pi / 180.0
        let halfPitch = (pitchDeg * deg2rad) * 0.5
        let halfRoll = (rollDeg * deg2rad) * 0.5
        let halfYaw = (-yawDeg * deg2rad) * 0.5

        let cp = cos(halfPitch), sp = sin(halfPitch)
        let cr = cos(halfRoll), sr = sin(halfRoll)
        let cy = cos(halfYaw), sy = sin(halfYaw)

        return Quaternion(
            x: sp * cr * cy - cp * sr * sy,
            y: cp * sr * cy + sp * cr * sy,
            z: cp * cr * sy - sp * sr * cy,
            w: cp * cr * cy + sp * sr * sy
        ).normalized
    }
}

public struct HeadAngles: Sendable, Equatable, Codable {
    public var yawDeg: Double
    public var pitchDeg: Double
    public var rollDeg: Double

    public static let zero = HeadAngles(yawDeg: 0, pitchDeg: 0, rollDeg: 0)

    public init(yawDeg: Double, pitchDeg: Double, rollDeg: Double) {
        self.yawDeg = yawDeg
        self.pitchDeg = pitchDeg
        self.rollDeg = rollDeg
    }

    /// Combined off-screen angle (yaw & pitch) used for safety auto-pause.
    public var lookDeviationDeg: Double {
        (yawDeg * yawDeg + pitchDeg * pitchDeg).squareRoot()
    }
}

/// Raw IMU packet from CMHeadphoneMotionManager or Synthetic Simulator.
public struct IMUSample: Sendable, Equatable {
    public var timestamp: TimeInterval
    public var attitude: Quaternion
    /// Gyroscope rotation rate in rad/s (x: pitch rate, y: roll rate, z: yaw rate).
    public var rotationRate: Vector3
    /// Linear acceleration excluding gravity in G (x: lateral, y: forward/back, z: vertical).
    public var userAcceleration: Vector3
    public var gravity: Vector3

    public init(
        timestamp: TimeInterval,
        attitude: Quaternion,
        rotationRate: Vector3,
        userAcceleration: Vector3,
        gravity: Vector3 = Vector3(x: 0, y: 0, z: -1)
    ) {
        self.timestamp = timestamp
        self.attitude = attitude
        self.rotationRate = rotationRate
        self.userAcceleration = userAcceleration
        self.gravity = gravity
    }
}

public enum GestureAction: String, CaseIterable, Sendable, Codable, Identifiable {
    case none = "None"
    case leftClick = "Left Click"
    case rightClick = "Right Click"
    case doubleClick = "Double Click"
    case recenter = "Recenter Pose"
    case togglePrecision = "Toggle Precision Slowdown"

    public var id: String { rawValue }
}

public struct OrientConfiguration: Sendable, Equatable, Codable {
    // Sensitivity & Curve
    public var yawSensitivity: Double = 28.0
    public var pitchSensitivity: Double = 38.0
    public var deadzoneDegPerSec: Double = 1.1
    public var responseCurveExponent: Double = 1.30
    public var precisionSlowdownMultiplier: Double = 0.45
    public var invertYaw: Bool = false
    public var invertPitch: Bool = false

    // Hybrid Edge Continuous Pan
    public var hybridEdgePanEnabled: Bool = true
    public var edgeYawThresholdDeg: Double = 22.0
    public var edgePitchThresholdDeg: Double = 16.0
    public var edgePanSpeedPxPerSec: Double = 900.0

    // 1-Euro Adaptive Low-Pass Filter
    public var oneEuroMinCutoff: Double = 1.6
    public var oneEuroBeta: Double = 0.085
    public var oneEuroDerivativeCutoff: Double = 1.0

    // Click Gestures & Aim-Freeze Compensation
    public var aimFreezeDurationMs: Double = 85.0
    public var preClickRollbackWindowMs: Double = 45.0
    public var rollClickEnabled: Bool = true
    public var rollLeftAction: GestureAction = .leftClick
    public var rollRightAction: GestureAction = .rightClick
    public var rollTriggerAngleDeg: Double = 14.0
    public var rollReleaseAngleDeg: Double = 8.0

    public var impulseClickEnabled: Bool = true
    public var forwardImpulseAction: GestureAction = .leftClick
    public var upwardImpulseAction: GestureAction = .doubleClick
    public var impulseThresholdG: Double = 0.52
    public var gestureCooldownMs: Double = 260.0

    // Safety & Audio Keep-Alive
    public var safetyCutoffAngleDeg: Double = 75.0
    public var silentAudioKeepAliveEnabled: Bool = true

    public init() {}
}

