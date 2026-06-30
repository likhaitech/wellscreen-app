import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/intervention_recommendation_service.dart';

void main() {
  group('InterventionRecommendationService', () {
    test('returns no intervention for healthy usage', () {
      final service = InterventionRecommendationService();

      final report = UsageReport(
        totalUsageDuration: const Duration(minutes: 45),
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.healthy,
        recommendationMessage:
            'Usage looks healthy. Keep maintaining balanced screen time.',
      );

      final recommendation = service.getRecommendation(report);

      expect(recommendation.type, InterventionType.none);
      expect(recommendation.isUrgent, false);
      expect(recommendation.title, 'Healthy Usage');
    });

    test(
      'returns app limit recommendation for warning usage with unhealthy apps',
      () {
        final service = InterventionRecommendationService();

        final report = UsageReport(
          totalUsageDuration: const Duration(hours: 3),
          topUsedApp: AppUsageSummary(
            packageName: 'com.zhiliaoapp.musically',
            displayName: 'TikTok',
            usageDuration: const Duration(hours: 2),
          ),
          unhealthyAppCount: 1,
          generatedAt: DateTime(2026, 6, 30),
          patternStatus: UsagePatternStatus.warning,
          recommendationMessage:
              'Some social media or gaming apps have high usage.',
        );

        final recommendation = service.getRecommendation(report);

        expect(recommendation.type, InterventionType.appLimit);
        expect(recommendation.isUrgent, false);
        expect(recommendation.message.contains('TikTok'), true);
      },
    );

    test('returns break reminder for warning usage without unhealthy apps', () {
      final service = InterventionRecommendationService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 3),
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage: 'Screen time is getting high.',
      );

      final recommendation = service.getRecommendation(report);

      expect(recommendation.type, InterventionType.breakReminder);
      expect(recommendation.isUrgent, false);
    });

    test('returns bedtime restriction for unhealthy late-night usage', () {
      final service = InterventionRecommendationService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 5),
        topUsedApp: null,
        unhealthyAppCount: 1,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.unhealthy,
        recommendationMessage:
            'Late-night phone usage was detected. Consider enabling bedtime restrictions.',
      );

      final recommendation = service.getRecommendation(report);

      expect(recommendation.type, InterventionType.bedtimeRestriction);
      expect(recommendation.isUrgent, true);
    });

    test('returns focus mode for general unhealthy usage', () {
      final service = InterventionRecommendationService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 6),
        topUsedApp: null,
        unhealthyAppCount: 3,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.unhealthy,
        recommendationMessage:
            'Total screen time is too high. Consider using focus mode.',
      );

      final recommendation = service.getRecommendation(report);

      expect(recommendation.type, InterventionType.focusMode);
      expect(recommendation.isUrgent, true);
    });
  });
}
