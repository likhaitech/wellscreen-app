package com.wellscreen.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
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

    private val appInfoChannelName =
        "com.wellscreen.app/app_info"

    // Backs the per-app rules picker (rules_screen.dart / AndroidAppService):
    // lists launchable apps so a parent can choose which ones to monitor or
    // restrict individually, distinct from the appInfoChannelName above
    // (which only resolves one package's label on demand).
    private val installedAppsChannelName =
        "wellscreen/apps"

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
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    )

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
                            exception.message
                                ?: "Unable to save restriction rules.",
                            null
                        )
                    }
                }

                "saveEmergencyAccessState" -> {
                    try {
                        saveEmergencyAccessState(call.arguments)
                        result.success(true)
                    } catch (exception: Exception) {
                        result.error(
                            "EMERGENCY_ACCESS_SAVE_ERROR",
                            exception.message
                                ?: "Unable to save emergency access state.",
                            null
                        )
                    }
                }

                "saveSmsBackupAlertSettings" -> {
                    try {
                        saveSmsBackupAlertSettings(
                            call.arguments
                        )

                        result.success(true)
                    } catch (exception: Exception) {
                        result.error(
                            "SMS_BACKUP_SAVE_ERROR",
                            exception.message
                                ?: "Unable to save SMS backup alert settings.",
                            null
                        )
                    }
                }

                "isSmsPermissionGranted" -> {
                    result.success(
                        isSmsPermissionGranted()
                    )
                }

                "requestSmsPermission" -> {
                    requestSmsPermission()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appInfoChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplicationLabel" -> {
                    val targetPackageName =
                        call.argument<String>(
                            "packageName"
                        )

                    if (targetPackageName.isNullOrBlank()) {
                        result.error(
                            "INVALID_PACKAGE",
                            "Package name is missing.",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    try {
                        @Suppress("DEPRECATION")
                        val applicationInfo =
                            packageManager.getApplicationInfo(
                                targetPackageName,
                                0
                            )

                        val label =
                            packageManager
                                .getApplicationLabel(
                                    applicationInfo
                                )
                                .toString()
                                .trim()

                        result.success(
                            label.ifEmpty {
                                targetPackageName
                            }
                        )
                    } catch (
                        exception:
                        PackageManager.NameNotFoundException
                    ) {
                        result.success(null)
                    } catch (exception: Exception) {
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installedAppsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }

                "openAccessibilitySettings" -> {
                    val intent = Intent(
                        Settings.ACTION_ACCESSIBILITY_SETTINGS
                    )
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }

                "openUsageAccessSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_USAGE_ACCESS_SETTINGS
                    )
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Lists apps with a home-screen launcher icon, for the per-app rules
     * picker (rules_screen.dart). Uses queryIntentActivities against
     * ACTION_MAIN/CATEGORY_LAUNCHER rather than PackageManager.getInstalledApplications(),
     * which also returns system components/services with no icon a parent
     * could ever open - those would just be confusing noise in the picker.
     *
     * Requires the <queries> MAIN/LAUNCHER intent declaration in
     * AndroidManifest.xml (Android 11+ package-visibility rules hide
     * other apps' launcher activities from queryIntentActivities otherwise -
     * without it this silently returns only WellScreen itself).
     */
    private fun getInstalledApps(): List<Map<String, String>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        @Suppress("DEPRECATION")
        val resolvedActivities =
            packageManager.queryIntentActivities(launcherIntent, 0)

        val seenPackageNames = mutableSetOf<String>()
        val apps = mutableListOf<Map<String, String>>()

        for (resolveInfo in resolvedActivities) {
            val resolvedPackageName = resolveInfo.activityInfo.packageName

            // Skip WellScreen itself - it isn't something a parent would
            // ever monitor or restrict, and would just clutter its own
            // rules picker.
            if (resolvedPackageName == packageName) {
                continue
            }

            if (!seenPackageNames.add(resolvedPackageName)) {
                continue
            }

            val label = try {
                resolveInfo.loadLabel(packageManager)
                    .toString()
                    .trim()
            } catch (exception: Exception) {
                resolvedPackageName
            }

            apps.add(
                mapOf(
                    "appName" to label.ifEmpty { resolvedPackageName },
                    "packageName" to resolvedPackageName
                )
            )
        }

        return apps
    }

    private fun saveRestrictionRules(
        arguments: Any?
    ) {
        val rules = arguments as? Map<*, *>
            ?: throw IllegalArgumentException(
                "Restriction rule data is missing."
            )

        val preferences =
            getSharedPreferences(
                restrictionRulesPreferencesName,
                MODE_PRIVATE
            )

        preferences.edit()
            .putInt(
                "limitMinutes",
                readInt(
                    rules["limitMinutes"],
                    120
                )
            )
            .putBoolean(
                "appBlockingEnabled",
                readBoolean(
                    rules["appBlocking"],
                    true
                )
            )
            .putBoolean(
                "focusModeEnabled",
                readBoolean(
                    rules["focusMode"],
                    false
                )
            )
            .putBoolean(
                "cooldownTimerEnabled",
                readBoolean(
                    rules["cooldownTimer"],
                    true
                )
            )
            .putBoolean(
                "scheduledLockEnabled",
                readBoolean(
                    rules["scheduledLock"],
                    false
                )
            )
            .putBoolean(
                "categoryRestrictionEnabled",
                readBoolean(
                    rules["categoryRestriction"],
                    true
                )
            )
            .putBoolean(
                "emergencyAccessEnabled",
                readBoolean(
                    rules["emergencyAccess"],
                    true
                )
            )
            .putBoolean(
                "smsBackupAlertsEnabled",
                readBoolean(
                    rules["smsBackupAlerts"],
                    false
                )
            )
            .putString(
                "guardianPhoneNumber",
                readString(
                    rules["guardianPhoneNumber"],
                    ""
                )
            )
            .putLong(
                "updatedAtMillis",
                System.currentTimeMillis()
            )
            .apply()
    }

    private fun saveEmergencyAccessState(
        arguments: Any?
    ) {
        val accessData = arguments as? Map<*, *>
            ?: throw IllegalArgumentException(
                "Emergency access data is missing."
            )

        val preferences =
            getSharedPreferences(
                restrictionRulesPreferencesName,
                MODE_PRIVATE
            )

        preferences.edit()
            .putBoolean(
                "emergencyAccessApproved",
                readBoolean(
                    accessData[
                        "emergencyAccessApproved"
                    ],
                    false
                )
            )
            .putLong(
                "emergencyAccessApprovedUntilMillis",
                readLong(
                    accessData[
                        "emergencyAccessApprovedUntilMillis"
                    ],
                    0L
                )
            )
            .putLong(
                "emergencyAccessUpdatedAtMillis",
                System.currentTimeMillis()
            )
            .apply()
    }

    private fun saveSmsBackupAlertSettings(
        arguments: Any?
    ) {
        val smsData = arguments as? Map<*, *>
            ?: throw IllegalArgumentException(
                "SMS backup alert data is missing."
            )

        val preferences =
            getSharedPreferences(
                restrictionRulesPreferencesName,
                MODE_PRIVATE
            )

        preferences.edit()
            .putBoolean(
                "smsBackupAlertsEnabled",
                readBoolean(
                    smsData["smsBackupAlertsEnabled"],
                    false
                )
            )
            .putString(
                "guardianPhoneNumber",
                readString(
                    smsData["guardianPhoneNumber"],
                    ""
                )
            )
            .putLong(
                "smsBackupSettingsUpdatedAtMillis",
                System.currentTimeMillis()
            )
            .apply()
    }

    private fun requestSmsPermission() {
        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M &&
            !isSmsPermissionGranted()
        ) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.SEND_SMS
                ),
                SMS_PERMISSION_REQUEST_CODE
            )
        }
    }

    private fun isSmsPermissionGranted(): Boolean {
        return if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M
        ) {
            checkSelfPermission(
                Manifest.permission.SEND_SMS
            ) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun readBoolean(
        value: Any?,
        defaultValue: Boolean
    ): Boolean {
        return when (value) {
            is Boolean -> value

            is String -> value.equals(
                "true",
                ignoreCase = true
            )

            else -> defaultValue
        }
    }

    private fun readInt(
        value: Any?,
        defaultValue: Int
    ): Int {
        return when (value) {
            is Int -> value

            is Number -> value.toInt()

            is String ->
                value.toIntOrNull()
                    ?: defaultValue

            else -> defaultValue
        }
    }

    private fun readLong(
        value: Any?,
        defaultValue: Long
    ): Long {
        return when (value) {
            is Long -> value

            is Int -> value.toLong()

            is Number -> value.toLong()

            is String ->
                value.toLongOrNull()
                    ?: defaultValue

            else -> defaultValue
        }
    }

    private fun readString(
        value: Any?,
        defaultValue: String
    ): String {
        return when (value) {
            is String -> value
            else -> defaultValue
        }
    }

    private fun isAccessibilityServiceEnabled():
        Boolean {
        val expectedComponentName =
            "$packageName/" +
                WellScreenAccessibilityService::
                class.java.name

        val enabledServicesSetting =
            Settings.Secure.getString(
                contentResolver,
                Settings.Secure
                    .ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false

        val colonSplitter =
            TextUtils.SimpleStringSplitter(':')

        colonSplitter.setString(
            enabledServicesSetting
        )

        while (colonSplitter.hasNext()) {
            if (
                colonSplitter.next().equals(
                    expectedComponentName,
                    ignoreCase = true
                )
            ) {
                return true
            }
        }

        return false
    }

    companion object {
        private const val
        SMS_PERMISSION_REQUEST_CODE = 9004
    }
}