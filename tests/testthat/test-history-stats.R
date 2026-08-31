# Generic numeric histories are a trunk input contract, not institutional rows.
test_that("prior statistics exclude the current value and use population SD", {
  stats <- prior_history_stats(c(44, 64, 100))
  expect_equal(stats$hist_n, c(0L, 1L, 2L))
  expect_equal(stats$hist_mean, c(NA, 44, 54))
  expect_equal(stats$hist_sd, c(NA, NA, 10))
  expect_equal(stats$hist_sum, c(0, 44, 108))
})

test_that("missing evidence and flat histories cannot manufacture a spread", {
  stats <- prior_history_stats(c(NA, Inf, 20, 20, 60))
  expect_equal(stats$hist_n, c(0L, 0L, 0L, 1L, 2L))
  expect_equal(stats$hist_sd, c(NA, NA, NA, NA, 0))
  expect_equal(nrow(prior_history_stats(numeric())), 0L)
})

test_that("population SD remains accurate on a large numeric offset", {
  stats <- prior_history_stats(1e12 + c(44, 64, 100))
  expect_equal(stats$hist_sd[3], 10)
})

test_that("grouped histories reject ambiguous observation order", {
  frame <- tibble(group = "a", time = c(1L, 1L), value = c(20, 60))
  expect_error(add_prior_history_stats(frame, "value", "group", "time"), "unique, non-missing")
  frame$time <- c(1L, NA_integer_)
  expect_error(add_prior_history_stats(frame, "value", "group", "time"), "unique, non-missing")
})
