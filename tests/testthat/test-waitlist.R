# Tests for waitlist analysis functions
# Tests get_unique_waitlisted() and inspect_waitlist()

context("Waitlist Analysis")

test_that("get_unique_waitlisted identifies waitlisted students correctly", {
  message("\n  Testing get_unique_waitlisted basic functionality...")

  # Create test data with waitlisted and registered students
  test_waitlist_data <- data.frame(
    campus = rep("ABQ", 6),
    term = rep(202310, 6),
    subject_course = rep("MATH 1430", 6),
    course_title = rep("Applications of Calculus I", 6),
    student_id = c("S001", "S002", "S003", "S004", "S005", "S006"),
    registration_status = c(
      "Wait Listed", "Wait Listed", "Wait Listed",
      "Student Registered", "Student Registered", "Wait Listed"
    ),
    stringsAsFactors = FALSE
  )

  # S001, S002, S003 are waitlisted only
  # S004, S005 are registered
  # S006 is also waitlisted

  # Filter to just waitlisted
  waitlisted_only <- test_waitlist_data %>% filter(registration_status == "Wait Listed")

  result <- get_unique_waitlisted(test_waitlist_data, list())

  message("  Result has ", nrow(result), " rows")
  message("  Columns: ", paste(colnames(result), collapse = ", "))

  expect_s3_class(result, "data.frame")
  expect_true("campus" %in% colnames(result))
  expect_true("subject_course" %in% colnames(result))
  expect_true("count" %in% colnames(result))
  expect_equal(nrow(result), 1) # One course
  expect_equal(result$count[1], 4) # 4 waitlisted students total
})

test_that("get_unique_waitlisted excludes students who are also registered", {
  message("\n  Testing waitlist exclusion logic...")

  # Create test data where some students are both waitlisted AND registered
  test_data <- data.frame(
    campus = rep("ABQ", 8),
    term = rep(202310, 8),
    subject_course = c(rep("MATH 1430", 4), rep("MATH 1430", 4)),
    course_title = rep("Applications of Calculus I", 8),
    student_id = c("S001", "S002", "S001", "S002", "S003", "S004", "S003", "S005"),
    registration_status = c(
      "Wait Listed", "Wait Listed", "Student Registered", "Student Registered",
      "Wait Listed", "Wait Listed", "Student Registered", "Wait Listed"
    ),
    stringsAsFactors = FALSE
  )

  # S001: waitlisted AND registered (should be excluded from count)
  # S002: waitlisted AND registered (should be excluded from count)
  # S003: waitlisted AND registered (should be excluded from count)
  # S004: waitlisted only (should be counted)
  # S005: waitlisted only (should be counted)

  result <- get_unique_waitlisted(test_data, list())

  message("  Only waitlisted count: ", result$count[1])

  expect_equal(result$count[1], 2) # Only S004 and S005
})

test_that("shared waitlist demand preserves title and part-of-term grain", {
  students <- tibble::tibble(
    campus = "ABQ", college = "ARTS", term = 202580L,
    part_term = c("1", "1", "1", "2", "2"),
    subject_course = "TOP 399", course_title = c("A", "A", "B", "A", "A"),
    student_id = c("S1", "S1", "S1", "S2", "S2"),
    registration_status_code = c("WL", "RE", "WL", "WL", "WL")
  )

  demand <- get_true_waitlisted_rows(students) %>% summarize_waitlist_courses()

  # S1's registered seat removes the matching title-A waitlist, but not the
  # title-B waitlist. S2's duplicate part-term-2 rows count once.
  expect_equal(nrow(demand), 2L)
  expect_equal(demand$course_title, c("B", "A"))
  expect_equal(demand$part_term, c("1", "2"))
  expect_equal(demand$count, c(1L, 1L))
})

test_that("linked waitlist demand can retain one course-title group", {
  students <- tibble::tibble(
    campus = "ABQ", college = "ARTS", term = 202580L, part_term = "1",
    subject_course = "TOP 399", course_title = c("Topic A", "Topic A", "Topic B"),
    student_id = c("S1", "S1", "S2"),
    registration_status_code = "WL"
  )

  demand <- get_classlist_waitlist_demand(
    students,
    list(term = 202580L, course = "TOP 399", course_title = "Topic A", uel = FALSE),
    group_cols = c("campus", "college", "term", "part_term",
                   "subject_course", "course_title"),
    count_name = "waiting"
  )

  expect_equal(nrow(demand), 1L)
  expect_equal(demand$course_title, "Topic A")
  expect_equal(demand$waiting, 1L)
})

test_that("get_unique_waitlisted handles multiple campuses and courses", {
  message("\n  Testing multiple campuses and courses...")

  test_data <- data.frame(
    campus = c(rep("ABQ", 6), rep("TAOS", 4)),
    term = rep(202310, 10),
    subject_course = c(rep("MATH 1430", 6), rep("BIOL 1110", 4)),
    course_title = c(rep("Calculus I", 6), rep("Biology I", 4)),
    student_id = paste0("S", sprintf("%03d", 1:10)),
    registration_status = c(
      "Wait Listed", "Wait Listed", "Student Registered",
      "Wait Listed", "Student Registered", "Wait Listed",
      "Wait Listed", "Wait Listed", "Registered", "Wait Listed"
    ),
    stringsAsFactors = FALSE
  )

  result <- get_unique_waitlisted(test_data, list())

  message("  Result has ", nrow(result), " campus-course combinations")
  message("  Campuses: ", paste(unique(result$campus), collapse = ", "))
  message("  Courses: ", paste(unique(result$subject_course), collapse = ", "))

  expect_gte(nrow(result), 1)
  expect_true(all(c("campus", "subject_course", "count") %in% colnames(result)))
})

test_that("get_unique_waitlisted handles empty waitlist", {
  message("\n  Testing empty waitlist handling...")

  test_data <- data.frame(
    campus = rep("ABQ", 3),
    term = rep(202310, 3),
    subject_course = rep("MATH 1430", 3),
    course_title = rep("Calculus I", 3),
    student_id = paste0("S", 1:3),
    registration_status = rep("Student Registered", 3),
    stringsAsFactors = FALSE
  )

  result <- get_unique_waitlisted(test_data, list())

  message("  Empty waitlist result has ", nrow(result), " rows (should be 0)")
  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_unique_waitlisted handles all waitlisted (no registered)", {
  message("\n  Testing all-waitlisted scenario...")

  test_data <- data.frame(
    campus = rep("ABQ", 5),
    term = rep(202310, 5),
    subject_course = rep("MATH 1430", 5),
    course_title = rep("Calculus I", 5),
    student_id = paste0("S", 1:5),
    registration_status = rep("Wait Listed", 5),
    stringsAsFactors = FALSE
  )

  result <- get_unique_waitlisted(test_data, list())

  message("  All waitlisted count: ", result$count[1])
  expect_equal(result$count[1], 5) # All 5 students waitlisted
})

test_that("get_unique_waitlisted uses correct CEDAR column names", {
  message("\n  Testing CEDAR column name usage...")

  test_data <- data.frame(
    campus = "ABQ",
    term = 202310,
    subject_course = "MATH 1430",
    course_title = "Calculus I",
    student_id = "S001",
    registration_status = "Wait Listed",
    stringsAsFactors = FALSE
  )

  # Should not error with CEDAR column names
  result <- get_unique_waitlisted(test_data, list())

  expect_s3_class(result, "data.frame")
  expect_true("campus" %in% colnames(result))
  expect_true("subject_course" %in% colnames(result))
  message("  CEDAR column names working correctly")
})

test_that("inspect_waitlist structure is correct", {
  message("\n  Testing inspect_waitlist structure...")

  expect_true(exists("inspect_waitlist"))

  # Function should take students, opt, an optional sections table (only needed
  # when students lack a course_title column), an optional precomputed
  # enrollment base (M12: never looked up by name) and the student-term table
  # that describes each waiting student.
  args <- formals(inspect_waitlist)
  expect_equal(names(args), c("students", "opt", "sections", "enrl_base", "student_terms"))

  message("  inspect_waitlist function signature verified")
})

test_that("inspect_waitlist course overview reports college and section supply", {
  message("\n  Testing inspect_waitlist course-overview supply columns...")

  # Real fixtures: NURS 2010 202080 has a full section (S80010, enrolled 24) with
  # 28 waitlisted students (registration_status_code WL). See the waitlist design
  # block in fixtures/designed_test_data.R.
  opt <- create_test_opt(list(term = 202080, uel = FALSE))
  out <- inspect_waitlist(test_students, opt, sections = test_sections, student_terms = test_student_terms)

  cnt <- out[["count"]]
  expect_true(all(c("campus", "college", "subject_course", "course_title",
                    "count", "n_sections", "avg_size", "sections_needed")
                  %in% names(cnt)))

  nurs <- cnt %>% filter(subject_course == "NURS 2010", campus == "ABQ")
  message("  NURS 2010 overview: ", paste(colnames(nurs), collapse = ", "))

  expect_equal(nrow(nurs), 1)
  expect_equal(nurs$college, "NURS")          # college column (from get_unique_waitlisted)
  expect_equal(nurs$count, 28L)               # unique waitlisted students
  expect_equal(nurs$n_sections, 1L)           # one active NURS 2010 section in 202080
  expect_equal(nurs$avg_size, 24)             # S80010 enrolled
  expect_equal(nurs$sections_needed, 2L)      # ceiling(28 / 24)

  # Enrollment-context columns are attached (values may be sparse in this
  # waitlist-focused fixture; attach_enrollment_history has its own value test).
  expect_true(all(c("census_enrl", "census_enrl_mean", "n_hist_terms",
                    "trend_hist", "trend_terms") %in% names(cnt)))
  expect_true(is.list(cnt$trend_hist))
})

test_that("inspect_waitlist excludes registered overlap from every summary", {
  opt <- create_test_opt(list(term = 202080, uel = FALSE))
  out <- inspect_waitlist(test_students, opt, sections = test_sections, student_terms = test_student_terms)

  course_count <- out$count %>%
    filter(subject_course == "NURS 2010", campus == "ABQ")
  program_count <- out$majors %>%
    filter(subject_course == "NURS 2010", campus == "ABQ")
  classification_count <- out$classifications %>%
    filter(subject_course == "NURS 2010", campus == "ABQ")

  # Fixture carries 28 waitlist-only students plus one student with both WL and
  # RE rows. Every view must describe the same 28-student true-demand population.
  expect_equal(course_count$count, 28L)
  expect_equal(sum(program_count$count), 28L)
  expect_equal(sum(classification_count$count), 28L)
  expect_named(
    out$majors,
    c("campus", "term", "major_code", "subject_course", "course_title", "count", "former_codes")
  )
  expect_named(
    out$classifications,
    c("campus", "term", "student_classification", "subject_course", "course_title", "count",
      "former_codes")
  )
})

test_that("inspect_waitlist describes waiting students from the student-term table", {
  opt <- create_test_opt(list(term = 202080, uel = FALSE))
  waiting <- test_students %>%
    filter(subject_course == "NURS 2010", registration_status_code == "WL")

  # The roster's own major and classification are never read: stamp them with
  # values the table does not carry and the splits still show the table's.
  roster <- test_students %>%
    mutate(major_code = if_else(student_id %in% waiting$student_id, "ROSTER", major_code),
           student_classification = if_else(student_id %in% waiting$student_id,
                                            "Roster Class", student_classification))
  table <- test_student_terms %>%
    mutate(primary_major_code = if_else(student_id %in% waiting$student_id & term == 202080L,
                                        "NURS-BSN", primary_major_code))
  out <- inspect_waitlist(roster, opt, sections = test_sections, student_terms = table)

  majors <- out$majors %>% filter(subject_course == "NURS 2010", campus == "ABQ")
  expect_setequal(unique(majors$major_code), "NURS-BSN")
  expect_equal(sum(majors$count), 28L)
  classes <- out$classifications %>% filter(subject_course == "NURS 2010", campus == "ABQ")
  expect_false("Roster Class" %in% classes$student_classification)
  expect_equal(sum(classes$count), 28L)

  expect_error(
    inspect_waitlist(test_students, opt, sections = test_sections),
    "reads cedar_student_terms"
  )
})

test_that("Waitlists, Regstats, and Department Dashboard reconcile true demand", {
  wait_opt <- create_test_opt(list(
    term = 202080L, course = "NURS 2010", course_campus = "ABQ",
    dept_code = "NURS", uel = TRUE
  ))
  waitlists <- inspect_waitlist(test_students, wait_opt, sections = test_sections, student_terms = test_student_terms)$count %>%
    filter(subject_course == "NURS 2010") %>%
    transmute(campus, college, term, part_term, subject_course, course_title,
              waiting = count)

  reg_opt <- wait_opt
  reg_opt$thresholds <- modifyList(cedar_regstats_thresholds, list(min_wait = 28))
  regstats <- get_reg_stats(test_students, test_sections, reg_opt)$waits %>%
    filter(subject_course == "NURS 2010") %>%
    select(all_of(names(waitlists)))

  course_history <- get_enrl(test_sections, list(
    dept_code = "NURS", status = "A", crosslist = "home", uel = TRUE,
    course_campus = "ABQ",
    group_cols = c("subject_course", "course_title", "campus", "term")
  )) %>% ungroup() %>% filter(enrolled > 0)
  dashboard_flags <- get_dashboard_enrollment_flags(
    test_sections, course_history, "NURS", 202080L, campus = "ABQ",
    cedar_students = test_students
  )
  dashboard <- dashboard_flags$high_waitlist %>%
    filter(subject_course == "NURS 2010") %>%
    select(all_of(names(waitlists)))

  expect_equal(waitlists$waiting, 28L)
  expect_equal(regstats, waitlists)
  expect_equal(dashboard, waitlists)
  expect_identical(dashboard_flags$waitlist_info$source, "classlist_true_demand")

  # Inclusive minimum: exactly 28 clears Min Waiting = 28.
  expect_equal(regstats$waiting, 28L)
})

test_that("waitlist definition v3 follows the course and names the dashboard's lag", {
  definition <- cedar_definition("waitlist")
  expect_identical(definition$version, "3.0.0")
  expect_match(definition$summary, "followed across the codes it has carried", fixed = TRUE)
  expect_match(definition$numerator, "holds a seat in the course", fixed = TRUE)
  expect_match(definition$exclusions, "RE/RS/RR", fixed = TRUE)
  expect_true(any(grepl("Department Dashboard still matches by course code",
                        definition$limitations, fixed = TRUE)))
})

test_that("inspect_waitlist requires sections when course titles are absent", {
  students_without_titles <- test_students %>%
    select(-course_title)
  opt <- create_test_opt(list(term = 202080, uel = FALSE))

  expect_error(
    inspect_waitlist(students_without_titles, opt, student_terms = test_student_terms),
    "input has no course_title column and no sections table was supplied",
    fixed = TRUE
  )
})

test_that("enrollment history scope drops unrelated courses but keeps all terms", {
  enrl_base <- calc_cl_enrls(test_students, by_part_term = TRUE)
  focal_row <- test_students %>%
    filter(subject_course == "HIST 1110") %>%
    slice(1) %>%
    transmute(campus, college, term, part_term, subject_course, course_title, count = 1L)

  scoped <- scope_waitlist_enrollment_base(enrl_base, focal_row)
  expected <- enrl_base %>%
    filter(campus == focal_row$campus,
           college == focal_row$college,
           subject_course == focal_row$subject_course,
           (is.na(part_term) & is.na(focal_row$part_term)) | part_term == focal_row$part_term)

  expect_equal(unique(scoped$data$subject_course), "HIST 1110")
  expect_equal(sort(unique(scoped$data$term)), sort(unique(expected$term)))
  expect_equal(nrow(scoped$data), nrow(expected))
  expect_lt(nrow(scoped$data), nrow(enrl_base))
})

test_that("attach_enrollment_history adds census enrollment context", {
  message("\n  Testing attach_enrollment_history census enrollment context...")

  # Three fall offerings of one course, with late drops so census enrollment
  # (registered + late drops) differs from the still-registered count:
  #   202080: 2 RE + 1 DW → census 3
  #   202180: 4 RE        → census 4
  #   202280: 6 RE + 2 DW (+3 WL, viewed term) → census 8
  mk <- function(term, n_re, n_wl = 0, n_dw = 0) {
    tibble::tibble(
      campus = "ABQ", college = "ARTS", term = as.integer(term),
      subject_course = "WLST 1000", course_id = "WLST 1000", part_term = "1", term_type = "fall",
      student_id = paste0("S", term, "_", seq_len(n_re + n_wl + n_dw)),
      registration_status_code = c(rep("RE", n_re), rep("WL", n_wl), rep("DW", n_dw))
    )
  }
  students <- dplyr::bind_rows(mk(202080, 2, n_dw = 1), mk(202180, 4),
                               mk(202280, 6, n_wl = 3, n_dw = 2))

  # Course overview row for the viewed (latest) term, as get_unique_waitlisted builds it.
  count_df <- tibble::tibble(
    campus = "ABQ", college = "ARTS", term = 202280L, part_term = "1",
    subject_course = "WLST 1000", course_title = "Waitlist Studies", count = 3L
  )

  res <- attach_enrollment_history(count_df, students)

  expect_equal(res$census_enrl, 8)                      # census this term (6 RE + 2 DW)
  expect_equal(res$census_enrl_mean, 3.5)               # mean(3, 4), viewed term excluded
  expect_equal(res$n_hist_terms, 2L)                    # two prior same-type terms
  expect_equal(res$trend_terms[[1]], c(202080L, 202180L, 202280L))
  expect_equal(res$trend_hist[[1]], c(3, 4, 8))         # census series, oldest → newest

  # A precomputed base passed in gives the same answer as the scoped recompute,
  # and a global of the same name is not consulted (M12): a bogus
  # cedar_cl_enrls_base in the global environment must change nothing.
  base <- calc_cl_enrls(students, by_part_term = TRUE)
  res_base <- attach_enrollment_history(count_df, students, enrl_base = base)
  expect_equal(res_base$census_enrl, res$census_enrl)
  expect_equal(res_base$census_enrl_mean, res$census_enrl_mean)
  expect_equal(res_base$trend_hist[[1]], res$trend_hist[[1]])

  bogus <- base %>% dplyr::mutate(registered = registered * 100L)
  rlang::local_bindings(cedar_cl_enrls_base = bogus, .env = .GlobalEnv)
  res_global <- attach_enrollment_history(count_df, students)
  expect_equal(res_global$census_enrl, 8)
  expect_equal(res_global$trend_hist[[1]], c(3, 4, 8))
})

test_that("attach_enrollment_history follows the course when the class list names a former code", {
  # RN01: HIST 320's class list in Spring 2020 is the course HIST 3201, whose
  # Spring 2021 offering the base counts under its id (build_cl_enrls_base()).
  # A waitlist row names the class list's code; matched by code it finds no
  # base row and reads no census and no history.
  rn <- rn01_course_tables()
  students <- rn$cedar_students
  base <- build_cl_enrls_base(students)
  expect_false("HIST 320" %in% base$subject_course)
  count_df <- students %>%
    filter(subject_course %in% c("HIST 320", "SOCI 250"), term == 202010L) %>%
    distinct(campus, college, term, part_term, subject_course, course_title) %>%
    arrange(subject_course) %>%
    mutate(count = 1L)

  with_base <- attach_enrollment_history(count_df, students, enrl_base = base)
  recomputed <- attach_enrollment_history(count_df, students)
  for (res in list(with_base, recomputed)) {
    # The rows keep the codes they arrived with, and no helper column leaks.
    expect_equal(res$subject_course, c("HIST 320", "SOCI 250"))
    expect_equal(names(res)[seq_along(count_df)], names(count_df))
    expect_false(any(c(".listed_code", "course_id") %in% names(res)))
    hist <- res %>% filter(subject_course == "HIST 320")
    expect_equal(hist$census_enrl, 1)
    expect_equal(hist$trend_terms[[1]], c(202010L, 202110L))
    expect_equal(hist$n_hist_terms, 1L)
    # The two-step chain SOCI 250 -> SOCI 2315 reaches Spring 2021 too.
    soci <- res %>% filter(subject_course == "SOCI 250")
    expect_equal(soci$trend_terms[[1]], c(202010L, 202110L))
  }
  expect_equal(with_base$census_enrl_mean, recomputed$census_enrl_mean)

  expect_error(
    attach_enrollment_history(count_df, dplyr::select(students, -course_id), enrl_base = base),
    "course_id"
  )
})

test_that("inspect_waitlist counts a course's waitlist across its live codes (RN02)", {
  # RN02: in Spring 2020 W1 waits under SOC 371, W2 under SOCI 371, and W3
  # waits under SOC 371 while registered under SOCI 371, one course.
  rn <- rn02_course_tables()
  # The description table is scaffolding: one row per class-list student-term.
  student_terms <- rn$cedar_students %>%
    distinct(student_id, term) %>%
    mutate(student_classification = "Junior", primary_major_code = "SOCI")
  opt <- create_test_opt(list(term = 202010, uel = FALSE))
  out <- inspect_waitlist(rn$cedar_students, opt, sections = rn$cedar_sections,
                          student_terms = student_terms)

  # One row for the course: W1 and W2 wait; W3 holds a seat in it.
  expect_equal(out$count$subject_course, "SOCI 371")
  expect_equal(out$count$count, 2L)
  expect_equal(out$count$former_codes, "SOC 371 (Spring 2020)")
  # The schedule's SOC 371 section is the course's supply.
  expect_equal(out$count$n_sections, 1L)
  expect_equal(sum(out$majors$count), 2L)
  expect_equal(sum(out$classifications$count), 2L)
  expect_equal(unique(out$majors$former_codes), "SOC 371 (Spring 2020)")

  # Read by code, the same rows split in two and W3 counts as waiting.
  by_code <- lapply(rn, function(tbl) dplyr::mutate(tbl, course_id = subject_course))
  split <- inspect_waitlist(by_code$cedar_students, opt, sections = by_code$cedar_sections,
                            student_terms = student_terms)$count %>%
    arrange(subject_course)
  expect_equal(split$subject_course, c("SOC 371", "SOCI 371"))
  expect_equal(split$count, c(2L, 1L))

  # A former code asked for is its course.
  picked <- inspect_waitlist(rn$cedar_students,
                             create_test_opt(list(course = "SOC 371", term = 202010, uel = FALSE)),
                             sections = rn$cedar_sections, student_terms = student_terms)
  expect_equal(picked$count$subject_course, "SOCI 371")
  expect_equal(picked$count$count, 2L)
})

test_that("waitlist.R uses consistent message prefixes", {
  message("\n  Testing message prefix consistency...")

  # Read the file content
  waitlist_content <- readLines("../../R/cones/waitlist.R")

  # Find all message() calls
  message_lines <- grep("message\\(", waitlist_content, value = TRUE)

  # Check that most use [waitlist.R] prefix
  prefixed_messages <- grep("\\[waitlist\\.R\\]", message_lines)

  message("  Found ", length(message_lines), " message calls")
  message("  ", length(prefixed_messages), " use [waitlist.R] prefix")

  # At least 80% should use the prefix (allowing some flexibility)
  expect_gte(length(prefixed_messages) / length(message_lines), 0.8)
})

test_that("waitlist.R has roxygen documentation for all functions", {
  message("\n  Testing roxygen documentation coverage...")

  # Read the file content
  waitlist_content <- readLines("../../R/cones/waitlist.R")

  # Find function definitions
  function_defs <- grep("^[a-z_]+ <- function\\(", waitlist_content)

  message("  Found ", length(function_defs), " function definitions")

  # Check that each function has roxygen docs above it
  for (func_line in function_defs) {
    # Look at previous lines for roxygen comments
    check_lines <- max(1, func_line - 10):func_line
    has_roxygen <- any(grepl("^#'", waitlist_content[check_lines]))

    if (!has_roxygen) {
      func_name <- sub(" <-.*", "", waitlist_content[func_line])
      warning("Function '", func_name, "' missing roxygen documentation")
    }

    expect_true(has_roxygen)
  }

  message("  All functions have roxygen documentation")
})
