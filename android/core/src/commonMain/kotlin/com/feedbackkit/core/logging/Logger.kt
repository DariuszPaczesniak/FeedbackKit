package com.feedbackkit.core.logging

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

object Logger {
    private const val MAX_ENTRIES = 500
    private val entries = ArrayDeque<String>()

    fun log(level: LogLevel, tag: String, message: String) {
        val line = "${epochMillisNow()} [${level.name}] $tag: $message"
        entries.addLast(line)
        while (entries.size > MAX_ENTRIES) {
            entries.removeFirst()
        }
        platformLog(level, tag, message)
    }

    fun debug(tag: String, message: String) = log(LogLevel.DEBUG, tag, message)
    fun info(tag: String, message: String) = log(LogLevel.INFO, tag, message)
    fun warn(tag: String, message: String) = log(LogLevel.WARN, tag, message)
    fun error(tag: String, message: String) = log(LogLevel.ERROR, tag, message)

    fun recentLogsText(): String = entries.joinToString("\n")

    fun size(): Int = entries.size

    fun clear() {
        entries.clear()
    }
}

expect fun platformLog(level: LogLevel, tag: String, message: String)

expect class DeviceInfoProvider {
    fun summary(): String
}
