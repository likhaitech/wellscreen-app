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

    // usage_stats' UsageInfo stores totalTimeInForeground as a String (its
    // own API choice, not this app's), so the only thing extracted from it
    // here is that one already-parsed number - everything else this
    // method does (readable-name conversion, filtering, sorting, take-10)
    // is plain-Dart logic with no dependency on the native plugin's types,
    // and lives in summarizeUsage() below specifically so it can be
    // exercised directly in tests without needing a fake UsageInfo.
    final usageMillisecondsByPackage = <String, int>{
      for (final entry in usageMap.entries)
        entry.key: int.tryParse(entry.value.totalTimeInForeground ?? '0') ?? 0,
    };

    return summarizeUsage(usageMillisecondsByPackage);
  }

  /// The pure part of getTodayUsage(): turns raw per-package foreground
  /// milliseconds into the sorted, capped, human-readable summary list the
  /// UI actually shows. Deliberately takes a plain `Map<String, int>` rather
  /// than the native plugin's UsageInfo type, so this can be tested
  /// directly with plain Dart values instead of needing a fake for a
  /// third-party plugin class.
  List<AppUsageSummary> summarizeUsage(
    Map<String, int> usageMillisecondsByPackage,
  ) {
    final summaries = <AppUsageSummary>[];

    for (final entry in usageMillisecondsByPackage.entries) {
      final packageName = entry.key;
      final usageMilliseconds = entry.value;

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