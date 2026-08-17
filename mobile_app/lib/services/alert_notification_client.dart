import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';

/// Calls the backend's POST /alerts/notify (see
/// backend/app/routes/alerts.py) to push a real notification to the paired
/// parent's device. This is fire-and-forget by design: push is a
/// nice-to-have layered on top of what already works without it (Firestore
/// sync the parent's app picks up live, plus the SMS backup alert for
/// restricted-app blocks) - a failed/unreachable backend here should never
/// block or fail the caller's real work (syncing usage data, sharing GPS).
class AlertNotificationClient {
  AlertNotificationClient()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.backendBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

  final Dio _dio;

  Future<void> notifyParent({
    required String parentUid,
    required String title,
    required String body,
    required String alertType,
    Map<String, dynamic>? data,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || parentUid.isEmpty) return;

    try {
      final idToken = await user.getIdToken();

      await _dio.post(
        '/alerts/notify',
        data: {
          'parent_uid': parentUid,
          'title': title,
          'body': body,
          'alert_type': alertType,
          'data': ?data,
        },
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
    } catch (_) {
      // Best-effort - see class doc. The underlying data (usage report,
      // GPS, SMS log) has already been written to Firestore/sent by the
      // time this is called, so a failure here only means the parent
      // doesn't get an immediate push; they'll still see it next time they
      // open the app.
    }
  }
}
