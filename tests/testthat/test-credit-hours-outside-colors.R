# Outside-majors colour consistency (Dept Trends > Credit Hours).
#
# The lower-division, upper-division, and all-undergrad views each name their own
# set of outside programs. They used to build a colour map independently from
# their own ranking, so a department ranked 1st in lower and 3rd in upper got two
# different colours across charts sitting on the same page. One shared map is now
# built across all three and handed to every level.

context("Credit hours outside-majors colours")

# test_students has no major_name (the fixture predates the column); derive one
# so credit_hours_by_major()'s column check passes. Colour assignment keys on
# major_code, so the derived name does not affect what is being tested.
ch_fixture <- function() {
  st <- test_students
  if (!"major_name" %in% names(st)) st$major_name <- st$major_code
  st
}

# Home major codes the way Dept Trends resolves them (set_payload's prog_codes).
hist_major_codes <- function() {
  names(major_to_dept)[!is.na(major_to_dept) & major_to_dept == "HIST"]
}

ch_result <- function() {
  credit_hours_by_major(ch_fixture(), "HIST", hist_major_codes(),
                        cedar_report_start_term, cedar_report_end_term)
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

# HIST course rows in test_students carry no major_code, so the raw fixture
# cannot tell a home major from an outside one. Stamp one here: HIST students
# sorted by id, first half "HIST-BA" (home), second half "BIOL-BS" (outside).
# Local scaffolding for this contract; the shared course rows stay unchanged.
ch_fixture_with_majors <- function() {
  st <- ch_fixture()
  is_hist  <- st$department == "HIST"
  ids      <- sort(unique(st$student_id[is_hist]))
  home_ids <- ids[seq_len(ceiling(length(ids) / 2))]
  st$major_code[is_hist] <- ifelse(st$student_id[is_hist] %in% home_ids, "HIST-BA", "BIOL-BS")
  st$major_name <- st$major_code
  st
}

test_that("credit_hours_by_major takes its home major codes from the caller (M12)", {
  # No major_codes: an error, never a lookup of major_to_dept or dept_code as a major code.
  expect_error(
    credit_hours_by_major(ch_fixture(), "HIST",
                          term_start = cedar_report_start_term, term_end = cedar_report_end_term),
    "major_codes"
  )
  expect_error(
    credit_hours_by_major(ch_fixture(), "HIST", NULL,
                          cedar_report_start_term, cedar_report_end_term),
    "major_codes"
  )

  st   <- ch_fixture_with_majors()
  run  <- function(codes) {
    credit_hours_by_major(st, "HIST", codes, cedar_report_start_term, cedar_report_end_term,
                          include_all_ug = FALSE, include_wide_table = FALSE)
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
