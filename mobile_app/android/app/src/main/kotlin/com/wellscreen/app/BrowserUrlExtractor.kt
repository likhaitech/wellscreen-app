package com.wellscreen.app

import android.view.accessibility.AccessibilityNodeInfo

/**
 * Reads the current URL out of a browser's address bar via the
 * accessibility node tree, so [WellScreenAccessibilityService] can see what
 * site a child is on - it currently only sees which *app* is foreground.
 *
 * HOW THIS WORKS: every browser's address bar is just a normal Android
 * view with a resource-id (e.g. Chrome's is "com.android.chrome:id/url_bar").
 * canRetrieveWindowContent + flagReportViewIds are already enabled in
 * wellscreen_accessibility_service.xml (needed for restricted-app
 * detection), so `findAccessibilityNodeInfosByViewId` can look that view up
 * directly instead of walking the whole node tree.
 *
 * HONESTY NOTE ON FRAGILITY: these resource-ids are internal implementation
 * details of each browser, not a public API - they can change when a
 * browser updates and there is no guarantee they'll stay the same. This is
 * the same limitation every accessibility-based URL-capture tool has (this
 * mapping is cross-checked against two independent real-world
 * implementations that use the same technique - KeePass2Android's
 * accessibility-based autofill service, and a public writeup on browser
 * usage tracking - not guessed). If a browser update breaks its resource-id,
 * capture silently stops working for that browser specifically (falls
 * through to returning null) rather than crashing anything.
 *
 * Only browsers with a known resource-id are supported. Any other browser
 * app is left alone entirely - WellScreen already knows it's "a browser was
 * opened" from the app-usage tracking that exists today; this class is only
 * responsible for the extra step of "and here's the specific URL."
 */
object BrowserUrlExtractor {

    // package name -> address bar resource-id, in the order to try (some
    // browsers have shipped more than one over the years).
    private val ADDRESS_BAR_VIEW_IDS: Map<String, List<String>> = mapOf(
        "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
        "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
        "org.mozilla.firefox" to listOf(
            "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
        ),
        "com.sec.android.app.sbrowser" to listOf(
            "com.sec.android.app.sbrowser:id/location_bar_edit_text",
        ),
        "com.opera.browser" to listOf("com.opera.browser:id/url_field"),
        "com.opera.mini.native" to listOf("com.opera.mini.native:id/url_field"),
        "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
        "com.duckduckgo.mobile.android" to listOf(
            "com.duckduckgo.mobile.android:id/omnibarTextInput",
        ),
        "com.android.browser" to listOf("com.android.browser:id/url"),
    )

    fun isKnownBrowser(packageName: String): Boolean =
        ADDRESS_BAR_VIEW_IDS.containsKey(packageName)

    /**
     * Returns the normalized domain currently shown in [packageName]'s
     * address bar, or null if it can't be found (browser not supported,
     * resource-id didn't match this version, or the bar doesn't currently
     * hold URL-shaped text - e.g. the user is mid-search-query).
     */
    fun extractDomain(root: AccessibilityNodeInfo, packageName: String): String? {
        val viewIds = ADDRESS_BAR_VIEW_IDS[packageName] ?: return null

        for (viewId in viewIds) {
            val matches = try {
                root.findAccessibilityNodeInfosByViewId(viewId)
            } catch (_: Exception) {
                null
            }

            val rawText = matches?.firstOrNull()?.text?.toString()
            if (!rawText.isNullOrBlank()) {
                normalizeToDomain(rawText)?.let { return it }
            }
        }

        return null
    }

    /**
     * Best-effort conversion of whatever text is sitting in an address bar
     * into a bare registrable domain ("example.com", not
     * "https://www.example.com/path?query"). Returns null for text that
     * doesn't look like a URL at all (most commonly: the user is typing a
     * search query, not a URL - browsers show the raw query text in the
     * same field).
     */
    fun normalizeToDomain(rawText: String): String? {
        var text = rawText.trim().lowercase()
        if (text.isEmpty() || text.contains(" ")) return null

        // Strip scheme.
        val schemeIndex = text.indexOf("://")
        if (schemeIndex != -1) {
            text = text.substring(schemeIndex + 3)
        }

        // Strip userinfo (rare, but "user:pass@host" is valid URL syntax).
        val atIndex = text.indexOf("@")
        if (atIndex != -1) {
            text = text.substring(atIndex + 1)
        }

        // Strip path/query/fragment.
        val endIndex = text.indexOfAny(charArrayOf('/', '?', '#'))
        if (endIndex != -1) {
            text = text.substring(0, endIndex)
        }

        // Strip port.
        val colonIndex = text.indexOf(":")
        if (colonIndex != -1) {
            text = text.substring(0, colonIndex)
        }

        if (text.startsWith("www.")) {
            text = text.removePrefix("www.")
        }

        // A search query typed into the same field ("best pizza near me")
        // won't contain a dot; a real domain will. This is a heuristic, not
        // a strict validator - good enough to filter out the common case of
        // "user is still typing" without false-rejecting real domains.
        if (!text.contains(".")) return null

        return text
    }
}
