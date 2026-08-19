package com.wellscreen.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray

class WellScreenAccessibilityService : AccessibilityService() {

    private var lastBlockedPackage: String? = null
    private var lastBlockTime: Long = 0L

    // Last domain captured per browser package, so repeated events for the
    // same still-loaded page (this fires more than once per navigation in
    // practice) don't spam BrowsingLogger with duplicate entries.
    private val lastCapturedDomain = mutableMapOf<String, String>()

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val validEvent =
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
                    event.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED

        if (!validEvent) return

        val currentPackage = event.packageName?.toString() ?: return

        // Do not block WellScreen itself.
        if (currentPackage == packageName) return

        maybeCaptureBrowserUrl(currentPackage)

        val restrictedPackages = getRestrictedPackages()

        if (restrictedPackages.contains(currentPackage)) {
            val now = System.currentTimeMillis()

            val recentlyBlockedSameApp =
                lastBlockedPackage == currentPackage && now - lastBlockTime < 2500

            if (!recentlyBlockedSameApp) {
                lastBlockedPackage = currentPackage
                lastBlockTime = now

                try {
                    openBlockedScreen(currentPackage)
                    RestrictionLogger.recordOutcome(this, currentPackage, "blocked", now)
                } catch (_: Exception) {
                    RestrictionLogger.recordOutcome(
                        this,
                        currentPackage,
                        "failed_exception",
                        now,
                    )
                }

                SmsAlertSender.maybeSendRestrictedAppAlert(
                    this,
                    currentPackage,
                    getAppLabel(currentPackage),
                    now,
                )
            }
        }
    }

    override fun onInterrupt() {
        // Required override.
    }

    /**
     * Attempts to read the current URL out of [currentPackage]'s address
     * bar (only does anything for the known-browser packages listed in
     * BrowserUrlExtractor) and records it via BrowsingLogger if it's a new
     * domain since the last time this ran for that package.
     *
     * SCOPE/LIMITATION, stated honestly: this only fires on
     * TYPE_WINDOW_STATE_CHANGED / TYPE_WINDOWS_CHANGED - the events this
     * service already listens to for restricted-app detection - not on
     * every keystroke or DOM change. That reliably catches full page loads
     * and new tabs without adding a noisy new event subscription, but it
     * can miss same-page navigation that doesn't trigger a window-state
     * change (e.g. some single-page-app route changes). A reasonable
     * tradeoff for a first working version, not a hidden gap - see
     * ml/site_category/README.md and BrowserUrlExtractor's doc comment for
     * the rest of what's deliberately not handled yet (category matching,
     * blocking, self-harm keyword detection).
     */
    private fun maybeCaptureBrowserUrl(currentPackage: String) {
        if (!BrowserUrlExtractor.isKnownBrowser(currentPackage)) return

        try {
            val root = rootInActiveWindow ?: return
            val domain = BrowserUrlExtractor.extractDomain(root, currentPackage) ?: return

            if (lastCapturedDomain[currentPackage] == domain) return

            lastCapturedDomain[currentPackage] = domain
            BrowsingLogger.recordVisit(this, currentPackage, domain)
        } catch (_: Exception) {
            // Best-effort capture only - never let this interfere with the
            // restricted-app blocking logic below.
        }
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

    private fun getAppLabel(packageName: String): String {
        return try {
            val info = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            packageName
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