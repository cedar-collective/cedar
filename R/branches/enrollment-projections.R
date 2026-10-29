


# Reusable enrollment-projection computations: settings, shared helpers and
# the output schemas. The stages live beside it, one file each: inputs,
# candidates, context, backtests, history, plan, error-sources and bundle
# (enrollment-projection-*.R). None reads global data or Shiny state.

projection_course_group_courses <- function(group_id) {
  group <- CEDAR_ENROLLMENT_PROJECTION_GROUPS[[group_id]]
  if (is.null(group)) {
    stop("[enrollment-projections.R] Unknown projection course group: ", group_id,
         call. = FALSE)
  }
  unname(group$courses)
}


projection_course_group_campuses <- function(group_id) {
  group <- CEDAR_ENROLLMENT_PROJECTION_GROUPS[[group_id]]
  if (is.null(group)) {
    stop("[enrollment-projections.R] Unknown projection course group: ", group_id,
         call. = FALSE)
  }
  unname(group$campuses)
}


projection_course_group_always_monitored_courses <- function(group_id) {
  group <- CEDAR_ENROLLMENT_PROJECTION_GROUPS[[group_id]]
  if (is.null(group)) {
    stop("[enrollment-projections.R] Unknown projection course group: ", group_id,
         call. = FALSE)
  }
  unname(group$always_monitored_courses %||% character(0))
}


projection_course_group_market_id <- function(group_id) {
  group <- CEDAR_ENROLLMENT_PROJECTION_GROUPS[[group_id]]
  if (is.null(group)) {
    stop("[enrollment-projections.R] Unknown projection course group: ", group_id,
         call. = FALSE)
  }
  unname(group$market_id)
}


#' Every model option's default, in one place
#'
#' enrollment_projection_model_config() starts from this list, and helpers read
#' an option a caller did not set through projection_option(), so no call site
#' restates a default that could drift from this one.
enrollment_projection_defaults <- function() {
  list(
    history_start_term = CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM,
    course_history_start_terms =
      CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS,
    recent_history_terms = 4L,
    projection_methods = names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
    summer = FALSE,
    pressure_min_seat_gap = 10,
    pressure_fill_threshold = CEDAR_NEAR_FULL_FILL,
    pressure_chronic_terms = 2L,
    pressure_history_window = 3L,
    backtest_terms = 6L,
    registration_capacity_threshold = CEDAR_FULL_FILL,
    # Parts of term left out of every input (0.24.0); see
    # prepare_enrollment_projection_inputs().
    intersession_parts_of_term = CEDAR_INTERSESSION_PARTS_OF_TERM,
    capacity_explained_share_threshold = 0.50,
    first_day_retention_window = 4L,
    first_day_retention_min_terms = 2L,
    course_first_day_retention_min_terms =
      CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS,
    # Spine / floor / delta model (0.20.0).
    #
    # The spine is prior same-season class-list demand. The floor applies when
    # that term was saturated (first-day fill at or above
    # saturation_fill_threshold): demand is then at least the spine plus the
    # distinct students left waiting who are on no campus's class list in the
    # market, because the observed count was clipped by the seats offered
    # (0.22.0; ISSUES.md I27). Seats are judged on the first
    # day, not at census: three weeks of drops (census is the 15th day of
    # instruction; the term calendar in AGENTS.md) let a course full on day
    # one read 95% at census (0.21.0). The two deltas read the term immediately
    # before the target -- the course's own enrollment change and its feeder
    # courses' enrollment change -- each scaled by the share that historically
    # carried into this course the following same-season term. Enrollment, not
    # grades: grades are not posted when the schedule is built.
    saturation_fill_threshold = CEDAR_NEAR_FULL_FILL,
    delta_pairs_window = 4L,
    delta_min_pairs = 2L,
    feeder_max_courses = 8L,
    feeder_min_students = 3L,
    # Context, not a multiplier: among same-season pairs whose prior term was
    # saturated and whose capacity grew by at least expansion_capacity_change,
    # what share of the added seats filled. Needs expansion_min_pairs.
    expansion_capacity_change = 0.10,
    expansion_min_pairs = 5L,
    # Pressure bump (0.23.0): a planning allowance, not a forecast. A course
    # near full on the first day (saturation_fill_threshold) in every one of
    # its last pressure_bump_window same-season offerings with a known first
    # day -- at least pressure_bump_min_terms of them -- is planned for
    # pressure_bump_share more registrations than last time, or for the
    # students left waiting if that is more. A near-full course's
    # registrations follow its seats: given 10% or more seats they filled them
    # (median 100%, 89 course-terms), held flat they stayed flat (139), cut
    # they fell by the cut (51). The forecast and its accuracy are untouched,
    # because a full course's registrations are capped and cannot score an
    # allowance for the demand it turned away. 5% from 0.26.0: the median
    # always-full Fall 2026 course left 4.7% of its registrations waiting, and
    # a course with more waiting is sized by its waitlist.
    pressure_bump_share = 0.05,
    pressure_bump_window = 3L,
    pressure_bump_min_terms = 2L,
    # Feeder plan (0.26.0): the pooled feeders' change moves the plan only
    # when it is plan_feeder_change or more either way; a listed sequence's
    # change always does. Neither is added when the published projection
    # already includes the deltas.
    plan_feeder_change = 0.05,
    # Only targets in these seasons follow their feeders (0.27.0). Scored on
    # past forecasts, size-weighted error: Spring 14.7% for the spine alone,
    # 13.6% following sequences and feeders; Fall 12.8% and 13.0%. A Spring
    # feeder change pointed the way the Fall course moved no more often than
    # chance (correlation -0.09), and ENGL 1110's pointed the wrong way for
    # ENGL 1120 in two of three Falls.
    plan_feeder_seasons = "spring",
    # Course sequences (projection_sequences.csv): from_course, to_course.
    sequences = CEDAR_ENROLLMENT_PROJECTION_SEQUENCES,
    # Seat consistency (0.23.0): over the past forecast terms behind a
    # course's reliability, how often its scheduled seats moved by
    # seat_consistency_change or more from the previous same-season offering.
    # None is High, up to seat_consistency_moderate_max_moves is Moderate,
    # more is Low. A seat move alone does not say whose a miss was: that is
    # read per past forecast term, from whether the course was near full
    # (projection_fold_miss_cause(); ISSUES.md I40).
    seat_consistency_change = 0.10,
    seat_consistency_moderate_max_moves = 1L,
    # Students left waiting in the term just finished (schema 26) are context,
    # never added to the plan. A course is flagged when they would fill at
    # least this share of one section.
    preceding_waiting_flag_sections = 0.5,
    regime_alarm_threshold = 0.25,
    # Rolling selection: prior same-season is the default. A challenger
    # replaces it for a target only when, on at least selection_min_backtests
    # earlier aftcast terms both methods share, the challenger's WAPE was lower
    # by at least selection_challenger_margin. The same rule is replayed at
    # every historical fold, and the published accuracy is the error of the
    # method the rule would have picked there -- never the error of the winner
    # on the folds that crowned it. On the Spring 2027 audit (0.18.0) the
    # in-sample winner scored 13.7% while the same rule applied rolling scored
    # 16.5%, and prior same-season alone 15.9%.
    #
    # Three shared folds, not two. Replayed on the 0.19.0 Spring 2027 bundle
    # with two, 26 challengers were live on the 2026 fold and scored 11.4%
    # where the default scored 8.2% on the same courses; with three, the
    # rule's record equals the default's (14.9%). Two folds still pick noise.
    selection_min_backtests = 3L,
    selection_challenger_margin = 0.02,
    capacity_constrained_share = 0.50,
    # Three independent reader-facing axes (2026-09-07):
    #   stability -- is this course predictable from its own history at all?
    #                Measured with no model, from the comparable class-list
    #                series.
    #   depth     -- how many rolling-selection aftcasts stand behind the
    #                published row.
    #   accuracy  -- how close those aftcasts landed.
    stability_stable_max_cv = 0.10,
    stability_moderate_max_cv = 0.25,
    stability_min_terms = 3L,
    depth_deep_min_aftcasts = 4L,
    depth_moderate_min_aftcasts = 3L,
    accuracy_close_max_wape = 0.10,
    accuracy_fair_max_wape = 0.20,
    accuracy_min_aftcasts = 2L,
    demand_history_window = 5L,
    demand_recent_window = 3L,
    capacity_response_fraction = 0.50,
    demand_min_growth_per_year = 2,
    demand_min_growth_share = 0.02,
    disagreement_threshold = 0.20,
    recommendation_min_seat_gap = 10
  )
}


# "1 section", "2 sections": a whole count and its noun, for recommendations.
projection_count_noun <- function(n, noun) {
  paste(format(n, big.mark = ","), if (isTRUE(n == 1)) noun else paste0(noun, "s"))
}


#' One model option: the caller's value, else the model default
projection_option <- function(opt, name) {
  value <- opt[[name]]
  if (!is.null(value)) return(value)
  defaults <- enrollment_projection_defaults()
  if (!name %in% names(defaults)) {
    stop("[enrollment-projections.R] Unknown projection option: ", name, call. = FALSE)
  }
  defaults[[name]]
}


enrollment_projection_model_config <- function(opt = list()) {
  if (is.null(opt$history_start_term) && is.na(CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM)) {
    stop("[enrollment-projections.R] No history window: set projection_history_start_term ",
         "in institution/<id>/settings.csv or pass opt$history_start_term.", call. = FALSE)
  }
  # modifyList() merges nested lists, and a table is one: a caller's sequences
  # replace the default table whole rather than column by column.
  defaults <- enrollment_projection_defaults()
  config <- utils::modifyList(defaults, opt[setdiff(names(opt), "sequences")])
  config$sequences <- opt$sequences %||% defaults$sequences
  margin <- as.numeric(config$selection_challenger_margin)
  if (length(margin) != 1L || !is.finite(margin) || margin < 0) {
    stop(
      "[enrollment-projections.R] selection_challenger_margin must be a non-negative number.",
      call. = FALSE
    )
  }
  config$selection_challenger_margin <- margin
  saturation <- as.numeric(config$saturation_fill_threshold)
  if (length(saturation) != 1L || !is.finite(saturation) || saturation <= 0 ||
      saturation > 1.25) {
    stop(
      "[enrollment-projections.R] saturation_fill_threshold must be a fill rate between 0 and 1.25.",
      call. = FALSE
    )
  }
  config$saturation_fill_threshold <- saturation
  sequences <- config$sequences
  if (!is.data.frame(sequences) ||
      !all(c("from_course", "to_course") %in% names(sequences)) ||
      anyNA(sequences$from_course) || anyNA(sequences$to_course)) {
    stop(
      "[enrollment-projections.R] sequences must be a table of from_course and to_course.",
      call. = FALSE
    )
  }
  config$sequences <- tibble::tibble(
    from_course = as.character(sequences$from_course),
    to_course = as.character(sequences$to_course)
  )
  # Stops on anything but spring, summer or fall.
  projection_plan_feeder_seasons_rule(config$plan_feeder_seasons)
  for (field in c("pressure_bump_share", "plan_feeder_change")) {
    value <- as.numeric(config[[field]])
    if (length(value) != 1L || !is.finite(value) || value < 0 || value > 1) {
      stop("[enrollment-projections.R] ", field,
           " must be a share between 0 and 1.", call. = FALSE)
    }
    config[[field]] <- value
  }
  bump_window <- suppressWarnings(as.integer(config$pressure_bump_window))
  bump_min <- suppressWarnings(as.integer(config$pressure_bump_min_terms))
  if (length(bump_window) != 1L || length(bump_min) != 1L ||
      is.na(bump_window) || is.na(bump_min) || bump_min < 1L ||
      bump_window < bump_min) {
    stop(
      "[enrollment-projections.R] pressure_bump_min_terms must be at least 1 ",
      "and no larger than pressure_bump_window.", call. = FALSE
    )
  }
  config$pressure_bump_window <- bump_window
  config$pressure_bump_min_terms <- bump_min
  history_start <- suppressWarnings(as.integer(config$history_start_term))
  if (length(history_start) != 1L || is.na(history_start)) {
    stop("[enrollment-projections.R] history_start_term must be one YYYYSS term.",
         call. = FALSE)
  }
  config$history_start_term <- history_start
  for (field in c(
    "course_history_start_terms", "course_first_day_retention_min_terms"
  )) {
    values <- suppressWarnings(as.integer(config[[field]]))
    value_names <- names(config[[field]])
    if (length(values) > 0L &&
        (is.null(value_names) || any(is.na(values)) ||
          any(!nzchar(value_names)) || anyDuplicated(value_names))) {
      stop("[enrollment-projections.R] ", field,
           " must be a uniquely named integer vector.", call. = FALSE)
    }
    names(values) <- value_names
    config[[field]] <- values
  }
  if (any(config$course_history_start_terms < history_start)) {
    stop(
      "[enrollment-projections.R] Course history starts cannot precede the ",
      "general history_start_term.", call. = FALSE
    )
  }
  if (any(config$course_first_day_retention_min_terms < 1L)) {
    stop("[enrollment-projections.R] Course retention minimums must be positive.",
         call. = FALSE)
  }
  config
}


projection_require_columns <- function(data, required, caller) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop("[enrollment-projections.R] ", caller, " needs column(s): ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(data)
}


# Occupancy against scheduled seats.
#
# `occupancy` is the count of students actually holding seats: first-day
# enrollment (calc_first_day_enrl()) for a finished term, or the students
# registered right now for a term still filling. It is deliberately NOT the
# ever-registered class-list total. Ever-registered counts seat churn -- every
# early drop freed a seat someone else took -- so it exceeds capacity whenever a
# course turns over. On the Spring 2027 audit it flagged 72% of course-terms as
# capacity reached while census flagged 17% and final enrollment 6%, and in 87
# of those 284 "reached" terms fewer than 85% of seats were still filled at the
# end. Nor is it census, which 0.19.0 and 0.20.0 used: census is the 15th day of
# instruction, three weeks of drops after the first day, and on 598 ABQ+EA
# course-terms 199 were full on the first day but under capacity at census
# (median first-day fill 98.9%, census 95.6%).
# Reached means at least CEDAR_FULL_FILL (98%) of seats filled, since pooled
# capacity rarely fills to the last seat (R/lists/seat_fill.R).
# Unknown first-day enrollment is unknown occupancy: capacity_usable is FALSE,
# so the term is neither reached nor unreached. Every downstream reading of
# capacity_reached (Capacity-bounded labels, the capacity caveat, demand
# signals, the pressure screen) depends on this measuring real occupancy.
projection_capacity_metrics <- function(
    occupancy, capacity,
    reached_threshold = CEDAR_FULL_FILL) {
  occupancy <- as.numeric(occupancy)
  capacity <- as.numeric(capacity)
  capacity_fill <- dplyr::if_else(
    is.finite(capacity) & capacity > 0,
    occupancy / capacity,
    NA_real_
  )
  capacity_usable <- is.finite(capacity_fill)

  tibble::tibble(
    capacity_fill = capacity_fill,
    capacity_gap = dplyr::if_else(
      capacity_usable,
      capacity - occupancy,
      NA_real_
    ),
    capacity_usable = capacity_usable,
    capacity_reached = capacity_usable &
      capacity_fill >= as.numeric(reached_threshold)
  )
}


# The first-day occupancy a yes/no fill judgement may read. A complete count is
# itself. While a term's later sessions have not begun (a second-half session
# pulled mid-term, ISSUES.md I28), the sections that have begun give a lower
# bound: if it already reaches the threshold against ALL the term's seats, the
# true fill does too, so the bound settles the judgement and is returned.
# Below the threshold it settles nothing and the term stays unknown. Never use
# the result as a count: it exists to answer "at least this full?".
projection_judged_first_day <- function(first_day, started, basis, capacity,
                                        threshold) {
  first_day <- as.numeric(first_day)
  started <- as.numeric(started)
  capacity <- as.numeric(capacity)
  proves <- basis %in% "sessions_pending" & is.finite(started) &
    is.finite(capacity) & capacity > 0 &
    started / capacity >= as.numeric(threshold)
  dplyr::case_when(
    is.finite(first_day) ~ first_day,
    proves ~ started,
    TRUE ~ NA_real_
  )
}


projection_mode_character <- function(x, missing = "Unknown") {
  x <- as.character(x)
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0) return(missing)
  counts <- sort(table(x), decreasing = TRUE)
  sort(names(counts)[counts == max(counts)])[[1]]
}


projection_named_course_value <- function(course, values, default) {
  values <- values %||% numeric(0)
  index <- match(as.character(course), names(values))
  if (is.na(index)) default else unname(values[[index]])
}


projection_course_history_starts <- function(courses, opt = list()) {
  global_start <- as.integer(
    projection_option(opt, "history_start_term")
  )
  if (is.na(global_start)) {
    stop("[enrollment-projections.R] No history window: set projection_history_start_term ",
         "in institution/<id>/settings.csv or pass opt$history_start_term.", call. = FALSE)
  }
  overrides <- projection_option(opt, "course_history_start_terms")
  vapply(
    as.character(courses),
    function(course) {
      max(global_start, as.integer(
        projection_named_course_value(course, overrides, global_start)
      ))
    },
    integer(1),
    USE.NAMES = FALSE
  )
}


projection_filter_history_window <- function(data, opt = list()) {
  if (nrow(data) == 0L) return(data)
  projection_require_columns(
    data, c("subject_course", "term"),
    "projection_filter_history_window()"
  )
  starts <- projection_course_history_starts(data$subject_course, opt)
  terms <- suppressWarnings(as.integer(as.character(data$term)))
  data[!is.na(terms) & terms >= starts, , drop = FALSE]
}


projection_key_cols <- function() {
  c("market_id", "subject_course", "term_type")
}


projection_row_key_cols <- function() {
  c("market_id", "subject_course")
}


empty_projection_candidates <- function() {
  keys <- tibble::tibble(
    market_id = character(), college = character(), subject_course = character(),
    term_type = character(), target_term = integer(), target_term_label = character()
  )
  candidate <- projection_candidate("seasonal_last")[0, , drop = FALSE]

  dplyr::bind_cols(keys, candidate) %>%
    dplyr::left_join(
      empty_projection_performance(),
      by = c(
        "market_id", "college", "subject_course", "term_type",
        "method_id", "method_label"
      )
    ) %>%
    dplyr::mutate(
      raw_projected_classlist_total = numeric(),
      selected = logical()
    )
}


empty_enrollment_projections <- function() {
  empty_projection_candidates() %>%
    dplyr::select(-selected) %>%
    dplyr::mutate(
      interval_error = numeric(), projection_low = numeric(),
      projection_high = numeric(),
      projection_low_first_day_equivalent = numeric(),
      projection_high_first_day_equivalent = numeric(),
      stability = character(), stability_reason = character(),
      history_terms = integer(), history_first_term = integer(),
      history_last_term = integer(),
      history_mean_classlist_total = numeric(), history_cv = numeric(),
      history_median_yoy_change = numeric(),
      history_max_yoy_change = numeric(),
      depth = character(), depth_reason = character(),
      accuracy = character(), accuracy_reason = character(),
      selection_reason = character(),
      selection_wape = numeric(), selection_n_backtests = integer(),
      selection_pct_error_sd = numeric(),
      selection_basis = character(), selection_common_n = integer(),
      selection_default_wape = numeric(), selection_challenger_wape = numeric(),
      capacity_constrained_history = logical(),
      department = character(),
      scheduled_sections = integer(), scheduled_capacity = numeric(),
      target_schedule_available = logical(),
      target_classlist_total_to_date = numeric(),
      target_registered_now = numeric(), target_early_drops_to_date = numeric(),
      target_late_drops_to_date = numeric(),
      target_other_status_to_date = numeric(),
      target_registration_observed = logical(),
      target_available_seats = numeric(), target_classlist_fill = numeric(),
      target_active_fill = numeric(),
      target_capacity_reached = logical(),
      projected_over_capacity = numeric(), capacity_limit_signal = logical(),
      capacity_limit_status = character(), capacity_limit_note = character(),
      inclusion_reason = character(), candidate_min = numeric(),
      candidate_max = numeric(), candidate_spread = numeric(),
      n_applicable_methods = integer(), reference_section_size = numeric(),
      seat_gap = numeric(), recommended_sections = integer(),
      additional_sections = integer(), methods_disagree = logical(),
      observed_baseline = numeric(), observed_method_id = character(),
      observed_method = character(), observed_wape = numeric(),
      observed_n_backtests = integer(),
      adjusted_projection = numeric(), adjusted_wape = numeric(),
      adjusted_n_backtests = integer(), adjusted_applicable = logical(),
      adjusted_reason = character(),
      adjusted_saturated_prior = logical(), adjusted_prior_first_day_fill = numeric(),
      adjusted_prior_first_day_basis = character(),
      adjusted_waitlisted_prior = integer(), adjusted_floor_uplift = numeric(),
      adjusted_floor_basis = character(), adjusted_preceding_term = integer(),
      adjusted_waitlisted_preceding = integer(),
      adjusted_feeder_check = character(),
      adjusted_preceding_term_enrollment = numeric(),
      adjusted_preceding_term_change = numeric(), adjusted_regime_alarm = logical(),
      adjusted_delta_repeat = numeric(), adjusted_repeat_rate = numeric(),
      adjusted_delta_sequence = numeric(), adjusted_sequence_courses = character(),
      adjusted_sequence_change = numeric(),
      adjusted_delta_feeder = numeric(), adjusted_feeder_rate = numeric(),
      adjusted_feeder_courses = character(), adjusted_feeder_change = numeric(),
      adjusted_feeder_change_rate = numeric(),
      adjusted_delta_basis = character(),
      pressure_judged_terms = integer(), pressure_full_terms = integer(),
      pressure_bump_applied = logical(), pressure_bump = numeric(),
      pressure_bump_note = character(), plan_feeder_adjustment = numeric(),
      plan_feeder_note = character(), planned_registrations = numeric(),
      plan_feeder_sections = integer(), pressure_bump_sections = integer(),
      seat_consistency = character(), seat_consistency_reason = character(),
      seat_consistency_terms = integer(), seat_consistency_moves = integer(),
      expansion_pairs = integer(), expansion_fill_rate = numeric(),
      expansion_note = character(), floor_note = character(),
      regime_note = character(),
      capacity_data_quality = character(), recent_capacity_terms = integer(),
      recent_capacity_reached_terms = integer(),
      last_first_day_fill = numeric(),
      observed_enrollment_slope = numeric(), observed_enrollment_rising = logical(),
      persistent_capacity_reached = logical(), capacity_increase_terms = integer(),
      demand_followed_capacity_terms = integer(),
      why_uncertain = character(),
      recommendation = character()
    )
}


# ---- Rolling method selection ------------------------------------------------
#
# Prior same-season is the default projection. A challenger replaces it for a
# target only when, on earlier aftcast terms the two methods share, the
# challenger's WAPE was lower by at least `selection_challenger_margin` across
# at least `selection_min_backtests` such terms.
#
# The same rule is replayed at every historical fold using only the folds
# before it, and the accuracy published for a course is the realised error of
# the method the rule would have picked at each fold -- never the error of the
# winner on the folds that crowned it. The 0.18.0 engine chose in-sample on two
# common folds: it reported 13.7% WAPE for its picks, the same rule replayed
# honestly scored 16.5%, and prior same-season alone scored 15.9%. A method
# that cannot beat the default out of sample does not get to replace it.
