package com.wellscreen.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Shared block screen for manually restricted apps, blocked websites,
 * and guardian-configured daily app time limits.
 *
 * WellScreenAccessibilityService passes `time_limit_reached = true` only
 * when the daily allowance is exhausted. Existing restriction paths keep
 * their original titles, messages, and Go Back behavior.
 */
class BlockedAppActivity : Activity() {

    companion object {
        // Used by WellScreenAccessibilityService's debounce logic. Preserve
        // this lifecycle signal so reopening a restricted app re-blocks it.
        @Volatile
        var isShowing: Boolean = false
            private set
    }

    private var isDailyTimeLimitBlock = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val blockedDomain = intent.getStringExtra("blocked_domain")
        val blockedPackage = intent.getStringExtra("blocked_package") ?: "Restricted app"
        isDailyTimeLimitBlock = blockedDomain == null &&
            intent.getBooleanExtra("time_limit_reached", false)

        val appLabel = if (isDailyTimeLimitBlock) {
            try {
                val appInfo = packageManager.getApplicationInfo(blockedPackage, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                blockedPackage
            }
        } else {
            blockedPackage
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }

        val title = TextView(this).apply {
            text = when {
                blockedDomain != null -> "Website Blocked"
                isDailyTimeLimitBlock -> "Daily App Time Limit Reached"
                else -> "App Restricted"
            }
            textSize = 30f
            gravity = Gravity.CENTER
        }

        val message = TextView(this).apply {
            text = when {
                blockedDomain != null ->
                    "This website is blocked by WellScreen.\n\n$blockedDomain\n\nPlease ask your parent/guardian."
                isDailyTimeLimitBlock ->
                    "You've reached today's usage limit for $appLabel.\n\n" +
                        "This app will be available again after the next daily reset, " +
                        "or when your parent/guardian increases its limit."
                else ->
                    "This app is currently restricted by WellScreen.\n\n" +
                        "Package:\n$blockedPackage\n\nPlease take a break or ask your parent/guardian."
            }
            textSize = 17f
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 32)
        }

        val button = Button(this).apply {
            text = if (isDailyTimeLimitBlock) "Go Home" else "Go Back"
            setOnClickListener {
                when {
                    // Existing blocked-website behavior: leave the browser
                    // instead of revealing the blocked page underneath.
                    blockedDomain != null -> returnToHome()
                    // A time-limited app may still be open underneath this
                    // activity; leaving to Home avoids immediately exposing it.
                    isDailyTimeLimitBlock -> returnToHome()
                    // Preserve the existing manual restriction behavior.
                    else -> finish()
                }
            }
        }

        root.addView(title)
        root.addView(message)
        root.addView(button)
        setContentView(root)
    }

    private fun returnToHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(homeIntent)
        finish()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (isDailyTimeLimitBlock) {
            returnToHome()
        } else {
            // Preserve the old back behavior for manual restrictions/websites.
            super.onBackPressed()
        }
    }

    override fun onStart() {
        super.onStart()
        isShowing = true
    }

    override fun onStop() {
        super.onStop()
        isShowing = false
    }
}
