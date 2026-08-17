import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level (not a class member) because firebase_messaging requires the
/// background message handler to be a top-level or static function, so the
/// OS can invoke it in a separate isolate when the app isn't running.
/// Deliberately minimal: for a "notification" message (which is what
/// notification_service.py on the backend sends), Android/iOS already show
/// the system notification themselves when the app is backgrounded or
/// terminated - this handler exists only because the plugin requires one to
/// be registered, not because it needs to do the displaying itself here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Registers the parent's device for push notifications and displays them
/// while the app is open (foreground messages don't auto-display on
/// Android/iOS - that's what flutter_local_notifications is for here).
///
/// This is the real, standard FCM pattern: get a device token, save it to
/// Firestore so the backend can look it up, and use
/// firebase_admin.messaging.send() server-side (see
/// backend/app/services/notification_service.py) to actually deliver.
/// There is no client-side way to push to a specific other device - that
/// always requires a server holding Firebase Admin credentials, which is
/// why this needs the FastAPI backend deployed (see
/// backend/DEPLOYMENT.md), not just app code.
class PushNotificationService {
  static const String _channelId = 'wellscreen_alerts';
  static const String _channelName = 'WellScreen Alerts';
  static const String _channelDescription =
      'Real-time alerts about your child\'s device activity.';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(settings: initSettings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );

    await _saveTokenToFirestore();
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => _saveTokenToFirestore(),
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  Future<void> _saveTokenToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort - the parent just won't receive push until this
      // succeeds on a later app open; nothing else depends on it.
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );

    await _localNotifications.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}
