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
      'riskScore': report.riskScore,
      'riskFactors': report.riskFactors,
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

    if (decodedValue is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(decodedValue);
  }

  Future<UsageReport?> getCachedTodayReport() async {
    final data = await getCachedTodayReportData();

    if (data == null) {
      return null;
    }

    final topUsedAppPackageName = data['topUsedAppPackageName'] as String?;
    final topUsedAppDisplayName = data['topUsedAppDisplayName'] as String?;
    final topUsedAppUsageDurationMs = _readInt(
      data['topUsedAppUsageDurationMs'],
    );

    AppUsageSummary? topUsedApp;

    if (topUsedAppPackageName != null &&
        topUsedAppDisplayName != null &&
        topUsedAppUsageDurationMs > 0) {
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
        milliseconds: _readInt(data['totalUsageDurationMs']),
      ),
      topUsedApp: topUsedApp,
      unhealthyAppCount: _readInt(data['unhealthyAppCount']),
      generatedAt:
          DateTime.tryParse(data['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      patternStatus: patternStatus,
      recommendationMessage:
          data['recommendationMessage'] as String? ??
          'No recommendation available.',
      riskScore: _readInt(data['riskScore']),
      riskFactors: _readStringList(data['riskFactors']),
    );
  }

  Future<void> clearTodayReport() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_todayUsageReportKey);
  }

  List<String> _readStringList(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toList();
    }

    return const [];
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
