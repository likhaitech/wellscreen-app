import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/sync_status_service.dart';

/// Covers SyncStatusService - previously untestable because it
/// constructed the real connectivity_plus Connectivity() directly, which
/// talks to real OS platform channels and has no built-in fake. Fixed by
/// injecting the two plain function/stream seams the class actually
/// needs (checkConnectivity, connectivityChanges) rather than the
/// Connectivity object itself - a minimal, backward-compatible change
/// (both params are optional and default to wrapping a real
/// Connectivity(), so the app's one real call site in
/// child_home_screen.dart needed no change at all).
///
/// The class doc comment explains WHY this exists: cloud_firestore's
/// set()/update() hangs forever offline instead of throwing
/// (flutterfire#17643), so the app needs its own honest online/offline
/// signal. These tests cover the two behaviors that actually matter for
/// that: correctly collapsing a List<ConnectivityResult> (a device can
/// have more than one active connection type) down to a single bool, and
/// the transition-only dedup logic in onlineStatusChanges.
void main() {
  group('SyncStatusService.isOnline', () {
    test('true when checkConnectivity reports any real connection', () async {
      final service = SyncStatusService(
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      expect(await service.isOnline(), isTrue);
    });

    test('false when checkConnectivity reports only "none"', () async {
      final service = SyncStatusService(
        checkConnectivity: () async => [ConnectivityResult.none],
      );
      expect(await service.isOnline(), isFalse);
    });

    test(
      'true when the result list has multiple entries and at least one is '
      'real (a device can have more than one active connection type)',
      () async {
        final service = SyncStatusService(
          checkConnectivity: () async =>
              [ConnectivityResult.none, ConnectivityResult.mobile],
        );
        expect(await service.isOnline(), isTrue);
      },
    );

    test('false when the result list is empty', () async {
      final service = SyncStatusService(checkConnectivity: () async => []);
      expect(await service.isOnline(), isFalse);
    });
  });

  group('SyncStatusService.onlineStatusChanges', () {
    test(
      'emits only on real online<->offline transitions, not on every '
      'connectivity-type change while already online',
      () async {
        final controller = StreamController<List<ConnectivityResult>>();
        final service = SyncStatusService(
          connectivityChanges: controller.stream,
        );

        final emitted = <bool>[];
        final subscription = service.onlineStatusChanges.listen(
          emitted.add,
        );

        // wifi -> online (first event, should emit true)
        controller.add([ConnectivityResult.wifi]);
        // mobile -> still online, different connection TYPE, should NOT
        // emit again (this is the exact case the class doc comment calls
        // out: "not on every connectivity type change, e.g. wifi to
        // mobile data while already online")
        controller.add([ConnectivityResult.mobile]);
        // none -> offline (a real transition, should emit false)
        controller.add([ConnectivityResult.none]);
        // none again -> still offline, should NOT emit again
        controller.add([ConnectivityResult.none]);
        // wifi -> online again (a real transition, should emit true)
        controller.add([ConnectivityResult.wifi]);

        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        await controller.close();

        expect(emitted, [true, false, true]);
      },
    );

    test(
      'a fresh subscription emits its first real status immediately, '
      'regardless of direction',
      () async {
        final controller = StreamController<List<ConnectivityResult>>();
        final service = SyncStatusService(
          connectivityChanges: controller.stream,
        );

        final emitted = <bool>[];
        final subscription = service.onlineStatusChanges.listen(
          emitted.add,
        );

        controller.add([ConnectivityResult.none]);
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        await controller.close();

        expect(emitted, [false]);
      },
    );
  });
}
