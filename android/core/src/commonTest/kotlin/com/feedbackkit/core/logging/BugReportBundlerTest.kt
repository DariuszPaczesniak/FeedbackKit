package com.feedbackkit.core.logging

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertTrue

class BugReportBundlerTest {

    @BeforeTest
    fun clearBuffer() {
        Logger.clear()
    }

    @AfterTest
    fun cleanUp() {
        Logger.clear()
    }

    @Test
    fun build_includesDeviceInfoAndRecentLogs() {
        Logger.info("Discovery", "advertising + scanning")
        Logger.error("TrustGroup", "delete failed")

        val bundler = BugReportBundler(deviceInfoSummary = { "App version: 0.1\nPlatform: Test OS 1.0\n" })
        val report = bundler.build()

        assertTrue(report.contains("=== FeedbackKit bug report ==="))
        assertTrue(report.contains("App version: 0.1"))
        assertTrue(report.contains("Platform: Test OS 1.0"))
        assertTrue(report.contains("advertising + scanning"))
        assertTrue(report.contains("delete failed"))
    }

    @Test
    fun build_reportsHowManyLogLinesAreIncluded() {
        Logger.info("Tag", "one")
        Logger.info("Tag", "two")
        Logger.info("Tag", "three")

        val bundler = BugReportBundler(deviceInfoSummary = { "" })
        val report = bundler.build()

        assertTrue(report.contains("Recent logs (3 lines)"))
    }

    @Test
    fun build_stillProducesAReport_whenNoLogsHaveBeenRecorded() {
        val bundler = BugReportBundler(deviceInfoSummary = { "App version: 0.1\n" })
        val report = bundler.build()

        assertTrue(report.contains("Recent logs (0 lines)"))
    }

    @Test
    fun build_withNoTestSession_isUnchanged() {
        val bundler = BugReportBundler(deviceInfoSummary = { "App version: 0.1\n" })
        val report = bundler.build()

        assertTrue(!report.contains("Test session"))
    }

    @Test
    fun build_withTestSession_appendsMergedSection() {
        val session = TestSession("Smoke test", now = { 2000L })
        session.recordResult("Scenario A", TestResult.PASS)
        session.recordResult("Scenario B", TestResult.FAIL, "crashed")

        val bundler = BugReportBundler(
            deviceInfoSummary = { "App version: 0.1\n" },
            testSession = session
        )
        val report = bundler.build()

        assertTrue(report.contains("=== Test session: Smoke test ==="))
        assertTrue(!report.contains("=== FeedbackKit test session:"))
        assertTrue(report.contains("2 scenario(s) recorded"))
        assertTrue(report.contains("[PASS] Scenario A"))
        assertTrue(report.contains("[FAIL] Scenario B — crashed"))
    }
}
