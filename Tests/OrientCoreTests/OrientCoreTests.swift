import Testing
import Foundation
@testable import OrientCore

@Suite("OrientCore Signal & Cursor Pipeline Tests")
struct OrientCoreTests {

    @Test("Quaternion roundtrip and relative head pose extraction")
    func testQuaternionHeadAngles() {
        let qRef = Quaternion.fromHeadAnglesDegrees(yawDeg: 15.0, pitchDeg: -5.0, rollDeg: 2.0)
        let qCur = qRef * Quaternion.fromHeadAnglesDegrees(yawDeg: 20.0, pitchDeg: 10.0, rollDeg: -16.0)
        let rel = qCur.relative(to: qRef).toHeadAnglesDegrees()

        #expect(abs(rel.yawDeg - 20.0) < 0.25)
        #expect(abs(rel.pitchDeg - 10.0) < 0.25)
        #expect(abs(rel.rollDeg - (-16.0)) < 0.25)
    }

    @Test("1-Euro filter attenuates static micro-jitter while preserving fast flicks")
    func testOneEuroFilterAdaptiveBehavior() {
        var filter = OneEuroFilter1D(minCutoff: 1.5, beta: 0.1, derivativeCutoff: 1.0)
        var t: TimeInterval = 0.0

        // Feed small resting tremor (+/- 0.8 deg/s)
        var tremorOutputs: [Double] = []
        for i in 0..<20 {
            t += 0.01
            let noisy = (i % 2 == 0) ? 0.8 : -0.8
            tremorOutputs.append(filter.filter(noisy, timestamp: t))
        }
        let maxFilteredTremor = tremorOutputs.suffix(10).map { abs($0) }.max() ?? 1.0
        #expect(maxFilteredTremor < 0.45)

        // Now feed a fast 150 deg/s flick — adaptive beta should track rapidly with low lag
        t += 0.01
        let flickOut = filter.filter(150.0, timestamp: t)
        #expect(flickOut > 110.0)
        #expect(filter.lastEstimatedLagMs < 4.0)
    }

    @Test("Hybrid CursorPipeline: 1:1 center gyro delta + edge continuous pan")
    func testHybridCursorMovement() {
        var config = OrientConfiguration()
        config.edgeYawThresholdDeg = 20.0
        let pipeline = CursorPipeline(config: config)
        let bounds = Rect2D(minX: 0, minY: 0, maxX: 1920, maxY: 1080)
        var cursor = Point2D(x: 960, y: 540)

        // Anchor neutral pose at t=1.0
        pipeline.ingestSample(IMUSample(
            timestamp: 1.0,
            attitude: .identity,
            rotationRate: .zero,
            userAcceleration: .zero
        ))

        // Rotate head right at 40 deg/s (-Z in CoreMotion) within center zone (yaw = 8 deg)
        let deg2rad = Double.pi / 180.0
        pipeline.ingestSample(IMUSample(
            timestamp: 1.01,
            attitude: Quaternion.fromHeadAnglesDegrees(yawDeg: 8.0, pitchDeg: 0, rollDeg: 0),
            rotationRate: Vector3(x: 0, y: 0, z: -40.0 * deg2rad),
            userAcceleration: .zero
        ))

        let step1 = pipeline.step120Hz(timestamp: 1.012, currentCursor: cursor, screenBounds: bounds)
        #expect(step1.shouldMoveCursor)
        #expect(step1.deltaX > 0)
        #expect(!pipeline.telemetry.isInEdgePanZone)
        cursor = step1.targetPosition

        // Hold head stationary in Edge Zone (yaw = 30 deg > 20 deg threshold, rotationRate = 0)
        pipeline.ingestSample(IMUSample(
            timestamp: 1.03,
            attitude: Quaternion.fromHeadAnglesDegrees(yawDeg: 30.0, pitchDeg: 0, rollDeg: 0),
            rotationRate: .zero,
            userAcceleration: .zero
        ))
        let stepEdge = pipeline.step120Hz(timestamp: 1.035, currentCursor: cursor, screenBounds: bounds)
        #expect(pipeline.telemetry.isInEdgePanZone)
        #expect(stepEdge.deltaX > 0)
    }

    @Test("Click Gesture triggers Aim-Freeze and Pre-Click Cursor Rollback")
    func testClickGestureAimFreezeAndRollback() {
        var config = OrientConfiguration()
        config.rollTriggerAngleDeg = 14.0
        config.aimFreezeDurationMs = 90.0
        config.preClickRollbackWindowMs = 45.0
        let pipeline = CursorPipeline(config: config)
        let bounds = Rect2D(minX: 0, minY: 0, maxX: 1920, maxY: 1080)

        // t=0.0: Neutral at target button (500, 500)
        pipeline.ingestSample(IMUSample(timestamp: 0.0, attitude: .identity, rotationRate: .zero, userAcceleration: .zero))
        _ = pipeline.step120Hz(timestamp: 0.01, currentCursor: Point2D(x: 500, y: 500), screenBounds: bounds)

        // t=0.04: Slight unwanted cursor drift to (518, 512) right as user starts tilting head to click
        _ = pipeline.step120Hz(timestamp: 0.04, currentCursor: Point2D(x: 518, y: 512), screenBounds: bounds)

        // t=0.06: Roll Left crosses -16 deg -> triggers Left Click + Aim Freeze + Rollback to t<=0.015 (500, 500)
        let deg2rad = Double.pi / 180.0
        pipeline.ingestSample(IMUSample(
            timestamp: 0.06,
            attitude: Quaternion.fromHeadAnglesDegrees(yawDeg: 2.0, pitchDeg: 1.0, rollDeg: -16.0),
            rotationRate: Vector3(x: 20.0 * deg2rad, y: 0, z: -25.0 * deg2rad),
            userAcceleration: .zero
        ))

        let clickFrame = pipeline.step120Hz(timestamp: 0.062, currentCursor: Point2D(x: 518, y: 512), screenBounds: bounds)
        #expect(clickFrame.triggeredGesture?.action == .leftClick)
        #expect(clickFrame.rollbackPositionForClick == Point2D(x: 500, y: 500))
        #expect(pipeline.telemetry.isAimFrozen)

        // Subsequent frame at t=0.08 (within 90ms freeze window) must not move cursor despite nonzero rotationRate
        let frozenFrame = pipeline.step120Hz(timestamp: 0.08, currentCursor: Point2D(x: 500, y: 500), screenBounds: bounds)
        #expect(frozenFrame.deltaX == 0)
        #expect(frozenFrame.deltaY == 0)
    }

    @Test("Safety auto-pause engages when looking >75 degrees away from monitor")
    func testSafetyAutoPauseAndClutchRecenter() {
        let pipeline = CursorPipeline()
        let bounds = Rect2D(minX: 0, minY: 0, maxX: 1920, maxY: 1080)

        pipeline.ingestSample(IMUSample(timestamp: 0.0, attitude: .identity, rotationRate: .zero, userAcceleration: .zero))

        // Turn head 82 degrees away
        let deg2rad = Double.pi / 180.0
        pipeline.ingestSample(IMUSample(
            timestamp: 0.02,
            attitude: Quaternion.fromHeadAnglesDegrees(yawDeg: 82.0, pitchDeg: 0, rollDeg: 0),
            rotationRate: Vector3(x: 0, y: 0, z: -50.0 * deg2rad),
            userAcceleration: .zero
        ))

        let frame = pipeline.step120Hz(timestamp: 0.025, currentCursor: Point2D(x: 800, y: 400), screenBounds: bounds)
        #expect(pipeline.telemetry.isSafetyPaused)
        #expect(!frame.shouldMoveCursor)

        // Holding and releasing Clutch re-centers neutral pose to the new angle
        pipeline.isClutchHeld = true
        pipeline.isClutchHeld = false
        #expect(abs(pipeline.relativeAngles.yawDeg) < 0.01)
    }
}

