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

run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -ne "${YELLOW}[dry-run]${NC} "
        printf '%q ' "$@"
        echo
        return 0
    fi

    "$@"
}

enter_dir() {
    local target_dir="$1"

    if [[ -d "$target_dir" ]]; then
        cd "$target_dir"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "Directory not found (dry-run continuing): $target_dir"
        return 0
    fi

    log_error "Directory not found: $target_dir"
    exit 1
}

# ── Detect runtime mode ──────────────────────────────────────────────────────
# Modes:
#   production = run mrgather + R scripts via Docker
#   local      = run mrgather (node) + R scripts directly
detect_mode() {
    # Auto-detect production host by expected production paths
    if [[ -f "$PROD_DOCKER_COMPOSE_FILE" ]] && [[ -d "$PROD_MRGATHER_DIR" ]]; then
        echo "production"
    else
        echo "local"
    fi
}

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") -s START_TERM [-e END_TERM] [--mode MODE] [--dry-run] [REPORTS...]

Update CEDAR data by fetching, parsing, and transforming MyReports data.

Required:
  -s START_TERM    Starting term code (e.g., 202610 for Spring 2026)

Optional:
  -e END_TERM      Ending term code (defaults to START_TERM)
    --mode MODE      Runtime mode: production | local
                                     production = use Docker for mrgather + R scripts
                                     local      = use node + Rscript directly
                                     default: auto-detect from host paths
    --dry-run        Show detection logic and commands without executing them
    Env overrides:
        UPDATE_DATA_MODE         production|local
        PROD_CEDAR_REPO          (default: /root/cedar)
        PROD_DOCKER_COMPOSE_FILE (default: /root/cedar/docker-compose.yml)
        PROD_MRGATHER_DIR        (default: /root/mrgather)
        PROD_MRGATHER_COMPOSE_FILE (default: /root/mrgather/docker-compose.yml)
        PROD_SHARED_DATA_DIR     (default: /root/shared-data)
        PROD_CONTAINER_NAME      (default: cedar-shiny)
        PROD_APP_URL             (default: http://localhost:3838/cedar/)
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
MODE_OVERRIDE="${UPDATE_DATA_MODE:-}"
DRY_RUN=false

# Production path defaults (override via env on droplet)
PROD_CEDAR_REPO="${PROD_CEDAR_REPO:-/root/cedar}"
PROD_DOCKER_COMPOSE_FILE="${PROD_DOCKER_COMPOSE_FILE:-$PROD_CEDAR_REPO/docker-compose.yml}"
PROD_MRGATHER_DIR="${PROD_MRGATHER_DIR:-/root/mrgather}"
PROD_MRGATHER_COMPOSE_FILE="${PROD_MRGATHER_COMPOSE_FILE:-$PROD_MRGATHER_DIR/docker-compose.yml}"
PROD_SHARED_DATA_DIR="${PROD_SHARED_DATA_DIR:-/root/shared-data}"
PROD_CONTAINER_NAME="${PROD_CONTAINER_NAME:-cedar-shiny}"
PROD_APP_URL="${PROD_APP_URL:-http://localhost:3838/cedar/}"

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
        --mode)
            MODE_OVERRIDE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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

# ── Mode detection ───────────────────────────────────────────────────────────
MODE_SOURCE="auto"
PROD_COMPOSE_EXISTS=false
PROD_MRGATHER_EXISTS=false

if [[ -f "$PROD_DOCKER_COMPOSE_FILE" ]]; then
    PROD_COMPOSE_EXISTS=true
fi

if [[ -d "$PROD_MRGATHER_DIR" ]]; then
    PROD_MRGATHER_EXISTS=true
fi

if [[ -n "$MODE_OVERRIDE" ]]; then
    case "$MODE_OVERRIDE" in
        production|local) MODE="$MODE_OVERRIDE" ;;
        *)
            log_error "Invalid --mode value: $MODE_OVERRIDE (expected: production|local)"
            exit 1
            ;;
    esac
    MODE_SOURCE="override"
else
    MODE=$(detect_mode)
fi

log_step "Mode: $MODE"
log_step "Mode source: $MODE_SOURCE"
if [[ "$MODE_SOURCE" == "auto" ]]; then
    log_step "Auto-detect checks: $PROD_DOCKER_COMPOSE_FILE=$PROD_COMPOSE_EXISTS, $PROD_MRGATHER_DIR=$PROD_MRGATHER_EXISTS"
else
    log_step "Override value: $MODE_OVERRIDE"
fi
if [[ "$DRY_RUN" == true ]]; then
    log_warning "Dry-run enabled: commands will be printed, not executed"
fi

# ── Configuration ────────────────────────────────────────────────────────────
if [[ "$MODE" == "production" ]]; then
    MRGATHER_DIR="$PROD_MRGATHER_DIR"
    CEDAR_HOST_DIR="$PROD_CEDAR_REPO"
    CEDAR_CONTAINER_DIR="/srv/shiny-server/cedar"
    DOCKER_COMPOSE_FILE="$PROD_DOCKER_COMPOSE_FILE"
    CONTAINER_NAME="$PROD_CONTAINER_NAME"

    if ! command -v docker &> /dev/null; then
        log_error "docker is required in production mode but was not found"
        exit 1
    fi
else
    # Local paths (adjust these to match your setup)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CEDAR_HOST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

    # Try to find mrgather relative to cedar
    if [[ -d "$CEDAR_HOST_DIR/../mrgather" ]]; then
        MRGATHER_DIR="$(cd "$CEDAR_HOST_DIR/../mrgather" && pwd)"
    else
        log_error "Cannot find mrgather directory. Expected at: $CEDAR_HOST_DIR/../mrgather"
        log_error "Please set MRGATHER_DIR environment variable or adjust script."
        exit 1
    fi
fi

log_step "CEDAR host directory: $CEDAR_HOST_DIR"
if [[ "$MODE" == "production" ]]; then
    log_step "CEDAR container directory: $CEDAR_CONTAINER_DIR"
fi
log_step "mrgather directory: $MRGATHER_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────
echo
echo "────────────────────────────────────────────────────"
echo " CEDAR Data Update Pipeline"
echo "────────────────────────────────────────────────────"
echo "  Mode:        $MODE"
echo "  Mode source: $MODE_SOURCE"
echo "  Dry run:     $DRY_RUN"
echo "  Start term:  $START_TERM"
echo "  End term:    $END_TERM"
echo "  Reports:     ${REPORTS[*]}"
echo "────────────────────────────────────────────────────"
echo

# ── Step 1: Fetch data with mrgather ─────────────────────────────────────────
log_step "Step 1: Fetching data from MyReports (mrgather)"
echo

enter_dir "$MRGATHER_DIR"

# ── Check if today's files already exist ────────────────────────────────────
# MyReports data is only updated once per day, so if we already have today's
# files, we can skip the slow mrgather step.
#
# mrgather saves one file per report type (covering all terms), named like:
#   S_Department_Enrollment_Status_YYYYMMDD_HHMMSS.xlsx
# These land in SHARED_DATA_PATH (from mrgather's .env), not in mrgather/data/.
TODAY=$(date +%Y%m%d)

# Resolve the shared data directory where mrgather drops files
if [[ "$MODE" == "production" ]]; then
    MRGATHER_DATA_DIR="$PROD_SHARED_DATA_DIR"
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

    if [[ "$MODE" == "production" ]]; then
        log_step "Running mrgather via Docker (production mode)..."
        run_cmd docker compose -f "$PROD_MRGATHER_COMPOSE_FILE" run --rm mrgather \
            node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
    else
        log_step "Running mrgather with node directly (local mode)..."

        if ! command -v node &> /dev/null; then
            log_error "node not found. Please install Node.js"
            exit 1
        fi

        run_cmd node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
    fi

    log_success "Data fetch complete"
    echo
fi

# ── Step 2: Parse raw data ───────────────────────────────────────────────────
log_step "Step 2: Parsing raw MyReports data (parse-data.R)"
echo

if [[ "$MODE" == "local" ]]; then
    enter_dir "$CEDAR_HOST_DIR"
fi

# Convert reports array to comma-separated string for R
REPORTS_CSV=$(IFS=,; echo "${REPORTS[*]}")

if [[ "$MODE" == "production" ]]; then
    # Production: run inside cedar-shiny container (must be running)
    log_step "Ensuring cedar-shiny container is running..."
    run_cmd /usr/bin/docker compose -f "$DOCKER_COMPOSE_FILE" up -d "$CONTAINER_NAME"
    run_cmd sleep 2  # Give container time to start

    log_step "Running parse-data.R inside container..."
    run_cmd /usr/bin/docker exec "$CONTAINER_NAME" \
        Rscript "$CEDAR_CONTAINER_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV"
else
    # Local: run with local Rscript
    log_step "Running parse-data.R with local Rscript..."

    if ! command -v Rscript &> /dev/null; then
        log_error "Rscript not found. Please install R"
        exit 1
    fi

    run_cmd Rscript "$CEDAR_HOST_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV"
fi

log_success "Data parsing complete"
echo

# ── Step 3: Transform to CEDAR model ─────────────────────────────────────────
log_step "Step 3: Transforming to CEDAR model (transform-to-cedar.R)"
echo

if [[ "$MODE" == "production" ]]; then
    # Production: run inside cedar-shiny container
    log_step "Running transform-to-cedar.R inside container..."
    run_cmd /usr/bin/docker exec "$CONTAINER_NAME" \
        Rscript "$CEDAR_CONTAINER_DIR/R/data-parsers/transform-to-cedar.R"
else
    # Local: run with local Rscript
    log_step "Running transform-to-cedar.R with local Rscript..."

    if ! command -v Rscript &> /dev/null; then
        log_error "Rscript not found. Please install R"
        exit 1
    fi

    run_cmd Rscript "$CEDAR_HOST_DIR/R/data-parsers/transform-to-cedar.R"
fi

log_success "CEDAR model transformation complete"
echo

# ── Step 4: Reload app (Docker only) ─────────────────────────────────────────
if [[ "$MODE" == "production" ]]; then
    log_step "Step 4: Reloading CEDAR Shiny app"
    # Touch restart.txt to trigger Shiny Server app reload without restarting
    # the container. Shiny Server detects this file and restarts only the app.
    run_cmd /usr/bin/docker exec "$CONTAINER_NAME" \
        touch "$CEDAR_CONTAINER_DIR/restart.txt"
    log_success "App reload triggered (restart.txt touched)"

    # Wait a moment for app to reload
    log_step "Waiting for app to reload..."
    run_cmd sleep 5

    # Warm up the app
    log_step "Warming up app (curl $PROD_APP_URL)"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[dry-run]${NC} /usr/bin/curl -s $PROD_APP_URL > /dev/null"
        log_success "App responsiveness check skipped in dry-run"
    else
        if /usr/bin/curl -s "$PROD_APP_URL" > /dev/null 2>&1; then
            log_success "App is responsive"
        else
            log_warning "App did not respond to warmup curl (may still be starting)"
        fi
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
if [[ "$MODE" == "production" ]]; then
    log_step "Container logs (Ctrl+C to exit):"
    run_cmd /usr/bin/docker logs --tail 30 -f "$CONTAINER_NAME"
fi
