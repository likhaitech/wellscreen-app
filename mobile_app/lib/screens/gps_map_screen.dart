import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GpsMapScreen extends StatelessWidget {
  const GpsMapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.updatedAt,
  });

  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color pageBg = Color(0xFFF3F4F6);

  final double latitude;
  final double longitude;
  final String label;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    final locationPoint = LatLng(latitude, longitude);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'GPS Map View',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: pageBg,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [purple, deepPurple],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 14,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.location_on_rounded,
                    color: purple,
                    size: 38,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Child Location',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 430,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: locationPoint,
                  initialZoom: 15.5,
                  minZoom: 5,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.wellscreen.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: locationPoint,
                        width: 72,
                        height: 72,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.redAccent,
                          size: 60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _infoCard(
            icon: Icons.place_rounded,
            iconColor: purple,
            title: 'Location Label',
            subtitle: label,
          ),
          _infoCard(
            icon: Icons.my_location_rounded,
            iconColor: teal,
            title: 'Coordinates',
            subtitle:
                '${latitude.toStringAsFixed(5)}, '
                '${longitude.toStringAsFixed(5)}',
          ),
          _infoCard(
            icon: Icons.access_time_rounded,
            iconColor: Colors.orange,
            title: 'Last Updated',
            subtitle: updatedAt,
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFF4F0FF),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GpsMapPreview extends StatelessWidget {
  const GpsMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.hasLocation,
  });

  static const Color purple = Color(0xFF5B2BBF);

  final double latitude;
  final double longitude;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final locationPoint = LatLng(latitude, longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          SizedBox(
            height: 170,
            width: double.infinity,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: locationPoint,
                initialZoom: hasLocation ? 15 : 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.wellscreen.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: locationPoint,
                      width: 64,
                      height: 64,
                      child: Icon(
                        hasLocation
                            ? Icons.location_pin
                            : Icons.location_searching_rounded,
                        color: hasLocation ? Colors.redAccent : purple,
                        size: hasLocation ? 54 : 42,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                hasLocation ? 'Shared GPS' : 'Cebu Preview',
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
