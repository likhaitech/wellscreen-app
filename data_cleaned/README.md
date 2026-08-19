# data_cleaned/

Top-level folder dedicated to **final, cleaned dataset outputs** - kept
separate from the code that produces them (which lives under `ml/`) so
graders/reviewers can find the actual deliverable data without digging
through pipeline scripts.

Each subfolder here corresponds to one dataset-cleaning effort, and holds
only the *output* of that cleaning: the cleaned data file plus its
cleaning report. The raw (pre-cleaning) source files and the script that
produced these live alongside the matching folder under `ml/` - see each
subfolder's note below for the exact path.

## Contents

### `site_categories/`

- `cleaned_site_categories.csv` - 32,704 domains labeled by category
  (gambling, drugs, dangerous_material), cleaned from real UT1 Blacklists
  data (Universite Toulouse Capitole, CC BY-SA 4.0).
- `cleaning_report.txt` - exact before/after counts: what was removed at
  each cleaning step (IP addresses mixed into the domain list, malformed
  entries, duplicates) and why.

Produced by `ml/site_category/clean_dataset.py`, run against the raw
files in `ml/site_category/raw/`. Full methodology, source attribution,
and honest limitations (imbalanced categories, no self-harm category,
`adult` category excluded, live URL capture not yet built) are documented
in `ml/site_category/README.md` - read that before citing this dataset
anywhere in the manuscript.
