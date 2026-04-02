# Unit tests for the isolated population outcome functions in population.R.
#
# These tests are written BEFORE implementation (TDD). They define the
# expected API and behavior of each function. The tests use the shared
# designed fixture (test_programs, test_degrees from setup.R).
#
# Function signatures being tested:
#
#   get_ongoing_ids(programs, focal_names, max_data_term)
#     Returns character vector: students who are currently ongoing —
#     either declared focal at max_data_term OR pre-major-only at max_data_term.
#
#   get_graduated_ids(programs, degrees, focal_names, focal_codes = NULL)
#     Returns character vector: students with a focal degree in the
#     graduation window [last_declared_term, last_declared_term + 100].
#
#   get_switched_out_ids(programs, focal_names)
#     Returns character vector: students (detection only) with a declared
#     non-focal program record AFTER their last declared focal term.
#     Priority over graduated/stopped_out is applied by the orchestrator.
#
#   get_never_declared_ids(programs, focal_names, max_data_term)
#     Returns character vector: students who were only ever pre-major in
#     the focal program, AND whose last focal record predates max_data_term.
#
#   get_entry_pathways(programs, focal_names)
#     Returns data frame (student_id, entry_pathway) for all declared focal
#     students. entry_pathway is one of: "direct", "switched_in", "pre_major".
#
# =============================================================================
# EXPECTED VALUES (HIST focal, max_data_term = 202110)
# =============================================================================
#
# ongoing    (declared, 202110) : STU-HD-SP2-001..009 (9)
#                                 STU-ENGL-HIST-001/002 (2)
#                                 STU-HIST-PREDECL-001 (1)
# ongoing    (current pre-major): STU-HP-SP2-001..003 (3)
#                                 total ongoing = 15
#
# graduated                     : STU-HD-SP1-001..004 (4) + STU-HIST-PREDECL-002 (1)
#                                 total graduated = 5
#
# switched_out (raw detection)  : STU-HIST-SWOUT-001/002 (→POLS) + STU-HIST-SWOUT-003 (→BIOL)
#                                 total = 3
#
# stopped_out (residual)        : STU-HD-SP1-005..039 (35) + STU-HD-SU1-001..008 (8)
#                                 + STU-HD-FA1-001..010 (10) = 53
#
# never_declared (historical)   : STU-HP-SP1-001..004 (4) + STU-HP-SU1-001 (1)
#                                 + STU-HP-FA1-001..002 (2) = 7
#
# entry pathway (declared only, 36 total):
#   direct     = 32  (no prior major, no focal pre-major before declaration)
#   switched_in =  2  (STU-ENGL-HIST-001/002: had ENGL before entering HIST)
#   pre_major   =  2  (STU-HIST-PREDECL-001/002: had HIST pre-major before declaring)
#
# =============================================================================

library(dplyr)

# Focal program constants for HIST tests
HIST_NAMES <- "History"
HIST_CODES <- "HIST-BA"
MAX_TERM   <- 202110L


# =============================================================================
# get_ongoing_ids()
# =============================================================================

context("get_ongoing_ids")

test_that("returns 15 total ongoing HIST students (12 declared + 3 current pre-major)", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_equal(length(result), 15)
})

test_that("includes all 9 directly-declared HIST students at max_data_term", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_true(all(sprintf("STU-HD-SP2-%03d", 1:9) %in% result))
})

test_that("includes switched-in students declared HIST at max_data_term", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_true("STU-ENGL-HIST-001" %in% result)
  expect_true("STU-ENGL-HIST-002" %in% result)
})

test_that("includes pre-major pathway student declared HIST at max_data_term", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_true("STU-HIST-PREDECL-001" %in% result)
})

test_that("includes current pre-majors (focal pre-major in max_data_term, never declared)", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_true(all(sprintf("STU-HP-SP2-%03d", 1:3) %in% result))
})

test_that("excludes declared HIST students whose last HIST term predates max_data_term", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  # SP1 students appeared in 202010 only
  expect_false("STU-HD-SP1-005" %in% result)
  expect_false("STU-HD-SP1-039" %in% result)
  # SU1 students appeared in 202060 only
  expect_false("STU-HD-SU1-001" %in% result)
  # FA1 students appeared in 202080 only
  expect_false("STU-HD-FA1-001" %in% result)
})

test_that("excludes switched-out students (HIST 202010 only, then POLS/BIOL in 202110)", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_false("STU-HIST-SWOUT-001" %in% result)
  expect_false("STU-HIST-SWOUT-003" %in% result)
})

test_that("excludes historical pre-majors (last focal term < max_data_term)", {
  result <- get_ongoing_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_false("STU-HP-FA1-001" %in% result)
  expect_false("STU-HP-SU1-001" %in% result)
  expect_false("STU-HP-SP1-001" %in% result)
})


# =============================================================================
# get_graduated_ids()
# =============================================================================

context("get_graduated_ids")

test_that("returns 5 HIST graduates", {
  result <- get_graduated_ids(test_programs, test_degrees, HIST_NAMES)
  expect_equal(length(result), 5)
})

test_that("includes the four direct-entry History graduates", {
  result <- get_graduated_ids(test_programs, test_degrees, HIST_NAMES)
  expect_true(all(sprintf("STU-HD-SP1-%03d", 1:4) %in% result))
})

test_that("includes pre-major pathway graduate (STU-HIST-PREDECL-002)", {
  result <- get_graduated_ids(test_programs, test_degrees, HIST_NAMES)
  expect_true("STU-HIST-PREDECL-002" %in% result)
})

test_that("catches graduation lag: degree awarded 100 terms after last_declared_term", {
  # STU-HD-SP1-004: last HIST term = 202010, degree at 202110 (= 202010 + 100)
  result <- get_graduated_ids(test_programs, test_degrees, HIST_NAMES)
  expect_true("STU-HD-SP1-004" %in% result)
})

test_that("excludes non-focal degrees (Mathematics, Anthropology graduates)", {
  result <- get_graduated_ids(test_programs, test_degrees, HIST_NAMES)
  expect_false("STU-MA-001" %in% result)
  expect_false("STU-AN-001" %in% result)
})

test_that("returns empty vector when degrees is NULL", {
  result <- get_graduated_ids(test_programs, NULL, HIST_NAMES)
  expect_equal(length(result), 0)
  expect_type(result, "character")
})

test_that("graduation matched by program_name, not major_code (formats differ across tables)", {
  # cedar_degrees uses major_code = department ("HIST");
  # cedar_programs uses Banner code ("HIST-BA"). program_name ("History") is
  # the reliable match key shared by both tables.
  result <- get_graduated_ids(test_programs, test_degrees, HIST_NAMES)
  expect_equal(length(result), 5)
})


# =============================================================================
# get_switched_out_ids()
# =============================================================================

context("get_switched_out_ids")

test_that("detects 3 HIST students with non-focal program after last_declared_term", {
  result <- get_switched_out_ids(test_programs, HIST_NAMES)
  expect_true("STU-HIST-SWOUT-001" %in% result)
  expect_true("STU-HIST-SWOUT-002" %in% result)
  expect_true("STU-HIST-SWOUT-003" %in% result)
})

test_that("excludes STU-ENGL-HIST students (non-HIST record is BEFORE first HIST term, not after)", {
  result <- get_switched_out_ids(test_programs, HIST_NAMES)
  # ENGL-HIST students have ENGL in 202010, HIST in 202110.
  # last_declared_term = 202110. ENGL 202010 < 202110 → not after → not switched_out.
  expect_false("STU-ENGL-HIST-001" %in% result)
  expect_false("STU-ENGL-HIST-002" %in% result)
})

test_that("excludes students with no post-focal non-focal program record", {
  result <- get_switched_out_ids(test_programs, HIST_NAMES)
  # STU-HD-SP1-005: HIST only in 202010, never appeared in another major
  expect_false("STU-HD-SP1-005" %in% result)
})

test_that("returns only character vector (student IDs)", {
  result <- get_switched_out_ids(test_programs, HIST_NAMES)
  expect_type(result, "character")
})


# =============================================================================
# get_never_declared_ids()
# =============================================================================

context("get_never_declared_ids")

test_that("returns 7 historical never-declared HIST pre-majors", {
  result <- get_never_declared_ids(test_programs, HIST_NAMES, MAX_TERM)
  expect_equal(length(result), 7)
})

test_that("includes pre-majors from all three historical terms", {
  result <- get_never_declared_ids(test_programs, HIST_NAMES, MAX_TERM)
  # 202010 pre-majors
  expect_true("STU-HP-SP1-001" %in% result)
  expect_true("STU-HP-SP1-004" %in% result)
  # 202060 pre-major
  expect_true("STU-HP-SU1-001" %in% result)
  # 202080 pre-majors
  expect_true("STU-HP-FA1-001" %in% result)
  expect_true("STU-HP-FA1-002" %in% result)
})

test_that("excludes current pre-majors (last focal term == max_data_term)", {
  result <- get_never_declared_ids(test_programs, HIST_NAMES, MAX_TERM)
  # STU-HP-SP2-001..003 are pre-major in 202110 = max_data_term → ongoing, not never_declared
  expect_false(any(sprintf("STU-HP-SP2-%03d", 1:3) %in% result))
})

test_that("excludes students who eventually declared (pre_major pathway)", {
  result <- get_never_declared_ids(test_programs, HIST_NAMES, MAX_TERM)
  # PREDECL-001: pre-major 202010, declared 202080 → NOT never_declared
  expect_false("STU-HIST-PREDECL-001" %in% result)
  # PREDECL-002: pre-major 202010, declared 202060 → NOT never_declared
  expect_false("STU-HIST-PREDECL-002" %in% result)
})


# =============================================================================
# get_entry_pathways()
# =============================================================================

context("get_entry_pathways")

test_that("returns data frame with student_id and entry_pathway columns", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_true("student_id"    %in% names(result))
  expect_true("entry_pathway" %in% names(result))
})

test_that("covers all 36 declared HIST students (one row each)", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_equal(nrow(result), 36)
  expect_equal(n_distinct(result$student_id), 36)
})

test_that("excludes pre-major-only students (never declared)", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_false("STU-HP-SP1-001" %in% result$student_id)
  expect_false("STU-HP-FA1-001" %in% result$student_id)
  expect_false("STU-HP-SP2-001" %in% result$student_id)
})

test_that("direct pathway: first UNM major was the focal program", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_equal(result$entry_pathway[result$student_id == "STU-HD-SP1-005"],     "direct")
  expect_equal(result$entry_pathway[result$student_id == "STU-HIST-SWOUT-001"], "direct")
  expect_equal(result$entry_pathway[result$student_id == "STU-HD-SP2-001"],     "direct")
})

test_that("switched_in pathway: had non-focal declared major before first HIST declaration", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_equal(result$entry_pathway[result$student_id == "STU-ENGL-HIST-001"], "switched_in")
  expect_equal(result$entry_pathway[result$student_id == "STU-ENGL-HIST-002"], "switched_in")
})

test_that("pre_major pathway: had focal pre-major record before declaring", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_equal(result$entry_pathway[result$student_id == "STU-HIST-PREDECL-001"], "pre_major")
  expect_equal(result$entry_pathway[result$student_id == "STU-HIST-PREDECL-002"], "pre_major")
})

test_that("pathway counts: 32 direct, 2 switched_in, 2 pre_major", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_equal(sum(result$entry_pathway == "direct"),     32)
  expect_equal(sum(result$entry_pathway == "switched_in"), 2)
  expect_equal(sum(result$entry_pathway == "pre_major"),   2)
})

test_that("all entry_pathway values are valid", {
  result <- get_entry_pathways(test_programs, HIST_NAMES)
  expect_true(all(result$entry_pathway %in% c("direct", "switched_in", "pre_major")))
})


# =============================================================================
# build_population() integration
# =============================================================================

context("build_population integration")

test_that("returns the standard population schema", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  expect_true(all(c("student_id", "population_label", "outcome",
                    "origin", "entry_method", "entry_status",
                    "first_unit_term", "last_unit_term", "last_declared_term",
                    "relevant_until") %in% names(result)))
})

test_that("outcome counts: 15 ongoing, 5 graduated, 3 switched_out, 16 stopped_out", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  counts <- table(result$outcome)
  expect_equal(as.integer(counts[["ongoing"]]),     15L)
  expect_equal(as.integer(counts[["graduated"]]),    5L)
  expect_equal(as.integer(counts[["switched_out"]]), 3L)
  expect_equal(as.integer(counts[["stopped_out"]]), 16L)
})

test_that("stopped_out is the residual: all declared students not ongoing/graduated/switched_out", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  stopped <- result[result$outcome == "stopped_out", ]
  expect_true("STU-HD-SP1-005" %in% stopped$student_id)
  expect_true("STU-HD-SU1-001" %in% stopped$student_id)
  expect_true("STU-HD-FA1-001" %in% stopped$student_id)
  expect_false("STU-HIST-SWOUT-001" %in% stopped$student_id)
  expect_false("STU-HIST-PREDECL-002" %in% stopped$student_id)
})

test_that("pre-major sub-outcomes included when explicitly requested (7 students total)", {
  result <- build_population(
    test_programs, test_degrees,
    opt = list(type = "dept", dept_code = "HIST",
               outcomes = c("ongoing","graduated","switched_out","stopped_out",
                            "chose_elsewhere","left_undeclared"))
  )
  # All 7 historical pre-majors never declared elsewhere → left_undeclared
  expect_equal(sum(result$outcome %in% c("chose_elsewhere","left_undeclared")), 7L)
})

test_that("STU-HIST-SWOUT-001: switched_out, unclear, major", {
  # entry_method = "unclear" because first HIST record is at 202010 = min_data_term.
  # We cannot tell if they had prior history before the earliest term in the data.
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  row <- result[result$student_id == "STU-HIST-SWOUT-001", ]
  expect_equal(row$outcome,       "switched_out")
  expect_equal(row$entry_method,  "unclear")
  expect_equal(row$entry_status,  "major")
})

test_that("STU-ENGL-HIST-001: ongoing, switched_in, major", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  row <- result[result$student_id == "STU-ENGL-HIST-001", ]
  expect_equal(row$outcome,       "ongoing")
  expect_equal(row$entry_method,  "switched_in")
  expect_equal(row$entry_status,  "major")
})

test_that("STU-HIST-PREDECL-001: ongoing, entry_status = pre_major", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  row <- result[result$student_id == "STU-HIST-PREDECL-001", ]
  expect_equal(row$outcome,      "ongoing")
  expect_equal(row$entry_status, "pre_major")
})

test_that("STU-HIST-PREDECL-002: graduated, entry_status = pre_major", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  row <- result[result$student_id == "STU-HIST-PREDECL-002", ]
  expect_equal(row$outcome,      "graduated")
  expect_equal(row$entry_status, "pre_major")
})

test_that("STU-HP-SP2-001: ongoing (current pre-major), entry_status = pre_major", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  row <- result[result$student_id == "STU-HP-SP2-001", ]
  expect_equal(row$outcome,      "ongoing")
  expect_equal(row$entry_status, "pre_major")
})

test_that("relevant_until is NA for all ongoing students", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  ongoing <- result[result$outcome == "ongoing", ]
  expect_true(all(is.na(ongoing$relevant_until)))
})

test_that("relevant_until = last_declared_term for switched_out students", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  # SWOUT-001: declared HIST only in 202010 → last_declared_term = 202010
  row <- result[result$student_id == "STU-HIST-SWOUT-001", ]
  expect_equal(row$relevant_until, 202010L)
})

test_that("relevant_until = last_declared_term for stopped_out students", {
  result <- build_population(test_programs, test_degrees,
                             opt = list(type = "dept", dept_code = "HIST"))
  # SU1 students: declared HIST only in 202060
  row <- result[result$student_id == "STU-HD-SU1-001", ]
  expect_equal(row$relevant_until, 202060L)
})
