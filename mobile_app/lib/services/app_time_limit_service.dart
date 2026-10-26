import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_time_limit.dart';

/// Parent-side editing and child-side local mirroring of per-app allowances.
///
/// The native WellScreenAccessibilityService enforces this service's local
/// cache while Accessibility and Usage Access permissions remain enabled.
/// Do NOT add time-limited packages to `restricted_packages_json`: that key
/// represents permanent restrictions, not daily time allowances.
class AppTimeLimitService {
  static const String nativeCacheKey = 'app_time_limits_json';

  CollectionReference<Map<String, dynamic>> _limitsCollection(String childId) {
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child profile required');
    }
    return FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childId)
        .collection('app_time_limits');
  }

  Future<int?> readLimitMinutes({
    required String childProfileId,
    required String packageName,
  }) async {
    final doc = await _limitsCollection(childProfileId).doc(packageName).get();
    final data = doc.data();
    if (data == null) return null;
    final value = data['limitMinutes'];
    if (value is! num) return null;
    final minutes = value.toInt();
    return minutes >= 1 && minutes <= 1440 ? minutes : null;
  }

  Future<void> saveLimit({
    required String childProfileId,
    required String packageName,
    required String appName,
    required int minutes,
  }) async {
    if (minutes < 1 || minutes > 1440) {
      throw ArgumentError.value(minutes, 'minutes', 'Must be 1–1440');
    }
    if (packageName.trim().isEmpty || packageName.contains('/')) {
      throw ArgumentError.value(packageName, 'packageName', 'Invalid package');
    }

    final guardian = FirebaseAuth.instance.currentUser;
    if (guardian == null) throw StateError('Please sign in again.');

    // Client-side check improves clarity; Firestore Security Rules still must
    // enforce ownership. Never treat this check as authorization by itself.
    final child = await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .get();
    if (!child.exists || child.data()?['parentId'] != guardian.uid) {
      throw StateError('Only the paired guardian can edit these limits.');
    }

    await _limitsCollection(childProfileId).doc(packageName).set({
      'packageName': packageName,
      'appName': appName,
      'limitMinutes': minutes,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeLimit({
    required String childProfileId,
    required String packageName,
  }) async {
    final guardian = FirebaseAuth.instance.currentUser;
    if (guardian == null) throw StateError('Please sign in again.');
    final child = await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .get();
    if (!child.exists || child.data()?['parentId'] != guardian.uid) {
      throw StateError('Only the paired guardian can edit these limits.');
    }
    await _limitsCollection(childProfileId).doc(packageName).delete();
  }

  Stream<List<AppTimeLimit>> watchLimits(String childProfileId) {
    if (childProfileId.trim().isEmpty) {
      return Stream<List<AppTimeLimit>>.value(<AppTimeLimit>[]);
    }
    return _limitsCollection(childProfileId).snapshots().map(_decodeSnapshot);
  }

  /// Child-only stream: stores the latest rules for native Android enforcement.
  /// Cache is tagged with the specific child profile to avoid
  /// accidentally applying another child's limits after account switching.
  Stream<List<AppTimeLimit>> watchForChildAndCache(String childProfileId) {
    return watchLimits(childProfileId).asyncMap((limits) async {
      final prefs = await SharedPreferences.getInstance();
      // Write the envelope first; only publish the active profile ID when
      // the complete new cache is ready for the Android AccessibilityService.
      await prefs.setString(
        nativeCacheKey,
        jsonEncode({
          'childProfileId': childProfileId,
          'limits': limits.map((limit) => limit.toMap()).toList(),
        }),
      );
      await prefs.setString('active_child_profile_id', childProfileId);
      return limits;
    });
  }

  /// Keep an offline cache for the SAME paired child when the screen
  /// restarts. Clear it only if the account/pairing actually changed.
  Future<void> prepareCacheForChild(String childProfileId) async {
    if (childProfileId.trim().isEmpty) {
      await clearCachedLimits();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('active_child_profile_id') != childProfileId) {
      await clearCachedLimits();
    }
  }

  Future<void> clearCachedLimits() async {
    final prefs = await SharedPreferences.getInstance();
    // Revoke the native guard before removing the cached rules, so a later
    // parent login on the same handset cannot inherit a child's app limits.
    await prefs.remove('active_child_profile_id');
    await prefs.remove(nativeCacheKey);
  }

  static List<AppTimeLimit> _decodeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final limits = <AppTimeLimit>[];
    for (final document in snapshot.docs) {
      try {
        limits.add(AppTimeLimit.fromMap(document.data()));
      } on FormatException {
        // Invalid records aren't enforced. Report through monitoring if
        // needed; never silently treat an invalid limit as zero minutes.
      }
    }
    return limits;
  }
}
