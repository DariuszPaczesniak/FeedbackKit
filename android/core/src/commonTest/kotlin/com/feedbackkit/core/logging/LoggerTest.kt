package com.feedbackkit.core.logging

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LoggerTest {

    @BeforeTest
    fun clearBuffer() {
        Logger.clear()
    }

    @AfterTest
    fun cleanUp() {
        Logger.clear()
    }

    @Test
    fun log_appendsAFormattedLine() {
        Logger.info("Discovery", "started scanning")

        val text = Logger.recentLogsText()
        assertTrue(text.contains("[INFO]"))
        assertTrue(text.contains("Discovery:"))
        assertTrue(text.contains("started scanning"))
    }

    @Test
    fun log_preservesOrder() {
        Logger.info("Tag", "first")
        Logger.info("Tag", "second")
        Logger.info("Tag", "third")

        val lines = Logger.recentLogsText().lines()
        assertTrue(lines[0].contains("first"))
        assertTrue(lines[1].contains("second"))
        assertTrue(lines[2].contains("third"))
    }

    @Test
    fun log_eachConvenienceMethod_usesTheRightLevel() {
        Logger.debug("Tag", "d")
        Logger.info("Tag", "i")
        Logger.warn("Tag", "w")
        Logger.error("Tag", "e")

        val lines = Logger.recentLogsText().lines()
        assertTrue(lines[0].contains("[DEBUG]"))
        assertTrue(lines[1].contains("[INFO]"))
        assertTrue(lines[2].contains("[WARN]"))
        assertTrue(lines[3].contains("[ERROR]"))
    }

    @Test
    fun log_capsAtMaxEntries_evictingOldestFirst() {
        repeat(520) { i -> Logger.info("Tag", "message-$i") }

        assertEquals(500, Logger.size())
        val lines = Logger.recentLogsText().lines()
        assertTrue(lines.none { it.endsWith("message-0") }, "oldest entries should have been evicted")
        assertTrue(lines.none { it.endsWith("message-19") }, "oldest entries should have been evicted")
        assertTrue(lines.any { it.endsWith("message-20") }, "the 500 most recent entries should remain")
        assertTrue(lines.any { it.endsWith("message-519") }, "the most recent entry should remain")
    }

    @Test
    fun clear_emptiesTheBuffer() {
        Logger.info("Tag", "something")
        assertTrue(Logger.size() > 0)

        Logger.clear()

        assertEquals(0, Logger.size())
        assertEquals("", Logger.recentLogsText())
    }
}
