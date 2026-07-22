import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/daily_screen_time_limit_service.dart';
import '../services/usage_dashboard_controller_service.dart';

class RuleSettingsScreen extends StatefulWidget {
  const RuleSettingsScreen({super.key});

  @override
  State<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends State<RuleSettingsScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

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

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Rule Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshDashboard,
          ),
        ],
      ),
      body: FutureBuilder<UsageDashboardControllerState>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final goalResult = state?.screenTimeGoalResult;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Configure Restrictions',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set daily screen-time limits, focus mode, cooldown timers, scheduled locks, category restrictions, and emergency access.',
                style: TextStyle(color: grayText, height: 1.4),
              ),
              const SizedBox(height: 24),

              RuleGoalStatusCard(
                title: 'Daily Screen-Time Goal',
                subtitle: _getGoalStatusText(state),
                icon: Icons.flag_rounded,
                iconColor: _getGoalColor(state),
              ),

              RuleGoalStatusCard(
                title: 'Todayâ€™s Usage Progress',
                subtitle: goalResult == null
                    ? 'No usage report is available yet. The goal will be evaluated after usage data is loaded.'
                    : 'Used: ${_formatDuration(goalResult.usedDuration)} â€¢ Remaining: ${_formatDuration(goalResult.remainingDuration)}\n${goalResult.message}',
                icon: Icons.insights_rounded,
                iconColor: purple,
              ),

              const SizedBox(height: 8),

              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Daily Usage Limit in Minutes',
                  helperText:
                      'Example: 120 minutes means 2 hours of daily screen time.',
                  prefixIcon: const Icon(Icons.timer_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (isLoadingRules)
                const RuleGoalStatusCard(
                  title: 'Loading Saved Rules',
                  subtitle: 'Preparing saved restriction settings...',
                  icon: Icons.hourglass_top_rounded,
                  iconColor: purple,
                ),

              RuleSwitch(
                title: 'App Blocking',
                subtitle: 'Block selected apps after limits are reached.',
                value: appBlocking,
                onChanged: (value) => setState(() => appBlocking = value),
              ),

              RuleSwitch(
                title: 'Focus Mode',
                subtitle: 'Limit distracting apps during study or rest time.',
                value: focusMode,
                onChanged: (value) => setState(() => focusMode = value),
              ),

              RuleSwitch(
                title: 'Cooldown Timer',
                subtitle: 'Add a break reminder after long continuous usage.',
                value: cooldownTimer,
                onChanged: (value) => setState(() => cooldownTimer = value),
              ),

              RuleSwitch(
                title: 'Scheduled Lock Session',
                subtitle: 'Apply restrictions during the default scheduled lock time, 10:00 PM to 5:00 AM.',
                value: scheduledLock,
                onChanged: (value) => setState(() => scheduledLock = value),
              ),

              RuleSwitch(
                title: 'Harmful Category Restriction',
                subtitle:
                    'Restrict supported harmful website or category events.',
                value: categoryRestriction,
                onChanged: (value) {
                  setState(() => categoryRestriction = value);
                },
              ),

              RuleSwitch(
                title: 'Emergency Access',
                subtitle:
                    'Allow selected essential functions during restrictions.',
                value: emergencyAccess,
                onChanged: (value) => setState(() => emergencyAccess = value),
              ),

              const SizedBox(height: 12),

              const RuleGoalStatusCard(
                title: 'Prototype Restriction Status',
                subtitle:
                    'Rules are saved for parent review and synced to the monitored child device for local enforcement when permissions are enabled.',
                icon: Icons.info_outline_rounded,
                iconColor: purple,
              ),

              const SizedBox(height: 22),

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
            ],
          );
        },
      ),
    );
  }

  String _getGoalStatusText(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading current daily screen-time limit...';
    }

    final goalResult = state.screenTimeGoalResult;

    if (goalResult == null) {
      return 'Current daily limit: ${_formatDuration(state.dailyScreenTimeLimit)}. Save a new value to update the parent rule.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)} â€¢ Progress: ${_getProgressPercent(goalResult.progressPercent)}';
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
      setState(() => isLoading = false);
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
          phoneController.text =
              data['guardianPhoneNumber'] as String? ?? '';
          break;
        }
      }
    } catch (_) {
      // Keep default values when settings cannot be loaded.
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
      final data = {
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                labelText: 'Guardian phone number',
                hintText: 'Example: 09XXXXXXXXX',
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
            .where((doc) => (doc.data()['status'] as String? ?? '') == 'pending')
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
                          style: const TextStyle(
                            color: grayText,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => approveRequest(doc.id),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Approve 15 min'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => denyRequest(doc.id),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Deny'),
                              ),
                            ),
                          ],
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
        leading: Icon(icon, color: iconColor, size: 34),
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
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

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




