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
        colors = cedar_plotly_palette(data$program_type, label_order = CEDAR_PROGRAM_TYPE_ORDER),
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

  incoming_dept <- opt[["dept_code"]]
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

build_dept_enrollment_history <- function(sections, dept_code, palette,
                                          term_start, term_end) {
  opt <- list(
    dept_code = dept_code,
    term = paste0(term_start, "-", term_end),
    status = "A",
    crosslist = "home",
    uel = TRUE,
    x = "compress",
    group_cols = c("term", "level")
  )

  history <- filter_out_summer(sections, "term") %>%
    get_enrl(opt) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      term_code = as.integer(as.character(term)),
      level = dplyr::coalesce(level, "Unknown")
    ) %>%
    add_avg_section_size() %>%
    dplyr::arrange(term_code, level)

  if (nrow(history) == 0) {
    return(list(plots = list(), tables = list(enrl_history_by_level = history)))
  }

  plot_history <- history %>%
    dplyr::mutate(term = term_axis_factor(term_code))

  make_line <- function(y_col, y_label, hover_label) {
    plotly::plot_ly(
      plot_history,
      x = ~term,
      y = stats::as.formula(paste0("~", y_col)),
      color = ~level,
      colors = cedar_plotly_palette(plot_history$level, palette, label_order = CEDAR_LEVEL_ORDER),
      type = "scatter",
      mode = "lines+markers",
      hovertemplate = paste0(
        "%{x}<br>Level: %{fullData.name}<br>",
        hover_label, ": %{y}<extra></extra>"
      )
    ) %>%
      plotly::layout(
        xaxis = list(title = "", tickangle = -45),
        yaxis = list(title = y_label),
        legend = list(orientation = "h", x = 0, y = -0.2)
      )
  }

  list(
    plots = list(
      enrl_term_enrollment_plot = make_line(
        "total_enrl", "Total course enrollment", "Enrollment"
      ),
      enrl_term_sections_plot = make_line(
        "sections", "Active sections", "Sections"
      ),
      enrl_term_avg_size_plot = make_line(
        "avg_section_size", "Average enrollment per section", "Avg size"
      )
    ),
    tables = list(enrl_history_by_level = history)
  )
}

build_dept_gen_ed_college_context <- function(sections, dept_code,
                                              term_start, term_end) {
  dept_college <- sections %>%
    dplyr::filter(
      department == dept_code,
      !is.na(college),
      nzchar(college)
    ) %>%
    dplyr::count(college, sort = TRUE) %>%
    dplyr::slice_head(n = 1) %>%
    dplyr::pull(college)

  if (length(dept_college) == 0 || is.na(dept_college) || !nzchar(dept_college)) {
    return(list(plot = NULL, table = tibble::tibble()))
  }

  gen_ed_sections <- sections %>%
    filter_out_summer("term") %>%
    keep_home_sections_compat() %>%
    dplyr::filter(
      term >= term_start,
      term <= term_end,
      status == "A",
      campus %in% c("ABQ", "EA"),
      !is.na(gen_ed_area)
    ) %>%
    dplyr::mutate(.enrl = dplyr::coalesce(section_metric(., "total_enrl", "enrolled"), 0))

  dept_totals <- gen_ed_sections %>%
    dplyr::filter(department == dept_code) %>%
    dplyr::group_by(term) %>%
    dplyr::summarize(dept_total = sum(.enrl, na.rm = TRUE), .groups = "drop")

  college_totals <- gen_ed_sections %>%
    dplyr::filter(college == dept_college) %>%
    dplyr::group_by(term) %>%
    dplyr::summarize(college_total = sum(.enrl, na.rm = TRUE), .groups = "drop")

  merged <- merge(dept_totals, college_totals, by = "term", all = TRUE) %>%
    dplyr::arrange(term)
  if (nrow(merged) == 0) {
    return(list(plot = NULL, table = tibble::tibble()))
  }
  merged[is.na(merged)] <- 0

  first_dept <- if (merged$dept_total[1] == 0) 1 else merged$dept_total[1]
  first_college <- if (merged$college_total[1] == 0) 1 else merged$college_total[1]

  indexed <- merged %>%
    dplyr::mutate(
      dept_indexed = dept_total / first_dept * 100,
      college_indexed = college_total / first_college * 100
    ) %>%
    tidyr::pivot_longer(
      cols = c(dept_indexed, college_indexed),
      names_to = "series",
      values_to = "indexed_value"
    ) %>%
    dplyr::mutate(series = dplyr::if_else(
      series == "dept_indexed",
      paste0(dept_code, " Department"),
      paste0(dept_college, " College")
    ))

  list(
    plot = plot_indexed_growth(
      indexed,
      dept_code,
      title_prefix = "Gen Ed Enrollment Growth",
      metric_label = "Gen Ed Enrollment"
    ),
    table = indexed
  )
}

compute_dept_enrl_tab <- function(base) {
  enrl <- get_enrl_for_dept_report(
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$palette,
    base$term_start,
    base$term_end
  )

  history <- build_dept_enrollment_history(
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$palette,
    base$term_start,
    base$term_end
  )
  enrl$plots <- c(enrl$plots, history$plots)
  enrl$tables <- c(enrl$tables, history$tables)

  gen_ed_context <- build_dept_gen_ed_college_context(
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$term_start,
    base$term_end
  )
  enrl$plots["enrl_gen_ed_college_context_plot"] <- list(gen_ed_context$plot)
  enrl$tables["enrl_gen_ed_college_context"] <- list(gen_ed_context$table)

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
  enrl$plots["enrl_cross_dept_minors"] <- list(enrl$plots$cross_dept_minors)
  enrl$plots$majors_with_minor <- plot_majors_with_dept_minor(
    base$data_objects_filt[["cedar_programs"]],
    base$dept_code,
    term = base$current_term
  )
  enrl$plots["enrl_majors_with_minor"] <- list(enrl$plots$majors_with_minor)
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

  plots <- c(sch_college$plots, sch_major$plots, sch_fac$plots)
  plots["enrl_college_dept_dual_plot"] <- list(plots$college_dept_dual_plot)
  plots["enrl_college_dept_upper_dual_plot"] <- list(plots$college_dept_upper_dual_plot)
  plots["enrl_college_dept_grad_dual_plot"] <- list(plots$college_dept_grad_dual_plot)

  list(
    plots = plots,
    tables = c(sch_college$tables, sch_major$tables, sch_fac$tables)
  )
}
