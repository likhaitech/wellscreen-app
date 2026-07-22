import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/accessibility_service_status_service.dart';
import '../services/firestore_usage_report_sync_service.dart';
import '../services/native_restriction_rules_service.dart';
import '../services/usage_tracking_service.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

  final TextEditingController pairingCodeController = TextEditingController();

  final FirestoreUsageReportSyncService _usageReportSyncService =
      FirestoreUsageReportSyncService();
  final UsageTrackingService _usageTrackingService = UsageTrackingService();
  final AccessibilityServiceStatusService _accessibilityStatusService =
      AccessibilityServiceStatusService();

  bool isPairing = false;
  bool isSyncingUsageReport = false;
  String? lastSyncStatusMessage;

  // Usage-access permission status.
  bool? hasUsageAccess;
  bool isCheckingUsageAccess = false;

  // Accessibility service status.
  bool? hasAccessibilityAccess;
  bool isCheckingAccessibilityAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUsagePermission();
    _checkAccessibilityPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pairingCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkUsagePermission();
      _checkAccessibilityPermission();
    }
  }

  Future<void> _checkUsagePermission() async {
    setState(() => isCheckingUsageAccess = true);

    try {
      final granted = await _usageTrackingService.hasUsagePermission();

      if (!mounted) return;

      setState(() {
        hasUsageAccess = granted;
        isCheckingUsageAccess = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => isCheckingUsageAccess = false);
    }
  }

  Future<void> _checkAccessibilityPermission() async {
    setState(() => isCheckingAccessibilityAccess = true);

    try {
      final granted = await _accessibilityStatusService
          .isAccessibilityServiceEnabled();

      if (!mounted) return;

      setState(() {
        hasAccessibilityAccess = granted;
        isCheckingAccessibilityAccess = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => isCheckingAccessibilityAccess = false);
    }
  }

  Future<void> pairChildDevice() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again before pairing.');
      return;
    }

    final code = pairingCodeController.text.trim();

    if (code.length != 6) {
      showMessage('Please enter a valid 6-digit pairing code.');
      return;
    }

    setState(() => isPairing = true);

    try {
      final pairingRef = FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final pairingSnapshot = await transaction.get(pairingRef);

        if (!pairingSnapshot.exists) {
          throw Exception('Invalid pairing code.');
        }

        final data = pairingSnapshot.data();

        if (data == null) {
          throw Exception('Pairing code data is missing.');
        }

        final status = data['status'] as String? ?? 'inactive';
        final isPaired = data['isPaired'] as bool? ?? false;
        final expiresAt = data['expiresAt'];

        if (status != 'active') {
          throw Exception('This pairing code is no longer active.');
        }

        if (isPaired) {
          throw Exception('This pairing code is already paired.');
        }

        if (expiresAt is Timestamp &&
            expiresAt.toDate().isBefore(DateTime.now())) {
          throw Exception('This pairing code has expired.');
        }

        final childId = data['childId'] as String?;
        final parentId = data['parentId'] as String?;

        if (childId == null || parentId == null) {
          throw Exception('Pairing record is incomplete.');
        }

        final childProfileRef = FirebaseFirestore.instance
            .collection('child_profiles')
            .doc(childId);

        final childDeviceRef = FirebaseFirestore.instance
            .collection('child_devices')
            .doc(user.uid);

        transaction.set(pairingRef, {
          'status': 'paired',
          'isPaired': true,
          'childUserId': user.uid,
          'childEmail': user.email,
          'deviceName': 'Android Child Device',
          'pairedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childProfileRef, {
          'childId': childId,
          'parentId': parentId,
          'childUserId': user.uid,
          'childEmail': user.email,
          'pairingCode': code,
          'pairingStatus': 'paired',
          'deviceStatus': 'connected',
          'deviceName': 'Android Child Device',
          'pairedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childDeviceRef, {
          'childUserId': user.uid,
          'childEmail': user.email,
          'parentId': parentId,
          'childId': childId,
          'pairingCode': code,
          'deviceName': 'Android Child Device',
          'deviceStatus': 'connected',
          'pairingStatus': 'paired',
          'lastOpenedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      pairingCodeController.clear();
      showMessage('Device paired successfully.');
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => isPairing = false);
      }
    }
  }

  Future<void> syncTodayUsageReport() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again before syncing usage reports.');
      return;
    }

    setState(() {
      isSyncingUsageReport = true;
      lastSyncStatusMessage = 'Syncing todayâ€™s usage report...';
    });

    try {
      final result = await _usageReportSyncService.syncTodayUsageReport();

      final message =
          'Usage report synced: ${result.report.totalUsageLabel} for ${result.reportDate}.';

      if (!mounted) return;

      setState(() {
        lastSyncStatusMessage = '$message\nSaved to: ${result.reportPath}';
      });

      showMessage(message);
    } catch (e) {
      final message = _cleanErrorMessage(e);

      if (!mounted) return;

      setState(() {
        lastSyncStatusMessage = message;
      });

      showMessage(message);
    } finally {
      if (mounted) {
        setState(() => isSyncingUsageReport = false);
      }
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await _usageTrackingService.openUsageAccessSettings();
      showMessage('Enable Usage Access for WellScreen, then return to sync.');
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _accessibilityStatusService.openAccessibilitySettings();
      showMessage(
        'Enable WellScreen under Accessibility settings, then return to this screen.',
      );
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
    }
  }

  String _cleanErrorMessage(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildDeviceAndRulesSection(String childUserId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_devices')
          .doc(childUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ChildStatusCard(
            icon: Icons.hourglass_top_rounded,
            iconColor: purple,
            title: 'Checking pairing status',
            subtitle: 'Preparing child device information...',
          );
        }

        if (snapshot.hasError) {
          return ChildStatusCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'Unable to load device status',
            subtitle: snapshot.error.toString(),
          );
        }

        final data = snapshot.data?.data();

        if (data == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ChildStatusCard(
                icon: Icons.link_off_rounded,
                iconColor: Colors.orange,
                title: 'Not paired yet',
                subtitle:
                    'Enter the parent pairing code above to connect this device.',
              ),
              SizedBox(height: 16),
              Text(
                'Parent Rules',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                ),
              ),
              SizedBox(height: 12),
              ChildStatusCard(
                icon: Icons.rule_rounded,
                iconColor: Colors.orange,
                title: 'No parent rules available',
                subtitle:
                    'Pair this device first so the parentâ€™s saved restrictions can appear here.',
              ),
            ],
          );
        }

        final pairingStatus = data['pairingStatus'] as String? ?? 'waiting';
        final deviceStatus = data['deviceStatus'] as String? ?? 'not_connected';
        final childEmail = data['childEmail'] as String? ?? 'Child user';
        final code = data['pairingCode'] as String? ?? 'No code';
        final parentId = data['parentId'] as String?;
        final childId = data['childId'] as String?;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChildStatusCard(
              icon: Icons.check_circle_rounded,
              iconColor: Colors.green,
              title: 'Connected to Parent Account',
              subtitle:
                  'Account: $childEmail\nPairing: ${_formatStatus(pairingStatus)}\nDevice: ${_formatStatus(deviceStatus)}\nCode: $code',
            ),
            const SizedBox(height: 16),
            const Text(
              'Parent Rules',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: darkText,
              ),
            ),
            const SizedBox(height: 12),
            ParentRulesSection(parentId: parentId),
            const SizedBox(height: 16),
            EmergencyAccessRequestSection(
              parentId: parentId,
              childId: childId,
              childEmail: childEmail,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Child Home',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Child Device Setup',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the pairing code from the parent device to connect this monitored Android device.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: softPurple,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.phone_android_rounded,
                  color: purple,
                  size: 72,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pair This Device',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ask your parent or guardian for the 6-digit pairing code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: grayText, height: 1.4),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: pairingCodeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isPairing ? null : pairChildDevice,
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(
                      isPairing ? 'Pairing...' : 'Connect to Parent',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Device Status',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 12),
          if (user == null)
            const ChildStatusCard(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.orange,
              title: 'No child account found',
              subtitle: 'Please log in again before pairing this device.',
            )
          else
            _buildDeviceAndRulesSection(user.uid),
          const SizedBox(height: 16),
          UsageAccessStatusCard(
            hasUsageAccess: hasUsageAccess,
            isChecking: isCheckingUsageAccess,
            onRecheck: _checkUsagePermission,
            onOpenSettings: openUsageAccessSettings,
          ),
          const SizedBox(height: 16),
          AccessibilityServiceStatusCard(
            hasAccessibilityAccess: hasAccessibilityAccess,
            isChecking: isCheckingAccessibilityAccess,
            onRecheck: _checkAccessibilityPermission,
            onOpenSettings: openAccessibilitySettings,
          ),
          const SizedBox(height: 16),
          UsageSyncCard(
            isSyncing: isSyncingUsageReport,
            lastSyncMessage: lastSyncStatusMessage,
            onSync: user == null ? null : syncTodayUsageReport,
            onOpenUsageAccess: openUsageAccessSettings,
          ),
        ],
      ),
    );
  }

  String _formatStatus(String value) {
    return value.replaceAll('_', ' ').toUpperCase();
  }
}

class UsageAccessStatusCard extends StatelessWidget {
  const UsageAccessStatusCard({
    super.key,
    required this.hasUsageAccess,
    required this.isChecking,
    required this.onRecheck,
    required this.onOpenSettings,
  });

  final bool? hasUsageAccess;
  final bool isChecking;
  final Future<void> Function() onRecheck;
  final Future<void> Function() onOpenSettings;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;

    if (isChecking && hasUsageAccess == null) {
      icon = Icons.hourglass_top_rounded;
      color = purple;
      title = 'Checking Usage Access';
      subtitle = 'Checking whether Usage Access permission is granted...';
    } else if (hasUsageAccess == true) {
      icon = Icons.check_circle_rounded;
      color = Colors.green;
      title = 'Usage Access Granted';
      subtitle =
          'WellScreen can read app usage data needed for monitoring and reports.';
    } else {
      icon = Icons.warning_amber_rounded;
      color = Colors.orange;
      title = 'Usage Access Permission Missing';
      subtitle =
          'WellScreen needs Usage Access permission to track screen time. '
          'Tap "Open Usage Access Settings" below, enable it for WellScreen, '
          'then return to this screen.';
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: grayText, height: 1.4),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Recheck permission',
              icon: isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: isChecking ? null : () => onRecheck(),
            ),
          ],
        ),
      ),
    );
  }
}

class AccessibilityServiceStatusCard extends StatelessWidget {
  const AccessibilityServiceStatusCard({
    super.key,
    required this.hasAccessibilityAccess,
    required this.isChecking,
    required this.onRecheck,
    required this.onOpenSettings,
  });

  final bool? hasAccessibilityAccess;
  final bool isChecking;
  final Future<void> Function() onRecheck;
  final Future<void> Function() onOpenSettings;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;

    if (isChecking && hasAccessibilityAccess == null) {
      icon = Icons.hourglass_top_rounded;
      color = purple;
      title = 'Checking Accessibility Service';
      subtitle =
          'Checking whether the WellScreen Accessibility Service is enabled...';
    } else if (hasAccessibilityAccess == true) {
      icon = Icons.check_circle_rounded;
      color = Colors.green;
      title = 'Accessibility Service Enabled';
      subtitle =
          'WellScreen can prepare app-level enforcement features on this device.';
    } else {
      icon = Icons.warning_amber_rounded;
      color = Colors.orange;
      title = 'Accessibility Service Not Enabled';
      subtitle =
          'Enforcement features (like app blocking and focus mode) require the '
          'WellScreen Accessibility Service. Tap "Open Accessibility Settings" '
          'below, enable WellScreen, then return to this screen.';
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: darkText,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(color: grayText, height: 1.4),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Recheck permission',
                  icon: isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onPressed: isChecking ? null : () => onRecheck(),
                ),
              ],
            ),
            if (hasAccessibilityAccess != true) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onOpenSettings(),
                  icon: const Icon(Icons.settings_accessibility_rounded),
                  label: const Text(
                    'Open Accessibility Settings',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UsageSyncCard extends StatelessWidget {
  const UsageSyncCard({
    super.key,
    required this.isSyncing,
    required this.lastSyncMessage,
    required this.onSync,
    required this.onOpenUsageAccess,
  });

  final bool isSyncing;
  final String? lastSyncMessage;
  final Future<void> Function()? onSync;
  final Future<void> Function() onOpenUsageAccess;

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
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_upload_rounded, color: purple, size: 34),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Usage Report Sync',
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
            Text(
              lastSyncMessage ??
                  'Sync todayâ€™s child-device usage report to the parent account.',
              style: const TextStyle(color: grayText, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSyncing || onSync == null ? null : () => onSync!(),
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  isSyncing ? 'Syncing...' : 'Sync Usage Report',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onOpenUsageAccess(),
                icon: const Icon(Icons.settings_rounded),
                label: const Text(
                  'Open Usage Access Settings',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ParentRulesSection extends StatelessWidget {
  const ParentRulesSection({super.key, required this.parentId});

  final String? parentId;

  static const Color purple = Color(0xFF5B2BBF);

  @override
  Widget build(BuildContext context) {
    if (parentId == null || parentId!.isEmpty) {
      return const ChildStatusCard(
        icon: Icons.rule_rounded,
        iconColor: Colors.orange,
        title: 'Parent rules unavailable',
        subtitle:
            'This device is paired, but the parent account reference is missing.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('restriction_settings')
          .doc(parentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ChildStatusCard(
            icon: Icons.hourglass_top_rounded,
            iconColor: purple,
            title: 'Loading parent rules',
            subtitle: 'Preparing saved restrictions from the parent account...',
          );
        }

        if (snapshot.hasError) {
          return ChildStatusCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'Unable to load parent rules',
            subtitle: snapshot.error.toString(),
          );
        }

        final data = snapshot.data?.data();

        if (data == null) {
          return const ChildStatusCard(
            icon: Icons.rule_rounded,
            iconColor: Colors.orange,
            title: 'No rules saved yet',
            subtitle:
                'Parent rules will appear here after the parent saves restriction settings.',
          );
        }

        final limitMinutesValue = data['limitMinutes'];
        final limitMinutes = limitMinutesValue is num
            ? limitMinutesValue.toInt()
            : 120;

        final appBlocking = _readBool(data, 'appBlocking', true);
        final focusMode = _readBool(data, 'focusMode', true);
        final cooldownTimer = _readBool(data, 'cooldownTimer', true);
        final scheduledLock = _readBool(data, 'scheduledLock', false);
        final categoryRestriction = _readBool(
          data,
          'categoryRestriction',
          true,
        );
        final emergencyAccess = _readBool(data, 'emergencyAccess', true);

        unawaited(
          const NativeRestrictionRulesService()
              .saveRules(
                limitMinutes: limitMinutes,
                appBlocking: appBlocking,
                focusMode: focusMode,
                cooldownTimer: cooldownTimer,
                scheduledLock: scheduledLock,
                categoryRestriction: categoryRestriction,
                emergencyAccess: emergencyAccess,
              )
              .catchError((Object _) {}),
        );

        return Column(
          children: [
            ChildStatusCard(
              icon: Icons.flag_rounded,
              iconColor: purple,
              title: 'Screen Goals',
              subtitle:
                  'Daily screen-time limit: ${_formatMinutes(limitMinutes)}.',
            ),
            ParentRuleCard(
              icon: Icons.block_rounded,
              title: 'App Blocking',
              isEnabled: appBlocking,
              enabledMessage: 'Selected apps may be blocked after limits.',
              disabledMessage: 'App blocking is currently disabled.',
            ),
            ParentRuleCard(
              icon: Icons.school_rounded,
              title: 'Focus Mode',
              isEnabled: focusMode,
              enabledMessage:
                  'Distracting apps may be limited during study or rest time.',
              disabledMessage: 'Focus mode is currently disabled.',
            ),
            ParentRuleCard(
              icon: Icons.notifications_active_rounded,
              title: 'Cooldown Timer',
              isEnabled: cooldownTimer,
              enabledMessage:
                  'Break reminders may appear after long continuous usage.',
              disabledMessage: 'Cooldown reminders are currently disabled.',
            ),
            ParentRuleCard(
              icon: Icons.lock_clock_rounded,
              title: 'Scheduled Lock Session',
              isEnabled: scheduledLock,
              enabledMessage:
                  'Restrictions may apply during selected scheduled sessions.',
              disabledMessage:
                  'Scheduled lock sessions are currently disabled.',
            ),
            ParentRuleCard(
              icon: Icons.category_rounded,
              title: 'Harmful Category Restriction',
              isEnabled: categoryRestriction,
              enabledMessage:
                  'Supported harmful or restricted category events may be limited.',
              disabledMessage: 'Category restriction is currently disabled.',
            ),
            ParentRuleCard(
              icon: Icons.emergency_rounded,
              title: 'Emergency Access',
              isEnabled: emergencyAccess,
              enabledMessage:
                  'Essential functions are allowed during restrictions.',
              disabledMessage:
                  'Emergency access is currently disabled by the parent.',
            ),
          ],
        );
      },
    );
  }

  bool _readBool(Map<String, dynamic> data, String key, bool defaultValue) {
    final value = data[key];

    if (value is bool) {
      return value;
    }

    return defaultValue;
  }

  String _formatMinutes(int minutes) {
    final duration = Duration(minutes: minutes);
    final hours = duration.inHours;
    final remainingMinutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${remainingMinutes}m';
    }

    return '${duration.inMinutes}m';
  }
}

class ParentRuleCard extends StatelessWidget {
  const ParentRuleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.isEnabled,
    required this.enabledMessage,
    required this.disabledMessage,
  });

  final IconData icon;
  final String title;
  final bool isEnabled;
  final String enabledMessage;
  final String disabledMessage;

  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color purple = Color(0xFF5B2BBF);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: isEnabled ? purple : Colors.grey, size: 34),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            isEnabled ? enabledMessage : disabledMessage,
            style: const TextStyle(color: grayText, height: 1.4),
          ),
        ),
        trailing: Icon(
          isEnabled ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isEnabled ? Colors.green : Colors.grey,
        ),
      ),
    );
  }
}



class SmsBackupPermissionSection extends StatefulWidget {
  const SmsBackupPermissionSection({super.key});

  @override
  State<SmsBackupPermissionSection> createState() =>
      _SmsBackupPermissionSectionState();
}

class _SmsBackupPermissionSectionState
    extends State<SmsBackupPermissionSection> {
  bool isChecking = true;
  bool isGranted = false;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  void initState() {
    super.initState();
    checkPermission();
  }

  Future<void> checkPermission() async {
    final granted =
        await const NativeRestrictionRulesService().isSmsPermissionGranted();

    if (!mounted) return;

    setState(() {
      isGranted = granted;
      isChecking = false;
    });
  }

  Future<void> requestPermission() async {
    setState(() => isChecking = true);

    await const NativeRestrictionRulesService().requestSmsPermission();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    await checkPermission();
  }

  @override
  Widget build(BuildContext context) {
    final title = isGranted
        ? 'SMS Backup Alerts Ready'
        : 'SMS Backup Permission Needed';

    final subtitle = isGranted
        ? 'The child device can send SMS backup alerts when critical restriction events occur.'
        : 'Allow SMS permission on this child device so WellScreen can send backup alerts to the guardian phone number. WellScreen does not read SMS messages.';

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sms_rounded,
              color: isGranted ? Colors.green : purple,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: grayText,
                      height: 1.4,
                    ),
                  ),
                  if (!isGranted) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isChecking ? null : requestPermission,
                        style: FilledButton.styleFrom(
                          backgroundColor: purple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.sms_rounded),
                        label: Text(
                          isChecking ? 'Checking...' : 'Allow SMS Backup Alerts',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class EmergencyAccessRequestSection extends StatefulWidget {
  const EmergencyAccessRequestSection({
    super.key,
    required this.parentId,
    required this.childId,
    required this.childEmail,
  });

  final String? parentId;
  final String? childId;
  final String childEmail;

  @override
  State<EmergencyAccessRequestSection> createState() =>
      _EmergencyAccessRequestSectionState();
}

class _EmergencyAccessRequestSectionState
    extends State<EmergencyAccessRequestSection> {
  final TextEditingController reasonController = TextEditingController();

  bool isSubmitting = false;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  Future<void> submitEmergencyRequest() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again before requesting emergency access.');
      return;
    }

    if (widget.parentId == null || widget.parentId!.isEmpty) {
      showMessage('Parent account is missing. Pair the device again.');
      return;
    }

    final reason = reasonController.text.trim();

    if (reason.length < 5) {
      showMessage('Please enter a short reason for emergency access.');
      return;
    }

    setState(() => isSubmitting = true);

    try {
      await FirebaseFirestore.instance
          .collection('emergency_access_requests')
          .doc(user.uid)
          .set({
        'parentId': widget.parentId,
        'childId': widget.childId,
        'childUserId': user.uid,
        'childEmail': widget.childEmail,
        'reason': reason,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      reasonController.clear();
      showMessage('Emergency access request sent to parent.');
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  void syncEmergencyAccessToNative(Map<String, dynamic>? data) {
    if (data == null) {
      unawaited(
        const NativeRestrictionRulesService().saveEmergencyAccessState(
          isApproved: false,
          approvedUntil: null,
        ),
      );
      return;
    }

    final status = data['status'] as String? ?? 'none';
    final approvedUntilValue = data['approvedUntil'];
    final approvedUntil = approvedUntilValue is Timestamp
        ? approvedUntilValue.toDate()
        : null;

    final isApproved = status == 'approved' &&
        approvedUntil != null &&
        approvedUntil.isAfter(DateTime.now());

    unawaited(
      const NativeRestrictionRulesService()
          .saveEmergencyAccessState(
            isApproved: isApproved,
            approvedUntil: approvedUntil,
          )
          .catchError((Object _) {}),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const ChildStatusCard(
        icon: Icons.emergency_rounded,
        iconColor: Colors.orange,
        title: 'Emergency Access Unavailable',
        subtitle: 'Please log in again before requesting emergency access.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('emergency_access_requests')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        syncEmergencyAccessToNative(data);

        final status = data?['status'] as String? ?? 'none';
        final reason = data?['reason'] as String? ?? 'No request submitted yet.';
        final approvedUntilValue = data?['approvedUntil'];
        final approvedUntil = approvedUntilValue is Timestamp
            ? approvedUntilValue.toDate()
            : null;

        final title = switch (status) {
          'pending' => 'Emergency Request Pending',
          'approved' => 'Emergency Access Approved',
          'denied' => 'Emergency Access Denied',
          _ => 'Emergency Access Request',
        };

        final subtitle = switch (status) {
          'pending' =>
            'Your request was sent to the parent account.\nReason: $reason',
          'approved' =>
            'Emergency access is temporarily approved until ${_formatDateTime(approvedUntil)}.\nReason: $reason',
          'denied' =>
            'The parent denied the request. You may send another request if needed.\nReason: $reason',
          _ =>
            'Send a request when you need temporary access for an urgent or essential reason.',
        };

        final iconColor = switch (status) {
          'approved' => Colors.green,
          'pending' => Colors.orange,
          'denied' => Colors.red,
          _ => purple,
        };

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.emergency_rounded, color: iconColor, size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: darkText,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: grayText,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonController,
                  minLines: 1,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason for emergency access',
                    hintText: 'Example: I need to contact my guardian.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isSubmitting ? null : submitEmergencyRequest,
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      isSubmitting ? 'Sending...' : 'Request Emergency Access',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'the approved time';
    }

    final hour = value.hour > 12
        ? value.hour - 12
        : value.hour == 0
            ? 12
            : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }
}
class ChildStatusCard extends StatelessWidget {
  const ChildStatusCard({
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





