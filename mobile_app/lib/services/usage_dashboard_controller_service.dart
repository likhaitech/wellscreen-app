import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_usage_summary.dart';
import 'age_based_screen_time_threshold_service.dart';
import 'daily_screen_time_limit_service.dart';
import 'screen_time_goal_service.dart';
import 'usage_dashboard_service.dart';
import 'usage_dashboard_view_model_service.dart';

class UsageDashboardControllerState {
  const UsageDashboardControllerState({
    required this.viewModel,
    required this.appUsageList,
    required this.dailyScreenTimeLimit,
    required this.recommendedDailyScreenTimeLimit,
    required this.isUsingGuardianCustomLimit,
    required this.ageThresholdLabel,
    required this.screenTimeGoalResult,
    this.childAge,
  });

  final UsageDashboardViewModel viewModel;
  final List<AppUsageSummary> appUsageList;
  final Duration dailyScreenTimeLimit;
  final Duration recommendedDailyScreenTimeLimit;
  final bool isUsingGuardianCustomLimit;
  final String ageThresholdLabel;
  final ScreenTimeGoalResult? screenTimeGoalResult;
  final int? childAge;
}

class UsageDashboardControllerService {
  UsageDashboardControllerService({
    UsageDashboardService? usageDashboardService,
    UsageDashboardViewModelService? viewModelService,
    DailyScreenTimeLimitService? dailyScreenTimeLimitService,
    ScreenTimeGoalService? screenTimeGoalService,
    AgeBasedScreenTimeThresholdService? ageThresholdService,
    this._firebaseAuth,
    this._firestore,
  }) : _usageDashboardService =
           usageDashboardService ?? UsageDashboardService(),
       _viewModelService = viewModelService ?? UsageDashboardViewModelService(),
       _dailyScreenTimeLimitService =
           dailyScreenTimeLimitService ?? DailyScreenTimeLimitService(),
       _screenTimeGoalService =
           screenTimeGoalService ?? ScreenTimeGoalService(),
       _ageThresholdService =
           ageThresholdService ?? AgeBasedScreenTimeThresholdService();

  final UsageDashboardService _usageDashboardService;
  final UsageDashboardViewModelService _viewModelService;
  final DailyScreenTimeLimitService _dailyScreenTimeLimitService;
  final ScreenTimeGoalService _screenTimeGoalService;
  final AgeBasedScreenTimeThresholdService _ageThresholdService;
  final FirebaseAuth? _firebaseAuth;
  final FirebaseFirestore? _firestore;

  Future<UsageDashboardControllerState> loadTodayDashboardState() async {
    final dashboardResult = await _usageDashboardService.loadTodayDashboard();
    final viewModel = _viewModelService.buildViewModel(dashboardResult);

    final childAge = await _loadFirstChildAgeForCurrentParent();
    final ageThreshold = _ageThresholdService.getThresholdForAge(childAge);

    final isUsingGuardianCustomLimit = await _dailyScreenTimeLimitService
        .hasCustomDailyLimit();

    final dailyLimit = await _dailyScreenTimeLimitService
        .getDailyLimitForChildAge(childAge);

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
      recommendedDailyScreenTimeLimit: ageThreshold.dailyLimit,
      isUsingGuardianCustomLimit: isUsingGuardianCustomLimit,
      ageThresholdLabel: ageThreshold.ageGroupLabel,
      childAge: childAge,
      screenTimeGoalResult: screenTimeGoalResult,
    );
  }

  Future<int?> _loadFirstChildAgeForCurrentParent() async {
    try {
      final firebaseAuth = _firebaseAuth ?? FirebaseAuth.instance;
      final firestore = _firestore ?? FirebaseFirestore.instance;

      final user = firebaseAuth.currentUser;

      if (user == null) {
        return null;
      }

      final childProfilesSnapshot = await firestore
          .collection('child_profiles')
          .where('parentId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (childProfilesSnapshot.docs.isEmpty) {
        return null;
      }

      final data = childProfilesSnapshot.docs.first.data();
      final ageValue = data['age'];

      if (ageValue is int) {
        return ageValue;
      }

      if (ageValue is num) {
        return ageValue.toInt();
      }

      if (ageValue is String) {
        return int.tryParse(ageValue);
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
