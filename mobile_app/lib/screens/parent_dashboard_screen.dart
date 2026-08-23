import 'dart:async';

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
import 'alerts_reports_screen.dart';
import 'device_pairing_screen.dart';
import 'login_screen.dart';
import 'parent_location_screen.dart';
import 'rule_settings_screen.dart';
import 'usage_summary_screen.dart';

const Color _purple = Color(0xFF5B2BBF);
const Color _darkText = Color(0xFF111827);
const Color _grayText = Color(0xFF4B5563);
const Color _softPurple = Color(0xFFF4F0FF);
const Color _softGray = Color(0xFFF9FAFB);

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

  final FirestoreUsagePeriodSummaryService _periodSummaryService =
      FirestoreUsagePeriodSummaryService();

  late Future<UsageDashboardControllerState> _dashboardFuture;

  late Future<FirestoreChildUsageReportSnapshot?> _latestChildReportFuture;

  late Future<UsagePeriodSummaryBundle> _periodSummaryFuture;

  @override
  void initState() {
    super.initState();

    _dashboardFuture = _controllerService.loadTodayDashboardState();

    _latestChildReportFuture = _childUsageReportService
        .getLatestReportForCurrentParent();

    _periodSummaryFuture = _periodSummaryService.getCurrentPeriodSummaries();

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

      _periodSummaryFuture = _periodSummaryService.getCurrentPeriodSummaries();
    });

    await Future.wait<Object?>([
      _dashboardFuture,
      _latestChildReportFuture,
      _periodSummaryFuture,
    ]);
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

  void _openUsageSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UsageSummaryScreen()),
    );
  }

  void _openRules() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RuleSettingsScreen()),
    );
  }

  void _openLocation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ParentLocationScreen()),
    );
  }

  Future<void> _sendMessageToChild(Map<String, dynamic> childData) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please log in again before sending a message.');
      return;
    }

    final childUserId = childData['childUserId'] as String?;
    final childId = childData['childId'] as String?;
    final childName =
        childData['name'] as String? ??
        childData['childEmail'] as String? ??
        'Child';

    if (childUserId == null || childUserId.isEmpty) {
      _showMessage('This child device is not linked to a child account yet.');
      return;
    }

    final message = await showDialog<String>(
      context: context,
      builder: (_) => ParentMessageDialog(childName: childName),
    );

    if (message == null || message.trim().isEmpty) {
      return;
    }

    try {
      await NotificationService.instance.createInAppAlert(
        recipientUserId: childUserId,
        parentId: user.uid,
        childId: childId,
        title: 'Message from Parent',
        message: message.trim(),
        triggerType: 'parent_contact_child',
        priority: 'medium',
        extraData: {
          'parentUserId': user.uid,
          'parentEmail': user.email,
          'childUserId': childUserId,
        },
      );

      _showMessage('Message sent to $childName.');
    } catch (e) {
      _showMessage(
        'Unable to send message: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleBottomNavigation(int index) {
    switch (index) {
      case 0:
        break;

      case 1:
        _openDevices();
        break;

      case 2:
        _openReports();
        break;

      case 3:
        _openRules();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final email = user?.email ?? 'Parent account';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                'assets/icons/wellscreen_icon.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'WellScreen',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ],
        ),
        actions: [
          if (user != null)
            UnreadNotificationBadgeButton(
              userId: user.uid,
              tooltip: 'Notifications and Reports',
              onPressed: _openReports,
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
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
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              children: [
                const Text(
                  'Parent Dashboard',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    color: _darkText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Monitor your connected child devices, screen time, usage patterns, reports, rules, and location updates.',
                  style: TextStyle(color: _grayText, height: 1.4),
                ),
                const SizedBox(height: 24),

                ParentChildDeviceOverview(
                  parentId: user?.uid,
                  usageStatusText: _getDeviceStatusText(viewModel),
                  hasUsagePermission: viewModel?.hasUsagePermission == true,
                  onViewLocation: _openLocation,
                  onViewRules: _openRules,
                  onManageDevices: _openDevices,
                  onMessageChild: _sendMessageToChild,
                ),

                const SizedBox(height: 18),

                ParentEmergencyRequestsSection(
                  onMessageChild: _sendMessageToChild,
                ),

                const SizedBox(height: 18),

                SyncedChildDashboardSection(
                  latestReportFuture: _latestChildReportFuture,
                  onOpenUsageSummary: _openUsageSummary,
                  onOpenReports: _openReports,
                ),

                const SizedBox(height: 18),

                WeeklyTrendSection(
                  periodSummaryFuture: _periodSummaryFuture,
                  onViewFullSummary: _openUsageSummary,
                ),

                const SizedBox(height: 18),

                QuickActionsSection(
                  onDevices: _openDevices,
                  onReports: _openReports,
                  onLocation: _openLocation,
                  onRules: _openRules,
                ),

                const SizedBox(height: 18),

                Card(
                  elevation: 0,
                  color: _softGray,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: const Icon(
                      Icons.developer_mode_rounded,
                      color: _purple,
                    ),
                    title: const Text(
                      'Local Parent Diagnostics',
                      style: TextStyle(
                        color: _darkText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: const Text(
                      'Development-only local device information',
                      style: TextStyle(color: _grayText),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    children: [
                      if (isLoading) const DashboardStatusCard.loading(),

                      if (snapshot.hasError)
                        const DashboardStatusCard(
                          icon: Icons.error_outline_rounded,
                          title: 'Local Dashboard Unavailable',
                          message: 'Unable to load local usage diagnostics.',
                          color: Colors.red,
                        ),

                      if (viewModel?.errorMessage != null)
                        DashboardStatusCard(
                          icon: Icons.info_outline_rounded,
                          title: viewModel?.isUsingCachedData == true
                              ? 'Cached Local Report'
                              : 'Local Action Needed',
                          message: viewModel!.errorMessage!,
                          color: viewModel.isUsingCachedData
                              ? Colors.orange
                              : Colors.red,
                        ),

                      Row(
                        children: [
                          Expanded(
                            child: DashboardMiniCard(
                              icon: Icons.timer_rounded,
                              title: 'Local Screen Time',
                              value: viewModel?.totalUsageLabel ?? '0s',
                              color: _purple,
                              onTap: _openUsageSummary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DashboardMiniCard(
                              icon: Icons.warning_amber_rounded,
                              title: 'Local Status',
                              value: viewModel?.statusLabel ?? 'No Report',
                              color: _getStatusColor(viewModel?.statusLabel),
                              onTap: _openReports,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      DashboardInfoCard(
                        icon: Icons.apps_rounded,
                        title: 'Local Most Used App',
                        subtitle:
                            viewModel?.topUsedAppLabel ??
                            'No app usage recorded.',
                      ),

                      const SizedBox(height: 10),

                      DashboardInfoCard(
                        icon: Icons.lightbulb_rounded,
                        title: 'Local Recommendation',
                        subtitle:
                            viewModel?.recommendationMessage ??
                            'No local usage report is available yet.',
                      ),

                      const SizedBox(height: 10),

                      DashboardInfoCard(
                        icon: Icons.health_and_safety_rounded,
                        title:
                            viewModel?.interventionTitle ??
                            'No Intervention Available',
                        subtitle:
                            viewModel?.interventionMessage ??
                            'Generate a usage report first to receive a recommendation.',
                      ),

                      const SizedBox(height: 10),

                      DashboardInfoCard(
                        icon: Icons.flag_rounded,
                        title: 'Daily Screen-Time Goal',
                        subtitle: _getGoalSummary(state),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openDevices,
                        style: FilledButton.styleFrom(
                          backgroundColor: _purple,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text(
                          'Manage Devices',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openRules,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.rule_rounded),
                        label: const Text(
                          'Rules',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: _handleBottomNavigation,
        backgroundColor: Colors.white,
        indicatorColor: _softPurple,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: _purple),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.phone_android_outlined),
            selectedIcon: Icon(Icons.phone_android_rounded, color: _purple),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded, color: _purple),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: _purple),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  String _getDeviceStatusText(UsageDashboardViewModel? viewModel) {
    if (viewModel == null) {
      return 'No local usage status available';
    }

    if (!viewModel.hasUsagePermission) {
      return 'Local usage access not enabled';
    }

    if (viewModel.isUsingCachedData) {
      return 'Showing cached local usage data';
    }

    return 'Local usage access connected';
  }

  String _getGoalSummary(UsageDashboardControllerState? state) {
    if (state == null) {
      return 'Loading daily screen-time goal...';
    }

    final goalResult = state.screenTimeGoalResult;

    final dailyLimitLabel = _formatDuration(state.dailyScreenTimeLimit);

    if (goalResult == null) {
      return 'Daily limit: $dailyLimitLabel. '
          'Generate a usage report to evaluate today\'s progress.';
    }

    return 'Limit: ${_formatDuration(goalResult.dailyLimit)}'
        ' - Used: ${_formatDuration(goalResult.usedDuration)}'
        ' - Remaining: ${_formatDuration(goalResult.remainingDuration)}'
        '\n${goalResult.message}';
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

class ParentMessageDialog extends StatefulWidget {
  const ParentMessageDialog({super.key, required this.childName});

  final String childName;

  @override
  State<ParentMessageDialog> createState() => _ParentMessageDialogState();
}

class _ParentMessageDialogState extends State<ParentMessageDialog> {
  final TextEditingController _controller = TextEditingController();

  static const List<String> _quickMessages = [
    'Please take a short break from your phone.',
    'Please call me when you can.',
    'Dinner is ready.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectQuickMessage(String message) {
    setState(() {
      _controller.text = message;
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
        'Message ${widget.childName}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send a message that will appear in the child notification panel.',
              style: TextStyle(color: _grayText, height: 1.35),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickMessages
                  .map(
                    (message) => ActionChip(
                      label: Text(message),
                      onPressed: () => _selectQuickMessage(message),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Message',
                hintText: 'Write a message...',
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
        FilledButton.icon(
          onPressed: _send,
          style: FilledButton.styleFrom(backgroundColor: _purple),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Send'),
        ),
      ],
    );
  }
}

class ParentEmergencyRequestsSection extends StatelessWidget {
  const ParentEmergencyRequestsSection({
    super.key,
    required this.onMessageChild,
  });

  final ValueChanged<Map<String, dynamic>> onMessageChild;

  String _formatDurationMinutes(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }

    return '$minutes minutes';
  }

  Future<int?> _chooseApprovalDuration(
    BuildContext context, {
    required int requestedMinutes,
  }) async {
    int selectedMinutes = requestedMinutes.clamp(1, 180);

    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            const options = [5, 10, 15, 30, 60];

            return AlertDialog(
              title: const Text(
                'Approve Emergency Access',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Child requested ${_formatDurationMinutes(requestedMinutes)}.',
                      style: const TextStyle(
                        color: _grayText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Choose how much time you want to approve:',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: options.map((minutes) {
                        return ChoiceChip(
                          label: Text(_formatDurationMinutes(minutes)),
                          selected: selectedMinutes == minutes,
                          onSelected: (_) {
                            setDialogState(() {
                              selectedMinutes = minutes;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: '$selectedMinutes',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Custom minutes',
                        helperText: '1 to 180 minutes',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 1 && parsed <= 180) {
                          selectedMinutes = parsed;
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(selectedMinutes);
                  },
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Approve'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _respondToRequest({
    required BuildContext context,
    required DocumentSnapshot<Map<String, dynamic>> document,
    required bool approve,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final data = document.data();

    if (user == null || data == null) {
      return;
    }

    final childUserId = data['childUserId'] as String?;
    final childId = data['childId'] as String?;
    final childLabel =
        data['childEmail'] as String? ?? data['name'] as String? ?? 'Child';

    if (childUserId == null || childUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Child account information is missing.')),
      );
      return;
    }

    try {
      if (approve) {
        final requestedMinutesValue = data['requestedDurationMinutes'];
        final requestedMinutes = requestedMinutesValue is num
            ? requestedMinutesValue.toInt()
            : 15;

        final approvedMinutes = await _chooseApprovalDuration(
          context,
          requestedMinutes: requestedMinutes,
        );

        if (approvedMinutes == null) {
          return;
        }

        final approvedUntil = DateTime.now().add(
          Duration(minutes: approvedMinutes),
        );

        await document.reference.set({
          'status': 'approved',
          'approvedDurationMinutes': approvedMinutes,
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedUntil': Timestamp.fromDate(approvedUntil),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await NotificationService.instance.createInAppAlert(
          recipientUserId: childUserId,
          parentId: user.uid,
          childId: childId,
          title: 'Emergency Access Approved',
          message:
              'Your parent approved temporary emergency access for '
              '${_formatDurationMinutes(approvedMinutes)}.',
          triggerType: 'emergency_access_approved',
          priority: 'high',
          extraData: {
            'childUserId': childUserId,
            'approvedDurationMinutes': approvedMinutes,
            'approvedUntil': Timestamp.fromDate(approvedUntil),
          },
        );
      } else {
        await document.reference.set({
          'status': 'denied',
          'deniedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await NotificationService.instance.createInAppAlert(
          recipientUserId: childUserId,
          parentId: user.uid,
          childId: childId,
          title: 'Emergency Access Denied',
          message: 'Your parent did not approve the emergency access request.',
          triggerType: 'emergency_access_denied',
          priority: 'high',
          extraData: {'childUserId': childUserId},
        );
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Emergency access approved for $childLabel.'
                : 'Emergency access request denied.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to respond: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  String _formatRequestTime(Object? value) {
    if (value is! Timestamp) {
      return 'Time unavailable';
    }

    final date = value.toDate();
    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('emergency_access_requests')
          .where('parentId', isEqualTo: user.uid)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DashboardStatusCard(
            icon: Icons.emergency_rounded,
            title: 'Emergency Requests',
            message: 'Checking emergency access requests...',
            color: _purple,
          );
        }

        if (snapshot.hasError) {
          return DashboardStatusCard(
            icon: Icons.error_outline_rounded,
            title: 'Emergency Requests Unavailable',
            message: snapshot.error.toString(),
            color: Colors.red,
          );
        }

        final pendingDocs = [...?snapshot.data?.docs]
            .where(
              (doc) => (doc.data()['status'] as String? ?? '') == 'pending',
            )
            .toList();

        pendingDocs.sort((a, b) {
          final aTime = a.data()['requestedAt'];
          final bTime = b.data()['requestedAt'];

          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }

          return 0;
        });

        if (pendingDocs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No pending emergency access requests.',
                    style: TextStyle(
                      color: _darkText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Emergency Requests',
              subtitle:
                  '${pendingDocs.length} request${pendingDocs.length == 1 ? '' : 's'} waiting for your response.',
            ),
            const SizedBox(height: 10),
            ...pendingDocs.map((doc) {
              final data = doc.data();
              final childLabel =
                  data['childEmail'] as String? ?? 'Child device';
              final reason = data['reason'] as String? ?? 'No reason provided.';

              final requestedDurationValue = data['requestedDurationMinutes'];

              final requestedDurationMinutes = requestedDurationValue is num
                  ? requestedDurationValue.toInt()
                  : 15;

              return Card(
                elevation: 1.5,
                shadowColor: Colors.black12,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Colors.orange.withAlpha(89)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.emergency_rounded,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  childLabel,
                                  style: const TextStyle(
                                    color: _darkText,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Requested ${_formatRequestTime(data['requestedAt'])}',
                                  style: const TextStyle(
                                    color: _grayText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const _StatusPill(
                            label: 'Pending',
                            color: Colors.orange,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        reason,
                        style: const TextStyle(
                          color: _darkText,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Requested duration: '
                        '${_formatDurationMinutes(requestedDurationMinutes)}',
                        style: const TextStyle(
                          color: _purple,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _respondToRequest(
                                context: context,
                                document: doc,
                                approve: true,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Review & Approve'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _respondToRequest(
                                context: context,
                                document: doc,
                                approve: false,
                              ),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Deny'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => onMessageChild(data),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          label: const Text(
                            'Send Message to Child',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _darkText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: _grayText,
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),

        ?trailing,
      ],
    );
  }
}

class ParentChildDeviceOverview extends StatelessWidget {
  const ParentChildDeviceOverview({
    super.key,
    required this.parentId,
    required this.usageStatusText,
    required this.hasUsagePermission,
    required this.onViewLocation,
    required this.onViewRules,
    required this.onManageDevices,
    required this.onMessageChild,
  });

  final String? parentId;
  final String usageStatusText;
  final bool hasUsagePermission;
  final VoidCallback onViewLocation;
  final VoidCallback onViewRules;
  final VoidCallback onManageDevices;
  final ValueChanged<Map<String, dynamic>> onMessageChild;

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
            message: 'Checking connected child profiles...',
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardStatusCard(
                icon: Icons.link_off_rounded,
                title: 'No Child Device Connected',
                message:
                    'Add a child device to begin monitoring usage activity.',
                color: Colors.orange,
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onManageDevices,
                  style: FilledButton.styleFrom(backgroundColor: _purple),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Add Child Device',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Children',
              subtitle:
                  '${docs.length} child profile${docs.length == 1 ? '' : 's'} connected to this parent account.',
              trailing: TextButton(
                onPressed: onManageDevices,
                child: const Text(
                  'Manage',
                  style: TextStyle(color: _purple, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...docs.map(
              (doc) => ChildDeviceOverviewCard(
                data: doc.data(),
                usageStatusText: usageStatusText,
                hasUsagePermission: hasUsagePermission,
                onViewLocation: onViewLocation,
                onViewRules: onViewRules,
                onManageDevices: onManageDevices,
                onMessageChild: onMessageChild,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ChildDeviceOverviewCard extends StatelessWidget {
  const ChildDeviceOverviewCard({
    super.key,
    required this.data,
    required this.usageStatusText,
    required this.hasUsagePermission,
    required this.onViewLocation,
    required this.onViewRules,
    required this.onManageDevices,
    required this.onMessageChild,
  });

  final Map<String, dynamic> data;
  final String usageStatusText;
  final bool hasUsagePermission;
  final VoidCallback onViewLocation;
  final VoidCallback onViewRules;
  final VoidCallback onManageDevices;
  final ValueChanged<Map<String, dynamic>> onMessageChild;

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Child Profile';
    final ageValue = data['age'];
    final age = ageValue is num ? ageValue.toInt() : 0;
    final pairingStatus = data['pairingStatus'] as String? ?? 'waiting';
    final deviceStatus = data['deviceStatus'] as String? ?? 'not_connected';
    final childEmail = data['childEmail'] as String?;
    final childUserId = data['childUserId'] as String?;
    final deviceName = data['deviceName'] as String?;
    final lastReportDate = data['lastUsageReportDate'] as String?;

    final isConnected =
        pairingStatus == 'paired' || deviceStatus == 'connected';

    final canMessage =
        isConnected && childUserId != null && childUserId.isNotEmpty;

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _softPurple,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: isConnected ? Colors.green : _purple,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: _darkText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (age > 0) 'Age $age',
                          deviceName ?? 'Android Device',
                        ].join(' - '),
                        style: const TextStyle(color: _grayText),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 9,
                            color: isConnected ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isConnected ? 'Connected' : 'Waiting for Pairing',
                            style: TextStyle(
                              color: isConnected ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Device Details',
                  onPressed: onManageDevices,
                  icon: const Icon(Icons.chevron_right_rounded, color: _purple),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _softGray,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  CompactDeviceDetailRow(
                    icon: Icons.email_outlined,
                    label: 'Child account',
                    value: childEmail ?? 'Not linked yet',
                  ),
                  CompactDeviceDetailRow(
                    icon: Icons.sync_rounded,
                    label: 'Last usage sync',
                    value: lastReportDate ?? 'No report yet',
                  ),
                  CompactDeviceDetailRow(
                    icon: Icons.monitor_heart_outlined,
                    label: 'Monitoring',
                    value: isConnected
                        ? 'Connected'
                        : 'Waiting for device connection',
                    isLast: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canMessage ? () => onMessageChild(data) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(
                  canMessage ? 'Message $name' : 'Child account not linked',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isConnected ? onViewLocation : null,
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Location'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewRules,
                    icon: const Icon(Icons.rule_rounded),
                    label: const Text('Rules'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CompactDeviceDetailRow extends StatelessWidget {
  const CompactDeviceDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _purple),
          const SizedBox(width: 9),
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: _grayText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _darkText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SyncedChildDashboardSection extends StatelessWidget {
  const SyncedChildDashboardSection({
    super.key,
    required this.latestReportFuture,
    required this.onOpenUsageSummary,
    required this.onOpenReports,
  });

  final Future<FirestoreChildUsageReportSnapshot?> latestReportFuture;

  final VoidCallback onOpenUsageSummary;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirestoreChildUsageReportSnapshot?>(
      future: latestReportFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DashboardStatusCard(
            icon: Icons.hourglass_top_rounded,
            title: 'Loading Child Usage',
            message: 'Checking the latest synchronized child usage report...',
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
                'Ask the child device to enable Usage Access and tap Sync Usage Report.',
            color: Colors.orange,
          );
        }

        final report = reportSnapshot.report;

        final riskLabel = _riskLabel(report.riskScore);

        final riskColor = _riskColor(report.riskScore);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Today\'s Overview',
              subtitle:
                  '${reportSnapshot.childLabel} - Report ${reportSnapshot.reportDate}',
              trailing: TextButton(
                onPressed: onOpenUsageSummary,
                child: const Text(
                  'View All',
                  style: TextStyle(color: _purple, fontWeight: FontWeight.w800),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DashboardMetricCard(
                    icon: Icons.timer_rounded,
                    label: 'Screen Time Today',
                    value: report.totalUsageLabel,
                    color: _purple,
                    onTap: onOpenUsageSummary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DashboardMetricCard(
                    icon: Icons.health_and_safety_rounded,
                    label: 'Risk Level',
                    value: '$riskLabel\n${report.riskScore}/100',
                    color: riskColor,
                    onTap: onOpenReports,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            TopAppsTodayCard(
              apps: reportSnapshot.appUsageList,
              onViewAll: onOpenUsageSummary,
            ),

            const SizedBox(height: 14),

            DashboardInfoCard(
              icon: Icons.insights_rounded,
              title: 'Detected Usage Pattern',
              subtitle:
                  '${report.patternStatus.label} - Risk Score ${report.riskScore}/100',
            ),

            const SizedBox(height: 12),

            DashboardInfoCard(
              icon: Icons.lightbulb_rounded,
              title: 'Recommendation',
              subtitle: report.recommendationMessage,
            ),
          ],
        );
      },
    );
  }

  static String _riskLabel(int riskScore) {
    if (riskScore >= 60) {
      return 'High Risk';
    }

    if (riskScore >= 30) {
      return 'Moderate';
    }

    return 'Low Risk';
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
}

class DashboardMetricCard extends StatelessWidget {
  const DashboardMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _grayText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _darkText,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TopAppsTodayCard extends StatelessWidget {
  const TopAppsTodayCard({
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

    final maxDuration = visibleApps.isEmpty
        ? 1
        : visibleApps.first.usageDuration.inSeconds;

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Top Apps Today',
                    style: TextStyle(
                      color: _darkText,
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
                      color: _purple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            if (visibleApps.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No synchronized app usage is available yet.',
                  style: TextStyle(color: _grayText),
                ),
              )
            else
              ...visibleApps.map((app) {
                final seconds = app.usageDuration.inSeconds;

                final progress = maxDuration <= 0
                    ? 0.0
                    : (seconds / maxDuration).clamp(0.0, 1.0).toDouble();

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.apps_rounded,
                            color: _purple,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              app.displayName,
                              style: const TextStyle(
                                color: _darkText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            app.usageLabel,
                            style: const TextStyle(
                              color: _grayText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: progress,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _purple,
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

class WeeklyTrendSection extends StatelessWidget {
  const WeeklyTrendSection({
    super.key,
    required this.periodSummaryFuture,
    required this.onViewFullSummary,
  });

  final Future<UsagePeriodSummaryBundle> periodSummaryFuture;

  final VoidCallback onViewFullSummary;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsagePeriodSummaryBundle>(
      future: periodSummaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const DashboardStatusCard(
            icon: Icons.bar_chart_rounded,
            title: 'Loading Weekly Trend',
            message: 'Checking synchronized daily reports for this week...',
            color: _purple,
          );
        }

        if (snapshot.hasError) {
          return DashboardStatusCard(
            icon: Icons.info_outline_rounded,
            title: 'Weekly Trend Unavailable',
            message: snapshot.error.toString(),
            color: Colors.orange,
          );
        }

        final bundle = snapshot.data;

        if (bundle == null) {
          return const DashboardStatusCard(
            icon: Icons.bar_chart_rounded,
            title: 'No Weekly Trend Yet',
            message:
                'Weekly usage will appear after daily child reports are synchronized.',
            color: Colors.orange,
          );
        }

        return WeeklyTrendCard(
          summary: bundle.weeklySummary,
          onViewFullSummary: onViewFullSummary,
        );
      },
    );
  }
}

class WeeklyTrendCard extends StatelessWidget {
  const WeeklyTrendCard({
    super.key,
    required this.summary,
    required this.onViewFullSummary,
  });

  final UsagePeriodSummary summary;
  final VoidCallback onViewFullSummary;

  @override
  Widget build(BuildContext context) {
    final points = summary.chartPoints;

    final maxHours = summary.maxChartHours <= 0 ? 1.0 : summary.maxChartHours;

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Weekly Trend',
                    style: TextStyle(
                      color: _darkText,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onViewFullSummary,
                  child: const Text(
                    'View Report',
                    style: TextStyle(
                      color: _purple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            Text(
              summary.dateRangeLabel,
              style: const TextStyle(color: _grayText, fontSize: 12),
            ),

            const SizedBox(height: 18),

            if (points.isEmpty || !summary.hasChartPoints)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    'Weekly activity will appear after synchronized daily usage reports are available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _grayText, height: 1.4),
                  ),
                ),
              )
            else
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: points.map((point) {
                    final factor = (point.usageHours / maxHours)
                        .clamp(0.03, 1.0)
                        .toDouble();

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
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
                                        top: Radius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              point.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _grayText,
                                fontSize: 10,
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

            const SizedBox(height: 12),

            Text(
              summary.chartInsightMessage,
              style: const TextStyle(
                color: _grayText,
                height: 1.35,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _trendColor(UsagePatternStatus status) {
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

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    super.key,
    required this.onDevices,
    required this.onReports,
    required this.onLocation,
    required this.onRules,
  });

  final VoidCallback onDevices;
  final VoidCallback onReports;
  final VoidCallback onLocation;
  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Quick Actions'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: QuickActionCard(
                icon: Icons.phone_android_rounded,
                label: 'Devices',
                onTap: onDevices,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: QuickActionCard(
                icon: Icons.analytics_rounded,
                label: 'Reports',
                onTap: onReports,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: QuickActionCard(
                icon: Icons.location_on_rounded,
                label: 'Location',
                onTap: onLocation,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: QuickActionCard(
                icon: Icons.rule_rounded,
                label: 'Rules',
                onTap: onRules,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _softPurple,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: _purple, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _darkText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      message = 'Preparing today\'s local usage report...',
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

class UnreadNotificationBadgeButton extends StatelessWidget {
  const UnreadNotificationBadgeButton({
    super.key,
    required this.userId,
    required this.onPressed,
    required this.tooltip,
  });

  final String userId;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('in_app_alerts')
          .where('recipientUserId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount =
            snapshot.data?.docs.where((doc) {
              return doc.data()['isRead'] != true;
            }).length ??
            0;

        return IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded),
              if (unreadCount > 0)
                Positioned(
                  top: -8,
                  right: -9,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 19,
                      minHeight: 19,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
