This is a snapshot based on the project kickoff interview and a read of Presence's existing `PresenceLogger`/`BugReportBundler`/`DeviceInfoProvider`/`FeedbackScreen`/`FeedbackView` code, as of 2026-09-26. It's meant to be updated as work progresses — treat it as a living checklist, not a permanent record.

## Done

- [x] Project docs bootstrapped (`docs/README.md`, `ARCHITECTURE.md`, `USE_CASES.md`, `TASKS.md`) and git repo initialized at `/Users/darius/Developer/FeedbackKit`.
- [x] **`spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — captured exact report text layout and ring-buffer semantics from Presence, both platforms now have one written contract to implement against.
- [x] **`android/core` scaffolded and extraction complete** — Kotlin Multiplatform module (commonMain + androidMain, no iOS target per the architectural rule), all sources ported from `presence/shared/src/{commonMain,androidMain}/kotlin/com/presence/shared/logging/`, tests passing on `testDebugUnitTest`.
- [x] **`ios/` Swift Package scaffolded and extraction complete** — pure Swift implementations (no Kotlin/Native bridge) of `Logger`, `DeviceInfo`, `BugReportBundler`, matching behavior exactly per spec files, with XCTest suites (buildable via Xcode or `swift build -Xswiftc -sdk ...`).

## Extraction from Presence

Goal: get the existing, working Presence feedback functionality out into this standalone repo without behavior regressions, as two independent platform implementations.

- [x] **Write `spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — captured the exact report text layout and ring-buffer semantics (capacity 500, eviction order, thread-safety non-guarantee) from Presence's current implementation before porting any code, so both platforms have one source of truth to implement against.
- [x] **Scaffold `android/core`** — new Gradle module (Kotlin Multiplatform, `commonMain` + `androidMain` only, no iOS target per the architectural rule), ported from `presence/shared/src/{commonMain,androidMain}/kotlin/com/presence/shared/logging/`.
- [x] **Scaffold `ios/`** — new standalone Swift Package (SPM manifest, `FeedbackKit` target), reimplemented `Logger`/`DeviceInfo`/`BugReportBundler` in pure Swift from Presence's iOS actuals and the shared `commonMain` logic — **not** generated or copied from the KMP `.xcframework`.
- [x] **Tests** — ported `BugReportBundlerTest`/`PresenceLoggerTest` (Kotlin `kotlin.test`) to `android/core` (passing on `testDebugUnitTest`), and wrote equivalent XCTest suite for the Swift package, both asserting conformance to `spec/REPORT_FORMAT.md`.
- [x] **Packaging** — created `Package.swift` manifest for `ios/` (ready for SPM consumption); `android/core`/build.gradle.kts has the foundation for Maven publish config (not yet configured for actual upload).
- [ ] **Port the UI layer** — Compose `FeedbackScreen` for Android, SwiftUI `FeedbackView` for iOS, adapted to call the new standalone packages instead of `PresenceShared`.
- [ ] **Wire Presence itself back up** — once UI layers are ported and both packages verified equivalent on real devices, switch Presence's own `FeedbackView.swift`/`FeedbackScreen.kt` to depend on this repo instead of its inline `com.presence.shared.logging` code, so there's exactly one place implementing this behavior going forward.

## Not started (planned)

- [ ] Sample/demo app per platform showing minimal integration.
- [ ] Localization strings (Presence currently uses `String(localized:)`/`stringResource` — FeedbackKit should decide whether to ship default strings or require the host app to supply them).

## Suggested near-term priorities

1. **Port the UI layer** (`FeedbackScreen.kt` for Android, `FeedbackView.swift` for iOS) — both platforms now have the core logging + bundler working; wiring them up to the native share sheets is the next natural step.
2. **Verify on real devices** — run both the Android app and iOS app with the new packages, confirm logs are collected and reports bundle correctly.
3. **Wire Presence back to FeedbackKit** — once the new packages are proven, switch Presence to depend on them (removing the inline `com.presence.shared.logging` code), so there's one source of truth.
