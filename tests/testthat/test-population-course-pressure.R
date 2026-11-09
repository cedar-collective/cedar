# The population course pressure preview and the three cones behind it, on
# HP02: a pre-nursing population of twelve through BIOL 1140, CHEM 1215 and
# NUTR 2110. Every expected number is pinned in the fixture header.

hp2_edges <- cedar_data_edges(test_students_hp2)
hp2_attempts <- attempts_for(test_students_hp2, hp2_edges)
hp2_course_terms <- course_terms_for(test_students_hp2, test_sections_hp2, hp2_edges)
hp2_population <- suppressMessages(build_population(
  test_programs_hp2, opt = list(type = "preset", program_names = "Nursing")
))
hp2_courses <- c("BIOL 1140", "CHEM 1215", "NUTR 2110")

test_that("HP02 settles as the header says", {
  expect_equal(hp2_edges$last_graded, 202080L)
  expect_equal(hp2_edges$last_enrolled_complete, 202110L)
  expect_equal(nrow(hp2_population), 12L)
  expect_true(all(hp2_population$outcome == "ongoing"))
  expect_true(all(is.na(hp2_population$relevant_until)))
  entry <- setNames(hp2_population$first_unit_term, hp2_population$student_id)
  expect_equal(unname(entry[sprintf("HP2-P%02d", 1:8)]), rep(202010L, 8))
  expect_equal(unname(entry[sprintf("HP2-P%02d", 9:12)]), rep(202080L, 4))
})


# ── get_population_course_uptake() ───────────────────────────────────────────

test_that("uptake counts takers, entry timing and suppresses small rows", {
  up <- get_population_course_uptake(
    test_students_hp2, hp2_population,
    list(course = c(hp2_courses, "PHYS 1110"), data_edges = hp2_edges, min_n = 2L)
  )
  expect_equal(up$subject_course, c("BIOL 1140", "CHEM 1215"))
  expect_equal(up$campus, c("ABQ", "ABQ"))
  biol <- up[up$subject_course == "BIOL 1140", ]
  expect_equal(biol$n_takers, 11L)
  expect_equal(biol$n_population, 12L)
  expect_equal(biol$share, 11 / 12)
  expect_equal(biol$n_before_entry, 1L)   # P09, before entering at 202080
  expect_equal(biol$n_after_entry, 10L)
  expect_equal(biol$median_terms_after_entry, 0)
  expect_equal(biol$p75_terms_after_entry, 0)
  chem <- up[up$subject_course == "CHEM 1215", ]
  expect_equal(chem$n_takers, 4L)
  expect_equal(chem$median_terms_after_entry, 1.5)
  expect_equal(chem$p75_terms_after_entry, 2)

  suppressed <- attr(up, "suppressed")
  expect_equal(suppressed$subject_course, "NUTR 2110")
  expect_equal(suppressed$n_takers, 1L)
  expect_equal(attr(up, "not_taken"), "PHYS 1110")
  expect_equal(attr(up, "edge"), 202110L)
  expect_equal(attr(up, "n_without_entry"), 0L)
})

test_that("uptake pins summer to the spring before it and stops at the settled edge", {
  # P05's summer retake is a later take; the first take decides the timing.
  # With the edge moved back to Fall 2020, the Spring 2021 rows vanish:
  # CHEM 1215 keeps P01 and P02 only.
  earlier <- modifyList(hp2_edges, list(last_enrolled_complete = 202080L))
  up <- get_population_course_uptake(
    test_students_hp2, hp2_population,
    list(course = hp2_courses, data_edges = earlier, min_n = 1L)
  )
  chem <- up[up$subject_course == "CHEM 1215", ]
  expect_equal(chem$n_takers, 2L)
  expect_equal(chem$median_terms_after_entry, 1)
})

test_that("uptake keeps campus beside the course", {
  # P07's Spring 2021 retake moved to another campus is a second row for the
  # course, not a taker folded into ABQ's.
  moved <- test_students_hp2 %>%
    mutate(campus = if_else(student_id == "HP2-P07" & term == 202110L, "GA", campus))
  up <- get_population_course_uptake(
    moved, hp2_population, list(course = "BIOL 1140", data_edges = hp2_edges, min_n = 1L)
  )
  expect_equal(up$campus, c("ABQ", "GA"))
  expect_equal(up$n_takers, c(11L, 1L))
  expect_equal(up$median_terms_after_entry, c(0, 2))
  scoped <- get_population_course_uptake(
    moved, hp2_population,
    list(course = "BIOL 1140", campus = "ABQ", data_edges = hp2_edges, min_n = 1L)
  )
  expect_equal(scoped$campus, "ABQ")
})

test_that("uptake refuses to run without a settled edge or a course", {
  expect_error(
    get_population_course_uptake(test_students_hp2, hp2_population, list(course = "BIOL 1140")),
    "last_enrolled_complete"
  )
  expect_error(
    get_population_course_uptake(test_students_hp2, hp2_population, list(data_edges = hp2_edges)),
    "course is required"
  )
})


# ── get_course_retake_timing() ───────────────────────────────────────────────

test_that("retake timing classifies each DFW's first retake and holds out recent ones", {
  rt <- get_course_retake_timing(
    hp2_attempts, test_students_hp2,
    list(course = "BIOL 1140", population_ids = hp2_population$student_id,
         data_edges = hp2_edges, min_n = 1L)
  )
  expect_equal(nrow(rt), 1L)
  expect_equal(rt$campus, "ABQ")
  expect_equal(rt$n_dfw, 4L)                 # P05, P06, P07, P08
  expect_equal(rt$n_summer, 1L)              # P05, Summer 2020
  expect_equal(rt$n_next_regular, 1L)        # P06, Fall 2020 (the 2H section)
  expect_equal(rt$n_within_year_other, 1L)   # P07, Spring 2021
  expect_equal(rt$n_none_within_year, 1L)    # P08
  expect_equal(rt$n_unobservable, 1L)        # P11's Fall 2020 DFW; its year ends 202180

  everyone <- get_course_retake_timing(
    hp2_attempts, test_students_hp2,
    list(course = "BIOL 1140", data_edges = hp2_edges, min_n = 1L)
  )
  expect_equal(everyone$n_dfw, 5L)           # plus N02
  expect_equal(everyone$n_none_within_year, 2L)
})

test_that("retake timing suppresses small rows and returns no rows without a DFW", {
  rt <- get_course_retake_timing(
    hp2_attempts, test_students_hp2,
    list(course = "BIOL 1140", data_edges = hp2_edges, min_n = 10L)
  )
  expect_equal(nrow(rt), 0L)
  expect_equal(attr(rt, "suppressed")$n_dfw, 5L)
  none <- get_course_retake_timing(
    hp2_attempts, test_students_hp2,
    list(course = "CHEM 1215", data_edges = hp2_edges, min_n = 1L)
  )
  expect_equal(nrow(none), 0L)
  expect_true(all(c("n_dfw", "n_next_regular", "n_unobservable") %in% names(none)))
})

test_that("retake timing needs the settled edge and agrees with the table's graded edge", {
  expect_error(
    get_course_retake_timing(hp2_attempts, test_students_hp2, list(course = "BIOL 1140")),
    "last_enrolled_complete"
  )
  expect_error(
    get_course_retake_timing(
      hp2_attempts, test_students_hp2,
      list(course = "BIOL 1140", data_edges = modifyList(hp2_edges, list(last_graded = 202010L)))
    ),
    "built to"
  )
})


# ── get_course_offering_pattern() ────────────────────────────────────────────

test_that("offering pattern counts seasons, parts of term, seats and first-day fill", {
  off <- get_course_offering_pattern(
    hp2_course_terms, list(course = hp2_courses, data_edges = hp2_edges, n_years = 3L)
  )
  expect_equal(attr(off, "window"), c(first = 202010L, last = 202110L))
  expect_true(all(off$campus == "ABQ"))
  key <- paste(off$subject_course, off$term_type, off$part_term)
  expect_setequal(key, c("BIOL 1140 spring 1", "BIOL 1140 summer 1", "BIOL 1140 fall 1",
                         "BIOL 1140 fall 2H", "CHEM 1215 fall 1", "CHEM 1215 spring 1",
                         "NUTR 2110 fall 1"))
  row <- function(course, season, part) off[key == paste(course, season, part), ]

  spring <- row("BIOL 1140", "spring", "1")
  expect_equal(spring$n_terms_offered, 2L)
  expect_equal(spring$n_terms_in_window, 2L)
  expect_equal(spring$last_offered, 202110L)
  expect_equal(spring$median_sections, 1)
  expect_equal(spring$median_seats, 12)
  expect_equal(spring$n_terms_fill_known, 2L)
  expect_equal(spring$median_first_day_fill, median(c(12 / 12, 2 / 12)))
  expect_equal(spring$n_terms_full, 1L)
  expect_equal(spring$n_terms_near_full, 1L)

  summer <- row("BIOL 1140", "summer", "1")
  expect_equal(c(summer$n_terms_offered, summer$n_terms_in_window), c(1L, 1L))
  expect_equal(summer$median_seats, 20)
  expect_equal(summer$median_first_day_fill, 2 / 20)

  half <- row("BIOL 1140", "fall", "2H")
  expect_equal(half$median_seats, 10)
  expect_equal(half$median_first_day_fill, 2 / 10)
  expect_equal(half$n_terms_full, 0L)

  chem_spring <- row("CHEM 1215", "spring", "1")
  expect_equal(c(chem_spring$n_terms_offered, chem_spring$n_terms_in_window), c(1L, 2L))
  expect_equal(chem_spring$median_first_day_fill, 2 / 24)
})

test_that("offering pattern stops at the settled edge and refuses an unknown fill", {
  earlier <- modifyList(hp2_edges, list(last_enrolled_complete = 202080L))
  off <- get_course_offering_pattern(
    hp2_course_terms, list(course = "BIOL 1140", data_edges = earlier, n_years = 3L)
  )
  expect_equal(max(off$last_offered), 202080L)
  spring <- off[off$term_type == "spring", ]
  expect_equal(c(spring$n_terms_offered, spring$n_terms_in_window), c(1L, 1L))

  # A section whose capacity is unknown offers, but its fill is unknown, never
  # a partial figure.
  blind <- test_sections_hp2 %>%
    mutate(available = if_else(crn == "HP2-B1140-SU20", NA_integer_, available))
  blind_terms <- course_terms_for(test_students_hp2, blind, hp2_edges)
  off <- get_course_offering_pattern(
    blind_terms, list(course = "BIOL 1140", data_edges = hp2_edges)
  )
  summer <- off[off$term_type == "summer", ]
  expect_equal(summer$n_terms_offered, 1L)
  expect_equal(summer$n_terms_fill_known, 0L)
  expect_true(is.na(summer$median_first_day_fill))
  expect_true(is.na(summer$median_seats))
})

test_that("offering pattern requires a built table, a course and the edge", {
  expect_error(get_course_offering_pattern(test_sections_hp2, list(course = "BIOL 1140",
                                                                   data_edges = hp2_edges)),
               "build_course_terms")
  expect_error(get_course_offering_pattern(hp2_course_terms, list(data_edges = hp2_edges)),
               "course is required")
  expect_error(get_course_offering_pattern(hp2_course_terms, list(course = "BIOL 1140")),
               "last_enrolled_complete")
})


# ── build_population_course_pressure() and its text ─────────────────────────

hp2_plans <- tibble::tribble(
  ~catalog_id,        ~subject_course,
  "nursing-bsn-2026", "BIOL 1140",
  "nursing-bsn-2026", "CHEM 1215",
  "medlab-bs-2026",   "BIOL 1140",
  "medlab-bs-2026",   "NUTR 2110",
  "pophealth-bs-2026", "BIOL 1140"
)

test_that("the payload joins the four measures on course and campus", {
  payload <- build_population_course_pressure(
    hp2_population, test_students_hp2, hp2_attempts, hp2_course_terms,
    list(courses = hp2_courses, plan_courses = hp2_plans, data_edges = hp2_edges,
         min_n = 2L, n_years = 3L, label = "Pre-nursing")
  )
  expect_s3_class(payload, "population_course_pressure")
  courses <- payload$courses
  expect_equal(courses$subject_course, hp2_courses)
  expect_true(all(courses$campus == "ABQ"))
  expect_equal(courses$n_plans, c(3L, 1L, 1L))
  expect_equal(courses$plans[[1]], "medlab-bs-2026, nursing-bsn-2026, pophealth-bs-2026")

  biol <- courses[1, ]
  expect_equal(biol$n_takers, 11L)
  expect_equal(biol$share, 11 / 12)
  expect_equal(c(biol$pop_n_attempts, biol$pop_n_dfw), c(13L, 5L))
  expect_equal(biol$pop_dfw_pct, round(100 * 5 / 13, 2))
  expect_equal(c(biol$all_n_attempts, biol$all_n_dfw), c(18L, 6L))
  expect_equal(biol$all_dfw_pct, round(100 * 6 / 18, 2))
  expect_equal(biol$n_dfw_judged, 4L)
  expect_equal(biol$n_unobservable, 1L)
  expect_false(biol$uptake_suppressed)
  expect_false(biol$retake_suppressed)

  chem <- courses[2, ]
  expect_equal(c(chem$pop_n_attempts, chem$pop_n_dfw), c(2L, 0L))
  expect_equal(c(chem$all_n_attempts, chem$all_n_dfw), c(3L, 0L))
  expect_true(is.na(chem$n_dfw_judged))      # no DFW, nothing to judge

  nutr <- courses[3, ]
  expect_true(nutr$uptake_suppressed)
  expect_true(is.na(nutr$n_takers))
  expect_true(is.na(nutr$pop_n_attempts))    # 1 attempt, under min_n

  expect_equal(payload$meta$n_population, 12L)
  expect_equal(payload$meta$settled_edge, 202110L)
  expect_equal(payload$meta$graded_edge, 202080L)
  expect_equal(payload$meta$n_plans, 3L)
  expect_equal(nrow(payload$offerings), 7L)
})

test_that("the courses come from the plans when none are named", {
  payload <- build_population_course_pressure(
    hp2_population, test_students_hp2, hp2_attempts, hp2_course_terms,
    list(plan_courses = hp2_plans, min_plans = 2L, data_edges = hp2_edges, min_n = 2L)
  )
  expect_equal(payload$meta$courses, "BIOL 1140")
  expect_equal(payload$courses$subject_course, "BIOL 1140")
  expect_error(
    build_population_course_pressure(
      hp2_population, test_students_hp2, hp2_attempts, hp2_course_terms,
      list(plan_courses = hp2_plans, min_plans = 4L, data_edges = hp2_edges)
    ),
    "No course is required by 4"
  )
  expect_error(
    build_population_course_pressure(
      hp2_population, test_students_hp2, hp2_attempts, hp2_course_terms,
      list(courses = "BIOL 1140")
    ),
    "data_edges"
  )
})

test_that("the text preview rounds once and names every suppression", {
  payload <- build_population_course_pressure(
    hp2_population, test_students_hp2, hp2_attempts, hp2_course_terms,
    list(courses = hp2_courses, plan_courses = hp2_plans, data_edges = hp2_edges,
         min_n = 2L, label = "Pre-nursing")
  )
  text <- format_population_course_pressure(payload)
  expect_type(text, "character")
  expect_equal(text[[1]], "Population course pressure: Pre-nursing")
  expect_match(text[[2]], "Population: 12 students")
  expect_match(text[[3]], "settled through Spring 2021; grades through Fall 2020")
  one <- function(pattern) {
    hits <- grep(pattern, text, fixed = TRUE, value = TRUE)
    expect_length(hits, 1L)
    hits
  }
  one("BIOL 1140 (ABQ) — required by 3 plans: medlab-bs-2026, nursing-bsn-2026, pophealth-bs-2026")
  one("Taken by 11 of 12 (91.7%); 1 before entering the unit; of the 10 at or after entry, median 0 terms after entry (75th percentile 0 terms)")
  one("median 1.5 terms after entry (75th percentile 2 terms)")
  one("DFW: population 38.5% of 13 attempts; all students 33.3% of 18 attempts")
  one("After a DFW (population): 4 judged; retook next regular term 25.0%, in a summer 25.0%, later within the year 25.0%, not within a year 25.0%; 1 too recent to judge")
  offered <- one("Offered: Fall full term 1 of 1 (median 1 section, 30 seats; day-1 fill 10% median, full 0 of 1, near full 0 of 1); Fall 2H 1 of 1 (median 1 section, 10 seats; day-1 fill 20% median, full 0 of 1, near full 0 of 1); Spring full term 2 of 2")
  expect_match(offered, "Spring full term 2 of 2 (median 1 section, 12 seats; day-1 fill 58% median, full 1 of 2, near full 1 of 2)", fixed = TRUE)
  expect_match(offered, "Summer full term 1 of 1 (median 1 section, 20 seats; day-1 fill 10% median", fixed = TRUE)
  one("Spring full term 1 of 2 (median 1 section, 24 seats; day-1 fill 8% median")
  one("Taken by fewer than 2 of 12; uptake suppressed")
  one("DFW: population suppressed or none; all students suppressed or none")
  expect_error(format_population_course_pressure(list()), "build_population_course_pressure")
})
