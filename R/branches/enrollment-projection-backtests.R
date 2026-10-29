# Aftcasts and choosing a method: rolling-origin backtests, their capacity
# censoring and scoring, and the rolling rule that keeps prior same-season
# unless a challenger beats it out of sample.

add_projection_capacity_censoring <- function(backtests, opt = list()) {
  projection_require_columns(
    backtests,
    c(
      "projected_classlist_total", "actual_classlist_total",
      "projected_first_day_equivalent", "actual_first_day", "scheduled_capacity"
    ),
    "add_projection_capacity_censoring()"
  )
  derived <- c(
    "capacity_fill", "capacity_gap", "capacity_usable",
    "capacity_reached", "error", "abs_error",
    "pct_error", "abs_pct_error", "first_day_equivalent_error",
    "first_day_equivalent_abs_error", "capacity_censored_classlist_projection",
    "capacity_censored_error", "capacity_censored_abs_error",
    "capacity_censored_miss", "capacity_explained_classlist_error",
    "capacity_explained_share"
  )
  base <- dplyr::select(backtests, -dplyr::any_of(derived))
  # Capacity reached is judged on first-day occupancy; the one-sided censor
  # below still compares the class-list projection with the class-list actual.
  # A fold whose first day cannot be reconstructed is never capacity-bounded.
  capacity_status <- projection_capacity_metrics(
    base$actual_first_day,
    base$scheduled_capacity,
    reached_threshold = as.numeric(
      projection_option(opt, "registration_capacity_threshold")
    )
  )

  dplyr::bind_cols(base, capacity_status) %>%
    dplyr::mutate(
      error = projected_classlist_total - actual_classlist_total,
      abs_error = abs(error),
      pct_error = dplyr::if_else(
        actual_classlist_total > 0, error / actual_classlist_total, NA_real_
      ),
      abs_pct_error = abs(pct_error),
      first_day_equivalent_error = projected_first_day_equivalent - actual_first_day,
      first_day_equivalent_abs_error = abs(first_day_equivalent_error),
      capacity_censored_classlist_projection = dplyr::if_else(
        capacity_reached & error > 0,
        actual_classlist_total,
        projected_classlist_total
      ),
      capacity_censored_error =
        capacity_censored_classlist_projection - actual_classlist_total,
      capacity_censored_abs_error = abs(capacity_censored_error),
      capacity_explained_classlist_error = pmax(
        0, abs_error - capacity_censored_abs_error
      ),
      capacity_explained_share = dplyr::if_else(
        abs_error > 0,
        capacity_explained_classlist_error / abs_error,
        0
      ),
      capacity_censored_miss = capacity_reached & error > 0 &
        capacity_explained_classlist_error > 1e-8
    )
}


backtest_course_projection_methods <- function(inputs, roster, target_term,
                                               opt = list()) {
  if (nrow(roster) == 0) return(tibble::tibble())
  max_terms <- as.integer(projection_option(opt, "backtest_terms"))

  results <- lapply(seq_len(nrow(roster)), function(i) {
    row <- roster[i, , drop = FALSE]
    actuals <- projection_history_for_row(
      inputs$enrollment_history, row, before_term = target_term
    ) %>%
      dplyr::slice_tail(n = max_terms) %>%
      dplyr::select(
        term, actual_classlist_total = classlist_total,
        actual_first_day = first_day_enrl,
        actual_census = census_enrl,
        actual_final_enrollment = registered
      )
    if (nrow(actuals) == 0) return(NULL)

    dplyr::bind_rows(lapply(seq_len(nrow(actuals)), function(j) {
      eval_term <- actuals$term[[j]]
      candidates <- project_course_method_candidates(inputs, row, eval_term, opt)
      section <- projection_section_history_for_row(
        inputs$section_history, row
      ) %>%
        dplyr::filter(term == eval_term) %>%
        dplyr::slice_head(n = 1)
      capacity <- if (nrow(section) == 0) NA_real_ else
        section$scheduled_capacity[[1]]
      candidates %>%
        dplyr::mutate(
          actual_classlist_total = actuals$actual_classlist_total[[j]],
          actual_first_day = actuals$actual_first_day[[j]],
          actual_census = actuals$actual_census[[j]],
          actual_final_enrollment = actuals$actual_final_enrollment[[j]],
          scheduled_capacity = capacity
        ) %>%
        add_projection_capacity_censoring(opt)
    }))
  })

  output <- dplyr::bind_rows(results)
  if (nrow(output) == 0) return(tibble::tibble())
  output %>%
    dplyr::mutate(raw_projected_classlist_total = projected_classlist_total) %>%
    dplyr::arrange(market_id, subject_course, target_term, method_id)
}


projection_wape <- function(errors, actuals) {
  keep <- is.finite(errors) & is.finite(actuals)
  denominator <- sum(actuals[keep])
  if (!any(keep) || denominator <= 0) return(NA_real_)
  sum(errors[keep]) / denominator
}


projection_direction_consistency <- function(pct_errors, neutral = 0.01) {
  directional <- pct_errors[
    is.finite(pct_errors) & abs(pct_errors) > as.numeric(neutral)
  ]
  if (length(directional) == 0) return(NA_real_)
  max(mean(directional > 0), mean(directional < 0))
}


validate_projection_capacity_rows <- function(data, caller) {
  if (nrow(data) == 0) return(invisible(TRUE))
  projection_require_columns(
    data,
    c(
      "projected_classlist_total", "actual_classlist_total",
      "projected_first_day_equivalent", "actual_first_day", "scheduled_capacity",
      "capacity_reached", "capacity_gap",
      "capacity_censored_classlist_projection", "capacity_censored_error",
      "abs_error",
      "capacity_censored_abs_error", "capacity_explained_classlist_error",
      "capacity_explained_share", "capacity_censored_miss"
    ),
    caller
  )
  expected_projection <- dplyr::if_else(
    data$capacity_reached &
      data$projected_classlist_total > data$actual_classlist_total,
    data$actual_classlist_total,
    data$projected_classlist_total
  )
  expected_censor_error <- abs(
    expected_projection - data$actual_classlist_total
  )
  expected_signed_error <- expected_projection - data$actual_classlist_total
  expected_explained <- pmax(
    0, data$abs_error - expected_censor_error
  )
  expected_share <- dplyr::if_else(
    data$abs_error > 0,
    expected_explained / data$abs_error,
    0
  )
  expected_limited <- data$capacity_reached &
    data$projected_classlist_total > data$actual_classlist_total &
    expected_explained > 1e-8
  comparable <- is.finite(expected_projection) &
    is.finite(data$capacity_censored_classlist_projection)
  invalid <- (comparable & abs(
    data$capacity_censored_classlist_projection - expected_projection
  ) > 1e-8) |
    (is.finite(expected_signed_error) &
       is.finite(data$capacity_censored_error) &
       abs(data$capacity_censored_error - expected_signed_error) > 1e-8) |
    (is.finite(expected_censor_error) &
       is.finite(data$capacity_censored_abs_error) &
       abs(data$capacity_censored_abs_error - expected_censor_error) >
         1e-8) |
    (is.finite(expected_explained) &
       is.finite(data$capacity_explained_classlist_error) &
       abs(data$capacity_explained_classlist_error - expected_explained) > 1e-8) |
    (is.finite(expected_share) & is.finite(data$capacity_explained_share) &
       abs(data$capacity_explained_share - expected_share) > 1e-8) |
    (!is.na(expected_limited) & data$capacity_censored_miss != expected_limited)

  if (any(invalid, na.rm = TRUE)) {
    stop(
      "[enrollment-projection-backtests.R] ", caller,
      " has an invalid capacity-censoring audit trail.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


empty_projection_performance <- function() {
  tibble::tibble(
    market_id = character(), college = character(), subject_course = character(),
    term_type = character(), method_id = character(), method_label = character(),
    n_backtests = integer(), mae = numeric(), rmse = numeric(), wape = numeric(),
    bias = numeric(), error_q80 = numeric(), backtest_start_term = integer(),
    backtest_end_term = integer(), backtest_terms = character(),
    backtest_term_labels = character(), backtest_term_range = character(),
    n_capacity_usable = integer(), n_capacity_reached = integer(),
    n_capacity_unreached = integer(), capacity_censored_wape = numeric(),
    first_day_equivalent_wape = numeric(), uncensored_wape = numeric(),
    n_capacity_censored_misses = integer(), capacity_explained_wape = numeric(),
    capacity_explained_error_share = numeric(),
    capacity_censored_terms = character(),
    capacity_censored_term_labels = character(),
    capacity_miss_assessment = character(), weighted_bias = numeric(),
    uncensored_weighted_bias = numeric(), mean_pct_error = numeric(),
    pct_error_sd = numeric(), uncensored_pct_error_sd = numeric(),
    overprediction_rate = numeric(),
    underprediction_rate = numeric(), direction_consistency = numeric(),
    signed_error_history = character()
  )
}


summarize_projection_backtests <- function(backtests, opt = list()) {
  if (nrow(backtests) == 0) return(empty_projection_performance())

  capacity_fields <- c(
    "capacity_gap", "capacity_censored_classlist_projection",
    "capacity_censored_miss", "capacity_explained_classlist_error",
    "capacity_explained_share"
  )
  if (!all(capacity_fields %in% names(backtests))) {
    backtests <- add_projection_capacity_censoring(backtests, opt)
  }
  if (!"method_role" %in% names(backtests)) {
    backtests$method_role <- unname(
      CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[backtests$method_id]
    )
  }
  if (!"pct_error" %in% names(backtests)) {
    backtests$pct_error <- dplyr::if_else(
      backtests$actual_classlist_total > 0,
      backtests$error / backtests$actual_classlist_total,
      NA_real_
    )
  }

  usable <- backtests %>%
    dplyr::filter(applicable, is.finite(projected_classlist_total), is.finite(actual_classlist_total))
  if (nrow(usable) == 0) return(empty_projection_performance())

  keys <- c(
    "market_id", "college", "subject_course", "term_type", "method_id",
    "method_label"
  )
  neutral <- 0.01
  usable %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::group_modify(function(.x, .y) {
      rows <- dplyr::arrange(.x, target_term)
      directional <- rows$pct_error[
        is.finite(rows$pct_error) & abs(rows$pct_error) > neutral
      ]
      uncensored <- rows$capacity_usable & !rows$capacity_reached
      censored_terms <- sort(unique(rows$target_term[rows$capacity_censored_miss]))
      tibble::tibble(
        n_backtests = nrow(rows),
        mae = mean(rows$abs_error),
        rmse = sqrt(mean(rows$error^2)),
        wape = projection_wape(rows$abs_error, rows$actual_classlist_total),
        bias = mean(rows$error),
        error_q80 = as.numeric(stats::quantile(rows$abs_error, 0.80, names = FALSE)),
        backtest_start_term = min(rows$target_term),
        backtest_end_term = max(rows$target_term),
        backtest_terms = paste(sort(unique(rows$target_term)), collapse = ","),
        backtest_term_labels = paste(
          vapply(sort(unique(rows$target_term)), fmt_term, character(1)),
          collapse = ", "
        ),
        backtest_term_range = if (min(rows$target_term) == max(rows$target_term)) {
          fmt_term(min(rows$target_term))
        } else {
          paste(fmt_term(min(rows$target_term)), "to", fmt_term(max(rows$target_term)))
        },
        n_capacity_usable = sum(rows$capacity_usable),
        n_capacity_reached = sum(rows$capacity_reached),
        n_capacity_unreached = sum(uncensored),
        first_day_equivalent_wape = projection_wape(
          rows$first_day_equivalent_abs_error, rows$actual_first_day
        ),
        capacity_censored_wape = projection_wape(
          rows$capacity_censored_abs_error, rows$actual_classlist_total
        ),
        uncensored_wape = projection_wape(
          rows$abs_error[uncensored], rows$actual_classlist_total[uncensored]
        ),
        n_capacity_censored_misses = sum(rows$capacity_censored_miss, na.rm = TRUE),
        capacity_explained_wape = projection_wape(
          rows$capacity_explained_classlist_error, rows$actual_classlist_total
        ),
        capacity_explained_error_share = if (sum(rows$abs_error, na.rm = TRUE) > 0) {
          sum(rows$capacity_explained_classlist_error, na.rm = TRUE) /
            sum(rows$abs_error, na.rm = TRUE)
        } else {
          0
        },
        capacity_censored_terms = paste(censored_terms, collapse = ","),
        capacity_censored_term_labels = paste(
          vapply(censored_terms, fmt_term, character(1)), collapse = ", "
        ),
        weighted_bias = projection_wape(rows$error, rows$actual_classlist_total),
        uncensored_weighted_bias = projection_wape(
          rows$error[uncensored], rows$actual_classlist_total[uncensored]
        ),
        mean_pct_error = mean(rows$pct_error, na.rm = TRUE),
        pct_error_sd = if (sum(is.finite(rows$pct_error)) >= 2L) {
          stats::sd(rows$pct_error, na.rm = TRUE)
        } else {
          NA_real_
        },
        uncensored_pct_error_sd = if (
          sum(uncensored & is.finite(rows$pct_error)) >= 2L
        ) {
          stats::sd(rows$pct_error[uncensored], na.rm = TRUE)
        } else {
          NA_real_
        },
        overprediction_rate = if (length(directional) > 0) {
          mean(directional > 0)
        } else {
          NA_real_
        },
        underprediction_rate = if (length(directional) > 0) {
          mean(directional < 0)
        } else {
          NA_real_
        },
        direction_consistency = projection_direction_consistency(
          rows$pct_error, neutral
        ),
        signed_error_history = paste(
          paste0(
            vapply(rows$target_term, fmt_term, character(1)), ": ",
            ifelse(
              is.finite(rows$pct_error),
              sprintf("%+.1f%%", 100 * rows$pct_error), "NA"
            )
          ),
          collapse = "; "
        )
      )
    }) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      capacity_miss_assessment = dplyr::case_when(
        n_capacity_usable == 0L ~ "Insufficient capacity history",
        n_capacity_censored_misses == 0L ~
          "No past forecast misses are explained by the seat ceiling",
        capacity_explained_error_share >= as.numeric(
          projection_option(opt, "capacity_explained_share_threshold")
        ) ~ "Capacity likely explains most of the apparent error",
        TRUE ~ "Capacity may explain part of the apparent error"
      )
    ) %>%
    dplyr::select(dplyr::all_of(names(empty_projection_performance())))
}


attach_projection_performance <- function(candidates, performance,
                                          opt = list()) {
  performance <- dplyr::bind_rows(
    empty_projection_performance(), performance
  )
  candidates %>%
    dplyr::left_join(
      performance,
      by = c(
        "market_id", "college", "subject_course", "term_type",
        "method_id", "method_label"
      )
    ) %>%
    dplyr::mutate(
      raw_projected_classlist_total = projected_classlist_total,
      projected_first_day_equivalent =
        projected_classlist_total * first_day_retention_rate
    )
}


projection_policy_record_columns <- function() {
  c(
    "n_backtests", "mae", "rmse", "wape", "bias", "error_q80",
    "backtest_start_term", "backtest_end_term", "backtest_terms",
    "backtest_term_labels", "backtest_term_range", "n_capacity_usable",
    "n_capacity_reached", "n_capacity_unreached", "first_day_equivalent_wape",
    "capacity_censored_wape", "uncensored_wape", "n_capacity_censored_misses",
    "capacity_explained_wape", "capacity_explained_error_share",
    "capacity_censored_terms", "capacity_censored_term_labels",
    "capacity_miss_assessment", "weighted_bias", "uncensored_weighted_bias",
    "mean_pct_error", "pct_error_sd", "uncensored_pct_error_sd",
    "overprediction_rate", "underprediction_rate", "direction_consistency",
    "signed_error_history"
  )
}


#' Replay the selection rule at every fold of one course's aftcasts
#'
#' @param backtests Aftcast rows for one course market and term type, every
#'   method. Only rows with `target_term < current_term` are read.
#' @param challengers Method ids allowed to challenge the default at
#'   `current_term`.
#' @param current_term The target being published.
#' @return `current`: the pick for `current_term` with its evidence and reason.
#'   `record`: the realised aftcast row the rule would have published at each
#'   historical fold, with a `policy_reason`.
projection_rolling_policy <- function(backtests, challengers, current_term,
                                      opt = list()) {
  default_method <- CEDAR_ENROLLMENT_PROJECTION_DEFAULT_METHOD
  default_label <- unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[default_method]])
  # Inline fallbacks mirror enrollment_projection_model_config().
  min_folds <- as.integer(projection_option(opt, "selection_min_backtests"))
  margin <- as.numeric(projection_option(opt, "selection_challenger_margin"))
  method_order <- names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  current_term <- as.integer(current_term)
  challengers <- setdiff(unique(as.character(challengers %||% character(0))),
                         default_method)

  usable <- if (nrow(backtests) == 0L) {
    backtests
  } else {
    projection_require_columns(
      backtests,
      c("method_id", "target_term", "applicable", "abs_error",
        "actual_classlist_total"),
      "projection_rolling_policy()"
    )
    backtests %>%
      dplyr::filter(
        applicable, is.finite(abs_error), is.finite(actual_classlist_total),
        actual_classlist_total > 0, target_term < current_term
      )
  }

  default_reason <- paste0(
    default_label, " is the default; no other forecast beat it by ",
    scales::percent(margin, accuracy = 0.1), " or more of average error on ",
    min_folds, " or more earlier terms both were made for"
  )

  decide <- function(at_term) {
    result <- list(
      method_id = default_method, common_n = NA_integer_,
      default_wape = NA_real_, challenger_wape = NA_real_,
      reason = default_reason
    )
    if (nrow(usable) == 0L || length(challengers) == 0L) return(result)
    prior <- usable %>% dplyr::filter(target_term < at_term)
    default_prior <- prior %>% dplyr::filter(method_id == default_method)
    if (nrow(default_prior) == 0L) return(result)

    scored <- dplyr::bind_rows(lapply(challengers, function(method) {
      own <- prior %>% dplyr::filter(method_id == method)
      common <- intersect(own$target_term, default_prior$target_term)
      if (length(common) < min_folds) return(NULL)
      shared_default <- default_prior %>%
        dplyr::filter(target_term %in% common)
      shared_own <- own %>% dplyr::filter(target_term %in% common)
      tibble::tibble(
        method_id = method,
        common_n = length(common),
        default_wape = projection_wape(
          shared_default$abs_error, shared_default$actual_classlist_total
        ),
        challenger_wape = projection_wape(
          shared_own$abs_error, shared_own$actual_classlist_total
        )
      )
    }))
    if (nrow(scored) == 0L) return(result)
    winners <- scored %>%
      dplyr::filter(
        is.finite(default_wape), is.finite(challenger_wape),
        challenger_wape <= default_wape - margin
      ) %>%
      dplyr::mutate(method_rank = match(method_id, method_order)) %>%
      dplyr::arrange(challenger_wape, method_rank)
    if (nrow(winners) == 0L) return(result)
    winner <- winners[1, , drop = FALSE]
    list(
      method_id = winner$method_id,
      common_n = as.integer(winner$common_n),
      default_wape = winner$default_wape,
      challenger_wape = winner$challenger_wape,
      reason = paste0(
        unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[winner$method_id]]),
        " beat ", default_label, " on ", winner$common_n,
        " earlier terms both were made for (",
        scales::percent(winner$challenger_wape, accuracy = 0.1), " vs ",
        scales::percent(winner$default_wape, accuracy = 0.1), " off on average)"
      )
    )
  }

  folds <- if (nrow(usable) == 0L) integer(0) else
    sort(unique(usable$target_term))
  record <- dplyr::bind_rows(lapply(folds, function(fold) {
    pick <- decide(fold)
    rows <- usable %>%
      dplyr::filter(target_term == fold, method_id == pick$method_id)
    # The rule may name a method that had no aftcast at this fold (the default
    # before its first comparable term); that fold then has no realised row.
    if (nrow(rows) == 0L) return(NULL)
    dplyr::mutate(rows, policy_reason = pick$reason)
  }))

  list(current = decide(current_term), record = record)
}


# Flag the aftcast row the rolling rule would have published at each fold.
mark_projection_policy_backtests <- function(backtests, policy_record) {
  if (nrow(backtests) == 0L) return(backtests)
  keys <- c("market_id", "subject_course", "term_type", "target_term",
            "method_id")
  picked <- if (is.null(policy_record) || nrow(policy_record) == 0L) {
    backtests[0, keys, drop = FALSE]
  } else {
    policy_record %>% dplyr::distinct(dplyr::across(dplyr::all_of(keys)))
  }
  picked$policy_selected <- rep(TRUE, nrow(picked))
  backtests %>%
    dplyr::select(-dplyr::any_of("policy_selected")) %>%
    dplyr::left_join(picked, by = keys) %>%
    dplyr::mutate(policy_selected = dplyr::coalesce(policy_selected, FALSE))
}


#' Publish one method per course from leakage-safe rolling selection
#'
#' Returns the selected candidate rows. The realised fold-by-fold record the
#' rule produced is attached as `attr(, "policy_record")` so the cone can mark
#' `backtests$policy_selected` without replaying the rule.
select_projection_methods <- function(candidates, performance, backtests,
                                      opt = list()) {
  if (nrow(candidates) == 0) return(tibble::tibble())
  constrained_share <- as.numeric(projection_option(opt, "capacity_constrained_share"))
  method_order <- names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  default_method <- CEDAR_ENROLLMENT_PROJECTION_DEFAULT_METHOD
  default_label <- unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[default_method]])
  keys <- c("market_id", "subject_course", "term_type", "target_term")
  record_columns <- projection_policy_record_columns()
  na_performance <- empty_projection_performance()[NA_integer_, , drop = FALSE]

  joined <- attach_projection_performance(candidates, performance, opt) %>%
    dplyr::mutate(
      method_rank = match(method_id, method_order),
      capacity_constrained_history =
        dplyr::coalesce(n_capacity_usable, 0L) >= 2L &
        dplyr::coalesce(n_capacity_reached / n_capacity_usable, 0) >=
          constrained_share
    )

  records <- list()
  selected <- joined %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::group_modify(function(.x, .y) {
      group_backtests <- backtests
      if (nrow(backtests) > 0L) {
        for (key in intersect(
          c("market_id", "subject_course", "term_type"), names(backtests)
        )) {
          group_backtests <- group_backtests[
            group_backtests[[key]] == .y[[key]][[1]], , drop = FALSE
          ]
        }
      }
      challengers <- .x %>%
        dplyr::filter(
          method_id != default_method, applicable,
          is.finite(projected_classlist_total)
        ) %>%
        dplyr::pull(method_id)
      policy <- projection_rolling_policy(
        group_backtests, challengers, .y$target_term[[1]], opt
      )
      pick <- policy$current
      chosen <- .x %>%
        dplyr::filter(
          method_id == pick$method_id, applicable,
          is.finite(projected_classlist_total)
        )
      selection_reason <- pick$reason
      if (nrow(chosen) == 0L) {
        fallback <- .x %>%
          dplyr::filter(applicable, is.finite(projected_classlist_total)) %>%
          dplyr::arrange(method_rank)
        if (nrow(fallback) == 0L) return(.x[0, , drop = FALSE])
        chosen <- dplyr::slice_head(fallback, n = 1)
        pick <- list(
          common_n = NA_integer_, default_wape = NA_real_,
          challenger_wape = NA_real_
        )
        selection_reason <- paste0(
          "Fallback: ", default_label, " is not available for this target; ",
          chosen$method_label, " is the first applicable candidate"
        )
      }

      realized <- policy$record
      records[[length(records) + 1L]] <<- realized
      summary <- if (nrow(realized) == 0L) {
        na_performance
      } else {
        realized %>%
          dplyr::mutate(
            method_id = chosen$method_id, method_label = chosen$method_label,
            method_role = chosen$method_role
          ) %>%
          summarize_projection_backtests(opt)
      }
      for (column in record_columns) {
        chosen[[column]] <- summary[[column]][[1]]
      }
      chosen %>%
        dplyr::mutate(
          selection_basis = "Rolling selection",
          selection_wape = wape,
          selection_n_backtests = as.integer(n_backtests),
          selection_pct_error_sd = pct_error_sd,
          selection_common_n = as.integer(pick$common_n),
          selection_default_wape = as.numeric(pick$default_wape),
          selection_challenger_wape = as.numeric(pick$challenger_wape),
          selection_reason = selection_reason
        )
    }) %>%
    dplyr::ungroup()

  missing_groups <- joined %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::anti_join(
      dplyr::distinct(selected, dplyr::across(dplyr::all_of(keys))),
      by = keys
    )
  if (nrow(missing_groups) > 0) {
    placeholders <- joined %>%
      dplyr::semi_join(missing_groups, by = keys) %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
      dplyr::slice_head(n = 1) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(
        method_id = "none",
        method_label = "No applicable method",
        raw_projected_classlist_total = NA_real_,
        projected_classlist_total = NA_real_,
        applicable = FALSE,
        applicability_reason = "No candidate method has sufficient evidence",
        n_backtests = NA_integer_,
        mae = NA_real_,
        rmse = NA_real_,
        wape = NA_real_,
        bias = NA_real_,
        error_q80 = NA_real_,
        selection_basis = "Rolling selection",
        selection_wape = NA_real_,
        selection_n_backtests = NA_integer_,
        selection_pct_error_sd = NA_real_,
        selection_common_n = NA_integer_,
        selection_default_wape = NA_real_,
        selection_challenger_wape = NA_real_,
        selection_reason = "No candidate method has sufficient evidence"
      )
    selected <- dplyr::bind_rows(selected, placeholders)
  }

  published <- selected %>%
    dplyr::mutate(
      interval_error = error_q80,
      projected_classlist_total = round(projected_classlist_total),
      projected_first_day_equivalent = round(
        projected_classlist_total * first_day_retention_rate
      ),
      projection_low = pmax(0, round(projected_classlist_total - interval_error)),
      projection_high = round(projected_classlist_total + interval_error),
      projection_low_first_day_equivalent = round(
        projection_low * first_day_retention_rate
      ),
      projection_high_first_day_equivalent = round(
        projection_high * first_day_retention_rate
      ),
      # DEPTH and ACCURACY read the realised rolling-selection record: how many
      # folds the rule published and how far those published aftcasts missed.
      depth = dplyr::case_when(
        method_id == "none" ~ "None",
        dplyr::coalesce(n_backtests, 0L) >=
          as.integer(projection_option(opt, "depth_deep_min_aftcasts")) ~ "Deep",
        dplyr::coalesce(n_backtests, 0L) >=
          as.integer(projection_option(opt, "depth_moderate_min_aftcasts")) ~ "Moderate",
        dplyr::coalesce(n_backtests, 0L) >= 1L ~ "Thin",
        TRUE ~ "None"
      ),
      depth_reason = dplyr::case_when(
        method_id == "none" ~ "No applicable method",
        dplyr::coalesce(n_backtests, 0L) < 1L ~
          "No past forecast to check the selection rule against",
        TRUE ~ paste0(
          n_backtests, " past forecast",
          dplyr::if_else(n_backtests == 1L, "", "s"),
          ", each made with only the evidence available then"
        )
      ),
      accuracy = dplyr::case_when(
        method_id == "none" ~ "Unrated",
        dplyr::coalesce(n_backtests, 0L) <
          as.integer(projection_option(opt, "accuracy_min_aftcasts")) ~ "Unrated",
        !is.finite(wape) ~ "Unrated",
        # Shown to readers as Reliability: High, Moderate, Low (0.23.0; it
        # was Close, Fair, Poor). Whose a Low course's misses were is read
        # per past forecast term (projection_fold_miss_cause(); ISSUES.md I40).
        wape <= as.numeric(projection_option(opt, "accuracy_close_max_wape")) ~ "High",
        wape <= as.numeric(projection_option(opt, "accuracy_fair_max_wape")) ~ "Moderate",
        TRUE ~ "Low"
      ),
      accuracy_reason = dplyr::case_when(
        method_id == "none" ~ "No applicable method",
        dplyr::coalesce(n_backtests, 0L) <
          as.integer(projection_option(opt, "accuracy_min_aftcasts")) ~ paste0(
            "Fewer than ", as.integer(projection_option(opt, "accuracy_min_aftcasts")),
            " past forecasts; reliability cannot be measured"
          ),
        !is.finite(wape) ~ "No measurable reliability",
        TRUE ~ paste0(
          scales::percent(wape, accuracy = 0.1),
          " off on average across ", n_backtests,
          " past forecast", dplyr::if_else(n_backtests == 1L, "", "s"),
          dplyr::if_else(
            is.finite(selection_pct_error_sd),
            paste0(
              ", varying ",
              scales::percent(selection_pct_error_sd, accuracy = 0.1),
              " term to term"
            ),
            ""
          )
        )
      )
    )
  attr(published, "policy_record") <- dplyr::bind_rows(records)
  published
}
