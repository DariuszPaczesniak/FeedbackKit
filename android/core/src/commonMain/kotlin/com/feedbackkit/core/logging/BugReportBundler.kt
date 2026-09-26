package com.feedbackkit.core.logging

class BugReportBundler(
    private val deviceInfoSummary: () -> String,
    private val now: () -> Long = ::epochMillisNow
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
    }
}
