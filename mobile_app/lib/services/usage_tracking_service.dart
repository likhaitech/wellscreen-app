import 'package:usage_stats/usage_stats.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'usage_report_service.dart';

class UsageTrackingService {
  UsageTrackingService({UsageReportService? usageReportService})
    : _usageReportService = usageReportService ?? UsageReportService();

  final UsageReportService _usageReportService;

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

    summaries.sort((a, b) => b.usageDuration.compareTo(a.usageDuration));

    return summaries.take(10).toList();
  }

  Future<UsageReport> getTodayUsageReport() async {
    final summaries = await getTodayUsage();
    return _usageReportService.generateFromSummaries(summaries);
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
