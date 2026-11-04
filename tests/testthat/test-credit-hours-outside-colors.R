# Outside-majors colour consistency (Dept Trends > Credit Hours).
#
# The lower-division, upper-division, and all-undergrad views each name their own
# set of outside programs. They used to build a colour map independently from
# their own ranking, so a department ranked 1st in lower and 3rd in upper got two
# different colours across charts sitting on the same page. One shared map is now
# built across all three and handed to every level.

context("Credit hours outside-majors colours")

# Each row's major is its student-term's primary major, read off the
# student-term table; test_students' rows carry none, and test_student_terms
# (built from them without programs) names none either. Colour assignment keys
# on major_code, so the stamped codes below are what is being tested.
ch_fixture <- function() test_students

# Home major codes the way Dept Trends resolves them (set_payload's prog_codes).
hist_major_codes <- function() {
  names(major_to_dept)[!is.na(major_to_dept) & major_to_dept == "HIST"]
}

# test_student_terms names no primary major (built without programs), so the
# raw fixture cannot tell a home major from an outside one. Stamp one on the
# student-term table: HIST students sorted by id, first half "HIST-BA" (home),
# second half "BIOL-BS" (outside). Local scaffolding for this contract; the
# shared tables stay unchanged.
ch_student_terms_with_majors <- function() {
  st  <- test_student_terms
  ids <- sort(unique(test_students$student_id[test_students$department == "HIST"]))
  home_ids <- ids[seq_len(ceiling(length(ids) / 2))]
  st$primary_major_code <- dplyr::case_when(
    st$student_id %in% home_ids ~ "HIST-BA",
    st$student_id %in% ids      ~ "BIOL-BS",
    TRUE                        ~ st$primary_major_code
  )
  st
}

ch_result <- function() {
  credit_hours_by_major(ch_fixture(), test_sections, "HIST", hist_major_codes(),
                        cedar_report_start_term, cedar_report_end_term,
                        student_terms = ch_student_terms_with_majors())
}

test_that("every level slice is handed the same colour map object", {
  t <- ch_result()$tables
  lo <- build_color_map(t$sch_color_order_lower)
  up <- build_color_map(t$sch_color_order_upper)
  ug <- build_color_map(t$sch_color_order_all_ug)
  skip_if(is.null(lo) || is.null(up), "fixture produced fewer than two level slices")

  # This is the invariant: one map, shared. Per-level maps built from per-level
  # rankings are exactly what caused the mismatched colours.
  expect_identical(lo, up)
  if (!is.null(ug)) expect_identical(lo, ug)
})

test_that("a program named at more than one level resolves to one colour", {
  t <- ch_result()$tables
  lo <- build_color_map(t$sch_color_order_lower)
  up <- build_color_map(t$sch_color_order_upper)
  skip_if(is.null(lo) || is.null(up), "fixture produced fewer than two level slices")

  shared <- intersect(names(lo), names(up))
  shared <- shared[!is.na(shared) & nzchar(shared) & shared != "Other"]
  skip_if(length(shared) == 0, "no named program appears at both levels in the fixture")

  for (code in shared) {
    expect_equal(unname(lo[code]), unname(up[code]),
                 info = paste("colour differs across levels for", code))
  }
})

test_that("Other keeps the reserved neutral and is not a palette colour", {
  t <- ch_result()$tables
  lo <- build_color_map(t$sch_color_order_lower)
  skip_if(is.null(lo) || !"Other" %in% names(lo), "no Other slice in the fixture")

  expect_equal(unname(lo[["Other"]]), unname(CEDAR_SEMANTIC_COLORS["other"]))
})

test_that("credit_hours_by_major takes its home major codes from the caller (M12)", {
  # No major_codes: an error, never a lookup of major_to_dept or dept_code as a major code.
  expect_error(
    credit_hours_by_major(ch_fixture(), test_sections, "HIST",
                          term_start = cedar_report_start_term, term_end = cedar_report_end_term,
                          student_terms = test_student_terms),
    "major_codes"
  )
  expect_error(
    credit_hours_by_major(ch_fixture(), test_sections, "HIST", NULL,
                          cedar_report_start_term, cedar_report_end_term,
                          student_terms = test_student_terms),
    "major_codes"
  )

  terms <- ch_student_terms_with_majors()
  run  <- function(codes, st = terms, rows = ch_fixture()) {
    credit_hours_by_major(rows, test_sections, "HIST", codes, cedar_report_start_term, cedar_report_end_term,
                          student_terms = st, include_all_ug = FALSE, include_wide_table = FALSE)
  }
  outside_hours <- function(r) {
    sum(r$tables$sch_outside_full_lower$total_hours, na.rm = TRUE) +
      sum(r$tables$sch_outside_full_upper$total_hours, na.rm = TRUE)
  }
  home <- run("HIST-BA")
  # An empty vector is a unit with no degree programs: every student is outside.
  none <- run(character(0))

  expect_false("HIST-BA" %in% home$tables$sch_outside_full_lower$major_code)
  expect_true("HIST-BA" %in% none$tables$sch_outside_full_lower$major_code)
  expect_gt(outside_hours(none), outside_hours(home))
})

test_that("credit_hours_by_major reads each row's major off the student-term table, named by the caller", {
  terms <- ch_student_terms_with_majors()
  run  <- function(codes, st = terms, rows = ch_fixture(), names = NULL) {
    credit_hours_by_major(rows, test_sections, "HIST", codes, cedar_report_start_term, cedar_report_end_term,
                          student_terms = st, major_names = names,
                          include_all_ug = FALSE, include_wide_table = FALSE)
  }
  home <- run("HIST-BA")

  # The roster's major is not read: stamping every course row BIOL-BS changes
  # nothing, because the table still says HIST-BA for the home half.
  rows <- ch_fixture()
  rows$major_code <- "BIOL-BS"
  rows$major_name <- "Biology"
  expect_equal(run("HIST-BA", rows = rows)$tables$sch_split_lower, home$tables$sch_split_lower)

  # The table is read: calling every student BIOL-BS there empties the home share.
  st <- terms
  st$primary_major_code <- "BIOL-BS"
  all_outside <- run("HIST-BA", st = st)
  expect_equal(unname(all_outside$tables$sch_split_lower["home"]), 0)
  expect_equal(unname(all_outside$tables$sch_split_lower["outside"]),
               unname(home$tables$sch_split_lower["total"]))

  # Names come from the caller's vector; a code it does not name is itself.
  named <- run("HIST-BA", names = c("BIOL-BS" = "Biology"))
  outside_names <- c(named$tables$sch_outside_full_lower$major_name,
                     named$tables$sch_outside_full_upper$major_name)
  expect_true("Biology" %in% outside_names)
  expect_false("BIOL-BS" %in% outside_names)
  unnamed <- dplyr::filter(home$tables$sch_outside_full_lower, !is.na(major_code))
  expect_true(all(unnamed$major_name == unnamed$major_code))

  # A row the table lacks is an error, never a row without a major.
  expect_error(run("HIST-BA", st = dplyr::filter(terms, term != 202080L)),
               "no row on cedar_student_terms")
})
