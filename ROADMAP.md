# CEDAR Roadmap — Project Audit and Priorities

Audit date: 2026-07-12. This document is the strategic layer above the two
existing working documents:

- **`AGENTS.md`** — the architecture *reference*: what the layers are, what the
  tables contain, how to write code here.
- **`NEXT-STEPS.md`** — the tactical *work queue*: a prioritized code-cleanup
  backlog from the 2026-07-09 architecture audit, plus standing agent rules.
- **`ROADMAP.md`** (this file) — *direction and priorities* across the whole
  project: code, documentation, UX, testing, operations, and the collective
  vision. It says where effort should go and why; item-level code tasks stay
  in NEXT-STEPS.md and are referenced by their IDs (A1, B2, D3…).

When an item here is picked up, track it the usual way: one PR per item,
check it off, and update whichever of the three documents it invalidates.

---

## 1. Where the project stands

**The vision is well-articulated and the architecture broadly delivers on it.**
The docs site (`docs/index.md`, `why-cedar.md`, `questions.md`) makes a coherent
case: transparent, reproducible, unit-level curriculum analytics whose
methodology *is* the code, organized so analytical work accumulates instead of
resetting. The six-layer architecture (lists → trunk → branches → cones →
reports → modules), the fixtures-based test suite (~43 test files), the
institutionalized DFW policy, the cache-key correctness rule, the CI-gated
Docker deploy, and the changelog/spotlight system are all real, working
expressions of that vision.

**The codebase is mid-refactor and the refactor is going well.** The 2026-07-09
audit (NEXT-STEPS.md Part 2) fixed all architecture violations (A1–A4) within
days. What remains is the long-tail decomposition work (B-items), plotly
standardization (C1), and test-coverage gaps (D-items).

**The biggest gaps are not in the code — they are in documentation drift and
in the user-facing trust story.** The reference docs have fallen behind the
code in specific, enumerable ways (§4), and the open GitHub issues show users
hitting exactly the problem CEDAR exists to solve — numbers that don't
reconcile between views — *inside CEDAR itself* (§3).

Scale snapshot (for calibrating the backlog):

| Surface | Size |
|---|---|
| `server.R` (inline legacy tabs) | 5,207 lines |
| `R/modules/pathways.R` | 4,361 lines (was 4,271 at the 07-09 audit — it is still growing) |
| Total R code | ~42,600 lines |
| Cones / branches / reports / modules | 18 / 11 / 5 / 11 files |
| Test files | 43, fixtures-based |
| Open GitHub issues | 11 (oldest from 2025-04) |

---

## 2. Strategic direction — five themes

These are the through-lines that should drive prioritization. Individual tasks
in §3–§7 each serve one of these.

### Theme 1: Internal reconciliation is the product promise — treat it as a feature

CEDAR's pitch is "when numbers don't reconcile, the code makes the difference
explainable." The open issues show the pitch inverted: users can't reconcile
CEDAR with CEDAR. Issue #31 (Enrollment *Trends* vs *Plots* disagree for the
same course), #32 (Dept Dashboard says a course is "down" at 51 vs an average
of 47), and the AGENTS.md note that "Trends intentionally ignores exact
term-code filters" all point the same way: **different tabs make different
filtering/scoping choices, and those choices are invisible in the UI.**

Direction: every table/plot that applies a non-obvious scope (crosslist
dedup on or off, summer included or not, term filters ignored, census vs
current enrollment) should say so on-screen — a scope stripe or caption, not
a docs page. A user should never need the repo to explain why two CEDAR tabs
differ. This is the highest-leverage UX investment available and it is mostly
captions and small UI affordances, not new analytics.

### Theme 2: Finish the decomposition before adding major features

`server.R` (5,207 lines, six inline tabs) and `pathways.R` (4,361-line module
with leaked business logic) are where bugs will hide and where every future
change gets slower. The B-items in NEXT-STEPS.md are the plan; the roadmap
point is *sequencing*: the pathways module grew ~90 lines since the audit
three days ago, which means new Pathways work is still landing in the module
instead of in cones. Hold the line: no new `group_by`/`summarize` in modules,
and schedule B2 (pathways push-down) soon so the debt stops compounding.

### Theme 3: Close the documentation loop or the reference docs will stop being trusted

AGENTS.md is explicitly "the authoritative reference," and agents and human
contributors act on it. It currently omits four cones, two branches, one
report, and nine of eleven modules (§4). The public developer docs still point
at the old `fredgibbs/cedar` repo and describe a three-layer architecture that
became six layers. Stale authoritative docs are worse than no docs — they
cause confident wrong behavior. The fix is bounded (a few hours of updates)
plus a ritual: **every PR that adds/renames a cone, branch, or module updates
AGENTS.md in the same diff** (this rule already exists in NEXT-STEPS §1.5 —
it needs enforcing, because the undocumented files all postdate it).

### Theme 4: Make the "collective" claim installable

The docs promise adaptability across institutions, but UNM-specific knowledge
is hardcoded: college code `"AS"` in `credit-hours.R`, department/program
mappings in `R/lists/mappings.R` and `subj_dept_map.R`, campus and term
conventions. NEXT-STEPS.md section F (externalize domain data to YAML/CSV) is the
right move and should be treated as a real milestone — it is also the answer
to a whole class of user issues (#22 MPP, #12 PADM, #33 SHS) that are really
program→department mapping gaps that currently require code changes to fix.
A reviewable, data-file-driven mapping layer would let mapping corrections be
config PRs, ideally editable/verifiable via the existing Admin → Mappings tab.

### Theme 5: Decide the surface portfolio deliberately

CEDAR currently ships four surfaces: the Shiny app (primary), the CLI
(`cedar.R` + `command-handler.R`), a Plumber API (`plumber.R`), and rendered
Rmd reports. Each has maintenance cost (command-handler.R is one of the
remaining `get_grades()` consumers; plumber.R duplicates data loading). Worth
an explicit decision: which surfaces are supported products, which are
experiments, and which should be documented as unsupported. The docs currently
advertise all of them equally.

---

## 3. User-facing issues (GitHub triage)

All 11 open issues, grouped by root cause. These are the users' actual
priorities and several are quick wins.

**Reconciliation / trust (Theme 1):**
- **#31** — Enrollment *Trends* sub-tab vs *Plots* sub-tab show different
  pictures for the same course (CJ 1130). Likely the documented
  different-filter-scope behavior; needs an on-screen scope explanation or a
  genuine bug fix if scopes should match.
- **#32** — Dept Dashboard "down from average" logic confusing/wrong for
  ANTH 2190C (51 shown as *down* from an average of 47). Investigate the
  historical-average comparison and its labeling.

**Program/department mapping gaps (Theme 4):**
- **#33** — Speech & Hearing: Master's/doctoral students missing; Explore tab
  fails for the department. Likely mapping and/or grad-program coverage.
- **#22** — Add MPP to department reports.
- **#12** — Confirm PADM reports include health-admin students (mapping
  boundary question — the answer should be visible in the Admin Mappings tab).
- **#18** — MSST Dept Report errors outright. A department whose report
  crashes is also a missing-test case: reproduce, fix, and pin with a fixture
  edge case if the data shape is unusual.

**Feature requests (small, high goodwill):**
- **#35** — Downloadable spreadsheet of SCH from Dept Trends → Credit Hours.
  A general pattern is better: audit which tables lack CSV download buttons
  and add a standard download affordance to the table helper.
- **#36** — Add race/ethnicity/gender to the Demographics views. The columns
  exist in `cedar_programs` (`ipeds_race`, `gender`); this is display wiring
  plus small-cell suppression policy (decide a minimum-n rule before shipping).
- **#14** — DFW by instructor name in the web tool. `course-outcomes.R`
  already computes `instructor_dfw`; this is a display/permissions decision
  (named-instructor data is politically sensitive — decide policy, then wire).
- **#7** — Faculty counts from CEDAR. `get_permanent_faculty_fte()` exists in
  `sfr.R`; expose or document.

**Plot polish:**
- **#36 (second half)** — Gen Ed path diagram appears truncated.
- **#34** — Date axis formatting on Headcount → Undergrad majors (headcount.R
  is also on the ggplot→plotly conversion list, C1 — fix together).

Also: several issues have sat unanswered since 2025. Even a triage pass that
labels each (bug / mapping / feature / question) and posts a one-line status
would strengthen the collaborative-project story the docs lead with.

---

## 4. Documentation debt (specific, verified)

### 4.1 AGENTS.md (the authoritative reference) is missing recent work

**Done 2026-07-12** — cone/branch/report tables updated, module inventory
added, stale `cohortBuilder`/`lookout.R`/`get_course_report_data` references
fixed, and the duplicated Refactoring Status section replaced with a pointer
to NEXT-STEPS.md (open items carried over as NEXT-STEPS E4 and F1–F3).
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
  (`enrl.R` "936" → actual 1,328; etc. — NEXT-STEPS B4 has current numbers).
  The Phase lists in AGENTS.md and Part 2 of NEXT-STEPS.md now overlap;
  consider deleting the AGENTS.md "Refactoring Status" section entirely in
  favor of NEXT-STEPS.md so there is exactly one status list.

### 4.2 Public developer docs (docs/developers/) predate the current architecture

**Mostly done 2026-07-12** — repo URLs fixed (`fredgibbs` → `cedar-collective`
in index, contributing, installation), `index.md` rewritten for the six-layer
architecture with a current cone list, generator output path and front matter
fixed, `functions.md` regenerated (132 functions, was 77; needs a UTF-8
locale: see the usage note in `scripts/generate-function-docs.R`). Still open:
a fresh-install verification pass over `installation.md` / `cli-usage.md`.
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
- Worth a pass over `installation.md` / `cli-usage.md` to confirm the
  `setup.R` / `cedar.R -f shiny` instructions still match reality (the local
  renv situation in §6 suggests the install path deserves a fresh test).

### 4.3 User docs (docs/users/) are good but have coverage gaps

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

### 4.4 Root-level docs

- `README.md` is thin: no vision statement, no screenshot, no link to the
  user/developer split, just Docker data-mount notes. For a project whose
  strategy depends on adoption and contribution, the README is the front
  door — a half-page rewrite pointing to the docs site would pay for itself.
- `docs/grade-data-contract-audit.md` is a completed migration audit; mark it
  as historical (or move it to a `docs/decisions/` folder — see §7).

---

## 5. Testing gaps

The fixtures infrastructure is strong; coverage is uneven. Confirmed missing
test files (extends NEXT-STEPS D-items):

| Untested surface | Risk |
|---|---|
| `branches/comparison.R` + `cones/course-impact.R` (D2) | **Highest** — observational treatment/control machinery; silent-wrongness produces confidently wrong causal claims |
| `cones/health-whatif.R` + its module | High — 3,100 lines, live tab, zero tests |
| `branches/credit-hours.R` (D3) | High — SCH numbers go into program review; only indirectly covered |
| `cones/bottleneck.R`, `course-neighbors.R`, `course-retention.R`, `gened-fulfillment.R`, `branches/degrees.R` (D4) | Medium |
| `cones/forecast/` (4 files) | Medium — has `test-forecast.R`, verify it covers all four method files |
| `reports/course-report.R` render path | Medium — dept-report has tests, course-report does not |

Also from §3: every user-reported crash (#18 MSST, #33 SHS) should land with a
fixture edge case reproducing the data shape that broke, per the existing
edge-case policy in AGENTS.md.

E2E: the `tests/e2e/` harness exists and works, but only `nav.test.mjs`
asserts anything. The two reconciliation issues (#31, #32) are exactly the
kind of cross-tab behavior only e2e can pin — one "same course, same filters,
two tabs agree" test would guard the product promise directly.

---

## 6. Operations and repo hygiene

- **Local renv is recurrently broken** (per project memory: broken again
  2026-07-09 after a 2026-06-17 repair). Standing workaround is
  `Rscript --vanilla`. Decide: either fix renv for real (rebuild the local
  library and document the recovery), or officially demote renv to
  "Docker-only" and update AGENTS.md test instructions to `--vanilla`
  everywhere so agents stop rediscovering this.
- **Tracked files inside an ignored directory:** `/output/` is gitignored but
  `output/csv/enrollments.csv`, `output/dept-reports/html/HIST.html`, and
  `output/parse-data-summary.log` are committed (pre-ignore legacy). `git rm
  --cached` them so generated artifacts stop shipping in the repo.
- **Branch hygiene:** ~15 merged local branches and their remote counterparts
  linger (`fix-*`, `regstats-part-of-term`, `serve-app-at-root`, several
  `copilot/*` and `claude/*`). Prune merged branches; decide whether the
  unmerged ones (`feature/cedar-data-model`, `feature/dept-dashboard`,
  `pathways-concept-docs`, `chore/cleanup-and-whatsnew`, `delete-ai-reference`)
  are live, mergeable, or deletable — unmerged branches are invisible WIP.
- **Versioning:** the changelog uses versions (v.10.3.0) but no version string
  exists in code/config. Cheap fix: single source of truth in `config/` that
  the changelog and an About footer both read.
- **Plumber API** loads its own copy of all CEDAR data at startup, separate
  from the Shiny app. If it's a supported surface (Theme 5), it needs a
  deploy story and tests; if not, mark it experimental in-file and in docs.

---

## 7. Suggested sequencing

### Now (next 2–4 weeks) — trust, truth, and quick wins

1. **Issue triage pass** — label all 11 issues, answer the stale ones (§3).
2. **Reconciliation fixes**: investigate #31 and #32; ship scope
   stripes/captions for any intentionally different scoping (Theme 1). Add
   one e2e reconciliation test.
3. **Mapping bugs**: #18 (MSST crash) and #33 (SHS) — fix with fixture
   edge cases; #22/#12 via mapping data updates.
4. ~~**AGENTS.md truth pass** (§4.1)~~ — done 2026-07-12, along with most of
   the developer-docs refresh (§4.2).
5. **Quick-win features**: CSV download affordance (#35), demographics
   columns with a small-cell suppression rule (#36).

### Next (1–2 months) — decomposition and docs

6. **B2: pathways module push-down** — stop the compounding debt (Theme 2).
7. **B1 extractions** — continue one tab per PR (Data & Usage first, per
   NEXT-STEPS order), with C1 plotly conversions riding along (#34 fixes the
   headcount axis while converting `headcount.R`).
8. ~~**Developer docs refresh** (§4.2)~~ — mostly done 2026-07-12; remaining:
   fresh-install verification of `installation.md` / `cli-usage.md`.
9. **User doc gaps** (§4.3): Healthcare, Retention, Admin pages; naming sweep.
10. **D2 tests** (comparison/course-impact) before any new observational
    features ship.
11. **README rewrite** (§4.4).

### Later (this year) — the platform bets

12. **Domain-data externalization** (NEXT-STEPS F, Theme 4): mappings to data files, college
    code configurable, Admin tab as the mapping-review workflow. This is the
    prerequisite for any second-institution deployment.
13. **Surface portfolio decision** (Theme 5): support/experimental status for
    CLI, Plumber, Rmd reports; align docs and `get_grades()` migration plan
    (the legacy bundle's remaining consumers are course-report, dept-report,
    and the CLI — the decision here determines whether that migration ever
    finishes).
14. **Remaining B3/B4 decompositions and D3/D4 tests** as standing
    between-feature work.
15. **Decision records**: start a lightweight `docs/decisions/` folder (the
    DFW policy, cache-key rule, and grade-contract audit are already de facto
    ADRs scattered across AGENTS.md and docs/) so policy decisions accumulate
    the same way the vision says analyses should.

---

## 8. Recurring rituals (keep the audit from being needed again)

- Every PR adding/renaming a cone/branch/module updates AGENTS.md tables in
  the same diff (existing rule — enforce it in review).
- Regenerate `functions.md` on release (or in CI) once the generator path is
  fixed.
- Monthly: issue triage; prune merged branches.
- Per release: changelog entry (already habitual), version bump once a
  version source of truth exists.
- Quarterly: re-run the line-count snapshot in §1 and check it against the
  complexity budget in NEXT-STEPS §1.4 — growth in `server.R` or any module
  is the early-warning signal.
