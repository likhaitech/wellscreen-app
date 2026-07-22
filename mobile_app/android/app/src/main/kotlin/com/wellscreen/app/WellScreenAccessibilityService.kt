package com.wellscreen.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class WellScreenAccessibilityService : AccessibilityService() {

    private val websiteCategoryDetector = WebsiteCategoryDetector()

    private var lastDetectedDomain: String? = null
    private var lastDetectedCategory: String? = null
    private var lastDetectedTime: Long = 0L

    private var lastBlockedDomain: String? = null
    private var lastBlockedWebsiteTime: Long = 0L

    private var lastBlockedPackageName: String? = null
    private var lastBlockedAppTime: Long = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) {
            return
        }

        val packageName = event.packageName?.toString() ?: return

        if (!isSupportedEvent(event.eventType)) {
            return
        }

        handleRestrictedAppOpenIfNeeded(packageName)

        if (!isSupportedBrowser(packageName)) {
            return
        }

        val visibleTexts = mutableListOf<String>()

        for (textItem in event.text) {
            val text = textItem?.toString()?.trim()

            if (!text.isNullOrEmpty()) {
                visibleTexts.add(text)
            }
        }

        val rootNode = rootInActiveWindow
        collectVisibleText(rootNode, visibleTexts)

        val detectionResult =
            websiteCategoryDetector.detectFromTexts(visibleTexts) ?: return

        handleWebsiteCategoryDetection(
            browserPackageName = packageName,
            detectionResult = detectionResult
        )
    }

    override fun onInterrupt() {
        // No active interruption handling is needed for app and website blocking.
    }

    private fun handleRestrictedAppOpenIfNeeded(packageName: String) {
        if (!isRestrictedApp(packageName)) {
            return
        }

        val currentTime = System.currentTimeMillis()

        val isSameRecentBlock =
            packageName == lastBlockedPackageName &&
                currentTime - lastBlockedAppTime < APP_BLOCK_DEBOUNCE_MS

        if (isSameRecentBlock) {
            return
        }

        lastBlockedPackageName = packageName
        lastBlockedAppTime = currentTime

        val appName = getReadableAppName(packageName)
        val attemptCount = recordRestrictedAppOpenAttempt(
            packageName = packageName,
            appName = appName,
            attemptedAt = currentTime
        )

        val blockIntent = Intent(this, BlockedAppActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(BlockedAppActivity.EXTRA_APP_NAME, appName)
            putExtra(BlockedAppActivity.EXTRA_PACKAGE_NAME, packageName)
            putExtra(BlockedAppActivity.EXTRA_ATTEMPT_COUNT, attemptCount)
        }

        try {
            startActivity(blockIntent)

            Log.d(
                LOG_TAG,
                "Blocked restricted app: app=$appName, package=$packageName, " +
                    "attemptCount=$attemptCount"
            )
        } catch (exception: Exception) {
            Log.e(
                LOG_TAG,
                "Failed to open blocked app screen.",
                exception
            )
        }
    }

    private fun isRestrictedApp(packageName: String): Boolean {
        if (packageName == applicationContext.packageName) {
            return false
        }

        if (isSupportedBrowser(packageName)) {
            return false
        }

        return restrictedAppPackages.contains(packageName)
    }

    private fun recordRestrictedAppOpenAttempt(
        packageName: String,
        appName: String,
        attemptedAt: Long
    ): Int {
        val preferences = getSharedPreferences(
            RESTRICTED_APP_ATTEMPT_PREFERENCES,
            MODE_PRIVATE
        )

        val attemptKey = "attemptCount_$packageName"
        val attemptCount = preferences.getInt(attemptKey, 0) + 1

        preferences.edit()
            .putInt(attemptKey, attemptCount)
            .putString("lastBlockedAppName", appName)
            .putString("lastBlockedPackageName", packageName)
            .putInt("lastBlockedAttemptCount", attemptCount)
            .putLong("lastBlockedAttemptAt", attemptedAt)
            .apply()

        return attemptCount
    }

    private fun getReadableAppName(packageName: String): String {
        return try {
            val applicationInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA
            )

            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (exception: Exception) {
            packageName
                .substringAfterLast(".")
                .replaceFirstChar { firstChar ->
                    if (firstChar.isLowerCase()) {
                        firstChar.titlecase()
                    } else {
                        firstChar.toString()
                    }
                }
        }
    }

    private fun isSupportedBrowser(packageName: String): Boolean {
        return supportedBrowserPackages.contains(packageName)
    }

    private fun isSupportedEvent(eventType: Int): Boolean {
        return eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            eventType == AccessibilityEvent.TYPE_VIEW_FOCUSED ||
            eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED
    }

    private fun collectVisibleText(
        node: AccessibilityNodeInfo?,
        output: MutableList<String>,
        depth: Int = 0
    ) {
        if (node == null) {
            return
        }

        if (depth > MAX_NODE_DEPTH || output.size >= MAX_TEXT_ITEMS) {
            return
        }

        val nodeText = node.text?.toString()?.trim()
        val nodeDescription = node.contentDescription?.toString()?.trim()

        if (!nodeText.isNullOrEmpty()) {
            output.add(nodeText)
        }

        if (!nodeDescription.isNullOrEmpty()) {
            output.add(nodeDescription)
        }

        for (index in 0 until node.childCount) {
            if (output.size >= MAX_TEXT_ITEMS) {
                break
            }

            collectVisibleText(
                node = node.getChild(index),
                output = output,
                depth = depth + 1
            )
        }
    }

    private fun handleWebsiteCategoryDetection(
        browserPackageName: String,
        detectionResult: WebsiteCategoryDetectionResult
    ) {
        val currentTime = System.currentTimeMillis()

        val isSameRecentDetection =
            detectionResult.domain == lastDetectedDomain &&
                detectionResult.category == lastDetectedCategory &&
                currentTime - lastDetectedTime < DETECTION_DEBOUNCE_MS

        if (isSameRecentDetection) {
            return
        }

        lastDetectedDomain = detectionResult.domain
        lastDetectedCategory = detectionResult.category
        lastDetectedTime = currentTime

        saveLatestWebsiteDetection(
            browserPackageName = browserPackageName,
            detectionResult = detectionResult,
            detectedAt = currentTime
        )

        Log.d(
            LOG_TAG,
            "Detected website category: domain=${detectionResult.domain}, " +
                "category=${detectionResult.category}, " +
                "harmful=${detectionResult.isHarmful}, " +
                "browser=$browserPackageName"
        )

        blockHarmfulWebsiteIfNeeded(
            detectionResult = detectionResult,
            detectedAt = currentTime
        )
    }

    private fun blockHarmfulWebsiteIfNeeded(
        detectionResult: WebsiteCategoryDetectionResult,
        detectedAt: Long
    ) {
        if (!detectionResult.isHarmful) {
            return
        }

        val isSameRecentBlock =
            detectionResult.domain == lastBlockedDomain &&
                detectedAt - lastBlockedWebsiteTime < WEBSITE_BLOCK_DEBOUNCE_MS

        if (isSameRecentBlock) {
            return
        }

        lastBlockedDomain = detectionResult.domain
        lastBlockedWebsiteTime = detectedAt

        val blockIntent = Intent(this, BlockedWebsiteActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(BlockedWebsiteActivity.EXTRA_DOMAIN, detectionResult.domain)
            putExtra(BlockedWebsiteActivity.EXTRA_CATEGORY, detectionResult.category)
        }

        try {
            startActivity(blockIntent)

            Log.d(
                LOG_TAG,
                "Blocked harmful website: domain=${detectionResult.domain}, " +
                    "category=${detectionResult.category}"
            )
        } catch (exception: Exception) {
            Log.e(
                LOG_TAG,
                "Failed to open blocked website screen.",
                exception
            )
        }
    }

    private fun saveLatestWebsiteDetection(
        browserPackageName: String,
        detectionResult: WebsiteCategoryDetectionResult,
        detectedAt: Long
    ) {
        val preferences = getSharedPreferences(
            WEBSITE_DETECTION_PREFERENCES,
            MODE_PRIVATE
        )

        preferences.edit()
            .putString("lastBrowserPackage", browserPackageName)
            .putString("lastDomain", detectionResult.domain)
            .putString("lastCategory", detectionResult.category)
            .putBoolean("lastIsHarmful", detectionResult.isHarmful)
            .putString("lastMatchedValue", detectionResult.matchedValue)
            .putLong("lastDetectedAt", detectedAt)
            .apply()
    }

    companion object {
        private const val LOG_TAG = "WellScreenWebsiteDetection"

        private const val WEBSITE_DETECTION_PREFERENCES =
            "wellscreen_website_detection"
        private const val RESTRICTED_APP_ATTEMPT_PREFERENCES =
            "wellscreen_restricted_app_attempts"

        private const val DETECTION_DEBOUNCE_MS = 3000L
        private const val WEBSITE_BLOCK_DEBOUNCE_MS = 5000L
        private const val APP_BLOCK_DEBOUNCE_MS = 3000L
        private const val MAX_NODE_DEPTH = 8
        private const val MAX_TEXT_ITEMS = 120

        private val supportedBrowserPackages = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.google.android.googlequicksearchbox",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "com.microsoft.emmx",
            "com.brave.browser",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.sec.android.app.sbrowser",
            "com.duckduckgo.mobile.android"
        )

        private val restrictedAppPackages = setOf(
            "com.google.android.youtube",
            "com.zhiliaoapp.musically",
            "com.instagram.android",
            "com.facebook.katana",
            "com.facebook.orca",
            "com.roblox.client",
            "com.netflix.mediaclient",
            "com.mobile.legends",
            "com.tencent.ig",
            "com.garena.game.codm"
        )
    }
}
