# CEDAR Next Steps & Agent Working Instructions

Audit date: 2026-07-09. This file has two jobs:

1. **Standing instructions for AI agents** working on this codebase (Part 1).
2. **A prioritized cleanup backlog** from a full architecture audit (Part 2).

Agents: read Part 1 before writing any code. Pick work from Part 2 top-down.
`AGENTS.md` is the authoritative architecture reference; this file is the
work queue and the enforcement checklist.

---

## Part 1 — Standing Instructions for AI Agents

### 1.1 Before writing any function, place it in a layer

Every new function must answer the layer test from AGENTS.md **before** it is written:

| If it… | It goes in… |
|--------|-------------|
| Is a static constant or lookup | `R/lists/` |
| Would work in a non-CEDAR analytics project (term math, filtering, caching, I/O) | `R/trunk/` |
| Is a domain computation used by 2+ cones/reports | `R/branches/` |
| Answers exactly one analytical question | `R/cones/` |
| Assembles multiple cones into a rendered output | `R/reports/` |
| Is Shiny UI/server wiring | `R/modules/` |

**Hard rules, no exceptions:**

- **Cones never call other cones.** If you need two cones' logic, either promote
  the shared piece to a branch, or do the orchestration in a report/module.
- **Cones never touch global state.** No `exists("cedar_sections")`, no reading
  `data_objects` — every table a cone needs is a parameter. If a cone "optionally
  enriches" from a table, make it an optional parameter (see how
  `get_course_outcomes(students, cedar_faculty, opt)` handles optional faculty).
- **Modules contain zero business logic.** No `group_by`/`summarize` pipelines in
  module servers. A module server collects inputs into an `opt` list, calls a
  cone/branch, and renders the result. If you're transforming data in a module,
  stop and move that code into the cone it belongs to.
- **Reports may call multiple cones; nothing else may.**

### 1.2 Reuse before writing

Search these locations, in order, before implementing anything:

1. `R/trunk/utils.R` and `R/trunk/filter.R` — term math, `filter_class_list()`,
   `filter_DESRs()`, `add_next_term_col()`, `validate_population()`, etc.
2. `R/lists/` — `STATUS_REGISTERED`, `STATUS_WAITLIST`, `GRADES_DFW`,
   `GRADES_PASS`. Never inline `c("RE","RS","RR")` or grade strings.
3. `R/branches/` — `build_population()`, `build_comparison()`, `get_grades()`,
   `get_enrl()`, `get_course_section_counts()`.
4. The cone tables in AGENTS.md — an existing cone may already answer your question.

A concrete check: `grep -rn "your_concept" R/trunk R/branches R/lists` before
writing a helper. Duplicated logic found later gets consolidated *up* a layer,
never copied sideways.

### 1.3 No silent fallbacks

Per AGENTS.md coding standards: missing columns, empty joins, and malformed
inputs **stop with an explicit error**. The only permitted `tryCatch` is:

- In module servers, where the error is immediately surfaced via `showNotification()`.
- Around genuinely fallible *statistics* (e.g. `chisq.test` on a degenerate
  table) where `NA` is the correct mathematical answer — not around data access.

`tryCatch(..., error = function(e) NULL)` around a data pipeline is always a bug.

### 1.4 Complexity budget

- New cone functions: aim for < 150 lines per function. If a cone file passes
  ~500 lines, split by sub-question or extract branch helpers.
- New modules: UI and server for one tab, one file. If a module server passes
  ~300 lines, business logic has leaked in — extract it.
- No new dependencies (packages) without explicit user approval. Prefer what
  `renv.lock` already pins.
- Plotting: **native `plot_ly()` only.** No new `ggplot()` + `ggplotly()`. When
  touching a function that uses ggplot, convert it (see Part 2, item C1).

### 1.5 Every change ships with

- A test in `tests/testthat/` filtering from the committed fixtures (never
  inline tibbles), run via
  `Rscript -e "testthat::test_file('tests/testthat/test-<name>.R')"` from repo root.
- Updated AGENTS.md tables if you added/renamed a cone, branch, or module.
- No scratch scripts left at repo root — use `tests/e2e/` for browser-check
  scripts (then delete) or the session scratchpad for one-offs.

---

## Part 2 — Prioritized Backlog (from 2026-07-09 audit)

Sizes: S < 1 hr agent work, M = one focused session, L = multi-session.

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

- [ ] **B1 (L): shrink `server.R` (5,206 lines).** Six tabs are still inline.
  Extract in this order (most self-contained first), one module per PR,
  following `R/modules/headcount.R` as the template (it was extracted from here):
  1. Data & Usage tab (~lines 4773–5167)
  2. Low Enrollment Alert Dashboard (~1004–1644)
  3. Enrollment (`enrl_data`, ~328–1004) — feeds many outputs; map them first
  4. Unit Dashboard (~3471–4081)
  5. Dept Report (~4081–4773)
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

- [ ] **D1 (M):** `R/cones/waitlist.R` — `test-waitlist.R` exists but is mostly
  structural (signature checks, message-prefix style); add behavioral tests for
  `get_unique_waitlisted()` / `inspect_waitlist()` against fixtures, including
  the new sections-parameter error path.
- [ ] **D2 (M):** `R/branches/comparison.R` + `R/cones/course-impact.R` (the
  observational machinery — highest silent-wrongness risk in the codebase).
- [ ] **D3 (M):** `R/branches/credit-hours.R` (only indirectly covered via dept-report tests).
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
- [ ] **E3 (S):** `R/trunk/command-handler.R` (499 lines) and `R/trunk/logging.R`
  (657 lines) — verify they still pass the trunk test ("would work for a
  different analytics project"); if CEDAR-specific report knowledge has crept
  in, split it out.
- [ ] **E4 (S):** Remove commented-out code from `Rmd/` files (carried over
  from the retired AGENTS.md Phase 1 checklist).

### F. Externalize domain data (carried over from the retired AGENTS.md Phase 4)

Prerequisite work for any second-institution deployment; also the fix path for
mapping-gap issues (#22 MPP, #12 PADM, #33 SHS). See ROADMAP.md Theme 4.

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
