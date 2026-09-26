This is a snapshot based on the project kickoff interview, a read of the originating app's existing feedback code, and a follow-up design pass adding the QA test-session feature, as of 2026-09-26. It's meant to be updated as work progresses — treat it as a living checklist, not a permanent record.

## Done

- [x] Project docs bootstrapped (`docs/README.md`, `ARCHITECTURE.md`, `USE_CASES.md`, `TASKS.md`) and git repo initialized at `/Users/darius/Developer/FeedbackKit`.
- [x] **`spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — captured exact report text layout and ring-buffer semantics from the originating app, both platforms now have one written contract to implement against.
- [x] **`android/core` scaffolded and extraction complete** — Kotlin Multiplatform module (commonMain + androidMain, no iOS target per the architectural rule), all sources ported from the originating app's shared logging module, tests passing on `testDebugUnitTest`.
- [x] **`ios/` Swift Package scaffolded and extraction complete** — pure Swift implementations (no Kotlin/Native bridge) of `Logger`, `DeviceInfo`, `BugReportBundler`, matching behavior exactly per spec files, with XCTest suites (`swift test` passing on macOS; buildable for iOS via `swift build -Xswiftc -sdk ...` or Xcode).
- [x] **`TestSession` implemented on both platforms and wired into `BugReportBundler`** — see the QA test-session section below, fully checked off.
- [x] **`.gitignore` added** — build artifacts (`.gradle/`, `build/`, `ios/.build/`, `local.properties`) that were accidentally committed early on were untracked.
- [x] **UI layer ported on both platforms** (`android/ui`'s `FeedbackScreen.kt`, `ios/Sources/FeedbackKit/FeedbackView.swift`) — see "UI layer and integration" below.

## Initial extraction (bug report + logging)

Goal: get the existing, working feedback functionality (originally built inside the Presence app) out into this standalone repo without behavior regressions, as two independent platform implementations.

- [x] **Write `spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — captured the exact report text layout and ring-buffer semantics (capacity 500, eviction order, thread-safety non-guarantee) from the originating implementation before porting any code, so both platforms have one source of truth to implement against.
- [x] **Scaffold `android/core`** — new Gradle module (Kotlin Multiplatform, `commonMain` + `androidMain` only, no iOS target per the architectural rule), ported from the originating app's shared logging module.
- [x] **Scaffold `ios/`** — new standalone Swift Package (SPM manifest, `FeedbackKit` target), reimplemented `Logger`/`DeviceInfo`/`BugReportBundler` in pure Swift from the originating app's iOS actuals and shared logic — **not** generated or copied from a KMP `.xcframework`.
- [x] **Tests** — ported the Kotlin `kotlin.test` suite to `android/core` (passing on `testDebugUnitTest`), and wrote an equivalent XCTest suite for the Swift package, both asserting conformance to `spec/REPORT_FORMAT.md`.
- [x] **Packaging** — created `Package.swift` manifest for `ios/` (ready for SPM consumption); `android/core`/build.gradle.kts has the foundation for Maven publish config (not yet configured for actual upload).

## QA test-session feature

Goal: let a QA tester record structured pass/fail results for named test scenarios from inside the app under test, and export those results standalone or merged into a bug report.

- [x] **Write `spec/TEST_SESSION_FORMAT.md`** — API contract (`TestSession`/`TestResult`/`recordResult`/`exportReport`), behavior (no capacity cap, single-writer thread-safety expectation, session identity), and exact exported-text format, both standalone and merged into a `BugReportBundler` report.
- [x] **Implement `TestSession` in `android/core`** (`TestSession.kt`, commonMain — no platform actuals needed, pure Kotlin) — `recordResult`, `results()`, `exportReport()`, `clear()`, per the spec.
- [x] **Implement `TestSession` in `ios/Sources/FeedbackKit`** (`TestSession.swift`) — same API surface, pure Swift, per the spec.
- [x] **Wire `TestSession` into `BugReportBundler`** on both platforms — added the optional `testSession` constructor parameter, appending the merged section per `spec/TEST_SESSION_FORMAT.md`; confirmed `build()`'s output is unchanged when no session is supplied (additive, not breaking) via a dedicated test on each platform.
- [x] **Tests** — `TestSessionTest`/`TestSessionTests` on each platform (recording order, notes formatting, empty-session export, `clear()` behavior), plus new `BugReportBundler` tests covering the merged-section behavior. All passing: 17 tests on `gradle :android:core:testDebugUnitTest`, 16 on `swift test`.
- [x] **UI hook** — `FeedbackScreen`/`FeedbackView` (see below) include a session-name field + "Start session" button, then a scenario-name/notes field pair with PASS/FAIL/SKIP/BLOCKED buttons and a recorded-results list.

## UI layer and integration

- [x] **Port the UI layer** — `android/ui`'s `FeedbackScreen.kt` (new Gradle module: Android library + Jetpack Compose, depends on `android:core`, ships its own `FileProvider`/`res/xml/feedbackkit_file_paths.xml`) and `ios/Sources/FeedbackKit/FeedbackView.swift` (SwiftUI, gated `#if os(iOS)` since `ShareLink` needs iOS 16/macOS 13 and this package declares no macOS platform floor). Both build for real: `gradle :android:ui:compileDebugKotlin` succeeds, and a full `xcodebuild -scheme FeedbackKit -destination 'generic/platform=iOS Simulator' build` succeeds (not just a typecheck).
- [x] **Default strings shipped** (Android) — `android/ui/src/main/res/values/strings.xml` ships default English copy for every user-facing string; a host app can override any of them by declaring a same-named string resource, Android's standard resource-precedence mechanism, so no separate localization API was needed. iOS uses plain string literals in `FeedbackView.swift` (no `String(localized:)` catalog yet — revisit if/when this needs actual translations).
- [ ] **Verify on real devices** — run both the Android app and iOS app with the new packages/modules, confirm logs are collected, test sessions record correctly, and reports bundle/share correctly via a real device or simulator interaction pass (not just a successful build).
- [ ] **Wire the originating app back up** — once verified on real devices, switch the original app's feedback screen to depend on this repo instead of its inline logging code, so there's exactly one place implementing this behavior going forward.

## Not started (planned)

- [ ] Sample/demo app per platform showing minimal integration (bug report + test session).
- [ ] Maven publish config for `android/core`/`android/ui` (build.gradle.kts has the foundation; actual upload/coordinates not configured).

## Suggested near-term priorities

1. **Verify on real devices/simulators** — actually launch both apps, start a test session, record a few results, and confirm the share sheet produces a correctly-merged report. This is the one remaining gap between "builds successfully" and "the feature genuinely works."
2. **Wire the originating app back to depend on this repo**, once the above is verified.
3. Consider a sample/demo app per platform, to give integrators a working reference and a place to do the device verification above.
