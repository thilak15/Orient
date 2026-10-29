import SwiftUI
import OrientCore

struct TargetBenchmarkView: View {
    @Bindable var controller: HeadphoneMotionController

    @State private var targetPosition: CGPoint = CGPoint(x: 240, y: 160)
    @State private var targetRadius: CGFloat = 24
    @State private var targetSpawnTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    @State private var hits: Int = 0
    @State private var misses: Int = 0
    @State private var lastAcquisitionMs: Double = 0
    @State private var bestAcquisitionMs: Double = 0
    @State private var acquisitionHistoryMs: [Double] = []
    @State private var ripplePoint: CGPoint? = nil
    @State private var rippleColor: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Benchmark Metrics Bar
            HStack(spacing: 16) {
                benchmarkStat(title: "HITS", value: "\(hits)", color: .green)
                benchmarkStat(title: "ACCURACY", value: accuracyString, color: .cyan)
                benchmarkStat(
                    title: "LAST FLICK",
                    value: lastAcquisitionMs > 0 ? String(format: "%.0f ms", lastAcquisitionMs) : "—",
                    color: .orange
                )
                benchmarkStat(
                    title: "AVG FLICK",
                    value: averageAcquisitionMs > 0 ? String(format: "%.0f ms", averageAcquisitionMs) : "—",
                    color: .yellow
                )
                benchmarkStat(
                    title: "PIPELINE LAG",
                    value: String(format: "%.1f ms", controller.telemetry.endToEndLatencyMs),
                    color: .mint
                )

                Spacer()

                Picker("Target Size", selection: $targetRadius) {
                    Text("Small (28px)").tag(CGFloat(14))
                    Text("Medium (48px)").tag(CGFloat(24))
                    Text("Large (68px)").tag(CGFloat(34))
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Button("Reset Stats") {
                    hits = 0
                    misses = 0
                    lastAcquisitionMs = 0
                    bestAcquisitionMs = 0
                    acquisitionHistoryMs.removeAll()
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Interactive 2D Target Arena
            GeometryReader { geo in
                ZStack {
                    // Grid background
                    Canvas { context, size in
                        let step: CGFloat = 40
                        var path = Path()
                        var x: CGFloat = 0
                        while x <= size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            x += step
                        }
                        var y: CGFloat = 0
                        while y <= size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += step
                        }
                        context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)

                        // Center crosshair guide
                        var centerPath = Path()
                        centerPath.move(to: CGPoint(x: size.width / 2 - 12, y: size.height / 2))
                        centerPath.addLine(to: CGPoint(x: size.width / 2 + 12, y: size.height / 2))
                        centerPath.move(to: CGPoint(x: size.width / 2, y: size.height / 2 - 12))
                        centerPath.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 + 12))
                        context.stroke(centerPath, with: .color(.cyan.opacity(0.25)), lineWidth: 1.5)
                    }
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.06, green: 0.08, blue: 0.12), Color(red: 0.04, green: 0.05, blue: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                handleArenaClick(at: value.location, in: geo.size)
                            }
                    )

                    // Click Ripple Indicator
                    if let ripple = ripplePoint {
                        Circle()
                            .stroke(rippleColor.opacity(0.75), lineWidth: 2)
                            .frame(width: targetRadius * 2.2, height: targetRadius * 2.2)
                            .position(ripple)
                    }

                    // Active Target Bullseye
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.red, Color.orange.opacity(0.85), Color.red.opacity(0.2)],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: targetRadius
                                )
                            )
                            .frame(width: targetRadius * 2, height: targetRadius * 2)
                            .shadow(color: .red.opacity(0.6), radius: 8)

                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: targetRadius * 1.1, height: targetRadius * 1.1)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                    }
                    .position(targetPosition)
                    .allowsHitTesting(false)

                    // Bottom Overlay Instructions & Live Aim-Freeze Status
                    VStack {
                        HStack {
                            if controller.telemetry.isAimFrozen {
                                Label("AIM-FREEZE LOCKED (85ms Click Stabilization Active)", systemImage: "lock.shield.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.mint.opacity(0.25))
                                    .foregroundStyle(.mint)
                                    .clipShape(Capsule())
                            } else if controller.telemetry.isInEdgePanZone {
                                Label("HYBRID EDGE CONTINUOUS PAN ACTIVE", systemImage: "arrow.left.and.right.circle.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.25))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if let lastGesture = controller.telemetry.lastTriggeredGesture {
                                Text("Last Gesture: \(lastGesture.sourceName) → \(lastGesture.action.rawValue)")
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(10)

                        Spacer()

                        HStack {
                            Text("Move cursor with AirPods Yaw/Pitch • Tilt head (Roll) or nod (Impulse) or click target • Press ⌥Space to toggle cursor control, ⌥R to recenter")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.45))
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .onAppear {
                    spawnTarget(in: geo.size)
                }
            }
        }
    }

    private var accuracyString: String {
        let total = hits + misses
        guard total > 0 else { return "100%" }
        return String(format: "%.0f%%", (Double(hits) / Double(total)) * 100.0)
    }

    private var averageAcquisitionMs: Double {
        guard !acquisitionHistoryMs.isEmpty else { return 0 }
        return acquisitionHistoryMs.reduce(0, +) / Double(acquisitionHistoryMs.count)
    }

    private func handleArenaClick(at point: CGPoint, in size: CGSize) {
        let dx = point.x - targetPosition.x
        let dy = point.y - targetPosition.y
        let dist = sqrt(dx * dx + dy * dy)

        ripplePoint = point
        if dist <= targetRadius + 4 {
            hits += 1
            rippleColor = .green
            let now = ProcessInfo.processInfo.systemUptime
            let elapsedMs = max(15.0, (now - targetSpawnTime) * 1000.0)
            lastAcquisitionMs = elapsedMs
            if bestAcquisitionMs == 0 || elapsedMs < bestAcquisitionMs {
                bestAcquisitionMs = elapsedMs
            }
            acquisitionHistoryMs.append(elapsedMs)
            if acquisitionHistoryMs.count > 30 {
                acquisitionHistoryMs.removeFirst()
            }
            spawnTarget(in: size)
        } else {
            misses += 1
            rippleColor = .red
        }
    }

    private func spawnTarget(in size: CGSize) {
        let margin = max(48.0, targetRadius + 20.0)
        let maxW = max(margin + 20, size.width - margin)
        let maxH = max(margin + 20, size.height - margin - 26)
        targetPosition = CGPoint(
            x: CGFloat.random(in: margin...maxW),
            y: CGFloat.random(in: margin...maxH)
        )
        targetSpawnTime = ProcessInfo.processInfo.systemUptime
    }

    @ViewBuilder
    private func benchmarkStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

