import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_rule.dart';

class AppRulesService {
  static const String _rulesKey = 'app_rules_json';
  static const String _restrictedPackagesKey = 'restricted_packages_json';

  Future<List<AppRule>> getRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rulesKey);

    if (raw == null || raw.trim().isEmpty) {
      return [];
    }

    try {
      final List decoded = jsonDecode(raw);
      return decoded
          .map((item) => AppRule.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRules(List<AppRule> rules) async {
    await saveRulesLocally(rules);
    await syncRulesToFirestore(rules);
  }

  Future<void> saveRulesLocally(List<AppRule> rules) async {
    final prefs = await SharedPreferences.getInstance();

    final encodedRules = jsonEncode(rules.map((rule) => rule.toMap()).toList());

    final restrictedPackages = rules
        .where((rule) => rule.restrictEnabled)
        .map((rule) => rule.packageName)
        .where((packageName) => packageName.trim().isNotEmpty)
        .toSet()
        .toList();

    await prefs.setString(_rulesKey, encodedRules);

    // Android native AccessibilityService reads this local key.
    // On Android, shared_preferences stores it as:
    // flutter.restricted_packages_json
    await prefs.setString(
      _restrictedPackagesKey,
      jsonEncode(restrictedPackages),
    );
  }

  Future<void> syncRulesToFirestore(List<AppRule> rules) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    final monitoredRules = rules.where((rule) => rule.monitorEnabled).toList();
    final restrictedRules = rules
        .where((rule) => rule.restrictEnabled)
        .toList();

    await FirebaseFirestore.instance.collection('app_rules').doc(user.uid).set({
      'parentId': user.uid,
      'rules': rules.map((rule) => rule.toMap()).toList(),
      'monitoredCount': monitoredRules.length,
      'restrictedCount': restrictedRules.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<AppRule>> watchRulesForParent(String parentId) {
    if (parentId.trim().isEmpty) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection('app_rules')
        .doc(parentId)
        .snapshots()
        .asyncMap((snapshot) async {
          final data = snapshot.data();

          if (data == null) {
            await saveRulesLocally([]);
            return <AppRule>[];
          }

          final rawRules = data['rules'];

          if (rawRules is! List) {
            await saveRulesLocally([]);
            return <AppRule>[];
          }

          try {
            final rules = rawRules
                .map((item) => AppRule.fromMap(Map<String, dynamic>.from(item)))
                .toList();

            // Important:
            // This saves the Firebase rules into the CHILD PHONE local storage
            // so WellScreenAccessibilityService can block restricted packages.
            await saveRulesLocally(rules);

            return rules;
          } catch (_) {
            await saveRulesLocally([]);
            return <AppRule>[];
          }
        });
  }

  Future<void> upsertRule(AppRule rule) async {
    final rules = await getRules();

    final index = rules.indexWhere(
      (item) => item.packageName == rule.packageName,
    );

    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }

    await saveRules(rules);
  }

  Future<void> removeRule(String packageName) async {
    final rules = await getRules();

    rules.removeWhere((rule) => rule.packageName == packageName);

    await saveRules(rules);
  }

  Future<void> clearRules() async {
    await saveRulesLocally([]);

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    await FirebaseFirestore.instance.collection('app_rules').doc(user.uid).set({
      'parentId': user.uid,
      'rules': [],
      'monitoredCount': 0,
      'restrictedCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
