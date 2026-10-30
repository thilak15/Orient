import SwiftUI
import SceneKit
import OrientCore

struct Spatial3DLabView: View {
    @Bindable var controller: HeadphoneMotionController
    @State private var useFirstPersonCamera: Bool = false
    @State private var lockVisualRollWhenAiming: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Mode Selector + Non-VR Screen Aim Mode Bar
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Picker("3D Test Mode", selection: $controller.diagnosticEngine.mode) {
                        ForEach(DiagnosticLabMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(maxWidth: 310)
                    .onChange(of: controller.diagnosticEngine.mode) { _, _ in
                        controller.diagnosticEngine.resetCurrentMode()
                        controller.diagnosticEngine.spawnNext3DTarget()
                    }

                    Picker("View", selection: $useFirstPersonCamera) {
                        Text("3rd-Person Rig").tag(false)
                        Text("1st-Person POV").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)

                    Divider().frame(height: 20)

                    Toggle("Yaw", isOn: $controller.config.enableYawAxis)
                        .toggleStyle(.button)
                        .controlSize(.small)
                    Toggle("Pitch", isOn: $controller.config.enablePitchAxis)
                        .toggleStyle(.button)
                        .controlSize(.small)
                    Toggle("Roll", isOn: $controller.config.enableRollAxis)
                        .toggleStyle(.button)
                        .controlSize(.small)
                    Toggle("Stabilize 3D Roll", isOn: $lockVisualRollWhenAiming)
                        .toggleStyle(.button)
                        .controlSize(.small)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(classificationColor(controller.telemetry.motionClassification.kind))
                            .frame(width: 9, height: 9)
                        Text(controller.telemetry.motionClassification.kind.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(classificationColor(controller.telemetry.motionClassification.kind).opacity(0.18))
                    .foregroundStyle(classificationColor(controller.telemetry.motionClassification.kind))
                    .clipShape(Capsule())
                }

                // Non-VR Flat-Screen Solution Bar (Solves looking away from monitor!)
                HStack(spacing: 14) {
                    Label("Non-VR Screen Aim:", systemImage: "display")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)

                    Picker("", selection: $controller.diagnosticEngine.nonVRAimMode) {
                        ForEach(NonVRScreenAimMode.allCases) { aimMode in
                            Text(aimMode.rawValue).tag(aimMode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 340)

                    if controller.diagnosticEngine.nonVRAimMode == .microAmplified6x ||
                       controller.diagnosticEngine.nonVRAimMode == .rollAndPitchFaceForward {
                        HStack(spacing: 6) {
                            Text("Amplification:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $controller.diagnosticEngine.microGainMultiplier, in: 2.0...12.0)
                                .frame(width: 110)
                            Text(String(format: "%.1fx (±%.0f° Head = Full Screen)", controller.diagnosticEngine.microGainMultiplier, 22.0 / controller.diagnosticEngine.microGainMultiplier))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                    } else if controller.diagnosticEngine.nonVRAimMode == .velocityRateHold {
                        Button("Center Crosshair") {
                            controller.diagnosticEngine.effectiveAimYawDeg = 0
                            controller.diagnosticEngine.effectiveAimPitchDeg = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Mode-Specific Interactive Strip (Guided Wizard OR Diagnostic Metrics)
            modeMetricsStrip

            // Interactive 3D SceneKit Viewport + HUD Legend
            ZStack(alignment: .bottomLeading) {
                SpatialSceneKitContainer(
                    telemetry: controller.telemetry,
                    benchmark: controller.diagnosticEngine,
                    useFirstPersonCamera: useFirstPersonCamera,
                    lockVisualRollWhenAiming: lockVisualRollWhenAiming
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

                // Bottom Vector Legend & Live 6-DOF Readout Overlay
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("3D VECTOR LEGEND")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            legendDot(color: .cyan, label: "Gaze Ray / Yaw (+Z)")
                            legendDot(color: .red, label: "Pitch Axis (+X)")
                            legendDot(color: .green, label: "Roll Axis (+Y)")
                            legendDot(color: .orange, label: "Angular Velocity (ω)")
                            legendDot(color: .pink, label: "True Linear Accel (a)")
                            legendDot(color: .blue, label: "Gravity Vector (g)")
                        }
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(
                            format: "Yaw: %+.1f°  |  Pitch: %+.1f°  |  Roll: %+.1f°  |  Purity: %.0f%%",
                            controller.telemetry.relativeAngles.yawDeg,
                            controller.telemetry.relativeAngles.pitchDeg,
                            controller.telemetry.relativeAngles.rollDeg,
                            controller.telemetry.motionClassification.axisPurityPercent
                        ))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.mint)

                        Text(String(
                            format: "True Linear: %.2fG  |  Peek: %+.2fm  |  Decouple (R→Y: %+.2f, R→P: %+.2f)",
                            controller.telemetry.motionClassification.compensatedLinearAccel.magnitude,
                            controller.diagnosticEngine.lateralPeekMeters,
                            controller.config.decouplingMatrix.rollToYawCoupling,
                            controller.config.decouplingMatrix.rollToPitchCoupling
                        ))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var modeMetricsStrip: some View {
        switch controller.diagnosticEngine.mode {
        case .guidedWizard:
            guidedWizardBanner

        case .axisIsolation:
            HStack(spacing: 16) {
                statPill(title: "YAW PURITY", value: String(format: "%.0f%%", controller.diagnosticEngine.yawPurityScore), color: .cyan)
                statPill(title: "PITCH PURITY", value: String(format: "%.0f%%", controller.diagnosticEngine.pitchPurityScore), color: .red)
                statPill(title: "ROLL PURITY", value: String(format: "%.0f%%", controller.diagnosticEngine.rollPurityScore), color: .green)
                statPill(title: "TRANSLATION IMPULSES", value: "\(controller.diagnosticEngine.translationEventsCount)", color: .pink)

                Spacer()

                if controller.isCalibratingRollBleed {
                    Label("Tilt Head Left & Right Repeatedly (3s)...", systemImage: "waveform.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                } else {
                    Button("Calibrate Roll Cross-Bleed (3s)") {
                        controller.runThreeSecondRollCalibration()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)

                    Button("Reset Matrix") {
                        controller.resetRollCalibration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .coverPeekAndJump:
            HStack(spacing: 16) {
                statPill(
                    title: "COVER LINE OF SIGHT",
                    value: controller.diagnosticEngine.isLineOfSightBlockedByCover ? "BLOCKED BY PILLAR" : "CLEAR (PEEKING)",
                    color: controller.diagnosticEngine.isLineOfSightBlockedByCover ? .red : .green
                )
                statPill(
                    title: "LATERAL PEEK (ROLL >9°)",
                    value: String(format: "%+.2f m", controller.diagnosticEngine.lateralPeekMeters),
                    color: .yellow
                )
                statPill(
                    title: "VERTICAL STANCE (Z-ACCEL)",
                    value: String(format: "%+.2f m", controller.diagnosticEngine.verticalStanceMeters),
                    color: .pink
                )
                statPill(
                    title: "COVER TARGETS HIT",
                    value: "\(controller.diagnosticEngine.domeTargetsHit)",
                    color: .mint
                )
                Spacer()
                Text("Tilt ear-to-shoulder (>10° Roll) to slide around the red 3D pillar or nod/jump vertically to clear cover!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .targetDome360:
            HStack(spacing: 16) {
                statPill(
                    title: "3D DOME TARGETS HIT",
                    value: "\(controller.diagnosticEngine.domeTargetsHit)",
                    color: .green
                )
                statPill(
                    title: "NEXT TARGET (AZ / EL)",
                    value: String(format: "%+.0f° / %+.0f°", controller.diagnosticEngine.targetAzimuthDeg, controller.diagnosticEngine.targetElevationDeg),
                    color: .orange
                )
                statPill(
                    title: "CURRENT GAZE (Y / P)",
                    value: String(format: "%+.1f° / %+.1f°", controller.telemetry.relativeAngles.yawDeg, controller.telemetry.relativeAngles.pitchDeg),
                    color: .cyan
                )
                Spacer()
                Button("Skip Target") {
                    controller.diagnosticEngine.spawnNext3DTarget()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .whipDriftTest:
            HStack(spacing: 16) {
                statPill(
                    title: "WHIP EXCURSION (>100°/s)",
                    value: controller.diagnosticEngine.hasCompletedWhipExcursion ? "COMPLETED" : "TURN HEAD FAST >20°",
                    color: controller.diagnosticEngine.hasCompletedWhipExcursion ? .green : .orange
                )
                statPill(
                    title: "PEAK WHIP SPEED",
                    value: String(format: "%.0f °/s", controller.diagnosticEngine.peakWhipSpeedDegPerSec),
                    color: .cyan
                )
                statPill(
                    title: "RETURN-TO-CENTER DRIFT",
                    value: controller.diagnosticEngine.measuredReturnDriftDeg != nil
                        ? String(format: "%.2f°", controller.diagnosticEngine.measuredReturnDriftDeg!)
                        : "Return to Center & Hold",
                    color: .yellow
                )
                Spacer()
                Button("Reset Whip Test") {
                    controller.diagnosticEngine.resetCurrentMode()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Guided 5-Step Feasibility & Calibration Banner

    private var guidedWizardBanner: some View {
        let step = controller.diagnosticEngine.wizardStep
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(step.title, systemImage: step == .completed ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(step == .completed ? .green : .cyan)

                Spacer()

                if step == .step2YawLeftRight || step == .step3PitchUpDown || step == .step4RollPeekLeftRight {
                    HStack(spacing: 10) {
                        Label(
                            step == .step3PitchUpDown ? "Up (+12°)" : "Left Target",
                            systemImage: controller.diagnosticEngine.didHitLeftCriterion ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(controller.diagnosticEngine.didHitLeftCriterion ? .green : .secondary)

                        Label(
                            step == .step3PitchUpDown ? "Down (-12°)" : "Right Target",
                            systemImage: controller.diagnosticEngine.didHitRightCriterion ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(controller.diagnosticEngine.didHitRightCriterion ? .green : .secondary)
                    }
                } else if step == .step5TargetShootout {
                    Text("Targets Locked: \(controller.diagnosticEngine.domeTargetsHit) / 3")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                ProgressView(value: controller.diagnosticEngine.wizardStepProgress)
                    .frame(width: 110)
                    .tint(.green)

                if step != .completed {
                    Button("Skip Step →") {
                        if let next = GuidedWizardStep(rawValue: step.rawValue + 1) {
                            if next == .step5TargetShootout {
                                controller.diagnosticEngine.spawnNext3DTarget()
                            }
                            controller.diagnosticEngine.advanceWizardStep(to: next)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Restart Wizard") {
                    controller.recenterPose()
                    controller.diagnosticEngine.resetCurrentMode()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                Text(step.instruction)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if step == .completed {
                    Text(String(
                        format: "Resting Noise: %.1f°/s  •  Yaw→Roll Bleed: %.1f°  •  Verdict: Ready for 120Hz Aim + Q/E Roll Peek!",
                        controller.diagnosticEngine.measuredRestingNoiseDegPerSec,
                        controller.diagnosticEngine.measuredMaxRollBleedDuringYawDeg
                    ))
                    .font(.caption.bold())
                    .foregroundStyle(.mint)
                }
            }
        }
        .padding(10)
        .background(Color.cyan.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func classificationColor(_ kind: MotionKind) -> Color {
        switch kind {
        case .stationary: return .secondary
        case .pureYaw: return .cyan
        case .purePitch: return .orange
        case .pureRoll: return .green
        case .linearTranslation: return .pink
        case .compoundMotion: return .yellow
        }
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private func statPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

// MARK: - SceneKit 3D Spatial Room & 6-DOF Rig Representable

private struct SpatialSceneKitContainer: NSViewRepresentable {
    var telemetry: TelemetrySnapshot
    var benchmark: DiagnosticBenchmarkEngine
    var useFirstPersonCamera: Bool
    var lockVisualRollWhenAiming: Bool

    final class Coordinator {
        let scene = SCNScene()
        let thirdPersonCameraNode = SCNNode()
        let firstPersonCameraNode = SCNNode()
        let headRigNode = SCNNode()
        let gazeLaserNode = SCNNode()
        let omegaVectorNode = SCNNode()
        let linearAccelVectorNode = SCNNode()
        let gravityVectorNode = SCNNode()
        let coverPillarNode = SCNNode()
        let targetSphereNode = SCNNode()
        let leftGuideGateNode = SCNNode()
        let rightGuideGateNode = SCNNode()

        init() {
            setupScene()
        }

        private func setupScene() {
            scene.background.contents = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.10, alpha: 1.0)

            // Ambient & Directional Lights
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            ambient.light?.color = NSColor(calibratedWhite: 0.85, alpha: 1.0)
            scene.rootNode.addChildNode(ambient)

            let keyLight = SCNNode()
            keyLight.light = SCNLight()
            keyLight.light?.type = .directional
            keyLight.light?.intensity = 900
            keyLight.eulerAngles = SCNVector3(-0.6, 0.4, 0)
            scene.rootNode.addChildNode(keyLight)

            // 3rd-Person Camera
            let cam3 = SCNCamera()
            cam3.fieldOfView = 55
            cam3.zNear = 0.05
            cam3.zFar = 50.0
            thirdPersonCameraNode.camera = cam3
            thirdPersonCameraNode.position = SCNVector3(0, 0.85, 2.55)
            thirdPersonCameraNode.eulerAngles = SCNVector3(-0.18, 0, 0)
            scene.rootNode.addChildNode(thirdPersonCameraNode)

            // Floor & Coordinate Grid Walls + Depth Markers (-1.5m, -3.0m, -4.5m)
            let floorBox = SCNBox(width: 10.0, height: 0.02, length: 10.0, chamferRadius: 0)
            floorBox.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1.0)
            let floorNode = SCNNode(geometry: floorBox)
            floorNode.position = SCNVector3(0, -1.1, -2.0)
            scene.rootNode.addChildNode(floorNode)

            for depth in [1.5, 3.0, 4.5] {
                let archTorus = SCNTorus(ringRadius: 2.2, pipeRadius: 0.01)
                archTorus.firstMaterial?.diffuse.contents = NSColor.white.withAlphaComponent(0.12)
                let archNode = SCNNode(geometry: archTorus)
                archNode.position = SCNVector3(0, 0, -CGFloat(depth))
                archNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
                scene.rootNode.addChildNode(archNode)
            }

            // Concentric Reference Rings on 4.8m Target Dome
            for deg in [10.0, 20.0, 30.0] {
                let radius = CGFloat(4.8 * sin(deg * Double.pi / 180.0))
                let torus = SCNTorus(ringRadius: radius, pipeRadius: 0.015)
                torus.firstMaterial?.diffuse.contents = NSColor.systemCyan.withAlphaComponent(0.22)
                let ringNode = SCNNode(geometry: torus)
                ringNode.position = SCNVector3(0, 0, -4.8)
                ringNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
                scene.rootNode.addChildNode(ringNode)
            }

            // Build 3D Head & AirPods Avatar Rig
            let headSphere = SCNSphere(radius: 0.26)
            headSphere.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.34, alpha: 0.92)
            headSphere.firstMaterial?.specular.contents = NSColor.white
            let headMesh = SCNNode(geometry: headSphere)
            headRigNode.addChildNode(headMesh)

            let visor = SCNBox(width: 0.38, height: 0.12, length: 0.12, chamferRadius: 0.03)
            visor.firstMaterial?.diffuse.contents = NSColor.systemCyan
            let visorNode = SCNNode(geometry: visor)
            visorNode.position = SCNVector3(0, 0.04, -0.22)
            headRigNode.addChildNode(visorNode)

            for side in [-1.0, 1.0] {
                let pod = SCNCapsule(capRadius: 0.045, height: 0.16)
                pod.firstMaterial?.diffuse.contents = NSColor.white
                let podNode = SCNNode(geometry: pod)
                podNode.position = SCNVector3(side * 0.28, -0.02, 0.0)
                headRigNode.addChildNode(podNode)
            }

            headRigNode.addChildNode(makeAxisRod(length: 0.75, color: .systemRed, axis: .x))
            headRigNode.addChildNode(makeAxisRod(length: 0.75, color: .systemGreen, axis: .y))
            headRigNode.addChildNode(makeAxisRod(length: 0.75, color: .systemCyan, axis: .z))

            let laserCyl = SCNCylinder(radius: 0.012, height: 5.2)
            laserCyl.firstMaterial?.diffuse.contents = NSColor.systemCyan
            laserCyl.firstMaterial?.emission.contents = NSColor.systemCyan
            gazeLaserNode.geometry = laserCyl
            gazeLaserNode.position = SCNVector3(0, 0, -2.6)
            gazeLaserNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            headRigNode.addChildNode(gazeLaserNode)

            let cam1 = SCNCamera()
            cam1.fieldOfView = 68
            cam1.zNear = 0.05
            cam1.zFar = 50.0
            firstPersonCameraNode.camera = cam1
            firstPersonCameraNode.position = SCNVector3(0, 0.05, -0.28)
            headRigNode.addChildNode(firstPersonCameraNode)

            scene.rootNode.addChildNode(headRigNode)

            // Dynamic 3D Vectors Attached to Head Rig
            let omegaCyl = SCNCylinder(radius: 0.020, height: 0.55)
            omegaCyl.firstMaterial?.diffuse.contents = NSColor.systemOrange
            omegaCyl.firstMaterial?.emission.contents = NSColor.systemOrange
            omegaVectorNode.geometry = omegaCyl
            headRigNode.addChildNode(omegaVectorNode)

            let accelCyl = SCNCylinder(radius: 0.024, height: 0.55)
            accelCyl.firstMaterial?.diffuse.contents = NSColor.systemPink
            accelCyl.firstMaterial?.emission.contents = NSColor.systemPink
            linearAccelVectorNode.geometry = accelCyl
            headRigNode.addChildNode(linearAccelVectorNode)

            let gravCyl = SCNCylinder(radius: 0.016, height: 0.50)
            gravCyl.firstMaterial?.diffuse.contents = NSColor.systemBlue
            gravCyl.firstMaterial?.emission.contents = NSColor.systemBlue
            gravityVectorNode.geometry = gravCyl
            headRigNode.addChildNode(gravityVectorNode)

            // 3D Cover Pillar for Mode 2 (Cover-Peek & Crouch/Jump) at z = -2.8m
            let pillarBox = SCNBox(width: 0.68, height: 1.5, length: 0.25, chamferRadius: 0.02)
            pillarBox.firstMaterial?.diffuse.contents = NSColor.systemRed.withAlphaComponent(0.55)
            coverPillarNode.geometry = pillarBox
            coverPillarNode.position = SCNVector3(0, -0.35, -2.8)
            scene.rootNode.addChildNode(coverPillarNode)

            // 3D Target Sphere
            let targetGeom = SCNSphere(radius: 0.24)
            targetGeom.firstMaterial?.diffuse.contents = NSColor.systemOrange
            targetGeom.firstMaterial?.emission.contents = NSColor.systemRed
            targetSphereNode.geometry = targetGeom
            targetSphereNode.position = SCNVector3(0, 0, -4.8)
            scene.rootNode.addChildNode(targetSphereNode)

            // Guided Wizard Left & Right / Up & Down 3D Guide Gates
            for node in [leftGuideGateNode, rightGuideGateNode] {
                let gateTorus = SCNTorus(ringRadius: 0.34, pipeRadius: 0.035)
                gateTorus.firstMaterial?.diffuse.contents = NSColor.systemYellow
                gateTorus.firstMaterial?.emission.contents = NSColor.systemYellow.withAlphaComponent(0.5)
                node.geometry = gateTorus
                node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
                node.isHidden = true
                scene.rootNode.addChildNode(node)
            }
        }

        private enum AxisDir { case x, y, z }
        private func makeAxisRod(length: CGFloat, color: NSColor, axis: AxisDir) -> SCNNode {
            let cyl = SCNCylinder(radius: 0.01, height: length)
            cyl.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: cyl)
            switch axis {
            case .x:
                node.position = SCNVector3(length / 2, 0, 0)
                node.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
            case .y:
                node.position = SCNVector3(0, length / 2, 0)
            case .z:
                node.position = SCNVector3(0, 0, -length / 2)
                node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            }
            return node
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.thirdPersonCameraNode
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let coord = context.coordinator
        nsView.pointOfView = useFirstPersonCamera ? coord.firstPersonCameraNode : coord.thirdPersonCameraNode

        let deg2rad = CGFloat.pi / 180.0
        // Use amplified / Non-VR effective aim angles so user only moves head ±3-4° while keeping eyes on the monitor!
        let yawRad = CGFloat(-benchmark.effectiveAimYawDeg) * deg2rad
        let pitchRad = CGFloat(benchmark.effectiveAimPitchDeg) * deg2rad

        // Only apply full visual Roll to the 3D head when testing Roll (or when Stabilize 3D Roll is unchecked)
        let isRollFocusedStep = (benchmark.mode == .coverPeekAndJump) ||
            (benchmark.mode == .guidedWizard && benchmark.wizardStep == .step4RollPeekLeftRight) ||
            !lockVisualRollWhenAiming
        let effectiveRollDeg = isRollFocusedStep ? telemetry.relativeAngles.rollDeg : (telemetry.relativeAngles.rollDeg * 0.12)
        let rollRad = CGFloat(-effectiveRollDeg) * deg2rad

        // 1. Update 3D Head Rig Position & Orientation
        coord.headRigNode.position = SCNVector3(
            CGFloat(benchmark.lateralPeekMeters),
            CGFloat(benchmark.verticalStanceMeters),
            0
        )
        coord.headRigNode.eulerAngles = SCNVector3(pitchRad, yawRad, rollRad)

        // 2. Update Guided Wizard 3D Gate Rings (Steps 2, 3, 4)
        updateWizardGuideGates(coord: coord)

        // 3. Show/Hide 3D Cover Pillar & Target Sphere
        coord.coverPillarNode.isHidden = (benchmark.mode != .coverPeekAndJump)
        let showTarget = (benchmark.mode == .coverPeekAndJump ||
                          benchmark.mode == .targetDome360 ||
                          (benchmark.mode == .guidedWizard && benchmark.wizardStep == .step5TargetShootout))
        coord.targetSphereNode.isHidden = !showTarget

        if showTarget {
            let pos3D = benchmark.targetPosition3D(domeRadiusMeters: 4.8)
            coord.targetSphereNode.position = SCNVector3(pos3D.x, pos3D.y, pos3D.z)

            let mat = coord.targetSphereNode.geometry?.firstMaterial
            if benchmark.isCrosshairOn3DTarget {
                mat?.diffuse.contents = NSColor.systemGreen
                mat?.emission.contents = NSColor.systemGreen
            } else {
                mat?.diffuse.contents = NSColor.systemOrange
                mat?.emission.contents = NSColor.systemRed
            }
        }

        let laserMat = coord.gazeLaserNode.geometry?.firstMaterial
        if benchmark.isLineOfSightBlockedByCover {
            laserMat?.diffuse.contents = NSColor.systemRed
            laserMat?.emission.contents = NSColor.systemRed
        } else if benchmark.isCrosshairOn3DTarget {
            laserMat?.diffuse.contents = NSColor.systemGreen
            laserMat?.emission.contents = NSColor.systemGreen
        } else {
            laserMat?.diffuse.contents = NSColor.systemCyan
            laserMat?.emission.contents = NSColor.systemCyan
        }

        // 4. Orient & Scale 3D Vectors Attached to Head Rig
        let omegaVec = Vector3(
            x: telemetry.rawPitchRateDegPerSec / 90.0,
            y: telemetry.rawYawRateDegPerSec / 90.0,
            z: -telemetry.rawRollRateDegPerSec / 90.0
        )
        orientVectorNode(coord.omegaVectorNode, vector: omegaVec, baseOffset: SCNVector3(-0.36, 0.28, 0))

        let linAccel = telemetry.motionClassification.compensatedLinearAccel
        let scaledAccel = Vector3(x: linAccel.x * 2.2, y: linAccel.z * 2.2, z: -linAccel.y * 2.2)
        orientVectorNode(coord.linearAccelVectorNode, vector: scaledAccel, baseOffset: SCNVector3(0.36, 0.28, 0))

        let grav = telemetry.gravityVector
        let scaledGrav = Vector3(x: grav.x * 0.9, y: grav.z * 0.9, z: -grav.y * 0.9)
        orientVectorNode(coord.gravityVectorNode, vector: scaledGrav, baseOffset: SCNVector3(0, -0.36, 0))
    }

    private func updateWizardGuideGates(coord: Coordinator) {
        guard benchmark.mode == .guidedWizard else {
            coord.leftGuideGateNode.isHidden = true
            coord.rightGuideGateNode.isHidden = true
            return
        }

        switch benchmark.wizardStep {
        case .step2YawLeftRight:
            coord.leftGuideGateNode.isHidden = false
            coord.rightGuideGateNode.isHidden = false
            coord.leftGuideGateNode.position = SCNVector3(-1.45, 0, -4.6)
            coord.rightGuideGateNode.position = SCNVector3(1.45, 0, -4.6)
            colorGate(coord.leftGuideGateNode, passed: benchmark.didHitLeftCriterion)
            colorGate(coord.rightGuideGateNode, passed: benchmark.didHitRightCriterion)
        case .step3PitchUpDown:
            coord.leftGuideGateNode.isHidden = false
            coord.rightGuideGateNode.isHidden = false
            coord.leftGuideGateNode.position = SCNVector3(0, 1.05, -4.6)
            coord.rightGuideGateNode.position = SCNVector3(0, -1.05, -4.6)
            colorGate(coord.leftGuideGateNode, passed: benchmark.didHitLeftCriterion)
            colorGate(coord.rightGuideGateNode, passed: benchmark.didHitRightCriterion)
        case .step4RollPeekLeftRight:
            coord.leftGuideGateNode.isHidden = false
            coord.rightGuideGateNode.isHidden = false
            coord.leftGuideGateNode.position = SCNVector3(-0.95, 0.45, -2.5)
            coord.rightGuideGateNode.position = SCNVector3(0.95, 0.45, -2.5)
            colorGate(coord.leftGuideGateNode, passed: benchmark.didHitLeftCriterion)
            colorGate(coord.rightGuideGateNode, passed: benchmark.didHitRightCriterion)
        default:
            coord.leftGuideGateNode.isHidden = true
            coord.rightGuideGateNode.isHidden = true
        }
    }

    private func colorGate(_ node: SCNNode, passed: Bool) {
        let color: NSColor = passed ? .systemGreen : .systemYellow
        node.geometry?.firstMaterial?.diffuse.contents = color
        node.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.6)
    }

    private func orientVectorNode(_ node: SCNNode, vector: Vector3, baseOffset: SCNVector3) {
        let mag = max(0.06, min(2.0, vector.magnitude))
        node.scale = SCNVector3(1, CGFloat(mag), 1)
        node.position = baseOffset
        if vector.magnitude > 0.02 {
            let nx = vector.x / vector.magnitude
            let ny = vector.y / vector.magnitude
            let nz = vector.z / vector.magnitude
            let pitch = atan2(nz, ny)
            let roll = -asin(max(-1.0, min(1.0, nx)))
            node.eulerAngles = SCNVector3(CGFloat(pitch), 0, CGFloat(roll))
        }
    }
}
