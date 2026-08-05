#!/usr/bin/env bash
# The standard CEDAR test procedure. Run this; do not assemble it by hand.
#
#   ./run-tests.sh              # static checks + R suite  (fast, no browser)
#   ./run-tests.sh --e2e        # ...plus the browser suites against the running app
#   ./run-tests.sh --all        # ...rebuilding the container first
#   ./run-tests.sh --e2e smoke  # one named e2e suite
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

# Force a UTF-8 LC_CTYPE before any R runs.
#
# This is not cosmetic. --vanilla skips .Rprofile, and .Rprofile is what
# guarantees UTF-8 for interactive and plain-Rscript sessions. Without it R
# starts in the C locale and mangles multibyte bytes — CEDAR source and config
# use real Unicode glyphs (em dash, >=, arrows) rather than \uXXXX escapes.
# Measured: config/changelog.yml parses to 4 entries in the C locale against 41
# in UTF-8, and tests/testthat/test-changelog.R reports 2 failures that do not
# exist under UTF-8. The Docker image exports LC_ALL=C.UTF-8, so testing in C
# means testing in a locale the app never runs in.
# Keep an inherited UTF-8 setting; otherwise pick the first one available.
# C.UTF-8 leads because that is what the Docker image exports.
#
# Matched with shell globbing rather than grep on purpose: `grep` is a shell
# FUNCTION in some developers' environments (ugrep wrappers are common) and is
# exported into child shells, where it does not honour -qxF the same way. The
# check then fails silently and the script aborts claiming no UTF-8 locale
# exists on a machine that has several.
case "${LC_ALL:-}" in
  *UTF-8|*utf8) ;;
  *)
    _avail="$(printf '\n%s\n' "$(locale -a 2>/dev/null || true)")"
    for loc in C.UTF-8 en_US.UTF-8 en_US.utf8; do
      case "$_avail" in
        *"$(printf '\n%s\n' "$loc")"*) export LC_ALL="$loc"; break ;;
      esac
    done
    unset _avail
    ;;
esac
: "${LC_ALL:?no UTF-8 locale available; install one or set LC_ALL manually}"
echo "locale: LC_ALL=$LC_ALL"

E2E=0; REBUILD=0; ONLY=""
for arg in "$@"; do
  case "$arg" in
    --e2e)  E2E=1 ;;
    --all)  E2E=1; REBUILD=1 ;;
    --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $arg"; exit 2 ;;
    *)  ONLY="$arg" ;;
  esac
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

# ── 1. Static ────────────────────────────────────────────────────────────────
run_stage "e2e selector check" node tests/e2e/check-ids.mjs

# ── 2. R unit suite ──────────────────────────────────────────────────────────
# --vanilla is REQUIRED, not decoration: it skips .Rprofile, which otherwise
# activates renv. The system library has everything the suite needs. Plain
# `Rscript -e` works today but depends on renv's macOS cache, which gets purged.
# Never "fix" that with renv::deactivate() — it rewrites .Rprofile as a side
# effect. See AGENTS.md → Running tests.
run_stage "R test suite" Rscript --vanilla -e '
  suppressMessages(library(testthat))
  testthat::set_max_fails(Inf)
  res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE)
  df  <- as.data.frame(res)
  n_fail <- sum(df$failed) + sum(df$error)
  cat(sprintf("\n%d passed, %d failed, %d skipped\n",
              sum(df$passed), n_fail, sum(df$skipped)))
  quit(status = if (n_fail > 0) 1 else 0)
'

# ── 3. Browser suites ────────────────────────────────────────────────────────
if [ "$E2E" -eq 1 ]; then
  if [ "$REBUILD" -eq 1 ]; then
    run_stage "rebuild container" ./rebuild-and-test.sh
  fi

  run_stage "app responds at http://localhost:3838/" curl -sf -o /dev/null http://localhost:3838/

  # Absorb the cold start here, where a slow stage is expected. Otherwise
  # whichever suite runs first pays for global.R inside its own step budget and
  # fails as an ambiguous "timed out waiting for <output>".
  run_stage "warm up app" node tests/e2e/warmup.mjs

  # reports-smoke first: it is the broadest and fails fastest on a bad build.
  suites=(reports-smoke nav gen-ed-grads credit-timeline course-timing-truncation course-impact-covariates)
  [ "$ONLY" = "smoke" ] && ONLY="reports-smoke"
  matched=0
  # Suites run back-to-back against ONE Shiny worker, which holds each session
  # for a grace period after the browser disconnects. Without a gap the next
  # suite starts while the previous session is still being reaped, and a suite
  # that passes alone fails in the sequence. The gap plus a single labelled
  # retry keeps that from being reported as a product failure — a suite that
  # fails twice is a real failure and is reported as one.
  for s in "${suites[@]}"; do
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
