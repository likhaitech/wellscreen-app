import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Sends a best-effort push notification request AFTER a parent saves a limit.
/// The Worker authenticates the parent and reads the ACTUAL saved Firestore data.
/// It is not a replacement for AppTimeLimitService or the child FCM receiver.
class AppTimeLimitCloudflareNotifier {
  AppTimeLimitCloudflareNotifier._();

  // Replace with your Cloudflare Worker URL including /notify-limit.
  static const String workerUrl =
      'https://REPLACE_WITH_YOUR_WORKER.workers.dev/notify-limit';

  static Future<void> notifyLimitSaved({
    required String childProfileId,
    required String packageName,
  }) async {
    if (workerUrl.contains('REPLACE_WITH_YOUR_WORKER')) {
      debugPrint('Cloudflare notification not configured yet.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);

    try {
      final firebaseIdToken = await user.getIdToken();
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) return;

      final request = await client
          .postUrl(Uri.parse(workerUrl))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $firebaseIdToken',
      );
      request.add(utf8.encode(jsonEncode({
        'childProfileId': childProfileId,
        'packageName': packageName,
      })));

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        debugPrint('Cloudflare push request returned HTTP ${response.statusCode}');
      }
      await response.drain<void>();
    } catch (error) {
      // The Firestore save already succeeded. Do not fail the parent UI
      // just because a best-effort push notification could not be sent.
      debugPrint('Cloudflare app-limit notification failed: $error');
    } finally {
      client.close(force: true);
    }
  }
}
