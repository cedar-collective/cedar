context("Course Flow Branch")

test_that("next-course pairs are campus-scoped and campus-filterable", {
  pairs_all <- get_next_course_pairs(
    test_students,
    opt = list(summer = FALSE)
  )

  expect_true("campus" %in% names(pairs_all))
  expect_true("source_course" %in% names(pairs_all))
  expect_true("dest_course" %in% names(pairs_all))
  expect_true(nrow(pairs_all) > 0)

  campus_scope <- pairs_all$campus[[1]]
  source_course <- pairs_all$source_course[[1]]
  pairs_scoped <- get_next_course_pairs(
    test_students,
    opt = list(course = source_course, campus = campus_scope, summer = FALSE)
  )

  expect_true(nrow(pairs_scoped) > 0)
  expect_setequal(unique(pairs_scoped$campus), campus_scope)
})

test_that("destination and feeder summaries retain campus grouping", {
  pairs <- get_next_course_pairs(test_students, opt = list(summer = FALSE))
  source_course <- pairs$source_course[[1]]
  target_course <- pairs$dest_course[[1]]

  destinations <- get_course_destinations(
    test_students,
    opt = list(course = source_course, summer = FALSE)
  )
  feeders <- get_course_feeders(
    test_students,
    opt = list(course = target_course, summer = FALSE)
  )

  expect_true("campus" %in% names(destinations))
  expect_true("campus" %in% names(feeders))
  expect_false(any(is.na(destinations$campus)))
  expect_false(any(is.na(feeders$campus)))
})

test_that("concurrent course summaries keep student classification", {
  base_row <- test_students %>%
    dplyr::arrange(student_id, term, subject_course) %>%
    dplyr::slice(1)
  source_course <- base_row$subject_course[[1]]
  campus_scope <- base_row$campus[[1]]
  companion_row <- base_row %>%
    dplyr::mutate(
      subject_course = "TEST 999",
      subject_code = "TEST",
      course_title = "Concurrent Fixture Course"
    )
  students_with_concurrent <- dplyr::bind_rows(test_students, companion_row)

  concurrent <- get_concurrent_courses(
    students_with_concurrent,
    opt = list(course = source_course, campus = campus_scope)
  )

  # No classification split: the loaded class list carries none, and the
  # summary collapsed it (ADR-001 step 5).
  expect_false("student_classification" %in% names(concurrent))
  expect_true(nrow(concurrent) > 0)
  expect_true("TEST 999" %in% concurrent$subject_course)
})

test_that("concurrent course shares use every selected-course student-term", {
  students <- tibble::tribble(
    ~student_id, ~term, ~subject_course, ~campus, ~college, ~term_type, ~student_classification, ~registration_status_code,
    "s1", 202010L, "TEST 100", "ABQ", "TEST", "spring", "Freshman", "RE",
    "s1", 202010L, "TEST 200", "ABQ", "TEST", "spring", "Freshman", "RE",
    "s2", 202010L, "TEST 100", "ABQ", "TEST", "spring", "Freshman", "RE",
    "s2", 202010L, "TEST 200", "ABQ", "TEST", "spring", "Freshman", "RE",
    "s3", 202010L, "TEST 100", "ABQ", "TEST", "spring", "Sophomore", "RE",
    "s3", 202010L, "TEST 300", "ABQ", "TEST", "spring", "Sophomore", "RE",
    "s4", 202080L, "TEST 100", "ABQ", "TEST", "fall", "Sophomore", "RE",
    "s4", 202080L, "TEST 400", "ABQ", "TEST", "fall", "Sophomore", "WL"
  )

  concurrent <- get_concurrent_courses(
    students,
    opt = list(course = "TEST 100", campus = "ABQ")
  )
  summary <- summarize_concurrent_courses(concurrent)

  test_200 <- summary %>% dplyr::filter(subject_course == "TEST 200")
  expect_equal(test_200$coenrolled_student_terms, 2L)
  expect_equal(test_200$target_student_terms, 4L)
  expect_equal(test_200$target_terms, 2L)
  expect_equal(test_200$avg_students_per_target_term, 1)
  expect_equal(test_200$pct_selected_student_terms, 50)
  expect_false("TEST 400" %in% summary$subject_course)

  treemap <- plot_concurrent_course_treemap(summary, list(max_courses = 20L))
  expect_s3_class(treemap, "plotly")
})

test_that("old course-neighbor function names are intentionally unavailable", {
  expect_false(exists("where_to", mode = "function"))
  expect_false(exists("where_from", mode = "function"))
  expect_false(exists("where_at", mode = "function"))
  expect_false(exists("get_course_neighbors", mode = "function"))
})

test_that("course report flow tab returns sankey plots from branch outputs", {
  pairs <- get_next_course_pairs(test_students, opt = list(summer = FALSE))
  source_course <- pairs$source_course[[1]]
  campus_scope <- pairs$campus[[1]]
  old_base <- cedar_base_dir
  tmp_base <- tempfile("cedar-course-flow-cache-")
  dir.create(file.path(tmp_base, "data"), recursive = TRUE)
  assign("cedar_base_dir", tmp_base, envir = .GlobalEnv)
  on.exit(assign("cedar_base_dir", old_base, envir = .GlobalEnv), add = TRUE)

  payload <- compute_cr_flows_tab(
    base = list(
      opt = list(
        course = source_course,
        course_campus = campus_scope
      )
    ),
    data_objects = list(
      cedar_students = test_students,
      cedar_sections = test_sections,
      cedar_edges = list(
        last_enrolled = max(test_students$term),
        last_enrolled_complete = max(test_students$term),
        last_graded = max(test_students$term)
      )
    ),
    min_contrib = 1,
    max_courses = 6
  )

  expect_named(payload, c("plots", "tables"))
  sankey_names <- names(payload$plots)[grepl("^sankey_.*_plot$", names(payload$plots))]
  expect_true(length(sankey_names) > 0)
  expect_true("concurrent_courses" %in% names(payload$tables))
})

test_that("the start-up course flows stop at the longitudinal edge (ADR-001 step 4)", {
  unbounded <- get_next_course_pairs(test_students, opt = list(summer = FALSE))
  # The edge is the last term before the newest destination term, so the
  # pairs into that term are past it: the shape of a registration still open.
  next_terms <- sort(unique(unbounded$next_term))
  terms <- sort(unique(test_students$term))
  edge <- max(terms[terms < max(next_terms)])
  edges <- list(last_enrolled_complete = edge)
  expect_gt(sum(unbounded$next_term > edge), 0L)

  flows <- build_course_flows(test_students, edges)
  expect_true(all(flows$next_term <= edge))
  expected <- dplyr::filter(unbounded, next_term <= edge)
  expect_equal(nrow(flows), nrow(expected))
  expect_equal(sum(flows$n_students), sum(expected$n_students))
  expect_identical(attr(flows, "enrolled_edge"), as.integer(edge))
  expect_identical(attr(flows, "code_renames"), course_code_renames(test_students))

  # A saved copy is read only for this build, this edge and these codes.
  expect_true(course_flows_is_current(flows, test_students, edges))
  expect_false(course_flows_is_current(flows, test_students,
                                       list(last_enrolled_complete = max(next_terms))))
  stale <- flows
  attr(stale, "course_flows_build_version") <- COURSE_FLOWS_BUILD_VERSION - 1L
  expect_false(course_flows_is_current(stale, test_students, edges))
  recoded <- flows
  attr(recoded, "code_renames") <- c(attr(flows, "code_renames"), "SOC 371 -> SOCI 371")
  expect_false(course_flows_is_current(recoded, test_students, edges))
  expect_false(course_flows_is_current(NULL, test_students, edges))
  expect_error(build_course_flows(test_students, list()), "last_enrolled_complete")
})

test_that("Regstats' downstream signals read the flows they are given", {
  # The fixture settles no term (its edges carry no last_enrolled_complete),
  # so the edge is given, as the other follow-up tests give theirs.
  flows <- build_course_flows(test_students, list(last_enrolled_complete = max(test_students$term)))
  unstamped <- flows
  attr(unstamped, "enrolled_edge") <- NULL
  expect_error(get_next_term_signals(list(), NULL), "build_course_flows")
  expect_error(get_next_term_signals(list(), unstamped), "build_course_flows")
  expect_error(get_downstream_course_flows("HIST 1110", NULL), "build_course_flows")

  # The source course with the most next-term students: a bump there names
  # only destinations its own flows hold, and the page is told the edge.
  source <- flows %>% dplyr::count(source_course, wt = n_students, sort = TRUE) %>%
    dplyr::slice(1) %>% dplyr::pull(source_course)
  signals <- get_next_term_signals(list(bumps = tibble::tibble(subject_course = source)), flows)
  expect_identical(signals$enrolled_edge, attr(flows, "enrolled_edge"))
  expect_true(all(signals$downstream$dest_course %in%
                    flows$dest_course[flows$source_course == source]))
  expect_equal(nrow(get_downstream_course_flows(source, flows)),
               sum(flows$source_course == source))
})
