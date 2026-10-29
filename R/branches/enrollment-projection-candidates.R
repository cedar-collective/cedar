# The candidate methods: prior same-season (the spine) and the spine plus a
# saturation floor and the term-just-finished deltas, with the row helpers
# they share and the check that an adjusted row's parts sum.

projection_history_for_row <- function(history, row, before_term = NULL) {
  result <- history %>%
    dplyr::filter(
      market_id == row$market_id,
      subject_course == row$subject_course,
      term_type == row$term_type
    )
  if (!is.null(before_term)) result <- dplyr::filter(result, term < before_term)
  dplyr::arrange(result, term)
}


projection_section_history_for_row <- function(history, row, before_term = NULL) {
  result <- history %>%
    dplyr::filter(
      market_id == row$market_id,
      subject_course == row$subject_course,
      term_type == row$term_type
    )
  if (!is.null(before_term)) result <- dplyr::filter(result, term < before_term)
  dplyr::arrange(result, term)
}


# Share of the class-list total still holding a seat when classes began, over
# the latest prior same-season terms whose first day can be reconstructed. A
# term without status dates is skipped, not read as zero or as census.
projection_first_day_retention_for_row <- function(history, row, target_term,
                                                   opt = list()) {
  window <- as.integer(projection_option(opt, "first_day_retention_window"))
  min_terms <- as.integer(projection_named_course_value(
    row$subject_course,
    projection_option(opt, "course_first_day_retention_min_terms"),
    projection_option(opt, "first_day_retention_min_terms")
  ))
  prior <- projection_history_for_row(
    history, row, before_term = target_term
  ) %>%
    dplyr::filter(classlist_total > 0, is.finite(first_day_enrl)) %>%
    dplyr::slice_tail(n = window)
  rate <- if (nrow(prior) >= min_terms && sum(prior$classlist_total) > 0) {
    sum(prior$first_day_enrl) / sum(prior$classlist_total)
  } else {
    NA_real_
  }

  tibble::tibble(
    first_day_retention_rate = as.numeric(rate),
    first_day_retention_n_terms = as.integer(nrow(prior)),
    first_day_retention_terms = paste(prior$term, collapse = ","),
    first_day_retention_term_labels = paste(
      vapply(prior$term, fmt_term, character(1)), collapse = ", "
    )
  )
}


# Whether a demand-minus-seats gap reaches the screen's minimum. A fitted trend
# carries floating-point noise that differs by platform: NATV 1150's
# c(109, 120, 122) fits exactly 130, which Linux computed as 130 and macOS as
# 129.99999999999997, so one seat gap included the course on one machine and
# not the other (ISSUES.md I34). A gap within that noise of the minimum meets it.
projection_seat_gap_reached <- function(gap, min_gap) {
  gap >= min_gap - sqrt(.Machine$double.eps)
}


projection_linear_estimate <- function(values) {
  values <- as.numeric(values)
  if (length(values) < 3 || any(!is.finite(values))) return(NA_real_)
  x <- seq_along(values)
  fit <- stats::lm(values ~ x)
  estimate <- stats::predict(
    fit,
    newdata = data.frame(x = length(values) + 1),
    se.fit = FALSE
  )
  max(0, as.numeric(estimate[[1]]))
}


projection_all_term_history_for_row <- function(history, row, before_term = NULL) {
  result <- history %>%
    dplyr::filter(
      market_id == row$market_id,
      subject_course == row$subject_course
    )
  if (!is.null(before_term)) result <- dplyr::filter(result, term < before_term)
  dplyr::arrange(result, term)
}


projection_candidate <- function(method_id, estimate = NA_real_, applicable = FALSE,
                                 reason = "Insufficient evidence",
                                 n_history_terms = 0L, evidence_n = 0L,
                                 n_components = 0L,
                                 component_summary = NA_character_,
                                 spine = NA_real_, spine_term = NA_integer_,
                                 saturated_prior = NA,
                                 prior_first_day_fill = NA_real_,
                                 prior_first_day_basis = NA_character_,
                                 waitlisted_prior = NA_integer_,
                                 floor_uplift = 0,
                                 floor_basis = NA_character_,
                                 preceding_term = NA_integer_,
                                 waitlisted_preceding = NA_integer_,
                                 feeder_check = NA_character_,
                                 preceding_term_enrollment = NA_real_,
                                 preceding_term_change = NA_real_,
                                 regime_alarm = NA,
                                 delta_repeat = 0, repeat_rate = NA_real_,
                                 delta_sequence = 0,
                                 sequence_courses = NA_character_,
                                 sequence_change = NA_real_,
                                 delta_feeder = 0, feeder_rate = NA_real_,
                                 feeder_courses = NA_character_,
                                 feeder_change = NA_real_,
                                 feeder_change_rate = NA_real_,
                                 delta_basis = NA_character_,
                                 projection_formula = NA_character_) {
  tibble::tibble(
    method_id = method_id,
    method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[method_id]]),
    method_role = unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[[method_id]]),
    projected_classlist_total = as.numeric(estimate),
    first_day_retention_rate = NA_real_,
    first_day_retention_n_terms = 0L,
    first_day_retention_terms = NA_character_,
    first_day_retention_term_labels = NA_character_,
    projected_first_day_equivalent = NA_real_,
    applicable = isTRUE(applicable),
    applicability_reason = as.character(reason),
    n_history_terms = as.integer(n_history_terms),
    evidence_n = as.integer(evidence_n),
    n_components = as.integer(n_components),
    component_summary = as.character(component_summary),
    spine = as.numeric(spine),
    spine_term = as.integer(spine_term),
    saturated_prior = as.logical(saturated_prior),
    prior_first_day_fill = as.numeric(prior_first_day_fill),
    prior_first_day_basis = as.character(prior_first_day_basis),
    waitlisted_prior = as.integer(waitlisted_prior),
    floor_uplift = as.numeric(floor_uplift),
    floor_basis = as.character(floor_basis),
    preceding_term = as.integer(preceding_term),
    waitlisted_preceding = as.integer(waitlisted_preceding),
    feeder_check = as.character(feeder_check),
    preceding_term_enrollment = as.numeric(preceding_term_enrollment),
    preceding_term_change = as.numeric(preceding_term_change),
    regime_alarm = as.logical(regime_alarm),
    delta_repeat = as.numeric(delta_repeat),
    repeat_rate = as.numeric(repeat_rate),
    delta_sequence = as.numeric(delta_sequence),
    sequence_courses = as.character(sequence_courses),
    sequence_change = as.numeric(sequence_change),
    delta_feeder = as.numeric(delta_feeder),
    feeder_rate = as.numeric(feeder_rate),
    feeder_courses = as.character(feeder_courses),
    feeder_change = as.numeric(feeder_change),
    feeder_change_rate = as.numeric(feeder_change_rate),
    delta_basis = as.character(delta_basis),
    projection_formula = as.character(projection_formula)
  )
}


project_seasonal_last <- function(history, row, target_term, opt = list()) {
  prior <- projection_history_for_row(history, row, before_term = target_term) %>%
    dplyr::slice_tail(n = 1)

  if (nrow(prior) == 0) {
    return(projection_candidate(
      "seasonal_last", reason = "Needs one prior same-season term"
    ))
  }

  projection_candidate(
    "seasonal_last",
    estimate = prior$classlist_total[[1]],
    applicable = TRUE,
    reason = paste("Unique class-list registrants in prior", row$term_type, "term"),
    n_history_terms = 1L,
    evidence_n = prior$classlist_total[[1]],
    component_summary = paste(
      prior$term[[1]], prior$classlist_total[[1]], sep = ":"
    ),
    spine = prior$classlist_total[[1]],
    spine_term = as.integer(prior$term[[1]]),
    projection_formula = "prior same-season class-list total"
  )
}


# ---- The spine / floor / delta model ------------------------------------------
#
# seats needed = spine + floor uplift + repeat delta + feeder delta
#
#   spine          prior same-season class-list demand (the default itself)
#   floor uplift   if that term was saturated (first-day fill >= 90%), the
#                  students still waiting at close who never held a seat; the
#                  spine already counts everyone who registered, so demand was
#                  at least spine + those students
#   repeat delta   change in the course's own enrollment in the term just
#                  finished, times the share of those students who historically
#                  took the course again the following same-season term
#   feeder delta   change in distinct enrollment across the course's feeder
#                  courses in the term just finished, times the share of feeder
#                  students who historically took the course next term
#
# Why this shape: 77% of the Spring 2027 aftcast error sat in terms where the
# schedule moved, and the Spring roster decomposes into 86% continuing
# students, 7% new entrants, 5% repeaters after a Fall DFW, 2% returners. The
# spine already carries the steady state of all four; the adjustments move it
# only where a Fall driver measurably changed or where the prior count was
# clipped by the seats offered. Grades are not posted when the schedule is
# built, so both deltas read enrollments; the rates they are scaled by embed
# the historical pass and repeat behaviour.


projection_spine_floor <- function(spine_row, section_history, waitlist_history,
                                   row, opt = list()) {
  threshold <- as.numeric(projection_option(opt, "saturation_fill_threshold"))
  spine_term <- as.integer(spine_row$term[[1]])
  spine <- spine_row$classlist_total[[1]]
  capacity <- projection_section_history_for_row(section_history, row) %>%
    dplyr::filter(term == spine_term) %>%
    dplyr::slice_head(n = 1)
  capacity_value <- if (nrow(capacity) == 0) NA_real_ else
    capacity$scheduled_capacity[[1]]
  projection_require_columns(
    spine_row, c("first_day_enrl", "first_day_started_enrl", "first_day_basis"),
    "projection_spine_floor()"
  )
  # A term whose later sessions had not begun at the pull is judged on the
  # sections that had, when they alone settle it (ISSUES.md I28).
  first_day_basis <- spine_row$first_day_basis[[1]]
  first_day <- projection_judged_first_day(
    spine_row$first_day_enrl[[1]], spine_row$first_day_started_enrl[[1]],
    first_day_basis, capacity_value, threshold
  )
  partial <- !is.finite(spine_row$first_day_enrl[[1]]) && is.finite(first_day)
  # How the prior first day was read, as a code for flags: "complete",
  # "sessions_begun" (judged on the lower bound), "sessions_pending",
  # "undated", or "no_capacity".
  read_as <- if (partial) "sessions_begun" else as.character(first_day_basis)
  fill_text <- function(fill) paste0(
    "first-day fill ", if (partial) "at least " else "",
    scales::percent(fill, accuracy = 0.1),
    if (partial) ", from the sessions that had begun when the class list was pulled" else ""
  )
  saturation <- enrollment_capacity_metrics(
    first_day, capacity_value, constrained_threshold = threshold
  )
  waiting <- waitlist_history %>%
    dplyr::filter(
      market_id == row$market_id, subject_course == row$subject_course,
      term == spine_term
    )
  waitlisted <- if (nrow(waiting) == 0) 0L else as.integer(waiting$waitlisted[[1]])
  saturated <- isTRUE(saturation$capacity_constrained[[1]])

  if (!is.finite(first_day)) {
    started_fill <- spine_row$first_day_started_enrl[[1]] / capacity_value
    basis <- if (identical(first_day_basis, "sessions_pending")) {
      paste0(
        "Some of ", fmt_term(spine_term), "'s sessions had not begun when its ",
        "class list was pulled, so its first day is not yet complete",
        if (is.finite(started_fill)) paste0(
          "; the sessions that had begun fill ",
          scales::percent(started_fill, accuracy = 0.1), " of its seats, short of the ",
          scales::percent(threshold, accuracy = 1), " that would settle saturation"
        ) else ""
      )
    } else {
      paste0(
        fmt_term(spine_term), "'s class lists carry no registration status ",
        "dates, so its first day cannot be counted and saturation cannot be ",
        "judged; re-pulling that term's class list restores it"
      )
    }
    return(list(
      saturated = NA, fill = NA_real_, waitlisted = waitlisted, uplift = 0,
      basis = basis, first_day_basis = read_as
    ))
  }
  if (!isTRUE(saturation$capacity_usable[[1]])) {
    return(list(
      saturated = NA, fill = saturation$fill_rate[[1]], waitlisted = waitlisted,
      uplift = 0,
      basis = paste("No usable capacity for", fmt_term(spine_term),
                    "so saturation cannot be judged"),
      first_day_basis = "no_capacity"
    ))
  }
  if (!saturated) {
    return(list(
      saturated = FALSE, fill = saturation$fill_rate[[1]],
      waitlisted = waitlisted, uplift = 0,
      basis = paste0(
        fmt_term(spine_term), " was not saturated (",
        fill_text(saturation$fill_rate[[1]]), ")"
      ),
      first_day_basis = read_as
    ))
  }
  # The floor is in the spine's units: the ever-registered total plus the
  # waiting students, none of whom is on the market class list. Adding the
  # waitlist to first-day enrollment instead let the term's early-drop churn
  # absorb it, so 245 waiting students lifted Fall 2027 by 77 (ISSUES.md I27).
  floor_demand <- spine + waitlisted
  list(
    saturated = TRUE, fill = saturation$fill_rate[[1]], waitlisted = waitlisted,
    uplift = as.numeric(waitlisted), first_day_basis = read_as,
    basis = paste0(
      fmt_term(spine_term), " was saturated (",
      fill_text(saturation$fill_rate[[1]]), "); ",
      if (waitlisted > 0) {
        paste0("floor is spine ", round(spine), " + ", waitlisted,
               " still waiting = ", round(floor_demand))
      } else {
        "no waitlist rows retained for that term, so the floor is the spine itself"
      }
    )
  )
}


# Historical carry-through rates for the deltas (repeat, each listed sequence,
# pooled feeders), learned only from pairs (preceding term p, following
# same-season term s) with s before the target.
projection_delta_rates <- function(student_inputs, row, target_term,
                                   opt = list()) {
  window <- as.integer(projection_option(opt, "delta_pairs_window"))
  min_pairs <- as.integer(projection_option(opt, "delta_min_pairs"))
  max_feeders <- as.integer(projection_option(opt, "feeder_max_courses"))
  min_students <- as.integer(projection_option(opt, "feeder_min_students"))
  course <- row$subject_course
  enrollments <- student_inputs$course_enrollments
  targets <- student_inputs$target_students %>%
    dplyr::filter(subject_course == course)
  sequences <- projection_option(opt, "sequences")
  predecessors <- setdiff(
    sort(unique(sequences$from_course[sequences$to_course == course])), course
  )
  empty <- list(
    n_pairs = 0L, repeat_rate = NA_real_, feeder_rate = NA_real_,
    feeders = character(0), pairs = integer(0),
    sequence = tibble::tibble(course = predecessors, rate = NA_real_)
  )
  if (is.null(enrollments) || nrow(enrollments) == 0L || nrow(targets) == 0L) {
    return(empty)
  }

  season_terms <- targets %>%
    dplyr::filter(term < target_term,
                  vapply(term, get_term_type, character(1)) == row$term_type) %>%
    dplyr::distinct(term) %>%
    dplyr::arrange(term) %>%
    dplyr::pull(term)
  season_terms <- utils::tail(season_terms, window)
  pairs <- tibble::tibble(
    following = as.integer(season_terms),
    preceding = vapply(season_terms, subtract_term, integer(1), summer = FALSE)
  ) %>%
    dplyr::filter(preceding %in% enrollments$term)
  if (nrow(pairs) < min_pairs) return(utils::modifyList(empty, list(n_pairs = nrow(pairs))))

  preceding_rows <- enrollments %>%
    dplyr::inner_join(pairs, by = c("term" = "preceding"))
  following_rows <- targets %>%
    dplyr::inner_join(pairs, by = c("term" = "following")) %>%
    dplyr::transmute(student_id, following = term, took_next = TRUE) %>%
    dplyr::distinct()

  # Repeat rate: students in the course in p who are in it again in s.
  in_course <- preceding_rows %>%
    dplyr::filter(subject_course == course) %>%
    dplyr::distinct(student_id, following) %>%
    dplyr::left_join(following_rows, by = c("student_id", "following"))
  repeat_rate <- if (nrow(in_course) == 0L) NA_real_ else
    mean(dplyr::coalesce(in_course$took_next, FALSE))

  # Listed predecessors (projection_sequences.csv): each its own rate, the
  # share of its p students who took this course in s. A predecessor's students
  # then leave the pooled feeders, so none is counted twice.
  sequence_rates <- vapply(predecessors, function(predecessor) {
    pool <- preceding_rows %>%
      dplyr::filter(subject_course == predecessor) %>%
      dplyr::distinct(student_id, following) %>%
      dplyr::left_join(following_rows, by = c("student_id", "following"))
    if (nrow(pool) == 0L) NA_real_ else mean(dplyr::coalesce(pool$took_next, FALSE))
  }, numeric(1))
  in_sequence <- preceding_rows %>%
    dplyr::filter(subject_course %in% predecessors) %>%
    dplyr::distinct(student_id, following)
  pooled_rows <- dplyr::anti_join(
    preceding_rows, in_sequence, by = c("student_id", "following")
  )

  # Feeders: the courses whose p students most often took this course in s,
  # excluding the course itself. Then one pooled rate across the feeder set so
  # a student in two feeders counts once.
  # CAMPUS_ROLLUP: course_enrollments is already deduplicated across the named
  # planning market, so a feeder is counted once per student whichever campus
  # delivered it; a campus split here would double-count cross-campus students.
  transitions <- pooled_rows %>%
    dplyr::filter(subject_course != course) %>%
    dplyr::distinct(student_id, following, subject_course) %>%
    dplyr::inner_join(following_rows, by = c("student_id", "following")) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::summarise(
      n_transition = dplyr::n(), n_pairs = dplyr::n_distinct(following),
      .groups = "drop"
    ) %>%
    dplyr::filter(n_transition >= min_students, n_pairs >= min_pairs) %>%
    dplyr::arrange(dplyr::desc(n_transition), subject_course) %>%
    dplyr::slice_head(n = max_feeders)
  feeders <- transitions$subject_course
  feeder_rate <- if (length(feeders) == 0L) NA_real_ else {
    pool <- pooled_rows %>%
      dplyr::filter(subject_course %in% feeders) %>%
      dplyr::distinct(student_id, following) %>%
      dplyr::left_join(following_rows, by = c("student_id", "following"))
    mean(dplyr::coalesce(pool$took_next, FALSE))
  }

  list(
    n_pairs = nrow(pairs), repeat_rate = repeat_rate, feeder_rate = feeder_rate,
    feeders = feeders, pairs = pairs$following,
    sequence = tibble::tibble(course = predecessors, rate = unname(sequence_rates))
  )
}


# Distinct students enrolled in any of `courses` in `term`, excluding those in
# any of `exclude_courses` that term, from the market's deduplicated course
# enrollments.
projection_distinct_enrolled <- function(enrollments, term, courses,
                                         exclude_courses = NULL) {
  rows <- enrollments %>%
    dplyr::filter(term == .env$term, subject_course %in% courses)
  if (length(exclude_courses) > 0L) {
    excluded <- enrollments %>%
      dplyr::filter(term == .env$term, subject_course %in% exclude_courses) %>%
      dplyr::distinct(student_id)
    rows <- dplyr::anti_join(rows, excluded, by = "student_id")
  }
  dplyr::n_distinct(rows$student_id)
}


# Students left waiting in the term just finished who are on no class list
# for the course in the market: context for the plan, never added to it,
# because how many register next term cannot be measured until that term's
# class lists arrive. NA, not zero, when that term is not observed or no
# monitored course retained a waitlist row in it (class lists keep them only
# from Summer 2026).
projection_preceding_waitlist <- function(waitlist_history, row, preceding_term,
                                          observed) {
  if (!isTRUE(observed)) return(NA_integer_)
  term_rows <- waitlist_history %>%
    dplyr::filter(market_id == row$market_id, term == as.integer(preceding_term))
  if (nrow(term_rows) == 0L) return(NA_integer_)
  own <- term_rows %>% dplyr::filter(subject_course == row$subject_course)
  if (nrow(own) == 0L) 0L else as.integer(own$waitlisted[[1]])
}


project_spine_adjusted <- function(history, preceding_term_history,
                                   section_history, waitlist_history,
                                   student_inputs, row, target_term,
                                   opt = list()) {
  target_term <- as.integer(target_term)
  alarm_threshold <- as.numeric(projection_option(opt, "regime_alarm_threshold"))
  spine_row <- projection_history_for_row(history, row, before_term = target_term) %>%
    dplyr::slice_tail(n = 1)
  if (nrow(spine_row) == 0) {
    return(projection_candidate(
      "spine_adjusted", reason = "Needs one prior same-season term"
    ))
  }
  spine <- spine_row$classlist_total[[1]]
  spine_term <- as.integer(spine_row$term[[1]])
  floor <- projection_spine_floor(
    spine_row, section_history, waitlist_history, row, opt
  )

  # Deltas need the term immediately before the target to be observed.
  preceding_term <- subtract_term(target_term, summer = FALSE)
  prior_preceding_term <- subtract_term(
    subtract_term(preceding_term, summer = FALSE), summer = FALSE
  )
  all_terms <- projection_all_term_history_for_row(
    preceding_term_history, row, before_term = target_term
  )
  now_row <- all_terms %>% dplyr::filter(term == preceding_term)
  then_row <- all_terms %>% dplyr::filter(term == prior_preceding_term)
  enrollments <- student_inputs$course_enrollments %||% NULL
  preceding_observed <- nrow(now_row) == 1L &&
    !is.null(enrollments) && preceding_term %in% enrollments$term

  delta_repeat <- 0
  delta_sequence <- 0
  delta_feeder <- 0
  repeat_rate <- NA_real_
  feeder_rate <- NA_real_
  feeders <- character(0)
  sequence_courses <- character(0)
  sequence_change <- NA_real_
  feeder_change <- NA_real_
  feeder_change_rate <- NA_real_
  change <- NA_real_
  preceding_enrollment <- if (nrow(now_row) == 1L) now_row$classlist_total[[1]] else NA_real_
  delta_basis <- if (!preceding_observed) {
    paste("Preceding term", fmt_term(preceding_term),
          "is not observed yet; no Fall deltas")
  } else if (nrow(then_row) != 1L) {
    paste("No", fmt_term(prior_preceding_term),
          "enrollment to measure the change against; no Fall deltas")
  } else {
    rates <- projection_delta_rates(student_inputs, row, target_term, opt)
    then_enrollment <- then_row$classlist_total[[1]]
    change <- if (then_enrollment > 0) preceding_enrollment / then_enrollment - 1 else NA_real_
    repeat_rate <- rates$repeat_rate
    feeder_rate <- rates$feeder_rate
    feeders <- rates$feeders
    parts <- character(0)
    if (is.finite(repeat_rate)) {
      delta_repeat <- (preceding_enrollment - then_enrollment) * repeat_rate
      parts <- c(parts, paste0(
        "repeat: (", preceding_enrollment, " - ", then_enrollment, ") x ",
        round(repeat_rate, 3), " = ", sprintf("%+.1f", delta_repeat)
      ))
    } else {
      parts <- c(parts, paste0(
        "repeat: no carry-through rate from ", rates$n_pairs, " prior pairs"
      ))
    }
    # A listed predecessor carries its own change at its own rate.
    sequence <- rates$sequence %>% dplyr::filter(is.finite(rate))
    if (nrow(sequence) > 0L) {
      sequence_courses <- sequence$course
      counts <- vapply(sequence$course, function(predecessor) {
        c(
          now = projection_distinct_enrolled(
            enrollments, preceding_term, predecessor, row$subject_course
          ),
          then = projection_distinct_enrolled(
            enrollments, prior_preceding_term, predecessor, row$subject_course
          )
        )
      }, numeric(2))
      changes <- counts["now", ] - counts["then", ]
      sequence_change <- sum(changes)
      delta_sequence <- sum(changes * sequence$rate)
      parts <- c(parts, paste0(
        "sequence ", sequence$course, ": (", counts["now", ], " - ",
        counts["then", ], ") x ", round(sequence$rate, 3), " = ",
        sprintf("%+.1f", changes * sequence$rate)
      ))
    }
    if (is.finite(feeder_rate) && length(feeders) > 0L) {
      # Students in a listed predecessor are counted there, not here.
      feeder_now <- projection_distinct_enrolled(
        enrollments, preceding_term, feeders,
        c(row$subject_course, sequence_courses)
      )
      feeder_then <- projection_distinct_enrolled(
        enrollments, prior_preceding_term, feeders,
        c(row$subject_course, sequence_courses)
      )
      feeder_change <- feeder_now - feeder_then
      feeder_change_rate <- if (feeder_then > 0) feeder_change / feeder_then else NA_real_
      delta_feeder <- feeder_change * feeder_rate
      parts <- c(parts, paste0(
        "feeders (", paste(feeders, collapse = ", "), "): (", feeder_now,
        " - ", feeder_then, ") x ", round(feeder_rate, 3), " = ",
        sprintf("%+.1f", delta_feeder)
      ))
    } else {
      parts <- c(parts, "feeders: none met the evidence threshold")
    }
    paste(parts, collapse = "; ")
  }
  # Why a feeder change is or is not available, for the plan's feeder
  # adjustment note.
  feeder_check <- if (is.null(enrollments) || !preceding_term %in% enrollments$term) {
    "term_not_observed"
  } else if (!preceding_observed || nrow(then_row) != 1L) {
    "no_course_baseline"
  } else if (length(feeders) == 0L || !is.finite(feeder_rate)) {
    "no_feeders"
  } else if (is.finite(feeder_change_rate)) {
    "measured"
  } else {
    "unmeasurable"
  }
  # Unknown when the preceding term is unobserved; never FALSE by default.
  regime_alarm <- if (is.finite(change)) abs(change) >= alarm_threshold else NA
  waitlisted_preceding <- projection_preceding_waitlist(
    waitlist_history, row, preceding_term,
    observed = !is.null(enrollments) && preceding_term %in% enrollments$term
  )

  estimate <- max(0, spine + floor$uplift + delta_repeat + delta_sequence + delta_feeder)
  projection_candidate(
    "spine_adjusted",
    estimate = estimate,
    applicable = TRUE,
    reason = paste0(
      "Prior same-season ", spine, " + floor ", round(floor$uplift),
      " + repeat delta ", sprintf("%+.1f", delta_repeat),
      if (length(sequence_courses) > 0L) {
        paste0(" + sequence delta ", sprintf("%+.1f", delta_sequence))
      } else "",
      " + feeder delta ", sprintf("%+.1f", delta_feeder)
    ),
    n_history_terms = 1L,
    evidence_n = spine,
    n_components = 1L + (floor$uplift > 0) + (delta_repeat != 0) +
      (delta_sequence != 0) + (delta_feeder != 0),
    component_summary = paste(floor$basis, delta_basis, sep = "; "),
    spine = spine,
    spine_term = spine_term,
    saturated_prior = floor$saturated,
    prior_first_day_fill = floor$fill,
    prior_first_day_basis = floor$first_day_basis,
    waitlisted_prior = floor$waitlisted,
    floor_uplift = floor$uplift,
    floor_basis = floor$basis,
    preceding_term = preceding_term,
    waitlisted_preceding = waitlisted_preceding,
    feeder_check = feeder_check,
    preceding_term_enrollment = preceding_enrollment,
    preceding_term_change = change,
    regime_alarm = regime_alarm,
    delta_repeat = delta_repeat,
    repeat_rate = repeat_rate,
    delta_sequence = delta_sequence,
    sequence_courses = if (length(sequence_courses) == 0L) NA_character_ else
      paste(sequence_courses, collapse = ", "),
    sequence_change = sequence_change,
    delta_feeder = delta_feeder,
    feeder_rate = feeder_rate,
    feeder_courses = if (length(feeders) == 0L) NA_character_ else
      paste(feeders, collapse = ", "),
    feeder_change = feeder_change,
    feeder_change_rate = feeder_change_rate,
    delta_basis = delta_basis,
    projection_formula = "spine + floor uplift + repeat delta + sequence delta + feeder delta"
  )
}


project_course_method_candidates <- function(inputs, row, target_term,
                                             opt = list()) {
  method_ids <- as.character(
    projection_option(opt, "projection_methods")
  )
  unknown <- setdiff(method_ids, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
  if (length(unknown) > 0) {
    stop(
      "[enrollment-projection-candidates.R] Unknown projection method(s): ",
      paste(unknown, collapse = ", "), call. = FALSE
    )
  }
  builders <- list(
    seasonal_last = function() {
      project_seasonal_last(inputs$enrollment_history, row, target_term, opt)
    },
    spine_adjusted = function() {
      project_spine_adjusted(
        inputs$enrollment_history, inputs$preceding_term_history,
        inputs$section_history, inputs$waitlist_history, inputs$students,
        row, target_term, opt
      )
    }
  )
  candidates <- dplyr::bind_rows(lapply(method_ids, function(id) builders[[id]]()))
  retention <- projection_first_day_retention_for_row(
    inputs$enrollment_history, row, target_term, opt
  )

  candidates %>%
    dplyr::mutate(
      market_id = row$market_id,
      college = row$college,
      subject_course = row$subject_course,
      term_type = row$term_type,
      target_term = as.integer(target_term),
      target_term_label = fmt_term(as.integer(target_term)),
      .before = 1
    ) %>%
    dplyr::mutate(
      first_day_retention_rate = retention$first_day_retention_rate[[1]],
      first_day_retention_n_terms = retention$first_day_retention_n_terms[[1]],
      first_day_retention_terms = retention$first_day_retention_terms[[1]],
      first_day_retention_term_labels = retention$first_day_retention_term_labels[[1]],
      projected_first_day_equivalent =
        projected_classlist_total * first_day_retention_rate
    )
}


# Every applicable adjusted row must reconcile: spine + floor + deltas is the
# raw projection (floored at zero), the spine term precedes the target, and
# the floor is exactly the waiting students when the prior term was saturated
# and zero otherwise, so it stays in the spine's units (ISSUES.md I27).
validate_spine_rows <- function(data, caller) {
  if (nrow(data) == 0 || !"method_id" %in% names(data)) return(invisible(TRUE))
  rows <- data %>%
    dplyr::filter(method_id == "spine_adjusted", applicable)
  if (nrow(rows) == 0) return(invisible(TRUE))
  projection_require_columns(
    rows,
    c("target_term", "projected_classlist_total", "spine", "spine_term",
      "floor_uplift", "saturated_prior", "waitlisted_prior", "delta_repeat",
      "delta_sequence", "delta_feeder"),
    caller
  )
  floor_expected <- ifelse(
    rows$saturated_prior %in% TRUE, as.numeric(rows$waitlisted_prior), 0
  )
  raw <- if ("raw_projected_classlist_total" %in% names(rows)) {
    rows$raw_projected_classlist_total
  } else {
    rows$projected_classlist_total
  }
  expected <- pmax(
    0, rows$spine + rows$floor_uplift + rows$delta_repeat +
      rows$delta_sequence + rows$delta_feeder
  )
  valid <- is.finite(rows$spine) & rows$spine_term < rows$target_term &
    is.finite(floor_expected) & floor_expected >= 0 &
    abs(rows$floor_uplift - floor_expected) <= 1e-6 &
    is.finite(raw) & abs(raw - expected) <= 1e-6
  if (any(!valid)) {
    stop(
      "[enrollment-projection-candidates.R] ", caller,
      " has an invalid spine / floor / delta audit trail.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
