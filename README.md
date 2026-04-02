# 🥁 MacBeat

**Turn your MacBook into a professional drum machine.** MacBeat is a high-performance macOS Menu Bar app that uses your laptop's built-in accelerometer to detect physical strikes on the chassis, triggering drum samples with ultra-low latency.

---

## 🔥 Key Features

### 1. Two Performance Modes
*   **Standard Mode**: Real-time triggering of "Kick" and "Snare" (or "Bongo 1" and "Bongo 2"). Use vertical strikes for kicks and lateral strikes for snares. Includes "Invert Sides" for southpaw drummers.
*   **Looper Mode**: Dynamic pattern recording. Tap a beat, and MacBeat will automatically detect the BPM, quantize your performance, and loop it. Layer more instruments by switching pads mid-session.

### 2. High-Fidelity Tap Detection
*   **Apple Silicon Support**: Native integration with `AppleSPUHIDDriver` for M1, M2, and M3 Macs.
*   **Gesture Recognition**: Distinguishes between **Vertical (TOP)** and **Lateral (SIDE)** hits by analyzing peak jerk (rate of change of acceleration).
*   **Smart Lockout**: A 110ms cooldown window prevents phantom double-triggers from physical vibration.

### 3. Dynamic Sound Loading
MacBeat automatically scans its internal `Resources` folder for audio files. Add your own `.wav`, `.mp3`, or `.m4a` samples to expand your kit.

### 4. Minimalist Interface
A sleek, premium macOS popover with real-time visual feedback, kit selection, sensitivity sliders, and live BPM display.

---

## 🛠️ Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon Mac** (highly recommended) or Intel Mac with built-in accelerometer
- **Xcode 15+** (for building from source)

---

## 🚀 Quick Start

### 1. Add Sound Files
Place your samples in the `Sources/MacBeat/Resources/Sounds/` directory:

```text
Resources/
└── Sounds/
    ├── Standard/ 
    │   ├── kick.wav, snare.wav (or kick.mp3...)
    │   └── bongo1.wav, bongo2.wav
    └── Looper/
        ├── clap.wav, hihat.wav, rim.wav...
```

### 2. Configure signing & Privacy
1. Open `Package.swift` in Xcode.
2. Select the **MacBeat** target.
3. Under **Signing & Capabilities**:
    - Set your Development Team.
    - **Disable App Sandbox** (Required to access low-level HID reports from the accelerometer).

### 3. Build & Run
Press **⌘R**. The 🎵 icon will appear in your menu bar. 

### 4. Play!
- **Standard**: Tap the palm rest (Top hit) for Kick, or the side of the chassis (Side hit) for Snare.
- **Looper**: Switch to Looper mode, select a pad, and start tapping. MacBeat starts recording on the first tap and closes the loop after a brief silence.

---

## 🧠 Technical Details

### Architecture

| File | Purpose |
|---|---|
| `MacBeatApp.swift` | Main entry point, sets up global event handlers and menu bar icon. |
| `MotionManager.swift` | Wakes `AppleSPUHIDDriver`, parses raw HID reports, and handles peak-jerk tap recognition. |
| `AudioEngineManager.swift` | Manages `AVAudioEngine` player nodes for zero-latency sample playback. |
| `LooperManager.swift` | Logic for BPM calculation, quantization, and real-time overdubbing. |
| `ContentView.swift` | SwiftUI-based UI with two modes and settings panel. |

### Tap Recognition Algorithm
1. Polls raw accelerometer data via `IOHIDManager`.
2. Filters for linear acceleration (removing gravity).
3. Detects triggers when the absolute Jerk (Delta of Acceleration) exceeds a user-defined threshold.
4. Classifies the tap: if `xMagnitude > (zMagnitude * 0.35)`, it's a **SIDE** tap; otherwise, it's a **TOP** tap.

---

## 🏗️ Adding Your Own Sounds
To add new instruments to the Looper:
1. Drag your files into `Sources/MacBeat/Resources/Sounds/Looper/`.
2. Rebuild the app.
3. The UI will automatically generate a new colored pad for each unique filename.

---

## ⚖️ License

Copyright (c) 2026 Angelo Quartarone. All rights reserved.

This source code is confidential and private. Unauthorized copying, distribution, or use is strictly prohibited.

