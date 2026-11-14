# Tests for R/features/registration-watch.R: the Regstats screens read
# together. watch_flagged (scenario_tables.R) is a payload typed by hand with
# each row's expected pattern written above it; watch_regstats is the fixture
# Regstats run (EC-11).

test_that("each course gets the pattern its flags make, in the watch's order", {
  x <- watch_payload$courses
  expect_equal(
    paste(x$subject_course, x$campus, x$pattern),
    c("SPAN 1110 ABQ seats_cut", "FDMA 1520 ABQ seats_cut",
      "BIOL 2210 ABQ unmet_demand", "SPAN 1110 EA unmet_demand",
      "BIOL 2305 ABQ growth_at_capacity", "CHEM 1215 ABQ churn",
      "HIST 1110 ABQ falling_demand", "PSYC 1110 ABQ rising_demand",
      "MATH 1215 ABQ drop_spike", "ARTH 1120 ABQ fuller_than_usual"))
})

test_that("a course is read on each campus apart", {
  span <- dplyr::filter(watch_payload$courses, subject_course == "SPAN 1110")
  expect_equal(span$campus, c("ABQ", "EA"))
  # The same course dipped while full on one campus and grew with a waitlist
  # on the other: two readings, never one blended row.
  expect_equal(span$pattern, c("seats_cut", "unmet_demand"))
  expect_equal(span$n_screens, c(3L, 4L))
})

test_that("the students behind a row are the lead screen's own count", {
  x <- watch_payload$courses
  students <- function(course, campus = "ABQ") x$students[x$subject_course == course & x$campus == campus]
  expect_equal(students("SPAN 1110"), 60)          # the dip's students beyond the usual range
  expect_equal(students("SPAN 1110", "EA"), 12)    # students waiting, not the bump's 20
  expect_equal(students("CHEM 1215"), 15)          # churn: the drops, not the bump's 120
  expect_equal(students("MATH 1215"), 22)          # early 4 + late 18
  expect_true(is.na(students("ARTH 1120")))        # fill alone counts no students
})

test_that("usually near full is counted, not listed, unless asked for", {
  expect_false("ENGL 1120" %in% watch_payload$courses$subject_course)
  expect_equal(watch_payload$meta$n_usually_full, 1L)
  expect_equal(watch_payload$meta$n_flagged, 11L)
  expect_equal(watch_payload$meta$n_listed, 10L)
  known <- build_registration_watch(watch_flagged, list(include_known = TRUE))
  expect_equal(tail(known$courses$subject_course, 1), "ENGL 1120")
  expect_equal(tail(known$courses$pattern, 1), "usually_full")
})

test_that("the college roll-up counts the listed courses and their students", {
  r <- watch_payload$rollup
  as_seats <- r[r$college == "AS" & r$pattern == "unmet_demand", ]
  expect_equal(as_seats$courses, 2L)
  expect_equal(as_seats$students, 81)
  expect_equal(as_seats$examples, "BIOL 2210, SPAN 1110")
  fa_fill <- r[r$college == "FA" & r$pattern == "fuller_than_usual", ]
  expect_true(is.na(fa_fill$students))
  expect_equal(sum(r$courses), watch_payload$meta$n_listed)
})

test_that("the watch reads the fixture Regstats run as it comes", {
  x <- build_registration_watch(watch_regstats)$courses
  expect_equal(
    paste(x$campus, x$subject_course, x$part_term, x$pattern, x$students),
    c("EA SOCI 100 1 growth_at_capacity 50", "ABQ SOCI 100 1 growth_at_capacity 36",
      "ABQ SOCI 101 1 falling_demand 50", "ABQ SOCI 100 1H rising_demand 10"))
  # SOCI 100 on ABQ, part 1, is raised by every screen but the waitlist and
  # the dip; it grew into full sections, so drops do not make it churn.
  expect_equal(x$n_screens[2], 6L)
})

test_that("a missing table, column or repeated row stops the watch", {
  expect_error(build_registration_watch(watch_flagged[setdiff(names(watch_flagged), "waits")]),
               "no `waits` table")
  expect_error(build_registration_watch(replace(watch_flagged, "dips",
                 list(dplyr::select(watch_flagged$dips, -impacted)))),
               "flagged\\$dips lacks impacted")
  expect_error(build_registration_watch(replace(watch_flagged, "waits",
                 list(dplyr::bind_rows(watch_flagged$waits, watch_flagged$waits[1, ])))),
               "repeats a term, campus")
  # The preview prints the near-full rate it used; without one it cannot say.
  no_rate <- watch_payload
  no_rate$meta$thresholds$chronic_fill_rate <- NULL
  expect_error(format_registration_watch(no_rate), "lacks chronic_fill_rate")
})

test_that("the text preview names each pattern and its courses", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_registration_watch(watch_payload), sep = "\n"))
})
