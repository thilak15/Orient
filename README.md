# Orient — Ultra-Low-Latency AirPods 6-DOF Gaming & Cursor Controller for macOS

**Orient** transforms Apple AirPods (Pro, Max, 3rd Gen+) into a 120Hz, sub-pixel-accurate head-tracking mouse and tactical gaming controller on macOS using `CMHeadphoneMotionManager`, Casiez **1-Euro adaptive low-pass filtering**, **Pre-Click Cursor Rollback**, and **Aim-Freeze Stabilization**.

---

## Roadmap & Phased Architecture

### ✅ Phase 1: 120Hz Low-Latency macOS Cursor Control & 2D Telemetry Lab (Current)
- **Dedicated `.userInteractive` 120Hz Cursor Engine (`BackgroundCursorWorker`)**: Decouples AirPods Bluetooth packet arrival from display refresh rate and keeps the SwiftUI main thread 100% responsive.
- **Hybrid Aiming Model**:
  - **Center Zone (1:1 Gyro Delta)**: Uses raw gyroscope `rotationRate` (rad/s) for zero-phase-lag flicks and micro-tracking.
  - **Edge Zone (Continuous Rate Pan)**: Holding your head past a configurable Yaw/Pitch threshold smoothly pans the cursor across large displays.
- **1-Euro Adaptive Low-Pass Filter**: Suppresses resting head tremor while raising the cutoff frequency proportionally to head speed so fast flicks experience near-zero phase delay.
- **Click Gestures + 45ms Pre-Click Rollback + 85ms Aim-Freeze**:
  - **Roll Left / Right Tilt** (ear-to-shoulder with hysteresis) and **Linear Acceleration Impulses** (nod / vertical jolt) trigger synthetic mouse clicks.
  - Rewinds the cursor to its pre-gesture coordinate (`45ms` ring-buffer rollback) and freezes motion for `85ms` so clicking with a head motion never shifts the cursor off a button.
- **Silent Bluetooth Audio Keep-Alive**: Zero-amplitude `AVAudioSourceNode` keeps AirPods in high-frequency motion polling mode.
- **Built-in 2D Target & Latency Benchmark Pad**: Interactive target range measuring flick acquisition time (ms), hit accuracy (%), and pipeline latency.

### 🚧 Phase 2: Interactive 3D Head-Tracking & Motion Disambiguation Lab (Issue #1)
- **Real-Time 3D SceneKit Spatial Arena & 3D Head Avatar**: Visualize live 3D head orientation, coordinate axes, angular velocity vectors, gravity vector, and linear acceleration (`userAcceleration`) vectors in real time.
- **6-DOF Motion Disambiguation & Classifier**:
  - Cleanly separate **Pure Yaw Turn** vs. **Pure Pitch Nod** vs. **Pure Roll Tilt (Ear-to-Shoulder)** vs. **Physical Head Translation / Jolt** (forward/back/lateral/vertical linear motion).
  - **Anatomical Neck-Pivot Decoupling & Cross-Axis Bleed Cancellation**: Measure and cancel unintended Yaw/Pitch rotation and ear translation caused by natural human neck biomechanics when tilting the head (Roll).
- **Interactive 3D Diagnostic & Calibration Suite**:
  1. **Axis Isolation & Bleed Test**: Guided Yaw, Pitch, Roll, and Linear Impulse trials scoring axis purity (%) and auto-tuning decoupling matrices.
  2. **3D Cover-Peek & Translation Sandbox**: Test leaning left/right (`Roll`) around 3D cover pillars, crouching/jumping (`Z-axis acceleration`), and 360° target tracking inside a 3D dome.
  3. **Quaternion Drift & Return-to-Center Benchmark**: Quantify angular drift in degrees after rapid multi-axis head movements.

### 🎮 Phase 3: External 3D FPS Game Integration, PUBG Tactical Suite & In-Game HUD (Issue #2)
- **Pointer-Lock Raw Delta HID Injection**: Hardware-level `mouseEventDeltaX` / `mouseEventDeltaY` injection for 3D FPS games (*Combat Master*, *Counter-Strike*, Browser FPS like *Deadshot.io* / *Krunker.io*, and *PUBG: Battlegrounds* via GeForce NOW).
- **Emulator Touch-Drag Mode**: Virtual `leftMouseDragged` touch-look injection for *PUBG Mobile* on BlueStacks Air (Apple Silicon).
- **Tactical Game Action Bindings**: Roll Left/Right → `Q`/`E` Peek/Lean hold or toggle, automatic **ADS Sensitivity Slowdown** while scoped in, and impulse-driven Fire/Reload/Jump.
- **Translucent Click-Through In-Game HUD Overlay**: Always-on-top floating reticle & horizon indicator over external fullscreen games.

---

## Building & Running

```bash
# Run unit tests
swift test

# Package, sign, and launch Orient.app (with NSMotionUsageDescription for AirPods TCC)
./scripts/build_app.sh
open ./build/Orient.app
```

### Global Shortcuts
| Shortcut | Action |
| :--- | :--- |
| `Option + Space` (`⌥Space`) | Start / Stop Cursor Control (Emergency Kill-Switch) |
| `Option + R` (`⌥R`) | Instant Recenter Neutral Head Pose |
| `Option + C` (`⌥C`) | Toggle Clutch (reposition neck freely; releasing re-anchors center) |
