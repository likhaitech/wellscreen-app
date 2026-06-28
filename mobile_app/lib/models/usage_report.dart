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
  });

  final Duration totalUsageDuration;
  final AppUsageSummary? topUsedApp;
  final int unhealthyAppCount;
  final DateTime generatedAt;
  final UsagePatternStatus patternStatus;
  final String recommendationMessage;

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
