import 'dart:convert';

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
    final prefs = await SharedPreferences.getInstance();

    final encodedRules = jsonEncode(
      rules.map((rule) => rule.toMap()).toList(),
    );

    final restrictedPackages = rules
        .where((rule) => rule.restrictEnabled)
        .map((rule) => rule.packageName)
        .toList();

    await prefs.setString(_rulesKey, encodedRules);

    // Android native AccessibilityService will read this key.
    await prefs.setString(
      _restrictedPackagesKey,
      jsonEncode(restrictedPackages),
    );
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rulesKey);
    await prefs.remove(_restrictedPackagesKey);
  }
}