import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/accessibility_service_status_service.dart';
import '../services/firestore_usage_report_sync_service.dart';
import '../services/location_tracking_service.dart';
import '../services/native_restriction_rules_service.dart';
import '../services/notification_service.dart';
import '../services/usage_tracking_service.dart';
import 'login_screen.dart';

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

  final LocationTrackingService _locationTrackingService =
      LocationTrackingService();

  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool? _lastKnownNetworkAvailable;

  bool isPairing = false;

  bool isSyncingUsageReport = false;
  String? lastSyncStatusMessage;

  bool _isAutomaticUsageCatchUpRunning = false;

  bool? hasUsageAccess;
  bool isCheckingUsageAccess = false;

  bool? hasAccessibilityAccess;
  bool isCheckingAccessibilityAccess = false;

  LocationPermissionStatus? locationPermissionStatus;
  bool isCheckingLocationPermission = false;

  bool isSyncingLocation = false;
  String? lastLocationSyncMessage;

  int selectedTabIndex = 0;
  bool showRulesPage = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _checkUsagePermission();
    _checkAccessibilityPermission();
    _checkLocationPermission();

    unawaited(_startConnectivityMonitoring());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_attemptAutomaticUsageCatchUp());
    });

    unawaited(
      NotificationService.instance.initializeForCurrentUser(
        contextLabel: 'child_home',
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    pairingCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkUsagePermission();
      _checkAccessibilityPermission();
      _checkLocationPermission();

      unawaited(_attemptAutomaticUsageCatchUp());
    }
  }

  Future<void> _startConnectivityMonitoring() async {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChanged,
    );

    try {
      final initialResults = await _connectivity.checkConnectivity();
      _lastKnownNetworkAvailable = _hasNetworkConnection(initialResults);
    } catch (_) {
      // Connectivity monitoring is only a retry trigger.
      // Startup/resume catch-up still works if this check fails.
    }
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    final networkAvailable = _hasNetworkConnection(results);
    final wasNetworkAvailable = _lastKnownNetworkAvailable;

    _lastKnownNetworkAvailable = networkAvailable;

    if (wasNetworkAvailable == false && networkAvailable) {
      unawaited(_attemptAutomaticUsageCatchUp());
    }
  }

  bool _hasNetworkConnection(List<ConnectivityResult> results) {
    return results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _refreshEverything() async {
    await Future.wait([
      _checkUsagePermission(),
      _checkAccessibilityPermission(),
      _checkLocationPermission(),
    ]);
  }

  Future<void> _checkUsagePermission() async {
    if (mounted) {
      setState(() {
        isCheckingUsageAccess = true;
      });
    }

    try {
      final granted = await _usageTrackingService.hasUsagePermission();

      if (!mounted) return;

      setState(() {
        hasUsageAccess = granted;
        isCheckingUsageAccess = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isCheckingUsageAccess = false;
      });
    }
  }

  Future<void> _checkAccessibilityPermission() async {
    if (mounted) {
      setState(() {
        isCheckingAccessibilityAccess = true;
      });
    }

    try {
      final granted = await _accessibilityStatusService
          .isAccessibilityServiceEnabled();

      if (!mounted) return;

      setState(() {
        hasAccessibilityAccess = granted;
        isCheckingAccessibilityAccess = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isCheckingAccessibilityAccess = false;
      });
    }
  }

  Future<void> _checkLocationPermission() async {
    if (mounted) {
      setState(() {
        isCheckingLocationPermission = true;
      });
    }

    try {
      final status = await _locationTrackingService.checkPermissionStatus();

      if (!mounted) return;

      setState(() {
        locationPermissionStatus = status;
        isCheckingLocationPermission = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isCheckingLocationPermission = false;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    setState(() {
      isCheckingLocationPermission = true;
    });

    try {
      final status = await _locationTrackingService.requestPermission();

      if (!mounted) return;

      setState(() {
        locationPermissionStatus = status;
        isCheckingLocationPermission = false;
      });

      if (status == LocationPermissionStatus.granted) {
        showMessage('Location permission granted.');
      } else if (status == LocationPermissionStatus.serviceDisabled) {
        showMessage('Turn on device location services first.');
      } else {
        showMessage('Location permission is needed for GPS tracking.');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isCheckingLocationPermission = false;
      });

      showMessage(_cleanErrorMessage(e));
    }
  }

  Future<void> _openLocationSettings() async {
    try {
      await _locationTrackingService.openLocationSettings();

      showMessage('Turn on Location, then return to WellScreen.');
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await _usageTrackingService.openUsageAccessSettings();

      showMessage(
        'Enable Usage Access for WellScreen, then return to the app.',
      );
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _accessibilityStatusService.openAccessibilitySettings();

      showMessage(
        'Enable WellScreen under Accessibility settings, then return to the app.',
      );
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
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

    setState(() {
      isPairing = true;
    });

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

        final parentNameValue = data['parentName'];

        final parentName =
            parentNameValue is String && parentNameValue.trim().isNotEmpty
            ? parentNameValue.trim()
            : null;

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
          'parentName': ?parentName,
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
          'parentName': ?parentName,
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
        setState(() {
          isPairing = false;
        });
      }
    }
  }

  Future<void> _attemptAutomaticUsageCatchUp() async {
    if (_isAutomaticUsageCatchUpRunning) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    _isAutomaticUsageCatchUpRunning = true;

    try {
      final result = await _usageReportSyncService
          .syncPendingAndCatchUpUsageReports();

      if (!mounted) {
        return;
      }

      if (result.syncedCount > 0) {
        final latestReport = result.syncedReports.last;

        setState(() {
          lastSyncStatusMessage =
              'Automatic usage sync completed.\n'
              '${result.syncedCount} report'
              '${result.syncedCount == 1 ? '' : 's'} updated.\n'
              'Latest: ${latestReport.reportDate} - '
              '${latestReport.report.totalUsageLabel}';
        });
      }

      if (result.hasPendingDates) {
        setState(() {
          lastSyncStatusMessage =
              '${lastSyncStatusMessage ?? 'Automatic usage sync attempted.'}\n'
              '${result.pendingDates.length} report'
              '${result.pendingDates.length == 1 ? '' : 's'} '
              'still waiting to sync.';
        });
      }
    } catch (_) {
      // Being offline is expected. UsageStats keeps recording locally, and
      // WellScreen will retry when the app starts, resumes, or reconnects.
    } finally {
      _isAutomaticUsageCatchUpRunning = false;
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
      lastSyncStatusMessage = 'Syncing today\'s usage report...';
    });

    try {
      final result = await _usageReportSyncService.syncTodayUsageReport();

      final message =
          'Usage report synced: '
          '${result.report.totalUsageLabel} '
          'for ${result.reportDate}.';

      if (!mounted) return;

      setState(() {
        lastSyncStatusMessage =
            '$message\n'
            'Saved to: ${result.reportPath}';
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
        setState(() {
          isSyncingUsageReport = false;
        });
      }
    }
  }

  Future<void> _syncCurrentLocation() async {
    setState(() {
      isSyncingLocation = true;
      lastLocationSyncMessage = 'Capturing current GPS location...';
    });

    try {
      final result = await _locationTrackingService
          .captureAndSyncCurrentLocation();

      if (!mounted) return;

      setState(() {
        lastLocationSyncMessage =
            'Location synced at '
            '${result.capturedAtLabel}.\n'
            'Coordinates: '
            '${result.coordinateLabel}\n'
            '${result.accuracyLabel}\n'
            '${result.geoFenceLabel}';
      });

      showMessage('Current GPS location synced.');
    } catch (e) {
      final message = _cleanErrorMessage(e);

      if (!mounted) return;

      setState(() {
        lastLocationSyncMessage = message;
      });

      showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          isSyncingLocation = false;
        });
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

  Future<void> _contactParent(Map<String, dynamic> deviceData) async {
    final user = FirebaseAuth.instance.currentUser;

    final parentId = deviceData['parentId'] as String?;
    final childId = deviceData['childId'] as String?;

    final parentNameValue = deviceData['parentName'];

    final parentName =
        parentNameValue is String && parentNameValue.trim().isNotEmpty
        ? parentNameValue.trim()
        : 'Parent';

    if (user == null || parentId == null || parentId.isEmpty) {
      showMessage('Parent account information is unavailable.');
      return;
    }

    final message = await showDialog<String>(
      context: context,
      builder: (_) {
        return ContactParentDialog(parentName: parentName);
      },
    );

    if (message == null || message.trim().isEmpty) {
      return;
    }

    try {
      await NotificationService.instance.createInAppAlert(
        recipientUserId: parentId,
        parentId: parentId,
        childId: childId,
        title: 'Message from Child',
        message: message.trim(),
        triggerType: 'child_contact_parent',
        priority: 'medium',
        extraData: {'childUserId': user.uid, 'childEmail': user.email},
      );

      showMessage('Message sent to $parentName.');
    } catch (e) {
      showMessage('Unable to contact parent: ${_cleanErrorMessage(e)}');
    }
  }

  void _openNotifications() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return ChildNotificationsPanel(childUserId: user.uid);
      },
    );
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

  Widget _buildUnpairedScreen() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
      children: [
        const SizedBox(height: 30),

        const Icon(Icons.phone_android_rounded, color: purple, size: 74),

        const SizedBox(height: 18),

        const Text(
          'Connect This Device',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: darkText,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          'Enter the 6-digit pairing code provided by your parent or guardian.',
          textAlign: TextAlign.center,
          style: TextStyle(color: grayText, height: 1.4),
        ),

        const SizedBox(height: 28),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: softPurple,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
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
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 52,
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
                    isPairing ? 'Connecting...' : 'Connect to Parent',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHomeTab(Map<String, dynamic> data) {
    final pairingStatus = data['pairingStatus'] as String? ?? 'waiting';

    final deviceStatus = data['deviceStatus'] as String? ?? 'not_connected';

    final parentNameValue = data['parentName'];

    final parentName =
        parentNameValue is String && parentNameValue.trim().isNotEmpty
        ? parentNameValue.trim()
        : 'Parent / Guardian';

    final isConnected =
        pairingStatus == 'paired' || deviceStatus == 'connected';

    final monitoringReady =
        isConnected && hasUsageAccess == true && hasAccessibilityAccess == true;

    final updatedAt = data['updatedAt'];

    final updatedDate = updatedAt is Timestamp ? updatedAt.toDate() : null;

    return RefreshIndicator(
      onRefresh: _refreshEverything,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
        children: [
          ProtectedStatusCard(isProtected: monitoringReady),

          const SizedBox(height: 20),

          Card(
            elevation: 1.5,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  ChildInfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Parent',
                    value: parentName,
                  ),

                  ChildInfoRow(
                    icon: Icons.shield_outlined,
                    label: 'Status',
                    value: monitoringReady ? 'Protected' : 'Setup Needed',
                    valueColor: monitoringReady ? Colors.green : Colors.orange,
                  ),

                  ChildInfoRow(
                    icon: Icons.sync_rounded,
                    label: 'Connection',
                    value: isConnected ? 'Active' : 'Offline',
                    valueColor: isConnected ? Colors.green : Colors.orange,
                  ),

                  ChildInfoRow(
                    icon: Icons.schedule_rounded,
                    label: 'Last Update',
                    value: _formatLastUpdate(updatedDate),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          ChildActionTile(
            icon: Icons.fact_check_outlined,
            title: 'View Rules',
            subtitle: 'See current rules and limits',
            onTap: () {
              setState(() {
                showRulesPage = true;
              });
            },
          ),

          ChildActionTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Contact Parent',
            subtitle: 'Send a message to $parentName',
            onTap: () {
              _contactParent(data);
            },
          ),

          ChildActionTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            subtitle: 'View messages and alerts',
            onTap: _openNotifications,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsTab() {
    return RefreshIndicator(
      onRefresh: _refreshEverything,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
        children: [
          const Text(
            'Device Permissions',
            style: TextStyle(
              color: darkText,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 7),

          const Text(
            'WellScreen needs these permissions to monitor the device and apply parent rules.',
            style: TextStyle(color: grayText, height: 1.4),
          ),

          const SizedBox(height: 22),

          PermissionOverviewCard(
            hasUsageAccess: hasUsageAccess,
            hasAccessibilityAccess: hasAccessibilityAccess,
            locationStatus: locationPermissionStatus,
          ),

          const SizedBox(height: 14),

          UsageAccessStatusCard(
            hasUsageAccess: hasUsageAccess,
            isChecking: isCheckingUsageAccess,
            onRecheck: _checkUsagePermission,
            onOpenSettings: openUsageAccessSettings,
          ),

          AccessibilityServiceStatusCard(
            hasAccessibilityAccess: hasAccessibilityAccess,
            isChecking: isCheckingAccessibilityAccess,
            onRecheck: _checkAccessibilityPermission,
            onOpenSettings: openAccessibilitySettings,
          ),

          LocationPermissionStatusCard(
            status: locationPermissionStatus,
            isChecking: isCheckingLocationPermission,
            onRecheck: _checkLocationPermission,
            onRequestPermission: _requestLocationPermission,
            onOpenLocationSettings: _openLocationSettings,
          ),

          const SmsBackupPermissionSection(),
        ],
      ),
    );
  }

  Widget _buildServiceTab(Map<String, dynamic> data) {
    final parentId = data['parentId'] as String?;

    final childId = data['childId'] as String?;

    final childEmail =
        data['childEmail'] as String? ??
        FirebaseAuth.instance.currentUser?.email ??
        'Child';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
      children: [
        const Text(
          'Device Service',
          style: TextStyle(
            color: darkText,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 7),

        const Text(
          'Sync monitoring information and access safety features.',
          style: TextStyle(color: grayText, height: 1.4),
        ),

        const SizedBox(height: 22),

        UsageSyncCard(
          isSyncing: isSyncingUsageReport,
          lastSyncMessage: lastSyncStatusMessage,
          onSync: syncTodayUsageReport,
          onOpenUsageAccess: openUsageAccessSettings,
        ),

        LocationSyncCard(
          isSyncing: isSyncingLocation,
          lastSyncMessage: lastLocationSyncMessage,
          onSync: _syncCurrentLocation,
        ),

        const SizedBox(height: 10),

        const ChildSectionHeader(
          title: 'Emergency Access',
          subtitle:
              'Request temporary access for an urgent or essential reason.',
        ),

        const SizedBox(height: 12),

        EmergencyAccessRequestSection(
          parentId: parentId,
          childId: childId,
          childEmail: childEmail,
        ),
      ],
    );
  }

  Widget _buildSettingsTab(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;

    final connected =
        data['deviceStatus'] == 'connected' ||
        data['pairingStatus'] == 'paired';

    final parentNameValue = data['parentName'];

    final parentName =
        parentNameValue is String && parentNameValue.trim().isNotEmpty
        ? parentNameValue.trim()
        : 'Parent / Guardian';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            color: darkText,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: softPurple,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: Colors.white,
                child: Icon(Icons.person_rounded, color: purple, size: 30),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Child Account',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      user?.email ?? 'No email available',
                      style: const TextStyle(color: grayText),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      connected ? 'Connected to $parentName' : 'Not connected',
                      style: TextStyle(
                        color: connected ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        const ChildStatusCard(
          icon: Icons.info_outline_rounded,
          iconColor: purple,
          title: 'About WellScreen',
          subtitle:
              'WellScreen helps parents and children build healthier digital habits through screen-time monitoring, safety rules, and device wellness features.',
        ),

        const SizedBox(height: 10),

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
  }

  Widget _buildRulesPage(Map<String, dynamic> data) {
    final parentId = data['parentId'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      children: [
        const Text(
          'Rules',
          style: TextStyle(
            color: darkText,
            fontSize: 29,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          'These rules are set by your parent or guardian.',
          style: TextStyle(color: grayText, height: 1.4),
        ),

        const SizedBox(height: 22),

        ParentRulesSection(parentId: parentId),

        const SizedBox(height: 12),

        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: Text(
              'These rules are set by your parent to help you build healthy digital habits.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: purple,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatLastUpdate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final difference = DateTime.now().difference(value);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }

    return '${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: _logout,
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_devices')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final deviceData = snapshot.data?.data();

        final isPaired =
            deviceData != null &&
            (deviceData['pairingStatus'] == 'paired' ||
                deviceData['deviceStatus'] == 'connected');

        return Scaffold(
          backgroundColor: Colors.white,

          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: purple,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 16,
            leading: showRulesPage && isPaired
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        showRulesPage = false;
                      });
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
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

                const SizedBox(width: 10),

                Text(
                  showRulesPage ? 'Rules' : 'WellScreen Child',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
              ],
            ),
            actions: [
              if (isPaired)
                UnreadNotificationBadgeButton(
                  userId: user.uid,
                  tooltip: 'Notifications',
                  onPressed: _openNotifications,
                ),
            ],
          ),

          body: snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : snapshot.hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : !isPaired
              ? _buildUnpairedScreen()
              : showRulesPage
              ? _buildRulesPage(deviceData)
              : switch (selectedTabIndex) {
                  0 => _buildHomeTab(deviceData),
                  1 => _buildPermissionsTab(),
                  2 => _buildServiceTab(deviceData),
                  _ => _buildSettingsTab(deviceData),
                },

          bottomNavigationBar: isPaired && !showRulesPage
              ? NavigationBar(
                  selectedIndex: selectedTabIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      selectedTabIndex = index;
                    });
                  },
                  indicatorColor: softPurple,
                  backgroundColor: const Color(0xFFF3F4F6),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded, color: purple),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.security_outlined),
                      selectedIcon: Icon(Icons.security_rounded, color: purple),
                      label: 'Permissions',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.health_and_safety_outlined),
                      selectedIcon: Icon(
                        Icons.health_and_safety_rounded,
                        color: purple,
                      ),
                      label: 'Service',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings_rounded, color: purple),
                      label: 'Settings',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class ProtectedStatusCard extends StatelessWidget {
  const ProtectedStatusCard({super.key, required this.isProtected});

  final bool isProtected;

  @override
  Widget build(BuildContext context) {
    final color = isProtected ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: isProtected
                  ? const Color(0xFFE8F7EE)
                  : const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isProtected
                  ? Icons.verified_user_rounded
                  : Icons.warning_amber_rounded,
              color: color,
              size: 44,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isProtected ? 'You are protected' : 'Setup needed',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  isProtected
                      ? 'WellScreen is active and currently monitoring your device.'
                      : 'Enable the required permissions so WellScreen can fully monitor this device.',
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChildInfoRow extends StatelessWidget {
  const ChildInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF111827), size: 25),

          const SizedBox(width: 13),

          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? const Color(0xFF4B5563),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChildActionTile extends StatelessWidget {
  const ChildActionTile({
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
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: const Color(0xFF5B2BBF)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF5B2BBF),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFF5B2BBF),
          size: 30,
        ),
      ),
    );
  }
}

class ContactParentDialog extends StatefulWidget {
  const ContactParentDialog({super.key, required this.parentName});

  final String parentName;

  @override
  State<ContactParentDialog> createState() => _ContactParentDialogState();
}

class _ContactParentDialogState extends State<ContactParentDialog> {
  static const Color purple = Color(0xFF5B2BBF);

  final TextEditingController messageController = TextEditingController();

  String selectedQuickMessage = 'Please contact me when you can.';

  @override
  void initState() {
    super.initState();
    messageController.text = selectedQuickMessage;
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  void selectQuickMessage(String message) {
    setState(() {
      selectedQuickMessage = message;
      messageController.text = message;
      messageController.selection = TextSelection.collapsed(
        offset: messageController.text.length,
      );
    });
  }

  void sendMessage() {
    final message = messageController.text.trim();

    if (message.isEmpty) {
      return;
    }

    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    const quickMessages = [
      'Please contact me when you can.',
      'I need help.',
      'Please call me.',
    ];

    return AlertDialog(
      title: Text(
        'Contact ${widget.parentName}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose a quick message or write your own.'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickMessages.map((message) {
                return ChoiceChip(
                  label: Text(message),
                  selected: selectedQuickMessage == message,
                  onSelected: (_) {
                    selectQuickMessage(message);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Message',
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
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: sendMessage,
          style: FilledButton.styleFrom(backgroundColor: purple),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class ChildNotificationsPanel extends StatelessWidget {
  const ChildNotificationsPanel({super.key, required this.childUserId});

  final String childUserId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('in_app_alerts')
                      .where('recipientUserId', isEqualTo: childUserId)
                      .limit(20)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
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
                      return const Center(
                        child: Text(
                          'No notifications yet.',
                          style: TextStyle(color: Color(0xFF4B5563)),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];

                        final data = doc.data();

                        final title = data['title'] as String? ?? 'WellScreen';

                        final message = data['message'] as String? ?? '';

                        final isRead = data['isRead'] as bool? ?? false;

                        return Card(
                          color: isRead
                              ? Colors.white
                              : const Color(0xFFF4F0FF),
                          child: ListTile(
                            onTap: () async {
                              await doc.reference.set({
                                'isRead': true,
                                'readAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                            },
                            leading: Icon(
                              isRead
                                  ? Icons.notifications_none_rounded
                                  : Icons.notifications_active_rounded,
                              color: const Color(0xFF5B2BBF),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(message),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChildSectionHeader extends StatelessWidget {
  const ChildSectionHeader({super.key, required this.title, this.subtitle});

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
              height: 1.35,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class PermissionOverviewCard extends StatelessWidget {
  const PermissionOverviewCard({
    super.key,
    required this.hasUsageAccess,
    required this.hasAccessibilityAccess,
    required this.locationStatus,
  });

  final bool? hasUsageAccess;
  final bool? hasAccessibilityAccess;

  final LocationPermissionStatus? locationStatus;

  @override
  Widget build(BuildContext context) {
    final locationGranted = locationStatus == LocationPermissionStatus.granted;

    final enabledCount = [
      hasUsageAccess == true,
      hasAccessibilityAccess == true,
      locationGranted,
    ].where((value) => value).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.security_rounded,
              color: Color(0xFF5B2BBF),
              size: 29,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Permission Status',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '$enabledCount of 3 main monitoring permissions enabled',
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          Text(
            '$enabledCount/3',
            style: const TextStyle(
              color: Color(0xFF5B2BBF),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final granted = hasUsageAccess == true;

    return PermissionCard(
      icon: Icons.bar_chart_rounded,
      title: 'Usage Access',
      subtitle: 'Track screen time and app usage.',
      granted: granted,
      isChecking: isChecking,
      onRecheck: onRecheck,
      onEnable: onOpenSettings,
      buttonText: 'Open Usage Access Settings',
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

  @override
  Widget build(BuildContext context) {
    return PermissionCard(
      icon: Icons.accessibility_new_rounded,
      title: 'Accessibility Service',
      subtitle: 'Detect blocked apps and enforce parent rules.',
      granted: hasAccessibilityAccess == true,
      isChecking: isChecking,
      onRecheck: onRecheck,
      onEnable: onOpenSettings,
      buttonText: 'Open Accessibility Settings',
    );
  }
}

class LocationPermissionStatusCard extends StatelessWidget {
  const LocationPermissionStatusCard({
    super.key,
    required this.status,
    required this.isChecking,
    required this.onRecheck,
    required this.onRequestPermission,
    required this.onOpenLocationSettings,
  });

  final LocationPermissionStatus? status;

  final bool isChecking;

  final Future<void> Function() onRecheck;

  final Future<void> Function() onRequestPermission;

  final Future<void> Function() onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final granted = status == LocationPermissionStatus.granted;

    return PermissionCard(
      icon: Icons.location_on_rounded,
      title: 'Location Permission',
      subtitle: 'Share safety location information with the parent account.',
      granted: granted,
      isChecking: isChecking,
      onRecheck: onRecheck,
      onEnable: status == LocationPermissionStatus.serviceDisabled
          ? onOpenLocationSettings
          : onRequestPermission,
      buttonText: status == LocationPermissionStatus.serviceDisabled
          ? 'Open Location Settings'
          : 'Allow Location Permission',
    );
  }
}

class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.isChecking,
    required this.onRecheck,
    required this.onEnable,
    required this.buttonText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool isChecking;

  final Future<void> Function() onRecheck;

  final Future<void> Function() onEnable;

  final String buttonText;

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
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F0FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    icon,
                    color: granted ? Colors.green : const Color(0xFF5B2BBF),
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed: isChecking ? null : () => onRecheck(),
                  icon: isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          granted
                              ? Icons.check_circle_rounded
                              : Icons.refresh_rounded,
                          color: granted ? Colors.green : null,
                        ),
                ),
              ],
            ),

            if (!granted) ...[
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isChecking ? null : () => onEnable(),
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(
                    buttonText,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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

  final Future<void> Function() onSync;

  final Future<void> Function() onOpenUsageAccess;

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      icon: Icons.cloud_upload_rounded,
      title: 'Usage Report Sync',
      description:
          lastSyncMessage ??
          'Send today\'s usage information to the parent account.',
      isWorking: isSyncing,
      buttonText: isSyncing ? 'Syncing...' : 'Sync Usage Report',
      onPressed: isSyncing ? null : onSync,
    );
  }
}

class LocationSyncCard extends StatelessWidget {
  const LocationSyncCard({
    super.key,
    required this.isSyncing,
    required this.lastSyncMessage,
    required this.onSync,
  });

  final bool isSyncing;
  final String? lastSyncMessage;

  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return ServiceCard(
      icon: Icons.gps_fixed_rounded,
      title: 'Location Sync',
      description:
          lastSyncMessage ??
          'Send the latest GPS location to the parent account.',
      isWorking: isSyncing,
      buttonText: isSyncing ? 'Syncing...' : 'Sync Current Location',
      onPressed: isSyncing ? null : onSync,
    );
  }
}

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.isWorking,
    required this.buttonText,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isWorking;
  final String buttonText;

  final Future<void> Function()? onPressed;

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
            Row(
              children: [
                Icon(icon, color: const Color(0xFF5B2BBF), size: 32),

                const SizedBox(width: 12),

                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              description,
              style: const TextStyle(color: Color(0xFF4B5563), height: 1.4),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPressed == null ? null : () => onPressed!(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5B2BBF),
                ),
                icon: isWorking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  buttonText,
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
        title: 'Parent Rules Unavailable',
        subtitle: 'The linked parent account could not be found.',
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
            title: 'Loading Parent Rules',
            subtitle: 'Preparing restrictions from the parent account...',
          );
        }

        if (snapshot.hasError) {
          return ChildStatusCard(
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: 'Unable to Load Parent Rules',
            subtitle: snapshot.error.toString(),
          );
        }

        final data = snapshot.data?.data();

        if (data == null) {
          return const ChildStatusCard(
            icon: Icons.rule_rounded,
            iconColor: Colors.orange,
            title: 'No Rules Saved Yet',
            subtitle:
                'Rules will appear after the parent saves restriction settings.',
          );
        }

        final limitValue = data['limitMinutes'];

        final limitMinutes = limitValue is num ? limitValue.toInt() : 120;

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
              icon: Icons.timer_outlined,
              iconColor: purple,
              title: 'Daily Screen-Time Limit',
              subtitle: '${_formatMinutes(limitMinutes)} per day',
            ),

            ParentRuleCard(
              icon: Icons.block_rounded,
              title: 'App Blocking',
              isEnabled: appBlocking,
              enabledMessage:
                  'Selected apps are blocked after limits are reached.',
              disabledMessage: 'App blocking is disabled.',
            ),

            ParentRuleCard(
              icon: Icons.center_focus_strong_rounded,
              title: 'Focus Mode',
              isEnabled: focusMode,
              enabledMessage:
                  'Distracting apps are limited during study or rest time.',
              disabledMessage: 'Focus Mode is disabled.',
            ),

            ParentRuleCard(
              icon: Icons.hourglass_bottom_rounded,
              title: 'Cooldown Timer',
              isEnabled: cooldownTimer,
              enabledMessage:
                  'Break reminders are enabled after long continuous usage.',
              disabledMessage: 'Cooldown reminders are disabled.',
            ),

            ParentRuleCard(
              icon: Icons.lock_clock_rounded,
              title: 'Scheduled Lock Session',
              isEnabled: scheduledLock,
              enabledMessage: 'Default lock time: 10:00 PM to 5:00 AM.',
              disabledMessage: 'Scheduled lock sessions are disabled.',
            ),

            ParentRuleCard(
              icon: Icons.shield_outlined,
              title: 'Harmful Category Restriction',
              isEnabled: categoryRestriction,
              enabledMessage:
                  'Supported harmful website or category events are restricted.',
              disabledMessage: 'Harmful category restriction is disabled.',
            ),

            ParentRuleCard(
              icon: Icons.emergency_rounded,
              title: 'Emergency Access',
              isEnabled: emergencyAccess,
              enabledMessage:
                  'Selected essential functions are allowed during restrictions.',
              disabledMessage: 'Emergency access is disabled.',
            ),
          ],
        );
      },
    );
  }

  bool _readBool(Map<String, dynamic> data, String key, bool defaultValue) {
    final value = data[key];

    return value is bool ? value : defaultValue;
  }

  String _formatMinutes(int minutes) {
    final duration = Duration(minutes: minutes);

    final hours = duration.inHours;

    final remaining = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${remaining}m';
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: const Color(0xFF5B2BBF)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(isEnabled ? enabledMessage : disabledMessage),
        ),
        trailing: Text(
          isEnabled ? 'ON' : 'OFF',
          style: TextStyle(
            color: isEnabled ? Colors.green : Colors.grey,
            fontWeight: FontWeight.w900,
          ),
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

  @override
  void initState() {
    super.initState();
    checkPermission();
  }

  Future<void> checkPermission() async {
    final granted = await const NativeRestrictionRulesService()
        .isSmsPermissionGranted();

    if (!mounted) return;

    setState(() {
      isGranted = granted;
      isChecking = false;
    });
  }

  Future<void> requestPermission() async {
    setState(() {
      isChecking = true;
    });

    await const NativeRestrictionRulesService().requestSmsPermission();

    await Future<void>.delayed(const Duration(milliseconds: 800));

    await checkPermission();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionCard(
      icon: Icons.sms_outlined,
      title: 'SMS Backup Permission',
      subtitle:
          'Allow WellScreen to send critical backup alerts. WellScreen does not read SMS messages.',
      granted: isGranted,
      isChecking: isChecking,
      onRecheck: checkPermission,
      onEnable: requestPermission,
      buttonText: 'Allow SMS Backup Alerts',
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
  int requestedDurationMinutes = 30;

  static const Color purple = Color(0xFF5B2BBF);

  static const List<int> requestDurationOptions = [15, 30, 60];

  String _formatDurationMinutes(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }

    return '$minutes minutes';
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  Future<void> submitEmergencyRequest() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    if (widget.parentId == null || widget.parentId!.isEmpty) {
      _showMessage('Parent account is unavailable.');
      return;
    }

    final reason = reasonController.text.trim();

    if (reason.length < 5) {
      _showMessage('Please enter a short reason.');
      return;
    }

    setState(() {
      isSubmitting = true;
    });

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
            'requestedDurationMinutes': requestedDurationMinutes,
            'status': 'pending',
            'requestedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      var parentAlertSent = true;

      try {
        await NotificationService.instance.createInAppAlert(
          recipientUserId: widget.parentId!,
          parentId: widget.parentId!,
          childId: widget.childId,
          title: 'Emergency Access Request',
          message:
              '$reason\nRequested duration: '
              '${_formatDurationMinutes(requestedDurationMinutes)}',
          triggerType: 'emergency_access_request',
          priority: 'high',
          extraData: {
            'childUserId': user.uid,
            'childEmail': widget.childEmail,
            'requestedDurationMinutes': requestedDurationMinutes,
          },
        );
      } catch (_) {
        parentAlertSent = false;
      }

      reasonController.clear();

      _showMessage(
        parentAlertSent
            ? 'Emergency access request sent.'
            : 'Emergency access request sent, but the parent notification alert could not be created.',
      );
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void _syncToNative(Map<String, dynamic>? data) {
    final status = data?['status'] as String? ?? 'none';

    final approvedUntilValue = data?['approvedUntil'];

    final approvedUntil = approvedUntilValue is Timestamp
        ? approvedUntilValue.toDate()
        : null;

    final approved =
        status == 'approved' &&
        approvedUntil != null &&
        approvedUntil.isAfter(DateTime.now());

    unawaited(
      const NativeRestrictionRulesService()
          .saveEmergencyAccessState(
            isApproved: approved,
            approvedUntil: approvedUntil,
          )
          .catchError((Object _) {}),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const SizedBox();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('emergency_access_requests')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();

        _syncToNative(data);

        final status = data?['status'] as String? ?? 'none';

        final statusText = switch (status) {
          'pending' => 'Request pending',
          'approved' => 'Temporary access approved',
          'denied' => 'Previous request denied',
          _ => 'No active request',
        };

        final savedRequestedDuration = data?['requestedDurationMinutes'] is num
            ? (data!['requestedDurationMinutes'] as num).toInt()
            : null;

        return Card(
          elevation: 1.5,
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
                    const Icon(
                      Icons.emergency_rounded,
                      color: purple,
                      size: 30,
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        statusText,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                DropdownButtonFormField<int>(
                  initialValue: requestedDurationMinutes,
                  decoration: InputDecoration(
                    labelText: 'Requested Duration',
                    prefixIcon: const Icon(Icons.timer_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: requestDurationOptions.map((minutes) {
                    return DropdownMenuItem<int>(
                      value: minutes,
                      child: Text(_formatDurationMinutes(minutes)),
                    );
                  }).toList(),
                  onChanged: isSubmitting
                      ? null
                      : (value) {
                          if (value == null) return;

                          setState(() {
                            requestedDurationMinutes = value;
                          });
                        },
                ),

                if (savedRequestedDuration != null && status == 'pending') ...[
                  const SizedBox(height: 10),
                  Text(
                    'Current request: '
                    '${_formatDurationMinutes(savedRequestedDuration)}',
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Example: I need to call my guardian.',
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
                    style: FilledButton.styleFrom(backgroundColor: purple),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      isSubmitting ? 'Sending...' : 'Request Emergency Access',
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: iconColor, size: 32),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF4B5563), height: 1.4),
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
