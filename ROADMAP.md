# CEDAR Roadmap

This is CEDAR's plan for **new features and significant upgrades**. It answers:

- **What do we have?**
- **Where is the product going, and in what order?**
- **What might we build later?**

Known problems and improvements to what already exists — defects, debt,
inconsistencies, missing tests, interface standards — live in
[`ISSUES.md`](ISSUES.md), and this file links to them rather than repeating
them. The test for which file: if someone could write "done when…" for it today
against existing code, it is an issue; if it needs design or a decision about
something new, it is here.

Completed work belongs in the repo, the changelog, release notes, and git
history. `AGENTS.md` remains the architecture and coding reference.

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
- [ ] Shape the reusable course-history spine so it supports section-needs
  projections as well as low-enrollment alerts.

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

First decide which core tabs get one: likely DFW, Enrollment Trends, Headcount
Trends, and Gen Ed.

The pattern to aim for: a first screen with a few ranked signals, concise
explanations, and links into the detailed tables/plots that support each flag.
This should make CEDAR feel less like a data warehouse front end and more like
an analytical partner that points people toward the next useful question.

---

## Before New Features: Cleanup

An audit on 2026-10-07 measured where CEDAR could disagree with itself, where it
breaks its own architecture rules, and where pages are built inconsistently.
The findings are entries in [`ISSUES.md`](ISSUES.md). Work them in this order,
because new features build most cleanly on the first two:

1. **Reconcile counts computed twice** — all three confirmed 2026-10-07; I17
   (two "returned next term" definitions on Course Dynamics → Retention) fixed
   in #119. I15 (headcount department scope) fixed with Stage 3. I16
   (bottleneck waitlist pressure) is RStudio-only: decide its definition, or
   retire it. Each gets one helper or a documented difference, with a cross-tab
   test. Then M1–M3 and M24 (lifecycle labels).
2. **Finish ADR-002** (below), which also closes I7, I9, I11, and I12.
3. **Architecture rules, file by file** — M11 (silent fallbacks) first, because
   they hide failures; then M12 (global reads) and M13 (logic in modules).
4. **Interface consistency, one tab per PR** — M17, M18.
5. **File size alongside other work** — M14, M16.

---

## Significant Upgrades

Larger changes to how CEDAR works, each needing design. Smaller, concrete
improvements are in [`ISSUES.md`](ISSUES.md).

### 1. Explicit mapping files (ADR-002)

Every unit, college, and program relationship stated in reviewable files under
`institution/<id>/`, so adopting CEDAR means editing files, not code.
Plan: [ADR-002](docs/developers/adr-002-explicit-mapping-files.md).

- Done: Stages 0–2 and colleges — the files and their validation, the mapping
  assistant, the transform-time audit, and the Admin decisions table.
- [ ] Decide the largest programs and course subjects still proposed (Admin →
  Data & Usage → Mappings; `scripts/mapping-review.R`).
- Done 2026-10-09: **Stage 3**, units — the transform takes every unit from the
  files and creates no self-named department. Closed I7; I11's stored units.
- Done 2026-10-10: **Stage 3b**, colleges — students under their primary
  major's college, courses under their subject's, Banner's value labelled for
  codes not yet decided. Closed I12.
- Done 2026-10-10: **Stage 4** — `generate_program_map()`, `program_map.qs` and
  `program_code_maps.R` retired; runtime lookups and pre-major flags come from
  the files. Closed I9.
- [ ] **Stage 5:** the demo institution runs on its own files — the adopter test.

### 2. Domain-shaped data model (ADR-001)

- [ ] Plan the long-term move from report-shaped `cedar_*` tables toward
  domain-shaped facts and dimensions; ADR-002's unit dimension is the first
  piece.

### 3. Operational monitoring

- [ ] Lightweight post-release monitoring for Shiny errors, usage-log parsing,
  scheduled data-update outcomes, and cold-cache dashboard latency.

---

## Future Product Bets

These are not scheduled until the cleanup above is done.

- **Standard CSV/spreadsheet export** across user-facing tables through a shared
  table helper.
- **Demographics by race/ethnicity/gender** in the right chair-facing or
  Explore surfaces, with small-cell suppression.
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

- Two live lists: this file for new features and significant upgrades;
  [`ISSUES.md`](ISSUES.md) for defects and improvements to what exists. Link,
  don't copy: a roadmap item names the issue IDs it depends on.
- When a roadmap item ships, the leftover concrete work becomes issues.
- Do not add completed-work narratives here. Close the loop in the code,
  changelog, release notes, and commit history.
- Every PR that adds or renames a cone, branch, feature, module, or user-facing
  surface updates `AGENTS.md`, the relevant docs, and this roadmap in the same
  diff.
- Re-run the scale snapshot before major releases and whenever decomposition
  work changes the shape of the project.
