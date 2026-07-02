import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
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

class FirestoreUsageReportSyncService {
  FirestoreUsageReportSyncService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    UsageTrackingService? usageTrackingService,
    UsageReportService? usageReportService,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _usageTrackingService = usageTrackingService ?? UsageTrackingService(),
       _usageReportService = usageReportService ?? UsageReportService();

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final UsageTrackingService _usageTrackingService;
  final UsageReportService _usageReportService;

  Future<FirestoreUsageReportSyncResult> syncTodayUsageReport() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('Please log in before syncing usage reports.');
    }

    final childDeviceRef = _firestore.collection('child_devices').doc(user.uid);
    final childDeviceSnapshot = await childDeviceRef.get();
    final childDeviceData = childDeviceSnapshot.data();

    if (childDeviceData == null) {
      throw Exception(
        'This child device is not paired yet. Enter the parent pairing code first.',
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

    final appUsageList = await _usageTrackingService.getTodayUsage();
    final report = _usageReportService.generateFromSummaries(appUsageList);
    final reportDate = _formatDate(report.generatedAt);

    final childUsageReportRef = _firestore
        .collection('child_usage_reports')
        .doc(childId);

    final dailyReportRef = childUsageReportRef
        .collection('daily_reports')
        .doc(reportDate);

    await childUsageReportRef.set({
      'parentId': parentId,
      'childId': childId,
      'childUserId': user.uid,
      'childEmail': user.email,
      'lastReportDate': reportDate,
      'lastSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await dailyReportRef.set({
      'parentId': parentId,
      'childId': childId,
      'childUserId': user.uid,
      'childEmail': user.email,
      'reportDate': reportDate,
      'totalUsageDurationMs': report.totalUsageDuration.inMilliseconds,
      'totalUsageLabel': report.totalUsageLabel,
      'topUsedApp': _appUsageToMap(report.topUsedApp),
      'unhealthyAppCount': report.unhealthyAppCount,
      'generatedAt': Timestamp.fromDate(report.generatedAt),
      'patternStatus': report.patternStatus.name,
      'patternStatusLabel': report.patternStatus.label,
      'recommendationMessage': report.recommendationMessage,
      'appUsageList': appUsageList.map(_requiredAppUsageToMap).toList(),
      'syncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await childDeviceRef.set({
      'deviceStatus': 'connected',
      'lastUsageReportDate': reportDate,
      'lastUsageReportSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('child_profiles').doc(childId).set({
      'deviceStatus': 'connected',
      'lastUsageReportDate': reportDate,
      'lastUsageReportSyncedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return FirestoreUsageReportSyncResult(
      parentId: parentId,
      childId: childId,
      childUserId: user.uid,
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

  String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
