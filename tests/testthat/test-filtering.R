# Tests for data filtering functions
# Tests functions in R/trunk/filter.R (CEDAR model)
#
# Uses designed_test_data.R fixtures (hand-crafted, transparent).
# All expected values match counts from cedar_sections / cedar_students in that file.
# When fixture data changes, update the counts below accordingly.
#
# === SECTIONS (status=A) — 85 total rows (71 base + 14 XL merged in) ===
# By dept (active):     HIST=21  MATH=10  ANTH=9  NURS=8
# By term (active):     202010=28  202060=12  202080=15  202110=17  total=72
# By campus (active):   ABQ=64  EA=7
# By delivery (active): ENH=43  ONL=22  MOPS=6  NA=1
# By level (active):    lower=46  upper=20  grad=6
# By part_term (active):1=56  1H=4  2H=3  NF=8  NA=1
# Cancelled (status=C): 8
#
# filter_by_term (all statuses):
#   "202010-202060"=44  "202010-202110"=85  spring=50  summer=14  fall=21
#
# Selected dept×term combos (status=A):
#   HIST×202010=10  ANTH×202060=1  MATH×202010=3  NURS×202060=2
#
# === STUDENTS ===
# By dept:     HIST=279  MATH=280  ANTH=219
# By term:     202010=440  202060=219
# MATH 1430:   146 rows across 4 terms

context("Data Filtering - CEDAR Model")

# Use uel=FALSE throughout filtering tests so the exclude list (loaded by
# load_funcs) doesn't mask section/student records. The uel behavior is
# tested separately. All expected counts below are from discover-expected-values.R
# run against the current fixtures.
make_opt <- function(...) create_test_opt(c(list(uel = FALSE), list(...)))

# =============================================================================
# Department Filtering
# =============================================================================

test_that("filter_DESRs filters by HIST department correctly", {
  opt <- make_opt(dept = "HIST")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 21)
  expect_true(all(filtered$department == "HIST"))
})

test_that("filter_DESRs filters by MATH department correctly", {
  opt <- make_opt(dept = "MATH")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 10)
  expect_true(all(filtered$department == "MATH"))
})

test_that("filter_DESRs filters by ANTH department correctly", {
  opt <- make_opt(dept = "ANTH")
  filtered <- filter_DESRs(test_sections, opt)

  # 12 pre-XL06-S + 6 ANTH 2190C spring rows = 18
  expect_equal(nrow(filtered), 18)
  expect_true(all(filtered$department == "ANTH"))
})

test_that("filter_DESRs filters by NURS department correctly", {
  opt <- make_opt(dept = "NURS")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 8)
  expect_true(all(filtered$department == "NURS"))
})

# =============================================================================
# Term Filtering
# =============================================================================

test_that("filter_DESRs filters by term 202010 correctly", {
  opt <- make_opt(term = 202010)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 30)
  expect_true(all(filtered$term == 202010))
})

test_that("filter_DESRs filters by term 202060 (summer) correctly", {
  opt <- make_opt(term = 202060)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 12)
  expect_true(all(filtered$term == 202060))
})

test_that("filter_DESRs filters by term 202080 correctly", {
  opt <- make_opt(term = 202080)
  filtered <- filter_DESRs(test_sections, opt)

  # 18 base + 14 C-suffix rows (EC-04:4, EC-05:4, EC-06:6) + 3 EC-07 = 35
  expect_equal(nrow(filtered), 35)
  expect_true(all(filtered$term == 202080))
})

test_that("filter_DESRs filters by term 202110 correctly", {
  opt <- make_opt(term = 202110)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 19)
  expect_true(all(filtered$term == 202110))
})

# =============================================================================
# Campus Filtering
# =============================================================================

test_that("filter_DESRs filters by ABQ campus correctly", {
  opt <- make_opt(course_campus = "ABQ")
  filtered <- filter_DESRs(test_sections, opt)

  # 67 base + 14 C-suffix + 3 EC-07 + 6 XL06-S rows (all ABQ campus) = 90
  expect_equal(nrow(filtered), 90)
  expect_true(all(filtered$campus == "ABQ"))
})

test_that("filter_DESRs filters by EA campus correctly", {
  opt <- make_opt(course_campus = "EA")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 7)
  expect_true(all(filtered$campus == "EA"))
})

# =============================================================================
# Status Filtering
# =============================================================================

test_that("filter_DESRs returns only active sections by default", {
  opt <- make_opt(dept = "HIST")
  filtered <- filter_DESRs(test_sections, opt)

  # create_test_opt sets status="A" by default — no cancelled sections should appear
  expect_true(all(filtered$status == "A"))
})

test_that("filter_DESRs filters by active status explicitly", {
  opt <- make_opt(status = "A")
  filtered <- filter_DESRs(test_sections, opt)

  # 75 base + 14 C-suffix + 3 EC-07 + 6 XL06-S rows (all status="A") = 98
  expect_equal(nrow(filtered), 98)
  expect_true(all(filtered$status == "A"))
})

test_that("filter_DESRs filters by cancelled status correctly", {
  opt <- make_opt(status = "C")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 8)
  expect_true(all(filtered$status == "C"))
})

# =============================================================================
# Delivery Method Filtering
# =============================================================================

test_that("filter_DESRs filters by ONL delivery correctly", {
  opt <- make_opt(im = "ONL")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 22)
  expect_true(all(filtered$delivery_method == "ONL"))
})

test_that("filter_DESRs filters by ENH delivery correctly", {
  opt <- make_opt(im = "ENH")
  filtered <- filter_DESRs(test_sections, opt)

  # 46 base + 14 C-suffix + 3 EC-07 + 6 XL06-S rows (all delivery="ENH") = 69
  expect_equal(nrow(filtered), 69)
  expect_true(all(filtered$delivery_method == "ENH"))
})

test_that("filter_DESRs filters by MOPS delivery correctly", {
  opt <- make_opt(im = "MOPS")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 6)
  expect_true(all(filtered$delivery_method == "MOPS"))
})

# =============================================================================
# Part of Term Filtering
# =============================================================================

test_that("filter_DESRs filters by full term (1) correctly", {
  opt <- make_opt(pt = "1")
  filtered <- filter_DESRs(test_sections, opt)

  # 59 base + 14 C-suffix + 3 EC-07 + 6 XL06-S rows (all part_term="1") = 82
  expect_equal(nrow(filtered), 82)
  expect_true(all(filtered$part_term == "1"))
})

test_that("filter_DESRs filters by first half (1H) correctly", {
  opt <- make_opt(pt = "1H")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 4)
  expect_true(all(filtered$part_term == "1H"))
})

test_that("filter_DESRs filters by second half (2H) correctly", {
  opt <- make_opt(pt = "2H")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$part_term == "2H"))
})

test_that("filter_DESRs filters by NF part_term (NURS-only) correctly", {
  opt <- make_opt(pt = "NF")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 8)
  expect_true(all(filtered$part_term == "NF"))
})

# =============================================================================
# Level Filtering
# =============================================================================

test_that("filter_DESRs filters by lower level correctly", {
  opt <- make_opt(level = "lower")
  filtered <- filter_DESRs(test_sections, opt)

  # 49 base + 14 C-suffix + 3 EC-07 + 6 XL06-S rows (all level="lower") = 72
  expect_equal(nrow(filtered), 72)
  expect_true(all(filtered$level == "lower"))
})

test_that("filter_DESRs filters by upper level correctly", {
  opt <- make_opt(level = "upper")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 20)
  expect_true(all(filtered$level == "upper"))
})

test_that("filter_DESRs filters by grad level correctly", {
  opt <- make_opt(level = "grad")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 6)
  expect_true(all(filtered$level == "grad"))
})

# =============================================================================
# Combined Filter Tests
# =============================================================================

test_that("filter_DESRs filters by HIST + term 202010 correctly", {
  opt <- make_opt(dept = "HIST", term = 202010)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 10)
  expect_true(all(filtered$department == "HIST"))
  expect_true(all(filtered$term == 202010))
})

test_that("filter_DESRs filters by ANTH + term 202060 correctly", {
  opt <- make_opt(dept = "ANTH", term = 202060)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 1)
  expect_true(all(filtered$department == "ANTH"))
  expect_true(all(filtered$term == 202060))
})

test_that("filter_DESRs filters by MATH + term 202010 correctly", {
  opt <- make_opt(dept = "MATH", term = 202010)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 3)
  expect_true(all(filtered$department == "MATH"))
  expect_true(all(filtered$term == 202010))
})

test_that("filter_DESRs filters by NURS + term 202060 correctly", {
  opt <- make_opt(dept = "NURS", term = 202060)
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 2)
  expect_true(all(filtered$department == "NURS"))
  expect_true(all(filtered$term == 202060))
})

# =============================================================================
# Empty Result Tests
# =============================================================================

test_that("filter_DESRs handles nonexistent department gracefully", {
  opt <- make_opt(dept = "NONEXISTENT")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 0)
  expect_true(is.data.frame(filtered))
})

test_that("filter_DESRs handles impossible filter combination gracefully", {
  # HIST has no NF part_term sections (NF is NURS-only)
  opt <- make_opt(dept = "HIST", pt = "NF")
  filtered <- filter_DESRs(test_sections, opt)

  expect_equal(nrow(filtered), 0)
  expect_true(is.data.frame(filtered))
})

# =============================================================================
# Core Function Tests
# =============================================================================

test_that("filter_by_col works with department column", {
  filtered <- filter_by_col(test_sections, "department", "HIST")

  # All rows should be HIST (includes all statuses — filter_by_col is status-agnostic)
  expect_true(all(filtered$department == "HIST"))
  expect_gt(nrow(filtered), 0)
})

test_that("filter_by_col works with multiple values", {
  filtered <- filter_by_col(test_sections, "department", c("HIST", "MATH"))

  expect_true(all(filtered$department %in% c("HIST", "MATH")))
  expect_gt(nrow(filtered), 0)
})

test_that("filter_by_col errors on missing column", {
  expect_error(
    filter_by_col(test_sections, "nonexistent_column", "value"),
    "Column 'nonexistent_column' not found in data"
  )
})

test_that("filter_by_term handles term range correctly", {
  # 202010 (32 all-status incl. 2 XL06-S) + 202060 (14) = 46
  filtered <- filter_by_term(test_sections, "202010-202060", "term")

  expect_equal(nrow(filtered), 46)
  expect_true(all(filtered$term %in% c(202010, 202060)))
})

test_that("filter_by_term covers all terms in fixture range", {
  # The 4 stable terms = 106 rows (85 base + 14 C-suffix + 3 EC-07 + 4 XL06-S
  # in 202010/202110); the 2 XL06-S rows in 201910 fall outside the range
  filtered <- filter_by_term(test_sections, "202010-202110", "term")

  expect_equal(nrow(filtered), 106)
})

test_that("filter_by_term handles 'spring' keyword", {
  # Spring = terms ending in 10: 202010 + 202110
  filtered <- filter_by_term(test_sections, "spring", "term")

  # 50 pre-XL06-S + 6 ANTH 2190C spring rows (201910/202010/202110) = 56
  expect_equal(nrow(filtered), 56)
  expect_true(all(substring(as.character(filtered$term), 5, 6) == "10"))
})

test_that("filter_by_term handles 'summer' keyword", {
  # Summer = terms ending in 60: 202060 (14 all-status)
  filtered <- filter_by_term(test_sections, "summer", "term")

  expect_equal(nrow(filtered), 14)
  expect_true(all(substring(as.character(filtered$term), 5, 6) == "60"))
})

test_that("filter_by_term handles 'fall' keyword", {
  # Fall = terms ending in 80: 202080 (21 base + 14 C-suffix + 3 EC-07 = 38)
  filtered <- filter_by_term(test_sections, "fall", "term")

  expect_equal(nrow(filtered), 38)
  expect_true(all(substring(as.character(filtered$term), 5, 6) == "80"))
})

# =============================================================================
# Student/Class List Filtering Tests
# =============================================================================

test_that("filter_class_list filters by HIST department correctly", {
  opt <- make_opt(dept = "HIST")
  filtered <- filter_class_list(test_students, opt)

  expect_equal(nrow(filtered), 84)
  expect_true(all(filtered$department == "HIST"))
})

test_that("filter_class_list filters by MATH department correctly", {
  opt <- make_opt(dept = "MATH")
  filtered <- filter_class_list(test_students, opt)

  expect_equal(nrow(filtered), 10)
  expect_true(all(filtered$department == "MATH"))
})

test_that("filter_class_list filters by ANTH department correctly", {
  opt <- make_opt(dept = "ANTH")
  filtered <- filter_class_list(test_students, opt)

  expect_equal(nrow(filtered), 87)
  expect_true(all(filtered$department == "ANTH"))
})

test_that("filter_class_list filters by term 202010 correctly", {
  opt <- make_opt(term = 202010)
  filtered <- filter_class_list(test_students, opt)

  expect_equal(nrow(filtered), 133)
  expect_true(all(filtered$term == 202010))
})

test_that("filter_class_list filters by term 202060 correctly", {
  opt <- make_opt(term = 202060)
  filtered <- filter_class_list(test_students, opt)

  expect_equal(nrow(filtered), 4)
  expect_true(all(filtered$term == 202060))
})

test_that("filter_class_list filters by course correctly", {
  opt <- make_opt(course = "MATH 1430")
  filtered <- filter_class_list(test_students, opt)

  expect_equal(nrow(filtered), 2)
  expect_true(all(filtered$subject_course == "MATH 1430"))
  # MATH 1430 appears in 1 fixture term (202010 only)
  expect_equal(n_distinct(filtered$term), 1)
})

# =============================================================================
# Instructor Name Filtering (comma handling — pure logic, no fixture dependency)
# =============================================================================

test_that("convert_param_to_list preserves instructor names with commas", {
  result <- convert_param_to_list("Gibbs, Frederick", split_on_comma = FALSE)

  expect_length(result, 1)
  expect_equal(result[1], "Gibbs, Frederick")
})

test_that("convert_param_to_list splits course lists on comma", {
  result <- convert_param_to_list("MATH 1430,ENGL 1110", split_on_comma = TRUE)

  expect_length(result, 2)
  expect_equal(result[1], "MATH 1430")
  expect_equal(result[2], "ENGL 1110")
})

test_that("convert_param_to_list trims whitespace correctly", {
  result <- convert_param_to_list("HIST 300 , ENGL 1110", split_on_comma = TRUE)

  expect_length(result, 2)
  expect_equal(result[1], "HIST 300")
  expect_equal(result[2], "ENGL 1110")
})

test_that("convert_param_to_list handles single values without comma", {
  result_no_split <- convert_param_to_list("Smith, John", split_on_comma = FALSE)
  result_split    <- convert_param_to_list("MATH 1215", split_on_comma = TRUE)

  expect_length(result_no_split, 1)
  expect_equal(result_no_split[1], "Smith, John")
  expect_length(result_split, 1)
  expect_equal(result_split[1], "MATH 1215")
})

test_that("convert_param_to_list preserves vector input", {
  input_vector <- c("Gibbs, Frederick", "Smith, John", "Doe, Jane")
  result <- convert_param_to_list(input_vector, split_on_comma = FALSE)

  expect_length(result, 3)
  expect_equal(result, input_vector)
})

test_that("instructor names with commas match correctly with %in% operator", {
  test_instructors <- c("Gibbs, Frederick", "Smith, John", "Doe, Jane")
  filter_value <- "Gibbs, Frederick"
  matches <- test_instructors %in% filter_value

  expect_true(matches[1])
  expect_false(matches[2])
  expect_false(matches[3])
})

test_that("filtering handles edge cases in instructor names", {
  test_data <- data.frame(
    instructor_name = c(
      "Gibbs, Frederick",
      "Smith, Jr., John",
      "Single Name",
      NA_character_,
      "",
      " Leading Space"
    ),
    course = 1:6,
    stringsAsFactors = FALSE
  )

  expect_equal(nrow(test_data %>% filter(instructor_name == "Gibbs, Frederick")), 1)
  expect_equal(nrow(test_data %>% filter(instructor_name == "Smith, Jr., John")), 1)
  expect_equal(nrow(test_data %>% filter(instructor_name == "Single Name")), 1)
  expect_equal(nrow(test_data %>% filter(instructor_name == NA_character_)), 0)
  expect_equal(nrow(test_data %>% filter(instructor_name == "")), 1)
})

test_that("instructor filtering with NA values works safely", {
  test_data <- data.frame(
    instructor_name = c("Gibbs, Frederick", "Smith, John", NA_character_),
    course = c("HIST 300", "MATH 101", "ENGL 200"),
    stringsAsFactors = FALSE
  )

  filtered <- test_data %>% filter(!is.na(instructor_name))
  expect_equal(nrow(filtered), 2)
  expect_true(all(!is.na(filtered$instructor_name)))
})
