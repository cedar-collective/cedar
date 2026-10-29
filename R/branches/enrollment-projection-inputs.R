# Preparing a projection's inputs: class-list demand history for the market,
# first-day counts, section history, the delivery components behind each
# market row, student inputs for the deltas, and the retained waitlist.

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
# It is what "were the seats full" is judged on: census, the 15th day of
# instruction, follows three weeks of drops, so a course full on day one can
# read 95% at census. Sections are sized for projected registrations (0.23.0). It is NA, never a partial count, for a term whose class lists
# carry no status dates or were pulled before a section began;
# `first_day_basis` says which, and `first_day_started_enrl` is the count over
# the sections that had begun (ISSUES.md I28, projection_judged_first_day()).
prepare_projection_market_enrollment_history <- function(students, sections,
                                                         courses, campuses,
                                                         market_id,
                                                         through_term = NULL) {
  classlist_rows <- projection_market_classlist_rows(
    students, courses, campuses, through_term,
    "prepare_projection_market_enrollment_history()"
  )

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
        dplyr::mutate(
          first_day_enrl = as.numeric(first_day_enrl),
          first_day_started_enrl = as.numeric(first_day_started_enrl)
        ),
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


# The market's non-waitlist class-list rows: its declared campuses and courses,
# through the enrollment edge. Pooled and per-campus first days read the same
# rows.
projection_market_classlist_rows <- function(students, courses, campuses,
                                             through_term, caller) {
  projection_require_columns(
    students,
    c("student_id", "term", "campus", "college", "subject_course",
      "registration_status_code", "crn", "registration_date", "as_of_date"),
    caller
  )
  rows <- students %>%
    dplyr::ungroup() %>%
    dplyr::filter(
      campus %in% .env$campuses,
      subject_course %in% .env$courses,
      !registration_status_code %in% STATUS_WAITLIST
    ) %>%
    dplyr::mutate(term = suppressWarnings(as.integer(as.character(term))))
  if (!is.null(through_term) && length(through_term) > 0) {
    rows <- dplyr::filter(rows, term <= as.integer(through_term[[1]]))
  }
  rows
}


# Each delivery campus's own first day, per course and term: distinct students
# across that campus's colleges and sessions. The forecast pools the market;
# this keeps a campus that filled on day one visible beside one that had room
# (ISSUES.md M36). It never feeds a projection.
prepare_projection_delivery_first_day <- function(students, sections, courses,
                                                  campuses,
                                                  through_term = NULL) {
  classlist_rows <- projection_market_classlist_rows(
    students, courses, campuses, through_term,
    "prepare_projection_delivery_first_day()"
  )
  empty <- tibble::tibble(
    campus = character(), term = integer(), subject_course = character(),
    first_day_enrl = numeric(), first_day_basis = character()
  )
  if (nrow(classlist_rows) == 0L) return(empty)
  # pool_campuses on one campus's rows counts each student-course once
  # within that campus; nothing is pooled across campuses here.
  dplyr::bind_rows(lapply(split(classlist_rows, classlist_rows$campus), function(rows) {
    calc_first_day_enrl(rows, sections, pool_campuses = TRUE) %>%
      dplyr::transmute(
        campus = rows$campus[[1]], term = as.integer(term), subject_course,
        first_day_enrl = as.numeric(first_day_enrl), first_day_basis
      )
  })) %>%
    dplyr::arrange(subject_course, term, campus)
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


# Distinct students left waiting on a course, per market term, who are on no
# campus's class list in the market. Starts from the canonical class-list
# waitlist-demand rule (R/branches/waitlist-demand.R), then removes anyone the
# market's class-list total already counts. Class lists retain waitlist rows
# only from Summer 2026, so earlier terms report zero rows here rather than
# zero demand; the floor says which.
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

  # The canonical rule removes anyone registered in the same delivery group,
  # so a student holding an EA seat while waiting at ABQ survives it. The
  # floor adds these students to the market's class-list total, which already
  # counts anyone with a non-waitlist row on either campus (registered, or an
  # earlier drop), so they are removed first (ISSUES.md I27).
  on_class_list <- scoped %>%
    dplyr::filter(!registration_status_code %in% STATUS_WAITLIST) %>%
    # CAMPUS_ROLLUP: membership of the pooled market's class list, either campus.
    dplyr::distinct(student_id, term, subject_course)
  # CAMPUS_ROLLUP: the market counts each waiting student once across its
  # pooled campuses.
  get_true_waitlisted_rows(scoped, sections) %>%
    dplyr::distinct(student_id, term, subject_course) %>%
    dplyr::anti_join(on_class_list, by = c("student_id", "term", "subject_course")) %>%
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
                                                 graded_through_term = NULL,
                                                 intersession_parts_of_term) {
  # December intersession is out of the forecast (0.24.0). It starts weeks
  # after the term's first day, so its seats left a course's first day unknown
  # until December (ISSUES.md I28), and it registers after a Fall settles, so
  # its students read the Fall spine from a partial Fall (I35). Its sections
  # and class-list rows leave here, so no demand, seat or first-day count reads
  # them. (cl_enrls only supplies prior counts for the target's sections.)
  drop_intersession <- function(rows) {
    if (length(intersession_parts_of_term) == 0L) return(rows)
    projection_require_columns(rows, "part_term", "prepare_enrollment_projection_inputs()")
    rows[!trimws(as.character(rows$part_term)) %in% intersession_parts_of_term, ,
         drop = FALSE]
  }
  sections <- drop_intersession(sections)
  # Only the class-list columns the helpers below read are copied: a second
  # copy of the whole table ran the Docker build out of memory.
  students <- drop_intersession(dplyr::select(students, dplyr::all_of(c(
    "student_id", "term", "campus", "college", "subject_course", "part_term",
    "crn", "registration_status_code", "registration_date", "as_of_date",
    "major_code", "student_classification", "final_grade"
  ))))
  if (is.null(target_courses) || length(target_courses) == 0) {
    stop("[enrollment-projection-inputs.R] target_courses is required.", call. = FALSE)
  }
  target_courses <- sort(unique(as.character(target_courses)))
  if (is.null(target_campuses) || length(target_campuses) == 0) {
    stop("[enrollment-projection-inputs.R] target_campuses is required.", call. = FALSE)
  }
  target_campuses <- sort(unique(as.character(target_campuses)))
  if (is.null(target_market_id) || length(target_market_id) != 1L ||
      is.na(target_market_id) || !nzchar(target_market_id)) {
    stop("[enrollment-projection-inputs.R] target_market_id is required.", call. = FALSE)
  }
  if (is.null(section_through_term) || length(section_through_term) != 1L ||
      is.na(section_through_term)) {
    stop("[enrollment-projection-inputs.R] section_through_term is required.",
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
    delivery_first_day = prepare_projection_delivery_first_day(
      students, sections, courses = target_courses, campuses = target_campuses,
      through_term = enrollment_through_term
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
