import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/location_geocoding_service.dart';

/// Covers the software half of the "GPS Location Update Accuracy"
/// technical evaluation criterion: given a raw lat/lng, does WellScreen
/// correctly turn Nominatim's reverse-geocoding response into the short
/// place label shown on the parent's GPS Map screen, and does it degrade
/// safely (return null, never throw) when the network call fails? The
/// accuracy of the underlying GPS fix itself is hardware-dependent and is
/// left to the on-device technical evaluation checklist (Appendix I).
///
/// No real HTTP call is made: an interceptor resolves/rejects the request
/// before it reaches the network, so this only exercises
/// LocationGeocodingService's own parsing/fallback logic.
Dio _dioThatResolves(Object? data, {int statusCode = 200}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(requestOptions: options, data: data, statusCode: statusCode),
        );
      },
    ),
  );
  return dio;
}

Dio _dioThatFails() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
            error: 'simulated network failure',
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  group('LocationGeocodingService.reverseGeocode', () {
    test('builds a short "street, area, city" label from a full address', () async {
      final dio = _dioThatResolves({
        'display_name':
            'Salinas Drive, Lahug, Cebu City, Cebu, Central Visayas, 6000, Philippines',
        'address': {
          'road': 'Salinas Drive',
          'suburb': 'Lahug',
          'city': 'Cebu City',
          'state': 'Central Visayas',
        },
      });
      final service = LocationGeocodingService(dio: dio);

      final label = await service.reverseGeocode(latitude: 10.3324, longitude: 123.9057);

      expect(label, 'Salinas Drive, Lahug, Cebu City');
    });

    test('falls back to display_name when no usable address fields are present', () async {
      final dio = _dioThatResolves({
        'display_name': 'Somewhere, Philippines',
        'address': <String, dynamic>{},
      });
      final service = LocationGeocodingService(dio: dio);

      final label = await service.reverseGeocode(latitude: 10.0, longitude: 123.0);

      expect(label, 'Somewhere, Philippines');
    });

    test('falls back to region when only a state/region is available', () async {
      final dio = _dioThatResolves({
        'display_name': 'Cebu, Philippines',
        'address': {'state': 'Cebu'},
      });
      final service = LocationGeocodingService(dio: dio);

      final label = await service.reverseGeocode(latitude: 10.0, longitude: 123.0);

      expect(label, 'Cebu');
    });

    test('returns null instead of throwing when the network call fails', () async {
      final service = LocationGeocodingService(dio: _dioThatFails());

      final label = await service.reverseGeocode(latitude: 10.0, longitude: 123.0);

      expect(label, isNull);
    });

    test('returns null when the response has no address or display_name', () async {
      final dio = _dioThatResolves({'address': <String, dynamic>{}});
      final service = LocationGeocodingService(dio: dio);

      final label = await service.reverseGeocode(latitude: 10.0, longitude: 123.0);

      expect(label, isNull);
    });
  });
}
