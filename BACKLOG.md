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
  - `rebuild_dept_report_plots()` in dept-report.R (~265 lines, 8 tryCatch
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
     `R/modules/dept-trends.R` with support in `R/reports/dept-trends.R`.
  6. Course Report (~1644–3433, incl. rollcall plot blocks) — largest, do last
  Rule per extraction: any dplyr pipeline found inline moves to a cone/branch,
  not into the new module.
- [ ] **B2 (L): `R/modules/pathways.R` (4,271 lines) has leaked business logic.**
  41 `group_by`/`summarize` calls live in the module. Inventory them, push each
  into the cone that owns the question (`pathway.R`, `major-changes.R`,
  `population.R`), leaving the module as wiring. Also remove the module's local
  `` `%||%` `` definition — modules always load after trunk, so it can never be
  needed there.
- [ ] **B3 (M): `health-whatif` pair (cone 1,425 + module 1,679 lines).**
  Same treatment: audit the module for computation, push down into the cone;
  split the cone by sub-question if it answers more than one.
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

- [ ] **C1 (M): finish the plotly conversion.** `ggplot()` remains in:
  `R/branches/enrl.R`, `R/branches/headcount.R`, `R/cones/pathway.R`,
  `R/cones/population-trend.R`, `R/cones/gened-fulfillment.R`,
  `R/reports/dept-dashboard.R`, `R/modules/cancellations.R`.
  Convert to native `plot_ly()` when touching each file; do pure conversions as
  standalone small PRs.
- [ ] **C2 (S, decision needed): where do plot functions live?** ~17 `plot_*`/
  `make_*` functions sit inside branches (12 in `credit-hours.R` alone).
  Recommended: keep computation and plotting in the same domain file but split
  them into clearly marked sections, and require every `plot_*` to accept the
  tibble its sibling computation returns (no re-computation inside plot
  functions). Document the decision in AGENTS.md; don't relocate files just
  for tidiness.
- [ ] **C3 (M): `opt$dept` vs `opt$dept_code`** — 40 vs 10 uses. AGENTS.md says
  filter opts use `dept`. Sweep the 10 `opt$dept_code` uses (report params
  `d_params$dept_code` are a different, legitimate context — leave those).
- [ ] **C4 (S): consolidate `` `%||%` `` fallback definitions.** Local copies in
  `comparison.R`, `course-impact.R`, `pathway.R`, `stopout.R`, `pathways.R`
  (module). Keep the documented pattern (bottom-of-file fallback for standalone
  sourcing) for cones/branches but make the definition identical everywhere;
  delete the module copy (B2).

### D. Test coverage gaps

No dedicated test file exists for these; add one per PR, fixtures-only, starting
with the ones used by live tabs:

- [x] **D1 (M): `R/cones/waitlist.R`.** DONE 2026-07-24. Behavioral coverage now
  exercises true waitlist demand (including a student with both WL and RE rows),
  aligned course/program/classification counts, section-supply output, scoped
  enrollment history, and the missing-title/sections error path.
- [ ] **D2 (M):** `R/branches/comparison.R` + `R/cones/course-impact.R` (the
  observational machinery — highest silent-wrongness risk in the codebase).
- [ ] **D3 (M):** `R/branches/credit-hours.R` (only indirectly covered via Dept Trends/report-support tests).
- [ ] **D4 (S each):** `bottleneck.R`, `course-neighbors.R`, `course-retention.R`,
  `gened-fulfillment.R`, `gen-ed-conversion.R`, `degrees.R` branch, `health-whatif.R` cone.

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
mapping-boundary issues like #12 PADM/HLAD (and the now-closed #22 MPP and #33
SHS mapping gaps). See ROADMAP.md Theme 4.

- [ ] **F1 (M):** Move department/program mappings in `R/lists/mappings.R`
  (and `subj_dept_map.R`) to YAML/CSV data files.
- [ ] **F2 (S):** Make the college code configurable (currently hardcoded
  `"AS"` in `credit-hours.R`).
- [ ] **F3 (M):** Document all remaining hardcoded domain values.

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
- **#12 — PADM reports capture health admin enrollments.** Still a real mapping
  boundary decision. Current data has PADM and Public Policy rows under `PADM`,
  but Health Administration/MHA-HLAD is represented separately as `HLAD`, so a
  PADM-scoped view will not include those students unless CEDAR intentionally
  aliases/includes `HLAD` in PADM scope.
- **#36 — Race and gender.** Still open. `cedar_programs` has `ipeds_race` and
  `gender`, and Pathways can define populations by demographic criteria, but the
  user-facing Demographics views do not yet display race/ethnicity/gender
  breakdowns. The Gen Ed path-diagram truncation mentioned in the same issue is
  a separate UI/plot task and should probably be split before implementation.

**Closed/addressed in the 2026-07 triage pass:**
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

- **Cones absent from the cone table:** `health-whatif.R` (1,425 lines — also
  a whole "Healthcare" UI tab), `cancellations.R`, `gen-ed-conversion.R`, and
  the `forecast/` subdirectory (4 files: `forecast.R`, `forecast-stats.R`,
  `method-conduit.R`, `method-major.R` — the only cone subdirectory; its
  pattern should be documented or flattened).
- **Branches absent from the branch table:** `course-flows.R`,
  `pathways.R` (branch).
- **Reports absent from the report table:** `gen-ed.R`.
- **No module inventory exists.** Eleven modules ship
  (`admin`, `cancellations`, `gen-ed`, `headcount`, `health-whatif`,
  `pathways`, `regstats`, `retention`, `seatfinder`, `ui-helpers`, `waitlist`);
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
  and a project tree without `R/lists/`, `R/reports/`, `R/modules/`, or
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

- **Healthcare tab** (`health-whatif`) — a 3,100-line feature with zero user
  documentation.
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
| `cones/health-whatif.R` + its module | High — 3,100 lines, live tab, zero tests |
| `branches/credit-hours.R` (D3) | High — SCH numbers go into program review; only indirectly covered |
| `cones/bottleneck.R`, `course-neighbors.R`, `course-retention.R`, `gened-fulfillment.R`, `branches/degrees.R` (D4) | Medium |
| `cones/forecast/` (4 files) | Medium — has `test-forecast.R`, verify it covers all four method files |
| `reports/course-report.R` render path | Medium — Dept Trends support has tests, Course Report render wiring does not |

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
   (#12 and #36).
2. **Reconciliation hardening**: keep adding scope stripes/captions for any
   intentionally different scoping (Theme 1). Add one e2e reconciliation test.
3. **Mapping/product cleanup**: decide whether Health Administration/HLAD should
   be included in PADM-scoped views (#12); externalize mappings before this
   class of question grows.
4. ~~**AGENTS.md truth pass** (§4.1)~~ — done 2026-07-12, along with most of
   the developer-docs refresh (§4.2).
5. **Quick-win features**: demographics columns with a small-cell suppression
   rule (#36).

#### Next (1–2 months) — decomposition and docs

6. **B2: pathways module push-down** — stop the compounding debt (Theme 2).
7. **B1 extractions** — continue one tab per PR (Data & Usage first, per
   the B1 order above), with C1 plotly conversions riding along.
8. ~~**Developer docs refresh** (§4.2)~~ — mostly done 2026-07-12; remaining:
   fresh-install verification of `installation.md`.
9. **User doc gaps** (§4.3): Healthcare, Retention, Admin pages; naming sweep.
10. **D2 tests** (comparison/course-impact) before any new observational
    features ship.
11. **README rewrite** (§4.4).

#### Later (this year) — the platform bets

12. **Domain-data externalization** (section F above, Theme 4): mappings to data files, college
    code configurable, Admin tab as the mapping-review workflow. This is the
    prerequisite for any second-institution deployment.
13. **Surface portfolio** (Theme 5): mostly **done (2026-07)** — all Rmd reports
    and the CLI dispatcher (`cedar.R` + `command-handler.R`) are retired; the
    RStudio analysis environment is kept. Still open: settle the Plumber API's
    status and finish the remaining report-side `get_grades()` migration in
    Course Report.
14. **Remaining B3/B4 decompositions and D3/D4 tests** as standing
    between-feature work.
15. **Decision records**: start a lightweight `docs/decisions/` folder (the
    DFW policy, cache-key rule, and grade-contract audit are already de facto
    ADRs scattered across AGENTS.md and docs/) so policy decisions accumulate
    the same way the vision says analyses should.
