import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:app/services/usage_report_service.dart';

void main() {
  group('PatternDetectionService', () {
    test('returns Healthy when usage is low', () {
      final service = PatternDetectionService();

      final summaries = [
        AppUsageSummary(
          packageName: 'com.google.calculator',
          displayName: 'Calculator',
          usageDuration: Duration(minutes: 20),
        ),
        AppUsageSummary(
          packageName: 'com.android.settings',
          displayName: 'Settings',
          usageDuration: Duration(minutes: 10),
        ),
      ];

      final report = service.generateReport(summaries);

      expect(report.patternStatus, UsagePatternStatus.healthy);
      expect(report.totalUsageDuration, Duration(minutes: 30));
      expect(report.topUsedApp?.displayName, 'Calculator');
      expect(report.unhealthyAppCount, 0);

    });

    test('returns Warning when social media usage is high', () {
      final service = PatternDetectionService();

      final summaries = [
        AppUsageSummary(
          packageName: 'com.zhiliaoapp.musically',
          displayName: 'TikTok',
          usageDuration: Duration(hours: 2),
        ),
        AppUsageSummary(
          packageName: 'com.google.android.youtube',
          displayName: 'YouTube',
          usageDuration: Duration(hours: 1),
        ),
      ];

      final report = service.generateReport(summaries);

      expect(report.patternStatus, UsagePatternStatus.warning);
      expect(report.topUsedApp?.displayName, 'TikTok');
      expect(report.unhealthyAppCount, greaterThanOrEqualTo(1));

    });

    test('returns Unhealthy when total usage is too high', () {
      final service = PatternDetectionService();

      final summaries = [
        AppUsageSummary(
          packageName: 'com.roblox.client',
          displayName: 'Roblox',
          usageDuration: Duration(hours: 3),
        ),
        AppUsageSummary(
          packageName: 'com.google.android.youtube',
          displayName: 'YouTube',
          usageDuration: Duration(hours: 2, minutes: 30),
        ),
      ];

      final report = service.generateReport(summaries);

      expect(report.patternStatus, UsagePatternStatus.unhealthy);
      expect(report.totalUsageDuration, Duration(hours: 5, minutes: 30));
    });
  });

  group('UsageReportService', () {
    test('generates report from summaries', () {
      final service = UsageReportService();

      final summaries = [
        AppUsageSummary(
          packageName: 'com.instagram.android',
          displayName: 'Instagram',
          usageDuration: Duration(hours: 2),
        ),
      ];

      final report = service.generateFromSummaries(summaries);

      expect(report.topUsedApp?.displayName, 'Instagram');
      expect(report.patternStatus, UsagePatternStatus.warning);
    });
  });
}
