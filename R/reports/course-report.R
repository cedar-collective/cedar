# course_report produces a basic report for a particular course.
# This calls and gathers various other reporting functions, such as enrl, forecast, rollout, course-neighbors, gradebook,
# Designed to be run from the command line via cedar.R -f course-report -d DEPTCODE
# Reports are saved in CEDAR_OUTPUT_DIR/course-reports (in either.
# REQUIRES: opt$course and opt$term
# OPTIONAL: output-format: html (default) or aspx

# TODO: create loops to manage and accept course and term lists for batch processing
# some already in cedar.R; need to separate processing from actual report call as with forecast, regstats, etc

get_course_data <- function(data_objects, opt, skip_neighbors = FALSE) {
  # for studio testing...
  # students <- load_students()
  # courses <- load_courses()
  # opt <- list()
  # opt[["course"]] <- "MATH 1350"
  # opt[["term"]] <- 202580
  # opt[["skip_forecast"]] <- TRUE

  # Extract CEDAR data objects (no legacy fallbacks)
  students <- data_objects[["cedar_students"]]
  courses <- data_objects[["cedar_sections"]]
  forecasts <- data_objects[["forecasts"]]
  hr_data <- data_objects[["cedar_faculty"]]

  # Bail out early with a clear error if required datasets are missing
  if (is.null(courses)) {
    stop("[course_report.R] cedar_sections dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(students)) {
    stop("[course_report.R] cedar_students dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }
  if (is.null(hr_data)) {
    stop("[course_report.R] cedar_faculty dataset is NULL in data_objects\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  cedar_debug("[course_report.R] Students: ", nrow(students), " rows / Courses: ", nrow(courses), " rows")

  # init payload list for return value
  course_data <- list()

  # Set term range for filtering (parallel to dept-report.R)
  course_data[["term_start"]] <- cedar_report_start_term
  course_data[["term_end"]] <- cedar_report_end_term

  # these should always be set this way
  opt$status <- "A"
  opt$uel <- TRUE

  courses_filtered <- courses %>% filter(subject_course == opt[["course"]])

  # keep students as is for course-neighbors analysis
  filtered_students <- students %>% filter_class_list(opt)

  if (is.null(filtered_students) || nrow(filtered_students) == 0) {
    message("[course_report.R] WARNING: No students found after filtering for course ", opt[["course"]])
  }

  # create term agnostic opt param for getting historic enrollments from DESRs
  myopt <- opt
  myopt[["term"]] <- NULL
  myopt[["group_cols"]] <- c("campus","college","term", "term_type", "subject", "subject_course", "course_title")

  # Cheap term-type lookup on pre-filtered sections.
  # Replaces a full get_enrl() aggregate that was used only to check row counts.
  term_types_offered <- courses_filtered %>%
    filter(status == "A") %>%
    distinct(term_type) %>%
    pull(term_type)

  # get registration stats
  cedar_debug("[course_report.R] Calling calc_cl_enrls...")
  course_data[["cl_enrls"]] <- calc_cl_enrls(filtered_students)


  ####################
  # check if skipping new forecasts for shiny speed
  if (is.null(opt[["skip_forecast"]]) || opt[["skip_forecast"]] == FALSE) {

    forecast_data <- forecasts

    if (!is.null(forecast_data) && nrow(forecast_data) > 0) {
      forecast_data <- forecast_data %>% filter(subject_course == myopt[["course"]])
      forecast_data <- add_term_type_col(forecast_data, "term")
    } else {
      cedar_debug("[course_report.R] No forecasting file found. Creating empty table...")
      forecast_data <- data.frame()
    }

    if ("fall" %in% term_types_offered && nrow(forecast_data[forecast_data$term_type=="fall",]) < 6) {
      cedar_debug("[course_report.R] Need more fall forecasts — retroactively forecasting.")
      myopt$term <- "tl_falls"
      forecast(students, courses, myopt)
    }

    if ("spring" %in% term_types_offered && nrow(forecast_data[forecast_data$term_type=="spring",]) < 6) {
      cedar_debug("[course_report.R] Need more spring forecasts — retroactively forecasting.")
      myopt$term <- "tl_springs"
      forecast(students, courses, myopt)
    }

    if ("summer" %in% term_types_offered && nrow(forecast_data[forecast_data$term_type=="summer",]) < 6) {
      cedar_debug("[course_report.R] Need more summer forecasts — retroactively forecasting.")
      myopt$term <- "tl_summers"
      forecast(students, courses, myopt)
    }
  } else {
    cedar_debug("[course_report.R] Skipping forecasting (opt$skip_forecast=TRUE).")
  }

  # reset term after forecasting
  myopt$term <- NULL

  # get forecast stats (w enrollments and accuracy) - skip if skip_forecast is TRUE
  if (is.null(opt[["skip_forecast"]]) || opt[["skip_forecast"]] == FALSE) {
    forecasts <- calc_forecast_accuracy(students, courses, myopt)

    if (!is.null(forecasts)) {
      forecast_short <- forecasts[["forecast_short"]]

      if (!is.null(forecast_short) && nrow(forecast_short) > 0) {
        course_data[["forecasts"]] <- forecast_short %>%
          select(-c(dr_early_mean,dr_late_mean,use_enrl_vals,use_cl_vals)) %>%
          filter(subject_course %in% opt[["course"]])
      } else {
        course_data[["forecasts"]] <- forecast_short
      }
    }
  } else {
    cedar_debug("[course_report.R] Skipping forecast accuracy (opt$skip_forecast=TRUE).")
    course_data[["forecasts"]] <- NULL
  }


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

  tryCatch({
    demo_by_class_table <- demo_by_class_for_plot %>%
      pivot_wider(names_from = term, values_from = term_pct, values_fill = 0)
  }, error = function(e) {
    message("[course_report.R] Error in pivot_wider for demo_by_class: ", e$message)
    demo_by_class_table <- demo_by_class_for_plot
  })

  course_data[["rollcall_by_class"]] <- demo_by_class_table
  course_data[["rollcall_by_class_plot_data"]] <- demo_by_class_for_plot


  # demographics by major
  myopt[["group_cols"]] <- c("campus", "college", "term", "term_type", "major_code", "subject_course", "level")
  demo_by_major_raw <- get_course_demographics(filtered_students, myopt)
  cedar_debug("[course_report.R] demo_by_major: ", nrow(demo_by_major_raw), " rows")

  demo_by_major_for_plot <- demo_by_major_raw

  tryCatch({
    demo_by_major_table <- demo_by_major_for_plot %>%
      pivot_wider(names_from = term, values_from = term_pct, values_fill = 0)
  }, error = function(e) {
    message("[course_report.R] Error in pivot_wider for demo_by_major: ", e$message)
    demo_by_major_table <- demo_by_major_for_plot
  })

  course_data[["rollcall_by_major"]] <- demo_by_major_table
  course_data[["rollcall_by_major_plot_data"]] <- demo_by_major_for_plot


  #####################
  # Get GRADE DATA; opt term should be null to get all data
  grade_data <- get_grades(filtered_students, myopt)
  course_data[["grade_data"]] <- add_instructor_type(grade_data, hr_data)

  return(course_data)
}


use_NSO_data_for_forecasts <- function() {
  ###############
  # UNFINISHED: use nosedive to find out freshman contribution to course we're reporting on
  ###############
  cedar_debug("looking for NSO flag and if target term type is fall...")
  if (opt$nso && get_term_type(opt[["term"]]) == "fall") {

    # load NSO data
    NSOers <- load_NSO_data()

    # calculate NSO Freshman contribution to course
    # use opt, which should have target term specified
    # forecast_enrl_from_majors uses rollcall, so make sure necessary params are set
    # TODO: needs to fit new rollcall code
    myopt[["group_col"]] <- c("campus", "college", "term", "student_classification", "major_code", "subject_course")
    prog_NSO_enrl <- forecast_enrl_from_majors(NSOers,students,opt)
    cedar_debug("results from forecast_enrl_from_majors:")
    print(prog_NSO_enrl)

    # get just course for report
    prog_NSO_enrl <- prog_NSO_enrl %>%
      filter(subject_course == opt$course)

    cedar_debug("merging nso_enrl_projections from nosedive with forecast data...")
    forecast_next_term <- merge(forecast_next_term, prog_NSO_enrl[ , c("subject_course","fresh_proj")], by = "subject_course")
    forecast_next_term %>% tibble::as_tibble() %>% print(n = nrow(.), width=Inf)

    filtered_students <- students %>% filter_class_list(opt)

    cedar_debug("getting number of NSOers registered in courses...")
    NSOers_in_course <- get_NSOers_in_courses(NSOers, filtered_students, opt)

    forecast_next_term <- merge(forecast_next_term, NSOers_in_course[ , c("subject_course","count")], by = "subject_course")
    forecast_next_term %>% tibble::as_tibble() %>% print(n = nrow(.), width=Inf)
  } else {
    cedar_debug("ignoring nso data.")
  }
}


# ---- Shiny lazy-tab helpers ------------------------------------------------
#
# create_course_base_data(): fast initial load — skips course-neighbors and
#   all plot generation. Enrollment table and rollcall tables are available
#   immediately because renderers read directly from tables$.
#
# compute_cr_flows_tab(): Course Flows — computes neighbors + Sankey plots.
# compute_cr_dfw_tab():   DFW — generates DFW plots from grade_data.
# compute_cr_outcomes_tab(): Outcomes — calls get_course_outcomes().
#
# Server merges each result's plots/outcomes back into course_report_data()
# so existing renderers need no changes.

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

compute_cr_dfw_tab <- function(base) {
  plot_grades_for_course_report(base$tables[["grade_data"]], base$opt)
}

compute_cr_outcomes_tab <- function(base, data_objects) {
  get_course_outcomes(data_objects[["cedar_students"]], data_objects[["cedar_faculty"]], base$opt)
}

# ---------------------------------------------------------------------------

# Interactive course report data generation (for Shiny)
create_course_report_data <- function(data_objects, opt) {
  cedar_debug("[course_report.R] create_course_report_data: ", opt[["course"]])

  if (is.null(data_objects) || length(data_objects) == 0) {
    message("[course_report.R] WARNING: data_objects is NULL or empty!")
  }

  students <- data_objects[["cedar_students"]]
  courses  <- data_objects[["cedar_sections"]]

  course_data <- get_course_data(data_objects, opt)
  cedar_debug("[course_report.R] course_data elements: ", paste(names(course_data), collapse = ", "))

  plots <- list()

  ####################
  # ENROLLMENT PLOT
  if (!is.null(course_data$cl_enrls) && nrow(course_data$cl_enrls) > 0) {
    tryCatch({
      enrl_plot <- make_enrl_plot_from_cls(course_data$cl_enrls, opt)
      if (!is.null(enrl_plot) && "cl_enrl" %in% names(enrl_plot)) {
        plots$enrollment_plot <- enrl_plot$cl_enrl
      } else {
        cedar_debug("[course_report.R] Enrollment plot returned NULL or missing cl_enrl")
      }
    }, error = function(e) {
      message("[course_report.R] Error creating enrollment plot: ", e$message)
    })
  }


  ######################
  # SANKEY FLOW DIAGRAMS
  tryCatch({
    if (!is.null(course_data$where_to) && !is.null(course_data$where_from)) {
      sankey_opt <- opt
      sankey_opt$min_contrib <- 2
      sankey_opt$max_courses <- 8

      cedar_debug("[course_report.R] where_to: ", nrow(course_data$where_to),
                  " rows / where_from: ", nrow(course_data$where_from), " rows")

      sankey_plots <- plot_course_sankey_by_term_with_flow_counts(
        course_data$where_to,
        course_data$where_from,
        sankey_opt
      )

      if (length(sankey_plots) > 0) {
        for (term_type in names(sankey_plots)) {
          plots[[paste0("sankey_", term_type, "_plot")]] <- sankey_plots[[term_type]]
        }
        cedar_debug("[course_report.R] Sankey plots added: ", paste(names(sankey_plots), collapse = ", "))
      } else {
        cedar_debug("[course_report.R] No sankey plots — flow likely self-referential or insufficient cross-course patterns")
      }
    } else {
      cedar_debug("[course_report.R] No course-neighbors data for sankey plots")
    }
  }, error = function(e) {
    message("[course_report.R] Error creating sankey plots: ", e$message)
  })


  # Demographics plots with consistent colors across term types
  class_plots <- plot_demographics_with_consistent_colors(
    course_data[["rollcall_by_class_plot_data"]],
    fill_column = "student_classification",
    top_n = 6
  )
  plots$rollcall_by_class_plot <- class_plots

  major_plots <- plot_demographics_with_consistent_colors(
    course_data[["rollcall_by_major_plot_data"]],
    fill_column = "major_code",
    top_n = 6
  )
  plots$rollcall_by_major_plot <- major_plots

  plots$rollcall_by_class_time_plot <- plot_time_series(course_data[["rollcall_by_class_plot_data"]], fill_column = "student_classification")
  plots$rollcall_by_major_time_plot <- plot_time_series(course_data[["rollcall_by_major_plot_data"]], fill_column = "major_code")


  ##################
  # GRADE PLOTS
  plots_from_gradebook <- plot_grades_for_course_report(course_data[["grade_data"]], opt)
  cedar_debug("[course_report.R] Grade plots: ", length(plots_from_gradebook))
  plots[["dfw_summary_plot"]]    <- plots_from_gradebook[["dfw_summary_plot"]]
  plots[["dfw_by_term_plot"]]    <- plots_from_gradebook[["dfw_by_term_plot"]]
  plots[["dfw_by_inst_type_plot"]] <- plots_from_gradebook[["dfw_by_inst_type_plot"]]


  ##################
  # COURSE OUTCOMES
  outcomes_data <- tryCatch(
    get_course_outcomes(students, data_objects[["cedar_faculty"]], opt),
    error = function(e) {
      message("[course_report.R] Error computing course outcomes: ", e$message)
      list(persistence = tibble(), dfw_trend = tibble(), instructor_dfw = tibble(),
           courses = opt[["course"]])
    }
  )
  cedar_debug("[course_report.R] Course outcomes: ", nrow(outcomes_data$persistence), " persistence rows")

  result <- list(
    course_code  = opt[["course"]],
    course_name  = opt[["course"]],
    plots        = plots,
    tables       = course_data,
    outcomes     = outcomes_data,
    opt          = opt,
    generated_at = Sys.time()
  )

  cedar_debug("[course_report.R] Done. ", length(plots), " plots: ", paste(names(plots), collapse = ", "))
  return(result)
}



# Original RMarkdown report function (unchanged)
create_course_report <- function(data_objects, opt) {
  course_data <- get_course_data(data_objects, opt)

  d_params <- list("opt" = opt, "course_data" = course_data)

  d_params$output_filename  <- sub(" ", "_", opt[["course"]])
  d_params$rmd_file         <- file.path(cedar_base_dir, "Rmd", "course-report.Rmd")
  d_params$output_dir_base  <- file.path(cedar_output_dir, "course-reports")

  create_report(opt, d_params)
}
