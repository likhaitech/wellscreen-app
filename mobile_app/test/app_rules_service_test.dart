import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/app_rule.dart';
import 'package:app/services/app_rules_service.dart';

/// Covers the "Restriction Success or Failure" technical evaluation
/// criterion at the software layer: does WellScreen correctly compute and
/// persist which packages should be restricted, so that
/// WellScreenAccessibilityService (native Android) reads the right list?
/// Only saveRulesLocally()/getRules() are exercised here - saveRules(),
/// upsertRule(), removeRule(), and clearRules() also call
/// FirebaseAuth.instance.currentUser via syncRulesToFirestore(), which
/// requires Firebase.initializeApp() to have run and isn't set up in this
/// project's test target, so those Firestore-sync paths are intentionally
/// left for the on-device technical evaluation checklist (Appendix I)
/// rather than faked out here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppRulesService.saveRulesLocally / getRules', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trips saved rules through getRules', () async {
      final service = AppRulesService();
      final rules = [
        AppRule(
          appName: 'TikTok',
          packageName: 'com.zhiliaoapp.musically',
          monitorEnabled: true,
          restrictEnabled: true,
        ),
        AppRule(
          appName: 'Calculator',
          packageName: 'com.google.calculator',
          monitorEnabled: true,
          restrictEnabled: false,
        ),
      ];

      await service.saveRulesLocally(rules);
      final reloaded = await service.getRules();

      expect(reloaded.length, 2);
      expect(reloaded[0].packageName, 'com.zhiliaoapp.musically');
      expect(reloaded[0].restrictEnabled, true);
      expect(reloaded[1].packageName, 'com.google.calculator');
      expect(reloaded[1].restrictEnabled, false);
    });

    test('derives restricted_packages_json from only restrictEnabled rules', () async {
      final service = AppRulesService();
      final rules = [
        AppRule(
          appName: 'TikTok',
          packageName: 'com.zhiliaoapp.musically',
          monitorEnabled: true,
          restrictEnabled: true,
        ),
        AppRule(
          appName: 'YouTube',
          packageName: 'com.google.android.youtube',
          monitorEnabled: true,
          restrictEnabled: false,
        ),
        AppRule(
          appName: 'Roblox',
          packageName: 'com.roblox.client',
          monitorEnabled: false,
          restrictEnabled: true,
        ),
      ];

      await service.saveRulesLocally(rules);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('restricted_packages_json');
      expect(raw, isNotNull);

      final restricted = List<String>.from(jsonDecode(raw!));
      expect(restricted, unorderedEquals([
        'com.zhiliaoapp.musically',
        'com.roblox.client',
      ]));
      // Confirms the un-restricted rule (YouTube) never reaches the list the
      // native AccessibilityService blocks against.
      expect(restricted, isNot(contains('com.google.android.youtube')));
    });

    test('restricted package list has no duplicates even with duplicate rules', () async {
      final service = AppRulesService();
      final rules = [
        AppRule(
          appName: 'TikTok',
          packageName: 'com.zhiliaoapp.musically',
          monitorEnabled: true,
          restrictEnabled: true,
        ),
        AppRule(
          appName: 'TikTok (duplicate entry)',
          packageName: 'com.zhiliaoapp.musically',
          monitorEnabled: true,
          restrictEnabled: true,
        ),
      ];

      await service.saveRulesLocally(rules);

      final prefs = await SharedPreferences.getInstance();
      final restricted = List<String>.from(
        jsonDecode(prefs.getString('restricted_packages_json')!),
      );
      expect(restricted.length, 1);
      expect(restricted, ['com.zhiliaoapp.musically']);
    });

    test('blank/whitespace-only package names are excluded from the restricted list', () async {
      final service = AppRulesService();
      final rules = [
        AppRule(
          appName: 'Broken Rule',
          packageName: '   ',
          monitorEnabled: true,
          restrictEnabled: true,
        ),
      ];

      await service.saveRulesLocally(rules);

      final prefs = await SharedPreferences.getInstance();
      final restricted = List<String>.from(
        jsonDecode(prefs.getString('restricted_packages_json')!),
      );
      expect(restricted, isEmpty);
    });

    test('getRules returns an empty list when nothing has been saved yet', () async {
      final service = AppRulesService();
      final rules = await service.getRules();
      expect(rules, isEmpty);
    });

    test('getRules recovers to an empty list instead of throwing on corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({
        'app_rules_json': 'this is not valid json{{{',
      });
      final service = AppRulesService();

      final rules = await service.getRules();

      expect(rules, isEmpty);
    });
  });
}
