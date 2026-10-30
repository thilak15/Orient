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

