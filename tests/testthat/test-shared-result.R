# cedar_shared_result() (R/modules/ui-helpers.R): a result shared by every
# session stores a built value and nothing else (ISSUES I75).
# cedar_preload_shared_results(): the same results built ahead of their first
# reader, one job at a time, after the app has started.

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

test_that("a built result its caller declines to keep is handed back and built again", {
  cache <- cachem::cache_mem()
  builds <- 0L
  build <- function(value) function() { builds <<- builds + 1L; value }
  # A result that lost a part: this reader gets it, the next reader builds.
  expect_equal(cedar_shared_result(list("page", "UG"), build("in part"), cache, keep = function(value) FALSE), "in part")
  expect_equal(cedar_shared_result(list("page", "UG"), build("whole"), cache, keep = function(value) TRUE), "whole")
  expect_equal(cedar_shared_result(list("page", "UG"), build("again"), cache, keep = function(value) FALSE), "whole")
  expect_equal(builds, 2L)
  # `keep` sees the built value.
  expect_equal(cedar_shared_result(list("page", "GR"), build(list(whole = FALSE)), cache,
                                   keep = function(value) value$whole), list(whole = FALSE))
  expect_equal(cedar_shared_result(list("page", "GR"), build(list(whole = TRUE)), cache,
                                   keep = function(value) value$whole), list(whole = TRUE))
  expect_equal(builds, 4L)
})

test_that("a preload builds each job once, in order, and a job that fails stops nothing", {
  cache <- cachem::cache_mem()
  waits <- numeric(0)
  # A scheduler that runs its callback at once and records the wait asked for.
  at_once <- function(callback, delay) { waits <<- c(waits, delay); callback() }
  ran <- character(0)
  job <- function(name, value) list(key = list("page", name), build = function() { ran <<- c(ran, name); value })
  jobs <- list(job("first", 1), list(key = list("page", "broken"), build = function() stop("no such table")),
               job("empty", NULL), job("last", 4))
  log <- testthat::capture_messages(
    expect_equal(cedar_preload_shared_results(jobs, start_after = 10, gap = 1, schedule = at_once,
                                              cache = function() cache), 4L))
  expect_equal(ran, c("first", "empty", "last"))
  # The loop's start, the wait before the first job, then a gap before each later one.
  expect_equal(waits, c(0, 10, 1, 1, 1))
  # A page that asks afterwards reads what was built: its own build does not run.
  expect_equal(cedar_shared_result(list("page", "first"), function() stop("built twice"), cache), 1)
  expect_equal(cedar_shared_result(list("page", "last"), function() stop("built twice"), cache), 4)
  # The job that failed and the one that returned nothing stored nothing: the
  # page builds them when asked, and the failure is in the log.
  expect_equal(cedar_shared_result(list("page", "broken"), function() 2, cache), 2)
  expect_equal(cedar_shared_result(list("page", "empty"), function() 3, cache), 3)
  expect_equal(grepl("no such table", log, fixed = TRUE), c(FALSE, TRUE, FALSE, FALSE))

  # A result someone already built is left as it is.
  ran <- character(0)
  testthat::capture_messages(cedar_preload_shared_results(list(job("first", 9)), schedule = at_once,
                                                          cache = function() cache))
  expect_equal(ran, character(0))
  expect_equal(cedar_shared_result(list("page", "first"), function() 0, cache), 1)

  expect_equal(cedar_preload_shared_results(list(), schedule = function(...) stop("nothing to schedule")), 0L)
  expect_error(cedar_preload_shared_results(list(list(key = "page", build = function() 1)), schedule = at_once),
               "jobs of list(key, build)", fixed = TRUE)
})
