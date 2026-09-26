# FeedbackKit Test Session Format

This document specifies the API contract, behavior, and exported text format of `TestSession`. Both the Android (Kotlin) and iOS (Swift) implementations must conform, so a session recorded on one platform and a session recorded on the other produce comparable, identically-structured reports.

## Purpose

`TestSession` lets a QA tester record structured pass/fail results for a set of named test scenarios while working through a test plan *inside the app under test*, then export those results as a plain-text report — standalone, or merged into a `BugReportBundler` report so scenario results and diagnostic logs from the same run travel together.

## API contract

```
TestSession(name: String, now: () -> Long = epochMillisNow)

recordResult(scenarioName: String, result: TestResult, notes: String? = null): Unit
results(): List<TestScenarioResult>     // in recorded order, oldest first
exportReport(): String                  // see "Exported report format" below
clear(): Unit                            // empties recorded results; does not reset the session name/start time
```

```
enum TestResult { PASS, FAIL, SKIP, BLOCKED }
```

- `PASS` — the scenario completed with the expected outcome.
- `FAIL` — the scenario did not produce the expected outcome.
- `SKIP` — the tester deliberately did not run this scenario (e.g. not applicable to this build/config).
- `BLOCKED` — the tester could not run this scenario at all (e.g. a prerequisite step failed, environment issue) — distinct from `FAIL`, which implies the scenario *was* run.

```
TestScenarioResult (conceptual — result of a single recordResult call)
  scenarioName: String
  result: TestResult
  notes: String?               // free text, no escaping/length limit
  recordedAtMillis: Int64
```

## Behavior

### Recording

- `recordResult` appends a new `TestScenarioResult` — it does **not** overwrite a prior result for the same `scenarioName`. Recording the same scenario twice (e.g. after a retry) produces two entries in `results()`, both included in the exported report. Deduplication/retry semantics, if wanted, are the caller's responsibility (e.g. only call `recordResult` once the tester is done retrying).
- No capacity cap — unlike `Logger`'s 500-entry ring buffer, a `TestSession` never evicts entries. A test plan is a bounded, human-authored list; this is a deliberate simplicity tradeoff, not an oversight (see `ARCHITECTURE.md`).
- `recordedAtMillis` is captured at the moment `recordResult` is called, using the same `now` function pattern as `BugReportBundler` (for testability — a fixed/injectable clock in tests).

### Session identity

- `name` is set once at construction and is immutable for the life of the session object. There is no "rename a session" operation — start a new `TestSession` instead.
- A session has no persistent identity across app launches or process death — it is a plain in-memory object the host app or tester code holds a reference to for the duration of one test run.

### Thread safety

Not thread-safe, matching `Logger`'s documented tradeoff. `TestSession` is expected to be driven from a single thread (typically the UI thread, by a human tapping through a test plan one scenario at a time) — this is not a producer/consumer or multi-threaded logging scenario, so the risk profile is lower than `Logger`'s, but the same "don't call concurrently from multiple threads without external synchronization" caveat applies.

### `clear()`

Empties the recorded results list. The session's `name` is unchanged (this is not "start a new session" — construct a new `TestSession` for that). Exposed primarily for tests; not expected to be a common call in production app code.

## Exported report format (standalone)

`exportReport()` returns:

```
=== FeedbackKit test session: {name} ===
{count} scenario(s) recorded

[{RESULT}] {scenarioName}
[{RESULT}] {scenarioName} — {notes}
...
```

- Header line: `=== FeedbackKit test session: {name} ===`, where `{name}` is the session's name as given at construction, verbatim (no escaping).
- Count line: `{count} scenario(s) recorded`, where `{count}` is `results().size`.
- Blank line.
- One line per recorded result, **in recorded order** (oldest first, not grouped by result type):
  - `[{RESULT}]` — one of `PASS`, `FAIL`, `SKIP`, `BLOCKED` (uppercase).
  - `{scenarioName}` — as given to `recordResult`, verbatim.
  - If `notes` is non-null and non-empty: append ` — {notes}` (an em dash surrounded by single spaces). If `notes` is null or empty, the line ends after `{scenarioName}` with no trailing separator.
- If no results have been recorded, the count line reads `0 scenario(s) recorded` and no result lines follow.

### Example

```
=== FeedbackKit test session: Release candidate 1.4 smoke test ===
3 scenario(s) recorded

[PASS] Sign in with valid credentials
[FAIL] Sign in with expired token — did not redirect to login, showed blank screen
[BLOCKED] Password reset flow — email delivery not configured in this environment
```

## Merging into a `BugReportBundler` report

`BugReportBundler`'s constructor accepts an optional `testSession: TestSession? = null`. When supplied, `build()` appends one additional section **after** the log section (see `spec/REPORT_FORMAT.md`), separated by a blank line:

```
=== FeedbackKit bug report ===
Generated at (epoch millis): {generatedAtMillis}

{deviceInfoSummary}

=== Recent logs ({logCount} lines) ===
{logLines}

=== Test session: {name} ===
{count} scenario(s) recorded

[{RESULT}] {scenarioName}{optional " — " + notes}
...
```

Note the merged section's header omits the outer `FeedbackKit` wrapper (`=== Test session: {name} ===`, not `=== FeedbackKit test session: {name} ===`) since it's already nested inside a `=== FeedbackKit bug report ===`-headed document — avoids a redundant "FeedbackKit" appearing twice in the same report. The count line and per-result line format are otherwise identical to the standalone export.

When `testSession` is `null` (the default), `build()`'s output is byte-for-byte identical to a `BugReportBundler` with no test-session support at all — this is a purely additive, opt-in change to the existing report format.
