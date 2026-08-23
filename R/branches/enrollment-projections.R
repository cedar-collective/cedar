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
  defaults <- list(
    seasonal_window = 4L,
    seasonal_min_terms = 2L,
    trend_window = 6L,
    trend_min_terms = 3L,
    transition_window = 5L,
    transition_min_terms = 2L,
    feeder_min_students = 3L,
    feeder_max_courses = 8L,
    transition_min_coverage = 0.10,
    spring_source_min_population = 20L,
    spring_source_min_coverage = 0.10,
    spring_growth_prior_strength = 20,
    history_start_term = CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM,
    course_history_start_terms =
      CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS,
    recent_history_terms = 3L,
    projection_methods = names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
    summer = FALSE,
    pressure_min_seat_gap = 10,
    pressure_fill_threshold = 0.90,
    pressure_chronic_terms = 2L,
    pressure_history_window = 3L,
    backtest_terms = 6L,
    registration_capacity_threshold = 1.00,
    capacity_explained_share_threshold = 0.50,
    census_retention_window = 4L,
    census_retention_min_terms = 2L,
    course_census_retention_min_terms =
      CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS,
    calibration_min_terms = 4L,
    calibration_min_abs_bias = 0.05,
    calibration_min_direction_consistency = 0.75,
    calibration_factor_bounds =
      CEDAR_ENROLLMENT_PROJECTION_CALIBRATION_FACTOR_BOUNDS,
    calibration_neutral_error = 0.01,
    calibration_min_validation_terms = 2L,
    calibration_min_wape_gain = 0.01,
    selection_min_backtests = 2L,
    uncensored_selection_min_backtests = 2L,
    upstream_anchor_weight = 0.50,
    upstream_tie_margin = 0.02,
    upstream_capped_tie_margin = 0.05,
    capacity_constrained_share = 0.50,
    demand_history_window = 5L,
    demand_recent_window = 3L,
    capacity_response_fraction = 0.50,
    demand_min_growth_per_year = 2,
    demand_min_growth_share = 0.02,
    structural_min_backtests = 3L,
    structural_min_coverage = 0.40,
    structural_max_wape = 0.20,
    disagreement_threshold = 0.20,
    demand_min_structural_gap = 10,
    demand_min_structural_gap_share = 0.10,
    recommendation_min_seat_gap = 10
  )
  config <- utils::modifyList(defaults, opt)
  bounds <- as.numeric(config$calibration_factor_bounds)
  safety_bounds <- CEDAR_ENROLLMENT_PROJECTION_CALIBRATION_FACTOR_BOUNDS
  if (length(bounds) != 2L || any(!is.finite(bounds)) ||
      min(bounds) < min(safety_bounds) || max(bounds) > max(safety_bounds)) {
    stop(
      "[enrollment-projections.R] calibration_factor_bounds must stay within ",
      paste(safety_bounds, collapse = " to "), ".",
      call. = FALSE
    )
  }
  config$calibration_factor_bounds <- sort(bounds)
  anchor_weight <- as.numeric(config$upstream_anchor_weight)
  if (length(anchor_weight) != 1L || !is.finite(anchor_weight) ||
      anchor_weight < 0 || anchor_weight > 1) {
    stop(
      "[enrollment-projections.R] upstream_anchor_weight must be between 0 and 1.",
      call. = FALSE
    )
  }
  config$upstream_anchor_weight <- anchor_weight
  history_start <- suppressWarnings(as.integer(config$history_start_term))
  if (length(history_start) != 1L || is.na(history_start)) {
    stop("[enrollment-projections.R] history_start_term must be one YYYYSS term.",
         call. = FALSE)
  }
  config$history_start_term <- history_start
  for (field in c(
    "course_history_start_terms", "course_census_retention_min_terms"
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
  if (any(config$course_census_retention_min_terms < 1L)) {
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


projection_registration_capacity_metrics <- function(
    registrations, capacity, reached_threshold = 1) {
  registrations <- as.numeric(registrations)
  capacity <- as.numeric(capacity)
  registration_fill <- dplyr::if_else(
    is.finite(capacity) & capacity > 0,
    registrations / capacity,
    NA_real_
  )
  capacity_usable <- is.finite(registration_fill)

  tibble::tibble(
    registration_fill = registration_fill,
    registration_capacity_gap = dplyr::if_else(
      capacity_usable,
      capacity - registrations,
      NA_real_
    ),
    capacity_usable = capacity_usable,
    capacity_reached = capacity_usable &
      registration_fill >= as.numeric(reached_threshold)
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


prepare_projection_market_enrollment_history <- function(students, courses,
                                                         campuses, market_id,
                                                         through_term = NULL) {
  projection_require_columns(
    students,
    c("student_id", "term", "campus", "college", "subject_course",
      "registration_status_code"),
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
    dplyr::mutate(
      market_id = as.character(market_id),
      term_type = vapply(term, get_term_type, character(1)),
      census_retention_rate = dplyr::if_else(
        classlist_total > 0, census_enrl / classlist_total, NA_real_
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


prepare_projection_spring_inputs <- function(student_terms, target_students) {
  projection_require_columns(
    student_terms,
    c("student_id", "term", "major_code", "student_classification"),
    "prepare_projection_spring_inputs() student_terms"
  )
  projection_require_columns(
    target_students,
    c("student_id", "term", "subject_course"),
    "prepare_projection_spring_inputs() target_students"
  )

  source_populations <- student_terms %>%
    dplyr::filter(term %% 100L == 80L) %>%
    dplyr::count(
      term, major_code, student_classification, name = "n_population"
    )
  spring_targets <- target_students %>%
    dplyr::filter(term %% 100L == 10L) %>%
    dplyr::transmute(
      student_id, target_term = term, subject_course,
      source_term = (term %/% 100L - 1L) * 100L + 80L
    )
  matched <- spring_targets %>%
    dplyr::left_join(
      student_terms %>%
        dplyr::transmute(
          student_id, source_term = term, major_code, student_classification
        ),
      by = c("student_id", "source_term")
    ) %>%
    dplyr::mutate(
      source_matched = !is.na(major_code) & !is.na(student_classification)
    )

  list(
    source_populations = source_populations,
    cohort_cells = matched %>%
      dplyr::filter(source_matched) %>%
      dplyr::count(
        subject_course, target_term, source_term,
        major_code, student_classification,
        name = "n_target_baseline"
      ),
    cohort_totals = matched %>%
      # CAMPUS_ROLLUP: targets were deduplicated across the named market before
      # this course-level matched/unmatched decomposition was prepared.
      dplyr::group_by(subject_course, target_term, source_term) %>%
      dplyr::summarise(
        baseline_classlist_total = dplyr::n(),
        matched_baseline = sum(source_matched),
        unmatched_baseline = sum(!source_matched),
        .groups = "drop"
      )
  )
}


prepare_projection_student_inputs <- function(students, target_courses,
                                              campuses = NULL,
                                              through_term = NULL,
                                              from_term = NULL) {
  projection_require_columns(
    students,
    c("student_id", "term", "campus", "college", "subject_course",
      "part_term", "registration_status_code", "major_code",
      "student_classification"),
    "prepare_projection_student_inputs()"
  )

  classlist_rows <- students %>%
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
    classlist_rows <- dplyr::filter(
      classlist_rows, term <= as.integer(through_term[[1]])
    )
  }
  if (!is.null(from_term) && length(from_term) > 0) {
    classlist_rows <- dplyr::filter(
      classlist_rows, term >= as.integer(from_term[[1]])
    )
  }
  if (!is.null(campuses) && length(campuses) > 0) {
    classlist_rows <- dplyr::filter(
      classlist_rows, campus %in% .env$campuses
    )
  }

  # CAMPUS_ROLLUP: feeder membership is deduplicated across the declared market.
  course_enrollments <- classlist_rows %>%
    dplyr::distinct(student_id, term, subject_course)

  student_terms <- classlist_rows %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarise(
      major_code = projection_mode_character(major_code),
      student_classification = projection_mode_character(student_classification),
      .groups = "drop"
    )

  # CAMPUS_ROLLUP: a student taking the target in either delivery counts once.
  target_students <- classlist_rows %>%
    dplyr::filter(subject_course %in% .env$target_courses) %>%
    dplyr::distinct(student_id, term, subject_course)

  spring <- prepare_projection_spring_inputs(student_terms, target_students)

  list(
    course_enrollments = course_enrollments,
    student_terms = student_terms,
    target_students = target_students,
    spring = spring
  )
}


prepare_enrollment_projection_inputs <- function(cl_enrls, sections, students,
                                                 target_courses,
                                                 target_campuses,
                                                 target_market_id,
                                                 enrollment_through_term = NULL,
                                                 section_through_term = NULL,
                                                 history_start_term = NULL,
                                                 course_history_start_terms =
                                                   integer(0)) {
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
    students, courses = target_courses, campuses = target_campuses,
    market_id = target_market_id,
    through_term = enrollment_through_term
  )
  market_section_history <- prepare_projection_market_section_history(
    delivery_section_history, market_id = target_market_id
  )
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
    target_registration_snapshot = prepare_projection_market_enrollment_history(
      students, courses = target_courses, campuses = target_campuses,
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
      from_term = student_source_start
    ),
    target_courses = target_courses,
    target_campuses = target_campuses,
    target_market_id = target_market_id,
    enrollment_through_term = if (is.null(enrollment_through_term)) NULL else
      as.integer(enrollment_through_term[[1]]),
    section_through_term = if (is.null(section_through_term)) NULL else
      as.integer(section_through_term[[1]]),
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


projection_census_retention_for_row <- function(history, row, target_term,
                                                opt = list()) {
  window <- as.integer(opt$census_retention_window %||% 4L)
  min_terms <- as.integer(projection_named_course_value(
    row$subject_course,
    opt$course_census_retention_min_terms %||%
      CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS,
    opt$census_retention_min_terms %||% 2L
  ))
  prior <- projection_history_for_row(
    history, row, before_term = target_term
  ) %>%
    dplyr::filter(classlist_total > 0) %>%
    dplyr::slice_tail(n = window)
  rate <- if (nrow(prior) >= min_terms && sum(prior$classlist_total) > 0) {
    sum(prior$census_enrl) / sum(prior$classlist_total)
  } else {
    NA_real_
  }

  tibble::tibble(
    census_retention_rate = as.numeric(rate),
    census_retention_n_terms = as.integer(nrow(prior)),
    census_retention_terms = paste(prior$term, collapse = ","),
    census_retention_term_labels = paste(
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


projection_candidate <- function(method_id, estimate = NA_real_, applicable = FALSE,
                                 reason = "Insufficient evidence",
                                 n_history_terms = 0L, evidence_n = 0L,
                                 coverage_rate = NA_real_, n_components = 0L,
                                 component_summary = NA_character_,
                                 baseline_term = NA_integer_,
                                 prior_source_term = NA_integer_,
                                 source_term = NA_integer_,
                                 baseline_classlist_total = NA_real_,
                                 matched_baseline = NA_real_,
                                 unmatched_baseline = NA_real_,
                                 matched_projection = NA_real_,
                                 unmatched_projection = NA_real_,
                                 source_population_previous = NA_real_,
                                 source_population_current = NA_real_,
                                 source_population_growth = NA_real_,
                                 projection_formula = NA_character_) {
  tibble::tibble(
    method_id = method_id,
    method_label = unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[method_id]]),
    method_role = unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[[method_id]]),
    projected_classlist_total = as.numeric(estimate),
    census_retention_rate = NA_real_,
    census_retention_n_terms = 0L,
    census_retention_terms = NA_character_,
    census_retention_term_labels = NA_character_,
    projected_census_equivalent = NA_real_,
    applicable = isTRUE(applicable),
    applicability_reason = as.character(reason),
    n_history_terms = as.integer(n_history_terms),
    evidence_n = as.integer(evidence_n),
    coverage_rate = as.numeric(coverage_rate),
    n_components = as.integer(n_components),
    component_summary = as.character(component_summary),
    baseline_term = as.integer(baseline_term),
    prior_source_term = as.integer(prior_source_term),
    source_term = as.integer(source_term),
    baseline_classlist_total = as.numeric(baseline_classlist_total),
    matched_baseline = as.numeric(matched_baseline),
    unmatched_baseline = as.numeric(unmatched_baseline),
    matched_projection = as.numeric(matched_projection),
    unmatched_projection = as.numeric(unmatched_projection),
    source_population_previous = as.numeric(source_population_previous),
    source_population_current = as.numeric(source_population_current),
    source_population_growth = as.numeric(source_population_growth),
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
    )
  )
}


project_seasonal_median <- function(history, row, target_term, opt = list()) {
  window <- as.integer(opt$seasonal_window %||% 4L)
  min_terms <- as.integer(opt$seasonal_min_terms %||% 2L)
  prior <- projection_history_for_row(history, row, before_term = target_term) %>%
    dplyr::slice_tail(n = window)

  if (nrow(prior) < min_terms) {
    return(projection_candidate(
      "seasonal_median", reason = paste("Needs", min_terms, "same-season terms"),
      n_history_terms = nrow(prior), evidence_n = sum(prior$classlist_total)
    ))
  }

  projection_candidate(
    "seasonal_median",
    estimate = stats::median(prior$classlist_total, na.rm = TRUE),
    applicable = TRUE,
    reason = paste("Median of", nrow(prior), "prior", row$term_type, "terms"),
    n_history_terms = nrow(prior),
    evidence_n = sum(prior$classlist_total, na.rm = TRUE),
    component_summary = paste(
      prior$term, prior$classlist_total, sep = ":", collapse = ", "
    )
  )
}


project_seasonal_trend <- function(history, row, target_term, opt = list()) {
  window <- as.integer(opt$trend_window %||% 6L)
  min_terms <- as.integer(opt$trend_min_terms %||% 3L)
  prior <- projection_history_for_row(history, row, before_term = target_term) %>%
    dplyr::slice_tail(n = window)

  estimate <- projection_linear_estimate(prior$classlist_total)
  if (nrow(prior) < min_terms || !is.finite(estimate)) {
    return(projection_candidate(
      "seasonal_trend", reason = paste("Needs", min_terms, "same-season terms"),
      n_history_terms = nrow(prior), evidence_n = sum(prior$classlist_total)
    ))
  }

  projection_candidate(
    "seasonal_trend",
    estimate = estimate,
    applicable = TRUE,
    reason = paste("Linear trend over", nrow(prior), "prior", row$term_type, "terms"),
    n_history_terms = nrow(prior),
    evidence_n = sum(prior$classlist_total, na.rm = TRUE),
    component_summary = paste(
      prior$term, prior$classlist_total, sep = ":", collapse = ", "
    )
  )
}


projection_training_term_map <- function(history, row, target_term, opt = list()) {
  window <- as.integer(opt$transition_window %||% 5L)
  incl_summer <- isTRUE(opt$summer)
  terms <- projection_history_for_row(history, row, before_term = target_term) %>%
    dplyr::slice_tail(n = window) %>%
    dplyr::pull(term)

  tibble::tibble(
    target_term = as.integer(terms),
    source_term = vapply(
      terms,
      function(x) subtract_term(x, summer = incl_summer),
      integer(1)
    )
  )
}


projection_target_students_for_row <- function(target_students, row, terms) {
  target_students %>%
    dplyr::filter(
      subject_course == row$subject_course,
      term %in% .env$terms
    ) %>%
    dplyr::transmute(student_id, target_term = term) %>%
    dplyr::distinct()
}


project_from_feeders <- function(history, student_inputs, row, target_term,
                                 opt = list()) {
  term_map <- projection_training_term_map(history, row, target_term, opt)
  min_terms <- as.integer(opt$transition_min_terms %||% 2L)
  min_students <- as.integer(opt$feeder_min_students %||% 3L)
  max_feeders <- as.integer(opt$feeder_max_courses %||% 8L)
  min_coverage <- as.numeric(opt$transition_min_coverage %||% 0.10)

  if (nrow(term_map) < min_terms) {
    return(projection_candidate(
      "feeder", reason = paste("Needs", min_terms, "historical transitions"),
      n_history_terms = nrow(term_map)
    ))
  }

  targets <- projection_target_students_for_row(
    student_inputs$target_students, row, term_map$target_term
  )
  sources <- student_inputs$course_enrollments %>%
    dplyr::filter(term %in% term_map$source_term) %>%
    dplyr::inner_join(term_map, by = c("term" = "source_term")) %>%
    dplyr::transmute(student_id, target_term, source_course = subject_course) %>%
    dplyr::filter(source_course != row$subject_course) %>%
    dplyr::distinct()

  if (nrow(targets) == 0 || nrow(sources) == 0) {
    return(projection_candidate(
      "feeder", reason = "No historical source-to-target student pairs",
      n_history_terms = nrow(term_map)
    ))
  }

  feeder_rates <- sources %>%
    dplyr::count(source_course, name = "n_source") %>%
    dplyr::left_join(
      sources %>%
        dplyr::inner_join(targets, by = c("student_id", "target_term")) %>%
        dplyr::group_by(source_course) %>%
        dplyr::summarise(
          n_transition = dplyr::n(),
          n_terms = dplyr::n_distinct(target_term),
          .groups = "drop"
        ),
      by = "source_course"
    ) %>%
    dplyr::mutate(
      n_transition = dplyr::coalesce(n_transition, 0L),
      n_terms = dplyr::coalesce(n_terms, 0L),
      transition_rate = n_transition / n_source
    ) %>%
    dplyr::filter(n_transition >= min_students, n_terms >= min_terms) %>%
    dplyr::arrange(dplyr::desc(n_transition), dplyr::desc(transition_rate)) %>%
    dplyr::slice_head(n = max_feeders)

  if (nrow(feeder_rates) == 0) {
    return(projection_candidate(
      "feeder", reason = "No feeder course met the evidence threshold",
      n_history_terms = nrow(term_map)
    ))
  }

  selected_sources <- sources %>%
    dplyr::filter(source_course %in% feeder_rates$source_course)
  captured <- targets %>%
    dplyr::semi_join(selected_sources, by = c("student_id", "target_term"))
  coverage <- nrow(captured) / nrow(targets)
  if (!is.finite(coverage) || coverage < min_coverage) {
    return(projection_candidate(
      "feeder",
      reason = paste0("Selected feeders cover only ", round(100 * coverage, 1), "% of targets"),
      n_history_terms = nrow(term_map),
      evidence_n = sum(feeder_rates$n_transition),
      coverage_rate = coverage,
      n_components = nrow(feeder_rates)
    ))
  }

  source_term <- subtract_term(target_term, summer = isTRUE(opt$summer))
  current <- student_inputs$course_enrollments %>%
    dplyr::filter(
      term == source_term,
      subject_course %in% feeder_rates$source_course
    ) %>%
    dplyr::inner_join(
      dplyr::select(feeder_rates, source_course, transition_rate),
      by = c("subject_course" = "source_course")
    ) %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarise(student_probability = max(transition_rate), .groups = "drop")

  if (nrow(current) == 0) {
    return(projection_candidate(
      "feeder", reason = paste("No feeder population in source term", source_term),
      n_history_terms = nrow(term_map), coverage_rate = coverage,
      n_components = nrow(feeder_rates)
    ))
  }

  top <- feeder_rates %>% dplyr::slice_head(n = 3)
  summary <- paste0(
    top$source_course, " ", round(100 * top$transition_rate, 1), "%",
    collapse = "; "
  )

  projection_candidate(
    "feeder",
    estimate = sum(current$student_probability) / coverage,
    applicable = TRUE,
    reason = paste("Student-level transition model from", source_term),
    n_history_terms = nrow(term_map),
    evidence_n = sum(feeder_rates$n_transition),
    coverage_rate = coverage,
    n_components = nrow(feeder_rates),
    component_summary = summary
  )
}


project_spring_cohort_flow <- function(history, student_inputs, row,
                                       target_term, opt = list()) {
  method_id <- "spring_cohort_flow"
  target_term <- as.integer(target_term)
  if (get_term_type(target_term) != "spring") {
    return(projection_candidate(
      method_id, reason = "Spring cohort flow applies only to Spring targets"
    ))
  }

  baseline <- projection_history_for_row(
    history, row, before_term = target_term
  ) %>% dplyr::slice_tail(n = 1)
  if (nrow(baseline) == 0) {
    return(projection_candidate(
      method_id, reason = "Needs one prior Spring class-list term"
    ))
  }

  baseline_term <- as.integer(baseline$term[[1]])
  prior_source_term <- subtract_term(baseline_term)
  source_term <- subtract_term(target_term)
  min_population <- as.integer(opt$spring_source_min_population %||% 20L)
  min_coverage <- as.numeric(opt$spring_source_min_coverage %||% 0.10)
  prior_strength <- as.numeric(opt$spring_growth_prior_strength %||% 20)

  spring_inputs <- student_inputs$spring %||%
    prepare_projection_spring_inputs(
      student_inputs$student_terms, student_inputs$target_students
    )
  cohort_total <- spring_inputs$cohort_totals %>%
    dplyr::filter(
      target_term == baseline_term,
      subject_course == row$subject_course
    ) %>%
    dplyr::slice_head(n = 1)
  cohort_cells <- spring_inputs$cohort_cells %>%
    dplyr::filter(
      target_term == baseline_term,
      subject_course == row$subject_course
    )
  prior_source <- spring_inputs$source_populations %>%
    dplyr::filter(term == prior_source_term) %>%
    dplyr::transmute(
      major_code, student_classification,
      n_source_previous = n_population
    )
  current_source <- spring_inputs$source_populations %>%
    dplyr::filter(term == source_term) %>%
    dplyr::transmute(
      major_code, student_classification,
      n_source_current = n_population
    )
  prior_source_n <- sum(prior_source$n_source_previous)
  current_source_n <- sum(current_source$n_source_current)

  if (nrow(cohort_total) == 0) {
    return(projection_candidate(
      method_id, reason = paste("No course roster for", fmt_term(baseline_term)),
      baseline_term = baseline_term, prior_source_term = prior_source_term,
      source_term = source_term,
      baseline_classlist_total = baseline$classlist_total[[1]]
    ))
  }
  if (abs(
    cohort_total$baseline_classlist_total[[1]] - baseline$classlist_total[[1]]
  ) > 1e-8) {
    return(projection_candidate(
      method_id,
      reason = paste(
        "Course roster does not reconcile to",
        fmt_term(baseline_term), "class-list total"
      ),
      evidence_n = cohort_total$baseline_classlist_total[[1]], baseline_term = baseline_term,
      prior_source_term = prior_source_term, source_term = source_term,
      baseline_classlist_total = baseline$classlist_total[[1]]
    ))
  }
  if (prior_source_n < min_population || current_source_n < min_population) {
    return(projection_candidate(
      method_id,
      reason = "Preceding-Fall source population is too small",
      evidence_n = min(prior_source_n, current_source_n),
      baseline_term = baseline_term, prior_source_term = prior_source_term,
      source_term = source_term,
      baseline_classlist_total = baseline$classlist_total[[1]],
      source_population_previous = prior_source_n,
      source_population_current = current_source_n
    ))
  }

  matched_baseline <- cohort_total$matched_baseline[[1]]
  unmatched_baseline <- cohort_total$unmatched_baseline[[1]]
  coverage <- matched_baseline / cohort_total$baseline_classlist_total[[1]]
  if (!is.finite(coverage) || coverage < min_coverage) {
    return(projection_candidate(
      method_id,
      reason = paste0("Preceding Fall covers only ", round(100 * coverage, 1), "% of the baseline course"),
      evidence_n = matched_baseline, coverage_rate = coverage,
      baseline_term = baseline_term, prior_source_term = prior_source_term,
      source_term = source_term,
      baseline_classlist_total = baseline$classlist_total[[1]],
      matched_baseline = matched_baseline,
      unmatched_baseline = unmatched_baseline,
      source_population_previous = prior_source_n,
      source_population_current = current_source_n
    ))
  }

  overall_growth <- current_source_n / prior_source_n
  source_counts <- prior_source %>%
    dplyr::full_join(
      current_source,
      by = c("major_code", "student_classification")
    ) %>%
    dplyr::mutate(
      n_source_previous = dplyr::coalesce(n_source_previous, 0L),
      n_source_current = dplyr::coalesce(n_source_current, 0L)
    )

  components <- cohort_cells %>%
    dplyr::left_join(
      source_counts,
      by = c("major_code", "student_classification")
    ) %>%
    dplyr::mutate(
      growth_ratio = (n_source_current + prior_strength * overall_growth) /
        (n_source_previous + prior_strength),
      projected_component = n_target_baseline * growth_ratio
    )

  matched_projection <- sum(components$projected_component)
  unmatched_projection <- unmatched_baseline
  estimate <- matched_projection + unmatched_projection
  top <- components %>%
    dplyr::arrange(dplyr::desc(n_target_baseline)) %>%
    dplyr::slice_head(n = 3)
  component_summary <- paste0(
    top$major_code, " / ", top$student_classification, " ",
    top$n_target_baseline, " x ", round(top$growth_ratio, 3),
    collapse = "; "
  )

  projection_candidate(
    method_id,
    estimate = estimate,
    applicable = TRUE,
    reason = paste(
      "Prior Spring cohort propagated from", fmt_term(prior_source_term),
      "to", fmt_term(source_term), "with unmatched students carried forward"
    ),
    n_history_terms = 1L,
    evidence_n = matched_baseline,
    coverage_rate = coverage,
    n_components = nrow(components) + 1L,
    component_summary = component_summary,
    baseline_term = baseline_term,
    prior_source_term = prior_source_term,
    source_term = source_term,
    baseline_classlist_total = baseline$classlist_total[[1]],
    matched_baseline = matched_baseline,
    unmatched_baseline = unmatched_baseline,
    matched_projection = matched_projection,
    unmatched_projection = unmatched_projection,
    source_population_previous = prior_source_n,
    source_population_current = current_source_n,
    source_population_growth = overall_growth,
    projection_formula = paste(
      "sum(prior Spring matched major/class count x smoothed Fall population growth)",
      "+ prior Spring unmatched count"
    )
  )
}


project_spring_population_growth <- function(history, student_inputs, row,
                                             target_term, opt = list()) {
  result <- project_spring_cohort_flow(
    history, student_inputs, row, target_term, opt
  )
  result$method_id <- "spring_population_growth"
  result$method_label <- unname(
    CEDAR_ENROLLMENT_PROJECTION_METHODS[["spring_population_growth"]]
  )
  result$method_role <- unname(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[["spring_population_growth"]]
  )

  if (!isTRUE(result$applicable[[1]])) return(result)

  result$matched_projection <-
    result$matched_baseline * result$source_population_growth
  result$projected_classlist_total <-
    result$matched_projection + result$unmatched_projection
  result$n_components <- 2L
  result$component_summary <- paste0(
    "All Fall students ", round(result$source_population_previous), " to ",
    round(result$source_population_current), " (x",
    round(result$source_population_growth, 3), "); unmatched Spring students ",
    round(result$unmatched_projection), " carried forward"
  )
  result$applicability_reason <- paste(
    "Prior Spring matched population propagated by total student growth from",
    fmt_term(result$prior_source_term), "to", fmt_term(result$source_term),
    "with unmatched students carried forward"
  )
  result$projection_formula <- paste(
    "prior Spring matched count x total preceding-Fall population growth",
    "+ prior Spring unmatched count"
  )
  result
}


project_anchored_upstream <- function(anchor, upstream, method_id,
                                      opt = list()) {
  upstream_weight <- as.numeric(opt$upstream_anchor_weight %||% 0.50)
  result <- upstream
  result$method_id <- method_id
  result$method_label <- unname(CEDAR_ENROLLMENT_PROJECTION_METHODS[[method_id]])
  result$method_role <- unname(
    CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES[[method_id]]
  )

  anchor_ok <- isTRUE(anchor$applicable[[1]]) &&
    is.finite(anchor$projected_classlist_total[[1]])
  upstream_ok <- isTRUE(upstream$applicable[[1]]) &&
    is.finite(upstream$projected_classlist_total[[1]])
  if (!anchor_ok || !upstream_ok) {
    result$applicable <- FALSE
    result$projected_classlist_total <- NA_real_
    result$applicability_reason <- paste(
      "Needs both a prior same-season enrollment and usable upstream evidence;",
      if (!anchor_ok) anchor$applicability_reason[[1]] else
        upstream$applicability_reason[[1]]
    )
    return(result)
  }

  anchor_value <- anchor$projected_classlist_total[[1]]
  upstream_value <- upstream$projected_classlist_total[[1]]
  result$projected_classlist_total <-
    (1 - upstream_weight) * anchor_value + upstream_weight * upstream_value
  result$applicable <- TRUE
  result$applicability_reason <- paste0(
    scales::percent(1 - upstream_weight, accuracy = 1),
    " prior same-season enrollment plus ",
    scales::percent(upstream_weight, accuracy = 1),
    " upstream estimate; ", upstream$applicability_reason[[1]]
  )
  result$baseline_classlist_total <- anchor_value
  result$projection_formula <- paste0(
    format(1 - upstream_weight, trim = TRUE),
    " x prior same-season class-list enrollment + ",
    format(upstream_weight, trim = TRUE), " x upstream estimate"
  )
  result
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
    seasonal_median = function() {
      project_seasonal_median(inputs$enrollment_history, row, target_term, opt)
    },
    seasonal_trend = function() {
      project_seasonal_trend(inputs$enrollment_history, row, target_term, opt)
    },
    spring_population_growth = function() {
      project_spring_population_growth(
        inputs$enrollment_history, inputs$students, row, target_term, opt
      )
    },
    spring_cohort_flow = function() {
      project_spring_cohort_flow(
        inputs$enrollment_history, inputs$students, row, target_term, opt
      )
    },
    feeder = function() {
      project_from_feeders(
        inputs$enrollment_history, inputs$students, row, target_term, opt
      )
    },
    anchored_population = function() {
      project_anchored_upstream(
        get_candidate("seasonal_last"),
        get_candidate("spring_population_growth"),
        "anchored_population", opt
      )
    },
    anchored_cohort = function() {
      project_anchored_upstream(
        get_candidate("seasonal_last"),
        get_candidate("spring_cohort_flow"),
        "anchored_cohort", opt
      )
    },
    anchored_feeder = function() {
      project_anchored_upstream(
        get_candidate("seasonal_last"),
        get_candidate("feeder"),
        "anchored_feeder", opt
      )
    }
  )
  candidate_cache <- new.env(parent = emptyenv())
  get_candidate <- function(id) {
    if (!exists(id, envir = candidate_cache, inherits = FALSE)) {
      assign(id, builders[[id]](), envir = candidate_cache)
    }
    get(id, envir = candidate_cache, inherits = FALSE)
  }
  candidates <- dplyr::bind_rows(lapply(method_ids, get_candidate))
  retention <- projection_census_retention_for_row(
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
      census_retention_rate = retention$census_retention_rate[[1]],
      census_retention_n_terms = retention$census_retention_n_terms[[1]],
      census_retention_terms = retention$census_retention_terms[[1]],
      census_retention_term_labels = retention$census_retention_term_labels[[1]],
      projected_census_equivalent =
        projected_classlist_total * census_retention_rate
    )
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
    census_retention_rate = numeric(), quick_census_equivalent = numeric(),
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
    opt$registration_capacity_threshold %||% 1.00
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
      projection_registration_capacity_metrics(
        paired$classlist_total,
        paired$scheduled_capacity,
        reached_threshold = fill_threshold
      )
    ) %>%
      dplyr::mutate(fill_rate = registration_fill)

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
    target_capacity_status <- projection_registration_capacity_metrics(
      target_classlist_total,
      target_capacity,
      reached_threshold = capacity_threshold
    )
    target_active_status <- projection_registration_capacity_metrics(
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
    retention <- projection_census_retention_for_row(
      enrollment_history, row, target_term, opt
    )$census_retention_rate[[1]]
    baseline_census_equivalent <- baseline * retention
    trend_census_equivalent <- trend * retention
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
      " terms with class-list registrations at or above ",
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
             " registration/capacity history")
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
      target_available_seats = pmax(
        0, target_active_status$registration_capacity_gap
      ),
      target_classlist_fill = target_capacity_status$registration_fill,
      target_active_fill = target_active_status$registration_fill,
      target_capacity_reached = target_capacity_status$capacity_reached,
      historical_classlist_total = as.numeric(baseline),
      quick_trend_projection = as.numeric(trend),
      census_retention_rate = as.numeric(retention),
      quick_census_equivalent = as.numeric(trend_census_equivalent),
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
      "projected_census_equivalent", "actual_census", "scheduled_capacity"
    ),
    "add_projection_capacity_censoring()"
  )
  derived <- c(
    "registration_fill", "registration_capacity_gap", "capacity_usable",
    "capacity_reached", "error", "abs_error",
    "pct_error", "abs_pct_error", "census_equivalent_error",
    "census_equivalent_abs_error", "capacity_censored_classlist_projection",
    "capacity_censored_error", "capacity_censored_abs_error",
    "capacity_censored_miss", "capacity_explained_classlist_error",
    "capacity_explained_share"
  )
  base <- dplyr::select(backtests, -dplyr::any_of(derived))
  capacity_status <- projection_registration_capacity_metrics(
    base$actual_classlist_total,
    base$scheduled_capacity,
    reached_threshold = as.numeric(
      opt$registration_capacity_threshold %||% 1.00
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
      census_equivalent_error = projected_census_equivalent - actual_census,
      census_equivalent_abs_error = abs(census_equivalent_error),
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
          actual_census = actuals$actual_census[[j]],
          actual_final_enrollment = actuals$actual_final_enrollment[[j]],
          scheduled_capacity = capacity
        ) %>%
        add_projection_capacity_censoring(opt)
    }))
  })

  output <- dplyr::bind_rows(results)
  if (nrow(output) == 0) return(tibble::tibble())
  add_projection_rolling_calibration(output, opt)
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


projection_calibration_fit <- function(backtests, method_role, opt = list()) {
  min_terms <- as.integer(opt$calibration_min_terms %||% 4L)
  min_bias <- as.numeric(opt$calibration_min_abs_bias %||% 0.05)
  min_consistency <- as.numeric(opt$calibration_min_direction_consistency %||% 0.75)
  factor_bounds <- as.numeric(
    opt$calibration_factor_bounds %||%
      CEDAR_ENROLLMENT_PROJECTION_CALIBRATION_FACTOR_BOUNDS
  )
  neutral <- as.numeric(opt$calibration_neutral_error %||% 0.01)
  raw_projection <- if ("raw_projected_classlist_total" %in% names(backtests)) {
    backtests$raw_projected_classlist_total
  } else {
    backtests$projected_classlist_total
  }
  eligible <- backtests$applicable & is.finite(raw_projection) &
    raw_projection > 0 & is.finite(backtests$actual_classlist_total) &
    backtests$actual_classlist_total > 0
  if (as.character(method_role) %in%
      c("structural_demand", "anchored_upstream")) {
    eligible <- eligible & backtests$capacity_usable &
      !backtests$capacity_reached
  }

  actual <- backtests$actual_classlist_total[eligible]
  projected <- raw_projection[eligible]
  errors <- projected - actual
  pct_errors <- errors / actual
  n <- length(actual)
  weighted_bias <- if (n > 0 && sum(actual) > 0) {
    sum(errors) / sum(actual)
  } else {
    NA_real_
  }
  direction_consistency <- projection_direction_consistency(
    pct_errors, neutral = neutral
  )
  proposed_factor <- if (n > 0 && sum(projected) > 0) {
    sum(actual) / sum(projected)
  } else {
    NA_real_
  }
  enough_terms <- n >= min_terms
  material_bias <- is.finite(weighted_bias) && abs(weighted_bias) >= min_bias
  stable_direction <- is.finite(direction_consistency) &&
    direction_consistency >= min_consistency
  factor_in_bounds <- length(factor_bounds) == 2L &&
    is.finite(proposed_factor) && proposed_factor >= min(factor_bounds) &&
    proposed_factor <= max(factor_bounds)
  applicable <- enough_terms && material_bias && stable_direction &&
    factor_in_bounds
  reason <- dplyr::case_when(
    !enough_terms ~ paste("Needs", min_terms, "eligible prior aftcasts"),
    !material_bias ~ "Weighted bias is below the calibration threshold",
    !stable_direction ~ "Signed errors are not directionally consistent",
    !factor_in_bounds ~ "Proposed calibration factor is outside safety bounds",
    TRUE ~ "Stable signed bias is eligible for rolling validation"
  )

  list(
    n = as.integer(n),
    weighted_bias = as.numeric(weighted_bias),
    direction_consistency = as.numeric(direction_consistency),
    proposed_factor = as.numeric(proposed_factor),
    applicable = isTRUE(applicable),
    reason = as.character(reason)
  )
}


add_projection_rolling_calibration <- function(backtests, opt = list()) {
  if (nrow(backtests) == 0) return(backtests)
  keys <- c(
    "market_id", "college", "subject_course", "term_type", "method_id",
    "method_label", "method_role"
  )

  backtests %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::group_modify(function(.x, .y) {
      rows <- dplyr::arrange(.x, target_term)
      rows$raw_projected_classlist_total <- rows$projected_classlist_total
      rows$calibration_training_n <- 0L
      rows$calibration_training_bias <- NA_real_
      rows$calibration_direction_consistency <- NA_real_
      rows$calibration_factor <- NA_real_
      rows$calibration_applied <- FALSE
      rows$calibration_reason <- "No prior aftcasts"
      rows$calibrated_projected_classlist_total <- rows$raw_projected_classlist_total

      for (i in seq_len(nrow(rows))) {
        prior <- if (i == 1L) rows[0, , drop = FALSE] else
          rows[seq_len(i - 1L), , drop = FALSE]
        fit <- projection_calibration_fit(prior, .y$method_role[[1]], opt)
        rows$calibration_training_n[[i]] <- fit$n
        rows$calibration_training_bias[[i]] <- fit$weighted_bias
        rows$calibration_direction_consistency[[i]] <-
          fit$direction_consistency
        rows$calibration_factor[[i]] <- fit$proposed_factor
        rows$calibration_applied[[i]] <- fit$applicable
        rows$calibration_reason[[i]] <- fit$reason
        if (fit$applicable && is.finite(rows$raw_projected_classlist_total[[i]])) {
          rows$calibrated_projected_classlist_total[[i]] <-
            rows$raw_projected_classlist_total[[i]] * fit$proposed_factor
        }
      }

      rows %>%
        dplyr::mutate(
          calibrated_error = calibrated_projected_classlist_total - actual_classlist_total,
          calibrated_abs_error = abs(calibrated_error),
          calibrated_pct_error = dplyr::if_else(
            actual_classlist_total > 0, calibrated_error / actual_classlist_total, NA_real_
          )
        )
    }) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(market_id, subject_course, target_term, method_id)
}


validate_spring_cohort_rows <- function(data, caller) {
  if (nrow(data) == 0 || !"method_id" %in% names(data)) return(invisible(TRUE))
  rows <- data %>%
    dplyr::filter(
      method_id %in% c("spring_population_growth", "spring_cohort_flow"),
      applicable
    )
  if (nrow(rows) == 0) return(invisible(TRUE))

  projection_require_columns(
    rows,
    c(
      "term_type", "target_term", "projected_classlist_total", "baseline_term",
      "prior_source_term", "source_term", "baseline_classlist_total",
      "matched_baseline", "unmatched_baseline", "matched_projection",
      "unmatched_projection", "source_population_previous",
      "source_population_current", "source_population_growth"
    ),
    caller
  )
  expected_source <- vapply(rows$target_term, subtract_term, integer(1))
  expected_prior_source <- vapply(rows$baseline_term, subtract_term, integer(1))
  terms_valid <- rows$term_type == "spring" &
    rows$baseline_term < rows$target_term &
    rows$source_term == expected_source &
    rows$prior_source_term == expected_prior_source &
    rows$prior_source_term < rows$source_term &
    rows$source_term < rows$target_term
  baseline_valid <- abs(
    rows$matched_baseline + rows$unmatched_baseline - rows$baseline_classlist_total
  ) <= 1e-6
  formula_projection <- if ("raw_projected_classlist_total" %in% names(rows)) {
    rows$raw_projected_classlist_total
  } else {
    rows$projected_classlist_total
  }
  projection_valid <- abs(
    rows$matched_projection + rows$unmatched_projection -
      formula_projection
  ) <= 1e-6
  growth_valid <- rows$source_population_previous > 0 &
    abs(
      rows$source_population_current / rows$source_population_previous -
        rows$source_population_growth
    ) <= 1e-8

  if (any(!terms_valid | !baseline_valid | !projection_valid | !growth_valid)) {
    stop(
      "[enrollment-projections.R] ", caller,
      " has an invalid Spring population audit trail.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


validate_projection_calibration_rows <- function(data, caller,
                                                 published = FALSE) {
  if (nrow(data) == 0) return(invisible(TRUE))
  effective_col <- if (published) {
    if ("calibrated_projected_classlist_total" %in% names(data)) {
      "calibrated_projected_classlist_total"
    } else {
      "projected_classlist_total"
    }
  } else {
    "calibrated_projected_classlist_total"
  }
  required <- c(
    "raw_projected_classlist_total", "calibration_factor", "calibration_applied",
    effective_col
  )
  projection_require_columns(data, required, caller)

  applied <- !is.na(data$calibration_applied) & data$calibration_applied
  factor_bounds <- CEDAR_ENROLLMENT_PROJECTION_CALIBRATION_FACTOR_BOUNDS
  invalid_factor <- applied & (
    !is.finite(data$calibration_factor) |
      data$calibration_factor < min(factor_bounds) |
      data$calibration_factor > max(factor_bounds)
  )
  expected <- data$raw_projected_classlist_total
  expected[applied] <- data$raw_projected_classlist_total[applied] *
    data$calibration_factor[applied]
  comparable <- is.finite(expected) & is.finite(data[[effective_col]])
  invalid_value <- comparable & abs(data[[effective_col]] - expected) > 1e-8

  if (published) {
    invalid_default_factor <- !applied &
      (!is.finite(data$calibration_factor) | data$calibration_factor != 1)
    projection_require_columns(data, "calibration_adjustment", caller)
    expected_adjustment <- data[[effective_col]] - data$raw_projected_classlist_total
    adjustment_comparable <- is.finite(expected_adjustment) &
      is.finite(data$calibration_adjustment)
    invalid_adjustment <- adjustment_comparable &
      abs(data$calibration_adjustment - expected_adjustment) > 1e-8
  } else {
    invalid_default_factor <- rep(FALSE, nrow(data))
    invalid_adjustment <- rep(FALSE, nrow(data))
  }

  if (any(invalid_factor | invalid_value | invalid_default_factor |
          invalid_adjustment)) {
    stop(
      "[enrollment-projections.R] ", caller,
      " has an invalid projection calibration audit trail.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}


validate_projection_capacity_rows <- function(data, caller) {
  if (nrow(data) == 0) return(invisible(TRUE))
  projection_require_columns(
    data,
    c(
      "projected_classlist_total", "actual_classlist_total",
      "projected_census_equivalent", "actual_census", "scheduled_capacity",
      "capacity_reached", "registration_capacity_gap",
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
    census_equivalent_wape = numeric(), uncensored_wape = numeric(),
    n_capacity_censored_misses = integer(), capacity_explained_wape = numeric(),
    capacity_explained_error_share = numeric(),
    capacity_censored_terms = character(),
    capacity_censored_term_labels = character(),
    capacity_miss_assessment = character(), weighted_bias = numeric(),
    uncensored_weighted_bias = numeric(), mean_pct_error = numeric(),
    pct_error_sd = numeric(), overprediction_rate = numeric(),
    underprediction_rate = numeric(), direction_consistency = numeric(),
    signed_error_history = character(), calibration_training_n = integer(),
    proposed_calibration_factor = numeric(), calibration_candidate = logical(),
    n_calibrated_backtests = integer(), calibration_comparison_wape = numeric(),
    calibrated_wape = numeric(), calibration_wape_gain = numeric(),
    calibration_validated = logical(), calibration_recommended = logical(),
    calibration_reason = character()
  )
}


empty_projection_recent_history <- function() {
  tibble::tibble(
    market_id = character(), college = character(), department = character(),
    subject_course = character(), term_type = character(),
    projection_target_term = integer(), history_term = integer(),
    history_term_label = character(), recency_rank = integer(),
    actual_classlist_total = numeric(), actual_census = numeric(),
    actual_final_enrollment = numeric(),
    actual_census_retention_rate = numeric(), scheduled_sections = integer(),
    scheduled_capacity = numeric(), census_fill = numeric(),
    prior_classlist_total = numeric(), prior_scheduled_capacity = numeric(),
    classlist_change = numeric(), capacity_change = numeric(),
    registration_fill = numeric(), registration_capacity_gap = numeric(),
    capacity_usable = logical(), capacity_reached = logical(), method_id = character(),
    method_label = character(), aftcast_applicable = logical(),
    aftcast_reason = character(), raw_aftcast_classlist_total = numeric(),
    aftcast_classlist_total = numeric(), calibration_applied = logical(),
    calibration_factor = numeric(), aftcast_error = numeric(),
    aftcast_pct_error = numeric(), aftcast_capacity_censored = logical(),
    aftcast_censored_error = numeric(), aftcast_censored_pct_error = numeric(),
    potential_miss_explanation = character()
  )
}


build_projection_recent_history <- function(projections, enrollment_history,
                                            section_history, backtests,
                                            opt = list()) {
  if (nrow(projections) == 0L) return(empty_projection_recent_history())
  window <- as.integer(opt$recent_history_terms %||% 3L)
  if (!is.finite(window) || window < 1L) {
    stop("[enrollment-projections.R] recent_history_terms must be positive.",
         call. = FALSE)
  }

  empty_aftcasts <- tibble::tibble(
    history_term = integer(), aftcast_applicable = logical(),
    aftcast_reason = character(), raw_aftcast_classlist_total = numeric(),
    aftcast_classlist_total = numeric(), calibration_applied = logical(),
    calibration_factor = numeric(), aftcast_capacity_censored = logical(),
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
    aftcasts <- if (nrow(backtests) == 0L || projection$method_id == "none") {
      empty_aftcasts
    } else {
      backtests %>%
        dplyr::filter(
          market_id == projection$market_id,
          subject_course == projection$subject_course,
          term_type == projection$term_type,
          method_id == projection$method_id,
          target_term %in% history$term
        ) %>%
        dplyr::transmute(
          history_term = target_term,
          aftcast_applicable = applicable,
          aftcast_reason = applicability_reason,
          raw_aftcast_classlist_total = raw_projected_classlist_total,
          aftcast_classlist_total = calibrated_projected_classlist_total,
          calibration_applied = dplyr::coalesce(calibration_applied, FALSE),
          calibration_factor,
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
    capacity_status <- projection_registration_capacity_metrics(
      joined$classlist_total, joined$scheduled_capacity,
      reached_threshold = opt$registration_capacity_threshold %||% 1.00
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
        actual_census = as.numeric(census_enrl),
        actual_final_enrollment = as.numeric(registered),
        actual_census_retention_rate = dplyr::if_else(
          classlist_total > 0, census_enrl / classlist_total, NA_real_
        ),
        scheduled_sections = as.integer(scheduled_sections),
        scheduled_capacity = as.numeric(scheduled_capacity),
        prior_classlist_total, prior_scheduled_capacity,
        classlist_change, capacity_change,
        census_fill = dplyr::if_else(
          scheduled_capacity > 0,
          actual_census / scheduled_capacity,
          NA_real_
        ),
        registration_fill, registration_capacity_gap, capacity_usable,
        capacity_reached,
        method_id = projection$method_id,
        method_label = projection$method_label,
        aftcast_applicable = dplyr::coalesce(aftcast_applicable, FALSE),
        aftcast_reason = dplyr::coalesce(
          aftcast_reason, projection$applicability_reason
        ),
        raw_aftcast_classlist_total,
        aftcast_classlist_total,
        calibration_applied = dplyr::coalesce(calibration_applied, FALSE),
        calibration_factor,
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
              "Registration reached capacity; observed demand is a lower bound",
              "rather than a complete error measurement"
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
      raw_projected_classlist_total = numeric(), calibration_factor = numeric(),
      calibration_applied = logical(), calibration_adjustment = numeric(),
      selected = logical()
    )
}


empty_enrollment_projections <- function() {
  empty_projection_candidates() %>%
    dplyr::select(-selected) %>%
    dplyr::mutate(
      calibrated_projected_classlist_total = numeric(),
      interval_error = numeric(), projection_low = numeric(),
      projection_high = numeric(), confidence = character(),
      confidence_reason = character(), selection_reason = character(),
      selection_wape = numeric(), selection_n_backtests = integer(),
      selection_basis = character(), selection_uses_uncensored = logical(),
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
      target_capacity_reached = logical(), projected_census_equivalent = numeric(),
      projected_over_capacity = numeric(), capacity_limit_signal = logical(),
      capacity_limit_status = character(), capacity_limit_note = character(),
      inclusion_reason = character(), candidate_min = numeric(),
      candidate_max = numeric(), candidate_spread = numeric(),
      n_applicable_methods = integer(), reference_section_size = numeric(),
      seat_gap = numeric(), recommended_sections = integer(),
      additional_sections = integer(), methods_disagree = logical(),
      observed_baseline = numeric(), observed_method_id = character(),
      observed_method = character(), observed_wape = numeric(),
      observed_n_backtests = integer(), structural_projection = numeric(),
      structural_method_id = character(), structural_method = character(),
      structural_observed_wape = numeric(), structural_capacity_wape = numeric(),
      structural_uncensored_wape = numeric(), structural_coverage = numeric(),
      population_projection = numeric(), population_observed_wape = numeric(),
      population_capacity_wape = numeric(),
      population_uncensored_wape = numeric(), population_coverage = numeric(),
      population_n_backtests = integer(),
      spring_flow_projection = numeric(), spring_flow_observed_wape = numeric(),
      spring_flow_capacity_wape = numeric(),
      spring_flow_uncensored_wape = numeric(), spring_flow_coverage = numeric(),
      spring_flow_n_backtests = integer(),
      feeder_projection = numeric(),
      feeder_observed_wape = numeric(), feeder_capacity_wape = numeric(),
      feeder_uncensored_wape = numeric(), feeder_coverage = numeric(),
      feeder_n_backtests = integer(),
      capacity_data_quality = character(), recent_capacity_terms = integer(),
      recent_capacity_reached_terms = integer(),
      last_registration_fill = numeric(),
      observed_enrollment_slope = numeric(), observed_enrollment_rising = logical(),
      persistent_capacity_reached = logical(), capacity_increase_terms = integer(),
      demand_followed_capacity_terms = integer(),
      structural_gap_threshold = numeric(), structural_high_projection = numeric(),
      structural_gap = numeric(), n_structural_above_observed = integer(),
      population_credible = logical(), spring_flow_credible = logical(),
      feeder_credible = logical(),
      n_credible_structural_methods = integer(),
      coupling_n_backtests = integer(), coupling_wape_gain = numeric(),
      coupling_status = character(), coupling_reason = character(),
      why_uncertain = character(),
      demand_signal = character(), demand_signal_reason = character(),
      recommendation = character(), demand_note = character()
    )
}


summarize_projection_backtests <- function(backtests, opt = list()) {
  if (nrow(backtests) == 0) return(empty_projection_performance())

  capacity_fields <- c(
    "registration_capacity_gap", "capacity_censored_classlist_projection",
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
  if (!"calibration_applied" %in% names(backtests)) {
    backtests <- add_projection_rolling_calibration(backtests, opt)
  }

  usable <- backtests %>%
    dplyr::filter(applicable, is.finite(projected_classlist_total), is.finite(actual_classlist_total))
  if (nrow(usable) == 0) return(empty_projection_performance())

  keys <- c(
    "market_id", "college", "subject_course", "term_type", "method_id",
    "method_label"
  )
  base <- usable %>%
    dplyr::group_by(
      dplyr::across(dplyr::all_of(keys))
    ) %>%
    dplyr::summarise(
      n_backtests = dplyr::n(),
      mae = mean(abs_error),
      rmse = sqrt(mean(error^2)),
      wape = projection_wape(abs_error, actual_classlist_total),
      bias = mean(error),
      error_q80 = as.numeric(stats::quantile(abs_error, 0.80, names = FALSE)),
      backtest_start_term = min(target_term),
      backtest_end_term = max(target_term),
      backtest_terms = paste(sort(unique(target_term)), collapse = ","),
      backtest_term_labels = paste(
        vapply(sort(unique(target_term)), fmt_term, character(1)),
        collapse = ", "
      ),
      backtest_term_range = if (min(target_term) == max(target_term)) {
        fmt_term(min(target_term))
      } else {
        paste(fmt_term(min(target_term)), "to", fmt_term(max(target_term)))
      },
      n_capacity_usable = sum(capacity_usable),
      n_capacity_reached = sum(capacity_reached),
      n_capacity_unreached = sum(capacity_usable & !capacity_reached),
      census_equivalent_wape = projection_wape(
        census_equivalent_abs_error, actual_census
      ),
      capacity_censored_wape = projection_wape(
        capacity_censored_abs_error, actual_classlist_total
      ),
      uncensored_wape = projection_wape(
        abs_error[capacity_usable & !capacity_reached],
        actual_classlist_total[capacity_usable & !capacity_reached]
      ),
      n_capacity_censored_misses = sum(capacity_censored_miss, na.rm = TRUE),
      capacity_explained_wape = projection_wape(
        capacity_explained_classlist_error, actual_classlist_total
      ),
      capacity_explained_error_share =
        if (sum(abs_error, na.rm = TRUE) > 0) {
        sum(capacity_explained_classlist_error, na.rm = TRUE) /
          sum(abs_error, na.rm = TRUE)
      } else {
        0
      },
      capacity_censored_terms = paste(
        sort(unique(target_term[capacity_censored_miss])), collapse = ","
      ),
      capacity_censored_term_labels = paste(
        vapply(
          sort(unique(target_term[capacity_censored_miss])),
          fmt_term,
          character(1)
        ),
        collapse = ", "
      ),
      .groups = "drop"
    ) %>%
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
    )

  neutral <- as.numeric(opt$calibration_neutral_error %||% 0.01)
  min_validation <- as.integer(opt$calibration_min_validation_terms %||% 2L)
  min_gain <- as.numeric(opt$calibration_min_wape_gain %||% 0.01)
  diagnostics <- usable %>%
    dplyr::group_by(
      dplyr::across(dplyr::all_of(c(keys, "method_role")))
    ) %>%
    dplyr::group_modify(function(.x, .y) {
      rows <- dplyr::arrange(.x, target_term)
      fit <- projection_calibration_fit(rows, .y$method_role[[1]], opt)
      directional <- rows$pct_error[
        is.finite(rows$pct_error) & abs(rows$pct_error) > neutral
      ]
      calibrated <- rows %>%
        dplyr::filter(
          calibration_applied,
          is.finite(calibrated_abs_error),
          is.finite(actual_classlist_total)
        )
      if (.y$method_role[[1]] %in%
          c("structural_demand", "anchored_upstream")) {
        calibrated <- calibrated %>%
          dplyr::filter(capacity_usable, !capacity_reached)
      }
      n_calibrated <- nrow(calibrated)
      comparison_wape <- projection_wape(
        calibrated$abs_error, calibrated$actual_classlist_total
      )
      calibrated_wape <- projection_wape(
        calibrated$calibrated_abs_error, calibrated$actual_classlist_total
      )
      calibration_gain <- comparison_wape - calibrated_wape
      validated <- n_calibrated >= min_validation &&
        is.finite(calibration_gain) && calibration_gain >= min_gain
      recommended <- fit$applicable && validated
      reason <- dplyr::case_when(
        !fit$applicable ~ fit$reason,
        n_calibrated < min_validation ~ paste(
          "Stable bias found; needs", min_validation,
          "rolling calibration aftcasts"
        ),
        !is.finite(calibration_gain) || calibration_gain < min_gain ~
          "Rolling calibration did not improve WAPE enough",
        TRUE ~ paste0(
          "Validated calibration improved WAPE by ",
          scales::percent(calibration_gain, accuracy = 0.1)
        )
      )
      uncensored <- rows$capacity_usable & !rows$capacity_reached

      tibble::tibble(
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
        ),
        calibration_training_n = fit$n,
        proposed_calibration_factor = fit$proposed_factor,
        calibration_candidate = fit$applicable,
        n_calibrated_backtests = as.integer(n_calibrated),
        calibration_comparison_wape = comparison_wape,
        calibrated_wape = calibrated_wape,
        calibration_wape_gain = calibration_gain,
        calibration_validated = validated,
        calibration_recommended = recommended,
        calibration_reason = reason
      )
    }) %>%
    dplyr::ungroup() %>%
    dplyr::select(-method_role)

  base %>%
    dplyr::left_join(diagnostics, by = keys)
}


attach_projection_performance <- function(candidates, performance,
                                          opt = list()) {
  performance <- dplyr::bind_rows(
    empty_projection_performance(), performance
  )
  factor_bounds <- as.numeric(
    opt$calibration_factor_bounds %||%
      CEDAR_ENROLLMENT_PROJECTION_CALIBRATION_FACTOR_BOUNDS
  )
  factor_is_safe <- length(factor_bounds) == 2L &&
    all(is.finite(factor_bounds))
  factor_lower <- if (factor_is_safe) min(factor_bounds) else NA_real_
  factor_upper <- if (factor_is_safe) max(factor_bounds) else NA_real_
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
      calibration_applied = dplyr::coalesce(
        calibration_recommended, FALSE
      ) & dplyr::coalesce(applicable, FALSE) &
        is.finite(raw_projected_classlist_total) &
        is.finite(proposed_calibration_factor) & factor_is_safe &
        proposed_calibration_factor >= factor_lower &
        proposed_calibration_factor <= factor_upper,
      calibration_factor = dplyr::if_else(
        calibration_applied, proposed_calibration_factor, 1
      ),
      projected_classlist_total = dplyr::if_else(
        calibration_applied,
        raw_projected_classlist_total * calibration_factor,
        raw_projected_classlist_total
      ),
      calibration_adjustment =
        projected_classlist_total - raw_projected_classlist_total,
      projected_census_equivalent =
        projected_classlist_total * census_retention_rate
    )
}


select_projection_methods <- function(candidates, performance, backtests,
                                      opt = list()) {
  if (nrow(candidates) == 0) return(tibble::tibble())
  min_backtests <- as.integer(opt$selection_min_backtests %||% 2L)
  min_uncensored <- as.integer(
    opt$uncensored_selection_min_backtests %||% 2L
  )
  constrained_share <- as.numeric(opt$capacity_constrained_share %||% 0.50)
  method_order <- names(CEDAR_ENROLLMENT_PROJECTION_METHODS)
  keys <- c(
    "market_id", "subject_course", "term_type", "target_term"
  )

  joined <- attach_projection_performance(candidates, performance, opt) %>%
    dplyr::mutate(
      method_rank = match(method_id, method_order),
      capacity_constrained_history =
        dplyr::coalesce(n_capacity_usable, 0L) >= 2L &
        dplyr::coalesce(n_capacity_reached / n_capacity_usable, 0) >=
          constrained_share,
      selection_uses_uncensored = capacity_constrained_history &
        dplyr::coalesce(n_capacity_unreached, 0L) >= min_uncensored &
        is.finite(uncensored_wape),
      selection_wape = dplyr::if_else(
        selection_uses_uncensored, uncensored_wape, wape
      ),
      selection_n_backtests = dplyr::if_else(
        selection_uses_uncensored,
        as.integer(n_capacity_unreached), as.integer(n_backtests)
      ),
      selection_basis = dplyr::if_else(
        selection_uses_uncensored,
        "Unconstrained-term WAPE", "All-term WAPE"
      ),
      upstream_evidence_eligible = method_role == "anchored_upstream" &
        dplyr::coalesce(n_backtests, 0L) >=
          as.integer(opt$structural_min_backtests %||% 3L) &
        dplyr::coalesce(coverage_rate, 0) >=
          as.numeric(opt$structural_min_coverage %||% 0.40) &
        is.finite(selection_wape) & selection_wape <=
          as.numeric(opt$structural_max_wape %||% 0.20),
      selection_eligible =
        method_role %in% c("observed_enrollment", "anchored_upstream") &
        applicable & is.finite(projected_classlist_total) &
        is.finite(selection_wape) &
        dplyr::coalesce(selection_n_backtests, 0L) >= min_backtests &
        (method_role == "observed_enrollment" | upstream_evidence_eligible)
    )

  selected <- joined %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::group_modify(function(.x, .y) {
      observed <- .x %>%
        dplyr::filter(selection_eligible, method_role == "observed_enrollment") %>%
        dplyr::arrange(selection_wape, mae, method_rank) %>%
        dplyr::slice_head(n = 1)
      upstream <- .x %>%
        dplyr::filter(selection_eligible, method_role == "anchored_upstream") %>%
        dplyr::arrange(selection_wape, mae, method_rank) %>%
        dplyr::slice_head(n = 1)
      if (nrow(observed) > 0L && nrow(upstream) > 0L) {
        cap_limited <- any(.x$capacity_constrained_history, na.rm = TRUE)
        margin <- if (cap_limited) {
          as.numeric(opt$upstream_capped_tie_margin %||% 0.05)
        } else {
          as.numeric(opt$upstream_tie_margin %||% 0.02)
        }
        if (upstream$selection_wape[[1]] <=
            observed$selection_wape[[1]] + margin) upstream else observed
      } else if (nrow(upstream) > 0L) {
        upstream
      } else if (nrow(observed) > 0L) {
        observed
      } else {
        fallback <- dplyr::filter(
          .x,
          method_role == "observed_enrollment",
          applicable,
          is.finite(projected_classlist_total)
        ) %>%
          dplyr::arrange(method_rank)
        if (nrow(fallback) == 0) .x[0, , drop = FALSE] else
          dplyr::slice_head(fallback, n = 1)
      }
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
        calibration_applied = FALSE,
        calibration_factor = 1,
        calibration_adjustment = NA_real_,
        applicable = FALSE,
        applicability_reason = "No candidate method has sufficient evidence",
        selection_eligible = FALSE,
        n_backtests = NA_integer_,
        mae = NA_real_,
        rmse = NA_real_,
        wape = NA_real_,
        bias = NA_real_,
        error_q80 = NA_real_
      )
    selected <- dplyr::bind_rows(selected, placeholders)
  }

  intervals <- if (nrow(backtests) == 0) {
    tibble::tibble(
      market_id = character(), subject_course = character(),
      term_type = character(), method_id = character(), interval_error = numeric()
    )
  } else {
    backtests %>%
      dplyr::filter(applicable, is.finite(abs_error)) %>%
      dplyr::group_by(
        market_id, subject_course, term_type, method_id
      ) %>%
      dplyr::summarise(
        interval_error = as.numeric(stats::quantile(abs_error, 0.80, names = FALSE)),
        .groups = "drop"
      )
  }

  selected %>%
    dplyr::left_join(
      intervals,
      by = c(
        "market_id", "subject_course", "term_type", "method_id"
      )
    ) %>%
    dplyr::mutate(
      calibrated_projected_classlist_total = projected_classlist_total,
      projected_classlist_total = round(projected_classlist_total),
      projected_census_equivalent = round(
        projected_classlist_total * census_retention_rate
      ),
      projection_low = pmax(0, round(projected_classlist_total - interval_error)),
      projection_high = round(projected_classlist_total + interval_error),
      projection_low_census_equivalent = round(
        projection_low * census_retention_rate
      ),
      projection_high_census_equivalent = round(
        projection_high * census_retention_rate
      ),
      confidence = dplyr::case_when(
        capacity_constrained_history & !selection_uses_uncensored ~ "None",
        dplyr::coalesce(selection_n_backtests, 0L) >= 4L &
          dplyr::coalesce(selection_wape, Inf) <= 0.10 &
          (is.na(coverage_rate) | coverage_rate >= 0.40) ~ "High",
        dplyr::coalesce(selection_n_backtests, 0L) >= 3L &
          dplyr::coalesce(selection_wape, Inf) <= 0.15 &
          (is.na(coverage_rate) | coverage_rate >= 0.20) ~ "Medium",
        dplyr::coalesce(selection_n_backtests, 0L) >= 2L &
          dplyr::coalesce(selection_wape, Inf) <= 0.20 ~ "Low",
        TRUE ~ "None"
      ),
      confidence_reason = dplyr::case_when(
        method_id == "none" ~ "No applicable observed-enrollment method",
        capacity_constrained_history & !selection_uses_uncensored ~ paste0(
          "Only ", dplyr::coalesce(n_capacity_unreached, 0L),
          " unconstrained aftcast term(s); capped enrollment cannot validate latent demand"
        ),
        confidence == "High" ~ paste0(
          selection_n_backtests, " aftcasts with ",
          scales::percent(selection_wape, accuracy = 0.1), " ",
          dplyr::if_else(
            selection_uses_uncensored,
            "unconstrained-term WAPE", "all-term WAPE"
          )
        ),
        confidence == "Medium" ~ paste0(
          selection_n_backtests, " aftcasts with ",
          scales::percent(selection_wape, accuracy = 0.1), " ",
          dplyr::if_else(
            selection_uses_uncensored,
            "unconstrained-term WAPE", "all-term WAPE"
          )
        ),
        confidence == "Low" ~ paste0(
          selection_n_backtests, " aftcasts with ",
          scales::percent(selection_wape, accuracy = 0.1), " ",
          dplyr::if_else(
            selection_uses_uncensored,
            "unconstrained-term WAPE", "all-term WAPE"
          )
        ),
        dplyr::coalesce(selection_n_backtests, 0L) < 2L ~
          "Fewer than two comparable aftcasts",
        !is.finite(selection_wape) ~ "No measurable aftcast accuracy",
        selection_wape > 0.20 ~ paste0(
          selection_basis, " is ",
          scales::percent(selection_wape, accuracy = 0.1),
          ", above the 20% confidence ceiling"
        ),
        TRUE ~ "Historical evidence does not meet a confidence threshold"
      ),
      selection_reason = dplyr::if_else(
        method_id == "none",
        "No candidate method has sufficient evidence",
        dplyr::if_else(
          selection_eligible,
          dplyr::if_else(
            method_role == "anchored_upstream",
            paste0(
              "Upstream-anchored method is within the allowed evidence margin (",
              selection_basis, " ",
              scales::percent(selection_wape, accuracy = 0.1), "; n=",
              selection_n_backtests, ")"
            ),
            paste0(
              "Lowest historical WAPE among eligible methods (",
              selection_basis, "; ",
              scales::percent(selection_wape, accuracy = 0.1), "; n=",
              selection_n_backtests, ")"
            )
          ),
          "Fallback method; insufficient comparable backtests"
        )
      ),
      selection_reason = dplyr::if_else(
        calibration_applied,
        paste0(
          selection_reason, "; calibrated x",
          format(round(calibration_factor, 3), nsmall = 3), " (bias ",
          sprintf("%+.1f%%", 100 * weighted_bias), ")"
        ),
        selection_reason
      )
    )
}


projection_family_choice <- function(candidates, role, opt = list()) {
  keys <- c(
    "market_id", "subject_course", "term_type", "target_term"
  )
  family <- candidates %>%
    dplyr::filter(
      .data$method_role == .env$role,
      applicable,
      is.finite(projected_classlist_total)
    ) %>%
    dplyr::mutate(
      method_rank = match(method_id, names(CEDAR_ENROLLMENT_PROJECTION_METHODS))
    )
  if (nrow(family) == 0) {
    return(tibble::tibble(
      market_id = character(), subject_course = character(),
      term_type = character(), target_term = integer(),
      method_id = character(), method_label = character(),
      projected_classlist_total = numeric(), n_backtests = integer(), wape = numeric(),
      capacity_censored_wape = numeric(), uncensored_wape = numeric(),
      coverage_rate = numeric()
    ))
  }

  min_backtests <- as.integer(opt$selection_min_backtests %||% 2L)
  family %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::group_modify(function(.x, .y) {
      scored <- .x %>%
        dplyr::filter(
          is.finite(wape), dplyr::coalesce(n_backtests, 0L) >= min_backtests
        ) %>%
        dplyr::arrange(wape, method_rank)
      if (nrow(scored) > 0) dplyr::slice_head(scored, n = 1) else
        dplyr::slice_head(dplyr::arrange(.x, method_rank), n = 1)
    }) %>%
    dplyr::ungroup() %>%
    dplyr::select(
      dplyr::all_of(keys), method_id, method_label, projected_classlist_total,
      n_backtests, wape, capacity_censored_wape, uncensored_wape, coverage_rate
    )
}


projection_method_pairing <- function(candidates, opt = list()) {
  keys <- c(
    "market_id", "subject_course", "term_type", "target_term"
  )
  observed <- projection_family_choice(
    candidates, "observed_enrollment", opt
  ) %>%
    dplyr::transmute(
      dplyr::across(dplyr::all_of(keys)),
      observed_baseline = projected_classlist_total,
      observed_method_id = method_id,
      observed_method = method_label,
      observed_wape = wape,
      observed_n_backtests = n_backtests
    )
  structural <- projection_family_choice(
    candidates, "structural_demand", opt
  ) %>%
    dplyr::transmute(
      dplyr::across(dplyr::all_of(keys)),
      structural_projection = projected_classlist_total,
      structural_method_id = method_id,
      structural_method = method_label,
      structural_observed_wape = wape,
      structural_capacity_wape = capacity_censored_wape,
      structural_uncensored_wape = uncensored_wape,
      structural_coverage = coverage_rate
    )
  method_value <- function(method_id, prefix) {
    candidates %>%
      dplyr::filter(
        .data$method_id == .env$method_id,
        applicable,
        is.finite(projected_classlist_total)
      ) %>%
      dplyr::transmute(
        dplyr::across(dplyr::all_of(keys)),
        "{prefix}_projection" := projected_classlist_total,
        "{prefix}_observed_wape" := wape,
        "{prefix}_capacity_wape" := capacity_censored_wape,
        "{prefix}_uncensored_wape" := uncensored_wape,
        "{prefix}_coverage" := coverage_rate,
        "{prefix}_n_backtests" := n_backtests
      )
  }

  candidates %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::left_join(observed, by = keys) %>%
    dplyr::left_join(structural, by = keys) %>%
    dplyr::left_join(
      method_value("spring_population_growth", "population"), by = keys
    ) %>%
    dplyr::left_join(
      method_value("spring_cohort_flow", "spring_flow"), by = keys
    ) %>%
    dplyr::left_join(method_value("feeder", "feeder"), by = keys)
}


projection_enrollment_slope <- function(values) {
  values <- as.numeric(values)
  if (length(values) < 3L || any(!is.finite(values))) return(NA_real_)
  unname(stats::coef(stats::lm(values ~ seq_along(values)))[[2]])
}


projection_capacity_context <- function(enrollment_history, section_history,
                                        rows, opt = list()) {
  if (nrow(rows) == 0) return(tibble::tibble())
  history_window <- as.integer(opt$demand_history_window %||% 5L)
  recent_window <- as.integer(opt$demand_recent_window %||% 3L)
  capacity_threshold <- as.numeric(
    opt$registration_capacity_threshold %||% 1.00
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
      projection_registration_capacity_metrics(
        paired$classlist_total,
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
      last_registration_fill = if (nrow(recent) == 0) NA_real_ else
        dplyr::last(recent$registration_fill),
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


projection_structural_credible <- function(projection, n_backtests, wape,
                                           uncensored_wape, coverage_rate,
                                           opt = list()) {
  is.finite(projection) &
    dplyr::coalesce(as.integer(n_backtests), 0L) >=
      as.integer(opt$structural_min_backtests %||% 3L) &
    dplyr::coalesce(as.numeric(coverage_rate), 0) >=
      as.numeric(opt$structural_min_coverage %||% 0.40) &
    (
      dplyr::coalesce(as.numeric(wape), Inf) <=
        as.numeric(opt$structural_max_wape %||% 0.20) |
      dplyr::coalesce(as.numeric(uncensored_wape), Inf) <=
        as.numeric(opt$structural_max_wape %||% 0.20)
    )
}


add_projection_recommendations <- function(selected, candidates, pressure_screen,
                                           enrollment_history, section_history,
                                           opt = list()) {
  if (nrow(selected) == 0) return(selected)
  keys <- c(
    "market_id", "subject_course", "term_type", "target_term"
  )

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
  capacity_context <- projection_capacity_context(
    enrollment_history, section_history, selected, opt
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
      seat_gap = round(projected_classlist_total - scheduled_capacity),
      projected_over_capacity = pmax(0, seat_gap),
      capacity_limit_signal = target_schedule_available &
        target_capacity_reached & projected_over_capacity > 0,
      capacity_limit_status = dplyr::case_when(
        !target_schedule_available ~ "Target schedule unavailable",
        !is.finite(projected_classlist_total) ~
          "Insufficient history for a registration-demand estimate",
        projected_over_capacity <= 0 ~ "Projection fits scheduled capacity",
        capacity_limit_signal ~ "Seat ceiling likely limits observed enrollment",
        TRUE ~ "Projected demand exceeds planned capacity"
      ),
      capacity_limit_note = dplyr::case_when(
        !target_schedule_available ~
          "No target schedule is available for a seat-ceiling check",
        !is.finite(projected_classlist_total) ~
          "Class-list demand is not yet stable",
        projected_over_capacity <= 0 ~ paste(
          round(scheduled_capacity - projected_classlist_total),
          "planned seat(s) remain above projected class-list demand"
        ),
        capacity_limit_signal ~ paste0(
          "Projection exceeds capacity by ", round(projected_over_capacity),
          "; ", round(target_available_seats),
          " seat(s) are currently unoccupied"
        ),
        TRUE ~ paste0(
          "Projection exceeds capacity by ", round(projected_over_capacity),
          "; active registration fill is ",
          scales::percent(target_active_fill, accuracy = 0.1)
        )
      ),
      recommended_sections = dplyr::if_else(
        is.finite(reference_section_size) &
          is.finite(projected_classlist_total),
        as.integer(ceiling(
          projected_classlist_total / reference_section_size
        )),
        NA_integer_
      ),
      additional_sections = dplyr::if_else(
        !is.na(recommended_sections),
        pmax(0L, recommended_sections - scheduled_sections),
        NA_integer_
      ),
      methods_disagree = dplyr::if_else(
        is.finite(projected_classlist_total) & projected_classlist_total > 0 &
          is.finite(candidate_spread),
        candidate_spread / projected_classlist_total >=
          as.numeric(opt$disagreement_threshold %||% 0.20),
        FALSE
      ),
      coupling_n_backtests = pmin(
        dplyr::coalesce(population_n_backtests, 0L),
        dplyr::coalesce(spring_flow_n_backtests, 0L)
      ),
      coupling_wape_gain = population_observed_wape - spring_flow_observed_wape,
      coupling_status = dplyr::case_when(
        coupling_n_backtests < 3L |
          !is.finite(coupling_wape_gain) ~ "Insufficient evidence",
        coupling_wape_gain >= 0.02 ~ "Major/classification",
        coupling_wape_gain <= -0.02 ~ "Broad population",
        TRUE ~ "Mixed"
      ),
      coupling_reason = dplyr::case_when(
        coupling_status == "Insufficient evidence" ~
          "Needs at least three comparable aftcasts for both Spring population methods",
        coupling_status == "Major/classification" ~ paste0(
          "Major/classification improves WAPE by ",
          scales::percent(coupling_wape_gain, accuracy = 0.1),
          " versus broad population growth"
        ),
        coupling_status == "Broad population" ~ paste0(
          "Broad population improves WAPE by ",
          scales::percent(-coupling_wape_gain, accuracy = 0.1),
          " versus major/classification"
        ),
        TRUE ~ paste0(
          "Methods are within ",
          scales::percent(abs(coupling_wape_gain), accuracy = 0.1),
          " WAPE"
        )
      ),
      why_uncertain = dplyr::case_when(
        confidence == "None" & methods_disagree ~ paste0(
          confidence_reason, "; candidate methods also disagree materially"
        ),
        confidence == "None" ~ confidence_reason,
        TRUE ~ "Historical aftcast evidence meets the displayed confidence threshold"
      ),
      structural_gap_threshold = pmax(
        as.numeric(opt$demand_min_structural_gap %||% 10),
        as.numeric(opt$demand_min_structural_gap_share %||% 0.10) *
          observed_baseline
      ),
      spring_flow_credible = projection_structural_credible(
        spring_flow_projection, spring_flow_n_backtests,
        spring_flow_observed_wape, spring_flow_uncensored_wape,
        spring_flow_coverage, opt
      ),
      population_credible = projection_structural_credible(
        population_projection, population_n_backtests,
        population_observed_wape, population_uncensored_wape,
        population_coverage, opt
      ),
      feeder_credible = projection_structural_credible(
        feeder_projection, feeder_n_backtests, feeder_observed_wape,
        feeder_uncensored_wape, feeder_coverage, opt
      ),
      n_credible_structural_methods = sum(
        c(population_credible, spring_flow_credible, feeder_credible)
      ),
      structural_high_projection = {
        estimates <- c(
          if (population_credible) population_projection else NA_real_,
          if (spring_flow_credible) spring_flow_projection else NA_real_,
          if (feeder_credible) feeder_projection else NA_real_
        )
        if (any(is.finite(estimates))) max(estimates[is.finite(estimates)]) else
          NA_real_
      },
      structural_gap = structural_high_projection - observed_baseline,
      n_structural_above_observed = sum(
        c(
          if (population_credible) population_projection else NA_real_,
          if (spring_flow_credible) spring_flow_projection else NA_real_,
          if (feeder_credible) feeder_projection else NA_real_
        ) >=
          observed_baseline + structural_gap_threshold,
        na.rm = TRUE
      ),
      demand_signal = dplyr::case_when(
        n_structural_above_observed >= 2L & persistent_capacity_reached &
          observed_enrollment_rising ~ "Strong structural signal",
        n_structural_above_observed >= 1L & persistent_capacity_reached &
          observed_enrollment_rising ~ "Possible latent demand",
        is.finite(observed_baseline) & scheduled_capacity > 0 &
          observed_baseline - scheduled_capacity >=
            structural_gap_threshold & persistent_capacity_reached ~
          "Observed capacity pressure",
        n_structural_above_observed >= 1L ~
          "Structural estimate uncorroborated",
        TRUE ~ "Not indicated"
      ),
      demand_signal_reason = dplyr::case_when(
        demand_signal == "Strong structural signal" ~ paste0(
          "Multiple structural methods exceed the seasonal baseline; ",
          recent_capacity_reached_terms, "/", recent_capacity_terms,
          " recent terms reached registration capacity and enrollment is rising"
        ),
        demand_signal == "Possible latent demand" ~ paste0(
          "One structural method exceeds the seasonal baseline; ",
          recent_capacity_reached_terms, "/", recent_capacity_terms,
          " recent terms reached registration capacity and enrollment is rising"
        ),
        demand_signal == "Observed capacity pressure" ~
          "Seasonal class-list baseline exceeds scheduled capacity in a capacity-reached history",
        demand_signal == "Structural estimate uncorroborated" ~
          "A structural estimate is higher, but recent capacity history does not corroborate unmet demand",
        TRUE ~ "No structural estimate clears the evidence threshold"
      ),
      recommendation = dplyr::case_when(
        !is.finite(projected_classlist_total) ~ "Insufficient history",
        projected_classlist_total <= 0 ~ "No projected demand",
        !target_schedule_available & !is.na(recommended_sections) ~
          paste("Plan", recommended_sections, "section(s)"),
        is.finite(projection_high) &
          projection_high <= scheduled_capacity ~
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
      ),
      demand_note = dplyr::case_when(
        demand_signal %in% c("Strong structural signal", "Possible latent demand") ~
          paste0(
            demand_signal, ": structural high ",
            round(structural_high_projection), " vs seasonal baseline ",
            round(observed_baseline)
          ),
        demand_signal == "Capacity data review" ~
          "Review section capacity before inferring unmet demand",
        TRUE ~ demand_signal_reason
      )
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(
      -method_rank, -selection_eligible, -upstream_evidence_eligible
    )
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
    recent_history = analysis$recent_history
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
    "recent_history"
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
      "projected_classlist_total", "method_id", "confidence",
      "confidence_reason", "why_uncertain", "recommendation",
      "target_term_label", "backtest_terms", "backtest_term_range",
      "selection_wape", "selection_n_backtests", "selection_basis",
      "selection_uses_uncensored", "capacity_constrained_history",
      "observed_baseline", "capacity_data_quality", "demand_signal",
      "target_schedule_available", "raw_projected_classlist_total",
      "calibrated_projected_classlist_total", "calibration_factor",
      "census_retention_rate", "census_retention_n_terms",
      "census_retention_terms", "projected_census_equivalent",
      "calibration_applied", "calibration_adjustment",
      "weighted_bias", "direction_consistency", "signed_error_history",
      "proposed_calibration_factor", "calibration_recommended",
      "calibrated_wape", "calibration_wape_gain", "calibration_reason",
      "capacity_censored_wape", "n_capacity_censored_misses",
      "capacity_explained_error_share", "capacity_miss_assessment",
      "target_classlist_total_to_date", "target_registered_now",
      "target_early_drops_to_date", "target_late_drops_to_date",
      "target_other_status_to_date",
      "target_registration_observed", "target_available_seats",
      "target_classlist_fill", "target_active_fill", "target_capacity_reached",
      "projected_over_capacity",
      "capacity_limit_signal", "capacity_limit_status",
      "capacity_limit_note", "population_projection",
      "population_observed_wape", "population_n_backtests",
      "spring_flow_projection", "spring_flow_observed_wape",
      "spring_flow_n_backtests", "coupling_n_backtests",
      "coupling_wape_gain", "coupling_status", "coupling_reason"),
    "validate_enrollment_projection_bundle() projections"
  )
  projection_require_columns(
    bundle$recent_history,
    c(
      "market_id", "subject_course", "term_type",
      "projection_target_term", "history_term", "history_term_label",
      "recency_rank", "actual_classlist_total", "actual_census",
      "actual_final_enrollment",
      "scheduled_sections", "scheduled_capacity", "method_id",
      "prior_classlist_total", "prior_scheduled_capacity",
      "classlist_change", "capacity_change",
      "method_label", "aftcast_applicable", "aftcast_reason",
      "raw_aftcast_classlist_total", "aftcast_classlist_total",
      "calibration_applied", "calibration_factor", "aftcast_error",
      "aftcast_pct_error", "registration_fill", "capacity_reached",
      "aftcast_capacity_censored", "aftcast_censored_error",
      "aftcast_censored_pct_error", "potential_miss_explanation"
    ),
    "validate_enrollment_projection_bundle() recent_history"
  )
  projection_require_columns(
    bundle$candidates,
    c("market_id", "college", "subject_course", "target_term", "method_id",
      "method_role", "projected_classlist_total", "applicable", "selected",
      "census_retention_rate", "census_retention_n_terms",
      "census_retention_terms", "projected_census_equivalent",
      "target_term_label", "n_backtests", "backtest_terms",
      "backtest_term_range", "wape", "census_equivalent_wape",
      "capacity_censored_wape",
      "uncensored_wape", "raw_projected_classlist_total", "calibration_factor",
      "calibration_applied", "calibration_adjustment", "weighted_bias",
      "pct_error_sd", "direction_consistency", "signed_error_history",
      "proposed_calibration_factor", "calibration_recommended",
      "calibrated_wape", "calibration_wape_gain", "calibration_reason",
      "capacity_censored_wape", "n_capacity_censored_misses",
      "capacity_explained_wape", "capacity_explained_error_share",
      "capacity_censored_terms", "capacity_miss_assessment"),
    "validate_enrollment_projection_bundle() candidates"
  )
  projection_require_columns(
    bundle$candidates,
    c(
      "baseline_term", "prior_source_term", "source_term",
      "baseline_classlist_total", "matched_baseline", "unmatched_baseline",
      "matched_projection", "unmatched_projection",
      "source_population_previous", "source_population_current",
      "source_population_growth", "projection_formula"
    ),
    "validate_enrollment_projection_bundle() candidate audit fields"
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
      "direction_consistency", "signed_error_history",
      "proposed_calibration_factor", "calibration_candidate",
      "n_calibrated_backtests", "calibrated_wape", "calibration_wape_gain",
      "calibration_validated", "calibration_recommended",
      "calibration_reason", "capacity_censored_wape",
      "census_equivalent_wape",
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
        "method_role", "raw_projected_classlist_total", "calibration_training_n",
        "calibration_training_bias", "calibration_direction_consistency",
        "calibration_factor", "calibration_applied", "calibration_reason",
        "calibrated_projected_classlist_total", "calibrated_error",
        "calibrated_abs_error", "calibrated_pct_error",
        "actual_classlist_total", "actual_census", "actual_final_enrollment",
        "projected_census_equivalent", "registration_fill",
        "registration_capacity_gap", "capacity_reached",
        "capacity_censored_classlist_projection",
        "capacity_censored_error", "capacity_censored_abs_error",
        "capacity_censored_miss", "capacity_explained_classlist_error",
        "capacity_explained_share"
      ),
      "validate_enrollment_projection_bundle() backtests"
    )
  }
  invalid_confidence <- setdiff(
    unique(bundle$projections$confidence), c("High", "Medium", "Low", "None")
  )
  if (length(invalid_confidence) > 0L) {
    stop(
      "[enrollment-projections.R] Projection confidence contains unsupported values.",
      call. = FALSE
    )
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
  validate_spring_cohort_rows(
    bundle$candidates, "validate_enrollment_projection_bundle() candidates"
  )
  validate_projection_calibration_rows(
    bundle$projections,
    "validate_enrollment_projection_bundle() projections",
    published = TRUE
  )
  validate_projection_calibration_rows(
    bundle$candidates,
    "validate_enrollment_projection_bundle() candidates",
    published = TRUE
  )
  if (nrow(bundle$backtests) > 0) {
    validate_spring_cohort_rows(
      bundle$backtests, "validate_enrollment_projection_bundle() backtests"
    )
    validate_projection_calibration_rows(
      bundle$backtests,
      "validate_enrollment_projection_bundle() backtests"
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
