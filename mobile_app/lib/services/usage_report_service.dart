import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'pattern_detection_service.dart';

class UsageReportService {
  UsageReportService({PatternDetectionService? patternDetectionService})
    : _patternDetectionService =
          patternDetectionService ?? PatternDetectionService();

  final PatternDetectionService _patternDetectionService;

  UsageReport generateFromSummaries(
    List<AppUsageSummary> summaries, {
    int? childAge,
  }) {
    return _patternDetectionService.generateReport(
      summaries,
      childAge: childAge,
    );
  }
}
