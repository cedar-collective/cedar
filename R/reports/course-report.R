# course-report assembles the data behind the app's Course Dynamics tab.
# create_course_base_data() gathers enrollment and rollcall data; the per-sub-tab
# helpers compute flows and outcomes lazily when a sub-tab is opened.
# REQUIRES: opt$course (and typically opt$course_campus)
# TODO: separate remaining processing from report assembly as with the lazy tab helpers.

get_course_data <- function(data_objects, opt, skip_neighbors = FALSE) {
  # for studio testing...
  # students <- load_students()
  # courses <- load_courses()
  # opt <- list()
  # opt[["course"]] <- "MATH 1350"
  # opt[["term"]] <- 202580

  # Extract CEDAR data objects (no legacy fallbacks)
  students <- data_objects[["cedar_students"]]
  courses <- data_objects[["cedar_sections"]]

  # Bail out early with a clear error if required datasets are missing
  if (is.null(courses)) {
    stop("[course_report.R] cedar_sections dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(students)) {
    stop("[course_report.R] cedar_students dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  cedar_debug("[course_report.R] Students: ", nrow(students), " rows / Courses: ", nrow(courses), " rows")

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

  # get registration stats
  cedar_debug("[course_report.R] Calling calc_cl_enrls...")
  course_data[["cl_enrls"]] <- calc_cl_enrls(filtered_students)

  ####################
  # run LOOKOUT functions to see where students are coming and going from
  # Use caching to avoid expensive recomputation.
  # Skipped when skip_neighbors = TRUE (Shiny lazy-loads this on Course Flows tab click).
  if (!skip_neighbors) {
    use_cache <- is.null(opt[["skip_cache"]]) || !opt[["skip_cache"]]
    campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL
    cache_scope <- list(course_campus = campus_scope)
    neighbor_students <- students
    neighbor_courses <- courses

    if (!is.null(campus_scope) && length(campus_scope) > 0) {
      neighbor_students <- neighbor_students %>% dplyr::filter(campus %in% .env$campus_scope)
      neighbor_courses <- neighbor_courses %>% dplyr::filter(campus %in% .env$campus_scope)
    }

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
        course_data[["where_from"]] <- get_course_feeders(neighbor_students, myopt)
        course_data[["where_to"]] <- get_course_destinations(neighbor_students, myopt)
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
      course_data[["where_from"]] <- get_course_feeders(neighbor_students, myopt)
      course_data[["where_to"]] <- get_course_destinations(neighbor_students, myopt)
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
  demo_by_class_raw <- get_course_demographics(filtered_students, myopt)
  cedar_debug("[course_report.R] demo_by_class: ", nrow(demo_by_class_raw), " rows")

  demo_by_class_for_plot <- demo_by_class_raw

  demo_by_class_table <- demo_by_class_for_plot %>%
    pivot_wider(names_from = term, values_from = term_pct, values_fill = 0)

  course_data[["rollcall_by_class"]] <- demo_by_class_table
  course_data[["rollcall_by_class_plot_data"]] <- demo_by_class_for_plot


  # demographics by major
  myopt[["group_cols"]] <- c("campus", "college", "term", "term_type", "major_code", "subject_course", "level")
  demo_by_major_raw <- get_course_demographics(filtered_students, myopt)
  cedar_debug("[course_report.R] demo_by_major: ", nrow(demo_by_major_raw), " rows")

  demo_by_major_for_plot <- demo_by_major_raw

  demo_by_major_table <- demo_by_major_for_plot %>%
    pivot_wider(names_from = term, values_from = term_pct, values_fill = 0)

  course_data[["rollcall_by_major"]] <- demo_by_major_table
  course_data[["rollcall_by_major_plot_data"]] <- demo_by_major_for_plot

  return(course_data)
}


# ---- Shiny lazy-tab helpers ------------------------------------------------
#
# create_course_base_data(): fast initial load — skips course-neighbors.
#   Enrollment table and rollcall tables are available immediately because
#   renderers read directly from tables$.
#
# compute_cr_flows_tab(): Course Flows — computes neighbors + Sankey plots.
# compute_cr_outcomes_tab(): Outcomes — calls get_course_outcomes().
#
# Server merges each result's plots/outcomes back into course_report_data().

create_course_base_data <- function(data_objects, opt) {
  cedar_debug("[course_report.R] create_course_base_data: ", opt[["course"]])
  course_data <- get_course_data(data_objects, opt, skip_neighbors = TRUE)
  list(
    course_code  = opt[["course"]],
    course_name  = opt[["course"]],
    plots        = list(),
    tables       = course_data,
    outcomes     = NULL,
    opt          = opt,
    generated_at = Sys.time()
  )
}

compute_cr_flows_tab <- function(base, data_objects, min_contrib = 2, max_courses = 8) {
  opt      <- base$opt
  students <- data_objects[["cedar_students"]]
  courses  <- data_objects[["cedar_sections"]]
  myopt    <- opt
  myopt[["term"]] <- NULL
  campus_scope <- opt[["course_campus"]] %||% opt[["campus"]] %||% NULL
  cache_scope <- list(course_campus = campus_scope)

  if (!is.null(campus_scope) && length(campus_scope) > 0) {
    students <- students %>% dplyr::filter(campus %in% .env$campus_scope)
    courses <- courses %>% dplyr::filter(campus %in% .env$campus_scope)
  }

  use_cache <- is.null(opt[["skip_cache"]]) || !opt[["skip_cache"]]
  if (use_cache) {
    cached <- load_course_neighbors_cache(opt[["course"]], students, courses, cache_scope)
    if (!is.null(cached)) {
      message("[course_report.R] Cache hit: course-neighbors (flows tab) for ", opt[["course"]])
      where_from_data <- cached$where_from
      where_to_data   <- cached$where_to
    } else {
      message("[course_report.R] Cache miss: computing course-neighbors (flows tab) for ", opt[["course"]])
      where_from_data <- get_course_feeders(students, myopt)
      where_to_data   <- get_course_destinations(students, myopt)
      where_at_data   <- get_concurrent_courses(students, myopt)
      message("[course_report.R] Course-neighbors rows (flows tab): destinations=",
              nrow(where_to_data), ", feeders=", nrow(where_from_data),
              ", concurrent=", nrow(where_at_data))
      save_course_neighbors_cache(opt[["course"]],
        list(where_from = where_from_data, where_to = where_to_data, where_at = where_at_data),
        students, courses, cache_scope)
    }
  } else {
    where_from_data <- get_course_feeders(students, myopt)
    where_to_data   <- get_course_destinations(students, myopt)
    message("[course_report.R] Course-neighbors rows (flows tab, no cache): destinations=",
            nrow(where_to_data), ", feeders=", nrow(where_from_data))
  }

  sankey_opt <- opt
  sankey_opt$min_contrib <- min_contrib
  sankey_opt$max_courses <- max_courses
  raw_plots <- plot_course_sankey_by_term_with_flow_counts(where_to_data, where_from_data, sankey_opt)

  # Rename fall/spring/etc. → sankey_fall_plot/sankey_spring_plot/etc.
  # to match the pattern the renderers expect.
  named <- list()
  for (term_type in names(raw_plots)) {
    named[[paste0("sankey_", term_type, "_plot")]] <- raw_plots[[term_type]]
  }
  named
}

compute_cr_outcomes_tab <- function(base, data_objects) {
  get_course_outcomes(data_objects[["cedar_students"]], data_objects[["cedar_faculty"]], base$opt)
}
