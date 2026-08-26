import 'package:flutter/services.dart' show rootBundle;

import 'adult_keyword_detector.dart';
import 'site_category_ml_classifier.dart';

/// A category match for a captured domain, tagging WHICH mechanism found
/// it - the exact-match lookup (100% precise for domains it has seen),
/// keyword matching (AdultKeywordDetector - the technique described in
/// the manuscript, with a real, tested and honestly-documented
/// false-positive mitigation), or the live ML classifier (generalizes to
/// unseen domains, but only trusted above a measured confidence bar - see
/// SiteCategoryMlClassifier's doc comment). [confidence] is only set for
/// 'ml' matches; lookup and keyword matches are exact/rule-based, so
/// there's no confidence score to report for them.
class SiteCategoryMatch {
  const SiteCategoryMatch({
    required this.category,
    required this.source,
    this.confidence,
  });

  final String category;
  final String source; // 'lookup', 'keyword', or 'ml'
  final double? confidence;
}

/// On-device detection against WellScreen's real site-category data - see
/// ml/site_category/README.md and data_cleaned/site_categories/ for the
/// source, cleaning methodology, and honest limitations (imbalanced
/// categories, no self-harm category, adult category limited to 3
/// Philippines-specific domains - see README.md for why).
///
/// Three mechanisms, tried in order:
///   1. Exact-match lookup against the bundled cleaned_site_categories.csv
///      (gambling/drugs/dangerous_material/adult) - fast, 100% precise for
///      domains already in the dataset, but can never catch a domain that
///      isn't literally a row in it.
///   2. Keyword matching (AdultKeywordDetector), only when the lookup
///      finds nothing - the technique the manuscript describes for
///      pornography specifically (flagging domains containing terms like
///      "porn", "xxx", "sex", "tube"). Deliberately a DIFFERENT technique
///      from the ML classifier below, not a re-skin of it - see that
///      class's doc comment for why substring matching was chosen over
///      word-boundary matching, why a literal "x" keyword was rejected
///      (x.com is a real, massive site), and the allowlist that mitigates
///      the well-known "Scunthorpe problem" this technique is inherently
///      prone to.
///   3. Live ML fallback (SiteCategoryMlClassifier), only when neither of
///      the above finds anything - a real, trained-on-real-data text
///      classifier that can generalize to domains never seen before.
///      Deliberately restricted to 'gambling' predictions only, above a
///      high, measured confidence bar (see that class's doc comment) -
///      'drugs' was also tested (its real training data grew a lot this
///      iteration) but deliberately held back after a targeted stress
///      test found it false-positives on legitimate pharmacy/healthcare
///      domains; dangerous_material/adult stay out too, for having too
///      few real training examples. A false alert on a normal domain is
///      worse than a missed detection for a parental-control app's
///      credibility.
///
/// SCOPE: this classifies a domain that BrowserUrlExtractor/BrowsingLogger
/// already captured (see WellScreenAccessibilityService.kt) - it does not
/// itself capture anything, and it does not block the page from loading.
/// Real, same-moment blocking (like restricted-app blocking already does)
/// would need this same check running natively in Kotlin before the page
/// renders - not built yet, see ml/site_category/README.md's "What's NOT
/// done yet" section.
///
/// WHY ON-DEVICE, NOT A BACKEND CALL: matches the same privacy reasoning as
/// MlRiskClassifierService - a captured domain never has to leave the
/// child's device to be checked, for either mechanism.
class SiteCategoryService {
  static const String _assetPath =
      'assets/site_categories/cleaned_site_categories.csv';

  final SiteCategoryMlClassifier _mlClassifier = SiteCategoryMlClassifier();
  final AdultKeywordDetector _keywordDetector = AdultKeywordDetector();

  Map<String, String>? _domainToCategory;

  Future<void> _ensureLoaded() async {
    if (_domainToCategory != null) return;

    final raw = await rootBundle.loadString(_assetPath);
    final lines = raw.split('\n');
    final map = <String, String>{};

    // Skip the header row ("domain,category") and any trailing blank line.
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final commaIndex = trimmed.indexOf(',');
      if (commaIndex == -1) continue;

      final domain = trimmed.substring(0, commaIndex);
      final category = trimmed.substring(commaIndex + 1);
      map[domain] = category;
    }

    _domainToCategory = map;
  }

  /// Exact-match lookup only (the original mechanism, unchanged) - checks
  /// the domain itself and then progressively strips subdomains down to
  /// the bare registrable domain ("m.somecasino.com",
  /// "ads.somecasino.com", and "somecasino.com" all resolve to the same
  /// category as "somecasino.com" if that's what's in the dataset).
  String? _lookupExact(String normalizedDomain) {
    final map = _domainToCategory!;
    final labels = normalizedDomain.split('.');

    // Stop once only 2 labels remain (a bare "example.com") - checking a
    // single label or a bare TLD would be meaningless and could produce
    // absurd false positives.
    for (var start = 0; start <= labels.length - 2; start++) {
      final candidate = labels.sublist(start).join('.');
      final category = map[candidate];
      if (category != null) return category;
    }

    return null;
  }

  /// Returns a [SiteCategoryMatch] for [domain], or null if none of the
  /// exact lookup, keyword matching, or the live ML classifier (at its
  /// deployment bar) found anything. See the class doc comment for the
  /// three-mechanism order and why the ML fallback is deliberately
  /// conservative.
  Future<SiteCategoryMatch?> classify(String domain) async {
    await _ensureLoaded();

    final normalized = domain.trim().toLowerCase();

    final exactCategory = _lookupExact(normalized);
    if (exactCategory != null) {
      return SiteCategoryMatch(category: exactCategory, source: 'lookup');
    }

    if (_keywordDetector.matches(normalized)) {
      return const SiteCategoryMatch(category: 'adult', source: 'keyword');
    }

    final mlPrediction = await _mlClassifier.predict(normalized);
    if (mlPrediction != null && mlPrediction.meetsDeploymentBar) {
      return SiteCategoryMatch(
        category: mlPrediction.category,
        source: 'ml',
        confidence: mlPrediction.confidence,
      );
    }

    return null;
  }
}
