# CEDAR Roadmap

This is the single planning document for CEDAR. It should answer three
questions quickly:

- **What do we have?**
- **What needs attention next?**
- **What might we build later?**

Completed work belongs in the repo, the changelog, release notes, and git
history. Do not keep running completion logs here; remove or rewrite finished
items when they stop being useful for planning.

`AGENTS.md` remains the architecture and coding reference. `RELEASE-1.0.md`
remains the release checklist for the current milestone.

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
- **Installable structure:** UNM-specific mappings and vocabularies become
  reviewable configuration rather than hardcoded assumptions.
- **Focused surfaces:** the Shiny app is the primary product; RStudio analysis
  is supported through the normalized tables and reusable functions.

---

## Current Snapshot

Use this only for scale and prioritization, not as a history log.

| Surface | Current size / state |
|---|---|
| `server.R` | 5,828 lines; several legacy inline surfaces remain |
| `R/modules/pathways.R` | 4,650 lines; still contains business logic |
| Total R code | 41,234 lines |
| Cones / branches / features / modules | 17 / 13 / 5 / 11 files |
| Test files | 53, fixtures-based |
| Other supported surface | RStudio analysis via `.Rprofile` / `load_global_data()` |
| Undecided surface | `plumber.R` API |

Supported app surfaces: Dept Dashboard, Dept Trends, Course Dynamics, Pathways,
Open Seats, Waitlists, Regstats, Retention, and Admin/Data & Usage.

---

## Next Release Work

These are the remaining release-facing items. Keep this short; detailed release
validation lives in `RELEASE-1.0.md`.

- [ ] Do a server deploy rehearsal before tagging 1.0.
- [ ] Tag the release commit as `v1.0.0`.
- [ ] Deploy production.
- [ ] Run the post-deploy smoke test.
- [ ] Do a final docs pass for the core user pages, especially pages with
  non-obvious calculations or scope differences.
- [ ] Check that production data updates cannot publish mixed-vintage tables
  after a parse failure.

---

## Highest-Risk Work

### 1. Trust And Reconciliation

- [ ] Add visible scope notes anywhere the same-looking number can differ across
  tabs because of term scope, campus scope, crosslist handling, census/final
  enrollment, current-term exclusion, or grade edge.
- [ ] Add at least one cross-tab reconciliation e2e test: same course, same
  user-facing scope, two tabs either agree or visibly explain why they do not.
- [ ] Extract shared waitlist-demand logic so Dept Dashboard and Waitlists use
  the same true-demand definition when class-list waitlist rows are available.
- [ ] Keep expanding the usage overview into a glanceable dashboard: key counts,
  unique users, departments, active tabs/features, and trend over time, with
  detail available behind tabs.

### 2. Testing And Data Pipeline Safety

- [ ] Keep AGENTS and release docs explicit: use `./run-tests.sh`; never write
  custom testing scripts for routine verification.
- [ ] Maintain regression coverage for data-pipeline failures that can break
  production updates, especially class-list key type drift, waitlist
  preservation, and parse-step failures.
- [ ] Ensure update/transform scripts fail closed rather than publishing
  partially refreshed mixed-vintage tables.
- [ ] Add direct tests for `R/branches/credit-hours.R`.
- [ ] Add focused coverage for remaining medium-risk cones/branches:
  `bottleneck.R`, `course-neighbors.R`, `gened-fulfillment.R`, and
  `degrees.R`.
- [ ] Add render-path coverage for Course Dynamics feature wiring.

### 3. Decomposition

- [ ] Shrink `server.R` by extracting remaining inline surfaces into modules,
  following `R/modules/headcount.R` and `R/modules/dept-trends.R` as templates.
  Start with the most self-contained surfaces, and move business logic to
  branches/cones/features rather than into the new module.
- [ ] Refactor `R/modules/pathways.R`: inventory `group_by`/`summarize`
  pipelines and push each calculation into the cone or branch that owns the
  question.
- [ ] Precompute reusable course enrollment history so low-enrollment alerts do
  not scan course history row-by-row.
- [ ] Split repeated filter/summarize/cache-management code out of the longest
  analytical files: `enrl.R`, `regstats.R`, `credit-hours.R`, `pathway.R`, and
  `dept-dashboard.R`.

### 4. Documentation And Naming

- [ ] Add missing user docs for Retention.
- [ ] Add missing user docs for Admin/Data & Usage, especially Mappings.
- [ ] Regenerate developer function docs and make regeneration part of the
  release routine or CI.
- [ ] Do a fresh install-doc verification pass.
- [ ] Continue renaming misleading old internal names in focused, tested
  patches: `course-report.R` for Course Dynamics, `seatfinder` for Open Seats,
  and old department-profile naming.

### 5. Operations And Data Model

- [ ] Decide whether `plumber.R` is supported, experimental, or retired. If
  supported, give it a deploy story and tests.
- [ ] Externalize department/program/subject mappings to YAML or CSV data files.
- [ ] Make college code configurable instead of hardcoded.
- [ ] Normalize campus vocabularies so the same field name cannot mean codes in
  one table and labels in another.
- [ ] Plan the long-term move from report-shaped `cedar_*` tables toward
  domain-shaped facts and dimensions.

---

## Future Product Bets

These are not scheduled until they rise above the maintenance and trust work.

- **Standard CSV/spreadsheet export** across user-facing tables through a shared
  table helper.
- **General course-demand projections** using the reusable population builder,
  campus scope, and course-history spine.
- **Demographics by race/ethnicity/gender** in the right chair-facing or
  Explore surfaces, with small-cell suppression.
- **Pathways heatmap legibility** for long course labels and dense course-to-major
  views.
- **Named-instructor DFW display**, if the policy/permissions decision supports
  showing it in the web app.
- **Faculty counts surfaced from CEDAR** through existing faculty/FTE helpers.
- **Low-enrollment exception workflow** for collecting and tracking dean/chair
  decisions against flagged low-enrollment courses.

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
