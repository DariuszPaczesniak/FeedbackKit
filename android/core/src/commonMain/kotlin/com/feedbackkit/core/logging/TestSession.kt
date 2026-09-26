package com.feedbackkit.core.logging

enum class TestResult { PASS, FAIL, SKIP, BLOCKED }

data class TestScenarioResult(
    val scenarioName: String,
    val result: TestResult,
    val notes: String?,
    val recordedAtMillis: Long
)

class TestSession(
    val name: String,
    private val now: () -> Long = ::epochMillisNow
) {
    private val entries = mutableListOf<TestScenarioResult>()

    fun recordResult(scenarioName: String, result: TestResult, notes: String? = null) {
        entries.add(TestScenarioResult(scenarioName, result, notes, now()))
    }

    fun results(): List<TestScenarioResult> = entries.toList()

    fun exportReport(): String = buildString {
        appendLine("=== FeedbackKit test session: $name ===")
        appendLine("${entries.size} scenario(s) recorded")
        appendLine()
        entries.forEach { entry -> appendLine(formatResultLine(entry)) }
    }

    fun clear() {
        entries.clear()
    }
}

internal fun formatResultLine(entry: TestScenarioResult): String {
    val notesSuffix = if (!entry.notes.isNullOrEmpty()) " — ${entry.notes}" else ""
    return "[${entry.result.name}] ${entry.scenarioName}$notesSuffix"
}
