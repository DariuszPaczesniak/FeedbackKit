# FeedbackKit Test Checklist Format

This document specifies the predefined test checklist: the file format a host app hands to FeedbackKit, how a checklist maps onto a `TestSession`, how checklist progress is persisted, and the exported-report additions. Both the Android (Kotlin) and iOS (Swift) implementations must conform. It extends `spec/TEST_SESSION_FORMAT.md` -- everything there still applies, and a session **without** a checklist is completely unaffected by this document (its report stays byte-for-byte identical).

## Purpose

A plain `TestSession` records whatever scenario names a tester types. A checklist lets the host app ship a ready-made test plan instead, so the tester ticks through known items inside the app rather than retyping scenario names, progress survives an app relaunch, and the exported report also lists what was never run.

## Checklist file format (JSON)

```json
{
  "id": "example-smoke-test",
  "title": "Example smoke test",
  "version": "1",
  "sections": [
    {
      "id": "launch",
      "title": "Launch",
      "items": [
        { "id": "launch-cold", "title": "Cold launch shows the home screen" },
        { "id": "launch-offline", "title": "Launch in airplane mode", "detail": "Expect an offline banner, no crash." }
      ]
    },
    {
      "id": "share",
      "title": "Sharing",
      "items": [
        { "id": "share-report", "title": "Send a bug report via the share sheet" }
      ]
    }
  ]
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Identifies the checklist. A saved session remembers this id, so a relaunch can find the in-progress session for the same checklist. |
| `title` | string | yes | Shown in the UI and in the report. |
| `version` | string (a JSON number is also accepted and kept as its text form) | no | Free-form; shown in the report so a reader knows which revision of the plan was run. |
| `sections` | array | yes | Ordered. Report and UI keep this order. |
| `sections[].id` | string | yes | Unique within the checklist. |
| `sections[].title` | string | yes | |
| `sections[].items` | array | yes | Ordered. |
| `items[].id` | string | yes | **Stable and never reused** -- see below. Unique across the whole checklist (not just its section). |
| `items[].title` | string | yes | Used as the scenario name. |
| `items[].detail` | string | no | Steps / expected outcome, shown under the title in the UI. Not included in the report. |

Unknown keys are ignored (forward compatibility). The file is UTF-8 JSON.

### Validation

Loading fails with a descriptive error -- never a crash -- when:

- the data is not valid JSON, or a required field is missing or has the wrong type;
- the checklist `id` or `title`, or any section/item `id` or `title`, is empty or whitespace-only;
- there are no sections, or a section has no items;
- two sections share an `id`, or two items anywhere in the checklist share an `id`.

### The stable-id rule

Results are keyed by item `id`, never by title or position. Consequences:

- Editing an item's `title` or `detail`, or moving it to another position or section, never orphans recorded progress: the next report shows the result under the **new** title.
- An item `id` must never be reused for a different test. Retire the id with the item and mint a new one for the replacement.
- If a saved session holds a result for an item `id` the current checklist no longer contains, that result is not lost: the report lists it under "Ad-hoc scenarios" with the scenario name it was recorded under.

## Mapping a checklist onto `TestSession`

A checklist-backed session is a normal `TestSession` constructed with the checklist attached (`TestSession(name, checklist = ...)`). Additions to the API in `TEST_SESSION_FORMAT.md`:

```
TestSession(name: String, id: String = <random UUID>, checklist: TestChecklist? = null, now: () -> Long = epochMillisNow)

id: String                      // stable session id; also the persisted file name
checklist: TestChecklist?       // null for a plain (free-form) session

recordResult(item: TestChecklistItem, result: TestResult, notes: String? = null)
updateNotes(itemId: String, notes: String?)    // no-op if the item has no result
resetResult(itemId: String)                    // back to "not run"
result(itemId: String): TestScenarioResult?
checklistProgress(): TestChecklistProgress?    // null without a checklist

TestScenarioResult gains: itemId: String?      // null for free-form recordResult(scenarioName, ...)
```

- **One result per item.** `recordResult(item, ...)` records a `TestScenarioResult` whose `scenarioName` is the item's title at recording time and whose `itemId` is the item's id. Unlike the free-form `recordResult(scenarioName, ...)` (which always appends), recording an item that already has a result **replaces** it: the old entry is removed and the new one appended, so `results()` stays in "last recorded" order and each item appears at most once.
- **"Not run" is not a `TestResult`.** `TestResult` stays `PASS | FAIL | SKIP | BLOCKED`. An item is *not run* exactly when the session holds no result for its `id`; `resetResult` returns an item to that state. "Run" therefore means "has any recorded result" -- a deliberate `SKIP` counts as run.
- **Free-form entries still work.** `recordResult(scenarioName, ...)` on a checklist-backed session appends an ad-hoc result (`itemId = null`), exactly as on a plain session.
- `updateNotes` replaces only the notes of an item's existing result (keeping its result, position and `recordedAtMillis`); an empty string is stored as null.

```
TestChecklistProgress
  total: Int        // number of items in the checklist
  run: Int          // items with a recorded result
  notRun: Int       // total - run
  count(result: TestResult): Int   // items currently holding that result
```

## Persistence

Plain sessions remain in-memory only (the original behavior). A host app -- or the provided UI when it is given a checklist -- may persist a session with a session store:

- One JSON file per session id, under the app's Application Support directory (iOS: `Application Support/FeedbackKit/TestSessions/{id}.json`, with the id percent-encoded so it is always a safe file name).
- The file stores the session id, name, checklist id (not the checklist itself -- the checklist is re-supplied on restore so edited titles apply), every result (scenario name, result, notes, recorded-at time, item id), and a saved-at time used to pick the most recent in-progress session for a checklist.
- Read and write failures (missing directory, disk full, a corrupt or unreadable file) never crash: they are logged through `Logger` (tag `TestSessionStore`) and surface as "nothing saved" / "nothing to restore".
- Clearing a session deletes its file.

The persisted file is a platform-local cache, not an interchange format; the two platforms do not need to read each other's files.

## Exported report additions

When the session has **no** checklist, `exportReport()` and the `BugReportBundler` merged section are exactly as specified in `TEST_SESSION_FORMAT.md` -- byte-for-byte unchanged.

When the session **has** a checklist, the part after the session header line is:

```
{count} scenario(s) recorded
Checklist: {checklistTitle} ({checklistId}{", version " + version if present})
Progress: {run} of {total} run
Results: {pass} PASS, {fail} FAIL, {skip} SKIP, {blocked} BLOCKED, {notRun} NOT RUN

--- {section title} ---
[{RESULT}] {item title}{optional " — " + notes}
[NOT RUN] {item title}
...

--- Ad-hoc scenarios ---
[{RESULT}] {scenarioName}{optional " — " + notes}
...

--- Not run ({notRun}) ---
- {section title}: {item title}
...
```

- `{count}` is `results().size`, as before (checklist results plus ad-hoc results).
- `Progress` and `Results` count **checklist items only**; ad-hoc results are not included.
- One `--- {section title} ---` block per section, in checklist order, listing **every** item in checklist order. An item with a result uses the standard result line format from `TEST_SESSION_FORMAT.md`, with the item's **current** title; an item without one is `[NOT RUN] {item title}`.
- The `--- Ad-hoc scenarios ---` block lists, in recorded order, every result with no `itemId` plus any result whose `itemId` is not in the checklist (shown with its recorded `scenarioName`). Omitted entirely when there are none.
- The `--- Not run ({notRun}) ---` block repeats the not-run items, in checklist order, as `- {section title}: {item title}`, so a reader sees the gaps at a glance. Omitted entirely when every item has been run.
- Blocks are separated by one blank line. Every line ends with a newline; there is no trailing blank line.
- Item `detail` text is not included.

### Example (merged into a bug report)

```
=== Test session: RC 1.1 smoke test ===
3 scenario(s) recorded
Checklist: Example smoke test (example-smoke-test, version 1)
Progress: 2 of 3 run
Results: 1 PASS, 1 FAIL, 0 SKIP, 0 BLOCKED, 1 NOT RUN

--- Launch ---
[PASS] Cold launch shows the home screen
[FAIL] Launch in airplane mode — no offline banner

--- Sharing ---
[NOT RUN] Send a bug report via the share sheet

--- Ad-hoc scenarios ---
[PASS] Rotate to landscape on the home screen

--- Not run (1) ---
- Sharing: Send a bug report via the share sheet
```

(The standalone `exportReport()` form is identical except its first line is `=== FeedbackKit test session: {name} ===`.)
