import 'app_usage_summary.dart';

enum UsagePatternStatus { healthy, warning, unhealthy }

extension UsagePatternStatusLabel on UsagePatternStatus {
  String get label {
    switch (this) {
      case UsagePatternStatus.healthy:
        return 'Healthy';
      case UsagePatternStatus.warning:
        return 'Warning';
      case UsagePatternStatus.unhealthy:
        return 'Unhealthy';
    }
  }
}

class UsageReport {
  const UsageReport({
    required this.totalUsageDuration,
    required this.topUsedApp,
    required this.unhealthyAppCount,
    required this.generatedAt,
    required this.patternStatus,
    required this.recommendationMessage,
    this.riskScore = 0,
    this.riskFactors = const [],
  });

  final Duration totalUsageDuration;
  final AppUsageSummary? topUsedApp;
  final int unhealthyAppCount;
  final DateTime generatedAt;
  final UsagePatternStatus patternStatus;
  final String recommendationMessage;
  final int riskScore;
  final List<String> riskFactors;

  int get clampedRiskScore => riskScore.clamp(0, 100).toInt();

  String get riskScoreLabel {
    return '$clampedRiskScore/100';
  }

  String get riskLevelLabel {
    if (clampedRiskScore >= 60) {
      return 'Unhealthy Risk';
    }

    if (clampedRiskScore >= 30) {
      return 'Warning Risk';
    }

    return 'Healthy Risk';
  }

  String get riskFactorSummary {
    if (riskFactors.isEmpty) {
      return 'No risk factors were detected in this report.';
    }

    return riskFactors.join('\n');
  }

  String get totalUsageLabel {
    final hours = totalUsageDuration.inHours;
    final minutes = totalUsageDuration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m';
    }

    return '${totalUsageDuration.inSeconds}s';
  }
}
