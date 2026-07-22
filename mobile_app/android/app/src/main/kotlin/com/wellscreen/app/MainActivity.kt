package com.wellscreen.app

import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val accessibilityChannelName =
        "com.wellscreen.app/accessibility_service"
    private val restrictionRulesChannelName =
        "com.wellscreen.app/restriction_rules"
    private val restrictionRulesPreferencesName =
        "wellscreen_restriction_rules"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            accessibilityChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityServiceEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            restrictionRulesChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveRestrictionRules" -> {
                    try {
                        saveRestrictionRules(call.arguments)
                        result.success(true)
                    } catch (exception: Exception) {
                        result.error(
                            "RULE_SAVE_ERROR",
                            exception.message ?: "Unable to save restriction rules.",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveRestrictionRules(arguments: Any?) {
        val rules = arguments as? Map<*, *>
            ?: throw IllegalArgumentException("Restriction rule data is missing.")

        val preferences = getSharedPreferences(
            restrictionRulesPreferencesName,
            MODE_PRIVATE
        )

        preferences.edit()
            .putInt(
                "limitMinutes",
                readInt(rules["limitMinutes"], 120)
            )
            .putBoolean(
                "appBlockingEnabled",
                readBoolean(rules["appBlocking"], true)
            )
            .putBoolean(
                "focusModeEnabled",
                readBoolean(rules["focusMode"], false)
            )
            .putBoolean(
                "cooldownTimerEnabled",
                readBoolean(rules["cooldownTimer"], true)
            )
            .putBoolean(
                "scheduledLockEnabled",
                readBoolean(rules["scheduledLock"], false)
            )
            .putBoolean(
                "categoryRestrictionEnabled",
                readBoolean(rules["categoryRestriction"], true)
            )
            .putBoolean(
                "emergencyAccessEnabled",
                readBoolean(rules["emergencyAccess"], true)
            )
            .putLong("updatedAtMillis", System.currentTimeMillis())
            .apply()
    }

    private fun readBoolean(value: Any?, defaultValue: Boolean): Boolean {
        return when (value) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            else -> defaultValue
        }
    }

    private fun readInt(value: Any?, defaultValue: Int): Int {
        return when (value) {
            is Int -> value
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponentName =
            "$packageName/${WellScreenAccessibilityService::class.java.name}"

        val enabledServicesSetting = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)

        while (colonSplitter.hasNext()) {
            if (colonSplitter.next().equals(expectedComponentName, ignoreCase = true)) {
                return true
            }
        }

        return false
    }
}
