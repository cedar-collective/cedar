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
  result <- summarize_student_demographics(filtered, test_student_terms, test_course_terms, opt)

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
  result <- summarize_student_demographics(filtered, test_student_terms, test_course_terms, opt)

  pct_sums <- result %>%
    group_by(term) %>%
    summarize(total = sum(term_pct), .groups = "drop")

  expect_true(all(abs(pct_sums$total - 100) < 1))
})

test_that("term-type averages include zero-presence offered terms", {
  # HIST 1110 on ABQ ran in Spring 2020 (21 registered) and Spring 2021 (2).
  # Give one Spring 2020 student major B and everyone else major A: B is
  # present in one of the two springs, so its typical-spring count averages
  # over both (0.5), against the course's typical spring enrollment (11.5).
  roster <- test_students %>%
    filter(subject_course == "HIST 1110", registration_status_code %in% STATUS_REGISTERED,
           term %in% c(202010L, 202110L))
  one <- roster %>% filter(term == 202010L) %>% slice(1)
  student_terms <- test_student_terms %>%
    mutate(primary_major_code = if_else(student_id == one$student_id & term == 202010L, "B", "A"))
  result <- summarize_student_demographics(
    roster, student_terms, test_course_terms,
    list(group_cols = c("campus", "college", "term", "term_type", "major_code", "subject_course"))
  )
  springs <- test_course_terms %>%
    filter(subject_course == "HIST 1110", campus == "ABQ", term %in% c(202010L, 202110L),
           !is.na(registered))
  expect_equal(sort(springs$registered), c(2L, 21L))
  major_b <- result %>% dplyr::filter(major_code == "B")
  expect_equal(nrow(major_b), 2L)
  expect_setequal(major_b$count, c(0L, 1L))
  expect_true(all(major_b$mean == 0.5))
  expect_equal(unique(major_b$registered_mean), mean(springs$registered))
  expect_true(all(major_b$term_type_pct == round(0.5 / mean(springs$registered) * 100, 1)))
  # The denominator is the table's, not a recount of the rows handed in: a
  # roster cut to one student still reports the course's enrollment.
  cut <- summarize_student_demographics(
    one, student_terms, test_course_terms,
    list(group_cols = c("campus", "college", "term", "term_type", "major_code", "subject_course"))
  )
  expect_equal(cut$registered, 21L)
  expect_equal(cut$term_pct, round(1 / 21 * 100, 1))
  # Rows the table has no count for are refused, never given a denominator.
  expect_error(
    summarize_student_demographics(
      roster %>% mutate(subject_course = "HIST 9999"), student_terms, test_course_terms,
      list(group_cols = c("campus", "college", "term", "term_type", "major_code", "subject_course"))),
    "no registered count in cedar_course_terms")
  expect_error(
    summarize_student_demographics(roster, student_terms, calc_cl_enrls(roster, by_part_term = TRUE),
      list(group_cols = c("campus", "college", "term", "term_type", "major_code", "subject_course"))),
    "build_course_terms")
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


# -----------------------------------------------------------------------------
# Who a student is comes from cedar_student_terms (ADR-001 step 2). The fixture
# table describes every HIST 1110 registered student-term as a Sophomore with
# no primary major (the roster's major_code is NA too); the tests below stamp
# the table and the roster separately to show which one the summary reads.
# -----------------------------------------------------------------------------

test_that("classification is read off the student-term table, not the course row", {
  # Roster says Senior everywhere; the table still says Sophomore.
  relabelled_roster <- .hist_1110_registered %>%
    mutate(student_classification = "Senior")
  result <- summarize_student_demographics(relabelled_roster, test_student_terms, test_course_terms, .class_opt)
  expect_setequal(unique(result$student_classification), "Sophomore")
  expect_equal(sum(result$count), 27)

  # Move one student-term to Junior on the table: the summary follows the table.
  one <- .hist_1110_registered %>% distinct(student_id, term) %>% slice(1)
  relabelled_table <- test_student_terms %>%
    mutate(student_classification = if_else(
      student_id == one$student_id & term == one$term, "Junior", student_classification))
  result <- summarize_student_demographics(.hist_1110_registered, relabelled_table, test_course_terms, .class_opt)
  junior <- result %>% filter(student_classification == "Junior", count > 0)
  expect_equal(nrow(junior), 1L)
  expect_equal(junior$term, one$term)
  expect_equal(junior$count, 1L)
  expect_equal(sum(result$count), 27)
})

test_that("major_code is the student-term table's primary_major_code", {
  stamped_roster <- .hist_1110_registered %>% mutate(major_code = "ROSTER")
  stamped_table <- test_student_terms %>%
    mutate(primary_major_code = if_else(
      student_id %in% stamped_roster$student_id, "HIST-BA", primary_major_code))
  result <- summarize_student_demographics(stamped_roster, stamped_table, test_course_terms, .major_opt)
  expect_setequal(unique(result$major_code), "HIST-BA")
  expect_equal(sum(result$count), 27)
  expect_false("primary_major_code" %in% names(result))
})

test_that("a grouping that describes the student needs the table and every row on it", {
  expect_error(
    summarize_student_demographics(.hist_1110_registered, NULL, test_course_terms, .class_opt),
    "reads cedar_student_terms"
  )
  expect_error(
    summarize_student_demographics(.hist_1110_registered,
                                   select(test_student_terms, -student_classification),
                                   test_course_terms, .class_opt),
    "missing required column"
  )
  one <- .hist_1110_registered %>% distinct(student_id, term) %>% slice(1)
  short_table <- test_student_terms %>%
    filter(!(student_id == one$student_id & term == one$term))
  expect_error(
    summarize_student_demographics(.hist_1110_registered, short_table, test_course_terms, .class_opt),
    "1 enrollment rows have no row on cedar_student_terms"
  )
})

test_that("a grouping with no student description reads no table", {
  opt <- list(group_cols = c("campus", "college", "term", "term_type", "subject_course"))
  result <- summarize_student_demographics(.hist_1110_registered, NULL, test_course_terms, opt)
  expect_equal(sum(result$count), 27)
})


# =============================================================================
# get_course_demographics() tests
# =============================================================================


test_that("get_course_demographics default output includes classification and major columns", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(course = "HIST 1110"))

  expect_true("student_classification" %in% names(result))
  expect_true("major_code"             %in% names(result))
})

test_that("get_course_demographics filters to requested course only", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(course = "HIST 1110"))

  expect_true(all(result$subject_course == "HIST 1110"))
})

test_that("get_course_demographics total count matches registered students for HIST 1110", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(course = "HIST 1110"))

  # 27 registered (RE/RS/RR) HIST 1110 students in the fixture
  expect_equal(sum(result$count), 27)
})

test_that("get_course_demographics filters by term correctly", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(term = 202010))

  expect_true(all(result$term == 202010))
  expect_gt(nrow(result), 0)
})

test_that("get_course_demographics filters by department correctly", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(dept_code = "HIST"))

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

  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(course = "HIST 1120"))
  expect_equal(sum(result$count), hist_1120_reg)
})

test_that("get_course_demographics returns empty data frame for nonexistent course", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(course = "NONEXISTENT 9999"))

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_course_demographics respects custom group_cols", {
  opt <- list(
    course     = "HIST 1110",
    group_cols = c("campus", "college", "term", "term_type",
                   "student_classification", "subject_course")
  )
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, opt)

  expect_true("student_classification" %in% names(result))
  expect_false("major_code" %in% names(result))
})

test_that("get_course_demographics combined dept + term filter works", {
  result <- get_course_demographics(test_students, test_student_terms, test_course_terms, list(dept_code = "HIST", term = 202010))

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
# major (ADR-001 step 2), named through the dimension tables (programs.csv)
# =============================================================================

# ST01: ST_A (and six others) hold a HIST programs row in Spring 2020; ST_K has
# no programs row and a roster major of SPAN, which the table carries as the
# class-list primary major. Both took HIST 1110 that term. The demo
# institution's programs.csv (test_dims) names HIST "History" and SPAN "Spanish".

test_that("get_course_major_mix reads the student-term table's primary major, not the roster", {
  plain <- get_course_major_mix(cedar_registrations_st, test_student_terms_st, test_dims, .mix_opt)
  expect_true(all(c("History", "Spanish") %in% plain$major_label))
  expect_equal(plain$n_enrollments[plain$major_label == "Spanish"], 1L)
  # One seat per student-course: a student registered twice in the course that
  # term counts once.
  expect_equal(sum(plain$n_enrollments), dplyr::n_distinct(dplyr::filter(
    cedar_registrations_st, subject_course == "HIST 1110", term == 202010L,
    registration_status_code %in% STATUS_REGISTERED)$student_id))

  # The roster's major is not read: moving every roster major to SPAN changes
  # nothing, because the table still says HIST for the declared students.
  roster <- cedar_registrations_st
  roster$major_code <- "SPAN"
  expect_equal(get_course_major_mix(roster, test_student_terms_st, test_dims, .mix_opt), plain)

  # The table is read: blanking ST_K's primary major there moves the seat.
  st <- test_student_terms_st
  st$primary_major_code[st$student_id == "ST_K"] <- NA_character_
  blanked <- get_course_major_mix(cedar_registrations_st, st, test_dims, .mix_opt)
  expect_false("Spanish" %in% blanked$major_label)
  expect_equal(blanked$n_enrollments[blanked$major_label == "No major code"], 1L)

  # The pre-major flag is the table's too.
  st <- test_student_terms_st
  st$is_pre_major[st$student_id == "ST_K"] <- TRUE
  pre <- get_course_major_mix(cedar_registrations_st, st, test_dims, .mix_opt)
  expect_true("Spanish (pre-major)" %in% pre$major_label)
  expect_false("Spanish" %in% pre$major_label)
})

test_that("get_course_major_mix refuses enrollment rows the student-term table does not cover", {
  st <- dplyr::filter(test_student_terms_st, student_id != "ST_K")
  expect_error(get_course_major_mix(cedar_registrations_st, st, test_dims, .mix_opt),
               "no row on cedar_student_terms")
  expect_error(get_course_major_mix(cedar_registrations_st, dplyr::select(test_student_terms_st, -is_pre_major),
                                    test_dims, .mix_opt),
               "needs cedar_student_terms")
})

test_that("get_course_major_mix names codes from programs.csv alone, never from the data or a global", {
  # The file's name is the label, whatever the programs table or the roster
  # calls the code: ST01's programs rows name HIST by its code, the roster
  # names SPAN "Spanish", and the label is the file's for both.
  renamed <- test_dims
  renamed$programs$program_name[renamed$programs$program_code == "HIST"] <- "History of Everything"
  named <- get_course_major_mix(cedar_registrations_st, test_student_terms_st,
                                validate_cedar_dims(renamed), .mix_opt)
  expect_true("History of Everything" %in% named$major_label)
  expect_false("HIST" %in% named$major_label)

  # A code the file does not carry is itself, and the mapping audit lists it;
  # neither the roster's name nor a global of the retired lookup's name is read.
  without_span <- test_dims
  without_span$programs <- without_span$programs[without_span$programs$program_code != "SPAN", ]
  rlang::local_bindings(major_code_to_name = c(SPAN = "Should not appear"), .env = .GlobalEnv)
  unnamed <- get_course_major_mix(cedar_registrations_st, test_student_terms_st,
                                  validate_cedar_dims(without_span), .mix_opt)
  expect_true("SPAN" %in% unnamed$major_label)
  expect_false(any(c("Spanish", "Should not appear") %in% unnamed$major_label))

  # The dimension tables are required; the programs table is not a substitute.
  expect_error(get_course_major_mix(cedar_registrations_st, test_student_terms_st, cedar_programs_st, .mix_opt),
               "build_cedar_dims")
})
