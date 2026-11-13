# course-report assembles the data behind the app's Course Dynamics tab.
# create_course_base_data() gathers enrollment and rollcall data; the per-sub-tab
# helpers compute flows and outcomes lazily when a sub-tab is opened.
# REQUIRES: opt$course (and typically opt$course_campus)
# TODO: separate remaining processing from report assembly as with the lazy tab helpers.

get_course_data <- function(data_objects, opt, skip_neighbors = FALSE,
                            enrollment_payload = NULL) {
  # for studio testing...
  # students <- load_students()
  # courses <- load_courses()
  # opt <- list()
  # opt[["course"]] <- "MATH 1350"
  # opt[["term"]] <- 202580

  # Extract CEDAR data objects (no legacy fallbacks)
  students <- data_objects[["cedar_registrations"]]
  courses <- data_objects[["cedar_sections"]]
  # Rollcall reads each student's classification and major off the student-term
  # table, and each share's denominator off the course-term table.
  student_terms <- data_objects[["cedar_student_terms"]]
  course_terms <- data_objects[["cedar_course_terms"]]

  # Bail out early with a clear error if required datasets are missing
  if (is.null(courses)) {
    stop("[course_report.R] cedar_sections dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(students)) {
    stop("[course_report.R] cedar_registrations dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(student_terms)) {
    stop("[course_report.R] cedar_student_terms dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(course_terms)) {
    stop("[course_report.R] cedar_course_terms dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  cedar_debug("[course_report.R] Students: ", nrow(students), " rows / Courses: ", nrow(courses), " rows")

  # Course Dynamics follows the course, not the code (ADR-001 step 4): both
  # tables are read keyed on course_id, so every filter, grouping and flow
  # below sees SOCI 371's SOC 371 terms as its own and a feeder renumbered
  # mid-history as one course. The code asked for resolves to its course once.
  if (is.null(opt[["course"]]) || length(opt[["course"]]) == 0) {
    stop("[course_report.R] get_course_data requires opt$course")
  }
  opt[["course"]] <- course_id_of(courses, as.character(opt[["course"]])[[1]], "get_course_data")

  # init payload list for return value
  course_data <- list()

  # Set term range for filtering (parallel to dept-trends.R)
  course_data[["term_start"]] <- cedar_report_start_term
  course_data[["term_end"]] <- cedar_report_end_term

  # these should always be set this way
  opt$status <- "A"
  opt$uel <- TRUE

  # keep students as is for course-neighbors analysis
  filtered_students <- students %>% filter_class_list(opt)

  if (is.null(filtered_students) || nrow(filtered_students) == 0) {
    message("[course_report.R] WARNING: No students found after filtering for course ", opt[["course"]])
  }

  # create term agnostic opt param for getting historic enrollments from DESRs
  myopt <- opt
  myopt[["term"]] <- NULL
  myopt[["group_cols"]] <- c("campus","college","term", "term_type", "subject", "subject_course", "course_title")

  # Use the same crosslist-aware registration payload as Overview. Keeping the
  # family total under the established `cl_enrls` key means every Course
  # Dynamics enrollment plot and table consumes the same canonical counts;
  # the selected-code series remains available only for explicitly labeled
  # comparison context.
  if (is.null(enrollment_payload)) {
    enrollment_payload <- assemble_course_enrollment_payload(
      students, courses, opt
    )
  }
  course_data[["cl_enrls"]] <- enrollment_payload[["classlist"]]
  course_data[["selected_cl_enrls"]] <- enrollment_payload[["selected_classlist"]]

  ####################
  # run LOOKOUT functions to see where students are coming and going from
  # Use caching to avoid expensive recomputation.
  # Skipped when skip_neighbors = TRUE (Shiny lazy-loads this on Course Flows tab click).
  if (!skip_neighbors) {
    use_cache <- is.null(opt[["skip_cache"]]) || !opt[["skip_cache"]]
    campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL
    # The term-before and term-after courses are read off cedar_course_flows
    # (every next-term pair, counted by the transform to the longitudinal
    # edge); only the same-term courses are counted from the class list.
    course_flows <- data_objects[["cedar_course_flows"]]
    if (is.null(course_flows)) {
      stop("[course_report.R] cedar_course_flows dataset is NULL in data_objects\n",
           "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
    }
    require_course_flows(course_flows, "get_course_data")
    neighbor_students <- students
    neighbor_courses <- courses

    if (!is.null(campus_scope) && length(campus_scope) > 0) {
      neighbor_students <- neighbor_students %>% dplyr::filter(campus %in% .env$campus_scope)
      neighbor_courses <- neighbor_courses %>% dplyr::filter(campus %in% .env$campus_scope)
    }
    # The renames in the frame are an input to a result read by course, so
    # they are in the key: a newly confirmed code_history row is a miss. So is
    # the flows' edge: a newly settled term adds pairs.
    cache_scope <- list(
      course_campus = campus_scope,
      code_renames = course_code_renames(neighbor_students),
      enrolled_edge = attr(course_flows, "enrolled_edge", exact = TRUE)
    )

    if (use_cache) {
      course_neighbors_cache <- load_course_neighbors_cache(
        opt[["course"]], neighbor_students, neighbor_courses, cache_scope)

      if (!is.null(course_neighbors_cache)) {
        message("[course_report.R] Cache hit: course-neighbors for ", opt[["course"]])
        course_data[["where_from"]] <- course_neighbors_cache$where_from
        course_data[["where_to"]] <- course_neighbors_cache$where_to
        course_data[["where_at"]] <- course_neighbors_cache$where_at
      } else {
        message("[course_report.R] Cache miss: computing course-neighbors for ", opt[["course"]])
        course_data[["where_from"]] <- get_course_feeders(course_flows, myopt)
        course_data[["where_to"]] <- get_course_destinations(course_flows, myopt)
        course_data[["where_at"]] <- get_concurrent_courses(neighbor_students, myopt)

        course_neighbors_data <- list(
          where_from = course_data[["where_from"]],
          where_to = course_data[["where_to"]],
          where_at = course_data[["where_at"]]
        )
        save_course_neighbors_cache(
          opt[["course"]], course_neighbors_data, neighbor_students, neighbor_courses, cache_scope)
      }
    } else {
      cedar_debug("[course_report.R] Cache disabled — computing fresh course-neighbors.")
      course_data[["where_from"]] <- get_course_feeders(course_flows, myopt)
      course_data[["where_to"]] <- get_course_destinations(course_flows, myopt)
      course_data[["where_at"]] <- get_concurrent_courses(neighbor_students, myopt)
    }
  } else {
    cedar_debug("[course_report.R] Skipping course-neighbors (lazy-loaded on tab click).")
  }


  ###################
  # get DEMOGRAPHICS data (and pivot to wide for report display)
  ####################
  myopt[["registration_status_code"]] <- STATUS_REGISTERED

  # demographics by classification
  myopt[["group_cols"]] <- c("campus", "college", "term", "term_type", "student_classification", "subject_course", "level")
  demo_by_class_raw <- get_course_demographics(filtered_students, student_terms, course_terms, myopt)
  cedar_debug("[course_report.R] demo_by_class: ", nrow(demo_by_class_raw), " rows")

  demo_by_class_for_plot <- demo_by_class_raw

  demo_by_class_table <- demo_by_class_for_plot %>%
    pivot_wider(names_from = term, values_from = term_pct, values_fill = 0)

  course_data[["rollcall_by_class"]] <- demo_by_class_table
  course_data[["rollcall_by_class_plot_data"]] <- demo_by_class_for_plot


  # demographics by major
  myopt[["group_cols"]] <- c("campus", "college", "term", "term_type", "major_code", "subject_course", "level")
  demo_by_major_raw <- get_course_demographics(filtered_students, student_terms, course_terms, myopt)
  cedar_debug("[course_report.R] demo_by_major: ", nrow(demo_by_major_raw), " rows")

  demo_by_major_for_plot <- demo_by_major_raw

  demo_by_major_table <- demo_by_major_for_plot %>%
    pivot_wider(names_from = term, values_from = term_pct, values_fill = 0)

  course_data[["rollcall_by_major"]] <- demo_by_major_table
  course_data[["rollcall_by_major_plot_data"]] <- demo_by_major_for_plot

  return(course_data)
}


# ---- Course Overview assembly ----------------------------------------------

prepare_course_lifecycle_history <- function(cl_enrls) {
  # A course can have active sections and no class-list rows at all. Its
  # history is empty but keeps its columns, so the overview still shows the
  # sections and leaves enrollment blank instead of failing on a missing column.
  if (is.null(cl_enrls) || nrow(cl_enrls) == 0) {
    return(tibble::tibble(
      campus = character(), college = character(), term = integer(),
      term_type = character(), subject_course = character(),
      first_day_enrl = integer(), current_enrl = integer(),
      census_enrl = numeric(), early_drops = integer(), late_drops = integer(),
      waitlisted = integer(), all_drops = integer(), classlist_total = integer()
    ))
  }
  cedar_require_campus(cl_enrls, "prepare_course_lifecycle_history")
  if (!"first_day_enrl" %in% names(cl_enrls)) {
    stop("[course-report.R] prepare_course_lifecycle_history() needs first_day_enrl; ",
         "attach it with add_first_day_enrl()")
  }

  cl_enrls %>%
    add_census_enrl() %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      term = suppressWarnings(as.integer(as.character(term))),
      term_type = vapply(term, get_term_type, character(1)),
      current_enrl = registered,
      classlist_total = cl_total
    ) %>%
    dplyr::select(
      campus, college, term, term_type, subject_course,
      first_day_enrl, current_enrl, census_enrl, early_drops = dr_early,
      late_drops = dr_late, waitlisted = wl_all,
      all_drops = dr_all, classlist_total
    ) %>%
    dplyr::arrange(campus, term)
}


assemble_course_overview <- function(sections, cl_enrls, opt,
                                     crosslist_cl_enrls = NULL,
                                     listing_cl_enrls = NULL,
                                     listing_overlap = NULL) {
  selected_lifecycle <- prepare_course_lifecycle_history(cl_enrls)
  family_lifecycle <- if (!is.null(crosslist_cl_enrls) &&
                          nrow(crosslist_cl_enrls) > 0) {
    prepare_course_lifecycle_history(crosslist_cl_enrls)
  } else {
    selected_lifecycle
  }

  selected_counts <- selected_lifecycle %>%
    dplyr::select(
      campus, term, term_type, subject_course,
      selected_current_enrl = current_enrl,
      selected_census_enrl = census_enrl
    )
  # A family term with no rows under the selected code is a measured zero:
  # every student in that offering registered under a partner listing.
  lifecycle <- family_lifecycle %>%
    dplyr::left_join(
      selected_counts,
      by = c("campus", "term", "term_type", "subject_course")
    ) %>%
    dplyr::mutate(
      selected_current_enrl = dplyr::coalesce(selected_current_enrl, 0L),
      selected_census_enrl = dplyr::coalesce(selected_census_enrl, 0)
    )

  # Each code's own count, so a crosslisted total can be read against the
  # listings it combines. Without a family, the selected code is the only one.
  listings <- if (!is.null(listing_cl_enrls) && nrow(listing_cl_enrls) > 0) {
    prepare_course_lifecycle_history(listing_cl_enrls)
  } else {
    selected_lifecycle
  }

  overlap <- if (!is.null(listing_overlap) && nrow(listing_overlap) > 0) {
    listing_overlap %>%
      dplyr::mutate(
        term = as.integer(term),
        term_type = vapply(term, get_term_type, character(1))
      )
  } else {
    tibble::tibble(
      campus = character(), term = integer(), term_type = character(),
      kind = character(), from_code = character(), to_code = character(),
      students = integer()
    )
  }

  list(
    lifecycle = lifecycle,
    sections = get_course_section_history(sections, opt),
    listings = listings %>%
      dplyr::select(
        campus, term, term_type, subject_course, first_day_enrl,
        census_enrl, current_enrl, early_drops, late_drops, waitlisted
      ),
    overlap = overlap
  )
}


#' Assemble the shared Course Dynamics enrollment payload
#'
#' Resolves the selected course's active crosslist family once, calculates its
#' class-list lifecycle through the standard enrollment branch, and supplies
#' that same family series to both Overview and the detailed Enrollment tab.
#' Each listing's own counts are retained only for labeled comparison in the
#' Overview snapshot and the enrollment-history hover.
#'
#' @param students `cedar_registrations`.
#' @param sections `cedar_sections`.
#' @param opt Course Dynamics options including `course`.
#' @return A list containing `overview`, crosslist-family `classlist`, and
#'   `selected_classlist` comparison data.
assemble_course_enrollment_payload <- function(students, sections, opt) {
  classlist <- get_course_crosslist_classlist_enrl(students, sections, opt)
  list(
    overview = assemble_course_overview(
      sections, classlist$selected, opt,
      crosslist_cl_enrls = classlist$family,
      listing_cl_enrls = classlist$listings,
      listing_overlap = classlist$overlap
    ),
    classlist = classlist$family,
    selected_classlist = classlist$selected
  )
}


filter_course_overview <- function(overview, campuses = NULL, term_type = NULL) {
  filter_one <- function(data, source_name) {
    if (is.null(data) || nrow(data) == 0) return(data)
    data <- cedar_filter_campus(data, campuses, paste0("filter_course_overview$", source_name))
    selected_types <- setdiff(term_type %||% character(0), "all")
    if (length(selected_types) > 0) {
      data <- data[data$term_type %in% selected_types, , drop = FALSE]
    }
    data
  }

  list(
    lifecycle = filter_one(overview$lifecycle, "lifecycle"),
    sections = filter_one(overview$sections, "sections"),
    listings = filter_one(overview$listings, "listings"),
    overlap = filter_one(overview$overlap, "overlap")
  )
}


course_overview_term_types <- function(overview) {
  types <- unique(c(
    overview$lifecycle$term_type %||% character(0),
    overview$sections$term_type %||% character(0)
  ))
  intersect(c("fall", "spring", "summer"), types[!is.na(types)])
}


default_course_overview_term_type <- function(overview, current_term = NULL) {
  available <- course_overview_term_types(overview)
  if (length(available) == 0) return(NULL)

  current_type <- if (!is.null(current_term) && length(current_term) > 0) {
    get_term_type(current_term[[1]])
  } else {
    NULL
  }
  if (!is.null(current_type) && current_type %in% available) return(current_type)

  terms <- c(
    overview$lifecycle$term %||% integer(0),
    overview$sections$term %||% integer(0)
  )
  terms <- suppressWarnings(as.integer(as.character(terms)))
  terms <- terms[!is.na(terms)]
  if (length(terms) == 0) return(available[[1]])

  latest_type <- get_term_type(max(terms))
  if (latest_type %in% available) latest_type else available[[1]]
}


#' Join one campus-term row of every Overview measure
#'
#' @param overview Overview payload from `assemble_course_overview()`.
#' @param campuses,term_type Optional scope filters.
#' @return One row per campus, term, and course with the snapshot's lifecycle
#'   and section measures; a term missing from either source carries NA for
#'   its measures. Stops if either source holds a key twice, since joining or
#'   reading such a key would double a measure or silently keep one row.
course_overview_history <- function(overview, campuses = NULL, term_type = NULL) {
  scoped <- filter_course_overview(overview, campuses, term_type)
  keys <- c("campus", "term", "term_type", "subject_course")
  lifecycle_cols <- c(
    keys, "first_day_enrl", "census_enrl", "current_enrl",
    "early_drops", "late_drops", "waitlisted"
  )
  section_cols <- c(keys, "sections", "avg_section_size")
  lifecycle <- scoped$lifecycle
  sections <- scoped$sections
  if (nrow(lifecycle) == 0 && nrow(sections) == 0) return(tibble::tibble())
  missing <- c(
    if (nrow(lifecycle) > 0) setdiff(lifecycle_cols, names(lifecycle)),
    if (nrow(sections) > 0) setdiff(section_cols, names(sections))
  )
  if (length(missing) > 0) {
    stop("[course-report.R] course_overview_history() needs column(s): ",
         paste(missing, collapse = ", "))
  }
  for (source in c("lifecycle", "sections")) {
    data <- get(source)
    if (nrow(data) > 0 && anyDuplicated(data[, keys]) > 0) {
      stop("[course-report.R] course_overview_history(): overview$", source,
           " has more than one row per campus, term, and course")
    }
  }
  if (nrow(lifecycle) == 0) lifecycle <- NULL else lifecycle <- lifecycle[, lifecycle_cols]
  if (nrow(sections) == 0) sections <- NULL else sections <- sections[, section_cols]
  if (is.null(lifecycle)) return(dplyr::arrange(sections, campus, term))
  if (is.null(sections)) return(dplyr::arrange(lifecycle, campus, term))

  dplyr::full_join(lifecycle, sections, by = keys, relationship = "one-to-one") %>%
    dplyr::arrange(campus, term)
}


# The measures in the Overview snapshot, in display order. `split` measures are
# counted per listing; section measures are not, because a shared section is
# one room with one count.
COURSE_SNAPSHOT_MEASURES <- tibble::tribble(
  ~group,       ~key,               ~label,            ~digits, ~split, ~settles,
  "Enrollment", "first_day_enrl",   "First day",       0L,      TRUE,   FALSE,
  "Enrollment", "census_enrl",      "Census",          0L,      TRUE,   FALSE,
  "Enrollment", "current_enrl",     "Final",           0L,      TRUE,   TRUE,
  "Churn",      "early_drops",      "Early drops",     0L,      TRUE,   FALSE,
  "Churn",      "late_drops",       "Late drops",      0L,      TRUE,   TRUE,
  "Churn",      "waitlisted",       "Waitlisted",      0L,      TRUE,   FALSE,
  "Sections",   "sections",         "Active sections", 0L,      FALSE,  FALSE,
  "Sections",   "avg_section_size", "Average size",    1L,      FALSE,  FALSE
)


#' Prepare the Course Overview snapshot table for each campus
#'
#' One table per delivery campus: the latest term in the selected term type
#' beside the same term in up to `n_prior` earlier years. When that term was
#' crosslisted, its column splits into All listings and each code's own count,
#' selected code first. Earlier years stay totals and carry their split as hover
#' text. A footnote names students listed under more than one code, since their
#' rows make the code columns add up to more than All. Measures that keep
#' moving until a term ends say "so far" while it is in progress.
#'
#' This is the display adapter, so values arrive formatted.
#'
#' @param overview Overview payload from `assemble_course_overview()`.
#' @param selected_course The course code the report was run for.
#' @param campuses,term_type Optional scope filters.
#' @param in_progress_terms Term codes after the grade edge.
#' @param n_prior Earlier same-season years to show.
#' @return A list of table specs for `cedar_snapshot_table()`, one per campus.
prepare_course_snapshot_tables <- function(overview, selected_course,
                                           campuses = NULL, term_type = NULL,
                                           in_progress_terms = NULL,
                                           n_prior = 3L) {
  history <- course_overview_history(overview, campuses, term_type)
  if (nrow(history) == 0) return(list())
  scoped <- filter_course_overview(overview, campuses, term_type)
  lapply(sort(unique(history$campus)), function(campus_code) {
    course_snapshot_table_spec(
      history[history$campus == campus_code, , drop = FALSE],
      listings = scoped$listings[scoped$listings$campus == campus_code, , drop = FALSE],
      overlap = scoped$overlap[scoped$overlap$campus == campus_code, , drop = FALSE],
      campus_code = campus_code,
      selected_course = selected_course,
      in_progress_terms = in_progress_terms,
      n_prior = n_prior
    )
  })
}


course_snapshot_table_spec <- function(history, listings, overlap, campus_code,
                                       selected_course, in_progress_terms,
                                       n_prior) {
  current <- max(history$term, na.rm = TRUE)
  prior_terms <- current - 100L * seq_len(n_prior)
  in_progress <- current %in% in_progress_terms

  fmt <- function(x, digits) {
    if (length(x) == 0 || is.na(x)) return("\u2014")
    formatC(x, format = "f", digits = digits, big.mark = ",")
  }
  value_at <- function(term, key) {
    row <- history[history$term == term, , drop = FALSE]
    if (nrow(row) == 0) NA_real_ else row[[key]][[1]]
  }
  # The selected code's sections define the family, so a code with no rows in
  # a term it was offered is a measured zero.
  listing_codes <- function(term) {
    codes <- unique(listings$subject_course[listings$term == term])
    if (length(setdiff(codes, selected_course)) == 0) return(character(0))
    c(selected_course, sort(setdiff(codes, selected_course)))
  }
  listing_value <- function(term, code, key) {
    rows <- listings[listings$term == term & listings$subject_course == code, , drop = FALSE]
    if (nrow(rows) == 0) 0 else sum(rows[[key]])
  }
  listing_title <- function(term, key, digits) {
    codes <- listing_codes(term)
    if (length(codes) == 0) return(NA_character_)
    paste(
      paste(codes, vapply(codes, function(code) fmt(listing_value(term, code, key), digits), "")),
      collapse = " \u00b7 "
    )
  }

  codes <- listing_codes(current)
  rows <- lapply(seq_len(nrow(COURSE_SNAPSHOT_MEASURES)), function(i) {
    m <- COURSE_SNAPSHOT_MEASURES[i, ]
    split_here <- length(codes) > 0 && m$split
    list(
      group = m$group,
      label = paste0(m$label, if (in_progress && m$settles) " (so far)" else ""),
      current = c(
        fmt(value_at(current, m$key), m$digits),
        if (split_here) {
          vapply(codes, function(code) fmt(listing_value(current, code, m$key), m$digits),
                 "", USE.NAMES = FALSE)
        }
      ),
      span_listings = length(codes) > 0 && !m$split,
      prior = vapply(prior_terms, function(term) fmt(value_at(term, m$key), m$digits), ""),
      prior_titles = vapply(prior_terms, function(term) {
        if (m$split) listing_title(term, m$key, m$digits) else NA_character_
      }, "")
    )
  })

  list(
    caption = paste(selected_course, "\u00b7", campus_code),
    current_label = paste0(fmt_term(current), if (in_progress) " \u00b7 in progress" else ""),
    sub_labels = if (length(codes) > 0) c("All", codes) else NULL,
    prior_labels = fmt_term(prior_terms),
    rows = rows,
    footnote = if (length(codes) > 0) {
      course_listing_overlap_note(overlap[overlap$term == current, , drop = FALSE], length(codes))
    }
  )
}


#' Explain why listing counts add up to more than All
#'
#' @param overlap `summarize_listing_overlap()` rows for one campus and term.
#' @param n_codes Number of codes in the family that term.
#' @return A sentence, or NULL when no student is listed under two codes.
course_listing_overlap_note <- function(overlap, n_codes) {
  total <- sum(overlap$students)
  if (total == 0) return(NULL)
  where <- if (n_codes == 2) "both codes" else "more than one code"
  both <- if (n_codes == 2) "both" else "more than one"
  parts <- character(0)
  moved <- overlap[overlap$kind == "moved", , drop = FALSE]
  for (i in seq_len(nrow(moved))) {
    parts <- c(parts, paste0(moved$students[[i]], " moved from ", moved$from_code[[i]],
                             " to ", moved$to_code[[i]]))
  }
  n_of <- function(kind) sum(overlap$students[overlap$kind == kind])
  if (n_of("enrolled_both") > 0) {
    parts <- c(parts, paste0(n_of("enrolled_both"),
                             if (n_of("enrolled_both") == 1) " is" else " are",
                             " enrolled under ", both))
  }
  if (n_of("dropped_both") > 0) parts <- c(parts, paste0(n_of("dropped_both"), " dropped ", both))
  if (n_of("other") > 0) {
    parts <- c(parts, paste0(n_of("other"), " dropped or waitlisted under ", both))
  }
  joined <- if (length(parts) <= 2) {
    paste(parts, collapse = " and ")
  } else {
    paste0(paste(parts[-length(parts)], collapse = ", "), ", and ", parts[[length(parts)]])
  }
  paste0(
    total, if (total == 1) " student is" else " students are",
    " listed under ", where, ": ", joined, ". ",
    "All counts each student once, so the code columns can add up to more than All."
  )
}


#' Say which other codes the course has been listed under
#'
#' Reads `listed_as` off the overview's section history: the schedule's code
#' for the course in each campus-term, beside the `course_id` the report is
#' keyed on. Names every former code with the terms it covered, so a reader
#' knows the SOC 371 years are in SOCI 371's charts and why.
#'
#' @param overview Overview payload from `assemble_course_overview()`.
#' @param course_code The course's id, the code the report is named by.
#' @param selected_code The code that was picked, when it differs.
#' @return One or two sentences, or NULL when the course has carried one code.
course_former_codes_note <- function(overview, course_code, selected_code = NULL) {
  sections <- overview$sections
  spans <- character(0)
  former <- tibble::tibble(listed_as = character(), term = integer())
  if (!is.null(sections) && nrow(sections) > 0 && "listed_as" %in% names(sections)) {
    former <- sections %>%
      dplyr::filter(!is.na(listed_as), nzchar(listed_as)) %>%
      tidyr::separate_rows(listed_as, sep = " / ") %>%
      dplyr::filter(listed_as != .env$course_code)
  }
  if (nrow(former) > 0) {
    former <- former %>%
      dplyr::group_by(listed_as) %>%
      dplyr::summarize(first = min(term), last = max(term), .groups = "drop") %>%
      dplyr::arrange(first)
    spans <- paste0(
      former$listed_as, " (",
      ifelse(former$first == former$last, fmt_term(former$first),
             paste(fmt_term(former$first), "to", fmt_term(former$last))),
      ")"
    )
  }
  picked <- if (!is.null(selected_code) && !identical(selected_code, course_code)) {
    paste0(selected_code, " is now ", course_code, ". ")
  } else {
    ""
  }
  if (length(spans) == 0 && !nzchar(picked)) return(NULL)
  listed <- if (length(spans) > 0) {
    paste0("Also listed as ", paste(spans, collapse = ", "),
           ": every term under a former code is counted here as ", course_code, ".")
  } else {
    ""
  }
  paste0(picked, listed)
}


build_course_overview_metric_plot <- function(overview, source, metric, y_label,
                                              term_type = NULL, campuses = NULL) {
  source <- match.arg(source, c("lifecycle", "sections"))
  scoped <- filter_course_overview(overview, campuses, term_type)[[source]]
  if (is.null(scoped) || nrow(scoped) == 0 || !metric %in% names(scoped)) return(NULL)

  plot_data <- scoped %>%
    dplyr::filter(!is.na(.data[[metric]])) %>%
    dplyr::mutate(term_label = term_axis_factor(term)) %>%
    dplyr::arrange(campus, term)
  if (nrow(plot_data) == 0) return(NULL)

  plotly::plot_ly(
    plot_data,
    x = ~term_label,
    y = stats::as.formula(paste0("~", metric)),
    color = ~campus,
    split = ~campus,
    colors = cedar_plotly_palette(plot_data$campus),
    type = "scatter",
    mode = "lines+markers",
    line = list(width = 3),
    marker = list(size = 7),
    customdata = ~campus,
    hovertemplate = paste0(
      "Term: %{x}<br>Campus: %{customdata}<br>",
      y_label, ": %{y:,.1f}<extra></extra>"
    )
  ) %>%
    plotly::layout(
      xaxis = list(title = "", tickangle = -45),
      yaxis = list(title = y_label),
      legend = list(title = list(text = "Campus"), orientation = "h", x = 0, y = 1.12),
      margin = list(t = 52, b = 70),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)"
    )
}


#' Plot first-day, census, and final enrollment for each campus over time
#'
#' Three points in each term's life, one line style each and the same colour
#' per campus: first day (dotted), census (solid), final (dashed). First day is
#' a gap, not a zero, wherever it cannot be reconstructed, and absent when no
#' term in scope has it. For a term still in
#' progress the final line is current registration, so those terms are shaded
#' and labelled.
#'
#' @param lifecycle Lifecycle rows from `prepare_course_lifecycle_history()`.
#' @param term_type,campuses Optional scope filters.
#' @param in_progress_terms Term codes after the grade edge
#'   (`cedar_in_progress_terms()$term`).
build_course_enrollment_history_plot <- function(lifecycle, term_type = NULL,
                                                  campuses = NULL,
                                                  in_progress_terms = NULL) {
  if (is.null(lifecycle) || nrow(lifecycle) == 0) return(NULL)
  missing <- setdiff(c("first_day_enrl", "census_enrl", "current_enrl"), names(lifecycle))
  if (length(missing) > 0) {
    stop("[course-report.R] build_course_enrollment_history_plot() needs column(s): ",
         paste(missing, collapse = ", "))
  }
  data <- cedar_filter_campus(
    lifecycle, campuses, "build_course_enrollment_history_plot"
  )
  if (!is.null(term_type) && length(term_type) > 0) {
    data <- data[data$term_type %in% term_type, , drop = FALSE]
  }
  if (nrow(data) == 0) return(NULL)

  data <- data %>%
    dplyr::mutate(term_label = term_axis_factor(term)) %>%
    dplyr::arrange(campus, term)
  campus_colors <- cedar_plotly_palette(data$campus)
  measures <- list(
    list(col = "first_day_enrl", label = "First day", dash = "dot", symbol = "diamond"),
    list(col = "census_enrl", label = "Census", dash = "solid", symbol = "circle"),
    list(col = "current_enrl", label = "Final", dash = "dash", symbol = "square")
  )
  plot <- plotly::plot_ly()

  for (campus_code in unique(data$campus)) {
    campus_data <- data[data$campus == campus_code, , drop = FALSE]
    in_progress <- campus_data$term %in% in_progress_terms
    # When a term combines crosslisted codes, name the selected code's own
    # share so the history never leaves the combined figure unexplained.
    listing_only <- if ("selected_current_enrl" %in% names(campus_data)) {
      combined <- campus_data$selected_current_enrl != campus_data$current_enrl |
        campus_data$selected_census_enrl != campus_data$census_enrl
      ifelse(
        combined %in% TRUE,
        paste0(
          "<br>All listings combined; ", campus_data$subject_course, " alone: ",
          campus_data$selected_census_enrl, " census, ",
          campus_data$selected_current_enrl, " final"
        ),
        ""
      )
    } else {
      ""
    }
    hover <- paste0(
      "Campus: ", campus_data$campus,
      "<br>First day: ", ifelse(
        is.na(campus_data$first_day_enrl),
        "\u2014 (not reconstructable for this term)",
        campus_data$first_day_enrl
      ),
      "<br>Census: ", campus_data$census_enrl,
      "<br>Final: ", campus_data$current_enrl,
      ifelse(in_progress, " (term in progress: current registration)", ""),
      listing_only,
      "<br>Early drops: ", campus_data$early_drops,
      "<br>Late drops: ", campus_data$late_drops,
      "<br>Waitlisted: ", campus_data$waitlisted
    )
    color <- unname(campus_colors[[campus_code]])

    for (measure in measures) {
      # A line with no values in scope is left out: plotly turns an all-NA
      # trace into a nameless categorical one that corrupts the y axis. The
      # hover on the other lines still says why first day is missing.
      if (all(is.na(campus_data[[measure$col]]))) next
      plot <- plot %>%
        plotly::add_trace(
          data = campus_data,
          x = ~term_label,
          y = campus_data[[measure$col]],
          type = "scatter",
          mode = "lines+markers",
          name = paste(campus_code, "\u00b7", measure$label),
          legendgroup = campus_code,
          line = list(color = color, width = 3, dash = measure$dash),
          marker = list(color = color, size = 7, symbol = measure$symbol),
          customdata = hover,
          hovertemplate = paste0(
            "Term: %{x}<br>", measure$label, ": %{y}<br>%{customdata}<extra></extra>"
          )
        )
    }
  }

  plot %>%
    plotly::layout(
      xaxis = list(title = "", tickangle = -45),
      yaxis = list(title = "Students"),
      legend = list(
        title = list(text = "Campus \u00b7 point in term"),
        orientation = "h", x = 0, y = 1.12,
        xanchor = "left", yanchor = "bottom"
      ),
      margin = list(t = 52, b = 70),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)"
    ) %>%
    mark_plotly_terms(as.character(term_code_to_axis_label(in_progress_terms)))
}


build_course_drop_plot <- function(lifecycle, campuses = NULL) {
  if (is.null(lifecycle) || nrow(lifecycle) == 0) return(NULL)
  data <- cedar_filter_campus(lifecycle, campuses, "build_course_drop_plot")
  if (nrow(data) == 0) return(NULL)

  plot_data <- dplyr::bind_rows(
    data %>%
      dplyr::transmute(
        term, campus, drop_type = "Early drops", count = early_drops,
        current_enrl, census_enrl
      ),
    data %>%
      dplyr::transmute(
        term, campus, drop_type = "Late drops", count = late_drops,
        current_enrl, census_enrl
      )
  ) %>%
    dplyr::mutate(
      term_campus = paste(term_code_to_axis_label(term), campus, sep = " / "),
      term_campus = factor(
        term_campus,
        levels = unique(term_campus[order(term, campus)])
      )
    )

  plotly::plot_ly(
    plot_data,
    x = ~term_campus,
    y = ~count,
    color = ~drop_type,
    colors = c("Early drops" = "#486f84", "Late drops" = "#b06b2f"),
    type = "bar",
    customdata = ~paste0(
      "Campus: ", campus,
      "<br>Current enrollment: ", current_enrl,
      "<br>Census enrollment: ", census_enrl
    ),
    hovertemplate = paste0(
      "Term / campus: %{x}<br>%{fullData.name}: %{y}",
      "<br>%{customdata}<extra></extra>"
    )
  ) %>%
    plotly::layout(
      barmode = "group",
      xaxis = list(title = "", tickangle = -45),
      yaxis = list(title = "Students"),
      legend = list(orientation = "h", x = 0, y = 1.12),
      margin = list(t = 52, b = 80),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)"
    )
}


build_course_persistence_plot <- function(persistence) {
  required <- c(
    "campus", "outcome", "n_students", "n_returned", "pct_returned"
  )
  if (is.null(persistence) || nrow(persistence) == 0 ||
      !all(required %in% names(persistence))) {
    return(NULL)
  }

  outcome_order <- c("early drop", "late drop", "fail", "pass")
  outcome_colors <- c(
    "early drop" = unname(CEDAR_COLORS["blue"]),
    "late drop" = unname(CEDAR_COLORS["amber"]),
    "fail" = unname(CEDAR_COLORS["red"]),
    "pass" = unname(CEDAR_COLORS["green"])
  )
  multiple_campuses <- dplyr::n_distinct(persistence$campus) > 1L

  plot_data <- persistence %>%
    dplyr::filter(
      !is.na(campus), !is.na(outcome), !is.na(pct_returned),
      outcome %in% outcome_order
    ) %>%
    dplyr::mutate(
      outcome = as.character(outcome),
      outcome_rank = match(outcome, outcome_order),
      outcome_label = tools::toTitleCase(outcome)
    ) %>%
    dplyr::arrange(campus, outcome_rank) %>%
    dplyr::mutate(
      bar_label = if (multiple_campuses) {
        paste0(campus, " · ", outcome_label)
      } else {
        outcome_label
      },
      bar_label = factor(bar_label, levels = rev(unique(bar_label))),
      pct_label = paste0(round(100 * pct_returned, 1), "%"),
      bar_color = unname(outcome_colors[outcome]),
      hover_text = paste0(
        "Campus: ", campus,
        "<br>Outcome: ", outcome_label,
        "<br>Returned: ", n_returned, " of ", n_students,
        "<br>Next-term persistence: ", pct_label
      )
    )

  if (nrow(plot_data) == 0) return(NULL)

  plotly::plot_ly(
    plot_data,
    x = ~pct_returned,
    y = ~bar_label,
    type = "bar",
    orientation = "h",
    marker = list(color = ~bar_color, line = list(width = 0)),
    text = ~pct_label,
    textposition = "outside",
    cliponaxis = FALSE,
    hovertext = ~hover_text,
    hoverinfo = "text",
    showlegend = FALSE
  ) %>%
    plotly::layout(
      bargap = 0.28,
      xaxis = list(
        title = "Returned next term",
        tickformat = ".0%",
        tickvals = seq(0, 1, by = 0.2),
        range = c(0, 1.08),
        showgrid = TRUE,
        gridcolor = "#E8E3DA",
        zeroline = FALSE
      ),
      yaxis = list(title = "", automargin = TRUE),
      margin = list(l = 105, r = 48, t = 10, b = 45),
      font = list(color = unname(CEDAR_COLORS["text"])),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "#FFFFFF"
    )
}


# Build the Course Dynamics next-term retention benchmark chart. Campus is a
# panel, not a color or an implicit aggregation: every course line must be
# compared only with the department and college cohorts from the same campus.
build_retention_benchmark_plot <- function(diff_data) {
  required <- c(
    "campus", "term", "term_label", "horizon_n", "benchmark",
    "n_course", "course_retention_pct", "n_benchmark",
    "benchmark_retention_pct", "diff_pct"
  )
  if (is.null(diff_data) || nrow(diff_data) == 0 ||
      !all(required %in% names(diff_data))) {
    return(NULL)
  }

  one_term <- diff_data %>%
    dplyr::filter(horizon_n == 1L, !is.na(campus)) %>%
    dplyr::arrange(campus, term)
  if (nrow(one_term) == 0) return(NULL)

  join_keys <- c("campus", "term")
  course_line <- one_term %>%
    dplyr::distinct(
      campus, term, term_label, n_course, course_retention_pct
    ) %>%
    dplyr::left_join(
      one_term %>%
        dplyr::filter(benchmark == "Department") %>%
        dplyr::select(campus, term, dept_diff = diff_pct),
      by = join_keys
    ) %>%
    dplyr::left_join(
      one_term %>%
        dplyr::filter(benchmark == "College") %>%
        dplyr::select(campus, term, college_diff = diff_pct),
      by = join_keys
    ) %>%
    dplyr::transmute(
      campus,
      term,
      term_label,
      series = "Course",
      retention_pct = course_retention_pct,
      hover_text = paste0(
        "Campus: ", campus,
        "<br>", term_label,
        "<br>Course: ", course_retention_pct, "%",
        "<br>Students: ", n_course,
        ifelse(!is.na(dept_diff), paste0("<br>vs Dept: ", dept_diff, " pts"), ""),
        ifelse(!is.na(college_diff), paste0("<br>vs College: ", college_diff, " pts"), "")
      )
    )

  benchmark_lines <- one_term %>%
    dplyr::transmute(
      campus,
      term,
      term_label,
      series = benchmark,
      retention_pct = benchmark_retention_pct,
      hover_text = paste0(
        "Campus: ", campus,
        "<br>", term_label,
        "<br>", benchmark, ": ", benchmark_retention_pct, "%",
        "<br>Students: ", n_benchmark,
        "<br>Course difference: ", diff_pct, " pts"
      )
    )

  series_order <- c("Course", "Department", "College")
  plot_data <- dplyr::bind_rows(course_line, benchmark_lines) %>%
    dplyr::mutate(series = factor(series, levels = series_order)) %>%
    dplyr::arrange(campus, series, term)
  campuses <- sort(unique(as.character(plot_data$campus)))
  colors <- cedar_plotly_palette(series_order, label_order = series_order)
  dashes <- c(Course = "solid", Department = "dash", College = "dot")

  panels <- lapply(seq_along(campuses), function(campus_i) {
    campus_value <- campuses[[campus_i]]
    campus_data <- plot_data %>% dplyr::filter(campus == campus_value)
    term_levels <- campus_data %>%
      dplyr::distinct(term, term_label) %>%
      dplyr::arrange(term) %>%
      dplyr::pull(term_label)

    panel <- plotly::plot_ly()
    for (series_name in series_order) {
      series_data <- campus_data %>%
        dplyr::filter(as.character(series) == series_name)
      if (nrow(series_data) == 0) next
      panel <- plotly::add_trace(
        panel,
        x = series_data$term_label,
        y = series_data$retention_pct,
        type = "scatter",
        mode = "lines+markers",
        name = series_name,
        legendgroup = series_name,
        showlegend = campus_i == 1L,
        line = list(
          color = unname(colors[[series_name]]),
          dash = dashes[[series_name]],
          width = 3
        ),
        marker = list(color = unname(colors[[series_name]]), size = 6),
        text = series_data$hover_text,
        hovertemplate = "%{text}<extra></extra>"
      )
    }

    panel %>%
      plotly::layout(
        annotations = list(list(
          text = paste0("Campus: ", campus_value),
          showarrow = FALSE,
          xref = "paper",
          yref = "paper",
          x = 0.01,
          y = 0.98,
          xanchor = "left",
          yanchor = "top",
          bgcolor = "rgba(255,255,255,0.8)",
          font = list(size = 12, color = unname(CEDAR_COLORS["text"]))
        )),
        xaxis = list(
          title = "",
          tickangle = -45,
          categoryorder = "array",
          categoryarray = term_levels
        ),
        yaxis = list(title = "+1 retention", ticksuffix = "%")
      )
  })

  plotly::subplot(
    panels,
    nrows = length(panels),
    shareX = FALSE,
    shareY = TRUE,
    titleX = TRUE,
    titleY = TRUE,
    margin = 0.08
  ) %>%
    plotly::layout(
      legend = list(
        orientation = "h", x = 0, y = 1.04,
        xanchor = "left", yanchor = "bottom"
      ),
      margin = list(l = 58, r = 25, t = 58, b = 70),
      font = list(color = unname(CEDAR_COLORS["text"])),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "#FFFFFF"
    )
}


# ---- Shiny lazy-tab helpers ------------------------------------------------
#
# create_course_base_data(): fast initial load — skips course-neighbors.
#   Enrollment table and rollcall tables are available immediately because
#   renderers read directly from tables$.
#
# compute_cr_flows_tab(): Course Flows — computes neighbors, plots, and the
#   ranked concurrent-course table.
# compute_cr_outcomes_tab(): Outcomes — calls get_course_outcomes().
#
# Server merges each result's plots/outcomes back into course_report_data().

create_course_base_data <- function(data_objects, opt) {
  cedar_debug("[course_report.R] create_course_base_data: ", opt[["course"]])
  if (is.null(opt[["course"]]) || length(opt[["course"]]) == 0) {
    stop("[course_report.R] create_course_base_data requires opt$course")
  }
  # The report is for the course (ADR-001 step 4), named by its current code:
  # a former code picked from the schedule resolves to it here, once, and every
  # tab below reads opt$course as that course_id. `selected_code` keeps what
  # was picked so the page can say "SOC 371 is now SOCI 371".
  sections <- data_objects[["cedar_sections"]]
  selected_code <- as.character(opt[["course"]])[[1]]
  opt[["course"]] <- course_id_of(sections, selected_code, "create_course_base_data")
  enrollment_payload <- assemble_course_enrollment_payload(
    data_objects[["cedar_registrations"]], sections, opt
  )
  course_data <- get_course_data(
    data_objects, opt, skip_neighbors = TRUE,
    enrollment_payload = enrollment_payload
  )
  list(
    course_code  = opt[["course"]],
    course_name  = opt[["course"]],
    selected_code = selected_code,
    overview     = enrollment_payload$overview,
    plots        = list(),
    tables       = course_data,
    outcomes     = NULL,
    flows_loaded = FALSE,
    opt          = opt,
    generated_at = Sys.time()
  )
}

compute_cr_flows_tab <- function(base, data_objects, min_contrib = 2,
                                 max_courses = 8, concurrent_top_n = 20) {
  opt      <- base$opt
  # The loaded tables are keyed on the course: a feeder or destination
  # renumbered mid-history is one course.
  students <- data_objects[["cedar_registrations"]]
  courses  <- data_objects[["cedar_sections"]]
  myopt    <- opt
  myopt[["term"]] <- NULL
  observation_end <- cedar_longitudinal_edge(
    data_objects[["cedar_edges"]], grade_dependent = FALSE
  )
  if (is.null(observation_end)) {
    stop("[course_report.R] Course flows need a complete longitudinal observation term.")
  }
  # The term-before and term-after courses are read off cedar_course_flows,
  # counted by the transform to the same edge; the same-term courses are
  # counted from the class list bounded at it.
  course_flows <- data_objects[["cedar_course_flows"]]
  if (is.null(course_flows)) {
    stop("[course_report.R] cedar_course_flows dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  require_course_flows(course_flows, "compute_cr_flows_tab")
  flows_edge <- attr(course_flows, "enrolled_edge", exact = TRUE)
  if (!identical(as.integer(flows_edge), as.integer(observation_end))) {
    stop("[course_report.R] cedar_course_flows is bounded at ", flows_edge,
         " but the data edges settle at ", observation_end,
         "; the table and the edges must come from one class list.")
  }
  students <- students %>% dplyr::filter(term <= .env$observation_end)
  courses  <- courses %>% dplyr::filter(term <= .env$observation_end)
  campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL

  if (!is.null(campus_scope) && length(campus_scope) > 0) {
    students <- students %>% dplyr::filter(campus %in% .env$campus_scope)
    courses <- courses %>% dplyr::filter(campus %in% .env$campus_scope)
  }
  cache_scope <- list(
    course_campus = campus_scope, observation_end = observation_end,
    code_renames = course_code_renames(students)
  )

  use_cache <- is.null(opt[["skip_cache"]]) || !opt[["skip_cache"]]
  if (use_cache) {
    cached <- load_course_neighbors_cache(opt[["course"]], students, courses, cache_scope)
    if (!is.null(cached)) {
      message("[course_report.R] Cache hit: course-neighbors (flows tab) for ", opt[["course"]])
      where_from_data <- cached$where_from
      where_to_data   <- cached$where_to
      where_at_data   <- cached$where_at
    } else {
      message("[course_report.R] Cache miss: computing course-neighbors (flows tab) for ", opt[["course"]])
      where_from_data <- get_course_feeders(course_flows, myopt)
      where_to_data   <- get_course_destinations(course_flows, myopt)
      where_at_data   <- get_concurrent_courses(students, myopt)
      message("[course_report.R] Course-neighbors rows (flows tab): destinations=",
              nrow(where_to_data), ", feeders=", nrow(where_from_data),
              ", concurrent=", nrow(where_at_data))
      save_course_neighbors_cache(opt[["course"]],
        list(where_from = where_from_data, where_to = where_to_data, where_at = where_at_data),
        students, courses, cache_scope)
    }
  } else {
    where_from_data <- get_course_feeders(course_flows, myopt)
    where_to_data   <- get_course_destinations(course_flows, myopt)
    where_at_data   <- get_concurrent_courses(students, myopt)
    message("[course_report.R] Course-neighbors rows (flows tab, no cache): destinations=",
            nrow(where_to_data), ", feeders=", nrow(where_from_data),
            ", concurrent=", nrow(where_at_data))
  }

  sankey_opt <- opt
  sankey_opt$min_contrib <- min_contrib
  sankey_opt$max_courses <- max_courses
  raw_plots <- plot_course_sankey_by_term_with_flow_counts(where_to_data, where_from_data, sankey_opt)

  # Rename fall/spring/etc. → sankey_fall_plot/sankey_spring_plot/etc.
  # to match the pattern the renderers expect.
  plots <- list()
  for (term_type in names(raw_plots)) {
    plots[[paste0("sankey_", term_type, "_plot")]] <- raw_plots[[term_type]]
  }

  concurrent_courses <- summarize_concurrent_courses(
    where_at_data,
    top_n = concurrent_top_n
  )
  plots[["concurrent_treemap_plot"]] <- plot_concurrent_course_treemap(
    concurrent_courses,
    opt = list(max_courses = concurrent_top_n)
  )

  list(
    plots = plots,
    tables = list(concurrent_courses = concurrent_courses)
  )
}

compute_cr_outcomes_tab <- function(base, data_objects) {
  outcome_opt <- modifyList(base$opt, list(data_edges = data_objects[["cedar_edges"]]))
  get_course_outcomes(data_objects[["cedar_attempts"]], data_objects[["cedar_faculty"]], outcome_opt)
}


# ── Course Sequence: the result in plain words ───────────────────────────────
#
# The sequence comparison's page renders its outcome and balance tables, but a
# reader asking "did students who took X first do better in Y?" wants the two
# rates first, in one sentence, with the arithmetic beside them and the
# balance verdict right after: the groups are self-selected, and for a
# first-year course they differ on entering credits by construction, so the
# gap describes who took each path before it describes the course. The
# sentences are built here, over the cone's payload, so a test can pin them.

CEDAR_COVARIATE_LABELS <- c(
  unm_credits_entering   = "UNM credits entering",
  total_credits_entering = "total credits entering",
  cum_gpa_entering       = "GPA entering",
  high_school_cum_gpa    = "high-school GPA",
  unm_act_combined_score = "ACT score",
  transfer_gpa           = "transfer GPA",
  current_age            = "age",
  pell_eligible          = "Pell eligibility",
  first_gen              = "first-generation share"
)

#' The Course Sequence result as two or three sentences
#'
#' @param result `get_course_sequence_effect()` output.
#' @return Character vector of sentences: the two groups' DFW rates with their
#'   counts, then the balance verdict (how many measured covariates differ
#'   substantially, and the one that differs most), then, when a GPA band
#'   was active, how many students had no HS GPA and were left out. With an
#'   applicants table, a sentence between them gives the gap inside the same
#'   high-school GPA bands (`result$standardized`).
course_sequence_headline <- function(result) {
  required <- c("course_x", "course_y", "outcomes", "balance", "n_treatment", "n_control")
  missing <- setdiff(required, names(result))
  if (length(missing) > 0) {
    stop("[course-report.R] course_sequence_headline: result lacks ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  outcomes <- result$outcomes
  course_y <- paste(result$course_y, collapse = " or ")
  rate <- function(group) {
    rows <- outcomes[outcomes$group == group, , drop = FALSE]
    total <- sum(rows$n)
    dfw <- sum(rows$n[rows$outcome == "dfw"])
    if (total == 0L) stop("[course-report.R] course_sequence_headline: no classified outcomes for ", group,
                          call. = FALSE)
    list(dfw = dfw, total = total, pct = 100 * dfw / total)
  }
  t <- rate("treatment")
  c <- rate("control")
  fmt_n <- function(n) format(n, big.mark = ",", trim = TRUE)
  fmt_pct <- function(p) sprintf("%.1f%%", p)
  gap <- t$pct - c$pct
  direction <- if (abs(gap) < 0.05) "the same rate" else if (gap > 0) "a higher rate" else "a lower rate"

  rates <- paste0(
    "Students who passed ", result$course_x, " before ", course_y, " did not pass ",
    course_y, " ", fmt_pct(t$pct), " of the time (", fmt_n(t$dfw), " of ", fmt_n(t$total),
    "); students who took ", course_y, " without a prior pass in ", result$course_x, ", ",
    fmt_pct(c$pct), " (", fmt_n(c$dfw), " of ", fmt_n(c$total), "): ", direction,
    if (direction == "the same rate") "." else paste0(", by ", sprintf("%.1f", abs(gap)), " points.")
  )

  smd <- result$balance$smd_table
  measured <- if (is.null(smd)) 0L else sum(!smd$balance_band %in% "unavailable")
  if (measured == 0L) {
    verdict <- "No measured covariate could be compared, so nothing says how alike the two groups were."
  } else {
    flagged <- smd[smd$balance_band %in% "substantial", , drop = FALSE]
    if (nrow(flagged) == 0L) {
      verdict <- paste0(
        "On the ", measured, " measured covariates the groups did not differ substantially; ",
        "the gap is still a description of two self-selected paths, not an effect of ", result$course_x, "."
      )
    } else {
      top <- flagged[which.max(abs(flagged$smd)), , drop = FALSE]
      label <- CEDAR_COVARIATE_LABELS[top$covariate]
      if (is.na(label)) label <- gsub("_", " ", top$covariate)
      value <- function(v) if (top$type == "binary") sprintf("%.1f%%", v) else sprintf("%.2f", v)
      verdict <- paste0(
        "The groups differ substantially on ", nrow(flagged), " of ", measured, " measured covariates, ",
        "most on ", label, " (", value(top$value_treatment), " against ", value(top$value_control),
        "), so the gap describes who took each path before it describes ", result$course_x, "."
      )
    }
  }

  sentences <- c(rates, verdict)
  # The like-with-like reading: the first group against students of the same
  # high-school GPA band who took the other path.
  std <- result$standardized
  if (!is.null(std) && std$n_treatment_covered > 0L) {
    adj <- std$actual_dfw_pct - std$expected_dfw_pct
    sentences <- c(sentences, paste0(
      "Within the same high-school GPA bands, students without the prior pass did not pass ",
      fmt_pct(std$expected_dfw_pct), " of the time against ", fmt_pct(std$actual_dfw_pct),
      " for the ", fmt_n(std$n_treatment_covered), " who passed ", result$course_x, " first: ",
      if (abs(adj) < 0.05) "no gap" else paste0("a gap of ", sprintf("%.1f", abs(adj)), " points"),
      " once the two groups have the same GPA mix",
      if (std$n_treatment_left_out > 0L) paste0(" (", fmt_n(std$n_treatment_left_out),
        " in a band with fewer than ", std$min_band_n, " comparison students are left out)") else "",
      "."
    ))
  }
  if (isTRUE(result$n_missing_act_excluded > 0L)) {
    sentences <- c(sentences, paste0(
      fmt_n(result$n_missing_act_excluded),
      " students with no ACT score were left out because an ACT range was active."
    ))
  }
  if (isTRUE(result$n_missing_hs_gpa_excluded > 0L)) {
    sentences <- c(sentences, paste0(
      fmt_n(result$n_missing_hs_gpa_excluded),
      " students with no high-school GPA were left out because a GPA range was active."
    ))
  }
  sentences
}
