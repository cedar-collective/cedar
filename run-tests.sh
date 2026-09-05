#!/usr/bin/env bash
# The standard CEDAR test procedure. Run this; do not assemble it by hand.
#
#   ./run-tests.sh              # static checks + R suite  (fast, no browser)
#   ./run-tests.sh --e2e        # ...plus the browser suites against the running app
#   ./run-tests.sh --all        # ...rebuilding the container first
#   ./run-tests.sh --e2e smoke  # one named e2e suite
#   ./run-tests.sh --test-image cedar:ci --e2e demo  # R in Docker; browser on host
#
# ORDER IS THE POINT. The stages run cheapest-first, and a failure stops the run:
#
#   1. check-ids   seconds, no app     catches stale selectors, which otherwise
#                                      surface 30 minutes later as a browser
#                                      timeout that reads like a broken feature
#   2. R suite     ~2 min, no app      catches logic regressions
#   3. e2e         ~10 min, needs app  catches "the numbers never reach the page"
#
# Skipping to stage 3 to "just check the app" is the expensive mistake: every
# stale-id and logic failure then presents as an ambiguous timeout.
set -uo pipefail
cd "$(dirname "$0")"

# Force a working UTF-8 locale before any R runs.
#
# This is not cosmetic. --vanilla skips .Rprofile, and .Rprofile is what
# guarantees UTF-8 for interactive and plain-Rscript sessions. Without it R
# starts in the C locale and mangles multibyte bytes — CEDAR source and config
# use real Unicode glyphs (em dash, >=, arrows) rather than \uXXXX escapes.
# Locale aliases differ by OS, and an invalid inherited LC_ALL can still contain
# the text "UTF-8" while R silently falls back to C. Probe each candidate and
# accept it only when `locale charmap` confirms UTF-8.
_cedar_utf8_locale=""
for loc in "${LC_ALL:-}" C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  [ -n "$loc" ] || continue
  _charmap="$(LC_ALL="$loc" locale charmap 2>/dev/null || true)"
  case "$_charmap" in
    UTF-8|UTF8) _cedar_utf8_locale="$loc"; break ;;
  esac
done
: "${_cedar_utf8_locale:?no working UTF-8 locale available; install one or set LC_ALL manually}"
export LC_ALL="$_cedar_utf8_locale"
unset _cedar_utf8_locale _charmap
echo "locale: LC_ALL=$LC_ALL"

E2E=0; REBUILD=0; ONLY=""; TEST_IMAGE=""
while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --e2e)  E2E=1 ;;
    --all)  E2E=1; REBUILD=1 ;;
    --test-image)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
        echo "--test-image requires a prebuilt Docker image name" >&2; exit 2
      fi
      TEST_IMAGE="$2"; shift ;;
    --help|-h) sed -n '2,21p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $arg"; exit 2 ;;
    *)
      if [ -n "$ONLY" ]; then echo "only one e2e suite may be selected" >&2; exit 2; fi
      ONLY="$arg" ;;
  esac
  shift
done

pass=0; fail=0; failed_stages=()
finish() {
  echo
  echo "═════════════════════════════════════════════════════════════"
  if [ "$fail" -eq 0 ]; then
    echo "  ALL $pass STAGES PASSED"
  else
    echo "  $pass passed, $fail FAILED:"
    for s in "${failed_stages[@]}"; do echo "      - $s"; done
  fi
  echo "═════════════════════════════════════════════════════════════"
  if [ "$fail" -eq 0 ]; then exit 0; else exit 1; fi
}

stage() {
  local name="$1"; shift
  echo
  echo "─────────────────────────────────────────────────────────────"
  echo "  $name"
  echo "─────────────────────────────────────────────────────────────"
  if "$@"; then
    echo "PASS  $name"; pass=$((pass+1))
  else
    echo "FAIL  $name"; fail=$((fail+1)); failed_stages+=("$name")
    return 1
  fi
}

run_stage() {
  stage "$@" || finish
}

wait_for_app_response() {
  local url="${1:-http://localhost:3838/}"
  local timeout="${2:-240}"
  local start
  start="$(date +%s)"
  while true; do
    if curl --max-time 10 -sfI -o /dev/null "$url"; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      return 1
    fi
    sleep 2
  done
}

# ── 1. Static ────────────────────────────────────────────────────────────────
run_stage "e2e selector check" node tests/e2e/check-ids.mjs

# ── 2. R unit suite ──────────────────────────────────────────────────────────
# --vanilla is REQUIRED, not decoration: it skips .Rprofile, which otherwise
# activates renv. The system library has everything the suite needs. Plain
# `Rscript -e` works today but depends on renv's macOS cache, which gets purged.
# Never "fix" that with renv::deactivate() — it rewrites .Rprofile as a side
# effect. See AGENTS.md → Running tests.
R_TEST_CODE='
  suppressMessages(library(testthat))
  testthat::set_max_fails(Inf)
  res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE)
  df  <- as.data.frame(res)
  n_fail <- sum(df$failed) + sum(df$error)
  cat(sprintf("\n%d passed, %d failed, %d skipped\n",
              sum(df$passed), n_fail, sum(df$skipped)))
  quit(status = if (n_fail > 0) 1 else 0)
'
if [ -n "$TEST_IMAGE" ]; then
  # Use the exact built source/dependencies without mounting host data or config.
  # Chrome and Node remain on the host; the R test body is identical in both paths.
  run_stage "R test suite (Docker: $TEST_IMAGE)" docker run --rm \
    --platform linux/amd64 --user root --entrypoint Rscript "$TEST_IMAGE" \
    --vanilla -e "$R_TEST_CODE"
else
  run_stage "R test suite" Rscript --vanilla -e "$R_TEST_CODE"
fi

# ── 3. Browser suites ────────────────────────────────────────────────────────
if [ "$E2E" -eq 1 ]; then
  if [ "$REBUILD" -eq 1 ]; then
    run_stage "rebuild container" ./rebuild-and-test.sh
  fi

  APP_URL="${CEDAR_URL:-http://localhost:3838/}"
  run_stage "app responds at ${APP_URL}" wait_for_app_response "$APP_URL" 240

  # Absorb the cold start here, where a slow stage is expected. Otherwise
  # whichever suite runs first pays for global.R inside its own step budget and
  # fails as an ambiguous "timed out waiting for <output>".
  run_stage "warm up app" node tests/e2e/warmup.mjs

  # Validate the harness before relying on it, then run the broad smoke suite
  # before the focused regressions.
  suites=(harness admin reports-smoke nav enrollment-projections course-dynamics-deeplink waitlist-deeplink waitlist-reconciliation gen-ed-grads credit-timeline course-timing-truncation course-impact-covariates demo)
  [ "$ONLY" = "smoke" ] && ONLY="reports-smoke"
  matched=0
  # Suites run back-to-back against ONE Shiny worker, which holds each session
  # for a grace period after the browser disconnects. Without a gap the next
  # suite starts while the previous session is still being reaped, and a suite
  # that passes alone fails in the sequence. The gap plus a single labelled
  # retry keeps that from being reported as a product failure — a suite that
  # fails twice is a real failure and is reported as one.
  for s in "${suites[@]}"; do
    # Demo has fixed synthetic expectations and must be explicitly requested.
    [ "$s" = "demo" ] && [ "$ONLY" != "demo" ] && continue
    [ -n "$ONLY" ] && [ "$s" != "$ONLY" ] && continue
    matched=$((matched+1))
    [ -f "tests/e2e/$s.test.mjs" ] || { echo "no such suite: $s"; fail=$((fail+1)); failed_stages+=("e2e: $s missing"); finish; }
    sleep 6
    if node "tests/e2e/$s.test.mjs"; then
      echo "PASS  e2e: $s"; pass=$((pass+1))
    else
      echo "e2e: $s failed — retrying once after a longer settle"
      sleep 20
      run_stage "e2e: $s (retry)" node "tests/e2e/$s.test.mjs"
    fi
  done
  if [ -n "$ONLY" ] && [ "$matched" -eq 0 ]; then
    echo "no such e2e suite: $ONLY"
    fail=$((fail+1)); failed_stages+=("e2e: $ONLY missing")
    finish
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
finish
