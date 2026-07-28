# Tests for the Dept Dashboard current-term snapshot functions
# (R/reports/dept-dashboard.R). Regression coverage for issue #32:
# ANTH 2190C showed "51 down from an average of 47" because the displayed
# number (total_enrl) and the comparison basis (a single lab CRN's enrolled)
# came from different columns, and the historical average mixed whole-course
# totals with single-section counts. get_current_enrl_vs_avg() must compare
# crosslist-deduplicated course totals on BOTH sides, the number shown must
# be the number the diff was computed from, and campuses must never be
# merged — each campus compares to its own history.
#
# Fixture design (XL06 / XL06-S / XL06-EA in designed_test_data.R):
#   ANTH 2190C ABQ springs — 201910 total 52, 202010 total 50, 202110 total 47,
#   each term an internal-crosslist pair whose rows carry the course total in
#   total_enrl and per-lab counts in enrolled.
#   ANTH 2190C ABQ fall — 202080 total 47 (must not enter the spring average).
#   ANTH 2190C EA  spring — 201910 total 20 (must not enter the ABQ average).

# The dashboard's exact course_history build (create_dept_dashboard_data).
build_dashboard_course_history <- function(dept) {
  ch_opt <- list(dept = dept, status = "A", crosslist = "home", uel = TRUE,
                 group_cols = c("subject_course", "course_title", "campus", "term"))
  get_enrl(test_sections, ch_opt) %>% dplyr::filter(enrolled > 0)
}

test_that("course_history reports combined courses at course-level totals, not per-lab counts", {
  ch <- build_dashboard_course_history("ANTH") %>%
    dplyr::filter(subject_course == "ANTH 2190C", campus == "ABQ") %>%
    dplyr::arrange(term)

  springs <- ch %>% dplyr::filter(term %in% c(201910, 202010, 202110))
  expect_equal(springs$term, c(201910, 202010, 202110))
  # Each ABQ spring is a 2-CRN internal group: the group total must be counted
  # once (52/50/47), not per-row (104/100/94) and not one lab's count (26/25/24).
  expect_equal(springs$total_enrl, c(52, 50, 47))
  # For internal groups the home filter keeps all rows, so summed enrolled
  # equals the course total — enrolled and total_enrl must agree.
  expect_equal(springs$enrolled, springs$total_enrl)
})

test_that("course_history keeps campuses on separate rows", {
  ch <- build_dashboard_course_history("ANTH") %>%
    dplyr::filter(subject_course == "ANTH 2190C", term == 201910) %>%
    dplyr::arrange(campus)

  # One row per campus — 72 on a single merged row would mean campuses merged.
  expect_equal(ch$campus,     c("ABQ", "EA"))
  expect_equal(ch$total_enrl, c(52, 20))
})

test_that("get_current_enrl_vs_avg flags combined courses on deduplicated same-season totals", {
  ch <- build_dashboard_course_history("ANTH")
  cmp <- get_current_enrl_vs_avg(ch, 202110)

  row <- cmp$below %>% dplyr::filter(subject_course == "ANTH 2190C")
  expect_equal(nrow(row), 1)
  expect_equal(row$campus, "ABQ")

  # The displayed number is the full combined enrollment...
  expect_equal(row$total_enrl, 47)
  # ...the average is over prior SPRING course totals at the SAME campus only:
  # (52 + 50) / 2. The fall 202080 offering (total 47) must not contaminate the
  # spring average, and the EA 201910 offering (20) must not deflate the ABQ one
  # (a campus-merged 201910 of 72 would inflate it instead).
  expect_equal(row$hist_avg_enrl, 51)
  expect_equal(row$n_hist, 2)
  # ...and the diff is computed from the same number that is displayed
  # (the issue #32 failure showed total 51 while diffing a lab CRN's 17).
  expect_equal(row$diff, -4L)
  expect_equal(row$diff, as.integer(round(row$total_enrl - row$hist_avg_enrl)))
  expect_equal(row$pct_diff, -8L)

  # A below-average course must not also appear as above-average.
  expect_false("ANTH 2190C" %in% cmp$above$subject_course)
})

test_that("get_current_enrl_vs_avg never merges campuses", {
  ch <- build_dashboard_course_history("ANTH")
  cmp <- get_current_enrl_vs_avg(ch, 202110)
  flagged <- dplyr::bind_rows(cmp$above, cmp$below)

  # EA ran the course only once (201910) and has no current-term offering, so
  # no EA row can be flagged; the only flagged row is the ABQ one whose average
  # was proven unaffected by the EA offering above.
  expect_false("EA" %in% flagged$campus)
  expect_equal(flagged$campus, "ABQ")
})

test_that("get_current_enrl_vs_avg requires two prior same-season offerings", {
  ch <- build_dashboard_course_history("ANTH")
  cmp <- get_current_enrl_vs_avg(ch, 202110)
  flagged <- dplyr::bind_rows(cmp$above, cmp$below)

  # Everything flagged cleared the n_hist >= 2 gate.
  expect_true(all(flagged$n_hist >= 2))

  # Only ANTH 2190C at ABQ has rows in 201910, so every other ANTH course
  # current in 202110 has at most one prior spring and must be excluded. If
  # this fails after a fixture change, another course now spans >= 3 springs —
  # update the design notes in designed_test_data.R, not just this expectation.
  expect_equal(flagged$subject_course, "ANTH 2190C")
})

test_that("get_current_enrl_vs_avg uses recent same-season history only", {
  ch <- tibble(
    subject_course = "HIST 1110",
    course_title = "World History",
    campus = "ABQ",
    term = c(202010L, 202110L, 202210L, 202310L, 202410L),
    enrolled = c(999L, 10L, 20L, 40L, 50L),
    total_enrl = c(999L, 10L, 20L, 40L, 50L)
  )

  cmp <- get_current_enrl_vs_avg(ch, 202410, n_years = 3)
  row <- cmp$above

  expect_equal(nrow(row), 1)
  expect_equal(row$hist_avg_enrl, 23.3)
  expect_equal(row$n_hist, 3)
  expect_equal(row$hist_terms, "Sp21, Sp22, Sp23")
  expect_equal(row$hist_window_label, "3yr avg")
})

test_that("snapshot functions stop loudly when campus is missing from history", {
  # ungroup first: get_enrl returns grouped data, and select(-campus) on a
  # tibble grouped by campus silently re-adds the column
  ch_no_campus <- build_dashboard_course_history("ANTH") %>%
    dplyr::ungroup() %>% dplyr::select(-campus)
  expect_error(get_current_enrl_vs_avg(ch_no_campus, 202110), "campus")
  expect_error(get_new_this_term(ch_no_campus, 202110), "campus")
  expect_error(get_missing_from_earlier(ch_no_campus, 202110), "campus")
  expect_error(get_repeated_topics_courses(ch_no_campus, 202110), "campus")
})

test_that("dashboard recent history renders values first", {
  history <- tibble(
    subject_course = "HIST 1110",
    course_title = "World History",
    campus = "ABQ",
    term = c(202010L, 202080L, 202110L, 202180L, 202210L),
    enrolled = c(12L, 14L, 16L, 18L, 20L)
  )

  recent <- .recent_history_str(history, current_term = 202210L)

  expect_equal(recent$recent_history, "14, 16, 18 (Fa20, Sp21, Fa21)")
})

test_that("get_dashboard_enrollment_flags surfaces waitlists and threshold-based low enrollment", {
  sections <- tibble::tibble(
    department = "HIST",
    term = c(202010L, 202110L, 202210L, 202310L, 202410L,
             202010L, 202110L, 202210L, 202310L, 202410L),
    status = "A",
    section = "001",
    subject_course = c(rep("HIST 1110", 5), rep("HIST 490", 5)),
    course_title = c(rep("World History", 5), rep("Senior Seminar", 5)),
    campus = "ABQ",
    level = "upper",
    is_split = FALSE,
    delivery_method = "LEC",
    instructor_name = "Test Instructor",
    enrolled = c(24L, 25L, 23L, 24L, 30L, 8L, 9L, 7L, 8L, 6L),
    total_enrl = c(24L, 25L, 23L, 24L, 30L, 8L, 9L, 7L, 8L, 6L),
    capacity = c(30L, 30L, 30L, 30L, 30L, 99999L, 99999L, 99999L, 99999L, 99999L),
    waitlist_count = c(0L, 0L, 0L, 0L, 12L, 0L, 0L, 0L, 0L, 0L),
    crosslist_group = NA_character_,
    crosslist_role = NA_character_
  )

  course_history <- sections %>%
    dplyr::group_by(subject_course, course_title, campus, term) %>%
    dplyr::summarize(
      enrolled = sum(enrolled),
      total_enrl = sum(total_enrl),
      .groups = "drop"
    )

  flags <- get_dashboard_enrollment_flags(sections, course_history, "HIST", 202410L, campus = "ABQ")

  expect_equal(flags$high_waitlist$subject_course, "HIST 1110")
  expect_equal(flags$high_waitlist$waiting, 12)
  expect_equal(flags$high_waitlist$enrl_history, "23, 24, 30 (Sp22, Sp23, Sp24)")

  expect_equal(flags$low_enrollment$subject_course, "HIST 490")
  expect_equal(flags$low_enrollment$enrolled, 6)
  expect_equal(flags$low_enrollment$.threshold, 12)
  expect_true(flags$low_enrollment$perennial_low)

  review <- format_dashboard_low_enrollment_review(flags$low_enrollment)
  expect_equal(
    names(review),
    c(
      "campus", "course", "title", "section", "sections", "level",
      "enrolled", "course_total", "threshold", "priority", "repeated",
      "recent_history", ".priority_rank"
    )
  )
  expect_equal(review$course, "HIST 490")
  expect_equal(review$priority, "Warning")
  expect_equal(review$repeated, "Perennial")
  expect_equal(review$recent_history, "8, 9, 7, 8 (Sp20, Sp21, Sp22, Sp23)")
})

test_that("get_dashboard_enrollment_flags applies campus filter to high waitlists", {
  sections <- tibble::tibble(
    department = "CJ",
    term = c(202580L, 202680L, 202580L, 202680L),
    status = "A",
    section = c("001", "001", "002", "002"),
    subject_course = "COMM 1130",
    course_title = "Public Speaking",
    campus = c("EA", "EA", "TA", "TA"),
    level = "lower",
    is_split = FALSE,
    delivery_method = "LEC",
    instructor_name = "Test Instructor",
    enrolled = c(160L, 170L, 40L, 43L),
    total_enrl = c(160L, 170L, 40L, 43L),
    capacity = c(180L, 180L, 45L, 45L),
    waitlist_count = c(0L, 3L, 0L, 2L),
    crosslist_group = NA_character_,
    crosslist_role = NA_character_
  )

  course_history <- sections %>%
    dplyr::group_by(subject_course, course_title, campus, term) %>%
    dplyr::summarize(
      enrolled = sum(enrolled),
      total_enrl = sum(total_enrl),
      .groups = "drop"
    )

  flags <- get_dashboard_enrollment_flags(
    sections, course_history, "CJ", 202680L,
    campus = c("ABQ", "EA")
  )

  expect_equal(flags$high_waitlist$campus, "EA")
  expect_equal(flags$high_waitlist$waiting, 3)
  expect_false("TA" %in% flags$high_waitlist$campus)
})

test_that("dashboard keeps audience detail out of its payload", {
  data_objects <- list(
    cedar_programs = test_programs,
    cedar_students = test_students,
    cedar_sections = test_sections
  )

  dashboard <- create_dept_dashboard_data(
    data_objects,
    list(dept = "HIST", campus = "ABQ", term = 202110L)
  )

  expect_true("composition_shifts" %in% names(dashboard))
  expect_true("credit_hour_shifts" %in% names(dashboard))
  expect_false("cross_dept_minors" %in% names(dashboard$plots))
  expect_false("majors_with_minor" %in% names(dashboard$plots))
  expect_false("student_donuts" %in% names(dashboard$plots))
  expect_false("credit_hours_by_level" %in% names(dashboard$plots))
})
