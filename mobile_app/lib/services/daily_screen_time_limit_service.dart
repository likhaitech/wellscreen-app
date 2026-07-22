import 'package:shared_preferences/shared_preferences.dart';

import 'age_based_screen_time_threshold_service.dart';

class DailyScreenTimeLimitService {
  DailyScreenTimeLimitService({
    AgeBasedScreenTimeThresholdService? ageThresholdService,
  }) : _ageThresholdService =
           ageThresholdService ?? AgeBasedScreenTimeThresholdService();

  static const String _dailyScreenTimeLimitMinutesKey =
      'daily_screen_time_limit_minutes';

  static const Duration defaultDailyLimit = Duration(hours: 3);

  final AgeBasedScreenTimeThresholdService _ageThresholdService;

  Future<void> saveDailyLimit(Duration dailyLimit) async {
    try {
      final preferences = await SharedPreferences.getInstance();

      if (dailyLimit <= Duration.zero) {
        await preferences.remove(_dailyScreenTimeLimitMinutesKey);
        return;
      }

      await preferences.setInt(
        _dailyScreenTimeLimitMinutesKey,
        dailyLimit.inMinutes,
      );
    } catch (_) {
      return;
    }
  }

  Future<Duration> getDailyLimit() async {
    final customLimit = await getCustomDailyLimit();

    if (customLimit != null) {
      return customLimit;
    }

    return defaultDailyLimit;
  }

  Future<Duration> getDailyLimitForChildAge(int? childAge) async {
    final customLimit = await getCustomDailyLimit();

    if (customLimit != null) {
      return customLimit;
    }

    return _ageThresholdService.getDailyLimitForAge(childAge);
  }

  Duration getRecommendedDailyLimitForAge(int? childAge) {
    return _ageThresholdService.getDailyLimitForAge(childAge);
  }

  Future<Duration?> getCustomDailyLimit() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedMinutes = preferences.getInt(_dailyScreenTimeLimitMinutesKey);

      if (savedMinutes == null || savedMinutes <= 0) {
        return null;
      }

      return Duration(minutes: savedMinutes);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasCustomDailyLimit() async {
    final customLimit = await getCustomDailyLimit();
    return customLimit != null;
  }

  Future<void> clearDailyLimit() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_dailyScreenTimeLimitMinutesKey);
    } catch (_) {
      return;
    }
  }
}
