#!/usr/bin/env bash
#
# restart-cedar.sh — Reload the CEDAR Shiny app, optionally updating data first
#
# Default: just restart the app (touch restart.txt or docker compose restart).
# Pass --update to run update-data.sh before restarting.
#
# Usage:
#   restart-cedar.sh [--update -s START_TERM [-e END_TERM] [REPORTS...]]
#                    [--mode MODE] [--hard-restart] [--dry-run] [--log-tail N]
#
# Examples:
#   restart-cedar.sh                       # Restart only (default)
#   restart-cedar.sh --update -s 202610 desr cl   # Fetch desr+cl then restart
#   restart-cedar.sh --update -s 202610 -e 202680 # All reports, two terms, restart

PIPELINE_SUCCESS=true
PIPELINE_START=$SECONDS

# ── Step tracking ──────────────────────────────────────────────────────────────
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

# ── Colors (match update-data.sh) ─────────────────────────────────────────────
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

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") [--update -s START_TERM [-e END_TERM] [REPORTS...]]
                        [--mode MODE] [--hard-restart] [--dry-run] [--log-tail N]

Reload the CEDAR Shiny app. Pass --update to fetch fresh data first.

Data update options (require --update):
  -s START_TERM    Starting term code (e.g. 202610 for Spring 2026)
  -e END_TERM      Ending term code (defaults to START_TERM)
  REPORTS          Reports to fetch: desr deg as cl (default: all)

Restart options:
  --update         Run update-data.sh before restarting
  --hard-restart   Full docker compose restart instead of touch restart.txt

Shared options:
  --mode MODE      production | local (default: auto-detect)
  --dry-run        Print commands without executing
  --log-tail N     Show last N container log lines after restart (0=skip, default: 30)
  -h               Show this help

Env overrides (same as update-data.sh):
  PROD_CEDAR_REPO, PROD_DOCKER_COMPOSE_FILE, PROD_CONTAINER_NAME, PROD_APP_URL
  LOCAL_CONTAINER_NAME (default: cedar-shiny)
  LOCAL_APP_URL        (default: http://localhost:3838/cedar/)

Examples:
  $(basename "$0")                                      # Restart only (default)
  $(basename "$0") --update -s 202610 desr cl           # Fetch desr+cl then restart
  $(basename "$0") --update -s 202610 -e 202680         # All reports, two terms, restart
  $(basename "$0") --hard-restart                       # Full container restart
  $(basename "$0") --update -s 202610 --hard-restart    # Fetch all, full restart
EOF
    exit 0
}

# ── Defaults ───────────────────────────────────────────────────────────────────
RUN_UPDATE=false
HARD_RESTART=false
DRY_RUN=false
LOG_TAIL=30
MODE_OVERRIDE="${UPDATE_DATA_MODE:-}"
START_TERM=""
END_TERM=""
REPORTS=()

# Production path defaults (match update-data.sh)
PROD_CEDAR_REPO="${PROD_CEDAR_REPO:-/root/cedar}"
PROD_DOCKER_COMPOSE_FILE="${PROD_DOCKER_COMPOSE_FILE:-$PROD_CEDAR_REPO/docker-compose.yml}"
PROD_MRGATHER_DIR="${PROD_MRGATHER_DIR:-/root/mrgather}"
PROD_CONTAINER_NAME="${PROD_CONTAINER_NAME:-cedar-shiny}"
PROD_APP_URL="${PROD_APP_URL:-http://localhost:3838/cedar/}"
CEDAR_CONTAINER_DIR="${CEDAR_CONTAINER_DIR:-/srv/shiny-server/cedar}"

# ── Parse args ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --update)       RUN_UPDATE=true; shift ;;
        --hard-restart) HARD_RESTART=true; shift ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --mode)         MODE_OVERRIDE="$2"; shift 2 ;;
        --log-tail)     LOG_TAIL="$2"; shift 2 ;;
        -s)             START_TERM="$2"; shift 2 ;;
        -e)             END_TERM="$2"; shift 2 ;;
        -h|--help)      usage ;;
        desr|deg|as|cl) REPORTS+=("$1"); shift ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ "$RUN_UPDATE" == true && -z "$START_TERM" ]]; then
    log_error "Provide -s START_TERM when using --update"
    usage
fi

# ── Mode detection ─────────────────────────────────────────────────────────────
if [[ -n "$MODE_OVERRIDE" ]]; then
    case "$MODE_OVERRIDE" in
        production|local) MODE="$MODE_OVERRIDE" ;;
        *)
            log_error "Invalid --mode: $MODE_OVERRIDE (expected: production|local)"
            exit 1
            ;;
    esac
elif [[ -f "$PROD_DOCKER_COMPOSE_FILE" && -d "$PROD_MRGATHER_DIR" ]]; then
    MODE="production"
else
    MODE="local"
fi

# ── Resolve paths per mode ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$MODE" == "production" ]]; then
    CEDAR_HOST_DIR="$PROD_CEDAR_REPO"
    DOCKER_COMPOSE_FILE="$PROD_DOCKER_COMPOSE_FILE"
    CONTAINER_NAME="$PROD_CONTAINER_NAME"
    APP_URL="$PROD_APP_URL"
    DOCKER_CMD="/usr/bin/docker"
else
    CEDAR_HOST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    DOCKER_COMPOSE_FILE="$CEDAR_HOST_DIR/docker-compose.yml"
    CONTAINER_NAME="${LOCAL_CONTAINER_NAME:-cedar-shiny}"
    APP_URL="${LOCAL_APP_URL:-http://localhost:3838/cedar/}"
    DOCKER_CMD="docker"
fi

# ── Header ─────────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════"
echo " CEDAR Restart  $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════"
echo "  Mode:        $MODE"
echo "  Container:   $CONTAINER_NAME"
echo "  Update data: $RUN_UPDATE"
if [[ "$RUN_UPDATE" == true ]]; then
    echo "  Terms:       $START_TERM → ${END_TERM:-$START_TERM}"
    echo "  Reports:     ${REPORTS[*]:-all}"
fi
echo "  Restart:     $( [[ "$HARD_RESTART" == true ]] && echo "hard (docker compose restart)" || echo "soft (touch restart.txt)" )"
echo "  Dry run:     $DRY_RUN"
echo "════════════════════════════════════════════════════"
echo

# ── Step 1 (optional): Update data ────────────────────────────────────────────
if [[ "$RUN_UPDATE" == true ]]; then
    log_step "Step 1: Update data (update-data.sh)"
    STEP_START=$SECONDS

    UPDATE_ARGS=(-s "$START_TERM" --mode "$MODE" --log-tail 0)
    [[ -n "$END_TERM" ]]       && UPDATE_ARGS+=(-e "$END_TERM")
    [[ "$DRY_RUN" == true ]]   && UPDATE_ARGS+=(--dry-run)
    [[ ${#REPORTS[@]} -gt 0 ]] && UPDATE_ARGS+=("${REPORTS[@]}")

    if run_cmd "$SCRIPT_DIR/update-data.sh" "${UPDATE_ARGS[@]}"; then
        log_success "Data update complete"
        record_step "update-data.sh" "OK" "$((SECONDS - STEP_START))s"
    else
        log_error "Data update failed — aborting restart to avoid reloading with stale data"
        record_step "update-data.sh" "FAILED" "$((SECONDS - STEP_START))s" "restart aborted"
        PIPELINE_SUCCESS=false
    fi
    echo
fi

# ── Step 2: Restart app ────────────────────────────────────────────────────────
if [[ "$PIPELINE_SUCCESS" == true ]]; then
    STEP_START=$SECONDS

    # Check if container is running — if not, bring it up instead of restarting
    CONTAINER_RUNNING=false
    if [[ "$DRY_RUN" == false ]]; then
        if "$DOCKER_CMD" ps --filter "name=$CONTAINER_NAME" --filter "status=running" \
                --format "{{.Names}}" 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            CONTAINER_RUNNING=true
        fi
    else
        CONTAINER_RUNNING=true   # assume running in dry-run so we show the intended path
    fi

    if [[ "$CONTAINER_RUNNING" == false ]]; then
        log_step "Step 2: Container not running — starting with docker compose up --build"
        if run_cmd "$DOCKER_CMD" compose -f "$DOCKER_COMPOSE_FILE" up --build -d; then
            log_success "Container started"
            record_step "docker compose up --build" "OK" "$((SECONDS - STEP_START))s"
        else
            log_error "docker compose up --build failed"
            record_step "docker compose up --build" "FAILED" "$((SECONDS - STEP_START))s"
        fi
    elif [[ "$HARD_RESTART" == true ]]; then
        log_step "Step 2: Hard restart (docker compose restart $CONTAINER_NAME)"
        if run_cmd "$DOCKER_CMD" compose -f "$DOCKER_COMPOSE_FILE" restart "$CONTAINER_NAME"; then
            log_success "Container restarted"
            record_step "docker compose restart" "OK" "$((SECONDS - STEP_START))s"
        else
            log_error "docker compose restart failed"
            record_step "docker compose restart" "FAILED" "$((SECONDS - STEP_START))s"
        fi
    else
        log_step "Step 2: Soft reload (touch $CEDAR_CONTAINER_DIR/restart.txt)"
        if run_cmd "$DOCKER_CMD" exec "$CONTAINER_NAME" \
                touch "$CEDAR_CONTAINER_DIR/restart.txt"; then
            log_success "restart.txt touched"
            record_step "touch restart.txt" "OK" "$((SECONDS - STEP_START))s"
        else
            log_error "Failed to touch restart.txt in container"
            record_step "touch restart.txt" "FAILED" "$((SECONDS - STEP_START))s"
        fi
    fi
    echo

    # ── Step 3: Wait and warm up ───────────────────────────────────────────────
    # CEDAR loads large datasets on startup — allow up to ~90s before giving up.
    # Curl runs on the HOST (not inside the container) so localhost resolves correctly.
    log_step "Step 3: Waiting for app to reload (CEDAR startup can take 30-60s)..."
    STEP_START=$SECONDS
    sleep 10   # initial pause before first check

    WARMUP_STATUS="OK"
    WARMUP_NOTE=""
    MAX_ATTEMPTS=6
    RETRY_WAIT=15

    if [[ "$DRY_RUN" == false ]]; then
        for attempt in $(seq 1 $MAX_ATTEMPTS); do
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$APP_URL" 2>/dev/null)
            if [[ "$HTTP_CODE" =~ ^[23] ]]; then
                log_success "App responding — HTTP $HTTP_CODE (attempt $attempt, $((SECONDS - STEP_START))s elapsed)"
                WARMUP_NOTE="HTTP $HTTP_CODE on attempt $attempt"
                break
            fi
            if [[ $attempt -lt $MAX_ATTEMPTS ]]; then
                log_warning "Attempt $attempt: HTTP $HTTP_CODE — waiting ${RETRY_WAIT}s..."
                sleep $RETRY_WAIT
            else
                log_warning "App not responding after $MAX_ATTEMPTS attempts ($((SECONDS - STEP_START))s) — HTTP $HTTP_CODE"
                log_warning "Check container logs: $DOCKER_CMD logs $CONTAINER_NAME"
                WARMUP_STATUS="WARN"
                WARMUP_NOTE="HTTP $HTTP_CODE after $MAX_ATTEMPTS attempts"
            fi
        done
    else
        run_cmd curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$APP_URL"
    fi

    record_step "warmup curl" "$WARMUP_STATUS" "$((SECONDS - STEP_START))s" "$WARMUP_NOTE"
    echo
fi

# ── Summary ────────────────────────────────────────────────────────────────────
TOTAL_DURATION=$((SECONDS - PIPELINE_START))
echo "════════════════════════════════════════════════════"
if [[ "$PIPELINE_SUCCESS" == true ]]; then
    echo -e " ${GREEN}${BOLD}CEDAR restart complete${NC}  $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo -e " ${RED}${BOLD}CEDAR restart finished with errors${NC}  $(date '+%Y-%m-%d %H:%M:%S')"
fi
echo "════════════════════════════════════════════════════"
echo "  Container: $CONTAINER_NAME"
echo "  URL:       $APP_URL"
echo "  Duration:  ${TOTAL_DURATION}s"
echo "────────────────────────────────────────────────────"
printf "  %-28s %-8s %-8s %s\n" "Step" "Status" "Time" "Notes"
echo "  ──────────────────────────────────────────────"
for i in "${!STEP_NAMES[@]}"; do
    status="${STEP_STATUSES[$i]}"
    case "$status" in
        OK|SKIPPED) color="$GREEN" ;;
        WARN)       color="$YELLOW" ;;
        FAILED)     color="$RED" ;;
        *)          color="$NC" ;;
    esac
    printf "  %-28s ${color}%-8s${NC} %-8s %s\n" \
        "${STEP_NAMES[$i]}" "$status" "${STEP_DURATIONS[$i]}" "${STEP_NOTES[$i]}"
done
echo "════════════════════════════════════════════════════"
echo

# ── Optional log tail ──────────────────────────────────────────────────────────
if [[ "$LOG_TAIL" -gt 0 && "$DRY_RUN" == false ]]; then
    log_step "Last $LOG_TAIL lines of container logs:"
    "$DOCKER_CMD" logs --tail "$LOG_TAIL" "$CONTAINER_NAME" 2>&1 || true
    echo
fi
