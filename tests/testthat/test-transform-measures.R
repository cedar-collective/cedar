context("The measure tables are built by the transform (ADR-001 step 6)")

# load_transform_helpers() is in helper-transform.R.
#
# The principle: the transform runs once a day and may take as long as it
# needs; a restart is a load. So cedar_attempts, cedar_course_terms and
# cedar_course_flows are built by transform_measures() over the class list as
# global.R loads it, stamped so the loader can refuse a table built from other
# mapping files or over another first term, and global.R builds nothing.

# The fixtures are already keyed and attached; written as saved tables they
# round-trip, because attach_course_ids() keys again from listed_code and
# attach_default_units() drops the stamped unit columns first. The saved class
# list also carries Banner's section college (source_college), the key the
# attach reads, which the fixture never needed: the fixture's own college
# stands in for it.
write_saved_fixtures <- function(dir) {
  qs2::qs_save(test_sections, file.path(dir, "cedar_sections.qs"))
  qs2::qs_save(dplyr::mutate(test_students, source_college = college), file.path(dir, "cedar_students.qs"))
  qs2::qs_save(test_degrees, file.path(dir, "cedar_degrees.qs"))
  invisible(dir)
}

# The fixtures' pulls are all within a fortnight of their terms' start, so no
# settled edge can be determined from them (cedar_report_edges() stops, as it
# should in production); the tests state the edge, as test-course-flows.R does.
fixture_edges <- function() {
  terms <- sort(unique(test_students$term))
  modifyList(data_objects$cedar_edges, list(last_enrolled_complete = terms[length(terms) - 1L]))
}

test_that("transform_measures() builds the three tables the app loads, as the app would have built them", {
  env <- load_transform_helpers()
  dir <- withr::local_tempdir()
  write_saved_fixtures(dir)
  min_term <- min(test_students$term)
  edges <- fixture_edges()

  # Without an edge it fails closed on these fixtures, as the refresh would.
  expect_error(suppressMessages(env$transform_measures(dir, ".qs", min_term = min_term, dims = test_dims)),
               "settled edge cannot be determined")
  result <- suppressMessages(env$transform_measures(dir, ".qs", min_term = min_term, dims = test_dims,
                                                    edges = edges))
  expect_setequal(names(result$saved), c("attempts", "course_terms", "course_flows"))
  for (name in CEDAR_MEASURE_TABLES) expect_true(file.exists(file.path(dir, paste0(name, ".qs"))))

  # Each passes the check the loader applies, against the fixtures as loaded.
  attempts <- qs2::qs_read(file.path(dir, "cedar_attempts.qs"))
  course_terms <- qs2::qs_read(file.path(dir, "cedar_course_terms.qs"))
  flows <- qs2::qs_read(file.path(dir, "cedar_course_flows.qs"))
  expect_true(attempts_is_current(attempts, test_students, edges))
  expect_true(course_terms_is_current(course_terms, test_students, graded_edge = edges$last_graded))
  expect_true(course_flows_is_current(flows, test_students, edges))

  # The same rows the app used to build at start.
  expect_equal(nrow(attempts), nrow(attempts_for(test_students, edges)))
  expect_equal(nrow(course_terms), nrow(course_terms_for(test_students, edges)))
  expect_equal(nrow(flows), nrow(build_course_flows(test_students, edges)))

  # Stamped with the mapping files and the first term, for the loader's refusal.
  for (tbl in list(attempts, course_terms, flows)) {
    expect_identical(attr(tbl, "cedar_dims_fingerprint"), cedar_dims_fingerprint(test_dims))
    expect_identical(attr(tbl, "cedar_min_term"), as.integer(min_term))
  }

  # Trimmed as the app trims: a later first term drops the earlier rows, and
  # each table is what the builder gives over the class list trimmed the same
  # way (the fixtures have no same-campus next-term pair after Fall 2020, so
  # the flows are legitimately empty on this window).
  later <- 202080L
  window <- dplyr::filter(test_students, term >= later)
  trim_edges <- modifyList(edges, list(last_enrolled_complete = max(test_students$term)))
  suppressMessages(env$transform_measures(dir, ".qs", min_term = later, dims = test_dims, edges = trim_edges))
  trimmed <- qs2::qs_read(file.path(dir, "cedar_attempts.qs"))
  expect_true(all(trimmed$term >= later))
  expect_lt(nrow(trimmed), nrow(attempts))
  expect_gt(nrow(trimmed), 0L)
  expect_equal(nrow(trimmed), nrow(attempts_for(window, trim_edges)))
  expect_identical(attr(trimmed, "cedar_min_term"), as.integer(later))
  expect_equal(nrow(qs2::qs_read(file.path(dir, "cedar_course_terms.qs"))),
               nrow(course_terms_for(window, trim_edges)))
  expect_equal(nrow(qs2::qs_read(file.path(dir, "cedar_course_flows.qs"))),
               nrow(build_course_flows(window, trim_edges)))

  # The first term is required, not defaulted.
  expect_error(env$transform_measures(dir, ".qs", min_term = NULL, dims = test_dims, edges = edges), "min_term")
  expect_error(env$transform_measures(dir, ".qs", min_term = NA, dims = test_dims, edges = edges), "min_term")
})

test_that("transform_to_cedar() adds the measures stage whenever the class list is transformed, and needs the first term", {
  env <- load_transform_helpers()
  # The stage list is resolved before any file is read; an unknown-only
  # request leaves nothing to run, so the resolution is observed through the
  # messages and the error for a missing first term.
  dir <- withr::local_tempdir()
  expect_error(
    suppressMessages(env$transform_to_cedar(data_dir = dir, use_qs = TRUE, tables = "measures")),
    "min_term")
  expect_message(
    tryCatch(env$transform_to_cedar(data_dir = dir, use_qs = TRUE, tables = "students"),
             error = function(e) NULL),
    "Adding measures")
  expect_no_message(
    tryCatch(env$transform_to_cedar(data_dir = dir, use_qs = TRUE, tables = "students",
                                    include_student_terms = FALSE),
             error = function(e) NULL),
    message = "Adding measures")
})

# The deploy gate's question, answered from the saved files alone.
test_that("the measure tables are stale when missing, older than the class list, from another build, policy, column set, mapping files or first term", {
  env <- load_transform_helpers()
  dir <- withr::local_tempdir()
  min_term <- 201980L
  fingerprint <- cedar_dims_fingerprint(test_dims)
  t0 <- Sys.time() - 3600
  write_at <- function(name, when, data = tibble::tibble(x = 1)) {
    path <- file.path(dir, paste0(name, ".qs"))
    qs2::qs_save(data, path)
    Sys.setFileTime(path, when)
    path
  }
  one_row <- function(columns) {
    tibble::as_tibble(stats::setNames(as.list(rep(1, length(columns))), columns))
  }
  stamped <- function(tbl, version_attr, version, policy = NULL, dims = fingerprint, first = min_term) {
    attr(tbl, version_attr) <- version
    if (!is.null(policy)) attr(tbl, "cedar_outcome_policy_version") <- policy
    attr(tbl, "cedar_dims_fingerprint") <- dims
    attr(tbl, "cedar_min_term") <- first
    tbl
  }
  attempts <- stamped(one_row(ATTEMPTS_COLUMNS), "attempts_build_version", ATTEMPTS_BUILD_VERSION,
                      policy = CEDAR_OUTCOME_POLICY_VERSION)
  course_terms <- stamped(one_row(COURSE_TERMS_COLUMNS), "course_terms_build_version",
                          COURSE_TERMS_BUILD_VERSION)
  flows <- stamped(one_row(names(empty_next_course_pairs())), "course_flows_build_version",
                   COURSE_FLOWS_BUILD_VERSION)
  write_all <- function(when = t0 + 60) {
    write_at("cedar_attempts", when, attempts)
    write_at("cedar_course_terms", when, course_terms)
    write_at("cedar_course_flows", when, flows)
  }
  stale <- function() env$cedar_measures_staleness(dir, dims = test_dims, min_term = min_term)

  expect_match(stale(), "^cedar_students has not been built$")
  write_at("cedar_students", t0)
  expect_match(stale(), "^cedar_attempts has not been built$")
  write_all()
  expect_null(stale())

  # The class list rebuilt since: every measure is stale.
  write_at("cedar_students", t0 + 120)
  expect_match(stale(), "^cedar_students newer than cedar_attempts$")
  write_at("cedar_students", t0)

  # Another build of one table.
  older <- course_terms; attr(older, "course_terms_build_version") <- COURSE_TERMS_BUILD_VERSION - 1L
  write_at("cedar_course_terms", t0 + 60, older)
  expect_match(stale(), "^saved cedar_course_terms was built under build version ")
  write_all()

  # Another outcome policy on the attempts.
  other_policy <- attempts; attr(other_policy, "cedar_outcome_policy_version") <- CEDAR_OUTCOME_POLICY_VERSION + 1L
  write_at("cedar_attempts", t0 + 60, other_policy)
  expect_match(stale(), "^saved cedar_attempts was classified under outcome policy ")
  write_all()

  # A column the builder gained since.
  short <- stamped(one_row(ATTEMPTS_COLUMNS[-length(ATTEMPTS_COLUMNS)]), "attempts_build_version",
                   ATTEMPTS_BUILD_VERSION, policy = CEDAR_OUTCOME_POLICY_VERSION)
  write_at("cedar_attempts", t0 + 60, short)
  expect_match(stale(), "^saved cedar_attempts lacks column\\(s\\) the builder now writes: outcome$")
  write_all()

  # Other mapping files: the units on the measures would be another file's.
  write_at("cedar_course_flows", t0 + 60,
           stamped(one_row(names(empty_next_course_pairs())), "course_flows_build_version",
                   COURSE_FLOWS_BUILD_VERSION, dims = "000000000000"))
  expect_match(stale(), "^saved cedar_course_flows was built from other mapping files$")
  write_all()

  # Another first term: the renames stamped would be another window's.
  write_at("cedar_attempts", t0 + 60,
           stamped(one_row(ATTEMPTS_COLUMNS), "attempts_build_version", ATTEMPTS_BUILD_VERSION,
                   policy = CEDAR_OUTCOME_POLICY_VERSION, first = 201880L))
  expect_match(stale(), "^saved cedar_attempts starts at term 201880; the app starts at 201980$")
  unstamped <- attempts; attr(unstamped, "cedar_min_term") <- NULL
  write_at("cedar_attempts", t0 + 60, unstamped)
  expect_match(stale(), "starts at term unknown \\(unstamped\\)")
  write_all()
  expect_null(stale())

  expect_error(env$cedar_measures_staleness(dir, dims = test_dims), "min_term")
})

# The loader's side: cedar_load_measure_table() refuses every disagreement and
# never builds.
test_that("the app refuses a measure table that is missing, older than the class list, from other mapping files, another first term or another build", {
  dir <- withr::local_tempdir()
  edges <- fixture_edges()
  attempts <- attempts_for(test_students, edges)
  attr(attempts, "cedar_dims_fingerprint") <- cedar_dims_fingerprint(test_dims)
  attr(attempts, "cedar_min_term") <- 201980L
  class_list <- file.path(dir, "cedar_students.qs")
  qs2::qs_save(test_students, class_list)
  Sys.setFileTime(class_list, Sys.time() - 3600)
  path <- file.path(dir, "cedar_attempts.qs")
  write_measure <- function(tbl, when = Sys.time()) {
    qs2::qs_save(tbl, path)
    Sys.setFileTime(path, when)
  }
  check <- function(tbl) attempts_is_current(tbl, test_students, edges)
  load <- function(..., fingerprint = cedar_dims_fingerprint(test_dims), min_term = 201980L) {
    cedar_load_measure_table("cedar_attempts", dir, class_list, check, fingerprint, min_term, ext = ".qs")
  }

  expect_error(load(), "has not been built")
  write_measure(attempts, when = Sys.time() - 7200)
  expect_error(load(), "older than the class list")
  write_measure(attempts)
  expect_equal(nrow(load()), nrow(attempts))
  expect_error(load(fingerprint = "000000000000"), "other mapping files")
  expect_error(load(min_term = 201880L), "built over terms from 201980; this app starts at 201880")
  other_edge <- attempts; attr(other_edge, "graded_edge") <- 190080L
  write_measure(other_edge)
  expect_error(load(), "another build, outcome policy, edge or set of course codes")
  # Every refusal names the command that builds the tables.
  expect_error(load(), "--tables measures")
  expect_error(cedar_load_measure_table("cedar_sections", dir, class_list, check, "x", 1L), "not a measure table")
})
