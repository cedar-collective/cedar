# Dept Trends support for the active Shiny department profile.
#
# These functions assemble department metadata, build the fast headcount base,
# and compute lazy tab payloads. Heavy analysis stays in branches/cones.

set_payload <- function(dept_code, prog_focus = NULL) {
  message("[dept-trends.R] Welcome to set_payload!")
  message("[dept-trends.R] Received dept_code: ", dept_code)

  clean_codes <- function(x) {
    x <- as.character(x)
    unique(x[!is.na(x) & nzchar(x)])
  }

  message("[dept-trends.R] Setting program codes and names from mappings.R...")
  if (!is.null(prog_focus)) {
    prog_codes <- clean_codes(prog_focus)
  } else {
    prog_codes <- clean_codes(names(major_to_dept)[
      !is.na(major_to_dept) & major_to_dept == dept_code
    ])
    message("[dept-trends.R] prog_codes: ", paste(prog_codes, collapse = ", "))
  }

  cfg <- list(
    dept_code  = dept_code,
    dept_name  = dept_code_to_name[dept_code],
    subj_codes = clean_codes(names(subj_to_dept[
      !is.na(subj_to_dept) & subj_to_dept == dept_code
    ])),
    prog_focus = prog_focus,
    prog_codes = prog_codes,
    current_term = if (exists("cedar_current_term")) cedar_current_term else cedar_report_end_term,
    term_start = cedar_report_start_term,
    term_end   = cedar_report_end_term,
    palette    = cedar_report_palette
  )

  message("[dept-trends.R] returning cfg set as:\n",
          paste(capture.output(str(cfg, max.level = 1)), collapse = "\n"))

  cfg
}

filter_data_objects <- function(data_objects, campus_filter) {
  if (!is.null(campus_filter) && length(campus_filter) > 0) {
    data_objects[["cedar_students"]] <- data_objects[["cedar_students"]] %>%
      dplyr::filter(campus %in% campus_filter)
    data_objects[["cedar_sections"]] <- data_objects[["cedar_sections"]] %>%
      dplyr::filter(campus %in% campus_filter)
  }
  data_objects
}

rebuild_dept_hc_plots <- function(cached) {
  plots  <- list()
  tables <- cached$tables
  plot_names <- c(
    "hc_progs_under_long_majors",
    "hc_progs_under_long_minors",
    "hc_progs_grad_long_majors",
    "hc_progs_grad_long_minors"
  )

  for (data_name in plot_names) {
    data <- tables[[data_name]]
    if (!is.null(data) && nrow(data) > 0) {
      data$term <- term_axis_factor(data$term)
      plots[[paste0(data_name, "_plot")]] <- plotly::plot_ly(
        data,
        x = ~term,
        y = ~student_count,
        color = ~program_type,
        type = "bar",
        hovertemplate = "%{x}<br>Students: %{y}<extra>%{fullData.name}</extra>"
      ) %>%
        plotly::layout(
          barmode = "stack",
          xaxis = list(tickangle = -45),
          legend = list(orientation = "h", x = 0, y = -0.2)
        )
    }
  }

  plots
}

create_dept_report_base <- function(data_objects, opt) {
  required_datasets <- c(
    "cedar_students", "cedar_degrees", "cedar_sections",
    "cedar_faculty", "cedar_programs"
  )
  missing_datasets <- setdiff(required_datasets, names(data_objects))
  if (length(missing_datasets) > 0) {
    stop("[dept-trends.R] Missing required CEDAR datasets: ",
         paste(missing_datasets, collapse = ", "))
  }

  incoming_dept <- opt[["dept"]]
  dept_code <- if (incoming_dept %in% names(hr_org_desc_to_dept)) {
    hr_org_desc_to_dept[[incoming_dept]]
  } else {
    incoming_dept
  }

  cfg <- set_payload(dept_code, opt[["prog"]])
  if (!is.null(opt[["current_term"]]) && length(opt[["current_term"]]) > 0) {
    cfg$current_term <- as.integer(opt[["current_term"]][[1]])
  }
  cfg$dept_raw <- incoming_dept

  data_objects <- filter_data_objects(data_objects, opt[["campus"]])

  hc <- get_headcount_data_for_dept_report(
    data_objects[["cedar_programs"]],
    cfg$dept_code,
    cfg$term_start,
    cfg$term_end,
    lookups = data_objects[["cedar_lookups"]]
  )

  c(cfg, list(
    plots = hc$plots,
    tables = hc$tables,
    data_objects_filt = data_objects
  ))
}

compute_dept_enrl_tab <- function(base) {
  enrl <- get_enrl_for_dept_report(
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$palette,
    base$term_start,
    base$term_end
  )

  enrl$plots["enrl_credit_hours_by_level_plot"] <- list(
    plot_credit_hours_by_level(
      base$data_objects_filt[["cedar_students"]],
      base$dept_code,
      n_years = 5
    )
  )

  signals <- get_dept_enrollment_trend_signals(
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    term_start = base$term_start,
    term_end = base$term_end,
    current_term = base$current_term
  )
  enrl$tables <- c(enrl$tables, signals$tables)
  enrl$drop_stats <- get_dept_drop_stats(
    base$data_objects_filt[["cedar_students"]],
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$current_term
  )
  enrl$plots$cross_dept_minors <- plot_cross_dept_minors(
    base$data_objects_filt[["cedar_programs"]],
    base$dept_code,
    term = base$current_term
  )
  enrl$plots$majors_with_minor <- plot_majors_with_dept_minor(
    base$data_objects_filt[["cedar_programs"]],
    base$dept_code,
    term = base$current_term
  )
  enrl$plots$student_donuts <- plot_dept_student_donuts(
    base$data_objects_filt[["cedar_students"]],
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$current_term
  )

  enrl
}

compute_dept_degrees_tab <- function(base) {
  get_degrees_for_dept_report(
    base$data_objects_filt[["cedar_degrees"]],
    base$dept_name,
    base$prog_codes,
    base$term_start,
    base$term_end,
    base$palette
  )
}

compute_dept_credit_hours_tab <- function(base) {
  do_filt <- base$data_objects_filt
  filtered_cl <- do_filt[["cedar_students"]] %>%
    dplyr::filter(department == base$dept_code)

  sch_college <- get_credit_hours_for_dept_trends(
    do_filt[["cedar_students"]],
    base$dept_code,
    base$subj_codes,
    base$term_start,
    base$term_end,
    base$palette
  )
  sch_major <- credit_hours_by_major(
    filtered_cl,
    base$dept_code,
    base$term_start,
    base$term_end
  )
  sch_fac <- credit_hours_by_fac(
    do_filt,
    base$dept_code,
    base$subj_codes,
    base$term_start,
    base$term_end,
    base$palette
  )

  list(
    plots = c(sch_college$plots, sch_major$plots, sch_fac$plots),
    tables = c(sch_college$tables, sch_major$tables, sch_fac$tables)
  )
}
