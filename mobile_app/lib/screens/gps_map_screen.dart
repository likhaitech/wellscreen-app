import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_geocoding_service.dart';
import '../theme/app_theme.dart';

class GpsMapScreen extends StatefulWidget {
  const GpsMapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final String label;
  final String updatedAt;

  @override
  State<GpsMapScreen> createState() => _GpsMapScreenState();
}

class _GpsMapScreenState extends State<GpsMapScreen> {
  static const Color purple = AppColors.primary;
  static const Color deepPurple = AppColors.primaryDark;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;

  final LocationGeocodingService _geocodingService = LocationGeocodingService();

  bool _isResolvingAddress = true;
  String? _resolvedPlaceName;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void didUpdateWidget(covariant GpsMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve if the parent re-pushes this screen for an updated GPS fix
    // (e.g. after a fresh "Share GPS" sync) rather than showing a stale
    // address for the new coordinates.
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _resolveAddress();
    }
  }

  Future<void> _resolveAddress() async {
    setState(() {
      _isResolvingAddress = true;
      _resolvedPlaceName = null;
    });

    final placeName = await _geocodingService.reverseGeocode(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );

    if (!mounted) return;

    setState(() {
      _resolvedPlaceName = placeName;
      _isResolvingAddress = false;
    });
  }

  /// The best available text for "where this pin actually is" - a real
  /// resolved street/area/city when the reverse-geocode lookup succeeds,
  /// falling back to whatever label the caller passed in (parent_dashboard_
  /// screen.dart's openGpsMap() - either the last-known raw coordinate text
  /// or the "Cebu City, Philippines preview" placeholder) if the lookup
  /// fails or is still in flight.
  String get _placeNameText {
    if (_isResolvingAddress) return 'Locating address...';
    return _resolvedPlaceName ?? widget.label;
  }

  @override
  Widget build(BuildContext context) {
    final locationPoint = LatLng(widget.latitude, widget.longitude);

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
              child: Stack(
                children: [
                  FlutterMap(
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
                  // Floating place-name caption over the map itself, so the
                  // resolved address is visible at a glance without having
                  // to scroll down to the info cards below.
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (_isResolvingAddress)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: purple,
                              ),
                            )
                          else
                            const Icon(
                              Icons.place_rounded,
                              color: purple,
                              size: 18,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _placeNameText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: darkText,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _infoCard(
            icon: Icons.place_rounded,
            iconColor: purple,
            title: 'Place Name',
            subtitle: _placeNameText,
          ),
          _infoCard(
            icon: Icons.my_location_rounded,
            iconColor: teal,
            title: 'Coordinates',
            subtitle:
                '${widget.latitude.toStringAsFixed(5)}, '
                '${widget.longitude.toStringAsFixed(5)}',
          ),
          _infoCard(
            icon: Icons.access_time_rounded,
            iconColor: Colors.orange,
            title: 'Last Updated',
            subtitle: widget.updatedAt,
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
            backgroundColor: AppColors.primaryLight,
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

  static const Color purple = AppColors.primary;

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
