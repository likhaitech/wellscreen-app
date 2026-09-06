import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/alert_notification_client.dart';

/// Covers AlertNotificationClient - previously untestable because it
/// tangled together three separate real dependencies with no injection
/// seam at all: a real Dio() hitting a real backend, real
/// FirebaseAuth.instance.currentUser, and real
/// FirebaseFirestore.instance writes. Fixed by making all three
/// injectable (each optional, defaulting to the exact real behavior this
/// class had before - see the class doc comment on the constructor), so
/// the app's real call site in child_home_screen.dart needed no change.
///
/// This class's own doc comment says its whole reason for the
/// pushAlertLog write is "an honest, measured delivery success rate
/// instead of a fire-and-forget guess" - these tests are what actually
/// verify that promise: that every real outcome (sent, backend-reported
/// failure, network exception, unexpected exception) gets classified and
/// logged correctly, and that a logging failure itself never propagates
/// to the caller (this is fire-and-forget by design, per the class doc).
void main() {
  group('AlertNotificationClient.notifyParent - early-return guards', () {
    test('does nothing (no request, no log) when parentUid is empty', () async {
      var requestMade = false;
      var logCalled = false;

      final client = AlertNotificationClient(
        dio: Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                requestMade = true;
                h.next(o);
              },
            ),
          ),
        getIdToken: () async => 'should-not-be-used',
        logPushAttempt: (id, entry) async => logCalled = true,
      );

      await client.notifyParent(
        parentUid: '',
        title: 't',
        body: 'b',
        alertType: 'test',
        childProfileId: 'cp1',
      );

      expect(requestMade, isFalse);
      expect(logCalled, isFalse);
    });

    test(
      'does nothing (no request, no log) when getIdToken returns null '
      '(no authenticated user)',
      () async {
        var requestMade = false;
        var logCalled = false;

        final client = AlertNotificationClient(
          dio: Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (o, h) {
                  requestMade = true;
                  h.next(o);
                },
              ),
            ),
          getIdToken: () async => null,
          logPushAttempt: (id, entry) async => logCalled = true,
        );

        await client.notifyParent(
          parentUid: 'parent1',
          title: 't',
          body: 'b',
          alertType: 'test',
          childProfileId: 'cp1',
        );

        expect(requestMade, isFalse);
        expect(logCalled, isFalse);
      },
    );
  });

  group('AlertNotificationClient.notifyParent - outcome classification', () {
    test(
      'a backend response with status "sent" logs outcome "sent"',
      () async {
        Map<String, dynamic>? loggedEntry;

        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'status': 'sent'},
                  ),
                );
              },
            ),
          );

        final client = AlertNotificationClient(
          dio: dio,
          getIdToken: () async => 'tok',
          logPushAttempt: (id, entry) async => loggedEntry = entry,
        );

        await client.notifyParent(
          parentUid: 'parent1',
          title: 't',
          body: 'b',
          alertType: 'restricted_app_attempt',
          childProfileId: 'cp1',
        );

        expect(loggedEntry, isNotNull);
        expect(loggedEntry!['outcome'], 'sent');
        expect(loggedEntry!['alertType'], 'restricted_app_attempt');
        expect(loggedEntry!['error'], isNull);
        expect(loggedEntry!['responseTimeMs'], isA<int>());
      },
    );

    test(
      'a 2xx backend response reporting a non-"sent" status logs '
      '"failed_backend" with the backend\'s error message',
      () async {
        Map<String, dynamic>? loggedEntry;

        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'status': 'failed', 'error': 'no FCM token on file'},
                  ),
                );
              },
            ),
          );

        final client = AlertNotificationClient(
          dio: dio,
          getIdToken: () async => 'tok',
          logPushAttempt: (id, entry) async => loggedEntry = entry,
        );

        await client.notifyParent(
          parentUid: 'parent1',
          title: 't',
          body: 'b',
          alertType: 'test',
          childProfileId: 'cp1',
        );

        expect(loggedEntry!['outcome'], 'failed_backend');
        expect(loggedEntry!['error'], 'no FCM token on file');
      },
    );

    test(
      'a DioException (network failure) logs "failed_network" with the '
      'exception message',
      () async {
        Map<String, dynamic>? loggedEntry;

        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionTimeout,
                    message: 'connection timed out',
                  ),
                );
              },
            ),
          );

        final client = AlertNotificationClient(
          dio: dio,
          getIdToken: () async => 'tok',
          logPushAttempt: (id, entry) async => loggedEntry = entry,
        );

        await client.notifyParent(
          parentUid: 'parent1',
          title: 't',
          body: 'b',
          alertType: 'test',
          childProfileId: 'cp1',
        );

        expect(loggedEntry!['outcome'], 'failed_network');
        expect(loggedEntry!['error'], 'connection timed out');
      },
    );

    test(
      'notifyParent itself never throws, even when the backend call fails',
      () async {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
              },
            ),
          );

        final client = AlertNotificationClient(
          dio: dio,
          getIdToken: () async => 'tok',
          logPushAttempt: (id, entry) async {},
        );

        // Should complete without throwing - this is fire-and-forget by
        // design (see class doc comment).
        await expectLater(
          client.notifyParent(
            parentUid: 'parent1',
            title: 't',
            body: 'b',
            alertType: 'test',
          ),
          completes,
        );
      },
    );
  });

  group('AlertNotificationClient.notifyParent - best-effort logging', () {
    test('does not attempt to log when childProfileId is omitted', () async {
      var logCalled = false;

      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'status': 'sent'},
                ),
              );
            },
          ),
        );

      final client = AlertNotificationClient(
        dio: dio,
        getIdToken: () async => 'tok',
        logPushAttempt: (id, entry) async => logCalled = true,
      );

      await client.notifyParent(
        parentUid: 'parent1',
        title: 't',
        body: 'b',
        alertType: 'test',
        // no childProfileId
      );

      expect(logCalled, isFalse);
    });

    test(
      'a failure in the log write itself does not propagate to the caller '
      '(logging is best-effort, per the class doc)',
      () async {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'status': 'sent'},
                  ),
                );
              },
            ),
          );

        final client = AlertNotificationClient(
          dio: dio,
          getIdToken: () async => 'tok',
          logPushAttempt: (id, entry) async =>
              throw Exception('Firestore is offline'),
        );

        await expectLater(
          client.notifyParent(
            parentUid: 'parent1',
            title: 't',
            body: 'b',
            alertType: 'test',
            childProfileId: 'cp1',
          ),
          completes,
        );
      },
    );

    test(
      'the "data" payload is omitted from the request entirely when null '
      '(null-aware spread), rather than sent as a null field',
      () async {
        Map<String, dynamic>? capturedBody;

        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                capturedBody = Map<String, dynamic>.from(options.data as Map);
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'status': 'sent'},
                  ),
                );
              },
            ),
          );

        final client = AlertNotificationClient(
          dio: dio,
          getIdToken: () async => 'tok',
          logPushAttempt: (id, entry) async {},
        );

        await client.notifyParent(
          parentUid: 'parent1',
          title: 't',
          body: 'b',
          alertType: 'test',
        );

        expect(capturedBody!.containsKey('data'), isFalse);
      },
    );
  });
}
