import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

class AdminSettingsApiService {
  AdminSettingsApiService()
    : _dio = Dio(
        BaseOptions(
          // Was hardcoded to the Android-emulator-only address
          // 'http://10.0.2.2:8000' - moved to AppConfig.backendBaseUrl so
          // this and the new push-notification client (see
          // alert_notification_client.dart) share one place to update once
          // the backend is actually deployed, instead of two.
          baseUrl: AppConfig.backendBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;

  Future<String> _getAdminToken() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('No authenticated user.');
    }

    final tokenResult = await user.getIdTokenResult(true);
    final token = tokenResult.token;

    if (token == null || token.isEmpty) {
      throw Exception('Unable to get Firebase ID token.');
    }

    return token;
  }

  Future<Map<String, dynamic>> getSettings() async {
    final token = await _getAdminToken();

    final response = await _dio.get(
      '/admin/settings/',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int defaultDailyLimitMinutes,
    required bool appBlockingEnabled,
    required bool focusModeEnabled,
    required bool cooldownTimerEnabled,
    required bool scheduledLockEnabled,
    required bool categoryRestrictionEnabled,
    required bool emergencyAccessEnabled,
  }) async {
    final token = await _getAdminToken();

    final response = await _dio.patch(
      '/admin/settings/',
      data: {
        'default_daily_limit_minutes': defaultDailyLimitMinutes,
        'app_blocking_enabled': appBlockingEnabled,
        'focus_mode_enabled': focusModeEnabled,
        'cooldown_timer_enabled': cooldownTimerEnabled,
        'scheduled_lock_enabled': scheduledLockEnabled,
        'category_restriction_enabled': categoryRestrictionEnabled,
        'emergency_access_enabled': emergencyAccessEnabled,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return Map<String, dynamic>.from(response.data);
  }
}
