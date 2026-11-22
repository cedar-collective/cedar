# XC01 (fixtures/scenario_tables.R): ten undergraduates' last terms, with the
# counts written above the fixture.

test_that("XC01: who left, who finished and who cannot be judged yet", {
  r <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, xc01$opt)
  expect_setequal(r$students$student_id, c("X-A", "X-B", "X-C", "X-H", "X-I", "X-J", "X-K"))
  expect_equal(c(r$meta$n_left, r$meta$n_with_degree, r$meta$n_not_judged), c(7L, 1L, 2L))
  # A student who came back is read at the last term, once.
  expect_equal(r$students$exit_term[r$students$student_id == "X-J"], 202110L)
  expect_equal(c(r$meta$first_exit_term, r$meta$last_exit_term), c(202080L, 202110L))
  expect_equal(c(r$meta$edge, r$meta$degree_edge), c(202280L, 202280L))
})

test_that("XC01: a degree on hold is not a degree, and an application to graduate is counted", {
  # X-D's Spring 2021 degree is on hold; X-K's Spring 2023 row is an application.
  degrees <- xc01$degrees %>% dplyr::mutate(graduation_status = c("Hold Pending", "Pending"))
  r <- get_exit_credits(xc01$student_terms, xc01$programs, degrees, xc01$terms, xc01$opt)
  expect_true("X-D" %in% r$students$student_id)
  expect_equal(c(r$meta$n_left, r$meta$n_with_degree), c(8L, 0L))
  expect_equal(r$students$student_id[r$students$applied_to_graduate], "X-K")
  expect_equal(r$meta$n_applied_to_graduate, 1L)
  # With no status on the table every row is an award and no one has applied.
  plain <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, xc01$opt)
  expect_equal(plain$meta$n_applied_to_graduate, 0L)
})

test_that("XC01: credits are the stamped total, with the last term added when the record predates it", {
  r <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, xc01$opt)
  s <- r$students[order(r$students$student_id), ]
  expect_equal(s$credits, c(100, 120, 20, NA, 65, 118, 125))
  expect_equal(s$credits_basis, c("recorded", "recorded + last term", "recorded", NA, rep("recorded", 3)))
  expect_equal(r$meta$n_last_term_added, 1L)
  expect_equal(as.character(s$band),
               c("90 to 114", "120 or more", "Under 30", "Not recorded", "60 to 89", "115 to 119", "120 or more"))
  expect_equal(as.character(r$bands$band),
               c("Under 30", "30 to 59", "60 to 89", "90 to 114", "115 to 119", "120 or more", "Not recorded"))
  expect_equal(r$bands$n, c(1L, 0L, 1L, 1L, 1L, 2L, 1L))
  expect_equal(sum(r$bands$share_pct), 100)
  expect_equal(r$by_term$n[r$by_term$exit_term == 202080L], 1L)
})

test_that("XC01: the floor, the ceiling and Pell are counted over the students each is known for", {
  r <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, xc01$opt)
  s <- r$students[order(r$students$student_id), ]
  # A B C H I J K. At the floor is not under it; no GPA is unknown, not fine.
  expect_equal(s$gpa_below, c(FALSE, TRUE, FALSE, NA, FALSE, NA, FALSE))
  expect_equal(s$attempted, c(110, 162, 24, NA, 70, 120, 130))
  expect_equal(s$over_ceiling, c(FALSE, TRUE, FALSE, NA, FALSE, FALSE, FALSE))
  expect_equal(s$flagged, c(FALSE, TRUE, FALSE, NA, FALSE, NA, FALSE))
  expect_equal(s$ever_pell, c(TRUE, FALSE, NA, NA, FALSE, TRUE, TRUE))
  top <- r$bands[r$bands$band == "120 or more", ]
  expect_equal(c(top$n_pell, top$n_pell_known, top$pell_pct), c(1, 2, 50))
  expect_equal(c(top$n_gpa_below, top$gpa_below_pct, top$n_over_ceiling, top$flagged_pct), c(1, 50, 1, 50))
  # Under the guard a band keeps its counts and has no rate.
  guarded <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                              list(student_level = "UG", data_edges = xc01$edges))
  expect_true(all(is.na(guarded$bands$pell_pct)))
  expect_equal(guarded$bands$n, r$bands$n)
})

test_that("XC01: scope, lines and edges are the caller's", {
  abq <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms, c(xc01$opt, list(campus = "ABQ")))
  expect_false("X-I" %in% abq$students$student_id)
  recent <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                             c(xc01$opt, list(first_exit_term = 202110L)))
  expect_false("X-C" %in% recent$students$student_id)
  # Every level: the student who moved to a graduate program is judged at
  # that level's last term, Fall 2021, and has left it.
  every <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                            list(min_n = 1L, data_edges = xc01$edges))
  expect_equal(every$students$exit_term[every$students$student_id == "X-G"], 202180L)
  strict <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                             c(xc01$opt, list(gpa_floor = 2.6, credit_ceiling = 110, breaks = c(60, 120))))
  expect_equal(sum(strict$students$gpa_below %in% TRUE), 3L)
  expect_equal(sum(strict$students$over_ceiling %in% TRUE), 4L)
  expect_equal(as.character(strict$bands$band), c("Under 60", "60 to 119", "120 or more", "Not recorded"))
  # A later degree edge posts X-K's degree; an earlier enrollment edge judges fewer.
  later <- get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                            list(student_level = "UG", min_n = 1L,
                                 data_edges = list(last_enrolled_complete = 202280L, last_degree = 202310L)))
  expect_false("X-K" %in% later$students$student_id)
  expect_error(get_exit_credits(xc01$student_terms, xc01$programs, xc01$degrees, xc01$terms,
                                list(data_edges = list(last_enrolled_complete = 202280L))),
               "degree edge")
  expect_error(get_exit_credits(xc01$student_terms, dplyr::select(xc01$programs, -inst_gpa), xc01$degrees,
                                xc01$terms, xc01$opt), "programs lacks inst_gpa")
})

test_that("XC01: how often two regular terms away was followed by a return", {
  run <- function(student_terms, window) {
    get_exit_credits(student_terms, xc01$programs, xc01$degrees, xc01$terms,
                     c(xc01$opt, list(return_window = window)))$meta$later_return
  }
  # Seven last terms were followed by two regular terms away and no degree by
  # then (X-C after Fall 2020; A, B, H, I, J, K after Spring 2021). No one came back.
  expect_equal(unlist(run(xc01$student_terms, 0L)[c("n", "n_returned", "through")]),
               c(n = 7L, n_returned = 0L, through = 202110L))
  # X-J was away one regular term (Fall 2020) before coming back: not such an absence.
  # Given two terms more to show a return, only the Fall 2020 absence is read
  # (Spring 2021's would need Spring 2023, past the edge).
  expect_equal(run(xc01$student_terms, 2L)$n, 1L)
  # Add X-A a Fall 2019 term: away Spring and Fall 2020, back in Spring 2021.
  back <- dplyr::bind_rows(xc01$student_terms,
                           xc01$student_terms %>% dplyr::filter(student_id == "X-A") %>% dplyr::mutate(term = 201980L))
  expect_equal(unlist(run(back, 0L)[c("n", "n_returned")]), c(n = 8L, n_returned = 1L))
})
