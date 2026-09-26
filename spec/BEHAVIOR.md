# FeedbackKit Ring Buffer & Logger Behavior

This document specifies the runtime behavior of the `Logger` ring buffer and the `BugReportBundler`. Both implementations (Kotlin for Android, Swift for iOS) must conform to these semantics.

## Logger: Ring Buffer semantics

### Buffer capacity

- Fixed capacity of **500 log entries**.
- When the buffer is full and a new entry is logged, the oldest entry is evicted (FIFO order).
- No other eviction policy (e.g., by level, by tag) — only age.

### Entry format

Each logged entry is stored as:
```
timestampMillis: Long (or UInt64 on iOS)
level: LogLevel (enum: DEBUG, INFO, WARN, ERROR)
tag: String
message: String
```

The timestamp is captured at the moment `log()` is called, as epoch milliseconds.

### Log levels

Four levels, in severity order:
- `DEBUG` — lowest severity
- `INFO`
- `WARN`
- `ERROR` — highest severity

No filtering by level — all levels are buffered equally. The level is included in the formatted output only for readability/debugging.

### Convenience methods

- `Logger.debug(tag, message)` — logs at DEBUG level.
- `Logger.info(tag, message)` — logs at INFO level.
- `Logger.warn(tag, message)` — logs at WARN level.
- `Logger.error(tag, message)` — logs at ERROR level.

All forward to the same underlying `log(level, tag, message)` function.

### Platform logging mirror

Every entry is **immediately mirrored** to the platform's native logging:
- **Android:** via `android.util.Log.d/i/w/e()` (Logcat).
- **iOS:** via `os_log()` or `print()` (Xcode console / system logs).

This mirror is asynchronous (fire-and-forget) — even if the platform logging call fails, the entry is still buffered. Both implementations must mirror every level; filtering by level is the responsibility of the native logging system, not this code.

### Thread safety

**Deliberately not thread-safe.** This is a live-session diagnostic aid, not a system of record.

Worst-case behavior under concurrent logging from multiple threads (e.g., a BLE callback thread and the UI thread simultaneously):
- An entry may be dropped (evicted early if two threads race to add at the tail).
- An entry may appear out-of-order in the buffer.
- An entry may be partially written (corrupted bytes).

These are acceptable tradeoffs for the use case. If a consumer needs thread-safe logging, they should synchronize at their call site before calling `Logger.log()`, or wrap the Logger in a mutex/serial queue.

### Query interface

- `Logger.size()` — returns the current number of entries in the buffer (0 to 500). Used primarily for testing.
- `Logger.recentLogsText()` — returns all buffered entries as a single plain-text string, oldest first, each line formatted per `REPORT_FORMAT.md`. Linebreaks between entries only (no leading/trailing blank lines unless the buffer is empty, in which case an empty string is returned).

### Lifecycle

- `Logger.clear()` — empties the buffer. Used by tests; not expected to be called by production app code.

## BugReportBundler

### Constructor

```
BugReportBundler(
  deviceInfoSummary: () -> String,     // injected, called at build() time
  now: () -> Long                      // optional, defaults to current epoch millis
)
```

Both parameters are functions, not values, so the bundler is unit-testable without a real `Context` (Android) or `UIDevice` (iOS).

### build(): String

Returns the formatted bug report as a single string, per `REPORT_FORMAT.md`.

**Timing:** The timestamp in the report header and the buffered logs are captured at the moment `build()` is called. If the Logger's buffer is still being written to concurrently (see "Thread safety" above), the report may contain partially-stale logs.

### No state

The bundler is stateless — each call to `build()` is independent and reads the Logger and device info fresh. Multiple calls to `build()` on the same bundler instance produce identical output (up to the timestamp field).

## Device info provider

### Interface

```
DeviceInfoProvider.summary(): String
```

Returns a multi-line plain-text summary of app + OS metadata, without trailing newline handling (the bundler adds a trailing newline if needed per `REPORT_FORMAT.md`).

### Expected fields

- **App version:** obtained from the app's own manifest/bundle metadata (e.g., `versionName` on Android, `CFBundleShortVersionString` on iOS).
- **Platform:** OS name + version (e.g., "Android 14 (API 34)", "iOS 17.0").
- **Device:** manufacturer + model (e.g., "Google Pixel 8", "iPhone").

### Error handling

If any field cannot be obtained (e.g., a missing manifest key, an exception reading the bundle), the provider should include the error context in the summary line itself (e.g., "App version: unknown (failed to read manifest)") rather than crashing or returning an empty string. A report with some fields missing is more useful than no report at all.

### Example output (iOS)

```
App version: 1.0.5 (42)
Platform: iOS 18.0
Device: iPhone
```

### Example output (Android)

```
App version: 1.0.5
Platform: Android 14 (API 34)
Device: Google Pixel 8
```

(Format is up to each platform's implementation — they don't need to match exactly, only express the same information.)

## No guarantees beyond these

- **Persistence:** the buffer is in-memory only, lost on process death.
- **Ordering:** entries are buffered in call order, but concurrent calls may reorder (see "Thread safety" above).
- **Capacity:** the 500-entry cap is a tuning constant, chosen to be small enough for typical share times yet large enough to capture a meaningful diagnostic window. It can be adjusted in future versions, but both platforms must remain in sync.
