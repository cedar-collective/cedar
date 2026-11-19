# Tests for enrollment analysis functions
# Tests R/branches/enrl.R: summarize_courses, aggregate_courses, get_enrl
#
# Uses designed_test_data.R fixtures (hand-crafted, transparent).
# calc_cl_enrls is also tested in test-course-demographics.R.
#
# Reference values (from designed_test_data.R, 85 total rows, 14 XL merged in):
#   Terms in fixture: 202010, 202060, 202080, 202110
#   Status=A sections per term: 202010=28, 202060=12, 202080=15, 202110=17
#   Total enrolled (status=A) per term: 202010=462, 202060=217, 202080=323, 202110=344
#   Cancelled sections per term: 202010=2, 202060=2, 202080=2, 202110=2
#   HIST dept, 202010, status=A: 10 sections, 109 enrolled
#   202010 active: xl_sections=11, reg_sections=17
#   Morgan, Rachel: 24 active sections across all 4 terms

context("Enrollment Analysis")

test_that("dept enrollment trend signals surface persistent low and waitlisted courses", {
  sections <- tibble::tibble(
    department = "HIST",
    term = rep(c(202110L, 202210L, 202310L, 202410L), 2),
    term_type = "spring",
    status = "A",
    campus = "ABQ",
    college = "AS",
    subject = c(rep("HIST", 4), rep("HIST", 4)),
    subject_course = c(rep("HIST 2010", 4), rep("HIST 3010", 4)),
    course_title = c(rep("Methods", 4), rep("Public History", 4)),
    level = c(rep("upper", 4), rep("upper", 4)),
    is_split = FALSE,
    section = "001",
    delivery_method = "LEC",
    instructor_name = "Test Instructor",
    enrolled = c(8L, 9L, 10L, 8L, 24L, 25L, 26L, 27L),
    total_enrl = c(8L, 9L, 10L, 8L, 24L, 25L, 26L, 27L),
    capacity = c(rep(20L, 4), rep(30L, 4)),
    waitlist_count = c(rep(0L, 4), c(2L, 3L, 0L, 4L)),
    crosslist_group = NA_character_,
    crosslist_role = NA_character_
  )

  signals <- get_dept_enrollment_trend_signals(
    sections, "HIST",
    term_start = 202110L,
    term_end = 202410L,
    current_term = 202410L,
    thresholds = c(lower = 12, upper = 12, split = 10, grad = 5),
    min_terms = 3,
    persistent_share = 0.70
  )

  expect_equal(signals$tables$perennial_low$subject_course, "HIST 2010")
  expect_equal(signals$tables$perennial_low$pct_low, 100)
  expect_equal(signals$tables$often_waitlisted$subject_course, "HIST 3010")
  expect_equal(signals$tables$often_waitlisted$pct_waitlisted, 75)
  expect_true("current_above_avg" %in% names(signals$tables))
  expect_true("current_below_avg" %in% names(signals$tables))
})

test_that("course trajectory signals keep repeated topics titles distinct", {
  course_history <- tibble::tibble(
    subject_course = rep(c("HIST 399", "HIST 399", "HIST 2010"), each = 4),
    course_title = rep(c("T: Water History", "T: Desert Empires", "Methods"), each = 4),
    campus = "ABQ",
    term = rep(c(202110L, 202210L, 202310L, 202410L), 3),
    enrolled = c(10L, 15L, 20L, 30L, 40L, 35L, 30L, 25L, 20L, 20L, 20L, 20L),
    total_enrl = c(10L, 15L, 20L, 30L, 40L, 35L, 30L, 25L, 20L, 20L, 20L, 20L)
  )

  signals <- get_course_enrollment_trajectory_signals(
    course_history,
    current_term = 202410L,
    min_terms = 4L,
    baseline_terms = 2L,
    recent_terms = 2L
  )

  expect_equal(signals$increase$course_title, "T: Water History")
  expect_equal(signals$increase$change_abs, 13L)
  expect_equal(signals$decrease$course_title, "T: Desert Empires")
  expect_equal(signals$decrease$change_abs, -10L)
  expect_setequal(
    signals$repeated_topics$course_title,
    c("T: Water History", "T: Desert Empires")
  )
  expect_equal(nrow(signals$repeated_topics), 2L)
})


# =============================================================================
# summarize_courses() tests
# =============================================================================

test_that("summarize_courses default grouping supplies course dimensions and measures", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  result <- summarize_courses(active, list(group_cols = NULL))

  expect_s3_class(result, "data.frame")
  expect_true(all(c(
    "campus", "college", "term", "subject_course", "level",
    "sections", "xl_sections", "reg_sections", "avg_size", "enrolled", "avail", "waiting"
  ) %in% names(result)))
})

test_that("course summaries preserve term totals, crosslist splits, and wrapper behavior", {
  active <- test_sections %>% filter(status == "A")
  opt <- list(group_cols = "term")
  result <- summarize_courses(active, opt) %>% arrange(term)

  # 202080: 18 base + 14 C-suffix (EC-04:4, EC-05:4, EC-06:6) + EC-07:3 = 35.
  # Enrolled: 370 + 89 + 89 + 230 + 71 = 849.
  # XL06-S springs: 201910 = 2 ABQ / 52 + 1 EA / 20; 202010 += 2 / 50;
  # 202110 += 2 / 47. These rows explain the fifth term and its totals.
  expected <- tibble::tribble(
    ~term,  ~sections, ~enrolled,
    201910, 3,         72,
    202010, 30,        512,
    202060, 12,        217,
    202080, 35,        849,
    202110, 19,        391
  )
  for (column in names(expected)) {
    expect_equal(result[[column]], expected[[column]], info = column)
  }

  # 202010 active: 11 XL sections + 2 XL06-S rows = 13, and 17 regular.
  spring <- result %>% filter(term == 202010)
  expect_equal(spring$xl_sections, 13)
  expect_equal(spring$reg_sections, 17)
  expect_equal(result$xl_sections + result$reg_sections, result$sections)
  expect_equal(aggregate_courses(active, opt) %>% arrange(term), result)
})


# =============================================================================
# aggregate_courses() tests
# =============================================================================

test_that("aggregate_courses stops when group_cols is NULL", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  opt    <- list(group_cols = NULL)

  expect_error(aggregate_courses(active, opt), "group_cols is null")
})


test_that("aggregate_courses groups by department within term", {
  active <- test_sections %>% filter(status == "A", term == 202010)
  opt    <- list(group_cols = c("term", "department"))
  result <- aggregate_courses(active, opt)

  expect_true("department" %in% names(result))
  expect_true("enrolled"   %in% names(result))

  # HIST 202010: 10 sections, 109 enrolled
  hist_row <- result %>% filter(department == "HIST")
  expect_equal(hist_row$sections, 10)
  expect_equal(hist_row$enrolled, 109)
})

test_that("course enrollment grouping keeps campus when grouping by course", {
  expect_equal(
    enforce_course_campus_grouping(c("term", "subject_course")),
    c("term", "subject_course", "campus")
  )
  expect_equal(
    enforce_course_campus_grouping(c("campus", "term", "subject_course")),
    c("campus", "term", "subject_course")
  )
  expect_equal(enforce_course_campus_grouping(c("term", "level")), c("term", "level"))
  expect_null(enforce_course_campus_grouping(NULL))
})

test_that("section-level enrollment retains fields required by DESR subtabs", {
  result <- get_enrl(
    test_sections,
    create_test_opt(list(crosslist = "all", group_cols = NULL))
  )
  expect_true(all(c(
    "crosslist_role", "crosslist_external", "crosslist_primary", "is_split"
  ) %in% names(result)))

  home <- filter_enrollment_crosslist_view(result, "home")
  home_grouped <- aggregate_courses(
    home,
    list(group_cols = c("term", "subject_course", "campus"))
  )
  expect_true(all(
    home_grouped %>% count(term, subject_course, campus) %>% pull(n) == 1L
  ))

  view_counts <- vapply(
    c("home", "split", "xl-home", "away", "all"),
    function(view) nrow(filter_enrollment_crosslist_view(result, view)),
    integer(1)
  )
  expect_gt(view_counts[["home"]], view_counts[["split"]])
  expect_gt(view_counts[["all"]], view_counts[["home"]])
})

test_that("Enrollment DESR crosslist views return distinct row sets", {
  rows <- tibble(
    id = c(
      "standalone", "external_home", "external_partner",
      "split_home", "split_partner", "internal_split"
    ),
    crosslist_role = c(NA, "home", "partner", "home", "partner", "internal"),
    crosslist_external = c(FALSE, TRUE, TRUE, TRUE, TRUE, FALSE),
    crosslist_primary = c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE),
    is_split = c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE)
  )

  expect_setequal(
    filter_enrollment_crosslist_view(rows, "home")$id,
    c("standalone", "external_home", "split_home", "internal_split")
  )
  expect_setequal(
    filter_enrollment_crosslist_view(rows, "split")$id,
    c("split_home", "internal_split")
  )
  expect_setequal(
    filter_enrollment_crosslist_view(rows, "xl-home")$id,
    c("external_home", "split_home")
  )
  expect_setequal(
    filter_enrollment_crosslist_view(rows, "away")$id,
    c("external_partner", "split_partner")
  )
  expect_equal(filter_enrollment_crosslist_view(rows, "all")$id, rows$id)
})


# =============================================================================
# get_enrl() tests
# =============================================================================

test_that("get_enrl aggregates active sections into the five fixture term totals", {
  opt <- list(status = "A", group_cols = "term", uel = FALSE)
  result <- get_enrl(test_sections, opt) %>% arrange(term)

  expect_s3_class(result, "data.frame")
  expect_true(all(c("enrolled", "avail", "waiting", "sections") %in% names(result)))
  # Same EC-04 through EC-07 and XL06-S totals documented above.
  expect_equal(result$term, c(201910, 202010, 202060, 202080, 202110))
  expect_equal(result$sections, c(3, 30, 12, 35, 19))
  expect_equal(result$enrolled, c(72, 512, 217, 849, 391))
})


test_that("get_enrl filters by department correctly", {
  opt    <- list(dept_code = "HIST", term = 202010, status = "A",
                 group_cols = c("term", "department"), uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 1)
  expect_true(result$department == "HIST")
  expect_equal(result$sections,   10)
  expect_equal(result$enrolled,   109)
})

test_that("get_enrl returns empty data frame for nonexistent term", {
  opt    <- list(term = 999999, status = "A",
                 group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 0)
  expect_s3_class(result, "data.frame")
})

test_that("get_enrl without group_cols returns section-level data", {
  opt    <- list(term = 202010, status = "A", uel = FALSE)
  result <- get_enrl(test_sections, opt)

  # Section-level: 28 active sections in 202010 + 2 XL06-S rows = 30
  expect_equal(nrow(result), 30)
  expect_true("crn"           %in% names(result))
  expect_true("subject_course" %in% names(result))
})

test_that("get_enrl filters by instructor correctly", {
  opt    <- list(inst = "Morgan, Rachel", status = "A", uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 24)
  expect_true(all(result$instructor_name == "Morgan, Rachel"))
})

test_that("get_enrl returns cancelled sections when status=C", {
  opt    <- list(term = 202010, status = "C",
                 group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(result$sections, 2)
})

test_that("get_enrl combined dept and term filter works", {
  opt    <- list(dept_code = "HIST", term = 202010, status = "A", uel = FALSE)
  result <- get_enrl(test_sections, opt)

  expect_equal(nrow(result), 10)
  expect_true(all(grepl("^HIST", result$subject_course)))
  expect_true(all(result$term == 202010))
})

test_that("get_enrl handles multiple terms correctly", {
  opt    <- list(term = c(202010, 202060), status = "A",
                 group_cols = c("term"), uel = FALSE)
  result <- get_enrl(test_sections, opt) %>% arrange(term)

  expect_equal(nrow(result), 2)
  expect_equal(result$sections, c(30, 12))
})


# =============================================================================
# calc_cl_enrls() — structural coverage + numeric value regression tests
# (additional behavioral tests in test-course-demographics.R)
#
# Numeric baselines derived from designed_test_data.R:
#   HIST 1110 202010: 21 RE + 9 DW = registered=21, dr_late=9, dr_all=9,
#                     dr_early=0, wl_all=0, cl_total=30
#   MATH 1215Z 202010: 2 RE + 3 DW = registered=2, dr_late=3, dr_all=3,
#                      dr_early=0, cl_total=5
#   HIST 327 202010: 3 DW for squeeze baseline → dr_late and dr_all non-zero
# =============================================================================

test_that("calc_cl_enrls preserves status counts, lifecycle totals, and seasonal means", {
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"))

  expect_s3_class(result, "data.frame")
  expect_true(all(c(
    "subject_course", "registered", "registered_mean", "dr_early", "dr_early_mean",
    "dr_late", "dr_late_mean", "dr_all", "dr_all_mean", "wl_all", "cl_total", "cl_total_mean"
  ) %in% names(result)))

  # HIST 1110 in Spring 2020: 21 RE + 9 DW; no early drops or waitlist.
  row <- result %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")
  expected <- tibble::tibble(
    registered = 21, dr_early = 0, dr_late = 9, dr_all = 9, wl_all = 0,
    cl_total = 30, first_day_proxy = 30, census_enrl = 30, last_day_or_current_enrl = 21
  )
  for (column in names(expected)) {
    expect_equal(row[[column]], expected[[column]], info = column)
  }

  # Absent status buckets must be zero throughout the course history, not NA.
  h1110 <- result %>% filter(subject_course == "HIST 1110")
  expect_true(all(h1110$dr_early == 0))
  expect_true(all(h1110$wl_all == 0))

  # Spring rows share the average of the two spring counts, never their sum.
  springs <- h1110 %>% filter(term_type == "spring", campus == "ABQ")
  expect_equal(unique(springs$registered_mean), mean(springs$registered))
})

test_that("calc_cl_enrls returns empty data frame for empty input", {
  empty  <- test_students %>% filter(term == 999999)
  result <- calc_cl_enrls(empty)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})


test_that("calc_cl_enrls adds part_term only on request and preserves single-part counts", {
  # This fixture has no part-of-term variation: adding the dimension must
  # preserve the counts while default callers keep one row per course/term.
  hist <- test_students %>% filter(department == "HIST")
  default_out <- calc_cl_enrls(hist)
  part_out <- calc_cl_enrls(hist, by_part_term = TRUE)

  expect_false("part_term" %in% names(default_out))
  expect_true("part_term" %in% names(part_out))
  default_row <- default_out %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")
  part_row <- part_out %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")
  expect_equal(nrow(part_row), 1)
  expect_equal(part_row$registered, default_row$registered)
  expect_equal(part_row$dr_all, default_row$dr_all)
})


test_that("calc_cl_enrls by_part_term stops loudly when part_term is absent", {
  no_pt <- test_students %>% filter(department == "HIST") %>% select(-part_term)
  expect_error(calc_cl_enrls(no_pt, by_part_term = TRUE), "part_term")
})


# =============================================================================
# Aggregated total_enrl — crosslist groups counted once (sum_xl_dedup_total)
#
# Every section row in a crosslist group carries the group's combined total in
# total_enrl, so a naive sum(total_enrl) multiply-counts the group. This is the
# bug that made the real BIOL 2305 report ~4x its actual enrollment.
# =============================================================================

test_that("aggregated total_enrl counts a non-combined internal group once (EC-07 / BIOL 2305)", {
  # EC-07: 3 CRNs in internal group E7, enrolled 24/24/23, each row total_enrl=71.
  # Naive sum = 3 x 71 = 213; correct course-level total_enrl = 71.
  opt <- list(term = 202080, status = "A", uel = FALSE,
              group_cols = c("campus", "term", "subject_course"))
  result <- get_enrl(test_sections, opt) %>%
    filter(subject_course == "BIOL 2305")

  expect_equal(nrow(result), 1)
  expect_equal(result$sections,   3L)
  expect_equal(result$enrolled,   71L)
  expect_equal(result$total_enrl, 71)
})

test_that("aggregated total_enrl counts each of multiple internal groups once (EC-06 / BIOL 300C)", {
  # EC-06: 2 internal groups (6G total=92, 62 total=138), 3 CRNs each.
  # Correct course-level total_enrl = 92 + 138 = 230 (not 3x92 + 3x138 = 690).
  opt <- list(term = 202080, status = "A", uel = FALSE,
              group_cols = c("campus", "term", "subject_course"))
  result <- get_enrl(test_sections, opt) %>%
    filter(subject_course == "BIOL 300C")

  expect_equal(nrow(result), 1)
  expect_equal(result$total_enrl, 230)
})

test_that("aggregated total_enrl keeps combined-with-partner semantics for cross-course groups", {
  # XL02: HIST 484 (8 enrolled) + HIST 584 (3 enrolled) share group total 11.
  # Each course's cell holds one row of the group, so each course reports the
  # combined total (11) — larger than its own enrolled. The dedup must not
  # change this: it only prevents counting a group twice WITHIN a cell.
  opt <- list(term = 202010, status = "A", uel = FALSE,
              group_cols = c("campus", "term", "subject_course"))
  result <- get_enrl(test_sections, opt)

  h484 <- result %>% filter(subject_course == "HIST 484")
  h584 <- result %>% filter(subject_course == "HIST 584")
  expect_equal(h484$total_enrl, 11)
  expect_equal(h584$total_enrl, 11)
  expect_equal(h484$enrolled,   8L)
})


test_that("calc_cl_enrls with non-NULL reg_status returns only matching codes", {
  # reg_status path: returns raw filtered data, not the full pivot summary
  result <- calc_cl_enrls(test_students %>% filter(department == "HIST"),
                          reg_status = c("DW"))

  expect_true(all(result$registration_status_code == "DW"),
              info = "non-NULL reg_status should filter to only specified codes")
})

test_that("add_census_enrl sums registered and late drops", {
  # Census headcount = still-registered + late drops (present at census); early
  # drops happened before census and are excluded.
  df <- tibble::tibble(
    subject_course = c("A 100", "B 200"),
    registered     = c(30, 10),
    dr_early       = c(5, 0),
    dr_late        = c(3, NA)     # NA late drops coalesce to 0
  )
  out <- add_census_enrl(df)
  expect_equal(out$census_enrl, c(33, 10))
  expect_error(add_census_enrl(tibble::tibble(registered = 1)),
               "add_census_enrl")     # missing dr_late
})

test_that("classlist lifecycle counts preserve the registration-status chronology", {
  df <- tibble::tibble(
    campus = "ABQ",
    registered = c(30, 10),
    dr_early = c(5, 0),
    dr_late = c(3, NA),
    dr_all = c(8, 0)
  )

  out <- add_classlist_lifecycle_enrl(df)

  expect_equal(out$first_day_proxy, c(38, 10))
  expect_equal(out$census_enrl, c(33, 10))
  expect_equal(out$last_day_or_current_enrl, c(30, 10))
  expect_true(all(out$first_day_proxy >= out$census_enrl))
  expect_true(all(out$census_enrl >= out$last_day_or_current_enrl))
  expect_error(
    add_classlist_lifecycle_enrl(tibble::tibble(registered = 1, dr_late = 0)),
    "dr_all"
  )
})


# ---------------------------------------------------------------------------
# The Enrollment table — EC-11b (test_sections_course_history /
# test_students_course_history), Fall 2020 (202080):
#   SOCI 100 ABQ full term: 100 seats; first day 107, census 100, final 80.
#   SOCI 100 ABQ 1H: 100 seats; first day 28, census 30.
#   SOCI 101 ABQ: two sections of 100; one (EC11B-NOMATCH) has no class-list
#     rows, so the course's census is the other's 10 and its first day unknown.
#   SOCI 103 ABQ: seats unknown (available NA); census 60.
#   SOCI 104 ABQ: no class-list rows: no census, never zero.
#   SOCI 100 EA: 100 seats; first day 58, census 60.
#   SOCI 102 is cancelled and so not in an active-section query.
# ---------------------------------------------------------------------------

test_that("calc_cl_enrls by section adds up to its course rows", {
  by_section <- calc_cl_enrls(test_students_course_history, by_section = TRUE) %>%
    ungroup() %>%
    group_by(campus, college, term, subject_course) %>%
    summarize(registered = sum(registered), census_enrl = sum(census_enrl), .groups = "drop")
  by_course <- calc_cl_enrls(test_students_course_history) %>%
    ungroup() %>%
    select(campus, college, term, subject_course, registered, census_enrl)
  expect_equal(arrange(by_section, campus, term, subject_course),
               arrange(by_course, campus, term, subject_course))
  expect_error(calc_cl_enrls(select(test_students_course_history, -crn), by_section = TRUE),
               "requires a crn column")
})

test_that("the Enrollment table attaches each section's class-list counts and leaves unregistered sections unknown", {
  raw <- get_enrl(test_sections_course_history,
                  list(status = "A", crosslist = "all", uel = FALSE, term = 202080L))
  counted <- attach_enrollment_section_counts(raw, test_students_course_history,
                                              test_sections_course_history)
  rows <- counted$rows
  expect_equal(counted$n_placeholders, 0L)
  expect_equal(nrow(rows), 7L)

  full_term <- filter(rows, crn == "EC11-3")
  expect_equal(c(full_term$seats, full_term$first_day_enrl, full_term$census_enrl,
                 full_term$registered, full_term$dr_early, full_term$dr_late),
               c(100, 107, 100, 80, 18, 20))
  expect_equal(full_term$first_day_basis, "complete")

  unmatched <- filter(rows, crn %in% c("EC11B-NOMATCH", "EC11-21"))
  expect_true(all(is.na(unmatched$census_enrl)))
  expect_true(all(is.na(unmatched$first_day_enrl)))
  expect_false(filter(rows, subject_course == "SOCI 103")$seats_known)

  # A section listed twice would attach its counts twice.
  expect_error(attach_enrollment_section_counts(bind_rows(raw, raw[1, ]),
                                                test_students_course_history,
                                                test_sections_course_history),
               "appears more than once")
})

test_that("a section with no seats and no students is not an offering", {
  # The full-term SOCI 100 section stated as an empty placeholder.
  schedule <- mutate(test_sections_course_history,
                     enrolled = ifelse(crn == "EC11-3", 0L, enrolled),
                     available = ifelse(crn == "EC11-3", 0, available),
                     total_enrl = ifelse(crn == "EC11-3", 0L, total_enrl))
  raw <- get_enrl(schedule, list(status = "A", crosslist = "all", uel = FALSE, term = 202080L))
  counted <- attach_enrollment_section_counts(raw, test_students_course_history, schedule)
  expect_equal(counted$n_placeholders, 1L)
  expect_false("EC11-3" %in% counted$rows$crn)
})

test_that("a grouped Enrollment row sums its sections and knows its first day only when every section's is known", {
  raw <- get_enrl(test_sections_course_history,
                  list(status = "A", crosslist = "all", uel = FALSE, term = 202080L))
  rows <- attach_enrollment_section_counts(raw, test_students_course_history,
                                           test_sections_course_history)$rows
  view <- summarize_enrollment_view(rows, list(
    view = "home", group_cols = c("campus", "subject_course", "part_term", "term")
  ))
  expect_true(view$grouped)
  expect_equal(view$n_before_filter, 6L)
  expect_equal(view$n_no_registrations, 1L)

  soci_101 <- filter(view$rows, subject_course == "SOCI 101")
  expect_equal(c(soci_101$sections, soci_101$sections_matched, soci_101$seats,
                 soci_101$census_enrl), c(2, 1, 200, 10))
  expect_true(is.na(soci_101$first_day_enrl))
  expect_equal(soci_101$enrolled, 20)

  soci_104 <- filter(view$rows, subject_course == "SOCI 104")
  expect_equal(soci_104$sections_matched, 0L)
  expect_true(is.na(soci_104$census_enrl))
  expect_true(is.na(soci_104$avg_census))

  # The two campuses and the two parts of term stay separate rows.
  soci_100 <- filter(view$rows, subject_course == "SOCI 100") %>% arrange(campus, part_term)
  expect_equal(soci_100$census_enrl, c(100, 30, 60))
})

test_that("a row grouped by course names its title, and says when its sections had several", {
  raw <- get_enrl(test_sections, list(status = "A", crosslist = "all", uel = FALSE, term = 202010L))
  rows <- attach_enrollment_section_counts(raw, test_students, test_sections)$rows
  view <- summarize_enrollment_view(rows, list(view = "all", group_cols = c("term", "subject_course")))
  shown <- enrollment_table_display(view)
  # The title follows the course.
  expect_equal(match("course_title", names(shown)), match("subject_course", names(shown)) + 1L)
  expect_equal(filter(shown, subject_course == "HIST 327")$course_title, "Modern European History")
  # HIST 490's two sections carry two titles (a topics course): one is shown,
  # with the other counted.
  hist_490 <- filter(view$rows, subject_course == "HIST 490")
  expect_equal(c(hist_490$sections, hist_490$n_titles), c(2, 2))
  expect_equal(filter(shown, subject_course == "HIST 490")$course_title,
               "Historical Research Methods (+1 more)")
  # Grouped by title itself, or not by course, a row adds no title of its own.
  by_title <- summarize_enrollment_view(rows, list(view = "all", group_cols = c("subject_course", "course_title")))
  expect_false("n_titles" %in% names(by_title$rows))
  by_dept <- enrollment_table_display(summarize_enrollment_view(rows, list(view = "all", group_cols = "department")))
  expect_false("course_title" %in% names(by_dept))
})

test_that("Enrollment first-day fill is judged against seats and withheld where seats cannot be read", {
  raw <- get_enrl(test_sections_course_history,
                  list(status = "A", crosslist = "all", uel = FALSE, term = c(202010L, 202080L)))
  rows <- attach_enrollment_section_counts(raw, test_students_course_history,
                                           test_sections_course_history)$rows
  group_cols <- c("campus", "subject_course", "part_term", "term")
  view <- summarize_enrollment_view(rows, list(view = "home", group_cols = group_cols))$rows

  fall <- filter(view, term == 202080L)
  full_term <- filter(fall, campus == "ABQ", subject_course == "SOCI 100", part_term == "1")
  expect_equal(full_term$first_day_fill, 1.07)
  expect_equal(full_term$fill_status, "full")
  ea <- filter(fall, campus == "EA")
  expect_equal(ea$first_day_fill, 0.58)
  expect_true(is.na(ea$fill_status))
  # Seats unknown, and a first day of 198 in 100 seats (implausible capacity).
  expect_true(is.na(filter(fall, subject_course == "SOCI 103")$first_day_fill))
  expect_true(is.na(filter(view, term == 202010L, subject_course == "SOCI 100")$first_day_fill))

  # The full-term section with 110 seats: 107 of 110 is near full, not full.
  near <- summarize_enrollment_view(
    mutate(rows, seats = ifelse(crn == "EC11-3", 110, seats)),
    list(view = "home", group_cols = group_cols)
  )$rows %>% filter(subject_course == "SOCI 100", campus == "ABQ",
                    part_term == "1", term == 202080L)
  expect_equal(near$fill_status, "near full")

  # A crosslisted section shares its seats with the partner listing: no fill.
  shared <- summarize_enrollment_view(
    mutate(rows, crosslisted = crn == "EC11-3"),
    list(view = "all", group_cols = group_cols)
  )$rows %>% filter(subject_course == "SOCI 100", campus == "ABQ", part_term == "1",
                    term == 202080L)
  expect_true(is.na(shared$first_day_fill))
})

test_that("Enrollment Min/Max reads census and keeps the rows it cannot judge", {
  raw <- get_enrl(test_sections_course_history,
                  list(status = "A", crosslist = "all", uel = FALSE, term = 202080L))
  rows <- attach_enrollment_section_counts(raw, test_students_course_history,
                                           test_sections_course_history)$rows
  group_cols <- c("campus", "subject_course", "part_term", "term")
  at_least_50 <- summarize_enrollment_view(rows, list(view = "home", group_cols = group_cols,
                                                      enrl_min = 50))
  expect_equal(nrow(at_least_50$rows), 4L)
  expect_setequal(paste(at_least_50$rows$campus, at_least_50$rows$subject_course),
                  c("ABQ SOCI 100", "ABQ SOCI 103", "ABQ SOCI 104", "EA SOCI 100"))
  expect_equal(at_least_50$n_no_registrations, 1L)
  expect_equal(at_least_50$n_before_filter, 6L)

  # Census, not the DESR count: SOCI 101's DESR count is 20, its census 10.
  at_most_15 <- summarize_enrollment_view(rows, list(view = "home", group_cols = group_cols,
                                                     enrl_max = 15))
  expect_setequal(at_most_15$rows$subject_course, c("SOCI 101", "SOCI 104"))
  expect_equal(nrow(summarize_enrollment_view(rows, list(view = "home", group_cols = group_cols,
                                                         enrl_min = NA))$rows), 6L)
})

test_that("the Enrollment table's display keeps one column order for each grain", {
  raw <- get_enrl(test_sections_course_history,
                  list(status = "A", crosslist = "all", uel = FALSE, term = 202080L))
  rows <- attach_enrollment_section_counts(raw, test_students_course_history,
                                           test_sections_course_history)$rows
  grouped <- enrollment_table_display(summarize_enrollment_view(rows, list(
    view = "home", group_cols = c("campus", "subject_course", "term")
  )))
  expect_named(grouped, c("campus", "subject_course", "course_title", "term", "sections", "sections_matched",
                          "xl_sections", "seats", "first_day_enrl", "first_day_fill",
                          "fill_status", "census_enrl", "avg_census", "registered",
                          "dr_early", "dr_late", "enrolled", "total_enrl"))
  expect_equal(filter(grouped, campus == "ABQ", subject_course == "SOCI 100")$first_day_fill,
               67.5)

  by_section <- enrollment_table_display(summarize_enrollment_view(rows, list(view = "home")))
  expect_equal(names(by_section)[1:5], c("campus", "college", "term", "term_type", "listed_code"))
  expect_false(any(c("sections", "xl_sections", "avg_census") %in% names(by_section)))
  expect_true(all(c("partners", "first_day_fill", "census_enrl", "enrolled") %in% names(by_section)))
})

test_that("Enrollment term filter opens on the shared configured default term", {
  # global.R resolves cedar_default_term once so every term picker opens on the
  # same term; the resolution itself is covered in test-utils.R. This pins the
  # Enrollment picker to that shared default rather than a tab-local choice.
  ui_source <- paste(readLines("../../ui.R", warn = FALSE), collapse = "\n")
  term_filter <- regmatches(
    ui_source,
    regexpr(
      'inputId = "enrl_term"[\\s\\S]{0,500}selected = as.character\\(cedar_default_term\\)',
      ui_source,
      perl = TRUE
    )
  )

  expect_true(nzchar(term_filter))
})

test_that("calc_census_enrl_baselines computes historic census mean, count, and series", {
  # One fall course over three terms; census = registered + dr_late.
  #   202080: 2 + 1 = 3   202180: 4 + 0 = 4   202280: 6 + 2 = 8 (viewed)
  df <- tibble::tibble(
    campus = "ABQ", college = "ARTS", subject_course = "WLST 1000",
    term_type = "fall", part_term = "1",
    term       = c(202080L, 202180L, 202280L),
    registered = c(2, 4, 6),
    dr_late    = c(1, 0, 2)
  )

  bl <- calc_census_enrl_baselines(df, target_terms = 202280L)
  expect_equal(nrow(bl), 1)
  expect_equal(bl$census_mean, 3.5)                     # mean(3, 4), viewed term excluded
  expect_equal(bl$n_hist_terms, 2L)
  expect_equal(bl$census_hist[[1]], c(3, 4, 8))         # full series incl. viewed term
  expect_equal(bl$census_hist_terms[[1]], c(202080L, 202180L, 202280L))

  # With no target term excluded, the mean and count span every term.
  bl_all <- calc_census_enrl_baselines(df)
  expect_equal(bl_all$census_mean, 5)                   # mean(3, 4, 8)
  expect_equal(bl_all$n_hist_terms, 3L)
})

test_that("census prior-only baselines keep each viewed term out of its own history", {
  df <- calc_cl_enrls(test_students_regstats, by_part_term = TRUE) %>% ungroup() %>%
    filter(subject_course == "SOCI 100", campus == "ABQ", part_term == "1", term_type == "fall")
  prior <- calc_census_enrl_baselines(df, prior_only = TRUE) %>% arrange(term)
  expect_equal(prior$census_mean, c(NA, 44, 54, 208 / 3))
  expect_equal(prior$census_sd[1:3], c(NA, NA, 10))
  expect_equal(prior$n_hist_terms, 0:3)
  expect_equal(prior$census_hist[[3]], c(44, 64, 100, 10))
  selected <- calc_census_enrl_baselines(df, target_terms = c(202080L, 202180L), prior_only = TRUE)
  expect_equal(selected, filter(prior, term %in% c(202080L, 202180L)))
  # Waitlists retains its existing all-history reference, including later terms.
  reference <- calc_census_enrl_baselines(df, target_terms = 202080L)
  expect_equal(reference$census_mean, 39.3)
})

test_that("enrollment momentum requires campus in history", {
  ch_no_campus <- test_sections_topics %>%
    filter(subject_course == "HIST 401") %>%
    group_by(subject_course, course_title, term) %>%
    summarize(enrolled = sum(enrolled), .groups = "drop")

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

test_that("enrollment level trends keep campuses in separate plot traces", {
  level_data <- tibble(
    term = rep(c(202410L, 202510L), times = 4),
    level = rep(c("lower", "upper", "lower", "upper"), each = 2),
    campus = rep(c("ABQ", "ABQ", "EA", "EA"), each = 2),
    enrolled = c(100L, 110L, 40L, 44L, 70L, 77L, 20L, 22L)
  )

  plot_data <- prepare_enrollment_level_trend_series(level_data)

  expect_equal(nrow(plot_data), 8L)
  expect_setequal(unique(plot_data$campus), c("ABQ", "EA"))
  expect_equal(
    plot_data %>% count(term, campus, level) %>% pull(n),
    rep(1L, 8)
  )

  plot <- build_enrollment_level_trend_plot(level_data)
  traces <- plotly::plotly_build(plot)$x$data
  trace_names <- vapply(traces, function(trace) trace$name, character(1))

  expect_length(traces, 4L)
  expect_true(all(vapply(traces, function(trace) length(trace$x) == 2L, logical(1))))
  expect_true(any(grepl("ABQ", trace_names, fixed = TRUE)))
  expect_true(any(grepl("EA", trace_names, fixed = TRUE)))
  expect_true(any(grepl("Lower Div", trace_names, fixed = TRUE)))
  expect_true(any(grepl("Upper Div", trace_names, fixed = TRUE)))
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

  plot_series <- prepare_enrollment_trend_plot_series(courses, history, n = 2)
  keys_by_campus <- plot_series %>% distinct(campus, series_key)

  expect_equal(nrow(keys_by_campus), 2)
  expect_setequal(
    unique(plot_series$series_label),
    c("COMM 1130 (ABQ): Public Speaking", "COMM 1130 (EA): Public Speaking")
  )
  expect_equal(plot_series$trace_name, plot_series$series_label)
  expect_equal(split(plot_series$term, plot_series$campus)$ABQ, c(202410L, 202510L))
  expect_equal(split(plot_series$term, plot_series$campus)$EA, c(202410L, 202510L))
  expect_false(
    keys_by_campus$series_key[keys_by_campus$campus == "ABQ"] ==
      keys_by_campus$series_key[keys_by_campus$campus == "EA"]
  )
})

test_that("cedar_course_terms counts each course-term once and sums exactly over part of term", {
  # EC-11's class list splits a course-term into a full term and a 2H half.
  course_terms <- course_terms_for(test_students_regstats, test_sections_regstats)
  expect_identical(names(course_terms), COURSE_TERMS_COLUMNS)
  expect_false(dplyr::is_grouped_df(course_terms))
  expect_identical(attr(course_terms, "course_terms_build_version"), COURSE_TERMS_BUILD_VERSION)
  # One row per campus, college, term, course and part of term.
  expect_equal(nrow(dplyr::distinct(course_terms, campus, college, term, subject_course, part_term)),
               nrow(course_terms))
  # No cross-term mean or baseline: those are the reader's (Regstats'
  # baselines are strictly prior), and a pooled column would put later
  # terms' counts in an earlier term's row.
  expect_false(any(grepl("_mean$|_sd$|hist", names(course_terms))))
  expect_equal(course_terms$census_enrl, course_terms$registered + course_terms$dr_late)

  # The class list holds one row per student, course, campus and term, so the
  # part-of-term rows sum to the course-term-campus count of distinct students.
  whole <- calc_cl_enrls(test_students_regstats) %>% dplyr::ungroup() %>%
    dplyr::select(campus, college, term, subject_course, registered, dr_late, cl_total)
  summed <- course_terms %>%
    dplyr::summarize(dplyr::across(c(registered, dr_late, cl_total), sum),
                     .by = c(campus, college, term, subject_course))
  joined <- dplyr::inner_join(whole, summed, by = c("campus", "college", "term", "subject_course"),
                              suffix = c("_whole", "_parts"))
  expect_equal(nrow(joined), nrow(whole))
  expect_equal(joined$registered_parts, joined$registered_whole)
  expect_equal(joined$cl_total_parts, joined$cl_total_whole)
  expect_true(any(duplicated(dplyr::select(course_terms, campus, term, subject_course))),
              info = "the fixture must carry a course-term split across parts of term")
})

test_that("Waitlists refuses a course-term table counted over other course codes", {
  rn <- rn01_course_tables
  stale <- course_terms_for(test_students, test_sections)
  expect_error(
    inspect_waitlist(rn$cedar_registrations, list(term = 202010L), sections = rn$cedar_sections,
                     course_terms = stale),
    "build_course_terms"
  )
})
