import SwiftUI
import OrientCore

public struct OrientDashboardView: View {
    @Bindable var controller: HeadphoneMotionController
    @State private var selectedTab: Int = 0

    public init(controller: HeadphoneMotionController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                // Left Panel: Live Head Pose Radar + Real-time Latency Telemetry + Simulator
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headPoseRadarCard
                        telemetryMetricsCard
                        velocitySparklineCard
                        simulatorControlCard
                    }
                    .padding(14)
                }
                .frame(minWidth: 330, idealWidth: 355, maxWidth: 400)

                // Right Panel: Live Game Mode, 3D Spatial Lab, 2D Target Benchmark Pad & Tuning Studio
                VStack(spacing: 12) {
                    Picker("Workspace", selection: $selectedTab) {
                        Text("🎮 Live Game Mode & PUBG Suite").tag(0)
                        Text("🧊 3D Spatial & 6-DOF Lab").tag(1)
                        Text("🎯 2D Target & Latency Pad").tag(2)
                        Text("⚡ Sensitivity & 1-Euro Filter").tag(3)
                        Text("🖱️ Click Gestures & Aim-Freeze").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .onChange(of: selectedTab) { _, newTab in
                        if newTab != 0 {
                            controller.isInAppGameBrowserActive = false
                        }
                    }

                    Group {
                        switch selectedTab {
                        case 0:
                            GameIntegrationView(controller: controller)
                        case 1:
                            Spatial3DLabView(controller: controller)
                        case 2:
                            TargetBenchmarkView(controller: controller)
                        case 3:
                            sensitivityAndFilterTab
                        default:
                            gesturesAndAimFreezeTab
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 960, minHeight: 660)
    }

    // MARK: - Top Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "airpodspro")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                    Text("ORIENT")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                    Text("PHASE 3 • LIVE 3D FPS GAME & PUBG SUITE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.16))
                        .foregroundStyle(.cyan)
                        .clipShape(Capsule())
                }
                Text("120Hz Predictive Cursor Engine • 1-Euro Adaptive Filter • Pre-Click Rollback & Aim-Freeze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sensor Connection Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(sensorStatusColor)
                    .frame(width: 9, height: 9)
                Text(controller.sensorState.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(sensorStatusColor.opacity(0.14))
            .clipShape(Capsule())

            // Accessibility Permission Badge
            if controller.isAccessibilityGranted {
                Label("Accessibility Ready", systemImage: "checkmark.shield.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.14))
                    .clipShape(Capsule())
            } else {
                Button {
                    controller.requestAccessibilityPermission()
                } label: {
                    Label("Fix / Grant Accessibility", systemImage: "exclamationmark.shield.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            // Primary Action Buttons
            Button {
                controller.isFloatingHUDVisible.toggle()
            } label: {
                Label(
                    controller.isFloatingHUDVisible ? "Hide Game HUD" : "Show Game HUD",
                    systemImage: "viewfinder.rectangular"
                )
            }
            .buttonStyle(.bordered)
            .tint(controller.isFloatingHUDVisible ? .cyan : .primary)

            Button {
                controller.recenterPose()
            } label: {
                Label("Recenter (⌥R)", systemImage: "scope")
            }
            .buttonStyle(.bordered)

            Button {
                controller.setClutchHeld(!controller.telemetry.isClutchHeld)
            } label: {
                Label(
                    controller.telemetry.isClutchHeld ? "Clutch Held (⌥C)" : "Clutch (⌥C)",
                    systemImage: controller.telemetry.isClutchHeld ? "hand.raised.fill" : "hand.raised"
                )
            }
            .buttonStyle(.bordered)
            .tint(controller.telemetry.isClutchHeld ? .yellow : .primary)

            Button {
                controller.toggleTracking()
            } label: {
                Label(
                    controller.isTrackingActive ? "Stop Cursor (⌥Space)" : "Start Cursor (⌥Space)",
                    systemImage: controller.isTrackingActive ? "stop.fill" : "play.fill"
                )
                .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isTrackingActive ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sensorStatusColor: Color {
        switch controller.sensorState {
        case .airPodsConnected: return .green
        case .simulatorActive: return .cyan
        case .waitingForAirPods: return .orange
        case .motionPermissionDenied: return .red
        }
    }

    // MARK: - Left Column Cards

    private var headPoseRadarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("6-DOF Head Pose & Hybrid Zone", systemImage: "gyroscope")
                    .font(.headline)
                Spacer()
                Text(String(
                    format: "Y:%+.1f° P:%+.1f° R:%+.1f°",
                    controller.telemetry.relativeAngles.yawDeg,
                    controller.telemetry.relativeAngles.pitchDeg,
                    controller.telemetry.relativeAngles.rollDeg
                ))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let scaleX = (size.width * 0.42) / 35.0
                let scaleY = (size.height * 0.42) / 25.0

                // Edge-Pan Threshold Box
                let edgeW = CGFloat(controller.config.edgeYawThresholdDeg) * scaleX * 2
                let edgeH = CGFloat(controller.config.edgePitchThresholdDeg) * scaleY * 2
                let edgeRect = CGRect(
                    x: center.x - edgeW / 2,
                    y: center.y - edgeH / 2,
                    width: edgeW,
                    height: edgeH
                )
                context.stroke(
                    Path(roundedRect: edgeRect, cornerRadius: 8),
                    with: .color(controller.telemetry.isInEdgePanZone ? .orange : .cyan.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )

                // Center Crosshair
                var cross = Path()
                cross.move(to: CGPoint(x: center.x - 10, y: center.y))
                cross.addLine(to: CGPoint(x: center.x + 10, y: center.y))
                cross.move(to: CGPoint(x: center.x, y: center.y - 10))
                cross.addLine(to: CGPoint(x: center.x, y: center.y + 10))
                context.stroke(cross, with: .color(.white.opacity(0.3)), lineWidth: 1)

                // Roll Tilt Indicator Bar at Top
                let rollBarWidth = size.width * 0.75
                let rollBarY: CGFloat = 14
                let rollStartX = (size.width - rollBarWidth) / 2
                var rollTrack = Path()
                rollTrack.move(to: CGPoint(x: rollStartX, y: rollBarY))
                rollTrack.addLine(to: CGPoint(x: rollStartX + rollBarWidth, y: rollBarY))
                context.stroke(rollTrack, with: .color(.white.opacity(0.18)), lineWidth: 4)

                // Roll Left / Right Click Threshold ticks
                let rollScale = (rollBarWidth / 2) / 30.0
                let threshOffset = CGFloat(controller.config.rollTriggerAngleDeg) * rollScale
                for sign in [-1.0, 1.0] {
                    let tx = center.x + CGFloat(sign) * threshOffset
                    var tick = Path()
                    tick.move(to: CGPoint(x: tx, y: rollBarY - 5))
                    tick.addLine(to: CGPoint(x: tx, y: rollBarY + 5))
                    context.stroke(tick, with: .color(.yellow), lineWidth: 2)
                }

                let rollDotX = max(rollStartX, min(rollStartX + rollBarWidth, center.x + CGFloat(controller.telemetry.relativeAngles.rollDeg) * rollScale))
                let rollCircle = CGRect(x: rollDotX - 5, y: rollBarY - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rollCircle), with: .color(.yellow))

                // Current Head Yaw/Pitch Reticle
                let headX = max(10, min(size.width - 10, center.x + CGFloat(controller.telemetry.relativeAngles.yawDeg) * scaleX))
                let headY = max(24, min(size.height - 10, center.y - CGFloat(controller.telemetry.relativeAngles.pitchDeg) * scaleY))

                let dotColor: Color = controller.telemetry.isAimFrozen ? .mint : (controller.telemetry.isInEdgePanZone ? .orange : .green)
                let headRect = CGRect(x: headX - 7, y: headY - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: headRect), with: .color(dotColor))
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("Dashed Box = 1:1 Gyro Zone (Outside = Edge Pan)")
                Spacer()
                Text("Top Bar = Roll Click Tilt")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var telemetryMetricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Latency & Signal Telemetry", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                if controller.config.silentAudioKeepAliveEnabled {
                    Text("Audio Keep-Alive ON")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.mint)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                telemetryTile(
                    label: "IMU PACKET RATE",
                    value: String(format: "%.0f Hz (%.1f ms)", controller.telemetry.sampleRateHz, controller.telemetry.packetIntervalMs),
                    color: .cyan
                )
                telemetryTile(
                    label: "1-EURO FILTER LAG",
                    value: String(format: "%.2f ms", controller.telemetry.filterLagMs),
                    color: .green
                )
                telemetryTile(
                    label: "CURSOR DISPATCH",
                    value: String(format: "%.0f Hz", controller.telemetry.outputRateHz),
                    color: .mint
                )
                telemetryTile(
                    label: "PIPELINE LATENCY",
                    value: String(format: "%.1f ms", controller.telemetry.endToEndLatencyMs),
                    color: .yellow
                )
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var velocitySparklineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Filtered Gyro Velocity (Yaw & Pitch deg/s)")
                    .font(.caption.bold())
                Spacer()
                Text(String(
                    format: "Y:%+.0f°/s P:%+.0f°/s",
                    controller.telemetry.filteredYawRateDegPerSec,
                    controller.telemetry.filteredPitchRateDegPerSec
                ))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Canvas { context, size in
                let midY = size.height / 2
                var zeroLine = Path()
                zeroLine.move(to: CGPoint(x: 0, y: midY))
                zeroLine.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(zeroLine, with: .color(.white.opacity(0.12)), lineWidth: 1)

                drawTrace(controller.yawVelocityTrace, in: size, context: &context, color: .cyan)
                drawTrace(controller.pitchVelocityTrace, in: size, context: &context, color: .orange)
            }
            .frame(height: 64)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func drawTrace(_ values: [Double], in size: CGSize, context: inout GraphicsContext, color: Color) {
        guard values.count > 1 else { return }
        var path = Path()
        let midY = size.height / 2
        let scaleY = (size.height * 0.45) / 120.0
        for (idx, val) in values.enumerated() {
            let x = CGFloat(idx) / CGFloat(values.count - 1) * size.width
            let y = max(2, min(size.height - 2, midY - CGFloat(val) * scaleY))
            if idx == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    private var simulatorControlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Synthetic IMU Simulator", isOn: $controller.isSimulatorEnabled)
                    .font(.subheadline.bold())
                Spacer()
            }

            Text("Use live AirPods in your ears, or enable the simulator to test the 120Hz cursor pipeline and click gestures right now without headphones.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if controller.isSimulatorEnabled {
                Toggle("Auto Figure-8 Smooth Tracking Demo", isOn: $controller.isAutoFigureEightDemo)
                    .font(.caption)

                VStack(spacing: 4) {
                    HStack {
                        Text("Sim Yaw")
                            .font(.caption2)
                            .frame(width: 58, alignment: .leading)
                        Slider(value: $controller.simYawDeg, in: -40...40)
                        Text(String(format: "%+.0f°", controller.simYawDeg))
                            .font(.caption2.monospaced())
                            .frame(width: 36)
                    }
                    HStack {
                        Text("Sim Pitch")
                            .font(.caption2)
                            .frame(width: 58, alignment: .leading)
                        Slider(value: $controller.simPitchDeg, in: -30...30)
                        Text(String(format: "%+.0f°", controller.simPitchDeg))
                            .font(.caption2.monospaced())
                            .frame(width: 36)
                    }
                    HStack {
                        Text("Sim Roll")
                            .font(.caption2)
                            .frame(width: 58, alignment: .leading)
                        Slider(value: $controller.simRollDeg, in: -25...25)
                        Text(String(format: "%+.0f°", controller.simRollDeg))
                            .font(.caption2.monospaced())
                            .frame(width: 36)
                    }
                }

                HStack(spacing: 8) {
                    Button("Sim Head Impulse (Click)") {
                        controller.triggerSimulatedImpulse(upward: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Zero Sim Pose") {
                        controller.isAutoFigureEightDemo = false
                        controller.recenterPose()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tab 2: Sensitivity, Hybrid Edge & 1-Euro Filter Tuning

    private var sensitivityAndFilterTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("1:1 Gyro Sensitivity & Response Curve") {
                    VStack(spacing: 10) {
                        sliderRow(
                            title: "Horizontal (Yaw) Sensitivity",
                            value: $controller.config.yawSensitivity,
                            range: 5...80,
                            unit: "px/deg"
                        )
                        sliderRow(
                            title: "Vertical (Pitch) Sensitivity (Ergonomic Boost)",
                            value: $controller.config.pitchSensitivity,
                            range: 5...95,
                            unit: "px/deg"
                        )
                        sliderRow(
                            title: "Gyro Deadzone",
                            value: $controller.config.deadzoneDegPerSec,
                            range: 0.0...5.0,
                            unit: "°/s"
                        )
                        sliderRow(
                            title: "S-Curve Response Exponent (1.0 = Linear, >1.2 = Micro-Precision)",
                            value: $controller.config.responseCurveExponent,
                            range: 1.0...2.0,
                            unit: "x"
                        )
                        HStack(spacing: 24) {
                            Toggle("Invert Horizontal (Yaw)", isOn: $controller.config.invertYaw)
                            Toggle("Invert Vertical (Pitch)", isOn: $controller.config.invertPitch)
                            Toggle("Silent Bluetooth Audio Keep-Alive", isOn: $controller.config.silentAudioKeepAliveEnabled)
                        }
                        .padding(.top, 4)
                    }
                    .padding(8)
                }

                GroupBox("Hybrid Edge Continuous Pan Zone") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable Continuous Pan when holding head past Edge Threshold", isOn: $controller.config.hybridEdgePanEnabled)
                        sliderRow(
                            title: "Horizontal Edge Threshold (Yaw)",
                            value: $controller.config.edgeYawThresholdDeg,
                            range: 12...40,
                            unit: "°"
                        )
                        sliderRow(
                            title: "Vertical Edge Threshold (Pitch)",
                            value: $controller.config.edgePitchThresholdDeg,
                            range: 10...30,
                            unit: "°"
                        )
                        sliderRow(
                            title: "Edge Continuous Pan Speed",
                            value: $controller.config.edgePanSpeedPxPerSec,
                            range: 200...2000,
                            unit: "px/s"
                        )
                    }
                    .padding(8)
                }

                GroupBox("1-Euro Adaptive Low-Pass Filter (Zero-Lag Tuning)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Lower Min Cutoff smooths micro-tremor when holding still; higher Beta eliminates phase lag during fast flicks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        sliderRow(
                            title: "Min Cutoff Frequency (Static Smoothing)",
                            value: $controller.config.oneEuroMinCutoff,
                            range: 0.3...5.0,
                            unit: "Hz"
                        )
                        sliderRow(
                            title: "Speed Beta (Fast-Flick Responsiveness)",
                            value: $controller.config.oneEuroBeta,
                            range: 0.01...0.30,
                            unit: ""
                        )
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Tab 3: Click Gestures & Aim-Freeze Compensation

    private var gesturesAndAimFreezeTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Pre-Click Cursor Rollback & Aim-Freeze Stabilization") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("When a head gesture triggers a click, Orient rewinds the cursor to its position right before the gesture started and freezes cursor motion briefly so your click never slips off a button.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        sliderRow(
                            title: "Pre-Click Cursor Rollback Window",
                            value: $controller.config.preClickRollbackWindowMs,
                            range: 0...120,
                            unit: "ms"
                        )
                        sliderRow(
                            title: "Post-Click Aim-Freeze Duration",
                            value: $controller.config.aimFreezeDurationMs,
                            range: 0...200,
                            unit: "ms"
                        )
                        sliderRow(
                            title: "Gesture Cooldown (Prevent Double-Trigger)",
                            value: $controller.config.gestureCooldownMs,
                            range: 120...600,
                            unit: "ms"
                        )
                    }
                    .padding(8)
                }

                GroupBox("Roll Head Tilt Clicks (Ear-to-Shoulder)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable Roll Tilt Gestures", isOn: $controller.config.rollClickEnabled)
                        HStack(spacing: 20) {
                            Picker("Roll Left Action", selection: $controller.config.rollLeftAction) {
                                ForEach(GestureAction.allCases) { action in
                                    Text(action.rawValue).tag(action)
                                }
                            }
                            Picker("Roll Right Action", selection: $controller.config.rollRightAction) {
                                ForEach(GestureAction.allCases) { action in
                                    Text(action.rawValue).tag(action)
                                }
                            }
                        }
                        sliderRow(
                            title: "Roll Trigger Angle",
                            value: $controller.config.rollTriggerAngleDeg,
                            range: 8...28,
                            unit: "°"
                        )
                        sliderRow(
                            title: "Roll Release Hysteresis Angle",
                            value: $controller.config.rollReleaseAngleDeg,
                            range: 4...18,
                            unit: "°"
                        )
                    }
                    .padding(8)
                }

                GroupBox("Linear Acceleration Impulse Clicks (Head Nod / Jolt)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable Linear Acceleration Impulse Gestures", isOn: $controller.config.impulseClickEnabled)
                        HStack(spacing: 20) {
                            Picker("Forward/Down Nod Action", selection: $controller.config.forwardImpulseAction) {
                                ForEach(GestureAction.allCases) { action in
                                    Text(action.rawValue).tag(action)
                                }
                            }
                            Picker("Sharp Upward Impulse Action", selection: $controller.config.upwardImpulseAction) {
                                ForEach(GestureAction.allCases) { action in
                                    Text(action.rawValue).tag(action)
                                }
                            }
                        }
                        sliderRow(
                            title: "Acceleration Impulse Threshold",
                            value: $controller.config.impulseThresholdG,
                            range: 0.25...1.20,
                            unit: "G"
                        )
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func telemetryTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.26))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .frame(width: 290, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f %@", value.wrappedValue, unit))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 90, alignment: .trailing)
        }
    }
}

