import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/daily_screen_time_limit_service.dart';
import '../services/notification_service.dart';
import '../services/usage_dashboard_controller_service.dart';
import 'alerts_reports_screen.dart';
import 'device_pairing_screen.dart';
import 'login_screen.dart';

class RuleSettingsScreen extends StatefulWidget {
  const RuleSettingsScreen({super.key});

  @override
  State<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends State<RuleSettingsScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGray = Color(0xFFF9FAFB);

  final TextEditingController limitController = TextEditingController(
    text: '120',
  );

  final UsageDashboardControllerService _controllerService =
      UsageDashboardControllerService();

  final DailyScreenTimeLimitService _dailyLimitService =
      DailyScreenTimeLimitService();

  late Future<UsageDashboardControllerState> _dashboardFuture;

  bool appBlocking = true;
  bool focusMode = true;
  bool cooldownTimer = true;
  bool scheduledLock = false;
  bool categoryRestriction = true;
  bool emergencyAccess = true;

  bool isSaving = false;
  bool isLoadingRules = true;

  @override
  void initState() {
    super.initState();

    _dashboardFuture = _controllerService.loadTodayDashboardState();

    _loadSavedRules();
  }

  @override
  void dispose() {
    limitController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedRules() async {
    final user = FirebaseAuth.instance.currentUser;

    try {
      final localLimit = await _dailyLimitService.getDailyLimit();

      if (!mounted) return;

      limitController.text = localLimit.inMinutes.toString();

      if (user != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('restriction_settings')
            .doc(user.uid)
            .get();

        final data = snapshot.data();

        if (data != null && mounted) {
          setState(() {
            limitController.text =
                (data['limitMinutes'] as int? ?? localLimit.inMinutes)
                    .toString();

            appBlocking = data['appBlocking'] as bool? ?? appBlocking;

            focusMode = data['focusMode'] as bool? ?? focusMode;

            cooldownTimer = data['cooldownTimer'] as bool? ?? cooldownTimer;

            scheduledLock = data['scheduledLock'] as bool? ?? scheduledLock;

            categoryRestriction =
                data['categoryRestriction'] as bool? ?? categoryRestriction;

            emergencyAccess =
                data['emergencyAccess'] as bool? ?? emergencyAccess;
          });
        }
      }
    } catch (e) {
      showMessage('Unable to load saved rules: $e');
    } finally {
      if (mounted) {
        setState(() => isLoadingRules = false);
      }
    }
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardFuture = _controllerService.loadTodayDashboardState();
    });

    await _dashboardFuture;
  }

  Future<void> saveRules() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final limitMinutes = int.tryParse(limitController.text.trim());

    if (limitMinutes == null || limitMinutes <= 0) {
      showMessage('Please enter a valid daily usage limit.');
      return;
    }

    if (limitMinutes > 1440) {
      showMessage('Daily usage limit cannot exceed 1440 minutes.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final dailyLimit = Duration(minutes: limitMinutes);

      await _dailyLimitService.saveDailyLimit(dailyLimit);

      await FirebaseFirestore.instance
          .collection('restriction_settings')
          .doc(user.uid)
          .set({
            'parentId': user.uid,
            'limitMinutes': limitMinutes,
            'appBlocking': appBlocking,
            'focusMode': focusMode,
            'cooldownTimer': cooldownTimer,
            'scheduledLock': scheduledLock,
            'categoryRestriction': categoryRestriction,
            'emergencyAccess': emergencyAccess,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _dashboardFuture = _controllerService.loadTodayDashboardState();
        });
      }

      showMessage('Rules saved and daily screen-time goal updated.');
    } catch (e) {
      showMessage('Rule saving error: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openDevices() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
    );
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlertsReportsScreen()),
    );
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _handleBottomNavigation(int index) {
    switch (index) {
      case 0:
        _goHome();
        break;

      case 1:
        _openDevices();
        break;

      case 2:
        _openReports();
        break;

      case 3:
        break;
    }
  }

  void _showAccountInfo() {
    final user = FirebaseAuth.instance.currentUser;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Account Information',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account Type',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              const Text(
                'Parent / Guardian',
                style: TextStyle(color: darkText, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              const Text(
                'Email',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                user?.email ?? 'No email available',
                style: const TextStyle(
                  color: darkText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyInfo() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Privacy & Security',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'WellScreen uses authenticated parent and child accounts to protect access to device, usage, restriction, alert, and location information.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showHelpInfo() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Help & Support',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'For device monitoring to work correctly, pair the child phone, enable the required Android permissions, and synchronize usage and location data from the child device.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showAboutInfo() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'About WellScreen',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'WellScreen is a parental digital wellness monitoring system designed to help parents review screen-time activity, usage patterns, restrictions, alerts, and child-device wellness information.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Image.asset(
                'assets/icons/wellscreen_icon.png',
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(width: 11),

            const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),

      body: FutureBuilder<UsageDashboardControllerState>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          final state = snapshot.data;

          final goalResult = state?.screenTimeGoalResult;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            children: [
              const Text(
                'Parent Settings',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Manage your account, child-device restrictions, safety features, notifications, and WellScreen preferences.',
                style: TextStyle(color: grayText, height: 1.4),
              ),

              const SizedBox(height: 22),

              AccountOverviewCard(
                email: user?.email ?? 'Parent account',
                onAccountTap: _showAccountInfo,
              ),

              const SizedBox(height: 24),

              const SettingsSectionHeader(
                title: 'Screen Time & Restrictions',
                subtitle:
                    'Configure the rules applied to monitored child devices.',
              ),

              const SizedBox(height: 12),

              RuleGoalStatusCard(
                title: 'Daily Screen-Time Goal',
                subtitle: _getGoalStatusText(state),
                icon: Icons.flag_rounded,
                iconColor: _getGoalColor(state),
              ),

              RuleGoalStatusCard(
                title: 'Today\'s Usage Progress',
                subtitle: goalResult == null
                    ? 'No usage report is available yet. The goal will be evaluated after usage data is loaded.'
                    : 'Used: ${_formatDuration(goalResult.usedDuration)}'
                          ' - Remaining: ${_formatDuration(goalResult.remainingDuration)}'
                          '\n${goalResult.message}',
                icon: Icons.insights_rounded,
                iconColor: purple,
              ),

              const SizedBox(height: 6),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: softGray,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Usage Limit',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Set the maximum amount of daily screen time allowed.',
                      style: TextStyle(color: grayText, height: 1.35),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: limitController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Daily Limit in Minutes',
                        helperText: 'Example: 120 minutes = 2 hours.',
                        prefixIcon: const Icon(Icons.timer_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              if (isLoadingRules)
                const RuleGoalStatusCard(
                  title: 'Loading Saved Rules',
                  subtitle: 'Preparing saved restriction settings...',
                  icon: Icons.hourglass_top_rounded,
                  iconColor: purple,
                ),

              RuleSwitch(
                icon: Icons.block_rounded,
                title: 'App Blocking',
                subtitle: 'Block selected apps after limits are reached.',
                value: appBlocking,
                onChanged: (value) {
                  setState(() => appBlocking = value);
                },
              ),

              RuleSwitch(
                icon: Icons.center_focus_strong_rounded,
                title: 'Focus Mode',
                subtitle: 'Limit distracting apps during study or rest time.',
                value: focusMode,
                onChanged: (value) {
                  setState(() => focusMode = value);
                },
              ),

              RuleSwitch(
                icon: Icons.hourglass_bottom_rounded,
                title: 'Cooldown Timer',
                subtitle: 'Add a break reminder after long continuous usage.',
                value: cooldownTimer,
                onChanged: (value) {
                  setState(() => cooldownTimer = value);
                },
              ),

              RuleSwitch(
                icon: Icons.lock_clock_rounded,
                title: 'Scheduled Lock Session',
                subtitle:
                    'Apply restrictions during the current scheduled lock period, 10:00 PM to 5:00 AM.',
                value: scheduledLock,
                onChanged: (value) {
                  setState(() => scheduledLock = value);
                },
              ),

              RuleSwitch(
                icon: Icons.shield_rounded,
                title: 'Harmful Category Restriction',
                subtitle:
                    'Restrict supported harmful website or category events.',
                value: categoryRestriction,
                onChanged: (value) {
                  setState(() => categoryRestriction = value);
                },
              ),

              RuleSwitch(
                icon: Icons.emergency_rounded,
                title: 'Emergency Access',
                subtitle:
                    'Allow selected essential functions during restrictions.',
                value: emergencyAccess,
                onChanged: (value) {
                  setState(() => emergencyAccess = value);
                },
              ),

              const SizedBox(height: 8),

              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: isSaving ? null : saveRules,
                  style: FilledButton.styleFrom(
                    backgroundColor: purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.save_rounded),
                  label: Text(
                    isSaving ? 'Saving...' : 'Save and Apply Rules',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const RuleGoalStatusCard(
                title: 'Restriction Status',
                subtitle:
                    'Rules are saved for parent review and synchronized to the monitored child device for local enforcement when the required permissions are enabled.',
                icon: Icons.info_outline_rounded,
                iconColor: purple,
              ),

              const SizedBox(height: 24),

              const SettingsSectionHeader(
                title: 'Notifications & Safety',
                subtitle:
                    'Configure backup alerts and review child emergency requests.',
              ),

              const SizedBox(height: 12),

              const SmsBackupAlertSettingsSection(),

              const EmergencyAccessApprovalSection(),

              const SizedBox(height: 24),

              const SettingsSectionHeader(
                title: 'Monitoring Shortcuts',
                subtitle: 'Quick access to other parent monitoring areas.',
              ),

              const SizedBox(height: 12),

              SettingsActionTile(
                icon: Icons.phone_android_rounded,
                title: 'Child Devices',
                subtitle: 'Manage paired child phones and device connections.',
                onTap: _openDevices,
              ),

              SettingsActionTile(
                icon: Icons.analytics_rounded,
                title: 'Reports & Notifications',
                subtitle:
                    'Review wellness reports, alerts, and location updates.',
                onTap: _openReports,
              ),

              const SizedBox(height: 24),

              const SettingsSectionHeader(title: 'More'),

              const SizedBox(height: 12),

              SettingsActionTile(
                icon: Icons.person_outline_rounded,
                title: 'Account Settings',
                subtitle: 'Review the current parent account.',
                onTap: _showAccountInfo,
              ),

              SettingsActionTile(
                icon: Icons.lock_outline_rounded,
                title: 'Privacy & Security',
                subtitle:
                    'Review how WellScreen protects monitoring information.',
                onTap: _showPrivacyInfo,
              ),

              SettingsActionTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                subtitle: 'View basic setup and monitoring guidance.',
                onTap: _showHelpInfo,
              ),

              SettingsActionTile(
                icon: Icons.info_outline_rounded,
                title: 'About WellScreen',
                subtitle: 'Learn more about the WellScreen system.',
                onTap: _showAboutInfo,
              ),

              const SizedBox(height: 8),

              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'Logout',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          );
        },
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: 3,
        onDestinationSelected: _handleBottomNavigation,
        backgroundColor: Colors.white,
        indicatorColor: softPurple,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.phone_android_outlined),
            selectedIcon: Icon(Icons.phone_android_rounded),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: purple),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  String _getGoalStatusText(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading current daily screen-time limit...';
    }

    final goalResult = state.screenTimeGoalResult;

    if (goalResult == null) {
      return 'Current daily limit: ${_formatDuration(state.dailyScreenTimeLimit)}. '
          'Save a new value to update the parent rule.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)}'
        ' - Progress: ${_getProgressPercent(goalResult.progressPercent)}';
  }

  Color _getGoalColor(UsageDashboardControllerState? state) {
    final goalResult = state?.screenTimeGoalResult;

    if (goalResult == null) {
      return purple;
    }

    final progress = goalResult.progressPercent;

    if (progress >= 1) {
      return Colors.red;
    }

    if (progress >= 0.8) {
      return Colors.orange;
    }

    return Colors.green;
  }

  String _getProgressPercent(double progressPercent) {
    final clampedValue = progressPercent.clamp(0, 1).toDouble();

    return '${(clampedValue * 100).round()}%';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m';
    }

    return '${duration.inSeconds}s';
  }
}

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class AccountOverviewCard extends StatelessWidget {
  const AccountOverviewCard({
    super.key,
    required this.email,
    required this.onAccountTap,
  });

  final String email;
  final VoidCallback onAccountTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person_rounded,
              color: Color(0xFF5B2BBF),
              size: 31,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Parent / Guardian',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Account Information',
            onPressed: onAccountTap,
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF5B2BBF),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsActionTile extends StatelessWidget {
  const SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF5B2BBF)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF4B5563), height: 1.35),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class SmsBackupAlertSettingsSection extends StatefulWidget {
  const SmsBackupAlertSettingsSection({super.key});

  @override
  State<SmsBackupAlertSettingsSection> createState() =>
      _SmsBackupAlertSettingsSectionState();
}

class _SmsBackupAlertSettingsSectionState
    extends State<SmsBackupAlertSettingsSection> {
  final TextEditingController phoneController = TextEditingController();

  bool smsBackupAlerts = false;
  bool isLoading = true;
  bool isSaving = false;

  static const Color purple = Color(0xFF5B2BBF);

  static const Color darkText = Color(0xFF111827);

  static const Color grayText = Color(0xFF4B5563);

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  Future<void> loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() => isLoading = false);
      }
      return;
    }

    try {
      final docIds = ['active', 'current', 'default'];

      for (final docId in docIds) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('restriction_settings')
            .doc(docId)
            .get();

        final data = snapshot.data();

        if (data != null) {
          smsBackupAlerts = data['smsBackupAlerts'] as bool? ?? false;

          phoneController.text = data['guardianPhoneNumber'] as String? ?? '';

          break;
        }
      }
    } catch (_) {
      // Keep defaults if SMS settings
      // cannot be loaded.
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> saveSettings() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again before saving SMS backup settings.');
      return;
    }

    final phoneNumber = phoneController.text.trim();

    if (smsBackupAlerts && phoneNumber.length < 7) {
      showMessage('Enter a valid guardian phone number for SMS alerts.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final data = <String, dynamic>{
        'smsBackupAlerts': smsBackupAlerts,
        'guardianPhoneNumber': phoneNumber,
        'smsBackupUpdatedAt': FieldValue.serverTimestamp(),
      };

      final docIds = ['active', 'current', 'default'];

      for (final docId in docIds) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('restriction_settings')
            .doc(docId)
            .set(data, SetOptions(merge: true));
      }

      showMessage('SMS backup alert settings saved.');
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const RuleGoalStatusCard(
        title: 'SMS Backup Alerts',
        subtitle: 'Loading SMS backup alert settings...',
        icon: Icons.sms_rounded,
        iconColor: purple,
      );
    }

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sms_rounded, color: purple, size: 34),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'SMS Backup Alerts',
                    style: TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            const Text(
              'Send SMS alerts to the guardian phone number when critical blocking events happen on the child device. WellScreen does not read SMS messages.',
              style: TextStyle(color: grayText, height: 1.4),
            ),

            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: purple,
              title: const Text(
                'Enable SMS Backup Alerts',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Used as a backup alert channel for blocked apps and harmful websites.',
              ),
              value: smsBackupAlerts,
              onChanged: (value) {
                setState(() => smsBackupAlerts = value);
              },
            ),

            const SizedBox(height: 8),

            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Guardian Phone Number',
                hintText: 'Example: 09XXXXXXXXX',
                prefixIcon: const Icon(Icons.phone_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSaving ? null : saveSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.save_rounded),
                label: Text(
                  isSaving ? 'Saving...' : 'Save SMS Backup Settings',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmergencyAccessApprovalSection extends StatelessWidget {
  const EmergencyAccessApprovalSection({super.key});

  static const Color purple = Color(0xFF5B2BBF);

  static const Color darkText = Color(0xFF111827);

  static const Color grayText = Color(0xFF4B5563);

  Future<void> approveRequest(String requestId) async {
    final approvedUntil = DateTime.now().add(const Duration(minutes: 15));

    await FirebaseFirestore.instance
        .collection('emergency_access_requests')
        .doc(requestId)
        .set({
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedUntil': Timestamp.fromDate(approvedUntil),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> denyRequest(String requestId) async {
    await FirebaseFirestore.instance
        .collection('emergency_access_requests')
        .doc(requestId)
        .set({
          'status': 'denied',
          'deniedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const RuleGoalStatusCard(
        title: 'Emergency Access Requests',
        subtitle: 'Please log in again to review child requests.',
        icon: Icons.emergency_rounded,
        iconColor: Colors.orange,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('emergency_access_requests')
          .where('parentId', isEqualTo: user.uid)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RuleGoalStatusCard(
            title: 'Emergency Access Requests',
            subtitle: 'Checking child emergency access requests...',
            icon: Icons.hourglass_top_rounded,
            iconColor: purple,
          );
        }

        if (snapshot.hasError) {
          return RuleGoalStatusCard(
            title: 'Emergency Access Requests',
            subtitle: snapshot.error.toString(),
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final pendingDocs = docs
            .where(
              (doc) => (doc.data()['status'] as String? ?? '') == 'pending',
            )
            .toList();

        if (pendingDocs.isEmpty) {
          return const RuleGoalStatusCard(
            title: 'Emergency Access Requests',
            subtitle:
                'No pending child emergency access request is available right now.',
            icon: Icons.emergency_rounded,
            iconColor: purple,
          );
        }

        return Card(
          elevation: 1.5,
          shadowColor: Colors.black12,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emergency_rounded, color: purple, size: 34),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Emergency Access Requests',
                        style: TextStyle(
                          color: darkText,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                ...pendingDocs.map((doc) {
                  final data = doc.data();

                  final childEmail =
                      data['childEmail'] as String? ?? 'Child device';

                  final reason =
                      data['reason'] as String? ?? 'No reason provided.';

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F0FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          childEmail,
                          style: const TextStyle(
                            color: darkText,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          'Reason: $reason',
                          style: const TextStyle(color: grayText, height: 1.4),
                        ),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  try {
                                    await approveRequest(doc.id);

                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Emergency access approved for 15 minutes.',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Unable to approve request: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: purple,
                                ),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Approve'),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    await denyRequest(doc.id);

                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Emergency access request denied.',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Unable to deny request: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Deny'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 7),

                        const Text(
                          'Approval grants temporary access for 15 minutes.',
                          style: TextStyle(color: grayText, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> createRuleTriggerAlerts({
  required String parentId,
  required int limitMinutes,
  required bool appBlocking,
  required bool focusMode,
  required bool cooldownTimer,
  required bool scheduledLock,
  required bool categoryRestriction,
  required bool emergencyAccess,
}) async {
  final notificationService = NotificationService.instance;

  final enabledRules = <String>[
    if (appBlocking) 'App Blocking',
    if (focusMode) 'Focus Mode',
    if (cooldownTimer) 'Cooldown Timer',
    if (scheduledLock) 'Scheduled Lock',
    if (categoryRestriction) 'Harmful Category Restriction',
    if (emergencyAccess) 'Emergency Access',
  ];

  final enabledRulesText = enabledRules.isEmpty
      ? 'No active restriction rule'
      : enabledRules.join(', ');

  const title = 'Rule Trigger Alert';

  final message =
      'Guardian rules were updated. '
      'Active rules: $enabledRulesText. '
      'Daily limit: $limitMinutes minutes.';

  await notificationService.initializeForCurrentUser(
    contextLabel: 'parent_rule_settings',
  );

  await notificationService.createInAppAlert(
    recipientUserId: parentId,
    parentId: parentId,
    title: title,
    message: message,
    triggerType: 'rule_settings_updated',
    priority: 'medium',
    extraData: {
      'limitMinutes': limitMinutes,
      'appBlocking': appBlocking,
      'focusMode': focusMode,
      'cooldownTimer': cooldownTimer,
      'scheduledLock': scheduledLock,
      'categoryRestriction': categoryRestriction,
      'emergencyAccess': emergencyAccess,
    },
  );

  final childDevices = await FirebaseFirestore.instance
      .collection('child_devices')
      .where('parentId', isEqualTo: parentId)
      .get();

  for (final device in childDevices.docs) {
    final data = device.data();

    final childUserId = data['childUserId'] as String?;

    final childId = data['childId'] as String?;

    if (childUserId == null || childUserId.isEmpty) {
      continue;
    }

    await notificationService.createInAppAlert(
      recipientUserId: childUserId,
      parentId: parentId,
      childId: childId,
      title: title,
      message: message,
      triggerType: 'child_rule_sync_needed',
      priority: 'medium',
      extraData: {
        'limitMinutes': limitMinutes,
        'appBlocking': appBlocking,
        'focusMode': focusMode,
        'cooldownTimer': cooldownTimer,
        'scheduledLock': scheduledLock,
        'categoryRestriction': categoryRestriction,
        'emergencyAccess': emergencyAccess,
      },
    );
  }
}

class RuleGoalStatusCard extends StatelessWidget {
  const RuleGoalStatusCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  static const Color darkText = Color(0xFF111827);

  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(color: grayText, height: 1.4),
          ),
        ),
      ),
    );
  }
}

class RuleSwitch extends StatelessWidget {
  const RuleSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  static const Color purple = Color(0xFF5B2BBF);

  static const Color darkText = Color(0xFF111827);

  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SwitchListTile(
        activeThumbColor: purple,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: purple, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: grayText, height: 1.35),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
