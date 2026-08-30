# CEDAR Development Reference

Open-source Shiny analytics platform for higher ed curriculum, enrollment, and student experience at UNM. Primary data sources are Banner/MyReports extracts. Primary audience is IR staff and deans using the Shiny app, with a secondary audience of analysts using the cones directly in RStudio.

**For AI agents doing broad codebase work** — debugging, adding features, understanding architecture, navigating modules, or working across multiple files. This is the comprehensive reference: full architecture, data model, coding standards, module patterns, CSS gotchas, and test infrastructure.

**Instructions for agents:** Trust the layer rules (trunk/branches/cones/features/modules) and the coding standards sections — they reflect hard-won decisions, not suggestions. The live cleanup backlog and refactoring priorities live in `ROADMAP.md` — check it before touching any file listed there. When in doubt about data structure, the authoritative source is `R/data-parsers/transform-to-cedar.R`.

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
R/features/             — app-facing orchestrators/payload builders for visible CEDAR features
R/modules/             — Shiny UI/server pairs
tests/testthat/        — unit tests for cones and branches
```

**Load order (trunk/load-funcs.R):** lists → trunk → branches → cones → features → modules.

### Layer rules

| Layer | Calls | Never calls | Test |
|-------|-------|-------------|------|
| lists | nothing | — | Is it a static constant or lookup? |
| trunk | lists | branches, cones, features, modules | Could this work for a different analytics project? If yes → trunk |
| branches | trunk, lists | cones, features, modules | Is it reused by multiple cones/features/modules? If yes → branch |
| cones | trunk, branches | other cones, features, modules | Does it answer exactly one analytical question? If yes → cone |
| features | trunk, branches, cones | modules | Does it assemble multiple analyses into a feature payload? If yes → feature |
| modules | trunk, branches, cones, features | — | Is it a Shiny UI/server pair? → module |

**The key rule: cones never call other cones.** If a function needs to call multiple cones, it belongs in `features/` or `modules/`, not `cones/`.

Two companion hard rules, no exceptions:

- **Cones never touch global state.** No `exists("cedar_sections")`, no reading `data_objects` — every table a cone needs is a parameter. Optional enrichment tables are optional parameters (see how `get_course_outcomes(students, cedar_faculty, opt)` handles optional faculty).
- **Modules contain zero business logic.** No `group_by`/`summarize` pipelines in a module server — collect inputs into an `opt` list, call a cone/branch, render the result. (Also stated in Shiny Module Pattern below.)

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
| `cedar_student_term_credits` | ~430k | `student_id`, `term`, `attempted_unm_credits`, `completed_unm_credits`, `registered_courses`, `completed_courses`, and their `cumulative_*` running totals. One row per ENROLLED term, derived from the class lists in `transform-to-cedar.R` |
| `cedar_lookups` | — | Named list: `program_name_lookup` (program_name→dept_code), `dept_name_lookup` (dept_code→display name), `dept_lookup` (raw dept string→dept_code), `college_code_to_name`, `subject_lookup` (tibble: `subject_code`, `dept_code`, `college` — maps subject prefixes to dept codes; invert to get all subject prefixes for a dept_code) |

**`cedar_programs$dept_code`** is derived during transform from `program_map.qs` and the catalog lookups in `R/lists/catalog_lookups.R`:
1. `major_college_to_dept["major_code:college_code"]` — compound key from `program_map` (most accurate)
2. `subj_to_dept[major_code]` — subject code fallback from `subj_dept_map`
3. `major_to_dept[major_code]` — simple program/major fallback from `program_map`
4. `major_code` itself — last resort identity mapping in `cedar_programs` only

`program_map.qs` may contain Banner programs with no defensible academic-department owner yet. Runtime lookup vectors exclude invalid or unmapped rows and collect them in `cedar_mapping_issues`, surfaced under Admin > Data & Usage > Mappings. Reviewed exceptions live in `allowed_unmapped_program_codes` in `R/lists/program_code_maps.R`. Regenerating `program_map.qs` should still fail loudly on new unmapped codes until they are mapped or reviewed.

### Field reliability contract — what may be claimed about a past term

**This is a hard rule, in the same class as the campus and DFW policies.** It exists because MyReports' Academic Studies report returns *cumulative* figures as of the moment you pull, stamped onto every historical row it hands back. A row keyed `(student_id, term = 202180)` does not necessarily describe Fall 2021.

#### The two tests

A field may be used in a claim about a past term only if it passes **both**:

1. **Pull independence.** Re-pulling the same `(student, term)` later returns the same value. If it drifts, the field records "now", not "then", and no pull cadence fixes that.
2. **Within-history variation.** Inside a *single* pull covering many terms, the value moves from term to term for the same student. A field frozen across a student's own history cannot be a timeline no matter how stable it is.

A field passing only (1) is stable but static. A field passing only (2) does not exist in practice. Both, or the field is off limits for temporal claims.

#### Measured verdict

Test 1 compares a 2025-02/03 pull against the 2026-03 full historical re-pull on the same `(ID, term)`. Test 2 asks whether the value varies across a student's own terms *within* the 2026 re-pull alone (27,795 students with 5+ terms).

| Field (`academic_studies`) | Survives re-pull | Varies across terms | Verdict |
|---|---|---|---|
| `Semester Credits Attempted` | 100.00% | 97.96% | **safe** |
| `Semester Credits Earned` | 99.97% | 98.05% | **safe** |
| `Total Credits` | 99.92% | 98.54% | **safe** — per-term load, *not* a running total |
| `Semester GPA` | 99.98% | 98.16% | **safe** |
| `Student Classification` | 99.82% | 74.00%, never regresses (n=30,098) | **safe** |
| `Student Level` | 100.00% | — | **safe** |
| `Academic Standing` | 100.00% | 7.40% | safe; genuinely rarely changes |
| `Major` / program | 80.6% raw, **99.2%** after normalising the `Pre-` prefix | — | **safe** with caveat |
| `Institution Credits Attempted` | ~92%* | **16.25%** | **BANNED for per-term claims** |
| `Institution Credits Earned` | ~92%* | **16.25%** | **BANNED for per-term claims** |
| `Overall Credits Attempted` | ~92%* | **16.15%** | **BANNED for per-term claims** |
| `Overall Credits Earned` | ~92%* | **16.14%** | **BANNED for per-term claims** |
| `Institution GPA` | — | **16.25%** | **BANNED for per-term claims** |

\* Read that column as unreliable good news: the cross-pull overlap skews toward students who had stopped accruing credits, so their totals could not drift. The within-re-pull figure is the sound measurement, and it is damning.

The canonical illustration, one student's entire history as returned by the **single** 2026 re-pull:

| term | sem att | sem earned | Total Credits | Institution Cr Earned | Overall Cr Earned | classification |
|---|---|---|---|---|---|---|
| 202180 | 16 | 16 | 16 | **129** | **139** | Freshman, 1st Yr, 2nd Sem |
| 202210 | 16 | 16 | 16 | **129** | **139** | Sophomore, 2nd Yr |
| 202280 | 18 | 18 | 18 | **129** | **139** | Junior, 3rd Yr |
| 202310 | 16 | 16 | 16 | **129** | **139** | Nursing, Lvl I |
| 202410 | 16 | 16 | 16 | **129** | **139** | Nursing, Lvl IV |
| 202460 | 15 | 15 | 15 | **129** | **139** | Nursing, Lvl V |

A freshman with 129 earned credits. The per-term columns are right; the cumulative columns are that student's 2026 totals printed six times.

#### What this permits and forbids

**Permitted:** when a student took a course; when they changed program and to what; their classification, level, standing, per-term credit load and per-term GPA at any past term.

**Forbidden:** any "how far into their degree were they" claim sourced from the banned fields — credit bands on a timing axis, "credits at the time of the major change", "credits at first declaration", credit-band cohorts. Use one of the two sound replacements below.

#### The two sound replacements

- **`cedar_student_term_credits`** — built in `transform-to-cedar.R` from the per-term fields, so it inherits their reliability. `cumulative_completed_unm_credits` is a genuine running total. UNM-only, so a transfer student places earlier than their true standing; History graduates carry a median 58 UNM credits against 129.5 on the degree record, and the upper bands thin out badly (eligibility 101, 80, 33, 16, 4). Biology is healthy on the same axis (453, 407, 285, 209, 60). Never assume a population whose UNM record is complete arrived with no credit.
- **`build_gpa_timeline()`** in `R/branches/gpa-timeline.R` — a cumulative GPA that moves, rebuilt as a credit-weighted running mean over class-list grade points. `gpa_entering` is the matchable one: it excludes the term's own grades, which in a course-effect study *are* the outcome. Validated where the frozen field is right — `inst_gpa` is stamped at pull, so it should equal a student's true cumulative GPA at the **end** of their record and nowhere else; for students whose whole history is in-window the reconstruction lands within a median of **0.090** of it (85% within 0.25, r = 0.937). Not Banner's official GPA: UNM's repeat policy replaces the earlier grade of a repeated course, this counts both attempts.
#### Descriptive vs matched — a pull-stamped field is not simply banned

The two tests decide whether a field may make a claim **about a past term**. They
do not make a frozen field worthless; they decide what job it can hold.

`inst_gpa` is the worked example. It may not be *matched* on: measured at the
pull, it postdates both the treatment and the outcome, so balancing on it partly
balances on the outcome and biases the effect toward zero. But it is a sound
*description* of where a student stands now, and on coverage it beats the
reconstruction badly — 166,859 students against 41,016 (25%), because the rebuilt
series loses left-truncated students, first graded terms, and any UNM coursework
predating the window.

So Course Dynamics shows both, in different places: `cum_gpa_entering` in the
balance table, `current_unm_gpa` in the group profile, with on-screen text saying
which is evidence of comparability and which is not. Measured gap between them:
median 0.142, worst at a student's first term (0.220; 44.8% differ by >0.25),
with the signed error growing +0.005 → +0.081 across a career as the frozen value
folds in later work.

**The rule:** a frozen field is barred from *temporal claims and from matching*.
It may still be displayed as a current-state description, provided the page says
so. Putting one in a balance table is the error; putting one in a profile beside
a clear label is not.

- **`student_classification`** — per-term, pull-stable, monotone in 100% of 30,098 students with 3+ classified terms, and transfer-aware because Banner classifies on total earned hours. The honest answer to "where in the degree". Caveat: 33 distinct values; professional ladders (`Nursing, Lvl I–V`, `Law, 3rd Yr`, the `Graduate,` family) do not map onto Freshman/Sophomore/Junior/Senior and are dropped by a naive four-way mapping.

`relative_term` (terms enrolled) needs no credit data at all and stays populated to the tail, but measures time at UNM rather than degree progress, and normally requires an `opt$start_classification` filter against left truncation — unnecessary for a cohort *defined* as starting inside the window, e.g. `get_gen_ed_grad_cohort()`.

#### Small-cell guards are mandatory on any progress axis

Eligibility thins sharply toward the far end of every one of these axes. `pct_pop` will report one student over four eligible as "25%", visually identical to a 23% built on 101. Guard the **band** (minimum students who reached it) and the **cell** (minimum students in it) separately — they fail differently. `get_gen_ed_grad_profile()`'s `min_band_n` / `min_n` are the worked example.

#### Where the sound replacement lives

`build_credit_timeline(term_credits, programs, opt)` in `R/branches/credit-timeline.R` is the single
sanctioned source for a per-term credit position. It returns `unm_credits_entering` /
`unm_credits_after` (class-list series) and `total_credits_entering` / `total_credits_after` (plus a
transfer block recovered as `overall_credits_attempted - inst_credits_attempted`, a difference taken
at one instant and so immune to the freeze), with `timeline_valid` marking students whose UNM history
predates the data window. `attach_credit_position()` joins it onto any event table.

Validated against the shared data: the reconstruction moves across a student's terms **100%** of the
time (the frozen columns: 16%), and at a student's first term the frozen field overstates the
position by a median of **84 credits** (117 vs 6), converging to 9 by term 8.

#### `timeline_valid` is not optional — filter on it

Fixing the freeze introduces a *different* exposure, and a consumer that takes the credit columns
without the flag trades one silent wrongness for another. The running total starts at zero on the
student's first term **in the data**, so anyone already enrolled when the window opens begins
mid-career reading zero. Measured on current data: **30.1%** of students are left-truncated, and
**100%** of them read 0 credits entering their first in-window term. The error only ever points one
way — truncated students shift *left* — so an unguarded map shows coursework happening earlier in a
career than it does, and the contamination worsens across the bands (32% of records in 0–30, **71%
in 150+**).

Any surface placing students on a credit axis must drop `timeline_valid == FALSE` rows (failing
closed on NA) and **say how many it dropped**. `get_course_timing()` does this for all three credit
axes and reports the count as `timing_meta$n_truncated`, which the Pathways scope bar prints.

`student_classification` is the axis with no such requirement: it varies within a student's history
for **63.9%** of students with 3+ terms, so it is a genuine per-term field by the second reliability
test and needs no cohort restriction. It is the default x-axis in Pathways → Course Timing for that
reason. Prefer it unless the question is specifically about credit progress.

**Every consumer has been migrated.** None of them falls back to the banned fields when
`term_credits` is absent — they return NA and say so, because a missing number is visible downstream
and a wrong one is not:

| Consumer | What it now reads |
|---|---|
| `detect_major_changes()` | position after `prev_term` (the decision point), via the timeline; `credits_position_valid` per event |
| `avg_credits_before_major()` | excludes events without a usable position and reports `n_excluded_position` per major |
| `get_declaration_context()` | position entering the declaration term |
| `get_course_timing()` | `inst_credit_band` / `overall_credit_band` / `unm_credit_band` all resolve through the timeline |
| Pathways movement cards | `credit_at_term()` helper in `R/modules/pathways.R` |

#### Adding a field

Any new `academic_studies` field used in a temporal claim must be run through both tests and added to the table above before it ships. `tests/testthat/test-field-reliability.R` holds the fixtures and the assertions.

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

**Term codes:** YYYYSS format. SS = 10 (spring), 60 (summer), 80 (fall). Numeric sort is chronological. E.g., 202510 = Spring 2025, 202560 = Summer 2025, 202580 = Fall 2025. A term code is an identifier even when stored as numeric: display all six digits with **no thousands separator and no decimal** (`202580`, never `202,580` or `202580.0`). Prefer a human term label such as `Fall 2025` on reader-facing surfaces when the raw code is not needed for audit.

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

- **Early drops (`DR`/`DD`, `STATUS_DROP_EARLY`)** occur *before* the grade-consequence deadline → absent from both census and final counts (registration churn / melt). `DD` is treated like `DR`: a drop/delete with full tuition refund.
- **Late drops (`DG`/`DW`, `STATUS_DROP_LATE`)** occur *after* census → **counted at census, gone from the final count.** These are what make a course look *less* saturated at term end than it was at census.

**Canonical census helpers (use these, don't re-derive the formula):** `add_census_enrl(df)` adds `census_enrl = registered + dr_late`; `calc_census_enrl_baselines(df, target_terms, keys)` returns the same-term-type historical mean (viewed term(s) excluded), the prior-term count, and the ordered series for a sparkline. Both live in `R/branches/enrl.R`. Enrollment comparisons across terms should flow through these so every tab measures enrollment at the census (peak) point — the regstats **bumps/dips** flags and the **Waitlists** course overview both do.

**Fall 2024 magnitude (matched courses):** 10,490 early drops (never in the DESR final) and **5,531 late drops**. The late drops make census headcount ~5% higher than DESR `enrolled` (112,115 vs 107,808).

### Consequence for saturation / capacity analysis

The Saturation report (`R/features/regstats.R`) computes `fill_rate` from DESR `enrolled`. Because the current term is measured pre-census and history post-drop, the two are **not the same lifecycle point**:
- **Emerging saturation is inflated** — current pre-drop fill compared against a deflated post-drop historical mean.
- **Chronic saturation is suppressed** — the historical ≥80% test runs on drop-deflated fill.

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

---

## Grade Constants

Defined in `R/lists/grades.R`. Use these constants for analytics; do not hardcode grade strings in cones.

| Constant | Purpose |
|----------|---------|
| `GRADES_DFW` | Known nonpassing outcomes: C-, D-range, F, W, I, NC, NR, P, S, and retake variants. Canonical classifiers also fail closed on unfamiliar recorded grades. |
| `GRADES_PASS` | Default analytics pass set: A+ through C, CR, and passing retake variants. |
| `GRADES_PASS_SUB_C_OPT_IN` | Explicit exception that also treats C- and D-range grades as passing. Never the default. |
| `passing_grades` | Grades that earn credit hours in the credit timeline; currently the ordinary-grade portion of `GRADES_PASS`. |

### CEDAR-wide DFW policy

**CEDAR's default DFW threshold treats only A+ through C and CR as passing. Every other recorded, non-audit grade plus late drops (`STATUS_DROP_LATE`) counts as DFW/nonpassing. Early drops (`STATUS_DROP_EARLY`) are NEVER DFW.** This definition is not negotiable per-cone:

- C-, every D grade, F, W, I, NC, NR, P, S, their retake equivalents, and unfamiliar nonblank grade codes count as DFW by default. Blank/NA grades and AUD are excluded because no final academic outcome is present.
- Some local course situations accept C- or D-range work. A visible page control may opt in to `GRADES_PASS_SUB_C_OPT_IN`; that exception adds only C- and D-range grades to passing. It does not make P or S pass, and it must never activate silently. A page without the control uses the default and says that grades below C and other recorded non-credit outcomes count as DFW.

- A **late drop** (DG/DW — after the deadline) is the registration-status form of a W. Most withdrawals in the data post as late-drop status rows, *not* as W grades under a registered status, so any DFW computation that looks only at grades undercounts W.
- An **early drop** (DR — before the deadline) posts no grade. It is registration churn (schedule shuffling, melt), not an academic outcome. Counting it as DFW inflates failure rates with non-failures.
- Early drops are still analytically interesting — track them **separately** (`dr_early`, `n_early_drop`, early-drop rates in `get_course_outcome_rates()`), never folded into DFW.

The canonical classifier is **`classify_enrollment_outcomes()` in `R/trunk/utils.R`** — used by the `cedar_grades` pre-computation (`transform-to-cedar.R`) and by `classify_outcomes()` (`cones/stopout.R`). Grade-only frames use `classify_grades()`. Do not write a new inline pass/DFW classification; call or extend a canonical classifier. Course-level DFW outputs should flow through `get_course_outcome_rates()` in `R/branches/course-attempts.R`.

---

## CEDAR-wide right-edge policy

**Never bound an analysis with `max(term)`, a hardcoded term, or arithmetic on `cedar_current_term`.** Use the edges computed once at startup by `cedar_data_edges()` (`R/branches/data-edges.R`). This is the same class of rule as the campus and DFW policies.

### Why an edge is not one number

CEDAR's local data runs behind the registrar, and a term does not arrive all at once — registration appears months early, grades land weeks late. At any moment the tail looks like this:

| term | rows | graded |
|---|---|---|
| Fall 2025 | 128k | **91%** |
| Spring 2026 | 119k | **7%** |
| Summer 2026 | 15k | 0% |
| Fall 2026 | 85k | 0% |

So "the last term in the data" is at least two different terms depending on what you are asking.

### Which edge

| Edge | Use it for |
|---|---|
| `last_graded` (`cedar_graded_through`) | anything reading a grade: DFW, pass rates, grade distributions, stop-out after a DFW, course outcomes |
| `last_enrolled_complete` (`cedar_report_end_term`) | settled enrollment reporting and the hard observation edge for every longitudinal analysis |
| `last_enrolled` | the raw extent of the data. **Not a reporting boundary** — it includes a term that is still filling |
| `last_degree` | completions |

`cedar_report_end_term` is **no longer hand-maintained**. `global.R` derives it from `last_enrolled_complete`; the config value survives only as a fallback for a snapshot with no `as_of_date`. On current data the derived value matches what the config had been set to by hand, which is the check that it works.

### Settled enrollment, and why not by size

A term counts as settled when the newest pull covering it happened at least `min_days_after_start` days (default 14, clearing add/drop) after the term began. Term start is approximated from the term code — Fall mid-August, Spring mid-January, Summer mid-June.

Comparing a term's row count against the same season in prior years separates the cases just as cleanly today (Fall 2026 sits at 71% of a typical fall). **Do not use it.** A genuine enrollment decline is indistinguishable from an unfinished term under a size rule, so it would quietly truncate reports in exactly the year a chair most needs to see the drop. Pull timing cannot make that mistake — it describes when the data was captured, not how many students exist. There is a test for this.

### Why this is a silent-wrongness rule

Bounding a grade rate by the enrollment edge does not error — it returns a plausible number. Measured before this policy existed: **the DFW rate for Spring 2026 read 0.3% against 6–8% for every other term**, because `prepare_course_attempts()` capped at `cedar_report_end_term` (the enrollment edge) and the denominator counted all 104,431 attempts while the numerator saw only the 7% of grades that had posted. Every DFW surface in the app showed the newest term as a dramatic improvement.

### Why config arithmetic is not the answer

`cedar_report_end_term <- subtract_term(cedar_current_term)` encodes a guess that exactly one term is in flight. It fails both ways:

- **Stale.** Grades land after the term ends; nothing advances until somebody edits config.
- **Overshoot.** A config set ahead of the data nominates a term with no grades at all, and every student in it reads as having no outcome.

`cedar_data_edges()` reads the data, so it is right on whatever snapshot is loaded and moves on its own. `cedar_report_end_term` survives as the *enrollment* edge and as a cache-key component; it is not a grade boundary.

### In practice

- Grade-dependent code uses `cedar_graded_through`; enrollment reporting uses `cedar_report_end_term`. Both fall back to config only when `global.R` never ran (standalone scripts).
- Startup prints all four edges, and says so when a derived value differs from what config arithmetic would have produced.
- The threshold (`min_graded_share`, default 0.5) is not finely balanced — finished terms sit at 83–91% and in-flight terms at 0–7%, so anything from ~0.2 to ~0.8 picks the same edge.
- An edge that cannot be determined is `NULL`, never a guess. Fail closed.
- **Say which edge you used.** `cedar_edge_note()` produces the sentence. A capped view that does not explain itself reads as a stale pipeline; "Spring 2026 is enrolled but not yet graded" reads as a data state and tells the user when it will move.

### Grade outcomes and longitudinal follow-up require two separate right edges

**Do not cap an entire page merely because it contains a longitudinal panel.**
Current registration is valid descriptive data and may appear in Course Dynamics
Overview and other explicitly current-enrollment summaries. The hard right edge
belongs to computations that need comparable history or a later observation:
retention, next-term persistence, course flows, sequence effects, and downstream
success. Those analyses stop at `last_enrolled_complete`. If they also read a
grade, use `cedar_longitudinal_edge(edges, grade_dependent = TRUE)`, which is the
earlier of `last_enrolled_complete` and `last_graded`. Never let a partial current
term enter a longitudinal cohort, lookup, denominator, cache key, or outcome.

This distinction is deliberate: on the August 2026 snapshot, Fall 2026
registration is useful in the Course Dynamics Overview, but longitudinal
sampling ends at Summer 2026, the previous complete term. A page-wide filter
would throw away good current information; no filter would turn advance
registration into apparently observed follow-up.

**A row with no posted grade is unknown, never a failure or a non-pass.** Filter
grade-dependent event rows to `last_graded` *before* selecting an attempt or
classifying its outcome, then pass them through `classify_enrollment_outcomes()`.
Do not use a catch-all branch such as `TRUE ~ "failed"`: blank grades, incomplete
work, audits, NR/NC, and other unclassifiable records must be excluded from the
grade-rate denominator and reported as unobserved.

An A→B analysis also needs an **opportunity edge** for the A cohort. A student
who took A too recently to have the declared follow-up interval before the
longitudinal observation edge has not failed to continue; the record is
right-censored. For a
one-regular-term opportunity window:

1. Compute the first possible follow-up with `add_next_term_col(..., summer = FALSE)`.
2. Exclude A rows whose follow-up term is after `last_enrolled_complete` from the continuation denominator.
3. Report the number excluded and show the data window in the page methodology.
4. Keep this separate from the B outcome edge: a graded B must be at or before the earlier of `last_enrolled_complete` and `last_graded`.

On the August 2026 snapshot, Fall 2026 enrollment is already present but has no
grades, so grade sampling ends at Summer 2026. This is data-derived, not a
hardcoded "current term minus one" rule; on another pull the named terms will
move. The Course Dynamics failure that established this rule was measurable:
33 Fall 2026 ENGL 1120 registrations after Oravetz's FYEX 1030 sections were
classified as failures. Capping at the graded edge changed that group's apparent
ENGL 1120 pass rate from 66.7% (98/147) to 86.0% (98/114 observed outcomes).
The corrected opportunity window excludes 123 of Oravetz's 418 first-attributed
FYEX students because their next regular term falls after the graded edge (90 of
them are Fall 2026 records with no later term in the data at all). Both errors
produced plausible instructor comparisons rather than an exception, which is
why every longitudinal page must display its outcome edge, opportunity rule,
and exclusion counts.

For prerequisite/order questions, distinguish **strictly earlier** (`term_y <
term_x`) from **same-term** (`term_y == term_x`) completion. Concurrent courses
must never be described as having been passed "before" the focal course. When a
single downstream course was already passed in a strictly earlier term, exclude
that student from a progression-to-that-course denominator and surface the count.
For a multi-course rollup, show prior completions as context but do not infer
that passing one member makes the student ineligible for every course in the set.
The worked FYEX 1030 audit illustrates why: among 439 distinct students ever
taught by Oravetz, 38 had passed ENGL 1110 or 1120 in a strictly earlier term,
80 passed one in the same term, and 110 were in the student-level union (8 did
both). Reporting the same-term rows as "passed before," or adding the two counts
without deduplicating, materially overstates the reverse-order population.

---

## CEDAR-wide campus policy

**Any analytic grouped by course must also be grouped by campus.** Wherever `subject_course` appears in a `group_cols` vector, a `group_by()`, a `count()`, or a join key, `campus` belongs beside it. This is not a display preference — it is the same class of rule as the DFW policy above and is not negotiable per-cone.

UNM is not one campus. `cedar_students` carries ten campus codes:

| | Code | Share of enrollment rows |
|---|---|---|
| Main | `ABQ` | 61% |
| Online | `EA` | 24% |
| Branch | `GA` `VA` `TA` `LA` `EW` `EF` `ELA` `TAQ` | **15%** |

**21% of all courses (1,310 of 6,244) are taught on more than one campus**, and they are the high-enrollment ones people actually analyse. The largest Gen Ed courses each run on six campuses and draw a quarter to a third of their rows from branches:

| Course | Rows | Campuses | Branch share |
|---|---|---|---|
| `ENGL 1120` | 26,419 | 6 | 26.9% |
| `SPAN 1110` | 17,252 | 6 | 35.7% |
| `COMM 1130` | 15,002 | 6 | 30.6% |

### Why this is a silent-wrongness rule

Main campus is the default reading of every number in the app. Nothing on a course-level chart says "this includes Gallup, Valencia, Taos, and Los Alamos," so a campus-blind aggregate quietly folds a fifth of a different institution into what a chair reads as their own course. The failure mode is not an error or an empty table — it is a plausible number that is wrong by 25–35%, which is why it survives review.

Grouping is also **not** the same as filtering. Filtering to `ABQ` answers one question and discards the rest; grouping keeps every campus visible as its own row and lets the reader see the gap. Prefer grouping. A campus filter is a user's choice about scope, never a substitute for the grouping key.

### What this requires in practice

- **Group, don't just filter.** `group_cols = c("campus", "department", "subject_course")`, not `c("department", "subject_course")`.
- **Carry campus through every join.** A table that is one row per campus joined on `(department, subject_course)` fans out silently and attaches the wrong comparison value. Campus goes in the join key too. See `R/features/gen-ed.R` for the worked example — an instructor is compared against the course rate *on the campus they taught on*.
- **Carry campus into plot keys.** A chart keyed on `subject_course` alone puts two campuses at the same axis position and draws one over the other with no warning. See `instructor_dfw_plot` in `R/modules/gen-ed.R`.
- **Keep headline totals independent of the display grain.** If a summary number is summed out of a table that applies a small-cell guard per campus row, changing the grouping moves the headline as a side effect. Compute totals from their own unfiltered pass.
- **Sibling tables on one page must share a grain.** If one table is per campus and the next is not, the same course shows a different number of rows in each and the page reads as though the data disagrees with itself.

### Two campus fields, and why filtering on the wrong one leaks

`cedar_students` carries **both**:

| Column | Meaning | Lives on |
|---|---|---|
| `campus` | the campus that **taught the section** | `cedar_students` |
| `student_campus` | the student's **home campus** | `cedar_programs`, `cedar_students` |

**They disagree on 28% of enrollment rows.** Albuquerque-home students take 404,684 rows online through EA and roughly 61,000 rows at branch campuses. A filter on `student_campus` therefore does *not* keep branch-delivered course rows out of a main-campus view — course-level analytics must scope on `campus`.

Use `cedar_filter_campus()` / `cedar_require_campus()` from `R/lists/campuses.R`, and `CEDAR_CAMPUS_DEFAULT` (`ABQ` + `EA`) for filter-bar defaults rather than a bare `c("ABQ", "EA")` literal.

### Cohort vs outcome

Scoping the cohort is not the same as scoping the outcome, and conflating them creates a different wrong number. Retention is the worked example: the *cohort* is campus-scoped (a student who took the course at Gallup is not in the Albuquerque cohort), but the *outcome* — still enrolled anywhere at UNM — is deliberately UNM-wide. Narrowing the outcome lookup to the cohort's campus would silently redefine retention as "stayed on the same campus" and count every inter-campus transfer as attrition. See `.build_registered_lookup()` in `R/cones/course-retention.R`, which is commented as the one deliberate UNM-wide aggregate in that file.

### Deliberate exceptions

`get_course_pairs()` in `R/cones/pathway.R` scopes by campus but does **not** put campus in the pair key. A pair is a statement about one student taking two courses, and those can legitimately sit on different campuses — an Albuquerque student taking the follow-on online is an ordinary path. Forcing one campus onto the row would either drop those pairs or label them with a campus half the pair does not belong to. Exceptions like this are allowed; they must be commented at the site with the reason.

`get_course_timing()` takes the same exception under `opt$group_campus = FALSE`, and only under it. The default keeps campus in the key. Pass `FALSE` when the row is a statement about one student's path through the curriculum — a student who took ENGL 1120 online and PSYC 1110 in Albuquerque has one trajectory, and splitting them by delivery campus both answers a different question and halves every count on a small population. It also puts two tiles at the same heatmap coordinate, which `plot_curriculum_map()` draws one over the other. A delivery-mix or course-audience view must keep the default.

Enrollment projections have one further named exception:
`market_id = "abq_ea_course_market"`. For the monitored Gen Ed/FYEX/gateway
scope, ABQ and EA are substitutable deliveries of one planning market: online
enrollment is strongly governed by the seats offered, so separate campus series
mostly forecast allocation rather than demand. The projection branch must
prefilter to the market's declared campuses, count each student-course once
across them, pool capacity, and save every campus/part-term row in
`delivery_components`. It must never label the result as an ABQ campus metric,
include a branch campus, or discard the components. Other analyses may not infer
an exception merely because they also use `CEDAR_CAMPUS_DEFAULT`.

### Audit enforcement

No active delivery-level course metric is exempt from the campus policy. A
campus-neutral curriculum, trajectory, or explicitly named planning-market
operation must carry a nearby
`CAMPUS_ROLLUP:` comment explaining why no single delivery campus belongs on
the result. `tests/testthat/test-architecture.R` enforces that marker for
literal `subject_course` groupings, while multi-campus fixtures pin the actual
behavior of delivery metrics. See the
[campus-grain audit](docs/developers/campus-grain-audit-2026-08.md) for the
completed 1.0 inventory.

The unfinished Healthcare what-if surface was retired before 1.0 rather than
shipping a campus-blind projection.

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

### Cones — Single-Question Analyses (`R/cones/`)

| File | Main function(s) | Takes cohort? | Purpose |
|------|-----------------|---------------|---------|
| `bottleneck.R` | `get_bottlenecks(cohort, students, opt)` | ✓ | Waitlist pressure / unmet enrollment demand |
| `stopout.R` | `get_stopout(students, cohort, opt)` | ✓ | Stop-out rate gap after DFW vs. passing |
| `pathway.R` | `get_course_timing(students, cohort, opt, students_full, term_credits)` | ✓ | When population students take each course. The `cohort` parameter name is legacy; pass the `build_population()` output. `opt$x_axis` picks the axis; `opt$subject_course` restricts to an explicit course list; `opt$group_campus = FALSE` drops campus from the key (trajectory questions only — see the campus-policy exceptions above) |
| | `plot_curriculum_map(timing_data, opt)` | — | Heatmap of course timing |
| | `get_course_pairs(students, cohort, opt)` | ✓ | Ordered A→B course sequences |
| `course-impact.R` | `get_course_sequence_effect(students, programs, applicants, opt, term_credits, data_edges)` | — | Observational: do students who took X before Y earn better grades in Y? Treatment/control via `build_comparison()`; Y is capped at the longitudinal grade edge |
| | `get_instructor_effect(students, programs, applicants, opt, term_credits, data_edges)` | — | Descriptive downstream progression and outcomes by upstream instructor. Caps Y at the longitudinal grade edge, excludes right-censored X cohorts and strict-prior Y completers from the single-course continuation denominator, classifies grades canonically, and returns eligibility/unobserved-outcome audit counts for the UI. Outcomes attribute a student once to their first X instructor; course-order totals are instructor-neutral and aggregated by year. The balance diagnostic is optional context for comparing only the two largest instructor groups: it does not define, sample, match, or adjust the descriptive rates and belongs after those results in the UI |
| `course-neighbors.R` | `plot_course_sankey_by_term_with_flow_counts(to_courses, from_courses, opt)` | — | Sankey diagram of before/after course flows |
| | `plot_concurrent_course_treemap(concurrent_courses, opt)` | — | Treemap of the most common same-campus, same-term companion courses |
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

### Grade Data In Cones

For new cones, use the focused grade APIs:

- Use `get_course_outcome_rates()` for DFW, W, D/F, C-, below-C, and early-drop metrics. It returns a tidy table with stable columns such as `n_attempts`, `n_pass`, `n_c_minus`, `n_d`, `n_f`, `n_w`, `n_early_drop`, `dfw_pct`, `w_pct`, `df_pct`, and `below_c_pct`.
- Use `get_grade_distribution()` for A/B/C/D/F/W/Other counts and percentages.
- Use `prepare_course_attempts()` only when the cone needs row-level cleaned attempts.
- `dfw_pct` is `(failed + late_dropped) / (passed + failed + late_dropped) * 100`, where `failed` includes C- and other non-passing, non-W grades.

### Plot Function Placement

Plot functions may live in the same domain file as the computation they
visualize when they are display adapters for that domain. Do not move plot
helpers into a separate plotting layer just for tidiness; split files into
clearly marked calculation / plot-prep / plotting sections instead.

Rules for new and touched plot code:
- Plot functions accept already-prepared tibbles or named result lists from
  their sibling computation helpers. They do not re-filter raw `cedar_*` tables,
  reload cached data, read global state, or silently recompute the analysis.
- Use `prepare_*_plot_data()` or `summarize_*_plot_data()` for plot data shaping
  and `plot_*()` for chart construction. Existing `make_*_plot()` names can stay
  until touched, but new helpers should use the clearer pattern.
- Modules call the relevant cone/branch/report helper and render the returned
  plot or table. If a module needs more than input collection, error handling,
  and output wiring, move that logic down into the appropriate layer.
- Use `term_axis_factor()` / `term_axis_levels()` for ordered term axes instead
  of ad hoc term-label sorting.
- Use native `plotly::plot_ly()` for new interactive plots. Do not add new
  `ggplot()` + `ggplotly()` paths.
- Use `build_color_map()`, `cedar_plotly_palette()`, `CEDAR_PALETTE`, and
  `CEDAR_SEMANTIC_COLORS` from `R/trunk/utils.R` for categorical and semantic
  colors. Do not call `RColorBrewer::brewer.pal()` directly outside `utils.R`,
  and do not create tab-local categorical palettes unless the chart has a
  specific semantic meaning that belongs in a shared constant.

### New cone checklist

When adding a new cone in `R/cones/`:

- Cones answer one analytical question and never call other cones.
- Accept CEDAR tables plus `opt = list()` as the final argument.
- Validate all required input columns up front and stop loudly if any are missing.
- Reuse trunk/branch helpers such as `filter_DESRs()` and `filter_class_list()`.
- If using `filter_DESRs()`, immediately call `ungroup()` on the result before downstream `count()`, `summarize()`, `mutate()`, or `group_by()`. `filter_DESRs()` may return grouped data.
- Define an explicit output contract. Do not append `everything()` unless the cone documents that it intentionally returns pass-through columns.
- Use `cedar_debug()` for key row counts and branch points. If the cone may be sourced standalone, guard debug calls with `exists("cedar_log_level") && cedar_log_level == "DEBUG"`.
- Use `%||%` for optional `opt` defaults.
- Do not silently recover from missing schema, malformed inputs, or empty joins that should be impossible.
- Add focused tests using committed fixtures or `fixtures/designed_test_data.R`; do not create inline test tibbles.

### Features — App-Facing Orchestrators (`R/features/`)

Features call multiple branches/cones and assemble payloads for visible app surfaces. They follow different rules than cones: they may call other cones. They do not contain Shiny UI/server wiring; that lives in `R/modules/` or, for older surfaces not yet modularized, `server.R`.

| File | Main function(s) | Purpose |
|------|-----------------|---------|
| `course-report.R` | `create_course_base_data(data_objects, opt)`, `compute_cr_flows_tab()`, `compute_cr_outcomes_tab()`, `prepare_downstream_outcomes_display()` | Assembles enrollment and rollcall data for the Course Dynamics tab; flows/outcomes computed lazily per sub-tab. The downstream display helper keeps the full analytical audit intact while presenting one sortable `% (count)` column per outcome and omitting instructor-level censoring/course-order fields already summarized above the table |
| `gen-ed.R` | `get_gen_ed_profile(students, sections, programs, degrees, opt)` | Gen Ed profile (scope filtering, outcome rates, grade distribution, major mix) for Explore > Gen Ed and the Dept Trends Gen Ed panel |
| | `get_gen_ed_grad_profile(students, degrees, term_credits, opt)` | Gen Ed *consumed by* a department's own graduates — cohort meta, a `get_course_timing()` heatmap on the `unm_credit_band` axis, and the uptake table — for the graduate sections of Dept Trends > Gen Ed. The rest of that subtab measures the department as a Gen Ed provider; this one flips the population, which is why it needs the strict cohort |
| | | Returns the three views twice: `timing`/`by_course`/`summary` over all Gen Ed, and `timing_dept`/`by_course_dept`/`summary_dept` over the unit's own. Both scopes are **cut from one `get_course_timing()` run**, not computed twice — `n_eligible` is built before that function applies its course filter, so narrowing the course list only removes rows and the two heatmaps stay comparable cell for cell. Pinned by a test in `test-gen-ed-grads.R` |
| `dept-dashboard.R` | `create_dept_dashboard_data(...)` | Dashboard metrics and plots for one dept (assembles headcount, enrl, credit-hour trends) |
| | `get_subject_current_stats(sections, subject, term)` | Lightweight current-term snapshot: returns `list(n_sections, total_enrl)` for a subject, crosslist-deduplicated. No full dashboard pipeline. Reusable in dashboard cards, comparison views, and RStudio analyses. |
| `dept-trends.R` | `create_dept_report_base(data_objects, opt)`, `compute_dept_enrl_tab()`, `compute_dept_degrees_tab()`, `compute_dept_credit_hours_tab()` | Assembles the active Dept Trends web profile base and lazy tab payloads |
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

- `filter_DESRs()` may return grouped data. Always call `ungroup()` immediately after using it inside cones before `count()`, `summarize()`, `group_by()`, or downstream joins.
- Do not use scalar `&&` or `||` inside `filter()` when the right-hand side is row-vector logic. It will try to coerce a whole column-length vector to one TRUE/FALSE and fail on real data. Branch outside the pipeline or use vectorized `&` / `|`.
```r
# Preferred when the filter is optional
filtered <- df %>%
  {
    if (length(seasons) == 0) .
    else filter(., term_type %in% seasons)
  }
```
- If a summary table intentionally uses a different filter scope than the main result (e.g., Trends ignores exact term-code filters but retains Fall/Spring/Summer filters), compute it as a separate named output in the cone and document that behavior in the module caption or scope stripe.
- When filtering by status codes, set the status option explicitly for each separate filter pass. Do not assume a copied `opt` object shares later mutations.

---

## Caching

Several expensive computations are cached to disk. The general infrastructure
lives in `R/trunk/cache.R` (course-neighbors, dept-profile tabs, population
benchmarks); the Regstats dashboard keeps its own cache in
`R/features/regstats.R`. All of them follow the same shape: a `get_*_cache_key()`
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

**The second cardinal rule: never persist configuration into a cached payload.**
A cache stores *data*. Configuration — palettes, thresholds, feature flags,
anything read from `config/` — belongs to the running app and must be read live
on every load. Storing it means a payload written under an old config keeps
forcing that old config on everything rebuilt from it, and the key has nothing
that could notice, because config is not an input the key covers.

This is exactly how the Dept Trends charts turned rainbow: `set_payload()` put
`palette = cedar_report_palette` into the report cfg, and `cache_dept_tab()`
persisted the whole cfg. Cache files written while the config said `"Spectral"`
kept feeding that string into `cedar_brewer_palette()` — which happily resolved
it as an RColorBrewer palette name — for every chart taking a `palette`
argument, months after the config had been set to `NULL`. The compute path was
correct the whole time; source-level tests all passed, because they read the
*current* config. Fixed 2026-07-31 by stripping `palette` on write, reading it
from live config on restore, and adding `cedar_dept_cache_version` to the key.

If a cached payload must record which config produced it, put that in the
**key**, not the payload — then a config change is a cache miss instead of a
silent override.

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
  granularity matches how the underlying data moves. **A time-based key alone is
  the weakest option**: it cannot notice a same-period change to the data *or*
  the code, so an entry written Monday is served all week no matter what ships
  after it. Prefer a data hash; if you use a week/term key, pair it with a
  version counter. The `dept_*` keys had neither until 2026-07-31, which is why
  the `"Spectral"` payloads above survived every deploy that week.
- **A manual version counter** (e.g. `cedar_course_neighbors_cache_version`,
  `cedar_population_benchmark_cache_version`)
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
  **data** — not plots, not live `data_objects`, and not configuration (see the
  second cardinal rule) — rebuilding the rest on load. `cache_dept_tab()` is the
  reference: it strips `plots`, `data_objects_filt`, and `palette` before
  writing. The dept *dashboard* cache is the deliberate exception — it does
  store built plot objects, which is why a palette change requires bumping
  `cedar_dept_dashboard_cache_version`.
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
| `gen-ed.R` | `genEdExploreUI/Server`, `deptProfileGenEdUI/Server` | Explore > Gen Ed; Dept Trends Gen Ed panel (`deptProfileGenEd*` is the legacy internal function name) |
| `regstats.R` | `regstatsUI/Server` | Regstats |
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
- If using URL autorun, register the tab, its accepted fields, and its run button in `CEDAR_SHARE_SPECS` (`R/trunk/url-state.R`), then make the ordinary observer consume `cedar_run_trigger()`. Add the public slug to append-only `CEDAR_TAB_SLUGS`; `ui.R` consumes that registry directly, so do not add another JavaScript tab map. See "URL deep links & shareable state" below.
- Match existing table styling. If one helper renders multiple table shapes, allow per-table column definitions instead of relying on raw snake_case defaults.
- Reuse display components for highly related tables before creating another table renderer. For example, waitlist/course-demand views on Dept Dashboard, Course Dynamics, the Waitlists tab, and Regstats should share the same course-overview reactable helper and adjust only column visibility, labels, links, and compactness. This reduces visual complexity across tabs and keeps users from relearning the same concept in different visual dialects.

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
- Prefer shared UI helpers and existing CSS classes (`filter_bar`,
  `filter_scope_stripe`, `scope-bar`, `section_block`, `cedar_tbl_theme`,
  etc.) over tab-local styling. Do not fix layout glitches with inline
  `style =` attributes or one-off CSS classes unless there is no reusable
  pattern; if a new visual pattern is genuinely needed, add/extend a shared
  helper or generic CSS rule and migrate the caller to it.
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

**User-facing polish review.**
Before marking a release-polish item complete, check the rendered app, not just
the code. The review pass should confirm:

- chart legends, labels, hover text, and dense plots are readable with no obvious
  overlap;
- scope notes or blue explanation panels are visible near non-obvious
  calculations, filters, denominators, and exclusions;
- empty states say what is missing and what the user can change;
- each tab or subtab opens with a clear first answer before optional detail;
- modals use shared title, close, confirmation, and error wording patterns;
- long explanations move into `info_panel()` or another compact disclosure when
  they interrupt the page's first answer;
- users do not have to read the docs to understand a basic calculation
  difference visible on the page.

**Prose width uses character measures, not viewport percentages.** CEDAR's app
canvas is fluid, so `70%` or `80%` becomes too wide on a large monitor and too
narrow inside a smaller panel. Use the shared tokens and semantic classes in
`www/cedar-custom.css`:

- `--prose-measure-brief` (`105ch`) for short subtab introductions and hints;
- `--prose-measure-standard` (`90ch`) for ordinary dashboard explanations;
- `--prose-measure-long` (`80ch`) for sustained methodology/help reading.

Apply a measure to the text, never to a wrapper that also contains tables,
plots, filter strips, or cards. Those data/layout containers normally use the
full available width. Prefer `.cedar-lead`, `.cedar-body`, `.text-hint`, or the
explicit `.cedar-prose-*` utilities over a new `max-width` literal.

**Input values must match actual data values.** Always check the data parser (`R/data-parsers/transform-to-cedar.R`) or existing filter usage before hardcoding `choices =` in a `selectInput`. Display labels and data values often differ — e.g., the Level field stores `"lower"`, `"upper"`, `"grad"` in the data, not `"undergrad"`. If a UI label like "Undergrad" maps to multiple data values, do the mapping in the server (`opt$level <- c("lower", "upper")`), not in the `choices` vector.

**Refactoring strategy for existing tabs:**
- Do not refactor the remaining inline server.R tabs unless touching them for a separate reason. The `enrl_data` reactive feeds 8+ output handlers and has non-obvious shared state.
- Headcount has been extracted to `R/modules/headcount.R` — use it (with pathways.R) as the extraction template. See `ROADMAP.md` for the recommended extraction order of the remaining inline surfaces.

### URL deep links & shareable state

One registry, `CEDAR_SHARE_SPECS` in `R/trunk/url-state.R`, drives BOTH directions of the shareable-URL round-trip so they cannot drift. Each entry is keyed by the exact navbar tab title and declares `slug` (the `?tab=` value), `prefix`/`sep` (how a namespaced input id is built), ordered `fields` (the only URL keys accepted, with dependency order such as campus before department), `run` (the ordinary run button), optional per-key `types`, optional `aliases`, and an optional early-loading `overlay`.

- **Copy (build a link):** a module wires `cedar_copy_url_observer(input, session, copy_id, values_fn, spec_title = "…")`. On click it builds `?tab=<slug>&autorun=true&k=v…` via `cedar_share_query()` and copies it (the `copy_cedar_url` handler in `ui.R`).
- **Bootstrap (one source of timing):** after all link-related browser handlers are registered, `ui.R` sends `cedar_link_bootstrap` with the original query string. `cedar_link_server()` parses that exact string once and stores the session's shared link state. Do not read `clientData$url_search` independently in a tab or module.
- **Restore (ordered and fail-closed):** `cedar_restore_from_query()` accepts only the spec's declared fields. `cedar_schedule_link_restore()` applies them one at a time in registry order and waits until each value has round-tripped to the server before moving on. If a value cannot be restored, autorun does not run with a different scope.
- **Run (same path as a person):** after every declared value matches, the controller publishes one server-side run event. The report's ordinary observer consumes `cedar_run_trigger(input, session, input_id, spec_title)`, which merges that event with manual button presses. There is one report entry point and no synthetic browser click or tab-specific autorun observer.
- **Tabs and history:** `CEDAR_TAB_SLUGS` is serialized to the browser for initial activation, URL updates, and Back/Forward. Never add a hand-maintained JavaScript slug map.

**Server-side selectize (`server = TRUE`) remains module-owned.** The module owns the potentially large choices, while shared link infrastructure owns the selected URL value. Initialize it through `cedar_linked_server_selectize()` after `cedar_link_server()` has been installed:

```r
cedar_linked_server_selectize(
  session = session,
  root_session = parent_session,
  input_id = "wl_course",
  choices = sort(unique(students$subject_course)),
  spec_title = "Waitlists",
  key = "course"
)
```

- Declare the key as `type = "select_server"` in the share spec. The module restores it through `cedar_linked_server_selectize()`; the controller only waits for its real server input value. Never add a second controller-side write, which can make a transient value look ready before module initialization settles.
- The `selectize_set_value` handler must include selectize's `label` field; adding only `value`/`text` renders the chip as the literal string `undefined`.

**Headcount is deliberately not deep-linkable in 1.0.** Its six server-side selectizes cascade (college → department → major/minor/concentration). It has no `CEDAR_SHARE_SPECS` entry and no copy button. Adding it requires declaring the full field order and verifying every cascade in the running app; partial restoration is not acceptable.

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
| `dept_code` | character | section/enrollment cones |
| `college` | character | section/enrollment cones |
| `level` | character | section/enrollment cones |
| `min_n` | integer | cohort-aware cones |
| `cohort_ids` | character vector | course-attempt and cohort-aware cones |
| `subject_code` | character vector | pathway.R |
| `start_classification` | character | pathway.R |
| `include_summer` | logical | pathway.R |

---

## Naming Conventions

### Department References

| Context | Name | Example |
|---------|------|---------|
| CEDAR table column | `department` | `filter(department == "HIST")` |
| Filter option objects | `dept_code` | `opt$dept_code` |
| Report parameter objects | `dept_code` | `d_params$dept_code` |

Use `dept_code` for option objects because the value is a code. Leave the CEDAR
table column name `department` alone; this is a code convention, not a schema
rename. `department_code` is not used anywhere.

### Other known variations

| Concept | Names in use | Where |
|---------|-------------|-------|
| Student count | `enrolled`, `registered`, `count` | enrl.R |
| Drop types | `dr_early`, `dr_late`, `dr_all`, `drops` | enrl.R |
| Program reference | `prog_codes`, `prog_names`, `program_code`, `program_name` | credit-hours.R, headcount.R |

---

## Refactoring Status

**The cleanup/maintenance backlog and refactoring priorities live in
`ROADMAP.md`** — one live planning list, focused on open work. Completed-phase
knowledge that still matters — e.g. the `is_lab` removal — is documented in the
relevant sections above, the changelog, release notes, or git history. The
durable "how to work" rules — layer placement, reuse, no fallbacks, complexity
budget, ships-with — live in this file's **Coding Standards** section.

---

## Key Data Flow Notes

- `dept-trends.R` passes **unfiltered** `cedar_students` to `get_credit_hours_for_dept_report` (needed for college vs. dept comparison), but **filtered** students to `credit_hours_by_major` and `credit_hours_by_fac`.
- `credit_hours_data` has a `level` column: `"lower"`, `"upper"`, `"grad"`, `"total"`. Filter to `"total"` to avoid double-counting.
- `appointment_pct` in `cedar_faculty` is stored as 0–100; divide by 100 for FTE.
- `get_stopout()` requires `add_next_term_col()` from utils.R — it is called internally. utils.R must be sourced first (it is, via load-funcs.R order).
- The `%||%` null-coalescing operator is defined in `utils.R`. Cones that are sourced standalone (tests, RStudio) include a local fallback definition at the bottom of the file.

---

## Coding Standards

### Numeric precision, rounding, and identifier display

**Round for display only, and preserve enough visible precision to explain every derived statistic shown beside it.** Calculations use unrounded values; round once in the final display adapter (`mutate()` for a display tibble, a shared formatter, or a table/plot column definition). Never round an input or intermediate value before computing a rate, difference, average, trend, SMD, or other statistic.

- **Do not apply one generic numeric formatter to semantically different columns.** Counts, percentages, continuous means, statistical diagnostics, and numeric-looking identifiers require separate column definitions or a row-aware shared formatter. A mixed table must not let a count formatter erase decimals from means.
- **Counts** display as whole numbers and may use thousands separators (`1,234`). **Percentages/rates** normally display one decimal unless the analytical context requires more. **GPA and continuous means** normally display two decimals. **SMDs and similar diagnostics** normally display three decimals.
- Display precision must make adjacent values reconcilable. If two group means feed a reported difference or SMD, do not render both as `3` when the underlying values are `3.26` and `2.98`; show the decimals needed to make the diagnostic plausible. Increase precision when ordinary defaults would still collapse meaningfully different values.
- Missing numeric values display as an em dash, not `0`, unless zero is the actual measured value.
- **Identifiers are not quantities.** Term codes, CRNs, student IDs, course numbers, and similar codes never receive thousands separators, decimal suffixes, or magnitude-based abbreviation. In particular, Banner term codes render as six ungrouped digits (`202580`), never `202,580`.
- Prefer or extend shared formatters in `R/modules/ui-helpers.R` when the same convention appears on multiple surfaces. Keep raw cone/branch outputs numeric and analysis-ready; formatting belongs in the UI/display layer.

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

This applies everywhere: cones, branches, trunk, data pipeline scripts, and test helpers. Only two `tryCatch` uses are allowed: (a) in Shiny module servers, where a caught error is immediately shown to the user via `showNotification()`; and (b) around a genuinely fallible *statistic* (e.g. `chisq.test` on a degenerate table) where `NA` is the correct mathematical answer — never around data access. `tryCatch(..., error = function(e) NULL)` around a data pipeline is always a bug.

### Standardize counts and shared visuals — always prefer a helper

**Before writing a count, a rate, or a visualization inline, look for an existing helper — and if one doesn't exist but the pattern shows up in more than one place, add one and route all callers through it.** Divergent local implementations of "the same thing" are how two tabs end up disagreeing about a course's enrollment or drawing subtly different sparklines.

- **Ways of counting** — enrollment, drops, DFW, fill, headcount: there is (or should be) exactly one canonical definition. Census enrollment is `add_census_enrl()` / `calc_census_enrl_baselines()` (`R/branches/enrl.R`); DFW is `classify_enrollment_outcomes()` (`R/trunk/utils.R`); term type is `add_term_type_col()` / `get_term_type()`. Call these, don't re-derive `registered + dr_late` (or a grade filter, or a `substr(term, 5, 6)`) by hand. If you find the same formula written twice, that's a bug waiting to happen — extract it.
- **Enrollment history** — per-term active-enrollment series and its display: `summarize_term_enrl_series()` builds the term→(`has_active`, `term_enrl`) series (single course or keyed by course group); `format_term_history()` is the canonical text formatter and renders values first, with terms after: `"12, C, 10 (Fa22, Sp23, Fa23)"`; `drop_shell_sections()` removes active/zero-enrollment/unstaffed placeholders first (instructor sentinels in `NO_INSTRUCTOR_NAMES`, `R/lists/status_codes.R`). All in `R/branches/enrl.R`; used by both `get_course_enrollment_history()` and `get_enrollment_concerns()`. Dashboard helpers such as `.compact_enrl_history_str()` and `.recent_history_str()` may choose which terms to show, but must call `format_term_history()` for display. Don't re-hand-roll either the `group_by(term) %>% summarize(sum(total_enrl[status=="A"]))` slice or the history string.
- **Enrollment Trend Signals tab** — momentum and plot-prep helpers live in `R/branches/enrl.R`. Campus is part of the course key; multi-campus selections must produce separate course-campus series.
- **Shared visualizations** — sparklines, fill bars, tier/status badges, trend cells, reactable column defs: live in `R/modules/ui-helpers.R` (`make_sparkline()`, `trend_cell_html()`, `cedar_pot_coldef()`, …). A new tab that needs a sparkline uses the shared one so every sparkline reads the same; it does not hand-roll SVG.
- When a computation or component is currently inline and you touch nearby code, that's the moment to promote it to a helper and migrate the other callers — leave the codebase more standardized than you found it.

### Page structure — every section is a heading plus a description

**Shared definitions:** `docs/_data/definitions.yml` is the authored source for
the migrated metric explanations. `R/trunk/definitions.R` validates and selects
records; `load_funcs()` loads them once as static metadata. Use
`cedar_definition_summary()` for descriptions and `cedar_definition_note()` /
`cedar_definition_panel()` from `ui-helpers.R` for blue boxes. Jekyll uses the
same records in its user guides and versioned reference page. Keep actual run
scope, data edges, and exclusion counts beside results. Full methodology lives
on the docs site; do not add static Methodology tabs. Preserve published record
versions and append a new version when meaning or wording changes. See
`docs/developers/definitions.md` for the contract and release order.

**A tab body is a stack of `dashboard_section()`s. Every section states what it
shows in one sentence, directly under its heading.** A heading alone makes the
reader infer the counting rule; the sentence is where scope, denominator, and
exclusions get said. This is the "transparency" half of the 1.0 UX north star,
and it is why the helpers take a `description` argument rather than just a
title.

The hierarchy, all from `R/modules/ui-helpers.R`:

| level | helper | renders |
|---|---|---|
| tab title + subtitle | `filter_bar(title, subtitle, …)` | the green band at the top of every tab |
| **subtab title** | **`subtab_header(title, description, …)`** | **near-black h2 + copy, no fill** |
| major group | `dashboard_section(title, description, …)` | filled green heading bar + copy |
| block inside a group | `dashboard_subsection(title, description, …)` | uppercase green heading + copy |
| minor in-flow heading | `section_heading(title, level = "h5"/"h6")` | plain text heading, no description slot |

Rules:

- **A subtab opens with `subtab_header()`, never with a section bar.** The
  subtab's own title must not look like a divider inside itself. `subtab_header`
  is larger than a section bar (1.35 vs 1.2rem) but carries no fill, so the page
  reads *subtab by size, section by fill*. Every `nav_panel()` / `tabPanel()`
  that holds content gets one.
- **Section bars are for dividing a subtab that has more than one section.** A
  subtab with a single section does not need both — the `subtab_header()` alone
  is the heading, and its `dashboard_subsection()`s can sit directly beneath.
- **Use `dashboard_section()` / `dashboard_subsection()` for anything a user
  reads as a section of the page.** Reach for `section_heading()` only for a
  minor label inside an already-described block.
- **Never use a bare `h3()`–`h6()`.** An unclassed heading renders at browser
  default and will not match anything around it.
- **`description` is not optional in spirit.** If a section genuinely needs no
  explanation, that is a signal the section may not need to exist.
- **Say the exclusions.** If a number leaves something out — early drops are not
  in DFW, crosslist partners are deduplicated, summers are dropped — the
  description is where that goes, not the docs. Pages should not depend on the
  user guide to explain a basic calculation difference.
- **Two sections showing the same numbers is a bug.** If a scope strip restates
  what the summary cards already show, delete one.

Reference implementations: Dept Dashboard (`ui.R`), Course Dynamics → Rollcall,
Explore → Gen Ed.

### Reuse before writing

Search these locations, in order, before implementing anything:

1. `R/trunk/utils.R` and `R/trunk/filter.R` — term math, `filter_class_list()`, `filter_DESRs()`, `add_next_term_col()`, `validate_population()`, etc.
2. `R/lists/` — `STATUS_REGISTERED`, `STATUS_WAITLIST`, `GRADES_DFW`, `GRADES_PASS`. Never inline `c("RE","RS","RR")` or grade strings.
3. `R/branches/` — `build_population()`, `build_comparison()`, `get_course_outcome_rates()`, `get_enrl()`, `get_course_section_counts()`.
4. The cone/branch tables above — an existing cone may already answer your question.

A concrete check: `grep -rn "your_concept" R/trunk R/branches R/lists` before writing a helper. Duplicated logic found later gets consolidated *up* a layer, never copied sideways.

### Readable package calls

Prefer bare function names for packages already loaded by the app/test harness (`filter()`, `mutate()`, `select()`, `bind_rows()`, etc.). Avoid `package::function()` prefixes when they only add visual noise. Use an explicit namespace only when it prevents ambiguity, calls a package that is not normally attached, or makes an uncommon dependency clearer.

### Complexity budget

- New cone functions: aim for < 150 lines per function. If a cone file passes ~500 lines, split by sub-question or extract branch helpers.
- New modules: UI and server for one tab, one file. If a module server passes ~300 lines, business logic has leaked in — extract it.
- No new dependencies (packages) without explicit user approval. Prefer what `renv.lock` already pins.
- Plotting: **native `plot_ly()` only.** No new `ggplot()` + `ggplotly()`. When you touch a function that still uses ggplot, convert it.

### Every change ships with

- A test in `tests/testthat/` filtering from the committed fixtures (never inline tibbles), run with `Rscript --vanilla -e "testthat::test_file('tests/testthat/test-<name>.R')"` from the repo root.
- Updated AGENTS.md tables if you added or renamed a cone, branch, or module.
- No custom testing scripts. Use the committed test harnesses and gates below; do not create ad hoc shell, R, Node, Python, or browser-driver scripts to "just check" behavior unless the user explicitly asks for a new permanent test tool.

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
- **Domain data belongs in `designed_test_data.R`; one function's input contract does not.** The failure this rule exists to prevent is a test that passes because the fixture *cannot express the bug* — not the mere presence of a tibble in a test file. Ask: **does this case describe a property of real data that other analytics also need?**

  **Yes → put it in `fixtures/designed_test_data.R`.** Raw enrollment, section, program, or degree rows. Multi-campus delivery, waitlisted students, crosslists, repeat enrolments — these are facts about how UNM data looks, and every analytic that touches them needs the same shape. Building them locally guarantees the next test re-invents them, and guarantees the shared fixture keeps producing vacuous passes. Worked example: `cedar_students` was 100% ABQ, so every campus-grouping test written against it asserted nothing; MC01–MC03 fixed that and the tests only became real once they moved.

  **No → build it locally, at the top of the file, with its expected values documented directly above.** Legitimate cases, all present in the suite today:
  - **Intermediate frames.** `compute_stopout_for_group()` takes a pre-joined frame with `outcome` and `stopped_out` already derived. That shape is one function's contract, not domain data; putting it in the shared fixture would dress a made-up intermediate up as real data.
  - **Expected-value tables.** The table you assert *against*.
  - **Test scaffolding.** `test-data-loading.R` writes temp `.Rds` files to exercise the loader.
  - **Scenarios needing terms outside the fixture's stable set.** The relative-term sequences in `test-pathway.R` and the data-boundary rows in `test-population.R` depend on term spacing the shared fixture deliberately does not have. `test-pathway.R` documents this in its header — follow that pattern and say why.

  When in doubt, the tell is reusability: if a second test file would want the same rows, it is domain data.

  **The reasoning is written up for humans in `docs/developers/testing.md` → "What belongs in the shared fixture, and what doesn't".** Short version: none of CEDAR's test data is real — it is all hand-written, deliberately, because sampled binary fixtures were opaque. So the question is never *is this data real?* but *does this data have a real-world counterpart it has to be faithful to?* Boundary tables (`cedar_students`, `cedar_sections`, …) do, and must keep looking like the institution. A frame that only exists mid-pipeline does not, and belongs beside the test that defines it. Keep the two documents in step if either changes.
- **Never write throwaway/scratch tests, and don't fragment the code or fixtures just to make something testable.** When you add or change behavior, expand the *real* suite that exercises it against the *real* fixtures — don't spin up a temporary `test-tmp-*.R`, a one-off inline scenario, or a helper extracted solely so a unit test can reach it, then delete it. If the fixtures can't yet represent the case (e.g. they had no waitlisted students because the status-code→text map only knew `RE`), fix the fixtures so they mirror actual data — that is the trivial, correct path, and it makes the case reusable. Concretely: the waitlist supply columns are covered by real NURS 2010 202080 waitlist rows in `designed_test_data.R` + assertions in `test-waitlist.R`, not by an isolated helper or a scratch file.

### Running tests

#### Standard Testing Procedure

**Hard rule for agents: NEVER WRITE CUSTOM TESTING SCRIPTS.** Do not create
temporary runners, one-off browser scripts, local shell wrappers, copied e2e
variants, Python probes, R scratch tests, or bespoke "smoke" commands to verify
CEDAR. They become a second, untrusted test system and waste release time.

The only allowed test entry points are the committed gates below, focused
`testthat::test_file()` / `test_dir()` calls against committed test files, and
the committed scripts already in `tests/e2e/`. If a case is worth testing, add
or update a real committed test in `tests/testthat/` or `tests/e2e/` and run it
through the standard harness. If a custom diagnostic is genuinely needed for
exploration, keep it in the session scratchpad, never in the repo, and do not
present it as release verification.

Follow this procedure exactly:

1. **Before testing:** start from the host repo root.

   ```bash
   cd /Users/fwgibbs/Dropbox/projects/cedar-project/cedar
   ```

2. **During a tight edit loop:** run only the focused committed test file or
   filter that covers the touched behavior.

   ```bash
   Rscript --vanilla -e "testthat::test_file('tests/testthat/test-<name>.R')"
   Rscript --vanilla -e "testthat::test_dir('tests/testthat', filter='<name|area>')"
   ```

   This is an iteration tool, not release evidence.

3. **Before saying a code change is done:** run the standard gate.

   ```bash
   ./run-tests.sh
   ```

   This is mandatory for non-trivial code changes. It runs the e2e selector
   check first, then the full R suite.

4. **For UI, routing, module wiring, browser behavior, screenshots, or anything
   that depends on Shiny rendering:** run the browser gate through the standard
   entrypoint.

   ```bash
   ./run-tests.sh --e2e smoke
   ./run-tests.sh --e2e <suite-name>
   ```

   The app must already answer on `http://localhost:3838/`.

5. **For release candidates, pre-merge release branches, Docker/source changes,
   or after changing R/Shiny source that the running container may not have
   loaded:** run the release gate.

   ```bash
   ./run-tests.sh --all
   ```

   This rebuilds the container from the current working tree, waits for the app,
   and then runs the browser suites. `./run-tests.sh --all smoke` is allowed for
   a broad smoke check, but it is not the final release gate.

6. **When reporting results:** name the exact command, pass/fail counts, known
   skips, whether Chrome/app setup succeeded, and whether the app image was
   rebuilt. If a browser run fails before Chrome launches, report it as setup
   failure, not app failure. If a browser run used an old running container,
   say it is not release evidence.

Quick command reference:

```bash
./run-tests.sh          # selector check + R suite      ~40s, no app needed
./run-tests.sh --e2e    # + browser suites              ~10min, app must be up
./run-tests.sh --all    # + rebuild the container first
./run-tests.sh --e2e reports-smoke     # one named suite
```

Stages run cheapest-first on purpose. Jumping straight to the browser to "just
check the app" is the expensive mistake: a stale selector and a logic regression
both present there as an ambiguous timeout that reads like a broken feature.

#### The two paths that cost an hour every time they are forgotten

| Where | Path | Applies to |
|---|---|---|
| **Host** | `/Users/fwgibbs/Dropbox/projects/cedar-project/cedar` | everything you run locally — `run-tests.sh`, `Rscript`, `node tests/e2e/*` |
| **Inside the container** | `/srv/shiny-server/cedar` | any `docker compose exec` |

`cd` to the host path first, always: `setup.R`, `load_funcs()`, the fixtures and
every e2e helper resolve relative to it. Inside the container the app is **not**
at `/srv/shiny-server` — that is the stock Shiny sample directory, and running
there gives `No test files found`, which reads like a broken image rather than a
wrong `-w`:

```bash
docker compose exec -T -w /srv/shiny-server/cedar cedar-shiny Rscript -e '...'
```

#### `--vanilla` is required, and renv is not the answer

Cedar is a **Shiny app, not an R package**. `devtools::test()`, `pkgload::load_all()`, `library(cedar)`, and `testthat::test_local()` all fail — there is no `DESCRIPTION` file. Use `testthat::test_file()` / `test_dir()`, and always:

```bash
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

`--vanilla` skips `.Rprofile`, which otherwise activates renv. The system library
has everything the suite needs, and the run takes ~35s.

**Never run `renv::deactivate()` to fix a library error.** It rewrites
`.Rprofile` as a side effect — commenting out every `source("renv/activate.R")`
— and that edit is easy to sweep into an unrelated commit, silently disabling
renv activation for the whole project. This has already happened once (commit
`e4237fd`, reverted). If `Rscript` reports a missing package, you almost
certainly omitted `--vanilla`, or you named the wrong package: the data files are
**qs2**, not qs, and `qs::qread()` fails with the unhelpful "QS format not
detected".

#### Ad-hoc checks against real data

Do not hand-roll the bootstrap; it has four separate gotchas. Source the helper:

```bash
Rscript --vanilla -e 'source("scripts/cedar-repl.R"); nrow(cedar_students)'
```

It sets `cedar_base_dir` and `cedar_data_dir` (both required globals with no
defaults), loads the CEDAR functions, and lazily exposes the cedar tables.
For method development, keep a vanilla R process alive, source this helper once,
materialize only the required tables, and re-source changed branch/cone files
without reloading the data. The full workflow, evidence boundaries, invalidation
rules, and projection example are in `docs/developers/testing.md` under
**Computational Prototyping Without Shiny**.

#### Text-first feature previews

For a computation-heavy feature, stabilize a canonical non-Shiny text preview
before building or revising its Shiny surface. The preview must be a committed
production formatter over the feature payload or validated saved artifact, not
a scratch script and not a second implementation of the analysis. It should
show the scope, terms, measures, selected method, confidence/caveats, and recent
evidence that the UI is expected to expose.

The formatter owns display formatting only. It never recomputes business logic,
and neither tests nor the eventual UI may parse its rendered text; both consume
the underlying typed payload. Exercise the formatter with committed `testthat`
expectations, then print it from the persistent real-data lab while iterating.
This is the preferred fast loop for computational and table-contract work.

A text preview is computational evidence, not UI evidence. Changes to layout,
reactivity, accessibility, CSS, routing, or browser behavior still require the
Dockerized app and browser checks below. Do not add a one-off preview script
when a canonical formatter exists. `format_enrollment_projection_preview()` is
the worked example.

#### Enrollment projection contract

Projection work has a stricter reusable-artifact boundary:

- The forecast target is unique total class-list demand, not DESR final
  enrollment and not census. Expected census is a separately saved retention
  conversion.
- Capacity is an audit and planning comparison, never a demand predictor. A
  reached-capacity overprojection is labeled `Capacity-bounded`; never display
  its one-sided technical zero as ordinary 0% error.
- Observed-enrollment methods select the published demand row. Broad population,
  major/classification, and feeder methods are structural evidence and do not
  silently replace or average with the selected observed method.
- Every Spring population candidate must preserve matched/unmatched components,
  use only preceding terms, and survive `validate_spring_cohort_rows()`.
  Course-level broad-versus-major/classification coupling is saved with its
  aftcast count and WAPE difference; the UI never derives it.
- Weak rows remain visible with confidence `None` and a reason. Do not withhold
  them, relabel them Low, or invent a reassuring default.
- Miss explanations say `Potential explanation` or `Potential contributor` and
  retain their underlying enrollment/capacity changes. They are not causal
  claims.
- Shiny and Course Dynamics read validated artifacts through
  `load_latest_enrollment_projection_bundle()` and
  `build_enrollment_projection_view()`. They never fit, aftcast, pressure-screen,
  calibrate, or select a model in a user session.
- `model_version` changes for calculation, selection, calibration, or scoring
  behavior; `schema_version` changes for artifact shape. Every published bundle
  retains validated hashes and embedded normalized source for the model files.
  Official vintages should be built from a clean commit, but dirty development
  artifacts remain auditable through their embedded source.
- A new method is incomplete until the registry, branch candidate, rolling
  aftcast, bundle validator, text preview, designed fixture, real-data audit,
  and any affected UI/browser test agree.

The full executable contract is in
`docs/developers/enrollment-projections.md`; empirical findings and rejected
assumptions are in `docs/developers/forecasting-lessons.md`. Keep the latter as
an evidence ledger, not a second roadmap.

#### The three environments

Three separate environments. None of them is expensive — the whole R suite is
28 seconds and a rebuild-and-look loop is about a minute — so the failure mode
is not overspending, it is skipping the environment that would have caught the
bug. A UI change verified only by a green R suite is unverified.

| Environment | Used for | Cost | Ready when |
|---|---|---|---|
| **`Rscript --vanilla`** | cones, branches, reports, everything in `tests/testthat` | ~28s full suite | always — no setup |
| **Dockerized app** | anything rendered: UI, routing, CSS, module wiring | ~65s rebuild | `docker ps` shows `cedar-shiny` *and* it was rebuilt since your last code change |
| **Headless Chrome** | driving the running app, screenshots | ~12s per run | `tests/e2e/node_modules` exists |

**Never `renv`.** The project renv library is not a supported run path and is
expected to be broken — it symlinks into a macOS cache that gets purged, so
every repair breaks again at the next purge. `--vanilla` uses the system
library, which has everything the tests need. This is a dated decision recorded
below; do not "fix" renv to run tests, and in particular never reach for
`renv::deactivate()` — see the warning under "Running tests" above for what it
does to `.Rprofile`.

**The container bakes source with `COPY`.** Only `data/` is bind-mounted, so a
running container does **not** pick up code changes — a container that has been
up for hours is running whatever the source looked like when it was built. This
is the single easiest way to spend an hour debugging a change that was never
deployed. Check before trusting anything you see:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'   # is it up, and how old?
./rebuild-and-test.sh                           # rebuild + restart + wait (~65s)
```

Measured 2026-08-01 after a one-line code change: ~25s for
`docker compose up -d --build`, then ~40s before the app answers HTTP 200.
Only the `COPY` layer and the few steps after it re-run; the R-package installs
above them are cached. A **cold** build that rebuilds those package layers is
several minutes, but that only happens after a prune or a Dockerfile change —
do not plan around it, and do not treat one slow build as the normal cost.

At about a minute, looking at the app is cheap. Do it whenever a change touches
anything rendered rather than saving it up.

#### Looking at the app

```bash
node tests/e2e/shot.mjs <tab-slug>     # screenshot a tab -> /tmp/cedar-<tab>.png  (~12s)
node tests/e2e/nav.test.mjs            # assert top-nav routing; exit code = pass/fail
```

Read the resulting PNG directly — that is the visual inspection step, and it is
the only way to catch a colour, spacing, or layout regression.

To assert on rendered content rather than eyeball it, write a short script **in
`tests/e2e/`** (not `/tmp` — the imports are relative to that directory) using
the helpers in `lib.mjs`: `launch`, `connect`, `clickSubTab`, `setInput`,
`click`, `waitForSelector`, `readReactable`, `colIndex`. Delete it when done.
The harness now enforces the three traps that used to cost the most time —
each throws with an actionable message instead of returning a confident wrong
answer. `node tests/e2e/harness.test.mjs` guards them.

- **`connect(page, { tab: 'gen-ed' })` takes options, not a URL.** Passing a URL
  string throws. It used to leave `tab` at its `'home'` default (a string has no
  `.tab`), so assertions described the Home page and it looked like routing was
  broken app-wide.
- **`connect()` verifies where it landed.** A slug that ends up on Home throws
  and names the likely cause. Pass `expect: 'Gen Ed'` to assert the exact tab,
  or a longer `settle:` for a slow one. It returns the tab it landed on.
- **Scope queries to the visible tab.** Every tab's markup is in the DOM at
  once. Use `queryActive(page, sel)` and `activeText(page)` rather than a raw
  `$$eval` — on Gen Ed that is 6 labels instead of 136 — and never slice a raw
  result for readability, which is how a control that was present nearly got
  reported missing. `clickSubTab()` now refuses a sub-tab belonging to another
  tab and lists the visible ones.
- **Module inputs are namespaced**: the id is `gen_ed-ge_button`, not
  `ge_button`. `click(page, id)` throws on a missing id, so prefer it over
  finding a button by its visible text.

#### Which test do I run?

**The full R suite takes 28 seconds. Run it.** Measured 2026-08-01 on 787 files
/ 2,233 assertions, twice, warm and cold — not "a few minutes", which is what
this document used to claim and which pushed agents into narrow runs that miss
blast radius. There is no budget argument for skipping it.

Use a narrower run only for a tight edit-test loop, where 1s beats 28s on the
tenth iteration:

| Scope | Time |
|---|---|
| `test_file()`, one file | ~1s |
| `test_dir(filter=...)`, a few files | ~3s |
| `test_dir()`, everything | **~28s** |

What actually needs thought is whether the R suite is *enough* for the change
you made — several kinds of change it cannot see:

| You changed | Also do this | Why |
|---|---|---|
| One cone / branch function | nothing extra | Pure functions over fixtures — the suite covers it |
| A `group_cols`, join key, or grouping grain | an ad-hoc real-data check | Fixtures are small and often single-valued on the axis you changed, so they pass while production breaks. This is how a campus-blind grouping shipped green. |
| A `list(...)` return shape from a cone | grep the renderers that read it | Tests check the cone; nothing checks that the UI still reads every field. A balance table was returned and silently dropped by the UI for months with the suite green. |
| Module UI / `ui.R` / `server.R` | parse check, render the UI function, then look at it | Module code is **not** loaded by the test suite (see below), so the suite passing says nothing about it |
| CSS only | check no later rule overrides yours, then look at it | testthat cannot see any of it |
| Anything user-visible, before a release | rebuild the container and actually look | |

#### Commands

```bash
# One file — the default while iterating
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-course-retention.R')"

# Several files by name pattern
Rscript --vanilla -e "testthat::test_dir('tests/testthat', filter='retention|pathway')"

# Everything (~28s) — the default
Rscript --vanilla -e "testthat::test_dir('tests/testthat')"
```

Add `stop_on_failure = FALSE` when you want the whole run to finish and report, rather than aborting at the first failure.

#### The suite does NOT load Shiny modules

`helper-load-functions.R` calls `load_funcs(cedar_base_dir, modules = FALSE)`. So `subtab_header()`, `gen_ed_pct_col()`, `deptProfileGenEdUI()` and every other module/UI function is **absent** during tests. A test that calls one fails with "could not find function", and that is not a bug in the test.

To exercise a UI function, re-run the loader with modules on — do not hand-source individual `R/modules/*.R` files, which pulls in a dependency chain (`fmt_term`, `report_time_estimates`, …) and wastes several attempts:

```r
setwd("tests/testthat")
for (f in list.files(".", "^helper")) source(f)
suppressPackageStartupMessages({library(shiny); library(reactable); library(bslib)})
load_funcs(cedar_base_dir, modules = TRUE)      # cedar_base_dir set by the helper

h <- as.character(deptProfileGenEdUI("g"))
grepl("cedar-subtab-title", h)                   # assert what should have rendered
```

#### Ad-hoc checks against fixtures or real data

Some questions cannot be answered from a test failure diff: *how many rows does this actually affect*, *does this grouping change a real number*, *is this leak material*. Those need a scratch script, and writing one is correct — it is how the campus leak was quantified and how a repeater double-count was found. Keep them in the scratchpad directory, never in `tests/`.

The helpers set `cedar_base_dir` from the working directory, so `setwd("tests/testthat")` first:

```r
setwd("tests/testthat")
for (f in list.files(".", "^helper")) source(f)   # cone/branch functions
source("setup.R")                                  # fixtures: test_students, test_sections, ...
suppressMessages(library(dplyr))

# Real data lives at ../../data/*.qs and is qs2 format.
# qs::qread() and qs2::qd_read() both fail on these files.
students <- qs2::qs_read("../../data/cedar_students.qs")
```

Run it with `Rscript --vanilla <script.R>`.

Two things the helper does not do for you, both of which look like broken code:

- **`optparse` is not loaded.** Anything reaching `filter_class_list()` —
  including `prepare_course_attempts()` — fails with
  `could not find function "print_help"`. Add `library(optparse)`.
- **An empty `opt` is a CLI path, not a no-op.** `prepare_course_attempts(s, list())`
  hits `filter_DESRs`/`filter_class_list`'s "no filters supplied" branch, which
  calls `print_help(opt_parser)` and dies on a global that only exists under the
  CLI. Pass at least one real filter: `list(course = "ENGL 1120")`.

#### Prove a new test actually catches the bug

A test written alongside a fix usually passes for the wrong reason. Before trusting it, reintroduce the bug and confirm it fails:

```bash
cp R/cones/thing.R /tmp/thing.bak
# revert the fix by hand or with a small sed/python edit
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect FAIL
cp /tmp/thing.bak R/cones/thing.R
Rscript --vanilla -e "testthat::test_file('tests/testthat/test-thing.R')"   # expect PASS
```

Do this for any test guarding a join key, a grouping grain, or a dedup — those are the ones that silently pass when the fixture is too simple to express the failure.

#### Fixtures too simple to express the case

A fixture that cannot represent the bug produces a test that passes forever without checking anything. The shared fixture is single-campus, so every campus-grouping test written against it is vacuous. When you hit this, extend `designed_test_data.R` so the case is representable and reusable — that is the documented path, not a tibble built inside the test file.

#### After a failing run

A failed run writes `tests/testthat/_problems/` and `tests/testthat/testthat-problems.rds`. Neither is gitignored, so delete them before staging:

```bash
rm -rf tests/testthat/_problems tests/testthat/testthat-problems.rds
```

#### What NOT to do

- Do not `source('setup.R')` from the shell **outside** `tests/testthat` — the paths resolve wrong. From inside that directory it is the correct way to load fixtures.
- Do not `source('global.R')` — it triggers the interactive setup wizard.
- Do not hand-source `R/modules/*.R` to reach a UI function; use `load_funcs(..., modules = TRUE)`.
- Do not run R just to discover an expected value for a new assertion. Assert something obviously wrong (`expect_equal(result, NULL)`) and read the real value out of the failure diff. This is different from an ad-hoc data investigation, which is legitimate and described above.
- Do not leave scratch scripts in `tests/`.

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

### E2E rules — the four that cause every flake

Written after a session lost hours to all four. `tests/e2e/lib.mjs` now solves
each one; use the helper instead of re-deriving it.

**1. Never `sleep()` to wait for Shiny. Use `waitForIdle()` / `runAndWait()`.**
Shiny publishes its own state: `shiny-busy` on `<html>`, `recalculating` on each
output. A fixed sleep races the app, and "wait for non-empty text" passes
*instantly on the previous run's output* — that is how a scope bar read "629
students analyzed" for a run that produced 401.

*The trap the helper exists for:* outputs on hidden tabs are suspended and keep
`recalculating` forever, so counting every `.recalculating` in the DOM never
reaches zero. Only **visible** ones count.

**2. `connect()` must settle before you touch inputs.** `isConnected()` goes true
well before the landing tab's first reactive flush. Inputs set inside that window
are overwritten by the app's own initialisation — the symptom is a selectize
still reading "Type to search..." after `setInput`, a page stuck on its empty
state, and a toast claiming the analysis ran. `connect()` now waits for idle.

**3. `offsetParent !== null` is not a visibility test.** It also returns null
inside `position: fixed`/`sticky` ancestors, which in bslib includes the sub-tab
bars — so `clickSubTab()` reported "Visible sub-tabs: (none)" on a page showing
seven of them, and tests grew their own hand-rolled tab clickers in response. Use
`Element.checkVisibility()`; `lib.mjs` injects one shared definition.

**4. Selectors rot silently. Run `node tests/e2e/check-ids.mjs`.** Four ids in
`reports-smoke` had rotted unnoticed: two sat inside a `.some()` and passed while
testing nothing, two failed as timeouts that looked like broken Core Surfaces.
The checker runs in seconds and names the likely replacement. It is stage 1 of
`run-tests.sh` for that reason. For a string a test asserts is *absent*, declare
it: `// check-ids-ignore: inst_gpa, overall_credits_earned`.

Also: `openSubTab()` clicks, waits for the pane to be visible, and waits for
idle — `clickSubTab()` alone only fires the click, and `innerText` on a
still-hidden pane returns `''`, which is indistinguishable from a tab that
rendered nothing.

### E2E / browser testing — setup and reference

The when/what/cost of the browser environment is in *The three environments*
above; this is the setup and the sharp edges.

One-time setup (`node_modules` is gitignored):

```bash
cd tests/e2e && npm install
```

The harness uses `puppeteer-core` against system Chrome — no browser download
and no extension needed. Override defaults with `CEDAR_URL` and `CHROME_PATH`.

`node tests/e2e/harness.test.mjs` checks the harness guards themselves; run it
if you change `lib.mjs`.

`tests/e2e/README.md` → "Driving inputs and reading output back" has a
copy-paste recipe for setting a filter, clicking run, and reading the rendered
table, plus the gotchas that cost the most time: namespaced module input ids,
server-side selectize choices, `suspendWhenHidden` sub-tabs, and reactable DOM
selectors with uppercased headers.

Notes:
- The app serves at `http://localhost:3838/`. Data is mounted from
  `CEDAR_DATA_DIR` (`.env`); source is **not** mounted — see the rebuild note
  above.
- The first connection after a restart runs `global.R` (heavy data load), so
  that request is slow. The scripts wait for it.
- If `docker compose up --build` fails with a blob "input/output error", the
  Docker store is out of disk: `docker compose down && docker builder prune -af`,
  then rebuild.

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
