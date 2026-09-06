---
title: Installation
parent: Developer Guide
nav_order: 1
---

# Installation

Choose the environment for the work you want to do. Evaluating CEDAR or making
a contribution should not require access to institutional data.

## Contributors: Docker with synthetic data

Install Git and Docker with Compose, start Docker, and open a terminal:

```bash
git clone https://github.com/cedar-collective/cedar.git
cd cedar
bash scripts/dev.sh up
```

Open [localhost:3838](http://localhost:3838/). The yellow synthetic-data notice
identifies the development instance. No local R, Node, `.env`, mrgather, or
production credentials are needed. Any editor works; R runs inside Docker.

Follow [Your First Change](first-hour.html) for the complete edit → restart →
browser check → test → PR workflow, expected demo results, and troubleshooting.

```bash
bash scripts/dev.sh restart  # reload saved source, then refresh the browser
bash scripts/dev.sh test     # selector checks and complete R suite in Docker
bash scripts/dev.sh logs     # follow startup/app diagnostics
bash scripts/dev.sh down     # stop; preserve synthetic data and caches
```

The first build downloads packages and can take several minutes. Subsequent
builds reuse Docker layers. Development source is mounted from the checkout;
restart the R worker after changes. The demo is fixed to Fall 2025, not the
computer's current date. Small-cell guards still apply, and saved projections
are not supplied.

## Institutional instance: restricted data and production-style Docker

This is a separate operational path, not the contributor quickstart. It requires
an approved data location containing normalized `cedar_*` files and the
corresponding `program_map.qs`. See [Data Integration](data-integration-guide.html)
for source mapping and validation, and the [Release Runbook](release-runbook.html)
for deployment. Access controls, retention, and backups are institution-owned.

The production `docker-compose.yml` reads `CEDAR_DATA_DIR` from `.env`, expects
the external `shiny-net` network, and bakes application source into its image.
It also needs a machine-local `config/shiny_config.R`, created from
`config/shiny_config_template.R`. For full institutional data, set
`cedar_use_small_data <- FALSE` and review term/scope settings.

These local configuration files are not committed. `.env` and `.Renviron`
are excluded from Docker build contexts. Never copy real data or secrets into
a PR. Unlike the synthetic demo, production-style containers must be rebuilt
to pick up source changes.

Do not combine `compose.dev.yml` with the production Compose file or point the
demo volumes at institutional data. The contributor launcher intentionally
ignores `.env` and uses its own network and volumes.

## Advanced: native R analysis

CEDAR is a Shiny application, not an installable R package. There is no
`library(cedar)` or `devtools::test()` entry point. Developers with an already
configured R environment can work directly with the analytical functions and
approved local normalized tables; see [Testing](testing.html) for computational
prototyping and the `scripts/cedar-repl.R` bootstrap.

### Prepare the same R packages as Docker

Keep native R if you want a persistent analysis session: data can stay loaded
while you re-source an edited branch or cone. Docker is still the default
first-hour path and the reference for system libraries and browser acceptance.

`renv.lock` is the shared package contract, not a historical inventory. It pins
R **4.4.2** and the packages from the tested Docker runtime. The September 2026
alignment preserved those runtime versions, including Shiny 1.10.0, dplyr
1.1.4, and qs2 0.2.2; it was not a package-upgrade exercise. Unused entries from
the old drifting lockfile and Docker-only `littler`/`docopt` helpers are not part
of the shared application library.

Install R 4.4.2 and Node, then run from the repository root:

```bash
Rscript --vanilla scripts/r-environment.R restore
Rscript --vanilla scripts/r-environment.R check-native
./run-tests.sh --project-library
```

The explicit restore uses `renv` to prepare
`renv/library/cedar/R-4.4.2/<platform>/`. Packages are physical copies, never
links into a purgeable cache. Exact matching installed packages are copied;
missing versions are downloaded. The command does not alter system libraries,
local data, the old renv library, `.Rprofile`, or `.Renviron`. Network access is
needed only during setup. Native source builds may require compiler/system
libraries; use Docker if those are unavailable. RStudio itself is optional.

Restart R after setup. Normal native startup selects the prepared library and
retains the existing automatic data-loading behavior when `config/config.R`
exists. Opening an unconfigured checkout does not launch a setup wizard or
install packages. Docker never activates a project library at runtime.

For a persistent vanilla R console, explicitly select the prepared library
**before loading any packages**, then use the usual analysis helper:

```r
source("scripts/r-environment.R")
cedar_use_native_library()
cedar_check_dependencies(library = cedar_native_library())
source("scripts/cedar-repl.R")
# Re-source changed functions as needed; keep already-loaded data in memory.
```

`./run-tests.sh` continues to use system R by default. The new
`--project-library` option uses the exact same tests with the prepared native
library; it does not restore packages or skip tests. `Rscript --vanilla
scripts/r-environment.R check` reports drift in system R without changing it.
Do not use `renv::deactivate()` or a bare `renv::restore()` as a setup fix: use
the shared helper so you do not revive the old cache-linked startup path.

### Changing dependencies

Review package/R changes deliberately in `renv.lock`. Keep the R version in
`Dockerfile.shiny` and the renv bootstrap version in `renv/activate.R` consistent.
Do not snapshot an arbitrary system library over the lockfile. The repository
URL is dated, not `latest`, and ordinary source edits reuse Docker's dependency
layer. Docker runs the same restore helper during its build and fails if the
result differs from the lockfile; no packages are installed during app startup.

**Two dated snapshots, on purpose.** `renv.lock` declares `CRAN`
(`.../cran/2025-03-01`) for the application stack and `CRAN_QS2`
(`.../cran/2026-06-05`) for `qs2`, `stringfish`, and `RcppParallel`. CEDAR's
saved `.qs` data is written by qs2 0.2.2, released 2026-06-03 — long after the
Shiny 1.10.0 / dplyr 1.1.4 / ggplot2 3.5.1 stack this app is tested against. One
snapshot date cannot express both, and the pre-alignment `Dockerfile.shiny`
encoded the same split as a separate `install.packages(..., repos =
'.../2026-06-05')` line.

Every pinned version must be the **current** version in its named repository.
That is the invariant to preserve, and it is not cosmetic: a version that is
merely *available* at the snapshot resolves through `src/contrib/Archive/`,
which forfeits PPM's prebuilt Linux binaries and compiles from source. Pointing
the whole lockfile at 2026-06-05 while keeping 2025-era pins put 96 of 133
packages on that path and broke the image build outright — `forcats 1.0.0`
failed to retrieve and the PR gate went red. After changing any pin, confirm the
version matches its repository's index before relying on the build:

```bash
curl -s https://packagemanager.posit.co/cran/2025-03-01/src/contrib/PACKAGES |
  grep -A1 '^Package: forcats$'
```

After a lock change, repeat native restore/check/tests, rebuild the image, and
run synthetic acceptance. Run the full institutional gate when preparing a
release, as described in [Testing](testing.html). A native library prepared
against an older lockfile is rejected until restored. These checks cover package versions, not identical
OS/compiler/BLAS behavior; Docker remains the reference runtime. See the
[renv Docker guidance](https://rstudio.github.io/renv/articles/docker.html).
