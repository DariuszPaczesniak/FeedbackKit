package com.feedbackkit.core.logging

import android.content.Context
import android.os.Build

actual class DeviceInfoProvider(private val context: Context) {

    actual fun summary(): String = buildString {
        val versionName = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown (${e.message})"
        }
        appendLine("App version: $versionName")
        appendLine("Platform: Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
    }
}
