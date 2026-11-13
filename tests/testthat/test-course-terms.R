# cedar_course_terms (R/branches/course-terms.R): the course-term measure table
# the count and fill readers filter instead of recounting the class list and
# the schedule (ADR-001 step 7, group 3). EC-11 and EC-11b are its fixtures:
# a designed class list and schedule with sessions, campuses, an unmatched
# section, a cancelled offering and an unknown capacity.

test_that("the table carries the class list's counts and the schedule's offerings at one grain", {
  tbl <- test_course_terms_regstats
  expect_identical(names(tbl), COURSE_TERMS_COLUMNS)
  expect_identical(attr(tbl, "course_terms_build_version"), COURSE_TERMS_BUILD_VERSION)
  expect_false(dplyr::is_grouped_df(tbl))
  expect_equal(anyDuplicated(tbl[course_term_key]), 0L)
  # EC-11: every offering has both a class list and a section, so every row is
  # matched on both sides.
  expect_false(anyNA(tbl$registered))
  expect_false(anyNA(tbl$sections))
  expect_true(all(tbl$sections_matched == tbl$sections))
  expect_true(all(tbl$seats_known))
  full <- tbl %>% filter(campus == "ABQ", subject_course == "SOCI 100", term == 202080L, part_term == "1")
  expect_equal(full$registered, 80L)
  expect_equal(full$dr_early, 18L)
  expect_equal(full$dr_late, 20L)
  expect_equal(full$census_enrl, 100)
  expect_equal(full$first_day_enrl, 107L)
  expect_equal(full$first_day_basis, "complete")
  expect_equal(full$sections, 1L)
  expect_equal(full$seats, 100)
  expect_equal(full$desr_enrl, 80L)
  expect_equal(full$subject_code, "SOCI")
  # The schedule's seats are get_enrl()'s (enrolled + available) and the first
  # day is calc_first_day_enrl()'s, read off the same tables.
  direct_seats <- get_enrl(test_sections_regstats, list(status = "A", uel = FALSE, group_cols = course_term_key)) %>%
    ungroup() %>% transmute(across(all_of(course_term_key)), direct = enrolled + avail)
  with_seats <- tbl %>% inner_join(direct_seats, by = course_term_key)
  expect_equal(nrow(with_seats), nrow(tbl))
  expect_equal(with_seats$seats, with_seats$direct)
  first_day <- calc_first_day_enrl(test_students_regstats, test_sections_regstats, by_part_term = TRUE)
  joined <- tbl %>% select(all_of(course_term_key), first_day_enrl) %>%
    inner_join(first_day, by = course_term_key, suffix = c("", ".direct"))
  expect_equal(nrow(joined), nrow(tbl))
  expect_equal(joined$first_day_enrl, joined$first_day_enrl.direct)
})

test_that("a side with no row is NA: unknown, never zero (EC-11b)", {
  tbl <- course_terms_for(test_students_course_history, test_sections_course_history)
  # SOCI 104's Fall 2020 section has no class-list row: the schedule offers it
  # and the class list says nothing, so its counts are unknown and no section
  # is matched.
  offered_only <- tbl %>% filter(subject_course == "SOCI 104", term == 202080L)
  expect_equal(nrow(offered_only), 1L)
  expect_equal(offered_only$sections, 1L)
  expect_equal(offered_only$sections_matched, 0L)
  expect_true(is.na(offered_only$registered))
  expect_true(is.na(offered_only$census_enrl))
  expect_true(is.na(offered_only$first_day_enrl))
  expect_true(is.na(offered_only$attempts))
  expect_equal(offered_only$seats, 100)
  expect_equal(offered_only$subject_code, "SOCI")   # the schedule's, no class list to read
  # SOCI 102's Fall 2020 section is cancelled: students registered and dropped,
  # the schedule offers nothing.
  cancelled <- tbl %>% filter(subject_course == "SOCI 102", term == 202080L)
  expect_equal(nrow(cancelled), 1L)
  expect_true(is.na(cancelled$sections))
  expect_true(is.na(cancelled$seats))
  expect_true(is.na(cancelled$seats_known))
  expect_equal(cancelled$registered, 60L)
  # SOCI 101's Fall 2020 has a second active section no student is listed in:
  # one of two matched, so a reader must not take its first day as the course's.
  partial <- tbl %>% filter(subject_course == "SOCI 101", term == 202080L)
  expect_equal(partial$sections, 2L)
  expect_equal(partial$sections_matched, 1L)
  expect_equal(partial$seats, 200)
  # SOCI 103's Fall 2020 capacity is unknown: the seats are not.
  unknown <- tbl %>% filter(subject_course == "SOCI 103", term == 202080L)
  expect_false(unknown$seats_known)
  # Regstats reads them as the schedule's side, never as class-list counts.
  opt <- list(term = 202080L, bypass_cache = TRUE,
              thresholds = list(min_impacted = 1, pct_sd = 1, chronic_fill_rate = .60,
                                min_sat_terms = 1, min_wait = 1, section_proximity = .3))
  result <- get_reg_stats(test_students_course_history, test_sections_course_history, opt, course_terms = tbl)
  coverage <- result$baseline_info$saturation_coverage
  expect_equal(coverage$unmatched, 1L)        # SOCI 104
  expect_gte(coverage$invalid_capacity, 1L)   # SOCI 103
  expect_false(any(result$dips$subject_course == "SOCI 104"))
})

test_that("a crosslisted section is one offering, counted under its home listing (XL04)", {
  # Spring 2020: HIST 490 has a section of its own (S10003, 20 seats) and is
  # the partner listing of XL04, whose home is ANTH 490 (XL0401, 20 seats).
  # Counted under every listing, HIST 490 would offer two sections and XL04's
  # seats would be counted twice. The schedule's side is the home listing's.
  xl <- test_course_terms %>%
    filter(subject_course %in% c("HIST 490", "ANTH 490"), term == 202010L, campus == "ABQ",
           !is.na(sections))
  hist <- xl %>% filter(subject_course == "HIST 490")
  anth <- xl %>% filter(subject_course == "ANTH 490")
  expect_equal(sum(hist$sections), 1L)
  expect_equal(sum(hist$seats), 20)
  expect_equal(sum(anth$sections), 1L)
  expect_equal(sum(anth$seats), 20)
  # The section its own listing: the plain count of active sections is two.
  plain <- test_sections %>%
    filter(subject_course == "HIST 490", term == 202010L, campus == "ABQ", status == "A")
  expect_equal(nrow(plain), 2L)
  # The partner's students stay under the partner's code: a row with students
  # and no section (the fixture's class-list rows carry no part of term, so
  # the sides do not join here; the regstats fixture joins them).
  expect_equal(sum(test_course_terms$registered[test_course_terms$subject_course == "HIST 490" &
                                                  test_course_terms$term == 202010L], na.rm = TRUE), 2L)
  expect_error(build_course_terms(test_students_regstats, attempts_for(test_students_regstats),
                                  select(test_sections_regstats, -crosslist_role)),
               "crosslist_role")
})

test_that("the builder refuses a class list or schedule missing what it counts", {
  expect_error(build_course_terms(select(test_students_regstats, -as_of_date),
                                  attempts_for(test_students_regstats), test_sections_regstats),
               "as_of_date")
  expect_error(build_course_terms(test_students_regstats, attempts_for(test_students_regstats),
                                  select(test_sections_regstats, -start_date)),
               "start_date")
  expect_error(build_course_terms(test_students_regstats, attempts_for(test_students_regstats),
                                  select(test_sections_regstats, -course_id)),
               "course_id")
})

test_that("a reader scopes the table with the class list's option names and refuses the rest", {
  tbl <- test_course_terms_regstats
  ea <- filter_course_terms(tbl, list(course_campus = "EA", course = "SOCI 100"))
  expect_true(all(ea$campus == "EA" & ea$subject_course == "SOCI 100"))
  expect_gt(nrow(ea), 0L)
  half <- filter_course_terms(tbl, list(pt = "1H", term = 202080L))
  expect_equal(half$part_term, "1H")
  expect_equal(half$term, 202080L)
  expect_equal(nrow(filter_course_terms(tbl, list(subj = "SOCI"))), nrow(tbl))
  expect_equal(nrow(filter_course_terms(tbl, list(level = "lower", dept_code = "SOCI"))), nrow(tbl))
  for (bad in list(list(inst = "X"), list(crn = "EC11-1"), list(im = "ONL"), list(classification = "Freshman"),
                   list(crosslist = "home"))) {
    expect_error(filter_course_terms(tbl, bad), "does not carry", info = names(bad))
  }
  # The empty string a Shiny input sends for "no choice" is not a scope.
  expect_equal(nrow(filter_course_terms(tbl, list(inst = ""))), nrow(tbl))
  # The table's offerings are the active sections: that status is its own
  # scope, any other is a question it cannot answer.
  expect_equal(nrow(filter_course_terms(tbl, list(status = "A"))), nrow(tbl))
  expect_error(filter_course_terms(tbl, list(status = "C")), "active sections")
})

test_that("the build check is the measure's, the currency check the class list's", {
  tbl <- test_course_terms_regstats
  expect_invisible(require_course_terms_build(tbl, "a_reader"))
  older <- tbl
  attr(older, "course_terms_build_version") <- COURSE_TERMS_BUILD_VERSION - 1L
  expect_error(require_course_terms_build(older, "a_reader"), "build_course_terms")
  expect_error(require_course_terms_build(select(tbl, -seats), "a_reader"), "build_course_terms")
  expect_error(require_course_terms_build(calc_cl_enrls(test_students_regstats, by_part_term = TRUE), "a_reader"),
               "build_course_terms")
  # Current for the class list it was counted over, not for another's codes.
  expect_true(course_terms_is_current(tbl, test_students_regstats))
  expect_false(course_terms_is_current(tbl, rn01_course_tables()$cedar_registrations))
})
