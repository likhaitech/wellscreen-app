import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';

class LocalUsageReportCacheService {
  static const String _todayUsageReportKey = 'today_usage_report';

  Future<void> saveTodayReport(UsageReport report) async {
    final preferences = await SharedPreferences.getInstance();

    final data = {
      'totalUsageDurationMs': report.totalUsageDuration.inMilliseconds,
      'topUsedAppPackageName': report.topUsedApp?.packageName,
      'topUsedAppDisplayName': report.topUsedApp?.displayName,
      'topUsedAppUsageDurationMs':
          report.topUsedApp?.usageDuration.inMilliseconds,
      'unhealthyAppCount': report.unhealthyAppCount,
      'generatedAt': report.generatedAt.toIso8601String(),
      'patternStatus': report.patternStatus.name,
      'recommendationMessage': report.recommendationMessage,
    };

    await preferences.setString(_todayUsageReportKey, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> getCachedTodayReportData() async {
    final preferences = await SharedPreferences.getInstance();
    final cachedValue = preferences.getString(_todayUsageReportKey);

    if (cachedValue == null || cachedValue.isEmpty) {
      return null;
    }

    final decodedValue = jsonDecode(cachedValue);

    if (decodedValue is! Map<String, dynamic>) {
      return null;
    }

    return decodedValue;
  }

  Future<UsageReport?> getCachedTodayReport() async {
    final data = await getCachedTodayReportData();

    if (data == null) {
      return null;
    }

    final topUsedAppPackageName = data['topUsedAppPackageName'] as String?;
    final topUsedAppDisplayName = data['topUsedAppDisplayName'] as String?;
    final topUsedAppUsageDurationMs =
        data['topUsedAppUsageDurationMs'] as int?;

    AppUsageSummary? topUsedApp;

    if (topUsedAppPackageName != null &&
        topUsedAppDisplayName != null &&
        topUsedAppUsageDurationMs != null) {
      topUsedApp = AppUsageSummary(
        packageName: topUsedAppPackageName,
        displayName: topUsedAppDisplayName,
        usageDuration: Duration(milliseconds: topUsedAppUsageDurationMs),
      );
    }

    final patternStatusName = data['patternStatus'] as String? ?? 'healthy';

    final patternStatus = UsagePatternStatus.values.firstWhere(
      (status) => status.name == patternStatusName,
      orElse: () => UsagePatternStatus.healthy,
    );

    return UsageReport(
      totalUsageDuration: Duration(
        milliseconds: data['totalUsageDurationMs'] as int? ?? 0,
      ),
      topUsedApp: topUsedApp,
      unhealthyAppCount: data['unhealthyAppCount'] as int? ?? 0,
      generatedAt: DateTime.tryParse(data['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      patternStatus: patternStatus,
      recommendationMessage: data['recommendationMessage'] as String? ??
          'No recommendation available.',
    );
  }

  Future<void> clearTodayReport() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_todayUsageReportKey);
  }
}