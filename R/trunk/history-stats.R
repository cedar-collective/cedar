# Statistics available before each observation, computed with Welford's stable
# running variance. Non-finite values supply no evidence. SD describes the
# observed history (denominator n); fewer than two observations cannot supply SD.
prior_history_stats <- function(values) {
  stopifnot(is.numeric(values))
  size <- length(values)
  counts <- integer(size)
  means <- spreads <- rep(NA_real_, size)
  totals <- numeric(size)
  n <- 0L
  avg <- m2 <- total <- 0
  for (i in seq_along(values)) {
    counts[i] <- n
    totals[i] <- total
    if (n > 0L) means[i] <- avg
    if (n >= 2L) spreads[i] <- sqrt(max(0, m2 / n))
    if (is.finite(values[i])) {
      n <- n + 1L
      delta <- values[i] - avg
      avg <- avg + delta / n
      m2 <- m2 + delta * (values[i] - avg)
      total <- total + values[i]
    }
  }
  tibble::tibble(hist_n = counts, hist_mean = means,
                 hist_sd = spreads, hist_sum = totals)
}

# Append prior-only summaries to uniquely ordered observations within groups.
# Generic infrastructure: callers define both the grouping and ordering grain.
# Tied/unknown ordering values are rejected rather than depending on row order.
add_prior_history_stats <- function(df, values, groups, order_by) {
  required <- unique(c(values, groups, order_by))
  if (!all(required %in% names(df))) stop("Missing history columns: ",
    paste(setdiff(required, names(df)), collapse = ", "))
  keys <- c(groups, order_by)
  if (anyNA(df[[order_by]]) || anyDuplicated(as.data.frame(df[keys]))) {
    stop("Prior history requires a unique, non-missing ordering value within each group.")
  }
  df <- dplyr::ungroup(df) %>% dplyr::arrange(.data[[order_by]])
  append_stats <- function(rows) {
    for (value in values) {
      stats <- prior_history_stats(rows[[value]])
      rows[paste0(value, "_", names(stats))] <- stats
    }
    rows
  }
  if (nrow(df) == 0L) return(append_stats(df))
  df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(groups))) %>%
    dplyr::group_modify(~ append_stats(.x)) %>%
    dplyr::ungroup()
}
