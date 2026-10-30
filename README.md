# Orient — Ultra-Low-Latency AirPods 6-DOF Gaming & Cursor Controller for macOS

**Orient** transforms Apple AirPods (Pro, Max, 3rd Gen+) into a 120Hz, sub-pixel-accurate head-tracking mouse and tactical 3D FPS gaming controller on macOS using `CMHeadphoneMotionManager`, Casiez **1-Euro adaptive low-pass filtering**, **TrackIR/Opentrack Accela Non-Linear 6x Micro-Gain**, **Auto-Ratchet Turn-Commit**, **Closed-Loop Horizon Synchronization**, **Pre-Click Cursor Rollback**, and **Aim-Freeze Stabilization**.

> 📖 **Deep-Dive Engineering & Research Chronicle**: See [`docs/ENGINEERING_AND_RESEARCH_CHRONICLE.md`](docs/ENGINEERING_AND_RESEARCH_CHRONICLE.md) for the complete technical walkthrough of every hardware, macOS systems, ergonomic, and 3D FPS gameplay challenge we encountered across Phases 1–3 and how each was solved.

---

## Roadmap & Phased Architecture

### ✅ Phase 1: 120Hz Low-Latency macOS Cursor Control & 2D Telemetry Lab (Completed)
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

### ✅ Phase 2: Interactive 3D Head-Tracking & Motion Disambiguation Lab (Issue #1 — Completed)
- **Real-Time 3D SceneKit Spatial Arena & 3D Head Avatar**: Visualize live 3D head orientation, coordinate axes, angular velocity vectors, gravity vector, and linear acceleration (`userAcceleration`) vectors in real time.
- **6-DOF Motion Disambiguation & Classifier (`MotionClassifier` & `CrossAxisCalibrator`)**:
  - Cleanly separate **Pure Yaw Turn** vs. **Pure Pitch Nod** vs. **Pure Roll Tilt (Ear-to-Shoulder)** vs. **Physical Head Translation / Jolt**.
  - **Anatomical Neck-Pivot Decoupling & Cross-Axis Bleed Cancellation**: Least-squares calibration and kinematic neck-pivot lever-arm subtraction ($\vec{r} = 8.5\text{ cm}$).
- **Interactive 3D Diagnostic & Calibration Suite + Guided 5-Step Feasibility Wizard**:
  1. **Axis Isolation & Bleed Test**: Guided Yaw, Pitch, Roll, and Linear Impulse trials scoring axis purity (%).
  2. **3D Cover-Peek & Translation Sandbox**: Test leaning left/right (`Roll`) around 3D cover pillars and 360° target tracking.
  3. **Quaternion Drift & Return-to-Center Benchmark**: Quantify angular drift in degrees after rapid multi-axis head movements.

### ✅ Phase 3: External 3D FPS Game Integration, PUBG Tactical Suite & In-Game HUD (Issue #2 — Completed)
- **Sub-Pixel Integer `CGEvent` Pointer-Lock Delta Injection**: Accumulates fractional sub-pixel deltas at 120Hz into `kCGMouseEventDeltaX` / `kCGMouseEventDeltaY` (`int64_t`) while keeping the cursor anchored inside the active game window.
- **TrackIR / Opentrack "Accela" 6x Non-Linear Micro-Gain + Auto-Ratchet Turn-Commit**:
  - **Auto-Ratchet Turn-Commit (`stepAutoRatchetYaw`)**: Turning your head past `±1.5°` rotates the 3D camera into the new hallway, and returning your head to the center of the monitor (`0°`) clutches the return stroke (`ΔX = 0`) so your character stays facing the new direction with zero pull-back.
  - **Closed-Loop Horizon Synchronization (`onRecenterPressed`)**: Tracks vertical camera displacement (`virtualCameraY`) so returning your head to level posture or pressing `⌥R` physically snaps the in-game 3D screen back to the level horizon.
- **Tactical Game Action Bindings**: Roll Left/Right → `Q`/`E` Peek/Lean hold with hysteresis, automatic **ADS Sensitivity Slowdown**, and emulator touch-drag anchor resets.
- **Translucent Click-Through In-Game HUD Overlay**: Always-on-top floating reticle & status bar over external fullscreen games.

---

## Building & Running

```bash
# Run unit tests
swift test

# Package, sign, and launch Orient.app (with NSMotionUsageDescription for AirPods TCC)
./scripts/build_app.sh
open /tmp/OrientAppBuild/Orient.app
```

### Global Shortcuts (Carbon `RegisterEventHotKey` — Works in Fullscreen Games)
| Shortcut | Action |
| :--- | :--- |
| `Option + Space` (`⌥Space`) | Start / Stop AirPods Aiming (Emergency Kill-Switch) |
| `Option + R` (`⌥R`) | Instant Recenter Head Pose & Snap In-Game Vertical Horizon to Center |
| `Option + M` (`⌥M`) | Live Cycle Between the 4 Non-VR In-Game Aim Styles |
| `Option + C` (`⌥C`) | Toggle Clutch (reposition neck freely; releasing re-anchors center) |

