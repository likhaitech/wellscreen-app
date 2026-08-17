"""
Trains WellScreen's proposed Random Forest risk classifier on the simulated
dataset (see generate_dataset.py), evaluates it, and exports:
  1. output/evaluation_report.txt - accuracy, per-class precision/recall/F1,
     confusion matrix, feature importances - for the manuscript's Results
     chapter.
  2. output/forest_rules.json - the trained forest's decision rules
     (per-tree splits + leaf class-vote distributions), consumed by
     mobile_app/lib/services/ml_risk_classifier_service.dart for on-device
     inference in pure Dart. See that file's doc comment for why this
     project transpiles the trees instead of shipping a TFLite model.

Follows the manuscript's "Training Method" (Ch. 3): 70/30 stratified
train/test split, Random Forest, and (per "Evaluation Metrics") explicit
attention to High Risk recall, since a missed High Risk case is more
consequential than a false alert.
"""

import json

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
)
from sklearn.model_selection import train_test_split

FEATURE_COLUMNS = [
    "total_screen_time_minutes",
    "daily_limit_minutes",
    "late_night_minutes",
    "longest_session_minutes",
    "restricted_app_attempts_today",
    "rule_violations_7d",
]
LABEL_COLUMN = "risk_label"
CLASS_ORDER = ["Low Risk", "Moderate Risk", "High Risk"]

RANDOM_STATE = 42


def main():
    df = pd.read_csv("output/simulated_usage_dataset.csv")

    x = df[FEATURE_COLUMNS].values
    y = df[LABEL_COLUMN].values

    # 70/30 stratified split (manuscript Ch. 3, "Training Method") -
    # preserves the Low/Moderate/High proportions in both splits.
    x_train, x_test, y_train, y_test = train_test_split(
        x,
        y,
        test_size=0.30,
        stratify=y,
        random_state=RANDOM_STATE,
    )

    # class_weight="balanced" matters here: the dataset is realistically
    # imbalanced (High Risk days are rare, as they should be), and without
    # this the forest can hit high overall accuracy just by defaulting
    # toward "Low Risk" while missing most High Risk cases - exactly what
    # the manuscript's evaluation guidance (prioritize High Risk recall)
    # warns against.
    # n_estimators=60/max_depth=7 chosen over a larger 100/8 grid point
    # after comparing both on this dataset: it gives slightly BETTER High
    # Risk recall (the metric the manuscript's evaluation guidance
    # prioritizes) at a small cost to overall accuracy, and exports a
    # smaller on-device asset. See ml/README.md for the comparison.
    model = RandomForestClassifier(
        n_estimators=60,
        max_depth=7,
        class_weight="balanced",
        random_state=RANDOM_STATE,
    )
    model.fit(x_train, y_train)

    y_pred = model.predict(x_test)

    accuracy = accuracy_score(y_test, y_pred)
    report = classification_report(
        y_test, y_pred, labels=CLASS_ORDER, digits=3, zero_division=0
    )
    cm = confusion_matrix(y_test, y_pred, labels=CLASS_ORDER)

    importances = sorted(
        zip(FEATURE_COLUMNS, model.feature_importances_),
        key=lambda pair: pair[1],
        reverse=True,
    )

    # --- Write the evaluation report (for the manuscript) ---
    lines = []
    lines.append("WellScreen Proposed ML Extension - Random Forest Evaluation")
    lines.append("=" * 60)
    lines.append(f"Dataset: {len(df)} simulated records (see generate_dataset.py)")
    lines.append(
        f"Split: 70% train ({len(x_train)}) / 30% test ({len(x_test)}), stratified"
    )
    lines.append(f"Model: RandomForestClassifier, n_estimators=60, max_depth=7, "
                  f"class_weight=balanced, random_state={RANDOM_STATE}")
    lines.append("")
    lines.append(f"Overall accuracy on held-out test set: {accuracy:.3f}")
    lines.append("")
    lines.append("Classification report (precision / recall / F1 per class):")
    lines.append(report)
    lines.append("Confusion matrix (rows = actual, columns = predicted):")
    lines.append(f"           {'  '.join(f'{c:>13}' for c in CLASS_ORDER)}")
    for actual_label, row in zip(CLASS_ORDER, cm):
        lines.append(f"{actual_label:>10} {'  '.join(f'{v:>13}' for v in row)}")
    lines.append("")
    lines.append(
        "High Risk recall is the metric to watch first - it's the "
        "proportion of actually-High-Risk test records the model "
        "correctly flagged. Missing a High Risk case is worse than a "
        "false alert (manuscript Ch. 3, Evaluation Metrics)."
    )
    lines.append("")
    lines.append("Feature importances (higher = more influence on the model's decisions):")
    for name, importance in importances:
        lines.append(f"  {name:<32} {importance:.4f}")

    report_text = "\n".join(lines)
    with open("output/evaluation_report.txt", "w") as f:
        f.write(report_text)

    print(report_text)

    # --- Export the trained forest as evaluable rules (see file doc comment) ---
    trees_json = []
    for estimator in model.estimators_:
        tree = estimator.tree_
        nodes = []
        for i in range(tree.node_count):
            if tree.children_left[i] == tree.children_right[i]:
                # Leaf node: class-vote distribution (sklearn stores raw
                # sample counts per class at this leaf, in model.classes_
                # order).
                value = tree.value[i][0]
                nodes.append({
                    "leaf": True,
                    "votes": [float(v) for v in value],
                })
            else:
                nodes.append({
                    "leaf": False,
                    "featureIndex": int(tree.feature[i]),
                    "threshold": float(tree.threshold[i]),
                    "left": int(tree.children_left[i]),
                    "right": int(tree.children_right[i]),
                })
        trees_json.append(nodes)

    forest_export = {
        "modelVersion": "risk_forest_v1",
        "trainedOn": "simulated_usage_dataset.csv (synthetic - see generate_dataset.py)",
        "sklearnVersion": __import__("sklearn").__version__,
        "featureOrder": FEATURE_COLUMNS,
        "classOrder": [str(c) for c in model.classes_],
        "testAccuracy": round(float(accuracy), 4),
        "trees": trees_json,
    }

    with open("output/forest_rules.json", "w") as f:
        json.dump(forest_export, f)

    print(f"\nExported {len(trees_json)} trees -> output/forest_rules.json")
    print(f"model.classes_ order (must match Dart's class ordering): {list(model.classes_)}")


if __name__ == "__main__":
    main()
