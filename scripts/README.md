# CEDAR Scripts

Utility scripts for CEDAR data management and operations.

## update-data.sh

Unified pipeline for updating CEDAR data from MyReports. Works in both production (Docker) and local development environments.

### What it does

Runs the complete data update workflow:
1. **Check** — Verifies if today's MyReports files already exist (skips fetch if found)
2. **Fetch** — Downloads data from MyReports via mrgather (only if needed)
3. **Parse** — Processes raw .xlsx files into R-readable format (parse-data.R)
4. **Transform** — Converts to CEDAR data model (transform-to-cedar.R)
5. **Restart** — (Docker only) Restarts Shiny app and warms it up

**Smart caching:** MyReports data is only updated once per day. If today's files already exist in `mrgather/data/`, the script skips the slow fetch step. This is especially useful when debugging parse or transform errors - you can re-run the script without re-downloading the same data.

### Usage

```bash
./scripts/update-data.sh -s START_TERM [-e END_TERM] [REPORTS...]
```

### Examples

```bash
# Update all reports for a single term
./scripts/update-data.sh -s 202610

# Update multiple terms, all reports
./scripts/update-data.sh -s 202610 -e 202680

# Update only specific reports (DESR and degrees)
./scripts/update-data.sh -s 202610 -e 202680 desr deg

# Quick DESR-only update for current term
./scripts/update-data.sh -s 202680 desr
```

### Report types

| Code | Full Name | Description |
|------|-----------|-------------|
| `desr` | Department Enrollment Status Report | Section-level course data (enrollments, capacity, instructor) |
| `deg` | Degrees | Graduates and pending graduates |
| `as` | Academic Studies | Program/major enrollment by student |
| `cl` | Class Lists | Student-level course enrollment data |

### Parameters

**Required:**
- `-s START_TERM` — Starting term code (e.g., `202610` for Spring 2026)

**Optional:**
- `-e END_TERM` — Ending term code (defaults to START_TERM)
- `REPORTS...` — Space-separated list of reports (default: all four)
- `-h` — Show help message

### Term codes

Term codes follow the format `YYYYSS`:
- `YYYY` = year
- `SS` = semester suffix

| Suffix | Semester |
|--------|----------|
| `10` | Spring |
| `60` | Summer |
| `80` | Fall |

Examples:
- `202580` = Fall 2025
- `202610` = Spring 2026
- `202660` = Summer 2026
- `202680` = Fall 2026

### Environment detection

The script automatically detects whether it's running in Docker or locally:

**Docker (production):**
- Uses `docker compose` to run mrgather
- Runs R scripts inside the `cedar-shiny` container
- Restarts the Shiny app after transformation
- Expects standard production paths (`/root/mrgather`, `/srv/shiny-server/cedar`)

**Local (development):**
- Runs `node` and `Rscript` commands directly
- Finds mrgather relative to cedar directory (`../mrgather`)
- Skips container restart (manual restart needed)
- Uses local config paths

### Prerequisites

**For Docker (production):**
- Docker and docker-compose installed
- `mrgather` container configured at `/root/mrgather/docker-compose.yml`
- `cedar-shiny` container configured at `/root/shiny/docker-compose.yml`
- MyReports credentials configured in mrgather `.env`

**For local (development):**

*Option 1: Docker-based (recommended for environment consistency)*
- Docker and docker-compose installed
- `docker-compose.dev.yml` in CEDAR directory (see [DOCKER-DEV.md](../DOCKER-DEV.md))
- mrgather directory at `../mrgather` with `docker-compose.yml`
- MyReports credentials configured in mrgather `.env`
- **No local R, Python, or xlsx2csv needed!**

*Option 2: Direct installation*
- Node.js installed (for mrgather - optional if using Docker)
- R installed (for parse-data.R and transform-to-cedar.R)
- Python with xlsx2csv package (`pip install xlsx2csv`)
- mrgather directory at same level as cedar (`../mrgather`)
- MyReports credentials configured in mrgather `.env`
- CEDAR config.R configured with local paths

### Typical workflow

**Weekly data refresh:**
```bash
# Update current term data only
./scripts/update-data.sh -s 202680 desr cl
```

**End-of-semester update:**
```bash
# Get final grades and degree data
./scripts/update-data.sh -s 202680 cl deg
```

**Historical data backfill:**
```bash
# Fill in multiple past terms
./scripts/update-data.sh -s 202510 -e 202580
```

**Pre-registration period:**
```bash
# Monitor DESR data for upcoming term
./scripts/update-data.sh -s 202710 desr
```

### Troubleshooting

**"Cannot find mrgather directory"**
- Local only: Ensure mrgather is at `../mrgather` relative to CEDAR
- Or set `MRGATHER_DIR` environment variable before running

**"node not found" / "Rscript not found"**
- Local only: Install Node.js and/or R
- Docker: These should be in the containers (check Dockerfiles)

**"Container cedar-shiny not found"**
- Docker only: Ensure container name matches `CONTAINER_NAME` variable
- Check: `docker ps -a | grep cedar`

**"App did not respond to warmup curl"**
- Docker only: App may still be starting, wait 30s and check manually
- Check logs: `docker logs cedar-shiny`

**Parse errors / transformation errors**
- Check individual script logs in `/data/parse-data-summary.log`
- Verify MyReports file formats haven't changed
- Check that config paths are correct

### Adding this to crontab (production)

For daily automated updates:

```cron
# Daily at 10:02 AM - refresh data, any requested projections, then reload
2 10 * * * /root/cedar/scripts/restart-cedar.sh --mode production --update -s 202680 -e 202710 >> /var/log/cedar-update.log 2>&1
```

This replaces the old multi-step crontab with a single command.
Keep the term window current. `update-data.sh` updates files and report caches;
`restart-cedar.sh --update` also reloads the running app after success.

### Sharing with collaborators

Anyone with both **mrgather** and **CEDAR** can use this script to update their local data:

1. **Clone both repos:**
   ```bash
   git clone https://github.com/yourusername/mrgather.git
   git clone https://github.com/yourusername/cedar.git
   ```

2. **Configure mrgather:**
   - Copy `.env.example` to `.env`
   - Add MyReports credentials

3. **Configure CEDAR:**
   - Edit `config/config.R` with local paths

4. **Run update:**
   ```bash
   cd cedar
   ./scripts/update-data.sh -s 202680
   ```

The script handles the rest automatically!

---

## cedar-repl.R

`cedar-repl.R` bootstraps a persistent, non-Shiny R environment for developing
and inspecting CEDAR computations against local data. Use it for branches,
cones, backtests, and artifact builders when restarting the full app would add no
useful coverage.

Start it from the repository root:

```bash
R --vanilla --quiet
```

```r
source("scripts/cedar-repl.R")
```

The function layers load immediately with Shiny modules disabled. CEDAR tables
load lazily on first access, so a session can materialize only what the analysis
needs:

```r
nrow(cedar_sections)
nrow(cedar_students)

critical_students <- cedar_students |>
  dplyr::filter(subject_course %in% c("BIOL 1140", "CHEM 1215", "MATH 1215"))
```

Keep the process alive, edit code normally, and re-source the changed branch or
cone. Already materialized tables remain resident:

```r
source("R/branches/enrollment-projections.R")
source("R/cones/enrollment-projections.R")
critical_courses <- projection_course_group_courses("critical_courses")
critical_campuses <- projection_course_group_campuses("critical_courses")
critical_market <- projection_course_group_market_id("critical_courses")
always_monitored_courses <-
  projection_course_group_always_monitored_courses("critical_courses")

cl_enrls <- calc_cl_enrls(cedar_students, by_part_term = TRUE)
prepared_inputs <- prepare_enrollment_projection_inputs(
  cl_enrls = cl_enrls,
  sections = cedar_sections,
  students = cedar_students,
  target_courses = critical_courses,
  target_campuses = critical_campuses,
  target_market_id = critical_market,
  enrollment_through_term = 202660L,
  section_through_term = 202680L
)
result <- get_course_enrollment_projections(
  prepared_inputs,
  target_term = 202680L,
  scope_courses = critical_courses,
  force_courses = always_monitored_courses
)
```

After the first input preparation, method edits normally require only the three
`source()` calls and the final cone call. The resident source tables and prepared
inputs are reused.

Build the replaceable working bundle in a clean non-interactive process with:

```bash
Rscript --vanilla scripts/build-enrollment-projections.R \
  --target-term 202680 \
  --as-of-term 202660 \
  --group critical_courses
```

Use `--courses "BIOL 1140,CHEM 1215" --campuses "ABQ,EA" --market-id my_market`
instead of `--group` for an explicit ad hoc scope, and `--output PATH.qs` to
control the artifact path. Named groups carry their own campus and market scope
and always-monitored core; remaining group courses are pressure-screened.
Explicit ad hoc courses are forced through for diagnosis. The publisher runs
the same feature, cone, and branch code as the lab; it does not start Shiny.
The standard comparable-history window begins with Spring 2022; MATH 1215 has a
documented Fall 2025 curriculum break. These effective floors are saved in the
bundle's model configuration.

### Automatic projection refresh

Projection freshness is now automatic. After a successful fetch/parse/transform,
`update-data.sh` runs the builder with `--refresh`. Configure the policy in
`config/enrollment-projections.yml`:

```yaml
enabled: true
target_term: next_spring
as_of_term: latest_settled
group: critical_courses
```

The defaults select the next Spring **after the settled enrollment edge** and
use that edge as the cutoff. Advance registrations do not move this boundary.
Only Spring targets are currently supported. You can pin explicit term codes in
the policy instead, or set `enabled: false` to stop automatic builds. Policy
changes belong in the deployed configuration and should be committed so the
next deploy does not reset them.

The check prepares the canonical model inputs and compares their content,
model-source hashes, scope, and configuration with the saved artifact. Missing,
unreadable, incompatible, or changed bundles rebuild. Older bundles without a
freshness signature rebuild once to acquire it. Identical re-pulls, reordered
prepared rows, and unrelated post-cutoff registrations reuse the artifact
without fitting or rewriting it. New target-course registrations and schedule
changes **do** count because the bundle includes that operational context.
Daily checking still loads and prepares data; it avoids the much more expensive
fitting and rolling backtests when nothing relevant changed.

Production uses a temporary container with the deployed Shiny image and data
mount. Only this publisher gets writable access to the host `output/` folder;
the app mount remains read-only. No host R installation is required. Local
refreshes use system R with `--vanilla`.

To check and refresh immediately, without fetching data again, run from the
deployed repository (normally `/root/cedar`):

```bash
docker compose run --rm --no-deps -T --user "$(id -u):$(id -g)" \
  --volume "$PWD/output:/srv/shiny-server/cedar/output:rw" \
  --workdir /srv/shiny-server/cedar --entrypoint Rscript cedar-shiny \
  --vanilla scripts/build-enrollment-projections.R --refresh
```

For a one-time **forced** build, copy
`config/enrollment-projections-request.example.yml` to
`output/projections/rebuild-request.yml` and fill in `target_term`,
`as_of_term`, and `group`. This overrides the policy for one run and clears
only after successful publication. The next refresh returns to the policy;
edit the policy itself to keep a target or cutoff pinned. Direct
`--target-term ... --as-of-term ... --group ...` builds also remain available.
Manual requests take precedence even when automatic builds are disabled.

New app sessions read the published file; existing sessions need a page reload.
The usual `restart-cedar.sh --update` morning job handles the app restart too.
Ordinary container starts and user sessions never build projections.

Failures preserve the previous artifact, return a nonzero scheduler status, and
retry on the next successful data refresh. A one-shot request remains queued
when it fails. Automatic and manual checks share `rebuild-request.yml.lock`
to prevent overlap. A hard-killed process can leave this lock; only after
confirming no builder is running, remove the empty directory with
`rmdir output/projections/rebuild-request.yml.lock`. Removing a one-shot
request cancels that force-build, not the automatic policy.

By default the command replaces
`output/projections/enrollment-projections-TARGET-latest.qs`. Routine reruns are
not an official forecast archive. When projections are deliberately published
for a scheduling decision, use `--output` with a reviewed, labeled filename to
retain that official vintage.
Store official vintages in a separate `output/projections/vintages/` directory
with a dated decision label, retain them permanently with production backups,
and never reuse a filename. Morning rebuilds replace only the working `latest`
artifact. The saved bundle embeds the normalized model source, SHA-256 hashes,
source provenance, target, cutoff, and build timestamp.

Inspect the canonical text table from the working bundle without starting
Shiny:

```r
bundle <- read_enrollment_projection_bundle(
  "output/projections/enrollment-projections-202680-latest.qs"
)
print_enrollment_projection_preview(
  bundle,
  courses = c("MATH 1215", "CHEM 1215")
)
```

This formatter reads the saved payload and does no model computation. Use it as
the fast table-contract check while developing methods; the eventual UI will
consume the same typed bundle tables rather than the rendered text.

This environment is an exploratory lab, not a test runner or publication path.
Formal behavior belongs in the designed-fixture `testthat` suite, and release
validation still runs through `./run-tests.sh --all`. Restart the REPL whenever
the underlying data files change.

See [Computational Prototyping Without Shiny](../docs/developers/testing.md#computational-prototyping-without-shiny)
for the complete workflow and evidence requirements.

---

## Other scripts (future)

This directory is for utility scripts. Future additions might include:
- `backup-data.sh` — Archive historical data to cloud storage
- `validate-data.sh` — Run data quality checks
- `export-reports.sh` — Generate PDF/CSV reports from data

## Synthetic developer workflow

`bash scripts/dev.sh up` starts the isolated demo on localhost:3839. `restart`
loads editor changes, `test` runs the standard gate in Docker, `logs` follows
diagnostics, and `down` stops the demo while preserving its volumes. No mrgather,
institutional data, or production configuration is needed. See
[Your First Change](../docs/developers/first-hour.md).
