import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_usage_summary.dart';
import '../services/usage_dashboard_controller_service.dart';
import '../services/usage_dashboard_view_model_service.dart';

class AlertsReportsScreen extends StatefulWidget {
  const AlertsReportsScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  State<AlertsReportsScreen> createState() => _AlertsReportsScreenState();
}

class _AlertsReportsScreenState extends State<AlertsReportsScreen> {
  final UsageDashboardControllerService _controllerService =
      UsageDashboardControllerService();

  late Future<UsageDashboardControllerState> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = _controllerService.loadTodayDashboardState();
  }

  Future<void> _refreshAlerts() async {
    setState(() {
      _alertsFuture = _controllerService.loadTodayDashboardState();
    });

    await _alertsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Alerts and Reports',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AlertsReportsScreen.darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshAlerts,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAlerts,
        child: FutureBuilder<UsageDashboardControllerState>(
          future: _alertsFuture,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final viewModel = state?.viewModel;
            final appUsageList = state?.appUsageList ?? <AppUsageSummary>[];

            final isLoading =
                snapshot.connectionState == ConnectionState.waiting &&
                state == null;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'System Outputs',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: AlertsReportsScreen.darkText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Review alerts, reports, recommendations, location updates, and delayed synchronization events.',
                  style: TextStyle(
                    color: AlertsReportsScreen.grayText,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Date filter will be available once weekly reports are connected.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.date_range_rounded),
                        label: const Text('Date Filter'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Report export prepared for prototype.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Export'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                if (isLoading)
                  const AlertReportCard(
                    icon: Icons.hourglass_top_rounded,
                    iconColor: AlertsReportsScreen.purple,
                    title: 'Loading Reports',
                    subtitle: 'Preparing alerts and usage report data...',
                  ),

                if (snapshot.hasError)
                  const AlertReportCard(
                    icon: Icons.error_outline_rounded,
                    iconColor: Colors.red,
                    title: 'Unable to Load Reports',
                    subtitle:
                        'The system could not load todayâ€™s alerts. Pull down to refresh or check usage access permission.',
                  ),

                if (viewModel?.errorMessage != null)
                  AlertReportCard(
                    icon: Icons.info_outline_rounded,
                    iconColor: viewModel?.isUsingCachedData == true
                        ? Colors.orange
                        : Colors.red,
                    title: viewModel?.isUsingCachedData == true
                        ? 'Cached Report Used'
                        : 'Action Needed',
                    subtitle: viewModel!.errorMessage!,
                  ),

                AlertReportCard(
                  icon: _getPatternIcon(viewModel?.statusLabel),
                  iconColor: _getStatusColor(viewModel?.statusLabel),
                  title: 'Usage Pattern Status',
                  subtitle:
                      '${viewModel?.statusLabel ?? 'No Report'} - ${viewModel?.recommendationMessage ?? 'Generate a usage report first to detect screen-time patterns.'}',
                ),

                AlertReportCard(
                  icon: Icons.timer_rounded,
                  iconColor: AlertsReportsScreen.purple,
                  title: 'Todayâ€™s Screen Time',
                  subtitle:
                      'Total monitored usage today: ${viewModel?.totalUsageLabel ?? '0s'}.',
                ),

                AlertReportCard(
                  icon: Icons.flag_rounded,
                  iconColor: _getGoalColor(state),
                  title: 'Daily Screen-Time Goal',
                  subtitle: _getGoalSubtitle(state),
                ),

                AlertReportCard(
                  icon: Icons.apps_rounded,
                  iconColor: AlertsReportsScreen.purple,
                  title: 'Most Used Applications',
                  subtitle: _getTopAppsSubtitle(appUsageList, viewModel),
                ),

                AlertReportCard(
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.orange,
                  title: 'Apps Needing Attention',
                  subtitle:
                      '${viewModel?.unhealthyAppCountLabel ?? '0 apps need attention'}. Social media, gaming, or high-usage apps may require parent review.',
                ),

                AlertReportCard(
                  icon: Icons.category_rounded,
                  iconColor: AlertsReportsScreen.purple,
                  title: 'Category Indicator',
                  subtitle: _getCategorySubtitle(appUsageList),
                ),

                AlertReportCard(
                  icon: Icons.nightlight_round,
                  iconColor: Colors.indigo,
                  title: 'Late-Night Usage Check',
                  subtitle: _getLateNightSubtitle(appUsageList),
                ),

                AlertReportCard(
                  icon: Icons.sync_problem_rounded,
                  iconColor: viewModel?.isUsingCachedData == true
                      ? Colors.redAccent
                      : Colors.green,
                  title: 'Synchronization Status',
                  subtitle: viewModel?.isUsingCachedData == true
                      ? 'The dashboard is showing cached usage data. The child device may sync newer logs once internet access is available.'
                      : 'Latest available usage report is loaded. Offline-first cache is ready if connection becomes unavailable.',
                ),

                const AlertReportCard(
                  icon: Icons.location_on_rounded,
                  iconColor: Colors.green,
                  title: 'Location Update',
                  subtitle:
                      'Location-related updates will appear here when GPS permission and tracking service are connected.',
                ),

                AlertReportCard(
                  icon: Icons.health_and_safety_rounded,
                  iconColor: AlertsReportsScreen.purple,
                  title:
                      viewModel?.interventionTitle ??
                      'No Intervention Available',
                  subtitle:
                      viewModel?.interventionMessage ??
                      'Generate a usage report first to receive a parent-guided intervention recommendation.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  IconData _getPatternIcon(String? statusLabel) {
    switch (statusLabel) {
      case 'Healthy':
        return Icons.check_circle_rounded;
      case 'Warning':
        return Icons.warning_amber_rounded;
      case 'Unhealthy':
        return Icons.error_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _getStatusColor(String? statusLabel) {
    switch (statusLabel) {
      case 'Healthy':
        return Colors.green;
      case 'Warning':
        return Colors.orange;
      case 'Unhealthy':
        return Colors.red;
      default:
        return AlertsReportsScreen.purple;
    }
  }

  Color _getGoalColor(UsageDashboardControllerState? state) {
    final goalResult = state?.screenTimeGoalResult;

    if (goalResult == null) {
      return AlertsReportsScreen.purple;
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

  String _getGoalSubtitle(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading daily screen-time goal data...';
    }

    final goalResult = state.screenTimeGoalResult;

    if (goalResult == null) {
      return 'Daily limit: ${_formatDuration(state.dailyScreenTimeLimit)}. Generate a usage report to evaluate todayâ€™s progress.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)} â€¢ Used: ${_formatDuration(goalResult.usedDuration)} â€¢ Remaining: ${_formatDuration(goalResult.remainingDuration)}\n${goalResult.message}';
  }

  String _getTopAppsSubtitle(
    List<AppUsageSummary> appUsageList,
    UsageDashboardViewModel? viewModel,
  ) {
    if (appUsageList.isEmpty) {
      return viewModel?.topUsedAppLabel ?? 'No app usage recorded yet.';
    }

    return appUsageList
        .take(3)
        .map((app) => '${app.displayName} (${app.usageLabel})')
        .join(', ');
  }

  String _getCategorySubtitle(List<AppUsageSummary> appUsageList) {
    final categoryApps = appUsageList.where(_isSocialOrGameApp).toList();

    if (categoryApps.isEmpty) {
      return 'No supported social media or gaming category event is currently flagged.';
    }

    final appNames = categoryApps
        .take(3)
        .map((app) => app.displayName)
        .join(', ');

    return 'Supported social media or gaming apps detected for review: $appNames.';
  }

  String _getLateNightSubtitle(List<AppUsageSummary> appUsageList) {
    final lateNightApps = appUsageList.where(_isLateNightApp).toList();

    if (lateNightApps.isEmpty) {
      return 'No late-night usage timestamp is currently available in todayâ€™s report.';
    }

    final appNames = lateNightApps
        .take(3)
        .map((app) => app.displayName)
        .join(', ');

    return 'Usage activity was recorded during rest hours for: $appNames.';
  }

  bool _isLateNightApp(AppUsageSummary app) {
    final lastTimeUsed = app.lastTimeUsed;

    if (lastTimeUsed == null) {
      return false;
    }

    return lastTimeUsed.hour >= 22 || lastTimeUsed.hour < 5;
  }

  bool _isSocialOrGameApp(AppUsageSummary app) {
    final value = '${app.packageName} ${app.displayName}'.toLowerCase();

    const keywords = [
      'facebook',
      'messenger',
      'instagram',
      'tiktok',
      'youtube',
      'twitter',
      'snapchat',
      'discord',
      'netflix',
      'game',
      'games',
      'gaming',
      'roblox',
      'minecraft',
      'mobilelegends',
      'mlbb',
      'pubg',
      'cod',
      'freefire',
    ];

    return keywords.any(value.contains);
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

class InAppRuleAlertsSection extends StatelessWidget {
  const InAppRuleAlertsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const AlertReportCard(
        icon: Icons.notifications_off_rounded,
        iconColor: Colors.orange,
        title: 'In-App Notifications',
        subtitle: 'Please log in again to view rule-trigger alerts.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('in_app_alerts')
          .where('recipientUserId', isEqualTo: user.uid)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertReportCard(
            icon: Icons.notifications_active_rounded,
            iconColor: AlertsReportsScreen.purple,
            title: 'In-App Notifications',
            subtitle: 'Checking rule-trigger alerts...',
          );
        }

        if (snapshot.hasError) {
          return AlertReportCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'In-App Notifications',
            subtitle: snapshot.error.toString(),
          );
        }

        final docs = [...?snapshot.data?.docs];

        docs.sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];

          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }

          return 0;
        });

        if (docs.isEmpty) {
          return const AlertReportCard(
            icon: Icons.notifications_none_rounded,
            iconColor: AlertsReportsScreen.purple,
            title: 'In-App Notifications',
            subtitle:
                'No rule-trigger alert has been recorded yet. Alerts will appear after guardian rules are saved or Firebase messages are received.',
          );
        }

        final unreadCount = docs
            .where((doc) => (doc.data()['isRead'] as bool? ?? false) == false)
            .length;

        return Card(
          elevation: 2,
          shadowColor: Colors.black12,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      unreadCount > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: unreadCount > 0
                          ? Colors.orange
                          : AlertsReportsScreen.purple,
                      size: 34,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        unreadCount > 0
                            ? 'In-App Notifications ($unreadCount unread)'
                            : 'In-App Notifications',
                        style: const TextStyle(
                          color: AlertsReportsScreen.darkText,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...docs.take(5).map((doc) {
                  final data = doc.data();
                  final title = data['title'] as String? ?? 'WellScreen Alert';
                  final message =
                      data['message'] as String? ?? 'No message available.';
                  final triggerType =
                      data['triggerType'] as String? ?? 'rule_trigger';
                  final isRead = data['isRead'] as bool? ?? false;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isRead
                          ? const Color(0xFFF9FAFB)
                          : const Color(0xFFF4F0FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      onTap: () {
                        doc.reference.set({
                          'isRead': true,
                          'readAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AlertsReportsScreen.darkText,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message,
                            style: const TextStyle(
                              color: AlertsReportsScreen.grayText,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Trigger: $triggerType${isRead ? ' • Read' : ' • Unread'}',
                            style: const TextStyle(
                              color: AlertsReportsScreen.purple,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
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
class AlertReportCard extends StatelessWidget {
  const AlertReportCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: iconColor, size: 34),
        title: Text(
          title,
          style: const TextStyle(
            color: AlertsReportsScreen.darkText,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: AlertsReportsScreen.grayText,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

