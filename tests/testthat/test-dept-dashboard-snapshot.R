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
  expect_error(get_enrollment_momentum(ch_no_campus), "campus")
})

test_that("enrollment momentum collapses regular-course retitles", {
  history <- test_sections_topics %>%
    filter(subject_course == "HIST 401") %>%
    group_by(subject_course, course_title, campus, term) %>%
    summarize(
      enrolled = sum(enrolled),
      total_enrl = sum(total_enrl),
      .groups = "drop"
    )

  momentum <- get_enrollment_momentum(history, n_terms = 10, threshold = 0.1)
  row <- momentum$investigate

  expect_equal(nrow(row), 1)
  expect_equal(row$subject_course, "HIST 401")
  expect_equal(row$course_title, "Introduction to Historical Methods")
  expect_equal(row$n_terms, 2)
  expect_equal(row$avg_enrl_early, 20)
  expect_equal(row$avg_enrl_recent, 18)
})

test_that("enrollment momentum keeps rotating topics separate", {
  history <- test_sections_topics %>%
    filter(subject_course == "HIST 395") %>%
    group_by(subject_course, course_title, campus, term) %>%
    summarize(
      enrolled = sum(enrolled),
      total_enrl = sum(total_enrl),
      .groups = "drop"
    )

  prepared <- prepare_enrollment_trend_history(history)
  expect_setequal(
    unique(prepared$course_title),
    c("T: Black Sports History", "T: Digital History")
  )

  momentum <- get_enrollment_momentum(history, n_terms = 10, threshold = 0.1)

  expect_equal(nrow(momentum$growing), 1)
  expect_equal(momentum$growing$course_title, "T: Black Sports History")
  expect_equal(momentum$growing$n_terms, 2)
  expect_false("T: Digital History" %in% momentum$growing$course_title)
  expect_true(is.null(momentum$investigate) || !"T: Digital History" %in% momentum$investigate$course_title)
})

test_that("enrollment momentum uses combined totals when present", {
  history <- tibble(
    subject_course = "CJ 326",
    course_title = "Gender & Communication",
    campus = "ABQ",
    term = c(202280L, 202310L),
    enrolled = c(43L, 22L),
    total_enrl = c(54L, 26L)
  )

  prepared <- prepare_enrollment_trend_history(history)

  expect_equal(prepared$enrolled, c(54L, 26L))
})

test_that("enrollment momentum uses is_topics flag when title prefix is missing", {
  history <- tibble(
    subject_course = c("CJ 393", "CJ 393", "CJ 394"),
    course_title = c("Advanced Conflict Management", "T: Different Topic", "Advanced Conflict Management"),
    campus = "ABQ",
    term = c(202410L, 202480L, 202410L),
    is_topics = c(FALSE, FALSE, TRUE),
    enrolled = c(27L, 12L, 8L),
    total_enrl = c(27L, 12L, 8L)
  )

  prepared <- prepare_enrollment_trend_history(history)

  cj393 <- prepared %>% filter(subject_course == "CJ 393")
  expect_setequal(cj393$course_title, c("Advanced Conflict Management", "T: Different Topic"))

  cj394 <- prepared %>% filter(subject_course == "CJ 394")
  expect_equal(cj394$course_title, "Advanced Conflict Management")
})

test_that("enrollment trend scope caps history at selected/current term", {
  history <- tibble(
    subject_course = "COMM 1130",
    course_title = "Public Speaking",
    campus = "ABQ",
    term = c(202410L, 202480L, 202510L, 202580L, 202610L),
    enrolled = c(381L, 547L, 382L, 560L, 435L)
  )

  scope <- resolve_enrollment_trend_term_scope("202510", current_term = 202610)
  scoped <- filter_enrollment_trend_scope(history, scope)

  expect_equal(scope$max_term, 202510L)
  expect_equal(scoped$term, c(202410L, 202480L, 202510L))
})

test_that("enrollment trend scope keeps term type filters", {
  history <- tibble(
    subject_course = "COMM 1130",
    course_title = "Public Speaking",
    campus = "ABQ",
    term = c(202410L, 202480L, 202510L, 202580L, 202610L),
    term_type = c("spring", "fall", "spring", "fall", "spring"),
    enrolled = c(381L, 547L, 382L, 560L, 435L)
  )

  scope <- resolve_enrollment_trend_term_scope(c("spring", "202580"), current_term = 202510)
  scoped <- filter_enrollment_trend_scope(history, scope)

  expect_equal(scope$term_types, "spring")
  expect_equal(scope$max_term, 202510L)
  expect_equal(scoped$term, c(202410L, 202510L))
})

test_that("enrollment trend plot selection keeps campus keys separate", {
  courses <- tibble(
    subject_course = c("COMM 1130", "COMM 1130"),
    course_title = "Public Speaking",
    campus = c("ABQ", "EA")
  )
  history <- tibble(
    subject_course = "COMM 1130",
    course_title = "Public Speaking",
    campus = rep(c("ABQ", "EA", "TA"), each = 2),
    term = rep(c(202410L, 202510L), times = 3),
    enrolled = 10L
  )

  plot_data <- select_enrollment_trend_plot_data(courses, history, n = 2)

  expect_setequal(unique(plot_data$campus), c("ABQ", "EA"))
  expect_false("TA" %in% plot_data$campus)
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
