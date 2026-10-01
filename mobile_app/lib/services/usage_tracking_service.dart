import 'package:usage_stats/usage_stats.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'local_usage_report_cache_service.dart';
import 'usage_report_service.dart';

/// A single raw usage event, reduced to the three fields
/// countMaxAppOpens() actually needs. Deliberately plain (a Dart 3
/// record) rather than the usage_stats plugin's own EventUsageInfo type,
/// for the same testability reason summarizeUsage() takes a plain
/// `Map<String, int>` instead of UsageInfo - see getTodayMaxAppOpenCount()
/// below for how a real EventUsageInfo list is reduced to this shape.
typedef UsageEventRecord = ({
  String packageName,
  int eventType,
  int timestampMs,
});

class UsageTrackingService {
  UsageTrackingService({
    UsageReportService? usageReportService,
    LocalUsageReportCacheService? localUsageReportCacheService,
  })  : _usageReportService = usageReportService ?? UsageReportService(),
        _localUsageReportCacheService =
            localUsageReportCacheService ?? LocalUsageReportCacheService();

  final UsageReportService _usageReportService;
  final LocalUsageReportCacheService _localUsageReportCacheService;

  // Android's UsageEvents.Event.MOVE_TO_FOREGROUND, exposed by the
  // usage_stats plugin as EventUsageInfo.eventTypeValue == 1 (its own
  // eventTypeName() maps this to the string 'ACTIVITY_RESUMED' - confirmed
  // directly from the plugin's source at
  // github.com/Parassharmaa/usage_stats/blob/master/lib/src/parse.dart,
  // since pub.dev's generated API docs don't spell out the underlying
  // integer values). This is the system event fired whenever an app's
  // activity becomes the foreground activity - i.e. what "opening" an app
  // looks like at the OS level.
  static const int _activityResumedEventType = 1;

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

  /// Returns how many times the single most-reopened app was brought to
  /// the foreground today - Table 6's "Frequent distracting app use (>15
  /// opens/day)" indicator (see ml/generate_dataset.py's doc comment and
  /// child_home_screen.dart's _buildMlFeatures()). Uses queryEvents()
  /// rather than queryAndAggregateUsageStats() above, since aggregated
  /// stats only expose total foreground *duration* per app, not how many
  /// separate times it was opened.
  Future<int> getTodayMaxAppOpenCount() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final events = await UsageStats.queryEvents(startOfDay, now);

    // Same reduction-to-plain-types reasoning as getTodayUsage() above:
    // only the three raw fields countMaxAppOpens() needs are pulled out
    // of the plugin's EventUsageInfo here.
    final rawEvents = <UsageEventRecord>[
      for (final event in events)
        (
          packageName: event.packageName ?? '',
          eventType: event.eventTypeValue ?? -1,
          timestampMs: int.tryParse(event.timeStamp ?? '') ?? 0,
        ),
    ];

    return countMaxAppOpens(rawEvents);
  }

  /// The pure part of getTodayMaxAppOpenCount(): turns raw usage events
  /// into the single highest per-app "open" count for the day. Takes
  /// plain UsageEventRecord values rather than the native plugin's
  /// EventUsageInfo type, so this can be tested directly instead of
  /// needing a fake for a third-party plugin class.
  ///
  /// "Opened" means an ACTIVITY_RESUMED event for a package that differs
  /// from the immediately-preceding ACTIVITY_RESUMED package - this
  /// collapses the burst of resume events Android emits when a single
  /// app's own activities hand off to each other (e.g. a multi-screen
  /// flow within one app) into a single "open", so this measures genuine
  /// switches into an app, not that app's internal navigation. Table 6's
  /// indicator is worded per-app ("the app was opened >15 times"), not as
  /// a cross-app total, so this returns the single highest count seen
  /// across all packages today, not the sum of every app's opens.
  int countMaxAppOpens(List<UsageEventRecord> events) {
    // queryEvents() is expected to already return events in chronological
    // order, but that isn't documented as a hard guarantee, and getting
    // it wrong here would silently miscount - sort defensively.
    final sorted = [...events]
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    final opensByPackage = <String, int>{};
    String? lastResumedPackage;

    for (final event in sorted) {
      if (event.eventType != _activityResumedEventType) continue;
      if (event.packageName.isEmpty) continue;

      if (event.packageName != lastResumedPackage) {
        opensByPackage[event.packageName] =
            (opensByPackage[event.packageName] ?? 0) + 1;
      }
      lastResumedPackage = event.packageName;
    }

    if (opensByPackage.isEmpty) return 0;

    return opensByPackage.values.reduce((a, b) => a > b ? a : b);
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