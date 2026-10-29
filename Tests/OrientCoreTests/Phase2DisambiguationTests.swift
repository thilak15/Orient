import Testing
import Foundation
@testable import OrientCore

@Suite("Phase 2: 6-DOF Motion Disambiguation & 3D Calibration Tests")
struct Phase2DisambiguationTests {

    @Test("Seam 1: MotionClassifier distinguishes Yaw, Pitch, Roll, and subtracts neck lever-arm acceleration")
    func testMotionClassifierWithLeverArmCompensation() {
        let classifier = MotionClassifier(leverArmRadiusMeters: 0.085)
        let deg2rad = Double.pi / 180.0

        // 1. Stationary within resting noise floor
        let s0 = IMUSample(
            timestamp: 1.0,
            attitude: .identity,
            rotationRate: Vector3(x: 0.2 * deg2rad, y: -0.1 * deg2rad, z: 0.3 * deg2rad),
            userAcceleration: Vector3(x: 0.01, y: -0.01, z: 0.01)
        )
        let res0 = classifier.analyze(sample: s0, previousSample: nil, relativeAngles: .zero)
        #expect(res0.kind == .stationary)

        // 2. Fast Pure Yaw whip (from 0 to 180 deg/s in 0.02s -> angular accel alpha_z = 9000 deg/s^2 = 157 rad/s^2)
        // With r = 0.085m, tangential/centripetal acceleration at the ear is ~1.36G!
        // Without lever-arm compensation this would falsely trigger a Linear Translation impulse.
        let prevYawSample = IMUSample(
            timestamp: 1.00,
            attitude: .identity,
            rotationRate: Vector3(x: 0, y: 0, z: -20.0 * deg2rad),
            userAcceleration: .zero
        )
        let omegaZ = -180.0 * deg2rad
        let alphaZ = (omegaZ - (-20.0 * deg2rad)) / 0.02
        let r = 0.085
        let g = 9.80665
        // Induced ear acceleration from neck pivot rotation: a_tangential = alphaZ * r, a_centripetal = omegaZ^2 * r
        let inducedEarAccelG = Vector3(
            x: -(omegaZ * omegaZ * r) / g,
            y: (alphaZ * r) / g,
            z: 0
        )

        let fastYawSample = IMUSample(
            timestamp: 1.02,
            attitude: Quaternion.fromHeadAnglesDegrees(yawDeg: 12.0, pitchDeg: 0, rollDeg: 0),
            rotationRate: Vector3(x: 1.0 * deg2rad, y: 0.5 * deg2rad, z: omegaZ),
            userAcceleration: inducedEarAccelG
        )

        let resYaw = classifier.analyze(
            sample: fastYawSample,
            previousSample: prevYawSample,
            relativeAngles: HeadAngles(yawDeg: 12.0, pitchDeg: 0, rollDeg: 0)
        )
        #expect(resYaw.kind == .pureYaw)
        #expect(resYaw.compensatedLinearAccel.magnitude < 0.20)
        #expect(resYaw.axisPurityPercent > 90.0)

        // 3. Pure Roll Tilt (Ear-to-Shoulder)
        let rollSample = IMUSample(
            timestamp: 1.04,
            attitude: Quaternion.fromHeadAnglesDegrees(yawDeg: 0.5, pitchDeg: -0.5, rollDeg: 16.0),
            rotationRate: Vector3(x: 1.0 * deg2rad, y: 55.0 * deg2rad, z: -1.5 * deg2rad),
            userAcceleration: .zero
        )
        let resRoll = classifier.analyze(
            sample: rollSample,
            previousSample: nil,
            relativeAngles: HeadAngles(yawDeg: 0.5, pitchDeg: -0.5, rollDeg: 16.0)
        )
        #expect(resRoll.kind == .pureRoll)
        #expect(resRoll.axisPurityPercent > 90.0)

        // 4. True Physical Head Translation (Forward thrust with minimal rotation)
        let transSample = IMUSample(
            timestamp: 1.06,
            attitude: .identity,
            rotationRate: Vector3(x: 2.0 * deg2rad, y: 1.0 * deg2rad, z: -1.0 * deg2rad),
            userAcceleration: Vector3(x: 0.02, y: 0.68, z: -0.10)
        )
        let resTrans = classifier.analyze(
            sample: transSample,
            previousSample: s0,
            relativeAngles: .zero
        )
        #expect(resTrans.kind == .linearTranslation)
        #expect(resTrans.compensatedLinearAccel.magnitude > 0.55)
    }

    @Test("Seam 2: CrossAxisCalibrator learns anatomical Roll bleed and reduces cursor drift during Roll tilts by >70%")
    func testCrossAxisRollDecouplingReducesCursorDrift() {
        let deg2rad = Double.pi / 180.0
        // Simulate a user whose neck pivot couples +22% of Roll velocity into rightward Yaw and -15% into Pitch
        let bleedYawRatio = 0.22
        let bleedPitchRatio = -0.15

        var calibrationSamples: [IMUSample] = []
        for i in 1...30 {
            let t = Double(i) * 0.015
            let rollRateDeg = 65.0 * sin(Double(i) * 0.3)
            let coupledYawRateDeg = bleedYawRatio * rollRateDeg + (i % 2 == 0 ? 0.4 : -0.4)
            let coupledPitchRateDeg = bleedPitchRatio * rollRateDeg + (i % 2 == 0 ? -0.3 : 0.3)

            calibrationSamples.append(IMUSample(
                timestamp: t,
                attitude: Quaternion.fromHeadAnglesDegrees(
                    yawDeg: coupledYawRateDeg * 0.05,
                    pitchDeg: coupledPitchRateDeg * 0.05,
                    rollDeg: rollRateDeg * 0.2
                ),
                rotationRate: Vector3(
                    x: coupledPitchRateDeg * deg2rad,
                    y: rollRateDeg * deg2rad,
                    z: -coupledYawRateDeg * deg2rad
                ),
                userAcceleration: .zero
            ))
        }

        let matrix = CrossAxisCalibrator.calibrateFromRollSamples(calibrationSamples)
        #expect(abs(matrix.rollToYawCoupling - bleedYawRatio) < 0.03)
        #expect(abs(matrix.rollToPitchCoupling - bleedPitchRatio) < 0.03)

        // Compare cursor drift during a Roll tilt before vs. after applying the calibrated matrix in CursorPipeline
        let uncalibratedPipeline = CursorPipeline()
        var calibratedConfig = OrientConfiguration()
        calibratedConfig.decouplingMatrix = matrix
        let calibratedPipeline = CursorPipeline(config: calibratedConfig)

        let bounds = Rect2D(minX: 0, minY: 0, maxX: 1920, maxY: 1080)
        var uncalCursor = Point2D(x: 960, y: 540)
        var calCursor = Point2D(x: 960, y: 540)

        uncalibratedPipeline.ingestSample(IMUSample(timestamp: 0, attitude: .identity, rotationRate: .zero, userAcceleration: .zero))
        calibratedPipeline.ingestSample(IMUSample(timestamp: 0, attitude: .identity, rotationRate: .zero, userAcceleration: .zero))

        for sample in calibrationSamples {
            uncalibratedPipeline.ingestSample(sample)
            calibratedPipeline.ingestSample(sample)
            let f1 = uncalibratedPipeline.step120Hz(timestamp: sample.timestamp + 0.004, currentCursor: uncalCursor, screenBounds: bounds)
            let f2 = calibratedPipeline.step120Hz(timestamp: sample.timestamp + 0.004, currentCursor: calCursor, screenBounds: bounds)
            uncalCursor = f1.targetPosition
            calCursor = f2.targetPosition
        }

        let uncalDrift = hypot(uncalCursor.x - 960.0, uncalCursor.y - 540.0)
        let calDrift = hypot(calCursor.x - 960.0, calCursor.y - 540.0)
        #expect(uncalDrift > 8.0)
        #expect(calDrift < uncalDrift * 0.30) // >70% drift reduction
    }

    @Test("Seam 3: DiagnosticBenchmarkEngine evaluates Cover-Peek occlusion, 360 Dome targets, and Whip Drift")
    func testDiagnosticBenchmarkEngineModes() {
        var engine = DiagnosticBenchmarkEngine()

        // 1. Cover-Peek & Crouch/Jump Mode: target directly behind pillar (azimuth 0, elevation 0) is occluded when upright (roll = 0)
        engine.mode = .coverPeekAndJump
        engine.targetAzimuthDeg = 0.0
        engine.targetElevationDeg = 0.0

        var snapUpright = TelemetrySnapshot()
        snapUpright.relativeAngles = HeadAngles(yawDeg: 0, pitchDeg: 0, rollDeg: 0)
        engine.update(telemetry: snapUpright, dt: 0.016)
        #expect(engine.isLineOfSightBlockedByCover == true)
        #expect(engine.isCrosshairOn3DTarget == false)

        // Now Roll Right (+20 deg) to peek around the right edge of the cover pillar while aiming at target (0, 0)
        var snapPeekRight = TelemetrySnapshot()
        snapPeekRight.relativeAngles = HeadAngles(yawDeg: 0, pitchDeg: 0, rollDeg: 20.0)
        for _ in 0..<15 {
            engine.update(telemetry: snapPeekRight, dt: 0.016)
        }
        #expect(engine.lateralPeekMeters > 0.38)
        #expect(engine.isLineOfSightBlockedByCover == false)
        #expect(engine.isCrosshairOn3DTarget == true)

        // 2. Whip & Quaternion Return-to-Center Drift Mode
        engine.mode = .whipDriftTest
        engine.resetCurrentMode()

        var whipSnap = TelemetrySnapshot()
        whipSnap.relativeAngles = HeadAngles(yawDeg: 38.0, pitchDeg: 5.0, rollDeg: 0)
        whipSnap.filteredYawRateDegPerSec = 185.0
        whipSnap.motionClassification = MotionClassification(
            kind: .pureYaw,
            compensatedLinearAccel: .zero,
            inducedRotationalAccel: .zero,
            axisPurityPercent: 95.0,
            dominantRotationalSpeedDegPerSec: 185.0
        )
        engine.update(telemetry: whipSnap, dt: 0.016)
        #expect(engine.hasCompletedWhipExcursion == true)
        #expect(engine.peakWhipSpeedDegPerSec >= 185.0)

        // Return to physical center with 0.8 deg residual quaternion drift and settle
        var returnSnap = TelemetrySnapshot()
        returnSnap.relativeAngles = HeadAngles(yawDeg: 0.8, pitchDeg: 0.0, rollDeg: 0)
        returnSnap.filteredYawRateDegPerSec = 0.2
        returnSnap.motionClassification = .idle
        for _ in 0..<20 {
            engine.update(telemetry: returnSnap, dt: 0.02)
        }
        #expect(engine.measuredReturnDriftDeg != nil)
        #expect(abs((engine.measuredReturnDriftDeg ?? 99.0) - 0.8) < 0.05)
    }
}
