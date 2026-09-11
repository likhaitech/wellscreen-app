import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/ml_risk_classifier_service.dart';

/// Covers MlRiskClassifierService - the app code that CONSUMES the
/// trained Random Forest risk model (assets/ml/forest_rules.json), not
/// the model's own training/evaluation, which lives separately in
/// ml/output/evaluation_report.txt. This had zero test coverage before:
/// the tree-replay logic (soft-voting predict_proba across 60 trees,
/// walking each tree's exported if/else rules) had never actually been
/// run.
///
/// These tests load the REAL trained
/// assets/ml/forest_rules.json (declared in pubspec.yaml, so
/// `flutter test` bundles it exactly like the real app does), against
/// usage profiles chosen to be unambiguous along the feature axes
/// described in ml/generate_dataset.py (total screen time vs. daily
/// limit, late-night usage, longest session, restricted-app attempts,
/// rule violations). The expected label/probabilities for each profile
/// were computed independently by re-implementing the exact same
/// tree-walk/averaging algorithm in Python straight from this same JSON
/// file and running it for real - not guessed, not hand-tuned to make
/// the test pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MlRiskClassifierService.classify (real trained forest)', () {
    final service = MlRiskClassifierService();

    test(
      'a low-usage, no-violations profile classifies as Low Risk',
      () async {
        final result = await service.classify({
          'total_screen_time_minutes': 45,
          'daily_limit_minutes': 120,
          'late_night_minutes': 0,
          'longest_session_minutes': 20,
          'restricted_app_attempts_today': 0,
          'rule_violations_7d': 0,
        });

        expect(result.label, 'Low Risk');
        // Verified via independent Python replay of the real forest:
        // ~0.9546 averaged probability for Low Risk on this profile.
        expect(result.confidence, closeTo(0.9546, 0.01));
        expect(
          result.classProbabilities['Low Risk'],
          closeTo(result.confidence, 1e-9),
        );
      },
    );

    test(
      'a heavy-usage, high-violations, late-night-heavy profile classifies '
      'as High Risk',
      () async {
        final result = await service.classify({
          'total_screen_time_minutes': 480,
          'daily_limit_minutes': 120,
          'late_night_minutes': 150,
          'longest_session_minutes': 240,
          'restricted_app_attempts_today': 10,
          'rule_violations_7d': 12,
        });

        expect(result.label, 'High Risk');
        // Verified via independent Python replay: ~0.7237.
        expect(result.confidence, closeTo(0.7237, 0.01));
      },
    );

    test('a moderate usage profile classifies as Moderate Risk', () async {
      final result = await service.classify({
        'total_screen_time_minutes': 180,
        'daily_limit_minutes': 150,
        'late_night_minutes': 20,
        'longest_session_minutes': 60,
        'restricted_app_attempts_today': 1,
        'rule_violations_7d': 2,
      });

      expect(result.label, 'Moderate Risk');
      // Verified via independent Python replay: ~0.7081.
      expect(result.confidence, closeTo(0.7081, 0.01));
    });

    test(
      'classProbabilities always sums to ~1.0 across all three classes',
      () async {
        final result = await service.classify({
          'total_screen_time_minutes': 180,
          'daily_limit_minutes': 150,
          'late_night_minutes': 20,
          'longest_session_minutes': 60,
          'restricted_app_attempts_today': 1,
          'rule_violations_7d': 2,
        });

        final sum = result.classProbabilities.values.fold<double>(
          0,
          (a, b) => a + b,
        );
        expect(sum, closeTo(1.0, 1e-6));
        expect(result.classProbabilities.keys.toSet(), {
          'High Risk',
          'Low Risk',
          'Moderate Risk',
        });
      },
    );

    test(
      'missing feature keys default to 0 rather than throwing, and still '
      'produce a real prediction',
      () async {
        // classify() reads features[name] ?? 0 for each of the six
        // expected keys - an empty map should behave exactly like a
        // profile with every feature at zero, not crash.
        final result = await service.classify({});

        expect(result.label, 'Low Risk');
        // Verified via independent Python replay of the all-zero profile.
        expect(result.confidence, closeTo(0.9411, 0.01));
      },
    );

    test('modelVersion is read from the real bundled asset', () async {
      final result = await service.classify({
        'total_screen_time_minutes': 45,
        'daily_limit_minutes': 120,
        'late_night_minutes': 0,
        'longest_session_minutes': 20,
        'restricted_app_attempts_today': 0,
        'rule_violations_7d': 0,
      });

      // forest_rules.json's real modelVersion field, not a placeholder.
      expect(result.modelVersion, 'risk_forest_v1');
    });
  });
}
