import Foundation

/// Selectable external game injection protocols for Phase 3 (Issue #2).
public enum GameInjectionProtocol: String, CaseIterable, Sendable, Codable, Identifiable {
    case pointerLockRawDelta = "3D FPS Pointer-Lock (Raw Delta + Cursor)"
    case pubgTacticalLean = "PUBG Tactical (Raw Delta + Q/E Roll Peek)"
    case emulatorTouchDrag = "Mobile Emulator Touch-Drag (BlueStacks)"

    public var id: String { rawValue }
}

/// Selectable in-game aiming paradigms designed for Non-VR flat screens.
/// Can be cycled live while inside a game using `Option + M` (`⌥M`).
public enum InGameAimStyle: String, CaseIterable, Sendable, Codable, Identifiable {
    case microGainAmplified = "1. Accela 6x Micro-Gain + Auto-Ratchet Turn (Recommended)"
    case gyroHybridTightEdge = "2. Hybrid Gyro + ±5.5° Edge Spin + Auto-Ratchet"
    case velocityThumbstick = "3. Velocity Thumbstick (Tilt to Turn, Center to Hold)"
    case faceForwardRollAim = "4. Face-Forward (Roll = Left/Right, Pitch = Up/Down)"

    public var id: String { rawValue }

    public var next: InGameAimStyle {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .microGainAmplified }
        return all[(idx + 1) % all.count]
    }
}

public enum TacticalLeanState: String, Sendable, Equatable, Codable {
    case upright = "Upright"
    case leanLeftQ = "Q (Peek Left)"
    case leanRightE = "E (Peek Right)"
}

/// Output of a 120Hz game controller tick, including raw camera deltas and Q/E key transitions.
public struct GameFrameCommand: Sendable, Equatable {
    public var deltaX: Double
    public var deltaY: Double
    public var leanStateChangedTo: TacticalLeanState?
    public var currentLeanState: TacticalLeanState
    public var shouldResetTouchDragAnchor: Bool

    public init(
        deltaX: Double,
        deltaY: Double,
        leanStateChangedTo: TacticalLeanState? = nil,
        currentLeanState: TacticalLeanState = .upright,
        shouldResetTouchDragAnchor: Bool = false
    ) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.leanStateChangedTo = leanStateChangedTo
        self.currentLeanState = currentLeanState
        self.shouldResetTouchDragAnchor = shouldResetTouchDragAnchor
    }
}

/// Research-Backed Non-VR 3D FPS Game Controller Engine:
/// - **Auto-Ratchet Turn-Commit (Yaw)**: Turning your head left/right (> `ratchetTurnThresholdDeg` = 1.5°) rotates the 3D camera
///   into the new direction (with 6x Accela gain + continuous spin past 3.8°), and bringing your head back to normal center (0°)
///   automatically clutches (`ΔX = 0`) so your character STAYS facing the new direction! You can pump/ratchet or hold to turn 360°+
///   while keeping your eyes on the monitor. Inside ±1.5°, aiming is 100% bidirectional for fine crosshair tracking.
/// - **Closed-Loop Horizon Lock (Pitch)**: Vertical Pitch (`Y`) is closed-loop synchronized (`ΔY = TargetCamY(θ_pitch) - virtualCameraY`),
///   so returning your head to level posture or pressing `Recenter (⌥R)` physically snaps the in-game screen back to the level horizon!
public struct GameControllerEngine: Sendable {
    public var injectionProtocol: GameInjectionProtocol = .pubgTacticalLean
    public var aimStyle: InGameAimStyle = .microGainAmplified
    public var isADSActive: Bool = false
    public var adsMultiplier: Double = 0.45
    public var inGameSensitivityMultiplier: Double = 1.25

    // Research-Backed Accela 6x Micro-Gain + Auto-Ratchet Turn Parameters
    public var autoRatchetYawEnabled: Bool = true
    public var ratchetTurnThresholdDeg: Double = 1.50
    public var outerContinuousTurnAngleDeg: Double = 3.80
    public var microGainFactor: Double = 6.2
    public var fovealRadiusDeg: Double = 1.25
    public var nonLinearCurveExponent: Double = 1.60
    public var verticalPitchRatio: Double = 0.55
    public var chinDipSuppressionStrength: Double = 0.72
    public var fovealTremorDeadbandDeg: Double = 0.05

    // Tight Non-VR Edge Pan thresholds for Hybrid 360° spin mode
    public var tightEdgeYawDeg: Double = 5.5
    public var tightEdgePitchDeg: Double = 4.5
    public var tightEdgePanSpeedPxPerSec: Double = 1350.0

    // Q/E Roll Peek Hysteresis thresholds
    public var leanTriggerAngleDeg: Double = 11.0
    public var leanReleaseAngleDeg: Double = 6.5
    public private(set) var currentLeanState: TacticalLeanState = .upright

    // Emulator Touch-Drag accumulator (resets when virtual finger travels > 280px from anchor)
    public var maxTouchDragRadiusPx: Double = 280.0
    public private(set) var accumulatedTouchDragX: Double = 0.0
    public private(set) var accumulatedTouchDragY: Double = 0.0

    // Closed-Loop Virtual Camera Displacement State (in pixels from centered horizon)
    public private(set) var virtualCameraX: Double = 0.0
    public private(set) var virtualCameraY: Double = 0.0
    private var continuousEdgeTurnOffsetX: Double = 0.0

    // Auto-Ratchet Yaw State Machine
    public private(set) var isRatchetingReturnToCenter: Bool = false
    private var prevSmoothedYawDeg: Double = 0.0
    private var peakTurnYawDeg: Double = 0.0
    private var uncommittedFovealYawPx: Double = 0.0

    // Velocity-Adaptive Smoothed Pose State
    private var smoothedYawDeg: Double = 0.0
    private var smoothedPitchDeg: Double = 0.0
    private var hasInitializedPose: Bool = false

    public init() {}

    /// Resets all state when tracking is turned OFF (`⌥Space`).
    public mutating func reset() {
        currentLeanState = .upright
        accumulatedTouchDragX = 0
        accumulatedTouchDragY = 0
        virtualCameraX = 0
        virtualCameraY = 0
        continuousEdgeTurnOffsetX = 0
        isRatchetingReturnToCenter = false
        prevSmoothedYawDeg = 0
        peakTurnYawDeg = 0
        uncommittedFovealYawPx = 0
        smoothedYawDeg = 0
        smoothedPitchDeg = 0
        hasInitializedPose = false
    }

    /// Called when the user presses `Recenter (⌥R)` while tracking is active:
    /// - Vertically (`Y` / Pitch): Preserves `virtualCameraY` while zeroing `smoothedPitchDeg`, so the next ticks inject
    ///   `-virtualCameraY` to physically bring the in-game screen back to the level horizon!
    /// - Horizontally (`X` / Yaw): Keeps committed body turns intact while snapping any uncommitted offset back to center.
    public mutating func onRecenterPressed() {
        smoothedYawDeg = 0.0
        smoothedPitchDeg = 0.0
        prevSmoothedYawDeg = 0.0
        peakTurnYawDeg = 0.0
        isRatchetingReturnToCenter = false
        continuousEdgeTurnOffsetX = 0.0
        if autoRatchetYawEnabled && (aimStyle == .microGainAmplified || aimStyle == .gyroHybridTightEdge) {
            // Only snap back uncommitted foveal offset so committed hallway turns stay facing the new direction
            virtualCameraX = uncommittedFovealYawPx
            uncommittedFovealYawPx = 0.0
        }
    }

    public mutating func step120Hz(
        telemetry: TelemetrySnapshot,
        baseDeltaX: Double,
        baseDeltaY: Double,
        dt: Double
    ) -> GameFrameCommand {
        let clampedDt = max(1.0 / 500.0, min(0.05, dt))
        let angles = telemetry.relativeAngles
        let scopeMult = isADSActive ? adsMultiplier : 1.0
        let masterMult = inGameSensitivityMultiplier * scopeMult

        // 1. Evaluate Q/E Roll Lean state transitions (unless Roll is used for horizontal aiming)
        var leanTransition: TacticalLeanState? = nil
        if injectionProtocol == .pubgTacticalLean && aimStyle != .faceForwardRollAim {
            let nextLean = evaluateLeanHysteresis(rollDeg: angles.rollDeg)
            if nextLean != currentLeanState {
                currentLeanState = nextLean
                leanTransition = nextLean
            }
        } else if currentLeanState != .upright {
            currentLeanState = .upright
            leanTransition = .upright
        }

        if telemetry.isSafetyPaused || telemetry.isClutchHeld || telemetry.isAimFrozen {
            return GameFrameCommand(
                deltaX: 0,
                deltaY: 0,
                leanStateChangedTo: leanTransition,
                currentLeanState: currentLeanState,
                shouldResetTouchDragAnchor: false
            )
        }

        // 2. Velocity-Adaptive Pose Filtering + Cross-Axis Chin-Dip Suppression
        updateSmoothedPose(angles: angles, telemetry: telemetry)

        // 3. Compute 3D Camera Delta (deltaX, deltaY) according to active Non-VR In-Game Aim Style
        var outDX: Double = 0.0
        var outDY: Double = 0.0

        switch aimStyle {
        case .microGainAmplified:
            // Vertical Pitch (Y): 100% Closed-Loop Horizon-Locked so the screen NEVER stays stuck looking at the floor/sky!
            let targetCamY = -evaluateAccelaNonLinearPixels(angleDeg: smoothedPitchDeg, isPitch: true, masterMult: masterMult)
            let rawErrY = targetCamY - virtualCameraY
            let maxStepPerTick = 140.0
            outDY = max(-maxStepPerTick, min(maxStepPerTick, rawErrY))
            virtualCameraY += outDY

            // Horizontal Yaw (X): Auto-Ratchet Turn-Commit + Foveal 6x Micro-Gain
            if autoRatchetYawEnabled {
                outDX = stepAutoRatchetYaw(masterMult: masterMult, dt: clampedDt)
                virtualCameraX += outDX
            } else {
                let targetCamX = evaluateAccelaNonLinearPixels(angleDeg: smoothedYawDeg, isPitch: false, masterMult: masterMult)
                let rawErrX = targetCamX - virtualCameraX
                outDX = max(-maxStepPerTick, min(maxStepPerTick, rawErrX))
                virtualCameraX += outDX
            }

        case .gyroHybridTightEdge:
            // Vertical Pitch (Y): Closed-Loop Horizon-Locked + base gyro delta
            let targetCamY = -evaluateAccelaNonLinearPixels(angleDeg: smoothedPitchDeg, isPitch: true, masterMult: masterMult)
            let rawErrY = (targetCamY - virtualCameraY) + baseDeltaY * masterMult
            let maxStepPerTick = 140.0
            outDY = max(-maxStepPerTick, min(maxStepPerTick, rawErrY))
            virtualCameraY += (outDY - baseDeltaY * masterMult)

            // Horizontal Yaw (X): Hybrid Gyro + ±tightEdgeYawDeg Continuous Spin + Auto-Ratchet Return-Clutch
            if autoRatchetYawEnabled {
                let ratchetStepX = stepAutoRatchetYaw(masterMult: masterMult, dt: clampedDt)
                if isRatchetingReturnToCenter {
                    // Returning head to monitor center -> clutch BOTH position and base gyro delta so zero pull-back occurs!
                    outDX = 0.0
                } else {
                    outDX = max(-maxStepPerTick, min(maxStepPerTick, ratchetStepX + baseDeltaX * masterMult))
                    virtualCameraX += outDX
                }
            } else {
                if abs(smoothedYawDeg) > tightEdgeYawDeg && abs(baseDeltaX) >= 0 {
                    let sign = smoothedYawDeg >= 0 ? 1.0 : -1.0
                    let excessNorm = min(2.0, (abs(smoothedYawDeg) - tightEdgeYawDeg) / 5.0)
                    continuousEdgeTurnOffsetX += sign * excessNorm * tightEdgePanSpeedPxPerSec * masterMult * clampedDt
                }
                let clampedCenterYaw = max(-tightEdgeYawDeg, min(tightEdgeYawDeg, smoothedYawDeg))
                let targetCamX = evaluateAccelaNonLinearPixels(angleDeg: clampedCenterYaw, isPitch: false, masterMult: masterMult) + continuousEdgeTurnOffsetX
                let rawErrX = (targetCamX - virtualCameraX) + baseDeltaX * masterMult
                outDX = max(-maxStepPerTick, min(maxStepPerTick, rawErrX))
                virtualCameraX += (outDX - baseDeltaX * masterMult)
            }

        case .velocityThumbstick:
            // Smooth spring-centered joystick: tilting >1.4° spins camera; returning to 0° holds new direction!
            let deadzoneYaw = 1.4
            let deadzonePitch = 1.1
            let maxSpeedPxPerSec = 1400.0 * masterMult

            if abs(angles.yawDeg) > deadzoneYaw {
                let sign = angles.yawDeg >= 0 ? 1.0 : -1.0
                let norm = min(2.2, pow((abs(angles.yawDeg) - deadzoneYaw) / 6.0, 1.35))
                outDX = sign * norm * maxSpeedPxPerSec * clampedDt
            }
            if abs(angles.pitchDeg) > deadzonePitch {
                let sign = angles.pitchDeg >= 0 ? -1.0 : 1.0
                let norm = min(2.2, pow((abs(angles.pitchDeg) - deadzonePitch) / 4.5, 1.35))
                outDY = sign * norm * maxSpeedPxPerSec * clampedDt
            }
            virtualCameraX += outDX
            virtualCameraY += outDY

        case .faceForwardRollAim:
            // Face stays 100% pointed at monitor; Roll steers X, Closed-Loop Pitch steers Y
            let rollDeadzone = 2.0
            let speedScale = 1250.0 * masterMult
            if abs(angles.rollDeg) > rollDeadzone {
                let sign = angles.rollDeg >= 0 ? 1.0 : -1.0
                let norm = min(2.0, (abs(angles.rollDeg) - rollDeadzone) / 8.0)
                outDX = sign * norm * speedScale * clampedDt
            }
            let targetCamY = -evaluateAccelaNonLinearPixels(angleDeg: smoothedPitchDeg, isPitch: true, masterMult: masterMult)
            let rawErrY = targetCamY - virtualCameraY
            outDY = max(-140.0, min(140.0, rawErrY))
            virtualCameraX += outDX
            virtualCameraY += outDY
        }

        // 4. Track Emulator Touch-Drag accumulation and trigger invisible anchor reset before hitting screen edge
        var needsTouchReset = false
        if injectionProtocol == .emulatorTouchDrag {
            accumulatedTouchDragX += outDX
            accumulatedTouchDragY += outDY
            if hypot(accumulatedTouchDragX, accumulatedTouchDragY) >= maxTouchDragRadiusPx {
                needsTouchReset = true
                accumulatedTouchDragX = 0
                accumulatedTouchDragY = 0
            }
        }

        return GameFrameCommand(
            deltaX: outDX,
            deltaY: outDY,
            leanStateChangedTo: leanTransition,
            currentLeanState: currentLeanState,
            shouldResetTouchDragAnchor: needsTouchReset
        )
    }

    // MARK: - Auto-Ratchet Turn-Commit + Foveal Bidirectional 6x Micro-Gain State Machine

    private mutating func stepAutoRatchetYaw(masterMult: Double, dt: Double) -> Double {
        let curYaw = smoothedYawDeg
        let prevYaw = prevSmoothedYawDeg
        prevSmoothedYawDeg = curYaw

        let absCur = abs(curYaw)
        let absPrev = abs(prevYaw)
        let crossedCenter = (curYaw * prevYaw < 0.0)

        if crossedCenter {
            isRatchetingReturnToCenter = false
            peakTurnYawDeg = curYaw
        }

        // If moving outward (away from monitor center 0°)
        if absCur > absPrev {
            if isRatchetingReturnToCenter && absPrev <= 0.5 {
                // Completed return to center and now starting a fresh outward turn
                peakTurnYawDeg = curYaw
            }
            isRatchetingReturnToCenter = false
            if absCur > abs(peakTurnYawDeg) {
                peakTurnYawDeg = curYaw
            }
        } else if absCur < absPrev {
            // Moving inward toward monitor center (0°):
            // If this excursion exceeded `ratchetTurnThresholdDeg` (1.5°), clutch the ENTIRE return stroke to 0°!
            if abs(peakTurnYawDeg) > ratchetTurnThresholdDeg {
                isRatchetingReturnToCenter = true
                uncommittedFovealYawPx = 0.0
                return 0.0
            }
        } else if isRatchetingReturnToCenter {
            return 0.0
        }

        // Compute Incremental Accela 6x Micro-Gain Delta
        let curPosPx = evaluateAccelaNonLinearPixels(angleDeg: curYaw, isPitch: false, masterMult: masterMult)
        let prevPosPx = evaluateAccelaNonLinearPixels(angleDeg: prevYaw, isPitch: false, masterMult: masterMult)
        var stepDX = curPosPx - prevPosPx

        // Also add smooth continuous outer spin when holding head past `outerContinuousTurnAngleDeg` (3.8°)
        // so the player can sweep 90°–360° without ever turning their head more than ~4°!
        if absCur > outerContinuousTurnAngleDeg {
            let sign = curYaw >= 0 ? 1.0 : -1.0
            let excessNorm = min(2.2, (absCur - outerContinuousTurnAngleDeg) / 4.0)
            stepDX += sign * excessNorm * tightEdgePanSpeedPxPerSec * masterMult * dt
            uncommittedFovealYawPx = 0.0
        } else if absCur <= ratchetTurnThresholdDeg {
            uncommittedFovealYawPx += stepDX
        } else {
            uncommittedFovealYawPx = 0.0
        }

        return max(-140.0, min(140.0, stepDX))
    }

    // MARK: - TrackIR / Opentrack Accela 3-Zone Non-Linear Spline & Anti-Tremor Filter

    private mutating func updateSmoothedPose(angles: HeadAngles, telemetry: TelemetrySnapshot) {
        if !hasInitializedPose {
            smoothedYawDeg = angles.yawDeg
            smoothedPitchDeg = angles.pitchDeg
            prevSmoothedYawDeg = angles.yawDeg
            hasInitializedPose = true
            return
        }

        let yawSpeed = abs(telemetry.filteredYawRateDegPerSec)
        let pitchSpeed = abs(telemetry.filteredPitchRateDegPerSec)
        let totalSpeed = hypot(yawSpeed, pitchSpeed)

        // Velocity-gated smoothing factor:
        // Low speed (< 4 deg/s): strong stabilization (alpha = 0.22) + deadband to lock crosshair on headshots
        // High speed (> 18 deg/s): instant response (alpha = 0.88) for zero-lag flicks
        let speedNorm = min(1.0, max(0.0, (totalSpeed - 2.5) / 16.0))
        let alpha = 0.22 + 0.66 * speedNorm

        let dYaw = angles.yawDeg - smoothedYawDeg
        if abs(dYaw) > fovealTremorDeadbandDeg || totalSpeed > 4.0 {
            smoothedYawDeg += alpha * dYaw
        }

        // Cross-Axis Dominant-Yaw Pitch Suppression (prevents anatomical chin-dip during fast horizontal flicks)
        var pitchAlpha = alpha
        if yawSpeed > 12.0 && yawSpeed > 1.8 * max(1.0, pitchSpeed) {
            let dominance = min(1.0, (yawSpeed / max(1.0, pitchSpeed) - 1.8) / 3.0)
            let suppression = 1.0 - (chinDipSuppressionStrength * dominance)
            pitchAlpha *= max(0.12, suppression)
        }

        let dPitch = angles.pitchDeg - smoothedPitchDeg
        if abs(dPitch) > fovealTremorDeadbandDeg || totalSpeed > 4.0 {
            smoothedPitchDeg += pitchAlpha * dPitch
        }
    }

    /// Maps physical head angle (deg) through the TrackIR / Opentrack Accela 3-Zone C¹ Spline:
    /// - Zone 1 (0° ..< fovealRadiusDeg): gentle precision gain (~2.4x) for steady headshots
    /// - Zone 2 (fovealRadiusDeg ..< 5.0°): non-linear power ramp up to `microGainFactor` (6.2x)
    /// - Zone 3 (> 5.0°): high outer gain (9x+) for fast 180° turns without looking away from the monitor
    public func evaluateAccelaNonLinearPixels(angleDeg: Double, isPitch: Bool, masterMult: Double) -> Double {
        let absDeg = abs(angleDeg)
        let sign = angleDeg >= 0 ? 1.0 : -1.0
        let axisRatio = isPitch ? verticalPitchRatio : 1.0
        let pxPerVirtualDeg = 22.0 * masterMult * axisRatio

        let r1 = max(0.3, fovealRadiusDeg)
        let g1 = max(1.0, microGainFactor * 0.38)

        // Zone 1: Foveal Precision Pocket
        if absDeg <= r1 {
            let norm = absDeg / r1
            let smoothNorm = norm * (0.48 + 0.52 * norm)
            return sign * (smoothNorm * r1 * g1) * pxPerVirtualDeg
        }

        let baseAtR1 = r1 * g1
        let r2 = max(r1 + 1.0, 5.0)

        // Zone 2: Tactical Combat Cone (1.25° ..< 5.0°)
        if absDeg <= r2 {
            let span = absDeg - r1
            let normSpan = span / (r2 - r1)
            let expPower = max(1.0, nonLinearCurveExponent - 0.25)
            let dynamicMult = g1 + (microGainFactor - g1) * pow(normSpan, expPower)
            let virtualDeg = baseAtR1 + span * dynamicMult
            return sign * virtualDeg * pxPerVirtualDeg
        }

        // Zone 3: Peripheral Wide Flick (> 5.0°)
        let spanZ2 = r2 - r1
        let baseAtR2 = baseAtR1 + spanZ2 * microGainFactor
        let outerSpan = absDeg - r2
        let outerGain = microGainFactor * 1.45
        let virtualDeg = baseAtR2 + outerSpan * outerGain
        return sign * virtualDeg * pxPerVirtualDeg
    }

    private func evaluateLeanHysteresis(rollDeg: Double) -> TacticalLeanState {
        switch currentLeanState {
        case .upright:
            if rollDeg <= -leanTriggerAngleDeg { return .leanLeftQ }
            if rollDeg >= leanTriggerAngleDeg { return .leanRightE }
            return .upright
        case .leanLeftQ:
            if rollDeg >= leanTriggerAngleDeg { return .leanRightE }
            if rollDeg > -leanReleaseAngleDeg { return .upright }
            return .leanLeftQ
        case .leanRightE:
            if rollDeg <= -leanTriggerAngleDeg { return .leanLeftQ }
            if rollDeg < leanReleaseAngleDeg { return .upright }
            return .leanRightE
        }
    }
}
