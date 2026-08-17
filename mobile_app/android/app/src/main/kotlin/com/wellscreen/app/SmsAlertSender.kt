package com.wellscreen.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Sends a backup SMS alert to the paired parent's phone number when the
 * accessibility service blocks a restricted app. This is a backup channel,
 * not a replacement for Firestore-based alerts - it works over the cellular
 * network alone, with no dependency on internet/auth, which is the whole
 * point of having it as a fallback.
 *
 * Rate-limited to once per package per [ALERT_COOLDOWN_MS] so repeatedly
 * opening the same blocked app doesn't spam the parent with SMS (and run up
 * carrier charges). Every send attempt's outcome (sent/failed,
 * delivered/undelivered) is recorded locally via [SmsSentReceiver] /
 * [SmsDeliveredReceiver] into `flutter.sms_alert_log_json`, which
 * child_home_screen.dart's syncUsageReport() pushes to Firestore so the
 * parent dashboard can show a real delivery success rate instead of a
 * fire-and-forget guess.
 *
 * NOT verified on a physical device - this sandbox has no Android runtime.
 * The SmsManager sent/delivered PendingIntent pattern here follows the
 * documented Android API contract, but needs a real on-device pass (with
 * and without a SIM/signal) before this can honestly be called "Done."
 */
object SmsAlertSender {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val PHONE_NUMBER_KEY = "flutter.parent_phone_number"
    private const val COOLDOWN_KEY = "wellscreen_sms_last_sent_json"
    private const val LOG_KEY = "flutter.sms_alert_log_json"
    private const val MAX_LOG_ENTRIES = 50
    private const val ALERT_COOLDOWN_MS = 24L * 60 * 60 * 1000 // once per app per day

    const val ACTION_SMS_SENT = "com.wellscreen.app.SMS_SENT"
    const val ACTION_SMS_DELIVERED = "com.wellscreen.app.SMS_DELIVERED"
    const val EXTRA_PACKAGE_NAME = "package_name"
    const val EXTRA_TRIGGERED_AT_MS = "triggered_at_ms"

    fun maybeSendRestrictedAppAlert(
        context: Context,
        blockedPackage: String,
        appLabel: String,
        triggeredAtMs: Long,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val phoneNumber = prefs.getString(PHONE_NUMBER_KEY, null)

        if (phoneNumber.isNullOrBlank()) return
        if (!hasSmsPermission(context)) return
        if (isOnCooldown(prefs, blockedPackage)) return

        markSent(prefs, blockedPackage)

        val message = "WellScreen alert: \"$appLabel\" was opened and blocked on your child's device."

        try {
            val smsManager = getSmsManager(context) ?: run {
                recordOutcome(context, blockedPackage, "failed_no_manager", triggeredAtMs)
                return
            }

            val sentPI = PendingIntent.getBroadcast(
                context,
                blockedPackage.hashCode(),
                Intent(ACTION_SMS_SENT).apply {
                    setPackage(context.packageName)
                    putExtra(EXTRA_PACKAGE_NAME, blockedPackage)
                    putExtra(EXTRA_TRIGGERED_AT_MS, triggeredAtMs)
                },
                pendingIntentFlags(),
            )

            val deliveredPI = PendingIntent.getBroadcast(
                context,
                blockedPackage.hashCode() + 1,
                Intent(ACTION_SMS_DELIVERED).apply {
                    setPackage(context.packageName)
                    putExtra(EXTRA_PACKAGE_NAME, blockedPackage)
                    putExtra(EXTRA_TRIGGERED_AT_MS, triggeredAtMs)
                },
                pendingIntentFlags(),
            )

            smsManager.sendTextMessage(phoneNumber, null, message, sentPI, deliveredPI)
        } catch (_: Exception) {
            recordOutcome(context, blockedPackage, "failed_exception", triggeredAtMs)
        }
    }

    private fun getSmsManager(context: Context): SmsManager? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    private fun hasSmsPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.SEND_SMS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isOnCooldown(prefs: SharedPreferences, packageName: String): Boolean {
        return try {
            val json = JSONObject(prefs.getString(COOLDOWN_KEY, "{}") ?: "{}")
            val lastSent = json.optLong(packageName, 0L)
            System.currentTimeMillis() - lastSent < ALERT_COOLDOWN_MS
        } catch (_: Exception) {
            false
        }
    }

    private fun markSent(prefs: SharedPreferences, packageName: String) {
        try {
            val json = JSONObject(prefs.getString(COOLDOWN_KEY, "{}") ?: "{}")
            json.put(packageName, System.currentTimeMillis())
            prefs.edit().putString(COOLDOWN_KEY, json.toString()).apply()
        } catch (_: Exception) {
            // Not critical if the cooldown record fails to save.
        }
    }

    fun recordOutcome(
        context: Context,
        packageName: String,
        outcome: String,
        triggeredAtMs: Long? = null,
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString(LOG_KEY, "[]") ?: "[]")

            val now = System.currentTimeMillis()

            val entry = JSONObject()
            entry.put("packageName", packageName)
            entry.put("outcome", outcome)
            if (triggeredAtMs != null) {
                entry.put("responseTimeMs", now - triggeredAtMs)
            }
            entry.put("timestampMs", now)
            log.put(entry)

            val trimmed = JSONArray()
            val start = maxOf(0, log.length() - MAX_LOG_ENTRIES)
            for (i in start until log.length()) {
                trimmed.put(log.get(i))
            }

            prefs.edit().putString(LOG_KEY, trimmed.toString()).apply()
        } catch (_: Exception) {
            // Best-effort logging only - never let this crash the caller.
        }
    }
}
