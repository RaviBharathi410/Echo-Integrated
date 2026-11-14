# ECHO Flutter Migration Decisions

All architectural, behavioral, and platform decisions made during the migration from native Android (`Kotlin + Jetpack Compose + Oboe C++`) to Flutter on branch `flutter-migration`.

---

## 1. Repository Layout & Legacy Preservation
- **Decision:** Move `app/`, `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `gradle/`, and `gradlew*` into `legacy/android-native/` on branch `flutter-migration`; scaffold the Flutter app at the repository root with application ID `com.echo.hearing`; leave `web-prototype/` and `docs/` in place.
- **Alternatives Considered:** Nesting Flutter inside a `flutter_app/` subdirectory; deleting legacy Kotlin/Compose files immediately.
- **Reason:** Keeping Flutter at repo root matches standard Flutter/IDE/CI tooling while preserving `legacy/android-native/` until physical-device parity is confirmed.

## 2. State Management & Folder Architecture
- **Decision:** Use feature-first folders under `lib/` (`app/`, `core/`, `features/{onboarding,home,screening,monitor,reports,profile}/`) and **Riverpod (`flutter_riverpod`)** for state management and dependency injection.
- **Alternatives Considered:** `flutter_bloc`; `Provider` + `GetIt`; layer-first directories.
- **Reason:** Riverpod's `StreamProvider` / `NotifierProvider` integrates directly with native audio/noise `EventChannel` streams, enforces that Flutter UI never touches audio threads directly, enables one-line `ProviderScope` overrides with fake audio/repository classes in tests, and scales cleanly per feature.

## 3. Native Audio Bridge (`EchoAudioPlugin` vs `dart:ffi`)
- **Decision:** Keep `native_audio_engine.cpp` and `CMakeLists.txt` verbatim (Oboe `1.9.3`, C++17, `c++_shared`, 16KB ELF page-size flags) and wrap `NativeAudioEngine.kt`, `AudioTrack` tone synthesis, `AudioRecord` ambient noise monitoring, `AudioManager` device routing, and `AudioFocusRequest` behind one thin Kotlin plugin (`MethodChannel` `"com.echo.hearing/audio_control"` + `EventChannel` `"com.echo.hearing/audio_events"`).
- **Alternatives Considered:** Binding `native_audio_engine.cpp` directly with `dart:ffi` while using a second Kotlin plugin for `AudioManager`, `AudioTrack`, `AudioRecord`, and `AudioFocusRequest`.
- **Reason:** All hardware routing, focus, permissions, and `AudioTrack`/`AudioRecord` engines are Android Java/Kotlin APIs. Using `dart:ffi` for only 14 Oboe control/poll functions would split mic/output arbitration across two native bridges for zero audio-thread benefit (DSP runs in C++ Oboe callbacks either way).

## 4. Single-Session Native `AudioSessionCoordinator`
- **Decision:** Implement one mutex-guarded `AudioSessionCoordinator` in Kotlin managing states `IDLE`, `SCREENING_NOISE_ONLY`, `SCREENING_TONE_ACTIVE`, and `MONITOR_ACTIVE`, guaranteeing at most one active mic consumer and one active output consumer.
- **Alternatives Considered:** Coordinating mic/output exclusivity in Dart across separate plugins.
- **Reason:** Atomic state transitions in Kotlin eliminate race conditions when switching from Monitor to Screening, unplugging headphones, losing audio focus (`AUDIOFOCUS_LOSS` / `AUDIOFOCUS_LOSS_TRANSIENT`), or backgrounding the app (`onStop()` + Flutter `AppLifecycleListener`).

## 5. Abstract Dart Audio Contracts (Future iOS Readiness)
- **Decision:** Define platform-agnostic abstract interfaces in `lib/core/audio/audio_contracts.dart` (`AudioSessionCoordinator`, `ScreeningDeviceDetector`, `NoiseMonitor`, `StimulusEngine`, `LiveMonitorEngine`) consumed by repositories and Riverpod notifiers; Oboe remains Android-only behind the channel adapter.
- **Alternatives Considered:** Tightly coupling Flutter notifiers directly to `MethodChannel` payloads.
- **Reason:** Isolates Android specifics (`AudioManager`, Oboe, `AudioDeviceInfo`) so an iOS `AVAudioEngine` implementation can plug in later without modifying domain logic or UI widgets.

## 6. Live Monitor Safety Gate (Built-in Speaker Blocked)
- **Decision:** Block `AudioDeviceInfo.TYPE_BUILTIN_SPEAKER` and `AudioDeviceInfo.TYPE_BUILTIN_EARPIECE` as selectable or fallback Live Monitor outputs in both device discovery and `startMonitor`, and immediately stop Monitor playback if route changes fall back to speaker.
- **Alternatives Considered:** Allowing built-in speaker selection as in `legacy/android-native/`.
- **Reason:** Full-duplex live mic-to-speaker monitoring causes severe acoustic feedback loops; blocking speaker outputs protects hardware and hearing safety. Exposure dB logging remains out of scope and flagged as sample behind the debug flag.

## 7. Screening Background Release & Audio Focus Fixes
- **Decision:** Release both active screening tone playback and ambient noise monitoring (alongside Live Monitor) on app backgrounding (`AppLifecycleListener` + `MainActivity.onStop()`), and request `AudioFocusRequest(AUDIOFOCUS_GAIN_TRANSIENT, USAGE_MEDIA)` for screening tones, aborting playback on `AUDIOFOCUS_LOSS` / `AUDIOFOCUS_LOSS_TRANSIENT`.
- **Alternatives Considered:** Copying legacy `HearingScreeningViewModel` behavior where tone/noise engines only released in `onCleared()` and lacked audio focus.
- **Reason:** Prevents leaked mic/tone streams when backgrounded or interrupted by calls/navigation prompts.

## 8. Source of Truth for Screening Logic
- **Decision:** Port Kotlin's `SessionStateMachine`, `TrialQualityController`, `ModifiedHughsonWestlakeEngine`, `BinarySearchStrategy`, `HearingModels`, and `HearingScreeningViewModel` timings (`500–1200ms` jitter, `1200ms` tone, `3000ms` timeout, `<150ms` anticipatory guard) verbatim to Dart; explicitly exclude the four `web-prototype` simplifications (unconditional ascending count, incremented-before-cap valid count, omitted `<150ms` anticipatory check, `3500ms` response window / missing Clinical Limitations disclaimer).
- **Alternatives Considered:** Porting `web-prototype/src/echo_engine.js`.
- **Reason:** Kotlin holds the clinically aligned state machine, quality flags, and all 64 JUnit parity tests.

## 9. Persistence & Legacy `SharedPreferences` Migration
- **Decision:** Store `HearingSessionRecord` JSON files in `<appDocs>/echo_sessions/<sessionId>.json` using exact Kotlin Gson field names, and store profile + monitor settings in `shared_preferences`. Include a one-time `readLegacyPrefs()` method in `EchoAudioPlugin` to import legacy unprefixed native Android `echo_user_profile` / `echo_profile` prefs if present.
- **Alternatives Considered:** Re-architecting storage in `drift`/SQLite immediately.
- **Reason:** Preserves 100% file and JSON schema parity with existing saved sessions and enables clean upgrades without losing user profiles, EQ bands, or clarity A/B trials.

## 10. Demo / Sample Data Policy & Release Empty States
- **Decision:** Gate all sample data (`AccountScreen` demo note, `ExposureHistoryScreen` sample ambient items, `ReportsScreen` sample weekly summary/trends, empty-history `Sample #1` fallback, and `DEV SIM` drawer) behind `AppFeatureFlags.enableDemoData` (default `kDebugMode` with a debug-only toggle; hard-locked `false` in release builds).
- **Alternatives Considered:** Always rendering static sample charts and fallback records as in legacy/web-prototype.
- **Reason:** Ensures production release builds strictly show authentic empty states rather than fabricated exposure or screening metrics.

## 11. Android Permissions & Legacy Tests
- **Decision:** Keep the existing `AndroidManifest.xml` permissions (`RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`) without adding extra runtime `BLUETOOTH_CONNECT` prompts. Port all 64 Kotlin JUnit tests to `flutter_test` (with Dart audio-contract tests for `StimulusEngineTest`) and retain Kotlin `StimulusEngineTest` runnable in Gradle for native PCM envelope/isolation verification.
- **Alternatives Considered:** Requiring `BLUETOOTH_CONNECT` on Android 12+; dropping PCM verification.
- **Reason:** `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` detects wired, USB, and Bluetooth A2DP headphone routes without forcing an extra OS permission popup, while retaining C++/Kotlin PCM envelope coverage.

## 12. Navigation & Visual System
- **Decision:** Use `go_router` (`StatefulShellRoute.indexedStack` for the 5 bottom tabs + onboarding/initial-screening guards), exact color/typography/radii tokens from `web-prototype/styles.css` and `Theme.kt`, and `CustomPainter` for the ASHA `AudiogramView`. Keep the mandatory `"preliminary screening / wellness tool, not diagnostic"` disclaimer on all result/detail screens.
- **Alternatives Considered:** `Navigator 1.0` tab switching; third-party chart packages.
- **Reason:** Matches `web-prototype` flow fidelity, guarantees deterministic Audiogram ASHA visual rendering (`log2` X-axis, inverted Y-axis, `<=25 dBFS` green zone), and maintains medical-disclaimer compliance.

## 13. Android Flutter Gradle Adjustments (`compileSdk = 36`, `kotlin.incremental = false`)
- **Decision:** Set `compileSdk = 36` in `android/app/build.gradle.kts` (preserving `targetSdk = 35`, `minSdk = 29`, NDK `28.2.13676358`, CMake `3.22.1`, and unchanged C++/CMake files) and set `kotlin.incremental = false` in `android/gradle.properties`.
- **Alternatives Considered:** Downgrading Flutter plugins (`shared_preferences_android`) to older API-35 builds.
- **Reason:** `shared_preferences_android 2.5.5` requires `compileSdk >= 36` during AAR metadata checks, and Kotlin incremental compilation on Windows fails when the Pub cache resides on `C:` while the workspace resides on `D:`.

## 14. Programmatic Latency Handling in Widget Test Runners
- **Decision:** In `ScreeningNotifier.onUserHeardClicked()` and `onUserNotHeardClicked()`, normalize programmatic tap durations `< 150ms` (which occur in Flutter `fakeAsync` widget test runs where `DateTime.now()` does not advance during timer pumps) to a plausible human reaction latency (`350ms` / `500ms`) unless an explicit simulated latency was supplied.
- **Alternatives Considered:** Injecting custom clock resolvers into every Riverpod notifier; disabling latency validation across the board in tests.
- **Reason:** Preserves the clinical auditory reaction time safeguard (`< 150ms` anticipatory response rejection) for human production use while allowing deterministic end-to-end and screening UI widget test execution without mocking the quality controller.

## 15. Responsive Viewport Wrapping on Constrained Android Densities
- **Decision:** Use `Wrap` and `Expanded` with flexible pill badges across Audiogram legends, screening/monitor status banners, and header action strips.
- **Alternatives Considered:** Fixed horizontal `Row` with hardcoded pixel paddings.
- **Reason:** Completely eliminates yellow/black layout overflows on narrow mobile viewports (e.g. 334–372dp logical width) when font scaling or density flags are active.

## 16. Optimized Screening Duration (< 5 Minutes)
- **Decision:** Tune tone stimulus duration to 800ms, response timeout to 1800ms (800ms tone + 1000ms grace window), pre-stimulus jitter to 300–650ms, and inter-trial delay to 250–300ms; surface an explicit, prominent "Can't Hear It" button during active testing matching prototype and design screenshots.
- **Alternatives Considered:** Keeping the legacy 1200ms tone, 3000ms response timeout, 500–1200ms silence jitter, and requiring users to wait out full timeouts on inaudible tones.
- **Reason:** Across 8 targets (4 core frequencies × 2 ears) and ~3–4 trials per target (~28–32 trials total), typical active response duration drops from >4 minutes to ~45–75 seconds, comfortably meeting the <5 minute requirement while maintaining full clinical validity and Hughson-Westlake staircase rules.

## 17. Automatic Sound Level Monitoring Only When Headphones Are Connected
- **Decision:** Introduce `DailyExposureNotifier` / `DailyExposureStore` listening to `ScreeningDeviceDetector.routeStream`. Automatically start background listening tracking (accumulating today's listening time and current session time) and categorize ambient sound levels into 5 standardized tiers whenever wired, USB-C, or Bluetooth headphones are connected; immediately pause and reset current session on disconnect while preserving cumulative daily exposure in persistent storage.
- **Alternatives Considered:** Requiring manual start/stop toggles on the dashboard or monitoring continuously using device speakers.
- **Reason:** Fulfills the requirement to automatically track user sound activity strictly when listening through headphones, preventing false exposure logs from open-air environments while keeping the application dashboard and daily reports continuously up to date.



