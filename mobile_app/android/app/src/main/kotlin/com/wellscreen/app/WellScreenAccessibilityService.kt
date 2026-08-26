package com.wellscreen.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray

// Debug-only tag for the browsing-capture path specifically (not restricted-
// app blocking, which already has its own real signal - the block screen
// itself). Added because remote troubleshooting hit a wall: usage-stats
// sync proved pairing/Firestore/sync all work, isolating the problem to
// this capture path specifically, with no way to see WHERE it fails short
// of reading actual logcat output. Filter with: adb logcat -s WellScreenCapture
private const val CAPTURE_LOG_TAG = "WellScreenCapture"

class WellScreenAccessibilityService : AccessibilityService() {

    private var lastBlockedPackage: String? = null
    private var lastBlockTime: Long = 0L

    // Last domain captured per browser package, so repeated events for the
    // same still-loaded page (this fires more than once per navigation in
    // practice) don't spam BrowsingLogger with duplicate entries.
    private val lastCapturedDomain = mutableMapOf<String, String>()

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val currentPackage = event.packageName?.toString() ?: return

        // Do not block WellScreen itself.
        if (currentPackage == packageName) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> {
                // Fires on app switches and new windows/tabs - covers both
                // "child opened a browser" (captures whatever's already in
                // the address bar) and restricted-app detection.
                if (BrowserUrlExtractor.isKnownBrowser(currentPackage)) {
                    val msg = "$currentPackage: window-state/windows-changed event received"
                    Log.d(CAPTURE_LOG_TAG, msg)
                    CaptureDebugLogger.log(this, msg)
                }
                maybeCaptureBrowserUrl(currentPackage)
                checkRestrictedApp(currentPackage)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                // Covers in-app navigation that DOESN'T fire a window-state
                // event - the common case of typing a new URL into an
                // already-open browser's address bar and hitting Go. This
                // was the original gap: without it, capture only ever saw
                // whatever page a browser happened to already be showing
                // at the moment it became the foreground window, and
                // silently missed every navigation after that. Content-
                // changed fires constantly across every app, so this is
                // deliberately restricted to known-browser packages only -
                // restricted-app blocking doesn't need it (that's fully
                // covered by the branch above), so it's skipped here to
                // avoid running that check on every UI update system-wide.
                if (BrowserUrlExtractor.isKnownBrowser(currentPackage)) {
                    val msg = "$currentPackage: content-changed event received"
                    Log.d(CAPTURE_LOG_TAG, msg)
                    CaptureDebugLogger.log(this, msg)
                    maybeCaptureBrowserUrl(currentPackage)
                }
            }
            else -> return
        }
    }

    private fun checkRestrictedApp(currentPackage: String) {
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
     * Called from two different event branches in [onAccessibilityEvent]:
     * TYPE_WINDOW_STATE_CHANGED/TYPE_WINDOWS_CHANGED (switching into a
     * browser, or a new tab/window) and TYPE_WINDOW_CONTENT_CHANGED
     * (navigating to a new URL while already inside an open browser -
     * typing an address and hitting Go doesn't change the window itself,
     * so it never fires the first two on its own). An earlier version of
     * this only listened to the first two, on the reasoning that adding
     * content-changed - which fires constantly across every app - wasn't
     * worth the noise; in practice that meant capture only ever saw
     * whatever page a browser happened to already be showing at the
     * moment it became the foreground window, and silently missed every
     * navigation after that, which is a much bigger gap than the
     * originally-scoped "misses some single-page-app route changes." The
     * dedup check below (lastCapturedDomain) plus restricting the
     * content-changed branch to known-browser packages only (see that
     * branch's comment) keeps the added event volume bounded.
     */
    private fun maybeCaptureBrowserUrl(currentPackage: String) {
        if (!BrowserUrlExtractor.isKnownBrowser(currentPackage)) return

        try {
            val root = rootInActiveWindow
            if (root == null) {
                val msg = "$currentPackage: rootInActiveWindow is null, skipping"
                Log.d(CAPTURE_LOG_TAG, msg)
                CaptureDebugLogger.log(this, msg)
                return
            }

            val domain = BrowserUrlExtractor.extractDomain(root, currentPackage, this)
            if (domain == null) {
                val msg = "$currentPackage: extractDomain found nothing (address bar view " +
                    "not found, or its text wasn't URL-shaped)"
                Log.d(CAPTURE_LOG_TAG, msg)
                CaptureDebugLogger.log(this, msg)
                return
            }

            if (lastCapturedDomain[currentPackage] == domain) {
                val msg = "$currentPackage: '$domain' same as last capture, skipping"
                Log.d(CAPTURE_LOG_TAG, msg)
                CaptureDebugLogger.log(this, msg)
                return
            }

            lastCapturedDomain[currentPackage] = domain
            val msg = "$currentPackage: recording visit to '$domain'"
            Log.d(CAPTURE_LOG_TAG, msg)
            CaptureDebugLogger.log(this, msg)
            BrowsingLogger.recordVisit(this, currentPackage, domain)
        } catch (e: Exception) {
            val msg = "$currentPackage: capture threw ${e.javaClass.simpleName}: ${e.message}"
            Log.d(CAPTURE_LOG_TAG, msg)
            CaptureDebugLogger.log(this, msg)
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