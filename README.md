CEDAR stands for Curriculuar (and) Enrollment Data Analytics and Reporting

It provides a suite of tools for gathering data from standardized output, filtering, aggregating and doing common analysis and reporting tasks.

It can be run as CLI tool, Rstudio environment, or as a Shiny web app.

Documentation in the [docs folder](https://cedar-collective.github.io/cedar)

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