context("Pathways branch helpers")

test_that("grouped paths count concurrent same-category courses once per student and campus", {
  p <- get_grouped_student_paths(test_students_mc, grouped_path_population,
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt())
  first <- p$cells %>% filter(relative_term == 1, group_id == "languages")
  expect_equal(first$n_students[first$campus == "ABQ"], 4L)
  expect_equal(first$n_students[first$campus == "GA"], 2L)
  second <- p$cells %>% filter(relative_term == 2, campus == "ABQ", group_id == "languages")
  expect_equal(second$n_students, 4L)
  expect_equal(second$n_eligible, 5L)
  # Campus filtering must not re-anchor MC_G1 at term 1 after moving to ABQ.
  scoped <- get_grouped_student_paths(test_students_mc, grouped_path_population,
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt(campus = "ABQ"))
  expect_equal(scoped$cells, filter(p$cells, campus == "ABQ"))
  expect_equal(nrow(filter(p$courses, subject_course == "SPAN 201", campus == "ABQ")), 2L)
})

test_that("grouped paths suppress thin bands and cells without leaking their counts", {
  p <- get_grouped_student_paths(test_students_mc, grouped_path_population,
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt(min_n = 3L, min_band_n = 4L))
  thin_band <- p$cells %>% filter(campus == "GA" | relative_term == 3)
  expect_true(all(is.na(thin_band$n_students)))
  expect_true(all(is.na(thin_band$n_eligible)))
  thin_cell <- p$cells %>% filter(campus == "ABQ", relative_term == 2, group_id == "humanities")
  expect_true(thin_cell$cell_suppressed)
  expect_true(is.na(thin_cell$pct_students))
  expect_true(is.na(thin_cell$n_students))
  expect_false(any(p$courses$subject_course == "PHIL 105"))
  expect_false("student_id" %in% names(p$courses))
  expect_true(all(p$courses$n_students >= 3 & p$courses$n_eligible >= 4))
})

test_that("grouped paths honor population ceilings and the settled observation edge", {
  pop <- grouped_path_population
  pop$relevant_until[pop$student_id == "MC_A1"] <- 202010L
  p <- get_grouped_student_paths(test_students_mc, pop, CEDAR_PATHWAY_SUBJECT_GROUPS,
    grouped_path_opt(data_edges = list(first_enrolled = 202010L, last_enrolled_complete = 202080L)))
  second <- p$cells %>% filter(campus == "ABQ", relative_term == 2, group_id == "languages")
  expect_equal(second$n_students, 3L)
  expect_false(any(p$cells$relative_term > 2))
  expect_error(get_grouped_student_paths(test_students_mc, pop, CEDAR_PATHWAY_SUBJECT_GROUPS,
    list(data_edges = list())), "settled enrollment edge")
  partial <- CEDAR_PATHWAY_SUBJECT_GROUPS %>% filter(subject_code != "PHIL")
  unmapped <- get_grouped_student_paths(test_students_mc, grouped_path_population, partial, grouped_path_opt())
  expect_equal(unmapped$meta$n_unmapped_rows, 1L)
  expect_true("Unmapped coursework" %in% unmapped$cells$group_label)
})


test_that("the courses inside the groups read as one row per campus and course, a column per term", {
  p <- get_grouped_student_paths(test_students_mc, grouped_path_population,
    CEDAR_PATHWAY_SUBJECT_GROUPS, grouped_path_opt())
  t <- degree_path_course_table(p)
  expect_equal(paste0("term_", seq_len(p$meta$max_terms)), grep("^term_", names(t), value = TRUE))
  expect_false(anyDuplicated(t[c("campus", "subject_course")]) > 0L)
  # Every long row lands in its own cell, unchanged; nothing else is filled in.
  for (i in seq_len(nrow(p$courses))) {
    r <- p$courses[i, ]
    row <- t[t$campus == r$campus & t$subject_course == r$subject_course, ]
    expect_equal(row[[paste0("term_", r$relative_term)]], r$pct_students)
    expect_equal(row[[paste0("n_", r$relative_term)]], r$n_students)
  }
  expect_equal(sum(!is.na(as.matrix(t[grep("^term_", names(t))]))), nrow(p$courses))
  # SPAN 201 on ABQ is one row with its two terms.
  span <- t[t$campus == "ABQ" & t$subject_course == "SPAN 201", ]
  expect_equal(nrow(span), 1L)
  expect_equal(sum(!is.na(unlist(span[grep("^term_", names(span))]))), 2L)
  expect_equal(span$peak_pct, max(p$courses$pct_students[p$courses$campus == "ABQ" & p$courses$subject_course == "SPAN 201"]))
  # A group keeps only its own courses.
  langs <- degree_path_course_table(p, "languages")
  expect_true(nrow(langs) > 0L && all(langs$group_id == "languages"))
  expect_error(degree_path_course_table(list(courses = p$courses["campus"], meta = p$meta)), "Course detail missing")
})

test_that("pathways_level_filter translates UI values to CEDAR level values", {
  expect_null(pathways_level_filter("all"))
  expect_null(pathways_level_filter(""))
  expect_equal(pathways_level_filter("undergrad"), c("lower", "upper"))
  expect_equal(pathways_level_filter("lower"), "lower")
  expect_equal(pathways_level_filter("upper"), "upper")
  expect_equal(pathways_level_filter("grad"), "grad")
})


test_that("filter_pathways_analysis_population excludes unclear entry rows only for entry split", {
  hist_pop <- build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_codes = HIST_CODES, split_by = "entry")
  )

  filtered <- filter_pathways_analysis_population(hist_pop, split_by = "entry")

  expect_true("unclear" %in% hist_pop$entry_method)
  expect_false("unclear" %in% filtered$entry_method)
  expect_lt(nrow(filtered), nrow(hist_pop))
})


test_that("filter_pathways_analysis_population applies selected population label", {
  hist_pop <- build_population(
    test_programs, test_degrees,
    opt = list(type = "preset", program_codes = HIST_CODES, split_by = "transfer")
  )
  label <- hist_pop$population_label[1]

  filtered <- filter_pathways_analysis_population(
    hist_pop, split_by = "transfer", selected_label = label
  )

  expect_true(nrow(filtered) > 0)
  expect_true(all(filtered$population_label == label))
})


test_that("resolve_pathways_focal_dept_codes resolves selected program codes", {
  opt <- list(type = "major", program_codes = "HIST-BA")

  dept_codes <- resolve_pathways_focal_dept_codes(opt, test_programs)

  expect_equal(dept_codes, "HIST")
})


test_that("resolve_pathways_focal_subjects uses subjects.csv, not dept code as course prefix", {
  opt <- list(type = "dept", dept_code = "GES")

  subjects <- resolve_pathways_focal_subjects(opt, test_programs, test_dims)

  expect_true("GEOG" %in% subjects)
  expect_false("GES" %in% subjects)
})


test_that("resolve_pathways_gen_ed_courses keeps only focal subject courses", {
  opt <- list(type = "dept", dept_code = "HIST")
  focal_subjects <- resolve_pathways_focal_subjects(opt, test_programs, test_dims)

  courses <- resolve_pathways_gen_ed_courses(focal_subjects)

  expect_true(length(courses) > 0)
  expect_true(all(sub(" .*", "", courses) %in% focal_subjects))
})


test_that("pathways_observation_boundary walks back complete regular terms", {
  # One term of follow-up: Fall 2025 outcomes need Spring 2026 complete.
  expect_equal(pathways_observation_boundary(202610L, 1L), 202580L)
  # Two terms of follow-up (e.g. course-pairs max gap = 2).
  expect_equal(pathways_observation_boundary(202510L, 2L), 202410L)
  # Summer input steps back to the prior regular term.
  expect_equal(pathways_observation_boundary(202560L, 1L), 202510L)
  # Zero follow-up = the boundary is the last complete term itself.
  expect_equal(pathways_observation_boundary(202510L, 0L), 202510L)
})

test_that("pathways_observation_boundary returns NULL when the anchor is unknown", {
  expect_null(pathways_observation_boundary(NULL, 1L))
  expect_null(pathways_observation_boundary(NA_integer_, 1L))
})


# =============================================================================
# pathways_coverage_facts() — what the data window can see about a population
# =============================================================================
#
# These counts back an on-screen disclosure, so the failure that matters is
# overstating coverage: a student whose record is bounded at either end must not
# be counted as fully readable.

test_that("coverage facts count truncation, censoring and complete records", {
  f <- pathways_coverage_facts(cov_pop, min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n, 6)
  expect_equal(f$n_truncated, 2)   # S1, S3
  expect_equal(f$n_censored, 2)    # S2, S3
  expect_equal(f$n_complete, 3)    # S4, S5, S6
  expect_equal(f$pct_complete, 50)
})

test_that("a student at the boundary counts as unreadable, not as a clean start", {
  # first_unm_term == min_data_term cannot be distinguished from "started earlier",
  # so it must fall on the truncated side. Counting it as complete would overstate
  # coverage, which is the one direction this must never fail.
  f <- pathways_coverage_facts(
    tibble::tibble(student_id = "S1", first_unm_term = 202010L, last_record_term = 202310L),
    min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n_truncated, 1)
  expect_equal(f$n_complete, 0)
})

test_that("coverage facts return NA rather than a confident zero when bookends are missing", {
  f <- pathways_coverage_facts(
    tibble::tibble(student_id = c("S1", "S2")),
    min_data_term = 202010L, max_data_term = 202480L)

  expect_equal(f$n, 2)
  expect_true(is.na(f$pct_truncated))
  expect_true(is.na(f$n_complete))
})

test_that("an empty population yields NA counts, not zero coverage", {
  f <- pathways_coverage_facts(cov_pop[0, ], min_data_term = 202010L, max_data_term = 202480L)
  expect_equal(f$n, 0)
  expect_true(is.na(f$pct_truncated))
})

test_that("coverage percentages never exceed 100 or fall below 0", {
  f <- pathways_coverage_facts(cov_pop, min_data_term = 202010L, max_data_term = 202480L)
  for (p in c(f$pct_truncated, f$pct_censored, f$pct_complete)) {
    expect_gte(p, 0); expect_lte(p, 100)
  }
})


# =============================================================================
# latest_graded_term() — the observation boundary comes from the data
# =============================================================================
#
# Deriving it from term arithmetic on cedar_current_term goes stale (grades land
# weeks after a term ends, and nothing moves the boundary until the config is
# edited) and can overshoot (a config set ahead of the data nominates a term
# with no grades, in which every student reads as stopped out).

test_that("the boundary is the last term whose grades are posted", {
  expect_equal(latest_graded_term(graded_students), 202580L)
})

test_that("a term with a trickle of early grades does not qualify", {
  # Spring 2026 sat at 7% on real data — enough to look non-empty, nowhere near
  # enough to measure a DFW rate against.
  expect_equal(latest_graded_term(graded_students, min_graded_share = 0.5), 202580L)
  expect_true(latest_graded_term(graded_students) < 202610L)
})

test_that("the boundary advances on its own once grades land", {
  # The behaviour the arithmetic version could not have: no config edit needed.
  later <- dplyr::bind_rows(
    dplyr::filter(graded_students, term != 202610L),
    tibble::tibble(term = rep(202610L, 100),
                   final_grade = c(rep("A", 88), rep(NA_character_, 12)))
  )
  expect_equal(latest_graded_term(later), 202610L)
})

test_that("max_term caps the boundary without changing the grade rule", {
  expect_equal(latest_graded_term(graded_students, max_term = 202510L), 202480L)
})

test_that("no graded term yields NULL rather than a confident guess", {
  ungraded <- tibble::tibble(term = rep(202680L, 10), final_grade = NA_character_)
  expect_null(latest_graded_term(ungraded))
  expect_null(latest_graded_term(graded_students[0, ]))
})

test_that("missing columns fail loudly", {
  # Delegates to cedar_data_edges(), which owns the schema check.
  expect_error(latest_graded_term(tibble::tibble(term = 202480L)),
               "missing required column")
})


# ── Program choices and the codes a population counted ───────────────────────

test_that("the Majors choices are one per program code, a rename joined, a shared name split", {
  # FSEC is the fixture's dept_code on Secondary Education; units.csv has no
  # FSEC, which real data cannot carry (units come from the mapping files).
  programs <- dplyr::filter(test_programs, dept_code != "FSEC")
  choices <- pathways_population_choice_lists(programs, test_dims, program_rename_successions)
  majors <- choices$program_choices

  # Renamed: one choice, valued by the newest code, listing both codes.
  expect_true("BUMG-BBA" %in% majors)
  expect_false("BUAN-BBA" %in% majors)
  expect_match(names(majors)[majors == "BUMG-BBA"], "\\(BUMG-BBA, BUAN-BBA\\)$")
  # One Banner name ("History"), two programs: two choices.
  expect_true(all(c("HIST-BA", "HIST-MA") %in% majors))
  # Labels are programs.csv's names; a code the file lacks says so, never
  # named after itself (the fixture's HIST-BA is not a UNM code).
  expect_equal(names(majors)[majors == "FDMA"],
               paste0(name_program_codes("FDMA", test_dims)[["FDMA"]], " (FDMA)"))
  expect_equal(names(majors)[majors == "HIST-BA"], "[no programs.csv row] (HIST-BA)")
  # A pre-major is never offered; it joins its program through leads_to.
  expect_false("FFDA" %in% majors)
  expect_equal(unname(majors), unname(majors[order(names(majors))]))

  # Without the rename the two codes are two programs.
  bare <- pathways_population_choice_lists(programs, test_dims, program_rename_successions[0, ])
  expect_true(all(c("BUAN-BBA", "BUMG-BBA") %in% bare$program_choices))

  # Departments are named from units.csv, never by their code.
  depts <- choices$dept_choices
  expect_equal(names(depts)[depts == "HIST"], unit_names(test_dims)$dept_name[unit_names(test_dims)$dept_code == "HIST"])
  expect_error(pathways_population_choice_lists(test_programs, test_dims), "units.csv names no unit FSEC")
})

test_that("the focal program facts name every code a population counted and why", {
  pop <- suppressMessages(build_population(test_programs, test_degrees,
    opt = list(type = "major", program_codes = "BUMG-BBA",
               program_successions = program_rename_successions)))
  facts <- pathways_focal_program_facts(pop, test_programs, test_dims)

  expect_equal(facts$codes$program_code, c("BUMG-BBA", "BUAN-BBA"))
  expect_equal(facts$codes$role, c("selected", "succession"))
  expect_equal(facts$codes$n_students, c(1L, 1L))
  expect_equal(facts$successions$from_code, "BUAN-BBA")
  expect_equal(facts$successions$effective_term, 202080L)

  # A pre-major is listed with the code it leads to.
  film <- suppressMessages(build_population(test_programs, test_degrees,
    opt = list(type = "major", program_codes = "FDMA", premajor_leads_to = c(FFDA = "FDMA"),
               outcomes = c("graduated", "switched_out", "stopped_out", "ongoing",
                            "chose_elsewhere", "left_undeclared"))))
  film_facts <- pathways_focal_program_facts(film, test_programs, test_dims)$codes
  expect_equal(film_facts$role[film_facts$program_code == "FFDA"], "pre_major")
  expect_equal(film_facts$leads_to[film_facts$program_code == "FFDA"], "FDMA")

  # A demographic population has no focal programs and no facts.
  expect_null(pathways_focal_program_facts(tibble::tibble(student_id = "x"), test_programs, test_dims))
})
