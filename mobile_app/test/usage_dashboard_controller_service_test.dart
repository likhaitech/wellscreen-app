import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/intervention_recommendation_service.dart';
import 'package:app/services/usage_dashboard_controller_service.dart';
import 'package:app/services/usage_dashboard_service.dart';

void main() {
  group('UsageDashboardControllerService', () {
    test('loads dashboard state with view model and app usage list', () async {
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

      final appUsageList = [
        const AppUsageSummary(
          packageName: 'com.zhiliaoapp.musically',
          displayName: 'TikTok',
          usageDuration: Duration(hours: 2),
        ),
      ];

      final service = UsageDashboardControllerService(
        usageDashboardService: FakeUsageDashboardService(
          result: UsageDashboardResult(
            hasUsagePermission: true,
            isUsingCachedData: false,
            report: report,
            interventionRecommendation: intervention,
            errorMessage: null,
          ),
          appUsageList: appUsageList,
        ),
      );

      final state = await service.loadTodayDashboardState();

      expect(state.viewModel.statusLabel, 'Warning');
      expect(state.viewModel.totalUsageLabel, '3h 20m');
      expect(state.viewModel.topUsedAppLabel, 'TikTok • 2h 0m');
      expect(state.viewModel.interventionTitle, 'App Limit Recommended');
      expect(state.appUsageList, appUsageList);
    });

    test('returns empty app usage list when permission is missing', () async {
      const result = UsageDashboardResult(
        hasUsagePermission: false,
        isUsingCachedData: false,
        report: null,
        interventionRecommendation: null,
        errorMessage:
            'Usage access permission is required to generate today’s report.',
      );

      final service = UsageDashboardControllerService(
        usageDashboardService: FakeUsageDashboardService(
          result: result,
          appUsageList: const [
            AppUsageSummary(
              packageName: 'com.roblox.client',
              displayName: 'Roblox',
              usageDuration: Duration(hours: 1),
            ),
          ],
        ),
      );

      final state = await service.loadTodayDashboardState();

      expect(state.viewModel.statusLabel, 'No Report');
      expect(state.viewModel.hasUsagePermission, false);
      expect(state.appUsageList, isEmpty);
    });
  });
}

class FakeUsageDashboardService extends UsageDashboardService {
  FakeUsageDashboardService({required this.result, required this.appUsageList});

  final UsageDashboardResult result;
  final List<AppUsageSummary> appUsageList;

  @override
  Future<UsageDashboardResult> loadTodayDashboard() async {
    return result;
  }

  @override
  Future<List<AppUsageSummary>> loadTodayAppUsageList() async {
    return appUsageList;
  }
}
