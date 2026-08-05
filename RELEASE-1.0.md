# CEDAR 1.0 Release Checklist

Target release date: **August 9, 2026**

CEDAR 1.0 is a trust, polish, documentation, and release-footing milestone. The
goal is not to finish every known idea; it is to make the current core product
stable, explainable, documented, and releasable.

## UX North Star

1.0 should feel consistent, transparent, and economical.

- **Consistency:** repeated interaction patterns should behave the same way
  across tabs. Tables, blue explain boxes, empty states, modals, filters, and
  restricted sections should look and behave like they belong to one product.
- **Transparency:** users should be able to tell what a number means without
  reading the source code. Scope and counting choices should be visible near the
  table or plot they affect.
- **Economy:** show enough to prompt useful questions, not everything the data
  can possibly say. Prefer compact charts, top/bottom review tables, accordions
  for detail, and deferring raw tables behind clear labels.
- **Expansive but not overwhelming:** 1.0 can include a few new ideas when they
  broaden what users understand data can tell them, but only when the concept is
  easy to read in one glance and supported by clear explanation.

## Release Rules

- No major new analytical features after **August 3** unless they fix correctness,
  trust, or a blocking usability issue.
- Every blocker must have either a fix or a written 1.1 deferral decision.
- Every user-facing number in a core tab should make its counting scope visible
  on-screen when the scope is not obvious.
- Every bug fixed for 1.0 ships with a focused regression test when practical.
- The final release commit should be tagged `v1.0.0`.

## Core Surfaces

These are the 1.0 smoke-test surfaces. Polish here matters more than polish in
lower-traffic corners.

- [x] Dept Dashboard — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Dept Trends - Enrollment — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Dept Trends - Credit Hours — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Dept Trends - Gen Ed — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Course Dynamics - Enrollment — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Course Dynamics - DFW — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Course Dynamics - Retention — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Open Seats — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Regstats — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.
- [x] Waitlists — SMOKED 2026-08-04 via `./run-tests.sh --e2e smoke`.

## Correctness And Trust

- [x] **Campus grouping across course-level analytics.** DONE 2026-08-01. Course
  figures are grouped by campus, not merely filtered by it — branch and online
  delivery were being folded into what reads as a main-campus number, wrong by
  25–35% on the highest-enrollment courses. Covers Gen Ed, Course Dynamics >
  Retention, and Pathways. See the CEDAR-wide campus policy in AGENTS.md.
- [x] **Program Health campus scope stated.** DONE 2026-08-01. `health-whatif.R`
  is deferred past 1.0 by decision, so the tab now says its figures combine all
  campuses and will not match other tabs.

- [ ] Commit the current DFW, retention, topics-course, and DD-status batch.
- [x] Verify topics courses do not duplicate in Open Seats/Seatfinder. VERIFIED
  2026-08-04 by focused Seatfinder tests plus Open Seats browser smoke.
- [ ] Verify cache versioning prevents stale Open Seats/Seatfinder results after deploy.
- [x] Verify DFW policy on Course Dynamics: non-passing grades plus late drops;
  early drops shown separately. VERIFIED 2026-08-01 against real data (ENGL 1120,
  ABQ: 312 early-drop rows, 145 late-drop rows). Early drops are excluded from the
  denominator, never counted as DFW, and tracked separately; every late drop counts
  as DFW. Checked on real data because the fixture has zero early-drop rows, so the
  same assertions pass vacuously against it.
- [x] Verify `DD` is treated as an early drop alongside `DR`. VERIFIED 2026-08-01.
  `STATUS_DROP_EARLY <- c("DR", "DD")`, and on real data both resolve identically on
  every rate: 0% in denominator, 0% DFW, 100% early-drop (DR n=211, DD n=101).
- [ ] Verify unexpected registration statuses are reported near DFW tables,
  especially if they carry nonblank grades.
- [x] Verify waitlist rows are preserved or explicitly reported when class-list
  imports replace prior rows. VERIFIED 2026-08-01 — **they are not preserved**, and
  now they are reported. `WL` rows survive at 580 for the current term (202610) but
  only 1–12 per term for all 13 prior terms: waitlist status is a live registration
  state, so a completed term retains only students still waitlisted at close. That
  is defensible, but nothing said so, and a near-empty historical result reads as
  "no demand" rather than "not retained". The Waitlists tab now states it.
- [ ] Verify Course Dynamics Retention benchmark charts and instructor highlight
  tables behave with and without instructor breakout.
- [x] Run the focused test set for recently touched areas. VERIFIED 2026-08-04:
  `./run-tests.sh` passed the full R suite, including `test-seatfinder.R`,
  `test-enrollment.R`, `test-course-attempts.R`, `test-course-outcomes.R`, and
  `test-course-retention.R`. The checklist's old `test-grades.R` entry was
  stale; no such file exists, and grade/drop policy is covered by course-attempt
  and course-outcome tests.

## User-Facing Polish

- [ ] Core tables use Cedar table styling consistently.
- [ ] Core charts have readable legends, no overlap, and clear hover text.
- [ ] Scope notes or blue explain boxes exist for non-obvious calculations.
- [ ] Empty states explain what is missing and what the user can change.
- [ ] Duplicate-looking rows have an obvious explanation, especially topics
  courses and crosslisted courses.
- [ ] Restricted instructor-level sections carry descriptive-use caution language.
- [ ] Pages do not rely on docs to explain basic calculation differences.

## Candidate Insight Additions Before Feature Freeze

These should ship in 1.0 only if they stay compact, explainable, and aggregate.
If they need new conceptual machinery or heavy UI, defer them to 1.1.

- [x] **Course Dynamics DFW context:** add a compact aggregate visualization for
  students who DFW the selected course showing whether that course was an
  isolated DFW in an otherwise successful term, one of several DFW outcomes, or
  part of a term where the student struggled broadly. Suggested shape: a small
  stacked bar or 100% bar with buckets such as "only DFW was this course",
  "some other courses passed", and "DFW/non-pass in most courses", plus an
  explain box defining the denominator and suppressing small cells. This should
  answer: is the course unusually hard for otherwise successful students, or is
  it mainly DFWing students already struggling across the term?

## Visible UI Audit Priorities

These are ordered by what users can notice immediately.

- [ ] **Table consistency:** core user-facing tables should use the Cedar
  `reactable` style unless there is a concrete reason to keep `DT`. Current
  high-priority mixed surfaces include Course Dynamics tables, retention tables,
  Admin/Data & Usage tables, and older module tables.
  - Progress: Course Dynamics Enrollment, Rollcall, DFW, and Retention tables
    now use the Cedar `reactable` style; Admin/Data & Usage and selected older
    modules still need review.
  - Progress: Admin/Data & Usage and Cache Management tables now use Cedar
    `reactable` styling. Remaining `DT` use is concentrated in older analysis
    detail panels that need a separate review.
  - Progress: Course Dynamics impact detail tables, Dept Trends outside-major
    breakdown, standalone Retention tables, and simple Health What-If tables now
    use Cedar `reactable` styling. Health What-If's large enrollment matrix
    remains a documented `DT` exception for wide-table performance/custom matrix
    display.
- [ ] **Explain-box consistency:** use `info_panel()` for column guides,
  methodology details, and raw-detail sections. Reserve always-open alerts for
  warnings, errors, or a short essential note. Current drift: Course Dynamics has
  several custom `alert alert-info` methodology blocks that should become
  compact summaries plus accordions.
  - Progress: Course Dynamics DFW and Retention now use collapsible
    `info_panel()` column/methodology guides for the main outcome tables; dynamic
    warning/status messages remain always visible.
- [ ] **Modal consistency:** standardize modal titles, close buttons,
  `easyClose`, destructive-confirmation footers, and error modal wording.
  Current drift appears in changelog, department-filter explanation, Admin cache,
  Health What-If, and Cancellations.
  - Progress: Added shared `cedar_info_modal()` and `cedar_confirm_modal()`
    helpers. Changelog, department-filter explanation, Admin cache confirmation,
    Health What-If detail, Cancellations error, and Pathways guard modals now
    use the same close/confirm behavior.
- [ ] **Section economy:** each tab should have a clear first answer, then
  optional detail. Use top/bottom tables and compact charts before full raw
  tables. Course Dynamics DFW and Retention are the reference pattern to refine.
  - Progress: Dept Trends > Enrollment now keeps long-run historical signals
    and removes selected-term signal cards that belong on Dept Dashboard; the
    dashboard now includes late-drop watch alongside above/below history,
    waitlist, early-drop, low-enrollment, activity, and audience signals.
- [ ] **Inline business logic risk:** avoid adding new data-shaping pipelines to
  modules or `server.R` during 1.0 polish. If UI cleanup exposes calculation
  logic in a module, either leave it alone for 1.1 or move it to a branch/cone in
  a focused tested patch.
- [ ] **Empty states:** use `empty_state()` or consistent short text for
  pre-run, no-data, and insufficient-data states. Avoid bare `NULL` outputs when
  the user needs to know what happened.
- [ ] **Copy economy:** replace long always-visible explanations with one short
  sentence plus an accordion. The screen should answer "what am I looking at?"
  before it answers "how is every column computed?"

## Documentation

- [x] Root `README.md` accurately states what CEDAR is and how to run it.
- [x] Root `README.md` frames CEDAR as a shared analytics platform and codebase,
  not a turnkey deployed product.
- [x] Docs GitHub links point to the current repository.
- [x] Add a data integration guide explaining local mapping work, normalized
  `cedar_*` tables, and hosting/access responsibilities.
- [ ] User docs are current for:
  - [ ] Dept Dashboard
  - [ ] Dept Trends / Department Reports
  - [ ] Course Dynamics
  - [ ] Open Seats
  - [ ] Waitlists
  - [ ] Regstats
- [x] Add or refresh a "What CEDAR Counts" definitions page.
- [ ] Add or refresh a "Why Numbers Differ Across Tabs" explanation.
- [x] Add a release/deploy runbook covering deploy, cache, smoke test, and
  rollback — see `docs/developers/release-runbook.md`.
- [ ] Write `v1.0.0` release notes.

## Release Footing

- [x] Choose a version source of truth for the app — newest entry in
  `config/changelog.yml`, exposed through `get_cedar_version_info()`.
- [x] Surface the version in the app footer or Admin/Data & Usage area — shown
  on Admin > Data & Usage > Data Summary.
- [x] Add `v1.0.0` changelog entry — verified 2026-08-04 via
  `get_cedar_version_info()`.
- [x] Run full test suite or document any test groups skipped and why. VERIFIED
  2026-08-04: `./run-tests.sh` passed with 2,516 pass / 0 fail / 1 skip. The
  skip is the known credit-hours outside-major colour fixture gap: no named
  program appears at both levels in the fixture.
- [x] Do a local smoke test of the core surfaces. VERIFIED 2026-08-04:
  `./run-tests.sh --e2e smoke` passed all 12 browser checks against the local
  Docker app.
- [ ] Do a server deploy rehearsal before release day.
- [x] Record cache-clear/cache-version steps for deployment.
- [ ] Tag the release commit as `v1.0.0`.
- [ ] Deploy production.
- [ ] Run post-deploy smoke test.

## Parking Lot For 1.1

These are important but should not block 1.0 unless a specific bug makes them
urgent.

- Continue `server.R` decomposition.
- Push remaining module business logic into branches/cones.
- Externalize UNM-specific mappings/configuration.
- Finish plotly conversion backlog.
- Add race/ethnicity/gender demographic views with small-cell suppression.
- Decide Plumber API status.
- Standardize downloads across every table surface.

## Daily Release Rhythm

- Start each day by moving any new idea to: blocker, polish, docs, or 1.1.
- End each day with: current blockers, tests run, and what is safe to defer.
- After August 3, only release blockers and polish fixes should enter the batch.
