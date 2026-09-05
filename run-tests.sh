#!/usr/bin/env bash
# The standard CEDAR test procedure. Run this; do not assemble it by hand.
#
#   ./run-tests.sh              # static checks + R suite  (fast, no browser)
#   ./run-tests.sh --e2e        # ...plus two representative report scenarios
#   ./run-tests.sh --e2e nav    # one browser suite against the running app
#   ./run-tests.sh --e2e reports # full institutional report tour, without rebuild
#   ./run-tests.sh --all        # rebuild, then all institutional browser suites
#   ./run-tests.sh --all smoke  # rebuild, then only the short smoke check
#   ./run-tests.sh --test-image cedar:ci --e2e demo  # R in Docker; browser on host
#   ./run-tests.sh --project-library  # same suite, prepared native dependencies
#
# ORDER IS THE POINT. The stages run cheapest-first, and a failure stops the run:
#
#   1. check-ids   seconds, no app     catches stale selectors, which otherwise
#                                      surface 30 minutes later as a browser
#                                      timeout that reads like a broken feature
#   2. R suite     no app             catches logic regressions
#   3. e2e         needs current app  checks the selected browser behavior
#
# Run static and R checks before browser verification. After diagnosis, focused
# reruns can use the committed browser script if application/R code is unchanged.
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

E2E=0; REBUILD=0; ONLY=""; TEST_IMAGE=""; PROJECT_LIBRARY=0
while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --e2e)  E2E=1 ;;
    --all)  E2E=1; REBUILD=1 ;;
    --project-library) PROJECT_LIBRARY=1 ;;
    --test-image)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
        echo "--test-image requires a prebuilt Docker image name" >&2; exit 2
      fi
      TEST_IMAGE="$2"; shift ;;
    --help|-h) sed -n '2,24p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $arg"; exit 2 ;;
    *)
      if [ -n "$ONLY" ]; then echo "only one e2e suite may be selected" >&2; exit 2; fi
      ONLY="$arg" ;;
  esac
  shift
done
if [ "$PROJECT_LIBRARY" -eq 1 ] && [ -n "$TEST_IMAGE" ]; then
  echo "--project-library is native-only; do not combine with --test-image" >&2; exit 2
fi
export CEDAR_TEST_PROJECT_LIBRARY="$PROJECT_LIBRARY"

# Validate selection before spending time on R or starting an app.
suites=(harness admin reports-smoke nav enrollment-projections course-dynamics-deeplink waitlist-deeplink waitlist-reconciliation gen-ed-grads credit-timeline course-impact-covariates demo)
REPORT_SCOPE=smoke
if [ "$E2E" -eq 0 ] && [ -n "$ONLY" ]; then
  echo "a suite name requires --e2e or --all" >&2; exit 2
fi
if [ "$E2E" -eq 1 ]; then
  if [ -z "$ONLY" ]; then
    if [ "$REBUILD" -eq 1 ]; then REPORT_SCOPE=all; else ONLY=smoke; fi
  fi
  case "$ONLY" in
    smoke|reports-smoke) ONLY=reports-smoke ;;
    reports) ONLY=reports-smoke; REPORT_SCOPE=all ;;
    dept-trends|roadblocks|retention|headcount) REPORT_SCOPE="$ONLY"; ONLY=reports-smoke ;;
  esac
  if [ -n "$ONLY" ] && [[ " ${suites[*]} " != *" $ONLY "* ]]; then
    echo "no such e2e suite: $ONLY" >&2; exit 2
  fi
fi

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
# --vanilla skips startup/data loading. System R remains the default;
# --project-library explicitly selects the prepared, copied native library.
R_TEST_CODE='
  if (identical(Sys.getenv("CEDAR_TEST_PROJECT_LIBRARY"), "1")) {
    source("scripts/r-environment.R")
    cedar_use_native_library()
    cedar_check_dependencies(library = cedar_native_library())
  }
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

  # A short gap lets the previous browser session disconnect from the worker.
  # Report the first failure; reruns are explicit after diagnosing its cause.
  for s in "${suites[@]}"; do
    # Demo has fixed synthetic expectations and must be explicitly requested.
    [ "$s" = "demo" ] && [ "$ONLY" != "demo" ] && continue
    [ -n "$ONLY" ] && [ "$s" != "$ONLY" ] && continue
    [ -f "tests/e2e/$s.test.mjs" ] || { echo "no such suite: $s"; fail=$((fail+1)); failed_stages+=("e2e: $s missing"); finish; }
    sleep 6
    if [ "$s" = "reports-smoke" ]; then
      run_stage "e2e: reports ($REPORT_SCOPE)" node "tests/e2e/$s.test.mjs" "$REPORT_SCOPE"
    else
      run_stage "e2e: $s" node "tests/e2e/$s.test.mjs"
    fi
  done
fi

# ── Summary ──────────────────────────────────────────────────────────────────
finish
