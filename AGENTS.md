# CEDAR Development Reference

Open-source Shiny analytics platform for higher ed curriculum, enrollment, and student experience at UNM. Primary data sources are Banner/MyReports extracts. Primary audience is IR staff and deans using the Shiny app, with a secondary audience of analysts using the cones directly in RStudio.

**Instructions for agents:** Trust the layer rules (trunk/branches/cones/features/modules) and the coding standards — they reflect hard-won decisions, not suggestions. The live cleanup backlog lives in `ROADMAP.md`; known unfixed defects live in `ISSUES.md`. When in doubt about data structure, the authoritative source is `R/data-parsers/transform-to-cedar.R`.

**Where the rest of the documentation lives.** This file carries the rules. The evidence, measurements, and per-function detail behind them live in `docs/developers/` and are **linked, not imported** — read a page when you need it, so it does not sit in every context window.

| Topic | Page |
|---|---|
| Which `academic_studies` fields may describe a past term, and the measurements | [field-reliability.md](docs/developers/field-reliability.md) |
| DESR vs classlist enrollment; the Regstats baseline contract | [enrollment-measures.md](docs/developers/enrollment-measures.md) |
| Why the data has four right edges, and the failures that proved it | [right-edge-policy.md](docs/developers/right-edge-policy.md) |
| Why every course metric is grouped by campus | [campus-policy.md](docs/developers/campus-policy.md) |
| Per-function index of branches, cones, features, and trunk helpers | [layer-inventory.md](docs/developers/layer-inventory.md) |
| Module tables, plots, CSS, URL state, page structure | [shiny-modules.md](docs/developers/shiny-modules.md) |
| Cache keys, the two cardinal rules, and the incidents behind them | [caching.md](docs/developers/caching.md) |
| Testing philosophy, fixtures, prototyping without Shiny | [testing.md](docs/developers/testing.md) |
| Driving the running app with headless Chrome | [e2e-testing.md](docs/developers/e2e-testing.md) |
| Ad-hoc data checks; proving a test catches its bug | [adhoc-analysis.md](docs/developers/adhoc-analysis.md) |
| Enrollment projections — the executable contract | [enrollment-projections.md](docs/developers/enrollment-projections.md) |
| Full table schemas, DESR input fields, source-to-CEDAR mapping | [data-model.md](docs/developers/data-model.md), [data-transformation-myreports.md](docs/developers/data-transformation-myreports.md) |

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
R/features/            — app-facing orchestrators/payload builders for visible features
R/modules/             — Shiny UI/server pairs
tests/testthat/        — unit tests for cones and branches
```

**Load order (trunk/load-funcs.R):** lists → trunk → branches → cones → features → modules.

| Layer | Calls | Never calls | Test |
|-------|-------|-------------|------|
| lists | nothing | — | Is it a static constant or lookup? |
| trunk | lists | branches, cones, features, modules | Could this work for a different analytics project? If yes → trunk |
| branches | trunk, lists | cones, features, modules | Is it reused by multiple cones/features/modules? If yes → branch |
| cones | trunk, branches | other cones, features, modules | Does it answer exactly one analytical question? If yes → cone |
| features | trunk, branches, cones | modules | Does it assemble multiple analyses into a feature payload? If yes → feature |
| modules | trunk, branches, cones, features | — | Is it a Shiny UI/server pair? → module |

**The key rule: cones never call other cones.** If a function needs to call multiple cones, it belongs in `features/` or `modules/`.

Two companion hard rules, no exceptions:

- **Cones never touch global state.** No `exists("cedar_sections")`, no reading `data_objects` — every table a cone needs is a parameter. Optional enrichment tables are optional parameters (see how `get_course_outcomes(students, cedar_faculty, opt)` handles optional faculty).
- **Modules contain zero business logic.** No `group_by`/`summarize` pipelines in a module server — collect inputs into an `opt` list, call a cone/branch, render the result.

---

## CEDAR Data Tables

All tables use lowercase snake_case columns. Legacy uppercase names (CAMP, DEPT, TERM) are fully deprecated. Authoritative schema source: `R/data-parsers/transform-to-cedar.R`; full column listings in [data-model.md](docs/developers/data-model.md).

| Table | Rows | What it is / most-used columns |
|-------|------|-------------------------------|
| `cedar_sections` | ~50k | One row per DESR section row. `term`, `crn`, `subject_course`, `campus`, `department`, `enrolled`, `total_enrl`, `is_combined`, `is_topics` |
| `cedar_students` | ~1.9M | One row per student-course-term. `student_id`, `term`, `subject_course`, `campus`, `level`, `final_grade`, `registration_status_code`, `student_classification`, `student_campus`, `major_code` |
| `cedar_programs` | ~200k | One row per student-term program declaration. `program_name`, `program_code`, `dept_code`, `college_code`, `student_campus`, `pell_eligible`, `first_gen`, `ipeds_race`, `gender`, `time_status`. Its `*_credits_*` columns are pull-stamped — see the field reliability contract |
| `cedar_degrees` | ~20k | Awarded degrees. `degree`, `program_name`, `dept_code`, `cumulative_gpa`, `cumulative_credits` |
| `cedar_faculty` | ~5k × terms | `instructor_id`, `instructor_name`, `department`, `job_category`, `appointment_pct` (0–100; divide by 100 for FTE), `college` |
| `cedar_student_term_credits` | ~430k | One row per ENROLLED term. Per-term and `cumulative_*` attempted/completed UNM credits, derived from class lists |
| `cedar_lookups` | — | Named list: `program_name_lookup`, `dept_name_lookup`, `dept_lookup`, `college_code_to_name`, `subject_lookup` (`subject_code` → `dept_code`, `college`) |

**`cedar_programs$dept_code`** is derived during transform from `program_map.qs` and `R/lists/catalog_lookups.R`, in order: `major_college_to_dept["major_code:college_code"]` → `subj_to_dept[major_code]` → `major_to_dept[major_code]` → `major_code` itself. Unmapped rows are excluded from runtime lookups and collected in `cedar_mapping_issues` (Admin > Data & Usage > Mappings); reviewed exceptions live in `allowed_unmapped_program_codes` (`R/lists/program_code_maps.R`). Regenerating `program_map.qs` must still fail loudly on new unmapped codes.

**`dept_code` ≠ subject prefix in `subject_course`.** Geography has `dept_code = "GES"` but courses appear as `"GEOG 101"`. `major_code` is also not a reliable subject prefix. Always go through `cedar_lookups$subject_lookup`; never filter `subject_course` by `dept_code` directly:

```r
# Subject prefixes for dept "GES" → c("GEOG")
cedar_lookups$subject_lookup %>% filter(dept_code == "GES") %>% pull(subject_code)
```

**`cedar_students$major`** is the raw Banner program code (e.g. `"NURS"`), not a readable name. Join against `cedar_programs` or use the validated catalog lookups; do not introduce a new ad hoc program→department map.

**Course suffix flags.** **C suffix** (`BIOL 2110C`) = combined lecture+lab, `is_combined = TRUE`; multiple CRNs share one `subject_course`, so count offerings with `n_distinct(subject_course)`, never `n_distinct(crn)` or `n()`. **L suffix** (`PHYS 151L`) = standalone lab, no flag (`is_lab` was removed as unused); filter on `grepl("[Ll]$", course_number)` if exclusion is ever needed.

**Term codes:** YYYYSS. SS = 10 (spring), 60 (summer), 80 (fall); numeric sort is chronological. A term code is an **identifier** even when numeric: display all six digits with no thousands separator and no decimal (`202580`, never `202,580`). Prefer a human label such as `Fall 2025` on reader-facing surfaces.

### Field reliability contract — what may be claimed about a past term

**A hard rule, in the same class as the campus and DFW policies.** MyReports' Academic Studies report returns *cumulative* figures as of the moment you pull, stamped onto every historical row it hands back. A row keyed `(student_id, term = 202180)` does not necessarily describe Fall 2021.

A field may be used in a claim about a past term only if it passes **both** tests: **pull independence** (re-pulling the same `(student, term)` later returns the same value) and **within-history variation** (inside a single pull, the value moves from term to term for the same student).

| Field (`academic_studies`) | Verdict |
|---|---|
| `Semester Credits Attempted` / `Earned`, `Total Credits`, `Semester GPA` | **safe** — per-term loads, not running totals |
| `Student Classification`, `Student Level`, `Academic Standing` | **safe** |
| `Major` / program | **safe**, after normalising the `Pre-` prefix |
| `Institution Credits Attempted` / `Earned` | **BANNED for per-term claims** |
| `Overall Credits Attempted` / `Earned` | **BANNED for per-term claims** |
| `Institution GPA` | **BANNED for per-term claims and for matching** |

The banned fields vary across a student's own history only ~16% of the time: they are that student's totals *at pull time*, printed on every historical row.

**Permitted:** when a student took a course; when they changed program and to what; their classification, level, standing, per-term credit load and per-term GPA at any past term.

**Forbidden:** any "how far into their degree were they" claim sourced from a banned field — credit bands on a timing axis, "credits at the time of the major change", "credits at first declaration", credit-band cohorts.

**The three sanctioned replacements:**

- **`build_credit_timeline(term_credits, programs, opt)`** (`R/branches/credit-timeline.R`) — the single sanctioned source for a per-term credit position. Returns `unm_credits_entering` / `_after`, `total_credits_entering` / `_after`, and `timeline_valid`. `attach_credit_position()` joins it onto any event table.
- **`build_gpa_timeline()`** (`R/branches/gpa-timeline.R`) — a cumulative GPA that moves. `gpa_entering` is the matchable one: it excludes the term's own grades, which in a course-effect study *are* the outcome.
- **`student_classification`** — per-term, pull-stable, monotone, transfer-aware. The default Pathways x-axis. Prefer it unless the question is specifically about credit progress.

**`timeline_valid` is not optional — filter on it.** The running total starts at zero on a student's first term *in the data*, so the ~30% of students already enrolled when the window opens begin mid-career reading zero. Any surface placing students on a credit axis must drop `timeline_valid == FALSE` rows (failing closed on NA) and **say how many it dropped** — see `timing_meta$n_truncated` in `get_course_timing()`.

**Descriptive vs matched.** A frozen field is barred from temporal claims *and from matching*, but may still be displayed as a current-state description if the page says so. `cum_gpa_entering` belongs in a balance table; `current_unm_gpa` (Banner Institution GPA) belongs in a group profile beside a clear label. Never add a pull-stamped field to `continuous_cols`.

**Small-cell guards are mandatory on any progress axis.** Eligibility thins sharply toward the far end of every one of these axes. Guard the **band** (minimum students who reached it) and the **cell** (minimum students in it) separately — they fail differently. `get_gen_ed_grad_profile()`'s `min_band_n` / `min_n` are the worked example.

**Adding a field:** run it through both tests and add it to the table in the docs before it ships. `tests/testthat/test-field-reliability.R` holds the fixtures.

Measurements, the canonical illustration, and the per-consumer migration table: [field-reliability.md](docs/developers/field-reliability.md).

---

## Registration Status Codes

Defined in `R/lists/status_codes.R`. Use these constants instead of inline strings.

| Constant | Values | Meaning |
|----------|--------|---------|
| `STATUS_REGISTERED` | `c("RE", "RS", "RR")` | Currently registered (RE=enrolled, RS=section change, RR=reserve seat) |
| `STATUS_WAITLIST` | `c("WL")` | Waitlisted |
| `STATUS_DROP_EARLY` | `c("DR", "DD")` | Early drop/drop-delete (before grade consequence, no DFW outcome) |
| `STATUS_DROP_LATE` | `c("DG", "DW")` | Late drop (after deadline, grade consequence) |
| `STATUS_DROP_ALL` | `c("DR", "DD", "DG", "DW")` | All drops |
| `STATUS_DROP_OTHER` | `character(0)` | Administrative/other drops not already counted above |

**Waitlist demand.** CEDAR's user-facing waitlist count is **class-list true demand**: distinct WL students after removing anyone with an RE/RS/RR registration in the same course title, term, delivery campus, college, and part-of-term group; duplicate WL rows within that group count once. Canonical helpers are in `R/branches/waitlist-demand.R`; Waitlists, Regstats, and the Department Dashboard must use them rather than summing `cedar_sections$waitlist_count` or `calc_cl_enrls()$wl_all`. `cedar_sections$waitlist_count` is a DESR snapshot field with a different source and grain, usable only as an explicitly labeled fallback. Historical extracts can retain only students still waiting when the term closed, so a small past-term count does not establish that earlier demand was small.

---

## Enrollment Measures: DESR `enrolled` vs Classlist `registered`

CEDAR carries **two independent enrollment counts** that do not mean the same thing. Comparing them — or comparing one measure across terms whose snapshots were taken at different points in the term — silently biases any demand/capacity analysis.

| Measure | Column(s) | Source | What it is |
|---------|-----------|--------|------------|
| **DESR enrolled** | `enrolled`, `available` | `cedar_sections` | Section headcount **as of the file pull** (`as_of_date`). One snapshot retained per term. |
| **Classlist registered** | `registered` (`calc_cl_enrls`, `R/branches/enrl.R`) | `cedar_students` | Distinct students in `STATUS_REGISTERED` — those **still registered** when the classlist was pulled. |

**Neither is a census freeze.** `CENSUS1`/`CENSUS2` are census *dates*, not counts. No census-frozen headcount exists anywhere in the raw data.

**DESR snapshot timing varies by term, and this is the trap.** For the current term the retained DESR was pulled during active registration (≈ peak demand); for past terms it was pulled after the term ended (≈ final, post-drop count).

Reconstruct any lifecycle point from classlist status codes: **census / peak** = `registered + dr_late`; **final / end-of-term** = `registered`; **total ever-registered** = `registered + dr_all`. Early drops (`DR`/`DD`) are registration churn and appear in neither census nor final counts. Late drops (`DG`/`DW`) are counted at census and gone from the final count — they are what make a course look *less* saturated at term end than it was at census.

**Use the canonical helpers, don't re-derive the formula:** `add_census_enrl(df)` adds `census_enrl = registered + dr_late`; `calc_census_enrl_baselines()` lives beside it in `R/branches/enrl.R`. Regstats uses `prior_only = TRUE` (mean and population SD from strictly earlier matching terms); the default `FALSE` preserves the Waitlists all-history reference.

**For saturation/capacity work:** derive fill rate from classlist headcounts at a single explicit lifecycle point, never from the DESR `enrolled` snapshot. Enrollment projections use `classlist_total >= scheduled_capacity` as the historical registration-capacity signal — an operational proxy, not a recovered peak-occupancy snapshot.

Regstats baseline contract (definition 3.0.0) and the Saturation report's exclusion rules: [enrollment-measures.md](docs/developers/enrollment-measures.md).

---

## Grade Constants

Defined in `R/lists/grades.R`. Use these constants for analytics; do not hardcode grade strings in cones.

| Constant | Purpose |
|----------|---------|
| `GRADES_DFW` | Known nonpassing outcomes: C-, D-range, F, W, I, NC, NR, P, S, and retake variants. Canonical classifiers also fail closed on unfamiliar recorded grades. |
| `GRADES_PASS` | Default analytics pass set: A+ through C, CR, and passing retake variants. |
| `GRADES_PASS_SUB_C_OPT_IN` | Explicit exception that also treats C- and D-range grades as passing. Never the default. |
| `passing_grades` | Grades that earn credit hours in the credit timeline. |

### CEDAR-wide DFW policy

**CEDAR's default DFW threshold treats only A+ through C and CR as passing. Every other recorded, non-audit grade plus late drops (`STATUS_DROP_LATE`) counts as DFW/nonpassing. Early drops (`STATUS_DROP_EARLY`) are NEVER DFW.** This definition is not negotiable per-cone:

- C-, every D grade, F, W, I, NC, NR, P, S, their retake equivalents, and unfamiliar nonblank grade codes count as DFW by default. AUD is excluded regardless of registration status, including DG/DW. Blank/NA grades are excluded unless late-drop status supplies the withdrawal outcome.
- A visible page control may opt in to `GRADES_PASS_SUB_C_OPT_IN`; that exception adds only C- and D-range grades to passing. It does not make P or S pass, and **it must never activate silently.** A page without the control uses the default and says so.
- A **late drop** (DG/DW) is the registration-status form of a W. Most withdrawals post as late-drop status rows, *not* as W grades, so any DFW computation that looks only at grades undercounts W.
- An **early drop** (DR) posts no grade. It is registration churn, not an academic outcome; counting it as DFW inflates failure rates with non-failures. Track early drops **separately** (`dr_early`, `n_early_drop`), never folded into DFW.

The canonical classifier is **`classify_enrollment_outcomes()` in `R/trunk/utils.R`** — used by the `cedar_grades` pre-computation and by `classify_outcomes()` (`cones/stopout.R`). Grade-only frames use `classify_grades()`. Do not write a new inline pass/DFW classification. Course-level DFW outputs flow through `get_course_outcome_rates()` (`R/branches/course-attempts.R`).

Saved `cedar_grades` carries `cedar_outcome_policy_version`, checked by `validate_cedar_grades_policy()` before Pathways outcome consumers use it. Bump `CEDAR_OUTCOME_POLICY_VERSION` when classification changes and rebuild from the current parsed `class_lists` through `transform_to_cedar(tables = "students")` — never stamp an old file, and never rebuild from the already course-deduplicated `cedar_students` (that would lose legitimate separate CRN outcomes). Docker mounts `CEDAR_DATA_DIR` from `.env`, which need not be the repository's `data/`; check the actual mount before refreshing saved files, update both runtime copies when separate, and restart the app.

---

## CEDAR-wide right-edge policy

**Never bound an analysis with `max(term)`, a hardcoded term, or arithmetic on `cedar_current_term`.** Use the edges computed once at startup by `cedar_data_edges()` (`R/branches/data-edges.R`). This is the same class of rule as the campus and DFW policies.

CEDAR's local data runs behind the registrar, and a term does not arrive all at once — registration appears months early, grades land weeks late. So "the last term in the data" is at least two different terms depending on what you ask.

| Edge | Use it for |
|---|---|
| `last_graded` (`cedar_graded_through`) | anything reading a grade: DFW, pass rates, grade distributions, stop-out after a DFW, course outcomes |
| `last_enrolled_complete` (`cedar_report_end_term`) | settled enrollment reporting, and the hard observation edge for every longitudinal analysis |
| `last_enrolled` | the raw extent of the data. **Not a reporting boundary** — it includes a term still filling |
| `last_degree` | completions |

`cedar_report_end_term` is **no longer hand-maintained**; `global.R` derives it from `last_enrolled_complete`. A term counts as settled when the newest pull covering it happened at least `min_days_after_start` days (default 14) after the term began — **never by comparing row counts to prior years**, which cannot distinguish a real enrollment decline from an unfinished term. An edge that cannot be determined is `NULL`, never a guess: fail closed. **Say which edge you used** — `cedar_edge_note()` produces the sentence.

### Grade outcomes and longitudinal follow-up require two separate right edges

**Do not cap an entire page merely because it contains a longitudinal panel.** Current registration is valid descriptive data. The hard right edge belongs to computations needing comparable history or a later observation — retention, next-term persistence, course flows, sequence effects, downstream success. Those stop at `last_enrolled_complete`; if they also read a grade, use `cedar_longitudinal_edge(edges, grade_dependent = TRUE)`. Never let a partial current term enter a longitudinal cohort, lookup, denominator, cache key, or outcome.

**A row with no posted grade is unknown, never a failure or a non-pass.** Filter grade-dependent rows to `last_graded` *before* selecting an attempt or classifying its outcome, then pass them through `classify_enrollment_outcomes()`. Never use a catch-all `TRUE ~ "failed"`: blank grades, incompletes, audits, and NR/NC are excluded from the denominator and reported as unobserved.

An A→B analysis also needs an **opportunity edge** for the A cohort. A student who took A too recently to have the declared follow-up interval is right-censored, not a non-continuer. For a one-regular-term window:

1. Compute the first possible follow-up with `add_next_term_col(..., summer = FALSE)`.
2. Exclude A rows whose follow-up term is after `last_enrolled_complete` from the continuation denominator.
3. Report the number excluded and show the data window in the page methodology.
4. Keep this separate from the B outcome edge.

For prerequisite/order questions, distinguish **strictly earlier** (`term_y < term_x`) from **same-term** (`term_y == term_x`) completion. Concurrent courses must never be described as passed "before" the focal course. When a single downstream course was already passed strictly earlier, exclude that student from the progression denominator and surface the count; for a multi-course rollup, show prior completions as context but do not infer that passing one member makes the student ineligible for every course in the set.

**Roadblocks observation grain:** `get_stopout()` selects the first eligible outcome per student/course/delivery campus after scope, population-window, and right-edge filtering. Agreeing first-term records collapse; conflicting ones exclude the comparison and are reported in `observation_info`. This does not change CEDAR's all-attempt course DFW rates — `get_dfw_rates()` is a separate ever-DFW measure and must not supply Roadblocks context.

The measured failures that established these rules: [right-edge-policy.md](docs/developers/right-edge-policy.md).

---

## CEDAR-wide campus policy

**Any analytic grouped by course must also be grouped by campus.** Wherever `subject_course` appears in a `group_cols` vector, a `group_by()`, a `count()`, or a join key, `campus` belongs beside it. Not a display preference — the same class of rule as the DFW policy, and not negotiable per-cone.

UNM is not one campus: `ABQ` is 61% of enrollment rows, online `EA` 24%, and eight branch campuses 15%. **21% of all courses are taught on more than one campus**, and they are the high-enrollment ones people actually analyse. A campus-blind aggregate is not an error or an empty table; it is a plausible number wrong by 25–35%, which is why it survives review.

Grouping is **not** filtering. Filtering to `ABQ` answers one question and discards the rest; grouping keeps every campus visible as its own row. Prefer grouping. A campus filter is a user's choice about scope, never a substitute for the grouping key.

- **Group, don't just filter.** `group_cols = c("campus", "department", "subject_course")`.
- **Carry campus through every join.** A one-row-per-campus table joined on `(department, subject_course)` fans out silently and attaches the wrong comparison value. See `R/features/gen-ed.R`.
- **Carry campus into plot keys.** A chart keyed on `subject_course` alone draws two campuses over each other with no warning. See `instructor_dfw_plot` in `R/modules/gen-ed.R`.
- **Keep headline totals independent of the display grain.** Compute totals from their own unfiltered pass, not by summing a small-cell-guarded table.
- **Sibling tables on one page must share a grain**, or the page reads as though the data disagrees with itself.

**Two campus fields.** `campus` is the campus that **taught the section**; `student_campus` is the student's **home campus**. **They disagree on 28% of enrollment rows** — Albuquerque-home students take hundreds of thousands of rows through EA and the branches. A filter on `student_campus` does *not* keep branch-delivered course rows out of a main-campus view. Course-level analytics scope on `campus`. Use `cedar_filter_campus()` / `cedar_require_campus()` (`R/lists/campuses.R`) and `CEDAR_CAMPUS_DEFAULT` rather than a bare `c("ABQ", "EA")` literal.

**Cohort vs outcome.** Scoping the cohort is not scoping the outcome. Retention's cohort is campus-scoped, but the outcome — still enrolled anywhere at UNM — is deliberately UNM-wide; narrowing it would count every inter-campus transfer as attrition. See `.build_registered_lookup()` in `R/cones/course-retention.R`.

**Deliberate exceptions** are allowed and must be commented at the site with the reason. The three that exist: `get_course_pairs()` (a pair is one student's path and may legitimately span campuses); `get_course_timing()` under `opt$group_campus = FALSE` only (trajectory questions); and enrollment projections' named `market_id = "abq_ea_course_market"` (ABQ and EA as one planning market — must prefilter to declared campuses, count each student-course once, pool capacity, and save every campus/part-term row in `delivery_components`). Other analyses may not infer an exception merely because they also use `CEDAR_CAMPUS_DEFAULT`.

**Audit enforcement.** A campus-neutral curriculum, trajectory, or named planning-market operation must carry a nearby `CAMPUS_ROLLUP:` comment explaining why no single delivery campus belongs on the result. `tests/testthat/test-architecture.R` enforces that marker for literal `subject_course` groupings.

Full reasoning and the 1.0 inventory: [campus-policy.md](docs/developers/campus-policy.md), [campus-grain audit](docs/developers/campus-grain-audit-2026-08.md).

---

## Cone Architecture

Each cone is a focused file in `R/cones/` answering one analytical question. Cones take CEDAR tables plus `opt = list()` and return a tibble or named list. No Shiny dependencies, no side effects, no calls to other cones.

**Before writing anything, read [layer-inventory.md](docs/developers/layer-inventory.md)** — the per-function index of branches, cones, features, and trunk helpers, with the parameters and behavioral caveats this file no longer carries. An existing function may already answer your question; `grep` the source for the authoritative signature.

- **`R/branches/`** — `population.R` (`build_population()`, the central cohort builder) · `comparison.R` (`build_comparison()`, `compute_balance()`) · `enrl.R` (`calc_cl_enrls()`, `get_enrl()`, census and history helpers) · `course-attempts.R` (`get_course_outcome_rates()`, `get_grade_distribution()`) · `data-edges.R` · `credit-timeline.R` · `gpa-timeline.R` · `course-flows.R` · `major-change-detection.R` · `retention-context.R` · `relative-terms.R` · `waitlist-demand.R` · `demographics.R` · `headcount.R` · `credit-hours.R` · `degrees.R` · `pathways.R`
- **`R/cones/`** — `pathway.R` (course timing + curriculum map) · `course-pairs.R` · `course-adjacency.R` · `course-sequence-effect.R` · `course-instructor-effect.R` · `course-outcomes.R` · `course-retention.R` · `retention-summaries.R` · `stopout.R` · `major-changes.R` · `gen-ed-grads.R` · `gen-ed-conversion.R` · `bottleneck.R` · `waitlist.R` · `seatfinder.R` · `cancellations.R` · `declaration-context.R` · `entry-heatmap.R` · `course-demographics.R` · `population-trend.R` · `sfr.R` · `course-neighbors.R` · `data-integrity.R`
- **`R/features/`** — `course-report.R` (Course Dynamics) · `dept-trends.R` · `dept-dashboard.R` · `gen-ed.R` · `regstats.R` · `admin.R` · `enrollment-projections.R` · `enrollment-projection-refresh.R` · `enrollment-projection-scenario.R`

**Grade data in cones:** `get_course_outcome_rates()` for DFW, W, D/F, C-, below-C, and early-drop metrics (returns `n_attempts`, `n_pass`, `n_c_minus`, `n_d`, `n_f`, `n_w`, `n_early_drop`, `dfw_pct`, `w_pct`, `df_pct`, `below_c_pct`); `get_grade_distribution()` for A/B/C/D/F/W/Other; `prepare_course_attempts()` only for row-level cleaned attempts. `dfw_pct` is `(failed + late_dropped) / (passed + failed + late_dropped) * 100`, where `failed` includes C- and other non-passing, non-W grades.

**Plot function placement.** Plot functions may live in the domain file they visualize; split files into marked calculation / plot-prep / plotting sections rather than adding a plotting layer. They accept already-prepared tibbles or result lists from their sibling helpers — never re-filter raw `cedar_*` tables, reload cached data, read global state, or recompute the analysis. Use `prepare_*_plot_data()` for shaping and `plot_*()` for construction; `term_axis_factor()` / `term_axis_levels()` for ordered term axes; `build_color_map()`, `cedar_plotly_palette()`, `CEDAR_PALETTE`, `CEDAR_SEMANTIC_COLORS` from `R/trunk/utils.R` for colour. **Native `plot_ly()` only** — no new `ggplot()` + `ggplotly()`; convert when you touch one. Never call `RColorBrewer::brewer.pal()` outside `utils.R` or create tab-local categorical palettes.

### New cone checklist

- One analytical question; never calls another cone; `opt = list()` is the final argument.
- Validate required input columns up front and stop loudly if any are missing.
- Reuse trunk/branch helpers (`filter_DESRs()`, `filter_class_list()`). After `filter_DESRs()`, call `ungroup()` immediately — it may return grouped data.
- Define an explicit output contract. Do not append `everything()` unless the cone documents that it returns pass-through columns.
- `cedar_debug()` for key row counts and branch points, guarded with `exists("cedar_log_level")` if the cone may be sourced standalone; `%||%` for optional `opt` defaults.
- Never silently recover from missing schema, malformed inputs, or empty joins that should be impossible.
- Add focused tests using the committed fixtures; no inline test tibbles.

---

## Population Architecture

A population is a tibble of `student_id`s (plus classification columns) built by `build_population()` in `R/branches/population.R` and passed to any population-aware cone. Population building is completely separate from analysis — cones accept a `population` argument and don't care how it was constructed.

**Before working in this code, read the CONCEPTS block at the top of `R/branches/population.R`.** It defines the shared ontology every Pathways analysis assumes: the six outcomes and their precedence (and why `stopped_out` is a residual, not a detection), the three independent entry axes (`origin` / `entry_method` / `entry_status`), the six per-student timestamps, the `relevant_until` enrollment-ceiling contract, and the two data-boundary rules.

```r
population <- build_population(cedar_programs, degrees = cedar_degrees, students = cedar_students,
  opt = list(
    focal_names        = c("Nursing", "Radiologic Sciences"),
    pre_major_names    = c("Biology", "Biochemistry"),
    include_pre_majors = "split"   # "majors_only" | "pre_only" | "lump" | "split"
  ))

get_bottlenecks(population, cedar_students, opt = list())
```

Key options: `focal_names`, `pre_major_names`, `include_pre_majors`, `campus` (restricts by `student_campus`), `term`.

**Cone parameter name:** population-aware cones use `population`, not `cohort`. Check the signature before passing — e.g. `detect_major_changes(programs, population = NULL, opt)`.

**`population$first_unit_term` is scoped to the focal programs.** Do NOT re-derive entry terms with `programs %>% filter(student_id %in% focal_ids) %>% group_by(student_id) %>% summarize(min(term))` — that picks up a student's entire program history, not just the focal program.

**Adding a population type:** add a `build_X_population(programs, opt)` helper in `population.R` and wire it into `build_population()`. Shiny wiring lives in `R/modules/pathways.R`.

**Observational comparisons:** use `build_comparison()` and `compute_balance()` from `branches/comparison.R`. See `course-sequence-effect.R` for the reference pattern.

---

## Trunk Helpers

Always check `R/trunk/utils.R` and `R/trunk/filter.R` before writing equivalent logic in a cone or branch. Full function tables: [layer-inventory.md](docs/developers/layer-inventory.md).

The ones you will reach for most: `add_next_term_col()` / `add_prev_term_col()` / `add_acad_year()` / `add_term_type_col()` / `term_diff()` / `fmt_term()` for term math; `filter_class_list()` and `filter_DESRs()` for the standard opt-driven filters; `keep_home_sections()` for crosslist de-dup; `validate_population()` at the top of any cone taking a population; `compute_trend()` and `compute_windowed_trend()` instead of hand-rolled `lm()` slopes.

### Filter / dplyr gotchas

- `filter_DESRs()` may return grouped data. Always `ungroup()` immediately before `count()`, `summarize()`, `group_by()`, or downstream joins.
- Do not use scalar `&&` / `||` inside `filter()` when the right-hand side is row-vector logic — it coerces a column-length vector to one TRUE/FALSE and fails on real data. Branch outside the pipeline or use vectorized `&` / `|`:

```r
filtered <- df %>%
  {
    if (length(seasons) == 0) .
    else filter(., term_type %in% seasons)
  }
```

- If a summary table intentionally uses a different filter scope than the main result, compute it as a separate named output in the cone and document that in the module caption or scope stripe.
- When filtering by status codes, set the status option explicitly for each separate filter pass. Do not assume a copied `opt` shares later mutations.
- **`compute_windowed_trend()` with `group_modify` over course *pairs* hangs** (thousands of groups × closure overhead). Use vectorized `group_by + summarize` for pair trends.

---

## Caching

General cache infrastructure lives in `R/trunk/cache.R`; Regstats keeps its own in `R/features/regstats.R`. All follow the same shape: a key builder, save/load helpers writing `.qs`/`.Rds` under `get_cache_dir()`, and a miss returning `NULL` so the caller recomputes.

**Cardinal rule 1: the cache key must encode every input that changes the result.** A filter not in the key makes two different requests collide, and the second silently gets the first's result — the filter appears dead even though the compute path is correct. When you add a filter or option to a cached feature, add it to that feature's key function *in the same change*, and verify the key string actually changes when the input changes.

**Cardinal rule 2: never persist configuration into a cached payload.** A cache stores *data*. Palettes, thresholds, feature flags, anything from `config/` belongs to the running app and must be read live on every load. A payload written under an old config otherwise keeps forcing that config on everything rebuilt from it, and the key has nothing that could notice. If a payload must record which config produced it, put that in the **key**, so a config change is a cache miss instead of a silent override.

A key must cover **every result-affecting option** (prefer hashing the whole option set over hand-listing keys, which is easy to under-specify), **data freshness** (a data hash, the current term, or a short time window — *a time-based key alone is the weakest option* and must be paired with a version counter), and **a manual version counter** bumped whenever the shape or logic of the cached output changes.

Conventions: loads return `NULL` on miss and the caller recomputes (a documented supported state, not a silent fallback); non-standard requests may bypass the cache rather than pollute it; write atomically (`.tmp` then `file.rename`) and keep live `data_objects` and configuration out of payloads. Dept Trends and the Dept Dashboard both retain built plot objects to avoid reconstructing charts; `cache_dept_tab()` strips `data_objects_filt` and `palette` and compacts the Plotly objects before saving. Dept Trends fingerprints the palette in its **key**, so a palette change is a miss; the Dashboard does not, so a palette change there requires bumping `cedar_dept_dashboard_cache_version`. `DEPT_CACHE_TABLES` declares each tab's source dependencies — add one when a tab starts reading a new source. `scripts/warm-dept-trends-cache.R` warms the standard production scope after a data refresh.

The two incidents behind the cardinal rules: [caching.md](docs/developers/caching.md).

---

## Shiny Module Pattern

Use for all new feature tabs. Do not refactor existing inline `server.R` tabs unless touching them for another reason — the `enrl_data` reactive feeds 8+ output handlers and has non-obvious shared state. Reference: `R/modules/pathways.R` (full pattern), `R/modules/headcount.R` (extraction template). Module inventory, mount points, and the table/plot/CSS gotchas: [shiny-modules.md](docs/developers/shiny-modules.md).

**CEDAR data lives in `data_objects`, not bare globals.** Tables and lookups are at `data_objects[["cedar_X"]]` and are NOT in scope inside a module server. Pass them explicitly: `pathwaysServer("pathways", cedar_students, cedar_programs, lookups = data_objects[["cedar_lookups"]])`.

- One file per module in `R/modules/`; sourced in `load-funcs.R` after cones; UI wired in `ui.R`, server in `server.R`.
- **Never put business logic in a module** — collect inputs into `opt`, call a cone, render.
- Errors caught with `tryCatch` + `showNotification()`. Slow operations in `withProgress()`. Large choice lists server-side via `updateSelectizeInput(server = TRUE)`. Do not call `handle_error()` unless it is passed in as a parameter.
- An Explore tool modeled on Open Seats or Regstats copies the full run pattern, not just the filters: loading overlay, `start_report_timer()` / `end_report_timer()`, `session$sendCustomMessage("*_load_complete", ...)`, URL copy and autorun.
- **Input values must match actual data values.** Check `transform-to-cedar.R` before hardcoding `choices =`. Level stores `"lower"`/`"upper"`/`"grad"`, not `"undergrad"`; map labels to values in the server (`opt$level <- c("lower", "upper")`), never in `choices`.
- **Tables are user interfaces, not raw cone dumps.** Each table picks an explicit display-column order; hide fields in the module `select()`, not by removing them from the cone output.
- **Prefer shared UI helpers and existing CSS classes** over tab-local styling — no inline `style =` or one-off classes; extend a shared helper and migrate callers. Reuse display components across related tables (one course-overview reactable serves four tabs).
- **Every section is a heading plus a one-sentence description** giving scope, denominator, and exclusions. `filter_bar()` → `subtab_header()` → `dashboard_section()` → `dashboard_subsection()` → `section_heading()`. A subtab opens with `subtab_header()`, never a section bar. **Never use a bare `h3()`–`h6()`.** Two sections showing the same numbers is a bug. Shared metric text is authored in `docs/_data/definitions.yml` and rendered with `cedar_definition_note()` / `cedar_definition_panel()`.

### URL deep links & shareable state

One registry, `CEDAR_SHARE_SPECS` (`R/trunk/url-state.R`), drives **both** directions of the round-trip so they cannot drift. Each entry is keyed by the exact navbar tab title and declares `slug`, `prefix`/`sep`, ordered `fields` (the only accepted URL keys, in dependency order), `run`, and optional `types`/`aliases`/`overlay`.

- **Copy:** `cedar_copy_url_observer(input, session, copy_id, values_fn, spec_title)`.
- **Bootstrap:** `ui.R` sends `cedar_link_bootstrap` once; `cedar_link_server()` parses that exact string. Never read `clientData$url_search` independently.
- **Restore:** `cedar_schedule_link_restore()` applies fields one at a time in registry order, waiting for each to round-trip. If a value cannot be restored, autorun does not run with a different scope.
- **Run:** the ordinary observer consumes `cedar_run_trigger()`. One entry point — no synthetic browser click, no tab-specific autorun observer.
- **Tabs:** `CEDAR_TAB_SLUGS` is serialized to the browser; never add a hand-maintained JavaScript slug map.
- **Server-side selectize stays module-owned:** initialize through `cedar_linked_server_selectize()` and declare the key `type = "select_server"`. A second controller-side write can make a transient value look ready before module init settles.

**Headcount is deliberately not deep-linkable in 1.0** — six cascading server-side selectizes, no share spec, no copy button. Its program filters intersect `(student_id, term)` pairs: AND across filters, OR within each selection. Never intersect student IDs across history to claim simultaneous membership.

---

## Opt List Convention

All cones accept `opt = list()` as their last argument, resolved inside the function with `%||%`:

```r
min_n  <- opt$min_n  %||% 10L
campus <- opt$campus %||% NULL
```

Common keys: `term`, `campus`, `dept_code`, `college`, `level`, `min_n`, `cohort_ids`, `subject_code`, `start_classification`, `include_summer`.

---

## Naming Conventions

| Context | Name | Example |
|---------|------|---------|
| CEDAR table column | `department` | `filter(department == "HIST")` |
| Filter option objects | `dept_code` | `opt$dept_code` |
| Report parameter objects | `dept_code` | `d_params$dept_code` |

Option objects use `dept_code` because the value is a code. Leave the CEDAR table column name `department` alone; this is a code convention, not a schema rename. `department_code` is not used anywhere.

Known variations still in use: student count (`enrolled`, `registered`, `count` in `enrl.R`), drop types (`dr_early`, `dr_late`, `dr_all`, `drops`), program reference (`prog_codes`, `prog_names`, `program_code`, `program_name`).

---

## Key Data Flow Notes

- `dept-trends.R` passes **unfiltered** `cedar_students` to `get_credit_hours_for_dept_report` (needed for college vs. dept comparison), but **filtered** students to `credit_hours_by_major` and `credit_hours_by_fac`.
- `credit_hours_data` has a `level` column: `"lower"`, `"upper"`, `"grad"`, `"total"`. Filter to `"total"` to avoid double-counting.
- `appointment_pct` in `cedar_faculty` is stored as 0–100; divide by 100 for FTE.
- `get_stopout()` requires `add_next_term_col()` from utils.R — called internally.
- `%||%` is defined in `utils.R`. Cones sourced standalone include a local fallback at the bottom of the file.
- The cleanup backlog and refactoring priorities live in `ROADMAP.md` — check it before touching any file listed there.

---

## Coding Standards

### No fallback behavior

**Never write silent fallbacks.** If a required column is missing, a join produces no rows, or an input is malformed, raise an explicit error. Do not substitute defaults, return empty results, or silently skip.

```r
result <- tryCatch(get_something(df), error = function(e) tibble())   # Wrong — hides the problem
dept   <- df$dept_code %||% df$department                             # Wrong — silent coalesce
if (!"dept_code" %in% names(df)) stop("dept_code column required")    # Right — fail loudly
```

Applies everywhere: cones, branches, trunk, pipeline scripts, test helpers. Only two `tryCatch` uses are allowed: in a Shiny module server where the error is immediately shown via `showNotification()`, and around a genuinely fallible *statistic* (`chisq.test` on a degenerate table) where `NA` is the correct mathematical answer. **`tryCatch(..., error = function(e) NULL)` around a data pipeline is always a bug.**

### Reuse before writing

Search in order: `R/trunk/utils.R` and `filter.R` → `R/lists/` (never inline `c("RE","RS","RR")` or grade strings) → `R/branches/` → the cone inventory. Concretely: `grep -rn "your_concept" R/trunk R/branches R/lists` before writing a helper. Duplicated logic found later gets consolidated *up* a layer, never copied sideways.

**Standardize counts and shared visuals — always prefer a helper.** There is exactly one canonical definition of each way of counting: census enrollment is `add_census_enrl()` / `calc_census_enrl_baselines()`, DFW is `classify_enrollment_outcomes()`, term type is `add_term_type_col()`. Don't re-derive `registered + dr_late`, a grade filter, or `substr(term, 5, 6)` by hand. Enrollment history has `summarize_term_enrl_series()`, `format_term_history()` (values first, terms after — `"12, C, 10 (Fa22, Sp23, Fa23)"`), and `drop_shell_sections()`. Shared visuals — sparklines, fill bars, tier badges, trend cells, reactable column defs — live in `R/modules/ui-helpers.R`; a new tab uses the shared sparkline, it does not hand-roll SVG. When a computation is inline and you touch nearby code, promote it to a helper and migrate the other callers.

### Numeric precision and identifier display

**Round for display only.** Calculations use unrounded values; round once in the final display adapter. Never round an input or intermediate before computing a rate, difference, average, trend, or SMD.

- **Do not apply one generic formatter to semantically different columns.** Counts, percentages, continuous means, diagnostics, and numeric-looking identifiers need separate column definitions or a row-aware shared formatter.
- Counts whole (thousands separators fine); percentages one decimal; GPA and means two; SMDs three. Increase precision when the default would collapse meaningfully different values — never render `3.26` and `2.98` as `3` beside a reported difference.
- Missing values display as an em dash, not `0`, unless zero is measured.
- **Identifiers are not quantities** — term codes, CRNs, student IDs, and course numbers get no separators, decimals, or abbreviation.
- Prefer or extend shared formatters in `R/modules/ui-helpers.R`; keep cone outputs numeric and analysis-ready.

### Readable package calls

Prefer bare function names for packages the app already loads (`filter()`, `mutate()`, `bind_rows()`). Use an explicit namespace only to prevent ambiguity, to call a package that is not normally attached, or to flag an uncommon dependency.

### Complexity budget

New cone functions under ~150 lines; a cone file past ~500 lines splits by sub-question or extracts branch helpers. A module is UI + server for one tab in one file; a module server past ~300 lines means business logic has leaked in. **No new dependencies without explicit user approval** — prefer what `renv.lock` pins.

### Every change ships with

- For changed analytical behavior, regression coverage in the existing relevant `tests/testthat/` suite, filtering from the committed fixtures (never inline tibbles). Prose, CSS spacing, and source rearrangement do not need assertions that restate the edit. Extend an existing suite before adding a file.
- Updated tables in this file if you added or renamed a cone, branch, or module — and in [layer-inventory.md](docs/developers/layer-inventory.md) if a signature changed.
- **No custom testing scripts.** Use the committed harnesses and gates below.

---

## Test Infrastructure

Full reference: **[agent-testing.md](docs/developers/agent-testing.md)** (fixture
conventions, environments, module loading, ad-hoc workflows),
[testing.md](docs/developers/testing.md) (philosophy),
[e2e-testing.md](docs/developers/e2e-testing.md) (browser harness).

All test data is hand-crafted tribbles in
`tests/testthat/fixtures/designed_test_data.R` — that file IS the test database.
`setup.R` exposes `test_sections`, `test_sections_sf`, `test_students`,
`test_programs`, `test_degrees`, `test_faculty`, `test_lookups`, `data_objects`.
Stable terms 202010/202060/202080/202110. Its header holds pinned expected counts
that tests hard-code against — **update the header and the affected tests in the
same change** as any fixture edit. New rows follow **EC-xx** / **XLxx** /
**SVARxx**. No regeneration script, no drift check: test failures are the signal.
`tests/testthat/create-test-fixtures.R` is dead legacy; rows added there are seen
by no test.

- Expected values are committed after running against fixtures. If one changes, the function or fixture changed — investigate before updating.
- Missing fixture columns get added to `designed_test_data.R`. Never add fallback logic in tests or fixtures. Use `uel = FALSE` in filter tests to isolate from `excluded_courses`.
- **Domain data belongs in `designed_test_data.R`; one function's input contract does not.** The failure this prevents is a test passing because the fixture *cannot express the bug*. Raw enrollment/section/program/degree rows — multi-campus delivery, waitlists, crosslists, repeats — go in the shared fixture. Intermediate frames, expected-value tables, scaffolding, and scenarios needing terms outside the stable set are built locally with expected values documented above them. The tell is reusability.
- **Never write throwaway/scratch tests, and don't fragment code or fixtures just to make something testable.** If the fixtures can't represent the case, fix the fixtures — that is the correct path, and it makes the case reusable.
- **A fixture too simple to express the bug produces a test that passes forever without checking anything.** Reintroduce the bug and confirm the test fails before trusting it. Mandatory for any test guarding a join key, a grouping grain, or a dedup.

### Running tests

**NEVER WRITE CUSTOM TESTING SCRIPTS.** No temporary runners, one-off browser
scripts, shell wrappers, copied e2e variants, Python probes, R scratch tests, or
bespoke "smoke" commands — they become a second, untrusted test system. The only
allowed entry points are the gates below, focused `testthat::test_file()` /
`test_dir()` against committed files, and the committed scripts in `tests/e2e/`.
Exploratory diagnostics stay in the session scratchpad, never in the repo, and are
never presented as release verification.

Start from the host repo root: `/Users/fwgibbs/Dropbox/projects/cedar-project/cedar`.

Choose checks by the behavior changed. A fresh container and the breadth of
browser coverage are separate decisions.

| Change / occasion | Required checks |
|---|---|
| Calculation or data contract | Focused committed R tests while editing; `./run-tests.sh` once when finished |
| UI, routing, or module wiring | R gate plus `./run-tests.sh --e2e <suite>` covering the changed behavior; inspect layout changes visually |
| Representative app check | `./run-tests.sh --e2e` (same as `--e2e smoke`): Enrollment and Course Dynamics |
| PR acceptance | The Docker/synthetic CI gate (`.github/workflows/pr-checks.yml`, check name `Synthetic checks`) |
| Release candidate or major data-pipeline change | `./run-tests.sh --all`: rebuild and run the full institutional browser suite |
| Dependency / R / Docker toolchain change | Verify the pinned native and Docker environments; run their R gates and synthetic acceptance |
| Documentation or presentation-only edit | Check links or affected appearance; no full R/browser run for prose, spacing, or colour alone |

**`./run-tests.sh --changed` reads the diff and selects the stages from it**,
printing one line of reasoning per file — a cone edit gets the R suite and no
browser, an `R/modules/**` edit gets both, a docs-only edit gets nothing. It
selects; it never certifies. It cannot know that a cone change moved a rendered
number, so widen it by hand when the blast radius is larger than the paths
suggest, and it is never a release pass.

The gate stops at the first failed suite and is not automatically retried;
diagnose an app, setup, or resource failure before rerunning. **Do not quote
runtimes as budgets** — cost depends on the machine, emulation, data, and cache
state, and a timeout does not identify its own cause. **When reporting results:**
name the exact command, pass/fail counts, known skips, whether Chrome/app setup
succeeded, and whether the image was rebuilt. A run that failed before Chrome
launched is a setup failure, not an app failure; a browser run against an old
container is not release evidence, and focused or synthetic success is not a
full institutional pass.

**One CEDAR app, one port.** Every browser suite targets `http://localhost:3838/`,
and only one CEDAR app runs at a time. The synthetic stack (`compose.dev.yml`)
and the institutional one (`docker-compose.yml`) are alternatives that share the
port, not neighbours — stop one to start the other. `run-tests.sh` reads the
served page to identify which surface answered and refuses a suite aimed at the
other. Details and the memory-pressure failure mode: [e2e-testing.md](docs/developers/e2e-testing.md).

**Two paths, and they cost an hour every time they are forgotten.** Host:
`/Users/fwgibbs/Dropbox/projects/cedar-project/cedar` for everything local.
Inside the container: `/srv/shiny-server/cedar` — **not** `/srv/shiny-server`,
which is the stock Shiny sample directory and gives `No test files found`, reading
like a broken image rather than a wrong `-w`.

**`--vanilla` is required.** Cedar is a Shiny app, not an R package —
`devtools::test()`, `pkgload::load_all()`, and `test_local()` all fail, there is
no `DESCRIPTION`. `--vanilla` skips `.Rprofile` and automatic data loading, which
keeps CLI and test startup explicit. A missing-package error usually means you
omitted `--vanilla`, or named the wrong package: the data files are **qs2**, not
qs, and `qs::qread()` fails with the unhelpful "QS format not detected".

**Dependencies go through `scripts/r-environment.R`, never a bare renv call.**
`renv.lock` pins the tested packages and R version; there is no runtime
activation. Native setup is `Rscript --vanilla scripts/r-environment.R restore`,
which copies exact matches into `renv/library/cedar/...` rather than cache
symlinks and rewrites no startup files; `check` / `check-native` are read-only
drift checks. `./run-tests.sh` tests system R by default, `--project-library`
selects the prepared native library. **Never run `renv::deactivate()` or a bare
`renv::restore()` to repair a library error** — `deactivate()` rewrites
`.Rprofile` as a side effect and already caused one unrelated startup regression
(`e4237fd`, reverted). Setup procedures: [installation.md](docs/developers/installation.md).

**Three environments; the failure mode is skipping the one that would have caught
the bug.** `Rscript --vanilla` for cones/branches/features; the Dockerized app for
anything rendered; headless Chrome for driving it. Cost depends on the machine,
architecture/emulation, data, and cold caches — do not turn one measured runtime
into a guarantee or a budget. **A UI change verified only by a green R suite is
unverified.** **The container bakes source with `COPY`** — only `data/`
is bind-mounted, so a running container does *not* pick up code changes. Check
`docker ps` before trusting what you see; rebuild with `./rebuild-and-test.sh`.

What the R suite cannot see:

| You changed | Also do this |
|---|---|
| One cone / branch function | nothing extra — pure functions over fixtures |
| A `group_cols`, join key, or grouping grain | an ad-hoc real-data check — fixtures are often single-valued on the axis you changed, so they pass while production breaks (this is how a campus-blind grouping shipped green) |
| A `list(...)` return shape from a cone | grep the renderers that read it — nothing checks that the UI still reads every field |
| Module UI / `ui.R` / `server.R` | parse check, render the UI function, then look at it — **module code is not loaded by the test suite** (`load_funcs(..., modules = FALSE)`) |
| CSS only | check no later rule overrides yours, then look at it |
| Anything user-visible, before a release | rebuild the container and actually look |

**What NOT to do:** `source('setup.R')` from outside `tests/testthat`; `source('global.R')`
(triggers the setup wizard); hand-sourcing `R/modules/*.R` (use `load_funcs(..., modules = TRUE)`);
running R just to discover an expected value (assert something obviously wrong and
read the real value from the failure diff); leaving scratch scripts in `tests/`.
After a failing run, `rm -rf tests/testthat/_problems tests/testthat/testthat-problems.rds` —
neither is gitignored.

**Ad-hoc checks against real data:** don't hand-roll the bootstrap, it has four
gotchas. `Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_students)'`
sets both required globals, loads the functions, and lazily exposes the tables.

**Text-first feature previews.** For a computation-heavy feature, stabilize a
canonical non-Shiny text preview before building its Shiny surface. It must be a
**committed production formatter** over the feature payload — not a scratch
script, not a second implementation. The formatter owns display formatting only;
neither tests nor the UI may parse its rendered text, both consume the typed
payload. **A text preview is computational evidence, not UI evidence.**

### Enrollment projection contract

Full contract: [enrollment-projections.md](docs/developers/enrollment-projections.md).
Findings and rejected assumptions: [forecasting-lessons.md](docs/developers/forecasting-lessons.md).
The rules an agent must not violate:

- The forecast target is **unique total class-list demand** — not DESR final enrollment, not census.
- **Capacity is an audit and planning comparison, never a demand predictor.** A reached-capacity overprojection is labeled `Capacity-bounded`; never display its one-sided technical zero as ordinary 0% error.
- Observed-enrollment methods select the published demand row. Broad population, major/classification, and feeder methods are structural evidence and never silently replace or average with it.
- **Weak rows remain visible** with an explicit `Unrated`/`None` axis value and a reason. Do not withhold them, relabel them, or invent a default. Projections carry three independent reader-facing axes — `stability` (model-free, from the course's own history), `depth` (comparable aftcast evidence), `accuracy` (how close those aftcasts landed). They may disagree; never collapse them into one label.
- Miss explanations say `Potential explanation` / `Potential contributor` — not causal claims.
- Shiny and Course Dynamics read validated artifacts through `load_latest_enrollment_projection_bundle()` / `load_enrollment_projection_bundle()` and `build_enrollment_projection_view()`. They **never** fit, aftcast, pressure-screen, calibrate, or select a model in a user session.
- **Horizon, not season, decides which methods apply.** The upstream-anchored and feeder methods read the population of the term immediately before the target; two steps past the settled edge that term is itself unobserved, so they drop out and the bundle publishes from observed baselines alone. Which season is the two-step target alternates through the year. A bundle with no applicable structural candidate reports `demand_signal = "Not indicated"` on every row — an absence of evidence, never evidence that there is no latent demand.
- **One bundle per season, never "the latest".** Spring and Fall publish separately and neither supersedes the other, so discovery is season-aware: `find_enrollment_projection_bundles()` lists what is saved and every loader names either a season or an exact target term. Picking the highest saved target term would hide Spring the day Fall publishes. Summer is refused at the builder — a different demand regime with no comparable evidence base.
- **A growth scenario is arithmetic over saved rows, never a second forecast.** `build_enrollment_projection_scenario()` grows one named population's cohort and holds every other student in the course flat. Year 1 *is* the published projection at any growth rate; later years are labeled `Scenario`, carry no accuracy axes, and never borrow year 1's. Show the population's share of the course — 10% growth on 13% of a roster is a 1.3% course effect, and a reader who cannot see the share will assume the whole course grew.
- **Named populations come from `CEDAR_POPULATION_GROUPS`** (`R/lists/population-presets.R`), shared by Pathways and projections so a group means one thing everywhere. Groups declare *program names*; `population_group_major_codes()` resolves them to Banner codes through both name matching and `premaj_canon`, because each alone misses real pre-majors. Never hand-list codes in a caller, and run `population_group_audit()` when adding a group — its `near_miss` output is how a drifted name is caught instead of silently dropped.
- `model_version` changes for calculation/selection/calibration/scoring; `schema_version` for artifact shape. Reused bundles are never rewritten.
- A new method is incomplete until the registry, branch candidate, rolling aftcast, bundle validator, text preview, designed fixture, real-data audit, and any affected UI/browser test agree.

### E2E rules — the four that cause every flake

`tests/e2e/lib.mjs` solves each; use the helper rather than re-deriving it.

1. **Never `sleep()` to wait for Shiny — use `waitForIdle()` / `runAndWait()`.** A fixed sleep races the app, and "wait for non-empty text" passes instantly on the *previous* run's output. Only visible outputs count toward idle.
2. **`connect()` must settle before you touch inputs** — inputs set before the landing tab's first reactive flush are overwritten by the app's own initialisation.
3. **`offsetParent !== null` is not a visibility test** — it also returns null inside `position: fixed`/`sticky` ancestors, which in bslib includes the sub-tab bars. Use `Element.checkVisibility()`.
4. **Selectors rot silently — run `node tests/e2e/check-ids.mjs`** (stage 1 of `run-tests.sh`). For a string a test asserts is *absent*: `// check-ids-ignore: <names>`.

`connect(page, { tab })` takes options, not a URL. Scope queries with
`queryActive()` / `activeText()` — every tab's markup is in the DOM at once.
Module input ids are namespaced (`gen_ed-ge_button`). `openSubTab()` waits for the
pane; `clickSubTab()` only fires the click.

---

## Sample Data

`bash scripts/dev.sh up` starts the standalone `compose.dev.yml` project on localhost:3838 — the same port as the institutional app, so stop one before starting the other. It mounts source read-only, uses private demo-only Docker volumes, and never reads production `.env` or mounts institutional data. Use `restart` after edits and `test` to invoke the standard gate inside a disposable image. Production Compose still bakes source and requires rebuilding.

`dev/demo-data.R` adapts the `designed_test_data.R` scenarios into a synthetic multi-year institution; the unit fixtures themselves are never rewritten. Five copied cohorts retain `fixture_source`, `fixture_student_id`, and `synthetic_cohort` provenance — select cohort 1 and the relevant scenario to recover the original expectations. The generator uses the production transforms and fixes the current term at Fall 2025. Extend `test-demo-data.R` when changing its known answers. **Do not weaken analytical rules or small-cell guards to populate a demo.** See [synthetic-institution.md](docs/developers/synthetic-institution.md) for export and provenance, and `docs/developers/first-hour.md` for contributor steps.

`data/samples/desr_sample.csv` — 297 rows of real DESR data (gitignored), covering split-level XL, non-split XL, SHORT_TEXT variations, multi-way XL, zero-enrollment, and lab sections. See `data/samples/README.md`.
