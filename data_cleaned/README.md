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

- `cleaned_site_categories.csv` - 58,219 domains labeled by category
  (gambling, drugs, dangerous_material, adult), cleaned from real source
  data. gambling/dangerous_material come from UT1 Blacklists (Universite
  Toulouse Capitole, CC BY-SA 4.0); drugs combines UT1's list with a
  second real source, The Block List Project (MIT licensed), added since
  UT1's own drugs list alone was too small to train a reliable ML
  classifier; adult is a separate, much smaller (3-domain)
  Philippines-specific set sourced from real news coverage of the NTC's
  2017 R.A. 9775 blocking order - see `ml/site_category/README.md` for
  full sourcing and why each category is the size it is.
- `cleaning_report.txt` - exact before/after counts: what was removed at
  each cleaning step (IP addresses mixed into the domain list, malformed
  entries, duplicates) and why.

Produced by `ml/site_category/clean_dataset.py`, run against the raw
files in `ml/site_category/raw/`. Full methodology, source attribution,
and honest limitations (imbalanced categories, no self-harm category,
UT1's own 4.6M-domain `adult` category excluded, live URL capture) are
documented in `ml/site_category/README.md` - read that before citing this
dataset anywhere in the manuscript.
