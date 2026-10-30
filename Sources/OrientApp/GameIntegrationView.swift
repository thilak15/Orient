import SwiftUI
import AppKit
import OrientCore

struct GameIntegrationView: View {
    @Bindable var controller: HeadphoneMotionController
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                externalBrowserLaunchersCard
                accelaMicroGainResearchCard
                aimStyleAndTuningCard
                pubgTacticalLeanCard
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 1. External Browser (Chrome / Safari) & Cloud PUBG Launchers

    private var externalBrowserLaunchersCard: some View {
        GroupBox("🚀 Step 1: Launch External 3D FPS Game (Chrome / Safari Pointer-Lock or Cloud PUBG)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if controller.isAccessibilityGranted {
                        Label("macOS Accessibility Permission Active", systemImage: "checkmark.shield.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    } else {
                        Label("Required for External Games — Click 'Fix & Grant Accessibility' ->", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button {
                        controller.requestAccessibilityPermission()
                    } label: {
                        Label(
                            controller.isAccessibilityGranted ? "Re-Verify Accessibility" : "Fix & Grant Accessibility Now",
                            systemImage: "lock.open.shield"
                        )
                        .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.isAccessibilityGranted ? .green : .orange)
                }

                Text("1. Click any game below to open it in your browser and automatically show the Floating In-Game HUD.  2. Click 'PLAY' inside the game to lock your crosshair.  3. Press Option+Space (⌥Space) to aim, and Option+R (⌥R) anytime to snap BOTH your head pose and the in-game screen back to center!")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    externalLauncherButton(
                        title: "🎯 Play Deadshot.io",
                        subtitle: "Fast 120Hz Pointer-Lock FPS",
                        icon: "scope",
                        color: .green,
                        url: "https://deadshot.io"
                    )
                    externalLauncherButton(
                        title: "🔫 Play Krunker.io",
                        subtitle: "Tactical FPS • Supports Q/E & ADS",
                        icon: "flame.fill",
                        color: .orange,
                        url: "https://krunker.io"
                    )
                    externalLauncherButton(
                        title: "⚡ Play Ev.io",
                        subtitle: "Sci-Fi Arena FPS • Instant Spawn",
                        icon: "bolt.shield.fill",
                        color: .cyan,
                        url: "https://ev.io"
                    )
                    externalLauncherButton(
                        title: "🪖 PUBG on GeForce NOW",
                        subtitle: "Cloud PC PUBG • Full Q/E Peek",
                        icon: "cloud.fill",
                        color: .yellow,
                        url: "https://play.geforcenow.com"
                    )
                }

                HStack(spacing: 18) {
                    Toggle("Keep Cursor Anchored Inside Game Window (Prevents Clicking Outside Canvas)", isOn: $controller.lockCursorInPlaceForExternal3DGame)
                        .font(.caption.bold())
                    Spacer()
                    Toggle("Show Click-Through Floating HUD Over Games", isOn: $controller.isFloatingHUDVisible)
                        .font(.caption.bold())
                        .tint(.cyan)
                }
            }
            .padding(8)
        }
    }

    // MARK: - 2. Research-Backed Accela 6x Non-Linear Micro-Gain & Closed-Loop Recenter

    private var accelaMicroGainResearchCard: some View {
        GroupBox("🧠 Step 2: Accela Non-Linear 6x Micro-Gain & Closed-Loop Screen Recenter (⌥R)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Closed-Loop Virtual Screen Displacement (Snaps to 0, 0 on ⌥R):")
                            .font(.caption.bold())
                        HStack(spacing: 12) {
                            Text(String(format: "Screen Offset X: %+.0f px", controller.virtualCameraOffsetPxX))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text(String(format: "Screen Offset Y: %+.0f px", controller.virtualCameraOffsetPxY))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.mint)
                        }
                    }

                    Spacer()

                    Button {
                        controller.recenterPose()
                    } label: {
                        Label("Recenter Screen & Head Now (⌥R)", systemImage: "scope")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }

                Text("Why this fixes looking down / off-center: Instead of open-loop velocity integration (which drifts toward the floor when you move down fast and up slow), Orient now uses Closed-Loop Pose Tracking (ΔCam = TargetCam(θ) - VirtualCam) + TrackIR/Opentrack's 3-Zone Accela Spline. Returning your head to 0° or pressing ⌥R injects (-ScreenOffsetX, -ScreenOffsetY) back into the game so the 3D screen physically snaps back to the horizon!")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                sliderRow(
                    title: "Accela Micro-Gain Amplification (Outer Sweep)",
                    value: $controller.gameEngine.microGainFactor,
                    range: 3.0...12.0,
                    unit: "x"
                )
                sliderRow(
                    title: "Foveal Precision Pocket Radius (Steady Crosshair Zone)",
                    value: $controller.gameEngine.fovealRadiusDeg,
                    range: 0.4...3.0,
                    unit: "°"
                )
                sliderRow(
                    title: "Non-Linear Spline Acceleration Exponent",
                    value: $controller.gameEngine.nonLinearCurveExponent,
                    range: 1.0...2.4,
                    unit: ""
                )
                sliderRow(
                    title: "Asymmetric Vertical Pitch-to-Yaw Ratio (Damps Floor/Sky Dive)",
                    value: $controller.gameEngine.verticalPitchRatio,
                    range: 0.25...1.0,
                    unit: "x"
                )
                sliderRow(
                    title: "Cross-Axis Chin-Dip Suppression (During Fast Horizontal Flicks)",
                    value: $controller.gameEngine.chinDipSuppressionStrength,
                    range: 0.0...0.95,
                    unit: ""
                )
            }
            .padding(8)
        }
    }

    // MARK: - 3. Aim Style & Master Sensitivity

    private var aimStyleAndTuningCard: some View {
        GroupBox("🎯 Step 3: Select Non-VR Aim Style (Press ⌥M Anytime In-Game to Cycle)") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("In-Game Aim Style (⌥M)", selection: $controller.gameEngine.aimStyle) {
                    ForEach(InGameAimStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                Divider()

                HStack(spacing: 20) {
                    Picker("Game Input Protocol", selection: $controller.gameEngine.injectionProtocol) {
                        ForEach(GameInjectionProtocol.allCases) { proto in
                            Text(proto.rawValue).tag(proto)
                        }
                    }
                    .frame(maxWidth: 420)

                    Toggle("ADS Scope Slowdown Active", isOn: $controller.gameEngine.isADSActive)
                }

                sliderRow(
                    title: "In-Game Master Look Speed Multiplier",
                    value: $controller.gameEngine.inGameSensitivityMultiplier,
                    range: 0.4...3.5,
                    unit: "x"
                )
                sliderRow(
                    title: "Hybrid Mode Edge Turn Threshold (Yaw)",
                    value: $controller.gameEngine.tightEdgeYawDeg,
                    range: 2.5...15.0,
                    unit: "°"
                )
            }
            .padding(8)
        }
    }

    // MARK: - 4. PUBG Tactical Q/E Roll Lean

    private var pubgTacticalLeanCard: some View {
        GroupBox("🛡️ Step 4: PUBG Tactical Q/E Roll Peek & ADS Settings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Current Lean Key State:")
                        .font(.subheadline.bold())
                    Text(controller.activeLeanState.rawValue)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(controller.activeLeanState == .upright ? Color.secondary.opacity(0.18) : Color.yellow.opacity(0.28))
                        .foregroundStyle(controller.activeLeanState == .upright ? Color.secondary : .yellow)
                        .clipShape(Capsule())

                    Spacer()

                    Text(String(format: "Live Head Roll: %+.1f°", controller.telemetry.relativeAngles.rollDeg))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                sliderRow(
                    title: "Q/E Peek Trigger Roll Angle",
                    value: $controller.gameEngine.leanTriggerAngleDeg,
                    range: 6.0...22.0,
                    unit: "°"
                )
                sliderRow(
                    title: "Q/E Peek Release Roll Angle (Hysteresis)",
                    value: $controller.gameEngine.leanReleaseAngleDeg,
                    range: 3.0...16.0,
                    unit: "°"
                )
                sliderRow(
                    title: "ADS Sniper Scope Slowdown Multiplier",
                    value: $controller.gameEngine.adsMultiplier,
                    range: 0.15...0.90,
                    unit: "x"
                )
            }
            .padding(8)
        }
    }

    private func externalLauncherButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        url: String
    ) -> some View {
        Button {
            controller.isFloatingHUDVisible = true
            controller.lockCursorInPlaceForExternal3DGame = true
            if url.contains("geforcenow") || url.contains("krunker") {
                controller.gameEngine.injectionProtocol = .pubgTacticalLean
            } else {
                controller.gameEngine.injectionProtocol = .pointerLockRawDelta
            }
            if let targetURL = URL(string: url) {
                openURL(targetURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 310, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f %@", value.wrappedValue, unit))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 85, alignment: .trailing)
        }
    }
}
