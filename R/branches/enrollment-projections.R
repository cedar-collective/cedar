


# Reusable enrollment-projection computations.
#
# This branch owns canonical inputs, pressure screening, candidate methods,
# leakage-safe backtesting, method selection, section recommendations, and the
# saved bundle contract. It does not read global data or Shiny state.

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


enrollment_projection_model_config <- function(opt = list()) {
  if (is.null(opt$history_start_term) && is.na(CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM)) {
    stop("[enrollment-projections.R] No history window: set projection_history_start_term ",
         "in institution/<id>/settings.csv or pass opt$history_start_term.", call. = FALSE)
  }
  defaults <- list(
    history_start_term = CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM,
    course_history_start_terms =
      CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS,
    recent_history_terms = 4L,
    projection_methods = names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
    summer = FALSE,
    pressure_min_seat_gap = 10,
    pressure_fill_threshold = 0.90,
    pressure_chronic_terms = 2L,
    pressure_history_window = 3L,
    backtest_terms = 6L,
    registration_capacity_threshold =
      CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL,
    capacity_explained_share_threshold = 0.50,
    first_day_retention_window = 4L,
    first_day_retention_min_terms = 2L,
    course_first_day_retention_min_terms =
      CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS,
    # Spine / floor / delta model (0.20.0).
    #
    # The spine is prior same-season class-list demand. The floor applies when
    # that term was saturated (first-day fill at or above
    # saturation_fill_threshold): demand is then at least first-day enrollment
    # plus the distinct students left on the waitlist, because the observed
    # count was clipped by the seats offered. Seats are judged on the first
    # day, not at census: three weeks of drops (census is the 15th day of
    # instruction; the term calendar in AGENTS.md) let a course full on day
    # one read 95% at census (0.21.0). The two deltas read the term immediately
    # before the target -- the course's own enrollment change and its feeder
    # courses' enrollment change -- each scaled by the share that historically
    # carried into this course the following same-season term. Enrollment, not
    # grades: grades are not posted when the schedule is built.
    saturation_fill_threshold = 0.90,
    delta_pairs_window = 4L,
    delta_min_pairs = 2L,
    feeder_max_courses = 8L,
    feeder_min_students = 3L,
    # Context, not a multiplier: among same-season pairs whose prior term was
    # saturated and whose capacity grew by at least expansion_capacity_change,
    # what share of the added seats filled. Needs expansion_min_pairs.
    expansion_capacity_change = 0.10,
    expansion_min_pairs = 5L,
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
  config <- utils::modifyList(defaults, opt)
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
# Reached means at least CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL
# (98%) of seats filled, since pooled capacity rarely fills to the last seat.
# Unknown first-day enrollment is unknown occupancy: capacity_usable is FALSE,
# so the term is neither reached nor unreached. Every downstream reading of
# capacity_reached (Capacity-bounded labels, the capacity caveat, demand
# signals, the pressure screen) depends on this measuring real occupancy.
projection_capacity_metrics <- function(
    occupancy, capacity,
    reached_threshold = CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL) {
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
    opt$history_start_term %||% CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM
  )
  if (is.na(global_start)) {
    stop("[enrollment-projections.R] No history window: set projection_history_start_term ",
         "in institution/<id>/settings.csv or pass opt$history_start_term.", call. = FALSE)
  }
  overrides <- opt$course_history_start_terms %||%
    CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS
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


prepare_projection_enrollment_history <- function(cl_enrls, courses = NULL,
                                                  campuses = NULL,
                                                  through_term = NULL) {
  projection_require_columns(
    cl_enrls,
    c("campus", "college", "subject_course", "term", "term_type",
      "registered", "dr_early", "dr_late", "cl_total"),
    "prepare_projection_enrollment_history()"
  )

  history <- cl_enrls %>%
    dplyr::ungroup() %>%
    add_census_enrl() %>%
    dplyr::mutate(
      term = suppressWarnings(as.integer(as.character(term))),
      term_type = as.character(term_type),
      part_term = if ("part_term" %in% names(.)) {
        dplyr::coalesce(dplyr::na_if(trimws(as.character(part_term)), ""), "Unknown")
      } else {
        "All"
      }
    )

  if (!is.null(courses) && length(courses) > 0) {
    history <- dplyr::filter(history, subject_course %in% .env$courses)
  }
  if (!is.null(campuses) && length(campuses) > 0) {
    history <- dplyr::filter(history, campus %in% .env$campuses)
  }
  if (!is.null(through_term) && length(through_term) > 0) {
    history <- dplyr::filter(history, term <= as.integer(through_term[[1]]))
  }

  history %>%
    dplyr::group_by(
      campus, college, subject_course, term, term_type, part_term
    ) %>%
    dplyr::summarise(
      registered = sum(registered, na.rm = TRUE),
      dr_early = sum(dr_early, na.rm = TRUE),
      dr_late = sum(dr_late, na.rm = TRUE),
      classlist_total = sum(cl_total, na.rm = TRUE),
      census_enrl = sum(census_enrl, na.rm = TRUE),
      census_retention_rate = dplyr::if_else(
        classlist_total > 0, census_enrl / classlist_total, NA_real_
      ),
      .groups = "drop"
    ) %>%
    dplyr::arrange(campus, subject_course, part_term, term)
}


# `first_day_enrl` is the market's seats held when classes began
# (calc_first_day_enrl(), each student-course once across the pooled campuses).
# It is what "were the seats full" is judged on and what sections are sized
# for: census, the 15th day of instruction, follows three weeks of drops, so a
# course full on day one can read 95%
# at census. It is NA, never a partial count, for a term whose class lists
# carry no status dates or were pulled before a section began.
prepare_projection_market_enrollment_history <- function(students, sections,
                                                         courses, campuses,
                                                         market_id,
                                                         through_term = NULL) {
  projection_require_columns(
    students,
    c("student_id", "term", "campus", "college", "subject_course",
      "registration_status_code", "crn", "registration_date", "as_of_date"),
    "prepare_projection_market_enrollment_history()"
  )

  classlist_rows <- students %>%
    dplyr::ungroup() %>%
    dplyr::filter(
      campus %in% .env$campuses,
      subject_course %in% .env$courses,
      !registration_status_code %in% STATUS_WAITLIST
    ) %>%
    dplyr::mutate(term = suppressWarnings(as.integer(as.character(term))))
  if (!is.null(through_term) && length(through_term) > 0) {
    classlist_rows <- dplyr::filter(
      classlist_rows, term <= as.integer(through_term[[1]])
    )
  }

  # CAMPUS_ROLLUP: this named market is prefiltered to its declared campuses;
  # student-course rows are deduplicated here before ABQ and EA are pooled.
  classlist_rows %>%
    dplyr::group_by(student_id, term, subject_course) %>%
    dplyr::summarise(
      college = projection_mode_character(college),
      is_registered = any(registration_status_code %in% STATUS_REGISTERED),
      is_late_drop = any(registration_status_code %in% STATUS_DROP_LATE),
      is_early_drop = any(registration_status_code %in% STATUS_DROP_EARLY),
      has_other_status = any(!registration_status_code %in%
        c(STATUS_REGISTERED, STATUS_DROP_ALL, STATUS_WAITLIST)),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      is_late_only = is_late_drop & !is_registered,
      is_early_only = is_early_drop & !is_registered & !is_late_drop,
      is_other_only = has_other_status & !is_registered & !is_late_drop &
        !is_early_drop
    ) %>%
    # CAMPUS_ROLLUP: output is the explicit market series, while delivery-level
    # campus rows remain in delivery_enrollment_history.
    dplyr::group_by(term, subject_course) %>%
    dplyr::summarise(
      college = projection_mode_character(college),
      registered = sum(is_registered),
      dr_early = sum(is_early_only),
      dr_late = sum(is_late_only),
      other_non_waitlist = sum(is_other_only),
      classlist_total = dplyr::n(),
      census_enrl = registered + dr_late,
      .groups = "drop"
    ) %>%
    dplyr::left_join(
      calc_first_day_enrl(classlist_rows, sections, pool_campuses = TRUE) %>%
        dplyr::mutate(first_day_enrl = as.numeric(first_day_enrl)),
      by = c("term", "subject_course"),
      relationship = "one-to-one"
    ) %>%
    dplyr::mutate(
      market_id = as.character(market_id),
      term_type = vapply(term, get_term_type, character(1)),
      first_day_retention_rate = dplyr::if_else(
        classlist_total > 0, first_day_enrl / classlist_total, NA_real_
      ),
      .before = 1
    ) %>%
    dplyr::arrange(subject_course, term)
}


prepare_projection_section_history <- function(sections, courses = NULL,
                                               campuses = NULL,
                                               through_term = NULL) {
  projection_require_columns(
    sections,
    c("campus", "college", "department", "subject_course", "term",
      "part_term", "status", "enrolled", "available", "total_enrl"),
    "prepare_projection_section_history()"
  )

  scoped_sections <- sections %>% dplyr::ungroup()
  if (!is.null(courses) && length(courses) > 0) {
    scoped_sections <- dplyr::filter(
      scoped_sections, subject_course %in% .env$courses
    )
  }
  if (!is.null(campuses) && length(campuses) > 0) {
    scoped_sections <- dplyr::filter(scoped_sections, campus %in% .env$campuses)
  }

  opt <- list(
    course = courses,
    term = NULL,
    status = "A",
    uel = TRUE,
    crosslist = "home",
    group_cols = c(
      "campus", "college", "term", "term_type", "subject_course", "part_term"
    )
  )

  history <- get_enrl(scoped_sections, opt) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      term = suppressWarnings(as.integer(as.character(term))),
      term_type = vapply(term, get_term_type, character(1)),
      part_term = dplyr::coalesce(
        dplyr::na_if(trimws(as.character(part_term)), ""), "Unknown"
      ),
      scheduled_sections = as.integer(sections),
      scheduled_capacity = pmax(0, as.numeric(enrolled) + as.numeric(avail)),
      capacity_per_section = dplyr::if_else(
        scheduled_sections > 0,
        scheduled_capacity / scheduled_sections,
        NA_real_
      )
    )

  if (!is.null(through_term) && length(through_term) > 0) {
    history <- dplyr::filter(history, term <= as.integer(through_term[[1]]))
  }

  metadata <- scoped_sections %>%
    dplyr::ungroup() %>%
    dplyr::filter(status == "A") %>%
    dplyr::mutate(
      term = suppressWarnings(as.integer(as.character(term))),
      part_term = dplyr::coalesce(
        dplyr::na_if(trimws(as.character(part_term)), ""), "Unknown"
      )
    ) %>%
    dplyr::group_by(campus, college, term, subject_course, part_term) %>%
    dplyr::summarise(
      department = projection_mode_character(department),
      course_title = if ("course_title" %in% names(.)) {
        projection_mode_character(course_title)
      } else {
        subject_course[[1]]
      },
      .groups = "drop"
    )

  history %>%
    dplyr::select(
      campus, college, term, term_type, subject_course, part_term,
      scheduled_sections, scheduled_capacity,
      capacity_per_section
    ) %>%
    dplyr::left_join(
      metadata,
      by = c("campus", "college", "term", "subject_course", "part_term")
    ) %>%
    dplyr::arrange(campus, subject_course, part_term, term)
}


prepare_projection_market_section_history <- function(delivery_history,
                                                      market_id) {
  projection_require_columns(
    delivery_history,
    c("campus", "college", "department", "course_title", "subject_course",
      "term", "term_type", "part_term", "scheduled_sections",
      "scheduled_capacity"),
    "prepare_projection_market_section_history()"
  )

  # CAMPUS_ROLLUP: sum only the declared market's retained delivery components;
  # the unaggregated campus and part-term rows are saved separately.
  delivery_history %>%
    dplyr::group_by(term, subject_course) %>%
    dplyr::summarise(
      college = projection_mode_character(college),
      department = projection_mode_character(department),
      course_title = projection_mode_character(course_title),
      term_type = projection_mode_character(term_type),
      scheduled_sections = sum(scheduled_sections, na.rm = TRUE),
      scheduled_capacity = sum(scheduled_capacity, na.rm = TRUE),
      n_delivery_components = dplyr::n(),
      n_campuses = dplyr::n_distinct(campus),
      capacity_per_section = dplyr::if_else(
        scheduled_sections > 0,
        scheduled_capacity / scheduled_sections,
        NA_real_
      ),
      .groups = "drop"
    ) %>%
    dplyr::mutate(market_id = as.character(market_id), .before = 1) %>%
    dplyr::arrange(subject_course, term)
}


prepare_projection_delivery_components <- function(delivery_enrollment_history,
                                                   delivery_section_history,
                                                   target_term, market_id) {
  target_term <- as.integer(target_term)
  target_type <- get_term_type(target_term)
  target <- delivery_section_history %>%
    dplyr::filter(term == target_term)

  prior <- delivery_enrollment_history %>%
    dplyr::filter(term < target_term, term_type == target_type) %>%
    dplyr::group_by(campus, college, subject_course, part_term) %>%
    dplyr::slice_max(term, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(
      campus, college, subject_course, part_term,
      prior_comparable_term = term,
      prior_census_enrl = census_enrl
    ) %>%
    dplyr::left_join(
      delivery_section_history %>%
        dplyr::select(
          campus, college, subject_course, part_term,
          prior_comparable_term = term,
          prior_scheduled_capacity = scheduled_capacity
        ),
      by = c(
        "campus", "college", "subject_course", "part_term",
        "prior_comparable_term"
      )
    ) %>%
    dplyr::mutate(
      prior_census_fill = dplyr::if_else(
        prior_scheduled_capacity > 0,
        prior_census_enrl / prior_scheduled_capacity,
        NA_real_
      )
    )

  if (nrow(target) == 0) {
    return(tibble::tibble(
      market_id = character(), campus = character(), college = character(),
      department = character(), subject_course = character(),
      part_term = character(), target_term = integer(),
      target_term_label = character(), scheduled_sections = integer(),
      scheduled_capacity = numeric(),
      capacity_share = numeric(), prior_comparable_term = integer(),
      prior_census_enrl = numeric(), prior_scheduled_capacity = numeric(),
      prior_census_fill = numeric()
    ))
  }

  target %>%
    dplyr::left_join(
      prior,
      by = c("campus", "college", "subject_course", "part_term")
    ) %>%
    # CAMPUS_ROLLUP: shares describe allocation within the named market, not
    # campus-specific demand, and every component remains in this output.
    dplyr::group_by(subject_course) %>%
    dplyr::mutate(
      capacity_share = {
        total_capacity <- sum(scheduled_capacity, na.rm = TRUE)
        if (total_capacity > 0) scheduled_capacity / total_capacity else
          rep(NA_real_, dplyr::n())
      }
    ) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(
      market_id = as.character(market_id),
      campus, college, department, subject_course, part_term,
      target_term = term,
      target_term_label = fmt_term(term),
      scheduled_sections, scheduled_capacity,
      capacity_share, prior_comparable_term, prior_census_enrl,
      prior_scheduled_capacity, prior_census_fill
    ) %>%
    dplyr::arrange(subject_course, campus, part_term)
}


# Baseline roster composition: who actually holds the seats the projection is
# anchored on, counted by their SAME-TERM major and classification.
#
# This is what lets a population-growth scenario be arithmetic over saved rows
# rather than a model run in a user session. A scenario needs to know how many of
# a course's baseline students belong to a named population; that count is fixed
# once the baseline term is chosen, so it is computed here and saved.
#
# The baseline term is the most recent COMPARABLE (same-season) term at or before
# the cutoff in which the course had a roster -- the same comparability rule the
# projection methods use, so the composition describes the term the projection is
# actually anchored to rather than whichever term happens to be most recent.
#
# Students with no program row in that term are kept with major_code = NA. They
# are really on the roster, they simply cannot be attributed to a program, and
# dropping them would make the composition stop summing to the course total.
build_projection_cohort_composition <- function(student_inputs, target_term,
                                                as_of_term, market_id,
                                                scope_courses = NULL) {
  empty <- tibble::tibble(
    market_id = character(), subject_course = character(),
    baseline_term = integer(), major_code = character(),
    student_classification = character(), n_students = integer()
  )
  targets <- student_inputs$target_students %||% NULL
  student_terms <- student_inputs$student_terms %||% NULL
  if (is.null(targets) || is.null(student_terms)) return(empty)
  projection_require_columns(
    targets, c("student_id", "term", "subject_course"),
    "build_projection_cohort_composition() target_students"
  )
  projection_require_columns(
    student_terms, c("student_id", "term", "major_code", "student_classification"),
    "build_projection_cohort_composition() student_terms"
  )

  target_term <- as.integer(target_term)
  as_of_term <- as.integer(as_of_term)
  season <- get_term_type(target_term)
  comparable <- targets %>%
    dplyr::filter(get_term_type(term) == season, term <= as_of_term)
  if (!is.null(scope_courses)) {
    comparable <- dplyr::filter(comparable, subject_course %in% scope_courses)
  }
  if (nrow(comparable) == 0) return(empty)

  # CAMPUS_ROLLUP: the planning market pools its declared campuses into one
  # course market by design, and target_students was deduplicated across them
  # upstream, so a course has one baseline term here rather than one per campus.
  # Splitting by campus would give the same student two baselines.
  baseline <- comparable %>%
    dplyr::group_by(subject_course) %>%
    dplyr::summarise(baseline_term = max(term), .groups = "drop")

  # CAMPUS_ROLLUP: target_students is already deduplicated across the named
  # planning market, so a student appearing on two campuses counts once.
  comparable %>%
    dplyr::inner_join(baseline, by = "subject_course") %>%
    dplyr::filter(term == baseline_term) %>%
    dplyr::left_join(
      student_terms %>%
        dplyr::distinct(student_id, term, major_code, student_classification),
      by = c("student_id", "term")
    ) %>%
    dplyr::mutate(market_id = as.character(market_id)) %>%
    dplyr::count(
      market_id, subject_course, baseline_term, major_code,
      student_classification,
      name = "n_students"
    ) %>%
    dplyr::mutate(baseline_term = as.integer(baseline_term))
}


# Section sizing, in one place.
#
# The published row and any scenario built on top of it must convert demand to
# sections the same way, or a scenario at 0% growth would disagree with the
# projection it is anchored on.
projection_sections_for_demand <- function(demand, reference_section_size) {
  dplyr::if_else(
    is.finite(reference_section_size) & is.finite(demand) &
      reference_section_size > 0,
    as.integer(ceiling(demand / reference_section_size)),
    NA_integer_
  )
}


projection_additional_sections <- function(recommended_sections,
                                           scheduled_sections) {
  dplyr::if_else(
    !is.na(recommended_sections),
    pmax(0L, recommended_sections - as.integer(scheduled_sections)),
    NA_integer_
  )
}


prepare_projection_student_inputs <- function(students, target_courses,
                                              campuses = NULL,
                                              through_term = NULL,
                                              from_term = NULL,
                                              graded_through_term = NULL) {
  projection_require_columns(
    students,
    c("student_id", "term", "campus", "college", "subject_course",
      "part_term", "registration_status_code", "major_code",
      "student_classification", "final_grade"),
    "prepare_projection_student_inputs()"
  )

  all_classlist_rows <- students %>%
    dplyr::ungroup() %>%
    dplyr::filter(
      !registration_status_code %in% STATUS_WAITLIST
    ) %>%
    dplyr::mutate(
      term = suppressWarnings(as.integer(as.character(term))),
      part_term = dplyr::coalesce(
        dplyr::na_if(trimws(as.character(part_term)), ""), "Unknown"
      )
    )

  if (!is.null(through_term) && length(through_term) > 0) {
    all_classlist_rows <- dplyr::filter(
      all_classlist_rows, term <= as.integer(through_term[[1]])
    )
  }
  if (!is.null(from_term) && length(from_term) > 0) {
    all_classlist_rows <- dplyr::filter(
      all_classlist_rows, term >= as.integer(from_term[[1]])
    )
  }

  university_student_terms <- all_classlist_rows %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarise(
      student_classification = projection_mode_character(student_classification),
      .groups = "drop"
    )
  university_term_signals <- university_student_terms %>%
    dplyr::group_by(term) %>%
    dplyr::summarise(
      university_students = dplyr::n(),
      university_incoming_first_sem = sum(
        student_classification == "Freshman, 1st Yr, 1st Sem", na.rm = TRUE
      ),
      .groups = "drop"
    )

  classlist_rows <- all_classlist_rows
  if (!is.null(campuses) && length(campuses) > 0) {
    classlist_rows <- dplyr::filter(
      classlist_rows, campus %in% .env$campuses
    )
  }

  # CAMPUS_ROLLUP: course membership is deduplicated across the declared
  # market; the feeder and repeat deltas read it per student-term-course.
  course_enrollments <- classlist_rows %>%
    dplyr::distinct(student_id, term, subject_course)

  student_terms <- classlist_rows %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarise(
      major_code = projection_mode_character(major_code),
      student_classification = projection_mode_character(student_classification),
      .groups = "drop"
    )
  market_term_signals <- student_terms %>%
    dplyr::group_by(term) %>%
    dplyr::summarise(
      market_students = dplyr::n(),
      market_incoming_first_sem = sum(
        student_classification == "Freshman, 1st Yr, 1st Sem", na.rm = TRUE
      ),
      .groups = "drop"
    )

  # CAMPUS_ROLLUP: a student taking the target in either delivery counts once.
  target_students <- course_enrollments %>%
    dplyr::filter(subject_course %in% .env$target_courses)

  course_outcome_students <- classlist_rows %>%
    dplyr::filter(subject_course %in% .env$target_courses)
  if (!is.null(graded_through_term) && length(graded_through_term) > 0L &&
      !is.na(graded_through_term[[1]])) {
    course_outcome_students <- course_outcome_students %>%
      dplyr::filter(term <= as.integer(graded_through_term[[1]]))
  } else {
    course_outcome_students <- course_outcome_students[0, , drop = FALSE]
  }
  course_outcome_students <- course_outcome_students %>%
    classify_enrollment_outcomes() %>%
    # CAMPUS_ROLLUP: outcomes are deduplicated across the declared course
    # market before a student can contribute to its DFW pressure signal.
    dplyr::group_by(student_id, term, subject_course) %>%
    dplyr::summarise(
      outcome = dplyr::if_else(any(outcome == "dfw"), "dfw", "pass"),
      .groups = "drop"
    )
  course_outcomes <- course_outcome_students %>%
    # CAMPUS_ROLLUP: these are course-market outcome counts, not delivery rows.
    dplyr::group_by(term, subject_course) %>%
    dplyr::summarise(
      graded_students = dplyr::n(),
      dfw_students = sum(outcome == "dfw"),
      dfw_rate = dfw_students / graded_students,
      .groups = "drop"
    )
  course_repeat_pressure <- course_outcome_students %>%
    dplyr::filter(outcome == "dfw") %>%
    add_next_term_col("term", summer = FALSE) %>%
    dplyr::inner_join(
      target_students %>%
        dplyr::rename(next_term = term),
      by = c("student_id", "next_term", "subject_course")
    ) %>%
    # CAMPUS_ROLLUP: target_students is already unique across the named market.
    dplyr::count(term, next_term, subject_course,
                 name = "dfw_next_term_repeaters")

  list(
    course_enrollments = course_enrollments,
    student_terms = student_terms,
    target_students = target_students,
    university_term_signals = university_term_signals,
    market_term_signals = market_term_signals,
    course_outcomes = course_outcomes,
    course_repeat_pressure = course_repeat_pressure
  )
}


# Distinct students left waiting on a course, per market term, by the canonical
# class-list waitlist-demand rule (R/branches/waitlist-demand.R). Class lists
# retain waitlist rows only from Summer 2026, so earlier terms report zero
# rows here rather than zero demand; the floor says which.
prepare_projection_waitlist_history <- function(students, courses, campuses,
                                                market_id, through_term = NULL,
                                                sections = NULL) {
  projection_require_columns(
    students,
    c("student_id", "term", "campus", "subject_course",
      "registration_status_code"),
    "prepare_projection_waitlist_history()"
  )
  scoped <- students %>%
    dplyr::ungroup() %>%
    dplyr::filter(
      campus %in% .env$campuses,
      subject_course %in% .env$courses
    ) %>%
    dplyr::mutate(term = suppressWarnings(as.integer(as.character(term))))
  if (!is.null(through_term) && length(through_term) > 0) {
    scoped <- dplyr::filter(scoped, term <= as.integer(through_term[[1]]))
  }
  empty <- tibble::tibble(
    market_id = character(), subject_course = character(), term = integer(),
    waitlisted = integer()
  )
  if (nrow(scoped) == 0L) return(empty)

  # CAMPUS_ROLLUP: the canonical rule removes anyone registered in the same
  # course group; the market then counts each waiting student once across
  # its pooled campuses.
  get_true_waitlisted_rows(scoped, sections) %>%
    dplyr::distinct(student_id, term, subject_course) %>%
    dplyr::count(term, subject_course, name = "waitlisted") %>%
    dplyr::mutate(
      market_id = as.character(market_id),
      waitlisted = as.integer(waitlisted),
      .before = 1
    ) %>%
    dplyr::arrange(subject_course, term)
}


prepare_enrollment_projection_inputs <- function(cl_enrls, sections, students,
                                                 target_courses,
                                                 target_campuses,
                                                 target_market_id,
                                                 enrollment_through_term = NULL,
                                                 section_through_term = NULL,
                                                 history_start_term = NULL,
                                                 course_history_start_terms =
                                                   integer(0),
                                                 graded_through_term = NULL) {
  if (is.null(target_courses) || length(target_courses) == 0) {
    stop("[enrollment-projections.R] target_courses is required.", call. = FALSE)
  }
  target_courses <- sort(unique(as.character(target_courses)))
  if (is.null(target_campuses) || length(target_campuses) == 0) {
    stop("[enrollment-projections.R] target_campuses is required.", call. = FALSE)
  }
  target_campuses <- sort(unique(as.character(target_campuses)))
  if (is.null(target_market_id) || length(target_market_id) != 1L ||
      is.na(target_market_id) || !nzchar(target_market_id)) {
    stop("[enrollment-projections.R] target_market_id is required.", call. = FALSE)
  }
  if (is.null(section_through_term) || length(section_through_term) != 1L ||
      is.na(section_through_term)) {
    stop("[enrollment-projections.R] section_through_term is required.",
         call. = FALSE)
  }
  target_market_id <- as.character(target_market_id)
  history_opt <- list(
    history_start_term = history_start_term,
    course_history_start_terms = course_history_start_terms
  )

  delivery_enrollment_history <- prepare_projection_enrollment_history(
    cl_enrls, courses = target_courses,
    campuses = target_campuses,
    through_term = enrollment_through_term
  )
  delivery_section_history <- prepare_projection_section_history(
    sections, courses = target_courses,
    campuses = target_campuses,
    through_term = section_through_term
  )
  market_enrollment_history <- prepare_projection_market_enrollment_history(
    students, sections, courses = target_courses, campuses = target_campuses,
    market_id = target_market_id,
    through_term = enrollment_through_term
  )
  market_section_history <- prepare_projection_market_section_history(
    delivery_section_history, market_id = target_market_id
  )
  # Every term of the market series, not just the comparable-season rows at or
  # after the history floor. The Fall deltas read the term immediately before
  # each target (Fall 2021 for Spring 2022), which the floor would drop. It is
  # a source population, not an older target outcome.
  preceding_term_history <- market_enrollment_history
  if (!is.null(history_start_term)) {
    delivery_enrollment_history <- projection_filter_history_window(
      delivery_enrollment_history, history_opt
    )
    delivery_section_history <- projection_filter_history_window(
      delivery_section_history, history_opt
    )
    market_enrollment_history <- projection_filter_history_window(
      market_enrollment_history, history_opt
    )
    market_section_history <- projection_filter_history_window(
      market_section_history, history_opt
    )
  }
  student_source_start <- if (is.null(history_start_term)) NULL else
    subtract_term(as.integer(history_start_term), summer = FALSE)

  list(
    enrollment_history = market_enrollment_history,
    preceding_term_history = preceding_term_history,
    waitlist_history = prepare_projection_waitlist_history(
      students, courses = target_courses, campuses = target_campuses,
      market_id = target_market_id, through_term = enrollment_through_term,
      sections = sections
    ),
    target_registration_snapshot = prepare_projection_market_enrollment_history(
      students, sections, courses = target_courses, campuses = target_campuses,
      market_id = target_market_id,
      through_term = section_through_term
    ) %>%
      dplyr::filter(term == as.integer(section_through_term[[1]])),
    section_history = market_section_history,
    delivery_enrollment_history = delivery_enrollment_history,
    delivery_section_history = delivery_section_history,
    delivery_components = prepare_projection_delivery_components(
      delivery_enrollment_history, delivery_section_history,
      target_term = section_through_term, market_id = target_market_id
    ),
    students = prepare_projection_student_inputs(
      students, target_courses = target_courses,
      campuses = target_campuses,
      through_term = enrollment_through_term,
      from_term = student_source_start,
      graded_through_term = graded_through_term
    ),
    target_courses = target_courses,
    target_campuses = target_campuses,
    target_market_id = target_market_id,
    enrollment_through_term = if (is.null(enrollment_through_term)) NULL else
      as.integer(enrollment_through_term[[1]]),
    section_through_term = if (is.null(section_through_term)) NULL else
      as.integer(section_through_term[[1]]),
    graded_through_term = if (is.null(graded_through_term)) NULL else
      as.integer(graded_through_term[[1]]),
    history_start_term = if (is.null(history_start_term)) NULL else
      as.integer(history_start_term),
    course_history_start_terms = course_history_start_terms
  )
}


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
  window <- as.integer(opt$first_day_retention_window %||% 4L)
  min_terms <- as.integer(projection_named_course_value(
    row$subject_course,
    opt$course_first_day_retention_min_terms %||%
      CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS,
    opt$first_day_retention_min_terms %||% 2L
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
                                 waitlisted_prior = NA_integer_,
                                 floor_uplift = 0,
                                 floor_basis = NA_character_,
                                 preceding_term = NA_integer_,
                                 preceding_term_enrollment = NA_real_,
                                 preceding_term_change = NA_real_,
                                 regime_alarm = NA,
                                 delta_repeat = 0, repeat_rate = NA_real_,
                                 delta_feeder = 0, feeder_rate = NA_real_,
                                 feeder_courses = NA_character_,
                                 feeder_change = NA_real_,
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
    waitlisted_prior = as.integer(waitlisted_prior),
    floor_uplift = as.numeric(floor_uplift),
    floor_basis = as.character(floor_basis),
    preceding_term = as.integer(preceding_term),
    preceding_term_enrollment = as.numeric(preceding_term_enrollment),
    preceding_term_change = as.numeric(preceding_term_change),
    regime_alarm = as.logical(regime_alarm),
    delta_repeat = as.numeric(delta_repeat),
    repeat_rate = as.numeric(repeat_rate),
    delta_feeder = as.numeric(delta_feeder),
    feeder_rate = as.numeric(feeder_rate),
    feeder_courses = as.character(feeder_courses),
    feeder_change = as.numeric(feeder_change),
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
#   floor uplift   if that term was saturated (first-day fill >= 90%), demand
#                  is at least first-day enrollment + students left on the
#                  waitlist; the uplift is that floor minus the spine
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
  threshold <- as.numeric(opt$saturation_fill_threshold %||% 0.90)
  spine_term <- as.integer(spine_row$term[[1]])
  spine <- spine_row$classlist_total[[1]]
  capacity <- projection_section_history_for_row(section_history, row) %>%
    dplyr::filter(term == spine_term) %>%
    dplyr::slice_head(n = 1)
  capacity_value <- if (nrow(capacity) == 0) NA_real_ else
    capacity$scheduled_capacity[[1]]
  first_day <- spine_row$first_day_enrl[[1]]
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
    return(list(
      saturated = NA, fill = NA_real_, waitlisted = waitlisted, uplift = 0,
      basis = paste("First-day enrollment for", fmt_term(spine_term),
                    "cannot be reconstructed from the class lists,",
                    "so saturation cannot be judged")
    ))
  }
  if (!isTRUE(saturation$capacity_usable[[1]])) {
    return(list(
      saturated = NA, fill = saturation$fill_rate[[1]], waitlisted = waitlisted,
      uplift = 0,
      basis = paste("No usable capacity for", fmt_term(spine_term),
                    "so saturation cannot be judged")
    ))
  }
  if (!saturated) {
    return(list(
      saturated = FALSE, fill = saturation$fill_rate[[1]],
      waitlisted = waitlisted, uplift = 0,
      basis = paste0(
        fmt_term(spine_term), " was not saturated (first-day fill ",
        scales::percent(saturation$fill_rate[[1]], accuracy = 0.1), ")"
      )
    ))
  }
  floor_demand <- first_day + waitlisted
  uplift <- max(0, floor_demand - spine)
  list(
    saturated = TRUE, fill = saturation$fill_rate[[1]], waitlisted = waitlisted,
    uplift = uplift,
    basis = paste0(
      fmt_term(spine_term), " was saturated (first-day fill ",
      scales::percent(saturation$fill_rate[[1]], accuracy = 0.1), "); ",
      if (waitlisted > 0) {
        paste0("floor is first day + ", waitlisted, " waitlisted = ",
               round(floor_demand))
      } else {
        "no waitlist rows retained for that term, so the floor is the spine itself"
      }
    )
  )
}


# Historical carry-through rates for the two deltas, learned only from pairs
# (preceding term p, following same-season term s) with s before the target.
projection_delta_rates <- function(student_inputs, row, target_term,
                                   opt = list()) {
  window <- as.integer(opt$delta_pairs_window %||% 4L)
  min_pairs <- as.integer(opt$delta_min_pairs %||% 2L)
  max_feeders <- as.integer(opt$feeder_max_courses %||% 8L)
  min_students <- as.integer(opt$feeder_min_students %||% 3L)
  course <- row$subject_course
  enrollments <- student_inputs$course_enrollments
  targets <- student_inputs$target_students %>%
    dplyr::filter(subject_course == course)
  empty <- list(
    n_pairs = 0L, repeat_rate = NA_real_, feeder_rate = NA_real_,
    feeders = character(0), pairs = integer(0)
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

  # Feeders: the courses whose p students most often took this course in s,
  # excluding the course itself. Then one pooled rate across the feeder set so
  # a student in two feeders counts once.
  # CAMPUS_ROLLUP: course_enrollments is already deduplicated across the named
  # planning market, so a feeder is counted once per student whichever campus
  # delivered it; a campus split here would double-count cross-campus students.
  transitions <- preceding_rows %>%
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
    pool <- preceding_rows %>%
      dplyr::filter(subject_course %in% feeders) %>%
      dplyr::distinct(student_id, following) %>%
      dplyr::left_join(following_rows, by = c("student_id", "following"))
    mean(dplyr::coalesce(pool$took_next, FALSE))
  }

  list(
    n_pairs = nrow(pairs), repeat_rate = repeat_rate, feeder_rate = feeder_rate,
    feeders = feeders, pairs = pairs$following
  )
}


# Distinct students enrolled in any of `courses` in `term`, excluding those in
# `exclude_course`, from the market's deduplicated course enrollments.
projection_distinct_enrolled <- function(enrollments, term, courses,
                                         exclude_course = NULL) {
  rows <- enrollments %>%
    dplyr::filter(term == .env$term, subject_course %in% courses)
  if (!is.null(exclude_course)) {
    excluded <- enrollments %>%
      dplyr::filter(term == .env$term, subject_course == exclude_course) %>%
      dplyr::distinct(student_id)
    rows <- dplyr::anti_join(rows, excluded, by = "student_id")
  }
  dplyr::n_distinct(rows$student_id)
}


project_spine_adjusted <- function(history, preceding_term_history,
                                   section_history, waitlist_history,
                                   student_inputs, row, target_term,
                                   opt = list()) {
  target_term <- as.integer(target_term)
  alarm_threshold <- as.numeric(opt$regime_alarm_threshold %||% 0.25)
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
  delta_feeder <- 0
  repeat_rate <- NA_real_
  feeder_rate <- NA_real_
  feeders <- character(0)
  feeder_change <- NA_real_
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
    if (is.finite(feeder_rate) && length(feeders) > 0L) {
      feeder_now <- projection_distinct_enrolled(
        enrollments, preceding_term, feeders, row$subject_course
      )
      feeder_then <- projection_distinct_enrolled(
        enrollments, prior_preceding_term, feeders, row$subject_course
      )
      feeder_change <- feeder_now - feeder_then
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
  # Unknown when the preceding term is unobserved; never FALSE by default.
  regime_alarm <- if (is.finite(change)) abs(change) >= alarm_threshold else NA

  estimate <- max(0, spine + floor$uplift + delta_repeat + delta_feeder)
  projection_candidate(
    "spine_adjusted",
    estimate = estimate,
    applicable = TRUE,
    reason = paste0(
      "Prior same-season ", spine, " + floor ", round(floor$uplift),
      " + repeat delta ", sprintf("%+.1f", delta_repeat),
      " + feeder delta ", sprintf("%+.1f", delta_feeder)
    ),
    n_history_terms = 1L,
    evidence_n = spine,
    n_components = 1L + (floor$uplift > 0) + (delta_repeat != 0) + (delta_feeder != 0),
    component_summary = paste(floor$basis, delta_basis, sep = "; "),
    spine = spine,
    spine_term = spine_term,
    saturated_prior = floor$saturated,
    prior_first_day_fill = floor$fill,
    waitlisted_prior = floor$waitlisted,
    floor_uplift = floor$uplift,
    floor_basis = floor$basis,
    preceding_term = preceding_term,
    preceding_term_enrollment = preceding_enrollment,
    preceding_term_change = change,
    regime_alarm = regime_alarm,
    delta_repeat = delta_repeat,
    repeat_rate = repeat_rate,
    delta_feeder = delta_feeder,
    feeder_rate = feeder_rate,
    feeder_courses = if (length(feeders) == 0L) NA_character_ else
      paste(feeders, collapse = ", "),
    feeder_change = feeder_change,
    delta_basis = delta_basis,
    projection_formula = "spine + floor uplift + repeat delta + feeder delta"
  )
}


project_course_method_candidates <- function(inputs, row, target_term,
                                             opt = list()) {
  method_ids <- as.character(
    opt$projection_methods %||% names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  )
  unknown <- setdiff(method_ids, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
  if (length(unknown) > 0) {
    stop(
      "[enrollment-projections.R] Unknown projection method(s): ",
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
# raw projection (floored at zero), the floor never lowers the spine, and the
# spine term precedes the target.
validate_spine_rows <- function(data, caller) {
  if (nrow(data) == 0 || !"method_id" %in% names(data)) return(invisible(TRUE))
  rows <- data %>%
    dplyr::filter(method_id == "spine_adjusted", applicable)
  if (nrow(rows) == 0) return(invisible(TRUE))
  projection_require_columns(
    rows,
    c("target_term", "projected_classlist_total", "spine", "spine_term",
      "floor_uplift", "delta_repeat", "delta_feeder"),
    caller
  )
  raw <- if ("raw_projected_classlist_total" %in% names(rows)) {
    rows$raw_projected_classlist_total
  } else {
    rows$projected_classlist_total
  }
  expected <- pmax(
    0, rows$spine + rows$floor_uplift + rows$delta_repeat + rows$delta_feeder
  )
  valid <- is.finite(rows$spine) & rows$spine_term < rows$target_term &
    rows$floor_uplift >= 0 & is.finite(raw) & abs(raw - expected) <= 1e-6
  if (any(!valid)) {
    stop(
      "[enrollment-projections.R] ", caller,
      " has an invalid spine / floor / delta audit trail.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


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
  min_gap <- as.numeric(opt$pressure_min_seat_gap %||% 10)
  fill_threshold <- as.numeric(opt$pressure_fill_threshold %||% 0.90)
  capacity_threshold <- as.numeric(
    opt$registration_capacity_threshold %||%
      CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL
  )
  chronic_terms <- as.integer(opt$pressure_chronic_terms %||% 2L)
  history_window <- as.integer(opt$pressure_history_window %||% 3L)

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
      baseline - target_capacity >= min_gap
    chronic_fill <- high_fill_terms >= chronic_terms
    growth_pressure <- is.finite(trend) &&
      target_capacity_usable &&
      trend - target_capacity >= min_gap
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
      opt$registration_capacity_threshold %||%
      CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL
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
  max_terms <- as.integer(opt$backtest_terms %||% 6L)

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
      "[enrollment-projections.R] ", caller,
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
          "No aftcast misses are explained by the seat ceiling",
        capacity_explained_error_share >= as.numeric(
          opt$capacity_explained_share_threshold %||% 0.50
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
  window <- as.integer(opt$recent_history_terms %||% 4L)
  if (!is.finite(window) || window < 1L) {
    stop("[enrollment-projections.R] recent_history_terms must be positive.",
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
      reached_threshold = opt$registration_capacity_threshold %||%
      CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL
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
      adjusted_waitlisted_prior = integer(), adjusted_floor_uplift = numeric(),
      adjusted_floor_basis = character(), adjusted_preceding_term = integer(),
      adjusted_preceding_term_enrollment = numeric(),
      adjusted_preceding_term_change = numeric(), adjusted_regime_alarm = logical(),
      adjusted_delta_repeat = numeric(), adjusted_repeat_rate = numeric(),
      adjusted_delta_feeder = numeric(), adjusted_feeder_rate = numeric(),
      adjusted_feeder_courses = character(), adjusted_feeder_change = numeric(),
      adjusted_delta_basis = character(),
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
  min_folds <- as.integer(opt$selection_min_backtests %||% 3L)
  margin <- as.numeric(opt$selection_challenger_margin %||% 0.02)
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
    default_label, " is the default; no challenger beat it by at least ",
    scales::percent(margin, accuracy = 0.1), " WAPE on ", min_folds,
    " or more earlier shared aftcasts"
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
        " earlier shared aftcasts (",
        scales::percent(winner$challenger_wape, accuracy = 0.1), " vs ",
        scales::percent(winner$default_wape, accuracy = 0.1), " WAPE)"
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
  constrained_share <- as.numeric(opt$capacity_constrained_share %||% 0.50)
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
          as.integer(opt$depth_deep_min_aftcasts %||% 4L) ~ "Deep",
        dplyr::coalesce(n_backtests, 0L) >=
          as.integer(opt$depth_moderate_min_aftcasts %||% 3L) ~ "Moderate",
        dplyr::coalesce(n_backtests, 0L) >= 1L ~ "Thin",
        TRUE ~ "None"
      ),
      depth_reason = dplyr::case_when(
        method_id == "none" ~ "No applicable method",
        dplyr::coalesce(n_backtests, 0L) < 1L ~
          "No comparable aftcast for the selection rule",
        TRUE ~ paste0(
          n_backtests, " comparable rolling-selection aftcast",
          dplyr::if_else(n_backtests == 1L, "", "s")
        )
      ),
      accuracy = dplyr::case_when(
        method_id == "none" ~ "Unrated",
        dplyr::coalesce(n_backtests, 0L) <
          as.integer(opt$accuracy_min_aftcasts %||% 2L) ~ "Unrated",
        !is.finite(wape) ~ "Unrated",
        wape <= as.numeric(opt$accuracy_close_max_wape %||% 0.10) ~ "Close",
        wape <= as.numeric(opt$accuracy_fair_max_wape %||% 0.20) ~ "Fair",
        TRUE ~ "Poor"
      ),
      accuracy_reason = dplyr::case_when(
        method_id == "none" ~ "No applicable method",
        dplyr::coalesce(n_backtests, 0L) <
          as.integer(opt$accuracy_min_aftcasts %||% 2L) ~ paste0(
            "Fewer than ", as.integer(opt$accuracy_min_aftcasts %||% 2L),
            " comparable aftcasts; accuracy cannot be measured"
          ),
        !is.finite(wape) ~ "No measurable aftcast accuracy",
        TRUE ~ paste0(
          scales::percent(wape, accuracy = 0.1),
          " average rolling-selection aftcast error across ", n_backtests,
          " term", dplyr::if_else(n_backtests == 1L, "", "s"),
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
  history_window <- as.integer(opt$demand_history_window %||% 5L)
  min_terms <- as.integer(opt$stability_min_terms %||% 3L)
  stable_max <- as.numeric(opt$stability_stable_max_cv %||% 0.10)
  moderate_max <- as.numeric(opt$stability_moderate_max_cv %||% 0.25)

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
  history_window <- as.integer(opt$demand_history_window %||% 5L)
  recent_window <- as.integer(opt$demand_recent_window %||% 3L)
  capacity_threshold <- as.numeric(
    opt$registration_capacity_threshold %||%
      CEDAR_ENROLLMENT_PROJECTION_CAPACITY_REACHED_FILL
  )
  response_fraction <- as.numeric(opt$capacity_response_fraction %||% 0.50)

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
      as.numeric(opt$demand_min_growth_per_year %||% 2),
      as.numeric(opt$demand_min_growth_share %||% 0.02) *
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
      adjusted_waitlisted_prior = waitlisted_prior,
      adjusted_floor_uplift = floor_uplift,
      adjusted_floor_basis = floor_basis,
      adjusted_preceding_term = preceding_term,
      adjusted_preceding_term_enrollment = preceding_term_enrollment,
      adjusted_preceding_term_change = preceding_term_change,
      adjusted_regime_alarm = regime_alarm,
      adjusted_delta_repeat = delta_repeat,
      adjusted_repeat_rate = repeat_rate,
      adjusted_delta_feeder = delta_feeder,
      adjusted_feeder_rate = feeder_rate,
      adjusted_feeder_courses = feeder_courses,
      adjusted_feeder_change = feeder_change,
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
  threshold <- as.numeric(opt$saturation_fill_threshold %||% 0.90)
  min_change <- as.numeric(opt$expansion_capacity_change %||% 0.10)
  min_pairs <- as.integer(opt$expansion_min_pairs %||% 5L)
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
    series$first_day_enrl, series$scheduled_capacity,
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

  selected %>%
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
    dplyr::left_join(stability, by = keys) %>%
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
      # Seats are compared with EXPECTED FIRST-DAY OCCUPANCY, not with the
      # class-list demand headline: ever-registered runs above the first day
      # because every early drop frees a seat someone else takes.
      seat_gap = round(projected_first_day_equivalent - scheduled_capacity),
      projected_over_capacity = pmax(0, seat_gap),
      capacity_limit_signal = target_schedule_available &
        target_capacity_reached & projected_over_capacity > 0,
      capacity_limit_status = dplyr::case_when(
        !target_schedule_available ~ "Target schedule unavailable",
        !is.finite(projected_classlist_total) ~
          "Insufficient history for a registration-demand estimate",
        !is.finite(projected_first_day_equivalent) ~
          "Insufficient first-day history for a seat comparison",
        projected_over_capacity <= 0 ~ "Expected first-day enrollment fits scheduled capacity",
        capacity_limit_signal ~ "Seat ceiling likely limits observed enrollment",
        TRUE ~ "Projected demand exceeds planned capacity"
      ),
      capacity_limit_note = dplyr::case_when(
        !target_schedule_available ~
          "No target schedule is available for a seat-ceiling check",
        !is.finite(projected_classlist_total) ~
          "Class-list demand is not yet stable",
        !is.finite(projected_first_day_equivalent) ~
          "First-day retention cannot be measured from the comparable history",
        projected_over_capacity <= 0 ~ paste(
          round(scheduled_capacity - projected_first_day_equivalent),
          "planned seat(s) remain above expected first-day occupancy"
        ),
        capacity_limit_signal ~ paste0(
          "Expected first-day enrollment exceeds capacity by ",
          round(projected_over_capacity), "; ",
          round(target_available_seats),
          " seat(s) are currently unoccupied"
        ),
        TRUE ~ paste0(
          "Expected first-day enrollment exceeds capacity by ",
          round(projected_over_capacity), "; active registration fill is ",
          scales::percent(target_active_fill, accuracy = 0.1)
        )
      ),
      recommended_sections = projection_sections_for_demand(
        projected_first_day_equivalent, reference_section_size
      ),
      additional_sections = projection_additional_sections(
        recommended_sections, scheduled_sections
      ),
      methods_disagree = dplyr::if_else(
        is.finite(projected_classlist_total) & projected_classlist_total > 0 &
          is.finite(candidate_spread),
        candidate_spread / projected_classlist_total >=
          as.numeric(opt$disagreement_threshold %||% 0.20),
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
        accuracy == "Poor" & methods_disagree ~ paste0(
          accuracy_reason, "; candidate methods also disagree materially"
        ),
        accuracy == "Poor" ~ accuracy_reason,
        stability == "Volatile" ~ paste0(
          "Aftcasts land within ", accuracy, " range, but the course's own ",
          "history is volatile: ", stability_reason
        ),
        TRUE ~ paste0(accuracy_reason, "; ", stability_reason)
      ),
      recommendation = dplyr::case_when(
        !is.finite(projected_classlist_total) ~ "Insufficient history",
        projected_classlist_total <= 0 ~ "No projected demand",
        !is.finite(projected_first_day_equivalent) ~
          "Insufficient first-day history",
        !target_schedule_available & !is.na(recommended_sections) &
          adjusted_saturated_prior %in% TRUE ~
          paste("Plan at least", recommended_sections, "section(s); prior term was saturated"),
        !target_schedule_available & !is.na(recommended_sections) ~
          paste("Plan", recommended_sections, "section(s)"),
        is.finite(projection_high_first_day_equivalent) &
          projection_high_first_day_equivalent <= scheduled_capacity ~
          "Capacity appears sufficient",
        !is.na(additional_sections) & additional_sections > 0 &
          (scheduled_sections == 0L |
            seat_gap >= pmax(
              as.numeric(opt$recommendation_min_seat_gap %||% 10),
              0.25 * reference_section_size
            )) ~
          paste("Add", additional_sections, "section(s)"),
        seat_gap > 0 ~ paste("Open", seat_gap, "additional seat(s)"),
        methods_disagree ~ "Review method disagreement",
        TRUE ~ "Monitor near capacity"
      )
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-method_rank)
}


validate_enrollment_projection_model_provenance <- function(
    provenance, model_version, schema_version) {
  provenance_required <- c(
    "model_version", "schema_version", "git_commit",
    "relevant_worktree_dirty", "source_hashes", "source_snapshot"
  )
  if (!is.list(provenance)) {
    stop("[enrollment-projections.R] Projection model_provenance must be a list.",
         call. = FALSE)
  }
  provenance_missing <- setdiff(provenance_required, names(provenance))
  if (length(provenance_missing) > 0L) {
    stop(
      "[enrollment-projections.R] Projection model_provenance is missing: ",
      paste(provenance_missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (!identical(as.character(provenance$model_version),
                 as.character(model_version)) ||
      !identical(as.integer(provenance$schema_version),
                 as.integer(schema_version))) {
    stop(
      "[enrollment-projections.R] Model provenance versions do not match the bundle.",
      call. = FALSE
    )
  }
  git_commit_valid <- is.character(provenance$git_commit) &&
    length(provenance$git_commit) == 1L &&
    (is.na(provenance$git_commit) ||
       grepl("^[0-9a-f]{40}$", provenance$git_commit))
  dirty_valid <- is.logical(provenance$relevant_worktree_dirty) &&
    length(provenance$relevant_worktree_dirty) == 1L
  hashes <- provenance$source_hashes
  snapshot <- provenance$source_snapshot
  source_names_valid <- is.character(hashes) && is.character(snapshot) &&
    length(hashes) > 0L && length(snapshot) > 0L &&
    !is.null(names(hashes)) && !is.null(names(snapshot)) &&
    identical(names(hashes), names(snapshot)) &&
    all(!is.na(names(hashes)) & nzchar(names(hashes))) &&
    all(!is.na(hashes) & grepl("^[0-9a-f]{64}$", hashes)) &&
    all(!is.na(snapshot))
  if (!git_commit_valid || !dirty_valid || !source_names_valid) {
    stop("[enrollment-projections.R] Projection model provenance is invalid.",
         call. = FALSE)
  }
  calculated_hashes <- vapply(
    snapshot,
    digest::digest,
    character(1),
    algo = "sha256",
    serialize = FALSE,
    USE.NAMES = TRUE
  )
  if (!identical(unname(calculated_hashes), unname(hashes))) {
    stop(
      "[enrollment-projections.R] Saved model source does not match its hashes.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


new_enrollment_projection_bundle <- function(analysis, target_term, as_of_term,
                                             scope_courses, scope_campuses,
                                             scope_market_id,
                                             model_provenance,
                                             model_config =
                                               enrollment_projection_model_config(),
                                             source_fingerprint = list(),
                                             built_at = Sys.time()) {
  bundle <- list(
    schema_version = CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION,
    model_version = CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION,
    built_at = as.POSIXct(built_at, tz = "UTC"),
    target_term = as.integer(target_term),
    as_of_term = as.integer(as_of_term),
    scope_courses = sort(unique(as.character(scope_courses))),
    scope_campuses = sort(unique(as.character(scope_campuses))),
    scope_market_id = as.character(scope_market_id),
    model_config = model_config,
    model_provenance = model_provenance,
    source_fingerprint = source_fingerprint,
    pressure_screen = analysis$pressure_screen,
    projections = analysis$projections,
    delivery_components = analysis$delivery_components,
    candidates = analysis$candidates,
    backtests = analysis$backtests,
    method_performance = analysis$method_performance,
    recent_history = analysis$recent_history,
    cohort_composition = analysis$cohort_composition
  )
  validate_enrollment_projection_bundle(bundle)
  bundle
}


validate_enrollment_projection_bundle <- function(bundle) {
  required <- c(
    "schema_version", "model_version", "built_at", "target_term", "as_of_term",
    "scope_courses", "scope_campuses", "scope_market_id", "model_config",
    "model_provenance", "source_fingerprint", "pressure_screen", "projections",
    "delivery_components", "candidates", "backtests", "method_performance",
    "recent_history", "cohort_composition"
  )
  missing <- setdiff(required, names(bundle))
  if (length(missing) > 0) {
    stop("[enrollment-projections.R] Projection bundle is missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!identical(as.integer(bundle$schema_version),
                 CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION)) {
    stop("[enrollment-projections.R] Unsupported projection bundle schema version.",
         call. = FALSE)
  }
  if (!identical(as.character(bundle$model_version),
                 CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION)) {
    stop("[enrollment-projections.R] Unsupported projection model version.",
         call. = FALSE)
  }
  validate_enrollment_projection_model_provenance(
    bundle$model_provenance,
    model_version = bundle$model_version,
    schema_version = bundle$schema_version
  )
  if (!is.list(bundle$model_config)) {
    stop("[enrollment-projections.R] Projection model_config must be a list.",
         call. = FALSE)
  }
  config_required <- names(enrollment_projection_model_config())
  config_missing <- setdiff(config_required, names(bundle$model_config))
  if (length(config_missing) > 0) {
    stop(
      "[enrollment-projections.R] Projection model_config is missing: ",
      paste(config_missing, collapse = ", "),
      call. = FALSE
    )
  }
  enrollment_projection_model_config(bundle$model_config)
  if (length(bundle$target_term) != 1L || is.na(bundle$target_term) ||
      length(bundle$as_of_term) != 1L || is.na(bundle$as_of_term) ||
      as.integer(bundle$as_of_term) >= as.integer(bundle$target_term)) {
    stop("[enrollment-projections.R] Bundle cutoff must precede its target term.",
         call. = FALSE)
  }
  if (length(bundle$scope_courses) == 0L ||
      any(is.na(bundle$scope_courses) | !nzchar(bundle$scope_courses)) ||
      length(bundle$scope_campuses) == 0L ||
      any(is.na(bundle$scope_campuses) | !nzchar(bundle$scope_campuses)) ||
      length(bundle$scope_market_id) != 1L || is.na(bundle$scope_market_id) ||
      !nzchar(bundle$scope_market_id)) {
    stop("[enrollment-projections.R] Bundle course, campus, and market scopes are required.",
         call. = FALSE)
  }

  scoped_tables <- c(
    "pressure_screen", "projections", "delivery_components", "candidates",
    "backtests", "method_performance", "recent_history"
  )
  for (table_name in scoped_tables) {
    data <- bundle[[table_name]]
    if ("subject_course" %in% names(data) &&
        any(!data$subject_course %in% bundle$scope_courses)) {
      stop("[enrollment-projections.R] ", table_name,
           " contains a course outside the saved scope.", call. = FALSE)
    }
    if ("campus" %in% names(data) &&
        any(!data$campus %in% bundle$scope_campuses)) {
      stop("[enrollment-projections.R] ", table_name,
           " contains a campus outside the saved scope.", call. = FALSE)
    }
    if ("market_id" %in% names(data) &&
        any(data$market_id != bundle$scope_market_id)) {
      stop("[enrollment-projections.R] ", table_name,
           " contains a market outside the saved scope.", call. = FALSE)
    }
  }

  projection_require_columns(
    bundle$pressure_screen,
    c(
      "market_id", "subject_course", "target_term", "scheduled_capacity",
      "target_classlist_total_to_date", "target_registered_now",
      "target_early_drops_to_date", "target_late_drops_to_date",
      "target_other_status_to_date",
      "target_registration_observed", "target_available_seats",
      "target_classlist_fill", "target_active_fill", "target_capacity_reached",
      "recent_high_fill_terms", "recent_capacity_terms", "is_forced",
      "pressure_capacity_shortfall", "pressure_chronic_fill",
      "pressure_growth", "included", "inclusion_reason"
    ),
    "validate_enrollment_projection_bundle() pressure_screen"
  )
  projection_require_columns(
    bundle$projections,
    c("market_id", "college", "department", "subject_course", "target_term",
      "projected_classlist_total", "method_id",
      "stability", "stability_reason", "history_terms", "history_cv",
      "depth", "depth_reason", "accuracy", "accuracy_reason",
      "why_uncertain", "recommendation",
      "target_term_label", "backtest_terms", "backtest_term_range",
      "selection_wape", "selection_n_backtests", "selection_basis",
      "selection_pct_error_sd", "selection_common_n",
      "selection_default_wape", "selection_challenger_wape",
      "selection_reason", "capacity_constrained_history",
      "observed_baseline", "capacity_data_quality",
      "target_schedule_available", "raw_projected_classlist_total",
      "first_day_retention_rate", "first_day_retention_n_terms",
      "first_day_retention_terms", "projected_first_day_equivalent",
      "weighted_bias", "direction_consistency", "signed_error_history",
      "capacity_censored_wape", "n_capacity_censored_misses",
      "capacity_explained_error_share", "capacity_miss_assessment",
      "target_classlist_total_to_date", "target_registered_now",
      "target_early_drops_to_date", "target_late_drops_to_date",
      "target_other_status_to_date",
      "target_registration_observed", "target_available_seats",
      "target_classlist_fill", "target_active_fill", "target_capacity_reached",
      "projected_over_capacity",
      "capacity_limit_signal", "capacity_limit_status",
      "capacity_limit_note", "recommended_sections",
      "adjusted_projection", "adjusted_applicable", "adjusted_reason",
      "adjusted_saturated_prior", "adjusted_floor_uplift",
      "adjusted_floor_basis", "adjusted_delta_repeat", "adjusted_delta_feeder",
      "adjusted_regime_alarm", "adjusted_delta_basis",
      "expansion_pairs", "expansion_fill_rate", "expansion_note",
      "floor_note", "regime_note"),
    "validate_enrollment_projection_bundle() projections"
  )
  projection_require_columns(
    bundle$recent_history,
    c(
      "market_id", "subject_course", "term_type",
      "projection_target_term", "history_term", "history_term_label",
      "recency_rank", "actual_classlist_total", "actual_first_day",
      "actual_census", "actual_final_enrollment", "capacity_usable",
      "scheduled_sections", "scheduled_capacity", "method_id",
      "prior_classlist_total", "prior_scheduled_capacity",
      "classlist_change", "capacity_change",
      "method_label", "aftcast_method_id", "aftcast_method_label",
      "aftcast_applicable", "aftcast_reason",
      "aftcast_classlist_total", "aftcast_error",
      "aftcast_pct_error", "first_day_fill", "first_day_capacity_gap",
      "capacity_reached",
      "aftcast_capacity_censored", "aftcast_censored_error",
      "aftcast_censored_pct_error", "potential_miss_explanation",
      "source_term", "source_term_label", "prior_source_term",
      "prior_source_term_label", "university_students",
      "prior_university_students", "university_student_change",
      "university_incoming_first_sem",
      "prior_university_incoming_first_sem", "university_incoming_change",
      "market_students", "prior_market_students", "market_student_change",
      "source_outcomes_complete", "source_graded_students",
      "source_dfw_students", "source_dfw_rate",
      "prior_source_dfw_students", "prior_source_dfw_rate",
      "source_dfw_student_change", "source_dfw_rate_change",
      "source_dfw_next_term_repeaters", "source_dfw_repeater_share",
      "movement_context"
    ),
    "validate_enrollment_projection_bundle() recent_history"
  )
  projection_require_columns(
    bundle$candidates,
    c("market_id", "college", "subject_course", "target_term", "method_id",
      "method_role", "projected_classlist_total", "applicable", "selected",
      "first_day_retention_rate", "first_day_retention_n_terms",
      "first_day_retention_terms", "projected_first_day_equivalent",
      "target_term_label", "n_backtests", "backtest_terms",
      "backtest_term_range", "wape", "first_day_equivalent_wape",
      "capacity_censored_wape",
      "uncensored_wape", "raw_projected_classlist_total", "weighted_bias",
      "pct_error_sd", "uncensored_pct_error_sd", "direction_consistency",
      "signed_error_history",
      "n_capacity_censored_misses",
      "capacity_explained_wape", "capacity_explained_error_share",
      "capacity_censored_terms", "capacity_miss_assessment",
      "spine", "spine_term", "saturated_prior", "prior_first_day_fill",
      "waitlisted_prior", "floor_uplift", "floor_basis", "preceding_term",
      "preceding_term_enrollment", "preceding_term_change", "regime_alarm",
      "delta_repeat", "repeat_rate", "delta_feeder", "feeder_rate",
      "feeder_courses", "feeder_change", "delta_basis", "projection_formula"),
    "validate_enrollment_projection_bundle() candidates"
  )
  projection_require_columns(
    bundle$delivery_components,
    c("market_id", "campus", "college", "subject_course", "part_term",
      "target_term", "scheduled_sections", "scheduled_capacity",
      "capacity_share"),
    "validate_enrollment_projection_bundle() delivery_components"
  )
  projection_require_columns(
    bundle$method_performance,
    c(
      "market_id", "college", "subject_course", "term_type", "method_id",
      "method_label", "wape", "weighted_bias", "pct_error_sd",
      "uncensored_pct_error_sd",
      "direction_consistency", "signed_error_history",
      "capacity_censored_wape", "first_day_equivalent_wape",
      "n_capacity_censored_misses", "capacity_explained_wape",
      "capacity_explained_error_share", "capacity_censored_terms",
      "capacity_miss_assessment"
    ),
    "validate_enrollment_projection_bundle() method_performance"
  )
  if (nrow(bundle$backtests) > 0) {
    projection_require_columns(
      bundle$backtests,
      c(
        "method_role", "raw_projected_classlist_total",
        "actual_classlist_total", "actual_first_day", "actual_census",
        "actual_final_enrollment",
        "projected_first_day_equivalent", "capacity_fill",
        "capacity_gap", "capacity_reached", "policy_selected",
        "capacity_censored_classlist_projection",
        "capacity_censored_error", "capacity_censored_abs_error",
        "capacity_censored_miss", "capacity_explained_classlist_error",
        "capacity_explained_share"
      ),
      "validate_enrollment_projection_bundle() backtests"
    )
  }
  # Each reader-facing axis has its own vocabulary and is checked separately.
  # They are allowed to disagree -- a Stable course with Thin depth and Unrated
  # accuracy is a real and common state -- so a shared check would have to
  # accept every value on every axis and would catch nothing.
  axis_values <- list(
    stability = c("Stable", "Moderate", "Volatile", "Unrated"),
    depth     = c("Deep", "Moderate", "Thin", "None"),
    accuracy  = c("Close", "Fair", "Poor", "Unrated")
  )
  for (axis in names(axis_values)) {
    invalid <- setdiff(unique(bundle$projections[[axis]]), axis_values[[axis]])
    if (length(invalid) > 0L) {
      stop(
        "[enrollment-projections.R] Projection ", axis,
        " contains unsupported values: ",
        paste(invalid, collapse = ", "),
        call. = FALSE
      )
    }
  }

  projection_keys <- c("market_id", "subject_course", "target_term")
  duplicate_projections <- bundle$projections %>%
    dplyr::count(dplyr::across(dplyr::all_of(projection_keys))) %>%
    dplyr::filter(n > 1)
  if (nrow(duplicate_projections) > 0) {
    stop("[enrollment-projections.R] Projection bundle has duplicate published rows.",
         call. = FALSE)
  }
  duplicate_candidates <- bundle$candidates %>%
    dplyr::count(
      dplyr::across(dplyr::all_of(c(projection_keys, "method_id")))
    ) %>%
    dplyr::filter(n > 1)
  if (nrow(duplicate_candidates) > 0) {
    stop("[enrollment-projections.R] Projection bundle has duplicate candidates.",
         call. = FALSE)
  }
  validate_spine_rows(
    bundle$candidates, "validate_enrollment_projection_bundle() candidates"
  )
  if (nrow(bundle$backtests) > 0) {
    validate_spine_rows(
      bundle$backtests, "validate_enrollment_projection_bundle() backtests"
    )
    validate_projection_capacity_rows(
      bundle$backtests,
      "validate_enrollment_projection_bundle() backtests"
    )
  }
  component_keys <- c(
    "market_id", "campus", "college", "subject_course", "part_term",
    "target_term"
  )
  duplicate_components <- bundle$delivery_components %>%
    dplyr::count(dplyr::across(dplyr::all_of(component_keys))) %>%
    dplyr::filter(n > 1)
  if (nrow(duplicate_components) > 0) {
    stop("[enrollment-projections.R] Projection bundle has duplicate delivery components.",
         call. = FALSE)
  }

  target_term <- as.integer(bundle$target_term)
  projection_targets_match <- all(
    !is.na(bundle$projections$target_term) &
      as.integer(bundle$projections$target_term) == target_term
  )
  candidate_targets_match <- all(
    !is.na(bundle$candidates$target_term) &
      as.integer(bundle$candidates$target_term) == target_term
  )
  component_targets_match <- all(
    !is.na(bundle$delivery_components$target_term) &
      as.integer(bundle$delivery_components$target_term) == target_term
  )
  if (!projection_targets_match || !candidate_targets_match ||
      !component_targets_match) {
    stop("[enrollment-projections.R] Saved rows do not match the bundle target term.",
         call. = FALSE)
  }
  recent_targets_match <- all(
    !is.na(bundle$recent_history$projection_target_term) &
      as.integer(bundle$recent_history$projection_target_term) == target_term &
      as.integer(bundle$recent_history$history_term) < target_term
  )
  if (!recent_targets_match) {
    stop("[enrollment-projections.R] Recent history has invalid target terms.",
         call. = FALSE)
  }
  if (nrow(bundle$recent_history) > 0L) {
    recent_starts <- projection_course_history_starts(
      bundle$recent_history$subject_course, bundle$model_config
    )
    if (any(bundle$recent_history$history_term < recent_starts)) {
      stop("[enrollment-projections.R] Recent history precedes its model window.",
           call. = FALSE)
    }
    recent_duplicates <- bundle$recent_history %>%
      dplyr::count(
        market_id, subject_course, projection_target_term, history_term
      ) %>%
      dplyr::filter(n > 1L)
    if (nrow(recent_duplicates) > 0L) {
      stop("[enrollment-projections.R] Recent history contains duplicate terms.",
           call. = FALSE)
    }
  }
  if (nrow(bundle$backtests) > 0L) {
    backtest_starts <- projection_course_history_starts(
      bundle$backtests$subject_course, bundle$model_config
    )
    if (any(bundle$backtests$target_term < backtest_starts)) {
      stop("[enrollment-projections.R] Aftcasts precede their model window.",
           call. = FALSE)
    }
  }

  # CAMPUS_ROLLUP: reconcile the named market total back to every saved campus
  # and part-term component so the rollup cannot silently lose a delivery.
  component_totals <- bundle$delivery_components %>%
    dplyr::group_by(market_id, subject_course, target_term) %>%
    dplyr::summarise(
      component_sections = sum(scheduled_sections, na.rm = TRUE),
      component_capacity = sum(scheduled_capacity, na.rm = TRUE),
      .groups = "drop"
    )
  capacity_audit <- bundle$pressure_screen %>%
    dplyr::select(
      market_id, subject_course, target_term,
      scheduled_sections, scheduled_capacity
    ) %>%
    dplyr::left_join(
      component_totals,
      by = c("market_id", "subject_course", "target_term")
    ) %>%
    dplyr::mutate(
      component_sections = dplyr::coalesce(component_sections, 0),
      component_capacity = dplyr::coalesce(component_capacity, 0)
    ) %>%
    dplyr::filter(
      scheduled_sections != component_sections |
        abs(scheduled_capacity - component_capacity) > 1e-8
    )
  if (nrow(capacity_audit) > 0) {
    stop("[enrollment-projections.R] Delivery components do not reconcile to market capacity.",
         call. = FALSE)
  }

  expected_selected <- bundle$projections %>%
    dplyr::filter(method_id != "none") %>%
    dplyr::select(dplyr::all_of(projection_keys), method_id)
  actual_selected <- bundle$candidates %>%
    dplyr::filter(!is.na(selected), selected) %>%
    dplyr::select(dplyr::all_of(projection_keys), method_id)
  missing_selected <- dplyr::anti_join(
    expected_selected, actual_selected,
    by = c(projection_keys, "method_id")
  )
  unexpected_selected <- dplyr::anti_join(
    actual_selected, expected_selected,
    by = c(projection_keys, "method_id")
  )
  if (nrow(missing_selected) > 0 || nrow(unexpected_selected) > 0) {
    stop("[enrollment-projections.R] Published methods and selected candidates disagree.",
         call. = FALSE)
  }
  numeric_audit <- bundle$projections %>%
    dplyr::filter(method_id != "none") %>%
    dplyr::select(
      dplyr::all_of(projection_keys), method_id,
      published_projection = projected_classlist_total,
      published_raw = raw_projected_classlist_total
    ) %>%
    dplyr::inner_join(
      bundle$candidates %>%
        dplyr::filter(!is.na(selected), selected) %>%
        dplyr::select(
          dplyr::all_of(projection_keys), method_id,
          candidate_raw = raw_projected_classlist_total
        ),
      by = c(projection_keys, "method_id")
    ) %>%
    dplyr::mutate(
      rounded_matches =
        (is.na(published_projection) & is.na(candidate_raw)) |
        dplyr::near(published_projection, round(candidate_raw), tol = 1e-8),
      raw_matches =
        (is.na(published_raw) & is.na(candidate_raw)) |
        dplyr::near(published_raw, candidate_raw, tol = 1e-8)
    ) %>%
    dplyr::filter(
      !dplyr::coalesce(rounded_matches, FALSE) |
        !dplyr::coalesce(raw_matches, FALSE)
    )
  if (nrow(numeric_audit) > 0L) {
    stop(
      "[enrollment-projections.R] Published projection values and selected candidates disagree.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


write_enrollment_projection_bundle <- function(bundle, path) {
  validate_enrollment_projection_bundle(bundle)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp_path <- paste0(path, ".tmp")
  if (grepl("\\.qs$", path, ignore.case = TRUE)) {
    qs2::qs_save(bundle, tmp_path)
  } else if (grepl("\\.Rds$", path, ignore.case = TRUE)) {
    saveRDS(bundle, tmp_path)
  } else {
    stop("[enrollment-projections.R] Bundle path must end in .qs or .Rds.",
         call. = FALSE)
  }
  if (!file.rename(tmp_path, path)) {
    stop("[enrollment-projections.R] Could not atomically publish bundle: ", path,
         call. = FALSE)
  }
  invisible(path)
}


read_enrollment_projection_bundle <- function(path) {
  if (!file.exists(path)) {
    stop("[enrollment-projections.R] Projection bundle not found: ", path,
         call. = FALSE)
  }
  bundle <- if (grepl("\\.qs$", path, ignore.case = TRUE)) {
    qs2::qs_read(path)
  } else if (grepl("\\.Rds$", path, ignore.case = TRUE)) {
    readRDS(path)
  } else {
    stop("[enrollment-projections.R] Bundle path must end in .qs or .Rds.",
         call. = FALSE)
  }
  validate_enrollment_projection_bundle(bundle)
  bundle
}
