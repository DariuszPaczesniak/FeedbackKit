# FeedbackKit Bug Report Format

This document specifies the exact text format of a bundled bug report. Both the Android (Kotlin) and iOS (Swift) implementations must produce byte-for-byte identical output for identical inputs, so a report generated on one platform and shared on another is indistinguishable.

## Overall structure

```
=== FeedbackKit bug report ===
Generated at (epoch millis): {generatedAtMillis}

{deviceInfoSummary}

=== Recent logs ({logCount} lines) ===
{logLines}
```

## Field definitions

### Header
- Literal string: `=== FeedbackKit bug report ===`
- Followed by a newline.

### Generated timestamp
- Line: `Generated at (epoch millis): {generatedAtMillis}`
- `{generatedAtMillis}` is the current epoch time in milliseconds (integer, no decimal places), as returned by `System.currentTimeMillis()` (Android) or `Date().timeIntervalSince1970 * 1000` (iOS), rounded to an integer.
- Followed by a newline.

### Empty line
- A single blank line separating header from device info.

### Device info summary
- Multi-line string provided by `DeviceInfoProvider.summary()`.
- Each line ends with a newline. If the summary string does not end with a newline, one is appended.
- Example (Android):
  ```
  App version: 1.0.5
  Platform: Android 14 (API 34)
  Device: Google Pixel 8
  ```
- Example (iOS):
  ```
  App version: 1.0.5
  Platform: iOS 18.0
  Device: iPhone
  ```

### Empty line
- A single blank line separating device info from logs.

### Log section header
- Line: `=== Recent logs ({logCount} lines) ===`
- `{logCount}` is the number of buffered log lines, as an integer (e.g., "0", "42", "500").
- Followed by a newline.

### Log lines
- The buffered log lines, oldest first, each in the format:
  ```
  {timestampMillis} [{LEVEL}] {tag}: {message}
  ```
  - `{timestampMillis}`: epoch milliseconds (integer, no padding).
  - `{LEVEL}`: one of `DEBUG`, `INFO`, `WARN`, `ERROR` (uppercase).
  - `{tag}`: the log tag as-is (no escaping).
  - `{message}`: the log message as-is (no escaping).
- Joined with newlines (newline after each entry, including the last).
- If the buffer is empty, this section is empty (just the header, no individual lines).

## Examples

### Example 1: With logs

```
=== FeedbackKit bug report ===
Generated at (epoch millis): 1695384924000

App version: 1.0
Platform: iOS 17.0
Device: iPhone

=== Recent logs (2 lines) ===
1695384920000 [INFO] Discovery: started scanning
1695384922000 [ERROR] TrustGroup: delete failed
```

### Example 2: Empty buffer

```
=== FeedbackKit bug report ===
Generated at (epoch millis): 1695384924000

App version: 1.0
Platform: iOS 17.0
Device: iPhone

=== Recent logs (0 lines) ===
```

## Implementation notes

- No escaping or encoding — logs are included as-is, even if they contain newlines, quotes, or special characters. The report is meant to be human-readable, not machine-parsed.
- The timestamp in the report header is captured fresh at bundle time, so it reflects the moment the bundler was called, not when the first log was recorded.
- The log count in the header should match the actual number of lines that follow, for sanity-checking.
