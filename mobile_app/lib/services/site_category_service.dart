import 'package:flutter/services.dart' show rootBundle;

/// On-device lookup against the real, cleaned UT1 Blacklists domain dataset
/// (see ml/site_category/README.md and
/// data_cleaned/site_categories/cleaned_site_categories.csv for the source,
/// cleaning methodology, and honest limitations - imbalanced categories, no
/// self-harm category, adult category deliberately excluded).
///
/// SCOPE: this classifies a domain that BrowserUrlExtractor/BrowsingLogger
/// already captured (see WellScreenAccessibilityService.kt) - it does not
/// itself capture anything, and it does not block the page from loading.
/// What it enables is: syncUsageReport() can now tag each captured domain
/// with a category and alert the parent when a harmful one shows up. Real,
/// same-moment blocking (like restricted-app blocking already does) would
/// need this same check running natively in Kotlin before the page
/// renders - not built yet, see ml/site_category/README.md's "What's NOT
/// done yet" section.
///
/// WHY ON-DEVICE, NOT A BACKEND CALL: matches the same privacy reasoning as
/// MlRiskClassifierService - a captured domain never has to leave the
/// child's device to be checked. The tradeoff is app size (~1MB bundled
/// asset) and that updating the list requires a new app build, not a
/// runtime data change - an accepted tradeoff here, not an oversight.
class SiteCategoryService {
  static const String _assetPath =
      'assets/site_categories/cleaned_site_categories.csv';

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

  /// Returns the dataset's category for [domain] (e.g. "gambling"), or null
  /// if it isn't in the dataset. Checks the domain itself and then
  /// progressively strips subdomains down to the bare registrable domain
  /// ("m.somecasino.com", "ads.somecasino.com", and "somecasino.com" all
  /// resolve to the same category as "somecasino.com" if that's what's in
  /// the dataset) - a raw exact-string match alone would miss most real
  /// subdomains a browser actually shows.
  Future<String?> classify(String domain) async {
    await _ensureLoaded();

    final map = _domainToCategory!;
    final normalized = domain.trim().toLowerCase();
    final labels = normalized.split('.');

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
}
