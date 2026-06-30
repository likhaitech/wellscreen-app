import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/intervention_recommendation_service.dart';
import 'package:app/services/usage_dashboard_service.dart';
import 'package:app/services/usage_dashboard_view_model_service.dart';

void main() {
  group('UsageDashboardViewModelService', () {
    test('builds view model from live dashboard result', () {
      final service = UsageDashboardViewModelService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 3, minutes: 20),
        topUsedApp: const AppUsageSummary(
          packageName: 'com.zhiliaoapp.musically',
          displayName: 'TikTok',
          usageDuration: Duration(hours: 2),
        ),
        unhealthyAppCount: 1,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage:
            'Some social media or gaming apps have high usage.',
      );

      const intervention = InterventionRecommendation(
        type: InterventionType.appLimit,
        title: 'App Limit Recommended',
        message: 'Consider setting an app limit or cooldown timer.',
        isUrgent: false,
      );

      final result = UsageDashboardResult(
        hasUsagePermission: true,
        isUsingCachedData: false,
        report: report,
        interventionRecommendation: intervention,
        errorMessage: null,
      );

      final viewModel = service.buildViewModel(result);

      expect(viewModel.statusLabel, 'Warning');
      expect(viewModel.totalUsageLabel, '3h 20m');
      expect(viewModel.topUsedAppLabel, 'TikTok • 2h 0m');
      expect(viewModel.unhealthyAppCountLabel, '1 app needs attention');
      expect(
        viewModel.recommendationMessage,
        'Some social media or gaming apps have high usage.',
      );
      expect(viewModel.interventionTitle, 'App Limit Recommended');
      expect(
        viewModel.interventionMessage,
        'Consider setting an app limit or cooldown timer.',
      );
      expect(viewModel.hasUsagePermission, true);
      expect(viewModel.isUsingCachedData, false);
      expect(viewModel.errorMessage, isNull);
    });

    test('builds fallback view model when report is missing', () {
      final service = UsageDashboardViewModelService();

      const result = UsageDashboardResult(
        hasUsagePermission: false,
        isUsingCachedData: false,
        report: null,
        interventionRecommendation: null,
        errorMessage:
            'Usage access permission is required to generate today’s report.',
      );

      final viewModel = service.buildViewModel(result);

      expect(viewModel.statusLabel, 'No Report');
      expect(viewModel.totalUsageLabel, '0s');
      expect(viewModel.topUsedAppLabel, 'No app usage recorded');
      expect(viewModel.unhealthyAppCountLabel, '0 apps need attention');
      expect(viewModel.recommendationMessage, 'No usage report available yet.');
      expect(viewModel.interventionTitle, 'No Intervention Available');
      expect(
        viewModel.interventionMessage,
        'Generate a usage report first to receive a recommendation.',
      );
      expect(viewModel.hasUsagePermission, false);
      expect(viewModel.isUsingCachedData, false);
      expect(
        viewModel.errorMessage,
        'Usage access permission is required to generate today’s report.',
      );
    });

    test('builds cached dashboard view model', () {
      final service = UsageDashboardViewModelService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 5),
        topUsedApp: null,
        unhealthyAppCount: 2,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.unhealthy,
        recommendationMessage: 'Total screen time is too high.',
      );

      const intervention = InterventionRecommendation(
        type: InterventionType.focusMode,
        title: 'Focus Mode Recommended',
        message: 'Consider enabling focus mode.',
        isUrgent: true,
      );

      final result = UsageDashboardResult(
        hasUsagePermission: true,
        isUsingCachedData: true,
        report: report,
        interventionRecommendation: intervention,
        errorMessage:
            'Showing the last cached usage report because live usage tracking failed.',
      );

      final viewModel = service.buildViewModel(result);

      expect(viewModel.statusLabel, 'Unhealthy');
      expect(viewModel.totalUsageLabel, '5h 0m');
      expect(viewModel.topUsedAppLabel, 'No app usage recorded');
      expect(viewModel.unhealthyAppCountLabel, '2 apps need attention');
      expect(viewModel.isUsingCachedData, true);
      expect(viewModel.interventionTitle, 'Focus Mode Recommended');
    });
  });
}
