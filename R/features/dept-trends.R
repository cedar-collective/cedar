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

rehydrate_dept_report_base <- function(cached, data_objects, opt = list()) {
  hc_plot_keys <- paste0(c(
    "hc_progs_under_long_majors", "hc_progs_under_long_minors",
    "hc_progs_grad_long_majors", "hc_progs_grad_long_minors"
  ), "_plot")
  plots <- rebuild_dept_hc_plots(cached)

  c(
    cached[c(
      "dept_code", "dept_raw", "dept_name", "subj_codes",
      "prog_codes", "prog_focus", "term_start", "term_end"
    )],
    list(
      palette = if (exists("cedar_report_palette")) cedar_report_palette else NULL,
      current_term = opt[["current_term"]] %||% cached[["current_term"]],
      plots = plots[intersect(names(plots), hc_plot_keys)],
      tables = cached$tables,
      data_objects_filt = filter_data_objects(data_objects, opt[["campus"]])
    )
  )
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

plot_dept_enrollment_history <- function(history, palette) {
  if (is.null(history) || nrow(history) == 0) return(list())

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
    enrl_term_enrollment_plot = make_line(
      "total_enrl", "Total course enrollment", "Enrollment"
    ),
    enrl_term_sections_plot = make_line(
      "sections", "Active sections", "Sections"
    ),
    enrl_term_avg_size_plot = make_line(
      "avg_section_size", "Average enrollment per section", "Avg size"
    )
  )
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

  list(
    plots = plot_dept_enrollment_history(history, palette),
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

plot_dept_composition_donut <- function(data, color_map) {
  if (is.null(data) || nrow(data) == 0) return(NULL)
  colors <- color_map[as.character(data$label)]
  colors[is.na(colors)] <- unname(CEDAR_SEMANTIC_COLORS["other"])

  plotly::plot_ly(
    data,
    labels = ~label,
    values = ~n,
    type = "pie",
    hole = 0.55,
    textinfo = "percent",
    hovertemplate = "%{label}: %{value:.1f} (%{percent})<extra></extra>",
    marker = list(
      colors = unname(colors),
      line = list(color = "#fff", width = 1)
    )
  ) %>%
    plotly::layout(
      showlegend = FALSE,
      margin = list(t = 8, b = 4, l = 4, r = 4)
    )
}

dept_student_donut_cache_data <- function(donuts) {
  table_keys <- grep("_table_df$", names(donuts), value = TRUE)
  tables <- lapply(donuts[table_keys], function(x) {
    if (is.null(x) || !is.data.frame(x)) return(x)
    dplyr::select(x, -dplyr::any_of("color"))
  })
  list(
    tables = tables,
    major_label_order = names(donuts$major_color_map %||% character(0)),
    class_label_order = names(donuts$class_color_map %||% character(0))
  )
}

rehydrate_dept_student_donuts <- function(cached) {
  if (is.null(cached)) return(list())
  major_map <- build_color_map(cached$major_label_order %||% character(0))
  class_map <- build_color_map(cached$class_label_order %||% character(0))
  result <- list(major_color_map = major_map, class_color_map = class_map)

  for (key in names(cached$tables %||% list())) {
    data <- cached$tables[[key]]
    map <- if (grepl("_major_", key)) major_map else class_map
    if (!is.null(data) && is.data.frame(data)) {
      colors <- map[as.character(data$label)]
      colors[is.na(colors)] <- unname(CEDAR_SEMANTIC_COLORS["other"])
      data$color <- unname(colors)
    }
    result[[key]] <- data
    plot_key <- sub("_table_df$", "_current", key)
    result[[plot_key]] <- plot_dept_composition_donut(data, map)
  }
  result
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

  credit_hours_by_level <- get_credit_hours_by_level_data(
    base$data_objects_filt[["cedar_students"]],
    base$dept_code,
    n_years = 5
  )
  enrl$tables$enrl_credit_hours_by_level <- credit_hours_by_level
  enrl$plots["enrl_credit_hours_by_level_plot"] <- list(
    plot_credit_hours_by_level_data(credit_hours_by_level)
  )

  signals <- get_dept_enrollment_trend_signals(
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    term_start = base$term_start,
    term_end = base$term_end,
    current_term = base$current_term
  )
  enrl$tables <- c(enrl$tables, signals$tables)

  cross_dept_minors <- get_cross_dept_minors_data(
    base$data_objects_filt[["cedar_programs"]],
    base$dept_code,
    term = base$current_term
  )
  majors_with_minor <- get_majors_with_dept_minor_data(
    base$data_objects_filt[["cedar_programs"]],
    base$dept_code,
    term = base$current_term
  )
  enrl$tables$enrl_cross_dept_minors <- cross_dept_minors
  enrl$tables$enrl_majors_with_minor <- majors_with_minor
  enrl$plots$cross_dept_minors <- plot_cross_dept_program_donut(cross_dept_minors)
  enrl$plots["enrl_cross_dept_minors"] <- list(enrl$plots$cross_dept_minors)
  enrl$plots$majors_with_minor <- plot_cross_dept_program_donut(majors_with_minor)
  enrl$plots["enrl_majors_with_minor"] <- list(enrl$plots$majors_with_minor)
  student_donuts <- plot_dept_student_donuts(
    base$data_objects_filt[["cedar_students"]],
    base$data_objects_filt[["cedar_sections"]],
    base$dept_code,
    base$current_term
  )
  enrl$tables$enrl_student_donuts <- dept_student_donut_cache_data(student_donuts)
  enrl$plots$student_donuts <- student_donuts

  enrl
}

rebuild_dept_enrl_tab <- function(cached, base) {
  tables <- cached$tables %||% list()
  plots <- plot_enrl_for_dept_report(
    tables$enrl_summary, base$palette, base$term_start, base$term_end
  )
  plots <- c(
    plots,
    plot_dept_enrollment_history(tables$enrl_history_by_level, base$palette)
  )
  plots["enrl_gen_ed_college_context_plot"] <- list(plot_indexed_growth(
    tables$enrl_gen_ed_college_context,
    base$dept_code,
    title_prefix = "Gen Ed Enrollment Growth",
    metric_label = "Gen Ed Enrollment"
  ))
  plots["enrl_credit_hours_by_level_plot"] <- list(
    plot_credit_hours_by_level_data(tables$enrl_credit_hours_by_level)
  )
  cross_dept_minors <- plot_cross_dept_program_donut(
    tables$enrl_cross_dept_minors
  )
  plots["cross_dept_minors"] <- list(cross_dept_minors)
  plots["enrl_cross_dept_minors"] <- list(cross_dept_minors)
  majors_with_minor <- plot_cross_dept_program_donut(
    tables$enrl_majors_with_minor
  )
  plots["majors_with_minor"] <- list(majors_with_minor)
  plots["enrl_majors_with_minor"] <- list(majors_with_minor)
  plots$student_donuts <- rehydrate_dept_student_donuts(
    tables$enrl_student_donuts
  )

  list(plots = plots, tables = tables)
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

rebuild_dept_degrees_tab <- function(cached, base) {
  tables <- cached$tables %||% list()
  list(
    plots = plot_degrees_for_dept_report(
      tables$degree_summary_filtered,
      tables$degree_summary_filtered_program,
      base$dept_name,
      base$prog_codes,
      base$palette
    ),
    tables = tables
  )
}

compute_dept_demographics_tab <- function(base) {
  population_trend <- get_population_trend_data(
    base$data_objects_filt[["cedar_programs"]],
    base$dept_code
  )
  list(
    plots = list(
      population_trend = plot_population_trend_data(
        population_trend, base$dept_code
      )
    ),
    tables = list(population_trend = population_trend)
  )
}

rebuild_dept_demographics_tab <- function(cached, base) {
  tables <- cached$tables %||% list()
  list(
    plots = list(
      population_trend = plot_population_trend_data(
        tables$population_trend, base$dept_code
      )
    ),
    tables = tables
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
  plots["chd_by_year_plot"] <- list(plots$chd_by_period_plot)
  plots["enrl_college_dept_dual_plot"] <- list(plots$college_dept_dual_plot)
  plots["enrl_college_dept_upper_dual_plot"] <- list(plots$college_dept_upper_dual_plot)
  plots["enrl_college_dept_grad_dual_plot"] <- list(plots$college_dept_grad_dual_plot)

  list(
    plots = plots,
    tables = c(sch_college$tables, sch_major$tables, sch_fac$tables)
  )
}

rebuild_dept_credit_hours_tab <- function(cached, base) {
  tables <- cached$tables %||% list()
  empty_table <- function(x) {
    if (is.null(x) || !is.data.frame(x)) tibble::tibble() else x
  }
  split_value <- function(x, name) {
    if (is.null(x) || !name %in% names(x)) 0 else unname(x[[name]])
  }
  major_plots <- function(suffix, label) {
    top <- empty_table(tables[[paste0("sch_top_outside_", suffix)]])
    time <- empty_table(tables[[paste0("sch_time_data_", suffix)]])
    split <- tables[[paste0("sch_split_", suffix)]]
    colors <- build_color_map(
      tables[[paste0("sch_color_order_", suffix)]] %||% character(0)
    )
    list(
      outside = plot_outside_majors_pie(top, colors, label),
      dept = plot_home_outside_pie(
        split_value(split, "home"),
        split_value(split, "outside"),
        split_value(split, "total"),
        label
      ),
      time = plot_outside_time_series(time, colors, label)
    )
  }

  lower <- major_plots("lower", "Lower Division")
  upper <- major_plots("upper", "Upper Division")
  all_ug <- major_plots("all_ug", "All Undergrad")
  by_fac_level <- empty_table(tables$chd_fac_by_level)
  by_fac_total <- empty_table(tables$chd_fac_by_total)

  plots <- list(
    college_credit_hours_plot = plot_college_credit_hours(
      empty_table(tables$chd_college)
    ),
    college_credit_hours_comp_plot = plot_college_comp(
      empty_table(tables$chd_diff_fr_college)
    ),
    college_dept_dual_plot = plot_indexed_growth(
      empty_table(tables$chd_indexed), base$dept_code
    ),
    college_dept_lower_dual_plot = plot_indexed_growth(
      empty_table(tables$chd_indexed_lower), base$dept_code,
      "Lower-Division SCH Growth", "SCH"
    ),
    college_dept_upper_dual_plot = plot_indexed_growth(
      empty_table(tables$chd_indexed_upper), base$dept_code,
      "Upper-Division SCH Growth", "SCH"
    ),
    college_dept_grad_dual_plot = plot_indexed_growth(
      empty_table(tables$chd_indexed_grad), base$dept_code,
      "Graduate SCH Growth", "SCH"
    ),
    chd_by_year_facet_subj_plot = plot_chd_by_subj_faceted(
      empty_table(tables$chd_by_subj_level), base$palette
    ),
    chd_by_year_subj_plot = plot_chd_by_subj_stacked(
      empty_table(tables$chd_by_subj_total)
    ),
    chd_by_period_plot = plot_chd_by_level(
      empty_table(tables$chd_by_period_data), base$subj_codes, base$palette
    ),
    sch_outside_pct_lower_plot = lower$outside,
    sch_dept_pct_lower_plot = lower$dept,
    sch_top_majors_lower_plot = lower$time,
    sch_outside_pct_upper_plot = upper$outside,
    sch_dept_pct_upper_plot = upper$dept,
    sch_top_majors_upper_plot = upper$time,
    sch_outside_pct_plot = all_ug$outside,
    sch_dept_pct_plot = all_ug$dept,
    chd_by_fac_facet_plot = if (nrow(by_fac_level) > 0) {
      plot_chd_by_fac_faceted(by_fac_level, base$subj_codes, base$palette)
    } else NULL,
    chd_by_fac_plot = if (nrow(by_fac_total) > 0) {
      plot_chd_by_fac_stacked(by_fac_total, base$subj_codes, base$palette)
    } else NULL
  )
  plots$chd_by_year_plot <- plots$chd_by_period_plot
  plots$enrl_college_dept_dual_plot <- plots$college_dept_dual_plot
  plots$enrl_college_dept_upper_dual_plot <- plots$college_dept_upper_dual_plot
  plots$enrl_college_dept_grad_dual_plot <- plots$college_dept_grad_dual_plot

  list(plots = plots, tables = tables)
}
