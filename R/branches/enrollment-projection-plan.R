# From a forecast to a plan: the pressure bump, the Spring feeder adjustment,
# and the recommendation and sections for each course.

# Every published plan is its projection plus its feeder adjustment plus its
# pressure bump (never below zero), the bump is zero unless it applies, the
# feeder adjustment is zero where the published projection already carries the
# deltas or the target's season does not follow feeders (`seasons`, the
# model's plan_feeder_seasons), and sections are sized from the plan, so the
# page can say exactly how much each raised it.
validate_pressure_bump_rows <- function(rows, seasons, caller) {
  if (!is.character(seasons) || anyNA(seasons)) {
    stop("[enrollment-projection-plan.R] ", caller,
         " needs the model's plan_feeder_seasons.", call. = FALSE)
  }
  if (nrow(rows) == 0L) return(invisible(TRUE))
  projected <- rows$projected_classlist_total
  bump <- rows$pressure_bump
  feeder <- rows$plan_feeder_adjustment
  planned <- rows$planned_registrations
  expected_sections <- projection_sections_for_demand(
    planned, rows$reference_section_size
  )
  sections_agree <- dplyr::if_else(
    is.na(expected_sections),
    is.na(rows$recommended_sections),
    !is.na(rows$recommended_sections) &
      rows$recommended_sections == expected_sections
  )
  valid <- is.finite(bump) & bump >= 0 & is.finite(feeder) &
    !is.na(rows$pressure_bump_applied) &
    (rows$pressure_bump_applied | bump == 0) &
    (rows$method_id != "spine_adjusted" | feeder == 0) &
    (rows$term_type %in% seasons | feeder == 0) &
    dplyr::if_else(
      is.finite(projected),
      is.finite(planned) &
        abs(planned - pmax(0, projected + feeder + bump)) <= 1e-6,
      is.na(planned)
    ) &
    sections_agree
  if (any(!valid)) {
    stop(
      "[enrollment-projection-plan.R] ", caller,
      " has a plan that is not its projection plus its feeder adjustment ",
      "plus its pressure bump.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


# The pressure bump: a planning allowance for a course that is always full.
#
# A course near full on the first day in every one of its last
# `pressure_bump_window` same-season offerings with a known first day (at least
# `pressure_bump_min_terms` of them) turned students away, and its
# registrations were capped by the seats offered. It is planned for
# `pressure_bump_share` more registrations than last time, or for the students
# left waiting if that is more. A floor the published method already added
# counts toward the bump. Feeder changes are the plan's separate feeder
# adjustment (projection_plan_feeder_adjustment()) and never cancel the bump:
# the backlog does not leave with them.
#
# `rows` are published rows joined to `projection_method_pairing()`. Returns
# one row per course: the terms judged, the bump in registrations, and a note
# that says why it applies or why not. The forecast is never changed here.
projection_pressure_bump <- function(enrollment_history, section_history, rows,
                                     opt = list()) {
  keys <- c("market_id", "subject_course", "term_type", "target_term")
  empty <- tibble::tibble(
    market_id = character(), subject_course = character(),
    term_type = character(), target_term = integer(),
    pressure_judged_terms = integer(), pressure_full_terms = integer(),
    pressure_bump_applied = logical(), pressure_bump = numeric(),
    pressure_bump_note = character()
  )
  if (nrow(rows) == 0L) return(empty)
  projection_require_columns(
    rows,
    c(keys, "method_id", "observed_baseline", "projected_classlist_total",
      "adjusted_waitlisted_prior", "adjusted_floor_uplift"),
    "projection_pressure_bump()"
  )
  threshold <- as.numeric(projection_option(opt, "saturation_fill_threshold"))
  share <- as.numeric(projection_option(opt, "pressure_bump_share"))
  window <- as.integer(projection_option(opt, "pressure_bump_window"))
  min_terms <- as.integer(projection_option(opt, "pressure_bump_min_terms"))
  share_label <- scales::percent(share, accuracy = 1)

  dplyr::bind_rows(lapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    season <- switch(row$term_type, spring = "Spring", fall = "Fall", "term")
    recent <- projection_history_for_row(
      enrollment_history, row, before_term = row$target_term
    ) %>%
      dplyr::slice_tail(n = window) %>%
      dplyr::left_join(
        projection_section_history_for_row(
          section_history, row, before_term = row$target_term
        ) %>%
          dplyr::select(term, scheduled_capacity),
        by = "term"
      )
    fill <- projection_capacity_metrics(
      projection_judged_first_day(
        recent$first_day_enrl, recent$first_day_started_enrl,
        recent$first_day_basis, recent$scheduled_capacity, threshold
      ),
      recent$scheduled_capacity,
      reached_threshold = threshold
    )
    judged <- recent$term[fill$capacity_usable]
    short <- fill$capacity_usable & !fill$capacity_reached
    terms_text <- function(terms) {
      paste(vapply(terms, fmt_term, character(1)), collapse = ", ")
    }

    spine <- row$observed_baseline
    waiting <- dplyr::coalesce(as.integer(row$adjusted_waitlisted_prior), 0L)
    always_full <- length(judged) >= min_terms && !any(short)

    applied <- is.finite(spine) && spine > 0 &&
      is.finite(row$projected_classlist_total) && always_full
    already <- if (identical(row$method_id, "spine_adjusted")) {
      dplyr::coalesce(as.numeric(row$adjusted_floor_uplift), 0)
    } else 0
    unserved <- max(share * spine, waiting)
    bump <- if (applied) round(max(0, unserved - already)) else 0

    full_text <- paste0(
      "near full on the first day in every recent ", season,
      " with a first-day count (", terms_text(judged), ")"
    )
    note <- if (!is.finite(spine) || spine <= 0) {
      "No pressure bump: no prior same-season registrations to raise"
    } else if (!is.finite(row$projected_classlist_total)) {
      "No pressure bump: no projection to raise"
    } else if (nrow(recent) < min_terms) {
      paste0(
        "No pressure bump: only ", nrow(recent), " ", season, " offering",
        if (nrow(recent) == 1L) "" else "s", " on record, and the bump needs ",
        min_terms, " with a first-day count"
      )
    } else if (length(judged) < min_terms) {
      paste0(
        "No pressure bump: ", length(judged), " of the last ", nrow(recent), " ",
        season, " offerings ha", if (length(judged) == 1L) "s" else "ve",
        " a first-day count", if (length(judged) > 0L) {
          paste0(" (", terms_text(judged), ")")
        } else "",
        ", and the bump needs ", min_terms
      )
    } else if (any(short)) {
      paste0(
        "No pressure bump: ",
        paste0(
          vapply(recent$term[short], fmt_term, character(1)), " filled ",
          scales::percent(fill$capacity_fill[short], accuracy = 0.1),
          collapse = " and "
        ),
        " of its seats on the first day, below the ",
        scales::percent(threshold, accuracy = 1), " near-full line"
      )
    } else {
      sized_by <- if (waiting > share * spine) {
        paste0(
          "planned for the ", waiting, " students left waiting, more than ",
          share_label, " of last ", season, "'s ",
          format(round(spine), big.mark = ","), " registrations"
        )
      } else {
        paste0(
          "planned for ", share_label, " more than last ", season, "'s ",
          format(round(spine), big.mark = ","), " registrations",
          if (waiting > 0L) paste0(" (", waiting, " students were left waiting)") else ""
        )
      }
      paste0(
        "Pressure bump +", format(bump, big.mark = ","), ": ", full_text,
        ", so its registrations were capped by its seats; ", sized_by,
        if (already > 0) {
          paste0("; the published projection already adds ", round(already),
                 " of them")
        } else ""
      )
    }

    tibble::tibble(
      market_id = row$market_id, subject_course = row$subject_course,
      term_type = row$term_type, target_term = row$target_term,
      pressure_judged_terms = as.integer(length(judged)),
      pressure_full_terms = as.integer(sum(fill$capacity_reached)),
      pressure_bump_applied = applied,
      pressure_bump = as.numeric(bump),
      pressure_bump_note = note
    )
  }))
}


# The plan's feeder adjustment (0.26.0): the term just finished, carried into
# the plan wherever the published projection does not already carry it.
#
# A listed sequence's change (projection_sequences.csv: the course taken the
# term before this one) always counts, either way, at that pair's own rate.
# The pooled feeders' change counts only when it moved `plan_feeder_change` or
# more either way; smaller moves are noise against the course's own year. When
# the published method is the adjusted candidate, its projection already holds
# both deltas and the plan adds nothing. Only targets in `plan_feeder_seasons`
# are adjusted (0.27.0): following Fall feeders improved past Spring forecasts,
# and following Spring feeders did not improve Fall ones. Planning only: the
# forecast and its accuracy are untouched.
#
# `rows` are published rows joined to `projection_method_pairing()`. Returns
# one row per course with the adjustment in registrations and a note.
projection_plan_feeder_adjustment <- function(rows, opt = list()) {
  keys <- c("market_id", "subject_course", "term_type", "target_term")
  empty <- tibble::tibble(
    market_id = character(), subject_course = character(),
    term_type = character(), target_term = integer(),
    plan_feeder_adjustment = numeric(), plan_feeder_note = character()
  )
  if (nrow(rows) == 0L) return(empty)
  projection_require_columns(
    rows,
    c(keys, "method_id", "projected_classlist_total", "adjusted_applicable",
      "adjusted_preceding_term", "adjusted_feeder_check",
      "adjusted_delta_sequence", "adjusted_sequence_courses",
      "adjusted_sequence_change", "adjusted_delta_feeder",
      "adjusted_feeder_change_rate"),
    "projection_plan_feeder_adjustment()"
  )
  line <- as.numeric(projection_option(opt, "plan_feeder_change"))
  line_label <- scales::percent(line, accuracy = 1)
  seasons <- projection_option(opt, "plan_feeder_seasons")
  seasons_rule <- projection_plan_feeder_seasons_rule(seasons)
  signed <- function(x) sprintf("%+.0f", x)
  sentence_case <- function(x) paste0(toupper(substr(x, 1, 1)), substring(x, 2))

  dplyr::bind_rows(lapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, , drop = FALSE]
    preceding <- if (is.na(row$adjusted_preceding_term)) "the term just finished" else
      fmt_term(row$adjusted_preceding_term)
    has_sequence <- !is.na(row$adjusted_sequence_courses)
    sequence_delta <- if (has_sequence) as.numeric(row$adjusted_delta_sequence) else 0
    rate <- row$adjusted_feeder_change_rate
    pooled_moves <- is.finite(rate) && abs(rate) >= line - 1e-9
    pooled_delta <- if (pooled_moves) as.numeric(row$adjusted_delta_feeder) else 0
    in_projection <- identical(row$method_id, "spine_adjusted")
    in_season <- row$term_type %in% seasons
    usable <- isTRUE(row$adjusted_applicable) && is.finite(row$projected_classlist_total)
    adjustment <- if (usable && !in_projection && in_season) {
      round(sequence_delta + pooled_delta)
    } else 0

    others <- if (has_sequence) "its other feeder courses" else "its feeder courses"
    sequence_text <- if (has_sequence) {
      paste0(
        row$adjusted_sequence_courses, ", taken the term before, moved ",
        signed(row$adjusted_sequence_change), " students in ", preceding,
        ", which carries ", signed(sequence_delta), " into this course"
      )
    }
    pooled_text <- if (is.finite(rate)) {
      # One decimal: a whole percent printed 5% on both sides of the line.
      paste0(
        others, " moved ", sprintf("%+.1f%%", 100 * rate), " in ", preceding,
        if (in_projection) {
          paste0(", which carries ", signed(row$adjusted_delta_feeder))
        } else if (pooled_moves) {
          paste0(", ", line_label, " or more, which carries ", signed(pooled_delta))
        } else {
          paste0(", inside the ", line_label, " line, so the plan does not follow them")
        }
      )
    } else {
      switch(
        dplyr::coalesce(row$adjusted_feeder_check, "unmeasurable"),
        term_not_observed = paste0(
          "feeder courses in ", preceding,
          " are not observed yet; recheck when they settle"
        ),
        no_course_baseline = paste0(
          "the feeder change needs the course's own enrollment in ", preceding,
          " and a year before"
        ),
        no_feeders = paste0("no ", if (has_sequence) "other " else "",
                            "feeder course met the evidence threshold"),
        "the feeder change could not be measured"
      )
    }
    detail <- paste(c(sequence_text, pooled_text), collapse = "; ")
    note <- if (!usable) {
      "No feeder adjustment: no projection to adjust"
    } else if (in_projection) {
      paste0("No feeder adjustment: the published projection already includes ",
             "the changes in ", preceding, ". ", sentence_case(detail))
    } else if (!in_season) {
      paste0("No feeder adjustment: ", seasons_rule)
    } else if (adjustment == 0) {
      paste0("No feeder adjustment: ", detail)
    } else {
      paste0("Feeder adjustment ", signed(adjustment), ": ", detail)
    }

    tibble::tibble(
      market_id = row$market_id, subject_course = row$subject_course,
      term_type = row$term_type, target_term = row$target_term,
      plan_feeder_adjustment = as.numeric(adjustment),
      plan_feeder_note = note
    )
  }))
}


# "only Spring plans follow their feeder courses", from plan_feeder_seasons.
projection_plan_feeder_seasons_rule <- function(seasons) {
  if (!is.character(seasons) || anyNA(seasons)) {
    stop("[enrollment-projection-plan.R] plan_feeder_seasons must name term types.",
         call. = FALSE)
  }
  labels <- c(spring = "Spring", summer = "Summer", fall = "Fall")
  unknown <- setdiff(seasons, names(labels))
  if (length(unknown) > 0L) {
    stop("[enrollment-projection-plan.R] Unknown plan_feeder_seasons: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  named <- unname(labels[intersect(names(labels), seasons)])
  if (length(named) == 0L) return("no plan follows its feeder courses")
  paste0("only ", paste(named, collapse = " and "),
         " plans follow their feeder courses")
}


add_projection_recommendations <- function(selected, candidates, pressure_screen,
                                           enrollment_history, section_history,
                                           opt = list()) {
  if (nrow(selected) == 0) return(selected)
  keys <- c("market_id", "subject_course", "term_type", "target_term")

  spread_input <- candidates %>%
    dplyr::filter(applicable, is.finite(projected_classlist_total)) %>%
    dplyr::select(dplyr::all_of(keys), projected_classlist_total)
  spread <- if (nrow(spread_input) == 0) {
    tibble::tibble(
      market_id = character(), subject_course = character(),
      term_type = character(), target_term = integer(),
      candidate_min = numeric(), candidate_max = numeric(),
      candidate_spread = numeric(), n_applicable_methods = integer()
    )
  } else {
    spread_input %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
      dplyr::summarise(
        candidate_min = min(projected_classlist_total),
        candidate_max = max(projected_classlist_total),
        candidate_spread = candidate_max - candidate_min,
        n_applicable_methods = dplyr::n(),
        .groups = "drop"
      )
  }
  pairing <- projection_method_pairing(candidates, opt)
  stability <- projection_history_stability(enrollment_history, selected, opt)
  capacity_context <- projection_capacity_context(
    enrollment_history, section_history, selected, opt
  )
  expansion <- projection_expansion_response(
    enrollment_history, section_history, selected$target_term[[1]], opt
  )

  joined <- selected %>%
    dplyr::left_join(
      dplyr::select(
        pressure_screen,
        dplyr::all_of(keys), department, scheduled_sections,
        scheduled_capacity, target_schedule_available,
        target_classlist_total_to_date, target_registered_now,
        target_early_drops_to_date, target_late_drops_to_date,
        target_other_status_to_date,
        target_registration_observed, target_available_seats,
        target_classlist_fill, target_active_fill, target_capacity_reached,
        inclusion_reason
      ),
      by = keys
    ) %>%
    dplyr::left_join(spread, by = keys) %>%
    dplyr::left_join(pairing, by = keys) %>%
    dplyr::left_join(capacity_context, by = keys) %>%
    dplyr::left_join(stability, by = keys)
  pressure <- projection_pressure_bump(
    enrollment_history, section_history, joined, opt
  )
  plan_feeder <- projection_plan_feeder_adjustment(joined, opt)

  joined %>%
    dplyr::left_join(pressure, by = keys) %>%
    dplyr::left_join(plan_feeder, by = keys) %>%
    dplyr::mutate(
      expansion_pairs = as.integer(expansion$n_pairs),
      expansion_fill_rate = as.numeric(expansion$fill_rate),
      expansion_note = as.character(expansion$note)
    ) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      reference_section_size = {
        target_size <- if (scheduled_sections > 0 && scheduled_capacity > 0) {
          scheduled_capacity / scheduled_sections
        } else {
          row_context <- list(
            market_id = market_id,
            subject_course = subject_course,
            term_type = term_type
          )
          prior <- projection_section_history_for_row(
            section_history, row_context, before_term = target_term
          ) %>% dplyr::slice_tail(n = 4)
          stats::median(prior$capacity_per_section, na.rm = TRUE)
        }
        if (!is.finite(target_size) || target_size <= 0) NA_real_ else target_size
      },
      # Seats are planned for REGISTRATIONS, not expected first-day occupancy
      # (0.23.0): projected registrations plus the feeder adjustment (0.26.0)
      # plus any pressure bump. Registrations run above the first day because
      # every early drop frees a seat someone else takes, and that margin is
      # kept on purpose: running short of seats costs more than an empty one.
      # Sized on the first day, 61% of 207 past aftcasts planned fewer seats
      # than were filled on day one; sized on registrations, 32%
      # (forecasting-lessons.md). A falling feeder can lower the plan, never
      # below zero.
      planned_registrations = if (is.finite(projected_classlist_total)) {
        max(0, projected_classlist_total + plan_feeder_adjustment + pressure_bump)
      } else NA_real_,
      seat_gap = round(planned_registrations - scheduled_capacity),
      projected_over_capacity = pmax(0, seat_gap),
      capacity_limit_signal = target_schedule_available &
        target_capacity_reached & projected_over_capacity > 0,
      capacity_limit_status = dplyr::case_when(
        !target_schedule_available ~ "Target schedule unavailable",
        !is.finite(projected_classlist_total) ~
          "Insufficient history for a registration-demand estimate",
        projected_over_capacity <= 0 ~ "Planned registrations fit scheduled capacity",
        capacity_limit_signal ~ "Seat ceiling likely limits observed enrollment",
        TRUE ~ "Projected demand exceeds planned capacity"
      ),
      capacity_limit_note = dplyr::case_when(
        !target_schedule_available ~
          "No target schedule is available for a seat-ceiling check",
        !is.finite(projected_classlist_total) ~
          "Class-list demand is not yet stable",
        projected_over_capacity <= 0 ~ paste(
          projection_count_noun(
            round(scheduled_capacity - planned_registrations), "planned seat"
          ),
          if (isTRUE(round(scheduled_capacity - planned_registrations) == 1)) "remains" else "remain",
          "above planned registrations"
        ),
        capacity_limit_signal ~ paste0(
          "Planned registrations exceed capacity by ",
          round(projected_over_capacity), "; ",
          projection_count_noun(round(target_available_seats), "seat"),
          if (isTRUE(round(target_available_seats) == 1)) " is" else " are",
          " currently unoccupied"
        ),
        TRUE ~ paste0(
          "Planned registrations exceed capacity by ",
          round(projected_over_capacity), "; active registration fill is ",
          scales::percent(target_active_fill, accuracy = 0.1)
        )
      ),
      recommended_sections = projection_sections_for_demand(
        planned_registrations, reference_section_size
      ),
      # The sections each part of the plan adds: the feeder adjustment's on top
      # of the projection's (negative when feeders fell), the bump's on top of
      # both. Together they are the plan's sections less the projection's.
      plan_feeder_sections = projection_sections_for_demand(
        max(0, projected_classlist_total + plan_feeder_adjustment),
        reference_section_size
      ) - projection_sections_for_demand(projected_classlist_total, reference_section_size),
      pressure_bump_sections = recommended_sections -
        projection_sections_for_demand(
          max(0, projected_classlist_total + plan_feeder_adjustment),
          reference_section_size
        ),
      additional_sections = projection_additional_sections(
        recommended_sections, scheduled_sections
      ),
      methods_disagree = dplyr::if_else(
        is.finite(projected_classlist_total) & projected_classlist_total > 0 &
          is.finite(candidate_spread),
        candidate_spread / projected_classlist_total >=
          as.numeric(projection_option(opt, "disagreement_threshold")),
        FALSE
      ),
      floor_note = dplyr::case_when(
        is.na(adjusted_saturated_prior) ~ dplyr::coalesce(
          adjusted_floor_basis, "Saturation of the prior term cannot be judged"
        ),
        adjusted_saturated_prior & adjusted_floor_uplift > 0 ~ paste0(
          "Floor: ", adjusted_floor_basis, ". ", expansion_note
        ),
        adjusted_saturated_prior ~ paste0(
          "Floor: ", adjusted_floor_basis,
          "; the projection is a lower bound. ", expansion_note
        ),
        TRUE ~ adjusted_floor_basis
      ),
      regime_note = dplyr::case_when(
        is.na(adjusted_regime_alarm) ~ dplyr::coalesce(
          adjusted_delta_basis, "Preceding term not observed"
        ),
        adjusted_regime_alarm ~ paste0(
          "Regime check: enrollment in ", fmt_term(adjusted_preceding_term),
          " moved ", sprintf("%+.0f%%", 100 * adjusted_preceding_term_change),
          " from the year before; review this course before scheduling to the projection"
        ),
        TRUE ~ paste0(
          "Enrollment in ", fmt_term(adjusted_preceding_term), " moved ",
          sprintf("%+.0f%%", 100 * adjusted_preceding_term_change),
          " from the year before"
        )
      ),
      why_uncertain = dplyr::case_when(
        accuracy == "Unrated" & methods_disagree ~ paste0(
          accuracy_reason, "; candidate methods also disagree materially"
        ),
        accuracy == "Unrated" ~ accuracy_reason,
        accuracy == "Low" & methods_disagree ~ paste0(
          accuracy_reason, "; candidate methods also disagree materially"
        ),
        accuracy == "Low" ~ accuracy_reason,
        stability == "Volatile" ~ paste0(
          "Aftcasts land within ", accuracy, " range, but the course's own ",
          "history is volatile: ", stability_reason
        ),
        TRUE ~ paste0(accuracy_reason, "; ", stability_reason)
      ),
      recommendation = dplyr::case_when(
        !is.finite(projected_classlist_total) ~ "Insufficient history",
        projected_classlist_total <= 0 ~ "No projected demand",
        !target_schedule_available & !is.na(recommended_sections) &
          adjusted_saturated_prior %in% TRUE ~
          paste0("Plan at least ", projection_count_noun(recommended_sections, "section"),
                 "; prior term was saturated"),
        !target_schedule_available & !is.na(recommended_sections) ~
          paste("Plan", projection_count_noun(recommended_sections, "section")),
        is.finite(projection_high) &
          projection_high + plan_feeder_adjustment + pressure_bump <=
            scheduled_capacity ~
          "Capacity appears sufficient",
        !is.na(additional_sections) & additional_sections > 0 &
          (scheduled_sections == 0L |
            seat_gap >= pmax(
              as.numeric(projection_option(opt, "recommendation_min_seat_gap")),
              0.25 * reference_section_size
            )) ~
          paste("Add", projection_count_noun(additional_sections, "section")),
        seat_gap > 0 ~ paste("Open", projection_count_noun(seat_gap, "additional seat")),
        methods_disagree ~ "Review method disagreement",
        TRUE ~ "Monitor near capacity"
      )
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-method_rank)
}
