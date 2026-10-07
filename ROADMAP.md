# CEDAR Roadmap

This is the single planning document for CEDAR. It should answer three
questions quickly:

- **What do we have?**
- **What needs attention next?**
- **What might we build later?**

Completed work belongs in the repo, the changelog, release notes, and git
history. Do not keep running completion logs here; remove or rewrite finished
items when they stop being useful for planning.

`AGENTS.md` remains the architecture and coding reference.

---

## Product Direction

CEDAR is a transparent, reproducible Shiny analytics platform for higher-ed
curriculum, enrollment, and student experience work. Its strongest promise is
not that every number is simple; it is that every number is explainable.

The product should keep moving toward:

- **Trustworthy numbers:** scope, counting rules, and known caveats are visible
  near the relevant table or plot.
- **Reusable analysis:** business logic lives in branches/cones/features, not in
  Shiny modules or `server.R`.
- **Standard testing:** agents and humans use the standard test runner and do
  not create custom one-off testing scripts.
- **Feature highlighting:** CEDAR should increasingly answer "where should I
  pay attention?" rather than only reporting what a user already knew to query.
- **Installable structure:** UNM-specific mappings and vocabularies become
  reviewable configuration rather than hardcoded assumptions.
- **Focused surfaces:** the Shiny app is the primary product; RStudio analysis
  is supported through the normalized tables and reusable functions.

---

## Current Snapshot

Use this only for scale and prioritization, not as a history log.

| Surface | Current size / state |
|---|---|
Measured 2026-10-07.

| Surface | Current size / state |
|---|---|
| `server.R` | 6,408 lines; several legacy inline surfaces remain |
| `R/modules/pathways.R` | 4,173 lines; still contains business logic (38 `group_by`/`summarize` pipelines) |
| Largest files | `R/branches/enrollment-projections.R` 4,736 · `R/branches/enrl.R` 2,779 · `R/features/dept-dashboard.R` 1,798 |
| Total R code | 96,012 lines (including tests and scripts) |
| Cones / branches / features / modules | 24 / 21 / 10 / 12 files |
| Test suites | 71 designed-fixture R test files; 12 browser suites (focused checks, demo, and the institutional release tour) |
| Institution configuration | `institution/unm/` mapping files (ADR-002), validated at startup |
| Other supported surface | RStudio analysis via `scripts/cedar-repl.R` and the normalized tables |

Supported app surfaces: Dept Dashboard, Dept Trends, Pathways, Course Dynamics
(top level); Regstats, Open Seats, Waitlists, Projections (Registration);
Enrollment, Headcount, Gen Ed (Explore); Cancellations, Data & Usage, Changelog
(Admin). Cross-course Retention is built but hidden until its comparison view
is ready; single-course retention is in Course Dynamics.

---

## Big Product Priorities

These are larger direction-setting priorities. They should shape future feature
work and refactors, even when the immediate task is small.

### 1. Section-Needs Projections

CEDAR should help departments and colleges anticipate section demand before the
schedule is locked. The goal is not a black-box forecast; it is a transparent
projection workflow that shows likely section needs, the evidence behind them,
and where human judgment still matters.

This builds on:

- historical classlist census enrollment and DESR scheduled capacity;
- census/final enrollment distinctions;
- campus and modality scope;
- program populations and pathway/course-taking patterns;
- low-enrollment risk and capacity signals.

Waitlists are deliberately not a projection input. Class lists only began
retaining waitlist rows in 2026 (Summer 2026: 543 rows; Fall 2026: 3,615); a
past term's extract keeps only students still waiting when it closed, so there
is no history to fit or test a waitlist method against yet.

The first shareable Spring-demand pass is implemented: an explicit monitored
course registry, pressure screening, six raw methods plus three fixed
upstream-anchored candidates, rolling-origin aftcasts, capacity-aware row-level
method selection, bias correction,
major/classification-versus-broad-population coupling evidence, confidence,
capacity-aware error assessment, section recommendations, and versioned saved
bundles with embedded model-source provenance. The same feature builder runs in
the persistent R lab and the standalone publisher. Registration > Projections
reads the validated saved bundle
and defaults to the always-monitored group with course-group, department,
course, and confidence filters, export, and navigable drill-down evidence
without recomputing models in a Shiny session.

The projection contract and measured lessons are documented in
`docs/developers/enrollment-projections.md` and
`docs/developers/forecasting-lessons.md`. Remaining product work is:

- [x] Define bundle refresh operations and an official-vintage retention rule:
  automatic freshness checks after successful morning data transformation, replaceable
  working bundles, and permanently retained labeled official vintages.
- [x] Publish Fall targets from the same engine: one bundle per season and a
  reader-chosen target term. The Spring structural methods stay inapplicable to
  Fall by design; the anchored and feeder methods drop out at a two-step
  horizon, so the current Fall bundle is observed-baseline only. Measured no
  accuracy penalty against Spring, thinner depth, and no structural demand
  signal — see the audit in `docs/developers/enrollment-projections.md`.
- [ ] Reuse the saved projection payload on Course Dynamics.
- [ ] Pilot the table and explanations with chairs and associate deans.
- [ ] Develop the *structural* Fall model — splitting continuing students from
  the incoming cohort — which needs retained admissions/acceptance/NSO snapshots
  that CEDAR does not archive today. Blocked on that data, not on the engine.
- [x] Population-growth scenarios over a published bundle: the shared
  `CEDAR_POPULATION_GROUPS` registry, `cohort_composition` saved in the bundle
  (schema 18), and a Scenario sub-tab answering "if health professions grows
  10% a year for five years". Arithmetic over saved rows; nothing is fitted in
  a session.
- [ ] Scenario extensions worth considering: more than one population at once,
  a per-population growth rate, and showing how a population's share of a
  course has moved over time rather than only at the baseline term.
- [ ] Keep testing upstream signals and course-specific method selection without
  weakening the common aftcast and audit contract.

The first useful version can be modest: highlight courses likely to need more,
fewer, or differently scoped sections, with enough context for chairs,
associate deans, and provost-level reviewers to understand the signal.

### 2. Attention Dashboards Across Core Tabs

CEDAR should move from data reporting toward feature highlighting. More tabs
should open with a compact, opinionated dashboard of notable patterns so users
do not have to hunt through controls and tables to find the story.

Regstats is the closest current model: it scans for bumps, dips, saturation,
and waitlist pressure rather than only displaying raw tables. Extend that idea
to DFW reports, enrollment trends, headcount trends, Gen Ed, and other
high-traffic views.

Useful dashboards should be audience-aware:

- **Chairs:** which courses, programs, or student groups need attention now?
- **Associate deans:** which departments or patterns are changing unusually?
- **Provost-level reviewers:** which cross-college patterns, bottlenecks, or
  risks deserve strategic attention?

The pattern to aim for: a first screen with a few ranked signals, concise
explanations, and links into the detailed tables/plots that support each flag.
This should make CEDAR feel less like a data warehouse front end and more like
an analytical partner that points people toward the next useful question.

---

## Highest-Risk Work

### Cleanup sequence before new features

An audit on 2026-10-07 measured where CEDAR could disagree with itself, where it
breaks its own architecture rules, and where pages are built inconsistently.
The counts are below, under the section each belongs to. Work it in this order,
because new features build most cleanly on the first two:

1. **Reconcile counts that are computed twice** (Trust And Reconciliation):
   headcount, then waitlists, then retention, each ending in one helper or a
   documented reason, and a cross-tab test.
2. **Finish ADR-002 Stages 3–5** (Operations And Data Model): the transform
   reads the mapping files, then the old program-map machinery is deleted.
3. **Fix rule violations file by file** (Decomposition): silent fallbacks first,
   because they hide failures; then cones reading globals; then business logic
   in `R/modules/pathways.R`.
4. **Bring pages to one standard, one tab per PR** (Interface Consistency).
5. **Reduce file size alongside whatever touches each file anyway.**

### 1. Trust And Reconciliation

Counting the same thing two ways — found 2026-10-07. Each item ends when both
paths use one helper, or the difference is documented on the page and in
`docs/users/why-numbers-differ.md`, with a cross-tab test either way.

- [ ] **Headcount.** The Dept Dashboard computes its own headcount
  (`get_headcount_summary()` / `get_headcount_series()` in
  `R/features/dept-dashboard.R`, `n_distinct(student_id)`) instead of
  `R/branches/headcount.R`, which the Headcount tab uses. Compare the two on
  real data for the same department and term first.
- [ ] **Waitlists.** `compute_waitlist_pressure()` (`R/cones/bottleneck.R`)
  counts raw waitlist status rows; every user-facing waitlist count should be
  class-list true demand through `R/branches/waitlist-demand.R`, as the
  Waitlists tab already is.
- [ ] **Retention.** Two definitions of "returned next term":
  `next_term_persistence()` (`R/cones/course-outcomes.R`) and
  `.compute_retention()` (`R/branches/retention-context.R`, used by Course
  Dynamics → Retention). Compare their registered-status and right-edge rules.
- [ ] Move the grade-distribution buckets (A/B/C/D/F/W, inline in
  `R/branches/course-attempts.R`) into `R/lists/grades.R` beside the DFW
  constants.
- [ ] Replace hand-derived census and term type with the canonical helpers:
  `registered + dr_late` in `R/branches/enrollment-projections.R`
  (`add_census_enrl()`); `substr(term, 5, 6)` in `R/branches/enrl.R` (2) and
  `R/branches/relative-terms.R` (`add_term_type_col()`).
- [ ] Review the 29 uses of `max(term)` against the right-edge policy — most may
  be a legitimate per-student latest term; `R/branches/population.R` (8) and
  `R/branches/enrollment-projections.R` (5) first.
- Checked and consistent: credit hours (the dashboard uses `filter_sch_rows()`
  and `get_credit_hours()`); the two DFW measures (`get_dfw_rates()` ever-DFW
  versus all-attempt rates) are deliberate and documented.

- [ ] Migrate remaining duplicated explanations into the shared definition
  records as each analysis is reconciled; keep local run-specific scope notes.
- [ ] Add visible scope notes anywhere the same-looking number can differ across
  tabs because of term scope, campus scope, crosslist handling, census/final
  enrollment, current-term exclusion, or grade edge.
- [x] Add at least one cross-tab reconciliation e2e test: same course, same
  user-facing scope, two tabs either agree or visibly explain why they do not.
- [x] Extract shared waitlist-demand logic so Dept Dashboard and Waitlists use
  the same true-demand definition when class-list waitlist rows are available.
- [ ] Keep expanding the usage overview into a glanceable dashboard: key counts,
  unique users, departments, active tabs/features, and trend over time, with
  detail available behind tabs.
- [ ] Identify which core tabs should get Regstats-style attention dashboards
  first: likely candidates are DFW, Enrollment Trends, Headcount Trends, and
  Gen Ed.

### 2. Testing And Data Pipeline Safety

- [x] Distinguish load/timing effects from application bugs in the institutional
  browser gate. Done 2026-09-05: they were **all** load effects. The three
  symptoms were one cause — the Shiny worker OOM-killed mid-tour (the tour grows
  it ~1.3GB against a 3.83GB VM, and a second CEDAR container was resident), after
  which `www/cedar-disconnect.js` reloaded the page and puppeteer blamed the step
  that happened to be running. With the demo stack stopped, the full 17-step tour
  passes in ~1m45s and all twelve suites pass. `lib.mjs` now detects the reload
  and names it; `run-tests.sh` reports memory and competing containers first.
- [ ] Complete institutional release validation of the dependency alignment on a
  host with memory headroom. The gate is green locally now, but a release pass
  should still run where the VM is not at 90% during the tour.
- [ ] On dependency changes, validate the shared lockfile in both the copied
  native library and rebuilt Docker image with their R gates and synthetic
  acceptance. Full institutional validation belongs to release preparation;
  package-version agreement alone does not establish platform equivalence.
- [ ] Require `Synthetic checks` in the `main` branch ruleset after the new
  secret-free PR workflow has run on GitHub. The workflow and local reproduction
  path are implemented; enforcement is a repository-admin setting.
- [ ] Maintain regression coverage for data-pipeline failures that can break
  production updates, especially class-list key type drift, waitlist
  preservation, and parse-step failures.
- [ ] Add direct tests for `R/branches/credit-hours.R`.
- [ ] Add focused coverage for remaining medium-risk cones/branches:
  `course-neighbors.R` and `degrees.R`.
- [ ] Add render-path coverage for Course Dynamics feature wiring.

### 3. Decomposition

Architecture-rule violations measured 2026-10-07 (`AGENTS.md` coding standards).
One file per PR, with tests where behavior changes.

- [ ] **Silent fallbacks** — 25 `tryCatch` blocks returning NULL or an empty
  result: `R/modules/pathways.R` (11), `server.R` (6), `R/trunk/logging.R` (4),
  `R/modules/ui-helpers.R`, `R/cones/stopout.R`, `R/branches/data-edges.R`.
  Keep only the two allowed kinds (a module error shown with
  `showNotification()`, a degenerate statistic returning `NA`).
- [ ] **Cones and branches reading globals** — 16 reads of `data_objects` or
  `exists("cedar_…")`: `R/branches/course-attempts.R` (6), `R/cones/seatfinder.R`
  (3), `R/cones/sfr.R` (2, including `get_sfr(data_objects)`),
  `R/cones/cancellations.R` (2), `R/branches/credit-hours.R` (2),
  `R/cones/waitlist.R`. Every table becomes a parameter.
- [ ] **Business logic in modules** — `R/modules/pathways.R` (38
  `group_by`/`summarize`), `R/modules/cancellations.R` (10),
  `R/modules/gen-ed.R` (2).
- [ ] **Charts** — six `ggplot`/`ggplotly` uses remain; convert to native
  `plot_ly()` when touched.
- [ ] **Cones over the 500-line budget** — `pathway.R` 904,
  `course-demographics.R` 679, `stopout.R` 577, `gen-ed-conversion.R` 542,
  `seatfinder.R` 522.

- [ ] Shrink `server.R` by extracting remaining inline surfaces into modules,
  following `R/modules/headcount.R` and `R/modules/dept-trends.R` as templates.
  Start with the most self-contained surfaces, and move business logic to
  branches/cones/features rather than into the new module.
- [ ] Refactor `R/modules/pathways.R`: inventory `group_by`/`summarize`
  pipelines and push each calculation into the cone or branch that owns the
  question.
- [x] Build reusable course enrollment histories in one grouped pass so
  low-enrollment alerts do not scan the section history row-by-row.
- [ ] Shape the reusable course-history spine so it can support section-needs
  projections as well as low-enrollment alerts.
- [ ] Split repeated filter/summarize/cache-management code out of the longest
  analytical files: `enrl.R`, `regstats.R`, `credit-hours.R`, `pathway.R`, and
  `dept-dashboard.R`.

### 4. Interface Consistency

Pages should look and behave alike. Measured 2026-10-07 in module and UI code:

- [ ] Replace 153 inline `style =` attributes with shared helpers and CSS classes
  (`R/modules/ui-helpers.R`).
- [ ] Replace 53 bare `h3()`–`h6()` headings with `subtab_header()`,
  `dashboard_section()`, `dashboard_subsection()`, and `section_heading()`, each
  with its one-sentence description.
- Do it one tab per PR, with a browser check and a look at the page.

### 5. Documentation And Naming

- [ ] Add function-reference regeneration or a stale-output check to CI.
- [ ] Do a fresh install-doc verification pass.
- [ ] Continue renaming misleading old internal names in focused, tested
  patches: `course-report.R` for Course Dynamics, `seatfinder` for Open Seats,
  and old department-profile naming.

### 6. Operations And Data Model

- [ ] Establish lightweight post-release monitoring for Shiny errors, usage-log
  parsing, scheduled data-update outcomes, and cold-cache dashboard latency.
- [ ] Finish moving department/program/subject/college mappings into
  `institution/<id>/` files
  ([ADR-002](docs/developers/adr-002-explicit-mapping-files.md)). Done: Stages
  0–2 and colleges — the files, validation, the mapping assistant, the audit,
  and the Admin decisions table. Next: decide the largest programs and subjects
  still proposed; Stage 3 (the transform reads the files and stops creating
  self-named departments; closes ISSUES I9, I11, I12); Stage 4 (delete
  `generate_program_map()`, `program_map.qs`, and the lists they fed); Stage 5
  (the demo institution runs on its own files).
- [ ] Report colleges through the mapping (program → unit → college) once Stage
  3 lands; `colleges.csv` and `units.csv` already state them.
- [ ] Normalize campus vocabularies so the same field name cannot mean codes in
  one table and labels in another.
- [ ] Plan the long-term move from report-shaped `cedar_*` tables toward
  domain-shaped facts and dimensions.

---

## Future Product Bets

These are not scheduled until they rise above the maintenance and trust work.

- **Standard CSV/spreadsheet export** across user-facing tables through a shared
  table helper.
- **Demographics by race/ethnicity/gender** in the right chair-facing or
  Explore surfaces, with small-cell suppression.
- **Pathways heatmap legibility** for long course labels and dense course-to-major
  views.
- **Named-instructor DFW display**, if the policy/permissions decision supports
  showing it in the web app.
- **Faculty counts surfaced from CEDAR** through existing faculty/FTE helpers.
- **Low-enrollment exception workflow** for collecting and tracking dean/chair
  decisions against flagged low-enrollment courses.

### Established Analytical Methods

These are evaluation opportunities, not claims that CEDAR already implements
the methods or meets an external reporting standard. Prioritize them after the
underlying counts and shared definitions are reconciled. Each implementation
should expose its population, assumptions, uncertainty, and interpretation
limits through a versioned definition and the docs site.

- [ ] **Separate enrollment growth from worsening outcomes.** Evaluate
  denominator-aware proportion charts or models for drop/DFW rates in Regstats
  and attention dashboards. Keep counts alongside rates to distinguish students
  affected from outcome probability; show practical effect sizes and uncertainty.
  Check independence, changing student mix, and baseline stability before using
  control limits. Reference: [NIST proportion-chart methods](https://www.itl.nist.gov/div898/handbook/pmc/section3/pmc332.htm).
- [ ] **Strengthen gateway-course and sequence comparisons.** Define eligibility,
  prior completion, comparison time, and outcome window before assigning groups.
  Improve baseline diagnostics and evaluate appropriate adjustment and research
  designs without implying that measured balance establishes causality. A
  difference of 0.25 SD is not automatically well balanced; applicable WWC
  designs require adjustment for differences above 0.05 through 0.25 SD.
  Reference: [WWC baseline-equivalence guidance](https://ies.ed.gov/ncee/wwc/Docs/ReferenceResources/WWC-Baseline-Brief-v6_508.pdf).
- [ ] **Model departure, switching, graduation, and return separately.** Evaluate
  time-to-event, competing-risk, or multistate methods for Pathways, with explicit
  states, transitions, and censoring at the observation edge. Treat temporary
  absence as distinguishable from permanent departure; acknowledge that leaving
  UNM does not establish leaving higher education. Reference:
  [Survival package multistate and competing-risk methods](https://cran.r-project.org/web/packages/survival/vignettes/compete.pdf).
- [ ] **Identify structural curricular bottlenecks.** Combine observed
  course-taking with a versioned catalog prerequisite graph. Evaluate blocking
  and delay measures to distinguish difficult courses from courses whose
  curricular position delays later requirements. Observed course pairs alone
  must not be treated as prerequisites. Reference:
  [Curricular Analytics framework](https://arxiv.org/abs/1811.09676).
- [ ] **Evaluate section-planning decisions as well as forecast accuracy.**
  Continue rolling-origin evaluation, then assess the complete model-selection
  and calibration procedure on later held-out terms and comparable data vintages.
  Report potential seat shortages and excess capacity alongside forecast error.
  Reference: [Forecasting: Principles and Practice — time-series cross-validation](https://otexts.com/fpp3/tscv.html).
- [ ] **Add early academic-momentum indicators.** Evaluate credit accumulation,
  credit completion ratios, and first-year gateway completion with explicit
  entering cohorts, transfer treatment, and attempted/completed-credit definitions.
  Use reliable term-level data and reconstructed timelines, not pull-stamped
  cumulative fields. Reference: [Postsecondary Data Partnership metrics](https://studentclearinghouse.org/academy/courses/postsecondary-data-partnership-an-introduction/lessons/the-postsecondary-data-partnership-metrics/).
- [ ] **Set common interpretation safeguards for these analyses.** Separate
  exploratory course flags from confirmatory findings. Where inferential tests
  are retained, address repeated observations and multiple comparisons, and
  report substantive importance alongside statistical evidence
  ([NCES statistical guidance](https://nces.ed.gov/statprog/2002/std5_1.asp)).
  Keep CEDAR's course-based return/retention measures distinct from the specified
  entering cohort and interval in [IPEDS retention](https://nces.ed.gov/ipeds/search/viewtable?returnUrl=%2Fsearch&tableId=36543).
  Review proposed methods for accurate, contextualized, transparent communication
  using [AIR ethical principles](https://www.airweb.org/resources/publications/statement-of-ethical-principles/principles).

---

## Planning Rules

- Keep one live planning list: this file.
- Do not add completed-work narratives here. Close the loop in the code,
  changelog, release notes, and commit history.
- Every PR that adds or renames a cone, branch, feature, module, or user-facing
  surface updates `AGENTS.md`, the relevant docs, and this roadmap in the same
  diff.
- Re-run the scale snapshot before major releases and whenever decomposition
  work changes the shape of the project.
