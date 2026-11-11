# Build and save an enrollment-projection bundle without starting Shiny.
#
# Example:
#   Rscript --vanilla scripts/build-enrollment-projections.R \
#     --target-term 202680 --as-of-term 202660 \
#     --group critical_courses

# The refresh policy may name several targets -- typically the next Fall and the
# next Spring -- and each publishes its own bundle. Data is loaded once and every
# target is built against it; a target that is already current is reused, so
# adding a season costs nothing on a morning where nothing moved.
build_enrollment_projections <- function(args, refresh_config = NULL) {
  repo_root <- getwd()
  while (!file.exists(file.path(repo_root, "global.R")) &&
         dirname(repo_root) != repo_root) {
    repo_root <- dirname(repo_root)
  }
  if (!file.exists(file.path(repo_root, "global.R"))) {
    stop("Could not find the CEDAR repository root.", call. = FALSE)
  }
  setwd(repo_root)
  if (is.null(refresh_config)) {
    return(invisible(build_one_enrollment_projection(args, repo_root, refreshing = FALSE)))
  }
  source(file.path(repo_root, "scripts", "cedar-repl.R"))
  scopes <- resolve_enrollment_projection_refresh(refresh_config, cedar_registrations)
  if (is.null(scopes)) {
    message("[projections] Automatic refresh disabled by configuration.")
    return(invisible(NULL))
  }
  message("[projections] Refresh policy publishes ", length(scopes), " target(s): ",
          paste(vapply(scopes, function(scope) fmt_term(scope$target_term),
                       character(1)), collapse = ", "), ".")
  paths <- vapply(scopes, function(scope) {
    build_one_enrollment_projection(
      c("--target-term", as.character(scope$target_term),
        "--as-of-term", as.character(scope$as_of_term), "--group", scope$group),
      repo_root, refreshing = TRUE
    )
  }, character(1))
  invisible(paths)
}


build_one_enrollment_projection <- function(args, repo_root, refreshing) {
  argument_value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args)) return(NULL)
    args[[index + 1L]]
  }

  stop_with_usage <- function(message) {
    stop(
      message,
      "\nUsage: Rscript --vanilla scripts/build-enrollment-projections.R ",
      "--target-term YYYYSS --as-of-term YYYYSS ",
      "(--group GROUP_ID | --courses 'COURSE 1,COURSE 2') ",
      "[--campuses 'ABQ,EA' --market-id MARKET_ID] [--output PATH]",
      call. = FALSE
    )
  }

  target_arg <- argument_value("--target-term")
  as_of_arg <- argument_value("--as-of-term")
  target_term <- suppressWarnings(as.integer(target_arg))
  as_of_term <- suppressWarnings(as.integer(as_of_arg))
  group_id <- argument_value("--group")
  course_arg <- argument_value("--courses")
  campus_arg <- argument_value("--campuses")
  market_arg <- argument_value("--market-id")
  output_path <- argument_value("--output")

  if (is.null(target_arg) || length(target_term) != 1 || is.na(target_term)) {
    stop_with_usage("--target-term is required.")
  }
  if (is.null(as_of_arg) || length(as_of_term) != 1 || is.na(as_of_term)) {
    stop_with_usage("--as-of-term is required.")
  }
  if (is.null(group_id) && is.null(course_arg)) {
    stop_with_usage("Choose an explicit --group or --courses scope.")
  }
  if (!is.null(group_id) && !is.null(course_arg)) {
    stop_with_usage("Use either --group or --courses, not both.")
  }
  if (!is.null(group_id) && (!is.null(campus_arg) || !is.null(market_arg))) {
    stop_with_usage("A named group supplies its own campus and market scope.")
  }

  if (!refreshing) {
    source(file.path(repo_root, "scripts", "cedar-repl.R"))
  }

  scope_courses <- if (!is.null(group_id)) {
    projection_course_group_courses(group_id)
  } else {
    trimws(strsplit(course_arg, ",", fixed = TRUE)[[1]])
  }
  scope_courses <- sort(unique(scope_courses[nzchar(scope_courses)]))
  if (length(scope_courses) == 0) stop_with_usage("The selected scope has no courses.")

  scope_campuses <- if (!is.null(campus_arg)) {
    trimws(strsplit(campus_arg, ",", fixed = TRUE)[[1]])
  } else if (!is.null(group_id)) {
    projection_course_group_campuses(group_id)
  } else {
    character(0)
  }
  scope_campuses <- sort(unique(scope_campuses[nzchar(scope_campuses)]))
  if (length(scope_campuses) == 0) {
    stop_with_usage("--campuses is required for an explicit course scope.")
  }
  scope_market_id <- if (!is.null(group_id)) {
    projection_course_group_market_id(group_id)
  } else {
    market_arg
  }
  if (is.null(scope_market_id) || length(scope_market_id) != 1L ||
      is.na(scope_market_id) || !nzchar(scope_market_id)) {
    stop_with_usage("--market-id is required for an explicit course scope.")
  }

  # Named monitoring groups always compute their explicit core and pressure-screen
  # the remainder. An ad hoc request bypasses pressure for diagnosis.
  force_courses <- if (is.null(group_id)) {
    scope_courses
  } else {
    projection_course_group_always_monitored_courses(group_id)
  }

  if (is.null(output_path)) {
    output_path <- file.path(
      repo_root, "output", "projections",
      paste0("enrollment-projections-", target_term, "-latest.qs")
    )
  }
  existing_bundle <- if (refreshing && file.exists(output_path)) {
    tryCatch(read_enrollment_projection_bundle(output_path), error = function(error) {
      message("[projections] Saved bundle cannot be reused: ", conditionMessage(error))
      NULL
    })
  } else NULL

  message("[build-enrollment-projections.R] Preparing class-list demand history...")
  # By course, not by code (0.28.0): the scope resolved to course ids, and
  # the demand history counted over the loaded class list, keyed on the course.
  course_scope <- enrollment_projection_course_scope(
    cedar_registrations, cedar_sections, scope_courses, force_courses
  )
  scope_courses <- course_scope$scope_courses
  force_courses <- course_scope$force_courses
  scoped_classlists <- cedar_registrations %>%
    dplyr::filter(
      campus %in% .env$scope_campuses,
      subject_course %in% .env$scope_courses
    )
  cl_enrls <- calc_cl_enrls(scoped_classlists, by_part_term = TRUE)
  rm(scoped_classlists, course_scope)

  message(
    "[build-enrollment-projections.R] Projecting ", length(scope_courses),
    " course market(s) in ", scope_market_id, " (",
    paste(scope_campuses, collapse = ", "), ") for ",
    target_term, " using data through ", as_of_term, "."
  )
  bundle <- build_enrollment_projection_bundle(
    cl_enrls = cl_enrls,
    sections = cedar_sections,
    students = cedar_registrations,
    student_terms = cedar_student_terms,
    target_term = target_term,
    as_of_term = as_of_term,
    scope_courses = scope_courses,
    scope_campuses = scope_campuses,
    scope_market_id = scope_market_id,
    force_courses = force_courses,
    reuse_if_current = refreshing,
    existing_bundle = existing_bundle
  )

  if (isTRUE(attr(bundle, "projection_reused"))) {
    return(invisible(output_path))
  }
  write_enrollment_projection_bundle(bundle, output_path)

  provenance <- bundle$model_provenance
  commit_label <- if (length(provenance$git_commit) == 1L &&
                      !is.na(provenance$git_commit)) {
    substr(provenance$git_commit, 1L, 8L)
  } else {
    "unavailable"
  }
  worktree_label <- if (isTRUE(provenance$relevant_worktree_dirty)) {
    "modified model source embedded"
  } else if (identical(provenance$relevant_worktree_dirty, FALSE)) {
    "clean model source"
  } else {
    "worktree status unavailable"
  }
  message(
    "[build-enrollment-projections.R] Saved ", nrow(bundle$projections),
    " projection row(s), ", nrow(bundle$candidates), " candidates, and ",
    nrow(bundle$backtests), " backtests to ", normalizePath(output_path), ".\n",
    "[build-enrollment-projections.R] Model ", bundle$model_version,
    ", schema ", bundle$schema_version, ", Git ", commit_label, " (",
    worktree_label, ")."
  )
  invisible(output_path)
}

# The lock is a directory, released by the caller's on.exit(). A failed create
# has two causes that need different hands: a lock already there, or a
# projections directory this process cannot write, which once passed for a
# stale lock every morning (I19). Say which.
#
# on.exit() never runs in a process that is killed (a deploy's SSH timeout, an
# out-of-memory kill, an interrupted `docker compose run`), and a lock left
# that way blocked every later refresh until someone removed it by hand
# (ISSUES.md I6). So a held lock carries a sign of life: a small shell loop
# beside the build touches `heartbeat` in the lock every few seconds for as
# long as the owning R process exists. A lock whose heartbeat has stopped for
# `stale_after` seconds belongs to a process that is gone, and the next run
# takes it over. A heartbeat rather than the owner's PID, because builds run
# in separate containers that share only this directory: one container cannot
# see another's processes. And not the lock's age, because a build has no
# maximum length safe to guess: a live build keeps its lock however long it
# runs.
PROJECTION_LOCK_HEARTBEAT_SECONDS <- 30
PROJECTION_LOCK_STALE_SECONDS <- 600
# A lock with no heartbeat file was taken by a build from before 2026-11-11,
# which had none; it is stale only once older than any such build could be.
PROJECTION_LOCK_LEGACY_STALE_SECONDS <- 6 * 3600

take_projection_lock <- function(
    lock_path,
    stale_after = PROJECTION_LOCK_STALE_SECONDS,
    heartbeat_every = PROJECTION_LOCK_HEARTBEAT_SECONDS,
    legacy_stale_after = PROJECTION_LOCK_LEGACY_STALE_SECONDS) {
  reason <- NULL
  created <- withCallingHandlers(
    dir.create(lock_path),
    warning = function(w) {
      reason <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  if (!created && !dir.exists(lock_path)) {
    stop("[projections] Cannot create the rebuild lock -- ",
         if (is.null(reason)) lock_path else reason, ". The projections ",
         "directory must be writable; in production, build through the ",
         "cedar-projections service (ISSUES.md I19).", call. = FALSE)
  }
  if (!created) {
    beat_path <- file.path(lock_path, "heartbeat")
    has_beat <- file.exists(beat_path)
    last_alive <- file.mtime(if (has_beat) beat_path else lock_path)
    silent_for <- as.numeric(difftime(Sys.time(), last_alive, units = "secs"))
    limit <- if (has_beat) stale_after else legacy_stale_after
    # Two runs that find the same dead lock race for one marker, named after
    # the heartbeat they both read; dir.create() lets exactly one of them win.
    takeover <- file.path(lock_path, paste0("takeover-", as.integer(last_alive)))
    if (is.na(silent_for) || silent_for <= limit ||
        !suppressWarnings(dir.create(takeover))) {
      stop("[projections] Rebuild already running: ", lock_path,
           " (taken ", format(file.mtime(lock_path), "%Y-%m-%d %H:%M"),
           ", last sign of life ", format(last_alive, "%Y-%m-%d %H:%M:%S"),
           "). A lock whose build was killed is taken over by the next run ",
           "once it has shown none for ", limit, " seconds (ISSUES.md I6).",
           call. = FALSE)
    }
    message("[projections] Taking over the rebuild lock of a build that is gone: ",
            "no sign of life since ", format(last_alive, "%Y-%m-%d %H:%M:%S"), ".")
    unlink(list.files(lock_path, pattern = "^owner-", full.names = TRUE))
  }

  # The owner file names this holder; its heartbeat stops when the file goes
  # (the lock was released or taken over) or this process does.
  token <- paste0(Sys.getpid(), "-", format(Sys.time(), "%Y%m%d%H%M%OS3"))
  owner_path <- file.path(lock_path, paste0("owner-", token))
  beat_path <- file.path(lock_path, "heartbeat")
  writeLines(c(paste("pid:", Sys.getpid()),
               paste("host:", Sys.info()[["nodename"]]),
               paste("started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))),
             owner_path)
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), beat_path)
  # A killed process whose parent has not collected it stays in the process
  # table as a zombie, and `kill -0` still succeeds on it: in a container
  # with no init, that kept a dead build's heartbeat going. On Linux, read
  # the state from /proc and count a zombie as gone.
  loop <- sprintf(paste(
    "alive() { kill -0 %1$d 2>/dev/null || return 1;",
    "if [ -r /proc/%1$d/stat ]; then case \"$(cat /proc/%1$d/stat 2>/dev/null)\" in",
    "*') Z '*) return 1 ;; esac; fi; return 0; };",
    # touch -c: never create the file. A release removes the lock's files and
    # then the directory; a heartbeat written back in between left the
    # directory, and so the lock, in place.
    "while alive && [ -f %2$s ]; do touch -c %3$s 2>/dev/null; sleep %4$d; done"),
    Sys.getpid(), shQuote(owner_path), shQuote(beat_path), as.integer(heartbeat_every))
  system2("sh", c("-c", shQuote(loop)), wait = FALSE, stdout = FALSE, stderr = FALSE)
  attr(lock_path, "owner_path") <- owner_path
  invisible(lock_path)
}

# Release only a lock this process still holds: one taken over while its
# holder was suspended belongs to the run that took it.
release_projection_lock <- function(lock_path) {
  owner_path <- attr(lock_path, "owner_path")
  if (is.null(owner_path)) {
    stop("[projections] release_projection_lock() needs the value take_projection_lock() returned.",
         call. = FALSE)
  }
  if (!file.exists(owner_path)) return(invisible(NULL))
  # The owner file first: the heartbeat loop stops when it is gone.
  unlink(owner_path)
  unlink(lock_path, recursive = TRUE)
  if (dir.exists(lock_path)) {
    stop("[projections] Could not remove the rebuild lock: ", lock_path, call. = FALSE)
  }
  invisible(NULL)
}

# A request file is a one-shot flag, checked before loading the data or model.
# Keep it on failure so the next successful morning refresh can retry.
run_projection_rebuild_request <- function(
    request_path, build = build_enrollment_projections) {
  if (!file.exists(request_path)) {
    message("[projections] No rebuild requested; keeping the saved projections.")
    return(invisible(FALSE))
  }
  # The standalone builder changes to the repository root before loading data.
  request_path <- normalizePath(request_path, mustWork = TRUE)
  lock_path <- take_projection_lock(paste0(request_path, ".lock"))
  on.exit(release_projection_lock(lock_path), add = TRUE)

  request_text <- readLines(request_path, warn = FALSE)
  request <- yaml::yaml.load(paste(request_text, collapse = "\n"), eval.expr = FALSE)
  fields <- c("target_term", "as_of_term", "group")
  if (!is.list(request) || is.null(names(request)) ||
      anyDuplicated(names(request)) || !setequal(names(request), fields)) {
    stop("[projections] Request must contain only target_term, as_of_term, and group.",
         call. = FALSE)
  }
  valid_term <- function(x) {
    length(x) == 1L && !is.na(x) &&
      grepl("^[0-9]{4}(10|60|80)$", as.character(x))
  }
  if (!valid_term(request$target_term) || !valid_term(request$as_of_term) ||
      as.integer(request$as_of_term) >= as.integer(request$target_term)) {
    stop("[projections] Use valid term codes with as_of_term before target_term.",
         call. = FALSE)
  }
  if (!is.character(request$group) || length(request$group) != 1L ||
      is.na(request$group) || !grepl("^[a-z][a-z0-9_]*$", request$group)) {
    stop("[projections] Request group must be a named course-group ID.", call. = FALSE)
  }

  build(c(
    "--target-term", as.character(request$target_term),
    "--as-of-term", as.character(request$as_of_term),
    "--group", request$group
  ))

  # Do not consume a newly edited request submitted while the model was running.
  if (file.exists(request_path) &&
      identical(readLines(request_path, warn = FALSE), request_text)) {
    if (unlink(request_path) != 0L) {
      stop("[projections] Bundle published but could not clear request: ", request_path,
           call. = FALSE)
    }
    message("[projections] Rebuild complete; request cleared.")
  } else {
    message("[projections] Rebuild complete; request changed during build and was retained.")
  }
  invisible(TRUE)
}

run_projection_auto_refresh <- function(
    config_path = "config/enrollment-projections.yml",
    request_path = "output/projections/rebuild-request.yml",
    build = build_enrollment_projections) {
  # Explicit one-shot requests take precedence and always force a rebuild.
  if (file.exists(request_path)) {
    return(run_projection_rebuild_request(request_path, build = build))
  }
  config <- yaml::read_yaml(config_path, eval.expr = FALSE)
  dir.create(dirname(request_path), recursive = TRUE, showWarnings = FALSE)
  lock_path <- take_projection_lock(
    file.path(normalizePath(dirname(request_path), mustWork = TRUE),
              paste0(basename(request_path), ".lock")))
  on.exit(release_projection_lock(lock_path), add = TRUE)
  build(character(0), refresh_config = config)
}

# Deploy-time gate: refresh only when the projection model itself moved.
#
# `--refresh` is safe to run at any time but is not cheap — it prepares the same
# inputs the analyses use before it can decide whether anything changed. Most
# CEDAR deploys touch no projection source at all, so running it on every deploy
# would pay that cost to learn nothing.
#
# This checks the model half only (schema version, model version, and the
# hashes of the model source files), which needs no CEDAR table, and delegates
# to the ordinary refresh when it finds drift. Data-driven staleness is NOT this
# function's job — the morning refresh still owns that, and still runs the full
# signature comparison.
run_projection_refresh_if_model_changed <- function(
    output_dir = file.path(getwd(), "output", "projections"),
    refresh = run_projection_auto_refresh) {
  source(file.path(getwd(), "scripts", "cedar-repl.R"))
  drift <- enrollment_projection_model_drift(output_dir)
  if (is.null(drift)) {
    message(
      "[projections] Model unchanged since the saved bundle; no rebuild. ",
      "Data-driven staleness is handled by the morning refresh."
    )
    return(invisible(FALSE))
  }
  message("[projections] Rebuilding because the model changed: ", drift)
  refresh()
  invisible(TRUE)
}


if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (identical(args, "--refresh")) {
    run_projection_auto_refresh()
  } else if (identical(args, "--refresh-if-model-changed")) {
    run_projection_refresh_if_model_changed()
  } else if ("--request" %in% args) {
    if (length(args) != 2L || args[[1]] != "--request") {
      stop("Usage: Rscript --vanilla scripts/build-enrollment-projections.R --request PATH",
           call. = FALSE)
    }
    run_projection_rebuild_request(args[[2]])
  } else {
    build_enrollment_projections(args)
  }
}
