import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_settings_api_service.dart';
import '../theme/app_theme.dart';
import 'admin_logs_screen.dart';
import 'login_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;

  final AdminSettingsApiService _apiService = AdminSettingsApiService();
  final TextEditingController limitController = TextEditingController();

  bool appBlockingEnabled = true;
  bool focusModeEnabled = true;
  bool cooldownTimerEnabled = true;
  bool scheduledLockEnabled = false;
  bool categoryRestrictionEnabled = true;
  bool emergencyAccessEnabled = true;

  bool isLoading = true;
  bool isSaving = false;
  String? loadError;

  DateTime? updatedAt;
  String? updatedBy;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    limitController.dispose();
    super.dispose();
  }

  Future<bool> currentUserIsAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return false;
    }

    final tokenResult = await user.getIdTokenResult(true);
    final claims = tokenResult.claims ?? <String, dynamic>{};

    return claims['admin'] == true || claims['role'] == 'admin';
  }

  Future<void> loadSettings() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final isAdmin = await currentUserIsAdmin();

      if (!isAdmin) {
        showMessage('Administrator access required.');

        if (mounted) {
          await logout();
        }

        return;
      }

      final data = await _apiService.getSettings();

      if (!mounted) return;

      setState(() {
        limitController.text = (data['default_daily_limit_minutes'] ?? 180)
            .toString();

        appBlockingEnabled = data['app_blocking_enabled'] ?? true;

        focusModeEnabled = data['focus_mode_enabled'] ?? true;

        cooldownTimerEnabled = data['cooldown_timer_enabled'] ?? true;

        scheduledLockEnabled = data['scheduled_lock_enabled'] ?? false;

        categoryRestrictionEnabled =
            data['category_restriction_enabled'] ?? true;

        emergencyAccessEnabled = data['emergency_access_enabled'] ?? true;

        final updatedAtValue = data['updated_at'];

        if (updatedAtValue is String && updatedAtValue.isNotEmpty) {
          updatedAt = DateTime.tryParse(updatedAtValue)?.toLocal();
        } else {
          updatedAt = null;
        }

        updatedBy = data['updated_by']?.toString();

        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      // Previously this only fired a transient SnackBar and then still
      // rendered the toggle UI with its in-memory default values (true/
      // true/true/false/true/true, 180 min) - an admin who didn't catch
      // the snackbar could hit "Save" and silently overwrite the real
      // system settings with those defaults. Now blocks on a persistent,
      // retryable error state instead (see the AppErrorState branch in
      // build() below), matching the pattern used on rules_screen.dart.
      setState(() {
        isLoading = false;
        loadError = 'Failed to load system settings. $e';
      });
    }
  }

  Future<void> saveSettings() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final isAdmin = await currentUserIsAdmin();

    if (!isAdmin) {
      showMessage('Administrator access required.');
      return;
    }

    final limitMinutes = int.tryParse(limitController.text.trim());

    if (limitMinutes == null || limitMinutes < 1 || limitMinutes > 1440) {
      showMessage('Daily usage limit must be between 1 and 1440 minutes.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final data = await _apiService.updateSettings(
        defaultDailyLimitMinutes: limitMinutes,
        appBlockingEnabled: appBlockingEnabled,
        focusModeEnabled: focusModeEnabled,
        cooldownTimerEnabled: cooldownTimerEnabled,
        scheduledLockEnabled: scheduledLockEnabled,
        categoryRestrictionEnabled: categoryRestrictionEnabled,
        emergencyAccessEnabled: emergencyAccessEnabled,
      );

      if (!mounted) return;

      setState(() {
        limitController.text =
            (data['default_daily_limit_minutes'] ?? limitMinutes).toString();

        appBlockingEnabled = data['app_blocking_enabled'] ?? appBlockingEnabled;

        focusModeEnabled = data['focus_mode_enabled'] ?? focusModeEnabled;

        cooldownTimerEnabled =
            data['cooldown_timer_enabled'] ?? cooldownTimerEnabled;

        scheduledLockEnabled =
            data['scheduled_lock_enabled'] ?? scheduledLockEnabled;

        categoryRestrictionEnabled =
            data['category_restriction_enabled'] ?? categoryRestrictionEnabled;

        emergencyAccessEnabled =
            data['emergency_access_enabled'] ?? emergencyAccessEnabled;

        final updatedAtValue = data['updated_at'];

        if (updatedAtValue is String && updatedAtValue.isNotEmpty) {
          updatedAt = DateTime.tryParse(updatedAtValue)?.toLocal();
        }

        updatedBy = data['updated_by']?.toString();
      });

      showMessage('System settings updated successfully.');
    } catch (e) {
      showMessage('Failed to update system settings: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void openSystemLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminLogsScreen()),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String formatUpdatedAt() {
    if (updatedAt == null) {
      return 'Not updated yet';
    }

    final date = updatedAt!;

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$month/$day/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'Admin System Settings',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppErrorState(
                  title: 'Could Not Load Settings',
                  message: loadError!,
                  onRetry: loadSettings,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: purple,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'System Configuration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Manage global WellScreen defaults and system features.',
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                AppCard(
                  onTap: openSystemLogs,
                  child: const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primaryLight,
                        child: Icon(
                          Icons.receipt_long_rounded,
                          color: purple,
                        ),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'System Logs',
                              style: TextStyle(
                                color: darkText,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Monitor administrative and system activity.',
                              style: TextStyle(color: grayText),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: grayText),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: limitController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Default Daily Usage Limit (minutes)',
                    prefixIcon: const Icon(Icons.timer_rounded, color: purple),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _settingSwitch(
                  title: 'App Blocking',
                  subtitle: 'Enable or disable app blocking system-wide.',
                  value: appBlockingEnabled,
                  onChanged: (value) {
                    setState(() => appBlockingEnabled = value);
                  },
                ),

                _settingSwitch(
                  title: 'Focus Mode',
                  subtitle: 'Enable focus mode functionality.',
                  value: focusModeEnabled,
                  onChanged: (value) {
                    setState(() => focusModeEnabled = value);
                  },
                ),

                _settingSwitch(
                  title: 'Cooldown Timer',
                  subtitle: 'Enable cooldown periods after extended usage.',
                  value: cooldownTimerEnabled,
                  onChanged: (value) {
                    setState(() => cooldownTimerEnabled = value);
                  },
                ),

                _settingSwitch(
                  title: 'Scheduled Lock',
                  subtitle: 'Enable scheduled device lock sessions.',
                  value: scheduledLockEnabled,
                  onChanged: (value) {
                    setState(() => scheduledLockEnabled = value);
                  },
                ),

                _settingSwitch(
                  title: 'Category Restriction',
                  subtitle: 'Enable supported harmful-category restrictions.',
                  value: categoryRestrictionEnabled,
                  onChanged: (value) {
                    setState(() => categoryRestrictionEnabled = value);
                  },
                ),

                _settingSwitch(
                  title: 'Emergency Access',
                  subtitle:
                      'Allow emergency-access functionality during restrictions.',
                  value: emergencyAccessEnabled,
                  onChanged: (value) {
                    setState(() => emergencyAccessEnabled = value);
                  },
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: isSaving ? null : saveSettings,
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      isSaving ? 'Saving...' : 'Save System Settings',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Last updated: ${formatUpdatedAt()}',
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (updatedBy != null)
                  Text(
                    'Updated by: $updatedBy',
                    style: const TextStyle(
                      color: grayText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _settingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: SwitchListTile(
          activeThumbColor: purple,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          title: Text(
            title,
            style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: grayText, height: 1.3),
          ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
