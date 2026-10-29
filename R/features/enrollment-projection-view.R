# Reading a saved enrollment projection bundle: the page view, its sentences,
# the course detail, the draft comparison and the text preview.
#
# Nothing here runs when a bundle is built, so this file is deliberately not
# in enrollment_projection_model_source_files(): editing a sentence the page
# shows must not change the model's fingerprint and rebuild both bundles on
# deploy. Anything the bundle builder calls belongs in
# enrollment-projections.R (features) or the branch files, which are listed.

enrollment_projection_group_choices <- function() {
  c(
    "All saved projections" = "all_saved",
    "Always monitored" = "always_monitored",
    "General Education" = "general_education"
  )
}


enrollment_projection_group_courses <- function(bundle, group_id) {
  switch(
    as.character(group_id %||% "all_saved"),
    all_saved = bundle$scope_courses,
    always_monitored = intersect(
      bundle$scope_courses,
      CEDAR_ENROLLMENT_PROJECTION_ALWAYS_MONITORED_COURSES
    ),
    general_education = intersect(
      bundle$scope_courses,
      unlist(gen_ed_all, use.names = FALSE)
    ),
    stop(
      "[enrollment-projection-view.R] Unknown projection display group: ",
      group_id, call. = FALSE
    )
  )
}


# Reader-facing prose for the three projection axes.
#
# One explanation covers all three because they are only useful together: a
# reader needs to know that a course is Volatile AND Deep (we have watched it
# closely and it genuinely jumps around) rather than Volatile AND Thin (we have
# barely seen it). The old single-paragraph confidence explanation could not
# express that, because it had one label to explain.
projection_axis_explanation <- function(stability, depth, accuracy,
                                        n_backtests, wape,
                                        history_terms = NA_integer_,
                                        history_cv = NA_real_,
                                        history_median_yoy = NA_real_,
                                        term_type = NA_character_,
                                        pct_error_sd = NA_real_,
                                        capacity_constrained = FALSE,
                                        n_capacity_reached = NA_integer_,
                                        n_capacity_unreached = NA_integer_,
                                        method_role = NA_character_,
                                        methods_disagree = FALSE) {
  size <- max(
    length(stability), length(depth), length(accuracy),
    length(n_backtests), length(wape), length(history_terms),
    length(history_cv), length(history_median_yoy),
    length(term_type),
    length(pct_error_sd), length(capacity_constrained),
    length(n_capacity_reached),
    length(n_capacity_unreached), length(method_role), length(methods_disagree)
  )
  stability <- rep_len(as.character(stability), size)
  depth <- rep_len(as.character(depth), size)
  accuracy <- rep_len(as.character(accuracy), size)
  n_backtests <- rep_len(as.integer(n_backtests), size)
  wape <- rep_len(as.numeric(wape), size)
  history_terms <- rep_len(as.integer(history_terms), size)
  history_cv <- rep_len(as.numeric(history_cv), size)
  history_median_yoy <- rep_len(as.numeric(history_median_yoy), size)
  term_type <- rep_len(as.character(term_type), size)
  pct_error_sd <- rep_len(as.numeric(pct_error_sd), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  n_capacity_reached <- rep_len(as.integer(n_capacity_reached), size)
  n_capacity_unreached <- rep_len(as.integer(n_capacity_unreached), size)
  method_role <- rep_len(as.character(method_role), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)

  vapply(seq_len(size), function(i) {
    n <- dplyr::coalesce(n_backtests[[i]], 0L)
    error <- wape[[i]]
    variation <- pct_error_sd[[i]]
    season <- switch(
      term_type[[i]], spring = "Spring", summer = "Summer", fall = "Fall",
      "same-term-type"
    )
    # Reader labels: the `stability` axis is "Own history" and `depth` is
    # "Evidence", so neither reads as a synonym of Reliability.
    stability_text <- switch(
      stability[[i]],
      Stable = paste0(
        "Own history: this course's ", season,
        " enrollment has moved only ",
        scales::percent(history_cv[[i]], accuracy = 0.1),
        " across ", history_terms[[i]], " comparable terms, so its history ",
        "alone supports a forecast."
      ),
      Moderate = paste0(
        "Own history: ", season, " enrollment varies ",
        scales::percent(history_cv[[i]], accuracy = 0.1),
        " across ", history_terms[[i]], " comparable terms — enough movement ",
        "to matter for planning, not enough to make the course unpredictable."
      ),
      Volatile = paste0(
        "Own history: ", season, " enrollment swings ",
        scales::percent(history_cv[[i]], accuracy = 0.1),
        " across ", history_terms[[i]], " comparable terms, typically ",
        scales::percent(history_median_yoy[[i]], accuracy = 0.1),
        " term to term. No method forecasts a course like this reliably; ",
        "the swing itself is the thing worth investigating."
      ),
      paste0(
        "Own history: ", history_terms[[i]], " comparable ", season,
        " term(s) observed, too few to judge whether this course behaves ",
        "predictably."
      )
    )

    depth_text <- switch(
      depth[[i]],
      Deep = paste0(
        "Evidence: ", n, " past ", season,
        " forecasts stand behind its reliability."
      ),
      Moderate = paste0(
        "Evidence: ", n, " past ", season,
        " forecasts, enough to measure reliability, not enough to be sure it holds."
      ),
      Thin = paste0(
        "Evidence: only ", n, " past ", season,
        " forecast", if (n == 1L) "" else "s",
        ", so its reliability rests on very little."
      ),
      "Evidence: no past forecast to measure reliability against."
    )

    # The figure is the realised error of the selection rule replayed at each
    # past term with only earlier evidence, so it is an out-of-sample record
    # rather than the fit of the winner on the terms that chose it.
    accuracy_text <- switch(
      accuracy[[i]],
      High = paste0(
        "Reliability: past forecasts, each made with only the evidence ",
        "available then, landed within ",
        scales::percent(error, accuracy = 0.1), " on average",
        if (is.finite(variation)) paste0(
          ", varying ", scales::percent(variation, accuracy = 0.1),
          " term to term"
        ) else "", "."
      ),
      Moderate = paste0(
        "Reliability: past forecasts, each made with only the evidence ",
        "available then, were ", scales::percent(error, accuracy = 0.1),
        " off on average — usable for planning, not for a precise seat count."
      ),
      Low = paste0(
        "Reliability: past forecasts, each made with only the evidence ",
        "available then, were ", scales::percent(error, accuracy = 0.1),
        " off on average. Treat this projection as a rough scale, not a ",
        "number to schedule to."
      ),
      "Reliability: too few past forecasts to measure how close they came."
    )

    caveats <- character(0)
    if (isTRUE(capacity_constrained[[i]])) {
      reached <- dplyr::coalesce(n_capacity_reached[[i]], 0L)
      unreached <- dplyr::coalesce(n_capacity_unreached[[i]], 0L)
      caveats <- c(caveats, paste0(
        "Capacity caveat: the course filled its seats on the first day in ",
        reached, " of ", reached + unreached,
        " past forecast terms whose first day is known, so its reliability ",
        "measures the students it had room for, not everyone who wanted it."
      ))
    }
    if (isTRUE(methods_disagree[[i]])) {
      caveats <- c(caveats, paste(
        "Method caveat: the two forecasts differ materially, so which one",
        "is used matters."
      ))
    }
    paste(c(stability_text, depth_text, accuracy_text, caveats), collapse = " ")
  }, character(1))
}


# Compact one-line summary for a table cell: the three axes in reading order.
projection_axis_brief <- function(stability, depth, accuracy,
                                  capacity_constrained = FALSE,
                                  methods_disagree = FALSE,
                                  regime_alarm = FALSE) {
  size <- max(
    length(stability), length(depth), length(accuracy),
    length(capacity_constrained), length(methods_disagree),
    length(regime_alarm)
  )
  stability <- rep_len(as.character(stability), size)
  depth <- rep_len(as.character(depth), size)
  accuracy <- rep_len(as.character(accuracy), size)
  capacity_constrained <- rep_len(as.logical(capacity_constrained), size)
  methods_disagree <- rep_len(as.logical(methods_disagree), size)
  regime_alarm <- rep_len(as.logical(regime_alarm), size)

  vapply(seq_len(size), function(i) {
    qualifier <- dplyr::case_when(
      isTRUE(regime_alarm[[i]]) ~ "regime check",
      isTRUE(capacity_constrained[[i]]) ~ "capacity-limited",
      isTRUE(methods_disagree[[i]]) ~ "methods differ",
      TRUE ~ NA_character_
    )
    parts <- c(
      paste0(stability[[i]], " history"),
      paste0(depth[[i]], " evidence"),
      paste0(accuracy[[i]], " reliability"),
      qualifier
    )
    paste(parts[!is.na(parts)], collapse = " \u00b7 ")
  }, character(1))
}


# What a course's reliability means, in one sentence, from where most of its
# past error came (projection_miss_attribution()): a full course whose seats
# changed missed because the schedule did; a course with seats to spare
# missed on its own, whatever its seats did.
projection_reliability_reading <- function(reliability, miss_cause, model_config) {
  close <- model_config$accuracy_close_max_wape
  fair <- model_config$accuracy_fair_max_wape
  if (!is.numeric(close) || !is.numeric(fair) || length(close) != 1L ||
      length(fair) != 1L) {
    stop("[enrollment-projection-view.R] model_config$accuracy_close_max_wape and ",
         "accuracy_fair_max_wape are required.", call. = FALSE)
  }
  pct <- function(x) paste0(round(100 * x), "%")
  reliability <- as.character(reliability)
  miss_cause <- dplyr::coalesce(as.character(miss_cause), "unknown")
  dplyr::case_when(
    reliability == "Unrated" ~
      "Too few past forecasts to say how reliable this course's projection is.",
    reliability == "High" ~
      "Past forecasts landed close, so the projection can be planned to.",
    reliability == "Low" & miss_cause == "seats" ~ paste0(
      "Past forecasts missed by more than ", pct(fair), ", mostly in terms",
      " when the course was near full and its seats changed: the schedule set",
      " those numbers, so the projection holds if the seats do."
    ),
    reliability == "Low" & miss_cause == "forecast" ~ paste0(
      "Past forecasts missed by more than ", pct(fair), " while the course had",
      " seats to spare, so the misses were the forecast's: enrollment changed",
      " on its own. Where the seats moved with it, the department saw the",
      " change coming; ask what it expects before planning to this number."
    ),
    reliability == "Low" ~ paste0(
      "Past forecasts missed by more than ", pct(fair), ", in terms whose seats",
      " or first day are not known, so the cause cannot be told."
    ),
    reliability == "Moderate" & miss_cause == "seats" ~ paste0(
      "Past forecasts were ", pct(close), " to ", pct(fair), " off, mostly",
      " when the course was near full and its seats changed."
    ),
    TRUE ~ paste0(
      "Past forecasts were ", pct(close), " to ", pct(fair), " off: usable for",
      " planning, not for a precise seat count."
    )
  )
}


# Plain-language flags for the summary table. Each one names a reason an
# administrator should look at the row that no column already shows; none
# changes a number. A flag on nearly every row is not a flag: last year's fill
# and its waiting students are the Day-1 fill column (projection_prior_fill()),
# and a forecast more than 20% off is the Reliability column. What stays is
# what a column cannot say: a campus full while the pooled market had room, a
# sharp change in the term just finished, a miss with seats to spare (the
# forecast's own, projection_miss_attribution()), a volatile course with no
# track record, and candidates that disagree.
projection_flags <- function(projections) {
  projection_require_columns(
    projections,
    c("adjusted_regime_alarm", "adjusted_preceding_term_change", "stability",
      "accuracy", "miss_cause", "methods_disagree", "campus_fill_flag"),
    "projection_flags()"
  )
  vapply(seq_len(nrow(projections)), function(i) {
    row <- projections[i, , drop = FALSE]
    flags <- c(
      if (!is.na(row$campus_fill_flag)) row$campus_fill_flag,
      if (isTRUE(row$adjusted_regime_alarm)) paste0(
        "Fall enrollment ",
        sprintf("%+.0f%%", 100 * row$adjusted_preceding_term_change)
      ),
      # With a track record, Reliability already says how predictable the
      # course was; without one, its own volatile history is the only warning.
      if (identical(row$stability, "Volatile") &&
          identical(row$accuracy, "Unrated")) "Hard to predict",
      # A miss while the course had seats to spare is the forecast's, which no
      # column says. A full course's miss as its seats changed is the
      # schedule's and needs no flag.
      if (identical(row$accuracy, "Low") &&
          identical(row$miss_cause, "forecast")) "Off 20%+ with seats to spare",
      if (isTRUE(row$methods_disagree)) "Candidates disagree"
    )
    if (length(flags) == 0L) "" else paste(flags, collapse = " | ")
  }, character(1))
}


# Last year's first-day fill, the term the plan starts from, for the Day-1 fill
# column: the share of seats filled on the first day, its level (full and near
# full, R/lists/seat_fill.R, read live), and beneath it the students left
# waiting or, when the fill is unknown, its cause (ISSUES.md I28).
# `prior_fill_text` joins level and percent for search and the text preview;
# the table shows `prior_fill_percent` with the level beneath. The term is
# named in the column header; `term_label` is set only for a row whose
# starting term differs from `header_term`.
projection_prior_fill <- function(projections, header_term = NULL) {
  projection_require_columns(
    projections,
    c("spine_term", "adjusted_saturated_prior", "adjusted_prior_first_day_fill",
      "adjusted_prior_first_day_basis", "adjusted_waitlisted_prior"),
    "projection_prior_fill()"
  )
  fill <- as.numeric(projections$adjusted_prior_first_day_fill)
  basis <- as.character(projections$adjusted_prior_first_day_basis)
  waiting <- as.numeric(projections$adjusted_waitlisted_prior)
  term <- as.integer(projections$spine_term)
  known <- is.finite(fill)
  level <- dplyr::case_when(
    known & fill >= CEDAR_FULL_FILL ~ "Full",
    known & fill >= CEDAR_NEAR_FULL_FILL ~ "Near full",
    TRUE ~ NA_character_
  )
  # One decimal: whole percents turned 98.8% into "99%" and read as full.
  percent <- dplyr::if_else(
    known, sprintf("%.1f%%", 100 * fill), NA_character_
  )
  unknown_cause <- dplyr::case_when(
    basis == "undated" ~ "no status dates",
    basis == "sessions_pending" ~ "a session had not begun",
    basis == "no_capacity" ~ "no seat count",
    TRUE ~ NA_character_
  )
  text <- dplyr::case_when(
    !is.na(level) ~ paste(level, "·", percent),
    known ~ percent,
    !is.na(unknown_cause) ~ "Unknown",
    TRUE ~ NA_character_
  )
  note <- dplyr::case_when(
    !is.na(level) & is.finite(waiting) & waiting > 0 ~
      paste(format(waiting, big.mark = ",", trim = TRUE), "waiting"),
    !known ~ unknown_cause,
    TRUE ~ NA_character_
  )
  term_label <- if (is.null(header_term)) {
    rep(NA_character_, length(term))
  } else {
    dplyr::if_else(!is.na(term) & term != header_term, fmt_term(term), NA_character_)
  }
  tibble::tibble(
    prior_fill = fill,
    prior_fill_text = text,
    prior_fill_percent = dplyr::if_else(known, percent, text),
    prior_fill_level = level,
    prior_fill_note = note,
    prior_fill_term = term_label
  )
}


# What each evidence axis measured, as the number behind its rating: the
# table and the course detail show these, coloured by the rating, so a reader
# needs no definition of "Moderate" to read them. Unrated and None stay words.
projection_axis_values <- function(projections) {
  projection_require_columns(
    projections,
    c("stability", "history_cv", "depth", "n_backtests", "accuracy", "wape",
      "seat_consistency", "seat_consistency_moves", "seat_consistency_terms"),
    "projection_axis_values()"
  )
  rated <- function(rating, value) {
    dplyr::if_else(rating %in% c("Unrated", "None") | is.na(value),
                   as.character(rating), value)
  }
  backtests <- as.integer(projections$n_backtests)
  tibble::tibble(
    stability_value = rated(
      projections$stability,
      sprintf("%.1f%% variation", 100 * projections$history_cv)
    ),
    depth_value = rated(
      projections$depth,
      paste0(backtests, " past forecast", dplyr::if_else(backtests == 1L, "", "s"))
    ),
    accuracy_value = rated(
      projections$accuracy, sprintf("%.1f%% off", 100 * projections$wape)
    ),
    # Shown beneath reliability, uncoloured: context for a miss, not a grade.
    seat_consistency_value = rated(
      projections$seat_consistency,
      paste("seats moved in", projections$seat_consistency_moves, "of",
            projections$seat_consistency_terms)
    )
  )
}


# What each past forecast's miss is attributable to, from the conditions saved
# with it (annotate_projection_fold_conditions()) and its first day. A course
# near full on the first day registers about as many students as it has seats,
# so a miss is the schedule's ("schedule") only when the seats moved and the
# course was full on the side the miss points to: seats added and the
# forecast low, with the course full the year before (demand held back) or
# after (it filled the new seats); or seats cut and the forecast high, with
# the course full after (the cut capped it). Seats that held on a course full
# after it ("seats_full") also set the number. A course with seats to spare
# could have registered more or fewer students than it did, so its miss is
# the forecast's ("forecast"), whatever its seats did; so is a miss against
# the way the seats moved. "unknown": the seats or the first day needed are
# not in the data.
projection_fold_miss_cause <- function(backtests, model_config) {
  projection_require_columns(
    backtests,
    c("error", "fold_seat_change", "fold_prior_near_full", "actual_first_day",
      "scheduled_capacity"),
    "projection_fold_miss_cause()"
  )
  change <- model_config$seat_consistency_change
  threshold <- model_config$saturation_fill_threshold
  if (!is.numeric(change) || !is.numeric(threshold) || length(change) != 1L ||
      length(threshold) != 1L) {
    stop("[enrollment-projection-view.R] model_config$seat_consistency_change and ",
         "saturation_fill_threshold are required.", call. = FALSE)
  }
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


# Where most of each course's past error came from, over the rule's published
# past forecasts (the terms behind its reliability): "seats" when the schedule
# set the number (projection_fold_miss_cause() "schedule" or "seats_full"),
# "forecast" when the course had seats to spare, "unknown" when the data
# cannot tell; whichever holds the largest share of its absolute error. NA for
# a course with no past forecast.
projection_miss_attribution <- function(projections, backtests, model_config) {
  keys <- c("market_id", "subject_course", "term_type")
  projection_require_columns(projections, keys, "projection_miss_attribution()")
  none <- tibble::tibble(miss_cause = rep(NA_character_, nrow(projections)),
                         miss_seat_share = NA_real_, miss_forecast_share = NA_real_)
  if (nrow(projections) == 0L || nrow(backtests) == 0L) return(none)
  projection_require_columns(
    backtests, c(keys, "policy_selected", "abs_error"),
    "projection_miss_attribution()"
  )
  folds <- backtests %>%
    dplyr::filter(policy_selected %in% TRUE, is.finite(abs_error))
  folds$cause <- projection_fold_miss_cause(folds, model_config)
  shares <- folds %>%
    dplyr::mutate(group = dplyr::case_when(
      cause %in% c("schedule", "seats_full") ~ "seats",
      TRUE ~ cause
    )) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::summarize(
      total = sum(abs_error),
      seats = sum(abs_error[group == "seats"]),
      forecast = sum(abs_error[group == "forecast"]),
      unknown = sum(abs_error[group == "unknown"]),
      .groups = "drop"
    ) %>%
    dplyr::filter(total > 0) %>%
    dplyr::mutate(
      # Ties go to the schedule, then the forecast: the larger known cause.
      miss_cause = dplyr::case_when(
        seats >= forecast & seats >= unknown ~ "seats",
        forecast >= unknown ~ "forecast",
        TRUE ~ "unknown"
      ),
      miss_seat_share = seats / total,
      miss_forecast_share = forecast / total
    ) %>%
    dplyr::select(dplyr::all_of(keys), miss_cause, miss_seat_share, miss_forecast_share)
  projections %>%
    dplyr::select(dplyr::all_of(keys)) %>%
    dplyr::left_join(shares, by = keys) %>%
    dplyr::select(miss_cause, miss_seat_share, miss_forecast_share)
}


# Sentences for the page on the courses whose past forecasts missed most: how
# many missed mostly as a full course's seats changed (the schedule's), and
# which missed with seats to spare (the forecast's own, named, since they are
# the ones to look at). Said even when the answer is none, because "none
# missed with seats to spare" is the finding.
projection_miss_sentence <- function(projections, model_config) {
  projection_require_columns(
    projections, c("accuracy", "miss_cause", "subject_course"),
    "projection_miss_sentence()"
  )
  fair_max <- model_config$accuracy_fair_max_wape
  if (!is.numeric(fair_max) || length(fair_max) != 1L || !is.finite(fair_max)) {
    stop("[enrollment-projection-view.R] model_config$accuracy_fair_max_wape is required.",
         call. = FALSE)
  }
  n <- nrow(projections)
  if (n == 0L) return(NA_character_)
  threshold <- paste0(round(100 * fair_max), "%")
  low <- projections$accuracy == "Low"
  n_low <- sum(low)
  course_word <- function(k) paste0("course", if (k == 1L) "" else "s")
  if (n_low == 0L) {
    return(paste0(
      if (n == 1L) "The course shown has not" else paste("None of the", n, "courses shown has"),
      " had past forecasts more than ", threshold, " off."
    ))
  }
  cause <- dplyr::coalesce(projections$miss_cause[low], "unknown")
  seats <- sum(cause == "seats")
  own <- sort(projections$subject_course[low][cause == "forecast"])
  unknown <- sum(cause == "unknown")
  for_how_many <- function(k) {
    if (k == n_low && n_low > 1L) paste("all", k) else as.character(k)
  }
  named <- function(courses) {
    if (length(courses) <= 5L) paste0(" (", paste(courses, collapse = ", "), ")") else ""
  }
  paste0(
    n_low, " of the ", n, " ", course_word(n), " shown had past forecasts more than ",
    threshold, " off.",
    if (seats > 0L) paste0(
      " For ", for_how_many(seats), ", most of the miss came when the course was",
      " near full and its seats changed, so the schedule set the number."
    ),
    if (length(own) > 0L) paste0(
      " For ", for_how_many(length(own)), named(own), ", the course had seats to",
      " spare, so the miss was the forecast's own."
    ) else " None missed with seats to spare.",
    if (unknown > 0L) paste0(
      " For ", for_how_many(unknown), ", the seats or first day of those terms",
      " are not known."
    )
  )
}


# One flag per projection where, in the latest recent term, a delivery campus
# was full on the first day while another had room. The forecast pools the
# campuses as one market; this keeps a full online campus from hiding behind
# open seats elsewhere (ISSUES.md M36). Only complete first days with usable
# seats are compared; NA where no campus pair qualifies.
projection_campus_fill_flags <- function(projections, campus_history) {
  projection_require_columns(
    projections, c("market_id", "subject_course", "target_term"),
    "projection_campus_fill_flags()"
  )
  projection_require_columns(
    campus_history,
    c("market_id", "subject_course", "projection_target_term", "history_term",
      "recency_rank", "campus", "first_day_basis", "first_day_fill"),
    "projection_campus_fill_flags() campus history"
  )
  # CAMPUS_ROLLUP: one flag per pooled market row, naming each campus.
  # The term is named: "last term" read as the term just finished, when this
  # is the latest same-season term.
  flags <- campus_history %>%
    dplyr::filter(
      recency_rank == 1L, first_day_basis == "complete",
      is.finite(first_day_fill)
    ) %>%
    dplyr::group_by(market_id, subject_course, projection_target_term) %>%
    dplyr::summarise(
      history_term = dplyr::first(history_term),
      full = paste(sort(campus[first_day_fill >= CEDAR_FULL_FILL]), collapse = " and "),
      room = paste(sort(campus[first_day_fill < CEDAR_NEAR_FULL_FILL]), collapse = " and "),
      .groups = "drop"
    ) %>%
    dplyr::filter(nzchar(full), nzchar(room)) %>%
    dplyr::transmute(
      market_id, subject_course, target_term = projection_target_term,
      campus_fill_flag = paste0(
        full, " full in ", fmt_term(history_term), ", ", room, " had room"
      )
    )
  projections %>%
    dplyr::select(market_id, subject_course, target_term) %>%
    dplyr::left_join(
      flags, by = c("market_id", "subject_course", "target_term"),
      relationship = "many-to-one"
    ) %>%
    dplyr::pull(campus_fill_flag)
}


# One sentence an administrator can act on, built from the published fields.
# The tables beneath it are supporting evidence, not the first thing a reader
# meets.
projection_summary_sentence <- function(projections) {
  vapply(seq_len(nrow(projections)), function(i) {
    row <- projections[i, , drop = FALSE]
    if (!is.finite(row$projected_classlist_total)) {
      return("Not enough comparable history to project this course.")
    }
    count <- function(x) format(round(x), big.mark = ",")
    bumped <- isTRUE(row$pressure_bump > 0)
    fed <- isTRUE(row$plan_feeder_adjustment != 0)
    raised <- bumped || fed
    first_day <- if (is.finite(row$projected_first_day_equivalent)) {
      paste0(
        " (about ", count(row$projected_first_day_equivalent),
        if (raised) paste0(" of the projected ", count(row$projected_classlist_total)) else "",
        " in seats on the first day)"
      )
    } else ""
    # The projection, then what the plan adds to it: the feeder adjustment
    # (either way) and the pressure bump.
    parts <- paste0(
      count(row$projected_classlist_total), " projected",
      if (fed) {
        paste0(", ", sprintf("%+.0f", row$plan_feeder_adjustment),
               " for the change in its feeder courses")
      } else "",
      if (bumped) {
        paste0(if (fed) "," else "", " plus a pressure bump of ",
               count(row$pressure_bump))
      } else ""
    )
    plan <- if (!is.na(row$recommended_sections)) {
      paste0(
        if (isTRUE(row$adjusted_saturated_prior)) "Plan at least " else "Plan ",
        row$recommended_sections, " section",
        if (row$recommended_sections == 1L) "" else "s", " for ",
        count(row$planned_registrations), " registrations",
        if (raised) paste0(": ", parts) else "",
        first_day, "."
      )
    } else {
      paste0(
        "Expect about ", count(row$planned_registrations), " registrations",
        if (raised) paste0(" (", parts, ")") else "",
        "; no section size is available to convert that to sections."
      )
    }
    change <- if (is.finite(row$observed_baseline) && row$observed_baseline > 0) {
      delta <- row$projected_classlist_total / row$observed_baseline - 1
      if (abs(delta) < 0.005) {
        " That is last year's level."
      } else {
        paste0(" That is ", sprintf("%+.0f%%", 100 * delta),
               " on last ", switch(row$term_type, spring = "Spring",
                                   fall = "Fall", "comparable term"), ".")
      }
    } else ""
    full <- if (isTRUE(row$adjusted_saturated_prior)) {
      paste0(
        " Last ", switch(row$term_type, spring = "Spring", fall = "Fall", "term"),
        " filled ", scales::percent(row$adjusted_prior_first_day_fill, accuracy = 0.1),
        " of its seats on the first day",
        if (isTRUE(row$adjusted_waitlisted_prior > 0)) {
          paste0(" with ", row$adjusted_waitlisted_prior, " students waiting")
        } else "",
        ", so this is a floor."
      )
    } else ""
    # A course full last term with no bump says why, so a reader does not
    # take the missing bump for an oversight.
    no_bump <- if (isTRUE(row$adjusted_saturated_prior) &&
                   isFALSE(row$pressure_bump_applied)) {
      paste0(" ", row$pressure_bump_note, ".")
    } else ""
    fall <- if (isTRUE(row$adjusted_regime_alarm)) {
      paste0(
        " Enrollment in ", fmt_term(row$adjusted_preceding_term), " moved ",
        sprintf("%+.0f%%", 100 * row$adjusted_preceding_term_change),
        " from the year before; review before scheduling to this number."
      )
    } else ""
    # The course's own figure, rounded as its plan steps round it: the band
    # ("10 to 20% off") read beside the step's 10.0% as though they disagreed.
    trust <- if (identical(row$accuracy, "Unrated") || !is.finite(row$wape)) {
      " Too few past forecasts to say how reliable this is."
    } else {
      paste0(
        " Past forecasts for this course missed by ",
        scales::percent(row$wape, accuracy = 0.1), " on average",
        if (identical(row$accuracy, "Low")) "; treat it as a rough scale" else "",
        "."
      )
    }
    paste0(plan, change, full, no_bump, fall, trust)
  }, character(1))
}


# How one course's plan was built, step by step from last year's class list to
# the sections: every number on the course's detail, each with where it came
# from, so a reader can check the plan without opening the evidence. Display
# only, from saved fields: the projection's own audit trail (spine, floor,
# deltas), the plan's two additions, and the section size. Returns one row per
# step: `label`, `amount`, `kind` ("start", "add", "total" or "sections") and
# `detail`. A course with no projection has no steps.
projection_plan_steps <- function(row) {
  projection_require_columns(
    row,
    c("term_type", "method_id", "spine", "spine_term", "floor_uplift",
      "delta_repeat", "delta_sequence", "delta_feeder",
      "adjusted_sequence_courses", "adjusted_preceding_term",
      "projected_classlist_total", "accuracy", "wape", "n_backtests",
      "backtest_term_range", "plan_feeder_adjustment", "plan_feeder_note",
      "pressure_bump", "pressure_bump_note", "planned_registrations",
      "reference_section_size", "recommended_sections",
      "scheduled_sections", "target_schedule_available"),
    "projection_plan_steps()"
  )
  if (nrow(row) != 1L) {
    stop("[enrollment-projection-view.R] projection_plan_steps() takes one row.",
         call. = FALSE)
  }
  empty <- tibble::tibble(
    label = character(), amount = numeric(), kind = character(),
    detail = character()
  )
  if (!is.finite(row$projected_classlist_total) || !is.finite(row$spine)) {
    return(empty)
  }
  count <- function(x) format(round(x), big.mark = ",")
  signed <- function(x) {
    paste0(if (round(x) > 0) "+" else if (round(x) < 0) "\u2212" else "",
           count(abs(x)))
  }
  season <- switch(row$term_type, spring = "Spring", fall = "Fall", "term")
  step <- function(label, amount, kind, detail = NA_character_) {
    tibble::tibble(label = label, amount = as.numeric(amount), kind = kind,
                   detail = detail)
  }
  # The plan notes open with "Feeder adjustment -68: " / "Pressure bump +109: ",
  # which the step's label and amount already say.
  reason <- function(note) {
    text <- sub("^[^:]*[+-][0-9,]+: ", "", note)
    paste0(toupper(substr(text, 1, 1)), substring(text, 2))
  }

  adjusted <- identical(row$method_id, "spine_adjusted")
  floor_uplift <- if (adjusted) dplyr::coalesce(row$floor_uplift, 0) else 0
  steps <- list(step(
    paste0("Registered in ", fmt_term(row$spine_term)), row$spine, "start",
    paste0("Everyone on last ", season, "'s class lists, including students ",
           "who later dropped")
  ))
  if (floor_uplift != 0) {
    steps <- c(steps, list(step(
      "Students still waiting", floor_uplift, "add",
      paste0("Waitlisted last ", season, " without a seat in any section, ",
             "because the course was near full")
    )))
  }
  # The projection is the rounded sum, so the change is whatever takes the
  # whole-number start to it; its parts are rounded separately and say so
  # when they no longer add up to it.
  # Parts that cancel still show, so the adjusted method's work is visible.
  change <- row$projected_classlist_total - row$spine - floor_uplift
  parts <- c(
    dplyr::coalesce(row$delta_repeat, 0),
    dplyr::coalesce(row$delta_sequence, 0),
    dplyr::coalesce(row$delta_feeder, 0)
  )
  if (adjusted && any(round(parts) != 0)) {
    names <- c(
      "students retaking this course",
      paste0(dplyr::coalesce(row$adjusted_sequence_courses, "the listed predecessor"),
             ", taken just before"),
      "other feeder courses"
    )
    shown <- round(parts) != 0
    detail <- paste0(
      paste0(names[shown], " ", vapply(parts[shown], signed, character(1)),
             collapse = "; "),
      if (sum(round(parts)) != round(change)) " (each rounded)" else ""
    )
    steps <- c(steps, list(step(
      paste0("Enrollment change in ", fmt_term(row$adjusted_preceding_term)),
      change, "add", detail
    )))
  }
  record <- if (identical(row$accuracy, "Unrated") || !is.finite(row$wape)) {
    "Too few past forecasts to say how close this one will be"
  } else {
    paste0(
      "Past forecasts for this course missed by ",
      scales::percent(row$wape, accuracy = 0.1), " on average (",
      row$n_backtests, " term", if (row$n_backtests == 1L) "" else "s",
      if (!is.na(row$backtest_term_range)) paste0(", ", row$backtest_term_range) else "",
      ")"
    )
  }
  steps <- c(steps, list(step(
    "Forecast registrations", row$projected_classlist_total, "total", record
  )))
  if (isTRUE(row$plan_feeder_adjustment != 0)) {
    steps <- c(steps, list(step(
      "Feeder adjustment", row$plan_feeder_adjustment, "add",
      reason(row$plan_feeder_note)
    )))
  }
  if (isTRUE(row$pressure_bump > 0)) {
    steps <- c(steps, list(step(
      "Pressure bump", row$pressure_bump, "add", reason(row$pressure_bump_note)
    )))
  }
  if (isTRUE(row$plan_feeder_adjustment != 0) || isTRUE(row$pressure_bump > 0)) {
    steps <- c(steps, list(step(
      "Planned registrations", row$planned_registrations, "total",
      "What the sections are sized for"
    )))
  }
  if (!is.na(row$recommended_sections)) {
    from_draft <- isTRUE(row$target_schedule_available) &&
      isTRUE(row$scheduled_sections > 0)
    steps <- c(steps, list(step(
      "Sections", row$recommended_sections, "sections",
      paste0(
        count(row$planned_registrations), " registrations at ",
        format(round(row$reference_section_size, 1), nsmall = 1),
        " per section (",
        if (from_draft) "the draft schedule's average" else "recent average",
        "), rounded up",
        if (from_draft) {
          paste0("; the draft schedule has ", row$scheduled_sections,
                 " section", if (row$scheduled_sections == 1L) "" else "s")
        } else ""
      )
    )))
  }
  dplyr::bind_rows(steps)
}


# What the pressure bump adds across the rows shown, and one sentence saying
# so, so the page states how much it raised the plan. Rows without a
# projection carry a zero bump and no sections, and are left out of the
# section total.
projection_pressure_bump_summary <- function(projections, share) {
  if (!is.numeric(share) || length(share) != 1L || !is.finite(share)) {
    stop("[enrollment-projection-view.R] The bundle's model_config has no ",
         "pressure_bump_share.", call. = FALSE)
  }
  applied <- projections$pressure_bump_applied %in% TRUE
  registrations <- sum(projections$pressure_bump[applied])
  projected <- sum(projections$projected_classlist_total[applied])
  sections <- sum(projections$pressure_bump_sections[applied], na.rm = TRUE)
  n_courses <- sum(applied)
  sentence <- if (n_courses == 0L) {
    paste(
      "No course shown gets a pressure bump: none was near full on the first",
      "day in every recent same-season term with a first-day count."
    )
  } else {
    paste0(
      "The pressure bump adds ", format(round(registrations), big.mark = ","),
      " registrations (", scales::percent(registrations / projected, accuracy = 0.1),
      " of those courses' projections) and ", format(sections, big.mark = ","),
      " section", if (sections == 1L) "" else "s", " across ", n_courses,
      " of the ", nrow(projections), " courses shown. They were near full on ",
      "the first day in every recent same-season term with a first-day count, ",
      "so their registrations were capped by their seats. The bump is ",
      scales::percent(share, accuracy = 1), ", or the students left waiting if ",
      "that is more, and it will be measured from waitlists as they accumulate."
    )
  }
  list(
    n_courses = as.integer(n_courses),
    registrations = as.numeric(registrations),
    sections = as.integer(sections),
    sentence = sentence
  )
}


# What the plan's feeder adjustment moves across the rows shown, and one
# sentence saying so: how many plans it raised and lowered and by how much,
# or why it moved none. `line` and `seasons` are the bundle's
# plan_feeder_change and plan_feeder_seasons.
projection_plan_feeder_summary <- function(projections, line, seasons) {
  if (!is.numeric(line) || length(line) != 1L || !is.finite(line)) {
    stop("[enrollment-projection-view.R] The bundle's model_config has no ",
         "plan_feeder_change.", call. = FALSE)
  }
  seasons_rule <- projection_plan_feeder_seasons_rule(seasons)
  projection_require_columns(
    projections,
    c("term_type", "projected_classlist_total", "method_id",
      "plan_feeder_adjustment", "adjusted_preceding_term",
      "adjusted_feeder_check"),
    "projection_plan_feeder_summary()"
  )
  projected <- is.finite(projections$projected_classlist_total)
  out_of_season <- projected & !projections$term_type %in% seasons
  adjustment <- projections$plan_feeder_adjustment
  up <- projected & adjustment > 0
  down <- projected & adjustment < 0
  in_projection <- projected & projections$method_id == "spine_adjusted"
  unobserved <- projected & projections$adjusted_feeder_check %in% "term_not_observed"
  preceding <- stats::na.omit(projections$adjusted_preceding_term)
  preceding_label <- if (length(preceding) > 0L) fmt_term(preceding[[1]]) else
    "the term just finished"
  count <- function(x) format(round(x), big.mark = ",")
  whose <- function(n, noun) {
    if (n == 1L) paste0("1 course's ", noun) else paste0(n, " courses' ", noun, "s")
  }
  rule <- paste0(
    "A course's listed predecessor, taken the term before, always counts; its ",
    "other feeder courses count when they moved ",
    scales::percent(line, accuracy = 1), " or more."
  )
  included <- if (sum(in_projection) > 0L) {
    paste0(
      " ", whose(sum(in_projection), "published projection"),
      if (sum(in_projection) == 1L) " already includes" else " already include",
      " those changes."
    )
  } else ""
  sentence <- if (sum(projected) > 0L && all(out_of_season[projected])) {
    paste0("No plan has a feeder adjustment: ", seasons_rule, ".")
  } else if (sum(projected) > 0L && all(unobserved[projected])) {
    paste0(
      "No plan has a feeder adjustment: ", preceding_label, " is not observed ",
      "yet, so its feeder courses cannot be read. They count once it settles."
    )
  } else if (sum(up) + sum(down) == 0L) {
    paste0(
      "No plan shown has a feeder adjustment: where the forecast is last ",
      "year's number, feeder courses moved less than ",
      scales::percent(line, accuracy = 1), " in ", preceding_label,
      " and no listed predecessor changed it.", included
    )
  } else {
    paste0(
      "Feeder courses in ", preceding_label, " ",
      paste(c(
        if (sum(up) > 0L) paste0("raise ", whose(sum(up), "plan"), " by ",
                                 count(sum(adjustment[up])), " registrations"),
        if (sum(down) > 0L) paste0("lower ", whose(sum(down), "plan"), " by ",
                                   count(-sum(adjustment[down])))
      ), collapse = " and "),
      ". ", rule, included
    )
  }
  list(
    n_raised = as.integer(sum(up)),
    n_lowered = as.integer(sum(down)),
    registrations = as.numeric(sum(adjustment[up | down])),
    sentence = sentence
  )
}


# Where past forecast error came from, as a table and one sentence, from the
# bundle's saved aftcasts.
projection_error_sources_summary <- function(backtests, model_config) {
  sources <- summarize_projection_error_sources(backtests, model_config)
  n_folds <- sum(sources$folds)
  share <- function(id) {
    value <- sources$share_of_error[sources$source == id]
    if (length(value) == 1L && is.finite(value)) scales::percent(value, accuracy = 1) else "none"
  }
  room_wape <- sources$wape[sources$source == "seats_held_room"]
  sentence <- if (n_folds == 0L) {
    "No past forecasts are saved for this target, so where error comes from cannot be shown."
  } else {
    paste0(
      "Across ", format(n_folds, big.mark = ","), " past forecasts, ",
      share("seats_changed"), " of the error came from terms whose seats ",
      "changed, ", share("data_missing"), " from terms with seat or first-day ",
      "data missing, ", share("seats_held_full"), " from near-full courses ",
      "whose seats held, and ", share("seats_held_room"), " from courses with ",
      "room whose seats held", if (length(room_wape) == 1L && is.finite(room_wape)) {
        paste0(" (", scales::percent(room_wape, accuracy = 0.1), " off on average)")
      } else "",
      ". Only that last group tests the forecast of demand itself; the rest ",
      "is the schedule, the data, or demand a full course could not show."
    )
  }
  list(table = sources, n_folds = as.integer(n_folds), sentence = sentence)
}


# How often the range held on past forecasts, by whether their seats held,
# as a table and one sentence, from the bundle's saved aftcasts (ISSUES.md
# M35). The range assumes steady seats and the page says so.
projection_range_coverage_summary <- function(backtests, model_config) {
  coverage <- summarize_projection_range_coverage(backtests, model_config)
  change <- scales::percent(
    as.numeric(projection_option(model_config, "seat_consistency_change")), accuracy = 1
  )
  steady <- coverage[coverage$seats == "steady", , drop = FALSE]
  moved <- coverage[coverage$seats == "moved", , drop = FALSE]
  above <- sum(coverage$actual_above)
  below <- sum(coverage$actual_below)
  held <- function(row) paste0(
    format(row$covered, big.mark = ","), " of ", format(row$folds, big.mark = ",")
  )
  sentence <- if (steady$folds + moved$folds == 0L) {
    paste(
      "The range assumes seats like last year's. No past forecast has an",
      "earlier one to build a range from, so how often it held cannot be shown",
      "yet."
    )
  } else {
    paste0(
      "The range assumes seats like last year's. Rebuilt for each past ",
      "forecast from the course's earlier ones only, it held ", held(steady),
      " times when seats stayed within ", change, " of the year before, and ",
      held(moved), " when they moved",
      if (above + below > 0L) paste0(
        ". Of its ", format(above + below, big.mark = ","),
        if (above + below == 1L) " miss, " else " misses, ",
        format(max(above, below), big.mark = ","), " had registrations ",
        if (above >= below) "above" else "below", " it"
      ) else "",
      "."
    )
  }
  list(table = coverage, sentence = sentence)
}


# Beside a row's range: when the draft schedule moves the seats from last
# year's same term by the seat-consistency change or more, the range, which
# assumes steady seats, says so (ISSUES.md M35). NA otherwise, including when
# no draft is in the data.
projection_range_seat_notes <- function(projections, recent_history, model_config) {
  change <- as.numeric(projection_option(model_config, "seat_consistency_change"))
  projection_require_columns(
    projections,
    c("market_id", "subject_course", "target_term", "target_schedule_available",
      "scheduled_capacity"),
    "projection_range_seat_notes()"
  )
  projection_require_columns(
    recent_history,
    c("market_id", "subject_course", "projection_target_term", "recency_rank",
      "scheduled_capacity", "history_term_label"),
    "projection_range_seat_notes() history"
  )
  last <- recent_history %>%
    dplyr::filter(recency_rank == 1L) %>%
    dplyr::transmute(
      market_id, subject_course, target_term = projection_target_term,
      last_capacity = scheduled_capacity, last_label = history_term_label
    )
  projections %>%
    dplyr::select(
      market_id, subject_course, target_term, target_schedule_available,
      scheduled_capacity
    ) %>%
    dplyr::left_join(
      last, by = c("market_id", "subject_course", "target_term"),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(
      seat_change = dplyr::if_else(
        target_schedule_available %in% TRUE & is.finite(last_capacity) &
          last_capacity > 0 & is.finite(scheduled_capacity),
        scheduled_capacity / last_capacity - 1, NA_real_
      ),
      note = dplyr::if_else(
        is.finite(seat_change) & abs(seat_change) >= change,
        sprintf(
          "Draft seats %+.0f%% on %s: the range assumes steady seats",
          100 * seat_change, last_label
        ),
        NA_character_
      )
    ) %>%
    dplyr::pull(note)
}


# The published plan beside the target term's schedule as it stands -- a
# draft until registration settles -- course by course. Arithmetic over saved
# rows: the bundle captured the schedule when it was built, and a changed
# draft rebuilds the bundle on the next refresh. Planned registrations carry
# the deliberate margin, the feeder adjustment and any pressure bump, so the
# comparison separates a
# draft short of the students expected on day one from one short only of the
# margin.
# A date as the page writes it: "October 26, 2026", no leading zero.
projection_date_label <- function(date) {
  # A build time is dated where it was written, not in UTC.
  date <- if (inherits(date, "POSIXt")) as.Date(format(date, "%Y-%m-%d")) else as.Date(date)
  dplyr::if_else(
    is.na(date), NA_character_,
    paste0(format(date, "%B "), as.integer(format(date, "%d")), format(date, ", %Y"))
  )
}


build_enrollment_projection_draft_comparison <- function(view) {
  projections <- view$projections
  projection_require_columns(
    projections,
    c("subject_course", "department", "market_id", "projected_classlist_total",
      "planned_registrations", "pressure_bump", "plan_feeder_adjustment",
      "projected_first_day_equivalent",
      "recommended_sections", "additional_sections", "reference_section_size",
      "scheduled_sections", "scheduled_capacity", "target_schedule_available",
      "target_registration_observed", "target_registered_now", "accuracy",
      "accuracy_value", "seat_consistency", "seat_consistency_value"),
    "build_enrollment_projection_draft_comparison()"
  )
  as_of <- view$meta$target_schedule_as_of
  count <- function(x) format(round(x), big.mark = ",", trim = TRUE)
  sections_note <- function(n) dplyr::if_else(
    dplyr::coalesce(n, 0L) > 0L,
    paste0(" (", n, " section", dplyr::if_else(n == 1L, "", "s"), ")"),
    ""
  )
  # CAMPUS_ROLLUP: the draft is shown per course across the pooled market, with
  # each campus's sections listed beside it from the saved delivery components.
  campus_sections <- view$delivery_components %>%
    dplyr::group_by(market_id, subject_course, campus) %>%
    dplyr::summarise(sections = sum(scheduled_sections), .groups = "drop") %>%
    dplyr::arrange(subject_course, campus) %>%
    dplyr::group_by(market_id, subject_course) %>%
    dplyr::summarise(
      campus_sections = paste(campus, sections, collapse = " \u00b7 "),
      .groups = "drop"
    )

  table <- projections %>%
    dplyr::filter(is.finite(projected_classlist_total)) %>%
    dplyr::left_join(campus_sections, by = c("market_id", "subject_course")) %>%
    dplyr::transmute(
      course = subject_course,
      department,
      in_draft = target_schedule_available %in% TRUE,
      draft_sections = dplyr::if_else(in_draft, as.integer(scheduled_sections), NA_integer_),
      draft_seats = dplyr::if_else(in_draft, as.numeric(scheduled_capacity), NA_real_),
      campus_sections,
      expected_first_day = projected_first_day_equivalent,
      planned_registrations,
      pressure_bump,
      plan_feeder_adjustment,
      plan_sections = recommended_sections,
      # Negative where the draft is short of the plan.
      draft_vs_plan = dplyr::if_else(in_draft, scheduled_capacity - planned_registrations, NA_real_),
      sections_to_add = dplyr::if_else(in_draft, additional_sections, NA_integer_),
      # Each shortfall carries its own sections, at the plan's section size:
      # "short by 10; the plan needs 2 more sections" read as 2 sections for 10
      # students, when the 2 were for the larger gap to the plan.
      day_one_sections = projection_sections_for_demand(
        expected_first_day - draft_seats, reference_section_size
      ),
      spare_line = pmax(10, dplyr::coalesce(reference_section_size, 0)),
      registered_now = dplyr::if_else(
        target_registration_observed %in% TRUE, as.numeric(target_registered_now), NA_real_
      ),
      reliability = accuracy,
      reliability_value = accuracy_value,
      seat_consistency,
      seat_consistency_value,
      status = dplyr::case_when(
        !in_draft ~ "not_in_draft",
        is.finite(expected_first_day) & draft_seats < expected_first_day ~ "short_day_one",
        draft_vs_plan < 0 ~ "short_plan",
        draft_vs_plan > spare_line ~ "spare",
        TRUE ~ "covers"
      ),
      verdict = dplyr::case_when(
        status == "not_in_draft" ~ "Not in the draft schedule",
        status == "short_day_one" ~ paste0(
          "Short of day-one seats by ", count(expected_first_day - draft_seats),
          sections_note(day_one_sections),
          # A falling feeder can put the plan below the first day.
          dplyr::if_else(
            draft_vs_plan < 0,
            paste0("; ", count(-draft_vs_plan), " short of the plan",
                   sections_note(sections_to_add)),
            ""
          )
        ),
        status == "short_plan" ~ paste0(
          "Covers day one; ", count(-draft_vs_plan), " short of the plan",
          sections_note(sections_to_add)
        ),
        status == "spare" ~ paste0(count(draft_vs_plan), " seats beyond the plan"),
        TRUE ~ dplyr::if_else(
          draft_vs_plan > 0, paste0("Covers the plan, ", count(draft_vs_plan), " to spare"),
          "Covers the plan"
        )
      )
    ) %>%
    dplyr::select(
      course, department, verdict, draft_sections, draft_seats,
      expected_first_day, planned_registrations, plan_sections, draft_vs_plan,
      registered_now, reliability, reliability_value, seat_consistency,
      seat_consistency_value,
      in_draft, campus_sections, pressure_bump, plan_feeder_adjustment,
      sections_to_add, status
    ) %>%
    dplyr::arrange(
      factor(status, levels = c("short_day_one", "short_plan", "not_in_draft", "covers", "spare")),
      draft_vs_plan
    )

  in_draft <- table$in_draft
  n <- function(id) sum(table$status == id)
  verb <- function(k, one, many) if (k == 1L) one else many
  gap_sum <- function(id, x) sum(x[table$status == id], na.rm = TRUE)
  available <- any(in_draft)
  sentence <- if (!available) {
    paste0(
      "No schedule for ", view$meta$target_term_label, " is in the data yet. ",
      "It appears here after a refresh pulls the target term's DESR from ",
      "MyReports, and the bundle rebuilds with it."
    )
  } else {
    paste0(
      "The draft schedule", if (!is.na(as_of)) paste0(
        " (pulled ", projection_date_label(as_of), ")"
      ) else "",
      " has ", count(sum(table$draft_seats, na.rm = TRUE)), " seats in ",
      sum(in_draft), " of the ", nrow(table), " courses shown, against ",
      count(sum(table$planned_registrations[in_draft])), " planned registrations. ",
      n("short_day_one"), " course", if (n("short_day_one") == 1L) " is" else "s are",
      " short of the students expected on day one",
      if (n("short_day_one") > 0L) paste0(
        " (by ", count(gap_sum("short_day_one", table$expected_first_day - table$draft_seats)), " seats)"
      ) else "", "; ", n("short_plan"), verb(n("short_plan"), " covers", " cover"),
      " day one but not the plan; ", n("covers"), verb(n("covers"), " covers", " cover"),
      " the plan; ", n("spare"), verb(n("spare"), " has", " have"),
      " more than a section to spare",
      if (n("not_in_draft") > 0L) paste0(
        ". ", n("not_in_draft"), " monitored course",
        if (n("not_in_draft") == 1L) " is" else "s are", " not in the draft"
      ) else "",
      "."
    )
  }
  list(
    available = available,
    as_of = as_of,
    table = table,
    counts = table %>% dplyr::count(status),
    sentence = sentence
  )
}


# The latest `n_terms` same-season terms in the view, oldest first, and for
# each course its first-day enrollment and scheduled sections in each: the
# at-a-glance history the summary table shows. First-day enrollment is NA where
# the class lists carry no status dates or a session had not begun when they
# were pulled, and both are NA in a term the course
# was not offered; a reader-facing surface shows either as an em dash, never as
# zero or as another lifecycle count.
build_enrollment_projection_history_summary <- function(
    projections, history, n_terms = 4L) {
  n_terms <- as.integer(n_terms)
  if (length(n_terms) != 1L || is.na(n_terms) || n_terms < 1L) {
    stop(
      "[enrollment-projection-view.R] Summary history terms must be positive.",
      call. = FALSE
    )
  }
  required <- c(
    "subject_course", "history_term", "history_term_label",
    "actual_first_day", "scheduled_sections"
  )
  missing <- setdiff(required, names(history))
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projection-view.R] Summary history needs column(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }

  # CAMPUS_ROLLUP: subject_course is unique inside the bundle's explicitly named
  # pooled planning market (currently ABQ + EA); campus components were already
  # reconciled into that market before publication and must stay combined here.
  courses <- unique(as.character(projections$subject_course))
  terms <- history %>%
    dplyr::distinct(term = history_term, term_label = history_term_label) %>%
    dplyr::arrange(dplyr::desc(term)) %>%
    dplyr::slice_head(n = n_terms) %>%
    dplyr::arrange(term) %>%
    dplyr::mutate(abbr = vapply(term, abbr_term, character(1)))

  slot <- function(course, column) {
    rows <- history[history$subject_course == course, , drop = FALSE]
    as.numeric(rows[[column]][match(terms$term, rows$history_term)])
  }
  first_day <- lapply(courses, slot, column = "actual_first_day")
  sections <- lapply(courses, slot, column = "scheduled_sections")
  text <- vapply(seq_along(courses), function(i) {
    if (nrow(terms) == 0L) return(NA_character_)
    paste(paste0(
      terms$abbr, " ",
      ifelse(is.finite(first_day[[i]]),
             format(round(first_day[[i]]), big.mark = ",", trim = TRUE),
             "\u2014"),
      " first day / ",
      ifelse(is.finite(sections[[i]]), sections[[i]], "\u2014"),
      " sections"
    ), collapse = "; ")
  }, character(1))

  list(
    data = tibble::tibble(
      course = courses,
      recent_first_day = first_day,
      recent_sections = sections,
      recent_terms = text
    ),
    columns = terms
  )
}


build_enrollment_projection_method_guide <- function(
    method_ids = names(CEDAR_ENROLLMENT_PROJECTION_METHODS)) {
  method_ids <- unique(as.character(method_ids))
  unknown <- setdiff(method_ids, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
  if (length(unknown) > 0L) {
    stop(
      "[enrollment-projection-view.R] Unknown projection methods in guide: ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }

  guide <- CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE
  guide <- guide[guide$method_id %in% method_ids, , drop = FALSE]
  guide$method_label <- unname(
    CEDAR_ENROLLMENT_PROJECTION_METHODS[guide$method_id]
  )
  guide <- guide[order(match(guide$method_id, method_ids)), , drop = FALSE]

  families <- lapply(
    seq_len(nrow(CEDAR_ENROLLMENT_PROJECTION_METHOD_FAMILIES)),
    function(i) {
      family <- CEDAR_ENROLLMENT_PROJECTION_METHOD_FAMILIES[i, , drop = FALSE]
      methods <- guide[guide$family_id == family$family_id[[1]], , drop = FALSE]
      if (nrow(methods) == 0L) return(NULL)
      list(
        id = family$family_id[[1]],
        label = family$family_label[[1]],
        description = family$description[[1]],
        selection_note = family$selection_note[[1]],
        methods = tibble::as_tibble(methods)
      )
    }
  )
  families <- Filter(Negate(is.null), families)

  n_candidates <- nrow(guide)
  n_ideas <- length(unique(guide$concept_id))
  forecast_word <- if (n_candidates == 1L) "forecast" else "forecasts"

  list(
    n_candidates = n_candidates,
    n_ideas = n_ideas,
    summary = paste0(
      n_candidates, " ", forecast_word, ": ",
      paste(guide$method_label, collapse = ", and ")
    ),
    overview = paste(
      "Every course has one published forecast. Each candidate below is",
      "computed for every course and every past term."
    ),
    selection_process = paste(
      "Prior same-season is the default for every course. Another forecast",
      "replaces it only after beating it by a margin on earlier past forecasts",
      "the two share, and the rule is replayed at every past term with only",
      "the evidence available then, so the reliability shown is what that rule",
      "would actually have delivered."
    ),
    families = families
  )
}


build_enrollment_projection_view <- function(bundle, opt = list()) {
  validate_enrollment_projection_bundle(bundle)
  group_id <- as.character(opt$group_id %||% "all_saved")[[1]]
  group_courses <- enrollment_projection_group_courses(bundle, group_id)
  departments <- as.character(opt$departments %||% character(0))
  departments <- departments[!is.na(departments) & nzchar(departments)]
  courses <- as.character(opt$courses %||% character(0))
  courses <- courses[!is.na(courses) & nzchar(courses)]
  stability <- as.character(opt$stability %||% character(0))
  stability <- stability[!is.na(stability) & nzchar(stability)]
  depth <- as.character(opt$depth %||% character(0))
  depth <- depth[!is.na(depth) & nzchar(depth)]
  accuracy <- as.character(opt$accuracy %||% character(0))
  accuracy <- accuracy[!is.na(accuracy) & nzchar(accuracy)]
  attention_only <- isTRUE(opt$attention_only)
  projections <- bundle$projections %>%
    dplyr::filter(subject_course %in% .env$group_courses)
  if (length(departments) > 0L) {
    projections <- dplyr::filter(
      projections, department %in% .env$departments
    )
  }
  if (length(courses) > 0L) {
    projections <- dplyr::filter(
      projections, subject_course %in% .env$courses
    )
  }
  if (length(stability) > 0L) {
    projections <- dplyr::filter(projections, stability %in% .env$stability)
  }
  if (length(depth) > 0L) {
    projections <- dplyr::filter(projections, depth %in% .env$depth)
  }
  if (length(accuracy) > 0L) {
    projections <- dplyr::filter(projections, accuracy %in% .env$accuracy)
  }
  projections <- projections %>%
    dplyr::mutate(
      # Rows a chair should actually look at; the rest can be planned at last
      # term's level.
      campus_fill_flag = projection_campus_fill_flags(
        dplyr::pick(dplyr::everything()), bundle$recent_campus_history
      ),
      attention = adjusted_saturated_prior %in% TRUE |
        adjusted_regime_alarm %in% TRUE | accuracy == "Low" |
        !is.na(campus_fill_flag)
    )
  if (attention_only) {
    projections <- dplyr::filter(projections, attention)
  }
  projections <- projections %>%
    dplyr::arrange(department, subject_course)
  projections <- dplyr::bind_cols(
    projections,
    projection_miss_attribution(projections, bundle$backtests, bundle$model_config)
  )
  projections <- projections %>%
    dplyr::mutate(
      # Why this method is live: the default, or the challenger evidence that
      # displaced it. The accuracy figures themselves live on the axes.
      selection_evidence = dplyr::case_when(
        method_id == "none" ~ "No applicable method",
        is.finite(selection_common_n) ~ paste0(
          "Beat prior same-season on ", selection_common_n,
          " earlier shared aftcasts (",
          projection_preview_percent(selection_challenger_wape), " vs ",
          projection_preview_percent(selection_default_wape), ")"
        ),
        TRUE ~ "Default; no challenger beat it on earlier aftcasts"
      ),
      axis_explanation = projection_axis_explanation(
        stability, depth, accuracy, n_backtests, wape,
        history_terms = history_terms,
        history_cv = history_cv,
        history_median_yoy = history_median_yoy_change,
        term_type, selection_pct_error_sd,
        capacity_constrained_history,
        n_capacity_reached, n_capacity_unreached, method_role,
        methods_disagree
      ),
      axis_brief = projection_axis_brief(
        stability, depth, accuracy,
        capacity_constrained = capacity_constrained_history,
        methods_disagree = methods_disagree,
        regime_alarm = dplyr::coalesce(adjusted_regime_alarm, FALSE)
      ),
      regime_alarm = dplyr::coalesce(adjusted_regime_alarm, FALSE),
      reliability_reading = projection_reliability_reading(
        accuracy, miss_cause, bundle$model_config
      ),
      flags = projection_flags(dplyr::pick(dplyr::everything())),
      summary_sentence = projection_summary_sentence(
        dplyr::pick(dplyr::everything())
      ),
      # The range is in registrations, the unit sections are sized from.
      demand_range = dplyr::if_else(
        is.finite(projection_low) & is.finite(projection_high),
        paste0(
          format(round(projection_low), big.mark = ",", trim = TRUE),
          " to ",
          format(round(projection_high), big.mark = ",", trim = TRUE)
        ),
        NA_character_
      ),
      range_note = dplyr::if_else(
        is.na(demand_range), NA_character_,
        projection_range_seat_notes(
          dplyr::pick(dplyr::everything()), bundle$recent_history,
          bundle$model_config
        )
      )
    )
  # The term most plans start from names the Day-1 fill column; a course that
  # starts from another term says so in its own cell.
  spine_terms <- projections$spine_term[!is.na(projections$spine_term)]
  fill_header_term <- if (length(spine_terms) == 0L) {
    NULL
  } else {
    counts <- table(spine_terms)
    max(as.integer(names(counts)[counts == max(counts)]))  # a tie goes to the latest
  }
  projections <- dplyr::bind_cols(
    projections,
    projection_prior_fill(projections, fill_header_term),
    projection_axis_values(projections)
  )
  selected_keys <- projections %>%
    dplyr::select(market_id, subject_course, term_type, target_term)
  history <- bundle$recent_history %>%
    dplyr::semi_join(
      selected_keys,
      by = c(
        "market_id", "subject_course",
        "projection_target_term" = "target_term"
      )
    ) %>%
    dplyr::arrange(subject_course, recency_rank)
  candidates <- bundle$candidates %>%
    dplyr::semi_join(
      selected_keys,
      by = c("market_id", "subject_course", "target_term")
    ) %>%
    dplyr::arrange(subject_course, method_role, method_id)
  method_history <- if (nrow(bundle$backtests) == 0L) {
    bundle$backtests
  } else {
    bundle$backtests %>%
      dplyr::semi_join(
        selected_keys,
        by = c("market_id", "subject_course", "term_type")
      ) %>%
      dplyr::arrange(subject_course, target_term, method_id)
  }
  history_summary <- build_enrollment_projection_history_summary(
    projections, history, n_terms = 4L
  )
  method_guide <- build_enrollment_projection_method_guide(
    bundle$model_config$projection_methods %||%
      names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )

  table <- projections %>%
    dplyr::transmute(
      course = subject_course,
      department,
      planning_sections = recommended_sections,
      planned_registrations,
      pressure_bump,
      pressure_bump_sections,
      pressure_bump_note,
      plan_feeder_adjustment,
      plan_feeder_sections,
      plan_feeder_note,
      expected_first_day = projected_first_day_equivalent,
      demand_range,
      range_note,
      prior_fill,
      prior_fill_text,
      prior_fill_percent,
      prior_fill_level,
      prior_fill_note,
      prior_fill_term,
      flags,
      attention,
      projected_demand = projected_classlist_total,
      method = method_label,
      selection_evidence,
      summary_sentence,
      stability,
      stability_value,
      stability_reason,
      history_terms,
      history_cv,
      history_median_yoy_change,
      depth,
      depth_value,
      depth_reason,
      accuracy,
      accuracy_value,
      accuracy_reason,
      seat_consistency,
      seat_consistency_value,
      seat_consistency_reason,
      reliability_reading,
      axis_brief,
      axis_explanation,
      regime_alarm,
      why_uncertain
    ) %>%
    dplyr::left_join(history_summary$data, by = "course") %>%
    dplyr::select(
      # The decision first: sections to plan, how much of them the feeder
      # adjustment and the pressure bump added, the registrations they are
      # sized from with their range, first-day seats, last year's first-day
      # fill, the recent first days and sections, and plain-language flags.
      # The evidence axes follow; the method and its evidence are for the
      # course detail.
      course, department, planning_sections, planned_registrations, pressure_bump,
      pressure_bump_sections, pressure_bump_note, plan_feeder_adjustment,
      plan_feeder_sections, plan_feeder_note, projected_demand,
      demand_range, range_note, expected_first_day,
      prior_fill, prior_fill_text, prior_fill_percent, prior_fill_level,
      prior_fill_note, prior_fill_term,
      recent_first_day, recent_sections, recent_terms, flags,
      stability, stability_value, stability_reason,
      depth, depth_value, depth_reason,
      # Reliability (accuracy) carries seat consistency beneath it, so the two
      # read together; the flags say when a miss was the forecast's own.
      accuracy, accuracy_value, accuracy_reason,
      seat_consistency, seat_consistency_value, seat_consistency_reason,
      reliability_reading,
      method, selection_evidence,
      summary_sentence, attention,
      axis_brief, axis_explanation, regime_alarm, why_uncertain
    )

  list(
    meta = list(
      target_term = bundle$target_term,
      target_term_label = fmt_term(bundle$target_term),
      season_label = switch(
        get_term_type(bundle$target_term),
        spring = "Spring", summer = "Summer", fall = "Fall"
      ),
      as_of_term = bundle$as_of_term,
      as_of_term_label = fmt_term(bundle$as_of_term),
      history_start_term = bundle$model_config$history_start_term,
      history_start_term_label = fmt_term(bundle$model_config$history_start_term),
      built_at = bundle$built_at,
      model_version = bundle$model_version,
      model_provenance = bundle$model_provenance,
      market_id = bundle$scope_market_id,
      campuses = bundle$scope_campuses,
      group_id = group_id,
      n_rows = nrow(projections),
      n_attention = sum(projections$attention),
      pressure_bump = projection_pressure_bump_summary(
        projections, bundle$model_config$pressure_bump_share
      ),
      plan_feeder = projection_plan_feeder_summary(
        projections, bundle$model_config$plan_feeder_change,
        bundle$model_config$plan_feeder_seasons
      ),
      # Bundle-wide, not filtered: the evidence for where error comes from is
      # every past forecast the rule would have published.
      error_sources = projection_error_sources_summary(
        bundle$backtests, bundle$model_config
      ),
      range_coverage = projection_range_coverage_summary(
        bundle$backtests, bundle$model_config
      ),
      target_schedule_as_of = bundle$target_schedule_as_of,
      prior_fill_term_label = if (is.null(fill_header_term)) {
        NA_character_
      } else {
        fmt_term(fill_header_term)
      },
      miss_sentence = projection_miss_sentence(projections, bundle$model_config),
      summary_history_columns = history_summary$columns,
      bundle_path = attr(bundle, "bundle_path") %||% NA_character_
    ),
    projections = projections,
    table = table,
    delivery_components = bundle$delivery_components %>%
      dplyr::semi_join(
        dplyr::select(projections, market_id, subject_course),
        by = c("market_id", "subject_course")
      ),
    campus_history = bundle$recent_campus_history %>%
      dplyr::semi_join(
        dplyr::select(projections, market_id, subject_course),
        by = c("market_id", "subject_course")
      ),
    history = history,
    candidates = candidates,
    method_history = method_history,
    method_guide = method_guide
  )
}


enrollment_projection_filter_choices <- function(bundle, opt = list()) {
  scoped <- build_enrollment_projection_view(
    bundle,
    utils::modifyList(opt, list(
      courses = character(0), stability = character(0),
      depth = character(0), accuracy = character(0)
    ))
  )$projections
  list(
    groups = enrollment_projection_group_choices(),
    departments = sort(unique(stats::na.omit(scoped$department))),
    courses = sort(unique(stats::na.omit(scoped$subject_course))),
    stability = c("Stable", "Moderate", "Volatile", "Unrated"),
    depth = c("Deep", "Moderate", "Thin", "None"),
    accuracy = c("High", "Moderate", "Low", "Unrated")
  )
}


enrollment_projection_course_detail <- function(view, subject_course) {
  course <- as.character(subject_course %||% character(0))
  if (length(course) != 1L || is.na(course) || !nzchar(course)) return(NULL)
  current <- view$projections %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::slice_head(n = 1)
  if (nrow(current) == 0L) return(NULL)
  course_history <- view$history %>%
    dplyr::filter(subject_course == .env$course) %>%
    dplyr::arrange(recency_rank)
  list(
    current = current,
    plan_steps = projection_plan_steps(current),
    history = course_history,
    movement = build_enrollment_projection_movement_detail(course_history),
    candidates = view$candidates %>%
      dplyr::filter(subject_course == .env$course),
    method_history = if (nrow(view$method_history) == 0L) {
      view$method_history
    } else {
      view$method_history %>%
        dplyr::filter(subject_course == .env$course) %>%
        dplyr::arrange(target_term, method_id)
    }
  )
}


build_enrollment_projection_movement_detail <- function(history) {
  required <- c(
    "history_term", "history_term_label", "actual_classlist_total",
    "classlist_change", "scheduled_sections", "scheduled_capacity",
    "capacity_change", "capacity_usable", "capacity_reached", "source_term_label",
    "university_students", "university_student_change",
    "university_incoming_first_sem", "university_incoming_change",
    "market_students", "market_student_change", "source_outcomes_complete",
    "source_graded_students", "source_dfw_students", "source_dfw_rate",
    "source_dfw_next_term_repeaters", "source_dfw_repeater_share",
    "movement_context"
  )
  missing <- setdiff(required, names(history))
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projection-view.R] Movement diagnostic needs column(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }
  if (nrow(history) == 0L) {
    return(list(
      schedule_summary = "No comparable same-season history is available.",
      upstream_summary = "No upstream population comparison is available.",
      dfw_summary = "No prior-term DFW comparison is available.",
      caveat = paste(
        "These indicators are descriptive context. They do not establish",
        "that a schedule, population, or DFW change caused enrollment."
      ),
      data = tibble::tibble()
    ))
  }

  ordered <- history %>% dplyr::arrange(history_term)
  paired <- ordered %>%
    dplyr::filter(is.finite(classlist_change), is.finite(capacity_change))
  movement_correlation <- if (nrow(paired) >= 3L &&
                              stats::sd(paired$classlist_change) > 0 &&
                              stats::sd(paired$capacity_change) > 0) {
    stats::cor(paired$classlist_change, paired$capacity_change)
  } else {
    NA_real_
  }
  # A term counts only where first-day occupancy and capacity are both known;
  # capacity_reached is FALSE, not NA, for a term that cannot be judged.
  reached_n <- sum(ordered$capacity_reached %in% TRUE)
  usable_n <- sum(ordered$capacity_usable %in% TRUE)
  schedule_summary <- paste0(
    if (is.finite(movement_correlation)) {
      paste0(
        "Across ", nrow(paired), " comparable movements, enrollment and ",
        "scheduled-capacity changes had r = ",
        sprintf("%.2f", movement_correlation), ". "
      )
    } else {
      "There are too few comparable movements for a stable correlation. "
    },
    "First-day enrollment reached scheduled capacity (",
    scales::percent(CEDAR_FULL_FILL),
    " of seats or more) in ", reached_n, " of ",
    usable_n, " terms where first day and capacity are both known."
  )

  movement_row <- ordered %>%
    dplyr::filter(is.finite(classlist_change)) %>%
    dplyr::slice_max(abs(classlist_change), n = 1L, with_ties = FALSE)
  upstream_summary <- if (nrow(movement_row) == 0L) {
    "No prior same-season enrollment movement is available to compare."
  } else {
    paste0(
      "The largest observed move was ", movement_row$history_term_label[[1]],
      " (", projection_preview_percent(
        movement_row$classlist_change[[1]], signed = TRUE
      ), "). In the preceding ", movement_row$source_term_label[[1]],
      ", enrolled-student population changed ",
      projection_preview_percent(
        movement_row$university_student_change[[1]], signed = TRUE
      ), ", first-semester freshman population changed ",
      projection_preview_percent(
        movement_row$university_incoming_change[[1]], signed = TRUE
      ), ", and the projection market changed ",
      projection_preview_percent(
        movement_row$market_student_change[[1]], signed = TRUE
      ), "."
    )
  }

  dfw_summary <- if (nrow(movement_row) == 0L ||
                     !isTRUE(movement_row$source_outcomes_complete[[1]])) {
    paste(
      "Prior-term DFW is unavailable because that source term is not through",
      "the graded data edge."
    )
  } else {
    paste0(
      "For that move, ",
      projection_preview_integer(movement_row$source_dfw_students[[1]]),
      " students had a DFW in the course during the preceding term (",
      projection_preview_percent(movement_row$source_dfw_rate[[1]]), "). ",
      projection_preview_integer(
        movement_row$source_dfw_next_term_repeaters[[1]]
      ), " of them then enrolled in the course in ",
      movement_row$history_term_label[[1]], "—",
      projection_preview_percent(
        movement_row$source_dfw_repeater_share[[1]]
      ), " of that term's course enrollment."
    )
  }

  table <- ordered %>%
    dplyr::transmute(
      term = history_term_label,
      enrollment = round(actual_classlist_total),
      enrollment_change = classlist_change,
      sections = scheduled_sections,
      capacity = round(scheduled_capacity),
      capacity_change,
      source_term = source_term_label,
      university_students = round(university_students),
      university_change = university_student_change,
      incoming_first_sem = round(university_incoming_first_sem),
      incoming_change = university_incoming_change,
      market_students = round(market_students),
      market_change = market_student_change,
      prior_term_dfw = dplyr::if_else(
        source_outcomes_complete,
        paste0(
          projection_preview_integer(source_dfw_students), " / ",
          projection_preview_percent(source_dfw_rate)
        ),
        "Not graded"
      ),
      dfw_repeaters = dplyr::if_else(
        source_outcomes_complete,
        paste0(
          projection_preview_integer(source_dfw_next_term_repeaters), " / ",
          projection_preview_percent(source_dfw_repeater_share)
        ),
        "—"
      ),
      context = movement_context
    )

  list(
    schedule_summary = schedule_summary,
    upstream_summary = upstream_summary,
    dfw_summary = dfw_summary,
    caveat = paste(
      "These are upstream and post-hoc diagnostics, not causal attribution.",
      "Schedules may respond to anticipated demand, and DFW repeaters are",
      "observed after the following term begins."
    ),
    data = table
  )
}


build_enrollment_projection_method_history_plot <- function(
    method_history, selected_method_id = NULL) {
  required <- c(
    "subject_course", "term_type", "method_id", "method_label", "target_term",
    "applicable", "raw_projected_classlist_total", "actual_classlist_total",
    "actual_first_day", "actual_census", "actual_final_enrollment"
  )
  missing <- setdiff(required, names(method_history))
  if (length(missing) > 0L) {
    stop(
      "[enrollment-projection-view.R] Historical-method plot needs column(s): ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }
  if (nrow(method_history) == 0L) return(NULL)

  term_types <- unique(stats::na.omit(as.character(method_history$term_type)))
  if (length(term_types) != 1L) {
    stop(
      "[enrollment-projection-view.R] Historical-method plot must contain one term type.",
      call. = FALSE
    )
  }
  term_order <- method_history %>%
    dplyr::distinct(target_term) %>%
    dplyr::arrange(target_term) %>%
    dplyr::pull(target_term)
  term_labels <- stats::setNames(
    vapply(term_order, fmt_term, character(1)), as.character(term_order)
  )
  actuals <- method_history %>%
    dplyr::distinct(
      target_term, actual_classlist_total, actual_first_day, actual_census,
      actual_final_enrollment
    ) %>%
    dplyr::arrange(target_term)
  methods <- method_history %>%
    dplyr::filter(
      applicable, is.finite(raw_projected_classlist_total),
      method_id %in% names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
    ) %>%
    dplyr::arrange(target_term, method_id)

  plot <- plotly::plot_ly()
  actual_specs <- list(
    list(
      label = "Ever registered (model target)",
      column = "actual_classlist_total", color = unname(CEDAR_COLORS["green_dark"]),
      width = 4L, symbol = "circle"
    ),
    # Gaps where the class lists carry no status dates: an unknown first day
    # is drawn as missing, not as zero or as census.
    list(
      label = "First day (seats judged here)", column = "actual_first_day",
      color = unname(CEDAR_COLORS["amber"]), width = 3L, symbol = "triangle-up"
    ),
    list(
      label = "Census", column = "actual_census",
      color = unname(CEDAR_COLORS["blue"]), width = 3L, symbol = "diamond"
    ),
    list(
      label = "Final / last day", column = "actual_final_enrollment",
      color = unname(CEDAR_COLORS["neutral"]), width = 3L, symbol = "square"
    )
  )
  for (spec in actual_specs) {
    values <- actuals[[spec$column]]
    plot <- plotly::add_trace(
      plot,
      x = unname(term_labels[as.character(actuals$target_term)]),
      y = values,
      type = "scatter", mode = "lines+markers", name = spec$label,
      legendgroup = "actual",
      line = list(color = spec$color, width = spec$width),
      marker = list(color = spec$color, size = 8, symbol = spec$symbol),
      text = paste0(
        spec$label, "<br>",
        unname(term_labels[as.character(actuals$target_term)]),
        "<br>Enrollment: ", round(values)
      ),
      hovertemplate = "%{text}<extra></extra>"
    )
  }

  method_ids <- intersect(
    names(CEDAR_ENROLLMENT_PROJECTION_METHODS), unique(methods$method_id)
  )
  method_colors <- cedar_plotly_palette(
    method_ids, label_order = names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )
  selected_method_id <- as.character(selected_method_id %||% NA_character_)[[1]]
  for (method in method_ids) {
    values <- methods %>% dplyr::filter(method_id == .env$method)
    selected <- identical(method, selected_method_id)
    label <- unique(values$method_label)[[1]]
    plot <- plotly::add_trace(
      plot,
      x = unname(term_labels[as.character(values$target_term)]),
      y = values$raw_projected_classlist_total,
      type = "scatter", mode = "lines+markers",
      name = paste0(label, if (selected) " (selected)" else ""),
      legendgroup = "methods",
      line = list(
        color = unname(method_colors[[method]]),
        width = if (selected) 3L else 1.5,
        dash = if (selected) "dash" else "dot"
      ),
      marker = list(
        color = unname(method_colors[[method]]),
        size = if (selected) 7 else 5
      ),
      opacity = if (selected) 1 else 0.78,
      text = paste0(
        label, if (selected) " (selected)" else "", "<br>",
        unname(term_labels[as.character(values$target_term)]),
        "<br>Raw aftcast: ", round(values$raw_projected_classlist_total)
      ),
      hovertemplate = "%{text}<extra></extra>"
    )
  }

  season <- switch(
    term_types[[1]], spring = "Spring", summer = "Summer", fall = "Fall",
    term_types[[1]]
  )
  plot %>%
    plotly::layout(
      xaxis = list(
        title = "",
        categoryorder = "array",
        categoryarray = unname(term_labels),
        tickangle = -30
      ),
      yaxis = list(title = "Students", rangemode = "tozero"),
      legend = list(orientation = "h", x = 0, y = -0.28),
      margin = list(t = 20, r = 20, b = 125, l = 65),
      hovermode = "x unified",
      annotations = list(list(
        text = paste0(season, " terms only"),
        showarrow = FALSE, xref = "paper", yref = "paper",
        x = 1, y = 1.06, xanchor = "right",
        font = list(size = 12, color = unname(CEDAR_COLORS["text"]))
      ))
    ) %>%
    plotly::config(displaylogo = FALSE)
}


projection_preview_integer <- function(x) {
  ifelse(
    is.finite(x),
    format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE),
    "--"
  )
}


projection_preview_percent <- function(x, signed = FALSE) {
  output <- rep("--", length(x))
  keep <- is.finite(x)
  format_string <- if (isTRUE(signed)) "%+.1f%%" else "%.1f%%"
  output[keep] <- sprintf(format_string, 100 * x[keep])
  output
}


projection_preview_markdown_table <- function(data, right_align = character()) {
  if (nrow(data) == 0L) return(character(0))
  cells <- lapply(data, function(x) {
    value <- as.character(x)
    value[is.na(value) | !nzchar(value)] <- "--"
    gsub("|", "\\|", value, fixed = TRUE)
  })
  headers <- names(data)
  widths <- vapply(seq_along(headers), function(i) {
    max(nchar(c(headers[[i]], cells[[i]])), na.rm = TRUE)
  }, integer(1))
  row_line <- function(values) {
    padded <- vapply(seq_along(values), function(i) {
      if (headers[[i]] %in% right_align) {
        sprintf(paste0("%", widths[[i]], "s"), values[[i]])
      } else {
        sprintf(paste0("%-", widths[[i]], "s"), values[[i]])
      }
    }, character(1))
    paste0("| ", paste(padded, collapse = " | "), " |")
  }
  separator <- vapply(seq_along(headers), function(i) {
    width <- max(3L, widths[[i]])
    if (headers[[i]] %in% right_align) {
      paste0(paste(rep("-", width - 1L), collapse = ""), ":")
    } else {
      paste(rep("-", width), collapse = "")
    }
  }, character(1))
  rows <- if (nrow(data) == 0L) character(0) else
    vapply(seq_len(nrow(data)), function(i) {
      row_line(vapply(cells, `[[`, character(1), i))
    }, character(1))
  c(row_line(headers), row_line(separator), rows)
}


format_enrollment_projection_preview <- function(bundle, courses = NULL) {
  validate_enrollment_projection_bundle(bundle)
  selected_courses <- if (is.null(courses)) {
    bundle$projections$subject_course
  } else {
    unique(as.character(courses))
  }
  projections <- bundle$projections %>%
    dplyr::filter(subject_course %in% .env$selected_courses) %>%
    dplyr::arrange(subject_course)
  history <- bundle$recent_history %>%
    dplyr::filter(subject_course %in% .env$selected_courses) %>%
    dplyr::arrange(subject_course, recency_rank)

  current_table <- projections %>%
    dplyr::transmute(
      Course = subject_course,
      Target = target_term_label,
      `Class-list demand` = projection_preview_integer(projected_classlist_total),
      `Feeder adjustment` = dplyr::if_else(
        plan_feeder_adjustment != 0, sprintf("%+.0f", plan_feeder_adjustment), "--"
      ),
      `Pressure bump` = dplyr::if_else(
        pressure_bump > 0, paste0("+", projection_preview_integer(pressure_bump)), "--"
      ),
      Planned = projection_preview_integer(planned_registrations),
      `Planned sections` = projection_preview_integer(recommended_sections),
      `First-day seats` = projection_preview_integer(projected_first_day_equivalent),
      `Day-1 fill, last year` = dplyr::coalesce(
        projection_prior_fill(dplyr::pick(dplyr::everything()))$prior_fill_text, "--"
      ),
      Method = method_label,
      Aftcasts = projection_preview_integer(n_backtests),
      `Accuracy terms` = backtest_term_range,
      `Raw WAPE` = projection_preview_percent(wape),
      `Capacity audit` = dplyr::case_when(
        dplyr::coalesce(n_backtests, 0L) == 0L ~ "--",
        dplyr::coalesce(n_capacity_censored_misses, 0L) == 0L ~
          "No bounded errors",
        n_capacity_censored_misses == n_backtests ~ paste0(
          "Capacity-bounded (", n_capacity_censored_misses, "/",
          n_backtests, ")"
        ),
        TRUE ~ paste0(
          n_capacity_censored_misses, "/", n_backtests,
          " capacity-bounded; minimum ",
          projection_preview_percent(capacity_censored_wape)
        )
      ),
      `Uncensored WAPE` = projection_preview_percent(uncensored_wape),
      Bias = projection_preview_percent(weighted_bias, signed = TRUE),
      Stability = stability,
      Depth = depth,
      Reliability = accuracy,
      `Seat consistency` = seat_consistency,
      `Why uncertain` = dplyr::if_else(
        accuracy %in% c("Unrated", "Low") | stability == "Volatile",
        why_uncertain, "--"
      ),
      Spine = projection_preview_integer(observed_baseline),
      Adjusted = projection_preview_integer(adjusted_projection),
      Floor = dplyr::case_when(
        adjusted_saturated_prior %in% TRUE & adjusted_floor_uplift > 0 ~
          paste0("Saturated; +", round(adjusted_floor_uplift)),
        adjusted_saturated_prior %in% TRUE ~ "Saturated; spine is a floor",
        adjusted_saturated_prior %in% FALSE ~ "Not saturated",
        TRUE ~ "Unknown"
      ),
      `Fall deltas` = dplyr::if_else(
        adjusted_applicable %in% TRUE,
        paste0(
          "repeat ", sprintf("%+.0f", adjusted_delta_repeat),
          dplyr::if_else(
            is.na(adjusted_sequence_courses), "",
            paste0(", sequence ", sprintf("%+.0f", adjusted_delta_sequence))
          ),
          ", feeder ", sprintf("%+.0f", adjusted_delta_feeder)
        ),
        "--"
      ),
      `Regime check` = dplyr::if_else(
        adjusted_regime_alarm %in% TRUE, "Review", "--"
      ),
      `Feeder adjustment basis` = plan_feeder_note,
      `Pressure bump basis` = pressure_bump_note,
      Recommendation = recommendation
    )
  history_table <- history %>%
    dplyr::transmute(
      Course = subject_course,
      Term = history_term_label,
      `Aftcast method` = dplyr::coalesce(aftcast_method_label, "--"),
      Aftcast = projection_preview_integer(aftcast_classlist_total),
      `Raw error` = projection_preview_percent(aftcast_pct_error, signed = TRUE),
      `Error assessment` = dplyr::case_when(
        !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "--",
        dplyr::coalesce(aftcast_capacity_censored, FALSE) ~
          "Capacity-bounded",
        TRUE ~ "Observed"
      ),
      `Ever registered` = projection_preview_integer(actual_classlist_total),
      `First day` = projection_preview_integer(actual_first_day),
      Census = projection_preview_integer(actual_census),
      `Final / last day` = projection_preview_integer(actual_final_enrollment),
      Sections = projection_preview_integer(scheduled_sections),
      Capacity = projection_preview_integer(scheduled_capacity),
      `First-day fill` = projection_preview_percent(first_day_fill),
      `Capacity status` = dplyr::case_when(
        !is.finite(actual_first_day) ~ "First day unknown",
        !capacity_usable ~ "No capacity",
        capacity_reached ~ "Reached",
        TRUE ~ "Not reached"
      ),
      `Potential explanation` = potential_miss_explanation
    )

  overrides <- bundle$model_config$course_history_start_terms
  override_note <- if (length(overrides) == 0L) {
    "None"
  } else {
    paste(
      paste0(names(overrides), " from ",
             vapply(overrides, fmt_term, character(1))),
      collapse = "; "
    )
  }
  context <- paste0(
    "Target: ", fmt_term(bundle$target_term),
    " | Data through: ", fmt_term(bundle$as_of_term),
    " | Market: ", bundle$scope_market_id,
    " | Model: ", bundle$model_version,
    " | General history: ", fmt_term(bundle$model_config$history_start_term),
    " | Overrides: ", override_note
  )
  current_lines <- projection_preview_markdown_table(
    current_table,
    right_align = c(
      "Class-list demand", "Pressure bump", "Planned", "Planned sections",
      "First-day seats", "Aftcasts", "Raw WAPE",
      "Uncensored WAPE", "Bias", "Spine", "Adjusted"
    )
  )
  history_lines <- projection_preview_markdown_table(
    history_table,
    right_align = c(
      "Ever registered", "First day", "Census", "Final / last day",
      "Sections", "Capacity", "First-day fill",
      "Aftcast", "Raw error"
    )
  )
  error_sources <- projection_error_sources_summary(
    bundle$backtests, bundle$model_config
  )
  error_lines <- projection_preview_markdown_table(
    error_sources$table %>%
      dplyr::transmute(
        Source = label,
        `Past forecasts` = projection_preview_integer(folds),
        `Average error` = projection_preview_percent(wape),
        `Share of error` = projection_preview_percent(share_of_error)
      ),
    right_align = c("Past forecasts", "Average error", "Share of error")
  )

  c(
    "# Enrollment Projection Preview",
    context,
    "",
    "## Current projections",
    if (length(current_lines) == 0L) "_No matching projection rows._" else
      current_lines,
    "",
    "## Recent same-season evidence",
    if (length(history_lines) == 0L) "_No comparable history rows._" else
      history_lines,
    "",
    "## Where past forecast error came from (whole bundle)",
    error_sources$sentence,
    "",
    error_lines,
    "",
    paste(
      "Historical predictions are leakage-safe aftcasts of the method the",
      "rolling selection rule would have published that term; they are not",
      "claims about a forecast published at that time."
    ),
    paste(
      "Capacity-bounded means overprojection cannot be measured because",
      paste0(
        "first-day enrollment reached scheduled capacity (",
        scales::percent(CEDAR_FULL_FILL),
        " of seats or more); it is not a claim of zero error."
      )
    )
  )
}


print_enrollment_projection_preview <- function(bundle, courses = NULL) {
  output <- format_enrollment_projection_preview(bundle, courses = courses)
  cat(output, sep = "\n")
  invisible(output)
}
