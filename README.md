# ECHO (Hearing Screening & Live Acoustic Monitor)

Flutter-migrated Android application combining pure-tone auditory screening with low-latency full-duplex acoustic monitoring and multi-band parametric equalization. Package ID: `com.echo.hearing`, Min SDK 29, Target SDK 35, Compile SDK 36.

---

## Architecture Overview

```
                      Flutter UI Layer (Riverpod + go_router)
    [Test / Screening]  [Home]  [Live Monitor]  [Reports]  [Profile & Settings]
            │                       │                       │
     ScreeningNotifier       MonitorNotifier        UserProfileStore
            │                       │                       │
   SessionStateMachine      MonitorProfileStore   LocalJsonSessionRepo
   TrialQualityController           │                       │
   HughsonWestlakeProtocol          │                       │
            └───────────────┬───────┴───────────────────────┘
                            ▼
            lib/core/audio/android_audio_bridge.dart
         MethodChannel("com.echo.hearing/audio_control")
         EventChannel("com.echo.hearing/audio_events")
                            │
               Platform Channel / JNI Boundary
                            ▼
        android/app/src/main/kotlin/com/echo/hearing/
          AudioSessionCoordinator.kt (Mutual Exclusivity Guard)
          EchoAudioPlugin.kt
          audio/AndroidAudioTrackStimulusEngine.kt (AudioTrack PCM)
          noise/AndroidMicrophoneNoiseMonitor.kt (AudioRecord Noise Floor)
          device/AndroidDeviceCapabilityManager.kt (AudioManager Routing)
          monitor/NativeAudioEngine.kt (JNI wrapper)
                            │
                      JNI Boundary
                            ▼
        android/app/src/main/cpp/native_audio_engine.cpp
          Oboe C++ Low-Latency Audio Engine (1.9.3)
          Noise Gate • Adaptive Denoiser • 4-Band Compression • Per-Ear 6-Band EQ
```

---

## 5-Tab Shell & Features

| Tab | What It Does | Visual Origin |
|---|---|---|
| **Test** | Onboarding consent, audio route check, ambient noise floor evaluation, demo practice tone, bilateral Modified Hughson-Westlake screening (or binary search), Left Ear Complete repositioning pause, and ASHA-standard digital Audiogram results. | Kotlin `Echo_Poc` + `web-prototype` |
| **Home** | Personalized greeting, primary auditory goal, initial baseline prompt (when screening is pending), latest screening audiogram snapshot (or clean empty state in release mode), and live sound monitor quick-launcher. | `web-prototype` |
| **Monitor** | Real-time full-duplex Oboe mic-to-headphone listening, peak output VU meter, built-in speaker safety blocker, 6-band per-ear graphic EQ, real-ear comfort verification, background noise gate, adaptive denoiser, speech compression, and Clarity A/B word trial logging. | Kotlin `ECHO` + `web-prototype` |
| **Reports** | Weekly listening summaries, exposure duration trends, acoustic tips, and historical screening access. (Gated behind demo flag in debug mode; genuine empty states in release builds). | `web-prototype` |
| **Profile** | User profile editor, connected headphone detection, notification toggles, privacy & data controls (delete sessions, reset EQ), full JSON data export to clipboard, and debug demo toggle. | `web-prototype` |

---

## Audio Safety & Parity Rules

1. **One Microphone, One Output Stream Active At A Time:** Arbitrated atomically in Kotlin by `AudioSessionCoordinator`. Starting the Live Monitor immediately stops noise monitoring. Switching away from the Monitor tab or backgrounding the app automatically stops the monitor.
2. **Built-in Speaker Blocked on Monitor:** To prevent severe acoustic feedback howling and ear injury, `AudioDeviceInfo.TYPE_BUILTIN_SPEAKER` (type 2) and `TYPE_BUILTIN_EARPIECE` (type 1) cannot be used as Live Monitor outputs. Headphones (3.5mm, USB-C, or Bluetooth A2DP) are required.
3. **Screening Baseline Import is Reference-Only:** Tapping "Import Latest Screening" (or completing an initial screening) loads the latest recorded screening thresholds into the Monitor's reference slots. They are uncalibrated digital attenuation levels (dBFS) and **never alter DSP gain sliders**.
4. **Audio Focus & Background Release:** Screening tones request `AUDIOFOCUS_GAIN_TRANSIENT` with `USAGE_MEDIA` and abort on audio focus loss. Screening tone engines and noise monitors release automatically when the app is backgrounded.
5. **Screening / Wellness Tool Disclaimer:** The mandatory phrase *"preliminary screening / wellness tool, not diagnostic"* is present on all result summaries, audiograms, and session detail screens.
6. **Release Builds Show Zero Sample Data:** When `kReleaseMode` is active (or demo data disabled), all sample banners, sample #1 fallback sessions, and illustrative trends are hidden; genuine empty states are displayed instead.

---

## Directory Layout

```
├── lib/
│   ├── app/                    # App entry, go_router, theme tokens, feature flags
│   ├── core/
│   │   ├── audio/              # Abstract audio interfaces, Android bridge, fake test engines
│   │   ├── data/               # User profile store, session JSON repo, monitor profile store
│   │   ├── domain/             # Hearing models, Hughson-Westlake, Binary Search, Quality Controller
│   │   └── permissions/        # Runtime permission gateway (OS handler + fake test gateway)
│   └── features/
│       ├── home/               # Home screen, initial baseline reminder card
│       ├── monitor/            # Live monitor screen, EQ sliders, DSP drawer, Clarity A/B log
│       ├── onboarding/         # Welcome, Account/Guest, Profile setup, Health Notice, Permissions
│       ├── profile/            # Profile settings, device list, export/delete data
│       ├── reports/            # Listening reports, weekly summary, exposure trends
│       └── screening/          # Device setup, Briefing, Practice round, Test runner, AudiogramView
├── test/                       # 74 unit, widget, platform bridge, and end-to-end integration tests
├── android/                    # Android host with Oboe C++ DSP and Kotlin AudioSessionCoordinator
├── legacy/android-native/      # Preserved native Kotlin/Compose project (retained until physical verification)
├── web-prototype/              # Original web prototype reference implementation
└── docs/                       # Migration decisions log and technical documentation
```

---

## Prerequisites & Build Instructions

### Prerequisites
- Flutter SDK: `3.44.4` (Dart `3.12.2`)
- Android SDK: API Level 35 (compileSdk 36)
- Android NDK: `28.2.13676358`
- CMake: `3.22.1`
- Google Oboe: `1.9.3`

### Run Tests
```bash
# Run all 74 unit, widget, platform channel, and end-to-end tests
flutter test

# Run static analysis
flutter analyze
```

### Build Android APK
```bash
# Build debug APK containing libechoaudio.so and liboboe.so
flutter build apk --debug

# Built artifact:
# build/app/outputs/flutter-apk/app-debug.apk
```

### Verify Native Libraries in APK
```powershell
tar -tf build/app/outputs/flutter-apk/app-debug.apk | Select-String "\.so"
```
The output confirms `libechoaudio.so` and `liboboe.so` are bundled in `lib/arm64-v8a/`, `lib/armeabi-v7a/`, and `lib/x86_64/`.

---

## Native Android Legacy Preservation

The original native Android app (`Kotlin + Jetpack Compose + Oboe C++`) is fully preserved under `legacy/android-native/` until physical Android device manual verification is completed and approved.
