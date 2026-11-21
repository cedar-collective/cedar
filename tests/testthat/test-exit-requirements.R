# XC01 (fixtures/scenario_tables.R): the students who left with 90 credits or
# more, read against the courses their program's degree plan names.

test_that("XC01: a board's named requirements are its course tiles, not its choices or preparation", {
  plans <- degree_named_requirements(xc01$boards$roadmaps, c("hist-ba", "anth-ba"))
  expect_equal(plans$courses$requirement_id, c("survey", "methods", "methods", "new", "intro"))
  expect_equal(plans$courses$subject_course, c("HIST 1101", "HIST 201", "HIST 201L", "HIST 900", "ANTH 101"))
  # The open choice and the preparation course; the shared math route is another track.
  expect_equal(plans$not_read$n_not_read[plans$not_read$catalog_id == "hist-ba"], 2L)
  expect_false("anth-ba" %in% plans$not_read$catalog_id)
})

test_that("XC01: each required course counts who passed, who tried and who has no attempt", {
  exit <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, xc01$opt)
  far <- exit$students[!is.na(exit$students$credits) & exit$students$credits >= 90, ]
  expect_setequal(far$student_id, c("X-A", "X-B", "X-J", "X-K"))
  plans <- degree_named_requirements(xc01$boards$roadmaps, c("hist-ba", "anth-ba"))
  run <- function(min_n) get_exit_requirement_progress(far, xc01$programs, xc01$attempts, plans$courses,
                                                       xc01$boards$catalog$program_codes, list(min_n = min_n))
  r <- run(2L)
  # X-A's two declaration rows are one student; X-A is the one pre-major.
  expect_equal(r$programs$catalog_id, c("anth-ba", "hist-ba"))
  expect_equal(r$programs$n_students, c(2L, 2L))
  expect_equal(r$programs$n_pre_major, c(1L, 0L))
  counts <- function(code) unlist(r$courses[r$courses$subject_course == code, c("n_passed", "n_tried", "n_none")])
  # The renumbered course is one course; a pass on another campus counts.
  expect_equal(counts("HIST 1101"), c(n_passed = 2L, n_tried = 0L, n_none = 0L))
  # Lecture and lab are counted apart: the lecture passed, the lab failed.
  expect_equal(counts("HIST 201"), c(n_passed = 1L, n_tried = 0L, n_none = 1L))
  expect_equal(counts("HIST 201L"), c(n_passed = 0L, n_tried = 1L, n_none = 1L))
  # First graded after the latest last term: unknown, never zero.
  expect_false(r$courses$readable[r$courses$subject_course == "HIST 900"])
  expect_true(all(is.na(counts("HIST 900"))))
  # An early drop is not an attempt; a pass by a student outside the plan is not counted.
  expect_equal(counts("ANTH 101"), c(n_passed = 0L, n_tried = 1L, n_none = 1L))
  expect_equal(r$courses$subject_course, c("ANTH 101", "HIST 1101", "HIST 201", "HIST 201L", "HIST 900"))
  expect_equal(c(r$meta$n_with_plan, r$meta$n_without_plan, r$meta$n_plans_withheld), c(4L, 0L, 0L))

  # Under the listing floor a plan is counted, not shown.
  small <- run(10L)
  expect_equal(nrow(small$courses), 0L)
  expect_equal(c(small$meta$n_plans_withheld, small$meta$n_students_withheld), c(2L, 4L))

  expect_error(get_exit_requirement_progress(far, dplyr::select(xc01$programs, -program_code), xc01$attempts,
                                             plans$courses, xc01$boards$catalog$program_codes),
               "programs lacks program_code")
})
