---
title: Branch, Cone, and Feature Inventory
parent: Developer Guide
nav_order: 25
---

# Branch, Cone, and Feature Inventory

A per-function index of `R/branches/`, `R/cones/`, and `R/features/`. `AGENTS.md` lists these one row per file; this page is the detail. Check the source before trusting a signature — this table drifts.

## Branches — Reusable Domain Computations (`R/branches/`)

| File | Main function(s) | Purpose |
|------|-----------------|---------|
| `population.R` | `build_population(programs, degrees, students, opt)` | Build student populations for analysis; returns tibble with `student_id` + classification columns. The central cohort-building function. |
| | `get_focal_programs(programs, opt)` | Resolve program names/codes to canonical list for population filters |
| | `build_demographic_population(programs, opt)` | Population scoped by demographic characteristics |
| | `get_ongoing_ids()`, `get_graduated_ids()`, `get_switched_out_ids()`, `get_never_declared_ids()` | Sub-classifiers used internally by `build_population()` |
| | `get_entry_pathways()`, `classify_origin()`, `classify_entry_method()`, `classify_entry_status()` | Entry-type classification helpers |
| `comparison.R` | `build_comparison(treatment_ids, pool_ids, programs, ..., term_credits)` | Build treatment/control groups for observational analyses. Demographic and standing covariates come from `cedar_programs` at each student's covariate term; the **matched** academic-position covariates (`cum_gpa_entering`, `unm_credits_entering`, `total_credits_entering`) are reconstructed via `build_gpa_timeline()` / `build_credit_timeline()`. `current_unm_gpa` (Banner Institution GPA) rides along for the **profile only** — see the descriptive-vs-matched split below. Never add a pull-stamped field to `continuous_cols` |
| | `compute_balance(groups)` | Report covariate balance between treatment and control |
| `enrl.R` | `calc_cl_enrls(students)`, `get_enrl(sections, opt)` | Enrollment counts and stats |
| | `get_course_section_counts(sections)` | Active section count + total enrollment per course, crosslist-deduplicated. Returns one row per (term, subject_course, course_title, campus). Join on those four columns. Reusable in any tab, feature, or RStudio analysis that needs a "how many sections / how many students" summary without running a full enrollment pipeline. |
| | `prepare_enrollment_trend_history()`, `get_enrollment_momentum()`, `prepare_enrollment_trend_plot_series()` | Enrollment Trend Signals helpers. Keep plot prep and campus-specific series handling here, not in dashboard/report modules. |
| | `get_low_enrollment_courses(courses, opt, threshold)` | Sections below a threshold, filtered and deduplicated via `filter_DESRs()` |
| `course-attempts.R` | `prepare_course_attempts(students, opt)` | Shared cleaned course-attempt rows for grade/outcome analyses. New cones usually should not call this directly unless they need row-level attempts |
| | `get_course_outcome_rates(students, opt, group_cols, min_n)` | Preferred cone API for DFW, W, D/F, C-, below-C, and early-drop metrics |
| | `get_grade_distribution(students, opt, group_cols, min_n)` | Preferred cone API for A/B/C/D/F/W/Other grade distributions |
| `demographics.R` | `summarize_student_demographics(filtered_students, opt)` | Flexible demographic summary grouped by `opt$group_cols` (counts, term-type means, pct of course enrollment). Used by course-demographics and waitlist cones |
| `headcount.R` | `get_headcount(programs, opt)` | Student enrollment counts by program |
| `credit-hours.R` | `get_credit_hours(students, opt)` | Credit hour production |
| `data-edges.R` | `cedar_data_edges(students, degrees, min_graded_share, max_term)` | **The canonical right/left edge of the loaded data.** Returns `first_enrolled`, `last_enrolled`, `last_enrolled_complete`, `last_graded`, `last_degree`. Never bound an analysis with `max(term)` or arithmetic on `cedar_current_term` — see the right-edge policy above |
| | `cedar_edge_note(edges, which)` | The sentence a capped surface shows to explain which edge it used |
| | `cedar_longitudinal_edge(edges, grade_dependent)` | Hard edge for analyses that require comparable history or later observation: `last_enrolled_complete`, or the earlier of it and `last_graded` when grades are read |
| `gpa-timeline.R` | `build_gpa_timeline(students, opt)`, `attach_gpa_position()` | Per-term cumulative GPA rebuilt from class-list grade points, because `inst_gpa` is frozen across a student's history for 67.8% of students with 5+ terms. `gpa_entering` excludes the term's own grades |
| `credit-timeline.R` | `build_credit_timeline(term_credits, programs, opt)` | **The only sanctioned source for "how far into their studies was this student at term T".** Rebuilds the position from the per-term class-list series plus a recovered transfer block, because the `cedar_programs` cumulative columns are stamped at pull time and frozen across a student's history. Read the field reliability contract above before using anything else |
| | `attach_credit_position(events, timeline, term_col, basis)` | Join a credit position onto any table of student-term events |
| `degrees.R` | `count_degrees(degrees, opt)` | Degree completion counts |
| `course-flows.R` | `get_next_course_pairs(students, opt, source_courses)`, `get_previous_course_pairs(students, opt, target_courses)` | Campus-scoped source→destination course pairs across adjacent terms. Course sequencing always joins and groups by campus so students at different campuses are never treated as one flow |
| | `get_course_destinations()`, `get_course_feeders()`, `get_concurrent_courses()`, `summarize_concurrent_courses()`, `get_course_flow_neighbors()` | Summaries of what registered students take after / before / alongside a course. Concurrent results count student-term enrollments, retain campus grain, and use every selected-course student-term in the percentage denominator; `get_course_flow_neighbors()` returns the combined named list |
| | `get_downstream_course_options(students, course_x, opt)` | Course Dynamics follow-on picker. Percentages use the same course-level eligibility denominator as the selected-pair analysis: complete follow-up opportunity, with students who already passed a single Y strictly before X excluded. Includes registered and late-drop Y attempts so the picker and analysis cannot drift |
| | `get_downstream_pair_audit(students, course_x, course_y, opt)` | Instructor-neutral course-pair denominator plus yearly course-order totals. Each student appears once, keyed to the year of first X; strict-prior and same-term Y passes remain separate |
| `pathways.R` | `pathways_level_filter()`, `pathways_observation_boundary()`, `apply_pathways_population_window()`, `resolve_pathways_focal_programs/dept_codes/subjects()` | Pure result-shaping helpers for the Pathways module — calculation-affecting rules kept testable without loading Shiny |

### Named population groups (`R/branches/population.R`)

| Function | Purpose |
|---|---|
| `population_group_ids()` / `population_group_choices()` | The shared group registry (`CEDAR_POPULATION_GROUPS`, `R/lists/population-presets.R`) as ids or selectize choices |
| `population_group_program_names(group_id)` | The program names a group declares |
| `population_group_major_codes(group_id, programs, include_pre_majors)` | Resolves a group to Banner major codes through name matching **and** `premaj_canon`, because each alone misses real pre-majors. `include_pre_majors` takes `build_population()`'s vocabulary: `lump` / `majors_only` / `pre_only` |
| `population_group_audit(group_id, programs)` | `codes`, `unmatched_names`, and `near_miss` — the drifted names a name-declared group would otherwise drop silently. Run it when adding a group |

## Cones — Single-Question Analyses (`R/cones/`)

| File | Main function(s) | Takes cohort? | Purpose |
|------|-----------------|---------------|---------|
| `bottleneck.R` | `get_bottlenecks(cohort, students, opt)` | ✓ | Waitlist pressure / unmet enrollment demand |
| `stopout.R` | `get_stopout(students, cohort, opt)` | ✓ | Stop-out rate gap after DFW vs. passing |
| `pathway.R` | `get_course_timing(students, cohort, opt, students_full, term_credits)` | ✓ | When population students take each course. The `cohort` parameter name is legacy; pass the `build_population()` output. `opt$x_axis` picks the axis; `opt$subject_course` restricts to an explicit course list; `opt$group_campus = FALSE` drops campus from the key (trajectory questions only — see the campus-policy exceptions above) |
| | `plot_curriculum_map(timing_data, opt)` | — | Heatmap of course timing |
| | `get_course_pairs(students, cohort, opt)` | ✓ | Ordered A→B course sequences |
| `course-sequence-effect.R` | `get_course_sequence_effect(students, programs, applicants, opt, term_credits, data_edges)` | — | Observational: do students who took X before Y earn better grades in Y? Treatment/control via `build_comparison()`; Y is capped at the longitudinal grade edge |
| `course-instructor-effect.R` | `get_instructor_effect(students, programs, applicants, opt, term_credits, data_edges)` | — | Descriptive downstream progression and outcomes by upstream instructor. Caps Y at the longitudinal grade edge, excludes right-censored X cohorts and strict-prior Y completers from the single-course continuation denominator, classifies grades canonically, and returns eligibility/unobserved-outcome audit counts for the UI. Outcomes attribute a student once to their first X instructor; course-order totals are instructor-neutral and aggregated by year. The balance diagnostic is optional context for comparing only the two largest instructor groups: it does not define, sample, match, or adjust the descriptive rates and belongs after those results in the UI |
| `course-neighbors.R` | `plot_course_sankey_by_term_with_flow_counts(to_courses, from_courses, opt)` | — | Sankey diagram of before/after course flows |
| | `plot_concurrent_course_treemap(concurrent_courses, opt)` | — | Treemap of the most common same-campus, same-term companion courses |
| `seatfinder.R` | `seatfinder(students, courses, cedar_faculty, opt)` | — | Seat availability analysis across terms; returns named list of course comparison tibbles |
| `waitlist.R` | `inspect_waitlist(students, opt, sections = NULL)` | — | Waitlist counts by course/major; `sections` only needed if students lack `course_title` |
| `course-outcomes.R` | `get_course_outcomes(students, cedar_faculty, opt)` | — | Returns named list: `persistence` (next-term return rates by grade), `dfw_trend` (DFW rate by term), `instructor_dfw` (per-instructor vs. course avg). `cedar_faculty` is optional; omitting it skips instructor breakdown |
| | `next_term_persistence(filtered, all_students, opt)` | — | By grade outcome, % who returned next term |
| `population-trend.R` | `make_population_trend(programs, opt)` | — | Entry type distribution over time |
| `major-changes.R` | `detect_major_changes(programs, cohort, opt)` — **moved to `R/branches/major-change-detection.R`** | ✓ | Detect term-over-term major changes |
| | `tag_major_changers(programs, cohort, opt)` | ✓ | Boolean flag per student: ever changed? |
| | `time_to_first_change(programs, cohort, opt)` | ✓ | Terms from first enrollment to first change |
| | `avg_credits_before_major(changes, opt)` | — | Avg credits when arriving in each major |
| | `majors_moved_out_of(changes, opt)` | — | Most-departed majors by frequency |
| | `major_change_pathways(changes, opt)` | — | Common A→B transition pairs |
| | `pathways_by_college(changes, opt)` | — | A→B pathways broken out by college |
| | `get_major_change_courses(changes, students, opt)` | — | Courses taken during change terms |
| | `get_pre_change_courses(changes, students, population, opt)` | — | Courses taken in `prev_term` — the last term on the old major, before the switch posts — each reported against the course's ordinary rate in the population. Returns a named list (`courses`, `n_switches`, `n_switches_with_courses`, `n_students`, `n_baseline_terms`). **The two shares have different denominators:** `pct_before_switch` is per *switch*; `pct_other_terms` is per *student-term* over the whole population (stayers included) minus switch-adjacent pairs. Pass the full analysis population — restricting it to changers silently converts the baseline into a within-person comparison. The baseline column is not optional garnish: on raw counts alone the table ranks the largest required courses for every population and reads as a finding |
| `course-retention.R` | `get_retention_comparison(students, opt, degrees)` | — | Descriptive next-term retention rates compared across courses (raw rates, not treatment/control) |
| | `get_retention_trend(students, opt, degrees)` | — | One course's retention rate over time |
| | `get_dept_retention_trend(students, opt, degrees)` | — | Dept-level retention trend |
| `course-demographics.R` | `get_course_demographics(students, opt)` | — | Major/classification breakdown per course |
| `sfr.R` | `get_permanent_faculty_fte(faculty, opt)` | — | Faculty FTE by dept |
| `cancellations.R` | `get_cancellations(sections, opt)` | — | Cancelled sections (section status "C") plus summary tables for Explore > Cancellations; related non-active statuses counted separately for context |
| `gen-ed-grads.R` | `get_gen_ed_grad_cohort(students, degrees, opt)` | — | Graduates of a department whose ENTIRE UNM record sits inside the data window (first enrolled after the data begins, awarded degree before it ends). Deliberately a small sample — read the block comment at the top of the file before using it |
| | `get_gen_ed_grad_uptake(students, cohort, gen_ed_lu, opt)` | ✓ | Share of that cohort taking each Gen Ed course, plus per-graduate course/area counts. Averages divide by the whole cohort, so a graduate with no recorded Gen Ed is a zero, not an omission. Also returns `summary_dept` — the same figures restricted to Gen Ed the graduates' own unit teaches, plus `dept_share_pct` |
| `gen-ed-conversion.R` | `get_gen_ed_conversion(students, programs, opt)` | — | Sankey flows from a student's program at the time of a gen-ed course to their last recorded program (graduated / stopped-out labeled); flows below `opt$min_n` collapsed into "Other" |
| | `get_course_major_associations(students, programs, opt)` | — | Course → eventual-major association table |
| `data-integrity.R` | `check_student_id_integrity(spine, tables, opt)` | — | Can the stored tables actually be joined on `student_id`? Compares each table term-by-term against a spine (pass `cedar_students`) and returns `by_term`, `by_table`, `spine`, `n_tables_split`. A term with records and **exactly zero** matches is the signature of a hash mismatch at ingest; a table covering a wider population sits partway in every term and never at zero, so only a mixture of zero-match and full-match terms is reported as `"split"`. Surfaced in Data & Usage → Join Integrity. Read ISSUES.md I1 before interpreting a `split` verdict |

## Features — App-Facing Orchestrators (`R/features/`)

Features call multiple branches/cones and assemble payloads for visible app surfaces. They follow different rules than cones: they may call other cones. They do not contain Shiny UI/server wiring; that lives in `R/modules/` or, for older surfaces not yet modularized, `server.R`.

| File | Main function(s) | Purpose |
|------|-----------------|---------|
| `admin.R` | `build_admin_data_status(summary, current_term)` | Tiny freshness-table payload built only from the precomputed startup summary; never scans institutional tables |
| `course-report.R` | `create_course_base_data(data_objects, opt)`, `compute_cr_flows_tab()`, `compute_cr_outcomes_tab()`, `prepare_downstream_outcomes_display()` | Assembles enrollment and rollcall data for the Course Dynamics tab; flows/outcomes computed lazily per sub-tab. The downstream display helper keeps the full analytical audit intact while presenting one sortable `% (count)` column per outcome and omitting instructor-level censoring/course-order fields already summarized above the table |
| `gen-ed.R` | `get_gen_ed_profile(students, sections, programs, degrees, opt)` | Gen Ed profile (scope filtering, outcome rates, grade distribution, major mix) for Explore > Gen Ed and the Dept Trends Gen Ed panel |
| | `get_gen_ed_grad_profile(students, degrees, term_credits, opt)` | Gen Ed *consumed by* a department's own graduates — cohort meta, a `get_course_timing()` heatmap on the `unm_credit_band` axis, and the uptake table — for the graduate sections of Dept Trends > Gen Ed. The rest of that subtab measures the department as a Gen Ed provider; this one flips the population, which is why it needs the strict cohort |
| | | Returns the three views twice: `timing`/`by_course`/`summary` over all Gen Ed, and `timing_dept`/`by_course_dept`/`summary_dept` over the unit's own. Both scopes are **cut from one `get_course_timing()` run**, not computed twice — `n_eligible` is built before that function applies its course filter, so narrowing the course list only removes rows and the two heatmaps stay comparable cell for cell. Pinned by a test in `test-gen-ed-grads.R` |
| `dept-dashboard.R` | `create_dept_dashboard_data(...)` | Dashboard metrics and plots for one dept (assembles headcount, enrl, credit-hour trends) |
| | `get_subject_current_stats(sections, subject, term)` | Lightweight current-term snapshot: returns `list(n_sections, total_enrl)` for a subject, crosslist-deduplicated. No full dashboard pipeline. Reusable in dashboard cards, comparison views, and RStudio analyses. |
| `dept-trends.R` | `create_dept_report_base(data_objects, opt)`, the `compute_dept_*_tab()` orchestrators, and matching `rebuild_*()` helpers | Assembles the active Dept Trends web profile and reconstructs charts from cached analytical tables |
| `regstats.R` | `get_reg_stats(students, courses, opt)` | Enrollment anomaly detection (calls enrl, course-demographics, waitlist branches) |
| | `filter_downstream_by_dept(downstream_df, dept, sections)` | Filters downstream registration signals (dest_course pairs) to only destinations in a given dept's subjects. Pass empty/NULL dept to return all rows unchanged. Eliminates a DRY violation — was duplicated in two server.R render blocks. Reusable in any downstream signals display. |
| `enrollment-projections.R` | `build_enrollment_projection_bundle(...)`, `build_enrollment_projection_view(bundle, opt)` | Builds and reads the published projection artifact. Spring and Fall targets only; Summer is refused |
| | `find_enrollment_projection_bundles(output_dir)` | Every saved bundle as one row per target term, with its season. The season-aware replacement for "the highest saved target term" |
| | `load_latest_enrollment_projection_bundle(output_dir, term_type)`, `load_enrollment_projection_bundle(output_dir, target_term)` | Read one bundle. `term_type` has no default: a caller that does not name a season would silently switch seasons when the other one publishes |
| | `format_enrollment_projection_preview(bundle, courses)` | Committed text formatter over the payload; the UI and tests read the typed payload, never this text |
| `enrollment-projection-refresh.R` | `resolve_enrollment_projection_refresh(config, students)` | Resolves the morning policy into one scope **per target**, nearest first. Returns a list, not a single scope |
| | `enrollment_projection_model_drift(output_dir, base_dir)` | Deploy-time gate. Checks every saved season's bundle against the deployed model source; loads no CEDAR table |
| `enrollment-projection-scenario.R` | `build_enrollment_projection_scenario(bundle, programs, opt)` | Grows one named population and reads the effect on published course demand. Arithmetic over saved rows only — year 1 is the published projection at any growth rate, later years are labeled `Scenario` and carry no accuracy axes |
| | `format_enrollment_projection_scenario_preview(scenario, measure)` | Text preview over the scenario payload; `measure` is students, sections, or additional |


## Trunk Helpers — full function tables

Moved from `AGENTS.md`. Always check these before writing equivalent logic in a cone or branch.

## `R/trunk/utils.R`

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

## `R/trunk/filter.R`

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

