package com.wellscreen.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.CountDownTimer
import android.widget.Button
import android.widget.TextView

class BlockedAppActivity : Activity() {

    private var cooldownTimer: CountDownTimer? = null
    private lateinit var cooldownText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContentView(R.layout.activity_blocked_app)

        val appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "Restricted app"
        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME) ?: "unknown"
        val attemptCount = intent.getIntExtra(EXTRA_ATTEMPT_COUNT, 1)
        val blockReasonLabel =
            intent.getStringExtra(EXTRA_BLOCK_REASON_LABEL) ?: "App Blocking"
        val cooldownEnabled = intent.getBooleanExtra(EXTRA_COOLDOWN_ENABLED, false)
        val cooldownEndAtMillis = intent.getLongExtra(
            EXTRA_COOLDOWN_END_AT_MILLIS,
            0L
        )

        cooldownText = findViewById(R.id.blockedAppCooldownText)

        findViewById<TextView>(R.id.blockedAppNameText).text = appName
        findViewById<TextView>(R.id.blockedAppPackageText).text = packageName
        findViewById<TextView>(R.id.blockedAppReasonText).text =
            "Reason: $blockReasonLabel"
        findViewById<TextView>(R.id.blockedAppAttemptText).text =
            "Open Attempts: $attemptCount"

        updateCooldownText(
            cooldownEnabled = cooldownEnabled,
            cooldownEndAtMillis = cooldownEndAtMillis
        )

        findViewById<Button>(R.id.blockedAppLeaveButton).setOnClickListener {
            leaveRestrictedApp()
        }
    }

    override fun onDestroy() {
        cooldownTimer?.cancel()
        cooldownTimer = null
        super.onDestroy()
    }

    override fun onBackPressed() {
        leaveRestrictedApp()
    }

    private fun updateCooldownText(
        cooldownEnabled: Boolean,
        cooldownEndAtMillis: Long
    ) {
        if (!cooldownEnabled || cooldownEndAtMillis <= 0L) {
            cooldownText.text = "Cooldown: Not active"
            return
        }

        val remainingMillis = cooldownEndAtMillis - System.currentTimeMillis()

        if (remainingMillis <= 0L) {
            cooldownText.text = "Cooldown complete. You may return after guardian rules allow it."
            return
        }

        cooldownTimer?.cancel()
        cooldownTimer = object : CountDownTimer(remainingMillis, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                cooldownText.text =
                    "Cooldown remaining: ${formatRemainingTime(millisUntilFinished)}"
            }

            override fun onFinish() {
                cooldownText.text =
                    "Cooldown complete. You may return after guardian rules allow it."
            }
        }.start()
    }

    private fun formatRemainingTime(millis: Long): String {
        val totalSeconds = (millis / 1000L).coerceAtLeast(0L)
        val minutes = totalSeconds / 60L
        val seconds = totalSeconds % 60L

        return if (minutes > 0L) {
            "${minutes}m ${seconds}s"
        } else {
            "${seconds}s"
        }
    }

    private fun leaveRestrictedApp() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        startActivity(homeIntent)
        finish()
    }

    companion object {
        const val EXTRA_APP_NAME = "extra_app_name"
        const val EXTRA_PACKAGE_NAME = "extra_package_name"
        const val EXTRA_ATTEMPT_COUNT = "extra_attempt_count"
        const val EXTRA_BLOCK_REASON_LABEL = "extra_block_reason_label"
        const val EXTRA_COOLDOWN_ENABLED = "extra_cooldown_enabled"
        const val EXTRA_COOLDOWN_END_AT_MILLIS = "extra_cooldown_end_at_millis"
    }
}
