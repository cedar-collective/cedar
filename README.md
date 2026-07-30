CEDAR stands for Curricular and Enrollment Data Analytics and Reporting.

CEDAR is an open-source Shiny analytics platform for higher education curriculum,
enrollment, and student experience data. It helps departments, colleges, and
analysts inspect enrollment patterns, course outcomes, waitlists, credit hours,
student flows, and program trends from standardized institutional data exports.

CEDAR runs as a Shiny web app, with an RStudio analysis environment for analysts
who work with the reusable analysis functions directly.

Documentation: <https://cedar-collective.github.io/cedar>

## Current Release Track

CEDAR is preparing for a 1.0 release on August 9, 2026. The release checklist
and runbook live in [`RELEASE-1.0.md`](RELEASE-1.0.md).

## Docker Compose data path setup

`docker-compose.yml` uses an environment variable for the host data mount:

`CEDAR_DATA_DIR` -> `/srv/shiny-server/cedar/data`

### One-time setup

1. Copy `.env.example` to `.env`
2. Set `CEDAR_DATA_DIR` to the absolute path on your machine

Examples:

- Local macOS: `CEDAR_DATA_DIR=/Users/yourname/path/to/shared-data`
- Droplet: `CEDAR_DATA_DIR=/root/shared-data`

Then run:

```bash
docker compose up -d --build
```

`.env` is gitignored so local and server paths can differ without editing `docker-compose.yml`.
