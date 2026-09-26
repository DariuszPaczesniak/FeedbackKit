package com.feedbackkit.core.logging

class BugReportBundler(
    private val deviceInfoSummary: () -> String,
    private val now: () -> Long = ::epochMillisNow,
    private val testSession: TestSession? = null
) {
    fun build(): String = buildString {
        appendLine("=== FeedbackKit bug report ===")
        appendLine("Generated at (epoch millis): ${now()}")
        appendLine()
        val deviceInfo = deviceInfoSummary()
        append(deviceInfo)
        if (!deviceInfo.endsWith("\n")) appendLine()
        appendLine()
        appendLine("=== Recent logs (${Logger.size()} lines) ===")
        appendLine(Logger.recentLogsText())

        testSession?.let { session ->
            appendLine()
            appendLine("=== Test session: ${session.name} ===")
            val results = session.results()
            appendLine("${results.size} scenario(s) recorded")
            appendLine()
            results.forEach { entry -> appendLine(formatResultLine(entry)) }
        }
    }
}
