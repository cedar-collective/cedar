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

Open [localhost:3839](http://localhost:3839/). The yellow synthetic-data notice
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
restart the R worker after changes. The demo is fixed to Fall 2026, not the
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

Use `Rscript --vanilla` for local scripts and the standard `./run-tests.sh`
gate when its R and Node dependencies are installed. The Docker wrapper is the
supported alternative when they are not. `renv.lock` records known package
versions, but restoring the local renv cache is not a prerequisite or the
supported repair path for the test gate. Do not use `renv::deactivate()` as a
setup fix; it rewrites the project's `.Rprofile`.
