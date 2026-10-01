package com.wellscreen.app

import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "wellscreen/apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }

                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }

                "openUsageAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)

        return installedApps
            .filter { app ->
                val hasLauncher = pm.getLaunchIntentForPackage(app.packageName) != null
                val isNotWellScreen = app.packageName != packageName

                // Keep launcher apps, including system apps like YouTube/Chrome,
                // because many demo phones have them pre-installed.
                hasLauncher && isNotWellScreen
            }
            .map { app ->
                val appName = pm.getApplicationLabel(app).toString()

                mapOf(
                    "appName" to appName,
                    "packageName" to app.packageName
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["appName"]?.lowercase() }
    }
}