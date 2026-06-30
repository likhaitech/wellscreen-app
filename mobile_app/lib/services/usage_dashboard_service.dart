import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'intervention_recommendation_service.dart';
import 'usage_tracking_service.dart';

class UsageDashboardResult {
  const UsageDashboardResult({
    required this.hasUsagePermission,
    required this.isUsingCachedData,
    required this.report,
    required this.interventionRecommendation,
    required this.errorMessage,
  });

  final bool hasUsagePermission;
  final bool isUsingCachedData;
  final UsageReport? report;
  final InterventionRecommendation? interventionRecommendation;
  final String? errorMessage;
}

class UsageDashboardService {
  UsageDashboardService({
    UsageTrackingService? usageTrackingService,
    InterventionRecommendationService? interventionRecommendationService,
  }) : _usageTrackingService = usageTrackingService ?? UsageTrackingService(),
       _interventionRecommendationService =
           interventionRecommendationService ??
           InterventionRecommendationService();

  final UsageTrackingService _usageTrackingService;
  final InterventionRecommendationService _interventionRecommendationService;

  Future<UsageDashboardResult> loadTodayDashboard() async {
    final hasPermission = await _usageTrackingService.hasUsagePermission();

    if (!hasPermission) {
      final cachedReport = await _usageTrackingService
          .getCachedTodayUsageReport();

      return UsageDashboardResult(
        hasUsagePermission: false,
        isUsingCachedData: cachedReport != null,
        report: cachedReport,
        interventionRecommendation: _getIntervention(cachedReport),
        errorMessage: cachedReport == null
            ? 'Usage access permission is required to generate today’s report.'
            : 'Showing the last cached usage report because usage permission is missing.',
      );
    }

    try {
      final report = await _usageTrackingService.getTodayUsageReport();

      return UsageDashboardResult(
        hasUsagePermission: true,
        isUsingCachedData: false,
        report: report,
        interventionRecommendation: _getIntervention(report),
        errorMessage: null,
      );
    } catch (_) {
      final cachedReport = await _usageTrackingService
          .getCachedTodayUsageReport();

      return UsageDashboardResult(
        hasUsagePermission: true,
        isUsingCachedData: cachedReport != null,
        report: cachedReport,
        interventionRecommendation: _getIntervention(cachedReport),
        errorMessage: cachedReport == null
            ? 'Unable to load today’s usage report.'
            : 'Showing the last cached usage report because live usage tracking failed.',
      );
    }
  }

  Future<List<AppUsageSummary>> loadTodayAppUsageList() {
    return _usageTrackingService.getTodayUsage();
  }

  InterventionRecommendation? _getIntervention(UsageReport? report) {
    if (report == null) {
      return null;
    }

    return _interventionRecommendationService.getRecommendation(report);
  }
}
