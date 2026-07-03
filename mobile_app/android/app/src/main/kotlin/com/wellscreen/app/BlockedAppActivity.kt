package com.wellscreen.app

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class BlockedAppActivity : Activity() {
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
}