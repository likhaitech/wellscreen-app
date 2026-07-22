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

        handleAppEnforcementIfNeeded(packageName)

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
        // No active interruption handling is needed for app, website, and focus-mode blocking.
    }

    private fun handleAppEnforcementIfNeeded(packageName: String) {
        val blockReason = getAppBlockReason(packageName) ?: return
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
        val attemptCount = recordBlockedAppOpenAttempt(
            packageName = packageName,
            appName = appName,
            reason = blockReason,
            attemptedAt = currentTime
        )

        val blockIntent = Intent(this, BlockedAppActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(BlockedAppActivity.EXTRA_APP_NAME, appName)
            putExtra(BlockedAppActivity.EXTRA_PACKAGE_NAME, packageName)
            putExtra(BlockedAppActivity.EXTRA_ATTEMPT_COUNT, attemptCount)
            putExtra(
                BlockedAppActivity.EXTRA_BLOCK_REASON_LABEL,
                getBlockReasonLabel(blockReason)
            )
        }

        try {
            startActivity(blockIntent)

            Log.d(
                LOG_TAG,
                "Blocked app: app=$appName, package=$packageName, " +
                    "reason=${getBlockReasonLabel(blockReason)}, " +
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

    private fun getAppBlockReason(packageName: String): String? {
        if (isEssentialOrAllowedApp(packageName)) {
            return null
        }

        if (isSupportedBrowser(packageName)) {
            return null
        }

        val rules = getRestrictionRules()

        if (rules.focusModeEnabled && distractingAppPackages.contains(packageName)) {
            return BLOCK_REASON_FOCUS_MODE
        }

        if (rules.appBlockingEnabled && restrictedAppPackages.contains(packageName)) {
            return BLOCK_REASON_APP_BLOCKING
        }

        return null
    }

    private fun isEssentialOrAllowedApp(packageName: String): Boolean {
        if (packageName == applicationContext.packageName) {
            return true
        }

        if (essentialAllowedPackages.contains(packageName)) {
            return true
        }

        return packageName.contains("launcher", ignoreCase = true)
    }

    private fun recordBlockedAppOpenAttempt(
        packageName: String,
        appName: String,
        reason: String,
        attemptedAt: Long
    ): Int {
        val preferences = getSharedPreferences(
            BLOCKED_APP_ATTEMPT_PREFERENCES,
            MODE_PRIVATE
        )

        val attemptKey = "attemptCount_$packageName"
        val attemptCount = preferences.getInt(attemptKey, 0) + 1

        preferences.edit()
            .putInt(attemptKey, attemptCount)
            .putString("lastBlockedAppName", appName)
            .putString("lastBlockedPackageName", packageName)
            .putString("lastBlockedReason", reason)
            .putString("lastBlockedReasonLabel", getBlockReasonLabel(reason))
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

        if (!getRestrictionRules().categoryRestrictionEnabled) {
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

    private fun getRestrictionRules(): RestrictionRules {
        val preferences = getSharedPreferences(
            RESTRICTION_RULE_PREFERENCES,
            MODE_PRIVATE
        )

        return RestrictionRules(
            appBlockingEnabled = preferences.getBoolean(
                "appBlockingEnabled",
                true
            ),
            focusModeEnabled = preferences.getBoolean(
                "focusModeEnabled",
                false
            ),
            categoryRestrictionEnabled = preferences.getBoolean(
                "categoryRestrictionEnabled",
                true
            ),
            emergencyAccessEnabled = preferences.getBoolean(
                "emergencyAccessEnabled",
                true
            )
        )
    }

    private fun getBlockReasonLabel(reason: String): String {
        return when (reason) {
            BLOCK_REASON_FOCUS_MODE -> "Focus Mode"
            BLOCK_REASON_APP_BLOCKING -> "App Blocking"
            else -> "Restriction"
        }
    }

    private data class RestrictionRules(
        val appBlockingEnabled: Boolean,
        val focusModeEnabled: Boolean,
        val categoryRestrictionEnabled: Boolean,
        val emergencyAccessEnabled: Boolean
    )

    companion object {
        private const val LOG_TAG = "WellScreenEnforcement"

        private const val WEBSITE_DETECTION_PREFERENCES =
            "wellscreen_website_detection"
        private const val BLOCKED_APP_ATTEMPT_PREFERENCES =
            "wellscreen_restricted_app_attempts"
        private const val RESTRICTION_RULE_PREFERENCES =
            "wellscreen_restriction_rules"

        private const val BLOCK_REASON_APP_BLOCKING = "app_blocking"
        private const val BLOCK_REASON_FOCUS_MODE = "focus_mode"

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

        private val essentialAllowedPackages = setOf(
            "android",
            "com.android.systemui",
            "com.android.settings",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
            "com.google.android.packageinstaller",
            "com.android.packageinstaller",
            "com.google.android.dialer",
            "com.android.dialer",
            "com.google.android.contacts",
            "com.android.contacts",
            "com.google.android.gms"
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

        private val distractingAppPackages = setOf(
            "com.google.android.youtube",
            "com.google.android.apps.youtube.kids",
            "com.zhiliaoapp.musically",
            "com.instagram.android",
            "com.facebook.katana",
            "com.facebook.orca",
            "com.twitter.android",
            "com.reddit.frontpage",
            "com.snapchat.android",
            "com.discord",
            "com.roblox.client",
            "com.netflix.mediaclient",
            "tv.twitch.android.app",
            "com.mobile.legends",
            "com.tencent.ig",
            "com.garena.game.codm"
        )
    }
}

