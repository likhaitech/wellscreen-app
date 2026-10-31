import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches the child's authoritative daily limits from Firestore and writes
/// the same Android SharedPreferences cache used by AppTimeLimitEnforcer.
///
/// Can run in a Firebase Messaging background isolate: no BuildContext,
/// widget tree, Activity, or MainActivity MethodChannel is required.
class AppTimeLimitBackgroundSync {
  AppTimeLimitBackgroundSync._();

  static const String _activeProfileKey = 'active_child_profile_id';
  static const String _limitsCacheKey = 'app_time_limits_json';

  static Future<bool> refreshForChild(String childProfileId) async {
    if (childProfileId.isEmpty) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('App limit background sync skipped: no signed-in user');
      return false;
    }
    final uid = user.uid;

    try {
      final prefs = await SharedPreferences.getInstance();
      // The background handler and foreground Flutter UI can have separate
      // SharedPreferences caches; reload to see cross-isolate changes.
      await prefs.reload();
      final activeProfile = prefs.getString(_activeProfileKey);
      if (activeProfile != null && activeProfile != childProfileId) {
        debugPrint('App limit background sync skipped: profile mismatch');
        return false;
      }

      const server = GetOptions(source: Source.server);
      final firestore = FirebaseFirestore.instance;
      // Never authorize a cache write using the FCM payload alone. Only the
      // signed-in paired child can read this Firestore document under rules.
      final profile = await firestore
          .collection('child_profiles')
          .doc(childProfileId)
          .get(server)
          .timeout(const Duration(seconds: 20));
      final profileData = profile.data();
      if (profileData == null ||
          profileData['childAccountId'] != uid ||
          profileData['pairingStatus'] != 'connected') {
        debugPrint('App limit background sync skipped: invalid child pairing');
        return false;
      }

      // Read the entire current collection, rather than trusting a limit
      // value sent in FCM. This also handles changes to multiple packages.
      final snapshot = await firestore
          .collection('child_profiles')
          .doc(childProfileId)
          .collection('app_time_limits')
          .get(server)
          .timeout(const Duration(seconds: 20));

      final limits = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final packageName = data['packageName'];
        final appName = data['appName'];
        final minutes = data['limitMinutes'];
        if (packageName is! String ||
            packageName != doc.id ||
            appName is! String ||
            appName.trim().isEmpty ||
            minutes is! int ||
            minutes < 1 ||
            minutes > 1440) {
          continue;
        }
        limits.add({
          'packageName': packageName,
          'appName': appName,
          'limitMinutes': minutes,
        });
      }

      // A sign-out or child-account switch could have happened during reads.
      // Do not restore another child's restrictions after that transition.
      if (FirebaseAuth.instance.currentUser?.uid != uid) return false;
      await prefs.reload();
      final activeAtWrite = prefs.getString(_activeProfileKey);
      if (activeAtWrite != null && activeAtWrite != childProfileId) {
        return false;
      }

      // This JSON shape is consumed by AppTimeLimitEnforcer.getStatus().
      await prefs.setString(
        _limitsCacheKey,
        jsonEncode({'childProfileId': childProfileId, 'limits': limits}),
      );
      // A fresh login may not have opened ChildHomeScreen yet. The profile
      // was verified from Firestore, so initialize the native profile key.
      await prefs.setString(_activeProfileKey, childProfileId);

      debugPrint('Background app limits synchronized (${limits.length} apps)');
      return true;
    } catch (error) {
      // Offline/permission failures must not erase a previously valid cache.
      debugPrint('App limit background sync failed: $error');
      return false;
    }
  }
}
