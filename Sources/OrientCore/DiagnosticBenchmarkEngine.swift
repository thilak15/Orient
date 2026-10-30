import Foundation

public enum DiagnosticLabMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case guidedWizard = "⭐ Guided 5-Step Feasibility & Calibration Wizard"
    case axisIsolation = "1. Axis Isolation & Bleed Calibration"
    case coverPeekAndJump = "2. 3D Cover-Peek & Crouch/Jump"
    case targetDome360 = "3. 360° 3D Target Dome"
    case whipDriftTest = "4. Whip & Quaternion Drift Test"

    public var id: String { rawValue }
}

public enum GuidedWizardStep: Int, CaseIterable, Sendable, Codable {
    case step1NeutralHold = 0
    case step2YawLeftRight = 1
    case step3PitchUpDown = 2
    case step4RollPeekLeftRight = 3
    case step5TargetShootout = 4
    case completed = 5

    public var title: String {
        switch self {
        case .step1NeutralHold: return "Step 1/5: Neutral Comfort Hold"
        case .step2YawLeftRight: return "Step 2/5: Horizontal Look (Yaw Left & Right)"
        case .step3PitchUpDown: return "Step 3/5: Vertical Look (Pitch Up & Down)"
        case .step4RollPeekLeftRight: return "Step 4/5: Ear-to-Shoulder Tilt (Roll Left & Right)"
        case .step5TargetShootout: return "Step 5/5: 3D Target Lock Mini-Game (Hit 3 Targets)"
        case .completed: return "All 5 Feasibility & Calibration Steps Completed!"
        }
    }

    public var instruction: String {
        switch self {
        case .step1NeutralHold:
            return "Press ⌥R (or click Recenter) while looking comfortably at the center of the 3D room, then hold still for 1.5 seconds."
        case .step2YawLeftRight:
            return "Turn your head LEFT past -18° and then RIGHT past +18° (notice how Roll stays locked at 0°!)."
        case .step3PitchUpDown:
            return "Nod your chin UP past +12° and then DOWN past -12°."
        case .step4RollPeekLeftRight:
            return "Tilt your LEFT ear toward your left shoulder (-14°) and RIGHT ear toward your right shoulder (+14°) like peeking in PUBG."
        case .step5TargetShootout:
            return "Aim the cyan 3D laser beam onto 3 glowing orange spheres in the 3D room to verify smooth aiming!"
        case .completed:
            return "Your AirPods 6-DOF tracking is verified! Review your feasibility report below or switch to any 3D sandbox mode."
        }
    }
}

/// Drives the interactive 3D diagnostic, guided wizard, and calibration modes in Phase 2 (Issue #1).
public struct DiagnosticBenchmarkEngine: Sendable {
    public var mode: DiagnosticLabMode = .guidedWizard

    // Guided Wizard State
    public var wizardStep: GuidedWizardStep = .step1NeutralHold
    public var wizardStepProgress: Double = 0.0
    public var didHitLeftCriterion: Bool = false
    public var didHitRightCriterion: Bool = false
    public var measuredRestingNoiseDegPerSec: Double = 0.0
    public var measuredMaxRollBleedDuringYawDeg: Double = 0.0

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
        wizardStep = .step1NeutralHold
        wizardStepProgress = 0.0
        didHitLeftCriterion = false
        didHitRightCriterion = false
        measuredRestingNoiseDegPerSec = 0.0
        measuredMaxRollBleedDuringYawDeg = 0.0
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
            let offsets: [(Double, Double)] = [(0.0, 0.0), (-3.5, 1.5), (3.5, -1.5), (0.0, 3.0)]
            let pick = offsets[domeTargetsHit % offsets.count]
            targetAzimuthDeg = pick.0
            targetElevationDeg = pick.1
        case .targetDome360, .guidedWizard:
            // Comfortable front-hemisphere 3D targets so user doesn't have to turn away from the Mac screen
            let azimuths: [Double] = [-22, 24, -16, 20, -28, 18, -12, 26]
            let elevations: [Double] = [10, -8, 14, 8, -12, 12, -6, 15]
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

        // 2. Compute 3D Lateral Peek (from Roll angle) and Vertical Stance ONLY in Cover-Peek mode
        //    (with a 9-degree deadzone so normal looking never slides the 3D head rig!)
        if mode == .coverPeekAndJump {
            let absRoll = abs(telemetry.relativeAngles.rollDeg)
            let effectiveRoll: Double
            if absRoll <= 9.0 {
                effectiveRoll = 0.0
            } else {
                let sign = telemetry.relativeAngles.rollDeg >= 0 ? 1.0 : -1.0
                effectiveRoll = sign * (absRoll - 9.0)
            }
            let targetPeek = max(-0.75, min(0.75, (effectiveRoll / 11.0) * 0.50))
            let blend = min(1.0, clampedDt * 14.0)
            lateralPeekMeters += (targetPeek - lateralPeekMeters) * blend

            let accelZ = classification.compensatedLinearAccel.z
            if abs(accelZ) > 0.32 {
                verticalStanceMeters = max(-0.55, min(0.65, verticalStanceMeters + accelZ * 0.45))
            } else {
                verticalStanceMeters *= max(0.0, 1.0 - clampedDt * 4.0)
            }
        } else {
            lateralPeekMeters = 0.0
            verticalStanceMeters = 0.0
        }

        // 3. Evaluate Cover-Peek & 360 Dome target line of sight
        let pillarHalfWidthMeters = 0.34
        let pillarVerticalClearanceMeters = 0.30
        if mode == .coverPeekAndJump {
            let targetBehindPillar = abs(targetAzimuthDeg) < 8.0 && abs(targetElevationDeg) < 6.0
            let cameraClearedPillar = abs(lateralPeekMeters) >= pillarHalfWidthMeters || abs(verticalStanceMeters) >= pillarVerticalClearanceMeters
            isLineOfSightBlockedByCover = targetBehindPillar && !cameraClearedPillar
        } else {
            isLineOfSightBlockedByCover = false
        }

        let targetPos = targetPosition3D(domeRadiusMeters: 4.8)
        let dx = targetPos.x - lateralPeekMeters
        let dy = targetPos.y - verticalStanceMeters
        let dz = -targetPos.z
        let horizDist = max(0.1, hypot(dx, dz))
        let rad2deg = 180.0 / Double.pi
        let requiredYawDeg = atan2(dx, dz) * rad2deg
        let requiredPitchDeg = atan2(dy, horizDist) * rad2deg

        let rayErrorDeg = hypot(
            telemetry.relativeAngles.yawDeg - requiredYawDeg,
            telemetry.relativeAngles.pitchDeg - requiredPitchDeg
        )
        let directErrorDeg = hypot(
            telemetry.relativeAngles.yawDeg - targetAzimuthDeg,
            telemetry.relativeAngles.pitchDeg - targetElevationDeg
        )
        isCrosshairOn3DTarget = !isLineOfSightBlockedByCover && (min(rayErrorDeg, directErrorDeg) <= 6.5)

        let isTargetActiveMode = (mode == .coverPeekAndJump || mode == .targetDome360 || (mode == .guidedWizard && wizardStep == .step5TargetShootout))
        if isCrosshairOn3DTarget && isTargetActiveMode {
            targetHoldAccumSec += clampedDt
            if targetHoldAccumSec >= 0.25 {
                targetHoldAccumSec = 0
                domeTargetsHit += 1
                spawnNext3DTarget()
            }
        } else {
            targetHoldAccumSec = max(0, targetHoldAccumSec - clampedDt * 2.0)
        }

        // 4. Evaluate Guided 5-Step Feasibility Wizard
        if mode == .guidedWizard {
            updateGuidedWizard(telemetry: telemetry, dt: clampedDt)
        }

        // 5. Evaluate Mode 4: High-Speed Whip & Quaternion Return-to-Center Drift
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

    private mutating func updateGuidedWizard(telemetry: TelemetrySnapshot, dt: Double) {
        let angles = telemetry.relativeAngles
        switch wizardStep {
        case .step1NeutralHold:
            let speed = hypot(telemetry.filteredYawRateDegPerSec, telemetry.filteredPitchRateDegPerSec)
            if angles.lookDeviationDeg < 6.0 && speed < 8.0 {
                wizardStepProgress = min(1.0, wizardStepProgress + dt / 1.4)
                measuredRestingNoiseDegPerSec = measuredRestingNoiseDegPerSec * 0.9 + speed * 0.1
                if wizardStepProgress >= 1.0 {
                    advanceWizardStep(to: .step2YawLeftRight)
                }
            }
        case .step2YawLeftRight:
            if abs(angles.yawDeg) > 10.0 {
                measuredMaxRollBleedDuringYawDeg = max(measuredMaxRollBleedDuringYawDeg, abs(angles.rollDeg))
            }
            if angles.yawDeg <= -16.0 { didHitLeftCriterion = true }
            if angles.yawDeg >= 16.0 { didHitRightCriterion = true }
            wizardStepProgress = (didHitLeftCriterion ? 0.5 : 0.0) + (didHitRightCriterion ? 0.5 : 0.0)
            if didHitLeftCriterion && didHitRightCriterion {
                advanceWizardStep(to: .step3PitchUpDown)
            }
        case .step3PitchUpDown:
            if angles.pitchDeg >= 11.0 { didHitLeftCriterion = true }
            if angles.pitchDeg <= -11.0 { didHitRightCriterion = true }
            wizardStepProgress = (didHitLeftCriterion ? 0.5 : 0.0) + (didHitRightCriterion ? 0.5 : 0.0)
            if didHitLeftCriterion && didHitRightCriterion {
                advanceWizardStep(to: .step4RollPeekLeftRight)
            }
        case .step4RollPeekLeftRight:
            if angles.rollDeg <= -13.0 { didHitLeftCriterion = true }
            if angles.rollDeg >= 13.0 { didHitRightCriterion = true }
            wizardStepProgress = (didHitLeftCriterion ? 0.5 : 0.0) + (didHitRightCriterion ? 0.5 : 0.0)
            if didHitLeftCriterion && didHitRightCriterion {
                domeTargetsHit = 0
                spawnNext3DTarget()
                advanceWizardStep(to: .step5TargetShootout)
            }
        case .step5TargetShootout:
            wizardStepProgress = min(1.0, Double(domeTargetsHit) / 3.0)
            if domeTargetsHit >= 3 {
                advanceWizardStep(to: .completed)
            }
        case .completed:
            wizardStepProgress = 1.0
        }
    }

    public mutating func advanceWizardStep(to next: GuidedWizardStep) {
        wizardStep = next
        wizardStepProgress = (next == .completed) ? 1.0 : 0.0
        didHitLeftCriterion = false
        didHitRightCriterion = false
    }
}
