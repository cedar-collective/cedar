# Course context that is not itself a forecast: which courses are under
# capacity pressure and so get projected, how steady a course's own history
# is, its capacity, and how its seats and enrollment moved together.

empty_projection_pressure_screen <- function() {
  tibble::tibble(
    market_id = character(), college = character(), department = character(),
    subject_course = character(), term_type = character(), target_term = integer(),
    scheduled_sections = integer(), scheduled_capacity = numeric(),
    n_delivery_components = integer(), n_campuses = integer(),
    target_classlist_total_to_date = numeric(), target_registered_now = numeric(),
    target_early_drops_to_date = numeric(), target_late_drops_to_date = numeric(),
    target_other_status_to_date = numeric(),
    target_registration_observed = logical(), target_available_seats = numeric(),
    target_classlist_fill = numeric(), target_active_fill = numeric(),
    target_capacity_reached = logical(),
    historical_classlist_total = numeric(), quick_trend_projection = numeric(),
    first_day_retention_rate = numeric(), quick_first_day_equivalent = numeric(),
    recent_high_fill_terms = integer(), recent_capacity_terms = integer(),
    is_forced = logical(),
    target_schedule_available = logical(),
    pressure_capacity_shortfall = logical(), pressure_chronic_fill = logical(),
    pressure_growth = logical(), included = logical(),
    inclusion_reason = character()
  )
}


build_projection_pressure_screen <- function(enrollment_history, section_history,
                                             target_term,
                                             target_registration_snapshot = NULL,
                                             target_market_id = NULL,
                                             force_courses = NULL,
                                             scope_courses = NULL,
                                             opt = list()) {
  target_term <- as.integer(target_term)
  target_type <- get_term_type(target_term)
  force_courses <- unique(as.character(force_courses %||% character(0)))
  scope_courses <- unique(as.character(scope_courses %||% character(0)))
  min_gap <- as.numeric(projection_option(opt, "pressure_min_seat_gap"))
  fill_threshold <- as.numeric(projection_option(opt, "pressure_fill_threshold"))
  capacity_threshold <- as.numeric(
    projection_option(opt, "registration_capacity_threshold")
  )
  chronic_terms <- as.integer(projection_option(opt, "pressure_chronic_terms"))
  history_window <- as.integer(projection_option(opt, "pressure_history_window"))

  target_sections <- section_history %>%
    dplyr::filter(term == target_term)
  if (length(scope_courses) > 0) {
    target_sections <- dplyr::filter(
      target_sections, subject_course %in% .env$scope_courses
    )
  }
  if (is.null(target_registration_snapshot)) {
    target_registration_snapshot <- enrollment_history[0, , drop = FALSE]
  }

  historical_keys <- enrollment_history %>%
    dplyr::filter(term < target_term, term_type == target_type) %>%
    {
      include <- unique(c(scope_courses, force_courses))
      if (length(include) > 0) {
        dplyr::filter(., subject_course %in% .env$include)
      } else {
        .
      }
    } %>%
    # CAMPUS_ROLLUP: market_id explicitly names the ABQ+EA planning rollup.
    dplyr::group_by(market_id, subject_course) %>%
    dplyr::slice_max(term, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(
      market_id, subject_course,
      term_type = target_type
    )

  target_keys <- target_sections %>%
    dplyr::transmute(market_id, subject_course, term_type)
  market_ids <- unique(c(
    as.character(target_market_id %||% character(0)),
    as.character(enrollment_history$market_id),
    as.character(section_history$market_id)
  ))
  market_ids <- market_ids[!is.na(market_ids) & nzchar(market_ids)]
  scope_keys <- if (length(scope_courses) > 0 && length(market_ids) > 0) {
    tidyr::expand_grid(
      market_id = market_ids,
      subject_course = scope_courses
    ) %>%
      dplyr::mutate(term_type = target_type)
  } else {
    target_keys[0, , drop = FALSE]
  }
  universe <- dplyr::bind_rows(scope_keys, target_keys, historical_keys) %>%
    dplyr::distinct()
  if (nrow(universe) == 0) return(empty_projection_pressure_screen())

  rows <- lapply(seq_len(nrow(universe)), function(i) {
    row <- universe[i, , drop = FALSE]
    hist <- projection_history_for_row(
      enrollment_history, row, before_term = target_term
    ) %>% dplyr::slice_tail(n = history_window)
    sec_hist <- projection_section_history_for_row(
      section_history, row, before_term = target_term
    ) %>% dplyr::slice_tail(n = history_window)
    paired <- hist %>%
      dplyr::left_join(
        dplyr::select(sec_hist, term, scheduled_capacity),
        by = "term"
      )
    paired <- dplyr::bind_cols(
      paired,
      projection_capacity_metrics(
        paired$first_day_enrl,
        paired$scheduled_capacity,
        reached_threshold = fill_threshold
      )
    ) %>%
      dplyr::mutate(fill_rate = capacity_fill)

    target <- target_sections %>%
      dplyr::filter(
        market_id == row$market_id,
        subject_course == row$subject_course
      ) %>%
      dplyr::slice_head(n = 1)

    target_capacity <- if (nrow(target) == 0) 0 else target$scheduled_capacity[[1]]
    registration <- target_registration_snapshot %>%
      dplyr::filter(
        market_id == row$market_id,
        subject_course == row$subject_course,
        term == target_term
      ) %>%
      dplyr::slice_head(n = 1)
    target_classlist_total <- if (nrow(registration) == 0) NA_real_ else
      registration$classlist_total[[1]]
    target_registered <- if (nrow(registration) == 0) NA_real_ else
      registration$registered[[1]]
    target_sections_n <- if (nrow(target) == 0) 0L else target$scheduled_sections[[1]]
    target_components_n <- if (nrow(target) == 0) 0L else
      target$n_delivery_components[[1]]
    target_campuses_n <- if (nrow(target) == 0) 0L else target$n_campuses[[1]]
    # A target term still filling has no first day yet, so the students registered
    # right now are its occupancy. Ever-registered to date is kept beside it
    # as a demand count, not as the capacity test.
    target_classlist_status <- projection_capacity_metrics(
      target_classlist_total,
      target_capacity,
      reached_threshold = capacity_threshold
    )
    target_active_status <- projection_capacity_metrics(
      target_registered,
      target_capacity,
      reached_threshold = capacity_threshold
    )
    college <- if (nrow(target) == 0) NA_character_ else target$college[[1]]
    department <- if (nrow(target) == 0) {
      latest <- section_history %>%
        dplyr::filter(
          market_id == row$market_id,
          subject_course == row$subject_course,
          term < target_term
        ) %>%
        dplyr::slice_max(term, n = 1, with_ties = FALSE)
      if (nrow(latest) == 0) {
        NA_character_
      } else {
        college <- latest$college[[1]]
        latest$department[[1]]
      }
    } else {
      target$department[[1]]
    }

    baseline <- if (nrow(hist) == 0) NA_real_ else
      stats::median(hist$classlist_total)
    trend <- projection_linear_estimate(hist$classlist_total)
    retention <- projection_first_day_retention_for_row(
      enrollment_history, row, target_term, opt
    )$first_day_retention_rate[[1]]
    baseline_first_day_equivalent <- baseline * retention
    trend_first_day_equivalent <- trend * retention
    high_fill_terms <- sum(paired$fill_rate >= fill_threshold, na.rm = TRUE)
    recent_capacity_terms <- sum(is.finite(paired$fill_rate))
    is_forced <- row$subject_course %in% force_courses
    target_capacity_usable <- is.finite(target_capacity) && target_capacity > 0
    capacity_shortfall <- is.finite(baseline) &&
      target_capacity_usable &&
      projection_seat_gap_reached(baseline - target_capacity, min_gap)
    chronic_fill <- high_fill_terms >= chronic_terms
    growth_pressure <- is.finite(trend) &&
      target_capacity_usable &&
      projection_seat_gap_reached(trend - target_capacity, min_gap)
    missing_schedule <- is_forced && !target_capacity_usable
    included <- is_forced || capacity_shortfall || chronic_fill || growth_pressure

    fill_evidence <- paste0(
      high_fill_terms, " of ", recent_capacity_terms, " recent ", target_type,
      " terms with first-day enrollment at or above ",
      round(fill_threshold * 100), "% of scheduled capacity"
    )
    flags <- c(
      if (is_forced) "Always monitored",
      if (capacity_shortfall) paste0(
        "Historical demand exceeds scheduled capacity by ",
        round(baseline - target_capacity), " registrations"
      ),
      if (chronic_fill) fill_evidence,
      if (growth_pressure) paste0(
        "Trend demand exceeds scheduled capacity by ",
        round(trend - target_capacity), " registrations"
      ),
      if (missing_schedule) "No usable target-term capacity"
    )
    exclusion_reason <- if (nrow(hist) == 0) {
      paste0("Not selected: no comparable ", target_type,
             " enrollment history")
    } else if (recent_capacity_terms == 0) {
      paste0("Not selected: no comparable ", target_type,
             " first-day enrollment and capacity history")
    } else {
      paste0(
        "Not selected: ", fill_evidence,
        if (!target_capacity_usable) {
          "; no usable target-term capacity for shortfall or growth checks"
        } else {
          paste0(
            "; historical and trend demand remain within ", min_gap,
            " seats of scheduled capacity"
          )
        }
      )
    }

    tibble::tibble(
      market_id = row$market_id,
      college = college,
      department = department,
      subject_course = row$subject_course,
      term_type = target_type,
      target_term = target_term,
      scheduled_sections = as.integer(target_sections_n),
      scheduled_capacity = as.numeric(target_capacity),
      n_delivery_components = as.integer(target_components_n),
      n_campuses = as.integer(target_campuses_n),
      target_classlist_total_to_date = as.numeric(target_classlist_total),
      target_registered_now = as.numeric(target_registered),
      target_early_drops_to_date = if (nrow(registration) == 0) NA_real_ else
        as.numeric(registration$dr_early[[1]]),
      target_late_drops_to_date = if (nrow(registration) == 0) NA_real_ else
        as.numeric(registration$dr_late[[1]]),
      target_other_status_to_date = if (nrow(registration) == 0) NA_real_ else
        as.numeric(registration$other_non_waitlist[[1]]),
      target_registration_observed = nrow(registration) > 0,
      target_available_seats = pmax(0, target_active_status$capacity_gap),
      target_classlist_fill = target_classlist_status$capacity_fill,
      target_active_fill = target_active_status$capacity_fill,
      target_capacity_reached = target_active_status$capacity_reached,
      historical_classlist_total = as.numeric(baseline),
      quick_trend_projection = as.numeric(trend),
      first_day_retention_rate = as.numeric(retention),
      quick_first_day_equivalent = as.numeric(trend_first_day_equivalent),
      recent_high_fill_terms = as.integer(high_fill_terms),
      recent_capacity_terms = as.integer(recent_capacity_terms),
      is_forced = is_forced,
      target_schedule_available = nrow(target) > 0,
      pressure_capacity_shortfall = capacity_shortfall,
      pressure_chronic_fill = chronic_fill,
      pressure_growth = growth_pressure,
      included = included,
      inclusion_reason = if (length(flags) == 0) exclusion_reason else
        paste(flags, collapse = "; ")
    )
  })

  dplyr::bind_rows(rows) %>%
    dplyr::arrange(dplyr::desc(included), subject_course)
}


projection_enrollment_slope <- function(values) {
  values <- as.numeric(values)
  if (length(values) < 3L || any(!is.finite(values))) return(NA_real_)
  unname(stats::coef(stats::lm(values ~ seq_along(values)))[[2]])
}


# Stability of a course's own comparable class-list history.
#
# This is the only one of the three reader-facing axes that needs no model, no
# aftcast, and no method selection: it asks whether the course has ever behaved
# predictably, using nothing but its own recorded same-season enrollments. That
# independence is the point. A course can be rated here when the aftcast
# machinery has nothing to say, which is most of the scope in a term where the
# upstream population has not settled.
#
# It is also not merely descriptive. On the Spring 2027 build the coefficient of
# variation correlates r = 0.69 with the selected method's realised aftcast
# error, and no course rated Stable was forecast poorly (13 Close, 2 Fair,
# 0 Poor). Volatility here is a finding in its own right: a course whose
# enrollment swings 50% year to year is not a forecasting failure, it is a
# programme where something is moving and someone should look.
#
# CV is the band driver because it is scale-free — a 30-student swing means
# something different in a 40-seat seminar than in a 700-seat gateway. Median
# and maximum year-over-year change are carried alongside it because a single
# structural break and steady churn produce similar CVs and want different
# responses.
projection_history_stability <- function(enrollment_history, rows, opt = list()) {
  if (nrow(rows) == 0) return(tibble::tibble())
  history_window <- as.integer(projection_option(opt, "demand_history_window"))
  min_terms <- as.integer(projection_option(opt, "stability_min_terms"))
  stable_max <- as.numeric(projection_option(opt, "stability_stable_max_cv"))
  moderate_max <- as.numeric(projection_option(opt, "stability_moderate_max_cv"))

  dplyr::bind_rows(lapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    history <- projection_history_for_row(
      enrollment_history, row, before_term = row$target_term
    ) %>%
      dplyr::slice_tail(n = history_window)

    values <- history$classlist_total
    keep <- is.finite(values) & values > 0
    values <- values[keep]
    terms <- history$term[keep]
    n_terms <- length(values)

    # A zero or negative mean cannot produce a meaningful CV, and one
    # observation has no variation to measure. Fail to Unrated rather than
    # emitting a number that looks like evidence.
    mean_enrl <- if (n_terms > 0) mean(values) else NA_real_
    cv <- if (n_terms >= 2L && is.finite(mean_enrl) && mean_enrl > 0) {
      stats::sd(values) / mean_enrl
    } else {
      NA_real_
    }
    yoy <- if (n_terms >= 2L) {
      abs(diff(values) / utils::head(values, -1L))
    } else {
      numeric(0)
    }
    yoy <- yoy[is.finite(yoy)]

    rated <- n_terms >= min_terms && is.finite(cv)
    stability <- if (!rated) {
      "Unrated"
    } else if (cv <= stable_max) {
      "Stable"
    } else if (cv <= moderate_max) {
      "Moderate"
    } else {
      "Volatile"
    }
    reason <- if (!rated) {
      paste0(
        n_terms, " comparable term",
        if (n_terms == 1L) "" else "s",
        " observed; ", min_terms, " needed to rate stability"
      )
    } else {
      paste0(
        scales::percent(cv, accuracy = 0.1),
        " variation across ", n_terms, " comparable terms, typically ",
        scales::percent(stats::median(yoy), accuracy = 0.1),
        " term to term"
      )
    }

    tibble::tibble(
      market_id = row$market_id,
      subject_course = row$subject_course,
      term_type = row$term_type,
      target_term = row$target_term,
      stability = stability,
      stability_reason = reason,
      history_terms = as.integer(n_terms),
      history_first_term = if (n_terms == 0) NA_integer_ else
        as.integer(min(terms)),
      history_last_term = if (n_terms == 0) NA_integer_ else
        as.integer(max(terms)),
      history_mean_classlist_total = mean_enrl,
      history_cv = cv,
      history_median_yoy_change = if (length(yoy) == 0) NA_real_ else
        stats::median(yoy),
      history_max_yoy_change = if (length(yoy) == 0) NA_real_ else max(yoy)
    )
  }))
}


projection_capacity_context <- function(enrollment_history, section_history,
                                        rows, opt = list()) {
  if (nrow(rows) == 0) return(tibble::tibble())
  history_window <- as.integer(projection_option(opt, "demand_history_window"))
  recent_window <- as.integer(projection_option(opt, "demand_recent_window"))
  capacity_threshold <- as.numeric(
    projection_option(opt, "registration_capacity_threshold")
  )
  response_fraction <- as.numeric(projection_option(opt, "capacity_response_fraction"))

  dplyr::bind_rows(lapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    history <- projection_history_for_row(
      enrollment_history, row, before_term = row$target_term
    ) %>%
      dplyr::slice_tail(n = history_window)
    capacities <- projection_section_history_for_row(
      section_history, row, before_term = row$target_term
    ) %>%
      dplyr::select(term, scheduled_capacity)
    paired <- history %>%
      dplyr::left_join(capacities, by = "term")
    paired <- dplyr::bind_cols(
      paired,
      projection_capacity_metrics(
        paired$first_day_enrl,
        paired$scheduled_capacity,
        reached_threshold = capacity_threshold
      )
    ) %>%
      dplyr::mutate(
        capacity_gain = scheduled_capacity - dplyr::lag(scheduled_capacity),
        enrollment_gain = classlist_total - dplyr::lag(classlist_total),
        usable_transition = capacity_usable & dplyr::lag(capacity_usable),
        demand_followed_capacity = usable_transition & capacity_gain > 0 &
          enrollment_gain >= response_fraction * capacity_gain
      )
    recent <- dplyr::slice_tail(paired, n = recent_window)
    slope <- projection_enrollment_slope(history$classlist_total)
    growth_threshold <- max(
      as.numeric(projection_option(opt, "demand_min_growth_per_year")),
      as.numeric(projection_option(opt, "demand_min_growth_share")) *
        stats::median(history$classlist_total, na.rm = TRUE)
    )
    usable_terms <- sum(recent$capacity_usable, na.rm = TRUE)
    reached_terms <- sum(recent$capacity_reached, na.rm = TRUE)
    capacity_quality <- dplyr::case_when(
      usable_terms < 2L ~ "Limited",
      TRUE ~ "Usable"
    )

    tibble::tibble(
      market_id = row$market_id,
      subject_course = row$subject_course,
      term_type = row$term_type, target_term = row$target_term,
      capacity_data_quality = capacity_quality,
      recent_capacity_terms = as.integer(usable_terms),
      recent_capacity_reached_terms = as.integer(reached_terms),
      last_first_day_fill = if (nrow(recent) == 0) NA_real_ else
        dplyr::last(recent$capacity_fill),
      observed_enrollment_slope = slope,
      observed_enrollment_rising = is.finite(slope) && slope >= growth_threshold,
      persistent_capacity_reached = capacity_quality == "Usable" &&
        reached_terms >= 2L,
      capacity_increase_terms = as.integer(sum(
        paired$usable_transition & paired$capacity_gain > 0, na.rm = TRUE
      )),
      demand_followed_capacity_terms = as.integer(sum(
        paired$demand_followed_capacity, na.rm = TRUE
      ))
    )
  }))
}


# The two candidates' values and audit fields, keyed per course, so every
# published row carries both the spine and the adjustment evidence whichever
# one the rule selected.
projection_method_pairing <- function(candidates, opt = list()) {
  keys <- c("market_id", "subject_course", "term_type", "target_term")
  observed <- candidates %>%
    dplyr::filter(method_id == CEDAR_ENROLLMENT_PROJECTION_DEFAULT_METHOD,
                  applicable, is.finite(projected_classlist_total)) %>%
    dplyr::transmute(
      dplyr::across(dplyr::all_of(keys)),
      observed_baseline = projected_classlist_total,
      observed_method_id = method_id,
      observed_method = method_label,
      observed_wape = wape,
      observed_n_backtests = n_backtests
    )
  adjusted <- candidates %>%
    dplyr::filter(method_id == "spine_adjusted") %>%
    dplyr::transmute(
      dplyr::across(dplyr::all_of(keys)),
      adjusted_projection = dplyr::if_else(
        applicable, projected_classlist_total, NA_real_
      ),
      adjusted_wape = wape,
      adjusted_n_backtests = n_backtests,
      adjusted_applicable = applicable,
      adjusted_reason = applicability_reason,
      adjusted_saturated_prior = saturated_prior,
      adjusted_prior_first_day_fill = prior_first_day_fill,
      adjusted_prior_first_day_basis = prior_first_day_basis,
      adjusted_waitlisted_prior = waitlisted_prior,
      adjusted_floor_uplift = floor_uplift,
      adjusted_floor_basis = floor_basis,
      adjusted_preceding_term = preceding_term,
      adjusted_feeder_check = feeder_check,
      adjusted_preceding_term_enrollment = preceding_term_enrollment,
      adjusted_preceding_term_change = preceding_term_change,
      adjusted_regime_alarm = regime_alarm,
      adjusted_delta_repeat = delta_repeat,
      adjusted_repeat_rate = repeat_rate,
      adjusted_delta_sequence = delta_sequence,
      adjusted_sequence_courses = sequence_courses,
      adjusted_sequence_change = sequence_change,
      adjusted_delta_feeder = delta_feeder,
      adjusted_feeder_rate = feeder_rate,
      adjusted_feeder_courses = feeder_courses,
      adjusted_feeder_change = feeder_change,
      adjusted_feeder_change_rate = feeder_change_rate,
      adjusted_delta_basis = delta_basis
    )
  candidates %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::left_join(observed, by = keys) %>%
    dplyr::left_join(adjusted, by = keys)
}


# Context for a saturated floor: among same-season pairs in this market whose
# prior term was saturated and whose capacity then grew by at least
# `expansion_capacity_change`, what share of the added seats filled. Learned
# only from pairs that precede the target. It is reported beside a floor so a
# reader knows what happened the last times saturated courses were given
# room; it is not applied as a multiplier, because the question is how many
# seats are needed, not what a hypothetical expansion would fill.
projection_expansion_response <- function(enrollment_history, section_history,
                                          target_term, opt = list()) {
  threshold <- as.numeric(projection_option(opt, "saturation_fill_threshold"))
  min_change <- as.numeric(projection_option(opt, "expansion_capacity_change"))
  min_pairs <- as.integer(projection_option(opt, "expansion_min_pairs"))
  target_term <- as.integer(target_term)
  target_type <- get_term_type(target_term)
  empty <- list(n_pairs = 0L, fill_rate = NA_real_,
                note = "No expansion history to read")
  if (nrow(enrollment_history) == 0L || nrow(section_history) == 0L) return(empty)

  series <- enrollment_history %>%
    dplyr::filter(term < target_term, term_type == target_type) %>%
    dplyr::inner_join(
      section_history %>%
        dplyr::select(market_id, subject_course, term, scheduled_capacity),
      by = c("market_id", "subject_course", "term")
    ) %>%
    dplyr::arrange(market_id, subject_course, term)
  if (nrow(series) == 0L) return(empty)
  # Saturation on the first day, as the floor judges it; a term whose first
  # day is unknown is not a saturated term.
  saturation <- enrollment_capacity_metrics(
    projection_judged_first_day(
      series$first_day_enrl, series$first_day_started_enrl,
      series$first_day_basis, series$scheduled_capacity, threshold
    ),
    series$scheduled_capacity,
    constrained_threshold = threshold
  )
  # CAMPUS_ROLLUP: the market series pools the declared campuses by design;
  # market_id names that rollup and the pairs are course-market pairs.
  pairs <- series %>%
    dplyr::mutate(saturated = saturation$capacity_constrained) %>%
    dplyr::group_by(market_id, subject_course) %>%
    dplyr::mutate(
      prior_saturated = dplyr::lag(saturated),
      prior_capacity = dplyr::lag(scheduled_capacity),
      prior_total = dplyr::lag(classlist_total)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::filter(
      prior_saturated %in% TRUE, is.finite(prior_capacity), prior_capacity > 0,
      scheduled_capacity / prior_capacity - 1 >= min_change, prior_total > 0
    ) %>%
    dplyr::mutate(
      fill_of_added = (classlist_total - prior_total) /
        (scheduled_capacity - prior_capacity)
    )
  if (nrow(pairs) < min_pairs) {
    return(list(
      n_pairs = nrow(pairs), fill_rate = NA_real_,
      note = paste0(
        "Only ", nrow(pairs), " saturated-then-expanded pairs before ",
        fmt_term(target_term), "; needs ", min_pairs
      )
    ))
  }
  rate <- stats::median(pairs$fill_of_added)
  list(
    n_pairs = nrow(pairs), fill_rate = rate,
    note = paste0(
      "When saturated courses in this market were given at least ",
      scales::percent(min_change, accuracy = 1), " more seats (", nrow(pairs),
      " cases before ", fmt_term(target_term), "), class-list demand grew by ",
      scales::percent(rate, accuracy = 1), " of the added seats"
    )
  )
}
