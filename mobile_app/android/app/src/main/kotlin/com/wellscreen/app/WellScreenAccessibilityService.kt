package com.wellscreen.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class WellScreenAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Intentionally empty for now — enforcement logic comes in a later task.
    }

    override fun onInterrupt() {
        // No-op for now.
    }
}