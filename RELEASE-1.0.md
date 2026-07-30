# CEDAR 1.0 Release Checklist

Target release date: **August 9, 2026**

CEDAR 1.0 is a trust, polish, documentation, and release-footing milestone. The
goal is not to finish every known idea; it is to make the current core product
stable, explainable, documented, and releasable.

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

- [ ] Dept Dashboard
- [ ] Dept Trends - Enrollment
- [ ] Dept Trends - Credit Hours
- [ ] Dept Trends - Gen Ed
- [ ] Course Dynamics - Enrollment
- [ ] Course Dynamics - DFW
- [ ] Course Dynamics - Retention
- [ ] Open Seats
- [ ] Regstats
- [ ] Waitlists

## Correctness And Trust

- [ ] Commit the current DFW, retention, topics-course, and DD-status batch.
- [ ] Verify topics courses do not duplicate in Open Seats/Seatfinder.
- [ ] Verify cache versioning prevents stale Open Seats/Seatfinder results after deploy.
- [ ] Verify DFW policy on Course Dynamics: non-passing grades plus late drops;
  early drops shown separately.
- [ ] Verify `DD` is treated as an early drop alongside `DR`.
- [ ] Verify unexpected registration statuses are reported near DFW tables,
  especially if they carry nonblank grades.
- [ ] Verify waitlist rows are preserved or explicitly reported when class-list
  imports replace prior rows.
- [ ] Verify Course Dynamics Retention benchmark charts and instructor highlight
  tables behave with and without instructor breakout.
- [ ] Run the focused test set for recently touched areas:
  - [ ] `tests/testthat/test-seatfinder.R`
  - [ ] `tests/testthat/test-enrollment.R`
  - [ ] `tests/testthat/test-course-attempts.R`
  - [ ] `tests/testthat/test-grades.R`
  - [ ] `tests/testthat/test-course-outcomes.R`
  - [ ] `tests/testthat/test-course-retention.R`

## User-Facing Polish

- [ ] Core tables use Cedar table styling consistently.
- [ ] Core charts have readable legends, no overlap, and clear hover text.
- [ ] Scope notes or blue explain boxes exist for non-obvious calculations.
- [ ] Empty states explain what is missing and what the user can change.
- [ ] Duplicate-looking rows have an obvious explanation, especially topics
  courses and crosslisted courses.
- [ ] Restricted instructor-level sections carry descriptive-use caution language.
- [ ] Pages do not rely on docs to explain basic calculation differences.

## Documentation

- [x] Root `README.md` accurately states what CEDAR is and how to run it.
- [x] Docs GitHub links point to the current repository.
- [ ] User docs are current for:
  - [ ] Dept Dashboard
  - [ ] Dept Trends / Department Reports
  - [ ] Course Dynamics
  - [ ] Open Seats
  - [ ] Waitlists
  - [ ] Regstats
- [ ] Add or refresh a "What CEDAR Counts" definitions page.
- [ ] Add or refresh a "Why Numbers Differ Across Tabs" explanation.
- [ ] Add a release/deploy runbook covering deploy, cache, smoke test, and
  rollback.
- [ ] Write `v1.0.0` release notes.

## Release Footing

- [ ] Choose a version source of truth for the app.
- [ ] Surface the version in the app footer or Admin/Data & Usage area.
- [ ] Add `v1.0.0` changelog entry.
- [ ] Run full test suite or document any test groups skipped and why.
- [ ] Do a local smoke test of the core surfaces.
- [ ] Do a server deploy rehearsal before release day.
- [ ] Record cache-clear/cache-version steps for deployment.
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
