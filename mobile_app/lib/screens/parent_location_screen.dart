import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ParentLocationScreen extends StatefulWidget {
  const ParentLocationScreen({super.key});

  @override
  State<ParentLocationScreen> createState() => _ParentLocationScreenState();
}

class _ParentLocationScreenState extends State<ParentLocationScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

  final MapController _mapController = MapController();

  void _recenter({required double latitude, required double longitude}) {
    _mapController.move(LatLng(latitude, longitude), 16);
  }

  double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Time not available';
    }

    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    final hour = value.hour > 12
        ? value.hour - 12
        : value.hour == 0
        ? 12
        : value.hour;

    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';

    return '$year-$month-$day $hour:$minute:$second $period';
  }

  String _formatRelativeTime(DateTime? value) {
    if (value == null) {
      return 'Unknown';
    }

    final difference = DateTime.now().difference(value);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }

    return '${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        title: const Text(
          'Child Location',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: user == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Please log in again to view your child\'s location.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('child_locations')
                  .where('parentId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load child location.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = [...?snapshot.data?.docs];

                if (docs.isEmpty) {
                  return const _EmptyLocationState();
                }

                docs.sort((a, b) {
                  final aTime = a.data()['capturedAt'];
                  final bTime = b.data()['capturedAt'];

                  if (aTime is Timestamp && bTime is Timestamp) {
                    return bTime.compareTo(aTime);
                  }

                  return 0;
                });

                final data = docs.first.data();

                final latitude = _readDouble(data['latitude']);
                final longitude = _readDouble(data['longitude']);
                final accuracy = _readDouble(data['accuracyMeters']);

                if (latitude == null || longitude == null) {
                  return const _EmptyLocationState(
                    message:
                        'The latest synchronized location does not contain valid coordinates.',
                  );
                }

                final childLabel =
                    data['childLabel'] as String? ??
                    data['childEmail'] as String? ??
                    'Child';

                final isOutsideSafeZone =
                    data['isOutsideSafeZone'] as bool? ?? false;

                final distanceFromSafeZone = _readDouble(
                  data['distanceFromSafeZoneMeters'],
                );

                final capturedAtValue = data['capturedAt'];
                final capturedAt = capturedAtValue is Timestamp
                    ? capturedAtValue.toDate()
                    : null;

                final childPoint = LatLng(latitude, longitude);

                return Column(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: childPoint,
                              initialZoom: 16,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.wellscreen.app',
                              ),
                              if (accuracy != null && accuracy > 0)
                                CircleLayer(
                                  circles: [
                                    CircleMarker(
                                      point: childPoint,
                                      radius: accuracy,
                                      useRadiusInMeter: true,
                                      color: purple.withAlpha(30),
                                      borderColor: purple.withAlpha(130),
                                      borderStrokeWidth: 1.5,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: childPoint,
                                    width: 72,
                                    height: 72,
                                    child: const _ChildLocationMarker(),
                                  ),
                                ],
                              ),
                              const RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution(
                                    'OpenStreetMap contributors',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 14,
                            right: 14,
                            child: Material(
                              elevation: 3,
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: IconButton(
                                tooltip: 'Recenter on child',
                                onPressed: () {
                                  _recenter(
                                    latitude: latitude,
                                    longitude: longitude,
                                  );
                                },
                                icon: const Icon(
                                  Icons.my_location_rounded,
                                  color: purple,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: softPurple,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: purple,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        childLabel,
                                        style: const TextStyle(
                                          color: darkText,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        'Latest synchronized GPS location',
                                        style: TextStyle(
                                          color: grayText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _LocationStatusPill(
                                  label: isOutsideSafeZone
                                      ? 'Outside Safe Zone'
                                      : 'Inside Safe Zone',
                                  color: isOutsideSafeZone
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _LocationDetailRow(
                              icon: Icons.schedule_rounded,
                              label: 'Last updated',
                              value:
                                  '${_formatRelativeTime(capturedAt)}\n${_formatDateTime(capturedAt)}',
                            ),
                            _LocationDetailRow(
                              icon: Icons.gps_fixed_rounded,
                              label: 'Accuracy',
                              value: accuracy == null
                                  ? 'Unknown'
                                  : '±${accuracy.toStringAsFixed(0)} m',
                            ),
                            _LocationDetailRow(
                              icon: Icons.pin_drop_outlined,
                              label: 'Coordinates',
                              value:
                                  '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                            ),
                            _LocationDetailRow(
                              icon: Icons.shield_outlined,
                              label: 'Safe zone',
                              value: isOutsideSafeZone
                                  ? 'Outside'
                                        '${distanceFromSafeZone == null ? '' : ' by ${distanceFromSafeZone.toStringAsFixed(0)} m'}'
                                  : 'Inside',
                              isLast: true,
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: const Text(
                                'This map shows the child\'s latest synchronized GPS location. '
                                'It is not continuous live tracking yet.',
                                style: TextStyle(
                                  color: grayText,
                                  height: 1.4,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ChildLocationMarker extends StatelessWidget {
  const _ChildLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF5B2BBF).withAlpha(38),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF5B2BBF),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.person_pin_circle_rounded,
            color: Colors.white,
            size: 25,
          ),
        ),
      ],
    );
  }
}

class _LocationDetailRow extends StatelessWidget {
  const _LocationDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF5B2BBF)),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationStatusPill extends StatelessWidget {
  const _LocationStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyLocationState extends StatelessWidget {
  const _EmptyLocationState({
    this.message =
        'No GPS location has been synchronized yet. Ask the child device to allow location access and tap Sync Current Location.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off_rounded,
              size: 64,
              color: Color(0xFF5B2BBF),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Location Available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF4B5563), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
