# cedar_shared_result() (R/modules/ui-helpers.R): a result shared by every
# session stores a built value and nothing else (ISSUES I75).

testthat::local_edition(3)

test_that("a shared result is built once, and a failed build is not kept", {
  cache <- cachem::cache_mem()
  builds <- 0L
  build <- function(value) function() { builds <<- builds + 1L; value }
  expect_equal(cedar_shared_result(list("page", "UG"), build(1), cache), 1)
  # The same key reads the stored value; the build does not run again.
  expect_equal(cedar_shared_result(list("page", "UG"), build(2), cache), 1)
  expect_equal(builds, 1L)
  # Another key builds its own.
  expect_equal(cedar_shared_result(list("page", "GR"), build(3), cache), 3)
  # A build that fails (NULL) is handed back and not kept: the next read builds.
  expect_null(cedar_shared_result(list("page", "LAW"), build(NULL), cache))
  expect_equal(cedar_shared_result(list("page", "LAW"), build(4), cache), 4)
  # A condition raised by the build (a failed req() among them) stores nothing.
  expect_error(cedar_shared_result(list("page", "MED"), function() stop("not ready"), cache), "not ready")
  expect_equal(cedar_shared_result(list("page", "MED"), build(5), cache), 5)
  expect_error(cedar_shared_result(list("page"), build(1), cache = NULL), "needs the app's cache")
})
