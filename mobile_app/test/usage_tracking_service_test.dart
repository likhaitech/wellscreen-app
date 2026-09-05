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
void main() {
  group('UsageTrackingService.summarizeUsage', () {
    final service = UsageTrackingService();

    test('drops packages with zero or negative usage', () {
      final result = service.summarizeUsage({
        'com.example.zero': 0,
        'com.example.real': 60000,
      });

      expect(result, hasLength(1));
      expect(result.single.packageName, 'com.example.real');
    });

    test('sorts by usage duration descending', () {
      final result = service.summarizeUsage({
        'com.example.small': 1000,
        'com.example.big': 500000,
        'com.example.medium': 60000,
      });

      expect(
        result.map((s) => s.packageName).toList(),
        ['com.example.big', 'com.example.medium', 'com.example.small'],
      );
    });

    test('caps the result at 10 entries even with more real usage', () {
      final input = <String, int>{
        for (var i = 0; i < 15; i++) 'com.example.app$i': (15 - i) * 1000,
      };

      final result = service.summarizeUsage(input);

      expect(result, hasLength(10));
      // Confirms the cap keeps the TOP 10 by usage, not just the first 10
      // map entries encountered.
      expect(result.first.packageName, 'com.example.app0');
      expect(result.last.packageName, 'com.example.app9');
    });

    test(
      'derives a capitalized display name from the last package-name segment',
      () {
        final result = service.summarizeUsage({
          'com.google.android.youtube': 60000,
        });

        expect(result.single.displayName, 'Youtube');
      },
    );

    test(
      'falls back to the raw package name when it has no dot-separated '
      'segments to derive a name from',
      () {
        final result = service.summarizeUsage({'singleword': 60000});
        expect(result.single.displayName, 'Singleword');
      },
    );

    test('usageDuration reflects the exact input milliseconds', () {
      final result = service.summarizeUsage({'com.example.app': 123456});
      expect(
        result.single.usageDuration,
        const Duration(milliseconds: 123456),
      );
    });

    test('an empty map produces an empty summary list', () {
      expect(service.summarizeUsage({}), isEmpty);
    });
  });
}
