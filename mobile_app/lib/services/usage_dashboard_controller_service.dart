import '../models/app_usage_summary.dart';
import 'usage_dashboard_service.dart';
import 'usage_dashboard_view_model_service.dart';

class UsageDashboardControllerState {
  const UsageDashboardControllerState({
    required this.viewModel,
    required this.appUsageList,
  });

  final UsageDashboardViewModel viewModel;
  final List<AppUsageSummary> appUsageList;
}

class UsageDashboardControllerService {
  UsageDashboardControllerService({
    UsageDashboardService? usageDashboardService,
    UsageDashboardViewModelService? viewModelService,
  }) : _usageDashboardService =
           usageDashboardService ?? UsageDashboardService(),
       _viewModelService = viewModelService ?? UsageDashboardViewModelService();

  final UsageDashboardService _usageDashboardService;
  final UsageDashboardViewModelService _viewModelService;

  Future<UsageDashboardControllerState> loadTodayDashboardState() async {
    final dashboardResult = await _usageDashboardService.loadTodayDashboard();
    final viewModel = _viewModelService.buildViewModel(dashboardResult);

    final appUsageList = dashboardResult.hasUsagePermission
        ? await _usageDashboardService.loadTodayAppUsageList()
        : <AppUsageSummary>[];

    return UsageDashboardControllerState(
      viewModel: viewModel,
      appUsageList: appUsageList,
    );
  }
}
