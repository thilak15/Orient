import SwiftUI
import AppKit
import OrientCore

struct GameIntegrationView: View {
    @Bindable var controller: HeadphoneMotionController
    @Environment(\.openURL) private var openURL
    @State private var selectedInAppURL: String = "https://deadshot.io"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.isInAppGameBrowserActive {
                inAppGameArenaView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        instantPlayLaunchersCard
                        externalBrowserInstructionsCard
                        aimStyleAndTuningCard
                        pubgTacticalLeanCard
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Built-In In-App 3D FPS Game Arena (Zero OS Permissions Needed)

    private var inAppGameArenaView: some View {
        VStack(spacing: 8) {
            // Compact Top Game Control Bar
            HStack(spacing: 10) {
                Button {
                    controller.isInAppGameBrowserActive = false
                } label: {
                    Label("Back to Game Settings", systemImage: "chevron.left")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Picker("Game", selection: $selectedInAppURL) {
                    Text("🎯 Deadshot.io").tag("https://deadshot.io")
                    Text("🔫 Krunker.io").tag("https://krunker.io")
                    Text("⚡ Ev.io").tag("https://ev.io")
                }
                .frame(width: 190)
                .onChange(of: selectedInAppURL) { _, newURL in
                    controller.inAppGameBridge.loadGame(url: newURL)
                }

                Button {
                    controller.inAppGameBridge.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Reload Game")

                Divider().frame(height: 20)

                Picker("Aim Style (⌥M)", selection: $controller.gameEngine.aimStyle) {
                    ForEach(InGameAimStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .frame(maxWidth: 290)

                Spacer()

                if controller.activeLeanState != .upright {
                    Text(controller.activeLeanState.rawValue)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.25))
                        .foregroundStyle(.yellow)
                        .clipShape(Capsule())
                }

                Button {
                    controller.recenterPose()
                } label: {
                    Label("Recenter (⌥R)", systemImage: "scope")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button {
                    controller.toggleTracking()
                } label: {
                    Label(
                        controller.isTrackingActive ? "AirPods Aim: ON (⌥Space)" : "AirPods Aim: OFF (⌥Space)",
                        systemImage: controller.isTrackingActive ? "dot.radiowaves.left.and.right" : "pause.circle"
                    )
                    .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isTrackingActive ? .green : .orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Instruction Banner
            HStack(spacing: 12) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(.green)
                Text("1. Click 'PLAY' inside the game below with your mouse.  2. AirPods Aiming turns ON automatically when you enter the match!  3. Press Option+R (⌥R) to recenter your crosshair, or Option+M (⌥M) to switch Aim Style.")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Embedded WebGL FPS Viewport
            InAppFPSWebViewRepresentable(
                bridge: controller.inAppGameBridge,
                initialURL: selectedInAppURL
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(controller.isTrackingActive ? Color.green.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 2)
            )
        }
    }

    // MARK: - Option 1: In-App Instant Game Launchers

    private var instantPlayLaunchersCard: some View {
        GroupBox("🚀 Option A (Recommended): Play 3D FPS Right Inside Orient (Instant • Zero OS Permissions Needed)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Play Deadshot.io, Krunker.io, or Ev.io directly inside Orient's built-in WebGL Arena. Our direct JavaScript Pointer-Lock bridge feeds your 120Hz AirPods head movement & Q/E lean straight into the game canvas automatically when you click 'Play'!")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    inAppLauncherButton(
                        title: "▶ Play Deadshot.io Inside Orient",
                        subtitle: "Recommended • Auto-locks & aims on click",
                        icon: "scope",
                        color: .green,
                        url: "https://deadshot.io"
                    )
                    inAppLauncherButton(
                        title: "▶ Play Krunker.io Inside Orient",
                        subtitle: "Tactical FPS • Supports Q/E & ADS",
                        icon: "flame.fill",
                        color: .orange,
                        url: "https://krunker.io"
                    )
                    inAppLauncherButton(
                        title: "▶ Play Ev.io Inside Orient",
                        subtitle: "Sci-Fi Arena FPS • Instant Spawn",
                        icon: "bolt.shield.fill",
                        color: .cyan,
                        url: "https://ev.io"
                    )
                }
            }
            .padding(8)
        }
    }

    // MARK: - Option 2: External Browser (Chrome / Safari) & Cloud PUBG

    private var externalBrowserInstructionsCard: some View {
        GroupBox("🌐 Option B: Use in External Browser (Chrome / Safari) or Cloud PUBG (GeForce NOW)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if controller.isAccessibilityGranted {
                        Label("Step 1: macOS Accessibility Permission Active", systemImage: "checkmark.shield.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    } else {
                        Label("Step 1: Required for External Apps — Click 'Fix & Grant Accessibility' ->", systemImage: "exclamationmark.triangle.fill")
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

                Text("How to play in External Chrome / Safari:  (1) Make sure Step 1 above is green.  (2) Click an external launcher below and click 'PLAY' inside the game so your crosshair is locked.  (3) Press Option + Space (⌥Space) while inside the match to start aiming with your AirPods!")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    externalLauncherButton(
                        title: "↗ Deadshot.io in Browser",
                        icon: "safari",
                        url: "https://deadshot.io"
                    )
                    externalLauncherButton(
                        title: "↗ Krunker.io in Browser",
                        icon: "safari",
                        url: "https://krunker.io"
                    )
                    externalLauncherButton(
                        title: "↗ PUBG on GeForce NOW",
                        icon: "cloud.fill",
                        url: "https://play.geforcenow.com"
                    )
                    Toggle("Keep Cursor Anchored Inside Game Window", isOn: $controller.lockCursorInPlaceForExternal3DGame)
                        .font(.caption.bold())
                }
            }
            .padding(8)
        }
    }

    // MARK: - Aim Style & Sensitivity Tuning

    private var aimStyleAndTuningCard: some View {
        GroupBox("🎯 Non-VR In-Game Aim Style (Press ⌥M Anytime In-Game to Switch!)") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Show Click-Through Floating HUD Over External Games", isOn: $controller.isFloatingHUDVisible)
                        .font(.subheadline.bold())
                        .tint(.cyan)
                    Spacer()
                    Text("Tip: Press Option + M (⌥M) while inside a game to cycle these 4 Aim Styles live!")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                }

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
                    title: "Tight Non-VR Edge Pan Threshold (Yaw)",
                    value: $controller.gameEngine.tightEdgeYawDeg,
                    range: 2.5...15.0,
                    unit: "°"
                )
                sliderRow(
                    title: "Tight Edge Continuous Turn Speed",
                    value: $controller.gameEngine.tightEdgePanSpeedPxPerSec,
                    range: 400...2800,
                    unit: "px/s"
                )
            }
            .padding(8)
        }
    }

    // MARK: - PUBG Tactical Q/E Roll Lean

    private var pubgTacticalLeanCard: some View {
        GroupBox("🛡️ PUBG Tactical Q/E Roll Peek & ADS Settings") {
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

    private func inAppLauncherButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        url: String
    ) -> some View {
        Button {
            selectedInAppURL = url
            controller.isInAppGameBrowserActive = true
            controller.inAppGameBridge.loadGame(url: url)
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

    private func externalLauncherButton(
        title: String,
        icon: String,
        url: String
    ) -> some View {
        Button {
            controller.isInAppGameBrowserActive = false
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.cyan.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
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
                .frame(width: 260, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f %@", value.wrappedValue, unit))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 85, alignment: .trailing)
        }
    }
}
