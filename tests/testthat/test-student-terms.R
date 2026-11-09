# Tests for R/branches/student-terms.R — one row per student-term
#
# Contract: docs/developers/student-terms.md. Fixture: ST01, eleven students,
# each guarding one rule. Mutation checks recorded 2026-11-03 — each of these
# breaks the named assertion when reintroduced:
#   enrolled = registered only                -> ST_A enrolled/returned (I44)
#   a DW counted as a DFW grade               -> ST_H dfw_grades
#   every Major row as primary                -> ST_G primary_major_code
#   class list winning precedence             -> ST_F classification
#   Summer as a return term                   -> ST_D returned
#   returned FALSE past the settled edge      -> ST_I returned NA
#   a return judged into a term with no pull  -> gap test, ST_A return_observable
#   retention reading registered rows only    -> I44 cross-tab, ret_1 0.2 not 0.3

context("Student terms")

st01 <- function() build_student_terms(test_students_st, test_programs_st, test_degrees_st)
row <- function(st, sid, term) {
  r <- st[st$student_id == sid & st$term == term, ]
  if (nrow(r) != 1L) stop("expected one row for ", sid, " ", term, ", got ", nrow(r))
  r
}


test_that("one row per student-term with any class-list row or declaration, pinned", {
  st <- st01()
  expect_equal(nrow(st), 17L)
  expect_equal(sum(st$enrolled), 14L)
  expect_equal(sum(st$declared & st$class_list_rows == 0L), 1L)
  expect_equal(sum(st$description_conflict), 1L)
  expect_equal(sum(st$degree_awarded), 1L)
  expect_equal(names(st), STUDENT_TERMS_COLUMNS)
  expect_false(any(STUDENT_TERMS_BANNED_COLUMNS %in% names(st)))
})

test_that("ST_A: a late withdrawal next term is enrolled, so the student returned (I44)", {
  st <- st01()
  a80 <- row(st, "ST_A", 202080L)
  expect_true(a80$enrolled)
  expect_equal(a80$class_list_rows, 1L)
  expect_equal(a80$registered_courses, 0L)
  expect_equal(a80$late_withdrawals, 1L)
  a10 <- row(st, "ST_A", 202010L)
  expect_equal(a10$next_regular_term, 202080L)
  expect_true(a10$return_observable)
  expect_true(a10$returned_next_regular_term)
})

test_that("ST_B and ST_C: an early drop or a waitlist next term is a row, not enrollment", {
  st <- st01()
  b80 <- row(st, "ST_B", 202080L)
  expect_false(b80$enrolled)
  expect_equal(b80$class_list_rows, 1L)
  expect_equal(b80$early_drops, 1L)
  expect_false(row(st, "ST_B", 202010L)$returned_next_regular_term)
  c80 <- row(st, "ST_C", 202080L)
  expect_false(c80$enrolled)
  expect_true(c80$waitlisted_only)
  expect_false(row(st, "ST_C", 202010L)$returned_next_regular_term)
  expect_false(row(st, "ST_A", 202080L)$waitlisted_only)
})

test_that("ST_D: Summer is not a return term", {
  st <- st01()
  d10 <- row(st, "ST_D", 202010L)
  expect_equal(d10$next_regular_term, 202080L)
  expect_false(d10$returned_next_regular_term)
  d60 <- row(st, "ST_D", 202060L)
  expect_true(d60$enrolled)
  expect_equal(d60$next_regular_term, 202080L)
  expect_false(d60$returned_next_regular_term)
})

test_that("ST_E: a declaration with no class list is a row with enrolled FALSE", {
  st <- st01()
  e80 <- row(st, "ST_E", 202080L)
  expect_true(e80$declared)
  expect_false(e80$enrolled)
  expect_equal(e80$class_list_rows, 0L)
  expect_equal(e80$description_source, "programs")
  expect_true(is.na(e80$classlist_as_of))
  expect_equal(e80$primary_major_code, "HIST")
  expect_false(row(st, "ST_E", 202010L)$returned_next_regular_term)
})

test_that("ST_F: the newest class-list pull is read, programs wins, and the conflict is flagged", {
  st <- st01()
  f <- row(st, "ST_F", 202010L)
  expect_equal(f$student_classification, "Sophomore, 2nd Yr")
  expect_equal(f$description_source, "programs")
  expect_true(f$description_conflict)
  expect_equal(f$classlist_as_of, as.Date("2021-02-15"))
  # a student whose two sources agree is both_agree, not a conflict
  a <- row(st, "ST_A", 202010L)
  expect_equal(a$description_source, "both_agree")
  expect_false(a$description_conflict)
})

test_that("ST_G: the primary major is the first Major row by code, and every declaration is counted", {
  st <- st01()
  g <- row(st, "ST_G", 202010L)
  expect_equal(g$primary_major_code, "AA")
  # The table stores the primary major's keys, never its unit (ADR-001 step 3).
  expect_equal(g$primary_source_college_code, "AS")
  expect_equal(g$primary_source_college, "College of Arts and Sciences")
  expect_false(any(STUDENT_TERMS_ATTACHED_COLUMNS %in% names(st)))
  expect_equal(g$n_declarations, 3L)
  expect_true(g$declared)
  expect_false(g$is_pre_major)
})

test_that("ST_H: late drops are withdrawals, never DFW grades; credits follow the registered rows", {
  st <- st01()
  h <- row(st, "ST_H", 202010L)
  expect_equal(h$class_list_rows, 3L)
  expect_equal(h$registered_courses, 2L)
  expect_equal(h$late_withdrawals, 1L)
  expect_equal(h$dfw_grades, 1L)      # the C-
  expect_equal(h$graded_rows, 2L)
  expect_equal(h$attempted_unm_credits, 6)
  expect_equal(h$completed_unm_credits, 3)   # A earns credit under passing_grades; C- does not
})

test_that("ST_I: a return past the settled edge is NA, never FALSE", {
  st <- st01()
  i <- row(st, "ST_I", 202110L)
  expect_equal(i$next_regular_term, 202180L)
  expect_false(i$return_observable)
  expect_true(is.na(i$returned_next_regular_term))
  expect_true(all(!is.na(st$returned_next_regular_term[st$return_observable])))
})

test_that("a Fall or Spring with no class list makes the return into it unobservable, never FALSE", {
  # Drop every Fall 2020 class-list row: Spring 2020 and Spring 2021 remain,
  # the settled edge still reaches Spring 2021, and Fall 2020 is a gap. Before
  # this rule, every Spring 2020 student read as not returning.
  expect_message(
    st <- build_student_terms(dplyr::filter(test_students_st, term != 202080L),
                              test_programs_st, test_degrees_st),
    "no class list for Fall 2020")
  a <- row(st, "ST_A", 202010L)
  expect_equal(a$next_regular_term, 202080L)
  expect_false(a$return_observable)
  expect_true(is.na(a$returned_next_regular_term))
  # Summer 2020's next regular term is the same gap.
  expect_false(row(st, "ST_D", 202060L)$return_observable)
  expect_false(any(st$return_observable[st$next_regular_term == 202080L]))
  # The complete fixture judges Spring 2020 returns, as ST_A shows.
  expect_true(row(st01(), "ST_A", 202010L)$return_observable)
})

test_that("ST_J: a degree awarded sits beside the return flag; the table does not combine them", {
  st <- st01()
  j <- row(st, "ST_J", 202010L)
  expect_true(j$degree_awarded)
  expect_false(j$returned_next_regular_term)
  expect_equal(sum(st$degree_awarded), 1L)
})

test_that("ST_K: with no programs row the class list describes the student, in code vocabulary", {
  st <- st01()
  k <- row(st, "ST_K", 202010L)
  expect_equal(k$description_source, "class_list")
  expect_false(k$declared)
  expect_equal(k$n_declarations, 0L)
  expect_true(is.na(k$academic_standing))
  expect_equal(k$student_level, "UG")
  expect_equal(k$student_campus, "ABQ")
  # The primary major is the one Banner stamped on the roster (SPAN), with the
  # roster's college as the key it resolves under and the file's pre-major
  # flag. Attached at load through the institution's files, it carries the
  # file's unit, never the code itself. A student with a programs row (ST_A)
  # keeps academic studies' major.
  files <- read_institution_mappings()
  expect_equal(k$primary_major_code, "SPAN")
  roster_college <- unique(test_students_st$student_college[test_students_st$student_id == "ST_K"])
  expect_length(roster_college, 1L)
  expect_equal(k$primary_source_college_code, roster_college)
  expect_equal(k$primary_source_college, roster_college)
  attached <- suppressMessages(attach_default_units(
    list(cedar_student_terms = st), build_cedar_dims(files)))$cedar_student_terms
  k_att <- row(attached, "ST_K", 202010L)
  key <- dplyr::coalesce(translate_source_college(roster_college, files), "")
  expect_equal(k_att$primary_dept_code, resolve_program_units("SPAN", key, files$programs))
  expect_false(is.na(k_att$primary_dept_code))
  expect_equal(k_att$primary_college_code, resolve_program_colleges("SPAN", key, files))
  expect_equal(names(attached), c(STUDENT_TERMS_COLUMNS, STUDENT_TERMS_ATTACHED_COLUMNS))
  expect_equal(k$is_pre_major, program_pre_major_flags("SPAN", files$programs))
  expect_equal(row(st, "ST_A", 202010L)$primary_major_code, "HIST")
  expect_equal(attr(st, "cedar_student_terms_build_version"), STUDENT_TERMS_BUILD_VERSION)
  # the programs names resolve to the same codes through the institution's files
  a <- row(st, "ST_A", 202010L)
  expect_equal(a$student_level, "UG")
  expect_equal(a$student_campus, "ABQ")
  expect_equal(a$academic_standing, "Good Standing")
  expect_equal(a$sem_gpa, 3.5)
  expect_true(row(st, "ST_K", 202080L)$returned_next_regular_term == FALSE |
                is.na(row(st, "ST_K", 202080L)$returned_next_regular_term))
})

test_that("credit position is a running total over the student's terms", {
  st <- st01()
  k10 <- row(st, "ST_K", 202010L); k80 <- row(st, "ST_K", 202080L)
  expect_equal(k10$unm_credits_entering, 0)
  expect_equal(k10$cumulative_attempted_unm_credits, 3)
  expect_equal(k80$unm_credits_entering, 3)
  expect_equal(k80$cumulative_attempted_unm_credits, 6)
  # ST_K passed both courses (A, B), so the completed total runs beside it;
  # ST_H's C- and DW earn nothing, so theirs stops at the A's credits.
  expect_equal(k10$cumulative_completed_unm_credits, 3)
  expect_equal(k80$cumulative_completed_unm_credits, 6)
  expect_equal(row(st, "ST_H", 202010L)$cumulative_completed_unm_credits, 3)
  # every ST01 student first appears in the data's first term, so none is valid
  expect_false(any(st$timeline_valid[st$student_id != "ST_I"]))
  expect_true(row(st, "ST_I", 202110L)$timeline_valid)
})

test_that("grade points and graded hours run beside the credits (ADR-001 step 7 group 4)", {
  st <- st01()
  # ST_K: an A (4.0 x 3) then a B (3.0 x 3); the running sums are what
  # build_gpa_timeline() divides (3.5 after Fall 2020, 4.0 entering it).
  k10 <- row(st, "ST_K", 202010L); k80 <- row(st, "ST_K", 202080L)
  expect_equal(c(k10$quality_points, k10$graded_hours), c(12, 3))
  expect_equal(c(k80$quality_points, k80$graded_hours), c(9, 3))
  expect_equal(c(k80$cumulative_quality_points, k80$cumulative_graded_hours), c(21, 6))
  tl <- build_gpa_timeline(st, opt = list(student_ids = "ST_K"))
  expect_equal(tl$gpa_after, c(4, 3.5))
  expect_equal(tl$gpa_entering, c(NA_real_, 4))
  # ST_H: an A and a C- carry points (4.0 x 3 + 1.7 x 3 over 6 hours); the
  # late drop has no grade and adds to neither sum.
  h <- row(st, "ST_H", 202010L)
  expect_equal(c(h$quality_points, h$graded_hours), c(17.1, 6))
  # ST_I registered with no posted grade: attempted credits, no graded hours.
  i <- row(st, "ST_I", 202110L)
  expect_equal(c(i$attempted_unm_credits, i$graded_hours, i$quality_points), c(3, 0, 0))
})

test_that("the credit window opens with the class lists, not with the programs", {
  # UNM's academic studies reaches back a year before its class lists. Judged
  # against the table's own first row, a student first registered in the first
  # class-list term looked valid whenever someone else had an earlier
  # declaration (12,935 students on the 2026-11-04 pull); and a student
  # declared before the class lists begin has credits no row can show.
  # Local scaffold: a term before the stable set, so outside ST01's counts.
  early <- dplyr::bind_rows(
    test_programs_st,
    .st_program("ST_A", "HIST", term = 201980L),   # someone declared a term earlier
    .st_program("ST_I", "HIST", term = 201980L)    # ST_I's history predates the class lists
  )
  st <- suppressMessages(build_student_terms(test_students_st, early, test_degrees_st))
  # ST_K first registers in 202010, the first class-list term: still invalid,
  # whatever the programs' first term is. (min(st$term) in the builder makes
  # this TRUE.)
  expect_false(any(st$timeline_valid[st$student_id == "ST_K"]))
  # ST_I's only class list is 202110, but their 201980 declaration says they
  # were here before the window opened.
  expect_false(any(st$timeline_valid[st$student_id == "ST_I"]))
  # ST_A: declared 201980, registered 202010 — invalid either way.
  expect_false(any(st$timeline_valid[st$student_id == "ST_A"]))
})

test_that("the build fails loudly without a settled edge or with a missing column", {
  e <- cedar_data_edges(test_students_st, degrees = test_degrees_st)
  e$last_enrolled_complete <- NULL
  expect_error(build_student_terms(test_students_st, test_programs_st, test_degrees_st, edges = e),
               "settled edge")
  expect_error(build_student_terms(dplyr::select(test_students_st, -residency), test_programs_st),
               "residency")
})

test_that("two values in one pull is an error, not a choice", {
  twice <- dplyr::bind_rows(
    test_students_st,
    dplyr::mutate(dplyr::filter(test_students_st, student_id == "ST_A", term == 202010L),
                  enrollment_id = paste0(enrollment_id, "-x"), student_classification = "Junior, 3rd Yr"))
  expect_error(build_student_terms(twice, test_programs_st, test_degrees_st), "more than one")
})

test_that("the validator rejects a banned column, a repeated key and a misjudged return", {
  st <- st01()
  expect_error(validate_student_terms(dplyr::mutate(st, inst_gpa = 3)), "pull-stamped")
  expect_error(validate_student_terms(dplyr::bind_rows(st, st[1, ])), "repeats")
  broken <- st
  broken$returned_next_regular_term[!broken$return_observable] <- FALSE
  expect_error(validate_student_terms(broken), "return_observable")
  nested <- st
  nested$student_level <- st[, c("student_level", "student_campus")]
  expect_error(validate_student_terms(nested), "plain vectors")
})

test_that("attach_student_term() joins named columns and refuses a clash", {
  st <- st01()
  rows <- dplyr::distinct(test_students_st, student_id, term, registration_status_code)
  out <- attach_student_term(rows, st, c("enrolled", "primary_major_code"))
  expect_equal(nrow(out), nrow(rows))
  expect_true(all(c("enrolled", "primary_major_code") %in% names(out)))
  expect_error(attach_student_term(out, st, "enrolled"), "already carry")
  expect_error(attach_student_term(rows, st, "nope"), "not on the student-term table")
})

test_that("class lists alone build a table in which no row is declared", {
  expect_message(
    st <- build_student_terms(test_students_st, NULL, test_degrees_st),
    "no programs supplied"
  )
  full <- st01()
  # ST_E's Fall 2020 declaration has no class list: the only row that goes.
  expect_equal(nrow(st), nrow(full) - 1L)
  expect_false(any(st$declared))
  expect_true(all(st$description_source == "class_list"))
  # No declaration anywhere, but the roster's major on every row.
  expect_true(all(st$primary_major_code == "SPAN"))
  expect_equal(sum(st$enrolled), sum(full$enrolled))
  expect_equal(dplyr::select(st, student_id, term, enrolled, returned_next_regular_term, return_observable),
               dplyr::select(dplyr::filter(full, class_list_rows > 0L),
                             student_id, term, enrolled, returned_next_regular_term, return_observable))
})

# ── I44: one definition of a return, read by Retention and Roadblocks ────────
# HIST 1110 at ABQ in Spring 2020: ten students. ST_A withdrew late next term
# (enrolled), ST_K registered, ST_J graduated that term; ST_B (early drop),
# ST_C (waitlist), ST_D (Summer only), ST_E (declared, no class list) and the
# rest did not return. Retention's ret_1 and one minus Roadblocks' pass
# stop-out rate are the same 3 of 10, because both read this table.
test_that("Retention and Roadblocks agree on who returned, through the table (I44)", {
  st <- st01()
  trend <- suppressMessages(get_retention_trend(
    test_students_st,
    opt = list(course = "HIST 1110", n_terms = 1L, min_n = 1L),
    degrees = test_degrees_st, student_terms = st
  ))
  spring <- trend[trend$campus == "ABQ" & trend$term == 202010L, ]
  expect_equal(spring$n, 10L)
  expect_equal(spring$ret_1, 0.3)

  population <- tibble::tibble(student_id = unique(test_students_st$student_id),
                               population_label = "ST01")
  stopout <- suppressMessages(get_stopout(
    test_students_st, population, degrees = test_degrees_st,
    opt = list(min_n = 1L, min_dfw_n = 0L, graded_through = 202010L,
               observation_end_term = 202080L),
    student_terms = st
  ))
  row <- stopout$by_course[stopout$by_course$campus == "ABQ" &
                             stopout$by_course$subject_course == "HIST 1110", ]
  expect_equal(row$pop_n_pass, 10L)
  expect_equal(1 - row$pop_pass_stopout_rate, spring$ret_1)
})


# ── name_program_codes(): one name per code, from programs.csv ───────────────
test_that("name_program_codes reads programs.csv through dims, the every-college row first", {
  # The demo institution's programs.csv names HIST "History" and SPAN "Spanish";
  # a code with no row is itself; NA and blank codes are dropped.
  labels <- name_program_codes(c("HIST", NA, "SPAN", "", "ZZZZ", "HIST"), test_dims)
  expect_equal(labels, c(HIST = "History", SPAN = "Spanish", ZZZZ = "ZZZZ"))

  # A code with a college-specific row beside its every-college row takes the
  # every-college row's name, whatever order the file lists them in.
  dims <- test_dims
  dims$programs <- rbind(
    data.frame(program_code = "HIST", in_college = "AS", program_name = "History (A&S)",
               unit_code = "HIST", college_code = "", is_pre_major = "FALSE", leads_to = "",
               basis = "override", status = "confirmed", evidence = "", notes = ""),
    dims$programs)
  expect_equal(name_program_codes("HIST", validate_cedar_dims(dims)), c(HIST = "History"))

  # The pre-major flag is the caller's, row for row: a code flagged on any row
  # is suffixed, so a pre-major never shares a label with the major it leads to.
  expect_equal(name_program_codes(c("HIST", "HIST", "SPAN"), test_dims,
                                  is_pre_major = c(FALSE, TRUE, FALSE)),
               c(HIST = "History (pre-major)", SPAN = "Spanish"))
  expect_error(name_program_codes("HIST", test_dims, is_pre_major = logical(0)), "parallel")
  # Dims are required: the programs table does not name codes.
  expect_error(name_program_codes("HIST", test_programs_st), "build_cedar_dims")
  # No names, no entries.
  expect_equal(name_program_codes(c(NA, ""), test_dims), stats::setNames(character(0), character(0)))
})

test_that("the loaded class list carries no student description (ADR-001 step 5)", {
  # The saved fixture has every column; the loaded one, as global.R and setup.R
  # load it, has none of the student-term columns, which readers attach.
  expect_true(all(c("major_code", "student_classification", "student_campus") %in%
                    names(cedar_registrations)))
  expect_length(intersect(CLASS_LIST_UNLOADED_COLUMNS, names(test_students)), 0L)
  expect_length(intersect(CLASS_LIST_UNLOADED_COLUMNS, names(data_objects$cedar_registrations)), 0L)

  stamped <- cedar_registrations
  attr(stamped, "cedar_provenance") <- "transform"
  thin <- thin_class_list(stamped)
  expect_equal(attr(thin, "cedar_provenance"), "transform")
  expect_equal(nrow(thin), nrow(stamped))
  expect_identical(thin_class_list(thin), thin)
  expect_error(thin_class_list(NULL), "class-list data frame")

  # A reader that filters on classification attaches it first; on the loaded
  # rows alone the filter stops loudly rather than matching nothing.
  expect_error(filter_class_list(test_students, list(classification = "Freshman")),
               "student_classification")
})

test_that("a classification filter selects on the student-term's value, not the class list's", {
  # Give one student-term a classification the class list never carried: the
  # filter in get_course_demographics() follows the table.
  key <- test_students %>%
    dplyr::filter(registration_status_code %in% STATUS_REGISTERED, term >= 201980L) %>%
    dplyr::slice(1)
  st <- test_student_terms
  hit <- st$student_id == key$student_id & st$term == as.integer(key$term)
  st$student_classification[hit] <- "Designed, Only Here"
  out <- suppressMessages(get_course_demographics(
    test_students, st, test_course_terms,
    list(classification = "Designed, Only Here",
         group_cols = c("campus", "college", "term", "term_type", "subject_course",
                        "course_title", "level"))
  ))
  expect_gt(nrow(out), 0L)
  expect_true(key$subject_course %in% out$subject_course)
  none <- suppressMessages(get_course_demographics(
    test_students, test_student_terms, test_course_terms,
    list(classification = "Designed, Only Here",
         group_cols = c("campus", "college", "term", "term_type", "subject_course",
                        "course_title", "level"))
  ))
  expect_equal(nrow(none), 0L)
})

test_that("the student-term table builds the same from the thin class list and its descriptions", {
  # ST01 exercises every description rule (two pulls with different
  # classifications, a programs row that disagrees, two majors, no programs
  # row). Built from the class list as the transform saves it -- thin, with
  # the description table beside it -- it is the table built from the full rows.
  full <- suppressMessages(build_student_terms(cedar_registrations_st, cedar_programs_st, cedar_degrees_st))
  descriptions <- build_class_list_descriptions(cedar_registrations_st)
  expect_equal(sum(descriptions$rows), nrow(cedar_registrations_st))
  from_saved <- suppressMessages(build_student_terms(
    thin_class_list(cedar_registrations_st), cedar_programs_st, cedar_degrees_st,
    edges = cedar_data_edges(cedar_registrations_st, degrees = cedar_degrees_st),
    class_list_descriptions = descriptions))
  expect_equal(from_saved, full)

  # A thin class list with no description table is refused, never built
  # as if no student had a description.
  expect_error(suppressMessages(build_student_terms(
    thin_class_list(cedar_registrations_st), cedar_programs_st, cedar_degrees_st,
    edges = cedar_data_edges(cedar_registrations_st, degrees = cedar_degrees_st))),
    "Build it before thin_class_list")

  # A class list saved before 2026-11-07 carries its own descriptions and has
  # no table beside it: they are read from it. Neither is refused.
  expect_message(legacy <- resolve_class_list_descriptions(NULL, cedar_registrations_st, "test"),
                 "saved before 2026-11-07")
  expect_equal(legacy, descriptions)
  expect_identical(resolve_class_list_descriptions(descriptions, NULL, "test"), descriptions)
  expect_error(resolve_class_list_descriptions(NULL, thin_class_list(cedar_registrations_st), "test"),
               "Re-run the transform")
  expect_error(resolve_class_list_descriptions(dplyr::select(descriptions, -rows), NULL, "test"),
               "lacks rows")

  # The roster's majors read the same off the description table as off the rows.
  expect_equal(summarize_class_list_majors(descriptions), summarize_class_list_majors(cedar_registrations_st))
})
