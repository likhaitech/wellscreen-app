import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// On-device inference for WellScreen's proposed Random Forest risk
/// classifier (manuscript Ch. 3, "Proposed Machine Learning Extension").
///
/// WHY NOT TFLITE: the trained model is a scikit-learn RandomForestClassifier,
/// not a TensorFlow/Keras model - scikit-learn tree ensembles don't export to
/// TFLite directly. The reliable path (TensorFlow Decision Forests -> TFLite)
/// requires TFLite's "select ops" runtime, which the standard tflite_flutter
/// plugin doesn't include by default - a real compatibility risk this project
/// isn't in a position to debug on a physical device before a defense
/// deadline. Instead, ml/train_model.py exports the trained forest's exact
/// decision rules (feature/threshold per split, class-vote distribution per
/// leaf) as assets/ml/forest_rules.json, and this class replays those exact
/// rules natively in Dart. The predictions are identical to what the Python
/// model produces - this is tree replay, not an approximation - and it adds
/// zero new native dependencies or build risk.
///
/// HONESTY NOTE (manuscript Ch. 3: "This model is proposed as an extension
/// and should not be presented as fully trained unless the researchers
/// already have the dataset, training results, and evaluation outputs."):
/// this model IS fully trained, with real evaluation outputs (see
/// ml/output/evaluation_report.txt) - but the training dataset is
/// SIMULATED, not real child usage data (see ml/generate_dataset.py's doc
/// comment for exactly which of Table 6's indicators are and aren't
/// included as inputs, and why). Present it as: a real, trained, evaluated
/// Random Forest classifier, trained on simulated/synthetic data because no
/// real labeled dataset exists yet - not as validated against real
/// children's behavior. It supplements PatternDetectionService's rule-based
/// detection (which remains primary, per the manuscript); it does not
/// replace it.
class MlRiskAssessment {
  const MlRiskAssessment({
    required this.label,
    required this.confidence,
    required this.classProbabilities,
    required this.modelVersion,
  });

  /// "Low Risk" / "Moderate Risk" / "High Risk" - matches Table 7 exactly.
  final String label;

  /// The winning class's averaged probability across all trees (0-1).
  final double confidence;

  /// Full probability distribution across all three classes, for anyone
  /// who wants to show e.g. "62% Moderate, 30% Low, 8% High" instead of
  /// just the top label.
  final Map<String, double> classProbabilities;

  final String modelVersion;
}

class MlRiskClassifierService {
  static const String _assetPath = 'assets/ml/forest_rules.json';

  Map<String, dynamic>? _forest;
  List<String>? _featureOrder;
  List<String>? _classOrder;

  Future<void> _ensureLoaded() async {
    if (_forest != null) return;

    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    _forest = decoded;
    _featureOrder = List<String>.from(decoded['featureOrder'] as List);
    _classOrder = List<String>.from(decoded['classOrder'] as List);
  }

  /// Classifies a single day's usage record. [features] must contain every
  /// key in forest_rules.json's featureOrder (see
  /// ml/generate_dataset.py for what each one means and where it comes
  /// from on-device): total_screen_time_minutes, daily_limit_minutes,
  /// late_night_minutes, longest_session_minutes,
  /// restricted_app_attempts_today, rule_violations_7d.
  Future<MlRiskAssessment> classify(Map<String, num> features) async {
    await _ensureLoaded();

    final featureOrder = _featureOrder!;
    final classOrder = _classOrder!;
    final trees = _forest!['trees'] as List;

    final x = featureOrder
        .map((name) => (features[name] ?? 0).toDouble())
        .toList();

    // Average each tree's leaf class-probability vector - this is exactly
    // what sklearn's RandomForestClassifier.predict_proba() does
    // internally (soft voting across estimators), so the result matches
    // the Python model's output, not just its majority-vote label.
    final summedProbabilities = List<double>.filled(classOrder.length, 0.0);

    for (final treeNodes in trees) {
      final nodes = treeNodes as List;
      final votes = _evaluateTree(nodes, x);
      final total = votes.fold<double>(0, (sum, v) => sum + v);

      if (total <= 0) continue;

      for (var i = 0; i < votes.length; i++) {
        summedProbabilities[i] += votes[i] / total;
      }
    }

    final treeCount = trees.length;
    final averagedProbabilities = summedProbabilities
        .map((sum) => treeCount > 0 ? sum / treeCount : 0.0)
        .toList();

    var winningIndex = 0;
    for (var i = 1; i < averagedProbabilities.length; i++) {
      if (averagedProbabilities[i] > averagedProbabilities[winningIndex]) {
        winningIndex = i;
      }
    }

    return MlRiskAssessment(
      label: classOrder[winningIndex],
      confidence: averagedProbabilities[winningIndex],
      classProbabilities: {
        for (var i = 0; i < classOrder.length; i++)
          classOrder[i]: averagedProbabilities[i],
      },
      modelVersion: _forest!['modelVersion'] as String? ?? 'unknown',
    );
  }

  /// Walks a single exported tree from the root (index 0) following the
  /// same convention scikit-learn's tree_ structure uses: at each internal
  /// node, go left if x[featureIndex] <= threshold, otherwise right.
  /// Returns the raw per-class vote counts at the leaf reached.
  List<double> _evaluateTree(List nodes, List<double> x) {
    var nodeIndex = 0;

    while (true) {
      final node = nodes[nodeIndex] as Map<String, dynamic>;

      if (node['leaf'] == true) {
        return List<double>.from(
          (node['votes'] as List).map((v) => (v as num).toDouble()),
        );
      }

      final featureIndex = node['featureIndex'] as int;
      final threshold = (node['threshold'] as num).toDouble();

      nodeIndex = x[featureIndex] <= threshold
          ? node['left'] as int
          : node['right'] as int;
    }
  }
}
