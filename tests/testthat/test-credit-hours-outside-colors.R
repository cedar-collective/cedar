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

ch_result <- function() {
  credit_hours_by_major(ch_fixture(), "HIST",
                        cedar_report_start_term, cedar_report_end_term)
}

test_that("every level slice is handed the same colour map object", {
  t <- ch_result()$tables
  lo <- t$sch_color_map_lower
  up <- t$sch_color_map_upper
  ug <- t$sch_color_map_all_ug
  skip_if(is.null(lo) || is.null(up), "fixture produced fewer than two level slices")

  # This is the invariant: one map, shared. Per-level maps built from per-level
  # rankings are exactly what caused the mismatched colours.
  expect_identical(lo, up)
  if (!is.null(ug)) expect_identical(lo, ug)
})

test_that("a program named at more than one level resolves to one colour", {
  t <- ch_result()$tables
  lo <- t$sch_color_map_lower
  up <- t$sch_color_map_upper
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
  lo <- t$sch_color_map_lower
  skip_if(is.null(lo) || !"Other" %in% names(lo), "no Other slice in the fixture")

  expect_equal(unname(lo[["Other"]]), unname(CEDAR_SEMANTIC_COLORS["other"]))
})
