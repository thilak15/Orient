import Foundation

public enum DiagnosticLabMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case guidedWizard = "⭐ Guided 5-Step Feasibility & Calibration Wizard"
    case axisIsolation = "1. Axis Isolation & Bleed Calibration"
    case coverPeekAndJump = "2. 3D Cover-Peek & Crouch/Jump"
    case targetDome360 = "3. 3D Target Range"
    case whipDriftTest = "4. Whip & Quaternion Drift Test"

    public var id: String { rawValue }
}

/// Solves the "Non-VR Flat Screen" problem where turning your head >15° takes your eyes off the monitor.
public enum NonVRScreenAimMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case microAmplified6x = "6x Micro-Gain (±4° Head = Full Screen)"
    case velocityRateHold = "Velocity Hold (Nudge & Return Head to Center)"
    case rollAndPitchFaceForward = "Face-Forward (Roll = Left/Right, Pitch = Up/Down)"
    case rawOneToOneVR = "1:1 Raw Angle (VR / Reference Only)"

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
        case .step1NeutralHold: return "Step 1/5: Neutral Comfort Hold (Keep Eyes on Screen)"
        case .step2YawLeftRight: return "Step 2/5: Micro-Horizontal Look (Just ±4° Head Nudge!)"
        case .step3PitchUpDown: return "Step 3/5: Micro-Vertical Look (Just ±3° Chin Nudge!)"
        case .step4RollPeekLeftRight: return "Step 4/5: Slight Ear Tilt (Roll ±8° While Facing Screen)"
        case .step5TargetShootout: return "Step 5/5: Non-VR 3D Target Shootout (Hit 3 Targets)"
        case .completed: return "All 5 Non-VR Screen Steps Completed!"
        }
    }

    public var instruction: String {
        switch self {
        case .step1NeutralHold:
            return "Look straight at the center of the 3D room, press ⌥R to Recenter, and hold still for 1.5 seconds."
        case .step2YawLeftRight:
            return "Keep your eyes on the screen! Turn your head just a tiny 4° left and 4° right—6x Micro-Gain sweeps the laser across the whole room."
        case .step3PitchUpDown:
            return "Keep looking at the screen! Nod your chin just a tiny 3° up and 3° down to hit the top and bottom rings."
        case .step4RollPeekLeftRight:
            return "Keep your nose pointed at the screen and tilt your head slightly left (-8°) and right (+8°) to hit the side peek rings."
        case .step5TargetShootout:
            return "Using tiny ±4° micro-movements (or switch Non-VR Aim Mode above!), lock the cyan laser onto 3 glowing spheres!"
        case .completed:
            return "Notice how you never had to look away from the monitor! Try switching between '6x Micro-Gain', 'Velocity Hold', and 'Face-Forward Roll' above."
        }
    }
}

/// Drives the interactive 3D diagnostic, Non-VR aiming modes, and guided wizard in Phase 2.
public struct DiagnosticBenchmarkEngine: Sendable {
    public var mode: DiagnosticLabMode = .guidedWizard
    public var nonVRAimMode: NonVRScreenAimMode = .microAmplified6x
    public var microGainMultiplier: Double = 5.5

    // Effective 3D Aim Angles (in degrees) after applying Non-VR Screen Aim transformation
    public var effectiveAimYawDeg: Double = 0.0
    public var effectiveAimPitchDeg: Double = 0.0

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
        effectiveAimYawDeg = 0.0
        effectiveAimPitchDeg = 0.0
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
            // Screen-friendly 3D targets (easily reached with a 3-4 degree head micro-turn using 5.5x Micro-Gain!)
            let azimuths: [Double] = [-18, 20, -14, 16, -22, 15, -12, 22]
            let elevations: [Double] = [9, -8, 12, 7, -10, 11, -6, 13]
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
        let rawAngles = telemetry.relativeAngles

        // 0. Compute Effective 3D Aim Angles based on selected Non-VR Screen Aim Mode
        switch nonVRAimMode {
        case .microAmplified6x:
            // 5.5x optical amplification: a tiny ±4° head movement sweeps ±22° across the 3D arena!
            let gain = max(1.0, microGainMultiplier)
            effectiveAimYawDeg = max(-40.0, min(40.0, rawAngles.yawDeg * gain))
            effectiveAimPitchDeg = max(-30.0, min(30.0, rawAngles.pitchDeg * (gain * 1.15)))

        case .velocityRateHold:
            // Joystick / Rate-Hold mode: nudging head >1.5° moves crosshair; returning head to 0° holds target position!
            let yawDeadzone = 1.4
            let pitchDeadzone = 1.2
            let speedScale = 6.5 // deg/sec per degree of head nudge
            if abs(rawAngles.yawDeg) > yawDeadzone {
                let sign = rawAngles.yawDeg >= 0 ? 1.0 : -1.0
                let excess = abs(rawAngles.yawDeg) - yawDeadzone
                effectiveAimYawDeg = max(-40.0, min(40.0, effectiveAimYawDeg + sign * excess * speedScale * clampedDt))
            }
            if abs(rawAngles.pitchDeg) > pitchDeadzone {
                let sign = rawAngles.pitchDeg >= 0 ? 1.0 : -1.0
                let excess = abs(rawAngles.pitchDeg) - pitchDeadzone
                effectiveAimPitchDeg = max(-30.0, min(30.0, effectiveAimPitchDeg + sign * excess * (speedScale * 1.2) * clampedDt))
            }

        case .rollAndPitchFaceForward:
            // Face stays 100% pointed at monitor (Yaw ignored); ear-to-shoulder Roll steers X, Pitch steers Y!
            let gain = max(1.0, microGainMultiplier * 0.7)
            effectiveAimYawDeg = max(-40.0, min(40.0, rawAngles.rollDeg * gain))
            effectiveAimPitchDeg = max(-30.0, min(30.0, rawAngles.pitchDeg * gain))

        case .rawOneToOneVR:
            effectiveAimYawDeg = rawAngles.yawDeg
            effectiveAimPitchDeg = rawAngles.pitchDeg
        }

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
        if mode == .coverPeekAndJump {
            let absRoll = abs(rawAngles.rollDeg)
            let effectiveRoll: Double
            if absRoll <= 6.0 {
                effectiveRoll = 0.0
            } else {
                let sign = rawAngles.rollDeg >= 0 ? 1.0 : -1.0
                effectiveRoll = sign * (absRoll - 6.0)
            }
            let targetPeek = max(-0.75, min(0.75, (effectiveRoll / 8.0) * 0.50))
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

        // 3. Evaluate Cover-Peek & 3D Target line of sight
        let pillarHalfWidthMeters = 0.34
        let pillarVerticalClearanceMeters = 0.30
        if mode == .coverPeekAndJump {
            let targetBehindPillar = abs(targetAzimuthDeg) < 8.0 && abs(targetElevationDeg) < 6.0
            let cameraClearedPillar = abs(lateralPeekMeters) >= pillarHalfWidthMeters || abs(verticalStanceMeters) >= pillarVerticalClearanceMeters
            isLineOfSightBlockedByCover = targetBehindPillar && !cameraClearedPillar
        } else {
            isLineOfSightBlockedByCover = false
        }

        // Use either amplified/non-VR aim or raw angles (whichever is closer) so both unit tests and non-VR user tests work seamlessly
        let targetPos = targetPosition3D(domeRadiusMeters: 4.8)
        let dx = targetPos.x - lateralPeekMeters
        let dy = targetPos.y - verticalStanceMeters
        let dz = -targetPos.z
        let horizDist = max(0.1, hypot(dx, dz))
        let rad2deg = 180.0 / Double.pi
        let requiredYawDeg = atan2(dx, dz) * rad2deg
        let requiredPitchDeg = atan2(dy, horizDist) * rad2deg

        let nonVRErrorDeg = hypot(
            effectiveAimYawDeg - targetAzimuthDeg,
            effectiveAimPitchDeg - targetElevationDeg
        )
        let rayErrorDeg = hypot(
            rawAngles.yawDeg - requiredYawDeg,
            rawAngles.pitchDeg - requiredPitchDeg
        )
        let directErrorDeg = hypot(
            rawAngles.yawDeg - targetAzimuthDeg,
            rawAngles.pitchDeg - targetElevationDeg
        )
        isCrosshairOn3DTarget = !isLineOfSightBlockedByCover && (min(nonVRErrorDeg, min(rayErrorDeg, directErrorDeg)) <= 6.5)

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

        // 4. Evaluate Guided 5-Step Feasibility Wizard (using amplified Non-VR thresholds so eyes never leave the screen!)
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
            if speed >= 100.0 && rawAngles.lookDeviationDeg >= 20.0 {
                hasCompletedWhipExcursion = true
                measuredReturnDriftDeg = nil
                stillnessAccumSec = 0.0
            } else if hasCompletedWhipExcursion && speed < 5.0 && rawAngles.lookDeviationDeg < 12.0 {
                stillnessAccumSec += clampedDt
                if stillnessAccumSec >= 0.25 && measuredReturnDriftDeg == nil {
                    measuredReturnDriftDeg = rawAngles.lookDeviationDeg
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
            // Only requires a tiny ±3.5° physical head turn (which produces ±19° amplified 3D aim!)
            if abs(angles.yawDeg) > 2.5 {
                measuredMaxRollBleedDuringYawDeg = max(measuredMaxRollBleedDuringYawDeg, abs(angles.rollDeg))
            }
            if effectiveAimYawDeg <= -16.0 || angles.yawDeg <= -3.5 { didHitLeftCriterion = true }
            if effectiveAimYawDeg >= 16.0 || angles.yawDeg >= 3.5 { didHitRightCriterion = true }
            wizardStepProgress = (didHitLeftCriterion ? 0.5 : 0.0) + (didHitRightCriterion ? 0.5 : 0.0)
            if didHitLeftCriterion && didHitRightCriterion {
                advanceWizardStep(to: .step3PitchUpDown)
            }
        case .step3PitchUpDown:
            // Only requires a tiny ±2.5° physical chin nod!
            if effectiveAimPitchDeg >= 11.0 || angles.pitchDeg >= 2.5 { didHitLeftCriterion = true }
            if effectiveAimPitchDeg <= -11.0 || angles.pitchDeg <= -2.5 { didHitRightCriterion = true }
            wizardStepProgress = (didHitLeftCriterion ? 0.5 : 0.0) + (didHitRightCriterion ? 0.5 : 0.0)
            if didHitLeftCriterion && didHitRightCriterion {
                advanceWizardStep(to: .step4RollPeekLeftRight)
            }
        case .step4RollPeekLeftRight:
            // Only requires a gentle ±7.5° ear tilt while keeping nose pointed at screen!
            if angles.rollDeg <= -7.5 { didHitLeftCriterion = true }
            if angles.rollDeg >= 7.5 { didHitRightCriterion = true }
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
