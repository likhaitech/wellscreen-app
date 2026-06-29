import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/local_usage_report_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalUsageReportCacheService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and reads today usage report data', () async {
      final service = LocalUsageReportCacheService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 4, minutes: 20),
        topUsedApp: AppUsageSummary(
          packageName: 'com.zhiliaoapp.musically',
          displayName: 'TikTok',
          usageDuration: const Duration(hours: 2),
        ),
        unhealthyAppCount: 2,
        generatedAt: DateTime(2026, 6, 30, 10, 30),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage:
            'Some social media or gaming apps have high usage.',
      );

      await service.saveTodayReport(report);

      final cachedData = await service.getCachedTodayReportData();

      expect(cachedData, isNotNull);
      expect(
        cachedData?['totalUsageDurationMs'],
        const Duration(hours: 4, minutes: 20).inMilliseconds,
      );
      expect(cachedData?['topUsedAppPackageName'], 'com.zhiliaoapp.musically');
      expect(cachedData?['topUsedAppDisplayName'], 'TikTok');
      expect(
        cachedData?['topUsedAppUsageDurationMs'],
        const Duration(hours: 2).inMilliseconds,
      );
      expect(cachedData?['unhealthyAppCount'], 2);
      expect(cachedData?['patternStatus'], UsagePatternStatus.warning.name);
      expect(
        cachedData?['recommendationMessage'],
        'Some social media or gaming apps have high usage.',
      );
    });

    test('reconstructs cached today usage report as UsageReport', () async {
      final service = LocalUsageReportCacheService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 4, minutes: 20),
        topUsedApp: AppUsageSummary(
          packageName: 'com.zhiliaoapp.musically',
          displayName: 'TikTok',
          usageDuration: const Duration(hours: 2),
        ),
        unhealthyAppCount: 2,
        generatedAt: DateTime(2026, 6, 30, 10, 30),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage:
            'Some social media or gaming apps have high usage.',
      );

      await service.saveTodayReport(report);

      final cachedReport = await service.getCachedTodayReport();

      expect(cachedReport, isNotNull);
      expect(
        cachedReport?.totalUsageDuration,
        const Duration(hours: 4, minutes: 20),
      );
      expect(cachedReport?.topUsedApp?.packageName, 'com.zhiliaoapp.musically');
      expect(cachedReport?.topUsedApp?.displayName, 'TikTok');
      expect(cachedReport?.topUsedApp?.usageDuration, const Duration(hours: 2));
      expect(cachedReport?.unhealthyAppCount, 2);
      expect(cachedReport?.patternStatus, UsagePatternStatus.warning);
      expect(
        cachedReport?.recommendationMessage,
        'Some social media or gaming apps have high usage.',
      );
    });

    test('returns null when no today usage report is cached', () async {
      final service = LocalUsageReportCacheService();

      final cachedData = await service.getCachedTodayReportData();
      final cachedReport = await service.getCachedTodayReport();

      expect(cachedData, isNull);
      expect(cachedReport, isNull);
    });

    test('clears cached today usage report data', () async {
      final service = LocalUsageReportCacheService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 1),
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.healthy,
        recommendationMessage:
            'Usage looks healthy. Keep maintaining balanced screen time.',
      );

      await service.saveTodayReport(report);
      await service.clearTodayReport();

      final cachedData = await service.getCachedTodayReportData();
      final cachedReport = await service.getCachedTodayReport();

      expect(cachedData, isNull);
      expect(cachedReport, isNull);
    });
  });
}
