package com.wellscreen.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the "delivered" half of the SmsManager.sendTextMessage callback
 * pair - fires when the carrier confirms the SMS reached the recipient's
 * device (not just left ours). Some carriers never send this report, so a
 * missing "delivered" entry doesn't necessarily mean failure - only "sent"
 * followed by no delivered/undelivered report within a reasonable window
 * means unknown, not failed.
 */
class SmsDeliveredReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.getStringExtra(SmsAlertSender.EXTRA_PACKAGE_NAME) ?: return
        val outcome = if (resultCode == Activity.RESULT_OK) "delivered" else "undelivered"
        SmsAlertSender.recordOutcome(context, packageName, outcome)
    }
}
