import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> clearTodayReport() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_todayUsageReportKey);
  }
}
