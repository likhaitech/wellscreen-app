import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'age_based_screen_time_threshold_service.dart';

class PatternDetectionService {
  PatternDetectionService({
    AgeBasedScreenTimeThresholdService? ageThresholdService,
  }) : _ageThresholdService =
           ageThresholdService ?? AgeBasedScreenTimeThresholdService();

  static const Duration warningSingleAppLimit = Duration(hours: 1, minutes: 30);
  static const Duration unhealthySingleAppLimit = Duration(hours: 3);

  static const Duration riskyAppUsageLimit = Duration(hours: 1);

  static const int warningRiskScore = 30;
  static const int unhealthyRiskScore = 60;
  static const int maximumRiskScore = 100;

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

  final AgeBasedScreenTimeThresholdService _ageThresholdService;

  UsageReport generateReport(List<AppUsageSummary> summaries, {int? childAge}) {
    final threshold = _ageThresholdService.getThresholdForAge(childAge);

    final totalUsageDuration = _getTotalUsageDuration(summaries);
    final topUsedApp = _getTopUsedApp(summaries);
    final unhealthyAppCount = _getUnhealthyAppCount(summaries);
    final hasLongSingleAppUsage = _hasLongSingleAppUsage(summaries);
    final hasLateNightUsage = _hasLateNightUsage(summaries);

    final riskResult = _calculateRiskScore(
      totalUsageDuration: totalUsageDuration,
      topUsedApp: topUsedApp,
      unhealthyAppCount: unhealthyAppCount,
      hasLateNightUsage: hasLateNightUsage,
      threshold: threshold,
    );

    final status = _detectStatus(riskScore: riskResult.score);

    return UsageReport(
      totalUsageDuration: totalUsageDuration,
      topUsedApp: topUsedApp,
      unhealthyAppCount: unhealthyAppCount,
      generatedAt: DateTime.now(),
      patternStatus: status,
      riskScore: riskResult.score,
      riskFactors: riskResult.factors,
      recommendationMessage: _getRecommendationMessage(
        status: status,
        riskScore: riskResult.score,
        topUsedApp: topUsedApp,
        unhealthyAppCount: unhealthyAppCount,
        hasLongSingleAppUsage: hasLongSingleAppUsage,
        hasLateNightUsage: hasLateNightUsage,
        threshold: threshold,
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
    return summaries.any((app) => app.usageDuration >= warningSingleAppLimit);
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

  _RiskScoreResult _calculateRiskScore({
    required Duration totalUsageDuration,
    required AppUsageSummary? topUsedApp,
    required int unhealthyAppCount,
    required bool hasLateNightUsage,
    required AgeBasedScreenTimeThreshold threshold,
  }) {
    var score = 0;
    final factors = <String>[];

    if (totalUsageDuration >= threshold.unhealthyLimit) {
      score += 60;
      factors.add(
        'Total screen time reached the unhealthy limit for ${threshold.ageGroupLabel}.',
      );
    } else if (totalUsageDuration >= threshold.warningLimit) {
      score += 20;
      factors.add(
        'Total screen time reached the warning limit for ${threshold.ageGroupLabel}.',
      );
    }

    if (topUsedApp != null &&
        topUsedApp.usageDuration >= unhealthySingleAppLimit) {
      score += 10;
      factors.add(
        '${topUsedApp.displayName} was used for ${topUsedApp.usageLabel}, which is a very long single-app session.',
      );
    } else if (topUsedApp != null &&
        topUsedApp.usageDuration >= warningSingleAppLimit) {
      score += 10;
      factors.add(
        '${topUsedApp.displayName} was used for ${topUsedApp.usageLabel}, which may need a break reminder.',
      );
    }

    if (unhealthyAppCount >= 3) {
      score += 60;
      factors.add(
        'Multiple social media, video, or gaming apps had high usage.',
      );
    } else if (unhealthyAppCount >= 1) {
      score += 20;
      factors.add(
        'At least one social media, video, or gaming app had high usage.',
      );
    }

    if (hasLateNightUsage) {
      score += 60;
      factors.add(
        'Late-night phone usage was detected between 10:00 PM and 5:00 AM.',
      );
    }

    if (factors.isEmpty) {
      factors.add('No major risk signals were detected.');
    }

    return _RiskScoreResult(
      score: score.clamp(0, maximumRiskScore).toInt(),
      factors: factors,
    );
  }

  UsagePatternStatus _detectStatus({required int riskScore}) {
    if (riskScore >= unhealthyRiskScore) {
      return UsagePatternStatus.unhealthy;
    }

    if (riskScore >= warningRiskScore) {
      return UsagePatternStatus.warning;
    }

    return UsagePatternStatus.healthy;
  }

  String _getRecommendationMessage({
    required UsagePatternStatus status,
    required int riskScore,
    required AppUsageSummary? topUsedApp,
    required int unhealthyAppCount,
    required bool hasLongSingleAppUsage,
    required bool hasLateNightUsage,
    required AgeBasedScreenTimeThreshold threshold,
  }) {
    final topAppName = topUsedApp?.displayName ?? 'No app';

    switch (status) {
      case UsagePatternStatus.healthy:
        return 'Risk score is $riskScore/100. Usage looks healthy for the ${threshold.ageGroupLabel.toLowerCase()} threshold. Keep maintaining balanced screen time.';

      case UsagePatternStatus.warning:
        if (hasLongSingleAppUsage) {
          return 'Risk score is $riskScore/100. $topAppName was used for a long session. A short break is recommended.';
        }

        if (unhealthyAppCount > 0) {
          return 'Risk score is $riskScore/100. Some social media, video, or gaming apps have high usage. Consider setting app limits.';
        }

        return 'Risk score is $riskScore/100. Screen time is above the recommended limit for ${threshold.ageGroupLabel.toLowerCase()}. Consider taking a break.';

      case UsagePatternStatus.unhealthy:
        if (hasLateNightUsage) {
          return 'Risk score is $riskScore/100. Late-night phone usage was detected. Consider enabling bedtime restrictions.';
        }

        if (unhealthyAppCount >= 3) {
          return 'Risk score is $riskScore/100. Multiple social media, video, or gaming apps show high usage. Guardian guidance is recommended.';
        }

        return 'Risk score is $riskScore/100. Total screen time is too high for ${threshold.ageGroupLabel.toLowerCase()}. Consider using focus mode or temporary app blocking.';
    }
  }
}

class _RiskScoreResult {
  const _RiskScoreResult({required this.score, required this.factors});

  final int score;
  final List<String> factors;
}
