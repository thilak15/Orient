import SwiftUI
import AppKit

@main
struct OrientApp: App {
    @State private var controller = HeadphoneMotionController()

    init() {
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false,
            "ApplePersistenceIgnoreState": true
        ])
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Orient — AirPods Low-Latency Cursor Lab") {
            OrientDashboardView(controller: controller)
                .preferredColorScheme(.dark)
                .onAppear {
                    controller.startEngineIfNeeded()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1060, height: 700)

        MenuBarExtra(
            "Orient",
            systemImage: controller.isTrackingActive ? "airpodspro.chargingcase.wireless.fill" : "airpodspro"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Orient • AirPods Cursor Control")
                    .font(.headline)
                Text(controller.sensorState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Button(controller.isTrackingActive ? "Stop Cursor Control (⌥Space)" : "Start Cursor Control (⌥Space)") {
                    controller.toggleTracking()
                }
                .keyboardShortcut(" ", modifiers: [.option])

                Button("Recenter Neutral Head Pose (⌥R)") {
                    controller.recenterPose()
                }
                .keyboardShortcut("r", modifiers: [.option])

                Button(controller.telemetry.isClutchHeld ? "Release Clutch (⌥C)" : "Hold Clutch (⌥C)") {
                    controller.setClutchHeld(!controller.telemetry.isClutchHeld)
                }

                Divider()

                Toggle("Synthetic IMU Simulator", isOn: $controller.isSimulatorEnabled)

                Divider()

                Button("Quit Orient") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(6)
        }
    }
}
