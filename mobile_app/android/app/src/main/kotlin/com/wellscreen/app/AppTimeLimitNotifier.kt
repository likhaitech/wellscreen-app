package com.wellscreen.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.util.Calendar

/** Quiet, drawer-only Android notifications for the child device. */
internal object AppTimeLimitNotifier {
    const val CHANNEL_ID = "wellscreen_limit_updates"
    private const val CHANNEL_NAME = "App time limits"
    private const val PREFS = "FlutterSharedPreferences"
    private const val TAG = "WellScreenLimitNotice"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Quiet notices about your daily app allowances"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun canNotify(context: Context): Boolean {
        return Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
    }

    fun showAssignedLimit(context: Context, appPackage: String, title: String, body: String): Boolean =
        post(context, "assigned:$appPackage", title, body)

    fun maybeNotifyFiveMinutes(
        context: Context,
        targetPackage: String,
        status: AppTimeLimitEnforcer.Status,
    ) {
        // An app whose entire allowance is <= 5 minutes never passes through
        // the five-minute boundary; don't misrepresent its remaining time.
        if (status.limitMinutes <= 5 || status.remainingMilliseconds <= 0L ||
            status.remainingMilliseconds > 300_000L
        ) return

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val childId = prefs.getString("flutter.active_child_profile_id", null)
        if (childId.isNullOrBlank()) return

        val now = Calendar.getInstance()
        val today = "${now.get(Calendar.YEAR)}-${now.get(Calendar.DAY_OF_YEAR)}"
        val key = "flutter.limit_warning_${childId.hashCode()}_${targetPackage.hashCode()}_${status.limitMinutes}"
        if (prefs.getString(key, null) == today) return

        val appName = status.appName.ifBlank { targetPackage }
        val title = if (status.remainingMilliseconds > 240_000L) {
            "Only 5 minutes remaining!"
        } else {
            "Less than 5 minutes remaining"
        }
        val body = "Your daily $appName allowance is nearly used up."
        if (post(context, "five:$childId:$targetPackage", title, body)) {
            // Persist de-duplication across process restarts and 5-second polls.
            prefs.edit().putString(key, today).apply()
        }
    }

    private fun post(context: Context, key: String, title: String, body: String): Boolean {
        if (!canNotify(context)) return false
        return try {
            ensureChannel(context)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager ?: return false
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .build()
            manager.notify(key.hashCode(), notification)
            true
        } catch (error: Exception) {
            Log.w(TAG, "Failed to post time-limit notification", error)
            false
        }
    }
}
