import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/daily_screen_time_limit_service.dart';

// Was previously a byte-for-byte copy of screen_time_goal_service_test.dart,
// which meant DailyScreenTimeLimitService had no real coverage despite a
// file bearing its name (flagged in the Unit Testing chapter's findings).
// These tests exercise the actual class: saving/reading the persisted
// limit, the default-limit fallback, clearing, and the invalid-duration
// edge case - not ScreenTimeGoalService's evaluate() logic.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyScreenTimeLimitService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns the default daily limit when nothing has been saved', () async {
      final service = DailyScreenTimeLimitService();

      final limit = await service.getDailyLimit();

      expect(limit, DailyScreenTimeLimitService.defaultDailyLimit);
      expect(limit, const Duration(hours: 3));
    });

    test('saves and reads back a custom daily limit', () async {
      final service = DailyScreenTimeLimitService();

      await service.saveDailyLimit(const Duration(hours: 1, minutes: 30));
      final limit = await service.getDailyLimit();

      expect(limit, const Duration(hours: 1, minutes: 30));
    });

    test('rounds the saved limit to whole minutes on read-back', () async {
      final service = DailyScreenTimeLimitService();

      // Saved as inMinutes internally, so a value with seconds should read
      // back truncated to whole minutes rather than throwing or losing the
      // rest of the value silently.
      await service.saveDailyLimit(const Duration(minutes: 45, seconds: 40));
      final limit = await service.getDailyLimit();

      expect(limit, const Duration(minutes: 45));
    });

    test('saving a zero duration clears the limit instead of storing zero', () async {
      final service = DailyScreenTimeLimitService();

      await service.saveDailyLimit(const Duration(hours: 2));
      await service.saveDailyLimit(Duration.zero);
      final limit = await service.getDailyLimit();

      // Zero/negative is treated as "no limit configured", so reading it
      // back falls through to the default rather than returning zero.
      expect(limit, DailyScreenTimeLimitService.defaultDailyLimit);
    });

    test('saving a negative duration also clears the limit', () async {
      final service = DailyScreenTimeLimitService();

      await service.saveDailyLimit(const Duration(hours: 2));
      await service.saveDailyLimit(const Duration(minutes: -10));
      final limit = await service.getDailyLimit();

      expect(limit, DailyScreenTimeLimitService.defaultDailyLimit);
    });

    test('clearDailyLimit removes a previously saved limit', () async {
      final service = DailyScreenTimeLimitService();

      await service.saveDailyLimit(const Duration(hours: 4));
      await service.clearDailyLimit();
      final limit = await service.getDailyLimit();

      expect(limit, DailyScreenTimeLimitService.defaultDailyLimit);
    });

    test('a saved limit persists across separate service instances', () async {
      // SharedPreferences-backed, so a second instance (as guardian and
      // child screens would each construct independently) must see the
      // same persisted value rather than an in-memory-only one.
      final writer = DailyScreenTimeLimitService();
      await writer.saveDailyLimit(const Duration(hours: 5));

      final reader = DailyScreenTimeLimitService();
      final limit = await reader.getDailyLimit();

      expect(limit, const Duration(hours: 5));
    });
  });
}
