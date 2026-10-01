import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/emergency_access_service.dart';

/// Covers EmergencyAccessService.syncGrantedUntilLocally - the one piece of
/// this service that doesn't require a live Firestore document
/// (requestAccess/respondToRequest/watchStatus all read or write
/// `child_profiles/{id}` directly via FirebaseFirestore.instance, and this
/// codebase doesn't fake Firestore - see report_export_service_test.dart's
/// doc comment for the same reasoning). syncGrantedUntilLocally is exactly
/// the kind of pure-enough, SharedPreferences-backed logic
/// daily_screen_time_limit_service_test.dart already established a mocking
/// pattern for (SharedPreferences.setMockInitialValues), so the same
/// pattern is used here.
///
/// This is the logic WellScreenAccessibilityService.kt on the native side
/// actually trusts to decide whether a restricted-app block should be
/// bypassed right now - a bug here either fails to honor a parent's
/// approval (child stays blocked despite being granted access) or worse,
/// keeps an expired bypass active (child stays unblocked past the granted
/// window), so it's worth covering precisely even though it's a small
/// method.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmergencyAccessService.syncGrantedUntilLocally', () {
    const key = 'emergency_access_granted_until_ms';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('a null grantedUntil clears any existing local flag', () async {
      SharedPreferences.setMockInitialValues({
        key: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
      });
      final service = EmergencyAccessService();

      await service.syncGrantedUntilLocally(null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(key), isNull);
    });

    test(
      'a future grantedUntil is stored as epoch milliseconds',
      () async {
        final service = EmergencyAccessService();
        final grantedUntil = DateTime.now().add(
          const Duration(minutes: 30),
        );

        await service.syncGrantedUntilLocally(grantedUntil);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(key), grantedUntil.millisecondsSinceEpoch);
      },
    );

    test(
      'a grantedUntil already in the past clears the flag rather than '
      'storing a stale expiry',
      () async {
        SharedPreferences.setMockInitialValues({
          key: DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        });
        final service = EmergencyAccessService();
        final expired = DateTime.now().subtract(
          const Duration(minutes: 1),
        );

        await service.syncGrantedUntilLocally(expired);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(key), isNull);
      },
    );

    test(
      'overwrites a previously stored value with a new future expiry',
      () async {
        final service = EmergencyAccessService();

        await service.syncGrantedUntilLocally(
          DateTime.now().add(const Duration(minutes: 5)),
        );
        final secondGrant = DateTime.now().add(const Duration(minutes: 45));
        await service.syncGrantedUntilLocally(secondGrant);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(key), secondGrant.millisecondsSinceEpoch);
      },
    );
  });
}
