# Tests for R/features/registration-watch.R: the Regstats screens read
# together. watch_flagged (scenario_tables.R) is a payload typed by hand with
# each row's expected pattern written above it; watch_regstats is the fixture
# Regstats run (EC-11).

test_that("each course gets the pattern its flags make, in the watch's order", {
  x <- watch_payload$courses
  expect_equal(
    paste(x$subject_course, x$campus, x$pattern),
    c("SPAN 1110 ABQ seats_cut", "FDMA 1520 ABQ seats_cut",
      "BIOL 2210 ABQ unmet_demand", "SPAN 1110 EA unmet_demand", "MATH 1350 EA unmet_demand",
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
  expect_equal(watch_payload$meta$n_flagged, 12L)
  expect_equal(watch_payload$meta$n_listed, 11L)
  known <- build_registration_watch(watch_flagged, list(include_known = TRUE))
  expect_equal(tail(known$courses$subject_course, 1), "ENGL 1120")
  expect_equal(tail(known$courses$pattern, 1), "usually_full")
})

test_that("the college roll-up counts the listed courses and their students", {
  r <- watch_payload$rollup
  as_seats <- r[r$college == "AS" & r$pattern == "unmet_demand", ]
  expect_equal(as_seats$courses, 3L)
  expect_equal(as_seats$students, 90)
  expect_equal(as_seats$examples, "BIOL 2210, SPAN 1110, MATH 1350")
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
  # A payload from before course_context, or one missing a raised course's row.
  expect_error(build_registration_watch(watch_flagged[setdiff(names(watch_flagged), "course_context")]),
               "no `course_context` table")
  expect_error(build_registration_watch(replace(watch_flagged, "course_context",
                 list(dplyr::filter(watch_flagged$course_context, subject_course != "HIST 1110")))),
               "has no row for HIST 1110")
  # The preview prints the near-full rate it used; without one it cannot say.
  no_rate <- watch_payload
  no_rate$meta$thresholds$chronic_fill_rate <- NULL
  expect_error(format_registration_watch(no_rate), "lacks chronic_fill_rate")
})

test_that("every course is read on its context row, whichever screen raised it", {
  x <- watch_payload$courses
  biol <- x[x$subject_course == "BIOL 2210", ]       # raised by its waitlist and fill alone
  expect_equal(biol$census_enrl_mean, 160)
  expect_equal(biol$enrl_ratio, 165 / 160)
  math <- x[x$subject_course == "MATH 1350", ]       # a first offering: no usual, no seats
  expect_true(is.na(math$census_enrl_mean))
  expect_true(is.na(math$enrl_ratio))
  expect_true(is.na(math$fill_rate))
})

test_that("the chart places each listed course by its usual and its fill", {
  pd <- prepare_registration_watch_plot_data(watch_payload)
  pt <- function(course, campus = "ABQ") pd$points[pd$points$label_text == course & pd$points$campus == campus, ]
  expect_equal(pt("SPAN 1110")$x, 445 / 548)
  expect_equal(pt("SPAN 1110")$y, 97.6)
  expect_equal(pt("HIST 1110")$x, 60 / 110)
  # FDMA 1520 fell to 0.19 of its usual: drawn at the quarter, marked off scale.
  expect_equal(pt("FDMA 1520")$x, 1 / 4)
  expect_true(pt("FDMA 1520")$off_scale)
  expect_equal(sum(pd$points$off_scale), 1L)
  # A course with no usual or no seats is not drawn, and is counted.
  expect_setequal(pd$not_drawn$reason, c("no earlier offering to compare", "no usable seats"))
  expect_equal(nrow(pd$points) + sum(pd$not_drawn$courses), watch_payload$meta$n_listed)
  expect_false(any(c("CHEM 1215", "MATH 1350") %in% pd$points$label_text))
  expect_equal(pd$near_full_pct, 90)
  # A wider axis takes FDMA 1520 on scale.
  wide <- prepare_registration_watch_plot_data(watch_payload, list(max_ratio = 8))
  expect_equal(wide$points$x[wide$points$label_text == "FDMA 1520"], 12 / 62)
  expect_false(any(wide$points$off_scale))
})

test_that("colour says the family, the shape the pattern, the size the students", {
  expect_setequal(.REGISTRATION_WATCH_MARKS$pattern, REGISTRATION_WATCH_PATTERNS$pattern)
  marks <- dplyr::distinct(.REGISTRATION_WATCH_MARKS, family, symbol)
  expect_equal(nrow(marks), nrow(.REGISTRATION_WATCH_MARKS))   # each pattern its own mark
  pd <- prepare_registration_watch_plot_data(watch_payload)
  fam <- function(course) pd$points$family[pd$points$label_text == course][1]
  expect_equal(fam("SPAN 1110"), "short")
  expect_equal(fam("PSYC 1110"), "moving")
  expect_equal(fam("ARTH 1120"), "other")
  size <- function(course) pd$points$size[pd$points$label_text == course][1]
  expect_equal(size("BIOL 2210"), 30)                         # the most students behind a flag
  expect_equal(size("ARTH 1120"), 9)                          # fill alone: no count, smallest
  # Named: the most students first, among those at least 15% off their usual.
  # BIOL 2210 (69 waiting, 1.03 times its usual) sits in the crowded middle;
  # SPAN 1110 on EA (1.6 times, 100%) would sit on BIOL 2305's name (1.36, 99%).
  named <- pd$points[pd$points$label, ]
  expect_equal(sort(paste(named$label_text, named$campus)),
               c("BIOL 2305 ABQ", "FDMA 1520 ABQ", "HIST 1110 ABQ", "PSYC 1110 ABQ", "SPAN 1110 ABQ"))
})

test_that("the chart draws one trace per pattern on a log axis centred on usual", {
  pd <- prepare_registration_watch_plot_data(watch_payload)
  b <- plotly::plotly_build(plot_registration_watch(pd))
  # Drawn other flags first, so they sit under the rest; listed by family.
  traces <- b$x$data[order(vapply(b$x$data, function(t) t$legendrank, numeric(1)))]
  expect_equal(vapply(traces, function(t) t$name, character(1)),
               c("Seats cut", "Students waiting", "Growth near capacity",
                 "Falling demand", "Rising demand", "Drop spike", "Fuller than usual"))
  expect_equal(vapply(b$x$data, function(t) t$legendgroup, character(1))[1:2], c("other", "other"))
  expect_equal(b$x$layout$xaxis$type, "log")
  expect_equal(sum(b$x$layout$xaxis$range), 0)
  expect_equal(b$x$layout$shapes[[1]]$y0, 90)
  expect_error(plot_registration_watch(list(points = pd$points[0, ])), "no course to draw")
})

test_that("the watch reads the fixture Regstats run's context", {
  pd <- prepare_registration_watch_plot_data(build_registration_watch(watch_regstats))
  ea <- pd$points[pd$points$campus == "EA", ]
  expect_equal(ea$x, 4)                                       # 60 against a usual 7.5: off scale
  expect_true(ea$off_scale)
  expect_equal(ea$y, 60)
})

test_that("the chart's note says what it leaves out", {
  testthat::local_edition(3)
  expect_snapshot(cat(registration_watch_plot_note(prepare_registration_watch_plot_data(watch_payload))))
})

test_that("the text preview names each pattern and its courses", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_registration_watch(watch_payload), sep = "\n"))
})
