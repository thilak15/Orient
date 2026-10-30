import SwiftUI
import AppKit
import OrientCore

struct GameIntegrationView: View {
    @Bindable var controller: HeadphoneMotionController
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Instant 1-Click External FPS Game Launchers
                GroupBox("🚀 Step 1: Launch a Real 3D FPS Game (Browser Pointer-Lock or Cloud PUBG)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Click any game below to open it, automatically enable the Floating Click-Through In-Game HUD at the top of your screen, and press ⌥Space once inside the match to aim with your AirPods!")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            gameLauncherButton(
                                title: "Play Deadshot.io (Instant 3D FPS)",
                                subtitle: "Zero install • Fast 120Hz Pointer-Lock",
                                icon: "scope",
                                color: .green,
                                url: "https://deadshot.io"
                            )
                            gameLauncherButton(
                                title: "Play Krunker.io (Tactical FPS)",
                                subtitle: "Zero install • Supports Q/E & ADS",
                                icon: "flame.fill",
                                color: .orange,
                                url: "https://krunker.io"
                            )
                            gameLauncherButton(
                                title: "Play Ev.io (Sci-Fi Arena FPS)",
                                subtitle: "Zero install • Instant Spawn",
                                icon: "bolt.shield.fill",
                                color: .cyan,
                                url: "https://ev.io"
                            )
                            gameLauncherButton(
                                title: "PUBG on GeForce NOW",
                                subtitle: "Cloud PC PUBG • Full Q/E Peek",
                                icon: "cloud.fill",
                                color: .yellow,
                                url: "https://play.geforcenow.com"
                            )
                        }
                    }
                    .padding(8)
                }

                // 2. Floating HUD & Non-VR In-Game Aim Style Selector (⌥M to cycle in-game!)
                GroupBox("🎯 Step 2: Choose Non-VR In-Game Aim Style (Press ⌥M Anytime In-Game to Switch!)") {
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

                // 3. PUBG Q/E Tactical Roll Leaning & Emulator Touch-Drag Settings
                GroupBox("🛡️ Step 3: PUBG Tactical Q/E Roll Peek & ADS Settings") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Current Lean Key State:")
                                .font(.subheadline.bold())
                            Text(controller.gameEngine.currentLeanState.rawValue)
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(controller.gameEngine.currentLeanState == .upright ? Color.secondary.opacity(0.18) : Color.yellow.opacity(0.28))
                                .foregroundStyle(controller.gameEngine.currentLeanState == .upright ? Color.secondary : Color.yellow)
                                .clipShape(Capsule())
                            Spacer()
                            Text("Tilting ear-to-shoulder holds down Q (Left) or E (Right) in-game; returning upright releases the key.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        sliderRow(
                            title: "Q/E Lean Trigger Roll Angle",
                            value: $controller.gameEngine.leanTriggerAngleDeg,
                            range: 6.0...22.0,
                            unit: "°"
                        )
                        sliderRow(
                            title: "Q/E Lean Release Angle (Hysteresis)",
                            value: $controller.gameEngine.leanReleaseAngleDeg,
                            range: 3.0...15.0,
                            unit: "°"
                        )
                        sliderRow(
                            title: "ADS Scoped Sensitivity Multiplier",
                            value: $controller.gameEngine.adsMultiplier,
                            range: 0.20...0.90,
                            unit: "x"
                        )
                    }
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private func gameLauncherButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        url: String
    ) -> some View {
        Button {
            controller.isFloatingHUDVisible = true
            if let targetURL = URL(string: url) {
                NSWorkspace.shared.open(targetURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
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
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .frame(width: 280, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f %@", value.wrappedValue, unit))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 85, alignment: .trailing)
        }
    }
}
