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
# Daily at 10:02 AM - fetch current term data
2 10 * * * /root/cedar/scripts/update-data.sh -s 202680 -e 202710 >> /var/log/cedar-update.log 2>&1
```

This replaces the old multi-step crontab with a single command.

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

## Other scripts (future)

This directory is for utility scripts. Future additions might include:
- `backup-data.sh` — Archive historical data to cloud storage
- `validate-data.sh` — Run data quality checks
- `export-reports.sh` — Generate PDF/CSV reports from data
