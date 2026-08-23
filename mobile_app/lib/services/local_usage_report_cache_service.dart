import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';

class LocalUsageReportCacheService {
  static const String _todayUsageReportKey = 'today_usage_report';

  static const String _lastSuccessfulUsageSyncDateKey =
      'last_successful_usage_sync_date';

  static const String _pendingUsageSyncDatesKey = 'pending_usage_sync_dates';

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

  // ============================================================
  // OFFLINE USAGE SYNC STATE
  // ============================================================

  /// Saves the latest calendar date that was successfully uploaded
  /// to Firestore.
  ///
  /// The value is stored as YYYY-MM-DD so it survives app restarts.
  Future<void> saveLastSuccessfulUsageSyncDate(DateTime date) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _lastSuccessfulUsageSyncDateKey,
      _formatDate(date),
    );
  }

  /// Returns the latest successfully synchronized calendar date.
  ///
  /// Returns null when the device has never completed a usage sync.
  Future<DateTime?> getLastSuccessfulUsageSyncDate() async {
    final preferences = await SharedPreferences.getInstance();

    final value = preferences.getString(_lastSuccessfulUsageSyncDateKey);

    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return _parseDate(value);
  }

  /// Adds a date to the local retry queue.
  ///
  /// Duplicate dates are automatically avoided.
  Future<void> addPendingUsageSyncDate(DateTime date) async {
    final preferences = await SharedPreferences.getInstance();

    final pendingDates =
        preferences.getStringList(_pendingUsageSyncDatesKey)?.toSet() ??
        <String>{};

    pendingDates.add(_formatDate(date));

    final sortedDates = pendingDates.toList()..sort();

    await preferences.setStringList(_pendingUsageSyncDatesKey, sortedDates);
  }

  /// Removes a date from the retry queue after a successful
  /// Firestore upload.
  Future<void> removePendingUsageSyncDate(DateTime date) async {
    final preferences = await SharedPreferences.getInstance();

    final pendingDates =
        preferences.getStringList(_pendingUsageSyncDatesKey)?.toSet() ??
        <String>{};

    pendingDates.remove(_formatDate(date));

    final sortedDates = pendingDates.toList()..sort();

    await preferences.setStringList(_pendingUsageSyncDatesKey, sortedDates);
  }

  /// Returns every calendar date that still needs to be uploaded.
  ///
  /// Invalid stored values are ignored.
  Future<List<DateTime>> getPendingUsageSyncDates() async {
    final preferences = await SharedPreferences.getInstance();

    final values =
        preferences.getStringList(_pendingUsageSyncDatesKey) ??
        const <String>[];

    final dates = values.map(_parseDate).whereType<DateTime>().toList();

    dates.sort();

    return dates;
  }

  /// Adds several dates to the retry queue at once.
  Future<void> addPendingUsageSyncDates(Iterable<DateTime> dates) async {
    final preferences = await SharedPreferences.getInstance();

    final pendingDates =
        preferences.getStringList(_pendingUsageSyncDatesKey)?.toSet() ??
        <String>{};

    for (final date in dates) {
      pendingDates.add(_formatDate(date));
    }

    final sortedDates = pendingDates.toList()..sort();

    await preferences.setStringList(_pendingUsageSyncDatesKey, sortedDates);
  }

  /// Clears all pending retry dates.
  ///
  /// This is mainly useful for account/device reset flows.
  Future<void> clearPendingUsageSyncDates() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_pendingUsageSyncDatesKey);
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

  DateTime? _parseDate(String value) {
    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      return null;
    }

    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
