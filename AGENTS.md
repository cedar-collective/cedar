# CEDAR Development Reference

**For AI agents doing broad codebase work** — debugging, adding features, understanding architecture, navigating modules, or working across multiple files. This is the comprehensive reference: full architecture, data model, coding standards, module patterns, CSS gotchas, test infrastructure, and refactoring status.

**If you are writing a single new cone**, use `AI-REFERENCE.md` instead — it is compact enough to paste directly into a chat context and covers exactly what cone-writing requires.

**Instructions for agents:** Trust the layer rules (trunk/branches/cones/reports) and the coding standards sections — they reflect hard-won decisions, not suggestions. Check the refactoring status before touching any file listed there. When in doubt about data structure, the authoritative source is `R/data-parsers/transform-to-cedar.R`.

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
| `cedar_programs` | ~200k | `student_id`, `term`, `program_name`, `program_code` (Banner), `program_type`, `dept_code`, `college_code`, `student_campus`, `student_college`, `student_population`, `inst_credits_attempted`, `overall_credits_earned`, `pell_eligible` (logical, per-term), `first_gen` (logical, per-term), `ipeds_race`, `gender`, `time_status` |
| `cedar_degrees` | ~20k | `student_id`, `term`, `degree`, `degree_abbr`, `program_name`, `program_code`, `dept_code`, `banner_program_code`, `cumulative_gpa`, `cumulative_credits` |
| `cedar_faculty` | ~5k × terms | `instructor_id`, `term`, `instructor_name`, `department`, `academic_title`, `job_title`, `job_category`, `appointment_pct` (stored 0–100, divide by 100 for FTE), `college`, `as_of_date` |
| `cedar_lookups` | — | Named list: `program_name_lookup` (program_name→dept_code), `dept_name_lookup` (dept_code→display name), `dept_lookup` (raw dept string→dept_code), `college_code_to_name`, `subject_lookup` (tibble: `subject_code`, `dept_code`, `college` — maps subject prefixes to dept codes; invert to get all subject prefixes for a dept_code) |

**`cedar_programs$dept_code`** is derived via 3-tier lookup during transform:
1. `pc_dept_lu["program_code:college_code"]` — compound key from `program_catalog` (most accurate)
2. `subj_to_dept[program_code]` — subject code fallback from `subj_dept_map`
3. `program_code` itself — last resort identity mapping

**`dept_code` ≠ subject prefix in `subject_course`.** For example, Geography has `dept_code = "GES"` but its courses appear as `"GEOG 101"` in `subject_course`. `major_code` in `cedar_programs` is also not a reliable subject prefix. To get subject prefixes for a given dept, use `cedar_lookups$subject_lookup`:
```r
# Subject prefixes for dept "GES" → c("GEOG")
cedar_lookups$subject_lookup %>%
  filter(dept_code == "GES") %>%
  pull(subject_code)
```
Never filter `subject_course` by `dept_code` directly — always go through `subject_lookup`.

**`cedar_students$major`** is the raw Banner program code (e.g., `"NURS"`), not a human-readable name. To get program names or dept_code from it, use `prgm_to_dept_map` or join against `cedar_programs`.

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

## Grade Constants

Defined in `R/lists/grades.R`. Use these constants for analytics; do not hardcode grade strings in cones.

| Constant | Purpose |
|----------|---------|
| `GRADES_DFW` | Outcomes that count as DFW for analytics (`D`, `D+`, `D-`, `F`, `W`, retake variants) |
| `GRADES_PASS` | Outcomes that count as passing for analytics (C or better, CR, P, S, retake variants) |
| `passing_grades` | Grades that earn credit hours — intentionally excludes D grades; do not use for DFW analytics |

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
| `gradebook.R` | `get_grades(students, opt)`, `add_instructor_type(grades, cedar_faculty)` | DFW rates by course/instructor/term; call `add_instructor_type()` separately to add TT/NTT breakdown (CAS only) |
| `headcount.R` | `get_headcount(programs, opt)` | Student enrollment counts by program |
| `credit-hours.R` | `get_credit_hours(students, opt)` | Credit hour production |
| `degrees.R` | `count_degrees(degrees, opt)` | Degree completion counts |

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
| | `create_seatfinder_report(students, courses, cedar_faculty, opt)` | — | Renders seatfinder Rmd report |
| `waitlist.R` | `get_waitlist(students, opt)` | — | Waitlist counts by course/major |
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
| `course-demographics.R` | `get_course_demographics(students, opt)` | — | Major/classification breakdown per course |
| `sfr.R` | `get_permanent_faculty_fte(faculty, opt)` | — | Faculty FTE by dept |
| `gened-fulfillment.R` | `get_gened_fulfillment(...)` | — | Gen ed area fulfillment by major |

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

Reports call multiple branches/cones and render Rmd output. They follow different rules than cones: they may call other cones.

| File | Main function(s) | Purpose |
|------|-----------------|---------|
| `course-report.R` | `get_course_report_data(students, sections, opt)` | Assembles enrl + gradebook + lookout + forecast → HTML/ASPX |
| `dept-dashboard.R` | `create_dept_dashboard_data(...)` | Dashboard metrics and plots for one dept (assembles headcount, enrl, credit-hour trends) |
| | `get_subject_current_stats(sections, subject, term)` | Lightweight current-term snapshot: returns `list(n_sections, total_enrl)` for a subject, crosslist-deduplicated. No full dashboard pipeline. Reusable in dashboard cards, comparison views, future API endpoints. |
| `dept-report.R` | `get_dept_report_data(...)` | Assembles headcount + degrees + credit-hours + gened → HTML/ASPX |
| `regstats.R` | `get_reg_stats(students, courses, opt)` | Enrollment anomaly detection (calls enrl, course-demographics, waitlist branches) |
| | `filter_downstream_by_dept(downstream_df, dept, sections)` | Filters downstream registration signals (dest_course pairs) to only destinations in a given dept's subjects. Pass empty/NULL dept to return all rows unchanged. Eliminates a DRY violation — was duplicated in two server.R render blocks. Reusable in any downstream signals display. |
| | `create_regstat_report(students, courses, opt)` | Renders regstats Rmd |

---

## Population Architecture

A population is a tibble of `student_id`s (plus classification columns) built by `build_population()` in `R/branches/population.R` and passed to any population-aware cone. Population building is completely separate from analysis — cones accept a `population` argument and don't care how it was constructed.

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

**Adding a new population type:** Add a `build_X_population(programs, opt)` helper in `population.R` and wire into `build_population()`. The Shiny wiring lives in `R/modules/pathways.R`, which contains `cohortBuilderUI` / `cohortBuilderServer` — the UI still uses the word "cohort" in its internal names even though the underlying branch was renamed to `population`.

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

## Shiny Module Pattern

Introduced with the Pathways tab. Use for all new feature tabs. Do not refactor existing inline tabs unless there's a separate reason to touch them.

**Reference implementation:** `R/modules/pathways.R`

```
R/modules/pathways.R
  cohortBuilderUI(id, program_choices, campus_choices)
  cohortBuilderServer(id, programs)    → returns reactive cohort tibble
  pathwaysUI(id, program_choices, campus_choices)
  pathwaysServer(id, students, programs, degrees = NULL)
```

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
- `pathwaysServer` shows the correct pattern: slow operations wrapped in `withProgress()`, errors caught with `tryCatch` + `showNotification()`, large choice lists sent server-side via `updateSelectizeInput(server = TRUE)`
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
- If using URL autorun, update both `tab_aliases` and `tab_prefixes` in `server.R`, plus the client-side tab map and overlay map in `ui.R`.
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
- Do not refactor Enrollment, Headcount, Regstats, etc. unless touching them for a separate reason. The `enrl_data` reactive feeds 8+ output handlers and has non-obvious shared state.
- Headcount (`hc_data`, ~line 418 server.R) is the best candidate for extraction if the opportunity arises — it's largely self-contained.

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

### Phase 1: Quick Cleanup
- [x] Rename `rollcall.R` → `course-demographics.R`; `rollcall()` → `get_course_demographics()` (all call sites updated)
- [ ] Delete `R/cones/course-report-orig.R` (380 LOC, no references)
- [ ] Delete `Rmd/dept-report-orig.Rmd` (no references)
- [ ] Remove commented-out code from Rmd files
- [x] Add `STATUS_REGISTERED <- c("RE", "RS", "RR")` and `STATUS_WAITLIST` to `status_codes.R`
- [x] Add `GRADES_DFW` and `GRADES_PASS` to `R/lists/grades.R`
- [x] Update `stopout.R` to use shared constants
- [x] Add `dedup_enrollment()` and `classify_grades()` to `trunk/utils.R`
- [x] Restructure layers: trunk/ (infrastructure), branches/ (domain computations), cones/ (single-question), reports/ (orchestrators)
- [x] Remove `is_lab` flag — defined but never consumed by any analysis. L-suffix courses remain in all counts.
- [x] Extract `get_course_section_counts()` from server.R inline block → `enrl.R`
- [x] Extract `filter_downstream_by_dept()` from two duplicated server.R blocks → `regstats.R`
- [x] Extract `get_subject_current_stats()` from server.R inline block → `dept-dashboard.R`
- [x] Replace all inline `c("RE", "RS", "RR")` with `STATUS_REGISTERED` in pathway.R, bottleneck.R, and test files
- [x] Remove dead `get_course_list()` from utils.R (zero callers)
- [x] Remove studio testing comments from enrl.R and seatfinder.R
- [x] Remove always-on DEBUG messages from headcount.R
- [x] Add `validate_population()` to utils.R; replace duplicate inline checks in pathway.R, stopout.R, bottleneck.R
- [x] Add arithmetic comments to `add_next_term_col()` explaining the YYYYSS offset math
- [x] Add rationale comments to `min_n` defaults in stopout.R and pathway.R
- [x] Add year-band rationale comment to credit thresholds in pathway.R
- [ ] Standardize `dept` vs `dept_code` in opt objects (large sweep, low priority)

### Phase 2: Shiny Modules
- [x] **Pathways tab** — complete, in `R/modules/pathways.R`. Use as reference.
- [ ] Headcount module (most self-contained of existing tabs)
- [ ] Seatfinder module
- [ ] Others only when the tab needs significant new work anyway

### Phase 3: Break Up Long Cone Functions
- [ ] `enrl.R` (936 LOC): extract `count_by_status()` from repeated filter/summarize blocks
- [ ] `regstats.R` (933 LOC): separate cache management from analysis
- [ ] `credit-hours.R` (876 LOC): split `get_credit_hours_for_dept_report` into sub-functions
- [ ] `lookout.R` (757 LOC): decompose anomaly detection from trend analysis

### Phase 4: Externalize Domain Data
- [ ] Move department/program mappings in `mappings.R` to YAML/CSV
- [ ] Make college code configurable (currently hardcoded `"AS"` in `credit-hours.R`)
- [ ] Document all remaining hardcoded domain values

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

---

## Test Infrastructure

Fixtures are committed `.qs` files built from real CEDAR data. They are the test database — stable, flat, and not re-generated unless the schema or test coverage needs change.

**Fixture files** (`tests/testthat/fixtures/cedar_*_test.qs`) — committed to the repo, loaded by `setup.R` as `test_sections`, `test_students`, `test_programs`, `test_degrees`, `test_faculty`.

**Stable terms:** 202010, 202060, 202080, 202110 (Spring/Summer/Fall 2020, Spring 2021). Graded, complete, never change.

**Departments:** HIST, MATH, ANTH, NURS (sections/students); HIST, MATH, ANTH (faculty — CAS only; nursing faculty are not in the HR extract).

**When to regenerate fixtures** (run `Rscript tests/testthat/create-test-fixtures.R` then commit):
- A column is renamed or removed in `transform-to-cedar.R` — tests will fail until you regenerate
- A new column is added that tests depend on — ditto
- Test coverage needs a real-data scenario not currently in the sample

**When NOT to regenerate:** Schema didn't change and existing coverage is sufficient. The committed `.qs` files are the ground truth; don't regenerate just because new data came in.

**Adding an edge case** that doesn't appear in real data: add rows inline in `create-test-fixtures.R` in the clearly marked edge-case block near the bottom of each table's assembly section, then regenerate and commit. Update hard-coded expected values in affected test files.

**Schema drift detection:** `require_cols()` in `create-test-fixtures.R` stops loudly if required columns are missing. This only runs during regeneration, not during `devtools::test()`. Test failures are the runtime signal that fixture and code schemas have diverged.

**Known data limitation:** `cedar_faculty` only contains CAS departments. Tests that join faculty data will produce results only for HIST/MATH/ANTH — correct behavior, not a gap.

**Rules:**
- Test expected values are hard-coded from running functions against fixtures, then committed. If a value changes, it means the function or fixture changed — investigate before updating.
- `uel=FALSE` in filter tests: the `uel=TRUE` default applies the `excluded_courses` list and mutates `subject_course`. Filter logic tests should use `make_opt(uel = FALSE)` to isolate from this behavior.
- If required columns are missing from fixtures, fix `transform-to-cedar.R`. Do not add fallback logic in tests or fixtures.
- **No inline fixtures in test files.** Never construct tibbles inside a `test_that()` block to feed a function under test. All test data lives in `fixtures/designed_test_data.R`; tests filter from `test_sections`, `test_students`, etc. Inline tibbles produce tests that pass by construction rather than tests that verify real behavior against representative data.

### Running tests

Cedar is a **Shiny app, not an R package**. Do not use `devtools::test()`, `pkgload::load_all()`, or `library(cedar)` — none of these work.

**Always `cd` to the project root first**, or all relative paths in `setup.R` and fixture sources will be wrong:

```bash
cd /Users/fwgibbs/Dropbox/projects/cedar
```

**Run all tests:**
```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

**Run a single test file:**
```bash
Rscript -e "testthat::test_file('tests/testthat/test-population.R')"
```

**What NOT to do:**
- Do not `source('setup.R')` from the shell — that triggers the interactive Cedar setup wizard, not the test setup.
- Do not try to load functions manually with `source('R/...')` or `source('global.R')` for ad-hoc scripts — the `global.R` also triggers interactive prompts. The `testthat::test_file()` / `test_dir()` runner sources `tests/testthat/setup.R` automatically, which calls `load_funcs()` and loads the fixture data.
- Do not try to get actual computed values by running R outside of testthat. Test failures already show the computed value in the diff — `expect_equal(x, 5)` failing prints the actual value of `x`. If you need to discover what a new function returns before you know the expected value, write `expect_equal(result, NULL)` or any obviously wrong value; the failure output reveals the real one.

**renv:** Handled automatically by `.Rprofile` — no manual activation needed.

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
| `CENSUS1`, `CENSUS2` | Enrollment at census dates |

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

## Building a New Cone: Retention (`course-retention.R`)

**Goal:** Compare next-term retention rates across courses, and track how a single course's retention rate changes over time. Descriptive, not inferential — raw rates, not treatment/control comparisons.

**Distinguish from existing functions:**
- `get_course_retention()` in `course-impact.R` — observational treatment/control: "did taking course X improve persistence vs. comparable students who didn't?" Different question. Reference it for pattern, not reuse.
- `next_term_persistence()` in `course-outcomes.R` — per-course persistence broken out by grade outcome (A/B/C/DFW). Closest existing building block; this new cone generalizes it across courses and adds the time-trend dimension.

**Data needed:**
- `cedar_students` — enrollment records; provides `student_id`, `term`, `subject_course`, `registration_status_code`
- `cedar_programs` — for filtering by dept/college and adding `pell_eligible`, `first_gen`, `ipeds_race` if demographic breakdowns are wanted

**Key trunk helpers to use:**
- `add_next_term_col(df, term_col)` — adds `next_term` column; central to computing whether a student appears the following term
- `filter_class_list(students, opt)` — standard student filter; don't re-implement
- `fmt_term(term_code)` — for display labels
- `STATUS_REGISTERED` — use this constant, not inline `c("RE", "RS", "RR")`

**Suggested function signatures:**
```r
# Compare retention rates across a set of courses for a given term range
get_course_retention_comparison <- function(students, opt = list()) {
  # opt keys: term, dept, college, campus, level, min_n
  # returns tibble: subject_course, term_type, n_enrolled, n_returned, retention_pct
}

# Track one course's retention over time
get_course_retention_trend <- function(students, opt = list()) {
  # opt keys: course (required), campus, include_summer
  # returns tibble: term, n_enrolled, n_returned, retention_pct
}
```

**Return a named list** (same pattern as `get_course_outcomes()`):
```r
list(
  comparison = tibble(...),   # cross-course rates
  trend      = tibble(...)    # single-course over time
)
```

**Shiny wiring:** Add to the Explore / Course Dynamics section. Follow the module pattern from `R/modules/pathways.R`. The UI needs: course selector (for trend), dept/term/level filters (for comparison), and two output panels — a sortable DT for comparison, a line chart for trend. Use `withProgress()` around the cone call.
