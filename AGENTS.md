# CEDAR Development Reference

Open-source Shiny analytics platform for higher-ed curriculum, enrollment and student experience at UNM. Data comes from Banner/MyReports extracts. The primary audience is IR staff and deans using the app; the secondary audience is analysts calling cones in RStudio.

**This file carries the rules.** They are hard-won decisions, not suggestions. The evidence, measurements, history and per-function detail live in `docs/developers/` and are **linked, not imported**: read a page when the work needs it. Defects and cleanup are in `ISSUES.md`; new functionality, enhancements and strategy are in `ROADMAP.md`. When in doubt about data structure, the authoritative source is `R/data-parsers/transform-to-cedar.R`.

**One home per fact.** A rule lives here, its reasoning and measurements on the linked page, a defect's status in `ISSUES.md`, a plan in `ROADMAP.md`, and what a PR changed in git. Do not restate one in another; link to it.

| Topic | Page |
|---|---|
| Table schemas; how each loaded table is built and gets its units and course ids | [data-model.md](docs/developers/data-model.md), [data-transformation-myreports.md](docs/developers/data-transformation-myreports.md) |
| Where the data model is heading and why (the domain model) | [ADR-001](docs/developers/architecture-decisions.md#adr-001-move-cedars-tables-from-report-shaped-to-domain-shaped) |
| The mapping files that decide every unit | [ADR-002](docs/developers/architecture-decisions.md#adr-002-explicit-mapping-files-replace-runtime-department-inference), [mapping-review-guide.md](docs/developers/mapping-review-guide.md) |
| `cedar_student_terms`: one definition of enrolled and returned | [student-terms.md](docs/developers/student-terms.md) |
| Which `academic_studies` fields may describe a past term | [field-reliability.md](docs/developers/field-reliability.md) |
| DESR vs class-list enrollment; the term calendar; Regstats baselines | [enrollment-measures.md](docs/developers/enrollment-measures.md) |
| The four right edges and the failures behind them | [right-edge-policy.md](docs/developers/right-edge-policy.md) |
| Why every course metric is grouped by campus | [campus-policy.md](docs/developers/campus-policy.md) |
| What is CEDAR and what is UNM | [audits/institution-boundary-audit.md](docs/developers/audits/institution-boundary-audit.md) |
| Recording what the data means; anomaly screens | [data-anomalies.md](docs/developers/data-anomalies.md) |
| What each branch, cone, feature and trunk file is for | [layer-inventory.md](docs/developers/layer-inventory.md) (generated signatures: [functions.md](docs/developers/functions.md)) |
| Cache keys and the incidents behind the cardinal rules | [caching.md](docs/developers/caching.md) |
| Module tables, plots, CSS, URL state, page structure | [shiny-modules.md](docs/developers/shiny-modules.md) |
| Enrollment projections: the contract | [enrollment-projections.md](docs/developers/enrollment-projections.md), [forecasting-lessons.md](docs/developers/forecasting-lessons.md) |
| Degree Explorer and the catalog tooling | [degree-explorer-rules.md](docs/developers/degree-explorer-rules.md), [degree-requirements.md](docs/developers/degree-requirements.md), [catalog-scanning.md](docs/developers/catalog-scanning.md), [catalog-normalization.md](docs/developers/catalog-normalization.md) |
| Running tests, fixtures, environments | [testing.md](docs/developers/testing.md), [e2e-testing.md](docs/developers/e2e-testing.md) |
| The synthetic institution | [synthetic-institution.md](docs/developers/synthetic-institution.md) |

---

## Architecture Layers

```
app.R          — 3 lines: loads ui/server, calls shinyApp()
global.R       — data loading, library loading, load_funcs()
ui.R           — page_navbar() structure; mounts module UIs
server.R       — module wiring + legacy inline handlers
R/lists/       — static constants and the readers of the institution files
R/trunk/       — pure infrastructure (filter, utils, cache, logging, data I/O)
R/branches/    — reusable CEDAR domain computations
R/cones/       — single-question analyses
R/features/    — app-facing orchestrators and payload builders
R/modules/     — Shiny UI/server pairs
tests/testthat — unit tests
```

**Load order (`R/trunk/load-funcs.R`):** lists → trunk → branches → cones → features → modules.

| Layer | Calls | Never calls | Test |
|---|---|---|---|
| lists | nothing | — | Is it a static constant or lookup? |
| trunk | lists | branches, cones, features, modules | Would it work for a different analytics project? |
| branches | trunk, lists | cones, features, modules | Is it reused by several cones/features/modules? |
| cones | trunk, branches | other cones, features, modules | Does it answer exactly one analytical question? |
| features | trunk, branches, cones | modules | Does it assemble several analyses into a payload? |
| modules | trunk, branches, cones, features | — | Is it a Shiny UI/server pair? |

Hard rules, no exceptions:

- **Cones never call other cones.** A function that needs several belongs in `features/` or `modules/`.
- **Cones and branches never touch global state.** No `exists("cedar_sections")`, no reading `data_objects`: every table is a parameter, optional enrichment an optional parameter (`get_course_outcomes(students, cedar_faculty, opt)`). `tests/testthat/test-architecture.R` fails on a global read (M12).
- **Modules contain zero business logic.** No `group_by`/`summarize` pipelines in a module server: collect inputs into `opt`, call a cone or branch, render.

**Platform vs institution.** Every file in `R/lists/` opens with `# CEDAR-PLATFORM:` or `# CEDAR-INSTITUTION:`. Institution data lives in plain CSVs under `institution/<id>/` (chosen by `CEDAR_INSTITUTION`, default `unm`): the subject → department → college hierarchy, programs, campuses, student levels, course-level bands, Gen Ed areas, excluded courses, population groups, projection scopes, text maps, and `code_history.csv` (which code replaced which). Each is validated at startup by `R/lists/institution_files.R` through `CEDAR_CONFIG_FILE_SPECS`. An adopter replaces exactly those files. **Platform code may read an institution constant through a name; it may never contain one.** `test-architecture.R` fails on institution codes as literals outside `R/lists/`; mark a deliberate exception `INSTITUTION-OK:` with a reason. The same test ratchets silent `tryCatch` fallbacks per file (M11): each file's allowance may only go down.

---

## CEDAR Data Tables

Lowercase snake_case columns; legacy uppercase names are deprecated. How each table is built, every column, and how rows get their units and course ids: [data-model.md](docs/developers/data-model.md).

| Table | Grain | What it is |
|---|---|---|
| `cedar_sections` | DESR section row | `term`, `crn`, `subject_course`, `campus`, `department`, `enrolled`, `total_enrl`, `is_combined`, `is_topics` |
| `cedar_students` | student × course × campus × term | the class list: `student_id`, `registration_status_code`, `final_grade`, `level`, `student_campus`, `major_code` |
| `cedar_programs` | student × term × program | declarations: `program_code`, `dept_code`, `college_code`, demographics. Its `*_credits_*` columns are pull-stamped (field reliability) |
| `cedar_degrees` | awarded degree | `degree`, `program_name`, `dept_code` |
| `cedar_faculty` | instructor × term | `appointment_pct` is 0–100; divide by 100 for FTE |
| `cedar_student_terms` | student × term | **CEDAR's one definition of an enrolled student-term** (`enrolled`) and of return (`returned_next_regular_term`, `return_observable`); running credits (`cumulative_*`, `timeline_valid`); primary major and classification. Built in the transform; the app stops without it ([student-terms.md](docs/developers/student-terms.md)) |
| `cedar_terms` | term | the term dimension: the right edges as flags (`is_settled`, `is_graded`, `in_progress`, …), season, next/previous regular term, first day, census date |
| `cedar_dims` | — | the mapping files as dimension tables (`colleges`, `units`, `subjects`, `programs`, `settings`); names through `unit_names()`, `college_code_names()`, `subject_units()`, `name_program_codes()` |
| `cedar_courses` / `cedar_course_codes` | course / code | the course dimension: one `course_id` per chain of confirmed renames in `code_history.csv` |
| `cedar_attempts` | student × course × campus × term | the attempt measure table: every graded attempt classified once (`outcome_category`; `outcome` pass / dfw / NA), to `last_graded` ([attempts.R](R/branches/attempts.R)) |
| `cedar_course_terms` | course × term × campus × part of term | the course-term measure table: class-list counts (`registered`, `dr_*`, `wl_all`, `cl_total`, `census_enrl`) and outcome counts (`attempts`, `passed`, `dfw`, `withdrawn`; NA past `last_graded`), no cross-term means ([course-terms.R](R/branches/course-terms.R)) |

The dimensions, `cedar_courses`, `cedar_attempts` and `cedar_course_terms` are built at startup and held in `data_objects`; none is a saved source of truth.

**Every unit and every course id is attached at load, in one place.** No saved table stores a unit or a college. Every loader (`global.R`, the cache-warming scripts, `scripts/cedar-repl.R`) calls `attach_default_units()` and `attach_course_ids()`:

- **Units:** `attach_unit(rows, dims, hierarchy)` (`R/branches/dims.R`) is the only code that resolves a unit; `test-architecture.R` ratchets every other site. The default columns (`department`, `college`, `dept_code`, …) mean the subject's unit (sections, class lists) or the program's unit (declarations, degrees, student-terms). A reader that wants another hierarchy calls `attach_unit()` with its own `cols`, never into those names.
- **Course ids:** on the loaded `cedar_sections` and `cedar_students`, `subject_course` **is the course** (`course_id`), and `listed_code` is the code the registrar used that term. A reader that filters, groups or joins on `subject_course` follows a renamed course with nothing to remember; one that names the term's code reads `listed_code`. A picked code resolves through `course_id_of()` / `course_ids_of()` or the shared `course` filter. The saved files keep the registrar's code: annotate, never mutate.
- **A cache over the loaded tables records `course_code_renames()`** in its key or on its payload.

**The mapping files decide every unit.** A program's unit comes from `programs.csv`, a course's from `subjects.csv` (by subject, section college and level). **A code with no confirmed row has no unit (`NA`)** and is listed on Admin > Mappings and in the transform's mapping audit, never given a department named after itself. Programs no department owns are `basis = no_unit`. A code not yet decided reports Banner's college, labelled `college_basis = "banner"`. A decision is an edit to the file, through a PR, taking effect at the next start. **The self-named fallback must not return** (ISSUES I7; EC-14 in `test-transform-status.R` guards it). A department's rows are those whose own `dept_code` it is (`filter_programs_to_dept()`), never rows matched by program name (I15). A pre-major's flag and target are the file's (`is_pre_major`, `leads_to`), never inferred from an F prefix.

**`dept_code` ≠ subject prefix.** Geography is `GES` but its courses are `GEOG`. Go through `subject_units(dims)`; never filter `subject_course` by `dept_code`. `cedar_students$major` is the raw Banner program code; never introduce an ad hoc program → department map.

**Course suffixes.** `C` (`BIOL 2110C`) is combined lecture+lab, `is_combined = TRUE`: count offerings with `n_distinct(subject_course)`, never `n_distinct(crn)`. `L` (`PHYS 151L`) is a standalone lab with no flag.

**Data semantics are recorded as data, not coded as exceptions.** When a code changes meaning or joins only by a non-obvious key, write it into `CEDAR_DATA_SEMANTICS` (`R/lists/data_semantics.R`). **Annotate, never mutate:** an entry explains a value and must never rewrite rows. A mapping error is corrected in the mapping files. Anomaly screens (`R/branches/data-anomalies.R`) produce candidates, never verdicts ([data-anomalies.md](docs/developers/data-anomalies.md)).

**Term codes** are `YYYYSS`: 10 spring, 60 summer, 80 fall; numeric sort is chronological. A term code is an identifier: six digits, no separator or decimal (`202580`). Prefer `Fall 2025` on reader-facing surfaces.

### Field reliability — what may be claimed about a past term

**A hard rule.** MyReports' Academic Studies returns cumulative figures as of the pull, stamped onto every historical row. A field may be used in a claim about a past term only if it is **pull-independent** and **varies within a student's history**.

| Field (`academic_studies`) | Verdict |
|---|---|
| Semester credits attempted/earned, total credits, semester GPA | safe |
| Student classification, level, academic standing | safe |
| Major / program (after normalising `Pre-`) | safe |
| Institution credits, overall credits | **banned** for per-term claims |
| Institution GPA | **banned** for per-term claims and for matching |

Forbidden: any "how far into their degree" claim from a banned field. The sanctioned replacements: `build_credit_timeline()` (running totals from `cedar_student_terms`), `build_gpa_timeline()` (`gpa_entering` excludes the term's own grades), and `student_classification`. **Filter on `timeline_valid`** (fail closed on NA) and say how many rows were dropped. A frozen field may be displayed as a labelled current-state description, never matched on; never add one to `continuous_cols`. **Guard small cells on any progress axis**, the band and the cell separately (`get_gen_ed_grad_profile()`'s `min_band_n` / `min_n`). Add a field only after running it through both tests: [field-reliability.md](docs/developers/field-reliability.md).

---

## Registration Status Codes

Defined in `R/lists/status_codes.R`; never inline the strings.

| Constant | Values | Meaning |
|---|---|---|
| `STATUS_REGISTERED` | `RE`, `RS`, `RR` | currently registered |
| `STATUS_WAITLIST` | `WL` | waitlisted |
| `STATUS_DROP_EARLY` | `DR`, `DD` | early drop: no grade consequence, never DFW |
| `STATUS_DROP_LATE` | `DG`, `DW` | late drop: a withdrawal |
| `STATUS_DROP_ALL` | all four drops | |

**Waitlist demand is class-list true demand:** distinct WL students after removing anyone registered in the same course title, term, delivery campus, college and part-of-term group, through `R/branches/waitlist-demand.R`. Never sum `cedar_sections$waitlist_count` or `calc_cl_enrls()$wl_all` for it; the DESR count is a labelled fallback only. A past term's small count does not show earlier demand was small.

## Enrollment Measures

DESR `enrolled` (`cedar_sections`) is the section headcount at the file pull: near peak for the current term, post-drop for past terms. Class-list `registered` counts students still registered at the pull. **Neither is a census freeze**, and comparing them, or one across terms pulled at different points, biases any demand or capacity analysis.

Reconstruct a lifecycle point from status codes: **census** = `registered + dr_late` (`add_census_enrl()`), **final** = `registered`, **ever registered** = `registered + dr_all`. **First day** is `calc_first_day_enrl()`, from status dates against each section's start. Census is the 15th day of instruction, three weeks after the first day, not "a week later"; read `start_date` and `census1` per section and never hardcode the interval ([enrollment-measures.md](docs/developers/enrollment-measures.md) has the calendar). Baselines: `calc_census_enrl_baselines()`, `prior_only = TRUE` for Regstats.

**Fill.** Derive it from class-list counts at one explicit lifecycle point, never from the DESR snapshot. A course is *near full* at `CEDAR_NEAR_FULL_FILL` (90%) and *full* at `CEDAR_FULL_FILL` (98% of seats on the first day), both in `R/lists/seat_fill.R`; never write either as a literal and never call a 90% course full. A term with no status dates has no first-day count and is not judged, never filled in from census.

## Grades and the DFW policy

Use the constants in `R/lists/grades.R` (`GRADES_DFW`, `GRADES_PASS`, `GRADES_PASS_SUB_C_OPT_IN`, `passing_grades`); never hardcode grade strings.

**Only A+ through C and CR pass by default. Every other recorded, non-audit grade, plus late drops, is DFW. Early drops are never DFW.** Not negotiable per cone:

- C-, D grades, F, W, I, NC, NR, P, S, retake variants and unfamiliar codes are DFW. AUD is excluded regardless of status. A blank grade is excluded unless late-drop status supplies the withdrawal.
- A visible page control may opt in to `GRADES_PASS_SUB_C_OPT_IN` (C- and D pass); it must never activate silently, and a page without the control says it uses the default.
- Most withdrawals post as DG/DW status, not W grades: a grade-only DFW undercounts W. Track early drops separately (`dr_early`), never in DFW.

The classifier is **`classify_enrollment_outcomes()`** (`R/trunk/utils.R`); `classify_grades()` for grade-only frames. Course-level rates go through `get_course_outcome_rates()`; a reader that wants every attempt's outcome reads `cedar_attempts`, classified once at load, never a saved classification. Bump `CEDAR_OUTCOME_POLICY_VERSION` when classification changes: a cached `cedar_attempts` under another version is rebuilt at start. The transform keeps one class-list row per student, course, campus and term, the row `STATUS_PRECEDENCE` ranks first (`dedup_class_list_rows()`). Docker mounts `CEDAR_DATA_DIR` from `.env`, which need not be the repository's `data/`.

## Right edges

**Never bound an analysis with `max(term)`, a hardcoded term, or arithmetic on `cedar_current_term`.** Use the edges `cedar_report_edges()` computes once at startup (`R/branches/data-edges.R`), also on `cedar_terms` as flags:

| Edge | Use it for |
|---|---|
| `last_graded` | anything that reads a grade |
| `last_enrolled_complete` | settled enrollment reporting; the hard edge for every longitudinal analysis |
| `last_enrolled` | descriptive current-registration charts only, with every term after `last_graded` labelled in progress (`mark_plotly_terms()`) |
| `last_degree` | completions |

- **Current enrollment is never hidden** from descriptive charts; it is labelled. SCH is attempted hours at census (`filter_sch_rows()`).
- A term counts as settled by pull date against its start, never by comparing row counts to prior years. An edge that cannot be determined is `NULL` and fails closed; startup stops without the settled and graded edges. Say which edge you used (`cedar_edge_note()`).
- **Longitudinal follow-up** (retention, persistence, flows, sequences) stops at `last_enrolled_complete`, or `cedar_longitudinal_edge(edges, grade_dependent = TRUE)` when it reads a grade. Never let a partial term into a cohort, denominator or cache key.
- **A row with no posted grade is unknown, never a failure.** Filter to `last_graded` before classifying; no catch-all `TRUE ~ "failed"`.
- **An A→B analysis needs an opportunity edge:** drop A rows whose follow-up term is past `last_enrolled_complete`, report how many, and keep that separate from B's outcome edge.
- Distinguish strictly earlier (`term_y < term_x`) from same-term completion; never call a concurrent course "before".
- `cedar_current_term` and `cedar_default_term` (`config/shiny_config.R`) are settings, not edges.

Details and the failures behind each: [right-edge-policy.md](docs/developers/right-edge-policy.md).

## Campus

**Any analytic grouped by course is also grouped by campus.** Wherever `subject_course` is in a `group_cols`, `group_by()`, `count()` or join key, `campus` is beside it. A campus-blind aggregate is not an error; it is a plausible number wrong by 25–35%.

- Group, don't just filter; a campus filter is the user's scope choice, never a substitute for the key.
- Carry campus through every join and into plot keys.
- Keep headline totals independent of the display grain; sibling tables on one page share a grain.
- `campus` is the campus that taught the section; `student_campus` is the student's home campus. They disagree on 28% of rows. Course analytics scope on `campus`, through `cedar_filter_campus()` / `CEDAR_CAMPUS_DEFAULT`, never a bare `c("ABQ", "EA")`.
- Scoping the cohort is not scoping the outcome: retention's outcome is UNM-wide.
- A deliberate campus-neutral operation carries a `CAMPUS_ROLLUP:` comment with the reason; `test-architecture.R` enforces it. The existing ones: `get_course_pairs()`, `get_course_timing(opt$group_campus = FALSE)`, and the projections' `abq_ea_course_market`.

Reasoning and the inventory: [campus-policy.md](docs/developers/campus-policy.md).

---

## Writing a cone

Each cone is one file in `R/cones/` answering one question. It takes CEDAR tables plus `opt = list()` and returns a tibble or named list: no Shiny, no side effects, no other cones. **Before writing anything, check [layer-inventory.md](docs/developers/layer-inventory.md) and `grep` the source**: an existing function may already answer it.

- Validate required columns up front and stop loudly.
- Reuse `filter_DESRs()` / `filter_class_list()`, and `ungroup()` immediately after `filter_DESRs()`.
- Define an explicit output contract; no trailing `everything()` unless documented.
- `cedar_debug()` for key counts (guard with `exists("cedar_log_level")` if sourced standalone); `%||%` for `opt` defaults.
- Never silently recover from missing schema, malformed input, or an impossible empty join.
- Tests use the committed fixtures, never inline tibbles.

**Grades in cones:** `get_course_outcome_rates()` (DFW, W, D/F, below-C, early drop), `get_grade_distribution()`, and `prepare_course_attempts()` for row-level attempts. `dfw_pct = (failed + late_dropped) / (passed + failed + late_dropped) * 100`.

**Plots** may live in the domain file they draw, in marked calculation / plot-prep / plotting sections. They take prepared results and never re-filter raw tables, read globals or recompute. `prepare_*_plot_data()` shapes, `plot_*()` builds; `term_axis_factor()` for term axes; colours from `build_color_map()` / `CEDAR_PALETTE` / `CEDAR_SEMANTIC_COLORS`. **Native `plot_ly()` only**; convert a `ggplotly()` when you touch it. No `brewer.pal()` outside `utils.R`, no tab-local palettes.

**Populations.** A population is a tibble of `student_id`s built by `build_population()` (`R/branches/population.R`) and passed to population-aware cones as `population` (never `cohort`). Read the CONCEPTS block at the top of `population.R` before working there. Never re-derive entry terms from a student's whole program history: `population$first_unit_term` is scoped to the focal programs. New population types are `build_X_population()` helpers wired into `build_population()`. Observational comparisons use `build_comparison()` / `compute_balance()` (`branches/comparison.R`).

**Trunk helpers first** (`R/trunk/utils.R`, `filter.R`): `add_next_term_col()`, `add_term_type_col()`, `term_diff()`, `fmt_term()`, `keep_home_sections()`, `validate_population()`, `compute_trend()` / `compute_windowed_trend()`. Gotchas:

- `filter_DESRs()` may return grouped data: `ungroup()` before `count()`, `summarize()` or a join.
- Never scalar `&&` / `||` inside `filter()` with row-vector logic; branch outside the pipeline.
- A summary with a different filter scope is its own named output, documented on the page.
- Set the status option explicitly for each filter pass.
- `compute_windowed_trend()` with `group_modify` over course pairs hangs; use vectorized `group_by + summarize`.

**Opt lists:** `opt = list()` is the last argument, resolved with `%||%`. Common keys: `term`, `campus`, `dept_code`, `college`, `level`, `min_n`, `subject_code`, `include_summer`. Option objects use `dept_code`; the table column is `department`; `department_code` is not used.

**Data-flow notes.** Dept Trends passes unfiltered `cedar_students` to `get_credit_hours_for_dept_trends()` and filtered students to `credit_hours_by_major()`; every SCH function also takes `cedar_sections`. `credit_hours_data$level` includes `"total"`: filter to it to avoid double counting. `get_stopout()` calls `add_next_term_col()` internally.

## Caching

Infrastructure is in `R/trunk/cache.R` (Regstats keeps its own). A miss returns `NULL` and the caller recomputes; write atomically (`.tmp` then rename).

- **Cardinal rule 1: the key encodes every input that changes the result.** Add a new option to the key in the same change, and check the key string changes. Cover data freshness and a manual version counter; prefer hashing the whole option set.
- **Cardinal rule 2: never persist configuration in a payload.** Palettes, thresholds, flags are read live; if a payload must record its config, put it in the key.
- `DEPT_CACHE_TABLES` declares each Dept tab's sources. `cache_dept_tab()` strips `data_objects_filt` and the palette. Dept Trends fingerprints the palette in its key; the Dashboard does not, so a palette change there bumps `cedar_dept_dashboard_cache_version`.

The incidents behind the rules: [caching.md](docs/developers/caching.md).

## Shiny modules

Every new tab is a module (`R/modules/pathways.R` is the full pattern, `headcount.R` the extraction template). Don't refactor inline `server.R` tabs unless you are touching them anyway. Details: [shiny-modules.md](docs/developers/shiny-modules.md).

- **Data lives in `data_objects`, not bare globals**; pass tables to the module server explicitly.
- One file per module, sourced after cones; UI in `ui.R`, server in `server.R`.
- Errors caught with `tryCatch` + `showNotification()`; slow work in `withProgress()`; large choice lists with `updateSelectizeInput(server = TRUE)`.
- An Explore tool modeled on Open Seats or Regstats copies the whole run pattern: overlay, report timer, `*_load_complete` message, URL copy, autorun.
- **Input values match data values**: level is `"lower"`/`"upper"`/`"grad"`; map labels to values in the server.
- **Tables are interfaces**: pick an explicit display-column order in the module.
- Shared UI helpers and CSS classes only; no inline `style =` or one-off classes.
- **Every section is a heading plus one sentence** giving scope, denominator and exclusions (`subtab_header()` → `dashboard_section()` → `section_heading()`); never a bare `h3()`–`h6()`. Two sections showing the same numbers is a bug. Shared metric text comes from `docs/_data/definitions.yml` via `cedar_definition_note()`.

**URL state.** One registry, `CEDAR_SHARE_SPECS` (`R/trunk/url-state.R`), drives copy and restore. Copy with `cedar_copy_url_observer()`; `cedar_link_server()` parses the single `cedar_link_bootstrap` string (never read `clientData$url_search` yourself); `cedar_schedule_link_restore()` restores fields in registry order and does not autorun a different scope; the run observer consumes `cedar_run_trigger()`. Server-side selectizes stay module-owned (`cedar_linked_server_selectize()`, `type = "select_server"`). Headcount is deliberately not deep-linkable.

---

## Coding standards

**No silent fallbacks.** A missing column, an impossible empty join or malformed input raises an error; never substitute a default, return an empty result or skip.

```r
result <- tryCatch(get_something(df), error = function(e) tibble())   # wrong
dept   <- df$dept_code %||% df$department                             # wrong
if (!"dept_code" %in% names(df)) stop("dept_code column required")    # right
```

`tryCatch` is allowed only in a module server that shows the error via `showNotification()`, and around a genuinely fallible statistic where `NA` is the right answer. `tryCatch(..., error = function(e) NULL)` around a data pipeline is always a bug.

**Reuse before writing.** Search `R/trunk/utils.R` and `filter.R`, then `R/lists/`, then `R/branches/`, then the cones. There is one canonical way to count each thing: census `add_census_enrl()`, DFW `classify_enrollment_outcomes()`, term type `add_term_type_col()`, enrollment history `summarize_term_enrl_series()` / `format_term_history()`. Shared visuals (sparklines, fill bars, badges) live in `R/modules/ui-helpers.R`. Duplicated logic is consolidated up a layer, never copied sideways.

**Numbers.** Round for display only, once, in the display adapter. Counts whole, percentages one decimal, GPA and means two, SMDs three; more when the default would collapse a reported difference. Missing values show as an em dash. Identifiers (terms, CRNs, IDs, course numbers) get no separators or decimals. Don't apply one formatter to different kinds of column.

**Style.** Bare function names for attached packages; a namespace only to disambiguate or flag an unusual dependency. Cone functions under ~150 lines, cone files under ~500, module servers under ~300. **No new dependencies without explicit approval.**

**Every change ships with** regression coverage for changed analytical behavior, in the existing suite, on the committed fixtures; and updated docs where its rule or table changed (here only for a rule; the inventory for a new file). Prose, CSS spacing and rearrangement need no assertions.

---

## Tests

All test data is in `tests/testthat/fixtures/designed_test_data.R`, which **is** the test database; `setup.R` exposes `test_sections`, `test_students`, `test_programs`, `test_degrees`, `test_faculty`, `test_dims`, `data_objects`. Its header pins expected counts: update it and the affected tests in the same change as any fixture edit. New rows follow EC-xx / XLxx / SVARxx.

- Expected values are committed after running against fixtures; if one changes, investigate before updating it.
- Domain rows belong in the shared fixture; one function's intermediate frames are built locally with documented expectations.
- **A fixture too simple to express the bug gives a test that passes forever.** Reintroduce the bug and confirm the test fails before trusting it; mandatory for any guard on a join key, grouping grain or dedup.
- **Never write custom testing scripts** (scratch runners, probes, ad-hoc smoke tests). The entry points are the gates below, `testthat::test_file()` / `test_dir()` on committed files, and `tests/e2e/`. Exploratory diagnostics stay in the session scratchpad.

| Change | Required checks |
|---|---|
| Calculation or data contract | focused R tests while editing; `./run-tests.sh` when finished |
| UI, routing, module wiring | the R gate plus `./run-tests.sh --e2e <suite>` for the changed behavior; look at layout changes |
| `global.R`, or a validator that can stop startup | also `bash scripts/dev.sh up && ./run-tests.sh --e2e demo` |
| A grouping grain or join key | also a real-data check (`scripts/cedar-repl.R`): fixtures are often single-valued on the axis you changed |
| Release candidate or major pipeline change | `./run-tests.sh --all` |
| Documentation or presentation only | check links or appearance |

`./run-tests.sh --changed` picks stages from the diff; it selects, it never certifies. When reporting, name the exact command, pass/fail counts, skips, whether Chrome and the app came up, and whether the image was rebuilt.

**Gotchas that cost an hour each:**

- **`--vanilla` is required**; CEDAR is not a package (`devtools::test()` fails). Data files are **qs2**, not qs.
- Host path `/Users/fwgibbs/Dropbox/projects/cedar-project/cedar`; in the container, `/srv/shiny-server/cedar` (not `/srv/shiny-server`).
- **The container bakes source with `COPY`**: a running container has old code until rebuilt. Check `docker ps`.
- One CEDAR app, one port (3838): the synthetic and institutional stacks are alternatives.
- **Module code is not loaded by the R suite** (`load_funcs(..., modules = FALSE)`): parse, render and look.
- Dependencies go through `scripts/r-environment.R`, never a bare renv call; never `renv::deactivate()`.
- Don't `source("setup.R")` from outside `tests/testthat`, `source("global.R")`, or hand-source modules. After a failing run, `rm -rf tests/testthat/_problems tests/testthat/testthat-problems.rds`.
- Real-data checks: `Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_students)'`.

**E2E rules** (`tests/e2e/lib.mjs` solves each): never `sleep()`, use `waitForIdle()` / `runAndWait()`; let `connect()` settle before touching inputs; `checkVisibility()`, not `offsetParent`; run `node tests/e2e/check-ids.mjs` for selector rot. `connect(page, { tab })` takes options; scope with `queryActive()`; module ids are namespaced.

Full reference: [testing.md](docs/developers/testing.md), [e2e-testing.md](docs/developers/e2e-testing.md).

**Text-first previews.** A computation-heavy feature gets a committed text formatter over its payload before its Shiny surface. Tests and UI consume the typed payload, never the text. It is computational evidence, not UI evidence.

---

## Enrollment projections

The full contract and the one summary of its rules: [enrollment-projections.md](docs/developers/enrollment-projections.md#the-rules-in-brief). Read the summary before any projection change. The rules most often at risk:

- The target is **unique total class-list demand**, not DESR final enrollment or census.
- **Capacity is a planning comparison, never a predictor.** Capacity reached is first-day fill of 98% or more; an unknown first day is unknown.
- **Selection is rolling and published accuracy is out of sample.** A challenger replaces the prior same-season spine only by beating it on earlier aftcasts.
- **The pressure bump and feeder adjustment change the plan, never the forecast or its accuracy.**
- **Shiny never fits a model:** it reads validated bundles (`load_enrollment_projection_bundle()`), one per season.
- `model_version` changes for calculation; `schema_version` for shape. **Editing any model-source file rebuilds both bundles on deploy**; page text belongs in `R/features/enrollment-projection-view.R`.
- Named populations come from `CEDAR_POPULATION_GROUPS`; run `population_group_audit()` when adding one.

## Degree Explorer and the catalog tooling

Before changing Degree Explorer, read [degree-explorer-rules.md](docs/developers/degree-explorer-rules.md). Its catalog excerpts, roadmap templates and shared requirements live under `institution/<id>/`; they are illustrative plans, **not student audits or forecast inputs**. Catalog acquisition runs offline (`scripts/scan-degree-catalog.R`), never in Shiny, and never edits reviewed degree files. Extracted rules stay unreviewed until a person signs off a complete unit; no AI API calls or automatic approvals occur. Where each piece lives: [degree-requirements.md](docs/developers/degree-requirements.md), [catalog-scanning.md](docs/developers/catalog-scanning.md), [catalog-normalization.md](docs/developers/catalog-normalization.md).

## Sample data

`bash scripts/dev.sh up` starts the synthetic institution (`compose.dev.yml`) on port 3838, with source mounted read-only and no institutional data; `restart` after edits. `dev/demo-data.R` adapts the fixture scenarios into a multi-year institution with provenance columns; extend `test-demo-data.R` when its answers change. **Do not weaken analytical rules or small-cell guards to populate a demo.** [synthetic-institution.md](docs/developers/synthetic-institution.md), `docs/developers/first-hour.md`.
