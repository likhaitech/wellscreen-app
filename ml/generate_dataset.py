"""
Generates the simulated, labeled training dataset for WellScreen's proposed
Random Forest risk classifier.

Per the approved manuscript (Ch. 3, "Dataset and Training Data Source"):
"The dataset for the future machine learning model may include usage-related
records generated during prototype testing, simulated usage scenarios
created by the researchers, and expert-labeled test cases based on the risk
criteria." This script produces exactly that: simulated daily usage records,
labeled using the manuscript's own official scoring rubric (Table 6,
"USAGE-INDICATOR THRESHOLD AND POINT ALLOCATION", and Table 7, "RISK LEVEL
INTERPRETATION") rather than an invented rule. No real child usage data is
used or required.

IMPORTANT SCOPE NOTE - read before citing this in the manuscript:
Table 6 lists 7 indicators. Only 5 are currently computable by the shipped
WellScreen app today:
  - Daily screen time exceeds the limit   (2 pts) - ScreenTimeGoalService
  - Late-night use                        (2 pts) - PatternDetectionService
  - Prolonged continuous session          (1 pt)  - PatternDetectionService
  - Restricted app attempt (>=3/day)      (2 pts) - RestrictionLogger.kt (blocks)
  - Repeated rule violations (>=3/7 days) (2 pts) - RestrictionLogger.kt (blocks, 7d window)
The remaining 2 are NOT included as model inputs, because the app cannot
supply real values for them yet, and training on a feature that's always 0
at inference time would be misleading, not a genuine capability:
  - Frequent distracting app use (>15 opens/day) - app tracks usage DURATION
    per app, not OPEN/LAUNCH COUNT. Would need a new usage_tracking_service
    capability (Android UsageEvents launch counting) - not built.
  - Harmful website/category attempt - category-level detection is
    explicitly unbuilt (see alerts_reports_screen.dart's own "Not
    implemented yet" note). Faking this would be fabricating a safety
    signal, which is worse than not having it.
Max achievable point total with 5 indicators is 9 (2+2+1+2+2), which still
spans all three of Table 7's bands (0-2 Low, 3-5 Moderate, 6+ High).
"""

import csv
import random

random.seed(42)  # reproducible dataset - re-running this script yields the same data

# 60,000, not 6,000: raised after diagnosing why High Risk recall was only
# ~70% on the original 6,000-record dataset. High Risk records are
# naturally rare (their point rule requires several indicators to fire at
# once - see score_record() below), so at 6,000 records there were only
# ~199 High Risk examples total, ~140 of them in the 70% training split -
# not enough for the forest to learn the pattern reliably. Verified via
# 5-fold cross-validation (not a single lucky train/test split) before
# committing to this: the SAME sampling distributions and the SAME Table
# 6/7 scoring rubric, just generating more records, raised High Risk
# recall from ~71% (6,000 records, ~199 High Risk) to ~84% (60,000
# records, ~2,029 High Risk) - and returns had already flattened out by
# 100,000 records (~84%), so 60,000 was chosen as the point of diminishing
# returns rather than inflating the dataset further for no real gain. No
# change to the labeling rule, the feature distributions, or the label
# noise rate - see ml/README.md's "Model selection" section for the full
# comparison, including hyperparameter and class-weight variants that were
# also tried and did NOT beat plain more-data at this label imbalance.
N_RECORDS = 60000

# Daily limits a parent might realistically configure (minutes). Mirrors
# Table 5's age-based defaults (60 / 120 / 180 min) plus the app's own
# DailyScreenTimeLimitService default of 180 min, plus a lenient 240 min
# option parents sometimes choose.
DAILY_LIMIT_CHOICES = [60, 120, 180, 240]

# Table 6 point values, applied only to the 5 currently-computable indicators.
POINTS_SCREEN_TIME_EXCEEDED = 2
POINTS_LATE_NIGHT = 2
POINTS_PROLONGED_SESSION = 1
POINTS_RESTRICTED_ATTEMPTS = 2
POINTS_RULE_VIOLATIONS_7D = 2

LABEL_NOISE_RATE = 0.04  # see README - simulates real-world labeling imperfection


def sample_record():
    daily_limit_minutes = random.choice(DAILY_LIMIT_CHOICES)

    # Total screen time: right-skewed - most days are moderate, some are
    # very high. Clipped to a plausible 0-600 min (10 hour) daily range.
    total_screen_time_minutes = max(
        0, min(600, int(random.gauss(150, 100)))
    )

    # Late-night minutes: most days 0 (no late-night use); when present,
    # follows a long-tailed distribution.
    late_night_minutes = 0
    if random.random() < 0.22:
        late_night_minutes = max(1, int(random.expovariate(1 / 35)))
        late_night_minutes = min(late_night_minutes, 300)

    # Longest continuous session: usually well under 90 min; occasionally
    # exceeds it.
    longest_session_minutes = max(0, int(random.gauss(40, 35)))
    if random.random() < 0.15:
        longest_session_minutes = max(
            longest_session_minutes, int(random.gauss(120, 40))
        )
    longest_session_minutes = min(longest_session_minutes, 480)

    # Restricted-app attempts today: most days 0, Poisson-ish tail.
    restricted_app_attempts_today = 0
    if random.random() < 0.30:
        restricted_app_attempts_today = min(
            int(random.expovariate(1 / 1.5)) + 1, 15
        )

    # Rule violations within the trailing 7 days: similar shape, slightly
    # higher counts since it's a longer window.
    rule_violations_7d = 0
    if random.random() < 0.35:
        rule_violations_7d = min(int(random.expovariate(1 / 2.2)) + 1, 25)

    return {
        "total_screen_time_minutes": total_screen_time_minutes,
        "daily_limit_minutes": daily_limit_minutes,
        "late_night_minutes": late_night_minutes,
        "longest_session_minutes": longest_session_minutes,
        "restricted_app_attempts_today": restricted_app_attempts_today,
        "rule_violations_7d": rule_violations_7d,
    }


def score_record(r):
    """Applies Table 6's point allocation (5 computable indicators only)
    and Table 7's risk-level bands. Returns (points, label)."""
    points = 0

    if r["total_screen_time_minutes"] > r["daily_limit_minutes"]:
        points += POINTS_SCREEN_TIME_EXCEEDED

    if r["late_night_minutes"] > 0:
        points += POINTS_LATE_NIGHT

    if r["longest_session_minutes"] > 90:
        points += POINTS_PROLONGED_SESSION

    if r["restricted_app_attempts_today"] >= 3:
        points += POINTS_RESTRICTED_ATTEMPTS

    if r["rule_violations_7d"] >= 3:
        points += POINTS_RULE_VIOLATIONS_7D

    if points <= 2:
        label = "Low Risk"
    elif points <= 5:
        label = "Moderate Risk"
    else:
        label = "High Risk"

    return points, label


def main():
    rows = []
    for _ in range(N_RECORDS):
        r = sample_record()
        points, label = score_record(r)

        # Label noise: simulates imperfect expert labeling / borderline
        # cases, per the manuscript's "expert-labeled test cases" framing -
        # a small fraction of records get bumped one band up or down. This
        # is documented, not hidden: a synthetic dataset with zero noise
        # would let the classifier hit ~100% trivially, which would not be
        # an honest representation of real labeling uncertainty.
        if random.random() < LABEL_NOISE_RATE:
            bands = ["Low Risk", "Moderate Risk", "High Risk"]
            idx = bands.index(label)
            shift = random.choice([-1, 1])
            idx = max(0, min(2, idx + shift))
            label = bands[idx]

        r["risk_points"] = points
        r["risk_label"] = label
        rows.append(r)

    fieldnames = [
        "total_screen_time_minutes",
        "daily_limit_minutes",
        "late_night_minutes",
        "longest_session_minutes",
        "restricted_app_attempts_today",
        "rule_violations_7d",
        "risk_points",
        "risk_label",
    ]

    with open("output/simulated_usage_dataset.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    from collections import Counter

    counts = Counter(r["risk_label"] for r in rows)
    print(f"Generated {len(rows)} records -> output/simulated_usage_dataset.csv")
    print("Label distribution:", dict(counts))


if __name__ == "__main__":
    main()
