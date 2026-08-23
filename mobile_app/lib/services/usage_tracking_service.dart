import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'local_usage_report_cache_service.dart';
import 'usage_report_service.dart';

class UsageTrackingService {
  UsageTrackingService({
    UsageReportService? usageReportService,
    LocalUsageReportCacheService? localUsageReportCacheService,
  }) : _usageReportService = usageReportService ?? UsageReportService(),
       _localUsageReportCacheService =
           localUsageReportCacheService ?? LocalUsageReportCacheService();

  static const MethodChannel _appInfoChannel = MethodChannel(
    'com.wellscreen.app/app_info',
  );

  final UsageReportService _usageReportService;
  final LocalUsageReportCacheService _localUsageReportCacheService;

  final Map<String, String> _applicationLabelCache = {};

  Future<bool> hasUsagePermission() async {
    final granted = await UsageStats.checkUsagePermission();

    return granted == true;
  }

  Future<void> openUsageAccessSettings() async {
    await UsageStats.grantUsagePermission();
  }

  /// Returns all available usage recorded for today from midnight until now.
  ///
  /// Android UsageStats is stored locally by Android, so usage that happens
  /// while the device has no internet connection can still be included here
  /// once WellScreen queries the device again.
  Future<List<AppUsageSummary>> getTodayUsage() {
    return getUsageForDate(DateTime.now());
  }

  /// Returns usage for one calendar day.
  ///
  /// For today:
  ///   midnight -> current time
  ///
  /// For a previous day:
  ///   midnight -> end of that calendar day
  ///
  /// This allows WellScreen to regenerate reports for days that could not be
  /// uploaded while the child device was offline.
  Future<List<AppUsageSummary>> getUsageForDate(DateTime date) async {
    final now = DateTime.now();

    final requestedDay = _startOfDay(date);
    final today = _startOfDay(now);

    if (requestedDay.isAfter(today)) {
      throw ArgumentError('Cannot load usage data for a future date.');
    }

    final start = requestedDay;

    final end = requestedDay == today
        ? now
        : requestedDay
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));

    return _getUsageBetween(start, end);
  }

  Future<List<AppUsageSummary>> _getUsageBetween(
    DateTime start,
    DateTime end,
  ) async {
    final usageMap = await UsageStats.queryAndAggregateUsageStats(start, end);

    final summaries = <AppUsageSummary>[];

    for (final entry in usageMap.entries) {
      final packageName = entry.key;
      final usageInfo = entry.value;

      final usageMilliseconds =
          int.tryParse(usageInfo.totalTimeInForeground ?? '0') ?? 0;

      if (usageMilliseconds <= 0) {
        continue;
      }

      final displayName = await _getApplicationLabel(packageName);

      summaries.add(
        AppUsageSummary(
          packageName: packageName,
          displayName: displayName,
          usageDuration: Duration(milliseconds: usageMilliseconds),
        ),
      );
    }

    summaries.sort((a, b) => b.usageDuration.compareTo(a.usageDuration));

    return summaries.take(10).toList();
  }

  Future<String> _getApplicationLabel(String packageName) async {
    final cached = _applicationLabelCache[packageName];

    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final label = await _appInfoChannel.invokeMethod<String>(
        'getApplicationLabel',
        {'packageName': packageName},
      );

      if (label != null && label.trim().isNotEmpty && label != packageName) {
        final cleanedLabel = label.trim();

        _applicationLabelCache[packageName] = cleanedLabel;

        return cleanedLabel;
      }
    } on PlatformException {
      // Fall back to package-name formatting.
    } on MissingPluginException {
      // Useful during tests or unsupported platforms.
    }

    final fallback = _makeReadableAppName(packageName);

    _applicationLabelCache[packageName] = fallback;

    return fallback;
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

  DateTime _startOfDay(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  String _makeReadableAppName(String packageName) {
    final knownPackages = <String, String>{
      'com.facebook.katana': 'Facebook',
      'com.facebook.orca': 'Messenger',
      'com.android.chrome': 'Chrome',
      'com.google.android.youtube': 'YouTube',
      'com.supercell.clashofclans': 'Clash of Clans',
      'com.mobile.legends': 'Mobile Legends',
    };

    final knownName = knownPackages[packageName];

    if (knownName != null) {
      return knownName;
    }

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
