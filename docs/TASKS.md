This is a snapshot based on the project kickoff interview and a read of Presence's existing `PresenceLogger`/`BugReportBundler`/`DeviceInfoProvider`/`FeedbackScreen`/`FeedbackView` code, as of 2026-09-26. It's meant to be updated as work progresses — treat it as a living checklist, not a permanent record.

## Done

- [x] Project docs bootstrapped (`docs/README.md`, `ARCHITECTURE.md`, `USE_CASES.md`, `TASKS.md`) and git repo initialized at `/Users/darius/Developer/FeedbackKit`.

## Extraction from Presence

Goal: get the existing, working Presence feedback functionality out into this standalone repo without behavior regressions, as two independent platform implementations.

- [ ] **Write `spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — capture the exact report text layout and ring-buffer semantics (capacity 500, eviction order, thread-safety non-guarantee) from Presence's current implementation, before porting any code, so both platforms have one source of truth to implement against.
- [ ] **Scaffold `android/core`** — new Gradle module (Kotlin Multiplatform, `commonMain` + `androidMain` only, no iOS target per the architectural rule), ported from `presence/shared/src/{commonMain,androidMain}/kotlin/com/presence/shared/logging/`.
- [ ] **Scaffold `ios/`** — new standalone Swift Package (SPM manifest, `FeedbackKit` target), reimplementing `Logger`/`DeviceInfo`/`BugReportBundler` in pure Swift from Presence's iOS actuals (`DeviceInfoProvider.ios.kt`, `PresenceLogger.ios.kt`) and the shared `commonMain` logic — **not** generated or copied from the KMP `.xcframework`.
- [ ] **Port the UI layer** — Compose `FeedbackScreen` for Android, SwiftUI `FeedbackView` for iOS, adapted to call the new standalone packages instead of `PresenceShared`.
- [ ] **Tests** — port `BugReportBundlerTest`/`PresenceLoggerTest` (Kotlin `kotlin.test`) to `android/core`, and write an equivalent XCTest suite for the Swift package, both asserting conformance to `spec/REPORT_FORMAT.md`.
- [ ] **Packaging** — Maven publish config for `android/core`; `Package.swift` manifest for `ios/`, versioned and tagged for SPM consumption.
- [ ] **Wire Presence itself back up** — once both packages exist and are verified equivalent, switch Presence's own `FeedbackView.swift`/`FeedbackScreen.kt` to depend on this repo instead of its inline `com.presence.shared.logging` code, so there's exactly one place implementing this behavior going forward.

## Not started (planned)

- [ ] Sample/demo app per platform showing minimal integration.
- [ ] Localization strings (Presence currently uses `String(localized:)`/`stringResource` — FeedbackKit should decide whether to ship default strings or require the host app to supply them).

## Suggested near-term priorities

1. Write `spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md` first — every other task depends on having one written contract instead of "whatever Presence's Kotlin code currently does."
2. Scaffold `android/core` and port its logic — this is the lower-risk, mechanical half (same language, same KMP tooling Presence already uses).
3. Scaffold `ios/` as a from-scratch Swift Package implementation against the spec — the higher-effort half, since it's a genuine reimplementation rather than a port.
4. Add tests to both before wiring either into Presence, so parity is verified before anything depends on it.
