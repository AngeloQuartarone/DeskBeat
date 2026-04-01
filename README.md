# 🥁 MacBeat

**Turn your MacBook into a drum machine.** MacBeat is a minimalist macOS Menu Bar app that uses your laptop's built-in accelerometer to detect physical taps on the chassis and plays drum sounds in real time.

---

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon or Intel Mac** with a built-in accelerometer
- **Xcode 15+** (for building)

## Quick Start

### 1. Add Sound Files

MacBeat requires two short drum samples (`.wav` **or** `.mp3`). Place them in the `Resources/Sounds/` directory:

```
Resources/
└── Sounds/
    ├── kick.wav   (or kick.mp3)
    └── snare.wav  (or snare.mp3)
```

> **Tip:** Any short (< 1 second) 44.1 kHz or 48 kHz WAV/MP3 files will work great. You can mix formats (e.g. `kick.wav` + `snare.mp3`). Files are searched in order: `.wav` first, then `.mp3`. You can find free drum samples on sites like [Freesound.org](https://freesound.org) or [SampleSwap.org](https://sampleswap.org).

### 2. Open in Xcode

```bash
open Package.swift
```

Or open the `MacBeat` folder directly via **File → Open** in Xcode. Xcode will recognize the Swift Package structure automatically.

### 3. Configure Signing & Entitlements

1. Select the **MacBeat** scheme in the project navigator.
2. Go to **Signing & Capabilities**.
3. Select your **Team**.
4. Under **Code Signing Entitlements**, point to `MacBeat.entitlements`.
5. **Disable App Sandbox** (required for CoreMotion accelerometer access).

### 4. Build & Run

Press **⌘R**. The 🥁 icon will appear in your menu bar.

### 5. Tap Your Laptop!

Tap the area around the trackpad or palm rest. You should hear a drum sound! Use the menu bar popover to:

- **Toggle** tap detection on/off
- **Switch** between Kick 🥁 and Snare 🪘
- **Adjust sensitivity** with the slider (lower = more sensitive)
- **Test** the sound with the Test button

---

## Architecture

| File | Purpose |
|---|---|
| `MacBeatApp.swift` | SwiftUI `@main` entry point with `MenuBarExtra` |
| `MenuBarView.swift` | Popover UI (toggle, picker, slider, quit) |
| `MotionManager.swift` | CoreMotion accelerometer → tap detection |
| `AudioEngineManager.swift` | AVAudioEngine → low-latency sample playback |

## How Tap Detection Works

1. The accelerometer is polled at **100 Hz**.
2. When the **Z-axis acceleration** exceeds the threshold (default 2.0g), a tap is registered.
3. A **150 ms cooldown** prevents double-triggers from the same physical tap.
4. The callback fires `AudioEngineManager.playSample()` on the main thread.

## Troubleshooting

| Problem | Solution |
|---|---|
| No sound | Make sure `kick.wav` and `snare.wav` are in `Resources/Sounds/` |
| "Accelerometer not available" | You may be running in the Simulator — use real hardware |
| Taps not detected | Try lowering the sensitivity (slider toward "High") |
| App Sandbox errors | Ensure `com.apple.security.app-sandbox` is `false` in entitlements |

---

## License

Copyright (c) 2026 Angelo Quartarone

All rights reserved.

This source code, and any of its derivatives, are strictly confidential and 
may not be copied, distributed, modified, or used without the express written 
permission of the copyright holder.
