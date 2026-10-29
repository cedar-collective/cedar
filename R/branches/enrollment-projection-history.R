# The recent same-season history shown beside each projection, its movement
# signals, and the per-campus split under a pooled market row.

empty_projection_recent_history <- function() {
  tibble::tibble(
    market_id = character(), college = character(), department = character(),
    subject_course = character(), term_type = character(),
    projection_target_term = integer(), history_term = integer(),
    history_term_label = character(), recency_rank = integer(),
    actual_classlist_total = numeric(), actual_first_day = numeric(),
    actual_census = numeric(), actual_final_enrollment = numeric(),
    actual_first_day_retention_rate = numeric(), scheduled_sections = integer(),
    scheduled_capacity = numeric(), first_day_fill = numeric(),
    prior_classlist_total = numeric(), prior_scheduled_capacity = numeric(),
    classlist_change = numeric(), capacity_change = numeric(),
    first_day_capacity_gap = numeric(),
    capacity_usable = logical(), capacity_reached = logical(), method_id = character(),
    method_label = character(), aftcast_method_id = character(),
    aftcast_method_label = character(), aftcast_applicable = logical(),
    aftcast_reason = character(),
    aftcast_classlist_total = numeric(), aftcast_error = numeric(),
    aftcast_pct_error = numeric(), aftcast_capacity_censored = logical(),
    aftcast_censored_error = numeric(), aftcast_censored_pct_error = numeric(),
    potential_miss_explanation = character(),
    source_term = integer(), source_term_label = character(),
    prior_source_term = integer(), prior_source_term_label = character(),
    university_students = numeric(), prior_university_students = numeric(),
    university_student_change = numeric(),
    university_incoming_first_sem = numeric(),
    prior_university_incoming_first_sem = numeric(),
    university_incoming_change = numeric(),
    market_students = numeric(), prior_market_students = numeric(),
    market_student_change = numeric(),
    source_outcomes_complete = logical(), source_graded_students = numeric(),
    source_dfw_students = numeric(), source_dfw_rate = numeric(),
    prior_source_dfw_students = numeric(), prior_source_dfw_rate = numeric(),
    source_dfw_student_change = numeric(), source_dfw_rate_change = numeric(),
    source_dfw_next_term_repeaters = numeric(),
    source_dfw_repeater_share = numeric(), movement_context = character()
  )
}


attach_projection_movement_signals <- function(
    history, student_inputs = NULL, graded_through_term = NULL) {
  if (nrow(history) == 0L) return(empty_projection_recent_history())
  empty <- empty_projection_recent_history()
  signal_start <- match("source_term", names(empty))
  signal_columns <- names(empty)[seq.int(signal_start, length(names(empty)))]
  history <- history %>% dplyr::select(-dplyr::any_of(signal_columns))
  required_inputs <- c(
    "university_term_signals", "market_term_signals", "course_outcomes",
    "course_repeat_pressure"
  )
  if (is.null(student_inputs) ||
      any(!required_inputs %in% names(student_inputs))) {
    for (column in setdiff(names(empty), names(history))) {
      history[[column]] <- empty[[column]][NA_integer_]
    }
    return(history)
  }

  university_now <- student_inputs$university_term_signals %>%
    dplyr::rename(
      source_term = term,
      university_students = university_students,
      university_incoming_first_sem = university_incoming_first_sem
    )
  university_prior <- student_inputs$university_term_signals %>%
    dplyr::rename(
      prior_source_term = term,
      prior_university_students = university_students,
      prior_university_incoming_first_sem = university_incoming_first_sem
    )
  market_now <- student_inputs$market_term_signals %>%
    dplyr::rename(source_term = term, market_students = market_students)
  market_prior <- student_inputs$market_term_signals %>%
    dplyr::rename(
      prior_source_term = term,
      prior_market_students = market_students
    )
  outcomes_now <- student_inputs$course_outcomes %>%
    dplyr::rename(
      source_term = term, source_graded_students = graded_students,
      source_dfw_students = dfw_students, source_dfw_rate = dfw_rate
    )
  outcomes_prior <- student_inputs$course_outcomes %>%
    dplyr::rename(
      prior_source_term = term,
      prior_source_dfw_students = dfw_students,
      prior_source_dfw_rate = dfw_rate
    ) %>%
    dplyr::select(
      subject_course, prior_source_term, prior_source_dfw_students,
      prior_source_dfw_rate
    )
  repeats <- student_inputs$course_repeat_pressure %>%
    dplyr::rename(
      source_term = term,
      source_dfw_next_term_repeaters = dfw_next_term_repeaters
    ) %>%
    dplyr::select(
      subject_course, source_term, next_term,
      source_dfw_next_term_repeaters
    )

  grade_edge <- if (is.null(graded_through_term) ||
                    length(graded_through_term) == 0L ||
                    is.na(graded_through_term[[1]])) {
    NA_integer_
  } else {
    as.integer(graded_through_term[[1]])
  }

  history %>%
    dplyr::mutate(
      source_term = vapply(history_term, subtract_term, integer(1), summer = FALSE),
      prior_source_term = source_term - 100L,
      source_term_label = vapply(source_term, fmt_term, character(1)),
      prior_source_term_label = vapply(prior_source_term, fmt_term, character(1))
    ) %>%
    dplyr::left_join(university_now, by = "source_term") %>%
    dplyr::left_join(university_prior, by = "prior_source_term") %>%
    dplyr::left_join(market_now, by = "source_term") %>%
    dplyr::left_join(market_prior, by = "prior_source_term") %>%
    dplyr::left_join(outcomes_now, by = c("subject_course", "source_term")) %>%
    dplyr::left_join(
      outcomes_prior, by = c("subject_course", "prior_source_term")
    ) %>%
    dplyr::left_join(
      repeats,
      by = c(
        "subject_course", "source_term", "history_term" = "next_term"
      )
    ) %>%
    dplyr::mutate(
      university_student_change = dplyr::if_else(
        prior_university_students > 0,
        university_students / prior_university_students - 1,
        NA_real_
      ),
      university_incoming_change = dplyr::if_else(
        prior_university_incoming_first_sem > 0,
        university_incoming_first_sem /
          prior_university_incoming_first_sem - 1,
        NA_real_
      ),
      market_student_change = dplyr::if_else(
        prior_market_students > 0,
        market_students / prior_market_students - 1,
        NA_real_
      ),
      source_outcomes_complete = !is.na(.env$grade_edge) &
        source_term <= .env$grade_edge,
      source_graded_students = dplyr::if_else(
        source_outcomes_complete,
        dplyr::coalesce(source_graded_students, 0), NA_real_
      ),
      source_dfw_students = dplyr::if_else(
        source_outcomes_complete,
        dplyr::coalesce(source_dfw_students, 0), NA_real_
      ),
      source_dfw_rate = dplyr::if_else(
        source_outcomes_complete & source_graded_students > 0,
        source_dfw_students / source_graded_students, NA_real_
      ),
      source_dfw_student_change = source_dfw_students -
        prior_source_dfw_students,
      source_dfw_rate_change = source_dfw_rate - prior_source_dfw_rate,
      source_dfw_next_term_repeaters = dplyr::if_else(
        source_outcomes_complete,
        dplyr::coalesce(source_dfw_next_term_repeaters, 0), NA_real_
      ),
      source_dfw_repeater_share = dplyr::if_else(
        actual_classlist_total > 0,
        source_dfw_next_term_repeaters / actual_classlist_total,
        NA_real_
      ),
      movement_context = dplyr::case_when(
        is.finite(classlist_change) & is.finite(capacity_change) &
          abs(capacity_change) >= 0.10 & abs(classlist_change) >= 0.08 &
          sign(classlist_change) == sign(capacity_change) ~
            "Enrollment and scheduled capacity moved together",
        dplyr::coalesce(capacity_reached, FALSE) ~
          "First-day enrollment reached scheduled capacity",
        is.finite(university_student_change) &
          abs(university_student_change) >= 0.05 ~
            "University enrollment also moved materially",
        TRUE ~ "No single measured movement dominates"
      )
    )
}


build_projection_recent_history <- function(projections, enrollment_history,
                                            section_history, backtests,
                                            opt = list(), student_inputs = NULL,
                                            graded_through_term = NULL) {
  if (nrow(projections) == 0L) return(empty_projection_recent_history())
  window <- as.integer(projection_option(opt, "recent_history_terms"))
  if (!is.finite(window) || window < 1L) {
    stop("[enrollment-projection-history.R] recent_history_terms must be positive.",
         call. = FALSE)
  }

  empty_aftcasts <- tibble::tibble(
    history_term = integer(), aftcast_method_id = character(),
    aftcast_method_label = character(), aftcast_applicable = logical(),
    aftcast_reason = character(), aftcast_classlist_total = numeric(),
    aftcast_capacity_censored = logical(),
    aftcast_censored_error = numeric(), aftcast_censored_pct_error = numeric()
  )

  rows <- dplyr::bind_rows(lapply(seq_len(nrow(projections)), function(i) {
    projection <- projections[i, , drop = FALSE]
    history <- projection_history_for_row(
      enrollment_history, projection, before_term = projection$target_term
    ) %>%
      dplyr::slice_tail(n = window + 1L)
    if (nrow(history) == 0L) return(NULL)

    sections <- projection_section_history_for_row(
      section_history, projection, before_term = projection$target_term
    ) %>%
      dplyr::select(term, scheduled_sections, scheduled_capacity)
    # The aftcast shown for a past term is the one the rolling selection rule
    # would have published then (policy_selected), which may be a different
    # method from today's pick. Showing today's method on every past term
    # would restate the in-sample fit 0.19.0 retired.
    aftcasts <- if (nrow(backtests) == 0L || projection$method_id == "none") {
      empty_aftcasts
    } else {
      projection_require_columns(
        backtests, "policy_selected",
        "build_projection_recent_history() backtests"
      )
      backtests %>%
        dplyr::filter(
          market_id == projection$market_id,
          subject_course == projection$subject_course,
          term_type == projection$term_type,
          policy_selected,
          target_term %in% history$term
        ) %>%
        dplyr::transmute(
          history_term = target_term,
          aftcast_method_id = method_id,
          aftcast_method_label = method_label,
          aftcast_applicable = applicable,
          aftcast_reason = applicability_reason,
          aftcast_classlist_total = projected_classlist_total,
          aftcast_capacity_censored = capacity_censored_miss,
          aftcast_censored_error = capacity_censored_error,
          aftcast_censored_pct_error = dplyr::if_else(
            actual_classlist_total > 0,
            capacity_censored_error / actual_classlist_total,
            NA_real_
          )
        )
    }

    joined <- history %>%
      dplyr::left_join(sections, by = "term") %>%
      dplyr::left_join(aftcasts, by = c("term" = "history_term"))
    capacity_status <- projection_capacity_metrics(
      joined$first_day_enrl, joined$scheduled_capacity,
      reached_threshold = projection_option(opt, "registration_capacity_threshold")
    )

    dplyr::bind_cols(joined, capacity_status) %>%
      dplyr::mutate(
        prior_classlist_total = dplyr::lag(classlist_total),
        prior_scheduled_capacity = dplyr::lag(scheduled_capacity),
        classlist_change = dplyr::if_else(
          prior_classlist_total > 0,
          classlist_total / prior_classlist_total - 1,
          NA_real_
        ),
        capacity_change = dplyr::if_else(
          prior_scheduled_capacity > 0,
          scheduled_capacity / prior_scheduled_capacity - 1,
          NA_real_
        )
      ) %>%
      dplyr::slice_tail(n = window) %>%
      dplyr::transmute(
        market_id = projection$market_id,
        college = projection$college,
        department = projection$department,
        subject_course = projection$subject_course,
        term_type = projection$term_type,
        projection_target_term = as.integer(projection$target_term),
        history_term = as.integer(term),
        history_term_label = vapply(term, fmt_term, character(1)),
        actual_classlist_total = as.numeric(classlist_total),
        actual_first_day = as.numeric(first_day_enrl),
        actual_census = as.numeric(census_enrl),
        actual_final_enrollment = as.numeric(registered),
        actual_first_day_retention_rate = dplyr::if_else(
          classlist_total > 0, first_day_enrl / classlist_total, NA_real_
        ),
        scheduled_sections = as.integer(scheduled_sections),
        scheduled_capacity = as.numeric(scheduled_capacity),
        prior_classlist_total, prior_scheduled_capacity,
        classlist_change, capacity_change,
        first_day_fill = capacity_fill,
        first_day_capacity_gap = capacity_gap,
        capacity_usable, capacity_reached,
        method_id = projection$method_id,
        method_label = projection$method_label,
        aftcast_method_id,
        aftcast_method_label,
        aftcast_applicable = dplyr::coalesce(aftcast_applicable, FALSE),
        aftcast_reason = dplyr::coalesce(
          aftcast_reason, projection$applicability_reason
        ),
        aftcast_classlist_total,
        aftcast_error = aftcast_classlist_total - actual_classlist_total,
        aftcast_pct_error = dplyr::if_else(
          actual_classlist_total > 0,
          aftcast_error / actual_classlist_total,
          NA_real_
        ),
        aftcast_capacity_censored,
        aftcast_censored_error,
        aftcast_censored_pct_error,
        potential_miss_explanation = dplyr::case_when(
          !aftcast_applicable | !is.finite(aftcast_classlist_total) ~
            "No comparable aftcast",
          dplyr::coalesce(aftcast_capacity_censored, FALSE) ~
            paste(
              "First-day enrollment reached scheduled capacity; observed demand",
              "is a lower bound rather than a complete error measurement"
            ),
          is.finite(aftcast_pct_error) & abs(aftcast_pct_error) <= 0.10 ~
            "Aftcast was within 10% of observed class-list enrollment",
          is.finite(classlist_change) & is.finite(capacity_change) &
            abs(capacity_change) >= 0.10 & abs(classlist_change) >= 0.08 &
            sign(classlist_change) == sign(capacity_change) ~ paste0(
              "Potential contributor: enrollment moved ",
              sprintf("%+.1f%%", 100 * classlist_change),
              " as scheduled capacity moved ",
              sprintf("%+.1f%%", 100 * capacity_change)
            ),
          is.finite(classlist_change) & abs(classlist_change) >= 0.15 ~ paste0(
            "Potential contributor: enrollment changed ",
            sprintf("%+.1f%%", 100 * classlist_change),
            " from the prior same-season term"
          ),
          TRUE ~
            "No measured enrollment or capacity shift explains this miss"
        )
      )
  }))
  if (nrow(rows) == 0L) return(empty_projection_recent_history())

  # CAMPUS_ROLLUP: market_id is the explicit pooled ABQ+EA planning market;
  # recent rows rank terms within that named market, not within a campus.
  rows %>%
    attach_projection_movement_signals(
      student_inputs = student_inputs,
      graded_through_term = graded_through_term
    ) %>%
    dplyr::group_by(market_id, subject_course, projection_target_term) %>%
    dplyr::arrange(dplyr::desc(history_term), .by_group = TRUE) %>%
    dplyr::mutate(recency_rank = dplyr::row_number(), .after = history_term_label) %>%
    dplyr::ungroup()
}


empty_projection_recent_campus_history <- function() {
  tibble::tibble(
    market_id = character(), subject_course = character(),
    projection_target_term = integer(), history_term = integer(),
    recency_rank = integer(), campus = character(),
    scheduled_sections = integer(), scheduled_capacity = numeric(),
    first_day_enrl = numeric(), first_day_basis = character(),
    first_day_fill = numeric()
  )
}


# The recent history's terms again, one row per delivery campus that offered
# the course: its own sections, seats and first day. The forecast pools the
# market, so a campus full on the first day can hide behind one with room
# (ISSUES.md M36). Fill is stored as arithmetic only; which fill counts as
# full is read live from the seat-fill levels where the rows are shown.
build_projection_recent_campus_history <- function(recent_history,
                                                   delivery_section_history,
                                                   delivery_first_day) {
  projection_require_columns(
    delivery_section_history,
    c("campus", "subject_course", "term", "scheduled_sections",
      "scheduled_capacity"),
    "build_projection_recent_campus_history() sections"
  )
  projection_require_columns(
    delivery_first_day,
    c("campus", "subject_course", "term", "first_day_enrl", "first_day_basis"),
    "build_projection_recent_campus_history() first day"
  )
  if (nrow(recent_history) == 0L) return(empty_projection_recent_campus_history())
  seats <- delivery_section_history %>%
    dplyr::group_by(campus, subject_course, term) %>%
    dplyr::summarise(
      scheduled_sections = as.integer(sum(scheduled_sections)),
      scheduled_capacity = if (all(is.finite(scheduled_capacity))) {
        sum(scheduled_capacity)
      } else {
        NA_real_
      },
      .groups = "drop"
    )
  rows <- recent_history %>%
    dplyr::distinct(
      market_id, subject_course, projection_target_term, history_term,
      recency_rank
    ) %>%
    dplyr::inner_join(
      seats, by = c("subject_course", "history_term" = "term"),
      relationship = "one-to-many"
    ) %>%
    dplyr::left_join(
      delivery_first_day,
      by = c("campus", "subject_course", "history_term" = "term"),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(
      # A campus whose sections have no class-list rows has no first day.
      first_day_basis = dplyr::coalesce(first_day_basis, "no_classlist")
    )
  fill <- projection_capacity_metrics(rows$first_day_enrl, rows$scheduled_capacity)
  rows %>%
    dplyr::mutate(first_day_fill = fill$capacity_fill) %>%
    dplyr::select(dplyr::all_of(names(empty_projection_recent_campus_history()))) %>%
    dplyr::arrange(subject_course, projection_target_term, recency_rank, campus)
}
