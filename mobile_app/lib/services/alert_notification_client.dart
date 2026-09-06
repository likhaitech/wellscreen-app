import 'package:cloud_firestore/cloud_firestore.dart';
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
///
/// The outcome (sent/failed + why) and round-trip response time ARE
/// recorded though - to child_profiles/{childProfileId}.pushAlertLog, the
/// same "log real outcomes, not just whether the feature is on" pattern
/// SmsAlertSender.kt uses for SMS - so this has an honest, measured delivery
/// success rate instead of a fire-and-forget guess.
class AlertNotificationClient {
  // All three are injectable so tests can exercise the real
  // outcome-classification and best-effort-logging logic below without a
  // real backend, real FirebaseAuth, or real Firestore - each is
  // optional and defaults to the exact real behavior this class had
  // before, so the app's real callers are unaffected.
  //
  // getIdToken collapses "no authenticated user" and "get the real ID
  // token" into one seam: returning null means bail out early (matching
  // the original `user == null` check), matching a real token string
  // means proceed - callers of notifyParent() can't tell the difference
  // between "no user" and "user with a token" from the outside anyway,
  // since both just mean "here is (or isn't) something to send".
  AlertNotificationClient({
    Dio? dio,
    Future<String?> Function()? getIdToken,
    Future<void> Function(String childProfileId, Map<String, dynamic> logEntry)?
    logPushAttempt,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.backendBaseUrl,
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 8),
             ),
           ),
       _getIdToken = getIdToken ?? _realGetIdToken,
       _logPushAttempt = logPushAttempt ?? _realLogPushAttempt;

  final Dio _dio;
  final Future<String?> Function() _getIdToken;
  final Future<void> Function(String childProfileId, Map<String, dynamic> logEntry)
  _logPushAttempt;

  static Future<String?> _realGetIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  static Future<void> _realLogPushAttempt(
    String childProfileId,
    Map<String, dynamic> logEntry,
  ) async {
    await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .set({
          'pushAlertLog': FieldValue.arrayUnion([logEntry]),
        }, SetOptions(merge: true))
        // cloud_firestore's set() hangs forever offline instead of
        // throwing (firebase/flutterfire#17643) - this is best-effort
        // logging, so a timeout here should just be swallowed like any
        // other failure, not hang the caller.
        .timeout(const Duration(seconds: 10));
  }

  Future<void> notifyParent({
    required String parentUid,
    required String title,
    required String body,
    required String alertType,
    String? childProfileId,
    Map<String, dynamic>? data,
  }) async {
    if (parentUid.isEmpty) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;

    final stopwatch = Stopwatch()..start();
    String outcome;
    String? error;

    try {
      final response = await _dio.post(
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

      // The backend already tells us whether messaging.send() actually
      // succeeded (see notification_service.py's {"status": "sent"/
      // "failed", ...} return value) - a 2xx HTTP response only means the
      // request was accepted and authorized, not that FCM delivered it.
      final responseData = response.data;
      final status = responseData is Map ? responseData['status'] : null;

      if (status == 'sent') {
        outcome = 'sent';
      } else {
        outcome = 'failed_backend';
        error = responseData is Map ? responseData['error']?.toString() : null;
      }
    } on DioException catch (e) {
      outcome = 'failed_network';
      error = e.message;
    } catch (e) {
      outcome = 'failed_exception';
      error = e.toString();
    }

    stopwatch.stop();

    // Best-effort - see class doc. The underlying data (usage report, GPS,
    // SMS log) has already been written to Firestore/sent by the time this
    // is called, so a failure here (either the push itself, or just this
    // log write) only means the parent doesn't get an immediate push;
    // they'll still see it next time they open the app.
    if (childProfileId != null && childProfileId.isNotEmpty) {
      try {
        await _logPushAttempt(childProfileId, {
          'alertType': alertType,
          'outcome': outcome,
          'responseTimeMs': stopwatch.elapsedMilliseconds,
          'timestampMs': DateTime.now().millisecondsSinceEpoch,
          'error': ?error,
        });
      } catch (_) {
        // Logging failure doesn't matter beyond the push attempt above.
      }
    }
  }
}
