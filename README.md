# 🥁 MacBeat

**Turn your MacBook into a professional drum machine.** MacBeat is a high-performance macOS Menu Bar app that uses your laptop's built-in accelerometer to detect physical strikes on the chassis, triggering drum samples with ultra-low latency.

---

## 🔥 Key Features

### 1. Two Performance Modes
*   **Standard Mode**: Real-time triggering of "Kick" and "Snare" (or "Bongo 1" and "Bongo 2"). Use vertical strikes for kicks and lateral strikes for snares. Includes "Invert Sides" for southpaw drummers.
*   **Looper Mode**: Dynamic pattern recording. Tap a beat, and MacBeat will automatically detect the BPM, quantize your performance, and loop it. Layer more instruments by switching pads mid-session.

### 2. High-Fidelity Tap Detection
*   **Apple Silicon Support**: Native integration with `AppleSPUHIDDriver` for M1, M2, and M3 Macs, bypassing legacy SMS APIs.
*   **Gesture Recognition**: Distinguishes between **Vertical (TOP)** and **Lateral (SIDE)** hits by analyzing peak jerk (rate of change of acceleration).
*   **Smart Lockout**: A 110ms cooldown window prevents phantom double-triggers from physical vibrations.
*   **5-Level Sensitivity**: Adjustable thresholds from "Low" for heavy hitters to "Max" for delicate, finger-tip drumming.

### 3. Infinite Sound Customization
Import your own `.wav` or `.mp3` samples directly through the Settings UI. MacBeat automatically generates new, color-coded pads for each unique sound, allowing you to build completely custom kits on the fly.

### 4. Smart Focus Management
To preserve battery and prevent accidental triggers, MacBeat only monitors the accelerometer when the popover is visible or when explicitly set to "Play in background".

---

## 🛠️ Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon Mac** (highly recommended) or Intel Mac with built-in accelerometer
- **Xcode 15+** (for building from source)

---

## 🚀 Quick Start

### 1. Build & Run
1. Open `Package.swift` in Xcode.
2. Select the **MacBeat** target.
3. Under **Signing & Capabilities**:
    - Set your Development Team.
    - **Disable App Sandbox** (Required to access low-level HID reports from the accelerometer).
4. Press **⌘R**. The 🎵 icon will appear in your menu bar. 

### 2. Play!
- **Standard**: Tap the palm rest (Top hit) for Kick, or the side of the chassis (Side hit) for Snare.
- **Looper**: Switch to Looper mode, select a pad, and start tapping. MacBeat starts recording on the first tap and closes the loop after a brief silence.

### 3. Add Your Own Sounds
Go to **Settings** (gear icon) and click **"Add Sounds"**. Select your audio files, and they will instantly appear as playable pads in Looper mode.

---

## 🧠 Technical Details

### Architecture

| Component | Purpose |
|---|---|
| `MacBeatApp.swift` | App lifecycle and Menu Bar management. |
| `MotionManager.swift` | Manages `IOHIDManager`, wakes `AppleSPUHIDDriver`, and handles peak-jerk tap recognition. |
| `AudioEngineManager.swift` | Low-latency `AVAudioEngine` implementation with dynamic sample management. |
| `LooperManager.swift` | Real-time rhythm logic: BPM detection, quantization, and event scheduling. |
| `ContentView.swift` | Modern SwiftUI interface with responsive visual feedback. |

### Tap Recognition Algorithm
1. **Raw Data**: Polls 3-axis accelerometer data at high frequency via HID.
2. **Filtering**: Applies a low-pass filter to isolate gravity, then subtracts it to get linear acceleration.
3. **Jerk Analysis**: Calculates the rate of change (Jerk). A trigger is fired when Jerk exceeds the sensitivity threshold.
4. **Classification**: Uses the ratio of X (lateral) to Z (vertical) jerk to distinguish hit location: `xMagnitude > (zMagnitude * 0.35)` is classified as **SIDE**.

---

## 🏗️ Permissions & Privacy
- **App Sandbox**: Must be disabled. The app requires direct access to the `AppleSPUHIDDevice` to read raw sensor data which is blocked by the default sandbox.
- **Microphone**: Not required. All detection is physical/mechanical.

---

## ⚖️ License

Copyright (c) 2026 Angelo Quartarone. All rights reserved.

This source code is confidential and private. Unauthorized copying, distribution, or use is strictly prohibited.
