import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/usage_report.dart';
import '../services/firestore_child_usage_report_service.dart';
import '../services/usage_dashboard_controller_service.dart';
import '../services/usage_dashboard_view_model_service.dart';
import '../services/notification_service.dart';
import 'alerts_reports_screen.dart';
import 'device_pairing_screen.dart';
import 'login_screen.dart';
import 'rule_settings_screen.dart';
import 'usage_summary_screen.dart';

const Color _purple = Color(0xFF5B2BBF);
const Color _darkText = Color(0xFF111827);
const Color _grayText = Color(0xFF4B5563);
const Color _softPurple = Color(0xFFF1ECFF);

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final UsageDashboardControllerService _controllerService =
      UsageDashboardControllerService();
  final FirestoreChildUsageReportService _childUsageReportService =
      FirestoreChildUsageReportService();

  late Future<UsageDashboardControllerState> _dashboardFuture;
  late Future<FirestoreChildUsageReportSnapshot?> _latestChildReportFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _controllerService.loadTodayDashboardState();
    _latestChildReportFuture = _childUsageReportService
        .getLatestReportForCurrentParent();
    unawaited(
      NotificationService.instance.initializeForCurrentUser(
        contextLabel: 'parent_dashboard',
      ),
    );
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardFuture = _controllerService.loadTodayDashboardState();
      _latestChildReportFuture = _childUsageReportService
          .getLatestReportForCurrentParent();
    });

    await Future.wait([_dashboardFuture, _latestChildReportFuture]);
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Parent account';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshDashboard,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: FutureBuilder<UsageDashboardControllerState>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final viewModel = state?.viewModel;
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting &&
                state == null;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Welcome, Parent',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: _darkText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Review child-device activity, alerts, recommendations, restrictions, reports, and location-related updates.',
                  style: TextStyle(color: _grayText, height: 1.4),
                ),
                const SizedBox(height: 24),

                if (isLoading) const DashboardStatusCard.loading(),

                if (snapshot.hasError)
                  const DashboardStatusCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Dashboard unavailable',
                    message:
                        'Unable to load usage dashboard data. Pull down to refresh or check usage access permission.',
                    color: Colors.red,
                  ),

                if (viewModel?.errorMessage != null)
                  DashboardStatusCard(
                    icon: Icons.info_outline_rounded,
                    title: viewModel?.isUsingCachedData == true
                        ? 'Cached Report'
                        : 'Action Needed',
                    message: viewModel!.errorMessage!,
                    color: viewModel.isUsingCachedData
                        ? Colors.orange
                        : Colors.red,
                  ),

                ParentChildDeviceOverview(
                  parentId: user?.uid,
                  usageStatusText: _getDeviceStatusText(viewModel),
                  hasUsagePermission: viewModel?.hasUsagePermission == true,
                ),

                const SizedBox(height: 16),

                LatestChildUsageReportSection(
                  latestReportFuture: _latestChildReportFuture,
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: DashboardMiniCard(
                        icon: Icons.timer_rounded,
                        title: 'Local Screen Time',
                        value: viewModel?.totalUsageLabel ?? '0s',
                        color: _purple,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UsageSummaryScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DashboardMiniCard(
                        icon: Icons.warning_amber_rounded,
                        title: 'Local Status',
                        value: viewModel?.statusLabel ?? 'No Report',
                        color: _getStatusColor(viewModel?.statusLabel),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AlertsReportsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                DashboardInfoCard(
                  icon: Icons.apps_rounded,
                  title: 'Local Most Used App',
                  subtitle:
                      viewModel?.topUsedAppLabel ?? 'No app usage recorded',
                ),

                const SizedBox(height: 12),

                DashboardInfoCard(
                  icon: Icons.lightbulb_rounded,
                  title: 'Local Recommendation',
                  subtitle:
                      viewModel?.recommendationMessage ??
                      'No usage report available yet.',
                ),

                const SizedBox(height: 12),

                DashboardInfoCard(
                  icon: Icons.health_and_safety_rounded,
                  title:
                      viewModel?.interventionTitle ??
                      'No Intervention Available',
                  subtitle:
                      viewModel?.interventionMessage ??
                      'Generate a usage report first to receive a recommendation.',
                ),

                const SizedBox(height: 12),

                DashboardInfoCard(
                  icon: Icons.flag_rounded,
                  title: 'Daily Screen-Time Goal',
                  subtitle: _getGoalSummary(state),
                ),

                const SizedBox(height: 22),

                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DevicePairingScreen(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text(
                    'Device Pairing',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RuleSettingsScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.rule_rounded),
                  label: const Text(
                    'Rule Settings',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _getDeviceStatusText(UsageDashboardViewModel? viewModel) {
    if (viewModel == null) {
      return 'Loading child-device usage data';
    }

    if (!viewModel.hasUsagePermission) {
      return 'Usage access permission needed';
    }

    if (viewModel.isUsingCachedData) {
      return 'Showing last cached child-device report';
    }

    return 'Usage access connected';
  }

  String _getGoalSummary(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading daily screen-time goal...';
    }

    final goalResult = state.screenTimeGoalResult;
    final dailyLimitLabel = _formatDuration(state.dailyScreenTimeLimit);

    if (goalResult == null) {
      return 'Daily limit: $dailyLimitLabel. Generate a usage report to evaluate todayâ€™s progress.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)} â€¢ Used: ${_formatDuration(goalResult.usedDuration)} â€¢ Remaining: ${_formatDuration(goalResult.remainingDuration)}\n${goalResult.message}';
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

  Color _getStatusColor(String? statusLabel) {
    switch (statusLabel) {
      case 'Healthy':
        return Colors.green;
      case 'Warning':
        return Colors.orange;
      case 'Unhealthy':
        return Colors.red;
      default:
        return _purple;
    }
  }
}

class ParentChildDeviceOverview extends StatelessWidget {
  const ParentChildDeviceOverview({
    super.key,
    required this.parentId,
    required this.usageStatusText,
    required this.hasUsagePermission,
  });

  final String? parentId;
  final String usageStatusText;
  final bool hasUsagePermission;

  @override
  Widget build(BuildContext context) {
    if (parentId == null) {
      return const DashboardStatusCard(
        icon: Icons.info_outline_rounded,
        title: 'No Parent Account',
        message: 'Please log in again to view paired child devices.',
        color: Colors.orange,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_profiles')
          .where('parentId', isEqualTo: parentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DashboardStatusCard(
            icon: Icons.hourglass_top_rounded,
            title: 'Loading Child Devices',
            message:
                'Checking paired child profiles for this parent account...',
            color: _purple,
          );
        }

        if (snapshot.hasError) {
          return DashboardStatusCard(
            icon: Icons.error_outline_rounded,
            title: 'Unable to Load Child Devices',
            message: snapshot.error.toString(),
            color: Colors.red,
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const DashboardStatusCard(
            icon: Icons.link_off_rounded,
            title: 'No Paired Child Device Yet',
            message:
                'Generate a pairing code and let the child device enter it to connect.',
            color: Colors.orange,
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();

            return ChildDeviceOverviewCard(
              data: data,
              usageStatusText: usageStatusText,
              hasUsagePermission: hasUsagePermission,
            );
          }).toList(),
        );
      },
    );
  }
}

class LatestChildUsageReportSection extends StatelessWidget {
  const LatestChildUsageReportSection({
    super.key,
    required this.latestReportFuture,
  });

  final Future<FirestoreChildUsageReportSnapshot?> latestReportFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirestoreChildUsageReportSnapshot?>(
      future: latestReportFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DashboardStatusCard(
            icon: Icons.hourglass_top_rounded,
            title: 'Loading Synced Usage Report',
            message:
                'Checking the latest usage report synced by the child device...',
            color: _purple,
          );
        }

        if (snapshot.hasError) {
          return DashboardStatusCard(
            icon: Icons.error_outline_rounded,
            title: 'Unable to Load Synced Report',
            message: snapshot.error.toString(),
            color: Colors.red,
          );
        }

        final reportSnapshot = snapshot.data;

        if (reportSnapshot == null) {
          return const DashboardStatusCard(
            icon: Icons.cloud_off_rounded,
            title: 'No Synced Child Usage Report Yet',
            message:
                'Ask the child device to tap Sync Usage Report after pairing and enabling Usage Access.',
            color: Colors.orange,
          );
        }

        return Column(
          children: [
            SyncedChildUsageReportCard(reportSnapshot: reportSnapshot),
            const SizedBox(height: 12),
            SyncedAppUsagePreviewCard(reportSnapshot: reportSnapshot),
          ],
        );
      },
    );
  }
}

class SyncedChildUsageReportCard extends StatelessWidget {
  const SyncedChildUsageReportCard({super.key, required this.reportSnapshot});

  final FirestoreChildUsageReportSnapshot reportSnapshot;

  @override
  Widget build(BuildContext context) {
    final report = reportSnapshot.report;
    final topUsedApp = report.topUsedApp;
    final topUsedAppLabel = topUsedApp == null
        ? 'No top app recorded'
        : '${topUsedApp.displayName} â€¢ ${topUsedApp.usageLabel}';

    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: _softPurple,
              child: Icon(
                Icons.cloud_done_rounded,
                color: _getPatternColor(report.patternStatus),
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latest Synced Child Usage',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _darkText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reportSnapshot.childLabel,
                    style: const TextStyle(
                      color: _darkText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Report Date: ${reportSnapshot.reportDate}\n'
                    'Screen Time: ${report.totalUsageLabel}\n'
                    'Top App: $topUsedAppLabel\n'
                    'Status: ${report.patternStatus.label}\n'
                    'Recommendation: ${report.recommendationMessage}',
                    style: const TextStyle(color: _grayText, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(
              _getPatternIcon(report.patternStatus),
              color: _getPatternColor(report.patternStatus),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPatternIcon(UsagePatternStatus status) {
    switch (status) {
      case UsagePatternStatus.healthy:
        return Icons.check_circle_rounded;
      case UsagePatternStatus.warning:
        return Icons.warning_amber_rounded;
      case UsagePatternStatus.unhealthy:
        return Icons.error_rounded;
    }
  }

  Color _getPatternColor(UsagePatternStatus status) {
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

class SyncedAppUsagePreviewCard extends StatelessWidget {
  const SyncedAppUsagePreviewCard({super.key, required this.reportSnapshot});

  final FirestoreChildUsageReportSnapshot reportSnapshot;

  @override
  Widget build(BuildContext context) {
    final apps = reportSnapshot.appUsageList.take(5).toList();

    final subtitle = apps.isEmpty
        ? 'No synced app breakdown is available yet.'
        : apps
              .map((app) => '${app.displayName} - ${app.usageLabel}')
              .join('\n');

    return DashboardInfoCard(
      icon: Icons.list_alt_rounded,
      title: 'Synced App Usage Breakdown',
      subtitle: subtitle,
    );
  }
}

class ChildDeviceOverviewCard extends StatelessWidget {
  const ChildDeviceOverviewCard({
    super.key,
    required this.data,
    required this.usageStatusText,
    required this.hasUsagePermission,
  });

  final Map<String, dynamic> data;
  final String usageStatusText;
  final bool hasUsagePermission;

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Child Profile';
    final ageValue = data['age'];
    final age = ageValue is num ? ageValue.toInt() : 0;
    final pairingStatus = data['pairingStatus'] as String? ?? 'waiting';
    final deviceStatus = data['deviceStatus'] as String? ?? 'not_connected';
    final childEmail = data['childEmail'] as String?;
    final deviceName = data['deviceName'] as String?;
    final pairingCode = data['pairingCode'] as String?;
    final lastReportDate = data['lastUsageReportDate'] as String?;

    final isPaired = pairingStatus == 'paired' || deviceStatus == 'connected';
    final ageText = age > 0 ? 'Age $age' : 'Age not set';

    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: _softPurple,
              child: Icon(
                isPaired
                    ? Icons.phone_android_rounded
                    : Icons.child_care_rounded,
                color: isPaired ? Colors.green : _purple,
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Child Device Overview',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _darkText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$name â€¢ $ageText',
                    style: const TextStyle(
                      color: _darkText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pairing: ${_formatStatus(pairingStatus)}\n'
                    'Device Status: ${_formatStatus(deviceStatus)}\n'
                    'Child Email: ${childEmail ?? 'Not linked yet'}\n'
                    'Device Name: ${deviceName ?? 'Not available'}\n'
                    'Pairing Code: ${pairingCode ?? 'No active code'}\n'
                    'Last Synced Report: ${lastReportDate ?? 'No report yet'}\n'
                    'Usage Data: $usageStatusText',
                    style: const TextStyle(color: _grayText, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(
              isPaired
                  ? Icons.check_circle_rounded
                  : hasUsagePermission
                  ? Icons.schedule_rounded
                  : Icons.info_rounded,
              color: isPaired
                  ? Colors.green
                  : hasUsagePermission
                  ? Colors.orange
                  : Colors.orange,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  String _formatStatus(String value) {
    return value.replaceAll('_', ' ').toUpperCase();
  }
}

class DashboardStatusCard extends StatelessWidget {
  const DashboardStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  const DashboardStatusCard.loading({super.key})
    : icon = Icons.hourglass_top_rounded,
      title = 'Loading Dashboard',
      message = 'Preparing todayâ€™s usage report...',
      color = _purple;

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ListTile(
          contentPadding: const EdgeInsets.all(18),
          leading: Icon(icon, color: color, size: 34),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: _darkText,
            ),
          ),
          subtitle: Text(
            message,
            style: const TextStyle(color: _grayText, height: 1.3),
          ),
        ),
      ),
    );
  }
}

class DashboardInfoCard extends StatelessWidget {
  const DashboardInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: _purple, size: 34),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, color: _darkText),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: _grayText, height: 1.3),
        ),
      ),
    );
  }
}

class DashboardMiniCard extends StatelessWidget {
  const DashboardMiniCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _grayText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _darkText,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

