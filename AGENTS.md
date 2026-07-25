# CEDAR Development Reference

Open-source Shiny analytics platform for higher ed curriculum, enrollment, and student experience at UNM. Primary data sources are Banner/MyReports extracts. Primary audience is IR staff and deans using the Shiny app, with a secondary audience of analysts using the cones directly in RStudio.

**For AI agents doing broad codebase work** — debugging, adding features, understanding architecture, navigating modules, or working across multiple files. This is the comprehensive reference: full architecture, data model, coding standards, module patterns, CSS gotchas, and test infrastructure.

**Instructions for agents:** Trust the layer rules (trunk/branches/cones/reports) and the coding standards sections — they reflect hard-won decisions, not suggestions. The cleanup backlog and refactoring status live in `NEXT-STEPS.md` — check it before touching any file listed there. When in doubt about data structure, the authoritative source is `R/data-parsers/transform-to-cedar.R`.

---

## Architecture Layers

```
app.R                  — 3 lines: loads ui/server, calls shinyApp()
global.R               — data loading, library loading, load_funcs()
ui.R                   — page_navbar() structure; mounts module UIs
server.R               — module wiring + legacy inline handlers
R/lists/               — static constants, domain lookups, grade/status codes
R/trunk/               — pure infrastructure (filter, utils, cache, logging, data I/O)
R/branches/            — reusable cedar domain computations (enrl, grades, cohort)
R/cones/               — single-question analyses; call trunk/branches, never other cones
R/reports/             — orchestrators that call multiple branches/cones and render output
R/modules/             — Shiny UI/server pairs
tests/testthat/        — unit tests for cones and branches
```

**Load order (trunk/load-funcs.R):** lists → trunk → branches → cones → reports → modules.

### Layer rules

| Layer | Calls | Never calls | Test |
|-------|-------|-------------|------|
| lists | nothing | — | Is it a static constant or lookup? |
| trunk | lists | branches, cones, reports | Could this work for a different analytics project? If yes → trunk |
| branches | trunk, lists | cones, reports | Is it called by more than one cone or report? If yes → branch |
| cones | trunk, branches | other cones, reports | Does it answer exactly one analytical question? If yes → cone |
| reports | trunk, branches, cones | — | Does it call multiple cones to assemble output? If yes → report |
| modules | trunk, branches, cones | reports | Is it a Shiny UI/server pair? → module |

**The key rule: cones never call other cones.** If a function needs to call multiple cones, it belongs in `reports/` or `modules/`, not `cones/`.

---

## CEDAR Data Tables

All tables use lowercase snake_case columns. Legacy uppercase names (CAMP, DEPT, TERM) are fully deprecated.
Authoritative schema source: `R/data-parsers/transform-to-cedar.R`.

| Table | Rows (approx) | Key columns |
|-------|--------------|-------------|
| `cedar_sections` | ~50k | `term`, `crn`, `subject_course`, `campus`, `department`, `enrolled`, `total_enrl`, `is_combined`, `is_topics` |
| `cedar_students` | ~1.9M | `student_id`, `term`, `subject_course`, `subject_code`, `course_title`, `level`, `final_grade`, `registration_status_code`, `student_classification`, `student_level`, `student_campus`, `major_code`, `major_name`, `residency`, `dual_credit` |
| `cedar_programs` | ~200k | `student_id`, `term`, `program_name`, `program_code` (Banner), `program_type`, `dept_code`, `college_code`, `student_campus`, `student_college`, `student_population`, `inst_credits_attempted` (UNM-only attempted, cumulative), `overall_credits_attempted` (UNM + transfer attempted, cumulative), `overall_credits_earned` (UNM + transfer earned, cumulative), `pell_eligible` (logical, per-term), `first_gen` (logical, per-term), `ipeds_race`, `gender`, `time_status` |
| `cedar_degrees` | ~20k | `student_id`, `term`, `degree`, `degree_abbr`, `program_name`, `program_code`, `dept_code`, `banner_program_code`, `cumulative_gpa`, `cumulative_credits` |
| `cedar_faculty` | ~5k × terms | `instructor_id`, `term`, `instructor_name`, `department`, `academic_title`, `job_title`, `job_category`, `appointment_pct` (stored 0–100, divide by 100 for FTE), `college`, `as_of_date` |
| `cedar_lookups` | — | Named list: `program_name_lookup` (program_name→dept_code), `dept_name_lookup` (dept_code→display name), `dept_lookup` (raw dept string→dept_code), `college_code_to_name`, `subject_lookup` (tibble: `subject_code`, `dept_code`, `college` — maps subject prefixes to dept codes; invert to get all subject prefixes for a dept_code) |

**`cedar_programs$dept_code`** is derived during transform from `program_map.qs` and the catalog lookups in `R/lists/catalog_lookups.R`:
1. `major_college_to_dept["major_code:college_code"]` — compound key from `program_map` (most accurate)
2. `subj_to_dept[major_code]` — subject code fallback from `subj_dept_map`
3. `major_to_dept[major_code]` — simple program/major fallback from `program_map`
4. `major_code` itself — last resort identity mapping in `cedar_programs` only

`program_map.qs` may contain Banner programs with no defensible academic-department owner yet. Runtime lookup vectors exclude invalid or unmapped rows and collect them in `cedar_mapping_issues`, surfaced under Admin > Data & Usage > Mappings. Reviewed exceptions live in `allowed_unmapped_program_codes` in `R/lists/program_code_maps.R`. Regenerating `program_map.qs` should still fail loudly on new unmapped codes until they are mapped or reviewed.

**`dept_code` ≠ subject prefix in `subject_course`.** For example, Geography has `dept_code = "GES"` but its courses appear as `"GEOG 101"` in `subject_course`. `major_code` in `cedar_programs` is also not a reliable subject prefix. To get subject prefixes for a given dept, use `cedar_lookups$subject_lookup`:
```r
# Subject prefixes for dept "GES" → c("GEOG")
cedar_lookups$subject_lookup %>%
  filter(dept_code == "GES") %>%
  pull(subject_code)
```
Never filter `subject_course` by `dept_code` directly — always go through `subject_lookup`.

**`cedar_students$major`** is the raw Banner program code (e.g., `"NURS"`), not a human-readable name. To get program names or dept_code from it, join against `cedar_programs` or use the validated catalog lookup vectors; do not introduce a new ad hoc program→department map.

**`cedar_sections` course suffix flags:**
- **C suffix** (`BIOL 2110C`): combined lecture+lab course. `is_combined = TRUE`. These are single courses where multiple CRNs appear in the DESR (one per lab section within the combined course), all sharing the same `subject_course`. When counting distinct course offerings, use `n_distinct(subject_course)` — not `n_distinct(crn)` or `n()` — to avoid counting each lab CRN as a separate course.
- **L suffix** (`PHYS 151L`): standalone lab section. No flag — `is_lab` was removed because it was never consumed by any analysis. L-suffix courses appear in enrollment counts like any other course. If exclusion is needed in future, add a filter on `grepl("[Ll]$", course_number)` rather than restoring the flag.

**Term codes:** YYYYSS format. SS = 10 (spring), 60 (summer), 80 (fall). Numeric sort is chronological. E.g., 202510 = Spring 2025, 202560 = Summer 2025, 202580 = Fall 2025.

---

## Registration Status Codes

Defined in `R/lists/status_codes.R`. Use these constants instead of inline strings.

| Constant | Values | Meaning |
|----------|--------|---------|
| `STATUS_REGISTERED` | `c("RE", "RS", "RR")` | Currently registered (RE=enrolled, RS=section change, RR=reserve seat) |
| `STATUS_WAITLIST` | `c("WL")` | Waitlisted |
| `STATUS_DROP_EARLY` | `c("DR")` | Early drop (before deadline, no grade) |
| `STATUS_DROP_LATE` | `c("DG", "DW")` | Late drop (after deadline, grade consequence) |
| `STATUS_DROP_ALL` | `c("DR", "DG", "DW")` | All drops |
| `STATUS_DROP_OTHER` | `c("DD")` | Administrative drop |

---

## Enrollment Measures: DESR `enrolled` vs Classlist `registered`

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

### How drops move each number

Reconstruct any lifecycle point from classlist status codes — all emitted by `calc_cl_enrls` (`registered`, `dr_early`, `dr_late`, `dr_all`):

| Lifecycle point | Formula | Includes |
|-----------------|---------|----------|
| **Census / peak headcount** | `registered + dr_late` | everyone present at census (only early drops `DR` removed) |
| **Final / end-of-term headcount** | `registered` | RE/RS/RR still enrolled |
| Total ever-registered | `registered + dr_all` | + early drops |

- **Early drops (`DR`, `STATUS_DROP_EARLY`)** occur *before* the deadline → absent from both census and final counts (registration churn / melt).
- **Late drops (`DG`/`DW`, `STATUS_DROP_LATE`)** occur *after* census → **counted at census, gone from the final count.** These are what make a course look *less* saturated at term end than it was at census.

**Canonical census helpers (use these, don't re-derive the formula):** `add_census_enrl(df)` adds `census_enrl = registered + dr_late`; `calc_census_enrl_baselines(df, target_terms, keys)` returns the same-term-type historical mean (viewed term(s) excluded), the prior-term count, and the ordered series for a sparkline. Both live in `R/branches/enrl.R`. Enrollment comparisons across terms should flow through these so every tab measures enrollment at the census (peak) point — the regstats **bumps/dips** flags and the **Waitlists** course overview both do.

**Fall 2024 magnitude (matched courses):** 10,490 early drops (never in the DESR final) and **5,531 late drops**. The late drops make census headcount ~5% higher than DESR `enrolled` (112,115 vs 107,808).

### Consequence for saturation / capacity analysis

The Saturation report (`R/reports/regstats.R`) computes `fill_rate` from DESR `enrolled`. Because the current term is measured pre-census and history post-drop, the two are **not the same lifecycle point**:
- **Emerging saturation is inflated** — current pre-drop fill compared against a deflated post-drop historical mean.
- **Chronic saturation is suppressed** — the historical ≥80% test runs on drop-deflated fill.

To compare like-for-like, derive fill rate from classlist headcounts at a single explicit lifecycle point (census `registered + dr_late` is the right denominator for demand/capacity work) rather than the DESR `enrolled` snapshot. Reporting **census fill** and **final fill** side by side also surfaces melt directly — the gap between them.

---

## Grade Constants

Defined in `R/lists/grades.R`. Use these constants for analytics; do not hardcode grade strings in cones.

| Constant | Purpose |
|----------|---------|
| `GRADES_DFW` | Outcomes that count as DFW for analytics (`D`, `D+`, `D-`, `F`, `W`, retake variants) |
| `GRADES_PASS` | Outcomes that count as passing for analytics (C or better, CR, P, S, retake variants) |
| `passing_grades` | Grades that earn credit hours — intentionally excludes D grades; do not use for DFW analytics |

### CEDAR-wide DFW policy

**DFW = D/F/W final grades (`GRADES_DFW`) plus late drops (`STATUS_DROP_LATE`). Early drops (`STATUS_DROP_EARLY`) are NEVER DFW.** This is the standard IR definition and is not negotiable per-cone:

- A **late drop** (DG/DW — after the deadline) is the registration-status form of a W. Most withdrawals in the data post as late-drop status rows, *not* as W grades under a registered status, so any DFW computation that looks only at grades undercounts W.
- An **early drop** (DR — before the deadline) posts no grade. It is registration churn (schedule shuffling, melt), not an academic outcome. Counting it as DFW inflates failure rates with non-failures.
- Early drops are still analytically interesting — track them **separately** (`dr_early`, `n_early_drop`, early-drop rates in `get_course_outcome_rates()`), never folded into DFW.

The canonical classifier is **`classify_enrollment_outcomes()` in `R/trunk/utils.R`** — used by the `cedar_grades` pre-computation (`transform-to-cedar.R`) and by `classify_outcomes()` (`cones/stopout.R`). Do not write a new inline pass/DFW classification; call or extend the canonical one. The legacy gradebook `dfw_pct` (`calculate_dfw()`) already follows this policy: `(failed + late_dropped) / (passed + failed + late_dropped)`, early drops excluded.

---

## Cone Architecture

Each cone is a focused R file in `R/cones/` answering one analytical question. Cones accept CEDAR tables + an `opt` list and return a tibble or named list. No Shiny dependencies, no side effects, no calls to other cones.

**Pattern:**
```r
get_my_analysis <- function(students, opt = list()) {
  # resolve options with %||% defaults
  # call trunk/branch helpers
  # compute and return tibble or named list
}
```

### Branches — Reusable Domain Computations (`R/branches/`)

| File | Main function(s) | Purpose |
|------|-----------------|---------|
| `population.R` | `build_population(programs, degrees, students, opt)` | Build student populations for analysis; returns tibble with `student_id` + classification columns. The central cohort-building function. |
| | `get_focal_programs(programs, opt)` | Resolve program names/codes to canonical list for population filters |
| | `build_demographic_population(programs, opt)` | Population scoped by demographic characteristics |
| | `get_ongoing_ids()`, `get_graduated_ids()`, `get_switched_out_ids()`, `get_never_declared_ids()` | Sub-classifiers used internally by `build_population()` |
| | `get_entry_pathways()`, `classify_origin()`, `classify_entry_method()`, `classify_entry_status()` | Entry-type classification helpers |
| `comparison.R` | `build_comparison(treatment_ids, pool_ids, programs, ...)` | Build treatment/control groups for observational analyses; joins covariates from `cedar_programs` |
| | `compute_balance(groups)` | Report covariate balance between treatment and control |
| `enrl.R` | `calc_cl_enrls(students)`, `get_enrl(sections, opt)` | Enrollment counts and stats |
| | `get_course_section_counts(sections)` | Active section count + total enrollment per course, crosslist-deduplicated. Returns one row per (term, subject_course, course_title, campus). Join on those four columns. Reusable in any tab, report, or API endpoint that needs a "how many sections / how many students" summary without running a full enrollment pipeline. |
| | `get_low_enrollment_courses(courses, opt, threshold)` | Sections below a threshold, filtered and deduplicated via `filter_DESRs()` |
| `course-attempts.R` | `prepare_course_attempts(students, opt)` | Shared cleaned course-attempt rows for grade/outcome analyses. New cones usually should not call this directly unless they need row-level attempts |
| | `get_course_outcome_rates(students, opt, group_cols, min_n)` | Preferred cone API for DFW, W, D/F, C-, below-C, and early-drop metrics |
| | `get_grade_distribution(students, opt, group_cols, min_n)` | Preferred cone API for A/B/C/D/F/W/Other grade distributions |
| `gradebook.R` | `get_grades(students, opt)`, `add_instructor_type(grades, cedar_faculty)` | Legacy/report grade bundle; keep for Course Report and Dept Report compatibility, but do not use for new cones unless the full legacy bundle is required |
| `demographics.R` | `summarize_student_demographics(filtered_students, opt)` | Flexible demographic summary grouped by `opt$group_cols` (counts, term-type means, pct of course enrollment). Used by course-demographics and waitlist cones |
| `headcount.R` | `get_headcount(programs, opt)` | Student enrollment counts by program |
| `credit-hours.R` | `get_credit_hours(students, opt)` | Credit hour production |
| `degrees.R` | `count_degrees(degrees, opt)` | Degree completion counts |
| `course-flows.R` | `get_next_course_pairs(students, opt, source_courses)`, `get_previous_course_pairs(students, opt, target_courses)` | Campus-scoped source→destination course pairs across adjacent terms. Course sequencing always joins and groups by campus so students at different campuses are never treated as one flow |
| | `get_course_destinations()`, `get_course_feeders()`, `get_concurrent_courses()`, `get_course_flow_neighbors()` | Summaries of what students take after / before / alongside a course; `get_course_flow_neighbors()` returns the combined named list |
| `pathways.R` | `pathways_level_filter()`, `pathways_observation_boundary()`, `apply_pathways_population_window()`, `resolve_pathways_focal_programs/dept_codes/subjects()` | Pure result-shaping helpers for the Pathways module — calculation-affecting rules kept testable without loading Shiny |

### Cones — Single-Question Analyses (`R/cones/`)

| File | Main function(s) | Takes cohort? | Purpose |
|------|-----------------|---------------|---------|
| `bottleneck.R` | `get_bottlenecks(cohort, students, opt)` | ✓ | Waitlist pressure / unmet enrollment demand |
| `stopout.R` | `get_stopout(students, cohort, opt)` | ✓ | Stop-out rate gap after DFW vs. passing |
| `pathway.R` | `get_course_timing(students, cohort, opt)` | ✓ | When cohort students take each course |
| | `plot_curriculum_map(timing_data, opt)` | — | Heatmap of course timing |
| | `get_course_pairs(students, cohort, opt)` | ✓ | Ordered A→B course sequences |
| `course-impact.R` | `get_course_retention(students, programs, applicants, opt)` | — | Observational: did students who took course X persist longer than comparable students who didn't? Returns survival-style tibble with +1/+2/+3 semester persistence rates for treatment vs. control |
| | `get_course_sequence_effect(students, programs, applicants, opt)` | — | Observational: do students who took X before Y earn better grades in Y? Treatment/control via `build_comparison()` |
| | `get_instructor_effect(students, programs, applicants, opt)` | — | Observational: did instructor A's students outperform instructor B's in a downstream course? |
| `course-neighbors.R` | `where_to(students, opt)`, `where_from(students, opt)` | — | Course flow analysis: what do students take next / before |
| | `plot_course_sankey_by_term_with_flow_counts(to_courses, from_courses, opt)` | — | Sankey diagram of course flows |
| | `where_at(students, opt)` | — | Concurrent enrollment: what else are students taking with this course |
| | `plot_whereat_trends(whereat_data, opt)` | — | Trend plot for concurrent enrollment |
| | `get_course_neighbors(students, opt)` | — | Combined where_to / where_from / where_at summary |
| `seatfinder.R` | `seatfinder(students, courses, cedar_faculty, opt)` | — | Seat availability analysis across terms; returns named list of course comparison tibbles |
| `waitlist.R` | `inspect_waitlist(students, opt, sections = NULL)` | — | Waitlist counts by course/major; `sections` only needed if students lack `course_title` |
| `course-outcomes.R` | `get_course_outcomes(students, cedar_faculty, opt)` | — | Returns named list: `persistence` (next-term return rates by grade), `dfw_trend` (DFW rate by term), `instructor_dfw` (per-instructor vs. course avg). `cedar_faculty` is optional; omitting it skips instructor breakdown |
| | `next_term_persistence(filtered, all_students, opt)` | — | By grade outcome, % who returned next term |
| `population-trend.R` | `make_population_trend(programs, opt)` | — | Entry type distribution over time |
| `major-changes.R` | `detect_major_changes(programs, cohort, opt)` | ✓ | Detect term-over-term major changes |
| | `tag_major_changers(programs, cohort, opt)` | ✓ | Boolean flag per student: ever changed? |
| | `time_to_first_change(programs, cohort, opt)` | ✓ | Terms from first enrollment to first change |
| | `avg_credits_before_major(changes, opt)` | — | Avg credits when arriving in each major |
| | `majors_moved_out_of(changes, opt)` | — | Most-departed majors by frequency |
| | `major_change_pathways(changes, opt)` | — | Common A→B transition pairs |
| | `pathways_by_college(changes, opt)` | — | A→B pathways broken out by college |
| | `get_major_change_courses(changes, students, opt)` | — | Courses taken during change terms |
| `course-retention.R` | `get_retention_comparison(students, opt, degrees)` | — | Descriptive next-term retention rates compared across courses (raw rates, not treatment/control) |
| | `get_retention_trend(students, opt, degrees)` | — | One course's retention rate over time |
| | `get_dept_retention_trend(students, opt, degrees)` | — | Dept-level retention trend |
| `course-demographics.R` | `get_course_demographics(students, opt)` | — | Major/classification breakdown per course |
| `sfr.R` | `get_permanent_faculty_fte(faculty, opt)` | — | Faculty FTE by dept |
| `gened-fulfillment.R` | `get_gened_fulfillment(...)` | — | Gen ed area fulfillment by major |
| `cancellations.R` | `get_cancellations(sections, opt)` | — | Cancelled sections (section status "C") plus summary tables for Explore > Cancellations; related non-active statuses counted separately for context |
| `gen-ed-conversion.R` | `get_gen_ed_conversion(students, programs, opt)` | — | Sankey flows from a student's program at the time of a gen-ed course to their last recorded program (graduated / stopped-out labeled); flows below `opt$min_n` collapsed into "Other" |
| | `get_course_major_associations(students, programs, opt)` | — | Course → eventual-major association table |
| `health-whatif.R` | `get_health_course_rates(programs, students, program_names, ...)` | — | Weighted course-taking rates per (program, course, term_type) for health programs: steady-state (`rate`) and new-entrant (`entry_rate`) weightings. Powers the Admin > Healthcare tab |
| | `project_health_increase(rates, sizes, ...)`, `get_section_size_lookup(sections, ...)` | — | What-if projection: seat and section demand implied by program enrollment increases |
| | `get_premajor_pipeline()`, `get_health_course_trends()`, `get_course_pressure()`, `get_actual_course_demand()`, `get_enrollment_matrix()` | — | Supporting pipeline / trend / pressure / demand views for the Healthcare tab |
| `forecast/` (subdir) | `forecast(students, courses, opt)` (`forecast.R`) | — | Course enrollment forecasting orchestrated across methods; the only cone subdirectory — methods split one per file |
| | `major_forecast()` (`method-major.R`), `conduit_forecast()` (`method-conduit.R`) | — | Forecast methods: declared-majors-based and feeder-course ("conduit") |
| | `calc_forecast_accuracy()` (`forecast-stats.R`) | — | Forecast accuracy statistics |

### Grade Data In Cones

For new cones, use the focused grade APIs instead of the legacy gradebook bundle:

- Use `get_course_outcome_rates()` for DFW, W, D/F, C-, below-C, and early-drop metrics. It returns a tidy table with stable columns such as `n_attempts`, `n_pass`, `n_c_minus`, `n_d`, `n_f`, `n_w`, `n_early_drop`, `dfw_pct`, `w_pct`, `df_pct`, and `below_c_pct`.
- Use `get_grade_distribution()` for A/B/C/D/F/W/Other counts and percentages.
- Use `prepare_course_attempts()` only when the cone needs row-level cleaned attempts.
- Do not call `get_grades()` from a new cone unless the cone explicitly needs the legacy report bundle (`counts`, `dfw_summary`, `course_inst_avg`, `course_term`, `course_avg`, `course_avg_by_term`).
- `dfw_pct` intentionally preserves the legacy gradebook policy in phase 1: `(failed + late_dropped) / (passed + failed + late_dropped) * 100`, where `failed` includes C- and other non-passing, non-W grades.

### New cone checklist

When adding a new cone in `R/cones/`:

- Cones answer one analytical question and never call other cones.
- Accept CEDAR tables plus `opt = list()` as the final argument.
- Validate all required input columns up front and stop loudly if any are missing.
- Reuse trunk/branch helpers such as `filter_DESRs()` and `filter_class_list()`.
- If using `filter_DESRs()`, immediately call `dplyr::ungroup()` on the result before downstream `count()`, `summarize()`, `mutate()`, or `group_by()`. `filter_DESRs()` may return grouped data.
- Define an explicit output contract. Do not append `dplyr::everything()` unless the cone documents that it intentionally returns pass-through columns.
- Use `cedar_debug()` for key row counts and branch points. If the cone may be sourced standalone, guard debug calls with `exists("cedar_log_level") && cedar_log_level == "DEBUG"`.
- Use `%||%` for optional `opt` defaults.
- Do not silently recover from missing schema, malformed inputs, or empty joins that should be impossible.
- Add focused tests using committed fixtures or `fixtures/designed_test_data.R`; do not create inline test tibbles.

### Reports — Orchestrators (`R/reports/`)

Reports call multiple branches/cones and assemble output. They follow different rules than cones: they may call other cones. Only `dept-report.R` still renders an Rmd (the downloadable department report, retained for shared consultation); every other report feeds the app directly. See ROADMAP Theme 5 for the surface-portfolio decision.

| File | Main function(s) | Purpose |
|------|-----------------|---------|
| `course-report.R` | `create_course_base_data(data_objects, opt)`, `compute_cr_flows_tab()`, `compute_cr_dfw_tab()`, `compute_cr_outcomes_tab()` | Assembles enrl + gradebook data for the Course Dynamics tab; flows/DFW/outcomes computed lazily per sub-tab |
| `gen-ed.R` | `get_gen_ed_profile(students, sections, programs, degrees, opt)` | Gen Ed profile (scope filtering, outcome rates, grade distribution, major mix) for Explore > Gen Ed and the Dept Profile Gen Ed panel |
| `dept-dashboard.R` | `create_dept_dashboard_data(...)` | Dashboard metrics and plots for one dept (assembles headcount, enrl, credit-hour trends) |
| | `get_subject_current_stats(sections, subject, term)` | Lightweight current-term snapshot: returns `list(n_sections, total_enrl)` for a subject, crosslist-deduplicated. No full dashboard pipeline. Reusable in dashboard cards, comparison views, future API endpoints. |
| `dept-report.R` | `get_dept_report_data(...)` | Assembles headcount + degrees + credit-hours + gened → HTML/ASPX |
| `regstats.R` | `get_reg_stats(students, courses, opt)` | Enrollment anomaly detection (calls enrl, course-demographics, waitlist branches) |
| | `filter_downstream_by_dept(downstream_df, dept, sections)` | Filters downstream registration signals (dest_course pairs) to only destinations in a given dept's subjects. Pass empty/NULL dept to return all rows unchanged. Eliminates a DRY violation — was duplicated in two server.R render blocks. Reusable in any downstream signals display. |

---

## Population Architecture

A population is a tibble of `student_id`s (plus classification columns) built by `build_population()` in `R/branches/population.R` and passed to any population-aware cone. Population building is completely separate from analysis — cones accept a `population` argument and don't care how it was constructed.

**Before working in this code, read the CONCEPTS block at the top of `R/branches/population.R`.** It defines the shared ontology every Pathways analysis assumes: the six outcomes and their precedence (and why `stopped_out` is a residual, not a detection), the three independent entry axes (`origin` / `entry_method` / `entry_status`), the six per-student timestamps with a worked timeline, the `relevant_until` enrollment-ceiling contract, and the two data-boundary (censoring) rules.

```r
# Build once
population <- build_population(cedar_programs, degrees = cedar_degrees, students = cedar_students,
  opt = list(
    focal_names        = c("Nursing", "Radiologic Sciences"),
    pre_major_names    = c("Biology", "Biochemistry"),
    include_pre_majors = "split"   # "majors_only" | "pre_only" | "lump" | "split"
  ))

# Pass to any population-aware cone
get_bottlenecks(population, cedar_students, opt = list())
get_stopout(cedar_students, population, opt = list())
get_course_timing(cedar_students, population, opt = list())
```

**Key `build_population()` options:**
- `focal_names` — program names to treat as the primary group
- `pre_major_names` — feeder/pre-major programs
- `include_pre_majors` — `"majors_only"` (default), `"pre_only"`, `"lump"`, `"split"`
- `campus` — restrict by `student_campus`
- `term` — restrict to a specific term's program declarations

**Cone parameter name:** Population-aware cones use `population` as the argument name (not `cohort`). Check the function signature before passing — e.g. `detect_major_changes(programs, population = NULL, opt)`.

**`population$first_unit_term` is scoped to the focal programs.** It is the first term each student appeared in a focal program record (e.g., Geography). Do NOT re-derive entry terms by querying `programs %>% filter(student_id %in% focal_ids) %>% group_by(student_id) %>% summarize(entry_term = min(term))` — that picks up ALL of a student's program history across every major they ever held, not just the focal program. Use `population$first_unit_term` directly instead.

**Adding a new population type:** Add a `build_X_population(programs, opt)` helper in `population.R` and wire into `build_population()`. The Shiny wiring lives in `R/modules/pathways.R` (`populationSelectorUI` / `populationSelectorServer`).

**Observational comparisons:** When you need treatment/control groups (e.g., took course X vs. didn't), use `build_comparison()` and `compute_balance()` from `branches/comparison.R`. See `course-impact.R` for the reference pattern.

---

## Trunk Helpers

Always check these before writing equivalent logic in a cone or branch.

### `R/trunk/utils.R`

| Function | Purpose |
|----------|---------|
| `add_next_term_col(df, term_col, summer=FALSE)` | Adds `next_term` column; required by `get_stopout()` |
| `add_prev_term_col(df, term_col, summer=FALSE)` | Adds `prev_term` column |
| `add_acad_year(df, term_col)` | Adds `acad_year` like `"2024-2025"` |
| `add_term_type_col(df, term_col)` | Adds `term_type`: `"spring"`, `"fall"`, `"summer"` |
| `add_term_bins(df, term_col)` | Groups terms into bins for trend analysis |
| `term_diff(from, to, include_summer=FALSE)` | Number of terms between two term codes |
| `fmt_term(term_code)` | `202580` → `"Fall 2025"` |
| `term_code_to_str(term_code)` | Alternate term label formatter |
| `academic_period_to_term(label)` | `"Fall 2025"` → `202580` |
| `make_term_sequence(start_year, end_year)` | Vector of term codes for a year range |
| `get_dept_from_course(course)` | `"BIOL 2310"` → `"BIOL"` |
| `validate_population(population, caller)` | Validates population has required columns; call at top of any cone that accepts a population argument |
| `term_diff(from, to, include_summer)` | Count terms between two term codes (YYYYSS integers) |
| `compute_trend(values, min_n=2, threshold=0)` | Canonical slope/direction helper: returns `list(slope, direction, arrow)` for an oldest→newest numeric vector (NAs dropped). Use instead of hand-rolling `coef(lm(v ~ seq_along(v)))`. Note a perfectly flat series needs a small `threshold` to read as `"stable"` rather than float-noise up/down. |
| `compute_windowed_trend(series, all_main_terms, top_n_terms)` | Computes `recent_avg`, `pct_1yr/2yr/4yr`, `abs_change_1yr`, `is_emerging` for a single time series (a tibble with `term` and `value` cols). Use with `group_modify` for per-course trend indicators — e.g. enrollment trend for each course in `cedar_cl_enrls_base`. Already used by `credit-hours.R`. **Do not use with `group_modify` over course pairs** (source→dest): thousands of groups × R closure overhead = multi-minute hang. For course-pair trends, use vectorized `group_by + summarize` instead. |

### `R/trunk/filter.R`

| Function | Purpose |
|----------|---------|
| `filter_DESRs(sections, opt)` | Standard filter for cedar_sections (campus, college, dept, term, level, etc.) |
| `filter_class_list(students, opt)` | Standard filter for cedar_students |
| `filter_by_col(data, col, val)` | Generic single-column filter |
| `filter_by_term(data, term, term_col)` | Filter to specific term(s) |
| `filter_out_summer(data, term_col)` | Remove summer terms |
| `filter_data(df, opt, opt_col_map)` | General-purpose opt-driven filter |
| `keep_home_sections(sections)` | Crosslist de-dup: keep each group's home/internal section + all non-crosslisted rows, so a course counts once. Use instead of inlining `is.na(crosslist_group) \| crosslist_role %in% c("home","internal")`. |

`filter_class_list()` handles the common pattern of filtering cedar_students by campus, dept, term, level, registration status, etc. Use it rather than reimplementing in cones.

### Filter / dplyr Gotchas

- `filter_DESRs()` may return grouped data. Always call `dplyr::ungroup()` immediately after using it inside cones before `count()`, `summarize()`, `group_by()`, or downstream joins.
- Do not use scalar `&&` or `||` inside `dplyr::filter()` when the right-hand side is row-vector logic. It will try to coerce a whole column-length vector to one TRUE/FALSE and fail on real data. Branch outside the pipeline or use vectorized `&` / `|`.
```r
# Preferred when the filter is optional
filtered <- df %>%
  {
    if (length(seasons) == 0) .
    else dplyr::filter(., term_type %in% seasons)
  }
```
- If a summary table intentionally uses a different filter scope than the main result (e.g., Trends ignores exact term-code filters but retains Fall/Spring/Summer filters), compute it as a separate named output in the cone and document that behavior in the module caption or scope stripe.
- When filtering by status codes, set the status option explicitly for each separate filter pass. Do not assume a copied `opt` object shares later mutations.

---

## Caching

Several expensive computations are cached to disk. The general infrastructure
lives in `R/trunk/cache.R` (course-neighbors, dept-profile tabs, population
benchmarks); the Regstats dashboard keeps its own cache in
`R/reports/regstats.R`. All of them follow the same shape: a `get_*_cache_key()`
(or `create_*_cache_filename()`) builds a key, save/load helpers read and write
`.qs`/`.Rds` files under `get_cache_dir()`, and a miss returns `NULL` so the
caller recomputes.

**The cardinal rule: the cache key must encode every input that changes the
result.** If a filter, option, or data version can change the output but is not
part of the key, two different requests collide on the same cache entry and the
second silently gets the first's result — the filter appears dead even though
the compute path is correct. This is exactly how the Regstats Part-of-Term
filter broke: `create_regstats_cache_filename()` omitted `pt`, so changing PoT
reused a stale cache file. When you add a new filter/option to a cached feature
(especially a new Regstats input), add it to that feature's key function in the
same change, and verify the key string actually changes when the input changes.

What a key must cover:
- **All result-affecting filters/options** — every `opt` field the computation
  reads. Prefer hashing the whole relevant option set over hand-listing keys:
  `get_population_benchmark_cache_key()` digests `list(version, term, college,
  opt)`, which can't silently under-specify. The hand-built readable filename in
  `create_regstats_cache_filename()` is easy to under-specify — that's what bit
  us; if you keep that style, treat the key builder as correctness-critical.
- **Data freshness** — so a stale entry can't outlive the data. Existing choices:
  a data hash (`cedar_students_hash` / `cedar_sections_hash` in course-neighbors),
  the current term (`cedar_current_term` / `cedar_report_end_term`), or an ISO
  week for auto-expiry (`dept_*` keys expire each Monday). Pick the one whose
  granularity matches how the underlying data moves.
- **A manual version counter** (e.g. `cedar_population_benchmark_cache_version`)
  — bump it whenever you change the *shape or logic* of the cached output so old
  files aren't served. A key that only covers inputs won't invalidate when you
  change the computation itself.

Other conventions in use, worth matching:
- Loads return `NULL` on miss/error and the caller recomputes. This is a
  documented supported state, **not** a silent fallback (see Coding Standards) —
  the "no fallbacks" rule is about masking *errors*, and a cache miss is not one.
- Non-standard requests may bypass the cache entirely rather than pollute it —
  Regstats skips the cache when custom thresholds are set (`using_custom_thresholds`).
- Write atomically (`.tmp` then `file.rename`) and store only serialisable
  tables/config — not plots or live `data_objects` — rebuilding the rest on load.
- `clear_all_caches()`, `clear_dept_cache()`, and `clear_course_cache()` exist
  for manual invalidation; reach for a version bump or a data-hash/term/week key
  before relying on manual clears.

---

## Shiny Module Pattern

Introduced with the Pathways tab. Use for all new feature tabs. Do not refactor existing inline tabs unless there's a separate reason to touch them.

**Reference implementation:** `R/modules/pathways.R`

```
R/modules/pathways.R
  populationSelectorUI(id, campus_choices, program_choices = character(), ...)
  populationSelectorServer(id, programs, degrees = NULL, students = NULL, ...)
                                        → returns reactive population tibble
  pathwaysUI(id, campus_choices, program_choices = character(), ...)
  pathwaysServer(id, students, programs, degrees = NULL, ...)
```

### Module inventory

| File | UI / server pairs | Mounted at |
|------|-------------------|------------|
| `pathways.R` | `pathwaysUI/Server`, `populationSelectorUI/Server` | Pathways |
| `headcount.R` | `headcountUI/Server` | Explore > Headcount |
| `seatfinder.R` | `seatfinderUI/Server` | Explore > Open Seats |
| `cancellations.R` | `cancellationsUI/Server` | Explore > Cancellations |
| `waitlist.R` | `waitlistUI/Server` | Explore > Waitlists |
| `gen-ed.R` | `genEdExploreUI/Server`, `deptProfileGenEdUI/Server` | Explore > Gen Ed; Dept Profile Gen Ed panel |
| `regstats.R` | `regstatsUI/Server` | Regstats |
| `health-whatif.R` | `healthWhatIfUI/Server` | Admin > Healthcare |
| `retention.R` | `retentionUI/Server` | **Hidden** — UI commented out in ui.R pending cross-course comparison (`retentionServer` is still wired in server.R); course-level retention lives in Course Dynamics |
| `admin.R` | `changelogUI/Server`, `cacheUI/Server` | Admin (changelog + cache management) |
| `ui-helpers.R` | shared UI primitives, not a module: `filter_bar`, `filter_scope_stripe`, `info_panel`, `empty_state`, `section_block`, `dept_selector_bar`, …; plus shared table pieces `cedar_tbl_theme` (the reactable theme every table uses) and `cedar_pot_coldef()` (standardized Part-of-Term column) | used across modules and ui.R |

**Layout pattern:**
```r
pathwaysUI uses layout_sidebar():
  sidebar (width=320, always open) — cohort builder
  main content — navset_tab with analysis panels
```

**Wiring in ui.R / server.R:**
```r
# ui.R
nav_panel("Pathways", icon = icon("route"),
  pathwaysUI("pathways", program_choices, campus_choices))

# server.R
pathwaysServer("pathways", cedar_students, cedar_programs)
```

**CEDAR data is in `data_objects`, not bare globals.** All CEDAR tables and lookups live in `data_objects[["cedar_X"]]` — they are NOT available as bare globals inside module server functions. Always pass them explicitly as module parameters:
```r
# Wrong — cedar_lookups is not in scope inside a module
pathwaysServer("pathways", cedar_students, cedar_programs)

# Right — pass via data_objects
pathwaysServer("pathways", cedar_students, cedar_programs,
               lookups = data_objects[["cedar_lookups"]])
```
The same applies to any other lookup or table a module needs that isn't already in its parameter list.

**Rules for new modules:**
- One file per module in `R/modules/`
- Four functions per module: `fooUI`, `fooServer`, plus any internal sub-modules
- Source in `load-funcs.R` after cones (section 5)
- `pathwaysServer` shows the correct pattern: errors caught with `tryCatch` + `showNotification()`, large choice lists sent server-side via `updateSelectizeInput(server = TRUE)`. Wrap slow operations in `withProgress()` for new modules (currently no module does — restore the pattern when touching one)
- Never put business logic in a module — call cone functions. Modules are wiring only.

**New Shiny module checklist:**
- Keep business logic out of the module; call cones, branches, or reports.
- Pass all CEDAR data explicitly from `server.R`; do not rely on bare globals inside modules.
- Source the module in `R/trunk/load-funcs.R` after cones.
- Wire UI in `ui.R` and server in `server.R`.
- If adding an Explore-tab tool modeled on Open Seats or Regstats, copy the full run pattern, not just the filters:
  - loading overlay in the module UI
  - `start_report_timer()` / `end_report_timer()`
  - `session$sendCustomMessage("*_load_complete", ...)`
  - URL copy and autorun support
  - app-level error handling passed from `server.R` when needed
- Do not call `handle_error()` from a module unless it is passed in as a parameter or otherwise known to be in scope.
- If using URL autorun, register the tab in `CEDAR_SHARE_SPECS` (`R/trunk/url-state.R`) and add its slug to `tab_aliases` (`server.R`), plus the client-side tab map in `ui.R`. See "URL deep links & shareable state" below. (`tab_prefixes` / `button_overrides` no longer exist — `CEDAR_SHARE_SPECS` replaced them.)
- Match existing table styling. If one helper renders multiple table shapes, allow per-table column definitions instead of relying on raw snake_case defaults.

### Module UI Gotchas From Cancellations

**Tables are user interfaces, not raw cone dumps.**
- Keep the cone return contract broad enough for analysis, but make each Shiny table choose an explicit display-column order.
- Put workflow/context columns first: campus, college, term, course, title, CRN/section, then metrics/dates.
- If users ask to hide fields, hide them in the module display `select()`, not by removing them from the cone output.
- If one `make_reactable()` helper serves multiple table shapes, either pass table-specific `columns =` or filter the column definitions before calling `reactable()`:
```r
columns <- columns[names(columns) %in% names(df)]
```
Reactable errors if `columns` includes names not present in `data`.
- For narrow inspection tables, use `fullWidth = FALSE` so striped rows do not stretch across the whole viewport. Keep wide raw-data tables full width.
- Sort inspection tables in the order users scan them. For trend backing tables, prefer chronological term, then descending count, then label.
- **Part-of-Term columns use the shared `cedar_pot_coldef()` helper** (`ui-helpers.R`), never a hand-rolled colDef. It renders `1` → "Full", blank/`NA` → "—", and half/nonstandard terms (`1H`, `2H`, `INT`, …) in semibold, so the label and cell treatment stay identical across tabs (regstats, seatfinder, cancellations, …). Any new table with a `part_term` column should call it.
- **`cedar_tbl_theme` uppercases every header** (`textTransform: uppercase`). A header that must keep mixed case — e.g. "PoT" rather than "POT" — has to override it with `headerStyle = list(textTransform = "none")` on its colDef. `cedar_pot_coldef()` already does this; hand-rolled colDefs that set `name = "PoT"` will silently render "POT".

**Plotly is preferred when hover detail matters.**
- CEDAR already loads `plotly`; use `plotlyOutput()` / `renderPlotly()` for charts where users need tooltips or dense drill-down detail.
- Keep chart labels quiet. Use `hovertext = ~...` plus `hoverinfo = "text"` for tooltip-only content. Do not use `text = ~...` unless you actually want labels printed on the plot; Plotly may render it visibly on bars.
- For stacked plots with many departments/units, show the top N units and collapse the rest to `"Other"` for color readability. Put the `"Other"` breakdown in hover text and expose the plotted data in a table underneath.
- Strip names from vectors before sending them to Plotly or Shiny JSON when they are intended as arrays:
```r
term_levels <- pull(df, term_label) |> unname()
colors <- as.list(unname(palette[seq_along(unit_levels)]))
names(colors) <- unit_levels
```
Named atomic vectors can trigger jsonlite warnings such as `Input to asJSON(keep_vec_names=TRUE) is a named vector`.
- Use lists, not named atomic vectors, for UI choice objects or JSON payloads when they need object semantics. Example: `choices = as.list(dept_choices)`.

**Selectize and CSS need special care.**
- Shiny/selectize copies Bootstrap classes onto generated wrappers and dropdowns. A selectize dropdown can have both `.selectize-dropdown` and `.form-control`.
- Do not style all `.filters-compact input[type=text]`; Selectize's tiny internal search input is also a text input and will become a stray bordered one-line box.
- Filter-bar form-control rules should exclude both Selectize wrappers and Selectize dropdowns:
```css
.filters-compact .form-control:not(.selectize-control):not(.selectize-dropdown) { ... }
```
- Reset Selectize internals separately:
```css
.selectize-control.form-control { border: none; padding: 0; background: transparent; }
.selectize-dropdown.form-control { height: auto; padding: 0; }
.selectize-input > input { border: none; padding: 0; box-shadow: none; }
```
- When CSS differs across tabs, inspect the live generated DOM. The same Shiny input type can render with different copied classes depending on `selectInput()` vs `selectizeInput()` and module/server-side setup.

**Loading and empty states.**
- Use the current modal/overlay pattern from Open Seats/Regstats; do not resurrect old notification-only loading protocols.
- Center loading overlays with a fixed-position overlay selector for the module ID.
- Always show a clear blue info callout when a run succeeds but returns no rows for the selected criteria. If a secondary tab intentionally ignores one filter (e.g., Trends ignoring exact term codes), do not hide useful secondary results just because the primary table is empty.

**Input values must match actual data values.** Always check the data parser (`R/data-parsers/transform-to-cedar.R`) or existing filter usage before hardcoding `choices =` in a `selectInput`. Display labels and data values often differ — e.g., the Level field stores `"lower"`, `"upper"`, `"grad"` in the data, not `"undergrad"`. If a UI label like "Undergrad" maps to multiple data values, do the mapping in the server (`opt$level <- c("lower", "upper")`), not in the `choices` vector.

**Refactoring strategy for existing tabs:**
- Do not refactor the remaining inline server.R tabs unless touching them for a separate reason. The `enrl_data` reactive feeds 8+ output handlers and has non-obvious shared state.
- Headcount has been extracted to `R/modules/headcount.R` — use it (with pathways.R) as the extraction template. See `NEXT-STEPS.md` for the recommended extraction order of the remaining inline tabs.

### URL deep links & shareable state

One registry, `CEDAR_SHARE_SPECS` in `R/trunk/url-state.R`, drives BOTH directions of the shareable-URL round-trip so they can't drift. Each entry is keyed by the exact navbar tab title and declares `slug` (the `?tab=` value), `prefix`/`sep` (how a namespaced input id is built), `run` (the run button), optional per-key `types` (restore widget kinds), and optional `aliases`.

- **Copy (build a link):** a module wires `cedar_copy_url_observer(input, session, copy_id, values_fn, spec_title = "…")`. On click it builds `?tab=<slug>&autorun=true&k=v…` via `cedar_share_query()` and copies it (the `copy_cedar_url` handler in `ui.R`).
- **Restore (load a link):** the single `observeEvent(session$clientData$url_search, …, once = TRUE)` in `server.R` resolves the tab and calls `cedar_restore_from_query(session, query, tab_name)`, which dispatches each param by its declared `type` and, if `autorun=true`, clicks the run button after a 0.5s delay (so input round-trips land first).
- Registering a new deep-linkable tab means: add a `CEDAR_SHARE_SPECS` entry, add the slug to `tab_aliases` in `server.R`, and add the client-side tab map in `ui.R`.

**Server-side selectize (`server = TRUE`) needs an extra step.** A module that populates a large selectize with `updateSelectizeInput(server = TRUE)` **re-initializes** that widget, which wipes any value the restore injected separately — the value flashes in and vanishes, and the autorun reads an empty input. Fix: bake the deep-linked value into that SAME init as `selected`, using `cedar_url_restore_value(root_session, spec_title, key)`, inside `observeEvent(<root>$clientData$url_search, …, once = TRUE)`:

```r
observeEvent(parent_session$clientData$url_search, {
  updateSelectizeInput(session, "wl_course",
    choices  = sort(unique(students$subject_course)),
    selected = cedar_url_restore_value(parent_session, "Waitlists", "course"),
    server   = TRUE)
}, once = TRUE)
```

- `clientData$url_search` is only reliable **inside a reactive context** (`observe`/`observeEvent`), never read synchronously in the server body — a synchronous read is a silent no-op. A module session's `session$clientData` delegates to the root, so either `session` or a passed-in `parent_session` works.
- The `selectize_set_value` custom message (`ui.R`) that `cedar_restore_from_query` sends for `select_server` keys must set the selectize `label` field (Shiny uses `labelField: "label"`); adding only `value`/`text` renders the chip as the literal string "undefined".

**Headcount deviates and its restore is known-broken (low priority).** Headcount's six filters are server-side selectizes that **cascade** (college→dept→major→minor→concentration): the `input$college` observer runs at startup (`ignoreInit = FALSE`) and resets everything downstream. The single-`selected` trick above fixes only the independent fields (campus, college); the dependent fields get clobbered by the cascade before the async values settle, so a deep link does not reload them. Because of this, **Headcount has no copy-shareable-link button** (removed on purpose) and is effectively not deep-linkable. Making it work needs *sequenced* restore (set college → await its cascade → set dept → await → …), not a one-liner — a real change to reactive ordering that must be verified in the running app. Its `CEDAR_SHARE_SPECS` entry is left in place for that future work.

---

## Opt List Convention

All cones accept `opt = list()` as their last argument. Options are resolved inside the function with `%||%`:

```r
min_n  <- opt$min_n  %||% 10L
campus <- opt$campus %||% NULL
```

Common opt keys across cones:

| Key | Type | Used in |
|-----|------|---------|
| `term` | integer | most cones |
| `campus` | character | most cones |
| `dept` | character | section/enrollment cones |
| `college` | character | section/enrollment cones |
| `level` | character | section/enrollment cones |
| `min_n` | integer | cohort-aware cones |
| `cohort_ids` | character vector | gradebook.R |
| `subject_code` | character vector | pathway.R |
| `start_classification` | character | pathway.R |
| `include_summer` | logical | pathway.R |

---

## Naming Conventions

### Department references — three established contexts (not inconsistencies)

| Context | Name | Example |
|---------|------|---------|
| CEDAR table column | `department` | `filter(department == "HIST")` |
| Filter option objects | `dept` | `opt$dept` |
| Report parameter objects | `dept_code` | `d_params$dept_code` |

`department_code` is not used anywhere. Unifying `dept`/`dept_code` → `department` in opt objects would require touching every cone — leave it unless doing a full sweep.

### Other known variations

| Concept | Names in use | Where |
|---------|-------------|-------|
| Student count | `enrolled`, `registered`, `count` | enrl.R |
| Drop types | `dr_early`, `dr_late`, `dr_all`, `drops` | enrl.R |
| Program reference | `prog_codes`, `prog_names`, `program_code`, `program_name` | credit-hours.R, headcount.R |

---

## Refactoring Status

**The cleanup backlog and its status live in `NEXT-STEPS.md` Part 2** — one
status list, kept current there. (The phase checklists that used to live here
were duplicated, drifted stale, and were removed 2026-07-12; completed-phase
knowledge that still matters — e.g. the `is_lab` removal — is documented in
the relevant sections above.) `ROADMAP.md` holds the strategic priorities
across code, docs, UX, and operations.

---

## Key Data Flow Notes

- `dept-report.R` passes **unfiltered** `cedar_students` to `get_credit_hours_for_dept_report` (needed for college vs. dept comparison), but **filtered** students to `credit_hours_by_major` and `credit_hours_by_fac`.
- `credit_hours_data` has a `level` column: `"lower"`, `"upper"`, `"grad"`, `"total"`. Filter to `"total"` to avoid double-counting.
- `appointment_pct` in `cedar_faculty` is stored as 0–100; divide by 100 for FTE.
- `get_stopout()` requires `add_next_term_col()` from utils.R — it is called internally. utils.R must be sourced first (it is, via load-funcs.R order).
- The `%||%` null-coalescing operator is defined in `utils.R`. Cones that are sourced standalone (tests, RStudio) include a local fallback definition at the bottom of the file.

---

## Coding Standards

### No fallback behavior

**Never write silent fallbacks.** If a required column is missing, a join produces no rows, or an input is malformed, raise an explicit error. Do not substitute defaults, return empty results, or silently skip.

```r
# Wrong — hides the real problem
result <- tryCatch(get_something(df), error = function(e) tibble())

# Wrong — silent coalesce when column should always exist
dept <- df$dept_code %||% df$department

# Right — fail loudly
if (!"dept_code" %in% names(df)) stop("dept_code column required but not found in input")
```

This applies everywhere: cones, branches, trunk, data pipeline scripts, and test helpers. The only `tryCatch` allowed is in Shiny module servers where a caught error is immediately shown to the user via `showNotification()`.

### Standardize counts and shared visuals — always prefer a helper

**Before writing a count, a rate, or a visualization inline, look for an existing helper — and if one doesn't exist but the pattern shows up in more than one place, add one and route all callers through it.** Divergent local implementations of "the same thing" are how two tabs end up disagreeing about a course's enrollment or drawing subtly different sparklines.

- **Ways of counting** — enrollment, drops, DFW, fill, headcount: there is (or should be) exactly one canonical definition. Census enrollment is `add_census_enrl()` / `calc_census_enrl_baselines()` (`R/branches/enrl.R`); DFW is `classify_enrollment_outcomes()` (`R/trunk/utils.R`); term type is `add_term_type_col()` / `get_term_type()`. Call these, don't re-derive `registered + dr_late` (or a grade filter, or a `substr(term, 5, 6)`) by hand. If you find the same formula written twice, that's a bug waiting to happen — extract it.
- **Enrollment history** — per-term active-enrollment series and its display: `summarize_term_enrl_series()` builds the term→(`has_active`, `term_enrl`) series (single course or keyed by course group); `format_term_history()` renders it as `"Fa22: 12 → Sp23: C"`; `drop_shell_sections()` removes active/zero-enrollment/unstaffed placeholders first (instructor sentinels in `NO_INSTRUCTOR_NAMES`, `R/lists/status_codes.R`). All in `R/branches/enrl.R`; used by both `get_course_enrollment_history()` and `get_enrollment_concerns()`. Don't re-hand-roll the `group_by(term) %>% summarize(sum(total_enrl[status=="A"]))` slice.
- **Shared visualizations** — sparklines, fill bars, tier/status badges, trend cells, reactable column defs: live in `R/modules/ui-helpers.R` (`make_sparkline()`, `trend_cell_html()`, `cedar_pot_coldef()`, …). A new tab that needs a sparkline uses the shared one so every sparkline reads the same; it does not hand-roll SVG.
- When a computation or component is currently inline and you touch nearby code, that's the moment to promote it to a helper and migrate the other callers — leave the codebase more standardized than you found it.

---

## Test Infrastructure

All test data is hand-crafted tribbles in `tests/testthat/fixtures/designed_test_data.R` — that single file IS the test database and the source of truth. `setup.R` sources it and exposes the tables as `test_sections`, `test_sections_sf` (seatfinder-specific 2024/2025 terms), `test_students`, `test_programs`, `test_degrees`, `test_faculty`, plus `test_lookups` and a `data_objects` list. Every expected value is traceable to explicit rows in that file — no sampling, no binary fixtures, no regeneration step.

**Pinned counts:** the header of `designed_test_data.R` is a large comment block of expected values (row counts by dept/term/campus/status/level, crosslist scenario summaries, regstats design values, etc.) that test files hard-code against. When you add or change rows, update the pinned counts in that header AND the hard-coded expected values in affected test files, in the same change.

**Stable terms:** 202010, 202060, 202080, 202110 (Spring/Summer/Fall 2020, Spring 2021). `test_sections_sf` additionally uses 2024/2025 terms for seatfinder tests.

**Departments:** sections/students center on HIST, MATH, ANTH, NURS, with variety rows in PSYC, BIOL, MGMT, ENGL, POLS, AMST. `test_faculty` covers HIST, MATH, ANTH, PSYC, BIOL, NURS, MGMT, ENGL, POLS — MGMT and POLS have only Term Teacher rows, so they are excluded from permanent-faculty counts.

**Adding an edge case:** add rows directly in the relevant table's section of `designed_test_data.R`, following the established naming conventions:
- **EC-xx** — numbered edge cases (e.g., EC-04..EC-06 are the combined C-suffix course patterns). Continue the sequence from the highest existing number. The numbering began in the legacy `create-test-fixtures.R` (EC-01..03), so do not reuse those numbers.
- **XLxx** — crosslist/split scenarios (XL01..XL06).
- **SVARxx** — section variety rows (unusual statuses, NA fields).

Document the new rows and their expected values in the pinned-counts header, then update hard-coded expectations in affected tests.

**Schema drift:** there is no regeneration script and no separate drift check — test failures are the signal. If `transform-to-cedar.R` renames, removes, or adds a column that code under test depends on, mirror the change in `designed_test_data.R` (the authoritative schema source is `transform-to-cedar.R`).

**Legacy pipeline (do not use):** `tests/testthat/create-test-fixtures.R` previously sampled real CEDAR data into binary `cedar_*_test.qs` fixture files. Nothing loads those anymore — the script is kept only as the documented recipe for drawing a stratified real-data sample, should that ever be revived. Never add fixture rows or edge cases there; they will not be seen by any test.

**Rules:**
- Test expected values are hard-coded from running functions against fixtures, then committed. If a value changes, it means the function or fixture changed — investigate before updating.
- `uel=FALSE` in filter tests: the `uel=TRUE` default applies the `excluded_courses` list and mutates `subject_course`. Filter logic tests should use `make_opt(uel = FALSE)` to isolate from this behavior.
- If required columns are missing from fixtures, add them to `designed_test_data.R` matching the schema in `transform-to-cedar.R`. Do not add fallback logic in tests or fixtures.
- **No inline fixtures in test files.** Never construct tibbles inside a `test_that()` block to feed a function under test. All test data lives in `fixtures/designed_test_data.R`; tests filter from `test_sections`, `test_students`, etc. Inline tibbles produce tests that pass by construction rather than tests that verify real behavior against representative data.
- **Never write throwaway/scratch tests, and don't fragment the code or fixtures just to make something testable.** When you add or change behavior, expand the *real* suite that exercises it against the *real* fixtures — don't spin up a temporary `test-tmp-*.R`, a one-off inline scenario, or a helper extracted solely so a unit test can reach it, then delete it. If the fixtures can't yet represent the case (e.g. they had no waitlisted students because the status-code→text map only knew `RE`), fix the fixtures so they mirror actual data — that is the trivial, correct path, and it makes the case reusable. Concretely: the waitlist supply columns are covered by real NURS 2010 202080 waitlist rows in `designed_test_data.R` + assertions in `test-waitlist.R`, not by an isolated helper or a scratch file.

### Running tests

Cedar is a **Shiny app, not an R package**. Do not use `devtools::test()`, `pkgload::load_all()`, or `library(cedar)` — none of these work.

**Always `cd` to the project root first**, or all relative paths in `setup.R` and fixture sources will be wrong:

```bash
cd /Users/fwgibbs/Dropbox/projects/cedar
```

**Run all tests:**
```bash
Rscript --vanilla -e "testthat::test_dir('tests/testthat')"
```

**Run a single test file:**
```bash
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-population.R')"
```

**What NOT to do:**
- Do not `source('setup.R')` from the shell — that triggers the interactive Cedar setup wizard, not the test setup.
- Do not try to load functions manually with `source('R/...')` or `source('global.R')` for ad-hoc scripts — the `global.R` also triggers interactive prompts. The `testthat::test_file()` / `test_dir()` runner sources `tests/testthat/setup.R` automatically, which calls `load_funcs()` and loads the fixture data.
- Do not try to get actual computed values by running R outside of testthat. Test failures already show the computed value in the diff — `expect_equal(x, 5)` failing prints the actual value of `x`. If you need to discover what a new function returns before you know the expected value, write `expect_equal(result, NULL)` or any obviously wrong value; the failure output reveals the real one.

**renv — always use `--vanilla` for local scripts and tests (decision 2026-07-12).**
The project renv library is **not** the supported local run path and is expected
to be broken at any given time. Root cause: the renv library is symlinks into
`~/Library/Caches/org.R-project.R/R/renv/cache`, and macOS periodically purges
that cache, leaving dangling links — so every "repair" (re-restore) breaks again
at the next purge. Docker deliberately does not use renv ("Docker provides the
reproducibility layer" — see `Dockerfile.shiny`), and the system library has
everything tests need, so `Rscript --vanilla` is the standard. `renv.lock` is
kept as the record of known-good package versions. If someone wants a working
RStudio+renv setup, the durable fix is `RENV_CONFIG_CACHE_ENABLED=FALSE` in
`.Renviron` (copies instead of cache symlinks) followed by `renv::restore()` —
do not just re-restore with the cache enabled.

### E2E / browser testing (UI, routing, rendered output)

testthat covers cones/branches but **cannot test client-side behavior** (tab URL
routing, JS, what actually renders). For that, drive the **dockerized app** with a
headless browser. The local renv is often broken, so do not try to run the Shiny
app outside Docker.

Harness in `tests/e2e/` (see `tests/e2e/README.md`); uses `puppeteer-core` against
system Chrome — no browser download, no Claude-in-Chrome extension needed.

```bash
cd tests/e2e && npm install          # one-time; node_modules is gitignored
cd <project root>
./rebuild-and-test.sh                 # rebuild image w/ current source, restart container, wait for app
node tests/e2e/nav.test.mjs           # assert top-nav URL routing; exit code = pass/fail
node tests/e2e/shot.mjs <tab-slug>    # screenshot a tab → /tmp/cedar-<tab>.png
```

**To drive inputs and read output back** (set a filter, click "gather"/"run",
read the rendered table) — don't re-derive the boilerplate. `tests/e2e/lib.mjs`
has the reusable helpers (`launch`, `connect`, `setInput`, `click`, `clickSubTab`,
`waitForSelector`, `readReactable`, `colIndex`), and `tests/e2e/README.md` →
"Driving inputs and reading output back" has a copy-paste recipe plus the gotchas
(namespaced module input ids, server-side selectize choices, `suspendWhenHidden`
sub-tabs, reactable DOM selectors + uppercased headers). Keep ad-hoc check scripts
in `tests/e2e/` while iterating, then delete them.

Notes:
- The app runs in Docker at `http://localhost:3838/` (source is baked via
  `COPY . .`, so **code changes need a rebuild** — `rebuild-and-test.sh`; only the
  `COPY` layer re-runs, so it's fast after the first cold build). Data is mounted
  from `CEDAR_DATA_DIR` (`.env`).
- First connection runs `global.R` (heavy data load), so the first request after a
  restart is slow — the scripts wait for it.
- Override defaults with env vars: `CEDAR_URL`, `CHROME_PATH`.
- If `docker compose up --build` fails with a blob "input/output error", that's the
  Docker store out of disk: `docker compose down && docker builder prune -af`, then
  rebuild.

---

## DESR Input Schema (cedar_sections source)

Source: MyReports "Department Enrollment Status Report." Key fields:

### Identifiers
| Column | Description |
|--------|-------------|
| `TERM` | Term code (e.g., 202610 = Spring 2026) |
| `CRN` | Course Reference Number |
| `SUBJ` | Subject code (HIST, MATH, etc.) |
| `CRSE#` | Course number — may include trailing "L" for labs |
| `SECT#` | Section number |

### Enrollment
| Column | Description |
|--------|-------------|
| `ENROLLED` | Section-level enrollment |
| `MAX_ENROLLED` | Capacity |
| `XL_TOTAL_ENROLLMENT` | Combined XL group enrollment (crosslisted only) |
| `WAIT_COUNT` | Waitlist count |
| `CENSUS1`, `CENSUS2` | Census **dates** (mm/dd/yyyy), **not** enrollment counts — parser reads `CENSUS1` as a date (`census1`). No census-frozen headcount exists in the DESR; `ENROLLED` is always the count as of the file pull. See [Enrollment Measures](#enrollment-measures-desr-enrolled-vs-classlist-registered). |

### Crosslist Fields
| Column | Description |
|--------|-------------|
| `XL_CODE` | 2-char crosslist group ID |
| `XL_SUBJ` | Subject code of partner section |
| `XL_CRN` | CRN of partner section |

**Crosslist quirk:** A section crosslisted with N partners has N rows (same CRN, different XL_SUBJ). `distinct()` does not deduplicate these. Downstream code must handle.

**SHORT_TEXT quirk:** `"HIST home 202610"` format signals home dept for cross-dept crosslists. Casing is inconsistent (`"home"` vs `"Home"`). Parser extracts subject case-insensitively.

### Parser-Added Columns (not in raw CSV)
| Column | Description |
|--------|-------------|
| `subject_course` | `paste(SUBJ, CRSE#)` → `"HIST 480"` |
| `total_enrl` | `max(ENROLLED, XL_TOTAL_ENROLLMENT)` |
| `level` | `"lower"` / `"upper"` / `"grad"` from course number |
| `term_type` | `"spring"` / `"fall"` / `"summer"` |
| `department` | Mapped from SUBJ via `subj_to_dept` |

---

## Sample Data

`data/samples/desr_sample.csv` — 297 rows of real DESR data (gitignored).
Covers: split-level XL, non-split XL, SHORT_TEXT variations, multi-way XL, zero-enrollment, lab sections.
See `data/samples/README.md` for group inventory.

---

