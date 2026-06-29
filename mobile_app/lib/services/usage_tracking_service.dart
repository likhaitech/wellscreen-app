import 'package:usage_stats/usage_stats.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'local_usage_report_cache_service.dart';
import 'usage_report_service.dart';

class UsageTrackingService {
  UsageTrackingService({
    UsageReportService? usageReportService,
    LocalUsageReportCacheService? localUsageReportCacheService,
  })  : _usageReportService = usageReportService ?? UsageReportService(),
        _localUsageReportCacheService =
            localUsageReportCacheService ?? LocalUsageReportCacheService();

  final UsageReportService _usageReportService;
  final LocalUsageReportCacheService _localUsageReportCacheService;

  Future<bool> hasUsagePermission() async {
    final granted = await UsageStats.checkUsagePermission();
    return granted == true;
  }

  Future<void> openUsageAccessSettings() async {
    await UsageStats.grantUsagePermission();
  }

  Future<List<AppUsageSummary>> getTodayUsage() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final usageMap = await UsageStats.queryAndAggregateUsageStats(
      startOfDay,
      now,
    );

    final summaries = <AppUsageSummary>[];

    for (final entry in usageMap.entries) {
      final packageName = entry.key;
      final usageInfo = entry.value;

      final usageMilliseconds =
          int.tryParse(usageInfo.totalTimeInForeground ?? '0') ?? 0;

      if (usageMilliseconds <= 0) {
        continue;
      }

      summaries.add(
        AppUsageSummary(
          packageName: packageName,
          displayName: _makeReadableAppName(packageName),
          usageDuration: Duration(milliseconds: usageMilliseconds),
        ),
      );
    }

    summaries.sort(
      (a, b) => b.usageDuration.compareTo(a.usageDuration),
    );

    return summaries.take(10).toList();
  }

  Future<UsageReport> getTodayUsageReport() async {
    final summaries = await getTodayUsage();
    final report = _usageReportService.generateFromSummaries(summaries);

    await _localUsageReportCacheService.saveTodayReport(report);

    return report;
  }

  Future<UsageReport?> getCachedTodayUsageReport() {
    return _localUsageReportCacheService.getCachedTodayReport();
  }

  Future<Map<String, dynamic>?> getCachedTodayUsageReportData() {
    return _localUsageReportCacheService.getCachedTodayReportData();
  }

  String _makeReadableAppName(String packageName) {
    final parts = packageName.split('.');

    if (parts.isEmpty) {
      return packageName;
    }

    final appName = parts.last;

    if (appName.isEmpty) {
      return packageName;
    }

    return appName[0].toUpperCase() + appName.substring(1);
  }
}