import '../models/app_usage_summary.dart';
import 'daily_screen_time_limit_service.dart';
import 'screen_time_goal_service.dart';
import 'usage_dashboard_service.dart';
import 'usage_dashboard_view_model_service.dart';

class UsageDashboardControllerState {
  const UsageDashboardControllerState({
    required this.viewModel,
    required this.appUsageList,
    required this.dailyScreenTimeLimit,
    required this.screenTimeGoalResult,
  });

  final UsageDashboardViewModel viewModel;
  final List<AppUsageSummary> appUsageList;
  final Duration dailyScreenTimeLimit;
  final ScreenTimeGoalResult? screenTimeGoalResult;
}

class UsageDashboardControllerService {
  UsageDashboardControllerService({
    UsageDashboardService? usageDashboardService,
    UsageDashboardViewModelService? viewModelService,
    DailyScreenTimeLimitService? dailyScreenTimeLimitService,
    ScreenTimeGoalService? screenTimeGoalService,
  }) : _usageDashboardService =
           usageDashboardService ?? UsageDashboardService(),
       _viewModelService = viewModelService ?? UsageDashboardViewModelService(),
       _dailyScreenTimeLimitService =
           dailyScreenTimeLimitService ?? DailyScreenTimeLimitService(),
       _screenTimeGoalService =
           screenTimeGoalService ?? ScreenTimeGoalService();

  final UsageDashboardService _usageDashboardService;
  final UsageDashboardViewModelService _viewModelService;
  final DailyScreenTimeLimitService _dailyScreenTimeLimitService;
  final ScreenTimeGoalService _screenTimeGoalService;

  Future<UsageDashboardControllerState> loadTodayDashboardState() async {
    final dashboardResult = await _usageDashboardService.loadTodayDashboard();
    final viewModel = _viewModelService.buildViewModel(dashboardResult);
    final dailyLimit = await _dailyScreenTimeLimitService.getDailyLimit();

    final screenTimeGoalResult = dashboardResult.report == null
        ? null
        : _screenTimeGoalService.evaluate(
            report: dashboardResult.report!,
            dailyLimit: dailyLimit,
          );

    final appUsageList = dashboardResult.hasUsagePermission
        ? await _usageDashboardService.loadTodayAppUsageList()
        : <AppUsageSummary>[];

    return UsageDashboardControllerState(
      viewModel: viewModel,
      appUsageList: appUsageList,
      dailyScreenTimeLimit: dailyLimit,
      screenTimeGoalResult: screenTimeGoalResult,
    );
  }
}
