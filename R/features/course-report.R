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


# ---- Course Overview assembly ----------------------------------------------

prepare_course_lifecycle_history <- function(cl_enrls) {
  if (is.null(cl_enrls) || nrow(cl_enrls) == 0) {
    return(tibble::tibble())
  }
  cedar_require_campus(cl_enrls, "prepare_course_lifecycle_history")

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
      current_enrl, census_enrl, early_drops = dr_early,
      late_drops = dr_late, waitlisted = wl_all,
      all_drops = dr_all, classlist_total
    ) %>%
    dplyr::arrange(campus, term)
}


assemble_course_overview <- function(sections, cl_enrls, opt) {
  list(
    lifecycle = prepare_course_lifecycle_history(cl_enrls),
    sections = get_course_section_history(sections, opt)
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
    sections = filter_one(overview$sections, "sections")
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


course_overview_history <- function(overview, campuses = NULL, term_type = NULL) {
  scoped <- filter_course_overview(overview, campuses, term_type)
  lifecycle <- if (!is.null(scoped$lifecycle) && nrow(scoped$lifecycle) > 0) {
    scoped$lifecycle %>%
      dplyr::select(
        campus, term, term_type, subject_course,
        current_enrl, census_enrl, early_drops, late_drops, waitlisted
      ) %>%
      dplyr::distinct()
  } else {
    tibble::tibble(
      campus = character(), term = integer(), term_type = character(),
      subject_course = character(), current_enrl = integer(),
      census_enrl = numeric(), early_drops = integer(), late_drops = integer(),
      waitlisted = integer()
    )
  }

  sections <- if (!is.null(scoped$sections) && nrow(scoped$sections) > 0) {
    scoped$sections %>%
      dplyr::select(
        campus, term, term_type, subject_course,
        sections, total_enrl, avg_section_size
      ) %>%
      dplyr::distinct()
  } else {
    tibble::tibble(
      campus = character(), term = integer(), term_type = character(),
      subject_course = character(), sections = integer(),
      total_enrl = numeric(), avg_section_size = numeric()
    )
  }

  dplyr::full_join(
    lifecycle,
    sections,
    by = c("campus", "term", "term_type", "subject_course")
  ) %>%
    dplyr::arrange(campus, term)
}


course_overview_snapshot <- function(overview, campuses = NULL, term_type = NULL,
                                     comparison_years = 1:3) {
  history <- course_overview_history(overview, campuses, term_type)
  if (nrow(history) == 0) return(tibble::tibble())

  snapshot <- history %>%
    dplyr::group_by(campus, subject_course) %>%
    dplyr::filter(term == max(term, na.rm = TRUE)) %>%
    dplyr::ungroup()
  metrics <- intersect(
    c(
      "census_enrl", "current_enrl", "sections", "avg_section_size",
      "early_drops", "late_drops", "waitlisted"
    ),
    names(history)
  )

  for (years_back in as.integer(comparison_years)) {
    prior_suffix <- paste0("_prior_", years_back, "y")
    prior <- history %>%
      dplyr::mutate(term = term + 100L * years_back) %>%
      dplyr::select(campus, term, subject_course, dplyr::all_of(metrics)) %>%
      dplyr::rename_with(~ paste0(.x, prior_suffix), dplyr::all_of(metrics))

    snapshot <- snapshot %>%
      dplyr::left_join(prior, by = c("campus", "term", "subject_course"))

    for (metric in metrics) {
      prior_col <- paste0(metric, prior_suffix)
      change_col <- paste0(metric, "_change_", years_back, "y")
      current <- snapshot[[metric]]
      previous <- snapshot[[prior_col]]
      snapshot[[change_col]] <- dplyr::case_when(
        is.na(current) | is.na(previous) ~ NA_real_,
        previous == 0 & current == 0 ~ 0,
        previous == 0 ~ NA_real_,
        TRUE ~ round(100 * (current - previous) / previous, 1)
      )
      snapshot[[prior_col]] <- NULL
    }
  }

  snapshot %>% dplyr::arrange(campus)
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


build_course_enrollment_history_plot <- function(lifecycle, term_type = NULL,
                                                  campuses = NULL) {
  if (is.null(lifecycle) || nrow(lifecycle) == 0) return(NULL)
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
  plot <- plotly::plot_ly()

  for (campus_code in unique(data$campus)) {
    campus_data <- data[data$campus == campus_code, , drop = FALSE]
    hover <- paste0(
      "Campus: ", campus_data$campus,
      "<br>Current enrollment: ", campus_data$current_enrl,
      "<br>Census enrollment: ", campus_data$census_enrl,
      "<br>Late drops: ", campus_data$late_drops,
      "<br>Early drops: ", campus_data$early_drops,
      "<br>Waitlisted: ", campus_data$waitlisted
    )
    color <- unname(campus_colors[[campus_code]])

    plot <- plot %>%
      plotly::add_trace(
        data = campus_data,
        x = ~term_label,
        y = ~census_enrl,
        type = "scatter",
        mode = "lines+markers",
        name = paste(campus_code, "Census enrollment"),
        legendgroup = campus_code,
        line = list(color = color, width = 3),
        marker = list(color = color, size = 7),
        customdata = hover,
        hovertemplate = "Term: %{x}<br>Census enrollment: %{y}<br>%{customdata}<extra></extra>"
      ) %>%
      plotly::add_trace(
        data = campus_data,
        x = ~term_label,
        y = ~current_enrl,
        type = "scatter",
        mode = "lines+markers",
        name = paste(campus_code, "Current enrollment"),
        legendgroup = campus_code,
        line = list(color = color, width = 3, dash = "dash"),
        marker = list(color = color, size = 7),
        customdata = hover,
        hovertemplate = "Term: %{x}<br>Current enrollment: %{y}<br>%{customdata}<extra></extra>"
      )
  }

  plot %>%
    plotly::layout(
      xaxis = list(title = "", tickangle = -45),
      yaxis = list(title = "Students"),
      legend = list(
        title = list(text = "Campus / measure"),
        orientation = "h", x = 0, y = 1.12,
        xanchor = "left", yanchor = "bottom"
      ),
      margin = list(t = 52, b = 70),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(0,0,0,0)"
    )
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
    overview     = assemble_course_overview(
      data_objects[["cedar_sections"]], course_data[["cl_enrls"]], opt
    ),
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
