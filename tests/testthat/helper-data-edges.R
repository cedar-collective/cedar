# What the tests in test-data-edges.R share: builders, option lists, constants.

edge_students <- function() {
  mk <- function(term, n, graded) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded))
  )
  dplyr::bind_rows(
    mk(202480, 100, 91),   # finished, graded
    mk(202580, 100, 91),   # finished, graded
    mk(202610, 100, 7),    # finished, grades still landing
    mk(202660, 100, 0),    # registration only
    mk(202680, 100, 0)     # registration only, partial
  )
}

edge_degrees <- function() tibble::tibble(
  term = c(202480L, 202580L, 202610L),
  graduation_status = c("Awarded", "Awarded", "Pending")
)

settled_students <- function() {
  mk <- function(term, n, graded, pull) tibble::tibble(
    term = rep(as.integer(term), n),
    final_grade = c(rep("A", graded), rep(NA_character_, n - graded)),
    as_of_date = as.Date(pull)
  )
  dplyr::bind_rows(
    mk(202580, 100, 91, "2026-03-07"),   # Fall 2025, pulled long after it began
    mk(202610, 100,  7, "2026-04-20"),   # Spring 2026, began Jan, pulled April
    mk(202660, 100,  0, "2026-04-27"),   # Summer 2026, pulled BEFORE it begins
    mk(202680,  70,  0, "2026-06-18")    # Fall 2026, pulled BEFORE it begins
  )
}
