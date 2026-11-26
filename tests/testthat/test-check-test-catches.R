# scripts/check-test-catches.R: put a bug back and see whether a test fails.
# Run for real on a three-function tree, since what matters is what it does to
# a tree and what it concludes from a run.

test_that("a break is caught only when a test fails with it in place, and the tree is never edited", {
  testthat::local_edition(3)
  root <- write_tiny_tree(withr::local_tempdir(), tiny_tree)
  before <- tree_checksums(root)

  run <- run_check_test_catches(
    root, tiny_breaks[c("adds_two", "stops", "triples", "never_settles", "does_not_parse")])

  # Two caught of five: the exit status says so to whatever called it.
  expect_equal(run$status, 1L)
  # R's own account of the break that does not parse is quoted, not held.
  quoted <- startsWith(run$report, "     | ")
  expect_true(any(grepl("unexpected '*'", run$report[quoted], fixed = TRUE)))
  expect_snapshot(writeLines(run$report[!quoted]))
  expect_identical(tree_checksums(root), before)
})

test_that("every break caught exits clean", {
  root <- write_tiny_tree(withr::local_tempdir(), tiny_tree)
  run <- run_check_test_catches(root, tiny_breaks["adds_two"])
  expect_equal(run$status, 0L)
  expect_equal(tail(run$report, 1), "1 of 1 break caught.")
})

test_that("breaks that could prove nothing are refused before a test runs", {
  testthat::local_edition(3)
  root <- write_tiny_tree(withr::local_tempdir(), tiny_tree)
  refused <- lapply(tiny_breaks[c("not_there", "there_twice", "no_such_test")],
                    function(entry) run_check_test_catches(root, list(entry)))
  expect_equal(unname(vapply(refused, `[[`, 0L, "status")), c(2L, 2L, 2L))
  expect_equal(unname(lengths(lapply(refused, `[[`, "report"))), c(0L, 0L, 0L))

  # A test that fails as the tree stands fails under any break.
  failing <- write_tiny_tree(
    withr::local_tempdir(),
    replace(tiny_tree, "R/sums.R", list(sub("x + 1", "x - 1", tiny_tree[["R/sums.R"]], fixed = TRUE))))
  already <- run_check_test_catches(failing, tiny_breaks["triples"])
  expect_equal(already$status, 2L)
  expect_false(any(grepl("^1\\. ", already$report)))

  expect_snapshot(writeLines(c(unlist(lapply(refused, `[[`, "said"), use.names = FALSE), already$said)))
})
