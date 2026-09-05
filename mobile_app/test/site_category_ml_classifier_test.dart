import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/site_category_ml_classifier.dart';

/// Covers SiteCategoryMlClassifier - the app code that CONSUMES the
/// trained gambling-detection model, not the model itself. The model's
/// own precision/recall/false-positive numbers are already measured in
/// ml/site_category/output/category_classifier_evaluation.txt; what had
/// never been checked is whether this Dart reimplementation of
/// TF-IDF + logistic regression actually reproduces those numbers when
/// run for real, and whether the confidence-threshold/class-restriction
/// gating (meetsDeploymentBar) behaves the way the class's own doc
/// comment says it does.
///
/// These tests load the REAL trained
/// assets/site_categories/category_classifier_weights.json (declared in
/// pubspec.yaml, so `flutter test` bundles it like the real app does) and
/// check real predictions against real, documented data points - not
/// synthetic fixtures with made-up numbers:
///
/// - odnoklassniki.ru is the exact false positive named in
///   category_classifier_evaluation.txt's "Held-out real-world
///   false-positive check" section (predicted "drugs" at 0.902,
///   above the 0.90 threshold). It's used here to confirm the
///   class-restriction half of meetsDeploymentBar actually holds: even
///   though this domain crosses the confidence bar, it should NOT be
///   flagged, because only 'gambling' is a live-deployment class.
/// - The safe-domain and gambling-domain examples below were selected by
///   independently re-implementing this exact algorithm in Python
///   straight from the same JSON weights file and running it for real
///   against validation/safe_domains_heldout.txt (the actual held-out
///   set the 0.90 threshold was chosen from) and raw/gambling_domains.txt
///   (the actual real training data) - not hand-picked to make the test
///   pass, picked because that independent run is what the real model
///   actually outputs for them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SiteCategoryMlClassifier.predict (real trained model)', () {
    final classifier = SiteCategoryMlClassifier();

    test('returns null for an empty string (no n-grams to score)', () async {
      final result = await classifier.predict('');
      expect(result, isNull);
    });

    test(
      'flags a real, high-confidence gambling domain and meets the deployment bar',
      () async {
        // Verified via independent Python replay of the real weights:
        // predicted 'gambling' at ~0.9987 confidence.
        final result = await classifier.predict('casinomaxi5.com');
        expect(result, isNotNull);
        expect(result!.category, 'gambling');
        expect(result.confidence, greaterThanOrEqualTo(0.9));
        expect(result.meetsDeploymentBar, isTrue);
      },
    );

    test(
      'an extremely confident real gambling domain also meets the bar',
      () async {
        // Verified via independent Python replay: ~0.999997 confidence -
        // about as unambiguous as this model gets.
        final result = await classifier.predict('betso888-casino.me');
        expect(result!.category, 'gambling');
        expect(result.confidence, greaterThan(0.99));
        expect(result.meetsDeploymentBar, isTrue);
      },
    );

    test(
      'a real gambling-training domain predicted gambling but BELOW the '
      'confidence threshold does NOT meet the deployment bar',
      () async {
        // Verified via independent Python replay: predicted 'gambling'
        // correctly, but only at ~0.675 confidence - below the 0.90 bar.
        // This is the confidence-gating half of meetsDeploymentBar: being
        // the right category is necessary but not sufficient.
        final result = await classifier.predict('mgmresortsdiversity.com');
        expect(result!.category, 'gambling');
        expect(result.confidence, lessThan(0.90));
        expect(result.meetsDeploymentBar, isFalse);
      },
    );

    test(
      'odnoklassniki.ru: the exact false positive named in the training '
      'evaluation report is correctly kept OUT of live deployment, because '
      "'drugs' is not a live-deployment class (class-restriction gate, "
      'not just the confidence gate)',
      () async {
        final result = await classifier.predict('odnoklassniki.ru');
        expect(result, isNotNull);
        expect(result!.category, 'drugs');
        // The evaluation report measured 0.902 - allow a little float
        // tolerance rather than pinning the exact double.
        expect(result.confidence, closeTo(0.902, 0.01));
        // This is the important assertion: confidence clears 0.90, but
        // meetsDeploymentBar must still be false, because 'drugs' isn't
        // in liveDeploymentClasses.
        expect(result.meetsDeploymentBar, isFalse);
      },
    );

    test(
      'real held-out safe domains never meet the deployment bar '
      '(matches the 0 gambling-false-positives-at-0.90 result in the '
      'training evaluation report)',
      () async {
        // A cross-section of validation/safe_domains_heldout.txt - the
        // actual genuinely-unseen-during-training set the 0.90 threshold
        // decision was based on. Not exhaustive (the full 200-domain
        // check lives in the Python training pipeline, which is the
        // right place for a statistical false-positive-rate claim), but
        // enough to catch a real regression if this Dart port ever drifts
        // from the Python model it's supposed to faithfully replay.
        const safeHeldoutSample = [
          'todyl.net',
          'zh.ch',
          'bmw.cloud',
          'arte-magazin.de',
          'streamelements.com',
        ];

        for (final domain in safeHeldoutSample) {
          final result = await classifier.predict(domain);
          expect(
            result == null || result.meetsDeploymentBar == false,
            isTrue,
            reason:
                '$domain should not meet the gambling deployment bar '
                '(got: ${result?.category} @ ${result?.confidence})',
          );
        }
      },
    );

    test('predictions are case-insensitive, like the training text', () async {
      final lower = await classifier.predict('casinomaxi5.com');
      final upper = await classifier.predict('CASINOMAXI5.COM');
      expect(upper!.category, lower!.category);
      expect(upper.confidence, closeTo(lower.confidence, 1e-9));
    });
  });
}
