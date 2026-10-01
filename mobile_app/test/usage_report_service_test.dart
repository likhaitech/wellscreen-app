import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/app_usage_summary.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:app/services/usage_report_service.dart';

/// UsageReportService is a thin wrapper around PatternDetectionService
/// (already covered directly by pattern_detection_service_test.dart) - so
/// what's worth pinning down here isn't the pattern-detection logic
/// itself, it's that UsageReportService actually delegates rather than
/// silently doing something else, and that its constructor injection
/// point (`PatternDetectionService? patternDetectionService`) really is
/// wired up and really does default to a real instance when omitted.
class _RecordingPatternDetectionService extends PatternDetectionService {
  List<AppUsageSummary>? receivedSummaries;
  int callCount = 0;

  final UsageReport _reportToReturn;

  _RecordingPatternDetectionService(this._reportToReturn);

  @override
  UsageReport generateReport(List<AppUsageSummary> summaries) {
    callCount += 1;
    receivedSummaries = summaries;
    return _reportToReturn;
  }
}

void main() {
  group('UsageReportService.generateFromSummaries', () {
    test('delegates to the injected PatternDetectionService, unchanged', () {
      final sentinelReport = UsageReport(
        totalUsageDuration: const Duration(minutes: 42),
        topUsedApp: null,
        unhealthyAppCount: 7,
        generatedAt: DateTime(2024, 1, 1),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage: 'sentinel-message',
      );
      final fakePatternDetection = _RecordingPatternDetectionService(
        sentinelReport,
      );
      final service = UsageReportService(
        patternDetectionService: fakePatternDetection,
      );
      final summaries = [
        const AppUsageSummary(
          packageName: 'com.example.app',
          displayName: 'Example',
          usageDuration: Duration(minutes: 10),
        ),
      ];

      final result = service.generateFromSummaries(summaries);

      // Same object back out - proves this is a real pass-through, not a
      // service that happens to produce an equivalent-looking report.
      expect(identical(result, sentinelReport), isTrue);
      expect(fakePatternDetection.callCount, 1);
      expect(identical(fakePatternDetection.receivedSummaries, summaries), isTrue);
    });

    test('calling twice delegates twice, not cached', () {
      final report = UsageReport(
        totalUsageDuration: Duration.zero,
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2024, 1, 1),
        patternStatus: UsagePatternStatus.healthy,
        recommendationMessage: 'ok',
      );
      final fakePatternDetection = _RecordingPatternDetectionService(report);
      final service = UsageReportService(
        patternDetectionService: fakePatternDetection,
      );

      service.generateFromSummaries([]);
      service.generateFromSummaries([]);

      expect(fakePatternDetection.callCount, 2);
    });

    test(
      'with no service injected, defaults to a real PatternDetectionService',
      () {
        // Behavioral proof, not just "it didn't throw": an empty usage list
        // must produce the exact healthy-status report
        // PatternDetectionService itself would produce, which is only true
        // if the default constructor really instantiates a real one.
        final service = UsageReportService();

        final result = service.generateFromSummaries([]);

        expect(result.totalUsageDuration, Duration.zero);
        expect(result.topUsedApp, isNull);
        expect(result.unhealthyAppCount, 0);
        expect(result.patternStatus, UsagePatternStatus.healthy);
        expect(
          result.recommendationMessage,
          'Usage looks healthy. Keep maintaining balanced screen time.',
        );
      },
    );
  });
}
