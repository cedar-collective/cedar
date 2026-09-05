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

For incoming PRs, require the **Synthetic checks** status from **PR Checks** in
the `main` branch ruleset after the workflow has run once. Enabling this is a
repository-admin setting, not something the workflow turns on itself. This
check uses invented data and cannot deploy; it supplements rather than replaces
the institutional release checks below.

Start from a clean working tree and an up-to-date branch:

```bash
git status --short
git pull --ff-only
```

Run the unit tests before cutting a release candidate:

```bash
./run-tests.sh
```

For release-candidate work, run the complete release gate:

```bash
./run-tests.sh --all
```

If a group cannot be run, record the reason in the release notes before
deploying.

Confirm the app-visible version. The newest entry in `config/changelog.yml` is
the source of truth:

```bash
Rscript --vanilla -e 'cedar_base_dir <- getwd(); source("R/trunk/changelog.R"); print(get_cedar_version_info())'
```

Before each release, add its changelog entry, confirm it is shown in Data &
Usage, and tag the final release commit.

## 2. Local Smoke Check

Build or restart the local container:

```bash
docker compose up -d --build
```

Check that Shiny responds:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3838/
```

Review the core release surfaces:

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

The browser smoke suites cover most of this mechanically:

```bash
./run-tests.sh --e2e
```

If Chrome cannot launch, resolve that setup failure and rerun before treating
the release candidate as smoke-tested.

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

### Projection artifact

For a release that includes Registration > Projections, publish the validated
latest bundle on the host before restarting the app. `docker-compose.yml`
mounts the gitignored repository `output/` directory read-only:

An ordinary Git push or production deploy does **not** publish this artifact:
`output/` is excluded from Git and from the Docker build context. For the normal
morning refresh, `restart-cedar.sh --mode production --update` automatically checks
and, if necessary, builds it in a temporary container before restarting the app.
The policy is `config/enrollment-projections.yml`: by default, the next Spring
after the settled enrollment edge with that edge as the cutoff. A missing or
incompatible bundle, changed model code, scope, or prepared inputs causes a
rebuild. Otherwise the existing artifact is reused without fitting or rewriting.
Failure preserves the prior artifact and reports a failed refresh for retry.

See the [scripts guide](https://github.com/cedar-collective/cedar/blob/main/scripts/README.md#automatic-projection-refresh)
for policy settings, force-rebuild requests, and an immediate Docker check; production does
not need a host R installation. Alternatively, securely copy a locally reviewed
bundle into `CEDAR_PATH/output/projections/`, or build directly when the host
has the required R environment:

```bash
Rscript --vanilla scripts/build-enrollment-projections.R \
  --target-term 202710 --as-of-term 202660 --group critical_courses
```

Confirm that `output/projections/enrollment-projections-202710-latest.qs`
exists. The cutoff must be the latest settled enrollment term; as of this
release, Fall 2026 is still active, so the valid cutoff is Summer 2026 (`202660`).
Publish an official artifact from a clean commit: the bundle records the
commit, checks whether model files were modified, and embeds their normalized
source and hashes. Shiny reads this artifact and never recomputes it during a
session.

### If GitHub deploy fails with "No space left on device"

That error is from the production host, not the GitHub runner. The deploy job
fetches into the checkout on the droplet and builds Docker images there, so old
Docker build cache and unused images can fill the disk before `git fetch`
finishes.

The GitHub deploy workflow now checks free space before touching Git. If the
checkout has less than 2 GiB free, it automatically prunes unused Docker build
cache, images, and stopped containers, then retries the space check. It does
**not** prune Docker volumes.

If the workflow still fails after the automatic prune, SSH to the production
host and inspect:

```bash
df -h /root/cedar /var/lib/docker
docker system df
du -xhd1 /root/cedar | sort -h | tail -20
du -xhd1 /var/lib/docker | sort -h | tail -20
```

Safe first manual cleanup:

```bash
docker builder prune -af
docker image prune -af
docker container prune -f
```

Avoid `docker volume prune` unless you have confirmed no CEDAR data is stored in
Docker volumes on that host.

## 5. Cache Handling

CEDAR stores runtime cache files under `data/cache` inside the app data mount.
Most cache keys include either source-data dimensions, the current term, or a
short freshness window, but code changes can still require explicit action.

| Cache | How it invalidates | Clear after |
|:--|:--|:--|
| Course-neighbors / course flows | Source table shape plus 7-day freshness window. | Flow logic changes, course identity logic changes, or stale Course Dynamics flows. |
| Dept Trends tab cache | Manual version, department, report window, tab-specific scope, visual palette, calendar year where needed, and source-data fingerprints. Ready-to-render charts and their analytical tables warm after production data refreshes. | Dept Trends logic or payload-shape changes. Source-file and palette changes invalidate automatically. |
| Pathways population benchmarks | Manual version, current term, college, campus, level, and scope. | Benchmark logic changes or mid-cycle comparison data corrections. |
| Open Seats (`seatfinder`) | Manual version, filter options, and `cedar_sections` hash. | Open Seats grouping/filter logic changes, especially course identity and topics-course fixes. |

Use Data & Usage > Cache for normal cache clearing:

- Clear Course Dynamics Cache
- Clear Dept Trends Cache
- Clear Pathways Benchmarks

When a cache key does not naturally change after a logic fix, bump the relevant
manual cache version in `R/trunk/cache.R`. For example, Open Seats
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

For a performance-sensitive release, also review the median and P90 end-to-end
times, wait/delivery time, and worker memory in Data & Usage. See
[Performance Monitoring](performance-monitoring.html) for interpretation.

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
