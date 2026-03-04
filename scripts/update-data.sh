#!/usr/bin/env bash
#
# update-data.sh — Unified CEDAR data update pipeline
#
# Runs the complete data update workflow:
#   1. Fetch data from MyReports (via mrgather)
#   2. Parse raw data files (parse-data.R)
#   3. Transform to CEDAR model (transform-to-cedar.R)
#   4. (Docker only) Restart app and warm up
#
# Works in both production (Docker) and local environments.
#
# Usage:
#   update-data.sh -s START_TERM -e END_TERM [reports]
#
# Examples:
#   update-data.sh -s 202610 -e 202680              # All reports (desr, deg, as, cl)
#   update-data.sh -s 202610 -e 202610 desr deg    # Only DESR and degrees
#   update-data.sh -s 202610                        # Single term, all reports
#
# Report options: desr deg as cl
#   desr = Department Enrollment Status Report (section data)
#   deg  = Degrees (graduation data)
#   as   = Academic Studies (program/major data)
#   cl   = Class Lists (student enrollment data)

set -e  # Exit on any error

# ── Colors for output ────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Helper functions ─────────────────────────────────────────────────────────
log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# ── Detect environment ───────────────────────────────────────────────────────
detect_environment() {
    if [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        echo "docker"
    else
        echo "local"
    fi
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") -s START_TERM [-e END_TERM] [REPORTS...]

Update CEDAR data by fetching, parsing, and transforming MyReports data.

Required:
  -s START_TERM    Starting term code (e.g., 202610 for Spring 2026)

Optional:
  -e END_TERM      Ending term code (defaults to START_TERM)
  -h               Show this help message
  REPORTS          Space-separated list of reports to fetch (default: all)
                   Options: desr deg as cl

Examples:
  $(basename "$0") -s 202610 -e 202680              # All reports, Spring 2026 - Fall 2026
  $(basename "$0") -s 202610 desr deg               # Only DESR and degrees for Spring 2026
  $(basename "$0") -s 202580                        # All reports for Fall 2025

Report types:
  desr   Department Enrollment Status Report (section/course data)
  deg    Degrees and pending graduates
  as     Academic Studies (program/major enrollment)
  cl     Class Lists (student-level enrollment)

EOF
    exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────
START_TERM=""
END_TERM=""
REPORTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -s)
            START_TERM="$2"
            shift 2
            ;;
        -e)
            END_TERM="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        desr|deg|as|cl)
            REPORTS+=("$1")
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$START_TERM" ]]; then
    log_error "Missing required argument: -s START_TERM"
    usage
fi

# Default END_TERM to START_TERM if not specified
if [[ -z "$END_TERM" ]]; then
    END_TERM="$START_TERM"
    log_warning "No end term specified, using START_TERM as END_TERM: $END_TERM"
fi

# Default to all reports if none specified
if [[ ${#REPORTS[@]} -eq 0 ]]; then
    REPORTS=(desr deg as cl)
    log_warning "No reports specified, using all: ${REPORTS[*]}"
fi

# ── Environment detection ────────────────────────────────────────────────────
ENV=$(detect_environment)
log_step "Environment: $ENV"

# ── Configuration ────────────────────────────────────────────────────────────
if [[ "$ENV" == "docker" ]]; then
    MRGATHER_DIR="/root/mrgather"
    CEDAR_DIR="/srv/shiny-server/cedar"
    DOCKER_COMPOSE_FILE="/root/shiny/docker-compose.yml"
    CONTAINER_NAME="cedar-shiny"
else
    # Local paths (adjust these to match your setup)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CEDAR_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

    # Try to find mrgather relative to cedar
    if [[ -d "$CEDAR_DIR/../mrgather" ]]; then
        MRGATHER_DIR="$(cd "$CEDAR_DIR/../mrgather" && pwd)"
    else
        log_error "Cannot find mrgather directory. Expected at: $CEDAR_DIR/../mrgather"
        log_error "Please set MRGATHER_DIR environment variable or adjust script."
        exit 1
    fi
fi

log_step "CEDAR directory: $CEDAR_DIR"
log_step "mrgather directory: $MRGATHER_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────
echo
echo "────────────────────────────────────────────────────"
echo " CEDAR Data Update Pipeline"
echo "────────────────────────────────────────────────────"
echo "  Environment: $ENV"
echo "  Start term:  $START_TERM"
echo "  End term:    $END_TERM"
echo "  Reports:     ${REPORTS[*]}"
echo "────────────────────────────────────────────────────"
echo

# ── Step 1: Fetch data with mrgather ─────────────────────────────────────────
log_step "Step 1: Fetching data from MyReports (mrgather)"
echo

cd "$MRGATHER_DIR"

# ── Check if today's files already exist ────────────────────────────────────
# MyReports data is only updated once per day, so if we already have today's
# files, we can skip the slow mrgather step.
#
# mrgather saves one file per report type (covering all terms), named like:
#   S_Department_Enrollment_Status_YYYYMMDD_HHMMSS.xlsx
# These land in SHARED_DATA_PATH (from mrgather's .env), not in mrgather/data/.
TODAY=$(date +%Y%m%d)

# Resolve the shared data directory where mrgather drops files
if [[ "$ENV" == "docker" ]]; then
    MRGATHER_DATA_DIR="/root/shared-data"
else
    # Read SHARED_DATA_PATH from mrgather .env (handles both KEY=value and KEY: value)
    MRGATHER_DATA_DIR=$(grep "SHARED_DATA_PATH" "$MRGATHER_DIR/.env" 2>/dev/null \
        | sed 's/.*SHARED_DATA_PATH[: =]*//' | tr -d '"' | xargs)
    if [[ -z "$MRGATHER_DATA_DIR" ]]; then
        log_warning "Could not read SHARED_DATA_PATH from $MRGATHER_DIR/.env — falling back to $MRGATHER_DIR/downloads"
        MRGATHER_DATA_DIR="$MRGATHER_DIR/downloads"
    fi
fi

log_step "Looking for today's data files in: $MRGATHER_DATA_DIR"
SKIP_FETCH=true

# Check if all requested report files exist for today
log_step "Checking for existing MyReports data from today ($TODAY)..."

for report in "${REPORTS[@]}"; do
    case "$(echo "$report" | tr '[:upper:]' '[:lower:]')" in
        desr) file_glob="*Department_Enrollment_Status*${TODAY}*.xlsx" ;;
        deg)  file_glob="*Degrees*${TODAY}*.xlsx" ;;
        as)   file_glob="*Academic_Studies*${TODAY}*.xlsx" ;;
        cl)   file_glob="*Class_List*${TODAY}*.xlsx" ;;
        *)
            log_warning "Unknown report type: $report"
            continue
            ;;
    esac

    if find "$MRGATHER_DATA_DIR" -maxdepth 1 -name "$file_glob" 2>/dev/null | grep -q .; then
        log_success "Found today's file for $report"
    else
        log_warning "Missing today's file for $report (pattern: $file_glob)"
        SKIP_FETCH=false
    fi
done

# Skip mrgather if all files exist
if [[ "$SKIP_FETCH" == true ]]; then
    log_success "All requested MyReports files already exist from today - skipping fetch"
    echo
else
    log_step "Some files missing or outdated - fetching from MyReports..."
    echo

    # Check if docker-compose.yml exists in mrgather directory
    if [[ -f "docker-compose.yml" ]]; then
        # Always use Docker for mrgather if docker-compose.yml exists
        log_step "Running mrgather via Docker (docker-compose.yml found)..."

        if [[ "$ENV" == "docker" ]]; then
            # Production: use absolute path
            docker compose -f /root/mrgather/docker-compose.yml run --rm mrgather \
                node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
        else
            # Local: use current directory
            docker compose run --rm mrgather \
                node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
        fi
    else
        # No docker-compose.yml: fall back to node directly
        log_warning "No docker-compose.yml found in mrgather directory"
        log_step "Running mrgather with node directly..."

        if ! command -v node &> /dev/null; then
            log_error "node not found. Please install Node.js or add docker-compose.yml to mrgather"
            exit 1
        fi
        node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
    fi

    log_success "Data fetch complete"
    echo
fi

# ── Step 2: Parse raw data ───────────────────────────────────────────────────
log_step "Step 2: Parsing raw MyReports data (parse-data.R)"
echo

cd "$CEDAR_DIR"

# Convert reports array to comma-separated string for R
REPORTS_CSV=$(IFS=,; echo "${REPORTS[*]}")

if [[ "$ENV" == "docker" ]]; then
    # Production: run inside cedar-shiny container (must be running)
    log_step "Ensuring cedar-shiny container is running..."
    /usr/bin/docker compose -f "$DOCKER_COMPOSE_FILE" up -d "$CONTAINER_NAME"
    sleep 2  # Give container time to start

    log_step "Running parse-data.R inside container..."
    /usr/bin/docker exec "$CONTAINER_NAME" \
        Rscript /srv/shiny-server/cedar/R/data-parsers/parse-data.R -r "$REPORTS_CSV"
else
    # Local: try Docker first (for environment consistency), fall back to Rscript
    if [[ -f "$CEDAR_DIR/docker-compose.dev.yml" ]] && command -v docker &> /dev/null; then
        log_step "Running parse-data.R via Docker (docker-compose.dev.yml found)..."

        # Build image if it doesn't exist
        if ! docker images | grep -q "cedar-shiny.*dev"; then
            log_step "Building cedar-dev image (first time only)..."
            docker compose -f "$CEDAR_DIR/docker-compose.dev.yml" build
        fi

        # Run parse-data.R in container
        docker compose -f "$CEDAR_DIR/docker-compose.dev.yml" run --rm cedar-dev \
            Rscript R/data-parsers/parse-data.R -r "$REPORTS_CSV"
    else
        # No Docker setup: fall back to local Rscript
        log_warning "docker-compose.dev.yml not found or Docker not available"
        log_step "Running parse-data.R with local Rscript..."

        if ! command -v Rscript &> /dev/null; then
            log_error "Rscript not found. Please install R or set up Docker (see docker-compose.dev.yml)"
            exit 1
        fi

        Rscript "$CEDAR_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV"
    fi
fi

log_success "Data parsing complete"
echo

# ── Step 3: Transform to CEDAR model ─────────────────────────────────────────
log_step "Step 3: Transforming to CEDAR model (transform-to-cedar.R)"
echo

if [[ "$ENV" == "docker" ]]; then
    # Production: run inside cedar-shiny container
    log_step "Running transform-to-cedar.R inside container..."
    /usr/bin/docker exec "$CONTAINER_NAME" \
        Rscript /srv/shiny-server/cedar/R/data-parsers/transform-to-cedar.R
else
    # Local: try Docker first, fall back to Rscript
    if [[ -f "$CEDAR_DIR/docker-compose.dev.yml" ]] && command -v docker &> /dev/null; then
        log_step "Running transform-to-cedar.R via Docker..."
        docker compose -f "$CEDAR_DIR/docker-compose.dev.yml" run --rm cedar-dev \
            Rscript R/data-parsers/transform-to-cedar.R
    else
        log_step "Running transform-to-cedar.R with local Rscript..."
        Rscript "$CEDAR_DIR/R/data-parsers/transform-to-cedar.R"
    fi
fi

log_success "CEDAR model transformation complete"
echo

# ── Step 4: Reload app (Docker only) ─────────────────────────────────────────
if [[ "$ENV" == "docker" ]]; then
    log_step "Step 4: Reloading CEDAR Shiny app"
    # Touch restart.txt to trigger Shiny Server app reload without restarting
    # the container. Shiny Server detects this file and restarts only the app.
    /usr/bin/docker exec "$CONTAINER_NAME" \
        touch /srv/shiny-server/cedar/restart.txt
    log_success "App reload triggered (restart.txt touched)"

    # Wait a moment for app to reload
    log_step "Waiting for app to reload..."
    sleep 5

    # Warm up the app
    log_step "Warming up app (curl http://localhost:3838/cedar/)"
    if /usr/bin/curl -s http://localhost:3838/cedar/ > /dev/null 2>&1; then
        log_success "App is responsive"
    else
        log_warning "App did not respond to warmup curl (may still be starting)"
    fi
else
    log_step "Step 4: Reload app (skipped - local environment)"
    log_warning "If you're running CEDAR locally, restart your R session or shiny app"
fi

echo
echo "────────────────────────────────────────────────────"
log_success "CEDAR data update complete!"
echo "────────────────────────────────────────────────────"
echo "  Updated terms: $START_TERM - $END_TERM"
echo "  Updated reports: ${REPORTS[*]}"
echo "────────────────────────────────────────────────────"
echo

# ── Tail logs ────────────────────────────────────────────────────────────────
if [[ "$ENV" == "docker" ]]; then
    log_step "Container logs (Ctrl+C to exit):"
    /usr/bin/docker logs --tail 30 -f "$CONTAINER_NAME"
fi
