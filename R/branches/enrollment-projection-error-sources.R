# Why past forecasts missed: each aftcast's seat change and prior fill, seat
# consistency, and the error and range-coverage summaries the page shows.

# ---- Why past forecasts missed ------------------------------------------------
#
# Each past forecast term is tagged with the conditions it was made under: how
# far the course's scheduled seats moved from its previous same-season
# offering (fold_seat_change), and whether that previous offering was near
# full on the first day (fold_prior_near_full; NA when its first day or seats
# are unknown). A near-full course's registrations follow its seats, so these
# two separate a miss the schedule caused from a miss the forecast made. They
# feed seat consistency and the error-source summary.
annotate_projection_fold_conditions <- function(backtests, enrollment_history,
                                                section_history, opt = list()) {
  if (nrow(backtests) == 0L) {
    return(dplyr::mutate(
      backtests, fold_seat_change = numeric(), fold_prior_near_full = logical()
    ))
  }
  keys <- c("market_id", "subject_course", "term_type")
  projection_require_columns(
    backtests, c(keys, "target_term"), "annotate_projection_fold_conditions()"
  )
  threshold <- as.numeric(projection_option(opt, "saturation_fill_threshold"))
  offerings <- section_history %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(c(keys, "term"))), scheduled_capacity) %>%
    dplyr::left_join(
      enrollment_history %>%
        dplyr::select(dplyr::all_of(c(keys, "term")), first_day_enrl),
      by = c(keys, "term")
    ) %>%
    dplyr::arrange(dplyr::across(dplyr::all_of(keys)), term) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::mutate(
      prior_capacity = dplyr::lag(scheduled_capacity),
      prior_first_day = dplyr::lag(first_day_enrl)
    ) %>%
    dplyr::ungroup()
  prior_fill <- projection_capacity_metrics(
    offerings$prior_first_day, offerings$prior_capacity,
    reached_threshold = threshold
  )
  offerings <- offerings %>%
    dplyr::mutate(
      fold_seat_change = dplyr::if_else(
        is.finite(prior_capacity) & prior_capacity > 0 &
          is.finite(scheduled_capacity),
        scheduled_capacity / prior_capacity - 1, NA_real_
      ),
      fold_prior_near_full = dplyr::if_else(
        prior_fill$capacity_usable, prior_fill$capacity_reached, NA
      )
    ) %>%
    dplyr::select(dplyr::all_of(keys), target_term = term,
                  fold_seat_change, fold_prior_near_full)
  backtests %>%
    dplyr::select(-dplyr::any_of(c("fold_seat_change", "fold_prior_near_full"))) %>%
    dplyr::left_join(offerings, by = c(keys, "target_term"))
}


# What each past forecast's miss is attributable to, from the conditions saved
# with it (annotate_projection_fold_conditions()) and its first day. A course
# near full on the first day registers about as many students as it has seats,
# so a miss is the schedule's ("schedule") only when the seats moved and the
# course was near full on the side the miss points to: seats added and the
# forecast low, with the course near full the year before (demand held back)
# or after (it filled the new seats); or seats cut and the forecast high,
# with the course near full after (the cut capped it). Seats that held on a
# course near full after it ("seats_full") also set the number. A course with seats to spare
# could have registered more or fewer students than it did, so its miss is
# the forecast's ("forecast"), whatever its seats did; so is a miss against
# the way the seats moved. "unknown": the seats or the first day needed are
# not in the data.
projection_fold_miss_cause <- function(backtests, opt = list()) {
  projection_require_columns(
    backtests,
    c("error", "fold_seat_change", "fold_prior_near_full", "actual_first_day",
      "scheduled_capacity"),
    "projection_fold_miss_cause()"
  )
  change <- as.numeric(projection_option(opt, "seat_consistency_change"))
  threshold <- as.numeric(projection_option(opt, "saturation_fill_threshold"))
  after <- projection_capacity_metrics(
    backtests$actual_first_day, backtests$scheduled_capacity,
    reached_threshold = threshold
  )
  full_after <- dplyr::if_else(after$capacity_usable, after$capacity_reached, NA)
  full_before <- as.logical(backtests$fold_prior_near_full)
  seats <- as.numeric(backtests$fold_seat_change)
  error <- as.numeric(backtests$error)
  up <- is.finite(seats) & seats >= change
  down <- is.finite(seats) & seats <= -change
  held <- is.finite(seats) & !up & !down
  dplyr::case_when(
    !is.finite(seats) | !is.finite(error) ~ "unknown",
    (up & error > 0) | (down & error < 0) ~ "forecast",
    up & (full_before %in% TRUE | full_after %in% TRUE) ~ "schedule",
    down & full_after %in% TRUE ~ "schedule",
    held & full_after %in% TRUE ~ "seats_full",
    up & full_before %in% FALSE & full_after %in% FALSE ~ "forecast",
    (down | held) & full_after %in% FALSE ~ "forecast",
    # An exact hit has no cause and no weight.
    error == 0 ~ "forecast",
    TRUE ~ "unknown"
  )
}


# Seat consistency: over the past forecast terms behind a course's
# reliability (the rolling rule's published aftcasts), how often its seats
# moved by seat_consistency_change or more. Read beside reliability: a Low
# reliability with Low seat consistency missed with the schedule; with High
# seat consistency, the forecast itself missed.
add_projection_seat_consistency <- function(projections, backtests,
                                            opt = list()) {
  keys <- c("market_id", "subject_course", "term_type")
  change <- as.numeric(projection_option(opt, "seat_consistency_change"))
  moderate_max <- as.integer(
    projection_option(opt, "seat_consistency_moderate_max_moves")
  )
  change_label <- scales::percent(change, accuracy = 1)
  policy <- if (nrow(backtests) == 0L) {
    tibble::tibble(
      market_id = character(), subject_course = character(),
      term_type = character(), target_term = integer(),
      fold_seat_change = numeric()
    )
  } else {
    projection_require_columns(
      backtests, c(keys, "target_term", "policy_selected", "fold_seat_change"),
      "add_projection_seat_consistency()"
    )
    dplyr::filter(backtests, policy_selected)
  }
  per_course <- policy %>%
    dplyr::arrange(target_term) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::summarise(
      seat_consistency_terms = sum(is.finite(fold_seat_change)),
      seat_consistency_moves = sum(
        is.finite(fold_seat_change) & abs(fold_seat_change) >= change
      ),
      moved_text = paste0(
        vapply(target_term[is.finite(fold_seat_change) &
                             abs(fold_seat_change) >= change],
               fmt_term, character(1)),
        " ",
        sprintf("%+.0f%%", 100 * fold_seat_change[
          is.finite(fold_seat_change) & abs(fold_seat_change) >= change
        ]),
        collapse = ", "
      ),
      .groups = "drop"
    )
  projections %>%
    dplyr::select(-dplyr::any_of(c(
      "seat_consistency", "seat_consistency_reason",
      "seat_consistency_terms", "seat_consistency_moves"
    ))) %>%
    dplyr::left_join(per_course, by = keys) %>%
    dplyr::mutate(
      seat_consistency_terms = dplyr::coalesce(seat_consistency_terms, 0L),
      seat_consistency_moves = dplyr::coalesce(seat_consistency_moves, 0L),
      seat_consistency = dplyr::case_when(
        seat_consistency_terms == 0L ~ "Unrated",
        seat_consistency_moves == 0L ~ "High",
        seat_consistency_moves <= moderate_max ~ "Moderate",
        TRUE ~ "Low"
      ),
      seat_consistency_reason = dplyr::case_when(
        seat_consistency_terms == 0L ~
          "No past forecast term has seat counts on both sides to compare",
        seat_consistency_moves == 0L ~ paste0(
          "Seats held within ", change_label, " in all ",
          seat_consistency_terms, " past forecast term",
          dplyr::if_else(seat_consistency_terms == 1L, "", "s")
        ),
        TRUE ~ paste0(
          "Seats moved ", change_label, " or more in ", seat_consistency_moves,
          " of ", seat_consistency_terms, " past forecast term",
          dplyr::if_else(seat_consistency_terms == 1L, "", "s"),
          " (", moved_text, ")"
        )
      )
    ) %>%
    dplyr::select(-moved_text)
}


# Where the published rule's past forecast error came from: each aftcast it
# would have published is read by projection_fold_miss_cause(), split by
# whether its seats held, and the error is summed by source. A near-full
# course's misses follow its seats, which no demand model can see; the misses
# with seats to spare, or with seats moving against the miss, are the
# forecast's own (ISSUES.md I40).
summarize_projection_error_sources <- function(backtests, opt = list()) {
  change_label <- scales::percent(
    as.numeric(projection_option(opt, "seat_consistency_change")), accuracy = 1
  )
  sources <- tibble::tibble(
    source = c("schedule", "seats_full", "forecast_seats_moved",
               "forecast_seats_held", "unknown"),
    owner = c("schedule", "schedule", "forecast", "forecast", "unknown"),
    label = c(
      paste("Near full; seats moved", change_label, "or more the way of the miss"),
      "Near full; seats held",
      paste("Seats moved", change_label, "or more, but did not set the number"),
      "Seats held; course had room",
      "Seat or first-day data missing"
    ),
    meaning = c(
      "A near-full course's registrations follow its seats, so the schedule set the number.",
      "The seats filled again. Close, but it cannot show how many students the course turned away.",
      "The course had seats to spare, or its seats moved against the miss, so the miss is the forecast's own.",
      "The forecast's own, with nothing on the schedule to explain it.",
      "The term's seats or first-day count are not in the data, so the cause cannot be told."
    )
  )
  empty <- dplyr::mutate(
    sources, folds = 0L, wape = NA_real_, share_of_error = NA_real_
  )
  if (nrow(backtests) == 0L) return(empty)
  projection_require_columns(
    backtests,
    c("policy_selected", "abs_error", "actual_classlist_total",
      "fold_seat_change"),
    "summarize_projection_error_sources()"
  )
  policy <- backtests %>%
    dplyr::filter(
      policy_selected, is.finite(abs_error),
      is.finite(actual_classlist_total), actual_classlist_total > 0
    )
  if (nrow(policy) == 0L) return(empty)
  total_error <- sum(policy$abs_error)
  change <- as.numeric(projection_option(opt, "seat_consistency_change"))
  by_source <- policy %>%
    dplyr::mutate(
      cause = projection_fold_miss_cause(policy, opt),
      held = is.finite(fold_seat_change) & abs(fold_seat_change) < change,
      source = dplyr::case_when(
        cause == "forecast" & held ~ "forecast_seats_held",
        cause == "forecast" ~ "forecast_seats_moved",
        TRUE ~ cause
      )
    ) %>%
    dplyr::group_by(source) %>%
    dplyr::summarise(
      folds = dplyr::n(),
      wape = sum(abs_error) / sum(actual_classlist_total),
      share_of_error = if (total_error > 0) sum(abs_error) / total_error else NA_real_,
      .groups = "drop"
    )
  sources %>%
    dplyr::left_join(by_source, by = "source") %>%
    dplyr::mutate(folds = dplyr::coalesce(folds, 0L))
}


# How often the published range would have held, out of sample. Each past
# forecast's range is rebuilt by the published rule from the course's earlier
# published forecasts only: plus or minus the 80th percentile of their misses,
# from one earlier miss on. Split by whether that term's seats held, because
# the range assumes they do (ISSUES.md M35). Arithmetic over saved aftcasts.
summarize_projection_range_coverage <- function(backtests, opt = list()) {
  change <- as.numeric(projection_option(opt, "seat_consistency_change"))
  empty <- tibble::tibble(
    seats = c("steady", "moved", "unknown"), folds = 0L, covered = 0L,
    actual_above = 0L, actual_below = 0L, coverage = NA_real_
  )
  if (nrow(backtests) == 0L) return(empty)
  projection_require_columns(
    backtests,
    c("market_id", "subject_course", "term_type", "target_term",
      "policy_selected", "projected_classlist_total", "actual_classlist_total",
      "fold_seat_change"),
    "summarize_projection_range_coverage()"
  )
  folds <- backtests %>%
    dplyr::filter(
      policy_selected, is.finite(projected_classlist_total),
      is.finite(actual_classlist_total)
    ) %>%
    dplyr::mutate(error = projected_classlist_total - actual_classlist_total) %>%
    dplyr::arrange(market_id, subject_course, term_type, target_term) %>%
    # CAMPUS_ROLLUP: a course's range is the pooled market row's; its earlier
    # misses are read within that market and season.
    dplyr::group_by(market_id, subject_course, term_type) %>%
    dplyr::mutate(half_width = vapply(seq_along(error), function(i) {
      if (i < 2L) return(NA_real_)
      as.numeric(stats::quantile(abs(error[seq_len(i - 1L)]), 0.80, names = FALSE))
    }, numeric(1))) %>%
    dplyr::ungroup() %>%
    dplyr::filter(is.finite(half_width))
  if (nrow(folds) == 0L) return(empty)
  counted <- folds %>%
    dplyr::mutate(
      seats = dplyr::case_when(
        !is.finite(fold_seat_change) ~ "unknown",
        abs(fold_seat_change) >= change ~ "moved",
        TRUE ~ "steady"
      ),
      covered = abs(error) <= half_width
    ) %>%
    dplyr::group_by(seats) %>%
    dplyr::summarise(
      folds = dplyr::n(),
      covered_n = sum(covered),
      # A forecast below the range means registrations came in above it.
      actual_above = sum(!covered & error < 0),
      actual_below = sum(!covered & error > 0),
      .groups = "drop"
    )
  empty %>%
    dplyr::select(seats) %>%
    dplyr::left_join(counted, by = "seats") %>%
    dplyr::transmute(
      seats,
      folds = dplyr::coalesce(folds, 0L),
      covered = dplyr::coalesce(covered_n, 0L),
      actual_above = dplyr::coalesce(actual_above, 0L),
      actual_below = dplyr::coalesce(actual_below, 0L),
      coverage = dplyr::if_else(folds > 0L, covered / folds, NA_real_)
    )
}
