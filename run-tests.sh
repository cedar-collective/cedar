#!/usr/bin/env bash
# The standard CEDAR test procedure. Run this; do not assemble it by hand.
#
#   ./run-tests.sh              # static checks + R suite  (fast, no browser)
#   ./run-tests.sh --changed    # read the diff; run only the checks it implies
#   ./run-tests.sh --e2e        # ...plus two representative report scenarios
#   ./run-tests.sh --e2e nav    # one browser suite against the running app
#   ./run-tests.sh --e2e reports # full institutional report tour, without rebuild
#   ./run-tests.sh --all        # rebuild, then all institutional browser suites
#   ./run-tests.sh --all smoke  # rebuild, then only the short smoke check
#   ./run-tests.sh --e2e --fresh  # restart the app, then time its first sessions
#   ./run-tests.sh --all --fresh  # the same on a rebuilt container (tests the diff)
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

E2E=0; REBUILD=0; ONLY=""; TEST_IMAGE=""; PROJECT_LIBRARY=0; CHANGED=0; SKIP_R=0; FRESH=0
SELECTED=()   # populated by --changed; empty means "use ONLY / the default"
while [ "$#" -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --e2e)  E2E=1 ;;
    --all)  E2E=1; REBUILD=1 ;;
    --fresh) E2E=1; FRESH=1 ;;
    --changed) CHANGED=1 ;;
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
suites=(fresh-start harness admin reports-smoke nav enrollment-projections course-dynamics-deeplink waitlist-deeplink waitlist-reconciliation gen-ed-deeplink gen-ed-grads credit-timeline course-impact-covariates course-cohort later-course downstream-glance course-topics concurrent-by-major dfw-rates first-year retention-dashboard graduation theme start-page run-buttons degree-explorer demo)
REPORT_SCOPE=smoke

# ── --changed: pick the smallest defensible set of checks for this diff ───────
#
# The browser stages need a rebuilt container and several minutes; the R suite
# needs neither. Most changes touch only one of the two, but it is easier to
# type --all than to work out which, so a one-line calculation edit ends up
# paying for a full browser tour. This reads the diff and says what is actually
# required, with its reasoning, so the choice is visible rather than habitual.
#
# It only ever selects checks. It never claims a release pass, and it cannot
# know that a cone change altered a rendered number, so widen it by hand when
# the blast radius is larger than the paths suggest.
plan_from_changes() {
  local base="" ref candidate files f
  # Where this branch left main. The local main of a clone that works in
  # branches and worktrees is rarely pulled, and against a main weeks old the
  # diff is everyone's work since (ISSUES M78). So ask origin/main as well,
  # as it stood at the last fetch, and take the later of the two.
  for ref in origin/main main; do
    candidate="$(git merge-base HEAD "$ref" 2>/dev/null || true)"
    [ -n "$candidate" ] || continue
    if [ -z "$base" ] || git merge-base --is-ancestor "$base" "$candidate" 2>/dev/null; then
      base="$candidate"
    fi
  done
  if [ -n "$base" ]; then
    files="$(git diff --name-only "$base" HEAD; git diff --name-only; git ls-files --others --exclude-standard)"
  else
    files="$(git diff --name-only; git ls-files --others --exclude-standard)"
  fi
  # Deleted paths still appear in the diff. Selecting a suite for one asks for a
  # script that no longer exists, which aborts the run before anything is tested.
  files="$(printf '%s\n' "$files" | sed '/^$/d' | sort -u | while IFS= read -r p; do
    [ -e "$p" ] && printf '%s\n' "$p"
  done)"
  if [ -z "$files" ]; then
    echo "  (no changes detected — defaulting to the R gate)"
    return
  fi

  # A file the projection model is hashed from: the deploy after the merge
  # rebuilds both bundles, which nothing said until it had (ISSUES M77).
  local model_source
  if ! model_source="$(printf '%s\n' "$files" | bash scripts/projection-model-source.sh --touched)"; then
    echo "  could not read the projection model-source list (scripts/projection-model-source.sh)" >&2
    exit 2
  fi

  local need_r=0 need_browser=0 need_deps=0 need_fresh=0 only_docs=1
  local -a browser_suites=()
  local reason
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    reason=""
    case "$f" in
      # Rendered surfaces: the R suite does not load modules, so only a browser
      # can tell whether these still render.
      ui.R|server.R|R/modules/*|www/*)
        need_r=1; need_browser=1; only_docs=0; reason="rendered surface -> R + browser" ;;
      # A browser script only needs its own suite.
      tests/e2e/*.test.mjs)
        only_docs=0; need_browser=1
        browser_suites+=("$(basename "$f" .test.mjs)")
        reason="browser suite" ;;
      tests/e2e/lib.mjs|tests/e2e/check-ids.mjs|tests/e2e/package*.json)
        only_docs=0; need_browser=1; browser_suites+=(harness); reason="shared harness -> harness suite" ;;
      # Dependency/toolchain: verify the environment, not the analytics.
      renv.lock|Dockerfile*|scripts/r-environment.R|.github/workflows/*|compose*.yml|docker-compose.yml)
        need_r=1; need_deps=1; only_docs=0; reason="toolchain -> dependency check + R" ;;
      # The synthetic institution is exercised by the demo browser suite.
      dev/*)
        need_r=1; need_browser=1; browser_suites+=(demo); only_docs=0; reason="synthetic data -> R + demo" ;;
      # What the app does as it starts, and so what its first readers wait for.
      # Only a process just started shows it, and only a rebuilt one has the diff.
      global.R|entrypoint.sh)
        need_r=1; need_fresh=1; only_docs=0; reason="how the app starts -> R suite + first sessions" ;;
      # Everything else under R/ plus the fixtures is pure computation.
      R/*|tests/testthat/*|config/*|setup.R)
        need_r=1; only_docs=0; reason="computation -> R suite" ;;
      docs/*|*.md)
        reason="docs only" ;;
      *)
        need_r=1; only_docs=0; reason="unclassified -> R suite" ;;
    esac
    if printf '%s\n' "$model_source" | grep -F -x -q -- "$f"; then
      reason="${reason}; PROJECTION MODEL SOURCE"
    fi
    printf '  %-44s %s\n' "$f" "$reason"
  done <<< "$files"

  if [ -n "$model_source" ]; then
    echo "  => projection model source is in this diff: $(printf '%s' "$model_source" | tr '\n' ' ')"
    echo "     Merged, it makes the next deploy rebuild both projection bundles: about 45"
    echo "     minutes of a deploy step that is stopped at 60 (ISSUES M77, I6). If no"
    echo "     projection reads the change, it belongs in a file that is not on the list"
    echo "     (bash scripts/projection-model-source.sh prints it). If the model did"
    echo "     change, say so in the pull request and merge it by itself."
  fi

  if [ "$only_docs" -eq 1 ]; then
    echo "  => documentation only: no R or browser run required"
    SKIP_R=1; E2E=0
    return
  fi
  [ "$need_deps" -eq 1 ] && echo "  => also verify pinned dependencies (scripts/r-environment.R check)"
  if [ "$need_fresh" -eq 1 ]; then
    echo "  => the app's start changed. This run does not cover it; afterwards:"
    echo "       ./run-tests.sh --all --fresh                          # rebuild, then its first sessions"
    echo "       bash scripts/dev.sh up && ./run-tests.sh --e2e demo   # the synthetic app still starts"
  fi
  if [ "$need_browser" -eq 1 ]; then
    E2E=1
    if [ "${#browser_suites[@]}" -gt 0 ]; then
      # Run every implicated suite. Picking one and telling the reader to run
      # the rest by hand is how a suite gets skipped and a regression ships.
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        [ -f "tests/e2e/$s.test.mjs" ] || continue
        SELECTED+=("$s")
      done <<< "$(printf '%s\n' "${browser_suites[@]}" | sort -u)"
    fi
    [ "${#SELECTED[@]}" -eq 0 ] && SELECTED=(reports-smoke)
    # demo asserts synthetic values and the rest read institutional data. Both
    # stacks now serve 3838 and only one can run, so a mixed set cannot be
    # satisfied by any single app — split it and say which run needs which.
    if [ "${#SELECTED[@]}" -gt 1 ] && [[ " ${SELECTED[*]} " == *" demo "* ]]; then
      local keep=()
      for s in "${SELECTED[@]}"; do [ "$s" = "demo" ] || keep+=("$s"); done
      SELECTED=("${keep[@]}")
      echo "  => demo needs the synthetic app; the others need the institutional one."
      echo "     Run this set now, then: bash scripts/dev.sh up && ./run-tests.sh --e2e demo"
    fi
    echo "  => browser suites: ${SELECTED[*]}"
  fi
  [ "$need_r" -eq 1 ] || SKIP_R=1
}

if [ "$CHANGED" -eq 1 ]; then
  if [ -n "$ONLY" ] || [ "$E2E" -eq 1 ]; then
    echo "--changed selects the checks itself; do not combine it with --e2e/--all or a suite name" >&2
    exit 2
  fi
  echo "change analysis:"
  plan_from_changes
  echo
fi
if [ "$E2E" -eq 0 ] && [ -n "$ONLY" ]; then
  echo "a suite name requires --e2e or --all" >&2; exit 2
fi
if [ "$E2E" -eq 1 ]; then
  # --fresh alone is the first-sessions check and nothing after it.
  if [ "$FRESH" -eq 1 ] && [ -z "$ONLY" ]; then ONLY=fresh-start; fi
  if [ "$FRESH" -eq 0 ] && [ "$ONLY" = fresh-start ]; then
    echo "fresh-start times a process's first sessions: run it with --fresh, which restarts the app first" >&2
    exit 2
  fi
  if [ "$FRESH" -eq 1 ] && [ -n "$TEST_IMAGE" ]; then
    echo "--fresh restarts the running app's container; do not combine it with --test-image" >&2; exit 2
  fi
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
    # A browser stage: say what the app's container shows (defined with the
    # browser stages below).
    if [ "${EXPLAIN_APP:-0}" -eq 1 ]; then explain_app_state || true; fi
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
if [ "$SKIP_R" -eq 1 ]; then
  echo
  echo "─────────────────────────────────────────────────────────────"
  echo "  R test suite — skipped (no computation changed)"
  echo "─────────────────────────────────────────────────────────────"
elif [ -n "$TEST_IMAGE" ]; then
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
  # Log lines older than this belong to the process a --fresh run replaces.
  FRESH_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$REBUILD" -eq 1 ]; then
    run_stage "rebuild container" ./rebuild-and-test.sh
  fi

  APP_URL="${CEDAR_URL:-http://localhost:3838/}"

  # A process just started is a different thing to test from one in use. R
  # compiles a function as it is first used, and a session's set-up arrives on
  # its own schedule, so a change to how the app or a session starts shows in a
  # new process's first sessions and nowhere else (ISSUES I81, I85). Every
  # other browser run reuses a process already in use; only a deploy met a new
  # one. --fresh restarts whichever container answers on the app's port, which
  # serves the institutional stack, the synthetic one and a one-off test
  # container alike. After --all the rebuilt container is already new.
  app_port() {
    local port="${APP_URL#*://}"; port="${port%%/*}"
    case "$port" in *:*) echo "${port##*:}" ;; *) echo 80 ;; esac
  }
  app_container() {
    docker ps --filter "publish=$(app_port)" --format '{{.Names}}' 2>/dev/null | sed -n 1p
  }
  restart_app() {
    local name; name="$(app_container)"
    if [ -z "$name" ]; then
      echo "no running container publishes port $(app_port): --fresh restarts the app's container" >&2
      return 1
    fi
    echo "restarting ${name}"
    # From here on: a build-ahead the old process finished a moment ago must
    # not be read as the new one's.
    FRESH_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    docker restart "$name" >/dev/null
  }
  # The app builds some pages ahead once it has started
  # (cedar_preload_shared_results()), one job at a time on its one R process,
  # and logs "[preload] 3 of 15: ...: built (2.8s)" as each ends. A session
  # opened meanwhile waits behind the job running, so a time taken then is the
  # job's. Read the log on stdin; succeed once the last job is there.
  build_ahead_done() {
    awk '/\[preload\] [0-9]+ of [0-9]+:/ {
           for (i = 2; i < NF; i++) if ($i == "of" && $(i - 1) + 0 == $(i + 1) + 0) last = 1
         }
         END { exit last ? 0 : 1 }'
  }
  wait_for_build_ahead() {
    local timeout="${1:-900}" name start
    name="$(app_container)"; start="$(date +%s)"
    if [ -z "$name" ]; then
      echo "no running container publishes port $(app_port): cannot read the app's log" >&2
      return 1
    fi
    while true; do
      if docker logs --since "$FRESH_SINCE" "$name" 2>&1 | build_ahead_done; then
        echo "build-ahead finished after $(( $(date +%s) - start ))s"
        return 0
      fi
      if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
        echo "the build-ahead did not log its last job within ${timeout}s. Its last lines:" >&2
        docker logs --since "$FRESH_SINCE" "$name" 2>&1 | awk '/\[preload\]/' | tail -3 >&2
        return 1
      fi
      sleep 5
    done
  }
  # ── After a failed browser stage: what the app's container says ────────────
  #
  # A browser stage that fails names the step that was running, and that step
  # is often not the cause. The app's R process is killed for memory and starts
  # again, so every open session is dropped and the page reloads under whatever
  # was waiting; the container restarts; the disk fills, and Docker answers
  # with input/output errors and the app with 500. Each has been read as a
  # broken page for an afternoon (docs/developers/e2e-testing.md; ISSUES M73).
  # So the runner notes what the container looked like before the suites and,
  # after a failed stage, says what changed. It explains a failure; it never
  # turns one into a pass, and it never retries.
  #
  # The app is one R process, which shiny-server starts at the first request
  # and again whenever it dies. Its pid tells one from the next at once; the
  # log would only show the next one after it had begun.
  app_worker() {   # app_worker <container>
    docker exec "$1" pgrep -f SockJSAdapter 2>/dev/null | tr '\n' ' ' | sed 's/ *$//' || true
  }
  container_fact() {   # container_fact <name> <State field>
    docker inspect --format "{{.State.$2}}" "$1" 2>/dev/null || true
  }
  note_app_state() {
    WATCH_CONTAINER="$(app_container)"
    WATCH_WORKER=""; WATCH_STARTED=""; WATCH_OOM=""
    if [ -n "$WATCH_CONTAINER" ]; then
      WATCH_WORKER="$(app_worker "$WATCH_CONTAINER")"
      WATCH_STARTED="$(container_fact "$WATCH_CONTAINER" StartedAt)"
      WATCH_OOM="$(container_fact "$WATCH_CONTAINER" OOMKilled)"
    fi
  }
  explain_app_state() {
    command -v docker >/dev/null 2>&1 || return 0
    local name worker free_kb free code memory found=0 same=""
    name="$(app_container)"
    echo
    if [ -z "$name" ]; then
      echo "What the app's container says: no running container publishes port $(app_port)."
      if [ -n "${WATCH_CONTAINER:-}" ]; then
        echo "  - ${WATCH_CONTAINER} was running before the suites and has stopped: docker logs ${WATCH_CONTAINER}"
      fi
      return 0
    fi
    echo "What the app's container says (${name}):"
    if [ -n "${WATCH_WORKER:-}" ]; then
      worker="$(app_worker "$name")"
      if [ "$worker" != "$WATCH_WORKER" ]; then
        found=1
        echo "  - The app's R process is not the one the suites began with (pid ${WATCH_WORKER} then, ${worker:-none running} now)."
        echo "    Every session open when it went was dropped, so the step that failed is probably not the cause."
      else
        same="the R process is the one the suites began with, "
      fi
    fi
    if [ -n "${WATCH_STARTED:-}" ] && [ "$(container_fact "$name" StartedAt)" != "$WATCH_STARTED" ]; then
      found=1
      echo "  - The container itself restarted during the suites."
    fi
    if [ "$(container_fact "$name" OOMKilled)" = true ]; then
      found=1
      if [ "${WATCH_OOM:-}" = true ]; then
        echo "  - Docker reports a process in it killed for memory, before the suites began (OOMKilled was already true)."
      else
        echo "  - Docker reports a process in it killed for memory (OOMKilled: true)."
      fi
      echo "    Usually a second CEDAR container is up, or courses are built ahead (CEDAR_PRELOAD_COURSES):"
      echo "    docs/developers/e2e-testing.md, the browser stages are memory-bound."
    fi
    free_kb="$(df -Pk . 2>/dev/null | awk 'NR == 2 { print $4 }')"
    free="$(awk -v kb="${free_kb:-0}" 'BEGIN { printf "%.1f", kb / 1048576 }')"
    if [ "${free_kb:-0}" -lt 2097152 ] 2>/dev/null; then
      found=1
      echo "  - The disk has ${free} GiB free. Docker stops, or answers with input/output errors, as it fills."
    fi
    code="$(curl --max-time 10 -s -o /dev/null -w '%{http_code}' "$APP_URL" 2>/dev/null || true)"
    if [ "$code" = 500 ]; then
      found=1
      echo "  - The app answers 500: it stopped as it started. docker logs ${name} 2>&1 | grep -B 5 'Execution halted'"
    elif [ "$code" != 200 ]; then
      found=1
      echo "  - The app does not answer at ${APP_URL} (HTTP ${code:-none})."
    fi
    if [ "$found" -eq 0 ]; then
      echo "  - Nothing here explains the failure: ${same}no process was killed for memory,"
      echo "    the disk has ${free} GiB free and the app answers. Read the suite's own output above."
    fi
    # docker drops the spaces a format begins with, so the line is indented here.
    memory="$(docker stats --no-stream --format '{{.Name}}  {{.MemUsage}}' "$name" 2>/dev/null || true)"
    if [ -n "$memory" ]; then echo "  memory now: ${memory}"; fi
  }

  if [ "$FRESH" -eq 1 ] && [ "$REBUILD" -eq 0 ]; then
    run_stage "restart app (a new process)" restart_app
  fi
  EXPLAIN_APP=1
  run_stage "app responds at ${APP_URL}" wait_for_app_response "$APP_URL" 240

  # Which data surface is actually answering? Both stacks serve the same port,
  # so the only reliable answer comes from the app itself. ui.R renders
  # #cedar_demo_banner when cedar_demo is TRUE, and never otherwise.
  # Identify BOTH modes positively. Absence of the demo banner is not evidence
  # of an institutional app: shiny-server answers before the R worker finishes
  # booting, and that early page has no banner either. Treating "no banner" as
  # institutional reported the demo stack as institutional and refused its own
  # suite. Require a rendered CEDAR page first; anything else is unknown.
  # Match in-shell rather than piping to grep. `printf "%s" "$body" | grep -q`
  # looks obvious and is wrong here: grep -q exits at the first match and closes
  # the pipe, printf dies of SIGPIPE mid-write, and `set -o pipefail` turns that
  # into rc=141 — so a successful match reports as failure. It only misbehaves
  # once the body is large enough for printf to still be writing, which is why
  # the small stubbed page in test-ci.R never showed it and the real 488KB page
  # always did.
  app_mode() {
    local body
    body="$(curl --max-time 30 -sf "$APP_URL" 2>/dev/null || true)"
    if [[ "$body" != *cedar-custom.css* ]]; then echo unknown
    elif [[ "$body" == *cedar_demo_banner* ]]; then echo synthetic
    else echo institutional; fi
  }

  # A suite carries expectations about its data. Running institutional
  # assertions against synthetic records (or the reverse) produces failures that
  # look like broken features, which is the same misdiagnosis the OOM reloads
  # caused. Check once, name the fix, and stop.
  check_app_mode() {
    local want="$1" have; have="$(app_mode)"
    echo "app on ${APP_URL}: ${have}   (suite expects: ${want})"
    [ "$have" = "$want" ] && return 0
    # Block only on positive evidence of the wrong surface. If the page could
    # not be read we do not know which app it is, and refusing to run on a
    # failed probe would turn a diagnostic aid into a new way to be stuck.
    if [ "$have" = unknown ]; then
      echo "NOTE: could not read the page to identify the data surface; continuing."
      return 0
    fi
    if [ -n "${CEDAR_ALLOW_APP_MODE_MISMATCH:-}" ]; then
      echo "NOTE: mismatch allowed by CEDAR_ALLOW_APP_MODE_MISMATCH."
      return 0
    fi
    echo
    echo "The running app is '${have}' but these suites expect '${want}'."
    if [ "$want" = synthetic ]; then
      echo "  docker compose down                # stop the institutional app"
      echo "  bash scripts/dev.sh up             # start the synthetic app on 3838"
    else
      echo "  bash scripts/dev.sh down           # stop the synthetic app"
      echo "  docker compose up -d --build       # start the institutional app on 3838"
    fi
    echo "Set CEDAR_ALLOW_APP_MODE_MISMATCH=1 only if you mean it."
    return 1
  }


  # Memory is the binding constraint on the browser stages, and running out of
  # it does not look like running out of it. A full report tour grows the Shiny
  # worker by ~1.3GB; if the Docker VM cannot absorb that the worker is
  # OOM-killed, www/cedar-disconnect.js reloads the page, and the failure is
  # reported against whichever step was unlucky. That is exactly how a healthy
  # Headcount acquired a reputation for being broken. Say the numbers up front.
  report_resources() {
    command -v docker >/dev/null 2>&1 || return 0
    local total others
    total="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
    [ "$total" -gt 0 ] 2>/dev/null && \
      awk -v b="$total" 'BEGIN{printf "docker VM memory: %.2f GiB\n", b/1073741824}'
    docker stats --no-stream --format '  {{.Name}}  {{.MemUsage}}' 2>/dev/null || true
    # A second CEDAR app resident during a tour is the usual reason for the
    # squeeze; it is easy to leave the demo stack up and never think about it.
    others="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c 'cedar' || true)"
    if [ "${others:-0}" -gt 1 ]; then
      echo "NOTE: ${others} CEDAR containers are running. The browser stages are"
      echo "      memory-bound; stop the ones you are not testing if a suite fails"
      echo "      with an unexplained reload or 'execution context destroyed'."
    fi
    return 0
  }
  run_stage "resource check" report_resources

  # Absorb the cold start here, where a slow stage is expected. Otherwise
  # whichever suite runs first pays for global.R inside its own step budget and
  # fails as an ambiguous "timed out waiting for <output>". A --fresh run has
  # no warm-up: the process's first session is the first thing it times.
  if [ "$FRESH" -eq 1 ]; then
    run_stage "build-ahead finished" wait_for_build_ahead "${CEDAR_BUILD_AHEAD_TIMEOUT:-900}"
  else
    run_stage "warm up app" node tests/e2e/warmup.mjs
  fi

  # demo asserts fixed synthetic values; everything else reads institutional
  # data. fresh-start reads no data at all, so it runs on either.
  WANT_MODE=institutional
  if [ "${#SELECTED[@]}" -gt 0 ]; then
    [[ " ${SELECTED[*]} " == *" demo "* ]] && WANT_MODE=synthetic
  elif [ "$ONLY" = demo ]; then
    WANT_MODE=synthetic
  elif [ "$ONLY" = fresh-start ]; then
    WANT_MODE=either
  fi
  if [ "$WANT_MODE" != either ]; then
    # This stage says what is wrong itself; the container has nothing to add.
    EXPLAIN_APP=0
    run_stage "app data surface" check_app_mode "$WANT_MODE"
    EXPLAIN_APP=1
  fi

  # From here a failure is a suite's: note the container as the suites meet it.
  note_app_state

  # First, and only on a process nothing has opened yet.
  if [ "$FRESH" -eq 1 ]; then
    run_stage "e2e: fresh-start (the process's first sessions)" node tests/e2e/fresh-start.test.mjs
  fi

  # Between suites, wait for the app to answer rather than sleeping a fixed 6s.
  # The blind sleep cost ~66s on a full run — 17% of the browser stage — and
  # contradicted this project's own rule against sleeping for Shiny. Running the
  # whole suite list back to back with no gap at all passes; responsiveness is
  # the real readiness signal, so poll for it.
  # Report the first failure; reruns are explicit after diagnosing its cause.
  for s in "${suites[@]}"; do
    # fresh-start ran above if it was asked for; it is no part of a tour.
    [ "$s" = "fresh-start" ] && continue
    if [ "${#SELECTED[@]}" -gt 0 ]; then
      # --changed picked an explicit set; demo is included only if it chose it.
      [[ " ${SELECTED[*]} " == *" $s "* ]] || continue
    else
      # Demo has fixed synthetic expectations and must be explicitly requested.
      [ "$s" = "demo" ] && [ "$ONLY" != "demo" ] && continue
      [ -n "$ONLY" ] && [ "$s" != "$ONLY" ] && continue
    fi
    [ -f "tests/e2e/$s.test.mjs" ] || { echo "no such suite: $s"; fail=$((fail+1)); failed_stages+=("e2e: $s missing"); finish; }
    wait_for_app_response "$APP_URL" 60 || {
      echo "app stopped responding before suite '$s'" >&2
      explain_app_state || true
      fail=$((fail+1)); failed_stages+=("app unresponsive before $s"); finish
    }
    if [ "$s" = "reports-smoke" ]; then
      run_stage "e2e: reports ($REPORT_SCOPE)" node "tests/e2e/$s.test.mjs" "$REPORT_SCOPE"
    else
      run_stage "e2e: $s" node "tests/e2e/$s.test.mjs"
    fi
  done
fi

# ── Summary ──────────────────────────────────────────────────────────────────
finish
