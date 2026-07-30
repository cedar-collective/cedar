---
title: Release Runbook
parent: Developer Guide
nav_order: 9
---

# Release Runbook

Use this checklist when preparing a CEDAR release or deploying a production
refresh. It is meant to keep versioning, data refreshes, cache behavior, and
smoke tests explicit enough that a release can be repeated without relying on
memory.

## 1. Preflight

Start from a clean working tree and an up-to-date branch:

```bash
git status --short
git pull --ff-only
```

Run the unit tests before cutting a release candidate:

```bash
Rscript --vanilla tests/testthat.R
```

For release-candidate work, also run the focused tests listed in
`RELEASE-1.0.md` for recently touched surfaces. If a group cannot be run, record
the reason in the release checklist before deploying.

Confirm the app-visible version. The newest entry in `config/changelog.yml` is
the source of truth:

```bash
Rscript --vanilla -e 'cedar_base_dir <- getwd(); source("R/trunk/changelog.R"); print(get_cedar_version_info())'
```

Before the final 1.0 release, add the `v1.0.0` changelog entry, confirm it is
shown in Data & Usage, and tag the final release commit.

## 2. Local Smoke Check

Build or restart the local container:

```bash
docker compose up -d --build
```

Check that Shiny responds:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3838/
```

Review the core release surfaces from `RELEASE-1.0.md`:

| Surface | What to confirm |
|:--|:--|
| Home | Recent highlights load from the changelog. |
| Data & Usage | Data Summary renders and shows the current CEDAR version. |
| Dept Dashboard | Selected-term cards load with no obvious table/chart styling drift. |
| Dept Trends | Enrollment, Credit Hours, and Gen Ed tabs run and show explain text near non-obvious numbers. |
| Course Dynamics | Enrollment, DFW, and Retention tabs run for a known course. |
| Open Seats | Shared autorun URLs run; topics courses do not duplicate incorrectly. |
| Regstats | Each signal subtab renders and shareable URLs still restore filters. |
| Waitlists | Waitlist rows appear when present and empty states are understandable. |

## 3. Data Refresh

Use `scripts/update-data.sh` for MyReports refreshes. It fetches data through
mrgather, parses raw files, transforms them into CEDAR tables, and restarts the
app in production mode.

Dry-run first when changing terms or report types:

```bash
./scripts/update-data.sh --mode production --dry-run -s 202680 -e 202710 desr cl
```

Then run the real update:

```bash
./scripts/update-data.sh --mode production -s 202680 -e 202710 desr cl
```

Use report subsets deliberately:

| Report | Use when |
|:--|:--|
| `desr` | Section availability, capacity, cancellation, and schedule data changed. |
| `cl` | Class-list registrations, drops, grades, waitlists, or demographics changed. |
| `as` | Program, major, population, or cohort data changed. |
| `deg` | Degree completion data changed. |
| `aa` | Applicant data changed. |

For a code-only deploy with no data refresh, skip this step.

## 4. Deploy Or Restart

For a code-only production deploy, update the production checkout and restart:

```bash
git pull --ff-only
./scripts/restart-cedar.sh --mode production --hard-restart --log-tail 80
```

For a data update followed by reload, prefer the combined script:

```bash
./scripts/restart-cedar.sh --mode production --update -s 202680 -e 202710 desr cl --log-tail 80
```

`restart-cedar.sh` warms the app with a curl check and prints a step summary.
If warmup returns a non-2xx/3xx status, check the container logs before
considering the deploy complete.

The GitHub production workflow can show a friendly nginx-served restart page
while the Shiny container is being replaced. See
[Deployment Maintenance Page](deployment-maintenance.html) for the one-time
nginx setup and marker-file behavior.

## 5. Cache Handling

CEDAR stores runtime cache files under `data/cache` inside the app data mount.
Most cache keys include either source-data dimensions, the current term, or a
short freshness window, but code changes can still require explicit action.

| Cache | How it invalidates | Clear after |
|:--|:--|:--|
| Course-neighbors / course flows | Source table shape plus 7-day freshness window. | Flow logic changes, course identity logic changes, or stale Course Dynamics flows. |
| Dept Trends tab cache | Department, configured report end term, ISO week, and tab. | Dept Trends logic changes or corrected historical data that must appear immediately. |
| Pathways population benchmarks | Manual version, current term, college, campus, level, and scope. | Benchmark logic changes or mid-cycle comparison data corrections. |
| Seatfinder / Open Seats | Manual version, filter options, and `cedar_sections` hash. | Seatfinder grouping/filter logic changes, especially course identity and topics-course fixes. |

Use Data & Usage > Cache for normal cache clearing:

- Clear Course Report Cache
- Clear Dept Trends Cache
- Clear Pathways Benchmarks

When a cache key does not naturally change after a logic fix, bump the relevant
manual cache version in `R/trunk/cache.R`. For example, Open Seats/Seatfinder
uses `cedar_seatfinder_cache_version`.

## 6. Post-Deploy Smoke Test

After production reload, repeat the core surface smoke check against the
production URL. Include at least one known autorun URL for Open Seats because it
exercises URL restoration, filtering, and the Seatfinder cache path together.

Record:

- release version shown on Data & Usage
- git commit deployed
- data terms refreshed
- cache actions taken
- smoke-test surfaces checked
- any known deferrals

## 7. Rollback

For a code rollback, return the production checkout to the last known-good tag
or commit and restart the app:

```bash
git checkout <known-good-tag-or-commit>
./scripts/restart-cedar.sh --mode production --hard-restart --log-tail 80
```

For a data rollback, restore the previous data files from the server backup or
snapshot process, then restart. If the issue may involve cached outputs, clear
the affected cache family before rechecking the surface.
