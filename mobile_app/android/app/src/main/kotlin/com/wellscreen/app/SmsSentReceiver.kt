package com.wellscreen.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.SmsManager

/**
 * Handles the "sent" half of the SmsManager.sendTextMessage callback pair
 * for backup SMS alerts. resultCode here is set by the Android telephony
 * stack itself (RESULT_OK, or one of SmsManager.RESULT_ERROR_*) - this is
 * the standard framework-documented way to observe whether an SMS actually
 * left the device, not a guess.
 */
class SmsSentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.getStringExtra(SmsAlertSender.EXTRA_PACKAGE_NAME) ?: return
        val triggeredAtMs = intent.getLongExtra(SmsAlertSender.EXTRA_TRIGGERED_AT_MS, -1L)
            .takeIf { it > 0 }

        val outcome = when (resultCode) {
            Activity.RESULT_OK -> "sent"
            SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "failed_generic"
            SmsManager.RESULT_ERROR_NO_SERVICE -> "failed_no_service"
            SmsManager.RESULT_ERROR_NULL_PDU -> "failed_null_pdu"
            SmsManager.RESULT_ERROR_RADIO_OFF -> "failed_radio_off"
            else -> "failed_unknown"
        }

        SmsAlertSender.recordOutcome(context, packageName, outcome, triggeredAtMs)
    }
}
