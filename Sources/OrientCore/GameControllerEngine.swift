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
    case gyroHybridTightEdge = "1. Gyro + Tight ±5° Edge Pan (Best All-Rounder)"
    case velocityThumbstick = "2. Velocity Thumbstick (Tilt to Turn, Center to Hold)"
    case microGainAmplified = "3. 6x Micro-Gain (±4° Head = Full Sweep)"
    case faceForwardRollAim = "4. Face-Forward (Roll = Left/Right, Pitch = Up/Down)"

    public var id: String { rawValue }

    public var next: InGameAimStyle {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .gyroHybridTightEdge }
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

/// Phase 3 (Issue #2) Game Controller Engine:
/// Computes 120Hz non-VR camera deltas (`deltaX`, `deltaY`), manages `Q`/`E` Roll tactical leaning
/// with hysteresis, ADS sensitivity slowdown, and emulator touch-drag boundary resets.
public struct GameControllerEngine: Sendable {
    public var injectionProtocol: GameInjectionProtocol = .pubgTacticalLean
    public var aimStyle: InGameAimStyle = .gyroHybridTightEdge
    public var isADSActive: Bool = false
    public var adsMultiplier: Double = 0.50
    public var inGameSensitivityMultiplier: Double = 1.35

    // Tight Non-VR Edge Pan thresholds so user never turns >6 deg away from monitor
    public var tightEdgeYawDeg: Double = 5.0
    public var tightEdgePitchDeg: Double = 4.0
    public var tightEdgePanSpeedPxPerSec: Double = 1350.0

    // Q/E Roll Peek Hysteresis thresholds
    public var leanTriggerAngleDeg: Double = 11.0
    public var leanReleaseAngleDeg: Double = 6.5
    public private(set) var currentLeanState: TacticalLeanState = .upright

    // Emulator Touch-Drag accumulator (resets when virtual finger travels > 280px from anchor)
    public var maxTouchDragRadiusPx: Double = 280.0
    public private(set) var accumulatedTouchDragX: Double = 0.0
    public private(set) var accumulatedTouchDragY: Double = 0.0

    private var prevAmplifiedYawDeg: Double = 0.0
    private var prevAmplifiedPitchDeg: Double = 0.0

    public init() {}

    public mutating func reset() {
        currentLeanState = .upright
        accumulatedTouchDragX = 0
        accumulatedTouchDragY = 0
        prevAmplifiedYawDeg = 0
        prevAmplifiedPitchDeg = 0
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

        // 2. Compute 3D Camera Delta (deltaX, deltaY) according to active Non-VR In-Game Aim Style
        var outDX: Double = 0.0
        var outDY: Double = 0.0

        switch aimStyle {
        case .gyroHybridTightEdge:
            // Center: 1:1 filtered gyro delta; Outside ±5°: continuous camera pan so eyes stay on monitor!
            outDX = baseDeltaX * masterMult
            outDY = baseDeltaY * masterMult

            if abs(angles.yawDeg) > tightEdgeYawDeg {
                let sign = angles.yawDeg >= 0 ? 1.0 : -1.0
                let excessNorm = min(2.0, (abs(angles.yawDeg) - tightEdgeYawDeg) / 6.0)
                outDX += sign * excessNorm * tightEdgePanSpeedPxPerSec * masterMult * clampedDt
            }
            if abs(angles.pitchDeg) > tightEdgePitchDeg {
                let sign = angles.pitchDeg >= 0 ? -1.0 : 1.0 // +pitch (up) -> -Y camera delta
                let excessNorm = min(2.0, (abs(angles.pitchDeg) - tightEdgePitchDeg) / 5.0)
                outDY += sign * excessNorm * tightEdgePanSpeedPxPerSec * masterMult * clampedDt
            }

        case .velocityThumbstick:
            // Smooth spring-centered joystick: tilting >1.5° spins camera; returning to 0° stops on target!
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

        case .microGainAmplified:
            // High-gain amplified gyro delta (2.4x boost over desktop cursor so ±4° sweeps 180° in-game)
            outDX = baseDeltaX * 2.4 * masterMult
            outDY = baseDeltaY * 2.4 * masterMult

        case .faceForwardRollAim:
            // Face stays 100% pointed at monitor; Roll rate/angle steers X, Pitch steers Y
            let rollDeadzone = 2.0
            let speedScale = 1250.0 * masterMult
            if abs(angles.rollDeg) > rollDeadzone {
                let sign = angles.rollDeg >= 0 ? 1.0 : -1.0
                let norm = min(2.0, (abs(angles.rollDeg) - rollDeadzone) / 8.0)
                outDX = sign * norm * speedScale * clampedDt
            }
            outDY = baseDeltaY * 1.8 * masterMult
        }

        // 3. Track Emulator Touch-Drag accumulation and trigger invisible anchor reset before hitting screen edge
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

