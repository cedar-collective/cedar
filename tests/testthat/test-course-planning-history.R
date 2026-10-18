# EC-11 and EC-11b provide raw institutional boundary rows. Edges and metadata
# below are explicit analytical parameters, not institutional fixture tables.
history_edges <- list(last_enrolled_complete = 202080L, last_enrolled = 202180L)
course_history <- function(courses = "SOCI 100", sections = test_sections_regstats,
                           students = test_students_regstats) {
  get_course_planning_history(sections, students, courses, history_edges)
}

# Catalog membership is analytical scaffolding over EC-11's recorded histories.
planning_gen_ed <- function() data.frame(subject_course = c("SOCI 100", "SOCI 101", "SOCI 104"),
  area_label = c("4: Social sciences", "4: Social sciences", "5: Humanities"))

test_that("Gen Ed suggestions retain season, campus and session and suppress small first-day cells", {
  h <- course_history(c("SOCI 100", "SOCI 101", "SOCI 104"))
  x <- get_gen_ed_planning_options(test_sections_regstats, h, planning_gen_ed(), "fall", 3)
  social <- x[x$subject_course == "SOCI 100", ]
  expect_equal(nrow(social), 3L)
  expect_equal(social$first_day_enrl[social$campus == "ABQ" & social$part_term == "1"], 107)
  expect_equal(social$first_day_enrl[social$campus == "ABQ" & social$part_term == "1H"], 28)
  expect_equal(social$first_day_enrl[social$campus == "EA"], 58)
  expect_true(all(social$capacity == 100))
  expect_true(all(x$term <= history_edges$last_enrolled_complete))
  expect_true(all(x$term %% 100 == 80))
  expect_false(anyDuplicated(x[c("campus", "subject_course", "college", "part_term")]) > 0L)
  spring <- get_gen_ed_planning_options(test_sections_regstats, h, planning_gen_ed(), "spring", 3)
  expect_setequal(spring$term, 202010L)
  expect_true(all(spring$season_frequency == "1 of 1"))
  # An earlier source edge makes EA's small 2018 offering the latest one.
  early <- get_course_planning_history(test_sections_regstats, test_students_regstats, "SOCI 100",
    list(last_enrolled_complete = 201880L))
  small <- get_gen_ed_planning_options(test_sections_regstats, early, planning_gen_ed(), "fall", 3)
  expect_true(is.na(small$first_day_enrl[small$campus == "EA"]))
  expect_equal(small$pressure_status[small$campus == "EA"], "Suppressed (<10)")
  expect_error(get_gen_ed_planning_options(select(test_sections_regstats, -credits_min), h,
    planning_gen_ed(), "fall", 3), "missing: credits_min")
})

test_that("allowance popups disclose credit fit and exclude courses already represented by the plan", {
  v <- build_degree_roadmap_view(CEDAR_DEGREE_CATALOG, CEDAR_DEGREE_ROADMAPS,
    "cs-bs-2026", "calculus", "composition")
  selection <- list(type = "allowance", catalog_id = "cs-bs-2026", math_start = "calculus",
    english_start = "composition", start_season = "fall", node_id = v$allowances$node_id[1])
  membership <- rbind(planning_gen_ed(), data.frame(subject_course = c("MATH 1512", "ENGL 1120"),
    area_label = c("2: Math", "1: Communication")))
  h <- build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    CEDAR_DEGREE_CATALOG, CEDAR_DEGREE_ROADMAPS, membership, selection)
  expect_equal(h$kind, "allowance")
  expect_equal(h$season, "fall")
  # The 123-credit workload uses the permitted 16-credit ceiling here: the
  # first semester's 14 shown credits leave a two-credit remainder.
  expect_equal(h$credits, 2)
  expect_true(all(h$table$credit_fit == "Needs more credits"))
  expect_false(any(c("MATH 1512", "ENGL 1120") %in% h$missing_courses))
  expect_match(h$credit_note, "rather than a complete course", fixed = TRUE)
  expect_match(format_degree_allowance_preview(h), "SOCI 100 · ABQ", fixed = TRUE)
  expect_false(any(c("student_id", "crn") %in% names(h$table)))
  selection$node_id <- "allowance-99-1"
  expect_error(build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    CEDAR_DEGREE_CATALOG, CEDAR_DEGREE_ROADMAPS, membership, selection), "Unknown degree allowance")
})

test_that("course pressure retains campus, college and session and uses first-day capacity", {
  h <- course_history()
  full <- h$pressure %>% filter(campus == "ABQ", part_term == "1", term == 202080L)
  half <- h$pressure %>% filter(campus == "ABQ", part_term == "1H", term == 202080L)
  online <- h$pressure %>% filter(campus == "EA", term == 202080L)
  expect_equal(full$first_day_enrl, 107)
  expect_equal(full$capacity, 100)
  expect_equal(full$first_day_fill, 1.07)
  expect_true(full$near_full)
  expect_equal(half$first_day_enrl, 28)
  expect_equal(half$first_day_fill, .28)
  expect_equal(online$first_day_enrl, 58)
  expect_equal(online$first_day_fill, .58)
  first_day <- calc_first_day_enrl(test_students_regstats, test_sections_regstats, by_part_term = TRUE)
  at <- first_day %>% filter(campus == "ABQ", subject_course == "SOCI 100", term == 202080L)
  expect_equal(at$first_day_enrl[at$part_term == "1"], 107L)
  expect_equal(at$first_day_enrl[at$part_term == "1H"], 28L)
  expect_false(any(h$pressure$term > history_edges$last_enrolled_complete))
  term <- h$terms %>% filter(campus == "ABQ", term == 202080L)
  expect_equal(term$capacity, 200)
  expect_true(term$near_full) # A constrained full-term session cannot be diluted.
  expect_equal(nrow(h$pressure), 10L)
})

test_that("frequency includes observed source terms when a course was absent", {
  h <- course_history("SOCI 104")
  fall <- h$frequency %>% filter(campus == "ABQ", term_type == "fall")
  spring <- h$frequency %>% filter(campus == "ABQ", term_type == "spring")
  summer <- h$frequency %>% filter(campus == "ABQ", term_type == "summer")
  expect_equal(fall$offered_terms, 1L)
  expect_equal(fall$eligible_terms, 3L)
  expect_equal(spring$offered_terms, 0L)
  expect_equal(spring$eligible_terms, 1L)
  expect_equal(summer$eligible_terms, 0L) # Not inferred to be a non-offering.
  h <- course_history()
  fall <- h$frequency %>% filter(campus == "ABQ", term_type == "fall")
  expect_equal(fall$typical_seats, 200)
  expect_equal(fall$near_full_terms, 1L)
  expect_equal(fall$scored_terms, 2L) # The oldest half-term first-day cell is small.
  pair <- course_history(c("SOCI 100", "SOCI 101"))
  expect_false(any(pair$frequency$subject_course == "SOCI 101" & pair$frequency$campus == "EA"))
  expect_equal(nrow(distinct(pair$frequency, subject_course, campus)), 3L)
})

test_that("unmatched, implausible, small and missing capacity histories fail closed", {
  h <- course_history(c("SOCI 100", "SOCI 101", "SOCI 102", "SOCI 103", "SOCI 104"),
    test_sections_course_history, test_students_course_history)
  p <- h$pressure
  expect_false(any(p$subject_course == "SOCI 102" & p$term == 202080L))
  expect_true(is.na(p$capacity[p$subject_course == "SOCI 103" & p$term == 202080L]))
  no_match <- p %>% filter(subject_course == "SOCI 104")
  expect_false(no_match$source_matched)
  expect_true(is.na(no_match$first_day_fill))
  partial <- p %>% filter(subject_course == "SOCI 101", term == 202080L)
  expect_false(partial$source_matched)
  expect_false(partial$pressure_known)
  expect_equal(partial$capacity, 200)
  expect_true(is.na(partial$near_full))
  small <- p %>% filter(subject_course == "SOCI 100", campus == "EA", term == 201880L)
  expect_true(small$small_cell)
  expect_true(is.na(small$first_day_enrl) && is.na(small$first_day_fill) && is.na(small$near_full))
  expect_true(is.na(small$capacity_constrained))
  spring <- h$frequency %>% filter(subject_course == "SOCI 100", campus == "ABQ", term_type == "spring")
  expect_equal(spring$offered_terms, 1L)
  expect_equal(spring$scored_terms, 0L)
  undated <- p %>% filter(subject_course == "SOCI 101", term == 201980L)
  expect_false(undated$first_day_known)
  expect_false(undated$pressure_known)
  expect_true(is.na(undated$first_day_enrl))
  expect_equal(undated$pressure_status, "First-day dates unavailable")
  expect_true(is.na(partial$first_day_enrl)) # A partial match never exposes a partial count.
  expect_equal(get_course_planning_history(test_sections, test_students, "none", list())$state, "unavailable")
  expect_equal(course_history("CSCI 1260")$state, "empty")
  expect_error(course_history(sections = select(test_sections_regstats, -available)), "missing: available")
})

test_that("history components are explicit and unenumerated groups and renamed courses stay unresolved", {
  r <- CEDAR_DEGREE_ROADMAPS
  expect_setequal(r$courses$subject_course[r$courses$node_id == "chem1"], c("CHEM 1215", "CHEM 1215L"))
  group <- build_degree_course_history(test_sections, test_students, history_edges, r, "cs-bs-2026", "communication")
  expect_equal(group$state, "choice")
  science <- build_degree_course_history(test_sections, test_students, history_edges, r, "cs-bs-2026", "science1")
  expect_equal(science$state, "ready")
  expect_setequal(union(science$missing_courses, science$table$subject_course),
    r$options$subject_course[r$options$catalog_id == "cs-bs-2026" & r$options$node_id == "science1"])
  course <- build_degree_course_history(test_sections, test_students, history_edges, r, "cs-bs-2026", "java1")
  expect_equal(course$state, "empty")
  expect_equal(course$missing_courses, "CSCI 1260")
  bad <- r; bad$courses$subject_course[bad$courses$node_id == "java1"] <- "CS 152L"
  expect_error(validate_degree_roadmaps(bad, CEDAR_DEGREE_CATALOG), "components disagree")
})

# Missing rows and source windows are fixture-backed; they are not zeros in a chart.
test_that("the single history table distinguishes non-offerings and missing source coverage", {
  h <- course_history("SOCI 104")
  spring <- h$offerings %>% filter(campus == "ABQ", term == 202010L)
  expect_equal(spring$pressure_status, "Not offered")
  expect_equal(spring$capacity, 0)
  expect_true(is.na(spring$first_day_enrl))
  summer <- h$offerings %>% filter(campus == "ABQ", term == 202060L)
  expect_equal(summer$pressure_status, "Source unavailable")
  expect_true(is.na(summer$capacity))
  pair <- course_history(c("SOCI 100", "SOCI 101"))
  expect_false(any(pair$offerings$subject_course == "SOCI 101" & pair$offerings$campus == "EA"))
  expect_error(course_history(students = select(test_students_regstats, -registration_date)), "missing: registration_date")
})
