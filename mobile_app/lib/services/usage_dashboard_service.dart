import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'usage_tracking_service.dart';

class UsageDashboardResult {
  const UsageDashboardResult({
    required this.hasUsagePermission,
    required this.isUsingCachedData,
    required this.report,
    required this.cachedReportData,
    required this.errorMessage,
  });

  final bool hasUsagePermission;
  final bool isUsingCachedData;
  final UsageReport? report;
  final Map<String, dynamic>? cachedReportData;
  final String? errorMessage;
}

class UsageDashboardService {
  UsageDashboardService({UsageTrackingService? usageTrackingService})
    : _usageTrackingService = usageTrackingService ?? UsageTrackingService();

  final UsageTrackingService _usageTrackingService;

  Future<UsageDashboardResult> loadTodayDashboard() async {
    final hasPermission = await _usageTrackingService.hasUsagePermission();

    if (!hasPermission) {
      final cachedData = await _usageTrackingService
          .getCachedTodayUsageReportData();

      return UsageDashboardResult(
        hasUsagePermission: false,
        isUsingCachedData: cachedData != null,
        report: null,
        cachedReportData: cachedData,
        errorMessage: cachedData == null
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
        cachedReportData: null,
        errorMessage: null,
      );
    } catch (_) {
      final cachedData = await _usageTrackingService
          .getCachedTodayUsageReportData();

      return UsageDashboardResult(
        hasUsagePermission: true,
        isUsingCachedData: cachedData != null,
        report: null,
        cachedReportData: cachedData,
        errorMessage: cachedData == null
            ? 'Unable to load today’s usage report.'
            : 'Showing the last cached usage report because live usage tracking failed.',
      );
    }
  }

  Future<List<AppUsageSummary>> loadTodayAppUsageList() {
    return _usageTrackingService.getTodayUsage();
  }
}
