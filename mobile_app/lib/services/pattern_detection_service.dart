import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';

class PatternDetectionService {
  static const Duration warningTotalUsageLimit = Duration(hours: 3);
  static const Duration unhealthyTotalUsageLimit = Duration(hours: 5);

  static const Duration warningSingleAppLimit = Duration(hours: 1, minutes: 30);
  static const Duration unhealthySingleAppLimit = Duration(hours: 3);

  static const Duration riskyAppUsageLimit = Duration(hours: 1);

  static const List<String> riskyKeywords = [
    'facebook',
    'messenger',
    'instagram',
    'tiktok',
    'youtube',
    'twitter',
    'x',
    'snapchat',
    'discord',
    'netflix',
    'game',
    'games',
    'gaming',
    'roblox',
    'minecraft',
    'mlbb',
    'mobilelegends',
    'pubg',
    'cod',
    'freefire',
  ];

  UsageReport generateReport(List<AppUsageSummary> summaries) {
    final totalUsageDuration = _getTotalUsageDuration(summaries);
    final topUsedApp = _getTopUsedApp(summaries);
    final unhealthyAppCount = _getUnhealthyAppCount(summaries);
    final hasLongSingleAppUsage = _hasLongSingleAppUsage(summaries);
    final hasLateNightUsage = _hasLateNightUsage(summaries);

    final status = _detectStatus(
      totalUsageDuration: totalUsageDuration,
      unhealthyAppCount: unhealthyAppCount,
      hasLongSingleAppUsage: hasLongSingleAppUsage,
      hasLateNightUsage: hasLateNightUsage,
    );

    return UsageReport(
      totalUsageDuration: totalUsageDuration,
      topUsedApp: topUsedApp,
      unhealthyAppCount: unhealthyAppCount,
      generatedAt: DateTime.now(),
      patternStatus: status,
      recommendationMessage: _getRecommendationMessage(
        status: status,
        totalUsageDuration: totalUsageDuration,
        topUsedApp: topUsedApp,
        unhealthyAppCount: unhealthyAppCount,
        hasLongSingleAppUsage: hasLongSingleAppUsage,
        hasLateNightUsage: hasLateNightUsage,
      ),
    );
  }

  Duration _getTotalUsageDuration(List<AppUsageSummary> summaries) {
    return summaries.fold(
      Duration.zero,
      (total, app) => total + app.usageDuration,
    );
  }

  AppUsageSummary? _getTopUsedApp(List<AppUsageSummary> summaries) {
    if (summaries.isEmpty) {
      return null;
    }

    final sortedApps = [...summaries]
      ..sort((a, b) => b.usageDuration.compareTo(a.usageDuration));

    return sortedApps.first;
  }

  int _getUnhealthyAppCount(List<AppUsageSummary> summaries) {
    return summaries.where((app) {
      return _isRiskyApp(app) && app.usageDuration >= riskyAppUsageLimit;
    }).length;
  }

  bool _hasLongSingleAppUsage(List<AppUsageSummary> summaries) {
    return summaries.any(
      (app) => app.usageDuration >= warningSingleAppLimit,
    );
  }

  bool _hasLateNightUsage(List<AppUsageSummary> summaries) {
    return summaries.any((app) {
      final lastTimeUsed = app.lastTimeUsed;

      if (lastTimeUsed == null) {
        return false;
      }

      return lastTimeUsed.hour >= 22 || lastTimeUsed.hour < 5;
    });
  }

  bool _isRiskyApp(AppUsageSummary app) {
    final packageName = app.packageName.toLowerCase();
    final displayName = app.displayName.toLowerCase();

    return riskyKeywords.any(
      (keyword) =>
          packageName.contains(keyword) || displayName.contains(keyword),
    );
  }

  UsagePatternStatus _detectStatus({
    required Duration totalUsageDuration,
    required int unhealthyAppCount,
    required bool hasLongSingleAppUsage,
    required bool hasLateNightUsage,
  }) {
    if (totalUsageDuration >= unhealthyTotalUsageLimit ||
        unhealthyAppCount >= 3 ||
        hasLateNightUsage) {
      return UsagePatternStatus.unhealthy;
    }

    if (totalUsageDuration >= warningTotalUsageLimit ||
        unhealthyAppCount >= 1 ||
        hasLongSingleAppUsage) {
      return UsagePatternStatus.warning;
    }

    return UsagePatternStatus.healthy;
  }

  String _getRecommendationMessage({
    required UsagePatternStatus status,
    required Duration totalUsageDuration,
    required AppUsageSummary? topUsedApp,
    required int unhealthyAppCount,
    required bool hasLongSingleAppUsage,
    required bool hasLateNightUsage,
  }) {
    final topAppName = topUsedApp?.displayName ?? 'No app';

    switch (status) {
      case UsagePatternStatus.healthy:
        return 'Usage looks healthy. Keep maintaining balanced screen time.';

      case UsagePatternStatus.warning:
        if (hasLongSingleAppUsage) {
          return '$topAppName was used for a long session. A short break is recommended.';
        }

        if (unhealthyAppCount > 0) {
          return 'Some social media or gaming apps have high usage. Consider setting app limits.';
        }

        return 'Screen time is getting high. Consider taking a break.';

      case UsagePatternStatus.unhealthy:
        if (hasLateNightUsage) {
          return 'Late-night phone usage was detected. Consider enabling bedtime restrictions.';
        }

        if (unhealthyAppCount >= 3) {
          return 'Multiple social media or gaming apps show high usage. Parent guidance is recommended.';
        }

        return 'Total screen time is too high. Consider using focus mode or temporary app blocking.';
    }
  }
}