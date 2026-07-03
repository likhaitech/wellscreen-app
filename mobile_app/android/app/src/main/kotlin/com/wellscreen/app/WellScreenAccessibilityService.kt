package com.wellscreen.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray

class WellScreenAccessibilityService : AccessibilityService() {

    private var lastBlockedPackage: String? = null
    private var lastBlockTime: Long = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val validEvent =
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
                    event.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED

        if (!validEvent) return

        val currentPackage = event.packageName?.toString() ?: return

        // Do not block WellScreen itself.
        if (currentPackage == packageName) return

        val restrictedPackages = getRestrictedPackages()

        if (restrictedPackages.contains(currentPackage)) {
            val now = System.currentTimeMillis()

            val recentlyBlockedSameApp =
                lastBlockedPackage == currentPackage && now - lastBlockTime < 2500

            if (!recentlyBlockedSameApp) {
                lastBlockedPackage = currentPackage
                lastBlockTime = now
                openBlockedScreen(currentPackage)
            }
        }
    }

    override fun onInterrupt() {
        // Required override.
    }

    private fun getRestrictedPackages(): Set<String> {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)

            // Flutter shared_preferences stores string keys with "flutter." prefix on Android.
            val raw = prefs.getString("flutter.restricted_packages_json", "[]") ?: "[]"

            val jsonArray = JSONArray(raw)
            val result = mutableSetOf<String>()

            for (i in 0 until jsonArray.length()) {
                result.add(jsonArray.getString(i))
            }

            result
        } catch (_: Exception) {
            emptySet()
        }
    }

    private fun openBlockedScreen(blockedPackage: String) {
        val intent = Intent(this, BlockedAppActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        intent.putExtra("blocked_package", blockedPackage)
        startActivity(intent)
    }
}