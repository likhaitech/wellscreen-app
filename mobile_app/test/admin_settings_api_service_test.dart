import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/admin_settings_api_service.dart';

/// Covers AdminSettingsApiService - previously untestable because it
/// constructed a real Dio() and called the real FirebaseAuth.instance
/// directly, with no injection seam at all. Fixed by making both
/// injectable (optional constructor params defaulting to the real
/// behavior, so the app's one real call site in admin_settings_screen.dart
/// needed no change).
///
/// No real network call is made here: each test wires the injected Dio
/// with an `InterceptorsWrapper` that intercepts onRequest and resolves
/// (or rejects) immediately with a canned response, inspecting the real
/// request Dio built (path, method, headers, body) before doing so. This
/// is a standard Dio testing technique (short-circuiting at the
/// interceptor stage, before Dio ever reaches its transport/adapter
/// layer) - deliberately chosen over faking Dio's lower-level
/// HttpClientAdapter, since this dev environment has no network access to
/// pub.dev to double-check that lower-level interface's exact shape
/// against the pinned dio version, and getting that detail wrong would
/// produce a test that fails for the wrong reason.
void main() {
  Dio dioWithInterceptor(
    void Function(RequestOptions options, RequestInterceptorHandler handler)
    onRequest,
  ) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: onRequest));
    return dio;
  }

  group('AdminSettingsApiService token handling', () {
    test(
      'getSettings propagates an error from the token provider without '
      'ever making a request',
      () async {
        var requestWasMade = false;
        final dio = dioWithInterceptor((options, handler) {
          requestWasMade = true;
          handler.next(options);
        });

        final service = AdminSettingsApiService(
          dio: dio,
          getAdminToken: () async => throw Exception('No authenticated user.'),
        );

        await expectLater(
          service.getSettings(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No authenticated user.'),
            ),
          ),
        );
        expect(requestWasMade, isFalse);
      },
    );

    test(
      'getSettings sends the token from the provider as a Bearer header',
      () async {
        String? capturedAuthHeader;

        final dio = dioWithInterceptor((options, handler) {
          capturedAuthHeader = options.headers['Authorization'] as String?;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'default_daily_limit_minutes': 120},
            ),
          );
        });

        final service = AdminSettingsApiService(
          dio: dio,
          getAdminToken: () async => 'test-token-123',
        );

        final result = await service.getSettings();

        expect(capturedAuthHeader, 'Bearer test-token-123');
        expect(result['default_daily_limit_minutes'], 120);
      },
    );

    test('getSettings requests GET /admin/settings/', () async {
      String? capturedPath;
      String? capturedMethod;

      final dio = dioWithInterceptor((options, handler) {
        capturedPath = options.path;
        capturedMethod = options.method;
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: {}),
        );
      });

      final service = AdminSettingsApiService(
        dio: dio,
        getAdminToken: () async => 'tok',
      );

      await service.getSettings();

      expect(capturedPath, '/admin/settings/');
      expect(capturedMethod, 'GET');
    });
  });

  group('AdminSettingsApiService.updateSettings', () {
    test('PATCHes /admin/settings/ with every field, snake_cased', () async {
      Map<String, dynamic>? capturedBody;
      String? capturedMethod;

      final dio = dioWithInterceptor((options, handler) {
        capturedMethod = options.method;
        capturedBody = Map<String, dynamic>.from(options.data as Map);
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: capturedBody),
        );
      });

      final service = AdminSettingsApiService(
        dio: dio,
        getAdminToken: () async => 'tok',
      );

      final result = await service.updateSettings(
        defaultDailyLimitMinutes: 90,
        appBlockingEnabled: true,
        focusModeEnabled: false,
        cooldownTimerEnabled: true,
        scheduledLockEnabled: false,
        categoryRestrictionEnabled: true,
        emergencyAccessEnabled: false,
      );

      expect(capturedMethod, 'PATCH');
      expect(capturedBody, {
        'default_daily_limit_minutes': 90,
        'app_blocking_enabled': true,
        'focus_mode_enabled': false,
        'cooldown_timer_enabled': true,
        'scheduled_lock_enabled': false,
        'category_restriction_enabled': true,
        'emergency_access_enabled': false,
      });
      // The response is round-tripped through Map<String, dynamic>.from -
      // confirm that conversion actually happens and returns usable data.
      expect(result['default_daily_limit_minutes'], 90);
    });

    test(
      'a backend error response surfaces as a DioException to the caller',
      () async {
        final dio = dioWithInterceptor((options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 403,
                data: {'detail': 'Not an admin'},
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        });

        final service = AdminSettingsApiService(
          dio: dio,
          getAdminToken: () async => 'tok',
        );

        await expectLater(
          service.updateSettings(
            defaultDailyLimitMinutes: 90,
            appBlockingEnabled: true,
            focusModeEnabled: false,
            cooldownTimerEnabled: true,
            scheduledLockEnabled: false,
            categoryRestrictionEnabled: true,
            emergencyAccessEnabled: false,
          ),
          throwsA(isA<DioException>()),
        );
      },
    );
  });
}
