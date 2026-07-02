import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/usage_dashboard_view_model_service.dart';
import '../services/usage_dashboard_controller_service.dart';
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

  late Future<UsageDashboardControllerState> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _controllerService.loadTodayDashboardState();
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardFuture = _controllerService.loadTodayDashboardState();
    });

    await _dashboardFuture;
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

                Card(
                  elevation: 3,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          backgroundColor: _softPurple,
                          child: Icon(
                            Icons.child_care_rounded,
                            color: _purple,
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
                              const SizedBox(height: 4),
                              Text(
                                _getDeviceStatusText(viewModel),
                                style: const TextStyle(
                                  color: _grayText,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          viewModel?.hasUsagePermission == true
                              ? Icons.check_circle_rounded
                              : Icons.info_rounded,
                          color: viewModel?.hasUsagePermission == true
                              ? Colors.green
                              : Colors.orange,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: DashboardMiniCard(
                        icon: Icons.timer_rounded,
                        title: 'Screen Time',
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
                        title: 'Status',
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
                  title: 'Most Used App',
                  subtitle:
                      viewModel?.topUsedAppLabel ?? 'No app usage recorded',
                ),

                const SizedBox(height: 12),

                DashboardInfoCard(
                  icon: Icons.lightbulb_rounded,
                  title: 'Recommendation',
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
      return 'Status: Loading child-device usage data';
    }

    if (!viewModel.hasUsagePermission) {
      return 'Status: Usage access permission needed';
    }

    if (viewModel.isUsingCachedData) {
      return 'Status: Showing last cached child-device report';
    }

    return 'Status: Connected to parent account';
  }

  String _getGoalSummary(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading daily screen-time goal...';
    }

    final goalResult = state.screenTimeGoalResult;
    final dailyLimitLabel = _formatDuration(state.dailyScreenTimeLimit);

    if (goalResult == null) {
      return 'Daily limit: $dailyLimitLabel. Generate a usage report to evaluate today’s progress.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)} • Used: ${_formatDuration(goalResult.usedDuration)} • Remaining: ${_formatDuration(goalResult.remainingDuration)}\n${goalResult.message}';
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
      message = 'Preparing today’s usage report...',
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
