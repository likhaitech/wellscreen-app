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
                subtitle: 'Apply restrictions during selected schedules.',
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

