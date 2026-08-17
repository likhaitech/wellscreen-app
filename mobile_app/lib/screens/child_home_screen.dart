import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_rule.dart';
import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import '../services/alert_notification_client.dart';
import '../services/app_rules_service.dart';
import '../services/daily_screen_time_limit_service.dart';
import '../services/ml_risk_classifier_service.dart';
import '../services/sync_status_service.dart';
import '../services/usage_dashboard_controller_service.dart';
import '../services/usage_tracking_service.dart';
import '../widgets/wellscreen_bottom_nav.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softBlue = Color(0xFFEFF6FF);
  static const Color softRed = Color(0xFFFFEFEF);

  final AppRulesService _rulesService = AppRulesService();
  final UsageTrackingService _usageTrackingService = UsageTrackingService();
  final AlertNotificationClient _alertNotificationClient =
      AlertNotificationClient();
  final UsageDashboardControllerService _usageDashboardController =
      UsageDashboardControllerService();
  final SyncStatusService _syncStatusService = SyncStatusService();
  final MlRiskClassifierService _mlRiskClassifierService =
      MlRiskClassifierService();
  final DailyScreenTimeLimitService _dailyScreenTimeLimitService =
      DailyScreenTimeLimitService();
  final pairingCodeController = TextEditingController();
  StreamSubscription<bool>? _connectivitySubscription;

  int currentIndex = 0;
  bool isPairing = false;
  bool isSharingLocation = false;
  bool isSyncingUsage = false;

  // Real local usage data loaded via UsageDashboardControllerService, which
  // wraps UsageTrackingService (Android UsageStats), PatternDetectionService
  // and ScreenTimeGoalService. This layer already existed in the codebase
  // (usage_dashboard_controller_service.dart etc.) but nothing imported it
  // from any screen, so this card was showing hardcoded "4h 25m" / "Low
  // Risk" / "32/100" placeholders instead. See BRANCH_REAUDIT for details.
  UsageDashboardControllerState? _usageDashboardState;
  bool _loadingUsageDashboard = true;

  // SMS backup-alert status (see SmsAlertSender.kt). The actual sending
  // happens natively in WellScreenAccessibilityService when a restricted
  // app is blocked - this state is just what the Flutter UI needs to show
  // whether that's actually wired up (permission granted + a parent phone
  // number cached) and a log of what's happened so far.
  bool _smsPermissionGranted = false;
  String? _cachedParentPhoneNumber;
  List<Map<String, dynamic>> _smsAlertLog = [];
  String? _syncedParentIdForPhoneNumber;

  // Synchronization status (see SyncStatusService / _attemptFirestoreSync
  // below). cloud_firestore's set()/update() Futures hang indefinitely when
  // offline instead of throwing (firebase/flutterfire#17643) - this state
  // tracks real online/offline status and a log of what actually happened
  // on each sync attempt (synced / queued_offline / failed_timeout), not
  // just whether the sync button was tapped.
  bool _isOnline = true;
  List<Map<String, dynamic>> _syncLog = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUsageDashboard();
    _refreshSmsAlertStatus();
    _refreshSyncStatus();
    _connectivitySubscription =
        _syncStatusService.onlineStatusChanges.listen(_handleConnectivityChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pairingCodeController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's "Usage Access" permission is granted from system Settings,
    // outside the app, so there's no in-app callback for it. Re-check when
    // the user comes back to the app (e.g. after granting the permission)
    // instead of requiring a manual refresh every time.
    if (state == AppLifecycleState.resumed) {
      _loadUsageDashboard();
      _refreshSmsAlertStatus();
      _refreshSyncStatus();
    }
  }

  /// Caches the paired parent's phone number locally (SharedPreferences),
  /// because WellScreenAccessibilityService.kt / SmsAlertSender.kt run in
  /// native Kotlin with no Firestore access of their own - they read the
  /// same "FlutterSharedPreferences" file the Flutter app writes to, the
  /// same pattern app_rules_service.dart already uses for restricted-app
  /// package lists. The number itself lives on users/{parentId}.phoneNumber
  /// (ProfileSettingsScreen), set by the parent on their own device.
  Future<void> _maybeSyncParentPhoneNumber(Map<String, dynamic> data) async {
    final parentId = (data['pairedParentId'] ?? '').toString();

    if (parentId.isEmpty || parentId == _syncedParentIdForPhoneNumber) {
      return;
    }

    _syncedParentIdForPhoneNumber = parentId;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .get();

      final phoneNumber = (doc.data()?['phoneNumber'] ?? '').toString().trim();
      final prefs = await SharedPreferences.getInstance();

      if (phoneNumber.isEmpty) {
        await prefs.remove('parent_phone_number');
      } else {
        await prefs.setString('parent_phone_number', phoneNumber);
      }

      await _refreshSmsAlertStatus();
    } catch (_) {
      // Best-effort - if this fails, SmsAlertSender simply has no cached
      // number yet and skips sending, same as the "no number yet" state.
    }
  }

  Future<void> _refreshSmsAlertStatus() async {
    final status = await Permission.sms.status;
    final prefs = await SharedPreferences.getInstance();
    final phoneNumber = prefs.getString('parent_phone_number');
    final log = _decodeJsonList(prefs.getString('sms_alert_log_json'));

    if (!mounted) return;

    setState(() {
      _smsPermissionGranted = status.isGranted;
      _cachedParentPhoneNumber =
          (phoneNumber != null && phoneNumber.isNotEmpty) ? phoneNumber : null;
      _smsAlertLog = log;
    });
  }

  List<Map<String, dynamic>> _decodeJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fires once per actual online<->offline transition (see
  /// SyncStatusService.onlineStatusChanges). On regaining connectivity,
  /// flushes whatever was cached by _queuePendingSync while offline - this
  /// is the "automatic retry after reconnecting" half of the offline-sync
  /// story; syncUsageReport()'s manual button press is the other half.
  Future<void> _handleConnectivityChange(bool isOnline) async {
    if (mounted) {
      setState(() => _isOnline = isOnline);
    }

    if (!isOnline) return;

    final prefs = await SharedPreferences.getInstance();
    final pendingRaw = prefs.getString('pending_sync_payload_json');
    if (pendingRaw == null) return;

    try {
      final pending = jsonDecode(pendingRaw);
      if (pending is! Map) {
        await prefs.remove('pending_sync_payload_json');
        return;
      }

      final childProfileId = (pending['childProfileId'] ?? '').toString();
      final payload = pending['payload'];
      final queuedAtMs = pending['queuedAtMs'];

      if (childProfileId.isEmpty || payload is! Map) {
        await prefs.remove('pending_sync_payload_json');
        return;
      }

      await _attemptFirestoreSync(
        childProfileId: childProfileId,
        payload: Map<String, dynamic>.from(payload),
        trigger: 'auto_reconnect',
        queuedAtMs: queuedAtMs is int ? queuedAtMs : null,
      );
    } catch (_) {
      // Malformed cache entry - drop it rather than retry forever.
      await prefs.remove('pending_sync_payload_json');
    }
  }

  Future<void> _queuePendingSync(
    String childProfileId,
    Map<String, dynamic> payload,
    int queuedAtMs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pending_sync_payload_json',
      jsonEncode({
        'childProfileId': childProfileId,
        'payload': payload,
        'queuedAtMs': queuedAtMs,
      }),
    );
  }

  Future<void> _clearPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_sync_payload_json');
  }

  Future<void> _recordSyncOutcome({
    required String outcome,
    required String trigger,
    int? responseTimeMs,
    int? recoveryTimeMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final log = _decodeJsonList(prefs.getString('sync_log_json'));

    log.add({
      'outcome': outcome,
      'trigger': trigger,
      'responseTimeMs': ?responseTimeMs,
      'recoveryTimeMs': ?recoveryTimeMs,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });

    final trimmed = log.length > 50 ? log.sublist(log.length - 50) : log;
    await prefs.setString('sync_log_json', jsonEncode(trimmed));
  }

  Future<void> _refreshSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final log = _decodeJsonList(prefs.getString('sync_log_json'));
    final online = await _syncStatusService.isOnline();

    if (!mounted) return;
    setState(() {
      _syncLog = log;
      _isOnline = online;
    });
  }

  /// Single choke point for writing the usage/SMS/restriction snapshot to
  /// child_profiles/{childProfileId} - used by both syncUsageReport()'s
  /// manual button and _handleConnectivityChange()'s automatic
  /// reconnect flush above.
  ///
  /// Always caches the payload locally BEFORE attempting the write (cleared
  /// only on confirmed success), and wraps the write in a timeout, because
  /// cloud_firestore's set() hangs forever offline instead of throwing
  /// (firebase/flutterfire#17643) - without this, a sync attempted while
  /// offline would spin the loading indicator forever with no error and no
  /// way to recover except restarting the app.
  ///
  /// [payload] must not contain FieldValue sentinels (e.g.
  /// FieldValue.serverTimestamp()) - those aren't JSON-encodable for the
  /// local cache; the server timestamp is added here, right before the
  /// real Firestore write.
  Future<bool> _attemptFirestoreSync({
    required String childProfileId,
    required Map<String, dynamic> payload,
    required String trigger,
    int? queuedAtMs,
  }) async {
    final stopwatch = Stopwatch()..start();
    final attemptStartMs = DateTime.now().millisecondsSinceEpoch;
    final effectiveQueuedAtMs = queuedAtMs ?? attemptStartMs;
    String outcome;

    await _queuePendingSync(childProfileId, payload, effectiveQueuedAtMs);

    try {
      final online = await _syncStatusService.isOnline();

      if (!online) {
        outcome = 'queued_offline';
      } else {
        await FirebaseFirestore.instance
            .collection('child_profiles')
            .doc(childProfileId)
            .set({
              ...payload,
              'usageReportUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));

        await _clearPendingSync();
        outcome = 'synced';
      }
    } on TimeoutException {
      outcome = 'failed_timeout';
    } catch (_) {
      outcome = 'failed_exception';
    }

    stopwatch.stop();

    final recoveryTimeMs = (outcome == 'synced' && queuedAtMs != null)
        ? DateTime.now().millisecondsSinceEpoch - queuedAtMs
        : null;

    await _recordSyncOutcome(
      outcome: outcome,
      trigger: trigger,
      responseTimeMs: stopwatch.elapsedMilliseconds,
      recoveryTimeMs: recoveryTimeMs,
    );

    if (!mounted) return outcome == 'synced';

    if (outcome == 'synced') {
      if (trigger == 'auto_reconnect') {
        showMessage(
          'Usage data synced automatically now that you\'re back online.',
        );
        await _loadUsageDashboard();
        await _refreshSmsAlertStatus();
      }
    } else if (outcome == 'queued_offline') {
      showMessage(
        'You\'re offline - this data is saved on your device and will '
        'sync automatically once you\'re back online.',
      );
    } else if (outcome == 'failed_timeout') {
      showMessage(
        'Sync is taking too long - your data is saved locally and will '
        'retry automatically when the connection improves.',
      );
    } else {
      showMessage(
        'Sync failed. Your data is saved locally - try again shortly.',
      );
    }

    await _refreshSyncStatus();

    return outcome == 'synced';
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();

    if (!mounted) return;

    setState(() => _smsPermissionGranted = status.isGranted);

    showMessage(
      status.isGranted
          ? 'SMS backup alerts enabled.'
          : 'SMS permission was not granted. Backup alerts will stay off '
              'until it\'s allowed.',
    );
  }

  String _maskPhoneNumber(String phone) {
    if (phone.length <= 4) return phone;
    return '${'*' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
  }

  Future<void> _loadUsageDashboard() async {
    if (!mounted) return;
    setState(() => _loadingUsageDashboard = true);

    try {
      final state = await _usageDashboardController.loadTodayDashboardState();
      if (!mounted) return;
      setState(() {
        _usageDashboardState = state;
        _loadingUsageDashboard = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingUsageDashboard = false);
    }
  }

  Future<void> pairWithParent() async {
    final code = pairingCodeController.text.trim().replaceAll(' ', '');
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    if (code.length != 6) {
      showMessage('Please enter a valid 6-digit pairing code.');
      return;
    }

    setState(() => isPairing = true);

    try {
      final firestore = FirebaseFirestore.instance;

      final codeRef = firestore.collection('pairing_codes').doc(code);
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        final codeSnapshot = await transaction.get(codeRef);

        if (!codeSnapshot.exists) {
          throw Exception('Pairing code not found.');
        }

        final codeData = codeSnapshot.data() ?? <String, dynamic>{};

        final status = (codeData['status'] ?? '').toString();
        final parentId = (codeData['parentId'] ?? '').toString();
        final childProfileId = (codeData['childId'] ?? '').toString();
        final expiresAt = codeData['expiresAt'];

        if (status != 'active') {
          throw Exception('This pairing code is no longer active.');
        }

        if (parentId.isEmpty || childProfileId.isEmpty) {
          throw Exception('Invalid pairing code data.');
        }

        if (expiresAt is Timestamp) {
          final expiryDate = expiresAt.toDate();

          if (DateTime.now().isAfter(expiryDate)) {
            throw Exception('This pairing code has expired.');
          }
        }

        final childProfileRef = firestore
            .collection('child_profiles')
            .doc(childProfileId);

        transaction.set(userRef, {
          'uid': user.uid,
          'email': user.email,
          'fullName': user.displayName ?? 'Student User',
          'role': 'child',
          'pairingStatus': 'connected',
          'pairedParentId': parentId,
          'pairedChildProfileId': childProfileId,
          'pairingCode': code,
          'pairedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(codeRef, {
          'status': 'connected',
          'childAccountId': user.uid,
          'childEmail': user.email,
          'connectedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childProfileRef, {
          'childAccountId': user.uid,
          'childEmail': user.email,
          'pairingStatus': 'connected',
          'connectedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      pairingCodeController.clear();

      if (!mounted) return;

      showConnectedSuccessDialog();
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      showMessage(message);
    } finally {
      if (mounted) {
        setState(() => isPairing = false);
      }
    }
  }

  /// Requests the device's real GPS position via [Geolocator] and shares it
  /// to the parent dashboard. Replaces the previous shareDemoLocation, which
  /// wrote a hardcoded constant coordinate regardless of the device's actual
  /// position - see the WellScreen re-audit notes for why that was a
  /// data-integrity problem, not just a missing feature.
  Future<void> shareCurrentLocation(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (childProfileId.isEmpty) {
      showMessage('Pair this device first before sharing GPS location.');
      return;
    }

    setState(() => isSharingLocation = true);

    try {
      final position = await _getCurrentPositionOrThrow();

      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final childProfileRef = firestore
          .collection('child_profiles')
          .doc(childProfileId);

      final sharedLocation = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'capturedAt': position.timestamp.toIso8601String(),
      };

      // Location isn't queued/auto-retried like usage data (see
      // _attemptFirestoreSync) - a stale GPS fix replayed automatically
      // after reconnecting would show the parent an outdated position
      // without saying so, which is worse than just failing visibly. It
      // still gets a timeout instead of hanging forever, though - same
      // underlying cloud_firestore bug (set()/runTransaction() never
      // complete offline: firebase/flutterfire#17643) applies here too.
      await firestore
          .runTransaction((transaction) async {
            transaction.set(userRef, {
              'latestLocation': sharedLocation,
              'locationUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            transaction.set(childProfileRef, {
              'latestLocation': sharedLocation,
              'locationUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          })
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      showMessage('Current GPS location shared to parent dashboard.');

      final parentId = (data['pairedParentId'] ?? '').toString();
      unawaited(
        _alertNotificationClient.notifyParent(
          parentUid: parentId,
          title: 'New location shared',
          body: 'Your child\'s device just shared its current location.',
          alertType: 'location_shared',
          childProfileId: childProfileId,
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      showMessage(
        'Sharing location is taking too long - check your connection and '
        'try again.',
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isSharingLocation = false);
      }
    }
  }

  /// Walks the full geolocator permission/service flow and returns a real
  /// device [Position], or throws a user-readable Exception describing
  /// exactly which step failed (services off, permission denied, permission
  /// permanently denied, or a timeout getting a fix).
  ///
  /// NOT verified on a physical device or emulator - this sandbox has no
  /// Android runtime to test against. The permission flow and API calls
  /// follow the documented geolocator ^14.x contract, but this needs a real
  /// on-device pass (indoors AND outdoors, and with location services
  /// toggled off) before this row can honestly move to "Done" in the
  /// tracker.
  Future<Position> _getCurrentPositionOrThrow() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are turned off on this device. Enable GPS/location and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission was denied. Allow location access for WellScreen and try again.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it from this device\'s App Settings > Permissions.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  /// Builds the 6-feature input vector for MlRiskClassifierService, using
  /// only data the app can genuinely compute today - see
  /// ml/generate_dataset.py's doc comment for which of the manuscript's
  /// Table 6 indicators are included and which are deferred (frequent-app
  /// launch counting and harmful-category detection aren't built yet, so
  /// they're not faked here).
  Map<String, num> _buildMlFeatures({
    required UsageReport report,
    required List<AppUsageSummary> summaries,
    required List<Map<String, dynamic>> restrictionLog,
    required int dailyLimitMinutes,
  }) {
    var lateNightMinutes = 0;
    var longestSessionMinutes = 0;

    for (final app in summaries) {
      final minutes = app.usageDuration.inMinutes;

      if (minutes > longestSessionMinutes) {
        longestSessionMinutes = minutes;
      }

      final lastUsed = app.lastTimeUsed;
      if (lastUsed != null && (lastUsed.hour >= 22 || lastUsed.hour < 5)) {
        // Best-effort proxy: AppUsageSummary only exposes a last-used
        // timestamp, not a minute-by-minute breakdown, so an app last
        // touched in the late-night window has its whole usage duration
        // counted toward late-night minutes. Same underlying signal
        // PatternDetectionService._hasLateNightUsage already uses (a
        // last-used-hour check), just summed into a duration instead of
        // left as a boolean.
        lateNightMinutes += minutes;
      }
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    var attemptsToday = 0;
    var violations7d = 0;

    for (final entry in restrictionLog) {
      if (entry['outcome'] != 'blocked') continue;

      final timestampMs = entry['timestampMs'];
      if (timestampMs is! int) continue;

      final eventTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);

      if (!eventTime.isBefore(startOfDay)) {
        attemptsToday++;
      }
      if (eventTime.isAfter(sevenDaysAgo)) {
        violations7d++;
      }
    }

    return {
      'total_screen_time_minutes': report.totalUsageDuration.inMinutes,
      'daily_limit_minutes': dailyLimitMinutes,
      'late_night_minutes': lateNightMinutes,
      'longest_session_minutes': longestSessionMinutes,
      'restricted_app_attempts_today': attemptsToday,
      'rule_violations_7d': violations7d,
    };
  }

  /// Syncs today's real on-device usage data to
  /// child_profiles/{childProfileId}.latestUsageReport, so the parent
  /// dashboard (ParentDashboardScreen's Screen Time/Usage Pattern/Top Apps
  /// cards and UsageSummaryScreen) can display it. Mirrors the
  /// shareCurrentLocation pattern above - same childProfileId lookup, same
  /// Firestore transaction shape.
  ///
  /// Requires Android's special "Usage Access" permission, which can only
  /// be granted from system Settings (not a normal runtime permission
  /// dialog). If it isn't granted yet, this opens that settings screen and
  /// asks the user to come back and tap again - didChangeAppLifecycleState
  /// above will also silently refresh the local dashboard when they return.
  Future<void> syncUsageReport(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (childProfileId.isEmpty) {
      showMessage('Pair this device first before syncing usage data.');
      return;
    }

    setState(() => isSyncingUsage = true);

    try {
      final hasPermission = await _usageTrackingService.hasUsagePermission();

      if (!hasPermission) {
        await _usageTrackingService.openUsageAccessSettings();
        if (!mounted) return;
        showMessage(
          'Grant "WellScreen" access under Usage Access in Settings, then '
          'come back and tap Sync Usage again.',
        );
        return;
      }

      final summaries = await _usageTrackingService.getTodayUsage();
      final report = await _usageTrackingService.getTodayUsageReport();

      final topApps = summaries
          .map(
            (AppUsageSummary app) => {
              'packageName': app.packageName,
              'displayName': app.displayName,
              'usageDurationMs': app.usageDuration.inMilliseconds,
              'lastTimeUsed': app.lastTimeUsed?.toIso8601String(),
            },
          )
          .toList();

      final usageReportData = {
        'totalUsageDurationMs': report.totalUsageDuration.inMilliseconds,
        'topApps': topApps,
        'unhealthyAppCount': report.unhealthyAppCount,
        'patternStatus': report.patternStatus.name,
        'recommendationMessage': report.recommendationMessage,
        'capturedAt': report.generatedAt.toIso8601String(),
      };

      // Also push the local SMS backup-alert log (written natively by
      // SmsSentReceiver/SmsDeliveredReceiver), the restriction enforcement
      // log (written natively by RestrictionLogger when
      // WellScreenAccessibilityService blocks a restricted app), and this
      // device's own sync-attempt log (see _recordSyncOutcome) so the
      // parent can see real sent/delivered/failed, blocked/failed, and
      // synced/queued-offline/failed outcomes with response times, not
      // just whether the features are turned on. Reuses this same sync
      // button rather than adding separate ones.
      final prefs = await SharedPreferences.getInstance();
      final smsAlertLog = _decodeJsonList(
        prefs.getString('sms_alert_log_json'),
      );
      final restrictionLog = _decodeJsonList(
        prefs.getString('restriction_log_json'),
      );
      final syncLog = _decodeJsonList(prefs.getString('sync_log_json'));

      // Proposed ML Extension (manuscript Ch. 3) - a real, trained,
      // evaluated Random Forest classifier (see ml/train_model.py and
      // ml/output/evaluation_report.txt), run on-device via
      // MlRiskClassifierService. Supplements PatternDetectionService's
      // rule-based status above; doesn't replace it. Best-effort: a
      // classification failure (e.g. the asset failing to load) should
      // never block the real sync.
      Map<String, dynamic>? mlRiskAssessmentData;
      try {
        final dailyLimit = await _dailyScreenTimeLimitService.getDailyLimit();
        final mlFeatures = _buildMlFeatures(
          report: report,
          summaries: summaries,
          restrictionLog: restrictionLog,
          dailyLimitMinutes: dailyLimit.inMinutes,
        );
        final assessment = await _mlRiskClassifierService.classify(
          mlFeatures,
        );

        mlRiskAssessmentData = {
          'label': assessment.label,
          'confidence': assessment.confidence,
          'classProbabilities': assessment.classProbabilities,
          'modelVersion': assessment.modelVersion,
          'inputFeatures': mlFeatures,
          'timestampMs': DateTime.now().millisecondsSinceEpoch,
        };
      } catch (_) {
        // Best-effort - see above. The rule-based status still syncs.
      }

      // _attemptFirestoreSync handles offline detection, the write timeout
      // (cloud_firestore's set() hangs forever offline instead of throwing
      // - firebase/flutterfire#17643), local queuing for automatic retry on
      // reconnect, and outcome logging - see its doc comment above.
      final synced = await _attemptFirestoreSync(
        childProfileId: childProfileId,
        payload: {
          'latestUsageReport': usageReportData,
          if (smsAlertLog.isNotEmpty) 'smsAlertLog': smsAlertLog,
          if (restrictionLog.isNotEmpty) 'restrictionLog': restrictionLog,
          if (syncLog.isNotEmpty) 'syncLog': syncLog,
          'mlRiskAssessment': ?mlRiskAssessmentData,
        },
        trigger: 'manual',
      );

      if (!mounted) return;

      if (synced) {
        showMessage('Today\'s usage report synced to the parent dashboard.');
        await _loadUsageDashboard();
        await _refreshSmsAlertStatus();
      }

      // Push a real notification only for the pattern that actually
      // matters to a parent (unhealthy) rather than on every sync - a
      // healthy-usage push every time would just be noise. Fired regardless
      // of whether the Firestore sync above succeeded - it's an
      // independent, best-effort channel (see AlertNotificationClient).
      if (report.patternStatus.name == 'unhealthy') {
        final parentId = (data['pairedParentId'] ?? '').toString();
        unawaited(
          _alertNotificationClient.notifyParent(
            parentUid: parentId,
            title: 'Unhealthy usage pattern detected',
            body: report.recommendationMessage,
            alertType: 'unhealthy_usage',
            childProfileId: childProfileId,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isSyncingUsage = false);
      }
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void handleBottomNavTap(int index) {
    if (index == 0) {
      setState(() => currentIndex = 0);
      return;
    }

    if (index == 1) {
      showMessage('Pairing is available on the student dashboard.');
    } else if (index == 2) {
      showMessage('Student usage reports will sync here.');
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }
  }

  void showConnectedSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          title: const Text(
            'Device Connected',
            textAlign: TextAlign.center,
            style: TextStyle(color: darkText, fontWeight: FontWeight.w900),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: softGreen,
                child: Icon(Icons.verified_rounded, color: teal, size: 55),
              ),
              SizedBox(height: 16),
              Text(
                'This student device is now connected to the parent dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: grayText,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String formatDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final year = date.year.toString();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$month/$day/$year $hour:$minute';
    }

    return 'Not available';
  }

  String locationText(Map<String, dynamic> data) {
    final latestLocation = data['latestLocation'];

    if (latestLocation is Map) {
      final label = latestLocation['label'];
      final latitude = latestLocation['latitude'];
      final longitude = latestLocation['longitude'];

      if (label != null && label.toString().isNotEmpty) {
        return label.toString();
      }

      if (latitude != null && longitude != null) {
        return '${formatCoordinate(latitude)}, ${formatCoordinate(longitude)}';
      }
    }

    return 'Not shared yet';
  }

  String locationUpdatedText(Map<String, dynamic> data) {
    final updatedAt = data['locationUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
  }

  String formatCoordinate(dynamic value) {
    if (value is num) {
      return value.toStringAsFixed(5);
    }

    return value.toString();
  }

  bool isConnected(Map<String, dynamic> data) {
    final pairingStatus = (data['pairingStatus'] ?? '').toString();

    return pairingStatus == 'connected' ||
        data['pairedParentId'] != null ||
        data['pairedChildProfileId'] != null;
  }

  String appTitle(AppRule rule) {
    final name = rule.appName.trim();

    if (name.isNotEmpty) {
      return name;
    }

    return rule.packageName.trim().isNotEmpty
        ? rule.packageName
        : 'Unknown App';
  }

  IconData appIconForName(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('youtube')) {
      return Icons.play_arrow_rounded;
    }

    if (lower.contains('tiktok') || lower.contains('music')) {
      return Icons.music_note_rounded;
    }

    if (lower.contains('facebook') || lower.contains('meta')) {
      return Icons.public_rounded;
    }

    if (lower.contains('game') ||
        lower.contains('mobile legends') ||
        lower.contains('roblox')) {
      return Icons.sports_esports_rounded;
    }

    if (lower.contains('chrome') ||
        lower.contains('browser') ||
        lower.contains('google')) {
      return Icons.language_rounded;
    }

    if (lower.contains('message') || lower.contains('chat')) {
      return Icons.chat_bubble_rounded;
    }

    return Icons.apps_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? <String, dynamic>{};
            final connected = isConnected(data);

            if (connected) {
              _maybeSyncParentPhoneNumber(data);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _studentProfileCard(data, connected),
                const SizedBox(height: 22),
                if (!connected) _pairingCard(),
                if (!connected) const SizedBox(height: 22),
                _screenTimeAndRiskSection(),
                const SizedBox(height: 18),
                _gpsCard(data, connected),
                if (connected) const SizedBox(height: 22),
                if (connected) _smsAlertsCard(),
                if (connected) const SizedBox(height: 22),
                if (connected) _activeRulesCard(data),
                const SizedBox(height: 22),
                _topAppsSection(),
                const SizedBox(height: 22),
                _weeklyTrendSection(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: WellScreenBottomNav(
        currentIndex: currentIndex,
        items: const [
          WellScreenNavItem(icon: Icons.home_rounded, label: 'Home'),
          WellScreenNavItem(icon: Icons.link_rounded, label: 'Pairing'),
          WellScreenNavItem(icon: Icons.analytics_rounded, label: 'Reports'),
          WellScreenNavItem(icon: Icons.settings_rounded, label: 'Settings'),
        ],
        onTap: handleBottomNavTap,
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [purple, deepPurple],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          _logoBox(),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'WellScreen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileSettingsScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.account_circle_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(31),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: Image.asset(
          'assets/icons/wellscreen_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.health_and_safety_rounded,
              color: purple,
              size: 38,
            );
          },
        ),
      ),
    );
  }

  Widget _studentProfileCard(Map<String, dynamic> data, bool connected) {
    final user = FirebaseAuth.instance.currentUser;

    final fullName = (data['fullName'] ?? user?.displayName ?? 'Student User')
        .toString();

    final email = (data['email'] ?? user?.email ?? '').toString();

    final photoUrl = (data['profilePhotoUrl'] ?? user?.photoURL ?? '')
        .toString();

    return _whiteCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;

          final profileRow = Row(
            children: [
              _profileAvatar(photoUrl, connected),
              const SizedBox(width: 14),
              Expanded(
                child: _profileInfo(
                  fullName: fullName,
                  email: email,
                  connected: connected,
                ),
              ),
            ],
          );

          final buttons = Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _smallPurpleButton(
                      label: connected ? 'Share GPS' : 'Pair Device',
                      onTap: () {
                        if (connected) {
                          shareCurrentLocation(data);
                        } else {
                          showMessage('Enter the pairing code below.');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _smallPurpleButton(
                      label: 'Profile',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (connected) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _smallPurpleButton(
                    label: isSyncingUsage ? 'Syncing...' : 'Sync Usage',
                    onTap: isSyncingUsage ? null : () => syncUsageReport(data),
                  ),
                ),
                _syncStatusIndicator(),
              ],
            ],
          );

          if (compact) {
            return Column(
              children: [profileRow, const SizedBox(height: 14), buttons],
            );
          }

          return Row(
            children: [
              Expanded(child: profileRow),
              const SizedBox(width: 14),
              SizedBox(width: 250, child: buttons),
            ],
          );
        },
      ),
    );
  }

  Widget _profileAvatar(String photoUrl, bool connected) {
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundColor: connected ? softGreen : softBlue,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
                color: connected ? teal : purple,
                size: 45,
              );
            },
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 40,
      backgroundColor: connected ? softGreen : softBlue,
      child: Icon(
        connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
        color: connected ? teal : purple,
        size: 45,
      ),
    );
  }

  Widget _profileInfo({
    required String fullName,
    required String email,
    required bool connected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$fullName's Phone",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: darkText,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: connected ? teal : Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                connected ? 'Online - $email' : 'Waiting for parent pairing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: grayText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _smallPurpleButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: purple,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _pairingCard() {
    return _whiteCard(
      child: Column(
        children: [
          const Icon(Icons.link_rounded, color: purple, size: 62),
          const SizedBox(height: 12),
          const Text(
            'Connect to Parent Dashboard',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the 6-digit pairing code generated from the parent account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: pairingCodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 7,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isPairing ? null : pairWithParent,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.verified_rounded),
              label: Text(
                isPairing ? 'Connecting...' : 'Pair Student Device',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${duration.inSeconds}s';
  }

  Widget _screenTimeAndRiskSection() {
    if (_loadingUsageDashboard) {
      return const SizedBox(
        height: 170,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final state = _usageDashboardState;

    if (state == null || !state.viewModel.hasUsagePermission) {
      return _usageAccessPrompt(state);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _screenTimeCard(state)),
        const SizedBox(width: 14),
        Expanded(child: _riskCard(state)),
      ],
    );
  }

  /// Shown when Android's "Usage Access" permission (a special permission
  /// only grantable from system Settings, not a normal runtime dialog)
  /// hasn't been granted yet - real device usage stats can't be read
  /// without it. loadTodayDashboardState() (usage_dashboard_service.dart)
  /// already falls back to a cached report when this happens; if there's
  /// no cache either, this prompts the child to grant access.
  Widget _usageAccessPrompt(UsageDashboardControllerState? state) {
    return _whiteCard(
      child: Column(
        children: [
          const Icon(Icons.bar_chart_rounded, color: purple, size: 42),
          const SizedBox(height: 10),
          Text(
            state?.viewModel.errorMessage ??
                'Usage access permission is required to show real screen '
                    'time data.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: grayText, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _smallPurpleButton(
            label: 'Grant Usage Access',
            onTap: () async {
              await _usageTrackingService.openUsageAccessSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _screenTimeCard(UsageDashboardControllerState state) {
    final goal = state.screenTimeGoalResult;
    final totalLabel = state.viewModel.totalUsageLabel;
    final limitLabel = _durationLabel(state.dailyScreenTimeLimit);
    final progress = (goal?.progressPercent ?? 0).clamp(0.0, 1.0);

    return _whiteCard(
      child: SizedBox(
        height: 170,
        child: Column(
          children: [
            const Text(
              'Screen Time\nToday',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: darkText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                totalLabel,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Daily Limit: $limitLabel',
              style: const TextStyle(color: grayText, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: purple,
                backgroundColor: const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskCard(UsageDashboardControllerState state) {
    final status = state.viewModel.statusLabel;

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'Unhealthy':
        statusColor = const Color(0xFFDC2626);
        statusIcon = Icons.warning_rounded;
        break;
      case 'Warning':
        statusColor = const Color(0xFFD97706);
        statusIcon = Icons.shield_moon_rounded;
        break;
      default:
        statusColor = teal;
        statusIcon = Icons.shield_rounded;
    }

    return _whiteCard(
      child: SizedBox(
        height: 170,
        child: Column(
          children: [
            const Text(
              'Usage Pattern',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: darkText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Icon(statusIcon, color: statusColor, size: 62),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                state.viewModel.unhealthyAppCountLabel,
                style: const TextStyle(
                  color: darkText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard(Map<String, dynamic> data, bool connected) {
    final location = locationText(data);
    final updated = locationUpdatedText(data);

    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: connected ? softGreen : softRed,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              connected
                  ? Icons.location_on_rounded
                  : Icons.location_off_rounded,
              color: connected ? teal : Colors.redAccent,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GPS Location',
                  style: TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  connected ? location : 'Pair device first',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  connected
                      ? 'Updated: $updated'
                      : 'Location sharing becomes available after pairing.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: connected && !isSharingLocation
                ? () => shareCurrentLocation(data)
                : null,
            icon: Icon(
              isSharingLocation
                  ? Icons.sync_rounded
                  : Icons.my_location_rounded,
              color: connected ? purple : grayText,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact real online/offline + last-sync-outcome line shown right under
  /// the Sync Usage button, sourced from SyncStatusService (_isOnline) and
  /// _recordSyncOutcome's local log (_syncLog) - not a decorative always-on
  /// indicator. Full history with response/recovery times lives in
  /// AlertsReportsScreen's Synchronization Status card.
  Widget _syncStatusIndicator() {
    final lastOutcome =
        _syncLog.isNotEmpty ? _syncLog.last['outcome']?.toString() : null;

    String label;
    if (!_isOnline) {
      label = 'Offline - usage data will sync automatically once '
          'reconnected.';
    } else if (lastOutcome == 'synced') {
      label = 'Online - last sync succeeded.';
    } else if (lastOutcome == 'queued_offline' ||
        lastOutcome == 'failed_timeout') {
      label = 'Online - retrying a queued sync from earlier...';
    } else if (lastOutcome != null) {
      label = 'Online - last sync failed. Tap Sync Usage to retry.';
    } else {
      label = 'Online';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: _isOnline ? teal : Colors.redAccent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: grayText, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Backup SMS alert status. The actual send happens natively (see
  /// SmsAlertSender.kt, triggered from WellScreenAccessibilityService when
  /// a restricted app is blocked) so it keeps working even if this Flutter
  /// screen isn't open - this card only shows whether it's actually able to
  /// fire (permission + a cached parent phone number) and a running tally
  /// from the real local delivery log.
  Widget _smsAlertsCard() {
    final hasPhoneNumber = _cachedParentPhoneNumber != null;
    final sentCount = _smsAlertLog
        .where((entry) =>
            entry['outcome'] == 'sent' || entry['outcome'] == 'delivered')
        .length;
    final failedCount = _smsAlertLog
        .where((entry) => (entry['outcome'] as String? ?? '').startsWith('failed'))
        .length;

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sms_rounded, color: purple, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SMS Backup Alerts',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !_smsPermissionGranted
                ? 'Off. Grant SMS permission so a backup text alert can '
                    'reach your parent even without internet, when a '
                    'restricted app is opened.'
                : hasPhoneNumber
                    ? 'Enabled. Blocked-app alerts will text '
                        '${_maskPhoneNumber(_cachedParentPhoneNumber!)}.'
                    : 'Permission granted, but your parent hasn\'t added a '
                        'phone number yet in their Profile Settings.',
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (!_smsPermissionGranted) ...[
            const SizedBox(height: 12),
            _smallPurpleButton(
              label: 'Enable SMS Alerts',
              onTap: _requestSmsPermission,
            ),
          ],
          if (_smsAlertLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Recent attempts: $sentCount sent, $failedCount failed',
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activeRulesCard(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString();

    if (parentId.isEmpty) {
      return _rulesMessageCard(
        icon: Icons.sync_problem_rounded,
        title: 'Rules Sync Waiting',
        message:
            'The parent account is connected, but the rule source is not ready yet.',
      );
    }

    return StreamBuilder<List<AppRule>>(
      stream: _rulesService.watchRulesForParent(parentId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _rulesMessageCard(
            icon: Icons.warning_rounded,
            title: 'Rules Sync Error',
            message: 'Unable to load monitored and restricted apps right now.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _whiteCard(
            child: const Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: purple,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Loading parent app rules...',
                    style: TextStyle(
                      color: grayText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final rules = snapshot.data ?? <AppRule>[];

        final activeRules =
            rules
                .where((rule) => rule.monitorEnabled || rule.restrictEnabled)
                .toList()
              ..sort(
                (a, b) => appTitle(
                  a,
                ).toLowerCase().compareTo(appTitle(b).toLowerCase()),
              );

        final monitoredCount = activeRules
            .where((rule) => rule.monitorEnabled)
            .length;

        final restrictedCount = activeRules
            .where((rule) => rule.restrictEnabled)
            .length;

        final restrictedRules = activeRules
            .where((rule) => rule.restrictEnabled)
            .toList();

        final monitoredOnlyRules = activeRules
            .where((rule) => rule.monitorEnabled && !rule.restrictEnabled)
            .toList();

        if (activeRules.isEmpty) {
          return _rulesMessageCard(
            icon: Icons.rule_folder_rounded,
            title: 'No Active App Rules',
            message:
                'When the parent selects Monitor or Restrict in View Rules, the apps will appear here.',
          );
        }

        return _whiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: softBlue,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: purple,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parent App Rules',
                          style: TextStyle(
                            color: darkText,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Synced from parent dashboard',
                          style: TextStyle(
                            color: grayText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ruleCountBadge(
                      label: 'Monitored',
                      count: monitoredCount,
                      icon: Icons.visibility_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ruleCountBadge(
                      label: 'Restricted',
                      count: restrictedCount,
                      icon: Icons.block_rounded,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              if (restrictedRules.isNotEmpty) const SizedBox(height: 18),
              if (restrictedRules.isNotEmpty)
                _appRuleGroup(
                  title: 'Restricted Apps',
                  rules: restrictedRules,
                  color: const Color(0xFFDC2626),
                  icon: Icons.block_rounded,
                ),
              if (monitoredOnlyRules.isNotEmpty) const SizedBox(height: 18),
              if (monitoredOnlyRules.isNotEmpty)
                _appRuleGroup(
                  title: 'Monitored Apps',
                  rules: monitoredOnlyRules,
                  color: const Color(0xFF2563EB),
                  icon: Icons.visibility_rounded,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _rulesMessageCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: softBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: purple, size: 31),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: grayText,
                    height: 1.35,
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

  Widget _ruleCountBadge({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appRuleGroup({
    required String title,
    required List<AppRule> rules,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...rules.map((rule) => _appRuleRow(rule)),
      ],
    );
  }

  Widget _appRuleRow(AppRule rule) {
    final name = appTitle(rule);
    final restricted = rule.restrictEnabled;
    final color = restricted
        ? const Color(0xFFDC2626)
        : const Color(0xFF2563EB);

    final status = restricted
        ? rule.monitorEnabled
              ? 'Blocked + Monitored'
              : 'Blocked'
        : 'Monitored';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: color,
            child: Icon(appIconForName(name), color: Colors.white, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rule.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Was explicitly labeled "Demo Data" with four hardcoded rows - honest
  /// about being fake, but still fake. Now reads
  /// UsageDashboardControllerState.appUsageList, the real top-10
  /// UsageStats-backed list loaded in _loadUsageDashboard().
  Widget _topAppsSection() {
    final apps = (_usageDashboardState?.appUsageList ?? []).take(4).toList();
    final maxDurationMs = apps
        .map((app) => app.usageDuration.inMilliseconds)
        .fold<int>(0, (highest, value) => value > highest ? value : highest);

    return _whiteCard(
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Top Apps Today',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingUsageDashboard)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No app usage recorded yet today.',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
              ),
            )
          else
            ...apps.map((app) {
              final ratio = maxDurationMs > 0
                  ? app.usageDuration.inMilliseconds / maxDurationMs
                  : 0.0;

              return _appUsageRow(
                icon: _iconForAppName(app.displayName),
                iconColor: purple,
                appName: app.displayName,
                time: app.usageLabel,
                value: ratio.clamp(0.0, 1.0),
              );
            }),
        ],
      ),
    );
  }

  IconData _iconForAppName(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('youtube') || lower.contains('video')) {
      return Icons.play_arrow_rounded;
    }
    if (lower.contains('tiktok') || lower.contains('music')) {
      return Icons.music_note_rounded;
    }
    if (lower.contains('facebook') ||
        lower.contains('chrome') ||
        lower.contains('browser')) {
      return Icons.public_rounded;
    }
    if (lower.contains('game') ||
        lower.contains('legends') ||
        lower.contains('pubg')) {
      return Icons.sports_esports_rounded;
    }

    return Icons.apps_rounded;
  }

  Widget _appUsageRow({
    required IconData icon,
    required Color iconColor,
    required String appName,
    required String time,
    required double value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: iconColor,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    color: purple,
                    backgroundColor: const Color(0xFFD1D5DB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Same fabricated Mon-Sun bar chart as the parent dashboard's version -
  /// see the note on ParentDashboardScreen._weeklyTrendSection. No daily
  /// history is stored yet, so this is an honest placeholder instead.
  Widget _weeklyTrendSection() {
    return _whiteCard(
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Weekly Trend',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Icon(Icons.bar_chart_rounded, color: grayText, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Weekly trends aren\'t available yet',
            textAlign: TextAlign.center,
            style: TextStyle(color: darkText, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'This needs several days of usage reports stored per day. '
            'Today\'s data only, for now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}
