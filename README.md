# CEDAR

**Curricular and Enrollment Data Analytics and Reporting**

CEDAR is an open-source analytics platform for higher education curriculum,
enrollment, and student experience data. It provides a runnable Shiny dashboard,
but the project is not best understood as a packaged app that an institution
installs and operates unchanged. CEDAR is a shared codebase, data model,
documentation set, and analysis architecture that higher education data people
can inspect, adapt, and build on together.

Documentation: <https://cedar-collective.github.io/cedar>

## What CEDAR Is

CEDAR has two connected purposes.

**As a dashboard**, it makes unit-level curriculum and enrollment questions
easier to inspect: course demand, DFW patterns, waitlists, credit hours,
student flows, program trends, and related context for departments and colleges.

**As a platform**, it gives analytical work a place to accumulate. Many useful
institutional analyses begin as one-off scripts or spreadsheets. CEDAR turns
those questions into documented, reusable R functions and Shiny views, organized
around a common higher-ed data model.

The goal is not to replace institutional systems of record, enterprise
warehouses, or official IR reporting. CEDAR is a complement: a transparent,
inspectable environment for questions that often fall between standard reports.

## Deployment Framing

CEDAR can run anywhere an institution can run R/Shiny and store its own data.
For the current UNM-hosted instance, that can be as simple as a small server
pulling code from GitHub and mounting a protected data directory. Other
institutions may put it behind a reverse proxy, campus authentication, a
container platform, or an internal analytics server.

That hosting work is real, but it is not the main product model. CEDAR is not a
vendor-managed reporting product with a universal installer, built-in campus
identity integration, or a promise that every institution can point it at raw
SIS exports and immediately run. The durable project is the shared analytics
code and data contract. Each institution owns its own data access, privacy
controls, hosting, and local mappings.

Future reviewers should evaluate CEDAR as:

- a common higher-ed analytics codebase,
- a normalized data model for curricular/enrollment analysis,
- a reference Shiny interface over that model,
- a set of documented definitions and reusable analysis functions,
- and an open place to develop and review methods.

It should not be evaluated as:

- a system of record,
- a campus-wide operational reporting replacement,
- a vendor-hosted SaaS product,
- or a turnkey deployment package for regulated student data.

## Data Integration

The main implementation work for a new institution is data integration. CEDAR
expects normalized `cedar_*` tables, not untouched Banner, PeopleSoft,
Colleague, Canvas, or local spreadsheet exports. Institutions need to map their
local data into the CEDAR model, including local decisions about:

- term codes and academic calendars,
- course identity, topics courses, crosslists, campuses, and colleges,
- registration status codes and withdrawal timing,
- grade values and pass/DFW definitions,
- program, major, department, and college ownership,
- student privacy, hashing, and small-cell rules,
- and data refresh timing.

See the [Data Integration Guide](docs/developers/data-integration-guide.md) and
the [Data Model](docs/developers/data-model.md) for the current contract.

## Running Locally

`docker-compose.yml` uses an environment variable for the host data mount:

`CEDAR_DATA_DIR` -> `/srv/shiny-server/cedar/data`

### One-Time Setup

1. Copy `.env.example` to `.env`.
2. Set `CEDAR_DATA_DIR` to the absolute path for your protected local data.

Examples:

- Local macOS: `CEDAR_DATA_DIR=/Users/yourname/path/to/shared-data`
- Server: `CEDAR_DATA_DIR=/root/shared-data`

Then run:

```bash
docker compose up -d --build
```

`.env` is gitignored so local and server paths can differ without editing
`docker-compose.yml`.

## Project Structure

```text
R/lists/       Static constants and domain lookups
R/trunk/       Shared infrastructure: filtering, data I/O, cache, utilities
R/branches/    Reusable domain computations
R/cones/       Focused analyses that answer one question
R/features/    App-facing orchestration and payload builders
R/modules/     Shiny UI/server modules
docs/          User and developer documentation
tests/         Unit and browser-oriented test coverage
```

## Current Release

CEDAR 1.0 was released on **August 9, 2026**. See the
[1.0 release notes](docs/developers/release-notes-v1.0.0.md) and the reusable
[release runbook](docs/developers/release-runbook.md).

## Contributing

CEDAR is intentionally open because the underlying analytical problems are
shared across higher education. Contributions can be code, tests, documentation,
data-model clarifications, local mapping notes, or issue reports that make a
definition easier to inspect.

Start with the [Developer Guide](docs/developers/index.md) and
[Contributing Guide](docs/developers/contributing.md).
