# CEDAR Roadmap — Vision and Direction

The longer-term vision and potential features for CEDAR. This is the strategic
layer; two working documents hold the day-to-day detail:

- **`AGENTS.md`** — the architecture *reference* and the *how-to-work* rules: the
  layers, the data tables, and the coding standards (layer placement, reuse, no
  silent fallbacks, complexity budget, ships-with-a-test).
- **`BACKLOG.md`** — the tactical *work queue*: a prioritized cleanup/maintenance
  backlog (architecture, decomposition, standardization, testing, docs, ops),
  tracked by item IDs (A1, B2, D3…).
- **`ROADMAP.md`** (this file) — *vision and direction*: the themes and bets that
  say where effort should go and why, plus potential features. Item-level
  maintenance tasks live in `BACKLOG.md`, not here.

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
audit (see BACKLOG.md) fixed all architecture violations (A1–A4) within
days. What remains is the long-tail decomposition work (B-items), plotly
standardization (C1), and test-coverage gaps (D-items).

**The biggest gaps are not in the code — they are in documentation drift and
in the user-facing trust story.** The reference docs have fallen behind the
code in specific, enumerable ways (tracked in BACKLOG.md), and recent GitHub issues have shown users
hitting exactly the problem CEDAR exists to solve — numbers that don't
reconcile between views — *inside CEDAR itself* (see the issue-triage notes in
BACKLOG.md).

Scale snapshot (for calibrating the backlog):

| Surface | Size |
|---|---|
| `server.R` (inline legacy tabs) | 5,207 lines |
| `R/modules/pathways.R` | 4,361 lines (was 4,271 at the 07-09 audit — it is still growing) |
| Total R code | ~42,600 lines |
| Cones / branches / reports / modules | 18 / 11 / 5 / 11 files |
| Test files | 43, fixtures-based |
| Open GitHub issues | 2 (audited 2026-07-27) |

---

## 2. Strategic direction — five themes

These are the through-lines that should drive prioritization. The tactical tasks
that serve them live in `BACKLOG.md`.

### Theme 1: Internal reconciliation is the product promise — treat it as a feature

CEDAR's pitch is "when numbers don't reconcile, the code makes the difference
explainable." Recent issues showed the pitch inverted: users could not easily
reconcile CEDAR with CEDAR. Issue #31 (Enrollment *Trends* vs *Plots* disagree
for the same course), #32 (Dept Dashboard says a course is "down" at 51 vs an
average of 47), and the AGENTS.md note that "Trends intentionally ignores exact
term-code filters" all pointed the same way: **different tabs make different
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
change gets slower. The B-items in BACKLOG.md are the plan; the roadmap
point is *sequencing*: the pathways module grew ~90 lines since the audit
three days ago, which means new Pathways work is still landing in the module
instead of in cones. Hold the line: no new `group_by`/`summarize` in modules,
and schedule B2 (pathways push-down) soon so the debt stops compounding.

### Theme 3: Close the documentation loop or the reference docs will stop being trusted

AGENTS.md is explicitly "the authoritative reference," and agents and human
contributors act on it. It currently omits four cones, two branches, one
report, and nine of eleven modules (tracked in BACKLOG.md). The public developer docs still point
at the old `fredgibbs/cedar` repo and describe a three-layer architecture that
became six layers. Stale authoritative docs are worse than no docs — they
cause confident wrong behavior. The fix is bounded (a few hours of updates)
plus a ritual: **every PR that adds/renames a cone, branch, or module updates
AGENTS.md in the same diff** (this rule already exists in AGENTS.md Coding Standards —
it needs enforcing, because the undocumented files all postdate it).

### Theme 4: Make the "collective" claim installable

The docs promise adaptability across institutions, but UNM-specific knowledge
is hardcoded: college code `"AS"` in `credit-hours.R`, department/program
mappings in `R/lists/mappings.R` and `subj_dept_map.R`, campus and term
conventions. BACKLOG.md section F (externalize domain data to YAML/CSV) is the
right move and should be treated as a real milestone — it is also the answer
to user issues that are really program→department mapping questions. The #12
PADM/HLAD correction is the current concrete example.
A reviewable, data-file-driven mapping layer would let mapping corrections be
config PRs, ideally editable/verifiable via the existing Admin → Mappings tab.

### Theme 5: Decide the surface portfolio deliberately

CEDAR's surfaces are now the Shiny app (primary), an RStudio analysis
environment (analysts load the tables and call the cones directly), and a
Plumber API (`plumber.R`, status still TBD; it duplicates data loading). Former
surfaces - the command-line dispatcher and all Rmd reports - were retired in
2026-07; see below.

**Rmd reports - retired (2026-07).** The app has superseded static reports for
timely and interactive views, and the old department report depended on stale
faculty-count assumptions that are no longer available. `Rmd/dept-report.Rmd`
was removed; `R/reports/dept-report.R` now contains only retired stubs that fail
loudly for stale callers. Active department longitudinal work lives in Dept
Trends (`R/modules/dept-trends.R` + `R/reports/dept-trends.R`).

**CLI — retired (2026-07).** The command-line dispatcher (`cedar.R` +
`command-handler.R` + the `cedar()` RStudio emulator + the `process_output()`
formatter) is gone. Its original rationale (fast iteration) had been fully
superseded by the fixture-based testthat suite, and the audit found it had **no
live producer the app depends on**: the real data pipeline (`parse-data.R` →
`transform-to-cedar.R`) already runs as direct scripts, and the one artifact the
dispatcher wrote (`regstats_dashboard.rds`) was vestigial — nothing loads it (the
app computes regstats live via `get_reg_stats()`). The **RStudio analysis
environment** (`.Rprofile` interactive loading + `load_global_data()`) was kept —
it is a separate surface, not the CLI. **Plumber API** status is still TBD.

---

## 3. Potential features

Forward-looking capabilities worth building when they rise above the maintenance
backlog. These are directions, not scheduled work (scheduled work lives in
`BACKLOG.md`):

- **Standard CSV/spreadsheet export** across data tables — a shared download
  affordance on the table helper rather than per-tab wiring. Requested
  repeatedly (e.g. SCH from Dept Trends → Credit Hours).
- **Demographics by race/ethnicity/gender** in the Demographics views. The
  columns exist in `cedar_programs` (`ipeds_race`, `gender`). Planned for the
  next minor release after the chair-facing dashboard/trends redesign clarifies
  where demographic summaries belong; needs a small-cell suppression rule before
  shipping.
- **Pathways Course-to-Major heatmap legibility** — split out from the older
  #36 Gen Ed path-diagram note. The original Explore > Gen Ed path diagram no
  longer appears to be a live UI surface; the current related surface is
  Pathways → Course to Major → Courses Before Major Entry heatmaps. During
  Pathways visual QA, verify long course labels and adjust margins/label display
  if truncation is still visible.
- **DFW by named instructor** in the web tool. `course-outcomes.R` already
  computes `instructor_dfw`; this is a display + permissions/policy decision
  (named-instructor data is politically sensitive).
- **Faculty counts surfaced from CEDAR** — `get_permanent_faculty_fte()` exists
  in `sfr.R`; expose or document it.
- **A low-enrollment exception workflow** — associate deans collecting and
  tracking dept-chair exception requests against the flagged low-enrollment list.
  Feasibility assessed: valuable but a genuinely new kind of surface for CEDAR
  (needs persistence + user identity), so it's a deliberate build, not a tab.
- **Shared waitlist-demand logic** — extract the true-demand core from the
  Waitlists cone into a reusable branch helper, so the Dept Dashboard waitlist
  card and the Waitlists tab count demand the same way. The dashboard should
  stay compact and fall back to `cedar_sections$waitlist_count` only when
  class-list waitlist rows are unavailable.

---

## 4. Recurring rituals (keep the audit from being needed again)

- Every PR adding/renaming a cone/branch/module updates AGENTS.md tables in
  the same diff (existing rule — enforce it in review).
- Regenerate `functions.md` on release (or in CI) once the generator path is
  fixed.
- Monthly: issue triage; prune merged branches.
- Per release: changelog entry (already habitual), version bump once a
  version source of truth exists.
- Quarterly: re-run the line-count snapshot in §1 and check it against the
  complexity budget in AGENTS.md Coding Standards — growth in `server.R` or any module
  is the early-warning signal.
