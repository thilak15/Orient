import Foundation

public enum DiagnosticLabMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case axisIsolation = "1. Axis Isolation & Bleed Calibration"
    case coverPeekAndJump = "2. 3D Cover-Peek & Crouch/Jump"
    case targetDome360 = "3. 360° 3D Target Dome"
    case whipDriftTest = "4. Whip & Quaternion Drift Test"

    public var id: String { rawValue }
}

/// Drives the 4 interactive 3D diagnostic & calibration modes in Phase 2 (Issue #1).
public struct DiagnosticBenchmarkEngine: Sendable {
    public var mode: DiagnosticLabMode = .axisIsolation

    // Mode 1: Axis Isolation & Calibration Metrics
    public var yawPurityScore: Double = 100.0
    public var pitchPurityScore: Double = 100.0
    public var rollPurityScore: Double = 100.0
    public var translationEventsCount: Int = 0

    // Mode 2 & 3: 3D Camera Peek/Stance & Target State
    public var lateralPeekMeters: Double = 0.0
    public var verticalStanceMeters: Double = 0.0
    public var targetAzimuthDeg: Double = 0.0
    public var targetElevationDeg: Double = 0.0
    public var isLineOfSightBlockedByCover: Bool = false
    public var isCrosshairOn3DTarget: Bool = false
    public var domeTargetsHit: Int = 0
    private var targetHoldAccumSec: Double = 0.0

    // Mode 4: High-Speed Whip & Quaternion Return-to-Center Drift
    public var hasCompletedWhipExcursion: Bool = false
    public var peakWhipSpeedDegPerSec: Double = 0.0
    public var measuredReturnDriftDeg: Double? = nil
    private var stillnessAccumSec: Double = 0.0

    public init() {}

    public mutating func resetCurrentMode() {
        yawPurityScore = 100.0
        pitchPurityScore = 100.0
        rollPurityScore = 100.0
        translationEventsCount = 0
        lateralPeekMeters = 0.0
        verticalStanceMeters = 0.0
        isLineOfSightBlockedByCover = false
        isCrosshairOn3DTarget = false
        domeTargetsHit = 0
        targetHoldAccumSec = 0.0
        hasCompletedWhipExcursion = false
        peakWhipSpeedDegPerSec = 0.0
        measuredReturnDriftDeg = nil
        stillnessAccumSec = 0.0
    }

    public mutating func spawnNext3DTarget() {
        switch mode {
        case .coverPeekAndJump:
            // Target sits directly behind the central cover pillar so user must Roll-peek or Jump to hit it
            let offsets: [(Double, Double)] = [(0.0, 0.0), (-3.5, 1.5), (3.5, -1.5), (0.0, 3.0)]
            let pick = offsets[domeTargetsHit % offsets.count]
            targetAzimuthDeg = pick.0
            targetElevationDeg = pick.1
        case .targetDome360:
            // Full 360-degree spherical dome targets (front, sides, rear-quadrants, and elevated)
            let azimuths: [Double] = [-55, 60, -110, 120, -35, 85, -145, 45]
            let elevations: [Double] = [16, -14, 22, 12, -20, 26, -10, 30]
            let idx = domeTargetsHit % azimuths.count
            targetAzimuthDeg = azimuths[idx]
            targetElevationDeg = elevations[idx]
        default:
            targetAzimuthDeg = 0.0
            targetElevationDeg = 0.0
        }
    }

    /// Computes the 3D position `(x, y, z)` in meters on the spherical target dome of radius `domeRadiusMeters`.
    public func targetPosition3D(domeRadiusMeters: Double = 4.8) -> Vector3 {
        let azRad = targetAzimuthDeg * Double.pi / 180.0
        let elRad = targetElevationDeg * Double.pi / 180.0
        let x = domeRadiusMeters * cos(elRad) * sin(azRad)
        let y = domeRadiusMeters * sin(elRad)
        let z = -domeRadiusMeters * cos(elRad) * cos(azRad)
        return Vector3(x: x, y: y, z: z)
    }

    public mutating func update(telemetry: TelemetrySnapshot, dt: Double) {
        let clampedDt = max(0.001, min(0.1, dt))
        let classification = telemetry.motionClassification

        // 1. Update Axis Isolation running purity scores
        switch classification.kind {
        case .pureYaw:
            yawPurityScore = yawPurityScore * 0.88 + classification.axisPurityPercent * 0.12
        case .purePitch:
            pitchPurityScore = pitchPurityScore * 0.88 + classification.axisPurityPercent * 0.12
        case .pureRoll:
            rollPurityScore = rollPurityScore * 0.88 + classification.axisPurityPercent * 0.12
        case .linearTranslation:
            translationEventsCount += 1
        default:
            break
        }

        // 2. Compute 3D Lateral Peek (from Roll angle) and Vertical Stance (from Z linear acceleration)
        let targetPeek = max(-0.75, min(0.75, (telemetry.relativeAngles.rollDeg / 18.0) * 0.50))
        let blend = min(1.0, clampedDt * 14.0)
        lateralPeekMeters += (targetPeek - lateralPeekMeters) * blend

        let accelZ = classification.compensatedLinearAccel.z
        if abs(accelZ) > 0.32 {
            verticalStanceMeters = max(-0.55, min(0.65, verticalStanceMeters + accelZ * 0.45))
        } else {
            verticalStanceMeters *= max(0.0, 1.0 - clampedDt * 4.0)
        }

        // 3. Evaluate Cover-Peek & 360 Dome target line of sight (both Jump +0.30m and Crouch -0.30m clear cover)
        let pillarHalfWidthMeters = 0.34
        let pillarVerticalClearanceMeters = 0.30
        if mode == .coverPeekAndJump {
            let targetBehindPillar = abs(targetAzimuthDeg) < 8.0 && abs(targetElevationDeg) < 6.0
            let cameraClearedPillar = abs(lateralPeekMeters) >= pillarHalfWidthMeters || abs(verticalStanceMeters) >= pillarVerticalClearanceMeters
            isLineOfSightBlockedByCover = targetBehindPillar && !cameraClearedPillar
        } else {
            isLineOfSightBlockedByCover = false
        }

        // Account for 3D camera translation (lateralPeekMeters, verticalStanceMeters) when computing line-of-sight angle to target
        let targetPos = targetPosition3D(domeRadiusMeters: 4.8)
        let dx = targetPos.x - lateralPeekMeters
        let dy = targetPos.y - verticalStanceMeters
        let dz = -targetPos.z
        let horizDist = max(0.1, hypot(dx, dz))
        let rad2deg = 180.0 / Double.pi
        let requiredYawDeg = atan2(dx, dz) * rad2deg
        let requiredPitchDeg = atan2(dy, horizDist) * rad2deg

        // Accept either translated 3D ray lock or direct angular alignment within 6.5 deg
        let rayErrorDeg = hypot(
            telemetry.relativeAngles.yawDeg - requiredYawDeg,
            telemetry.relativeAngles.pitchDeg - requiredPitchDeg
        )
        let directErrorDeg = hypot(
            telemetry.relativeAngles.yawDeg - targetAzimuthDeg,
            telemetry.relativeAngles.pitchDeg - targetElevationDeg
        )
        isCrosshairOn3DTarget = !isLineOfSightBlockedByCover && (min(rayErrorDeg, directErrorDeg) <= 6.5)

        if isCrosshairOn3DTarget && (mode == .coverPeekAndJump || mode == .targetDome360) {
            targetHoldAccumSec += clampedDt
            if targetHoldAccumSec >= 0.28 {
                targetHoldAccumSec = 0
                domeTargetsHit += 1
                spawnNext3DTarget()
            }
        } else {
            targetHoldAccumSec = max(0, targetHoldAccumSec - clampedDt * 2.0)
        }

        // 4. Evaluate Mode 4: High-Speed Whip & Quaternion Return-to-Center Drift
        if mode == .whipDriftTest {
            let speed = max(
                classification.dominantRotationalSpeedDegPerSec,
                hypot(telemetry.filteredYawRateDegPerSec, telemetry.filteredPitchRateDegPerSec)
            )
            if speed > peakWhipSpeedDegPerSec {
                peakWhipSpeedDegPerSec = speed
            }
            if speed >= 100.0 && telemetry.relativeAngles.lookDeviationDeg >= 20.0 {
                hasCompletedWhipExcursion = true
                measuredReturnDriftDeg = nil
                stillnessAccumSec = 0.0
            } else if hasCompletedWhipExcursion && speed < 5.0 && telemetry.relativeAngles.lookDeviationDeg < 12.0 {
                stillnessAccumSec += clampedDt
                if stillnessAccumSec >= 0.25 && measuredReturnDriftDeg == nil {
                    measuredReturnDriftDeg = telemetry.relativeAngles.lookDeviationDeg
                }
            } else {
                stillnessAccumSec = 0.0
            }
        }
    }
}

