import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'age_based_screen_time_threshold_service.dart';
import 'local_usage_report_cache_service.dart';
import 'usage_report_service.dart';
import 'usage_tracking_service.dart';

class FirestoreUsageReportSyncResult {
  const FirestoreUsageReportSyncResult({
    required this.parentId,
    required this.childId,
    required this.childUserId,
    required this.reportDate,
    required this.report,
    required this.appUsageList,
  });

  final String parentId;
  final String childId;
  final String childUserId;
  final String reportDate;
  final UsageReport report;
  final List<AppUsageSummary> appUsageList;

  String get reportPath {
    return 'child_usage_reports/$childId/daily_reports/$reportDate';
  }
}

class FirestoreUsageCatchUpSyncResult {
  const FirestoreUsageCatchUpSyncResult({
    required this.syncedReports,
    required this.pendingDates,
  });

  final List<FirestoreUsageReportSyncResult> syncedReports;
  final List<DateTime> pendingDates;

  int get syncedCount => syncedReports.length;

  bool get hasPendingDates => pendingDates.isNotEmpty;
}

class FirestoreUsageReportSyncService {
  FirestoreUsageReportSyncService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    UsageTrackingService? usageTrackingService,
    UsageReportService? usageReportService,
    AgeBasedScreenTimeThresholdService? ageThresholdService,
    LocalUsageReportCacheService? localUsageReportCacheService,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _usageTrackingService = usageTrackingService ?? UsageTrackingService(),
       _usageReportService = usageReportService ?? UsageReportService(),
       _ageThresholdService =
           ageThresholdService ?? AgeBasedScreenTimeThresholdService(),
       _localUsageReportCacheService =
           localUsageReportCacheService ?? LocalUsageReportCacheService();

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final UsageTrackingService _usageTrackingService;
  final UsageReportService _usageReportService;
  final AgeBasedScreenTimeThresholdService _ageThresholdService;
  final LocalUsageReportCacheService _localUsageReportCacheService;

  /// Keeps the existing manual "sync today" behavior.
  Future<FirestoreUsageReportSyncResult> syncTodayUsageReport() {
    return syncUsageReportForDate(DateTime.now());
  }

  /// Synchronizes one specific calendar day.
  ///
  /// This allows WellScreen to recreate reports for usage that happened
  /// while the child device was offline.
  Future<FirestoreUsageReportSyncResult> syncUsageReportForDate(
    DateTime date,
  ) async {
    final context = await _loadSyncContext();

    return _syncUsageReportForDateWithContext(date, context);
  }

  /// Synchronizes all dates that may have been missed while offline.
  ///
  /// Behavior:
  /// - Pending dates are retried.
  /// - Dates after the last successful sync are backfilled.
  /// - Today is always synchronized again so same-day offline usage
  ///   is included after reconnecting.
  /// - Failed dates remain in the persistent pending queue.
  Future<FirestoreUsageCatchUpSyncResult>
  syncPendingAndCatchUpUsageReports() async {
    final context = await _loadSyncContext();

    final today = _startOfDay(DateTime.now());

    final pendingDates = await _localUsageReportCacheService
        .getPendingUsageSyncDates();

    final localLastSuccessful = await _localUsageReportCacheService
        .getLastSuccessfulUsageSyncDate();

    final remoteLastSuccessful = _parseDate(
      context.childDeviceData['lastUsageReportDate'] as String?,
    );

    final lastSuccessful = _latestDate(
      localLastSuccessful,
      remoteLastSuccessful,
    );

    final datesByKey = <String, DateTime>{};

    for (final pendingDate in pendingDates) {
      final normalized = _startOfDay(pendingDate);

      if (!normalized.isAfter(today)) {
        datesByKey[_formatDate(normalized)] = normalized;
      }
    }

    if (lastSuccessful != null) {
      var date = _startOfDay(lastSuccessful);

      if (date.isBefore(today)) {
        date = date.add(const Duration(days: 1));
      } else {
        date = today;
      }

      while (!date.isAfter(today)) {
        datesByKey[_formatDate(date)] = date;

        date = date.add(const Duration(days: 1));
      }
    } else {
      datesByKey[_formatDate(today)] = today;
    }

    // Always re-sync today.
    //
    // Example:
    // 9 AM  -> report synced
    // 9-11  -> internet offline
    // 11 AM -> internet returns
    //
    // Re-reading today's Android UsageStats updates the same Firestore
    // daily report with usage accumulated during the offline period.
    datesByKey[_formatDate(today)] = today;

    final datesToSync = datesByKey.values.toList()..sort();

    await _localUsageReportCacheService.addPendingUsageSyncDates(datesToSync);

    final syncedReports = <FirestoreUsageReportSyncResult>[];

    for (final date in datesToSync) {
      try {
        final result = await _syncUsageReportForDateWithContext(date, context);

        syncedReports.add(result);

        await _localUsageReportCacheService.removePendingUsageSyncDate(date);

        final previousLastSuccessful = await _localUsageReportCacheService
            .getLastSuccessfulUsageSyncDate();

        if (previousLastSuccessful == null ||
            date.isAfter(previousLastSuccessful)) {
          await _localUsageReportCacheService.saveLastSuccessfulUsageSyncDate(
            date,
          );
        }
      } catch (_) {
        // Keep this date in the pending queue.
        //
        // A later reconnect/start/resume attempt can safely retry it because
        // the Firestore document ID is the YYYY-MM-DD report date.
      }
    }

    final remainingPendingDates = await _localUsageReportCacheService
        .getPendingUsageSyncDates();

    return FirestoreUsageCatchUpSyncResult(
      syncedReports: syncedReports,
      pendingDates: remainingPendingDates,
    );
  }

  Future<_UsageSyncContext> _loadSyncContext() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('Please log in before syncing usage reports.');
    }

    final childDeviceRef = _firestore.collection('child_devices').doc(user.uid);

    final childDeviceSnapshot = await childDeviceRef.get();

    final childDeviceData = childDeviceSnapshot.data();

    if (childDeviceData == null) {
      throw Exception(
        'This child device is not paired yet. '
        'Enter the parent pairing code first.',
      );
    }

    final parentId = childDeviceData['parentId'] as String?;
    final childId = childDeviceData['childId'] as String?;

    if (parentId == null || parentId.isEmpty) {
      throw Exception('Parent account reference is missing.');
    }

    if (childId == null || childId.isEmpty) {
      throw Exception('Child profile reference is missing.');
    }

    final hasPermission = await _usageTrackingService.hasUsagePermission();

    if (!hasPermission) {
      throw Exception(
        'Usage access permission is required before syncing usage reports.',
      );
    }

    final childProfileRef = _firestore
        .collection('child_profiles')
        .doc(childId);

    final childProfileSnapshot = await childProfileRef.get();

    final childProfileData = childProfileSnapshot.data();

    final childAge = _readIntOrNull(childProfileData?['age']);

    return _UsageSyncContext(
      user: user,
      childDeviceRef: childDeviceRef,
      childProfileRef: childProfileRef,
      childDeviceData: childDeviceData,
      parentId: parentId,
      childId: childId,
      childAge: childAge,
    );
  }

  Future<FirestoreUsageReportSyncResult> _syncUsageReportForDateWithContext(
    DateTime date,
    _UsageSyncContext context,
  ) async {
    final reportDay = _startOfDay(date);
    final today = _startOfDay(DateTime.now());

    if (reportDay.isAfter(today)) {
      throw ArgumentError(
        'Cannot synchronize a usage report for a future date.',
      );
    }

    final reportDate = _formatDate(reportDay);

    final ageThreshold = _ageThresholdService.getThresholdForAge(
      context.childAge,
    );

    final appUsageList = await _usageTrackingService.getUsageForDate(reportDay);

    final report = _usageReportService.generateFromSummaries(
      appUsageList,
      childAge: context.childAge,
    );

    final childUsageReportRef = _firestore
        .collection('child_usage_reports')
        .doc(context.childId);

    final dailyReportRef = childUsageReportRef
        .collection('daily_reports')
        .doc(reportDate);

    await dailyReportRef.set({
      'parentId': context.parentId,
      'childId': context.childId,
      'childUserId': context.user.uid,
      'childEmail': context.user.email,
      'reportDate': reportDate,
      'childAge': context.childAge,
      'ageGroupLabel': ageThreshold.ageGroupLabel,
      'recommendedDailyLimitMinutes': ageThreshold.dailyLimit.inMinutes,
      'warningTotalUsageLimitMinutes': ageThreshold.warningLimit.inMinutes,
      'unhealthyTotalUsageLimitMinutes': ageThreshold.unhealthyLimit.inMinutes,
      'totalUsageDurationMs': report.totalUsageDuration.inMilliseconds,
      'totalUsageLabel': report.totalUsageLabel,
      'topUsedApp': _appUsageToMap(report.topUsedApp),
      'unhealthyAppCount': report.unhealthyAppCount,
      'riskScore': report.riskScore,
      'riskScoreLabel': report.riskScoreLabel,
      'riskLevelLabel': report.riskLevelLabel,
      'riskFactors': report.riskFactors,
      'generatedAt': Timestamp.fromDate(report.generatedAt),
      'patternStatus': report.patternStatus.name,
      'patternStatusLabel': report.patternStatus.label,
      'recommendationMessage': report.recommendationMessage,
      'appUsageList': appUsageList.map(_requiredAppUsageToMap).toList(),
      'syncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // These summary documents are updated after the dated daily document.
    //
    // Since catch-up runs from oldest -> newest, the final metadata will
    // naturally point to the newest synchronized report.
    await childUsageReportRef.set({
      'parentId': context.parentId,
      'childId': context.childId,
      'childUserId': context.user.uid,
      'childEmail': context.user.email,
      'lastReportDate': reportDate,
      'lastChildAge': context.childAge,
      'lastAgeGroupLabel': ageThreshold.ageGroupLabel,
      'lastRecommendedDailyLimitMinutes': ageThreshold.dailyLimit.inMinutes,
      'lastRiskScore': report.riskScore,
      'lastRiskScoreLabel': report.riskScoreLabel,
      'lastRiskLevelLabel': report.riskLevelLabel,
      'lastSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await context.childDeviceRef.set({
      'deviceStatus': 'connected',
      'lastUsageReportDate': reportDate,
      'lastUsageReportSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await context.childProfileRef.set({
      'deviceStatus': 'connected',
      'lastUsageReportDate': reportDate,
      'lastUsageReportSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Save today's generated report to the existing local dashboard cache.
    if (reportDay == today) {
      await _localUsageReportCacheService.saveTodayReport(report);
    }

    return FirestoreUsageReportSyncResult(
      parentId: context.parentId,
      childId: context.childId,
      childUserId: context.user.uid,
      reportDate: reportDate,
      report: report,
      appUsageList: appUsageList,
    );
  }

  Map<String, dynamic>? _appUsageToMap(AppUsageSummary? appUsage) {
    if (appUsage == null) {
      return null;
    }

    return _requiredAppUsageToMap(appUsage);
  }

  Map<String, dynamic> _requiredAppUsageToMap(AppUsageSummary appUsage) {
    return {
      'packageName': appUsage.packageName,
      'displayName': appUsage.displayName,
      'usageDurationMs': appUsage.usageDuration.inMilliseconds,
      'usageLabel': appUsage.usageLabel,
      'lastTimeUsed': appUsage.lastTimeUsed == null
          ? null
          : Timestamp.fromDate(appUsage.lastTimeUsed!),
    };
  }

  int? _readIntOrNull(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      return null;
    }

    return _startOfDay(parsed);
  }

  DateTime? _latestDate(DateTime? first, DateTime? second) {
    if (first == null) {
      return second;
    }

    if (second == null) {
      return first;
    }

    return first.isAfter(second) ? first : second;
  }

  DateTime _startOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');

    final month = dateTime.month.toString().padLeft(2, '0');

    final day = dateTime.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}

class _UsageSyncContext {
  const _UsageSyncContext({
    required this.user,
    required this.childDeviceRef,
    required this.childProfileRef,
    required this.childDeviceData,
    required this.parentId,
    required this.childId,
    required this.childAge,
  });

  final User user;

  final DocumentReference<Map<String, dynamic>> childDeviceRef;

  final DocumentReference<Map<String, dynamic>> childProfileRef;

  final Map<String, dynamic> childDeviceData;

  final String parentId;
  final String childId;

  final int? childAge;
}
