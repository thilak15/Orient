import SwiftUI
import AppKit
import OrientCore

/// Translucent, click-through floating NSPanel that renders over external 3D games
/// without stealing focus or intercepting mouse clicks.
@MainActor
public final class InGameHUDWindowManager {
    private var panel: NSPanel?

    public init() {}

    public func setVisible(_ visible: Bool, controller: HeadphoneMotionController) {
        if visible {
            show(controller: controller)
        } else {
            hide()
        }
    }

    private func show(controller: HeadphoneMotionController) {
        if let existing = panel {
            positionAtTopCenter(existing)
            existing.orderFrontRegardless()
            return
        }

        let hudPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 74),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hudPanel.isFloatingPanel = true
        hudPanel.level = .statusBar
        hudPanel.backgroundColor = .clear
        hudPanel.isOpaque = false
        hudPanel.hasShadow = false
        hudPanel.ignoresMouseEvents = true
        hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hostingView = NSHostingView(rootView: InGameHUDOverlayView(controller: controller))
        hostingView.frame = hudPanel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        hudPanel.contentView = hostingView

        positionAtTopCenter(hudPanel)
        hudPanel.orderFrontRegardless()
        self.panel = hudPanel
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func positionAtTopCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - window.frame.width / 2
        let y = frame.maxY - window.frame.height - 8
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct InGameHUDOverlayView: View {
    @Bindable var controller: HeadphoneMotionController

    var body: some View {
        HStack(spacing: 14) {
            // Live Status Dot + Active / Paused
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.isTrackingActive ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(controller.isTrackingActive ? "ORIENT LIVE" : "PAUSED (⌥Space)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(controller.isTrackingActive ? .green : .orange)
            }

            Divider().frame(height: 28)

            // Mini Non-VR Sweet-Spot Reticle (±5° window)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let boxRect = CGRect(x: center.x - 16, y: center.y - 12, width: 32, height: 24)
                context.stroke(
                    Path(roundedRect: boxRect, cornerRadius: 4),
                    with: .color(.cyan.opacity(0.6)),
                    lineWidth: 1.2
                )
                let scale: CGFloat = 3.0
                let dx = max(-24, min(24, CGFloat(controller.telemetry.relativeAngles.yawDeg) * scale))
                let dy = max(-18, min(18, CGFloat(-controller.telemetry.relativeAngles.pitchDeg) * scale))
                let dotRect = CGRect(x: center.x + dx - 4, y: center.y + dy - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dotRect), with: .color(.green))
            }
            .frame(width: 54, height: 42)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Active Aim Style & Shortcuts
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.gameEngine.aimStyle.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                Text("⌥Space: Start/Stop  •  ⌥R: Recenter  •  ⌥M: Switch Aim Mode")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            // Q / E Tactical Lean & Aim-Freeze Badges
            if controller.gameEngine.currentLeanState != .upright {
                Text(controller.gameEngine.currentLeanState.rawValue)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.28))
                    .foregroundStyle(.yellow)
                    .clipShape(Capsule())
            }

            if controller.telemetry.isAimFrozen {
                Text("AIM-FREEZE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.mint.opacity(0.28))
                    .foregroundStyle(.mint)
                    .clipShape(Capsule())
            }

            Text(String(format: "%.1f ms", controller.telemetry.endToEndLatencyMs))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.mint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.78))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
        .padding(4)
    }
}
