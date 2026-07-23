import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_period_summary.dart';
import '../models/usage_report.dart';

class FirestoreUsagePeriodSummaryService {
  FirestoreUsagePeriodSummaryService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<UsagePeriodSummaryBundle> getCurrentPeriodSummaries() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('Please log in before loading usage summaries.');
    }

    final childProfiles = await _loadChildProfiles(user.uid);

    if (childProfiles.isEmpty) {
      final now = DateTime.now();

      return UsagePeriodSummaryBundle(
        weeklySummary: _emptySummary(
          title: 'Weekly Usage Summary',
          childLabel: 'No paired child device',
          startDate: _startOfCurrentWeek(now),
          endDate: _endOfCurrentWeek(now),
          message:
              'No paired child profile was found. Pair a child device first, then sync daily usage reports.',
        ),
        monthlySummary: _emptySummary(
          title: 'Monthly Usage Summary',
          childLabel: 'No paired child device',
          startDate: _startOfCurrentMonth(now),
          endDate: _endOfCurrentMonth(now),
          message:
              'No paired child profile was found. Pair a child device first, then sync daily usage reports.',
        ),
      );
    }

    final dailyReports = <_DailyUsageReportRecord>[];

    for (final childProfile in childProfiles) {
      final reports = await _loadDailyReportsForChild(childProfile);
      dailyReports.addAll(reports);
    }

    final now = DateTime.now();

    return UsagePeriodSummaryBundle(
      weeklySummary: _buildSummary(
        title: 'Weekly Usage Summary',
        childProfiles: childProfiles,
        dailyReports: dailyReports,
        startDate: _startOfCurrentWeek(now),
        endDate: _endOfCurrentWeek(now),
      ),
      monthlySummary: _buildSummary(
        title: 'Monthly Usage Summary',
        childProfiles: childProfiles,
        dailyReports: dailyReports,
        startDate: _startOfCurrentMonth(now),
        endDate: _endOfCurrentMonth(now),
      ),
    );
  }

  Future<List<_ChildProfileRecord>> _loadChildProfiles(String parentId) async {
    final childProfilesSnapshot = await _firestore
        .collection('child_profiles')
        .where('parentId', isEqualTo: parentId)
        .get();

    return childProfilesSnapshot.docs.map((doc) {
      final data = doc.data();

      return _ChildProfileRecord(
        childId: data['childId'] as String? ?? doc.id,
        childName: data['name'] as String?,
        childEmail: data['childEmail'] as String?,
      );
    }).toList();
  }

  Future<List<_DailyUsageReportRecord>> _loadDailyReportsForChild(
    _ChildProfileRecord childProfile,
  ) async {
    final dailyReportsSnapshot = await _firestore
        .collection('child_usage_reports')
        .doc(childProfile.childId)
        .collection('daily_reports')
        .get();

    final reports = <_DailyUsageReportRecord>[];

    for (final doc in dailyReportsSnapshot.docs) {
      final data = doc.data();
      final reportDate = data['reportDate'] as String? ?? doc.id;
      final reportDateValue = _parseReportDate(reportDate);

      if (reportDateValue == null) {
        continue;
      }

      final patternStatusName =
          data['patternStatus'] as String? ?? UsagePatternStatus.healthy.name;

      final patternStatus = UsagePatternStatus.values.firstWhere(
        (status) => status.name == patternStatusName,
        orElse: () => UsagePatternStatus.healthy,
      );

      final appUsageListValue = data['appUsageList'];
      final appUsageList = appUsageListValue is Iterable
          ? appUsageListValue
                .map(_appUsageFromMap)
                .whereType<AppUsageSummary>()
                .toList()
          : <AppUsageSummary>[];

      final topUsedApp = _appUsageFromMap(data['topUsedApp']);

      reports.add(
        _DailyUsageReportRecord(
          childId: childProfile.childId,
          childLabel: childProfile.childLabel,
          reportDate: reportDateValue,
          totalUsageDuration: Duration(
            milliseconds: _readInt(data['totalUsageDurationMs']),
          ),
          topUsedApp: topUsedApp,
          appUsageList: appUsageList,
          patternStatus: patternStatus,
          recommendationMessage:
              data['recommendationMessage'] as String? ??
              'No recommendation available.',
        ),
      );
    }

    return reports;
  }

  UsagePeriodSummary _buildSummary({
    required String title,
    required List<_ChildProfileRecord> childProfiles,
    required List<_DailyUsageReportRecord> dailyReports,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final reportsInPeriod = dailyReports.where((report) {
      final reportDay = _startOfDay(report.reportDate);
      return !reportDay.isBefore(startDate) && !reportDay.isAfter(endDate);
    }).toList();

    final childLabel = childProfiles.length == 1
        ? childProfiles.first.childLabel
        : 'All paired child devices';

    if (reportsInPeriod.isEmpty) {
      return _emptySummary(
        title: title,
        childLabel: childLabel,
        startDate: startDate,
        endDate: endDate,
        message:
            'No synced daily usage reports were found for this period. Open the child device and sync daily usage reports first.',
      );
    }

    final totalUsageMs = reportsInPeriod.fold<int>(
      0,
      (total, report) => total + report.totalUsageDuration.inMilliseconds,
    );

    final totalUsageDuration = Duration(milliseconds: totalUsageMs);

    final averageDailyUsageDuration = Duration(
      milliseconds: totalUsageMs ~/ reportsInPeriod.length,
    );

    final unhealthyReportCount = reportsInPeriod
        .where((report) => report.patternStatus == UsagePatternStatus.unhealthy)
        .length;

    final warningReportCount = reportsInPeriod
        .where((report) => report.patternStatus == UsagePatternStatus.warning)
        .length;

    final patternStatus = _getOverallPatternStatus(
      unhealthyReportCount: unhealthyReportCount,
      warningReportCount: warningReportCount,
    );

    final topUsedApp = _getTopUsedApp(reportsInPeriod);

    return UsagePeriodSummary(
      title: title,
      childLabel: childLabel,
      startDate: startDate,
      endDate: endDate,
      reportCount: reportsInPeriod.length,
      totalUsageDuration: totalUsageDuration,
      averageDailyUsageDuration: averageDailyUsageDuration,
      topUsedApp: topUsedApp,
      patternStatus: patternStatus,
      unhealthyReportCount: unhealthyReportCount,
      warningReportCount: warningReportCount,
      chartPoints: _buildChartPoints(
        title: title,
        reportsInPeriod: reportsInPeriod,
        startDate: startDate,
        endDate: endDate,
      ),
      recommendationMessage: _buildRecommendationMessage(
        title: title,
        reportCount: reportsInPeriod.length,
        patternStatus: patternStatus,
        averageDailyUsageDuration: averageDailyUsageDuration,
      ),
    );
  }

  UsagePeriodSummary _emptySummary({
    required String title,
    required String childLabel,
    required DateTime startDate,
    required DateTime endDate,
    required String message,
  }) {
    return UsagePeriodSummary(
      title: title,
      childLabel: childLabel,
      startDate: startDate,
      endDate: endDate,
      reportCount: 0,
      totalUsageDuration: Duration.zero,
      averageDailyUsageDuration: Duration.zero,
      topUsedApp: null,
      patternStatus: null,
      unhealthyReportCount: 0,
      warningReportCount: 0,
      chartPoints: _buildChartPoints(
        title: title,
        reportsInPeriod: const [],
        startDate: startDate,
        endDate: endDate,
      ),
      recommendationMessage: message,
    );
  }

  List<UsagePeriodChartPoint> _buildChartPoints({
    required String title,
    required List<_DailyUsageReportRecord> reportsInPeriod,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final usageByDate = <String, _UsagePointAccumulator>{};

    for (final report in reportsInPeriod) {
      final reportDay = _startOfDay(report.reportDate);
      final key = _formatDateKey(reportDay);
      final existing = usageByDate[key];

      if (existing == null) {
        usageByDate[key] = _UsagePointAccumulator(
          totalUsageDuration: report.totalUsageDuration,
          patternStatus: report.patternStatus,
        );
      } else {
        usageByDate[key] = existing.copyWithAddedReport(report);
      }
    }

    final points = <UsagePeriodChartPoint>[];
    var currentDate = startDate;

    while (!currentDate.isAfter(endDate)) {
      final key = _formatDateKey(currentDate);
      final accumulator = usageByDate[key];

      points.add(
        UsagePeriodChartPoint(
          label: _formatChartLabel(title, currentDate),
          date: currentDate,
          usageDuration: accumulator?.totalUsageDuration ?? Duration.zero,
          patternStatus:
              accumulator?.patternStatus ?? UsagePatternStatus.healthy,
        ),
      );

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return points;
  }

  UsagePatternStatus _getOverallPatternStatus({
    required int unhealthyReportCount,
    required int warningReportCount,
  }) {
    if (unhealthyReportCount > 0) {
      return UsagePatternStatus.unhealthy;
    }

    if (warningReportCount > 0) {
      return UsagePatternStatus.warning;
    }

    return UsagePatternStatus.healthy;
  }

  AppUsageSummary? _getTopUsedApp(List<_DailyUsageReportRecord> reports) {
    final usageByPackage = <String, _AppUsageAccumulator>{};

    for (final report in reports) {
      final apps = report.appUsageList.isNotEmpty
          ? report.appUsageList
          : [if (report.topUsedApp != null) report.topUsedApp!];

      for (final app in apps) {
        final existing = usageByPackage[app.packageName];

        if (existing == null) {
          usageByPackage[app.packageName] = _AppUsageAccumulator(
            packageName: app.packageName,
            displayName: app.displayName,
            usageDuration: app.usageDuration,
          );
        } else {
          usageByPackage[app.packageName] = existing.copyWithAddedDuration(
            app.usageDuration,
          );
        }
      }
    }

    if (usageByPackage.isEmpty) {
      return null;
    }

    final topApp = usageByPackage.values.reduce(
      (a, b) => a.usageDuration >= b.usageDuration ? a : b,
    );

    return AppUsageSummary(
      packageName: topApp.packageName,
      displayName: topApp.displayName,
      usageDuration: topApp.usageDuration,
    );
  }

  String _buildRecommendationMessage({
    required String title,
    required int reportCount,
    required UsagePatternStatus patternStatus,
    required Duration averageDailyUsageDuration,
  }) {
    final periodLabel = title.toLowerCase();

    switch (patternStatus) {
      case UsagePatternStatus.healthy:
        return 'The $periodLabel looks healthy based on $reportCount synced daily report(s). Continue maintaining balanced screen time.';
      case UsagePatternStatus.warning:
        return 'The $periodLabel shows warning signs based on $reportCount synced daily report(s). Review app habits and consider shorter breaks or adjusted limits.';
      case UsagePatternStatus.unhealthy:
        return 'The $periodLabel includes unhealthy usage patterns based on $reportCount synced daily report(s). Review the child’s usage and apply guardian-guided rules if needed.';
    }
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

  DateTime? _parseReportDate(String value) {
    final parsedDate = DateTime.tryParse(value);

    if (parsedDate == null) {
      return null;
    }

    return _startOfDay(parsedDate);
  }

  String _formatDateKey(DateTime dateTime) {
    return UsagePeriodSummary.formatDate(_startOfDay(dateTime));
  }

  String _formatChartLabel(String title, DateTime dateTime) {
    if (title.toLowerCase().contains('monthly')) {
      return dateTime.day.toString();
    }

    switch (dateTime.weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return dateTime.day.toString();
    }
  }

  DateTime _startOfCurrentWeek(DateTime dateTime) {
    final today = _startOfDay(dateTime);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  DateTime _endOfCurrentWeek(DateTime dateTime) {
    return _startOfCurrentWeek(dateTime).add(const Duration(days: 6));
  }

  DateTime _startOfCurrentMonth(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month);
  }

  DateTime _endOfCurrentMonth(DateTime dateTime) {
    final nextMonth = dateTime.month == 12
        ? DateTime(dateTime.year + 1)
        : DateTime(dateTime.year, dateTime.month + 1);

    return nextMonth.subtract(const Duration(days: 1));
  }

  DateTime _startOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }
}

class _ChildProfileRecord {
  const _ChildProfileRecord({
    required this.childId,
    required this.childName,
    required this.childEmail,
  });

  final String childId;
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

class _DailyUsageReportRecord {
  const _DailyUsageReportRecord({
    required this.childId,
    required this.childLabel,
    required this.reportDate,
    required this.totalUsageDuration,
    required this.topUsedApp,
    required this.appUsageList,
    required this.patternStatus,
    required this.recommendationMessage,
  });

  final String childId;
  final String childLabel;
  final DateTime reportDate;
  final Duration totalUsageDuration;
  final AppUsageSummary? topUsedApp;
  final List<AppUsageSummary> appUsageList;
  final UsagePatternStatus patternStatus;
  final String recommendationMessage;
}

class _AppUsageAccumulator {
  const _AppUsageAccumulator({
    required this.packageName,
    required this.displayName,
    required this.usageDuration,
  });

  final String packageName;
  final String displayName;
  final Duration usageDuration;

  _AppUsageAccumulator copyWithAddedDuration(Duration addedDuration) {
    return _AppUsageAccumulator(
      packageName: packageName,
      displayName: displayName,
      usageDuration: usageDuration + addedDuration,
    );
  }
}

class _UsagePointAccumulator {
  const _UsagePointAccumulator({
    required this.totalUsageDuration,
    required this.patternStatus,
  });

  final Duration totalUsageDuration;
  final UsagePatternStatus patternStatus;

  _UsagePointAccumulator copyWithAddedReport(_DailyUsageReportRecord report) {
    return _UsagePointAccumulator(
      totalUsageDuration: totalUsageDuration + report.totalUsageDuration,
      patternStatus: _getMoreSevereStatus(patternStatus, report.patternStatus),
    );
  }

  UsagePatternStatus _getMoreSevereStatus(
    UsagePatternStatus currentStatus,
    UsagePatternStatus nextStatus,
  ) {
    if (currentStatus == UsagePatternStatus.unhealthy ||
        nextStatus == UsagePatternStatus.unhealthy) {
      return UsagePatternStatus.unhealthy;
    }

    if (currentStatus == UsagePatternStatus.warning ||
        nextStatus == UsagePatternStatus.warning) {
      return UsagePatternStatus.warning;
    }

    return UsagePatternStatus.healthy;
  }
}
