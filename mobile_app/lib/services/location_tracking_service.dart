import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

extension LocationPermissionStatusLabel on LocationPermissionStatus {
  String get label {
    switch (this) {
      case LocationPermissionStatus.granted:
        return 'Granted';
      case LocationPermissionStatus.denied:
        return 'Denied';
      case LocationPermissionStatus.deniedForever:
        return 'Denied Forever';
      case LocationPermissionStatus.serviceDisabled:
        return 'Location Service Disabled';
    }
  }
}

class LocationCaptureResult {
  const LocationCaptureResult({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.geoFenceStatus,
    required this.isOutsideSafeZone,
    required this.safeZoneConfigured,
    required this.distanceFromSafeZoneMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final String geoFenceStatus;
  final bool isOutsideSafeZone;
  final bool safeZoneConfigured;
  final double? distanceFromSafeZoneMeters;

  String get coordinateLabel {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  String get accuracyLabel {
    return '${accuracyMeters.toStringAsFixed(0)}m accuracy';
  }

  String get capturedAtLabel {
    final hour = capturedAt.hour > 12
        ? capturedAt.hour - 12
        : capturedAt.hour == 0
            ? 12
            : capturedAt.hour;
    final minute = capturedAt.minute.toString().padLeft(2, '0');
    final period = capturedAt.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  String get geoFenceLabel {
    if (!safeZoneConfigured) {
      return 'Safe zone baseline was created from the first captured location.';
    }

    if (isOutsideSafeZone) {
      final distance = distanceFromSafeZoneMeters == null
          ? 'unknown distance'
          : '${distanceFromSafeZoneMeters!.toStringAsFixed(0)}m away';

      return 'Outside safe zone - $distance';
    }

    return 'Inside safe zone';
  }
}

class LocationTrackingService {
  LocationTrackingService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  static const double defaultSafeZoneRadiusMeters = 500;
  static const int geoFenceAlertDebounceMinutes = 10;

  Future<LocationPermissionStatus> checkPermissionStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    final permission = await Geolocator.checkPermission();

    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.denied;
    }
  }

  Future<LocationPermissionStatus> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    final permission = await Geolocator.requestPermission();

    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.denied:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.denied;
    }
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<LocationCaptureResult> captureAndSyncCurrentLocation() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('Please log in again before syncing location.');
    }

    final permissionStatus = await checkPermissionStatus();

    if (permissionStatus != LocationPermissionStatus.granted) {
      throw Exception(
        'Location permission is required before syncing GPS location.',
      );
    }

    final childDeviceSnapshot =
        await _firestore.collection('child_devices').doc(user.uid).get();

    final childDeviceData = childDeviceSnapshot.data();

    if (childDeviceData == null) {
      throw Exception('Pair this child device before syncing GPS location.');
    }

    final parentId = childDeviceData['parentId'] as String?;
    final childId = childDeviceData['childId'] as String?;

    if (parentId == null || parentId.isEmpty) {
      throw Exception('Parent account reference is missing.');
    }

    if (childId == null || childId.isEmpty) {
      throw Exception('Child profile reference is missing.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    final capturedAt = DateTime.now();

    final geoFenceSettings = await _loadOrCreateGeoFenceSettings(
      parentId: parentId,
      latitude: position.latitude,
      longitude: position.longitude,
    );

    final geoFenceResult = _evaluateGeoFence(
      latitude: position.latitude,
      longitude: position.longitude,
      settings: geoFenceSettings,
    );

    final result = LocationCaptureResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      capturedAt: capturedAt,
      geoFenceStatus: geoFenceResult.status,
      isOutsideSafeZone: geoFenceResult.isOutsideSafeZone,
      safeZoneConfigured: geoFenceSettings.isConfigured,
      distanceFromSafeZoneMeters: geoFenceResult.distanceFromSafeZoneMeters,
    );

    final latestLocationRef =
        _firestore.collection('child_locations').doc(user.uid);

    final historyRef = latestLocationRef
        .collection('history')
        .doc(capturedAt.millisecondsSinceEpoch.toString());

    final latestBeforeUpdate = await latestLocationRef.get();

    final locationData = {
      'parentId': parentId,
      'childId': childId,
      'childUserId': user.uid,
      'childEmail': user.email,
      'childLabel':
          childDeviceData['childEmail'] as String? ?? user.email ?? 'Child',
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracyMeters': position.accuracy,
      'altitudeMeters': position.altitude,
      'speedMetersPerSecond': position.speed,
      'headingDegrees': position.heading,
      'geoFenceStatus': geoFenceResult.status,
      'isOutsideSafeZone': geoFenceResult.isOutsideSafeZone,
      'safeZoneConfigured': geoFenceSettings.isConfigured,
      'safeZoneLatitude': geoFenceSettings.latitude,
      'safeZoneLongitude': geoFenceSettings.longitude,
      'safeZoneRadiusMeters': geoFenceSettings.radiusMeters,
      'distanceFromSafeZoneMeters': geoFenceResult.distanceFromSafeZoneMeters,
      'capturedAt': Timestamp.fromDate(capturedAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();

    batch.set(latestLocationRef, locationData, SetOptions(merge: true));
    batch.set(historyRef, {
      ...locationData,
      'historyCreatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_firestore.collection('child_devices').doc(user.uid), {
      'latestLatitude': position.latitude,
      'latestLongitude': position.longitude,
      'latestLocationAt': Timestamp.fromDate(capturedAt),
      'latestGeoFenceStatus': geoFenceResult.status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_firestore.collection('child_profiles').doc(childId), {
      'latestLatitude': position.latitude,
      'latestLongitude': position.longitude,
      'latestLocationAt': Timestamp.fromDate(capturedAt),
      'latestGeoFenceStatus': geoFenceResult.status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    if (geoFenceResult.isOutsideSafeZone) {
      await _createGeoFenceAlertIfNeeded(
        parentId: parentId,
        childId: childId,
        childUserId: user.uid,
        childEmail: user.email ?? 'Child device',
        result: result,
        latestBeforeUpdate: latestBeforeUpdate,
      );
    }

    return result;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchLatestLocationsForParent(
    String parentId,
  ) {
    return _firestore
        .collection('child_locations')
        .where('parentId', isEqualTo: parentId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchLocationHistoryForChild(
    String childUserId,
  ) {
    return _firestore
        .collection('child_locations')
        .doc(childUserId)
        .collection('history')
        .limit(20)
        .snapshots();
  }

  Future<_GeoFenceSettings> _loadOrCreateGeoFenceSettings({
    required String parentId,
    required double latitude,
    required double longitude,
  }) async {
    final settingsRef = _firestore.collection('location_settings').doc(parentId);
    final snapshot = await settingsRef.get();
    final data = snapshot.data();

    final enabled = data?['geoFenceEnabled'] as bool? ?? true;
    final safeLatitude = _readDouble(data?['safeZoneLatitude']);
    final safeLongitude = _readDouble(data?['safeZoneLongitude']);
    final radiusMeters =
        _readDouble(data?['safeZoneRadiusMeters']) ??
        defaultSafeZoneRadiusMeters;

    if (safeLatitude != null && safeLongitude != null) {
      return _GeoFenceSettings(
        enabled: enabled,
        isConfigured: true,
        latitude: safeLatitude,
        longitude: safeLongitude,
        radiusMeters: radiusMeters,
      );
    }

    await settingsRef.set({
      'parentId': parentId,
      'geoFenceEnabled': true,
      'safeZoneLatitude': latitude,
      'safeZoneLongitude': longitude,
      'safeZoneRadiusMeters': defaultSafeZoneRadiusMeters,
      'configuredFrom': 'first_child_location_capture',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return _GeoFenceSettings(
      enabled: true,
      isConfigured: false,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: defaultSafeZoneRadiusMeters,
    );
  }

  _GeoFenceResult _evaluateGeoFence({
    required double latitude,
    required double longitude,
    required _GeoFenceSettings settings,
  }) {
    if (!settings.enabled) {
      return const _GeoFenceResult(
        status: 'geo_fence_disabled',
        isOutsideSafeZone: false,
        distanceFromSafeZoneMeters: null,
      );
    }

    final distance = Geolocator.distanceBetween(
      settings.latitude,
      settings.longitude,
      latitude,
      longitude,
    );

    final isOutside = distance > settings.radiusMeters;

    return _GeoFenceResult(
      status: isOutside ? 'outside_safe_zone' : 'inside_safe_zone',
      isOutsideSafeZone: isOutside,
      distanceFromSafeZoneMeters: distance,
    );
  }

  Future<void> _createGeoFenceAlertIfNeeded({
    required String parentId,
    required String childId,
    required String childUserId,
    required String childEmail,
    required LocationCaptureResult result,
    required DocumentSnapshot<Map<String, dynamic>> latestBeforeUpdate,
  }) async {
    final previousData = latestBeforeUpdate.data();
    final lastAlertAtValue = previousData?['lastGeoFenceAlertAt'];
    final lastAlertAt = lastAlertAtValue is Timestamp
        ? lastAlertAtValue.toDate()
        : null;

    if (lastAlertAt != null) {
      final minutesSinceAlert = DateTime.now().difference(lastAlertAt).inMinutes;

      if (minutesSinceAlert < geoFenceAlertDebounceMinutes) {
        return;
      }
    }

    final distanceText = result.distanceFromSafeZoneMeters == null
        ? 'outside the configured safe zone'
        : '${result.distanceFromSafeZoneMeters!.toStringAsFixed(0)} meters from the safe zone';

    await _firestore.collection('in_app_alerts').add({
      'recipientUserId': parentId,
      'parentId': parentId,
      'childId': childId,
      'childUserId': childUserId,
      'title': 'Geo-Fence Safety Alert',
      'message':
          '$childEmail appears to be $distanceText. Review the latest location update.',
      'triggerType': 'geofence_outside_safe_zone',
      'priority': 'high',
      'isRead': false,
      'source': 'location_tracking_service',
      'extraData': {
        'latitude': result.latitude,
        'longitude': result.longitude,
        'accuracyMeters': result.accuracyMeters,
        'distanceFromSafeZoneMeters': result.distanceFromSafeZoneMeters,
        'geoFenceStatus': result.geoFenceStatus,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('child_locations').doc(childUserId).set({
      'lastGeoFenceAlertAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  double? _readDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }
}

class _GeoFenceSettings {
  const _GeoFenceSettings({
    required this.enabled,
    required this.isConfigured,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final bool enabled;
  final bool isConfigured;
  final double latitude;
  final double longitude;
  final double radiusMeters;
}

class _GeoFenceResult {
  const _GeoFenceResult({
    required this.status,
    required this.isOutsideSafeZone,
    required this.distanceFromSafeZoneMeters,
  });

  final String status;
  final bool isOutsideSafeZone;
  final double? distanceFromSafeZoneMeters;
}

