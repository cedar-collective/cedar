# Build and save an enrollment-projection bundle without starting Shiny.
#
# Example:
#   Rscript --vanilla scripts/build-enrollment-projections.R \
#     --target-term 202680 --as-of-term 202660 \
#     --group critical_courses

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
  if (!is.null(refresh_config)) {
    source(file.path(repo_root, "scripts", "cedar-repl.R"))
    scope <- resolve_enrollment_projection_refresh(refresh_config, cedar_students)
    if (is.null(scope)) {
      message("[projections] Automatic refresh disabled by configuration.")
      return(invisible(NULL))
    }
    args <- c("--target-term", as.character(scope$target_term),
              "--as-of-term", as.character(scope$as_of_term), "--group", scope$group)
  }
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

  if (is.null(refresh_config)) {
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
  existing_bundle <- if (!is.null(refresh_config) && file.exists(output_path)) {
    tryCatch(read_enrollment_projection_bundle(output_path), error = function(error) {
      message("[projections] Saved bundle cannot be reused: ", conditionMessage(error))
      NULL
    })
  } else NULL

  message("[build-enrollment-projections.R] Preparing class-list demand history...")
  scoped_classlists <- cedar_students %>%
    dplyr::filter(
      campus %in% .env$scope_campuses,
      subject_course %in% .env$scope_courses
    )
  cl_enrls <- calc_cl_enrls(scoped_classlists, by_part_term = TRUE)
  rm(scoped_classlists)

  message(
    "[build-enrollment-projections.R] Projecting ", length(scope_courses),
    " course market(s) in ", scope_market_id, " (",
    paste(scope_campuses, collapse = ", "), ") for ",
    target_term, " using data through ", as_of_term, "."
  )
  bundle <- build_enrollment_projection_bundle(
    cl_enrls = cl_enrls,
    sections = cedar_sections,
    students = cedar_students,
    target_term = target_term,
    as_of_term = as_of_term,
    scope_courses = scope_courses,
    scope_campuses = scope_campuses,
    scope_market_id = scope_market_id,
    force_courses = force_courses,
    reuse_if_current = !is.null(refresh_config),
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
  lock_path <- paste0(request_path, ".lock")
  if (!dir.create(lock_path, showWarnings = FALSE)) {
    stop("[projections] Rebuild already running or stale lock: ", lock_path,
         call. = FALSE)
  }
  on.exit(unlink(lock_path, recursive = TRUE), add = TRUE)

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
  lock_path <- file.path(normalizePath(dirname(request_path), mustWork = TRUE),
                         paste0(basename(request_path), ".lock"))
  if (!dir.create(lock_path, showWarnings = FALSE)) {
    stop("[projections] Rebuild already running or stale lock: ", lock_path,
         call. = FALSE)
  }
  on.exit(unlink(lock_path, recursive = TRUE), add = TRUE)
  build(character(0), refresh_config = config)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (identical(args, "--refresh")) {
    run_projection_auto_refresh()
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
