context("Projection rebuild requests")

projection_request_runner <- function() {
  env <- new.env(parent = globalenv())
  sys.source("../../scripts/build-enrollment-projections.R", envir = env)
  env$run_projection_rebuild_request
}

write_projection_request <- function(path) {
  yaml::write_yaml(list(
    target_term = 202710L, as_of_term = 202680L, group = "critical_courses"
  ), path)
}

test_that("an absent explicit request never forces the builder", {
  run <- projection_request_runner()
  path <- file.path(tempdir(), "absent-projection-request.yml")
  expect_false(run(path, build = function(args) stop("must not build")))
  expect_false(dir.exists(paste0(path, ".lock")))
})

test_that("the explicit-request CLI no-ops without loading source tables", {
  path <- tempfile(fileext = ".yml")
  output <- system2(file.path(R.home("bin"), "Rscript"), c(
    "--vanilla", "../../scripts/build-enrollment-projections.R",
    "--request", shQuote(path)
  ), stdout = TRUE, stderr = TRUE)
  expect_null(attr(output, "status"))
  expect_match(paste(output, collapse = "\n"), "No rebuild requested")
  expect_false(any(grepl("Loading|Building class-list", output)))
})

test_that("automatic refresh uses data edges and fails closed without them", {
  config <- yaml::read_yaml("../../config/enrollment-projections.yml")
  students <- test_students %>%
    filter(term <= 202080L) %>%
    mutate(as_of_date = .cedar_term_start(term) + 30L)
  scopes <- resolve_enrollment_projection_refresh(config, students)
  # The shipped policy publishes both seasons; nearest target first, so an
  # interrupted refresh leaves the soonest planning horizon published.
  expect_length(scopes, 2L)
  expect_equal(vapply(scopes, function(scope) scope$target_term, integer(1)),
               c(202110L, 202180L))
  expect_true(all(vapply(scopes, function(scope) scope$as_of_term, integer(1)) == 202080L))
  # Newer advance registration does not move the settled edge.
  ahead <- test_students %>%
    mutate(as_of_date = if_else(term > 202080L,
                               .cedar_term_start(term) - 30L,
                               .cedar_term_start(term) + 30L))
  expect_identical(resolve_enrollment_projection_refresh(config, ahead), scopes)
  expect_error(resolve_enrollment_projection_refresh(config,
                 select(students, -as_of_date)), "settled enrollment edge")
  # A single target and a repeated one both resolve to one scope.
  config$target_term <- "next_fall"
  expect_equal(
    resolve_enrollment_projection_refresh(config, students)[[1]]$target_term, 202180L
  )
  config$target_term <- c("next_spring", 202110L)
  expect_length(resolve_enrollment_projection_refresh(config, students), 1L)
  config$target_term <- 202160L
  expect_error(resolve_enrollment_projection_refresh(config, students),
               "Spring or Fall targets")
  config$target_term <- c("next_spring", 202160L)
  expect_error(resolve_enrollment_projection_refresh(config, students),
               "Spring or Fall targets")
  config$target_term <- character(0)
  expect_error(resolve_enrollment_projection_refresh(config, students),
               "At least one target term")
  config$target_term <- "next_spring"
  config$enabled <- FALSE
  expect_null(resolve_enrollment_projection_refresh(config, stop("must not load data")))
})

test_that("automatic runs share the manual lock, retry failures, and honor requests", {
  env <- new.env(parent = globalenv())
  sys.source("../../scripts/build-enrollment-projections.R", envir = env)
  root <- tempfile("projection-auto-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "rebuild-request.yml")
  config <- "../../config/enrollment-projections.yml"
  expect_error(env$run_projection_auto_refresh(config, path,
    build = function(args, refresh_config) stop("failed fit")), "failed fit")
  expect_false(dir.exists(paste0(path, ".lock")))
  calls <- 0L
  env$run_projection_auto_refresh(config, path, build = function(args, refresh_config) {
    calls <<- calls + 1L
    expect_length(args, 0L)
    expect_true(refresh_config$enabled)
  })
  expect_equal(calls, 1L)
  dir.create(paste0(path, ".lock"))
  expect_error(env$run_projection_auto_refresh(config, path), "already running")
  unlink(paste0(path, ".lock"), recursive = TRUE)
  write_projection_request(path)
  env$run_projection_auto_refresh(config, path, build = function(args) {
    expect_true("--target-term" %in% args)
  })
  expect_false(file.exists(path))
})

test_that("prepared input changes control fitting, not file dates or row order", {
  students <- test_students %>%
    mutate(as_of_date = .cedar_term_start(term) + 30L)
  build <- function(s = students, sections = test_sections, previous = NULL) {
    build_enrollment_projection_bundle(
      calc_cl_enrls(s, by_part_term = TRUE), sections, s,
      target_term = 202110L, as_of_term = 202080L,
      scope_courses = "MATH 1215Z", scope_campuses = "ABQ",
      scope_market_id = "abq_course_market", force_courses = "MATH 1215Z",
      opt = list(history_start_term = 202080L),
      reuse_if_current = TRUE, existing_bundle = previous
    )
  }
  bundle <- build()
  expect_null(attr(bundle, "projection_reused"))
  signature <- bundle$source_fingerprint$refresh
  expect_null(enrollment_projection_rebuild_reason(bundle, signature))
  expect_match(enrollment_projection_rebuild_reason(NULL, signature), "missing")
  old <- bundle
  old$model_version <- "obsolete"
  expect_match(enrollment_projection_rebuild_reason(old, signature), "incompatible")
  old <- bundle
  old$source_fingerprint$refresh <- NULL
  expect_match(enrollment_projection_rebuild_reason(old, signature), "predates")
  changed_model <- signature
  changed_model$source_hashes[[1]] <- "changed"
  expect_match(enrollment_projection_rebuild_reason(bundle, changed_model), "changed")

  repull <- students %>% mutate(as_of_date = as_of_date + 1L)
  reused <- build(repull, previous = bundle)
  expect_true(attr(reused, "projection_reused"))
  expect_identical(reused$built_at, bundle$built_at)
  expect_true(attr(build(students[nrow(students):1L, ], previous = bundle),
                   "projection_reused"))

  # Post-cutoff registrations outside the saved target-course market are irrelevant.
  unrelated <- students
  index <- which(unrelated$term > 202080L & unrelated$subject_course != "MATH 1215Z")
  expect_gt(length(index), 0L)
  unrelated$student_id[index] <- paste0(unrelated$student_id[index], "-changed")
  expect_true(attr(build(unrelated, previous = bundle), "projection_reused"))

  corrected <- students
  index <- which(corrected$term <= 202080L)
  expect_gt(length(index), 0L)
  corrected$student_id[index] <- paste0("corrected-", seq_along(index))
  expect_null(attr(build(corrected, previous = bundle), "projection_reused"))
  current <- students
  index <- which(current$term == 202110L & current$subject_course == "MATH 1215Z")
  expect_gt(length(index), 0L)
  current$registration_status_code[index] <- STATUS_DROP_EARLY[[1]]
  expect_null(attr(build(current, previous = bundle), "projection_reused"))
  schedule <- test_sections
  index <- which(schedule$term == 202110L & schedule$subject_course == "MATH 1215Z")
  expect_gt(length(index), 0L)
  schedule$available[index] <- schedule$available[index] + 10L
  expect_null(attr(build(sections = schedule, previous = bundle), "projection_reused"))
})

test_that("the deploy gate detects model drift without touching CEDAR tables", {
  # The deploy-time check answers a narrower question than the morning refresh:
  # did the MODEL move? It must reach that answer from the saved bundle and the
  # source files alone, because computing the data half is the expensive part it
  # exists to avoid.
  students <- test_students %>%
    mutate(as_of_date = .cedar_term_start(term) + 30L)
  bundle <- build_enrollment_projection_bundle(
    calc_cl_enrls(students, by_part_term = TRUE), test_sections, students,
    target_term = 202110L, as_of_term = 202080L,
    scope_courses = "MATH 1215Z", scope_campuses = "ABQ",
    scope_market_id = "abq_course_market", force_courses = "MATH 1215Z",
    opt = list(history_start_term = 202080L)
  )
  output_dir <- withr::local_tempdir()
  write_enrollment_projection_bundle(
    bundle, file.path(output_dir, "enrollment-projections-202110-latest.qs")
  )

  # A bundle built from this working tree, checked against this working tree,
  # is not drift. This is the case that must stay cheap: it is what ~every
  # deploy hits.
  expect_null(enrollment_projection_model_drift(output_dir))

  # Nothing saved at all is drift, not a silent skip. Failing towards a rebuild
  # is correct: the alternative is serving a page built by unknown code.
  expect_match(
    enrollment_projection_model_drift(withr::local_tempdir()),
    "no saved projection bundle"
  )
})

test_that("each half of the model signature is reported by name", {
  students <- test_students %>%
    mutate(as_of_date = .cedar_term_start(term) + 30L)
  bundle <- build_enrollment_projection_bundle(
    calc_cl_enrls(students, by_part_term = TRUE), test_sections, students,
    target_term = 202110L, as_of_term = 202080L,
    scope_courses = "MATH 1215Z", scope_campuses = "ABQ",
    scope_market_id = "abq_course_market", force_courses = "MATH 1215Z",
    opt = list(history_start_term = 202080L)
  )
  output_dir <- withr::local_tempdir()
  path <- file.path(output_dir, "enrollment-projections-202110-latest.qs")

  stale_schema <- bundle
  stale_schema$source_fingerprint$refresh$schema_version <- 1L
  write_enrollment_projection_bundle(stale_schema, path)
  expect_match(
    enrollment_projection_model_drift(output_dir), "schema version changed"
  )

  stale_model <- bundle
  stale_model$source_fingerprint$refresh$model_version <- "0.0.1"
  write_enrollment_projection_bundle(stale_model, path)
  expect_match(
    enrollment_projection_model_drift(output_dir), "model version changed"
  )

  # A changed source file is named, so a deploy log does not send someone
  # diffing thirteen files by hand.
  stale_source <- bundle
  stale_source$source_fingerprint$refresh$source_hashes[[
    "R/branches/enrollment-projections.R"
  ]] <- "changed"
  write_enrollment_projection_bundle(stale_source, path)
  drift <- enrollment_projection_model_drift(output_dir)
  expect_match(drift, "model source changed")
  expect_match(drift, "R/branches/enrollment-projections.R", fixed = TRUE)

  # A bundle predating provenance tracking rebuilds rather than being trusted.
  legacy <- bundle
  legacy$source_fingerprint$refresh <- NULL
  write_enrollment_projection_bundle(legacy, path)
  expect_match(enrollment_projection_model_drift(output_dir), "predates")
})

test_that("a successful request is consumed once with its explicit scope", {
  path <- tempfile(fileext = ".yml")
  write_projection_request(path)
  run <- projection_request_runner()
  actual_args <- NULL
  expect_true(run(path, build = function(args) actual_args <<- args))
  expect_equal(actual_args, c(
    "--target-term", "202710", "--as-of-term", "202680", "--group", "critical_courses"
  ))
  expect_false(file.exists(path))
  expect_false(dir.exists(paste0(path, ".lock")))
  expect_false(run(path, build = function(args) stop("must not rebuild")))
})

test_that("failed builds retain the request and release the lock for retry", {
  path <- tempfile(fileext = ".yml")
  write_projection_request(path)
  on.exit(unlink(path), add = TRUE)
  original <- readLines(path)
  run <- projection_request_runner()
  expect_error(run(path, build = function(args) stop("build failed")), "build failed")
  expect_equal(readLines(path), original)
  expect_false(dir.exists(paste0(path, ".lock")))
  expect_true(run(path, build = function(args) invisible(NULL)))
  expect_false(file.exists(path))
})

test_that("incomplete or invalid requests never start expensive work", {
  path <- tempfile(fileext = ".yml")
  on.exit(unlink(path), add = TRUE)
  run <- projection_request_runner()
  build <- function(args) stop("unexpected expensive build")
  file.copy("../../config/enrollment-projections-request.example.yml", path)
  expect_error(run(path, build), "valid term codes")
  yaml::write_yaml(list(target_term = 202710L, as_of_term = 202710L,
                        group = "critical_courses"), path)
  expect_error(run(path, build), "before target_term")
  yaml::write_yaml(list(target_term = 202710L, as_of_term = 202680L,
                        group = "critical_courses", typo = TRUE), path)
  expect_error(run(path, build), "contain only")
  expect_true(file.exists(path))
  expect_false(dir.exists(paste0(path, ".lock")))
})

test_that("an active build lock rejects a second request", {
  path <- tempfile(fileext = ".yml")
  write_projection_request(path)
  lock <- paste0(path, ".lock")
  dir.create(lock)
  on.exit(unlink(c(path, lock), recursive = TRUE), add = TRUE)
  expect_error(
    projection_request_runner()(path, function(args) stop("must not build")),
    "already running or stale lock"
  )
  expect_true(dir.exists(lock))
  expect_true(file.exists(path))
})

test_that("a request edited during a build is retained for the next refresh", {
  path <- tempfile(fileext = ".yml")
  write_projection_request(path)
  on.exit(unlink(path), add = TRUE)
  expect_true(projection_request_runner()(path, function(args) {
    yaml::write_yaml(list(target_term = 202780L, as_of_term = 202710L,
                          group = "critical_courses"), path)
  }))
  expect_equal(yaml::read_yaml(path)$target_term, 202780L)
  expect_false(dir.exists(paste0(path, ".lock")))
})
