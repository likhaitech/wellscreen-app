import 'package:dio/dio.dart';

/// Turns a raw GPS fix (latitude/longitude) into a human-readable place name
/// for the parent-facing GPS Map screen - previously that screen only ever
/// showed the raw coordinate pair (see gps_map_screen.dart's old
/// "Location Label" card, which just re-formatted latitude/longitude as
/// text; child_home_screen.dart's _writeSharedLocation never wrote a real
/// 'label' field, so there was never an address to show even though
/// locationText() in parent_dashboard_screen.dart already had a code path
/// that preferred one).
///
/// Uses OpenStreetMap's Nominatim reverse-geocoding endpoint - free, no API
/// key required, and consistent with the OSM tiles gps_map_screen.dart
/// already renders via flutter_map. This intentionally does NOT touch the
/// Firestore write path (child_home_screen.dart) or the security rules -
/// the resolution happens read-side, on the parent's device, from the
/// latitude/longitude the child already shares today. That keeps this
/// change isolated from the pairing/sync work that's still being verified
/// for the demo.
///
/// Nominatim's usage policy (https://operations.osmfoundation.org/policies/nominatim/)
/// caps free usage at ~1 request/second and requires a real identifying
/// User-Agent - both are honored below. For anything beyond demo/capstone
/// scale this should move to a paid geocoding provider or a self-hosted
/// Nominatim instance instead of the public endpoint.
class LocationGeocodingService {
  LocationGeocodingService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {
                  // Required by Nominatim's usage policy - identifies the
                  // calling application rather than looking like a generic
                  // bot/scraper request.
                  'User-Agent': 'WellScreenApp/1.0 (capstone project)',
                },
              ),
            );

  final Dio _dio;

  static const String _baseUrl = 'https://nominatim.openstreetmap.org/reverse';

  /// Returns a short, human-readable place name (e.g. "Lahug, Cebu City,
  /// Cebu") for the given coordinates, or null if the lookup fails or
  /// returns nothing usable. Callers should fall back to showing the raw
  /// coordinates on null - this must never throw for network/timeout
  /// failures, since a flaky reverse-geocode call should not block the
  /// parent from seeing the map itself.
  Future<String?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _baseUrl,
        queryParameters: {
          'format': 'jsonv2',
          'lat': latitude,
          'lon': longitude,
          'zoom': 16,
          'addressdetails': 1,
        },
      );

      final data = response.data;
      if (data == null) return null;

      final placeName = _buildShortPlaceName(data);
      if (placeName != null && placeName.isNotEmpty) {
        return placeName;
      }

      final displayName = data['display_name'];
      if (displayName is String && displayName.isNotEmpty) {
        return displayName;
      }

      return null;
    } catch (_) {
      // Network error, timeout, rate-limited, or malformed response - the
      // caller falls back to the raw coordinate label. No error is
      // surfaced here since a failed address lookup shouldn't read as a
      // failed location share to the parent.
      return null;
    }
  }

  /// Prefers a short "street/area, city, region" form over Nominatim's
  /// often very long display_name (which can include postcode, country,
  /// etc.) - closer to what a parent actually wants at a glance.
  String? _buildShortPlaceName(Map<String, dynamic> data) {
    final address = data['address'];
    if (address is! Map) return null;

    final street = address['road'] ?? address['pedestrian'];
    final area = address['neighbourhood'] ??
        address['suburb'] ??
        address['village'];
    final city = address['city'] ?? address['town'] ?? address['municipality'];
    final region = address['state'] ?? address['region'];

    final parts = <String>[];
    if (street is String && street.isNotEmpty) parts.add(street);
    if (area is String && area.isNotEmpty && area != street) parts.add(area);
    if (city is String && city.isNotEmpty) parts.add(city);
    if (parts.isEmpty && region is String && region.isNotEmpty) {
      parts.add(region);
    }

    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}
