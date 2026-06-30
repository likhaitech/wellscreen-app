import '../models/usage_report.dart';

enum InterventionType {
  none,
  breakReminder,
  appLimit,
  focusMode,
  bedtimeRestriction,
}

class InterventionRecommendation {
  const InterventionRecommendation({
    required this.type,
    required this.title,
    required this.message,
    required this.isUrgent,
  });

  final InterventionType type;
  final String title;
  final String message;
  final bool isUrgent;
}

class InterventionRecommendationService {
  InterventionRecommendation getRecommendation(UsageReport report) {
    switch (report.patternStatus) {
      case UsagePatternStatus.healthy:
        return const InterventionRecommendation(
          type: InterventionType.none,
          title: 'Healthy Usage',
          message:
              'Usage looks balanced. Continue maintaining healthy screen habits.',
          isUrgent: false,
        );

      case UsagePatternStatus.warning:
        return _getWarningRecommendation(report);

      case UsagePatternStatus.unhealthy:
        return _getUnhealthyRecommendation(report);
    }
  }

  InterventionRecommendation _getWarningRecommendation(UsageReport report) {
    final topAppName = report.topUsedApp?.displayName ?? 'the most used app';

    if (report.unhealthyAppCount > 0) {
      return InterventionRecommendation(
        type: InterventionType.appLimit,
        title: 'App Limit Recommended',
        message:
            '$topAppName has noticeable usage. Consider setting an app limit or cooldown timer.',
        isUrgent: false,
      );
    }

    return const InterventionRecommendation(
      type: InterventionType.breakReminder,
      title: 'Break Reminder Recommended',
      message: 'Screen time is getting high. A short break is recommended.',
      isUrgent: false,
    );
  }

  InterventionRecommendation _getUnhealthyRecommendation(UsageReport report) {
    final recommendationMessage = report.recommendationMessage.toLowerCase();

    if (recommendationMessage.contains('late-night') ||
        recommendationMessage.contains('bedtime')) {
      return const InterventionRecommendation(
        type: InterventionType.bedtimeRestriction,
        title: 'Bedtime Restriction Recommended',
        message:
            'Late-night usage was detected. Consider enabling bedtime restrictions.',
        isUrgent: true,
      );
    }

    return const InterventionRecommendation(
      type: InterventionType.focusMode,
      title: 'Focus Mode Recommended',
      message:
          'Usage is currently unhealthy. Consider enabling focus mode or temporary app blocking.',
      isUrgent: true,
    );
  }
}
