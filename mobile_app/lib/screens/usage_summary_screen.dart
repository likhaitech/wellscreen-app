import 'package:flutter/material.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_period_summary.dart';
import '../models/usage_report.dart';
import '../services/firestore_usage_period_summary_service.dart';
import '../services/screen_time_goal_service.dart';
import '../services/usage_dashboard_controller_service.dart';

class UsageSummaryScreen extends StatefulWidget {
  const UsageSummaryScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF1ECFF);

  @override
  State<UsageSummaryScreen> createState() => _UsageSummaryScreenState();
}

class _UsageSummaryScreenState extends State<UsageSummaryScreen> {
  final UsageDashboardControllerService _controllerService =
      UsageDashboardControllerService();
  final FirestoreUsagePeriodSummaryService _periodSummaryService =
      FirestoreUsagePeriodSummaryService();

  late Future<UsageDashboardControllerState> _summaryFuture;
  late Future<UsagePeriodSummaryBundle> _periodSummaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _controllerService.loadTodayDashboardState();
    _periodSummaryFuture = _periodSummaryService.getCurrentPeriodSummaries();
  }

  Future<void> _refreshSummary() async {
    setState(() {
      _summaryFuture = _controllerService.loadTodayDashboardState();
      _periodSummaryFuture = _periodSummaryService.getCurrentPeriodSummaries();
    });

    await Future.wait<Object?>([_summaryFuture, _periodSummaryFuture]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Usage Summary',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: UsageSummaryScreen.darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshSummary,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSummary,
        child: FutureBuilder<UsageDashboardControllerState>(
          future: _summaryFuture,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final viewModel = state?.viewModel;
            final appUsageList = state?.appUsageList ?? <AppUsageSummary>[];
            final goalResult = state?.screenTimeGoalResult;

            final isLoading =
                snapshot.connectionState == ConnectionState.waiting &&
                state == null;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Daily, Weekly, and Monthly Usage',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: UsageSummaryScreen.darkText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Review screen time, app usage, detected patterns, recommendations, and screen-time goal progress.',
                  style: TextStyle(
                    color: UsageSummaryScreen.grayText,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                if (isLoading)
                  const SummaryStatusCard(
                    icon: Icons.hourglass_top_rounded,
                    title: 'Loading Usage Summary',
                    message: 'Preparing today’s usage data...',
                    color: UsageSummaryScreen.purple,
                  ),

                if (snapshot.hasError)
                  const SummaryStatusCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Unable to Load Summary',
                    message:
                        'The usage summary could not be loaded. Pull down to refresh or check usage access permission.',
                    color: Colors.red,
                  ),

                if (viewModel?.errorMessage != null)
                  SummaryStatusCard(
                    icon: Icons.info_outline_rounded,
                    title: viewModel?.isUsingCachedData == true
                        ? 'Cached Usage Report'
                        : 'Action Needed',
                    message: viewModel!.errorMessage!,
                    color: viewModel.isUsingCachedData
                        ? Colors.orange
                        : Colors.red,
                  ),

                SummaryCard(
                  icon: Icons.today_rounded,
                  title: 'Today’s Screen Time',
                  value: viewModel?.totalUsageLabel ?? '0s',
                  description:
                      'Current monitored usage for the selected child profile.',
                ),

                SummaryCard(
                  icon: Icons.flag_rounded,
                  title: 'Daily Screen-Time Goal',
                  value: _getGoalValue(state),
                  description: _getGoalDescription(state),
                ),

                PeriodSummarySection(periodSummaryFuture: _periodSummaryFuture),

                SummaryCard(
                  icon: Icons.apps_rounded,
                  title: 'Top Used Application',
                  value: viewModel?.topUsedAppLabel ?? 'No app usage recorded',
                  description:
                      'App with the highest usage duration for today’s report.',
                ),

                AppUsageBreakdownCard(appUsageList: appUsageList),

                SummaryCard(
                  icon: Icons.nightlight_round,
                  title: 'Detected Pattern',
                  value: viewModel?.statusLabel ?? 'No Report',
                  description:
                      viewModel?.recommendationMessage ??
                      'Generate a usage report first to detect usage patterns.',
                ),

                SummaryCard(
                  icon: Icons.health_and_safety_rounded,
                  title:
                      viewModel?.interventionTitle ??
                      'No Intervention Available',
                  value:
                      viewModel?.interventionTitle ??
                      'No Intervention Available',
                  description:
                      viewModel?.interventionMessage ??
                      'Generate a usage report first to receive a recommendation.',
                ),

                SummaryCard(
                  icon: Icons.category_rounded,
                  title: 'Apps Needing Attention',
                  value:
                      viewModel?.unhealthyAppCountLabel ??
                      '0 apps need attention',
                  description:
                      'Social media, gaming, or high-usage apps that may require parent review.',
                ),

                SummaryCard(
                  icon: Icons.update_rounded,
                  title: 'Report Generated',
                  value: _getGeneratedAtLabel(state),
                  description: goalResult == null
                      ? 'No completed usage report is available yet.'
                      : 'This summary is based on the latest available usage report.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _getGoalValue(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading goal...';
    }

    final goalResult = state.screenTimeGoalResult;

    if (goalResult == null) {
      return 'Daily limit: ${_formatDuration(state.dailyScreenTimeLimit)}';
    }

    return '${_getGoalStatusLabel(goalResult.status)} • ${_formatDuration(goalResult.usedDuration)} used';
  }

  String _getGoalDescription(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading daily screen-time goal progress.';
    }

    final goalResult = state.screenTimeGoalResult;

    if (goalResult == null) {
      return 'Generate a usage report to evaluate today’s progress against the daily limit.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)} • Remaining: ${_formatDuration(goalResult.remainingDuration)} • Progress: ${_getProgressPercent(goalResult.progressPercent)}\n${goalResult.message}';
  }

  String _getGoalStatusLabel(ScreenTimeGoalStatus status) {
    switch (status) {
      case ScreenTimeGoalStatus.withinLimit:
        return 'Within Limit';
      case ScreenTimeGoalStatus.nearLimit:
        return 'Near Limit';
      case ScreenTimeGoalStatus.exceeded:
        return 'Exceeded';
    }
  }

  String _getProgressPercent(double progressPercent) {
    final clampedValue = progressPercent.clamp(0, 1).toDouble();
    return '${(clampedValue * 100).round()}%';
  }

  String _getGeneratedAtLabel(UsageDashboardControllerState? state) {
    final viewModel = state?.viewModel;

    if (viewModel == null || viewModel.statusLabel == 'No Report') {
      return 'No report yet';
    }

    return 'Today';
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

class PeriodSummarySection extends StatelessWidget {
  const PeriodSummarySection({super.key, required this.periodSummaryFuture});

  final Future<UsagePeriodSummaryBundle> periodSummaryFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsagePeriodSummaryBundle>(
      future: periodSummaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const SummaryStatusCard(
            icon: Icons.hourglass_top_rounded,
            title: 'Loading Weekly and Monthly Summaries',
            message: 'Checking synced daily usage reports from Firestore...',
            color: UsageSummaryScreen.purple,
          );
        }

        if (snapshot.hasError) {
          return SummaryStatusCard(
            icon: Icons.error_outline_rounded,
            title: 'Unable to Load Weekly and Monthly Summaries',
            message: snapshot.error.toString(),
            color: Colors.red,
          );
        }

        final bundle = snapshot.data;

        if (bundle == null) {
          return const SummaryStatusCard(
            icon: Icons.info_outline_rounded,
            title: 'No Period Summary Available',
            message:
                'Weekly and monthly summaries will appear after synced daily reports are available.',
            color: Colors.orange,
          );
        }

        return Column(
          children: [
            PeriodSummaryCard(summary: bundle.weeklySummary),
            PeriodSummaryCard(summary: bundle.monthlySummary),
          ],
        );
      },
    );
  }
}

class PeriodSummaryCard extends StatelessWidget {
  const PeriodSummaryCard({super.key, required this.summary});

  final UsagePeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final topUsedApp = summary.topUsedApp;
    final topUsedAppLabel = topUsedApp == null
        ? 'No top app recorded'
        : '${topUsedApp.displayName} • ${topUsedApp.usageLabel}';

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(_getIcon(summary), color: _getColor(summary), size: 34),
        title: Text(
          summary.title,
          style: const TextStyle(
            color: UsageSummaryScreen.darkText,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Child: ${summary.childLabel}\n'
            'Date Range: ${summary.dateRangeLabel}\n'
            'Reports Counted: ${summary.reportCount}\n'
            'Total Screen Time: ${summary.totalUsageLabel}\n'
            'Average Daily Usage: ${summary.averageDailyUsageLabel}\n'
            'Top App: $topUsedAppLabel\n'
            'Status: ${summary.statusLabel}\n'
            'Warning Days: ${summary.warningReportCount} • Unhealthy Days: ${summary.unhealthyReportCount}\n'
            '${summary.recommendationMessage}',
            style: const TextStyle(
              color: UsageSummaryScreen.grayText,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon(UsagePeriodSummary summary) {
    if (!summary.hasReports) {
      return Icons.info_outline_rounded;
    }

    switch (summary.patternStatus) {
      case null:
        return Icons.info_outline_rounded;
      case UsagePatternStatus.healthy:
        return Icons.check_circle_rounded;
      case UsagePatternStatus.warning:
        return Icons.warning_amber_rounded;
      case UsagePatternStatus.unhealthy:
        return Icons.error_rounded;
    }
  }

  Color _getColor(UsagePeriodSummary summary) {
    if (!summary.hasReports) {
      return Colors.orange;
    }

    switch (summary.patternStatus) {
      case null:
        return Colors.orange;
      case UsagePatternStatus.healthy:
        return Colors.green;
      case UsagePatternStatus.warning:
        return Colors.orange;
      case UsagePatternStatus.unhealthy:
        return Colors.red;
    }
  }
}

class SummaryStatusCard extends StatelessWidget {
  const SummaryStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: color, size: 34),
        title: Text(
          title,
          style: const TextStyle(
            color: UsageSummaryScreen.darkText,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            message,
            style: const TextStyle(
              color: UsageSummaryScreen.grayText,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class AppUsageBreakdownCard extends StatelessWidget {
  const AppUsageBreakdownCard({super.key, required this.appUsageList});

  final List<AppUsageSummary> appUsageList;

  @override
  Widget build(BuildContext context) {
    final visibleApps = appUsageList.take(5).toList();

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  color: UsageSummaryScreen.purple,
                  size: 34,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'App Usage Breakdown',
                    style: TextStyle(
                      color: UsageSummaryScreen.darkText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (visibleApps.isEmpty)
              const Text(
                'No live app usage list available yet. This may happen when usage permission is missing or only cached report data is available.',
                style: TextStyle(
                  color: UsageSummaryScreen.grayText,
                  height: 1.4,
                ),
              )
            else
              ...visibleApps.map(
                (app) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.apps_rounded,
                        color: UsageSummaryScreen.purple,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          app.displayName,
                          style: const TextStyle(
                            color: UsageSummaryScreen.darkText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        app.usageLabel,
                        style: const TextStyle(
                          color: UsageSummaryScreen.grayText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: UsageSummaryScreen.purple, size: 34),
        title: Text(
          title,
          style: const TextStyle(
            color: UsageSummaryScreen.darkText,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$value\n$description',
            style: const TextStyle(
              color: UsageSummaryScreen.grayText,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
