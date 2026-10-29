import Foundation

public struct Point2D: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public static let zero = Point2D(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Rect2D: Sendable, Equatable, Codable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public func clamp(_ point: Point2D) -> Point2D {
        Point2D(
            x: max(minX, min(maxX - 1.0, point.x)),
            y: max(minY, min(maxY - 1.0, point.y))
        )
    }
}

/// Output produced by a 120Hz frame tick of the CursorPipeline.
public struct CursorFrameOutput: Sendable, Equatable {
    public var shouldMoveCursor: Bool
    public var targetPosition: Point2D
    public var deltaX: Double
    public var deltaY: Double
    public var triggeredGesture: TriggeredGesture?
    public var rollbackPositionForClick: Point2D?

    public init(
        shouldMoveCursor: Bool,
        targetPosition: Point2D,
        deltaX: Double,
        deltaY: Double,
        triggeredGesture: TriggeredGesture? = nil,
        rollbackPositionForClick: Point2D? = nil
    ) {
        self.shouldMoveCursor = shouldMoveCursor
        self.targetPosition = targetPosition
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.triggeredGesture = triggeredGesture
        self.rollbackPositionForClick = rollbackPositionForClick
    }
}

/// Live telemetry metrics for the Studio UI and benchmark lab.
public struct TelemetrySnapshot: Sendable, Equatable {
    public var sampleRateHz: Double = 0
    public var packetIntervalMs: Double = 0
    public var filterLagMs: Double = 0
    public var outputRateHz: Double = 0
    public var endToEndLatencyMs: Double = 0
    public var relativeAngles: HeadAngles = .zero
    public var filteredYawRateDegPerSec: Double = 0
    public var filteredPitchRateDegPerSec: Double = 0
    public var rawYawRateDegPerSec: Double = 0
    public var rawPitchRateDegPerSec: Double = 0
    public var accelMagnitudeG: Double = 0
    public var isInEdgePanZone: Bool = false
    public var isAimFrozen: Bool = false
    public var isSafetyPaused: Bool = false
    public var isClutchHeld: Bool = false
    public var isPrecisionModeActive: Bool = false
    public var lastTriggeredGesture: TriggeredGesture?

    public init() {}
}

/// Complete low-latency signal pipeline:
/// CoreMotion IMU Sample -> Quaternion Relative Pose + 1-Euro Filtered Gyro ->
/// Gesture Detection + Pre-Click Rollback + Aim-Freeze -> 120Hz Predictive Upsampler.
public final class CursorPipeline: @unchecked Sendable {
    public var config: OrientConfiguration {
        didSet {
            syncFilterParameters()
        }
    }

    public private(set) var referenceAttitude: Quaternion?
    public private(set) var latestSample: IMUSample?
    public private(set) var relativeAngles: HeadAngles = .zero
    public private(set) var telemetry = TelemetrySnapshot()

    public var isClutchHeld: Bool = false {
        didSet {
            // Releasing the clutch re-anchors the head center pose seamlessly (like setting down a mouse)
            if oldValue == true && isClutchHeld == false {
                recenter()
            }
            telemetry.isClutchHeld = isClutchHeld
        }
    }

    public var isPrecisionModeActive: Bool = false {
        didSet {
            telemetry.isPrecisionModeActive = isPrecisionModeActive
        }
    }

    private var yawFilter: OneEuroFilter1D
    private var pitchFilter: OneEuroFilter1D
    private var gestureDetector = GestureDetector()

    private var filteredYawDegPerSec: Double = 0
    private var filteredPitchDegPerSec: Double = 0
    private var pendingGesture: TriggeredGesture?
    private var aimFreezeUntilTimestamp: TimeInterval = -1.0

    // Sub-pixel residual accumulators
    private var residualX: Double = 0
    private var residualY: Double = 0

    // Timing & telemetry state
    private var lastSampleTimestamp: TimeInterval?
    private var lastStepTimestamp: TimeInterval?
    private var smoothedPacketIntervalMs: Double = 12.0
    private var smoothedStepIntervalMs: Double = 8.33

    // Ring buffer of recent cursor positions for Pre-Click Rollback
    private struct CursorHistoryEntry {
        var timestamp: TimeInterval
        var position: Point2D
    }
    private var cursorHistory: [CursorHistoryEntry] = []
    private let maxHistoryEntries = 90

    public init(config: OrientConfiguration = OrientConfiguration()) {
        self.config = config
        self.yawFilter = OneEuroFilter1D(
            minCutoff: config.oneEuroMinCutoff,
            beta: config.oneEuroBeta,
            derivativeCutoff: config.oneEuroDerivativeCutoff
        )
        self.pitchFilter = OneEuroFilter1D(
            minCutoff: config.oneEuroMinCutoff,
            beta: config.oneEuroBeta,
            derivativeCutoff: config.oneEuroDerivativeCutoff
        )
    }

    private func syncFilterParameters() {
        yawFilter.minCutoff = config.oneEuroMinCutoff
        yawFilter.beta = config.oneEuroBeta
        yawFilter.derivativeCutoff = config.oneEuroDerivativeCutoff

        pitchFilter.minCutoff = config.oneEuroMinCutoff
        pitchFilter.beta = config.oneEuroBeta
        pitchFilter.derivativeCutoff = config.oneEuroDerivativeCutoff
    }

    /// Resets neutral head orientation to the current AirPods attitude.
    public func recenter() {
        if let latest = latestSample {
            referenceAttitude = latest.attitude
            relativeAngles = .zero
            telemetry.relativeAngles = .zero
        } else {
            referenceAttitude = nil
        }
        residualX = 0
        residualY = 0
    }

    /// Ingests an asynchronous IMU packet from CMHeadphoneMotionManager or the simulator.
    public func ingestSample(_ sample: IMUSample) {
        if referenceAttitude == nil {
            referenceAttitude = sample.attitude
        }

        if let prevTime = lastSampleTimestamp {
            let dtMs = max(1.0, min(250.0, (sample.timestamp - prevTime) * 1000.0))
            smoothedPacketIntervalMs = smoothedPacketIntervalMs * 0.82 + dtMs * 0.18
        }
        lastSampleTimestamp = sample.timestamp
        latestSample = sample

        // 1. Compute relative head pose from neutral anchor
        if let ref = referenceAttitude {
            let relQ = sample.attitude.relative(to: ref)
            var angles = relQ.toHeadAnglesDegrees()
            if config.invertYaw { angles.yawDeg = -angles.yawDeg }
            if config.invertPitch { angles.pitchDeg = -angles.pitchDeg }
            relativeAngles = angles
        }

        // 2. Convert gyroscope rotationRate (rad/s) to screen yaw/pitch velocity (deg/s)
        let rad2deg = 180.0 / Double.pi
        let yawSign = config.invertYaw ? 1.0 : -1.0
        let pitchSign = config.invertPitch ? -1.0 : 1.0

        // CoreMotion rotationRate.z: + is counter-clockwise (left), so -z is rightward (+X)
        let rawYawVel = sample.rotationRate.z * yawSign * rad2deg
        // CoreMotion rotationRate.x: + is pitch up, which maps to upward screen motion (-Y in CGEvent coordinates)
        let rawPitchVel = sample.rotationRate.x * pitchSign * rad2deg

        filteredYawDegPerSec = yawFilter.filter(rawYawVel, timestamp: sample.timestamp)
        filteredPitchDegPerSec = pitchFilter.filter(rawPitchVel, timestamp: sample.timestamp)

        // 3. Evaluate gestures (unless clutch is held or safety paused)
        let isSafetyOut = relativeAngles.lookDeviationDeg > config.safetyCutoffAngleDeg
        if !isClutchHeld && !isSafetyOut {
            if let gesture = gestureDetector.evaluate(
                sample: sample,
                relativeAngles: relativeAngles,
                config: config
            ) {
                handleTriggeredGesture(gesture, at: sample.timestamp)
            }
        }

        // 4. Update telemetry
        let filterLag = 0.5 * (yawFilter.lastEstimatedLagMs + pitchFilter.lastEstimatedLagMs)
        telemetry.packetIntervalMs = smoothedPacketIntervalMs
        telemetry.sampleRateHz = smoothedPacketIntervalMs > 0 ? (1000.0 / smoothedPacketIntervalMs) : 0
        telemetry.filterLagMs = filterLag
        telemetry.relativeAngles = relativeAngles
        telemetry.rawYawRateDegPerSec = rawYawVel
        telemetry.rawPitchRateDegPerSec = rawPitchVel
        telemetry.filteredYawRateDegPerSec = filteredYawDegPerSec
        telemetry.filteredPitchRateDegPerSec = filteredPitchDegPerSec
        telemetry.accelMagnitudeG = sample.userAcceleration.magnitude
        telemetry.isSafetyPaused = isSafetyOut
    }

    private func handleTriggeredGesture(_ gesture: TriggeredGesture, at timestamp: TimeInterval) {
        switch gesture.action {
        case .none:
            break
        case .recenter:
            recenter()
            telemetry.lastTriggeredGesture = gesture
        case .togglePrecision:
            isPrecisionModeActive.toggle()
            telemetry.lastTriggeredGesture = gesture
        case .leftClick, .rightClick, .doubleClick:
            // Activate Aim-Freeze window immediately so click impulse doesn't shift aim
            aimFreezeUntilTimestamp = timestamp + (config.aimFreezeDurationMs / 1000.0)
            pendingGesture = gesture
            telemetry.lastTriggeredGesture = gesture
        }
    }

    /// Executes a single high-frequency (120Hz) cursor update tick.
    public func step120Hz(
        timestamp: TimeInterval,
        currentCursor: Point2D,
        screenBounds: Rect2D
    ) -> CursorFrameOutput {
        let dt: Double
        if let prevStep = lastStepTimestamp {
            dt = max(1.0 / 500.0, min(0.05, timestamp - prevStep))
            let stepMs = dt * 1000.0
            smoothedStepIntervalMs = smoothedStepIntervalMs * 0.9 + stepMs * 0.1
        } else {
            dt = 1.0 / 120.0
        }
        lastStepTimestamp = timestamp

        telemetry.outputRateHz = smoothedStepIntervalMs > 0 ? (1000.0 / smoothedStepIntervalMs) : 120.0
        telemetry.endToEndLatencyMs = telemetry.filterLagMs + smoothedStepIntervalMs * 0.5

        // Consume any pending click gesture and look up pre-click rollback position
        let activeGesture = pendingGesture
        pendingGesture = nil

        var rollbackPos: Point2D? = nil
        if activeGesture != nil && config.preClickRollbackWindowMs > 0 {
            let targetHistoryTime = timestamp - (config.preClickRollbackWindowMs / 1000.0)
            rollbackPos = lookupCursorPosition(atOrBefore: targetHistoryTime)
        }

        let isFrozen = timestamp < aimFreezeUntilTimestamp
        telemetry.isAimFrozen = isFrozen

        // Safety, clutch, or no-sample checks
        guard let lastSampleTime = lastSampleTimestamp else {
            return CursorFrameOutput(
                shouldMoveCursor: false,
                targetPosition: currentCursor,
                deltaX: 0,
                deltaY: 0,
                triggeredGesture: activeGesture,
                rollbackPositionForClick: rollbackPos
            )
        }

        let isSafetyOut = relativeAngles.lookDeviationDeg > config.safetyCutoffAngleDeg
        telemetry.isSafetyPaused = isSafetyOut

        if isClutchHeld || isSafetyOut || isFrozen {
            residualX = 0
            residualY = 0
            let effectivePos = rollbackPos ?? currentCursor
            recordHistory(timestamp: timestamp, position: effectivePos)
            return CursorFrameOutput(
                shouldMoveCursor: rollbackPos != nil,
                targetPosition: effectivePos,
                deltaX: 0,
                deltaY: 0,
                triggeredGesture: activeGesture,
                rollbackPositionForClick: rollbackPos
            )
        }

        // Predictive dead-reckoning decay if time since last IMU sample grows > 18ms
        let sampleAge = max(0.0, timestamp - lastSampleTime)
        let decayFactor: Double
        if sampleAge <= 0.018 {
            decayFactor = 1.0
        } else if sampleAge < 0.12 {
            decayFactor = exp(-(sampleAge - 0.018) * 32.0)
        } else {
            decayFactor = 0.0
        }

        let precisionMult = isPrecisionModeActive ? config.precisionSlowdownMultiplier : 1.0

        // 1. Center Zone: 1:1 Gyro Delta with Deadzone & S-Curve Response
        let curvedYawVel = applyResponseCurve(
            degPerSec: filteredYawDegPerSec * decayFactor,
            deadzone: config.deadzoneDegPerSec,
            exponent: config.responseCurveExponent
        )
        let curvedPitchVel = applyResponseCurve(
            degPerSec: filteredPitchDegPerSec * decayFactor,
            deadzone: config.deadzoneDegPerSec,
            exponent: config.responseCurveExponent
        )

        // Note: screen +Y is downward, so looking up (+pitchVel) moves cursor upward (-Y)
        var stepDX = curvedYawVel * config.yawSensitivity * precisionMult * dt
        var stepDY = -curvedPitchVel * config.pitchSensitivity * precisionMult * dt

        // 2. Hybrid Edge Zone: Continuous Rate Pan when head is held past threshold
        var inEdgeZone = false
        if config.hybridEdgePanEnabled && sampleAge < 0.15 {
            let absYaw = abs(relativeAngles.yawDeg)
            if absYaw > config.edgeYawThresholdDeg {
                inEdgeZone = true
                let excessNorm = min(1.5, (absYaw - config.edgeYawThresholdDeg) / 15.0)
                let signYaw = relativeAngles.yawDeg >= 0 ? 1.0 : -1.0
                stepDX += signYaw * excessNorm * config.edgePanSpeedPxPerSec * precisionMult * dt
            }

            let absPitch = abs(relativeAngles.pitchDeg)
            if absPitch > config.edgePitchThresholdDeg {
                inEdgeZone = true
                let excessNorm = min(1.5, (absPitch - config.edgePitchThresholdDeg) / 12.0)
                let signPitch = relativeAngles.pitchDeg >= 0 ? -1.0 : 1.0 // +pitch (up) -> -Y (top of screen)
                stepDY += signPitch * excessNorm * config.edgePanSpeedPxPerSec * precisionMult * dt
            }
        }
        telemetry.isInEdgePanZone = inEdgeZone

        // 3. Sub-pixel accumulation
        let totalX = stepDX + residualX
        let totalY = stepDY + residualY

        // Emit sub-pixel smooth positions while retaining tiny fractional remainder
        let moveThreshold = 0.08
        if abs(totalX) < moveThreshold && abs(totalY) < moveThreshold {
            residualX = totalX
            residualY = totalY
            recordHistory(timestamp: timestamp, position: currentCursor)
            return CursorFrameOutput(
                shouldMoveCursor: false,
                targetPosition: currentCursor,
                deltaX: 0,
                deltaY: 0,
                triggeredGesture: activeGesture,
                rollbackPositionForClick: rollbackPos
            )
        }

        residualX = 0
        residualY = 0

        let unclamped = Point2D(x: currentCursor.x + totalX, y: currentCursor.y + totalY)
        let clamped = screenBounds.clamp(unclamped)
        let actualDX = clamped.x - currentCursor.x
        let actualDY = clamped.y - currentCursor.y

        recordHistory(timestamp: timestamp, position: clamped)

        return CursorFrameOutput(
            shouldMoveCursor: true,
            targetPosition: clamped,
            deltaX: actualDX,
            deltaY: actualDY,
            triggeredGesture: activeGesture,
            rollbackPositionForClick: rollbackPos
        )
    }

    private func applyResponseCurve(degPerSec: Double, deadzone: Double, exponent: Double) -> Double {
        let mag = abs(degPerSec)
        guard mag > deadzone else { return 0.0 }
        let sign = degPerSec >= 0 ? 1.0 : -1.0
        let excess = mag - deadzone
        // Normalize around 35 deg/s reference speed so sensitivity slider feels intuitive
        let refSpeed = 35.0
        let curved = refSpeed * pow(excess / refSpeed, max(0.8, min(2.2, exponent)))
        return sign * curved
    }

    private func recordHistory(timestamp: TimeInterval, position: Point2D) {
        cursorHistory.append(CursorHistoryEntry(timestamp: timestamp, position: position))
        if cursorHistory.count > maxHistoryEntries {
            cursorHistory.removeFirst(cursorHistory.count - maxHistoryEntries)
        }
    }

    private func lookupCursorPosition(atOrBefore targetTime: TimeInterval) -> Point2D? {
        guard !cursorHistory.isEmpty else { return nil }
        for entry in cursorHistory.reversed() {
            if entry.timestamp <= targetTime {
                return entry.position
            }
        }
        return cursorHistory.first?.position
    }
}

