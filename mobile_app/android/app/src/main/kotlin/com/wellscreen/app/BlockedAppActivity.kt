package com.wellscreen.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Block screen for manually restricted apps, blocked websites and daily limits.
 *
 * Only a DAILY LIMIT screen automatically dismisses when a refreshed local
 * allowance exceeds today's actual app usage. Other restriction paths retain
 * their existing behavior.
 */
class BlockedAppActivity : Activity() {

    companion object {
        @Volatile
        var isShowing: Boolean = false
            private set

        private const val TAG = "WellScreenLimits"
        private const val PREFS = "FlutterSharedPreferences"
        private const val LIMITS_CACHE_KEY = "flutter.app_time_limits_json"
        private const val PROFILE_KEY = "flutter.active_child_profile_id"
        private const val RESTRICTED_KEY = "flutter.restricted_packages_json"
        private const val RECHECK_INTERVAL_MS = 5_000L
    }

    private var isDailyTimeLimitBlock = false
    private var dailyBlockedPackage: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val statusExecutor = Executors.newSingleThreadExecutor()
    private val statusCheckInProgress = AtomicBoolean(false)
    private var listeningToPrefs = false

    private val cacheChangeListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == LIMITS_CACHE_KEY || key == PROFILE_KEY || key == RESTRICTED_KEY) {
                checkForGrantedTime()
            }
        }

    // Also retry on a timer. Changes written by another process or a background
    // Flutter engine are not guaranteed to notify every SharedPreferences listener.
    private val recheckRunnable = object : Runnable {
        override fun run() {
            if (!isShowing || !isDailyTimeLimitBlock) return
            checkForGrantedTime()
            mainHandler.postDelayed(this, RECHECK_INTERVAL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val blockedDomain = intent.getStringExtra("blocked_domain")
        val blockedPackage = intent.getStringExtra("blocked_package") ?: "Restricted app"
        isDailyTimeLimitBlock = blockedDomain == null &&
            intent.getBooleanExtra("time_limit_reached", false)
        if (isDailyTimeLimitBlock) dailyBlockedPackage = blockedPackage

        val appLabel = if (isDailyTimeLimitBlock) {
            try {
                val info = packageManager.getApplicationInfo(blockedPackage, 0)
                packageManager.getApplicationLabel(info).toString()
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
                    blockedDomain != null -> returnToHome()
                    isDailyTimeLimitBlock -> returnToHome()
                    else -> finish()
                }
            }
        }

        root.addView(title)
        root.addView(message)
        root.addView(button)
        setContentView(root)
    }

    override fun onStart() {
        super.onStart()
        isShowing = true
        if (isDailyTimeLimitBlock) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .registerOnSharedPreferenceChangeListener(cacheChangeListener)
            listeningToPrefs = true
            mainHandler.removeCallbacks(recheckRunnable)
            mainHandler.post(recheckRunnable)
        }
    }

    override fun onStop() {
        isShowing = false
        mainHandler.removeCallbacks(recheckRunnable)
        if (listeningToPrefs) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .unregisterOnSharedPreferenceChangeListener(cacheChangeListener)
            listeningToPrefs = false
        }
        super.onStop()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(recheckRunnable)
        statusExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun checkForGrantedTime() {
        val target = dailyBlockedPackage ?: return
        if (!isDailyTimeLimitBlock || !isShowing || isFinishing || isDestroyed) return
        if (!statusCheckInProgress.compareAndSet(false, true)) return

        // UsageStatsManager queries may scan today's events. Never run these
        // queries repeatedly on the main/UI thread.
        try {
            statusExecutor.execute {
                val allowanceIsAvailable = try {
                    !isManuallyRestricted(target) &&
                        (AppTimeLimitEnforcer.getStatus(applicationContext, target)
                            ?.remainingMilliseconds ?: 0L) > 0L
                } catch (error: Exception) {
                    Log.w(TAG, "Failed to recheck added allowance", error)
                    false
                }

                mainHandler.post {
                    statusCheckInProgress.set(false)
                    if (allowanceIsAvailable && isShowing && !isFinishing && !isDestroyed &&
                        dailyBlockedPackage == target
                    ) {
                        // The original target app may still be underneath this
                        // Activity. Finishing reveals it, now with a valid limit.
                        Log.d(TAG, "New allowance available; closing daily limit screen")
                        finish()
                    }
                }
            }
        } catch (error: RuntimeException) {
            statusCheckInProgress.set(false)
            Log.w(TAG, "Could not schedule allowance check", error)
        }
    }

    private fun isManuallyRestricted(targetPackage: String): Boolean {
        return try {
            val raw = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(RESTRICTED_KEY, "[]") ?: "[]"
            val array = JSONArray(raw)
            (0 until array.length()).any { array.optString(it) == targetPackage }
        } catch (_: Exception) {
            // An unreadable restriction cache is not proof that an app is safe.
            true
        }
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
            super.onBackPressed()
        }
    }
}
