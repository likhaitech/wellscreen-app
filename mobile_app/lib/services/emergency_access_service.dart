import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_notification_client.dart';

/// Child-requests-temporary-bypass Emergency Access workflow.
///
/// The parent-side on/off switch for this feature already existed before
/// this file (see rule_settings_screen.dart's `emergencyAccess` and
/// admin_settings_screen.dart's `emergencyAccessEnabled`) but nothing acted
/// on it - it was a setting that saved to Firestore and did nothing else.
/// This is the actual workflow: a child on a restricted app can ask for a
/// temporary lift, the parent gets notified the same way a restricted-app
/// block does (AlertNotificationClient, same as SMS/push alerts) and can
/// approve or deny it from their dashboard, and an approval is honored on
/// the child device by WellScreenAccessibilityService.kt checking a
/// granted-until timestamp before blocking anything - not just a Firestore
/// flag that only the Flutter UI happens to read.
///
/// State lives on `child_profiles/{childProfileId}.emergencyAccess`:
///   status: 'none' | 'requested' | 'approved' | 'denied'
///   reason: guardian-readable text the child typed, may be empty
///   requestedAt / respondedAt: server timestamps
///   grantedUntil: server timestamp the bypass expires at (approved only)
class EmergencyAccessService {
  static const String _grantedUntilKey = 'emergency_access_granted_until_ms';

  static const Duration defaultGrantDuration = Duration(minutes: 30);

  /// Child side: submits a request and best-effort notifies the parent.
  /// The Firestore write is what actually creates the pending request -
  /// the push notification is a convenience on top, same tradeoff
  /// AlertNotificationClient already documents for every other alert type.
  Future<void> requestAccess({
    required String childProfileId,
    required String parentId,
    String reason = '',
  }) async {
    if (childProfileId.isEmpty) {
      throw StateError('Not paired with a parent yet.');
    }

    final trimmedReason = reason.trim();

    await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .set({
          'emergencyAccess': {
            'status': 'requested',
            'reason': trimmedReason,
            'requestedAt': FieldValue.serverTimestamp(),
            'respondedAt': null,
            'grantedUntil': null,
          },
        }, SetOptions(merge: true));

    if (parentId.isEmpty) return;

    try {
      await AlertNotificationClient().notifyParent(
        parentUid: parentId,
        title: 'Emergency access requested',
        body: trimmedReason.isEmpty
            ? 'Your child is requesting temporary emergency access.'
            : 'Your child is requesting temporary emergency access: '
                  '$trimmedReason',
        alertType: 'emergency_access_request',
        childProfileId: childProfileId,
      );
    } catch (_) {
      // Firestore write above already went through - the parent still sees
      // the pending request live on their dashboard even if this push
      // notification itself fails (e.g. backend not deployed, no fcmToken
      // yet). Same best-effort tradeoff AlertNotificationClient documents.
    }
  }

  /// Parent side: approves (for [duration], default 30 minutes) or denies
  /// the currently pending request for this child.
  Future<void> respondToRequest({
    required String childProfileId,
    required bool approve,
    Duration duration = defaultGrantDuration,
  }) async {
    if (childProfileId.isEmpty) return;

    final grantedUntil = approve
        ? Timestamp.fromDate(DateTime.now().add(duration))
        : null;

    await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .set({
          'emergencyAccess': {
            'status': approve ? 'approved' : 'denied',
            'respondedAt': FieldValue.serverTimestamp(),
            'grantedUntil': grantedUntil,
          },
        }, SetOptions(merge: true));
  }

  /// Child side: live status for this child's own profile, and - as a
  /// side effect of each update - keeps the native side's local bypass
  /// flag in sync with whatever `grantedUntil` Firestore currently has.
  /// Mirrors AppRulesService.watchRulesForParent's "stream from Firestore,
  /// mirror into SharedPreferences for the native service" pattern.
  Stream<Map<String, dynamic>> watchStatus(String childProfileId) {
    if (childProfileId.isEmpty) return Stream.value(const {});

    return FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .snapshots()
        .asyncMap((snapshot) async {
          final raw = snapshot.data()?['emergencyAccess'];
          final status = raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};

          final grantedUntil = status['grantedUntil'];
          await syncGrantedUntilLocally(
            grantedUntil is Timestamp ? grantedUntil.toDate() : null,
          );

          return status;
        });
  }

  /// Writes (or clears) the local bypass-expiry flag that
  /// WellScreenAccessibilityService.kt reads before blocking a restricted
  /// app. Public (not just called from [watchStatus]) so a caller that
  /// already has the child profile data in hand (e.g. right after
  /// [respondToRequest] on a device that's somehow also the child device)
  /// can sync it without waiting for the next stream tick.
  Future<void> syncGrantedUntilLocally(DateTime? grantedUntil) async {
    final prefs = await SharedPreferences.getInstance();

    if (grantedUntil == null || grantedUntil.isBefore(DateTime.now())) {
      await prefs.remove(_grantedUntilKey);
      return;
    }

    // Android native AccessibilityService reads this local key.
    // On Android, shared_preferences stores it as:
    // flutter.emergency_access_granted_until_ms
    await prefs.setInt(
      _grantedUntilKey,
      grantedUntil.millisecondsSinceEpoch,
    );
  }
}
