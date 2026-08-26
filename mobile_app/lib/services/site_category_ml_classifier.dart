import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Result of a live ML prediction - always returned even when the caller
/// shouldn't act on it (see [SiteCategoryMlClassifier.predict]'s doc
/// comment). [meetsDeploymentBar] is what callers should actually check
/// before treating this as a real detection.
class MlCategoryPrediction {
  const MlCategoryPrediction({
    required this.category,
    required this.confidence,
    required this.meetsDeploymentBar,
  });

  final String category;
  final double confidence;
  final bool meetsDeploymentBar;
}

/// Pure-Dart reimplementation of a real scikit-learn model trained in
/// ml/site_category/train_category_classifier.py: TF-IDF over character
/// n-grams feeding a multinomial LogisticRegression, trained on 78,177
/// real domains (58,219 harmful + 19,958 real safe/benign - see that
/// script's doc comment for full sourcing and why this specific model
/// shape was chosen).
///
/// WHY THIS EXISTS, separate from SiteCategoryService's exact-match
/// lookup: the lookup can only ever catch a domain that is LITERALLY a
/// row in the bundled CSV. This classifier generalizes from the SHAPE of
/// a domain name, so it can flag a domain the lookup has never seen (a
/// brand-new gambling site, a variant spelling, etc) - genuine machine
/// learning, not string matching.
///
/// WHY IT'S RESTRICTED TO 'gambling' ONLY, AND ONLY ABOVE A HIGH
/// CONFIDENCE THRESHOLD: measured, not guessed - including a deliberate
/// attempt to break it before trusting it. Live testing during
/// development showed a version of this model with no "safe" training
/// class at all confidently mislabeling completely unrelated real sites
/// (slack.com, trello.com, duolingo.com, amazon.com) as "gambling" -
/// because it had never once seen a benign domain during training and
/// was forced to guess a harmful label for everything. After adding a
/// real ~19,958-domain "safe" class, a genuinely held-out validation set
/// of 200 real safe domains (never used in training - see
/// ml/site_category/validation/safe_domains_heldout.txt) still produced
/// false positives below a 0.90 confidence threshold; AT 0.90, zero false
/// positives were observed on that held-out set, while the model still
/// caught 89.3% of real gambling test domains (measured on a genuinely
/// held-out 20%-stratified split, 6,447 real examples).
///
/// 'drugs' was ALSO tested for live deployment after its real training
/// data grew from 436 to 25,948 domains (a second real source was added
/// - The Block List Project's "drugs" list - on top of UT1's smaller
/// one, see ml/site_category/clean_dataset.py's SOURCES comment), and it
/// looked promising on the same easy 200-domain safe holdout (also 0
/// false positives, 61.3% recall on 5,191 real held-out drugs test
/// examples). But a lot of that new training data is illicit
/// online-pharmacy spam, so a harder, more targeted stress test was
/// built on purpose - 27 real, legitimate pharmacy/healthcare companies
/// (ml/site_category/validation/safe_pharmacy_health_heldout.txt) - and
/// it caught a real problem the easy test missed: truepill.com, a real
/// US pharmacy company, predicted "drugs" at 95.5% confidence, above the
/// deployment bar. A follow-up cleaning pass removed 7 individually
/// verified, genuinely mislabeled legitimate domains from the drugs
/// training data (drugs.com, pharmacychecker.com, rxlist.com, and 4
/// university health-education sites - see
/// ml/site_category/clean_dataset.py's KNOWN_MISLABELED_LEGITIMATE_DOMAINS)
/// - but retesting after retraining showed this did NOT fix the problem
/// (truepill.com still predicts drugs at 95.1%). Diagnosis: the real
/// cause is broader than a handful of bad labels - roughly a third of
/// the raw drugs training data is hosted under .ru/.su TLDs, so the
/// model has learned a TLD-level bias, not just a pharmacy-naming one
/// (confirmed by a NEW false positive the cleanup surfaced:
/// odnoklassniki.ru, a real Russian social network with nothing to do
/// with drugs, predicted "drugs" at 90.2%). That is two concrete,
/// reproducible failure modes now, not one, so 'drugs' stays OUT of live
/// ML deployment even though its numbers looked good on the easier check
/// - see ml/site_category/train_category_classifier.py's
/// LIVE_DEPLOYMENT_CLASSES comment and README.md's "Cleanup attempt"
/// section for the full story. The much larger, now-cleaner real drugs
/// dataset still benefits the app through the exact-match lookup, just
/// not yet through ML generalization to unseen domains.
///
/// dangerous_material/adult are excluded from live deployment entirely
/// (not just threshold-gated) because those classes have far too few
/// real training examples (35/3) for the model to have learned a
/// reliable pattern - 0% recall at this threshold on their own held-out
/// test examples, measured, not assumed (see
/// ml/site_category/output/category_classifier_evaluation.txt). No
/// larger real domain-level source was found for either after
/// searching - see README.md. dangerous_material stays exact-lookup-only
/// in this app; adult is exact-lookup + keyword-matched (see
/// AdultKeywordDetector) but not ML-classified. This classifier is
/// deliberately conservative rather than comprehensive, because a false
/// "your child visited a harmful site" alert on an ordinary domain
/// actively damages a parent's trust in the whole app. The threshold and
/// class restriction are read directly from the exported weights file
/// (liveDeploymentThreshold/liveDeploymentClasses), not hardcoded here,
/// so the app's policy can never silently drift out of sync with what
/// was actually measured when the model was trained.
class SiteCategoryMlClassifier {
  static const String _assetPath =
      'assets/site_categories/category_classifier_weights.json';

  List<String>? _vocabulary;
  Map<String, int>? _vocabIndex;
  List<double>? _idf;
  List<String>? _classes;
  List<List<double>>? _coefficients; // [classIndex][featureIndex]
  List<double>? _intercepts;
  int _minN = 2;
  int _maxN = 4;
  double _deploymentThreshold = 1.0; // safe default if the asset is ever missing a field
  Set<String> _deploymentClasses = const {};

  Future<void> _ensureLoaded() async {
    if (_vocabulary != null) return;

    final raw = await rootBundle.loadString(_assetPath);
    final Map<String, dynamic> data = json.decode(raw) as Map<String, dynamic>;

    final ngramRange = (data['ngramRange'] as List).cast<num>();
    _minN = ngramRange[0].toInt();
    _maxN = ngramRange[1].toInt();

    _vocabulary = (data['vocabulary'] as List).cast<String>();
    _vocabIndex = {
      for (var i = 0; i < _vocabulary!.length; i++) _vocabulary![i]: i,
    };
    _idf = (data['idf'] as List)
        .map((e) => (e as num).toDouble())
        .toList(growable: false);
    _classes = (data['classes'] as List).cast<String>();
    _coefficients = (data['coefficients'] as List)
        .map(
          (row) => (row as List)
              .map((e) => (e as num).toDouble())
              .toList(growable: false),
        )
        .toList(growable: false);
    _intercepts = (data['intercepts'] as List)
        .map((e) => (e as num).toDouble())
        .toList(growable: false);
    _deploymentThreshold = (data['liveDeploymentThreshold'] as num).toDouble();
    _deploymentClasses = (data['liveDeploymentClasses'] as List)
        .cast<String>()
        .toSet();
  }

  /// Faithfully reimplements scikit-learn's
  /// TfidfVectorizer(analyzer='char', ngram_range, max_features) +
  /// multinomial LogisticRegression scoring - verified during development
  /// to reproduce sklearn's predict_proba() output exactly (to 6 decimal
  /// places) on real test domains before this was ported here. Returns
  /// null only if the domain contains none of the trained vocabulary's
  /// n-grams at all (e.g. an empty string).
  Future<MlCategoryPrediction?> predict(String domain) async {
    await _ensureLoaded();

    final vocabIndex = _vocabIndex!;
    final idf = _idf!;
    final text = domain.toLowerCase();

    // Step 1: raw term counts for vocabulary n-grams present in this
    // domain string. sklearn's analyzer='char' (deliberately NOT
    // 'char_wb' - see the training script) is a plain sliding window over
    // the whole string for every n in [minN, maxN], no word tokenization.
    final counts = <int, int>{};
    for (var n = _minN; n <= _maxN; n++) {
      if (text.length < n) continue;
      for (var i = 0; i <= text.length - n; i++) {
        final gram = text.substring(i, i + n);
        final idx = vocabIndex[gram];
        if (idx != null) {
          counts[idx] = (counts[idx] ?? 0) + 1;
        }
      }
    }

    if (counts.isEmpty) return null;

    // Step 2: tf * idf per present feature.
    final tfidf = <int, double>{};
    for (final entry in counts.entries) {
      tfidf[entry.key] = entry.value * idf[entry.key];
    }

    // Step 3: L2-normalize (TfidfVectorizer's default norm='l2') over the
    // present features - everything absent contributes exactly 0 to both
    // the norm and every dot product below, so it's safe to skip them.
    var sumSquares = 0.0;
    for (final v in tfidf.values) {
      sumSquares += v * v;
    }
    final norm = math.sqrt(sumSquares);
    if (norm == 0) return null;

    // Step 4: per-class linear score = dot(weights_class, tfidf_vector) + intercept_class.
    final classes = _classes!;
    final coefficients = _coefficients!;
    final intercepts = _intercepts!;
    final scores = List<double>.filled(classes.length, 0);

    for (var c = 0; c < classes.length; c++) {
      var score = intercepts[c];
      final classWeights = coefficients[c];
      for (final entry in tfidf.entries) {
        final normalizedValue = entry.value / norm;
        score += classWeights[entry.key] * normalizedValue;
      }
      scores[c] = score;
    }

    // Step 5: softmax over raw scores - matches LogisticRegression's
    // predict_proba() for a multinomial model.
    final maxScore = scores.reduce(math.max);
    final expScores = scores.map((s) => math.exp(s - maxScore)).toList();
    final sumExp = expScores.reduce((a, b) => a + b);
    final probs = expScores.map((e) => e / sumExp).toList();

    var bestIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIdx]) bestIdx = i;
    }

    final category = classes[bestIdx];
    final confidence = probs[bestIdx];
    final meetsBar = _deploymentClasses.contains(category) &&
        confidence >= _deploymentThreshold;

    return MlCategoryPrediction(
      category: category,
      confidence: confidence,
      meetsDeploymentBar: meetsBar,
    );
  }
}
