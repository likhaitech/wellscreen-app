import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';

class FirestoreChildUsageReportSnapshot {
  const FirestoreChildUsageReportSnapshot({
    required this.parentId,
    required this.childId,
    required this.reportDate,
    required this.report,
    required this.appUsageList,
    this.childName,
    this.childEmail,
  });

  final String parentId;
  final String childId;
  final String reportDate;
  final UsageReport report;
  final List<AppUsageSummary> appUsageList;
  final String? childName;
  final String? childEmail;

  String get childLabel {
    if (childName != null && childName!.trim().isNotEmpty) {
      return childName!;
    }

    if (childEmail != null && childEmail!.trim().isNotEmpty) {
      return childEmail!;
    }

    return 'Child Device';
  }
}

class FirestoreChildUsageReportService {
  FirestoreChildUsageReportService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<List<FirestoreChildUsageReportSnapshot>>
  getLatestReportsForCurrentParent() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('Please log in before loading child usage reports.');
    }

    final childProfilesSnapshot = await _firestore
        .collection('child_profiles')
        .where('parentId', isEqualTo: user.uid)
        .get();

    final reports = <FirestoreChildUsageReportSnapshot>[];

    for (final childDoc in childProfilesSnapshot.docs) {
      final childData = childDoc.data();
      final childId = childData['childId'] as String? ?? childDoc.id;

      final reportHeaderSnapshot = await _firestore
          .collection('child_usage_reports')
          .doc(childId)
          .get();

      final reportHeaderData = reportHeaderSnapshot.data();
      final lastReportDate = reportHeaderData?['lastReportDate'] as String?;

      if (lastReportDate == null || lastReportDate.isEmpty) {
        continue;
      }

      final dailyReportSnapshot = await _firestore
          .collection('child_usage_reports')
          .doc(childId)
          .collection('daily_reports')
          .doc(lastReportDate)
          .get();

      final dailyReportData = dailyReportSnapshot.data();

      if (dailyReportData == null) {
        continue;
      }

      reports.add(
        _snapshotFromData(
          parentId: user.uid,
          childId: childId,
          childData: childData,
          reportDate: lastReportDate,
          reportData: dailyReportData,
        ),
      );
    }

    reports.sort(
      (a, b) => b.report.generatedAt.compareTo(a.report.generatedAt),
    );

    return reports;
  }

  Future<FirestoreChildUsageReportSnapshot?>
  getLatestReportForCurrentParent() async {
    final reports = await getLatestReportsForCurrentParent();

    if (reports.isEmpty) {
      return null;
    }

    return reports.first;
  }

  FirestoreChildUsageReportSnapshot _snapshotFromData({
    required String parentId,
    required String childId,
    required Map<String, dynamic> childData,
    required String reportDate,
    required Map<String, dynamic> reportData,
  }) {
    final patternStatusName =
        reportData['patternStatus'] as String? ?? 'healthy';

    final patternStatus = UsagePatternStatus.values.firstWhere(
      (status) => status.name == patternStatusName,
      orElse: () => UsagePatternStatus.healthy,
    );

    final generatedAtValue = reportData['generatedAt'];
    final generatedAt = generatedAtValue is Timestamp
        ? generatedAtValue.toDate()
        : DateTime.now();

    final topUsedApp = _appUsageFromMap(reportData['topUsedApp']);

    final appUsageListValue = reportData['appUsageList'];
    final appUsageList = appUsageListValue is Iterable
        ? appUsageListValue
              .map(_appUsageFromMap)
              .whereType<AppUsageSummary>()
              .toList()
        : <AppUsageSummary>[];

    final report = UsageReport(
      totalUsageDuration: Duration(
        milliseconds: _readInt(reportData['totalUsageDurationMs']),
      ),
      topUsedApp: topUsedApp,
      unhealthyAppCount: _readInt(reportData['unhealthyAppCount']),
      generatedAt: generatedAt,
      patternStatus: patternStatus,
      recommendationMessage:
          reportData['recommendationMessage'] as String? ??
          'No recommendation available.',
    );

    return FirestoreChildUsageReportSnapshot(
      parentId: parentId,
      childId: childId,
      reportDate: reportDate,
      report: report,
      appUsageList: appUsageList,
      childName: childData['name'] as String?,
      childEmail: childData['childEmail'] as String?,
    );
  }

  AppUsageSummary? _appUsageFromMap(Object? value) {
    if (value == null || value is! Map) {
      return null;
    }

    final data = Map<String, dynamic>.from(value);

    final packageName = data['packageName'] as String?;
    final displayName = data['displayName'] as String?;
    final usageDurationMs = _readInt(data['usageDurationMs']);

    if (packageName == null || displayName == null) {
      return null;
    }

    final lastTimeUsedValue = data['lastTimeUsed'];
    final lastTimeUsed = lastTimeUsedValue is Timestamp
        ? lastTimeUsedValue.toDate()
        : null;

    return AppUsageSummary(
      packageName: packageName,
      displayName: displayName,
      usageDuration: Duration(milliseconds: usageDurationMs),
      lastTimeUsed: lastTimeUsed,
    );
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }
}
