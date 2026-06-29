import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/usage_dashboard_service.dart';
import 'package:app/services/usage_tracking_service.dart';

void main() {
  group('UsageDashboardService', () {
    test('returns cached data when usage permission is missing', () async {
      final cachedData = {
        'patternStatus': 'warning',
        'recommendationMessage': 'Cached report available.',
      };

      final service = UsageDashboardService(
        usageTrackingService: FakeUsageTrackingService(
          hasPermission: false,
          cachedData: cachedData,
        ),
      );

      final result = await service.loadTodayDashboard();

      expect(result.hasUsagePermission, false);
      expect(result.isUsingCachedData, true);
      expect(result.report, isNull);
      expect(result.cachedReportData, cachedData);
      expect(result.errorMessage, isNotNull);
    });

    test(
      'returns permission error when permission is missing and no cache exists',
      () async {
        final service = UsageDashboardService(
          usageTrackingService: FakeUsageTrackingService(
            hasPermission: false,
            cachedData: null,
          ),
        );

        final result = await service.loadTodayDashboard();

        expect(result.hasUsagePermission, false);
        expect(result.isUsingCachedData, false);
        expect(result.report, isNull);
        expect(result.cachedReportData, isNull);
        expect(
          result.errorMessage,
          'Usage access permission is required to generate today’s report.',
        );
      },
    );

    test('returns live report when permission is granted', () async {
      final liveReport = UsageReport(
        totalUsageDuration: const Duration(hours: 2),
        topUsedApp: AppUsageSummary(
          packageName: 'com.google.android.youtube',
          displayName: 'YouTube',
          usageDuration: const Duration(hours: 1),
        ),
        unhealthyAppCount: 1,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage:
            'Some social media or gaming apps have high usage.',
      );

      final service = UsageDashboardService(
        usageTrackingService: FakeUsageTrackingService(
          hasPermission: true,
          liveReport: liveReport,
        ),
      );

      final result = await service.loadTodayDashboard();

      expect(result.hasUsagePermission, true);
      expect(result.isUsingCachedData, false);
      expect(result.report, liveReport);
      expect(result.cachedReportData, isNull);
      expect(result.errorMessage, isNull);
    });

    test('returns cached data when live usage tracking fails', () async {
      final cachedData = {
        'patternStatus': 'warning',
        'recommendationMessage': 'Showing cached report.',
      };

      final service = UsageDashboardService(
        usageTrackingService: FakeUsageTrackingService(
          hasPermission: true,
          shouldThrowReportError: true,
          cachedData: cachedData,
        ),
      );

      final result = await service.loadTodayDashboard();

      expect(result.hasUsagePermission, true);
      expect(result.isUsingCachedData, true);
      expect(result.report, isNull);
      expect(result.cachedReportData, cachedData);
      expect(
        result.errorMessage,
        'Showing the last cached usage report because live usage tracking failed.',
      );
    });

    test('loads today app usage list', () async {
      final usageList = [
        AppUsageSummary(
          packageName: 'com.roblox.client',
          displayName: 'Roblox',
          usageDuration: const Duration(hours: 1),
        ),
      ];

      final service = UsageDashboardService(
        usageTrackingService: FakeUsageTrackingService(
          hasPermission: true,
          usageList: usageList,
        ),
      );

      final result = await service.loadTodayAppUsageList();

      expect(result, usageList);
    });
  });
}

class FakeUsageTrackingService extends UsageTrackingService {
  FakeUsageTrackingService({
    required this.hasPermission,
    this.liveReport,
    this.cachedData,
    this.usageList = const [],
    this.shouldThrowReportError = false,
  });

  final bool hasPermission;
  final UsageReport? liveReport;
  final Map<String, dynamic>? cachedData;
  final List<AppUsageSummary> usageList;
  final bool shouldThrowReportError;

  @override
  Future<bool> hasUsagePermission() async {
    return hasPermission;
  }

  @override
  Future<UsageReport> getTodayUsageReport() async {
    if (shouldThrowReportError) {
      throw Exception('Live usage tracking failed.');
    }

    return liveReport ??
        UsageReport(
          totalUsageDuration: Duration.zero,
          topUsedApp: null,
          unhealthyAppCount: 0,
          generatedAt: DateTime.now(),
          patternStatus: UsagePatternStatus.healthy,
          recommendationMessage:
              'Usage looks healthy. Keep maintaining balanced screen time.',
        );
  }

  @override
  Future<Map<String, dynamic>?> getCachedTodayUsageReportData() async {
    return cachedData;
  }

  @override
  Future<List<AppUsageSummary>> getTodayUsage() async {
    return usageList;
  }
}
