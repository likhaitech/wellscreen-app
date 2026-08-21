import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_period_summary.dart';
import '../models/usage_report.dart';
import '../services/firestore_child_usage_report_service.dart';
import '../services/firestore_usage_period_summary_service.dart';
import '../services/notification_service.dart';
import '../services/usage_dashboard_controller_service.dart';
import '../services/usage_dashboard_view_model_service.dart';
import 'device_pairing_screen.dart';
import 'rule_settings_screen.dart';
import 'usage_summary_screen.dart';

class AlertsReportsScreen extends StatefulWidget {
  const AlertsReportsScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGray = Color(0xFFF9FAFB);

  @override
  State<AlertsReportsScreen> createState() => _AlertsReportsScreenState();
}

class _AlertsReportsScreenState extends State<AlertsReportsScreen> {
  final UsageDashboardControllerService _controllerService =
      UsageDashboardControllerService();

  final FirestoreChildUsageReportService _childUsageReportService =
      FirestoreChildUsageReportService();

  final FirestoreUsagePeriodSummaryService _periodSummaryService =
      FirestoreUsagePeriodSummaryService();

  late Future<UsageDashboardControllerState> _alertsFuture;

  late Future<FirestoreChildUsageReportSnapshot?> _latestChildReportFuture;

  late Future<UsagePeriodSummaryBundle> _periodSummaryFuture;

  bool _showWeeklyReport = true;
  bool _showDiagnostics = false;

  @override
  void initState() {
    super.initState();

    _alertsFuture = _controllerService.loadTodayDashboardState();

    _latestChildReportFuture = _childUsageReportService
        .getLatestReportForCurrentParent();

    _periodSummaryFuture = _periodSummaryService.getCurrentPeriodSummaries();
  }

  Future<void> _refreshAlerts() async {
    setState(() {
      _alertsFuture = _controllerService.loadTodayDashboardState();

      _latestChildReportFuture = _childUsageReportService
          .getLatestReportForCurrentParent();

      _periodSummaryFuture = _periodSummaryService.getCurrentPeriodSummaries();
    });

    await Future.wait<Object?>([
      _alertsFuture,
      _latestChildReportFuture,
      _periodSummaryFuture,
    ]);
  }

  void _openUsageSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UsageSummaryScreen()),
    );
  }

  void _openDevices() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
    );
  }

  void _openRules() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RuleSettingsScreen()),
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
        break;

      case 3:
        _openRules();
        break;
    }
  }

  void _showExportMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'PDF report export will be connected in the export feature.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: AlertsReportsScreen.purple,
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
              'Reports',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshAlerts,
            icon: const Icon(Icons.refresh_rounded),
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
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              children: [
                const Text(
                  'Wellness Reports',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    color: AlertsReportsScreen.darkText,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Review your child\'s synchronized screen-time activity, wellness trends, alerts, recommendations, and location updates.',
                  style: TextStyle(
                    color: AlertsReportsScreen.grayText,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 22),

                ChildWellnessSnapshotSection(
                  latestReportFuture: _latestChildReportFuture,
                  onViewFullUsage: _openUsageSummary,
                ),

                const SizedBox(height: 20),

                ReportPeriodSelector(
                  showWeekly: _showWeeklyReport,
                  onWeeklySelected: () {
                    setState(() {
                      _showWeeklyReport = true;
                    });
                  },
                  onMonthlySelected: () {
                    setState(() {
                      _showWeeklyReport = false;
                    });
                  },
                ),

                const SizedBox(height: 14),

                PeriodWellnessReportSection(
                  periodSummaryFuture: _periodSummaryFuture,
                  showWeekly: _showWeeklyReport,
                  onViewFullSummary: _openUsageSummary,
                  onExport: _showExportMessage,
                ),

                const SizedBox(height: 24),

                const ReportSectionHeader(
                  title: 'Alerts & Monitoring',
                  subtitle:
                      'Rule-trigger notifications and synchronized location information.',
                ),

                const SizedBox(height: 12),

                const EmergencyRequestsReportSection(),

                const InAppRuleAlertsSection(),

                const LocationUpdatesReportSection(),

                const SizedBox(height: 10),

                Card(
                  elevation: 0,
                  color: AlertsReportsScreen.softGray,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        leading: const Icon(
                          Icons.developer_mode_rounded,
                          color: AlertsReportsScreen.purple,
                        ),
                        title: const Text(
                          'System & Local Diagnostics',
                          style: TextStyle(
                            color: AlertsReportsScreen.darkText,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: const Text(
                          'Development and local-device diagnostics.',
                          style: TextStyle(color: AlertsReportsScreen.grayText),
                        ),
                        trailing: Icon(
                          _showDiagnostics
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        onTap: () {
                          setState(() {
                            _showDiagnostics = !_showDiagnostics;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                if (_showDiagnostics) ...[
                  const SizedBox(height: 12),

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
                          'The system could not load the local usage report. Pull down to refresh.',
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
                        '${viewModel?.statusLabel ?? 'No Report'} - '
                        '${viewModel?.recommendationMessage ?? 'Generate a usage report first to detect screen-time patterns.'}',
                  ),

                  AlertReportCard(
                    icon: Icons.timer_rounded,
                    iconColor: AlertsReportsScreen.purple,
                    title: 'Today\'s Screen Time',
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
                        '${viewModel?.unhealthyAppCountLabel ?? '0 apps need attention'}. '
                        'Social media, gaming, or high-usage apps may require parent review.',
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
                        ? 'The dashboard is showing cached usage data. '
                              'The child device may sync newer logs once internet access is available.'
                        : 'Latest available local usage report is loaded. '
                              'Offline-first cache is ready if the connection becomes unavailable.',
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
              ],
            );
          },
        ),
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: _handleBottomNavigation,
        backgroundColor: Colors.white,
        indicatorColor: AlertsReportsScreen.softPurple,
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
            selectedIcon: Icon(
              Icons.analytics_rounded,
              color: AlertsReportsScreen.purple,
            ),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
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
      return 'Daily limit: ${_formatDuration(state.dailyScreenTimeLimit)}. '
          'Generate a usage report to evaluate today\'s progress.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)}'
        ' - Used: ${_formatDuration(goalResult.usedDuration)}'
        ' - Remaining: ${_formatDuration(goalResult.remainingDuration)}'
        '\n${goalResult.message}';
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
      return 'No late-night usage timestamp is currently available in today\'s report.';
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

class ReportSectionHeader extends StatelessWidget {
  const ReportSectionHeader({super.key, required this.title, this.subtitle});

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
            color: AlertsReportsScreen.darkText,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),

        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AlertsReportsScreen.grayText,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class ChildWellnessSnapshotSection extends StatelessWidget {
  const ChildWellnessSnapshotSection({
    super.key,
    required this.latestReportFuture,
    required this.onViewFullUsage,
  });

  final Future<FirestoreChildUsageReportSnapshot?> latestReportFuture;

  final VoidCallback onViewFullUsage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirestoreChildUsageReportSnapshot?>(
      future: latestReportFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertReportCard(
            icon: Icons.hourglass_top_rounded,
            iconColor: AlertsReportsScreen.purple,
            title: 'Loading Child Wellness Report',
            subtitle: 'Checking the latest synchronized usage report...',
          );
        }

        if (snapshot.hasError) {
          return AlertReportCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'Unable to Load Child Report',
            subtitle: snapshot.error.toString(),
          );
        }

        final reportSnapshot = snapshot.data;

        if (reportSnapshot == null) {
          return const AlertReportCard(
            icon: Icons.cloud_off_rounded,
            iconColor: Colors.orange,
            title: 'No Synced Child Report Yet',
            subtitle:
                'The child device must sync a usage report before wellness metrics can appear here.',
          );
        }

        final report = reportSnapshot.report;

        final topApp = report.topUsedApp;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportSectionHeader(
              title: 'Child Wellness Snapshot',
              subtitle:
                  '${reportSnapshot.childLabel} - ${reportSnapshot.reportDate}',
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: WellnessMetricCard(
                    icon: Icons.timer_rounded,
                    title: 'Screen Time',
                    value: report.totalUsageLabel,
                    color: AlertsReportsScreen.purple,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: WellnessMetricCard(
                    icon: Icons.health_and_safety_rounded,
                    title: 'Risk Score',
                    value: '${report.riskScore}/100',
                    color: _riskColor(report.riskScore),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: WellnessMetricCard(
                    icon: Icons.apps_rounded,
                    title: 'Top App',
                    value: topApp?.displayName ?? 'No Data',
                    subtitle: topApp?.usageLabel,
                    color: AlertsReportsScreen.purple,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: WellnessMetricCard(
                    icon: _patternIcon(report.patternStatus),
                    title: 'Status',
                    value: report.patternStatus.label,
                    color: _patternColor(report.patternStatus),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            ReportRecommendationCard(
              recommendation: report.recommendationMessage,
              onViewFullUsage: onViewFullUsage,
            ),

            const SizedBox(height: 14),

            ReportTopAppsCard(
              apps: reportSnapshot.appUsageList,
              onViewAll: onViewFullUsage,
            ),
          ],
        );
      },
    );
  }

  static Color _riskColor(int riskScore) {
    if (riskScore >= 60) {
      return Colors.red;
    }

    if (riskScore >= 30) {
      return Colors.orange;
    }

    return Colors.green;
  }

  static IconData _patternIcon(UsagePatternStatus status) {
    switch (status) {
      case UsagePatternStatus.healthy:
        return Icons.check_circle_rounded;

      case UsagePatternStatus.warning:
        return Icons.warning_amber_rounded;

      case UsagePatternStatus.unhealthy:
        return Icons.error_rounded;
    }
  }

  static Color _patternColor(UsagePatternStatus status) {
    switch (status) {
      case UsagePatternStatus.healthy:
        return Colors.green;

      case UsagePatternStatus.warning:
        return Colors.orange;

      case UsagePatternStatus.unhealthy:
        return Colors.red;
    }
  }
}

class WellnessMetricCard extends StatelessWidget {
  const WellnessMetricCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 145),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AlertsReportsScreen.softGray,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 29),

          const SizedBox(height: 9),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AlertsReportsScreen.grayText,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AlertsReportsScreen.darkText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),

          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AlertsReportsScreen.grayText,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ReportRecommendationCard extends StatelessWidget {
  const ReportRecommendationCard({
    super.key,
    required this.recommendation,
    required this.onViewFullUsage,
  });

  final String recommendation;
  final VoidCallback onViewFullUsage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AlertsReportsScreen.softPurple,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: AlertsReportsScreen.purple),
              SizedBox(width: 9),
              Text(
                'Recommendation',
                style: TextStyle(
                  color: AlertsReportsScreen.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            recommendation,
            style: const TextStyle(
              color: AlertsReportsScreen.grayText,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 10),

          TextButton.icon(
            onPressed: onViewFullUsage,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text(
              'View Full Usage Summary',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class ReportTopAppsCard extends StatelessWidget {
  const ReportTopAppsCard({
    super.key,
    required this.apps,
    required this.onViewAll,
  });

  final List<AppUsageSummary> apps;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final sortedApps = [...apps]
      ..sort((a, b) => b.usageDuration.compareTo(a.usageDuration));

    final visibleApps = sortedApps.take(5).toList();

    final maxSeconds = visibleApps.isEmpty
        ? 1
        : visibleApps.first.usageDuration.inSeconds;

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Top Apps',
                    style: TextStyle(
                      color: AlertsReportsScreen.darkText,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),

                TextButton(
                  onPressed: onViewAll,
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      color: AlertsReportsScreen.purple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            if (visibleApps.isEmpty)
              const Text(
                'No synchronized application usage is available yet.',
                style: TextStyle(color: AlertsReportsScreen.grayText),
              )
            else
              ...visibleApps.map((app) {
                final progress = maxSeconds <= 0
                    ? 0.0
                    : (app.usageDuration.inSeconds / maxSeconds)
                          .clamp(0.0, 1.0)
                          .toDouble();

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.apps_rounded,
                            color: AlertsReportsScreen.purple,
                            size: 21,
                          ),

                          const SizedBox(width: 9),

                          Expanded(
                            child: Text(
                              app.displayName,
                              style: const TextStyle(
                                color: AlertsReportsScreen.darkText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),

                          Text(
                            app.usageLabel,
                            style: const TextStyle(
                              color: AlertsReportsScreen.grayText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 7),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AlertsReportsScreen.purple,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class ReportPeriodSelector extends StatelessWidget {
  const ReportPeriodSelector({
    super.key,
    required this.showWeekly,
    required this.onWeeklySelected,
    required this.onMonthlySelected,
  });

  final bool showWeekly;
  final VoidCallback onWeeklySelected;
  final VoidCallback onMonthlySelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AlertsReportsScreen.softGray,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PeriodButton(
              label: 'Weekly',
              selected: showWeekly,
              onPressed: onWeeklySelected,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _PeriodButton(
              label: 'Monthly',
              selected: !showWeekly,
              onPressed: onMonthlySelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? AlertsReportsScreen.purple
                  : AlertsReportsScreen.grayText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class PeriodWellnessReportSection extends StatelessWidget {
  const PeriodWellnessReportSection({
    super.key,
    required this.periodSummaryFuture,
    required this.showWeekly,
    required this.onViewFullSummary,
    required this.onExport,
  });

  final Future<UsagePeriodSummaryBundle> periodSummaryFuture;

  final bool showWeekly;

  final VoidCallback onViewFullSummary;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsagePeriodSummaryBundle>(
      future: periodSummaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const AlertReportCard(
            icon: Icons.bar_chart_rounded,
            iconColor: AlertsReportsScreen.purple,
            title: 'Loading Wellness Report',
            subtitle: 'Preparing synchronized period usage data...',
          );
        }

        if (snapshot.hasError) {
          return AlertReportCard(
            icon: Icons.info_outline_rounded,
            iconColor: Colors.orange,
            title: 'Period Report Unavailable',
            subtitle: snapshot.error.toString(),
          );
        }

        final bundle = snapshot.data;

        if (bundle == null) {
          return const AlertReportCard(
            icon: Icons.bar_chart_rounded,
            iconColor: Colors.orange,
            title: 'No Period Report Yet',
            subtitle:
                'Weekly and monthly reports will appear after child usage reports are synchronized.',
          );
        }

        final summary = showWeekly
            ? bundle.weeklySummary
            : bundle.monthlySummary;

        return PeriodWellnessReportCard(
          title: showWeekly
              ? 'Weekly Wellness Report'
              : 'Monthly Wellness Report',
          summary: summary,
          onViewFullSummary: onViewFullSummary,
          onExport: onExport,
        );
      },
    );
  }
}

class PeriodWellnessReportCard extends StatelessWidget {
  const PeriodWellnessReportCard({
    super.key,
    required this.title,
    required this.summary,
    required this.onViewFullSummary,
    required this.onExport,
  });

  final String title;
  final UsagePeriodSummary summary;
  final VoidCallback onViewFullSummary;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final points = summary.chartPoints;

    final totalHours = points.fold<double>(
      0,
      (previousValue, point) => previousValue + point.usageHours,
    );

    final averageHours = points.isEmpty ? 0.0 : totalHours / points.length;

    final maxHours = summary.maxChartHours <= 0 ? 1.0 : summary.maxChartHours;

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.insert_chart_outlined_rounded,
                  color: AlertsReportsScreen.purple,
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AlertsReportsScreen.darkText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 5),

            Text(
              summary.dateRangeLabel,
              style: const TextStyle(
                color: AlertsReportsScreen.grayText,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: PeriodMetric(
                    label: 'Total',
                    value: _formatHours(totalHours),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: PeriodMetric(
                    label: 'Daily Average',
                    value: _formatHours(averageHours),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: PeriodMetric(
                    label: 'Report Days',
                    value: '${points.length}',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            if (points.isEmpty || !summary.hasChartPoints)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 25),
                child: Center(
                  child: Text(
                    'Period activity will appear after synchronized daily usage reports are available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AlertsReportsScreen.grayText,
                      height: 1.4,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 165,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: points.map((point) {
                    final factor = (point.usageHours / maxHours)
                        .clamp(0.03, 1.0)
                        .toDouble();

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: factor,
                                  widthFactor: 0.62,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _trendColor(point.patternStatus),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),

                            Text(
                              point.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AlertsReportsScreen.grayText,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 14),

            Text(
              summary.chartInsightMessage,
              style: const TextStyle(
                color: AlertsReportsScreen.grayText,
                height: 1.4,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewFullSummary,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('View Details'),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: onExport,
                    style: FilledButton.styleFrom(
                      backgroundColor: AlertsReportsScreen.purple,
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Export PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatHours(double hours) {
    final totalMinutes = (hours * 60).round();

    final wholeHours = totalMinutes ~/ 60;

    final minutes = totalMinutes % 60;

    if (wholeHours > 0) {
      return '${wholeHours}h ${minutes}m';
    }

    return '${minutes}m';
  }

  static Color _trendColor(UsagePatternStatus status) {
    switch (status) {
      case UsagePatternStatus.healthy:
        return Colors.green;

      case UsagePatternStatus.warning:
        return Colors.orange;

      case UsagePatternStatus.unhealthy:
        return Colors.red;
    }
  }
}

class PeriodMetric extends StatelessWidget {
  const PeriodMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AlertsReportsScreen.softPurple,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AlertsReportsScreen.darkText,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AlertsReportsScreen.grayText,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class LocationUpdatesReportSection extends StatelessWidget {
  const LocationUpdatesReportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const AlertReportCard(
        icon: Icons.location_off_rounded,
        iconColor: Colors.orange,
        title: 'Location Update',
        subtitle: 'Please log in again to view location updates.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_locations')
          .where('parentId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertReportCard(
            icon: Icons.location_searching_rounded,
            iconColor: AlertsReportsScreen.purple,
            title: 'Location Update',
            subtitle: 'Checking latest GPS location updates...',
          );
        }

        if (snapshot.hasError) {
          return AlertReportCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'Location Update',
            subtitle: snapshot.error.toString(),
          );
        }

        final docs = [...?snapshot.data?.docs];

        if (docs.isEmpty) {
          return const AlertReportCard(
            icon: Icons.location_off_rounded,
            iconColor: Colors.orange,
            title: 'Location Update',
            subtitle:
                'No GPS location update has been synced yet. '
                'Ask the child device to allow location permission '
                'and tap Sync Current Location.',
          );
        }

        docs.sort((a, b) {
          final aTime = a.data()['capturedAt'];

          final bTime = b.data()['capturedAt'];

          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }

          return 0;
        });

        final data = docs.first.data();

        final childLabel = data['childLabel'] as String? ?? 'Child device';

        final latitude = _readDouble(data['latitude']);

        final longitude = _readDouble(data['longitude']);

        final accuracy = _readDouble(data['accuracyMeters']);

        final isOutsideSafeZone = data['isOutsideSafeZone'] as bool? ?? false;

        final distance = _readDouble(data['distanceFromSafeZoneMeters']);

        final capturedAtValue = data['capturedAt'];

        final capturedAt = capturedAtValue is Timestamp
            ? capturedAtValue.toDate()
            : null;

        final coordinates = latitude == null || longitude == null
            ? 'Coordinates not available'
            : '${latitude.toStringAsFixed(6)}, '
                  '${longitude.toStringAsFixed(6)}';

        final geoFenceText = isOutsideSafeZone
            ? 'Geo-fence alert: outside safe zone'
                  '${distance == null ? '' : ' by ${distance.toStringAsFixed(0)}m'}'
            : 'Geo-fence status: inside safe zone';

        return AlertReportCard(
          icon: isOutsideSafeZone
              ? Icons.warning_amber_rounded
              : Icons.location_on_rounded,
          iconColor: isOutsideSafeZone ? Colors.red : Colors.green,
          title: 'Location Update',
          subtitle:
              '$childLabel\n'
              'Coordinates: $coordinates\n'
              'Accuracy: ${accuracy?.toStringAsFixed(0) ?? 'Unknown'}m\n'
              'Last captured: ${_formatDateTime(capturedAt)}\n'
              '$geoFenceText',
        );
      },
    );
  }

  double? _readDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Time not available';
    }

    final year = value.year.toString().padLeft(4, '0');

    final month = value.month.toString().padLeft(2, '0');

    final day = value.day.toString().padLeft(2, '0');

    final hour = value.hour > 12
        ? value.hour - 12
        : value.hour == 0
        ? 12
        : value.hour;

    final minute = value.minute.toString().padLeft(2, '0');

    final period = value.hour >= 12 ? 'PM' : 'AM';

    return '$year-$month-$day '
        '$hour:$minute $period';
  }
}

Future<void> _sendMessageToChild(
  BuildContext context, {
  required String parentId,
  required String childUserId,
  String? childId,
  String? childLabel,
  String? replyToAlertId,
}) async {
  final message = await showDialog<String>(
    context: context,
    builder: (_) =>
        ParentToChildMessageDialog(childLabel: childLabel ?? 'Child'),
  );

  if (message == null || message.trim().isEmpty) {
    return;
  }

  try {
    await NotificationService.instance.createInAppAlert(
      recipientUserId: childUserId,
      parentId: parentId,
      childId: childId,
      title: 'Message from Parent',
      message: message.trim(),
      triggerType: 'parent_contact_child',
      priority: 'medium',
      extraData: {'replyToAlertId': replyToAlertId},
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Message sent to ${childLabel ?? 'child'}.')),
    );
  } catch (e) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Unable to send message: $e')));
  }
}

Future<void> _sendEmergencyDecisionNotification(
  BuildContext context, {
  required String parentId,
  required String childUserId,
  required String? childId,
  required bool approved,
}) async {
  try {
    await NotificationService.instance.createInAppAlert(
      recipientUserId: childUserId,
      parentId: parentId,
      childId: childId,
      title: approved ? 'Emergency Access Approved' : 'Emergency Access Denied',
      message: approved
          ? 'Your emergency access request was approved for 15 minutes.'
          : 'Your emergency access request was denied. Contact your parent if you still need help.',
      triggerType: approved
          ? 'emergency_access_approved'
          : 'emergency_access_denied',
      priority: approved ? 'high' : 'medium',
      extraData: {'decision': approved ? 'approved' : 'denied'},
    );
  } catch (e) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Emergency request updated, but the child notification could not be sent: $e',
        ),
      ),
    );
  }
}

class ParentToChildMessageDialog extends StatefulWidget {
  const ParentToChildMessageDialog({super.key, required this.childLabel});

  final String childLabel;

  @override
  State<ParentToChildMessageDialog> createState() =>
      _ParentToChildMessageDialogState();
}

class _ParentToChildMessageDialogState
    extends State<ParentToChildMessageDialog> {
  final TextEditingController _controller = TextEditingController();

  static const List<String> _quickMessages = [
    'Please call me when you can.',
    'Please take a short break.',
    'Please come talk to me.',
  ];

  String? _selectedQuickMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectQuickMessage(String value) {
    setState(() {
      _selectedQuickMessage = value;
      _controller.text = value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _send() {
    final message = _controller.text.trim();

    if (message.isEmpty) {
      return;
    }

    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Message ${widget.childLabel}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a quick message or write your own.',
              style: TextStyle(color: AlertsReportsScreen.grayText),
            ),

            const SizedBox(height: 14),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickMessages.map((message) {
                return ChoiceChip(
                  label: Text(message),
                  selected: _selectedQuickMessage == message,
                  onSelected: (_) => _selectQuickMessage(message),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Message',
                hintText: 'Write a message to your child...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _send,
          style: FilledButton.styleFrom(
            backgroundColor: AlertsReportsScreen.purple,
          ),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class EmergencyRequestsReportSection extends StatelessWidget {
  const EmergencyRequestsReportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const AlertReportCard(
        icon: Icons.emergency_outlined,
        iconColor: Colors.orange,
        title: 'Emergency Requests',
        subtitle: 'Please log in again to view emergency access requests.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('emergency_access_requests')
          .where('parentId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertReportCard(
            icon: Icons.emergency_outlined,
            iconColor: AlertsReportsScreen.purple,
            title: 'Emergency Requests',
            subtitle: 'Checking emergency access requests...',
          );
        }

        if (snapshot.hasError) {
          return AlertReportCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'Emergency Requests',
            subtitle: snapshot.error.toString(),
          );
        }

        final docs = [...?snapshot.data?.docs];

        docs.sort((a, b) {
          final aTime = a.data()['requestedAt'];
          final bTime = b.data()['requestedAt'];

          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }

          return 0;
        });

        if (docs.isEmpty) {
          return const AlertReportCard(
            icon: Icons.emergency_outlined,
            iconColor: AlertsReportsScreen.purple,
            title: 'Emergency Requests',
            subtitle: 'No emergency access request has been received.',
          );
        }

        final pendingCount = docs.where((doc) {
          return (doc.data()['status'] as String? ?? 'none') == 'pending';
        }).length;

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
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: pendingCount > 0
                            ? const Color(0xFFFFF4E5)
                            : AlertsReportsScreen.softPurple,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.emergency_rounded,
                        color: pendingCount > 0
                            ? Colors.orange
                            : AlertsReportsScreen.purple,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Emergency Requests',
                            style: TextStyle(
                              color: AlertsReportsScreen.darkText,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            pendingCount > 0
                                ? '$pendingCount request${pendingCount == 1 ? '' : 's'} waiting for your response'
                                : 'No pending emergency requests',
                            style: const TextStyle(
                              color: AlertsReportsScreen.grayText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                ...docs.take(3).map((doc) {
                  final data = doc.data();

                  final status = data['status'] as String? ?? 'none';
                  final reason =
                      data['reason'] as String? ?? 'No reason provided.';
                  final childEmail = data['childEmail'] as String? ?? 'Child';
                  final childUserId = data['childUserId'] as String? ?? doc.id;
                  final childId = data['childId'] as String?;
                  final requestedAtValue = data['requestedAt'];
                  final requestedAt = requestedAtValue is Timestamp
                      ? requestedAtValue.toDate()
                      : null;

                  final statusColor = switch (status) {
                    'pending' => Colors.orange,
                    'approved' => Colors.green,
                    'denied' => Colors.red,
                    _ => AlertsReportsScreen.grayText,
                  };

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AlertsReportsScreen.softGray,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                childEmail,
                                style: const TextStyle(
                                  color: AlertsReportsScreen.darkText,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withAlpha(26),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        Text(
                          reason,
                          style: const TextStyle(
                            color: AlertsReportsScreen.grayText,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          requestedAt == null
                              ? 'Request time unavailable'
                              : _formatParentAlertTime(requestedAt),
                          style: const TextStyle(
                            color: AlertsReportsScreen.grayText,
                            fontSize: 11,
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (status == 'pending')
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await doc.reference.set({
                                      'status': 'denied',
                                      'approvedUntil': FieldValue.delete(),
                                      'respondedAt':
                                          FieldValue.serverTimestamp(),
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    if (!context.mounted) {
                                      return;
                                    }

                                    await _sendEmergencyDecisionNotification(
                                      context,
                                      parentId: user.uid,
                                      childUserId: childUserId,
                                      childId: childId,
                                      approved: false,
                                    );
                                  },
                                  child: const Text('Deny'),
                                ),
                              ),

                              const SizedBox(width: 8),

                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    final approvedUntil = DateTime.now().add(
                                      const Duration(minutes: 15),
                                    );

                                    await doc.reference.set({
                                      'status': 'approved',
                                      'approvedUntil': Timestamp.fromDate(
                                        approvedUntil,
                                      ),
                                      'respondedAt':
                                          FieldValue.serverTimestamp(),
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    if (!context.mounted) {
                                      return;
                                    }

                                    await _sendEmergencyDecisionNotification(
                                      context,
                                      parentId: user.uid,
                                      childUserId: childUserId,
                                      childId: childId,
                                      approved: true,
                                    );
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AlertsReportsScreen.purple,
                                  ),
                                  child: const Text('Approve 15 min'),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 8),

                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () {
                              _sendMessageToChild(
                                context,
                                parentId: user.uid,
                                childUserId: childUserId,
                                childId: childId,
                                childLabel: childEmail,
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text(
                              'Message Child',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
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
        subtitle: 'Please log in again to view alerts and child messages.',
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
            subtitle: 'Checking alerts and messages...',
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
            subtitle: 'No alerts or child messages have been received yet.',
          );
        }

        final unreadCount = docs.where((doc) {
          return (doc.data()['isRead'] as bool? ?? false) == false;
        }).length;

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
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: unreadCount > 0
                            ? const Color(0xFFFFF4E5)
                            : AlertsReportsScreen.softPurple,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        unreadCount > 0
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color: unreadCount > 0
                            ? Colors.orange
                            : AlertsReportsScreen.purple,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'In-App Notifications',
                            style: TextStyle(
                              color: AlertsReportsScreen.darkText,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            unreadCount > 0
                                ? '$unreadCount unread'
                                : 'You are all caught up',
                            style: const TextStyle(
                              color: AlertsReportsScreen.grayText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                ...docs.take(5).map((doc) {
                  final data = doc.data();

                  final title = data['title'] as String? ?? 'WellScreen Alert';
                  final message =
                      data['message'] as String? ?? 'No message available.';
                  final triggerType =
                      data['triggerType'] as String? ?? 'rule_trigger';
                  final isRead = data['isRead'] as bool? ?? false;
                  final childUserId = data['childUserId'] as String?;
                  final childId = data['childId'] as String?;

                  final extraData = data['extraData'];
                  final extraMap = extraData is Map
                      ? Map<String, dynamic>.from(extraData)
                      : <String, dynamic>{};

                  final childLabel =
                      extraMap['childEmail'] as String? ??
                      data['childEmail'] as String? ??
                      'Child';

                  final createdAtValue = data['createdAt'];
                  final createdAt = createdAtValue is Timestamp
                      ? createdAtValue.toDate()
                      : null;

                  final canMessageChild =
                      childUserId != null && childUserId.isNotEmpty;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isRead
                          ? AlertsReportsScreen.softGray
                          : AlertsReportsScreen.softPurple,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isRead
                            ? const Color(0xFFE5E7EB)
                            : const Color(0xFFD9CCFF),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: AlertsReportsScreen.darkText,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (!isRead)
                              const Icon(
                                Icons.circle,
                                size: 9,
                                color: Colors.orange,
                              ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        Text(
                          message,
                          style: const TextStyle(
                            color: AlertsReportsScreen.grayText,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 7),

                        Text(
                          '${_formatTriggerLabel(triggerType)}'
                          '${createdAt == null ? '' : ' • ${_formatParentAlertTime(createdAt)}'}',
                          style: const TextStyle(
                            color: AlertsReportsScreen.purple,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!isRead)
                              TextButton.icon(
                                onPressed: () {
                                  doc.reference.set({
                                    'isRead': true,
                                    'readAt': FieldValue.serverTimestamp(),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                },
                                icon: const Icon(Icons.done_rounded, size: 18),
                                label: const Text('Mark read'),
                              ),

                            if (canMessageChild)
                              FilledButton.icon(
                                onPressed: () {
                                  _sendMessageToChild(
                                    context,
                                    parentId: user.uid,
                                    childUserId: childUserId,
                                    childId: childId,
                                    childLabel: childLabel,
                                    replyToAlertId: doc.id,
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: AlertsReportsScreen.purple,
                                ),
                                icon: const Icon(Icons.reply_rounded, size: 18),
                                label: Text(
                                  triggerType == 'child_contact_parent'
                                      ? 'Reply'
                                      : 'Message Child',
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

String _formatTriggerLabel(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _formatParentAlertTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');

  final hour = value.hour > 12
      ? value.hour - 12
      : value.hour == 0
      ? 12
      : value.hour;

  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';

  return '$month/$day $hour:$minute $period';
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
