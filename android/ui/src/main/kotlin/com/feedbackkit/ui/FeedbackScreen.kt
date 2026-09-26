package com.feedbackkit.ui

import android.content.ClipData
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.feedbackkit.core.logging.BugReportBundler
import com.feedbackkit.core.logging.DeviceInfoProvider
import com.feedbackkit.core.logging.TestResult
import com.feedbackkit.core.logging.TestSession
import java.io.File

/**
 * Drop-in feedback screen: previews + shares a bug report (device info + recent
 * Logger lines), and optionally lets a QA tester run a named test session --
 * recording PASS/FAIL/SKIP/BLOCKED results per scenario -- merged into the
 * same shared report. A host app can use this as-is, or call
 * [BugReportBundler]/[TestSession] directly to build its own UI.
 */
@Composable
fun FeedbackScreen() {
    val context = LocalContext.current
    val deviceInfoProvider = remember { DeviceInfoProvider(context) }

    var sessionName by remember { mutableStateOf("") }
    var session by remember { mutableStateOf<TestSession?>(null) }
    var resultsVersion by remember { mutableIntStateOf(0) }
    var scenarioName by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }

    fun record(result: TestResult) {
        val active = session ?: return
        if (scenarioName.isBlank()) return
        active.recordResult(scenarioName, result, notes.ifBlank { null })
        scenarioName = ""
        notes = ""
        resultsVersion++
    }

    fun buildReportText(): String {
        val bundler = BugReportBundler(
            deviceInfoSummary = { deviceInfoProvider.summary() },
            testSession = session
        )
        return bundler.build()
    }

    Column(
        modifier = Modifier
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Text(stringResource(R.string.feedbackkit_test_session_title))

        if (session == null) {
            OutlinedTextField(
                value = sessionName,
                onValueChange = { sessionName = it },
                label = { Text(stringResource(R.string.feedbackkit_test_session_name_label)) },
                modifier = Modifier.fillMaxWidth()
            )
            Button(onClick = {
                if (sessionName.isNotBlank()) {
                    session = TestSession(sessionName)
                }
            }) {
                Text(stringResource(R.string.feedbackkit_test_session_start_button))
            }
        } else {
            Text(session!!.name)

            OutlinedTextField(
                value = scenarioName,
                onValueChange = { scenarioName = it },
                label = { Text(stringResource(R.string.feedbackkit_scenario_name_label)) },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(stringResource(R.string.feedbackkit_notes_label)) },
                modifier = Modifier.fillMaxWidth()
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { record(TestResult.PASS) }) {
                    Text(stringResource(R.string.feedbackkit_result_pass))
                }
                Button(onClick = { record(TestResult.FAIL) }) {
                    Text(stringResource(R.string.feedbackkit_result_fail))
                }
                Button(onClick = { record(TestResult.SKIP) }) {
                    Text(stringResource(R.string.feedbackkit_result_skip))
                }
                Button(onClick = { record(TestResult.BLOCKED) }) {
                    Text(stringResource(R.string.feedbackkit_result_blocked))
                }
            }

            Text(stringResource(R.string.feedbackkit_recorded_results_label))
            // Keyed on resultsVersion so this recomposes after each recordResult call --
            // TestSession itself isn't Compose-observable, it's a plain accumulator.
            val results = remember(resultsVersion) { session!!.results() }
            LazyColumn {
                items(results) { entry ->
                    val notesSuffix = if (!entry.notes.isNullOrEmpty()) " — ${entry.notes}" else ""
                    Text("[${entry.result.name}] ${entry.scenarioName}$notesSuffix")
                }
            }
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

        Text(stringResource(R.string.feedbackkit_title))
        Button(onClick = {
            val file = File(context.cacheDir, "feedbackkit-reports").apply { mkdirs() }
                .resolve("feedbackkit-bug-report-${System.currentTimeMillis()}.txt")
            file.writeText(buildReportText())
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.feedbackkit.fileprovider", file)

            val emailSubject = context.getString(R.string.feedbackkit_email_subject)
            val clipDataLabel = context.getString(R.string.feedbackkit_clip_data_label)
            val shareChooserTitle = context.getString(R.string.feedbackkit_share_chooser_title)
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, emailSubject)
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newUri(context.contentResolver, clipDataLabel, uri)
            }
            context.startActivity(Intent.createChooser(sendIntent, shareChooserTitle))
        }) {
            Text(stringResource(R.string.feedbackkit_send_button))
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
        Text(stringResource(R.string.feedbackkit_preview_label))
        Text(buildReportText())
    }
}
