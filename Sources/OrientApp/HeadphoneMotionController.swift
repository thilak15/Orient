import Foundation
import AppKit
import Carbon
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

/// Global Carbon hotkey callback router so Option+Space, Option+R, Option+C, and Option+M
/// work in 100% of external fullscreen games and browsers without needing Input Monitoring permissions.
private final class CarbonHotKeyRouter: @unchecked Sendable {
    static let shared = CarbonHotKeyRouter()
    var onHotKeyPressed: (@Sendable (UInt32) -> Void)?
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []

    func registerAll(onHotKey: @escaping @Sendable (UInt32) -> Void) {
        self.onHotKeyPressed = onHotKey
        guard handlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr {
                    CarbonHotKeyRouter.shared.onHotKeyPressed?(hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &handlerRef
        )

        let signature = OSType(0x4F524E54) // 'ORNT'
        let bindings: [(id: UInt32, keyCode: Int)] = [
            (1, kVK_Space),  // Option + Space -> Toggle Tracking
            (2, kVK_ANSI_R), // Option + R     -> Recenter Screen & Head Pose
            (3, kVK_ANSI_C), // Option + C     -> Toggle Clutch
            (4, kVK_ANSI_M)  // Option + M     -> Cycle In-Game Aim Style
        ]

        for binding in bindings {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: binding.id)
            RegisterEventHotKey(
                UInt32(binding.keyCode),
                UInt32(optionKey),
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            hotKeyRefs.append(ref)
        }
    }
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
}

/// Thread-safe 120Hz cursor engine worker running on a dedicated `.userInteractive` serial queue
/// so main-thread UI interactions and AppKit modals are never blocked or starved.
private final class BackgroundCursorWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.orient.engine120hz.queue", qos: .userInteractive)
    let pipeline = CursorPipeline()
    let cursorInjector = SystemCursorInjector()
    var gameEngine = GameControllerEngine()

    var isTrackingActive: Bool = false {
        didSet {
            if !isTrackingActive {
                cursorInjector.releaseAllHeldKeys()
                gameEngine.reset()
            }
        }
    }
    var lockCursorInPlaceForExternal3DGame: Bool = true
    var isSimulatorEnabled: Bool = false
    var isRecordingRollCalibration: Bool = false
    var recordedRollSamples: [IMUSample] = []

    private var timer120Hz: DispatchSourceTimer?
    private var frameCounter: Int = 0
    private var isUIUpdatePending: Bool = false

    func start(
        onTelemetryUpdate: @escaping @Sendable (TelemetrySnapshot, TriggeredGesture?, TacticalLeanState, Double, Double) -> Void
    ) {
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

    func markUIUpdateComplete() {
        queue.async { [weak self] in
            self?.isUIUpdatePending = false
        }
    }

    func ingest(_ sample: IMUSample) {
        if isRecordingRollCalibration {
            recordedRollSamples.append(sample)
        }
        pipeline.ingestSample(sample)
    }

    private func tick(
        onTelemetryUpdate: @escaping @Sendable (TelemetrySnapshot, TriggeredGesture?, TacticalLeanState, Double, Double) -> Void
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let currentPos = cursorInjector.currentCursorPosition()
        let bounds = cursorInjector.currentScreenBounds()

        let frame = pipeline.step120Hz(
            timestamp: now,
            currentCursor: currentPos,
            screenBounds: bounds
        )

        if frame.triggeredGesture?.action == .recenter {
            gameEngine.onRecenterPressed()
        }

        let gameCmd = gameEngine.step120Hz(
            telemetry: pipeline.telemetry,
            baseDeltaX: frame.deltaX,
            baseDeltaY: frame.deltaY,
            dt: 1.0 / 120.0
        )

        if isTrackingActive {
            if let leanChange = gameCmd.leanStateChangedTo {
                cursorInjector.updateTacticalLeanKeys(to: leanChange)
            }

            if abs(gameCmd.deltaX) > 0.02 || abs(gameCmd.deltaY) > 0.02 || gameCmd.shouldResetTouchDragAnchor {
                let targetPos = bounds.clamp(Point2D(
                    x: currentPos.x + gameCmd.deltaX,
                    y: currentPos.y + gameCmd.deltaY
                ))
                cursorInjector.moveCursor(
                    to: targetPos,
                    deltaX: gameCmd.deltaX,
                    deltaY: gameCmd.deltaY,
                    injectionProtocol: gameEngine.injectionProtocol,
                    shouldResetTouchDragAnchor: gameCmd.shouldResetTouchDragAnchor,
                    lockCursorInPlaceFor3DGame: lockCursorInPlaceForExternal3DGame
                )
            }

            if let gesture = frame.triggeredGesture {
                switch gesture.action {
                case .leftClick, .rightClick, .doubleClick:
                    let clickPos = frame.rollbackPositionForClick ?? frame.targetPosition
                    if frame.rollbackPositionForClick != nil && !lockCursorInPlaceForExternal3DGame {
                        cursorInjector.moveCursor(to: clickPos, deltaX: 0, deltaY: 0)
                    }
                    cursorInjector.performClick(action: gesture.action, at: clickPos)
                default:
                    break
                }
            }
        }

        frameCounter += 1
        // Throttle SwiftUI dashboard layout updates to ~15Hz (every 8th tick) so external 3D games get maximum GPU/CPU
        if (frameCounter % 8 == 0 || frame.triggeredGesture != nil || gameCmd.leanStateChangedTo != nil) && !isUIUpdatePending {
            isUIUpdatePending = true
            let snap = pipeline.telemetry
            let trig = frame.triggeredGesture
            let lean = gameCmd.currentLeanState
            let vCamX = gameEngine.virtualCameraX
            let vCamY = gameEngine.virtualCameraY
            let workerRef = self
            DispatchQueue.main.async {
                workerRef.markUIUpdateComplete()
                onTelemetryUpdate(snap, trig, lean, vCamX, vCamY)
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

    public var lockCursorInPlaceForExternal3DGame: Bool = true {
        didSet {
            let locked = lockCursorInPlaceForExternal3DGame
            worker.queue.async { [worker] in
                worker.lockCursorInPlaceForExternal3DGame = locked
            }
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

    public var diagnosticEngine = DiagnosticBenchmarkEngine()
    public var gameEngine = GameControllerEngine() {
        didSet {
            let updated = gameEngine
            worker.queue.async { [worker] in
                worker.gameEngine.injectionProtocol = updated.injectionProtocol
                worker.gameEngine.aimStyle = updated.aimStyle
                worker.gameEngine.isADSActive = updated.isADSActive
                worker.gameEngine.adsMultiplier = updated.adsMultiplier
                worker.gameEngine.inGameSensitivityMultiplier = updated.inGameSensitivityMultiplier
                worker.gameEngine.autoRatchetYawEnabled = updated.autoRatchetYawEnabled
                worker.gameEngine.ratchetTurnThresholdDeg = updated.ratchetTurnThresholdDeg
                worker.gameEngine.outerContinuousTurnAngleDeg = updated.outerContinuousTurnAngleDeg
                worker.gameEngine.microGainFactor = updated.microGainFactor
                worker.gameEngine.fovealRadiusDeg = updated.fovealRadiusDeg
                worker.gameEngine.nonLinearCurveExponent = updated.nonLinearCurveExponent
                worker.gameEngine.verticalPitchRatio = updated.verticalPitchRatio
                worker.gameEngine.chinDipSuppressionStrength = updated.chinDipSuppressionStrength
                worker.gameEngine.fovealTremorDeadbandDeg = updated.fovealTremorDeadbandDeg
                worker.gameEngine.tightEdgeYawDeg = updated.tightEdgeYawDeg
                worker.gameEngine.tightEdgePitchDeg = updated.tightEdgePitchDeg
                worker.gameEngine.tightEdgePanSpeedPxPerSec = updated.tightEdgePanSpeedPxPerSec
                worker.gameEngine.leanTriggerAngleDeg = updated.leanTriggerAngleDeg
                worker.gameEngine.leanReleaseAngleDeg = updated.leanReleaseAngleDeg
            }
        }
    }
    public var isFloatingHUDVisible: Bool = false {
        didSet {
            hudManager.setVisible(isFloatingHUDVisible, controller: self)
        }
    }
    public private(set) var activeLeanState: TacticalLeanState = .upright
    public private(set) var virtualCameraOffsetPxX: Double = 0.0
    public private(set) var virtualCameraOffsetPxY: Double = 0.0
    public private(set) var isCalibratingRollBleed: Bool = false
    public private(set) var sensorState: SensorSourceState = .waitingForAirPods
    public private(set) var isAccessibilityGranted: Bool = false
    public private(set) var hasMotionUsagePlistKey: Bool = false
    public private(set) var telemetry = TelemetrySnapshot()
    public private(set) var yawVelocityTrace: [Double] = Array(repeating: 0, count: 60)
    public private(set) var pitchVelocityTrace: [Double] = Array(repeating: 0, count: 60)
    public private(set) var recentGestureEvents: [TriggeredGesture] = []

    private let worker = BackgroundCursorWorker()
    private let audioKeepAlive = SilentAudioKeepAlive()
    private let hudManager = InGameHUDWindowManager()

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

        worker.start { [weak self] snap, triggered, lean, vCamX, vCamY in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.telemetry = snap
                self.activeLeanState = lean
                self.virtualCameraOffsetPxX = vCamX
                self.virtualCameraOffsetPxY = vCamY
                self.diagnosticEngine.update(telemetry: snap, dt: 8.0 / 120.0)
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
        isAccessibilityGranted = SystemCursorInjector.resetStaleTCCAndPromptAccessibility()
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

    /// Recenters the user's physical head pose AND triggers a closed-loop counter-delta (`-virtualCameraX, -virtualCameraY`)
    /// so the in-game 3D screen physically rotates right back to the centered horizon!
    public func recenterPose() {
        worker.queue.async { [worker] in
            worker.pipeline.recenter()
            worker.gameEngine.onRecenterPressed()
        }
        simYawDeg = 0
        simPitchDeg = 0
        simRollDeg = 0
    }

    public func setClutchHeld(_ held: Bool) {
        worker.queue.async { [worker] in
            worker.pipeline.isClutchHeld = held
        }
    }

    public func triggerSimulatedImpulse(upward: Bool) {
        let direction = upward ? 1.0 : -1.0
        pendingSimAccel = Vector3(x: 0.72 * direction, y: 0, z: 0)
    }

    public func triggerSyntheticImpulse(direction: Double) {
        pendingSimAccel = Vector3(x: 0.72 * direction, y: 0, z: 0)
    }

    public func runThreeSecondRollCalibration() {
        calibrateRollCrossAxisDecoupling()
    }

    public func resetRollCalibration() {
        resetRollDecoupling()
    }

    public func calibrateRollCrossAxisDecoupling() {
        guard !isCalibratingRollBleed else { return }
        isCalibratingRollBleed = true
        worker.queue.async { [worker] in
            worker.recordedRollSamples.removeAll()
            worker.isRecordingRollCalibration = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.worker.queue.async { [weak self, worker = self.worker] in
                worker.isRecordingRollCalibration = false
                let samples = worker.recordedRollSamples
                let matrix = CrossAxisCalibrator.calibrateFromRollSamples(samples)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.config.decouplingMatrix = matrix
                    self.isCalibratingRollBleed = false
                }
            }
        }
    }

    public func resetRollDecoupling() {
        config.decouplingMatrix = DecouplingMatrix()
    }

    // MARK: - CoreMotion AirPods Stream

    private func startHardwareMotionIfSupported() {
        let manager = CMHeadphoneMotionManager()
        manager.delegate = self
        self.motionManager = manager

        guard manager.isDeviceMotionAvailable else {
            sensorState = .waitingForAirPods
            return
        }

        let workerRef = self.worker
        let handler = NonIsolatedCallbackFactory.makeMotionHandler { [weak self] sample in
            workerRef.queue.async {
                if !workerRef.isSimulatorEnabled {
                    workerRef.ingest(sample)
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
        if active && !isAccessibilityGranted {
            isAccessibilityGranted = SystemCursorInjector.resetStaleTCCAndPromptAccessibility()
        }
        worker.queue.async { [worker] in
            if active {
                worker.pipeline.recenter()
                worker.gameEngine.reset()
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
            worker.ingest(sample)
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

    // MARK: - Carbon Global Hotkeys (Option+Space, Option+R, Option+C, Option+M)

    private func setupHotkeys() {
        CarbonHotKeyRouter.shared.registerAll { [weak self] hotKeyID in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch hotKeyID {
                case 1: // Option + Space -> Toggle Tracking
                    self.toggleTracking()
                case 2: // Option + R -> Recenter Screen & Head Pose
                    self.recenterPose()
                case 3: // Option + C -> Toggle Clutch
                    self.setClutchHeld(!self.telemetry.isClutchHeld)
                case 4: // Option + M -> Cycle In-Game Aim Style live!
                    self.gameEngine.aimStyle = self.gameEngine.aimStyle.next
                default:
                    break
                }
            }
        }
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
