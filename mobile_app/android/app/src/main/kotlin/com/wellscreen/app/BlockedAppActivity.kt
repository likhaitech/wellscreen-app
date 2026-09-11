package com.wellscreen.app

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class BlockedAppActivity : Activity() {

    companion object {
        // True while this screen is the foreground activity. Consumed by
        // WellScreenAccessibilityService.checkRestrictedApp() so a
        // restricted app that reappears in the foreground AFTER this
        // screen is dismissed gets re-blocked immediately, instead of
        // waiting out a fixed 2.5s debounce window that a quick "Go Back"
        // tap or Recents switch beats every time - without this, dismissing
        // the block screen and immediately switching back to the still-
        // running restricted app left it fully accessible and unblocked.
        @Volatile
        var isShowing: Boolean = false
            private set
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val blockedPackage = intent.getStringExtra("blocked_package") ?: "Restricted app"

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }

        val title = TextView(this).apply {
            text = "App Restricted"
            textSize = 30f
            gravity = Gravity.CENTER
        }

        val message = TextView(this).apply {
            text = "This app is currently restricted by WellScreen.\n\nPackage:\n$blockedPackage\n\nPlease take a break or ask your parent/guardian."
            textSize = 17f
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 32)
        }

        val button = Button(this).apply {
            text = "Go Back"
            setOnClickListener {
                finish()
            }
        }

        root.addView(title)
        root.addView(message)
        root.addView(button)

        setContentView(root)
    }

    override fun onBackPressed() {
        finish()
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