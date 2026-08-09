---
title: CEDAR v1.0.0 Release Notes
parent: Developer Guide
nav_order: 10
---

# CEDAR v1.0.0 Release Notes

Target release: 2026-08-09

CEDAR 1.0 is the first release intended to be defended as a stable local
analytics platform rather than a moving internal prototype. The release focuses
on trust: documented methods, consistent definitions, safer reporting edges, and
tests that exercise both analytical functions and rendered Shiny surfaces.

## Headline Changes

- Non-obvious calculations carry high-level explanations and links into user,
  methodology, and implementation documentation.
- Grade-dependent views stop at the last graded term instead of including
  newer terms whose grades have not posted.
- Enrollment reporting uses the settled enrollment edge rather than one
  hand-maintained report-end term.
- Core course outcome and enrollment analytics preserve campus as part of the
  grouping grain, so main, online, and branch delivery are distinguishable.
- DFW policy is centralized: D/F/W grades and late drops count as DFW; early
  drops are shown separately.
- Pathways and Course Dynamics no longer use frozen Academic Studies cumulative
  credit/GPA fields for temporal claims or matching.
- Pathways Course Timing defaults to Classification and clearly states credit
  axis exclusions for left-truncated students.
- Dept Trends Gen Ed now shows Gen Ed uptake among a department's graduates,
  including timing heatmaps and own-unit course views.
- Course Dynamics downstream course lists are derived from observed student
  flow rather than a fixed course list.
- Open Seats preserves topics-course identity where course number
  alone is ambiguous.

## Testing And Release Gate

The standard release gate is:

```bash
./run-tests.sh --all
```

The latest release-candidate run rebuilt the Docker image from the current
working tree and passed all 14 stages:

- e2e selector check
- full R suite: 2,731 passed, 0 failed, 1 known skip
- Docker rebuild and local app warmup
- browser smoke: 15/15 checks
- nav e2e: 11/11 checks
- Course Dynamics and Waitlists deep-link e2e suites
- focused Gen Ed grads, credit timeline, course timing truncation, and Course
  Impact covariate e2e suites

The one known skip is
`test-credit-hours-outside-colors.R:46`: no named program appears at both levels
in the designed fixture. It is a fixture coverage gap, not a failing assertion.

## Data Status

The release gate mounted `/Users/fwgibbs/Dropbox/projects/shared-data`, whose
`cedar-status.json` was generated 2026-08-05. This is newer than the repository's
small local development snapshot and is the data state exercised by the browser
tests.

Release-gate data status:

- sections, students, programs, degrees, student-term credits, and next-term
  lookup: through 202680
- graded outcomes: through 202610, so grade-dependent views correctly stop
  before the ungraded Fall 2026 edge
- sections/programs/degrees source as-of date: 2026-08-05
- students source as-of date: 2026-06-18
- applicants: through 202680, source as-of date 2026-06-18

Before production deployment, compare the production data status against this
tested snapshot and explicitly accept or refresh any older source dates.

## Known Deferrals

- Remaining `server.R` decomposition and module business-logic cleanup.
- User docs can continue to expand after 1.0, especially examples and
  institution-specific interpretation notes.
- GitHub reports one low Dependabot vulnerability on the default branch. Local
  triage found no `tests/e2e` npm audit findings, and the public low-severity
  REXML advisory does not affect the locked docs version (`rexml 3.4.4`).
  Viewing the exact Dependabot alert still requires a refreshed GitHub CLI login
  or the repository Security tab.

## Release Checklist

Before tagging `v1.0.0`:

- run or explicitly defer the true server deploy rehearsal; local production
  dry-runs verified command construction but did not exercise the server
- decide whether the current data snapshot is acceptable
- tag the final release commit
- deploy production
- run post-deploy smoke checks and record the deployed commit/data status
