# CEDAR Backlog

The prioritized cleanup/maintenance backlog, from a full architecture audit
(2026-07-09) and kept current since. Pick work top-down; one PR per item.

- **How to work in this codebase** — layer placement, reuse, no silent
  fallbacks, complexity budget, ships-with-a-test — lives in `AGENTS.md`
  (Coding Standards). Read it before writing code.
- **Longer-term vision and potential features** live in `ROADMAP.md`.

Sizes: S < 1 hr agent work, M = one focused session, L = multi-session.

## Prioritized backlog

### A. Architecture violations (fix first — these contradict documented rules)

- [x] **A1 (M): `waitlist.R` is a double violation.** DONE 2026-07-09.
  `ensure_course_title()` now takes `sections` as an explicit parameter and
  errors loudly if titles are needed but no table is supplied; global-env
  sniffing and the silent `tryCatch → NULL` are gone. `inspect_waitlist()` and
  `get_unique_waitlisted()` gained an optional `sections = NULL` parameter;
  call sites updated (waitlist module + server.R wiring, command-handler.R).
- [x] **A2 (M): cone→cone call: `waitlist.R` → `course-demographics.R`.** DONE
  2026-07-09. `summarize_student_demographics()` (and its deprecated alias
  `summarize_classifications()`) moved to `R/branches/demographics.R`, sourced
  in load-funcs.R, AGENTS.md branch table updated.
- [x] **A3 (S): inline `"WL"` strings** in bottleneck.R and enrl.R replaced with
  `STATUS_WAITLIST`. DONE 2026-07-09.
- [x] **A4 (M): silent-fallback sweep.** DONE 2026-07-09. Findings:
  - `rebuild_dept_report_plots()` in the retired legacy Dept Report path (~265 lines, 8 tryCatch
    blocks) had **zero callers** — dead code superseded by
    `rebuild_dept_hc_plots()`. Deleted. It also contained a scope bug
    (`opt$include_instructor_points` with no `opt` in scope) that the tryCatch
    had been hiding — the pattern working exactly as feared.
  - `rebuild_dept_hc_plots()`: tryCatch removed; errors propagate to the
    server.R handler (`handle_error()` at the caller).
  - course-report.R: two pivot_wider tryCatch blocks removed — their error
    handlers assigned to handler-local scope, so the "fallback" never worked
    (crash-later bugs). Enrollment-plot, sankey, and outcomes tryCatch wrappers
    removed; empty-data checks kept; errors now reach the server handler.
  - regstats.R: both cache-I/O tryCatch blocks kept with justification comments
    (unreadable cache = cache miss; failed cache write must not discard results).
  - stopout.R chisq.test tryCatch kept with justification comment (NA is the
    correct p-value for a degenerate contingency table).

### B. Decomposition (the big complexity debt)

- [ ] **B1 (L): shrink `server.R` (4,505 lines).** Five tabs are still inline.
  Extract in this order (most self-contained first), one module per PR,
  following `R/modules/headcount.R` as the template (it was extracted from here):
  1. Data & Usage tab (~lines 4773–5167)
  2. Low Enrollment Alert Dashboard (~1004–1644)
  3. Enrollment (`enrl_data`, ~328–1004) — feeds many outputs; map them first
  4. Unit Dashboard (~3471–4081)
  5. ~~Dept Report / Dept Trends (~4081–4773)~~ — DONE 2026-07-26:
     legacy Rmd retired; active Dept Trends extracted to
     `R/modules/dept-trends.R` with support in `R/features/dept-trends.R`.
  6. Course Report (~1644–3433, incl. rollcall plot blocks) — largest, do last
  Rule per extraction: any dplyr pipeline found inline moves to a cone/branch,
  not into the new module.
- [ ] **B2 (L): `R/modules/pathways.R` (4,271 lines) has leaked business logic.**
  41 `group_by`/`summarize` calls live in the module. Inventory them, push each
  into the cone that owns the question (`pathway.R`, `major-changes.R`,
  `population.R`), leaving the module as wiring. Also remove the module's local
  `` `%||%` `` definition — modules always load after trunk, so it can never be
  needed there.
- [x] **B3 (M): retire the unfinished `health-whatif` pair.**
  DONE 2026-08-06. Removed the Healthcare tab, server wiring, and health-specific
  projection cone/module from 1.0. The reusable population builder remains in
  `R/branches/population.R`; revisit projections after 1.0 as a general
  course-demand feature rather than a health-only surface.
- [ ] **B4 (M each): Phase-3 long files** (carried over from AGENTS.md, still open):
  `enrl.R` (1,279), `regstats.R` (1,385), `credit-hours.R` (1,239),
  `pathway.R` (1,084), `dept-dashboard.R` (1,675). Extract repeated
  filter/summarize blocks into named helpers; separate cache management from
  analysis in `regstats.R`.
- [ ] **B5 (M): precompute reusable course enrollment history.** Low-enrollment
  alerts still call `get_course_enrollment_history()` rowwise, producing repeated
  "Getting enrollment history for..." scans on every dashboard run. Build a
  richer course-history spine from `calc_cl_enrls()`/`cedar_cl_enrls_base`
  concepts instead of duplicating logic: preserve enough keys (`campus`,
  `college`, `department`, `subject_course`, `course_title`, `term`,
  `term_type`, `part_term`, `level`) and support both final enrollment
  (`registered`) and census enrollment (`registered + dr_late` via
  `add_census_enrl()`). Supplement with `cedar_sections` only for section-status
  semantics that class lists do not fully encode (cancelled "C" markers,
  shell-section removal, crosslist/home-section scope). Refactor
  `build_low_enrollment_alerts()` to join/query this precomputed spine in one
  grouped pass rather than per-row scans.

### C. Standardization

- [ ] **C1 (M): finish the plotly conversion.** Updated 2026-07-31. The
  duplicate "build a ggplot, then hand it to `ggplotly()`" pipeline is **gone** —
  `ggplotly()` no longer appears anywhere. Cleared since this item was written:
  `R/branches/enrl.R` (`make_enrl_plot()` was dead code — never called, and the
  only chart still using ggplot's default rainbow hue scale; deleted) and
  `R/features/dept-dashboard.R` (`plot_credit_hours_by_level()` converted to
  native `plot_ly`).

  `ggplot()` remains in five places, and **not all of them should be
  converted** — static ggplot is the right tool for dense facet grids and
  non-interactive marks:
  - `R/modules/cancellations.R` (2 charts) — convertible via `subplot()`; the
    real candidates for this item.
  - `R/cones/pathway.R` — curriculum-map heatmap: dense tile grid with a text
    label in every cell. Keep static.
  - `R/cones/population-trend.R` — faceted small-multiple. Keep static.
  - `R/branches/headcount.R` — 200px sparkline; hover/zoom buys nothing. Keep.
  - `R/cones/gened-fulfillment.R` — **not called from anywhere**; only its own
    commented-out examples reference it. Decide: document as a console-only
    analysis helper, or delete.

  Rename this item's goal from "convert everything" to "convert what benefits,
  and document why the rest stays static" so nobody re-opens it later.
- [x] **C2 (S): where do plot functions live?** Decision documented in
  `AGENTS.md`: keep plot helpers with their domain computation when they are
  display adapters, split files into calculation / plot-prep / plotting
  sections, require `plot_*` functions to accept prepared data rather than
  recomputing analysis, and use shared CEDAR palette helpers.
- [x] **C3 (M): `opt$dept` vs `opt$dept_code`** — decided in favor of
  `opt$dept_code` for code clarity. Runtime option maps, report/module handoff
  points, and tests now use `dept_code` while leaving source table column names
  such as `department` unchanged.
- [x] **C4 (S): consolidate `` `%||%` `` fallback definitions.** DONE
  2026-08-05. `R/trunk/utils.R` now defines the shared operator for the normal
  load path. `comparison.R`, `course-impact.R`, `pathway.R`, and `stopout.R`
  keep identical bottom-of-file guarded fallbacks for standalone sourcing; the
  Pathways module copy is gone.
- [x] **C5 (S): one cache-key strategy.** DONE 2026-08-05. The last unversioned
  cache, `course_neighbors`, now includes `cedar_course_neighbors_cache_version`
  in its key while retaining data hashes and campus scope; `clear_course_cache()`
  clears both old unversioned files and new versioned files.

  Original issue: the three caches keyed differently, and
  the weakest one silently served wrong output for weeks:
  - `course_neighbors` — data hashes, no version. DONE 2026-08-05.
  - `dept_dashboard` / `seatfinder` — version constant **and** data hashes.
  - `dept_<tab>` — now version constant + dept + term + ISO week + tab + data
    dimension hash as of 2026-08-04. Before that, it was dept + term + ISO week
    only, with no version until `cedar_dept_cache_version` was added 2026-07-31.

  **Why this is worth a PR, not a comment:** the dept cache persisted
  `palette` (configuration, not data) inside the payload. A cfg written when
  `cedar_report_palette` was `"Spectral"` kept forcing the RColorBrewer
  rainbow onto every Dept Trends chart that takes a palette argument, long
  after the config changed to `NULL` — because the key had nothing that could
  notice. Fixed 2026-07-31 by stripping `palette` on write, reading it from
  live config on restore, and versioning the key. The general rule the
  incident argues for: **never persist configuration into a data cache, and
  give every cache a key that changes when its inputs do.** This is now stated
  in `AGENTS.md` alongside the no-silent-fallbacks rule.

### D. Test coverage gaps

No dedicated test file exists for these; add one per PR, fixtures-only, starting
with the ones used by live tabs:

- [x] **D1 (M): `R/cones/waitlist.R`.** DONE 2026-07-24. Behavioral coverage now
  exercises true waitlist demand (including a student with both WL and RE rows),
  aligned course/program/classification counts, section-supply output, scoped
  enrollment history, and the missing-title/sections error path.
- [x] **D2 (M): `R/branches/comparison.R` + `R/cones/course-impact.R`.**
  DONE 2026-08-01. Pins both SMD formulas against hand-computed values, the 0.25
  flag threshold, zero-variance returning NA rather than dividing by zero,
  categorical covariates staying distributions, and covariate-term selection.
  Writing them found a crash: `compute_balance()` reached `arrange(desc(abs(smd)))`
  on a 0x0 tibble whenever a groups frame carried only categorical covariates.
  Two behaviours are pinned rather than changed — students with no program record
  leave the comparison silently, and a student in both groups counts as treatment.
- [ ] **D3 (M):** `R/branches/credit-hours.R` (only indirectly covered via Dept Trends/report-support tests).
- [ ] **D4 (S each):** `bottleneck.R`, `course-neighbors.R`,
  `gened-fulfillment.R`, `degrees.R` branch.
  (`course-retention.R` and `gen-ed-conversion.R` gained substantial coverage
  2026-08-01 with the campus work — retention cohort/outcome scoping, the
  benchmark join, and the campus guard are all pinned.)

### D-bis. Retired from the 2026-08-01 campus work

- [x] **`R/cones/health-whatif.R` campus scoping (M).** CLOSED 2026-08-06 by
  retiring the unfinished Healthcare projection surface from 1.0. If course
  demand projections return, build them as a general campus-scoped feature.
- [x] **`pct_took_y` denominator mismatch on Downstream Success (S).**
  DONE 2026-08-04. `n_total_in_x` now counts distinct students from the same
  first-X-instructor attribution used by the analysis, so `pct_took_y` divides
  students by students. Regression test derives a duplicate course-X attempt
  from MC02 and pins MC_I1 at 3 of 4 students, not 3 of 5 enrollments.

### E. Housekeeping

- [x] **E1 (S):** DONE 2026-07-09 — `inspect_applicants.R` removed,
  `.Rapp.history` gitignored. Still open: decide whether
  `.github/workflows/deploy.yml` (untracked) should be committed.
- [x] **E2 (S):** DONE 2026-07-09 — CLAUDE.md refreshed: orig-file deletions and
  headcount module checked off, waitlist cone table entry corrected to
  `inspect_waitlist(students, opt, sections)`, `withProgress` claim fixed,
  demographics branch added to the branch table.
- [ ] **E3 (S):** `R/trunk/logging.R` (657 lines) — verify it still passes the
  trunk test ("would work for a different analytics project"); if CEDAR-specific
  report knowledge has crept in, split it out. (`command-handler.R`, formerly
  the other half of this item, was retired 2026-07.)
- [ ] **E4 (S):** Remove commented-out code from `Rmd/` files (carried over
  from the retired AGENTS.md Phase 1 checklist).

### F. Externalize domain data (carried over from the retired AGENTS.md Phase 4)

Prerequisite work for any second-institution deployment; also the fix path for
mapping-boundary issues like the now-closed #12 PADM/HLAD, #22 MPP, and #33 SHS
mapping gaps. See ROADMAP.md Theme 4.

- [ ] **F1 (M):** Move department/program mappings in `R/lists/mappings.R`
  (and `subj_dept_map.R`) to YAML/CSV data files.
- [ ] **F2 (S):** Make the college code configurable (currently hardcoded
  `"AS"` in `credit-hours.R`).
- [ ] **F3 (M):** Document all remaining hardcoded domain values.
- [ ] **F5 (L, 1.x): domain-shaped tables instead of report-shaped ones.**
  See [ADR-001](../docs/developers/adr-001-domain-data-model.md) for the full
  argument, evidence, and migration path. Summary: the five `cedar_*` tables are
  1:1 with MyReports *reports*, not domain *entities*, so student-term facts
  (`student_level`, `student_classification`, `student_campus`,
  `student_college`) are stored 4.0× in `cedar_students` and 1.5× in
  `cedar_programs`. Because each copy was mapped independently, the same column
  name holds two vocabularies (0% overlap) — and where the copies disagree
  (classification, 0.14%) it is undetected snapshot skew, so the answer a user
  gets depends on which table their query read.

  Target: facts (`cedar_registrations` — **the class list, same grain, status
  columns untouched**; `cedar_program_enrollments`; `cedar_completions`) plus
  dimensions (`cedar_student_terms`, `cedar_sections`, `cedar_courses`).

  **Step 1 is additive and safe to do early:** build `cedar_student_terms` in
  the transform with a declared precedence for snapshot conflicts (~1 day).
  Readers migrate opportunistically after; the duplicated columns drop last.
  Migration surface is ~310 references across 26 files.

  Prerequisite for the second-institution goal: it lets onboarding ask for
  registrations/student-terms/sections rather than "a MyReports class-list
  export." Pairs with F1 and F4.
- [ ] **F4 (M): campus is three vocabularies with no mapping between them.**
  Re-checked 2026-08-01 — the split is worse than first written:

  | Column | Vocabulary |
  |---|---|
  | `cedar_sections$campus` | codes (`ABQ EA EF EG ELA ET EW GA LA TA TAP TAQ VA 05`) |
  | `cedar_students$campus` | codes |
  | `cedar_students$student_campus` | **codes** (`ABQ GA LA TA VA`) |
  | `cedar_programs$student_campus` | **labels** (`Albuquerque/Main`, `Valencia`, …) |

  So `student_campus` means different things in `cedar_students` and
  `cedar_programs` — same field name, different vocabulary by table. A filter
  written for one silently matches nothing against the other.

  All current call sites were verified correct on 2026-08-01: the population
  filter passes labels to `cedar_programs`, and the Course-campus controls pass
  codes to `cedar_students`. But `pathways.R` now has two `opt$campus` keys
  carrying different vocabularies, with nothing enforcing which is which — a
  latent version of exactly this bug.

  Raised in priority by the 2026-08-01 campus work: campus is now a visible
  column on most course-level tables, so a reader sees `ABQ` on one tab and
  `Albuquerque/Main` on another for the same place.

  Found 2026-07-31 via a live bug: Pathways is the only tab filtering on
  *student* campus, and its default was `selected = "ABQ"` — a code that does
  not exist in the label vocabulary. Selectize silently shows an empty
  selection for a `selected` value not present in `choices`, so the filter
  looked deliberate while quietly including all five campuses in every
  population. Fixed by resolving the default against the supplied choices
  (`^ABQ$|^Main$|Albuquer`) instead of hardcoding, but that is a workaround:
  the underlying split remains.

  Why it matters beyond the one default: a user comparing a Pathways population
  against a Regstats or Enrollment view is comparing across two vocabularies,
  and any future feature that filters both sides consistently has to bridge
  them ad hoc. Add a campus lookup alongside the other mappings in F1
  (code ↔ label ↔ display name), and have both columns resolve through it.

  **Watch for the silent-selectize failure mode generally:** a `selected =`
  literal that is not in `choices` fails invisibly. Any hardcoded default
  should be matched against its own column's vocabulary, not assumed. The six
  other `selected = c("ABQ", "EA")` defaults were checked and are correct —
  they all read `cedar_sections$campus`, which does use codes.

---

## Suggested sequencing

1. **Week 1:** A1–A4 + D1 (violations, with tests pinning behavior).
2. **Next:** B1 extractions one tab at a time, each PR = one module + moved
   business logic + its tests. C1 conversions ride along whenever a file is touched.
3. **Ongoing:** D2–D4 as standalone small PRs between extractions; E-items anytime.

One PR = one backlog item. Don't combine an extraction with a conversion with a
rename — small diffs keep the fixture-pinned tests meaningful.

---

## Roadmap audit — tactical backlog (2026-07)

_Moved here from ROADMAP.md so that file holds only vision + potential features. This is the tactical backlog from the 2026-07-09 architecture audit — user-facing issues, documentation debt, testing gaps, ops hygiene, and work sequencing. Many items are already done; kept for status/history._

### 3. User-facing issues (GitHub triage)

Live GitHub audit (2026-07-27): **2 open issues remain**. Closed issues below
are kept only as history/context.

**Currently open:**
- **#36 — Race and gender.** Still open. `cedar_programs` has `ipeds_race` and
  `gender`, and Pathways can define populations by demographic criteria, but the
  user-facing Demographics views do not yet display race/ethnicity/gender
  breakdowns. This is planned as a next-minor enhancement after the
  Enrollment/Regstats/Dept Trends/Dashboard overlap redesign settles the right
  home for chair-facing demographic summaries.
- **#75 — Pathways Course-to-Major heatmap label legibility.** Split from #36's
  older Gen Ed path-diagram note. Source audit found the old Explore > Gen Ed path
  diagram is no longer a live tab surface; the current related UI is Pathways →
  Course to Major → Courses Before Major Entry heatmaps. Verify whether long
  course labels still truncate there and address alongside Pathways visual QA.

**Closed/addressed in the 2026-07 triage pass:**
- **#12 — PADM reports capture health admin enrollments.** Health
  Administration (`MHA-HLAD`, major/program code `HLAD`) now maps to the PADM
  reporting unit. Regenerated `program_map.qs` and local transformed program
  data confirm PADM-scoped views include `HLAD`. Closed 2026-07-27.
- **#14 — DFW by instructor name in the web tool.** Implemented in Course
  Dynamics → DFW as restricted instructor-level DFW with password gating,
  instructor plot/table, and descriptive-use caution language. Closed
  2026-07-27.
- **#22 — Add MPP to department reports.** Current transformed data maps
  MPP/Public Policy (`MPP-PUPO`, `PUPO`) to `PADM`. Closed 2026-07-27.
- **#31 — Enrollment *Trends* vs *Plots* disagreement.** The old issue framing
  is obsolete after the Enrollment Trend Signals/history-scope cleanup. Trend
  scope now caps history at the selected/current term, retains term-type
  filters, uses combined totals where available, and keeps campus-specific
  series separate. Follow-up: consolidate enrollment-history helpers around one
  canonical course-term history spine.
- **#33 — Speech & Hearing missing grad students / Explore crash.** Current
  transformed data maps SHS, SPLP, and CSD to `SHS`; Dept Dashboard, Dept
  Trends, Headcount, and Open Seats edge cases have been fixed/audited.
- **#34 — Headcount date-axis formatting.** Headcount plots now use ordered term
  categories.
- **#74 — Downloadable spreadsheet for Headcount.** Headcount tab now exposes a
  CSV download using the summarized table behind the charts. Closed 2026-07-27.

**Historical / not currently open on GitHub:**
- **#18 — MSST Dept Report errors outright.** Active Dept Trends paths work; the
  crash was isolated to the retired legacy Rmd Dept Report DFW path.
- **#32 — Dept Dashboard "down from average" labeling.** Not currently open;
  related recent-average wording and same-term window explanations were revised
  during the dashboard enrollment-signal cleanup.
- **#35 — Downloadable spreadsheet of SCH from Dept Trends → Credit Hours.** SCH
  downloads exist in Dept Trends → Credit Hours. Keep the broader export
  standardization idea in ROADMAP.md.
- **#7 — Faculty counts from CEDAR.** `get_permanent_faculty_fte()` exists in
  `sfr.R`; this is not currently open on GitHub.

---

### 4. Documentation debt (specific, verified)

#### 4.1 AGENTS.md (the authoritative reference) is missing recent work

**Done 2026-07-12** — cone/branch/report tables updated, module inventory
added, stale `cohortBuilder`/`lookout.R`/`get_course_report_data` references
fixed, and the duplicated Refactoring Status section replaced with a pointer
to the backlog (open items carried over as E4 and F1–F3).
Original findings kept below for the record:

- **Cones absent from the cone table:** `cancellations.R`, `gen-ed-conversion.R`,
  and the `forecast/` subdirectory (4 files: `forecast.R`, `forecast-stats.R`,
  `method-conduit.R`, `method-major.R` — the only cone subdirectory; its pattern
  should be documented or flattened). Forecasting was later archived out of main
  before 1.0 because it is not a release surface and needs a full reboot before
  returning. The old `health-whatif.R` cone was retired before 1.0.
- **Branches absent from the branch table:** `course-flows.R`,
  `pathways.R` (branch).
- **Reports absent from the report table:** `gen-ed.R`.
- **No module inventory exists.** Ten modules ship
  (`admin`, `cancellations`, `gen-ed`, `headcount`, `pathways`, `regstats`,
  `retention`, `seatfinder`, `ui-helpers`, `waitlist`);
  AGENTS.md names only pathways and headcount. Add a module table mirroring
  the cone table.
- **Stale checkboxes/counts:** Phase 2 lists "Seatfinder module" as not done —
  `R/modules/seatfinder.R` exists (429 lines). Phase 3 line counts are stale
  (`enrl.R` "936" → actual 1,328; etc. — B4 (above) has current numbers).
  The Phase lists in AGENTS.md and this backlog now overlap;
  consider deleting the AGENTS.md "Refactoring Status" section entirely in
  favor of this backlog so there is exactly one status list.

#### 4.2 Public developer docs (docs/developers/) predate the current architecture

**Mostly done 2026-07-12** — repo URLs fixed (`fredgibbs` → `cedar-collective`
in index, contributing, installation), `index.md` rewritten for the six-layer
architecture with a current cone list, generator output path and front matter
fixed, `functions.md` regenerated (132 functions, was 77; needs a UTF-8
locale: see the usage note in `scripts/generate-function-docs.R`). Still open:
a fresh-install verification pass over `installation.md`.
Original findings kept below for the record:

- `index.md` and `contributing.md` link to `github.com/fredgibbs/cedar`; the
  project lives at `cedar-collective/cedar` (which `inspecting-cedar.md`
  correctly uses). Issue links, clone commands, and fork instructions all
  point at the wrong repo.
- `index.md` describes a **three-layer** architecture (trunk/branches/cones)
  and a project tree without `R/lists/`, `R/features/`, `R/modules/`, or
  `R/trunk/`. It should describe the six-layer model, or better, link to a
  single canonical architecture page generated from/aligned with AGENTS.md.
- `functions.md` (2,159 lines) says "auto-generated" with a timestamp of
  **2026-02-04** — five months stale. Worse, the generator
  (`scripts/generate-function-docs.R`) writes to `docs/reference/functions.md`,
  a path that doesn't exist; someone moved the output to
  `docs/developers/functions.md` without updating the script. Fix the script's
  `OUTPUT_DIR`, regenerate, and add regeneration to a release ritual (or a CI
  step) so it can't drift silently again.
- Worth a pass over `installation.md` to confirm the `setup.R` /
  `shiny::runApp()` instructions still match reality (the local renv situation in
  §6 suggests the install path deserves a fresh test).

#### 4.3 User docs (docs/users/) are good but have coverage gaps

The per-tab guides are recent and match the current tab names. Missing pages:

- **Retention** (Explore → Retention, `R/modules/retention.R`) — no page.
- **Admin / Data & Usage** — no page explaining the Mappings review surface,
  which is the tool users need for the mapping-gap issues in §3.
- `questions.md` refers to a "**Department Profile** tab" and issue traffic
  uses it too, while the UI and user guide say "Dept Trends" / "Dept
  Dashboard." Pick the canonical names, sweep `questions.md`, changelog
  entries, and UI labels for agreement.

#### 4.4 Root-level docs

- `README.md` is thin: no vision statement, no screenshot, no link to the
  user/developer split, just Docker data-mount notes. For a project whose
  strategy depends on adoption and contribution, the README is the front
  door — a half-page rewrite pointing to the docs site would pay for itself.
- `docs/grade-data-contract-audit.md` is a completed migration audit; mark it
  as historical (or move it to a `docs/decisions/` folder — see §7).

---

### 5. Testing gaps

The fixtures infrastructure is strong; coverage is uneven. Confirmed missing
test files (extends the D-items above):

| Untested surface | Risk |
|---|---|
| `branches/comparison.R` + `cones/course-impact.R` (D2) | **Highest** — observational treatment/control machinery; silent-wrongness produces confidently wrong causal claims |
| `branches/credit-hours.R` (D3) | High — SCH numbers go into program review; only indirectly covered |
| `cones/bottleneck.R`, `course-neighbors.R`, `course-retention.R`, `gened-fulfillment.R`, `branches/degrees.R` (D4) | Medium |
| `features/course-report.R` render path | Medium — Dept Trends support has tests, Course Report render wiring does not |

Also from §3: every user-reported crash in an active surface should land with a
fixture edge case reproducing the data shape that broke, per the existing
edge-case policy in AGENTS.md. The #18/#33 crash path was isolated to the
retired legacy Rmd Dept Report DFW pipeline and should not be revived as a
compatibility target.

E2E: the `tests/e2e/` harness exists and works. The 2026-07 reconciliation
work (#31 and related dashboard/enrollment scoping fixes) is exactly the kind
of cross-tab behavior e2e should pin — one "same course, same filters, two tabs
agree or clearly explain why not" test would guard the product promise directly.

---

### 6. Operations and repo hygiene

**Swept 2026-07-12** — everything below is resolved except the Plumber
decision, which belongs to Theme 5.

- ~~**Local renv is recurrently broken**~~ — root cause found and policy set.
  The renv library symlinks into `~/Library/Caches/org.R-project.R/R/renv/cache`,
  which macOS periodically purges — so every plain `renv::restore()` re-breaks
  at the next purge. Docker deliberately does not use renv, so renv served no
  supported runtime. `Rscript --vanilla` is now the documented standard in
  AGENTS.md "Running tests" (with the durable RStudio+renv fix noted:
  `RENV_CONFIG_CACHE_ENABLED=FALSE` before restoring). `renv.lock` remains as
  the known-good version record.
- ~~**Tracked files inside an ignored directory**~~ — the three pre-ignore
  legacy files under `output/` are untracked (`git rm --cached`); generated
  artifacts no longer ship in the repo.
- ~~**Branch hygiene**~~ — all 22 stale branches pruned, local and remote.
  Every deleted branch's PR was verified MERGED first; the two exceptions were
  `copilot/check-header-image-processing` (zero commits ahead of main — empty)
  and `copilot/fix-data-status-table-error` (12-line diff preserved forever in
  closed PR #29). Remaining branches: `main` plus the active working branch.
  The 5 previously "unmerged-looking" feature branches were in fact all merged
  (squash merges hide this from `git branch --merged` — always check PR state,
  not merge ancestry).
- ~~**Dependabot alerts**~~ (found during this sweep, not in the original
  audit) — all five (2 high, 3 low) were in `docs/Gemfile.lock`:
  `addressable` → 2.9.0, `concurrent-ruby` → 1.3.7, `rexml` → 3.4.4.
- ~~**Versioning**~~ — resolved by inspection, not code: a single source of
  truth already exists. `config/changelog.yml`'s top entry *is* the current
  version, and `server.R` already reads it (`changelog[[1]]$version`) for the
  what's-new modal. The only genuinely open piece is optional: display it in
  a visible About/footer spot. Downgraded from ops issue to nice-to-have.
- **Plumber API** (still open — Theme 5 decision) loads its own copy of all
  CEDAR data at startup, separate from the Shiny app. If it's a supported
  surface, it needs a deploy story and tests; if not, mark it experimental
  in-file and in docs.

---

### 7. Suggested sequencing

#### Now (next 2–4 weeks) — trust, truth, and quick wins

1. ~~**Issue triage pass**~~ — done 2026-07-27; two GitHub issues remain open
   (#36 and #75).
2. **Reconciliation hardening**: keep adding scope stripes/captions for any
   intentionally different scoping (Theme 1). Add one e2e reconciliation test.
3. **Mapping/product cleanup**: Health Administration/HLAD is now included in
   PADM-scoped views (#12); externalize mappings before this class of question
   grows.
4. ~~**AGENTS.md truth pass** (§4.1)~~ — done 2026-07-12, along with most of
   the developer-docs refresh (§4.2).
5. **Tab/functionality redesign**: settle chair-facing vs Explore surfaces before
   adding more Demographics/Enrollment/Regstats displays.
6. **Next-minor enhancement**: race/ethnicity/gender breakdowns with a small-cell
   suppression rule (#36), once the redesigned surface is clear.

#### Next (1–2 months) — decomposition and docs

7. **B2: pathways module push-down** — stop the compounding debt (Theme 2).
8. **B1 extractions** — continue one tab per PR (Data & Usage first, per
   the B1 order above), with C1 plotly conversions riding along.
9. ~~**Developer docs refresh** (§4.2)~~ — mostly done 2026-07-12; remaining:
   fresh-install verification of `installation.md`.
10. **User doc gaps** (§4.3): Retention, Admin pages; naming sweep.
11. **D2 tests** (comparison/course-impact) before any new observational
    features ship.
12. **README rewrite** (§4.4).

#### Later (this year) — the platform bets

13. **Domain-data externalization** (section F above, Theme 4): mappings to data files, college
    code configurable, Admin tab as the mapping-review workflow. This is the
    prerequisite for any second-institution deployment.
14. **Surface portfolio** (Theme 5): mostly **done (2026-07)** — all Rmd reports,
    the CLI dispatcher (`cedar.R` + `command-handler.R`), and the old grade
    report bundle are retired; the RStudio analysis environment is kept. Still
    open: settle the Plumber API's status.
15. **Remaining B3/B4 decompositions and D3/D4 tests** as standing
    between-feature work.
15. **Decision records**: start a lightweight `docs/decisions/` folder (the
    DFW policy, cache-key rule, and grade-contract audit are already de facto
    ADRs scattered across AGENTS.md and docs/) so policy decisions accumulate
    the same way the vision says analyses should.
