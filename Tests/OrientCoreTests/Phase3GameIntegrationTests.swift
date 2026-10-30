import Testing
import Foundation
@testable import OrientCore

@Suite("Phase 3: External 3D Game Controller & PUBG Tactical Lean Tests")
struct Phase3GameIntegrationTests {

    @Test("PUBG Tactical Lean hysteresis transitions cleanly between Upright, Q (Left), and E (Right)")
    func testTacticalLeanHysteresis() {
        var game = GameControllerEngine()
        game.injectionProtocol = .pubgTacticalLean
        game.leanTriggerAngleDeg = 11.0
        game.leanReleaseAngleDeg = 6.5

        var snap = TelemetrySnapshot()
        snap.relativeAngles = HeadAngles(yawDeg: 0, pitchDeg: 0, rollDeg: -13.0)
        let cmdLeft = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
        #expect(cmdLeft.leanStateChangedTo == .leanLeftQ)
        #expect(cmdLeft.currentLeanState == .leanLeftQ)

        // Small recovery to -8.0 deg (still beyond -6.5 deg release threshold) keeps Q held
        snap.relativeAngles.rollDeg = -8.0
        let cmdHold = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
        #expect(cmdHold.leanStateChangedTo == nil)
        #expect(cmdHold.currentLeanState == .leanLeftQ)

        // Return upright (-3.0 deg) releases Q
        snap.relativeAngles.rollDeg = -3.0
        let cmdRelease = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
        #expect(cmdRelease.leanStateChangedTo == .upright)
        #expect(cmdRelease.currentLeanState == .upright)
    }

    @Test("Auto-Ratchet Turn-Commit: turning left and returning head to center keeps camera facing left with zero pull-back")
    func testAutoRatchetTurnCommitAndMultiPump() {
        var game = GameControllerEngine()
        game.aimStyle = .microGainAmplified
        game.autoRatchetYawEnabled = true

        var totalInjectedGameX: Double = 0.0
        var snap = TelemetrySnapshot()

        // 1. Start at 0 deg
        snap.relativeAngles = .zero
        _ = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)

        // 2. Turn head Left from 0° -> -3.5°
        let outboundSteps = 15
        for i in 1...outboundSteps {
            let yaw = -3.5 * (Double(i) / Double(outboundSteps))
            snap.relativeAngles = HeadAngles(yawDeg: yaw, pitchDeg: 0, rollDeg: 0)
            snap.filteredYawRateDegPerSec = -25.0
            let cmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
            totalInjectedGameX += cmd.deltaX
        }

        let turnedLeftPositionX = totalInjectedGameX
        #expect(turnedLeftPositionX < -150.0)

        // 3. Bring head back from -3.5° -> 0.0° (normal center looking at monitor)
        let returnSteps = 15
        var pullBackDuringReturn: Double = 0.0
        for i in 1...returnSteps {
            let yaw = -3.5 * (1.0 - Double(i) / Double(returnSteps))
            snap.relativeAngles = HeadAngles(yawDeg: yaw, pitchDeg: 0, rollDeg: 0)
            snap.filteredYawRateDegPerSec = 25.0
            let cmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
            pullBackDuringReturn += cmd.deltaX
            totalInjectedGameX += cmd.deltaX
        }

        // Camera stays facing the new left direction (zero rightward pull-back when head returns to center!)
        #expect(pullBackDuringReturn <= 0.01)
        #expect(totalInjectedGameX <= turnedLeftPositionX)

        // 4. Turn head Left AGAIN from 0° -> -3.5° to turn even further left without twisting neck past -3.5°!
        for i in 1...outboundSteps {
            let yaw = -3.5 * (Double(i) / Double(outboundSteps))
            snap.relativeAngles = HeadAngles(yawDeg: yaw, pitchDeg: 0, rollDeg: 0)
            snap.filteredYawRateDegPerSec = -25.0
            let cmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
            totalInjectedGameX += cmd.deltaX
        }

        #expect(totalInjectedGameX < turnedLeftPositionX * 1.8)
    }

    @Test("Closed-Loop Horizon Pitch snaps in-game vertical view back to 0 when Recenter (⌥R) is pressed")
    func testClosedLoopRecenterSnapsVerticalHorizonBackToCenter() {
        var game = GameControllerEngine()
        game.aimStyle = .microGainAmplified

        var totalInjectedGameY: Double = 0.0

        // 1. User tilts head down (-5 deg)
        var snap = TelemetrySnapshot()
        snap.relativeAngles = HeadAngles(yawDeg: 0.0, pitchDeg: -5.0, rollDeg: 0.0)
        snap.filteredPitchRateDegPerSec = -25.0

        for _ in 0..<25 {
            let cmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
            totalInjectedGameY += cmd.deltaY
        }

        // In-game camera has moved down (+Y)
        #expect(totalInjectedGameY > 100.0)

        // 2. User presses Recenter (⌥R): pipeline resets relativeAngles to (0, 0) and calls onRecenterPressed()
        game.onRecenterPressed()
        snap.relativeAngles = .zero
        snap.filteredPitchRateDegPerSec = 0

        for _ in 0..<10 {
            let cmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 1.0 / 120.0)
            totalInjectedGameY += cmd.deltaY
        }

        // Closed-loop counter-deltas physically return the in-game 3D vertical view to exact 0.0 horizon!
        #expect(abs(totalInjectedGameY) < 0.01)
    }

    @Test("Non-VR Aim Styles: Tight Edge Pan, Velocity Thumbstick, and ADS Slowdown")
    func testNonVRAimStylesAndADSSlowdown() {
        var game = GameControllerEngine()
        game.aimStyle = .velocityThumbstick
        game.inGameSensitivityMultiplier = 1.0
        game.adsMultiplier = 0.5

        var snap = TelemetrySnapshot()
        snap.relativeAngles = HeadAngles(yawDeg: 5.0, pitchDeg: 0, rollDeg: 0)

        let hipfireCmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 0.01)
        #expect(hipfireCmd.deltaX > 0)

        game.isADSActive = true
        let adsCmd = game.step120Hz(telemetry: snap, baseDeltaX: 0, baseDeltaY: 0, dt: 0.01)
        #expect(abs(adsCmd.deltaX - hipfireCmd.deltaX * 0.5) < 0.01)
    }

    @Test("Emulator Touch-Drag mode triggers invisible anchor reset when drag radius is exceeded")
    func testEmulatorTouchDragAnchorReset() {
        var game = GameControllerEngine()
        game.injectionProtocol = .emulatorTouchDrag
        game.aimStyle = .gyroHybridTightEdge
        game.inGameSensitivityMultiplier = 1.0
        game.maxTouchDragRadiusPx = 100.0

        let snap = TelemetrySnapshot()
        let cmd1 = game.step120Hz(telemetry: snap, baseDeltaX: 60.0, baseDeltaY: 0, dt: 0.008)
        #expect(cmd1.shouldResetTouchDragAnchor == false)

        let cmd2 = game.step120Hz(telemetry: snap, baseDeltaX: 55.0, baseDeltaY: 0, dt: 0.008)
        #expect(cmd2.shouldResetTouchDragAnchor == true)
    }
}
