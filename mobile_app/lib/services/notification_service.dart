import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  StreamSubscription<String>? _tokenRefreshSubscription;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    await requestNotificationPermission();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    _isInitialized = true;
  }

  Future<void> initializeForCurrentUser({
    required String contextLabel,
  }) async {
    await initialize();
    await saveCurrentUserToken(contextLabel: contextLabel);
  }

  Future<void> requestNotificationPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    } catch (_) {
      // Notification permission errors should not stop the app.
    }
  }

  Future<void> saveCurrentUserToken({
    required String contextLabel,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null || token.trim().isEmpty) {
        return;
      }

      await _saveToken(
        user: user,
        token: token,
        contextLabel: contextLabel,
      );

      _tokenRefreshSubscription ??=
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final refreshedUser = FirebaseAuth.instance.currentUser;

        if (refreshedUser == null) {
          return;
        }

        unawaited(
          _saveToken(
            user: refreshedUser,
            token: newToken,
            contextLabel: 'token_refresh',
          ),
        );
      });
    } catch (_) {
      // Token saving is best-effort and should not block the app.
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> createInAppAlert({
    required String recipientUserId,
    required String title,
    required String message,
    required String triggerType,
    String? parentId,
    String? childId,
    String priority = 'medium',
    Map<String, dynamic> extraData = const {},
  }) async {
    return FirebaseFirestore.instance.collection('in_app_alerts').add({
      'recipientUserId': recipientUserId,
      'parentId': parentId,
      'childId': childId,
      'title': title,
      'message': message,
      'triggerType': triggerType,
      'priority': priority,
      'isRead': false,
      'source': 'wellscreen_app',
      'extraData': extraData,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    // System-level local notifications are intentionally not used here
    // to avoid version-specific plugin constructor issues.
    // Rule-trigger alerts are stored as in-app alerts instead.
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title'] as String? ??
        'WellScreen Alert';

    final body = message.notification?.body ??
        message.data['body'] as String? ??
        'A WellScreen notification was received.';

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    await createInAppAlert(
      recipientUserId: user.uid,
      parentId: message.data['parentId'] as String?,
      childId: message.data['childId'] as String?,
      title: title,
      message: body,
      triggerType: message.data['triggerType'] as String? ?? 'fcm_message',
      priority: message.data['priority'] as String? ?? 'medium',
      extraData: Map<String, dynamic>.from(message.data),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    unawaited(
      createInAppAlert(
        recipientUserId: user.uid,
        parentId: message.data['parentId'] as String?,
        childId: message.data['childId'] as String?,
        title: message.notification?.title ?? 'WellScreen Alert Opened',
        message: message.notification?.body ??
            'A WellScreen push notification was opened.',
        triggerType: 'fcm_opened',
        priority: message.data['priority'] as String? ?? 'medium',
        extraData: Map<String, dynamic>.from(message.data),
      ),
    );
  }

  Future<void> _saveToken({
    required User user,
    required String token,
    required String contextLabel,
  }) async {
    final safeTokenId = _tokenToDocumentId(token);

    final data = {
      'uid': user.uid,
      'email': user.email,
      'token': token,
      'platform': 'android',
      'contextLabel': contextLabel,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();

    final userTokenRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notification_tokens')
        .doc(safeTokenId);

    final globalTokenRef =
        FirebaseFirestore.instance.collection('notification_tokens').doc(
              safeTokenId,
            );

    batch.set(userTokenRef, data, SetOptions(merge: true));
    batch.set(globalTokenRef, data, SetOptions(merge: true));

    await batch.commit();
  }

  String _tokenToDocumentId(String token) {
    return token.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    await NotificationService.instance.createInAppAlert(
      recipientUserId: user.uid,
      parentId: message.data['parentId'] as String?,
      childId: message.data['childId'] as String?,
      title: message.notification?.title ?? 'WellScreen Alert',
      message: message.notification?.body ??
          'A WellScreen background notification was received.',
      triggerType: message.data['triggerType'] as String? ?? 'fcm_background',
      priority: message.data['priority'] as String? ?? 'medium',
      extraData: Map<String, dynamic>.from(message.data),
    );
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
