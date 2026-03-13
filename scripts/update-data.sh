#!/usr/bin/env bash
#
# update-data.sh — CEDAR data update pipeline
#
# Runs the complete data update workflow:
#   1. Fetch data from MyReports (via mrgather)
#   2. Parse raw data files (parse-data.R)
#   3. Transform to CEDAR model (transform-to-cedar.R)
#   4. (Docker only) Reload app and warm up
#
# Works in both production (Docker) and local environments.
# All output is tee'd to a timestamped log file.
#
# Usage:
#   update-data.sh -s START_TERM -e END_TERM [reports]
#
# Examples:
#   update-data.sh -s 202610 -e 202680              # All reports, Spring–Fall 2026
#   update-data.sh -s 202610 desr deg               # Only DESR and degrees
#   update-data.sh -s 202580                        # Single term, all reports
#
# Report options: desr deg as cl
#   desr = Department Enrollment Status Report (section data)
#   deg  = Degrees (graduation data)
#   as   = Academic Studies (program/major data)
#   cl   = Class Lists (student enrollment data)

# No set -e: exit codes are tracked explicitly so we always print the final summary

PIPELINE_SUCCESS=true
PIPELINE_START=$SECONDS

# ── Step tracking ─────────────────────────────────────────────────────────────
declare -a STEP_NAMES=()
declare -a STEP_STATUSES=()
declare -a STEP_DURATIONS=()
declare -a STEP_NOTES=()

record_step() {
    STEP_NAMES+=("$1")
    STEP_STATUSES+=("$2")
    STEP_DURATIONS+=("$3")
    STEP_NOTES+=("${4:-}")
    [[ "$2" == "FAILED" ]] && PIPELINE_SUCCESS=false
}

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_step()    { echo -e "${BLUE}==>${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

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

# ── Mode detection ────────────────────────────────────────────────────────────
detect_mode() {
    if [[ -f "$PROD_DOCKER_COMPOSE_FILE" ]] && [[ -d "$PROD_MRGATHER_DIR" ]]; then
        echo "production"
    else
        echo "local"
    fi
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") -s START_TERM [-e END_TERM] [--mode MODE] [--dry-run] [--log-tail N] [REPORTS...]

Update CEDAR data by fetching, parsing, and transforming MyReports data.
All output is logged to a timestamped file in /var/log/ (production) or /tmp/ (local).

Required:
  -s START_TERM    Starting term code (e.g., 202610 for Spring 2026)

Optional:
  -e END_TERM      Ending term code (defaults to START_TERM)
  --mode MODE      Runtime mode: production | local
                   production = use Docker for mrgather + R scripts
                   local      = use node + Rscript directly
                   default: auto-detect from host paths
  --dry-run        Show commands without executing them
  --log-tail N     Show last N container log lines at end (0 = skip, default: 30)

  Env overrides:
    UPDATE_DATA_MODE           production|local
    PROD_CEDAR_REPO            (default: /root/cedar)
    PROD_DOCKER_COMPOSE_FILE   (default: /root/cedar/docker-compose.yml)
    PROD_MRGATHER_DIR          (default: /root/mrgather)
    PROD_MRGATHER_COMPOSE_FILE (default: /root/mrgather/docker-compose.yml)
    PROD_SHARED_DATA_DIR       (default: /root/shared-data)
    PROD_CONTAINER_NAME        (default: cedar-shiny)
    PROD_APP_URL               (default: http://localhost:3838/cedar/)

  -h               Show this help message
  REPORTS          Space-separated list of reports to fetch (default: all)
                   Options: desr deg as cl

Examples:
  $(basename "$0") -s 202610 -e 202680              # All reports, Spring 2026 - Fall 2026
  $(basename "$0") -s 202610 desr deg               # Only DESR and degrees for Spring 2026
  $(basename "$0") -s 202580                        # All reports for Fall 2025

EOF
    exit 0
}

# ── Parse arguments ───────────────────────────────────────────────────────────
START_TERM=""
END_TERM=""
REPORTS=()
MODE_OVERRIDE="${UPDATE_DATA_MODE:-}"
DRY_RUN=false
LOG_TAIL=30

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
        -s) START_TERM="$2"; shift 2 ;;
        -e) END_TERM="$2"; shift 2 ;;
        -h|--help) usage ;;
        --mode) MODE_OVERRIDE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --log-tail) LOG_TAIL="$2"; shift 2 ;;
        desr|deg|as|cl) REPORTS+=("$1"); shift ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$START_TERM" ]]; then
    log_error "Missing required argument: -s START_TERM"
    usage
fi

[[ -z "$END_TERM" ]] && { END_TERM="$START_TERM"; log_warning "No end term specified, using START_TERM: $END_TERM"; }
[[ ${#REPORTS[@]} -eq 0 ]] && { REPORTS=(desr deg as cl); log_warning "No reports specified, using all: ${REPORTS[*]}"; }

# ── Mode detection ────────────────────────────────────────────────────────────
PROD_COMPOSE_EXISTS=false
PROD_MRGATHER_EXISTS=false
[[ -f "$PROD_DOCKER_COMPOSE_FILE" ]] && PROD_COMPOSE_EXISTS=true
[[ -d "$PROD_MRGATHER_DIR" ]] && PROD_MRGATHER_EXISTS=true

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
    MODE_SOURCE="auto ($PROD_DOCKER_COMPOSE_FILE=$PROD_COMPOSE_EXISTS, $PROD_MRGATHER_DIR=$PROD_MRGATHER_EXISTS)"
fi

# ── Logging setup ─────────────────────────────────────────────────────────────
# Set up log file before any real output; tee everything to it
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ "$MODE" == "production" ]]; then
    LOG_FILE="/var/log/cedar-update-${TIMESTAMP}.log"
else
    LOG_FILE="/tmp/cedar-update-${TIMESTAMP}.log"
fi

# Redirect all stdout+stderr through tee to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo
echo "════════════════════════════════════════════════════"
echo " CEDAR Data Update  $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════"
echo "  Mode:     $MODE"
echo "  Detect:   $MODE_SOURCE"
echo "  Dry run:  $DRY_RUN"
echo "  Terms:    $START_TERM → $END_TERM"
echo "  Reports:  ${REPORTS[*]}"
echo "  Log:      $LOG_FILE"
echo "════════════════════════════════════════════════════"
echo

# ── Configuration ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "production" ]]; then
    MRGATHER_DIR="$PROD_MRGATHER_DIR"
    CEDAR_HOST_DIR="$PROD_CEDAR_REPO"
    CEDAR_CONTAINER_DIR="/srv/shiny-server/cedar"
    DOCKER_COMPOSE_FILE="$PROD_DOCKER_COMPOSE_FILE"
    CONTAINER_NAME="$PROD_CONTAINER_NAME"

    if ! command -v docker &> /dev/null; then
        log_error "docker not found (required in production mode)"
        exit 1
    fi
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CEDAR_HOST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

    if [[ -d "$CEDAR_HOST_DIR/../mrgather" ]]; then
        MRGATHER_DIR="$(cd "$CEDAR_HOST_DIR/../mrgather" && pwd)"
    else
        log_error "Cannot find mrgather at: $CEDAR_HOST_DIR/../mrgather"
        exit 1
    fi
fi

REPORTS_CSV=$(IFS=,; echo "${REPORTS[*]}")

# Map requested reports to cedar table names for transform-to-cedar.R
# Only pass --tables when a subset of reports is requested (not all 4)
TABLES_ARGS=()
if [[ ${#REPORTS[@]} -lt 4 ]]; then
  TABLES=()
  for report in "${REPORTS[@]}"; do
    case "$report" in
      desr) TABLES+=("sections") ;;
      cl)   TABLES+=("students") ;;
      as)   TABLES+=("programs") ;;
      deg)  TABLES+=("degrees") ;;
    esac
  done
  TABLES_CSV=$(IFS=,; echo "${TABLES[*]}")
  TABLES_ARGS+=(--tables "$TABLES_CSV")
  log_step "Transform tables: ${TABLES[*]}"
fi

log_step "CEDAR dir:    $CEDAR_HOST_DIR"
log_step "mrgather dir: $MRGATHER_DIR"
[[ "$MODE" == "production" ]] && log_step "Container:    $CONTAINER_NAME"
echo

# ── Step 1: Fetch data (mrgather) ─────────────────────────────────────────────
log_step "Step 1: Fetch data from MyReports (mrgather)"
STEP_START=$SECONDS
FETCH_RC=0
FETCH_STATUS="OK"
FETCH_NOTE=""

enter_dir "$MRGATHER_DIR"

TODAY=$(date +%Y%m%d)

# Resolve where mrgather drops files
if [[ "$MODE" == "production" ]]; then
    MRGATHER_DATA_DIR="$PROD_SHARED_DATA_DIR"
else
    MRGATHER_DATA_DIR=$(grep "SHARED_DATA_PATH" "$MRGATHER_DIR/.env" 2>/dev/null \
        | sed 's/.*SHARED_DATA_PATH[: =]*//' | tr -d '"' | xargs)
    [[ -z "$MRGATHER_DATA_DIR" ]] && {
        log_warning "Could not read SHARED_DATA_PATH from $MRGATHER_DIR/.env — falling back to $MRGATHER_DIR/downloads"
        MRGATHER_DATA_DIR="$MRGATHER_DIR/downloads"
    }
fi

log_step "Data dir: $MRGATHER_DATA_DIR"
log_step "Checking for today's files ($TODAY)..."
SKIP_FETCH=true

for report in "${REPORTS[@]}"; do
    case "$(echo "$report" | tr '[:upper:]' '[:lower:]')" in
        desr) file_glob="*Department_Enrollment_Status*${TODAY}*.xlsx" ;;
        deg)  file_glob="*Degrees*${TODAY}*.xlsx" ;;
        as)   file_glob="*Academic_Studies*${TODAY}*.xlsx" ;;
        cl)   file_glob="*Class_List*${TODAY}*.xlsx" ;;
        *)    log_warning "Unknown report type: $report"; continue ;;
    esac
    if find "$MRGATHER_DATA_DIR" -maxdepth 1 -name "$file_glob" 2>/dev/null | grep -q .; then
        log_success "Found: $report"
    else
        log_warning "Missing: $report ($file_glob)"
        SKIP_FETCH=false
    fi
done

if [[ "$SKIP_FETCH" == true ]]; then
    log_success "All files current — skipping fetch"
    FETCH_STATUS="SKIPPED"
    FETCH_NOTE="files already from today"
else
    log_step "Fetching from MyReports..."
    if [[ "$MODE" == "production" ]]; then
        run_cmd /usr/bin/docker compose -f "$PROD_MRGATHER_COMPOSE_FILE" run --rm mrgather \
            node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
        FETCH_RC=$?
    else
        run_cmd docker compose -f "$MRGATHER_DIR/docker-compose.yml" run --rm mrgather \
            node mrgather.js "${REPORTS[@]}" -s "$START_TERM" -e "$END_TERM"
        FETCH_RC=$?
    fi
    if [[ $FETCH_RC -eq 0 ]]; then
        log_success "Fetch complete"
        FETCH_STATUS="OK"
        FETCH_NOTE="fetched: ${REPORTS[*]}"
    else
        log_error "Fetch failed (exit code: $FETCH_RC)"
        FETCH_STATUS="FAILED"
        FETCH_NOTE="exit code $FETCH_RC"
    fi
fi

record_step "mrgather fetch" "$FETCH_STATUS" "$((SECONDS - STEP_START))s" "$FETCH_NOTE"
echo

# ── Step 2: Parse raw data ────────────────────────────────────────────────────
log_step "Step 2: Parse raw data (parse-data.R)"
STEP_START=$SECONDS
PARSE_RC=0
PARSE_STATUS="OK"
PARSE_NOTE=""
PARSE_OUT=$(mktemp)

[[ "$MODE" == "local" ]] && enter_dir "$CEDAR_HOST_DIR"

if [[ "$MODE" == "production" ]]; then
    log_step "Ensuring container is running..."
    run_cmd /usr/bin/docker compose -f "$DOCKER_COMPOSE_FILE" up -d "$CONTAINER_NAME"
    run_cmd sleep 2

    if [[ "$DRY_RUN" == true ]]; then
        run_cmd /usr/bin/docker exec "$CONTAINER_NAME" \
            Rscript "$CEDAR_CONTAINER_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV"
    else
        /usr/bin/docker exec "$CONTAINER_NAME" \
            Rscript "$CEDAR_CONTAINER_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV" \
            2>&1 | tee "$PARSE_OUT"
        PARSE_RC=${PIPESTATUS[0]}
    fi
else
    if ! command -v Rscript &> /dev/null; then
        log_error "Rscript not found. Please install R."
        PARSE_RC=1
    elif [[ "$DRY_RUN" == true ]]; then
        run_cmd Rscript "$CEDAR_HOST_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV"
    else
        Rscript "$CEDAR_HOST_DIR/R/data-parsers/parse-data.R" -r "$REPORTS_CSV" \
            2>&1 | tee "$PARSE_OUT"
        PARSE_RC=${PIPESTATUS[0]}
    fi
fi

if [[ $PARSE_RC -eq 0 ]]; then
    log_success "Parsing complete"
    PARSE_STATUS="OK"
    # Extract brief summary from R output (last few informative lines)
    PARSE_NOTE=$(grep -E "(Copied|Parsed|Warning|xlsx|csv|rows|files)" "$PARSE_OUT" 2>/dev/null \
        | grep -v "^$" | tail -3 | tr '\n' ' ' || true)
else
    log_error "Parsing failed (exit code: $PARSE_RC)"
    PARSE_STATUS="FAILED"
    PARSE_NOTE="exit $PARSE_RC — see $LOG_FILE"
    echo "  Last output:"
    tail -10 "$PARSE_OUT" 2>/dev/null || true
fi

rm -f "$PARSE_OUT"
record_step "parse-data.R" "$PARSE_STATUS" "$((SECONDS - STEP_START))s" "$PARSE_NOTE"
echo

# ── Step 3: Transform to CEDAR model ─────────────────────────────────────────
log_step "Step 3: Transform to CEDAR model (transform-to-cedar.R)"
STEP_START=$SECONDS
TRANSFORM_RC=0
TRANSFORM_STATUS="OK"
TRANSFORM_NOTE=""
TRANSFORM_OUT=$(mktemp)

if [[ "$MODE" == "production" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        run_cmd /usr/bin/docker exec "$CONTAINER_NAME" \
            Rscript "$CEDAR_CONTAINER_DIR/R/data-parsers/transform-to-cedar.R" \
            "${TABLES_ARGS[@]}"
    else
        /usr/bin/docker exec "$CONTAINER_NAME" \
            Rscript "$CEDAR_CONTAINER_DIR/R/data-parsers/transform-to-cedar.R" \
            "${TABLES_ARGS[@]}" \
            2>&1 | tee "$TRANSFORM_OUT"
        TRANSFORM_RC=${PIPESTATUS[0]}
    fi
else
    if ! command -v Rscript &> /dev/null; then
        log_error "Rscript not found. Please install R."
        TRANSFORM_RC=1
    elif [[ "$DRY_RUN" == true ]]; then
        run_cmd Rscript "$CEDAR_HOST_DIR/R/data-parsers/transform-to-cedar.R" \
            "${TABLES_ARGS[@]}"
    else
        Rscript "$CEDAR_HOST_DIR/R/data-parsers/transform-to-cedar.R" \
            "${TABLES_ARGS[@]}" \
            2>&1 | tee "$TRANSFORM_OUT"
        TRANSFORM_RC=${PIPESTATUS[0]}
    fi
fi

if [[ $TRANSFORM_RC -eq 0 ]]; then
    log_success "Transform complete"
    TRANSFORM_STATUS="OK"
    # Extract brief summary — section count, term count, output file info
    TRANSFORM_NOTE=$(grep -E "(sections|terms|Wrote|cedar_sections|Copying)" "$TRANSFORM_OUT" 2>/dev/null \
        | grep -v "^$" | tail -3 | tr '\n' ' ' || true)
else
    log_error "Transform failed (exit code: $TRANSFORM_RC)"
    TRANSFORM_STATUS="FAILED"
    TRANSFORM_NOTE="exit $TRANSFORM_RC — see $LOG_FILE"
    echo "  Last output:"
    tail -10 "$TRANSFORM_OUT" 2>/dev/null || true
fi

rm -f "$TRANSFORM_OUT"
record_step "transform-to-cedar.R" "$TRANSFORM_STATUS" "$((SECONDS - STEP_START))s" "$TRANSFORM_NOTE"
echo

echo

# ── Final summary ─────────────────────────────────────────────────────────────
TOTAL_DURATION=$((SECONDS - PIPELINE_START))
FINISH_TIME=$(date '+%Y-%m-%d %H:%M:%S')

echo "════════════════════════════════════════════════════"
if [[ "$PIPELINE_SUCCESS" == true ]]; then
    echo -e " ${GREEN}${BOLD}CEDAR Update Complete${NC}  $FINISH_TIME"
else
    echo -e " ${RED}${BOLD}CEDAR Update Finished with Errors${NC}  $FINISH_TIME"
fi
echo "════════════════════════════════════════════════════"
if [[ "$PIPELINE_SUCCESS" == true ]]; then
    echo -e " ✅ CEDAR Update Complete  $FINISH_TIME"
else
    echo -e " ❌ CEDAR Update Finished with Errors  $FINISH_TIME"
fi
echo "════════════════════════════════════════════════════"
echo "  Terms:    $START_TERM → $END_TERM"
echo "  Reports:  ${REPORTS[*]}"
echo "  Duration: ${TOTAL_DURATION}s total"
echo "  Log:      $LOG_FILE"
echo "────────────────────────────────────────────────────"
printf "  %-28s %-8s %-8s %s\n" "Step" "Status" "Time" "Notes"
echo "  ──────────────────────────────────────────────"
for i in "${!STEP_NAMES[@]}"; do
    status="${STEP_STATUSES[$i]}"
    case "$status" in
        OK|SKIPPED) symbol="✅" ;;
        WARN)       symbol="⚠️" ;;
        FAILED)     symbol="❌" ;;
        *)          symbol="" ;;
    esac
    printf "  %-28s %-8s %-8s %s\n" \
        "${STEP_NAMES[$i]}" "$symbol" "${STEP_DURATIONS[$i]}" "${STEP_NOTES[$i]}"
done
echo "════════════════════════════════════════════════════"
echo

# ── Optional container log tail ───────────────────────────────────────────────
# Shows recent Shiny Server output without blocking (no -f flag)
if [[ "$MODE" == "production" && "$LOG_TAIL" -gt 0 ]]; then
    log_step "Last $LOG_TAIL lines of container logs:"
    /usr/bin/docker logs --tail "$LOG_TAIL" "$CONTAINER_NAME" 2>&1 || true
    echo
fi
