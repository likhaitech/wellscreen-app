import 'package:shared_preferences/shared_preferences.dart';

class DailyScreenTimeLimitService {
  static const String _dailyScreenTimeLimitMinutesKey =
      'daily_screen_time_limit_minutes';

  static const Duration defaultDailyLimit = Duration(hours: 3);

  Future<void> saveDailyLimit(Duration dailyLimit) async {
    final preferences = await SharedPreferences.getInstance();

    if (dailyLimit <= Duration.zero) {
      await preferences.remove(_dailyScreenTimeLimitMinutesKey);
      return;
    }

    await preferences.setInt(
      _dailyScreenTimeLimitMinutesKey,
      dailyLimit.inMinutes,
    );
  }

  Future<Duration> getDailyLimit() async {
    final preferences = await SharedPreferences.getInstance();
    final savedMinutes = preferences.getInt(_dailyScreenTimeLimitMinutesKey);

    if (savedMinutes == null || savedMinutes <= 0) {
      return defaultDailyLimit;
    }

    return Duration(minutes: savedMinutes);
  }

  Future<void> clearDailyLimit() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_dailyScreenTimeLimitMinutesKey);
  }
}
