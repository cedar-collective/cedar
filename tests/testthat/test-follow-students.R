# follow_students(), awarded_degrees() and pending_degrees() (branches/retention-context.R),
# on MT01 (fixtures/scenario_tables.R).

test_that("MT01: each student's readable steps, with enrollment and degree at each", {
  starts <- mt01$population %>% dplyr::filter(student_id != "M-E") %>% dplyr::transmute(student_id, start = first_unit_term)
  f <- follow_students(starts, mt01$student_terms, awarded_degrees(mt01$degrees), 3L, 202210L, 202210L)
  # M-D starts Fall 2021: two steps can be read; the other four have all four.
  expect_equal(as.integer(table(f$student_id)[c("M-A", "M-D")]), c(4L, 2L))
  c_rows <- f[f$student_id == "M-C", ]
  expect_equal(c_rows$target_term, c(202080L, 202110L, 202180L, 202210L))
  # M-C's degree is Fall 2021: held from that step on, enrolled that term too.
  expect_equal(c_rows$degree, c(FALSE, FALSE, TRUE, TRUE))
  expect_equal(c_rows$enrolled, c(TRUE, TRUE, TRUE, FALSE))
  # A degree edge a term earlier leaves the last step unread for everyone.
  expect_equal(max(follow_students(starts, mt01$student_terms, awarded_degrees(mt01$degrees), 3L, 202210L, 202180L)$target_term), 202180L)
  # Started after the degree: by default a degree held, with since_start not this start's.
  late <- tibble::tibble(student_id = "M-C", start = 202210L)
  expect_true(follow_students(late, mt01$student_terms, awarded_degrees(mt01$degrees), 0L, 202210L, 202210L)$degree)
  expect_false(follow_students(late, mt01$student_terms, awarded_degrees(mt01$degrees), 0L, 202210L, 202210L,
                               since_start = TRUE)$degree)
  expect_error(follow_students(dplyr::bind_rows(starts, starts), mt01$student_terms, awarded_degrees(mt01$degrees), 3L, 202210L, 202210L),
               "twice")
})

test_that("only an awarded degree is a degree; a pending row is an application", {
  degrees <- tibble::tibble(student_id = c("A", "B", "C", "D"), term = c(202110L, 202110L, 202180L, 202180L),
                            graduation_status = c("Awarded", "Hold Pending", "Pending", "Record Clear"))
  expect_equal(awarded_degrees(degrees), tibble::tibble(student_id = "A", degree_term = 202110L))
  expect_equal(pending_degrees(degrees), tibble::tibble(student_id = "C", degree_term = 202180L))
  # No status column: every row is an award. No table: no awards.
  expect_equal(nrow(awarded_degrees(degrees["student_id"] %>% dplyr::mutate(term = 202110L))), 4L)
  expect_equal(nrow(awarded_degrees(NULL)), 0L)
  expect_error(pending_degrees(degrees[c("student_id", "term")]), "graduation_status")
})
