package com.wellscreen.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

class BlockedAppActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContentView(R.layout.activity_blocked_app)

        val appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "Restricted app"
        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME) ?: "unknown"
        val attemptCount = intent.getIntExtra(EXTRA_ATTEMPT_COUNT, 1)

        findViewById<TextView>(R.id.blockedAppNameText).text = appName
        findViewById<TextView>(R.id.blockedAppPackageText).text = packageName
        findViewById<TextView>(R.id.blockedAppAttemptText).text =
            "Open Attempts: $attemptCount"

        findViewById<Button>(R.id.blockedAppLeaveButton).setOnClickListener {
            leaveRestrictedApp()
        }
    }

    override fun onBackPressed() {
        leaveRestrictedApp()
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
    }
}
