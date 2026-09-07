---
title: "Enrollment Measures: DESR vs Classlist"
parent: Developer Guide
nav_order: 21
---

# Enrollment Measures: DESR vs Classlist

CEDAR carries two independent enrollment counts that do not mean the same thing. This page is the full contract; `AGENTS.md` carries the short rule.

CEDAR carries **two independent enrollment counts** that do not mean the same thing. Comparing them — or comparing one measure across terms whose snapshots were taken at different points in the term — silently biases any demand/capacity analysis.

| Measure | Column(s) | Source table | What it is |
|---------|-----------|-------------|------------|
| **DESR enrolled** | `enrolled`, `available` | `cedar_sections` (DESR snapshot) | Section headcount **as of the file pull** (`as_of_date`). Only **one snapshot is retained per term** (a newer DESR replaces the term's rows — see `R/data-parsers/parse-data.R`). |
| **Classlist registered** | `registered` (from `calc_cl_enrls`, `R/branches/enrl.R`) | `cedar_students` | Distinct students in `STATUS_REGISTERED` (RE/RS/RR) — those **still registered** when the classlist was pulled. |

**Neither is a census freeze.** The DESR `CENSUS1`/`CENSUS2` fields are census *dates*, not counts (see [DESR Input Schema](#desr-input-schema-cedar_sections-source)). No census-frozen headcount exists anywhere in the raw data.

**DESR snapshot timing varies by term** (`as_of_date` vs term end), and this is the trap:
- **Upcoming / current term** — retained DESR was pulled during active registration, *before* census → `enrolled` = live, pre-drop count (≈ peak demand).
- **Past terms** — retained DESR was pulled *after* the term ended (backfills run hundreds–thousands of days post-end) → `enrolled` = **final, post-drop** count.

**Empirically, DESR `enrolled` tracks the classlist `registered` (RE/RS/RR) bucket at whatever point the snapshot was taken** (verified Fall 2024 and Fall 2026: per-course median ratio = 1.000). So a past term's DESR enrolled ≈ classlist **final** headcount, while the current term's DESR enrolled ≈ registered ≈ census (they coincide because no drops have happened yet).

## How drops move each number

Reconstruct any lifecycle point from classlist status codes — all emitted by `calc_cl_enrls` (`registered`, `dr_early`, `dr_late`, `dr_all`):

| Lifecycle point | Formula | Includes |
|-----------------|---------|----------|
| **Census / peak headcount** | `registered + dr_late` | everyone present at census (only early drops `DR` removed) |
| **Final / end-of-term headcount** | `registered` | RE/RS/RR still enrolled |
| Total ever-registered | `registered + dr_all` | + early drops |

- **Early drops (`DR`/`DD`, `STATUS_DROP_EARLY`)** occur *before* the grade-consequence deadline → absent from both census and final counts (registration churn / melt). `DD` is treated like `DR`: a drop/delete with full tuition refund.
- **Late drops (`DG`/`DW`, `STATUS_DROP_LATE`)** occur *after* census → **counted at census, gone from the final count.** These are what make a course look *less* saturated at term end than it was at census.

**Canonical census helpers (use these, don't re-derive the formula):** `add_census_enrl(df)` adds `census_enrl = registered + dr_late`. `calc_census_enrl_baselines(df, target_terms, keys, prior_only)` lives alongside it in `R/branches/enrl.R`. Regstats uses `prior_only = TRUE`: each course/term gets a mean, population SD, and count from strictly earlier matching terms. The default `FALSE` preserves the Waitlists all-history reference, excluding selected targets but potentially including later terms. Its count is reference terms, not necessarily prior terms. Both modes retain the full series for sparkline context. Neither reconstruction recovers a frozen census or peak-occupancy snapshot.

**Regstats baseline contract (definition 3.0.0):** group by course, delivery campus,
college, season, and part of term. Enrollment, early/late-drop counts, and fill use
the same prior-only population-SD policy via `add_prior_history_stats()` in
`R/trunk/history-stats.R`. The target and later terms enter neither mean nor SD.
Fewer than two prior observations or zero variation means unscored; show the
coverage counts in `baseline_info`. Drop alerts remain count-selected operational
volume screens; also expose early-drop rate over `first_day_proxy` and late-drop
rate over `census_enrl`, with prior mean rates, so enrollment growth can be
interpreted separately. Rates do not decide the flags. Saturation uses class-list
`census_enrl` over DESR scheduled capacity, requires matched sources and usable
capacity, and retains the enrollment-size floor. Its Full now badge is not an
independent table-entry rule. Regstats and the Dept Dashboard that embeds it have
versioned caches; bump both when these calculations change.

**Fall 2024 magnitude (matched courses):** 10,490 early drops (never in the DESR final) and **5,531 late drops**. The late drops make census headcount ~5% higher than DESR `enrolled` (112,115 vs 107,808).

## Consequence for saturation / capacity analysis

The Saturation report (`R/features/regstats.R`) computes `fill_rate` as class-list
`census_enrl / DESR capacity`. This keeps the lifecycle numerator in one source;
DESR enrollment remains visible only as independently timed snapshot context.
The class-list numerator is reconstructed from final/current statuses rather than
a frozen census roster, and capacity can have a different extract date. The
result is not recovered peak occupancy or registration speed. Unmatched sources
and unusable capacity are excluded and counted in `baseline_info`. The current
fill threshold is user-controlled (90% by default), not a fixed institutional
capacity standard.

To compare like-for-like occupancy, derive fill rate from classlist headcounts at
a single explicit lifecycle point rather than the DESR `enrolled` snapshot.
Census `registered + dr_late` is the right denominator for census occupancy and
attrition reporting, but **not** for deciding whether registration hit a seat
ceiling. Enrollment projections use `classlist_total >= scheduled_capacity` as
the historical registration-capacity signal; later drops cannot erase an
earlier registration constraint, and over-cap overrides do not make the signal
false. Because the class list has no registration timestamps, this is an
operational proxy rather than a recovered peak-occupancy snapshot. Reporting
class-list registrations, census enrollment, and final enrollment together
keeps those lifecycle questions separate.
