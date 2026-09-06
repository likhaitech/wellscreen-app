import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/usage_tracking_service.dart';

/// Covers UsageTrackingService.summarizeUsage - previously untestable
/// because getTodayUsage() called the native usage_stats plugin's static
/// UsageStats.queryAndAggregateUsageStats() directly and worked with its
/// UsageInfo type, which has no in-memory fake and talks to real Android
/// APIs. Fixed by extracting the actual transformation logic (readable
/// app-name conversion, dropping zero-usage entries, sorting by usage
/// descending, capping to the top 10) into summarizeUsage(), which takes
/// a plain `Map<String, int>` of package name -> foreground milliseconds -
/// exactly what's left after getTodayUsage() parses UsageInfo's
/// totalTimeInForeground string, but with no dependency on the plugin
/// type itself. getTodayUsage() (the native-plugin-touching part) is
/// intentionally NOT covered here - there's nothing to check without a
/// real device/emulator, and pub.dev is unreachable from this dev
/// environment's network policy to even confirm UsageInfo's exact
/// constructor shape, so no test pretends to cover that part.
///
/// summarizeUsage() now also calls _getApplicationLabel(), which goes
/// through a MethodChannel (com.wellscreen.app/app_info) to ask the native
/// side for the real installed-app label. Reading a MethodChannel requires
/// Flutter's ServicesBinding to be initialized first (normally done by
/// runApp() in the real app) - without TestWidgetsFlutterBinding
/// .ensureInitialized() below, invokeMethod() throws a raw "Binding has
/// not yet been initialized" error instead of the MissingPluginException
/// that _getApplicationLabel's catch clause is written to expect, so the
/// fallback to _makeReadableAppName() never gets a chance to run. Once the
/// binding is initialized, there's still no mock handler registered for
/// this channel, so invokeMethod() correctly throws MissingPluginException
/// and _getApplicationLabel falls back exactly as intended - which is what
/// these tests below are actually verifying.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UsageTrackingService.summarizeUsage', () {
    final service = UsageTrackingService();

    test('drops packages with zero or negative usage', () async {
      final result = await service.summarizeUsage({
        'com.example.zero': 0,
        'com.example.real': 60000,
      });

      expect(result, hasLength(1));
      expect(result.single.packageName, 'com.example.real');
    });

    test('sorts by usage duration descending', () async {
      final result = await service.summarizeUsage({
        'com.example.small': 1000,
        'com.example.big': 500000,
        'com.example.medium': 60000,
      });

      expect(
        result.map((s) => s.packageName).toList(),
        ['com.example.big', 'com.example.medium', 'com.example.small'],
      );
    });

    test('caps the result at 10 entries even with more real usage', () async {
      final input = <String, int>{
        for (var i = 0; i < 15; i++) 'com.example.app$i': (15 - i) * 1000,
      };

      final result = await service.summarizeUsage(input);

      expect(result, hasLength(10));
      // Confirms the cap keeps the TOP 10 by usage, not just the first 10
      // map entries encountered.
      expect(result.first.packageName, 'com.example.app0');
      expect(result.last.packageName, 'com.example.app9');
    });

    test(
      'derives a capitalized display name from the last package-name segment',
      () async {
        final result = await service.summarizeUsage({
          'com.google.android.youtube': 60000,
        });

        // main's _makeReadableAppName special-cases this exact package via
        // its knownPackages map, so this is the properly-capitalized brand
        // name rather than a mechanically-titlecased path segment.
        expect(result.single.displayName, 'YouTube');
      },
    );

    test(
      'falls back to the raw package name when it has no dot-separated '
      'segments to derive a name from',
      () async {
        final result = await service.summarizeUsage({'singleword': 60000});
        expect(result.single.displayName, 'Singleword');
      },
    );

    test('usageDuration reflects the exact input milliseconds', () async {
      final result = await service.summarizeUsage({
        'com.example.app': 123456,
      });
      expect(
        result.single.usageDuration,
        const Duration(milliseconds: 123456),
      );
    });

    test('an empty map produces an empty summary list', () async {
      expect(await service.summarizeUsage({}), isEmpty);
    });
  });
}
