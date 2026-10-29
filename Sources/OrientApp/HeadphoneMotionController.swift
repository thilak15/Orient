import Foundation
import AppKit
import CoreMotion
import MediaPlayer
import Observation
import OrientCore

public enum SensorSourceState: String, Sendable {
    case airPodsConnected = "AirPods Connected (Live IMU)"
    case waitingForAirPods = "Listening for AirPods (Put in Ears)"
    case simulatorActive = "Synthetic IMU Simulator Active"
    case motionPermissionDenied = "Motion Permission Required"
}

/// Non-isolated factory for Objective-C blocks so Swift 6 never injects `@MainActor`
/// runtime assertions onto background framework callbacks.
private enum NonIsolatedCallbackFactory {
    static func makeMotionHandler(
        onSample: @escaping @Sendable (IMUSample) -> Void
    ) -> CMHeadphoneMotionManager.DeviceMotionHandler {
        return { motion, _ in
            guard let motion else { return }
            let q = motion.attitude.quaternion
            let rot = motion.rotationRate
            let acc = motion.userAcceleration
            let grav = motion.gravity
            let now = ProcessInfo.processInfo.systemUptime

            let sample = IMUSample(
                timestamp: now,
                attitude: Quaternion(x: q.x, y: q.y, z: q.z, w: q.w),
                rotationRate: Vector3(x: rot.x, y: rot.y, z: rot.z),
                userAcceleration: Vector3(x: acc.x, y: acc.y, z: acc.z),
                gravity: Vector3(x: grav.x, y: grav.y, z: grav.z)
            )
            onSample(sample)
        }
    }

    static func makeMediaCommandHandler(
        onTrigger: @escaping @Sendable () -> Void
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        return { _ in
            onTrigger()
            return .success
        }
    }

    static func makeGlobalKeyHandler(
        onKeyCode: @escaping @Sendable (UInt16) -> Void
    ) -> (NSEvent) -> Void {
        return { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.option) else { return }
            let code = event.keyCode
            if code == 49 || code == 15 || code == 8 {
                onKeyCode(code)
            }
        }
    }

    static func makeLocalKeyHandler(
        onKeyCode: @escaping @Sendable (UInt16) -> Void
    ) -> (NSEvent) -> NSEvent? {
        return { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.option) {
                let code = event.keyCode
                if code == 49 || code == 15 || code == 8 {
                    onKeyCode(code)
                    return nil
                }
            }
            return event
        }
    }
}

/// Thread-safe 120Hz cursor engine worker running on a dedicated `.userInteractive` serial queue
/// so main-thread UI interactions and AppKit modals are never blocked or starved.
private final class BackgroundCursorWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.orient.engine120hz.queue", qos: .userInteractive)
    let pipeline = CursorPipeline()
    let cursorInjector = SystemCursorInjector()

    var isTrackingActive: Bool = false
    var isSimulatorEnabled: Bool = false

    private var timer120Hz: DispatchSourceTimer?
    private var frameCounter: Int = 0
    private var isUIUpdatePending: Bool = false

    func start(onTelemetryUpdate: @escaping @Sendable (TelemetrySnapshot, TriggeredGesture?) -> Void) {
        queue.async { [weak self] in
            guard let self, self.timer120Hz == nil else { return }
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .microseconds(8333), leeway: .microseconds(600))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.tick(onTelemetryUpdate: onTelemetryUpdate)
            }
            timer.resume()
            self.timer120Hz = timer
        }
    }

    private func tick(onTelemetryUpdate: @escaping @Sendable (TelemetrySnapshot, TriggeredGesture?) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        let currentPos = cursorInjector.currentCursorPosition()
        let bounds = cursorInjector.currentScreenBounds()

        let frame = pipeline.step120Hz(
            timestamp: now,
            currentCursor: currentPos,
            screenBounds: bounds
        )

        if isTrackingActive {
            if frame.shouldMoveCursor {
                cursorInjector.moveCursor(
                    to: frame.targetPosition,
                    deltaX: frame.deltaX,
                    deltaY: frame.deltaY
                )
            }

            if let gesture = frame.triggeredGesture {
                switch gesture.action {
                case .leftClick, .rightClick, .doubleClick:
                    let clickPos = frame.rollbackPositionForClick ?? frame.targetPosition
                    if frame.rollbackPositionForClick != nil {
                        cursorInjector.moveCursor(to: clickPos, deltaX: 0, deltaY: 0)
                    }
                    cursorInjector.performClick(action: gesture.action, at: clickPos)
                default:
                    break
                }
            }
        }

        frameCounter += 1
        // Throttle UI state updates to ~20Hz (every 6th tick) and never queue backlogged main-thread blocks
        if (frameCounter % 6 == 0 || frame.triggeredGesture != nil) && !isUIUpdatePending {
            isUIUpdatePending = true
            let snap = pipeline.telemetry
            let trig = frame.triggeredGesture
            DispatchQueue.main.async { [weak self] in
                self?.queue.async {
                    self?.isUIUpdatePending = false
                }
                onTelemetryUpdate(snap, trig)
            }
        }
    }
}

@MainActor
@Observable
public final class HeadphoneMotionController: NSObject, @unchecked Sendable {
    public var isTrackingActive: Bool = false {
        didSet {
            handleTrackingStateChanged()
        }
    }

    public var isSimulatorEnabled: Bool = false {
        didSet {
            let enabled = isSimulatorEnabled
            worker.queue.async { [worker] in
                worker.isSimulatorEnabled = enabled
            }
            configureSimulatorTimer()
            updateSensorSourceState()
        }
    }

    public var isAutoFigureEightDemo: Bool = false
    public var simYawDeg: Double = 0.0
    public var simPitchDeg: Double = 0.0
    public var simRollDeg: Double = 0.0

    public var config = OrientConfiguration() {
        didSet {
            let newConfig = config
            worker.queue.async { [worker] in
                worker.pipeline.config = newConfig
            }
            if isTrackingActive {
                if config.silentAudioKeepAliveEnabled {
                    audioKeepAlive.start()
                } else {
                    audioKeepAlive.stop()
                }
            }
        }
    }

    public private(set) var sensorState: SensorSourceState = .waitingForAirPods
    public private(set) var isAccessibilityGranted: Bool = false
    public private(set) var hasMotionUsagePlistKey: Bool = false
    public private(set) var telemetry = TelemetrySnapshot()
    public private(set) var yawVelocityTrace: [Double] = Array(repeating: 0, count: 60)
    public private(set) var pitchVelocityTrace: [Double] = Array(repeating: 0, count: 60)
    public private(set) var recentGestureEvents: [TriggeredGesture] = []

    private let worker = BackgroundCursorWorker()
    private let audioKeepAlive = SilentAudioKeepAlive()

    private var hasStartedEngine: Bool = false
    private var motionManager: CMHeadphoneMotionManager?
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.orient.headphonemotion.queue"
        q.qualityOfService = .userInteractive
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var simulatorTimer: DispatchSourceTimer?
    private var permissionCheckTimer: DispatchSourceTimer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    private var lastSimYawDeg: Double = 0
    private var lastSimPitchDeg: Double = 0
    private var lastSimRollDeg: Double = 0
    private var pendingSimAccel: Vector3 = .zero

    public override init() {
        super.init()
        self.isAccessibilityGranted = SystemCursorInjector.isAccessibilityTrusted(promptIfNeeded: false)
        self.hasMotionUsagePlistKey = Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") != nil
    }

    /// Starts the 120Hz engine and AirPods CoreMotion listener after the UI window has finished appearing.
    public func startEngineIfNeeded() {
        guard !hasStartedEngine else { return }
        hasStartedEngine = true

        setupHotkeys()
        setupMediaCommandCenter()
        startPermissionMonitor()

        worker.start { [weak self] snap, triggered in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.telemetry = snap
                self.yawVelocityTrace.append(snap.filteredYawRateDegPerSec)
                if self.yawVelocityTrace.count > 60 { self.yawVelocityTrace.removeFirst() }
                self.pitchVelocityTrace.append(snap.filteredPitchRateDegPerSec)
                if self.pitchVelocityTrace.count > 60 { self.pitchVelocityTrace.removeFirst() }

                if let triggered {
                    self.recentGestureEvents.insert(triggered, at: 0)
                    if self.recentGestureEvents.count > 12 {
                        self.recentGestureEvents.removeLast()
                    }
                }
            }
        }

        startHardwareMotionIfSupported()
    }

    public func requestAccessibilityPermission() {
        isAccessibilityGranted = SystemCursorInjector.isAccessibilityTrusted(promptIfNeeded: true)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openMotionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") {
            NSWorkspace.shared.open(url)
        }
    }

    public func toggleTracking() {
        isTrackingActive.toggle()
    }

    public func recenterPose() {
        worker.queue.async { [worker] in
            worker.pipeline.recenter()
        }
        simYawDeg = 0
        simPitchDeg = 0
        simRollDeg = 0
    }

    public func setClutchHeld(_ held: Bool) {
        worker.queue.async { [worker] in
            worker.pipeline.isClutchHeld = held
        }
        telemetry.isClutchHeld = held
    }

    public func triggerSimulatedImpulse(upward: Bool = false) {
        if !isSimulatorEnabled {
            isSimulatorEnabled = true
        }
        pendingSimAccel = upward
            ? Vector3(x: 0, y: 0, z: config.impulseThresholdG * 1.45)
            : Vector3(x: 0, y: config.impulseThresholdG * 1.35, z: -config.impulseThresholdG * 1.35)
    }

    // MARK: - CoreMotion AirPods Setup

    private func startHardwareMotionIfSupported() {
        guard hasMotionUsagePlistKey else {
            isSimulatorEnabled = true
            return
        }

        let authStatus = CMHeadphoneMotionManager.authorizationStatus()
        if authStatus == .denied || authStatus == .restricted {
            sensorState = .motionPermissionDenied
            return
        }

        let manager = CMHeadphoneMotionManager()
        manager.delegate = self
        self.motionManager = manager

        guard manager.isDeviceMotionAvailable else {
            sensorState = .waitingForAirPods
            return
        }

        let workerRef = self.worker
        let handler = NonIsolatedCallbackFactory.makeMotionHandler { [weak self] sample in
            // Ingest sample directly on the 120Hz background worker queue for minimum latency!
            workerRef.queue.async {
                if !workerRef.isSimulatorEnabled {
                    workerRef.pipeline.ingestSample(sample)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.isSimulatorEnabled && self.sensorState != .airPodsConnected {
                    self.sensorState = .airPodsConnected
                }
            }
        }

        manager.startDeviceMotionUpdates(to: motionQueue, withHandler: handler)
        updateSensorSourceState()
    }

    private func updateSensorSourceState() {
        if isSimulatorEnabled {
            sensorState = .simulatorActive
            return
        }
        let authStatus = CMHeadphoneMotionManager.authorizationStatus()
        if authStatus == .denied || authStatus == .restricted {
            sensorState = .motionPermissionDenied
            return
        }
        if let manager = motionManager, manager.isDeviceMotionActive {
            sensorState = .airPodsConnected
        } else {
            sensorState = .waitingForAirPods
        }
    }

    private func handleTrackingStateChanged() {
        let active = isTrackingActive
        worker.queue.async { [worker] in
            if active {
                worker.pipeline.recenter()
            }
            worker.isTrackingActive = active
        }
        if active {
            if config.silentAudioKeepAliveEnabled {
                audioKeepAlive.start()
            }
        } else {
            audioKeepAlive.stop()
        }
    }

    // MARK: - Synthetic IMU Simulator (60Hz packet feed)

    private func configureSimulatorTimer() {
        simulatorTimer?.cancel()
        simulatorTimer = nil

        guard isSimulatorEnabled else { return }

        lastSimYawDeg = simYawDeg
        lastSimPitchDeg = simPitchDeg
        lastSimRollDeg = simRollDeg

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isSimulatorEnabled else { return }
                self.stepSyntheticIMU()
            }
        }
        timer.resume()
        self.simulatorTimer = timer
    }

    private func stepSyntheticIMU() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = 1.0 / 60.0

        if isAutoFigureEightDemo {
            simYawDeg = 14.0 * sin(now * 1.9)
            simPitchDeg = 8.0 * sin(now * 3.8)
        }

        let dYawDegPerSec = (simYawDeg - lastSimYawDeg) / dt
        let dPitchDegPerSec = (simPitchDeg - lastSimPitchDeg) / dt
        let dRollDegPerSec = (simRollDeg - lastSimRollDeg) / dt

        lastSimYawDeg = simYawDeg
        lastSimPitchDeg = simPitchDeg
        lastSimRollDeg = simRollDeg

        let deg2rad = Double.pi / 180.0
        let noiseYaw = Double.random(in: -0.25...0.25)
        let noisePitch = Double.random(in: -0.25...0.25)

        let rotRate = Vector3(
            x: (dPitchDegPerSec + noisePitch) * deg2rad,
            y: dRollDegPerSec * deg2rad,
            z: -(dYawDegPerSec + noiseYaw) * deg2rad
        )

        let attitude = Quaternion.fromHeadAnglesDegrees(
            yawDeg: simYawDeg,
            pitchDeg: simPitchDeg,
            rollDeg: simRollDeg
        )

        let accel = pendingSimAccel
        pendingSimAccel = .zero

        let sample = IMUSample(
            timestamp: now,
            attitude: attitude,
            rotationRate: rotRate,
            userAcceleration: accel
        )
        worker.queue.async { [worker] in
            worker.pipeline.ingestSample(sample)
        }
    }

    private func startPermissionMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.5, repeating: .milliseconds(1500))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAccessibilityGranted = SystemCursorInjector.isAccessibilityTrusted(promptIfNeeded: false)
            }
        }
        timer.resume()
        self.permissionCheckTimer = timer
    }

    // MARK: - Global & Local Hotkeys (Option+Space, Option+R, Option+C)

    private func setupHotkeys() {
        let handleKey: @Sendable (UInt16) -> Void = { [weak self] keyCode in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch keyCode {
                case 49: // Option + Space -> Toggle Tracking
                    self.toggleTracking()
                case 15: // Option + R -> Recenter Neutral Pose
                    self.recenterPose()
                case 8:  // Option + C -> Toggle Clutch
                    self.setClutchHeld(!self.telemetry.isClutchHeld)
                default:
                    break
                }
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown,
            handler: NonIsolatedCallbackFactory.makeGlobalKeyHandler(onKeyCode: handleKey)
        )
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: NonIsolatedCallbackFactory.makeLocalKeyHandler(onKeyCode: handleKey)
        )
    }

    // MARK: - AirPods Stem Press (MPRemoteCommandCenter)

    private func setupMediaCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.isEnabled = true
        let workerRef = self.worker
        let handler = NonIsolatedCallbackFactory.makeMediaCommandHandler {
            workerRef.queue.async {
                guard workerRef.isTrackingActive else { return }
                let pos = workerRef.cursorInjector.currentCursorPosition()
                workerRef.cursorInjector.performClick(action: .leftClick, at: pos)
            }
        }
        commandCenter.togglePlayPauseCommand.addTarget(handler: handler)
    }
}

extension HeadphoneMotionController: CMHeadphoneMotionManagerDelegate {
    nonisolated public func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isSimulatorEnabled {
                self.sensorState = .airPodsConnected
            }
        }
    }

    nonisolated public func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isSimulatorEnabled {
                self.isTrackingActive = false
                self.sensorState = .waitingForAirPods
            }
        }
    }
}
