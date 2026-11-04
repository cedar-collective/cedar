# Tests for get_course_demographics function
# Tests R/cones/course-demographics.R
#
# Uses test_students (from fixtures/designed_test_data.R).
#
# Reference values (from designed_test_data.R fixtures):
#   HIST 1110 registered (RE/RS/RR): 27 students across 4 terms
#   HIST courses in students: HIST 1110, HIST 327, HIST 490, HIST 601
#   calc_cl_enrls(HIST): 14 distinct course-term-campus rows

context("Course Demographics")


# =============================================================================
# summarize_student_demographics() tests
# =============================================================================


test_that("summarize_student_demographics groups by student_classification", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% STATUS_REGISTERED)

  opt    <- list(group_cols = c("campus", "college", "term", "term_type",
                                "student_classification", "subject_course"))
  result <- summarize_student_demographics(filtered, opt)

  expect_true("student_classification" %in% names(result))
  # 27 registered HIST 1110 students across all terms
  expect_equal(sum(result$count), 27)
})

test_that("summarize_student_demographics pct sums to 100 per term", {
  filtered <- test_students %>%
    filter(subject_course == "HIST 1110",
           registration_status_code %in% STATUS_REGISTERED)

  opt    <- list(group_cols = c("campus", "college", "term", "term_type",
                                "student_classification", "subject_course"))
  result <- summarize_student_demographics(filtered, opt)

  pct_sums <- result %>%
    group_by(term) %>%
    summarize(total = sum(term_pct), .groups = "drop")

  expect_true(all(abs(pct_sums$total - 100) < 1))
})

test_that("term-type averages include zero-presence offered terms", {
  students <- tibble::tibble(
    student_id = c("A1", "B1", "A2"),
    campus = "ABQ",
    college = "AS",
    term = c(202080L, 202080L, 202180L),
    term_type = "fall",
    subject_course = "HIST 1110",
    major_code = c("A", "B", "A"),
    registration_status_code = "RE"
  )
  result <- summarize_student_demographics(
    students,
    list(group_cols = c(
      "campus", "college", "term", "term_type", "major_code", "subject_course"
    ))
  )

  major_b <- result %>% dplyr::filter(major_code == "B")
  expect_equal(nrow(major_b), 2L)
  expect_setequal(major_b$count, c(0L, 1L))
  expect_true(all(major_b$mean == 0.5))
  expect_true(all(major_b$term_type_pct == 33.3))
})

test_that("plot_time_series uses actual term percentages, not term-type averages", {
  demo <- tibble::tibble(
    campus = "ABQ",
    college = "AS",
    subject_course = "HIST 1110",
    term = c(202080L, 202180L),
    term_type = "fall",
    student_classification = "Freshman",
    count = c(10L, 30L),
    registered = c(100L, 100L),
    term_pct = c(10, 30),
    term_type_pct = c(20, 20)
  )

  built <- suppressWarnings(
    plot_time_series(demo, fill_column = "student_classification") %>%
      plotly::plotly_build()
  )

  expect_equal(as.numeric(built$x$data[[1]]$y), c(10, 30))
})

test_that("multi-campus trend denominators include campuses where a category is absent", {
  demo <- tibble::tibble(
    campus = c("ABQ", "EA"),
    college = "AS",
    subject_course = "HIST 1110",
    term = 202080L,
    term_type = "fall",
    major_code = c("A", "X"),
    count = c(10L, 100L),
    registered = c(100L, 100L),
    term_pct = c(10, 100),
    term_type_pct = c(10, 100)
  )

  built <- suppressWarnings(
    plot_time_series(demo, fill_column = "major_code") %>%
      plotly::plotly_build()
  )
  trace_names <- vapply(built$x$data, function(x) x$name %||% "", character(1))
  a_trace <- built$x$data[[which(trace_names == "A")]]

  expect_equal(as.numeric(a_trace$y), 5)
})


# =============================================================================
# get_course_demographics() tests
# =============================================================================


test_that("get_course_demographics default output includes classification and major columns", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  expect_true("student_classification" %in% names(result))
  expect_true("major_code"             %in% names(result))
})

test_that("get_course_demographics filters to requested course only", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  expect_true(all(result$subject_course == "HIST 1110"))
})

test_that("get_course_demographics total count matches registered students for HIST 1110", {
  result <- get_course_demographics(test_students, list(course = "HIST 1110"))

  # 27 registered (RE/RS/RR) HIST 1110 students in the fixture
  expect_equal(sum(result$count), 27)
})

test_that("get_course_demographics filters by term correctly", {
  result <- get_course_demographics(test_students, list(term = 202010))

  expect_true(all(result$term == 202010))
  expect_gt(nrow(result), 0)
})

test_that("get_course_demographics filters by department correctly", {
  result <- get_course_demographics(test_students, list(dept_code = "HIST"))

  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_setequal(unique(result$term), c(202010, 202060, 202080, 202110))
})

test_that("get_course_demographics excludes early drops from count", {
  # HIST 1120 has both registered and DR (early drop) students
  # Only registered should appear in counts
  hist_1120_reg <- test_students %>%
    filter(subject_course == "HIST 1120",
           registration_status_code %in% STATUS_REGISTERED) %>%
    nrow()

  result <- get_course_demographics(test_students, list(course = "HIST 1120"))
  expect_equal(sum(result$count), hist_1120_reg)
})

test_that("get_course_demographics returns empty data frame for nonexistent course", {
  result <- get_course_demographics(test_students, list(course = "NONEXISTENT 9999"))

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_course_demographics respects custom group_cols", {
  opt <- list(
    course     = "HIST 1110",
    group_cols = c("campus", "college", "term", "term_type",
                   "student_classification", "subject_course")
  )
  result <- get_course_demographics(test_students, opt)

  expect_true("student_classification" %in% names(result))
  expect_false("major_code" %in% names(result))
})

test_that("get_course_demographics combined dept + term filter works", {
  result <- get_course_demographics(test_students, list(dept_code = "HIST", term = 202010))

  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_true(all(result$term == 202010))
})


# =============================================================================
# calc_cl_enrls() tests
# =============================================================================


test_that("calc_cl_enrls returns a row per course for HIST department", {
  filtered <- test_students %>%
    filter(department == "HIST",
           registration_status_code %in% STATUS_REGISTERED)

  result <- calc_cl_enrls(filtered)

  # 14 rows = 4 distinct HIST courses × terms × campus combos
  expect_equal(nrow(result), 14)
  expect_true("HIST 1110" %in% result$subject_course)
  expect_true("HIST 327"  %in% result$subject_course)
})


# =============================================================================
# get_course_major_mix(): each row's major is the student-term table's primary
# major (ADR-001 step 2), named through opt$major_code_to_name (M12)
# =============================================================================

# ST01: ST_A (and six others) hold a HIST programs row in Spring 2020; ST_K has
# no programs row and a roster major of SPAN, which the table carries as the
# class-list primary major. Both took HIST 1110 that term.
.mix_opt <- list(course = "HIST 1110", term = 202010L, min_n = 1L, top_n = 50L)

test_that("get_course_major_mix reads the student-term table's primary major, not the roster", {
  plain <- get_course_major_mix(cedar_students_st, test_student_terms_st, cedar_programs_st, .mix_opt)
  expect_true(all(c("HIST", "SPAN") %in% plain$major_label))
  expect_equal(plain$n_enrollments[plain$major_label == "SPAN"], 1L)
  # One seat per student-course: a student registered twice in the course that
  # term counts once.
  expect_equal(sum(plain$n_enrollments), dplyr::n_distinct(dplyr::filter(
    cedar_students_st, subject_course == "HIST 1110", term == 202010L,
    registration_status_code %in% STATUS_REGISTERED)$student_id))

  # The roster's major is not read: moving every roster major to SPAN changes
  # nothing, because the table still says HIST for the declared students.
  roster <- cedar_students_st
  roster$major_code <- "SPAN"
  expect_equal(get_course_major_mix(roster, test_student_terms_st, cedar_programs_st, .mix_opt), plain)

  # The table is read: blanking ST_K's primary major there moves the seat.
  st <- test_student_terms_st
  st$primary_major_code[st$student_id == "ST_K"] <- NA_character_
  blanked <- get_course_major_mix(cedar_students_st, st, cedar_programs_st, .mix_opt)
  expect_false("SPAN" %in% blanked$major_label)
  expect_equal(blanked$n_enrollments[blanked$major_label == "No major code"], 1L)

  # The pre-major flag is the table's too.
  st <- test_student_terms_st
  st$is_pre_major[st$student_id == "ST_K"] <- TRUE
  pre <- get_course_major_mix(cedar_students_st, st, cedar_programs_st, .mix_opt)
  expect_true("SPAN (pre-major)" %in% pre$major_label)
  expect_false("SPAN" %in% pre$major_label)
})

test_that("get_course_major_mix refuses enrollment rows the student-term table does not cover", {
  st <- dplyr::filter(test_student_terms_st, student_id != "ST_K")
  expect_error(get_course_major_mix(cedar_students_st, st, cedar_programs_st, .mix_opt),
               "no row on cedar_student_terms")
  expect_error(get_course_major_mix(cedar_students_st, dplyr::select(test_student_terms_st, -is_pre_major),
                                    cedar_programs_st, .mix_opt),
               "needs cedar_student_terms")
})

test_that("get_course_major_mix names codes from programs, then opt$major_code_to_name, never a global", {
  # HIST is named by its programs rows (ST01 names it by its code); SPAN has no
  # programs row, so the lookup names it, and without the lookup it is itself.
  # programs first: its name is the mapping file's, with a pre-major's "Pre"
  # taken off, where the class list's lookup keeps it ("Pre Biology (pre-major)").
  named <- get_course_major_mix(cedar_students_st, test_student_terms_st, cedar_programs_st,
                                c(.mix_opt, list(major_code_to_name = c(SPAN = "Spanish", HIST = "Pre History"))))
  expect_true(all(c("Spanish", "HIST") %in% named$major_label))
  expect_false(any(c("SPAN", "Pre History") %in% named$major_label))

  # A global of the same name is not consulted.
  rlang::local_bindings(major_code_to_name = c(SPAN = "Should not appear"), .env = .GlobalEnv)
  ignored <- get_course_major_mix(cedar_students_st, test_student_terms_st, cedar_programs_st, .mix_opt)
  expect_false("Should not appear" %in% ignored$major_label)
  expect_true("SPAN" %in% ignored$major_label)
})
