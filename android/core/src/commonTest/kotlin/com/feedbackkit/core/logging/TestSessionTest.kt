package com.feedbackkit.core.logging

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TestSessionTest {

    @Test
    fun recordResult_appendsInOrder() {
        val session = TestSession("My session", now = { 1000L })
        session.recordResult("Scenario A", TestResult.PASS)
        session.recordResult("Scenario B", TestResult.FAIL, "did not respond")

        val results = session.results()
        assertEquals(2, results.size)
        assertEquals("Scenario A", results[0].scenarioName)
        assertEquals(TestResult.PASS, results[0].result)
        assertEquals("Scenario B", results[1].scenarioName)
        assertEquals(TestResult.FAIL, results[1].result)
        assertEquals("did not respond", results[1].notes)
    }

    @Test
    fun recordResult_sameScenarioTwice_producesTwoEntries() {
        val session = TestSession("Session", now = { 1000L })
        session.recordResult("Scenario A", TestResult.FAIL)
        session.recordResult("Scenario A", TestResult.PASS)

        assertEquals(2, session.results().size)
    }

    @Test
    fun exportReport_includesHeaderCountAndResults() {
        val session = TestSession("Release candidate 1.4 smoke test", now = { 1000L })
        session.recordResult("Sign in with valid credentials", TestResult.PASS)
        session.recordResult(
            "Sign in with expired token",
            TestResult.FAIL,
            "did not redirect to login, showed blank screen"
        )
        session.recordResult(
            "Password reset flow",
            TestResult.BLOCKED,
            "email delivery not configured in this environment"
        )

        val report = session.exportReport()

        assertTrue(report.contains("=== FeedbackKit test session: Release candidate 1.4 smoke test ==="))
        assertTrue(report.contains("3 scenario(s) recorded"))
        assertTrue(report.contains("[PASS] Sign in with valid credentials"))
        assertTrue(
            report.contains(
                "[FAIL] Sign in with expired token — did not redirect to login, showed blank screen"
            )
        )
        assertTrue(
            report.contains(
                "[BLOCKED] Password reset flow — email delivery not configured in this environment"
            )
        )
    }

    @Test
    fun exportReport_withNoNotes_hasNoTrailingSeparator() {
        val session = TestSession("Session", now = { 1000L })
        session.recordResult("Scenario A", TestResult.SKIP)

        val report = session.exportReport()

        assertTrue(report.contains("[SKIP] Scenario A"))
        assertTrue(!report.contains("Scenario A —"))
    }

    @Test
    fun exportReport_withNoResults_reportsZero() {
        val session = TestSession("Empty session", now = { 1000L })

        val report = session.exportReport()

        assertTrue(report.contains("0 scenario(s) recorded"))
    }

    @Test
    fun clear_emptiesResults_butKeepsName() {
        val session = TestSession("Session", now = { 1000L })
        session.recordResult("Scenario A", TestResult.PASS)

        session.clear()

        assertEquals(0, session.results().size)
        assertEquals("Session", session.name)
    }
}
