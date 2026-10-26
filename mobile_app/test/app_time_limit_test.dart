import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/app_time_limit.dart';
import 'package:app/services/usage_tracking_service.dart';

void main() {
  test('per-app allowance uses exact milliseconds, not rounded minutes', () {
    const limit = AppTimeLimit(
      packageName: 'com.example.video',
      appName: 'Video',
      limitMinutes: 60,
    );
    expect(limit.remainingMilliseconds(59 * 60 * 1000), 60 * 1000);
    expect(limit.limitReached(59 * 60 * 1000), false);
    expect(limit.limitReached(60 * 60 * 1000), true);
    expect(limit.remainingMilliseconds(70 * 60 * 1000), 0);
  });

  test('full usage contains every used app; existing top-ten stays capped', () {
    final service = UsageTrackingService();
    final durations = <String, int>{
      for (var i = 0; i < 12; i++) 'com.example.app$i': (i + 1) * 1000,
    };
    final full = service.summarizeAllUsage(durations);
    final top = service.summarizeUsage(durations);
    expect(full.length, 12);
    expect(top.length, 10);
    expect(full.first.packageName, 'com.example.app11');
    expect(top.first.packageName, 'com.example.app11');
  });
}
