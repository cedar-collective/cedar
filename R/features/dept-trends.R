# Dept Trends support for the active Shiny department profile.
#
# These functions assemble department metadata, build the fast headcount base,
# and compute tab payloads. Heavy analysis stays in branches/cones.

DEPT_TRENDS_PRELOAD_TABS <- c(
  "Enrollment", "Credit Hours", "Degrees", "Demographics"
)

DEPT_TRENDS_CREDIT_HOUR_PLOTS <- c(
  "sch_census_final_plot",
  "chd_by_year_facet_subj_plot",
  "chd_by_year_subj_plot",
  "college_dept_dual_plot",
  "sch_outside_pct_lower_plot",
  "sch_outside_pct_upper_plot",
  "sch_dept_pct_lower_plot",
  "sch_dept_pct_upper_plot",
  "sch_top_majors_lower_plot",
  "sch_top_majors_upper_plot"
)

# One source of truth for the tab preload/cache contract. Keeping this outside
# the Shiny module makes the set of eagerly prepared tabs and their required
# plot payloads directly testable.
dept_trends_tab_spec <- function(tab) {
  switch(tab,
    Enrollment = list(
      code = "enrl",
      compute = compute_dept_enrl_tab,
      rebuild = rebuild_dept_enrl_tab,
      campus_scoped = TRUE
    ),
    Degrees = list(
      code = "deg",
      compute = compute_dept_degrees_tab,
      rebuild = rebuild_dept_degrees_tab,
      campus_scoped = FALSE
    ),
    `Credit Hours` = list(
      code = "ch",
      compute = compute_dept_credit_hours_tab,
      rebuild = rebuild_dept_credit_hours_tab,
      campus_scoped = TRUE,
      required_plots = DEPT_TRENDS_CREDIT_HOUR_PLOTS
    ),
    Demographics = list(
      code = "demo",
      compute = compute_dept_demographics_tab,
      rebuild = rebuild_dept_demographics_tab,
      campus_scoped = FALSE
    ),
    NULL
  )
}

preload_dept_trends_tabs <- function(load_tab,
                                     tabs = DEPT_TRENDS_PRELOAD_TABS) {
  if (!is.function(load_tab)) {
    stop("load_tab must be a function")
  }
  stats::setNames(vapply(tabs, function(tab) {
    isTRUE(load_tab(tab))
  }, logical(1)), tabs)
}

set_payload <- function(dept_code, prog_focus = NULL) {
  message("[dept-trends.R] Welcome to set_payload!")
  message("[dept-trends.R] Received dept_code: ", dept_code)

  clean_codes <- function(x) {
    x <- as.character(x)
    unique(x[!is.na(x) & nzchar(x)])
  }

  message("[dept-trends.R] Setting program codes and names from the mapping files...")
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
    term_start = cedar_report_start_term,
    # Charts run to the newest enrolled term; the in-progress tail is labelled
    # in the module. Trend signals (largest increases, perennial lows) compare
    # against history and stop at the settled edge.
    term_end   = cedar_report_latest_term,
    settled_end = cedar_report_end_term,
    palette    = cedar_report_palette
  )

  message("[dept-trends.R] returning cfg set as:\n",
          paste(capture.output(str(cfg, max.level = 1)), collapse = "\n"))

  cfg
}

filter_data_objects <- function(data_objects, campus_filter) {
  if (!is.null(campus_filter) && length(campus_filter) > 0) {
    data_objects[["cedar_registrations"]] <- data_objects[["cedar_registrations"]] %>%
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
    plot <- plot_dept_program_headcount(tables[[data_name]])
    if (!is.null(plot)) plots[[paste0(data_name, "_plot")]] <- plot
  }

  plots
}

rehydrate_dept_report_base <- function(cached, opt = list()) {
  hc_plot_keys <- paste0(c(
    "hc_progs_under_long_majors", "hc_progs_under_long_minors",
    "hc_progs_grad_long_majors", "hc_progs_grad_long_minors"
  ), "_plot")
  plots <- if ("plots" %in% names(cached)) {
    cached$plots %||% list()
  } else {
    rebuild_dept_hc_plots(cached)
  }

  c(
    cached[c(
      "dept_code", "dept_raw", "dept_name", "subj_codes",
      "prog_codes", "prog_focus", "term_start", "term_end", "settled_end"
    )],
    list(
      palette = if (exists("cedar_report_palette")) cedar_report_palette else NULL,
      current_term = opt[["current_term"]] %||% cached[["current_term"]],
      plots = plots[intersect(names(plots), hc_plot_keys)],
      tables = cached$tables
    )
  )
}

# Return a ready-to-render cached tab. The rebuild callback supports old or
# deliberately data-only payloads, while current versioned cache entries take
# the fast path and reuse their stored plots.
rehydrate_dept_tab_payload <- function(cached, base, rebuild,
                                       required_plots = character(0)) {
  cached_plot_names <- names(cached$plots %||% list())
  ready <- "plots" %in% names(cached) &&
    all(required_plots %in% cached_plot_names)

  if (ready) {
    return(list(
      plots = cached$plots %||% list(),
      tables = cached$tables %||% list()
    ))
  }
  rebuild(cached, base)
}

create_dept_report_base <- function(data_objects, opt) {
  required_datasets <- c(
    "cedar_registrations", "cedar_degrees", "cedar_sections", "cedar_programs",
    "cedar_student_terms"
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

  if (is.null(opt[["current_term"]]) || length(opt[["current_term"]]) == 0) {
    stop("[dept-trends.R] opt$current_term is required.")
  }

  cfg <- set_payload(dept_code, opt[["prog"]])
  cfg$current_term <- as.integer(opt[["current_term"]][[1]])
  cfg$dept_raw <- incoming_dept

  hc <- get_headcount_data_for_dept_report(
    data_objects[["cedar_programs"]],
    cfg$dept_code,
    cfg$term_start,
    cfg$term_end,
    dims = data_objects[["cedar_dims"]]
  )

  c(cfg, list(
    plots = hc$plots,
    tables = hc$tables
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

compute_dept_enrl_tab <- function(base, data_objects, campus_filter = NULL) {
  # Campus-scoped source rows are needed only while building an uncached tab.
  # Do not attach this large intermediate object to `base`: Dept Trends keeps
  # `base` in a session reactive for the life of the report.
  scoped_data <- filter_data_objects(data_objects, campus_filter)

  enrl <- get_enrl_for_dept_report(
    scoped_data[["cedar_sections"]],
    base$dept_code,
    base$palette,
    base$term_start,
    base$term_end
  )

  history <- build_dept_enrollment_history(
    scoped_data[["cedar_sections"]],
    base$dept_code,
    base$palette,
    base$term_start,
    base$term_end
  )
  enrl$plots <- c(enrl$plots, history$plots)
  enrl$tables <- c(enrl$tables, history$tables)

  gen_ed_context <- build_dept_gen_ed_college_context(
    scoped_data[["cedar_sections"]],
    base$dept_code,
    base$term_start,
    base$term_end
  )
  enrl$plots["enrl_gen_ed_college_context_plot"] <- list(gen_ed_context$plot)
  enrl$tables["enrl_gen_ed_college_context"] <- list(gen_ed_context$table)

  credit_hours_by_level <- get_credit_hours_by_level_data(
    scoped_data[["cedar_registrations"]],
    scoped_data[["cedar_sections"]],
    base$dept_code,
    n_years = 5
  )
  enrl$tables$enrl_credit_hours_by_level <- credit_hours_by_level
  enrl$plots["enrl_credit_hours_by_level_plot"] <- list(
    plot_credit_hours_by_level_data(credit_hours_by_level)
  )

  signals <- get_dept_enrollment_trend_signals(
    scoped_data[["cedar_sections"]],
    base$dept_code,
    term_start = base$term_start,
    term_end = base$settled_end,
    current_term = base$current_term
  )
  enrl$tables <- c(enrl$tables, signals$tables)

  cross_dept_minors <- get_cross_dept_minors_data(
    scoped_data[["cedar_programs"]],
    base$dept_code,
    term = base$current_term
  )
  majors_with_minor <- get_majors_with_dept_minor_data(
    scoped_data[["cedar_programs"]],
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
    scoped_data[["cedar_registrations"]],
    scoped_data[["cedar_sections"]],
    base$dept_code,
    base$current_term,
    dims = scoped_data[["cedar_dims"]],
    student_terms = scoped_data[["cedar_student_terms"]]
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

compute_dept_degrees_tab <- function(base, data_objects, campus_filter = NULL) {
  get_degrees_for_dept_report(
    data_objects[["cedar_degrees"]],
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

compute_dept_demographics_tab <- function(base, data_objects, campus_filter = NULL) {
  population_trend <- get_population_trend_data(
    data_objects[["cedar_programs"]],
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

compute_dept_credit_hours_tab <- function(base, data_objects,
                                          campus_filter = NULL) {
  # As with Enrollment, retain this campus-scoped copy only for the duration of
  # a cold computation. Cached Credit Hours tabs rebuild from summary tables.
  do_filt <- filter_data_objects(data_objects, campus_filter)
  filtered_cl <- do_filt[["cedar_registrations"]] %>%
    dplyr::filter(department == base$dept_code)

  sch_college <- get_credit_hours_for_dept_trends(
    do_filt[["cedar_registrations"]],
    do_filt[["cedar_sections"]],
    base$dept_code,
    base$subj_codes,
    base$term_start,
    base$term_end,
    base$palette
  )
  # Each row's major is its student-term's primary major (ADR-001 step 2),
  # named through the dimension tables; the roster's major columns are not read.
  sch_major <- credit_hours_by_major(
    filtered_cl,
    do_filt[["cedar_sections"]],
    base$dept_code,
    base$prog_codes,
    base$term_start,
    base$term_end,
    student_terms = do_filt[["cedar_student_terms"]],
    major_names = name_program_codes(
      do_filt[["cedar_student_terms"]]$primary_major_code,
      do_filt[["cedar_dims"]],
      is_pre_major = do_filt[["cedar_student_terms"]]$is_pre_major
    ),
    include_all_ug = FALSE,
    include_wide_table = FALSE
  )

  # Faculty-category and all-undergraduate duplicate charts are not displayed
  # anywhere in Dept Trends. Computing their joins/summaries here made the
  # visible Credit Hours tab slower; the faculty join could also prevent every
  # visible SCH chart from loading when faculty data was absent or stale.
  plots <- c(sch_college$plots, sch_major$plots)
  plots["chd_by_year_plot"] <- list(plots$chd_by_period_plot)
  plots["enrl_college_dept_dual_plot"] <- list(plots$college_dept_dual_plot)
  plots["enrl_college_dept_upper_dual_plot"] <- list(plots$college_dept_upper_dual_plot)
  plots["enrl_college_dept_grad_dual_plot"] <- list(plots$college_dept_grad_dual_plot)

  list(
    plots = plots,
    tables = c(sch_college$tables, sch_major$tables)
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
    sch_census_final_plot = plot_sch_census_final(
      empty_table(tables$chd_census_final)
    ),
    sch_outside_pct_lower_plot = lower$outside,
    sch_dept_pct_lower_plot = lower$dept,
    sch_top_majors_lower_plot = lower$time,
    sch_outside_pct_upper_plot = upper$outside,
    sch_dept_pct_upper_plot = upper$dept,
    sch_top_majors_upper_plot = upper$time,
    sch_outside_pct_plot = all_ug$outside,
    sch_dept_pct_plot = all_ug$dept
  )
  plots$chd_by_year_plot <- plots$chd_by_period_plot
  plots$enrl_college_dept_dual_plot <- plots$college_dept_dual_plot
  plots$enrl_college_dept_upper_dual_plot <- plots$college_dept_upper_dual_plot
  plots$enrl_college_dept_grad_dual_plot <- plots$college_dept_grad_dual_plot

  list(plots = plots, tables = tables)
}


# ── Courses Taken: where this unit's majors take their courses ───────────────
# The inverse of Students Served on the Credit Hours tab: that asks whose
# majors fill this unit's seats; this asks which units teach the courses this
# unit's majors sit in. Computed on activation (three passes of the cone, under
# two seconds on the full class list, 2026-11-12), never cached, so it is not
# in DEPT_CACHE_TABLES.

#' Compute the Courses Taken tab
#'
#' @param base The Dept Trends base payload (`dept_code`, `dept_name`).
#' @param data_objects The loaded tables: `cedar_student_terms`,
#'   `cedar_registrations`, `cedar_dims`, `cedar_edges`.
#' @param campus_filter Teaching campuses to keep (the page's scope); NULL
#'   keeps every campus, each its own row.
#' @param min_n The smallest distinct-student count a teaching unit or college
#'   shows on its own. Colleges under it are pooled as one row; units under it
#'   are pooled with the other small units of their college. An outside
#'   course under it in a term has no row for that term, and a term and campus
#'   with fewer members has no point or chart of its own.
#' @param program_code One or more of the unit's program codes to narrow the
#'   members to (`meta$programs` lists them); NULL reads every program.
#' @param n_outside How many outside courses the page charts per teaching
#'   campus (`meta$n_outside`).
#' @param n_top How many outside units get a bar in the latest-term chart.
#' @return `tables` (`own_share`: per term and campus, the members' students
#'   and registrations and the share in the unit's own courses; `by_college`:
#'   per term, campus and teaching college, the share, with every college
#'   under `min_n` students that term pooled as one row (`pooled`,
#'   `n_pooled`); `latest_units`: the latest term's teaching units per campus,
#'   the units under `min_n` students pooled one row per label of
#'   `by_college` (`n_pooled` units), so the rows under a college's label add
#'   up to its row of `by_college` for that term; `top_units`: the same term
#'   as bars (`prepare_major_course_units_top_units()`), under the same
#'   labels; `outside_courses`: per term, campus and course outside the unit
#'   with `min_n` members in it, the members in it and their share of that
#'   term's members on the campus), `plots` (`top_units`: one plotly per
#'   campus with `min_n` members in the latest term, a bar in its college's
#'   colour) and `meta` (`chart_campuses`: the campuses with `min_n` members
#'   in some term, which the over-time charts draw). The over-time charts are
#'   drawn by the page from `own_share`, `by_college` and `outside_courses`,
#'   for the term types its reader ticks.
compute_dept_course_units_tab <- function(base, data_objects, campus_filter = NULL, min_n = 10L,
                                          program_code = NULL, n_outside = 15L, n_top = 8L) {
  for (key in c("cedar_student_terms", "cedar_registrations", "cedar_dims", "cedar_edges")) {
    if (is.null(data_objects[[key]])) stop("[dept-trends.R] compute_dept_course_units_tab: data_objects lacks ", key)
  }
  if (is.null(base$dept_code) || !nzchar(base$dept_code)) stop("[dept-trends.R] base$dept_code is required")
  min_n <- as.integer(min_n)

  # Every unit row, so the shares below are over every member registration;
  # the display guard is applied once, to the latest-term table.
  result <- get_major_course_units(
    data_objects[["cedar_student_terms"]], data_objects[["cedar_registrations"]],
    list(dept_code = base$dept_code, campus = campus_filter, min_n = 1L, program_code = program_code,
         include_in_progress = TRUE, data_edges = data_objects[["cedar_edges"]])
  )
  dims <- data_objects[["cedar_dims"]]
  # The unit's programs, counted over every member whatever program is chosen.
  programs <- attr(result, "member_programs")
  program_names <- name_program_codes(programs$primary_major_code, dims, programs$is_pre_major)
  programs <- programs %>%
    group_by(program_code = primary_major_code) %>%
    summarize(n_students = sum(n_students), .groups = "drop") %>%
    mutate(program_label = unname(program_names[program_code])) %>%
    arrange(desc(n_students), program_code)
  if (!is.null(program_code) && !all(program_code %in% programs$program_code)) {
    stop("[dept-trends.R] compute_dept_course_units_tab: ", base$dept_code, " has no member in program ",
         paste(setdiff(program_code, programs$program_code), collapse = ", "))
  }
  dept_name <- base$dept_name %||% base$dept_code
  member_name <- if (is.null(program_code)) dept_name else {
    paste(programs$program_label[match(program_code, programs$program_code)], collapse = ", ")
  }
  unit_labels <- unit_names(dims)
  college_labels <- college_code_names(dims)
  no_unit <- "No unit decided"

  rows <- result %>%
    left_join(unit_labels, by = "dept_code") %>%
    mutate(unit_label = case_when(is.na(dept_code) ~ no_unit, is.na(dept_name) ~ dept_code, TRUE ~ dept_name))

  own_share <- rows %>%
    group_by(term, campus, in_progress) %>%
    summarize(
      students = first(term_students),
      registrations = first(term_registrations),
      own_registrations = sum(n_registrations[is_own_unit]),
      n_units = n_distinct(dept_code),
      .groups = "drop"
    ) %>%
    mutate(own_share = own_registrations / registrations) %>%
    arrange(term, campus)

  # The same registrations one level up. A college under min_n students in a
  # term and campus is pooled there: most colleges teach a major's students a
  # course or two, and a legend of every one of them hides the few that
  # matter. The students are counted per college by the cone, since a unit
  # row's students cannot be added up to a college's.
  colleges <- get_major_course_units(
    data_objects[["cedar_student_terms"]], data_objects[["cedar_registrations"]],
    list(dept_code = base$dept_code, campus = campus_filter, min_n = 1L, program_code = program_code,
         grain = "college", include_in_progress = TRUE, data_edges = data_objects[["cedar_edges"]])
  )
  other_colleges <- paste0("Other colleges (each under ", min_n, " students)")
  colleges <- colleges %>%
    mutate(
      pooled = n_students < min_n,
      college_label = case_when(
        pooled ~ other_colleges,
        !unit_decided ~ no_unit,
        is.na(college) ~ "No college",
        TRUE ~ coalesce(unname(college_labels[college]), college)
      )
    )
  by_college <- colleges %>%
    group_by(term, campus, in_progress, college_label, pooled) %>%
    summarize(
      n_pooled = sum(pooled),
      # Distinct students cannot be added across the rows of a pooled cell.
      n_students = if (n() == 1L && !pooled[[1]]) n_students[[1]] else NA_integer_,
      n_registrations = sum(n_registrations),
      share = sum(share_of_registrations),
      .groups = "drop"
    ) %>%
    arrange(term, campus, pooled, desc(share))

  # The cone's latest_term is the end of the data window. The table and the
  # lead read the latest term in which a member actually holds a registration,
  # which is earlier for a department whose majors have stopped enrolling.
  window_end <- attr(result, "latest_term")
  latest <- if (nrow(rows) > 0L) max(rows$term) else window_end
  # Each of the latest term's units under the label the college chart draws its
  # college under that term and campus, so the table and the bars pool small
  # units inside a segment of that chart and add up to it. One row for every
  # small unit hid a college whose units are each under the guard: Fine Arts
  # taught History's majors through six of them in Fall 2026. The label is the
  # chart's for every row, the department's own unit included: where its
  # college is under the guard, its row is under the pooled label too.
  latest_rows <- rows %>%
    filter(term == latest) %>%
    mutate(unit_decided = !is.na(dept_code),
           band_key = if_else(unit_decided, college, NA_character_)) %>%
    left_join(colleges %>% transmute(term, campus, unit_decided, band_key = college, college_label,
                                     band_pooled = pooled, band_students = n_students),
              by = c("term", "campus", "unit_decided", "band_key"))
  if (anyNA(latest_rows$college_label)) {
    stop("[dept-trends.R] compute_dept_course_units_tab: a unit row has no college row for its term and campus")
  }
  shown <- latest_rows %>% filter(n_students >= min_n | is_own_unit)
  pooled <- latest_rows %>%
    filter(n_students < min_n, !is_own_unit) %>%
    group_by(term, campus, in_progress, college_label, band_pooled) %>%
    summarize(
      n_pooled = n(),
      n_registrations = sum(n_registrations),
      share_of_registrations = sum(share_of_registrations),
      band_students = first(band_students),
      .groups = "drop"
    ) %>%
    left_join(shown %>% count(campus, college_label, name = "n_shown"), by = c("campus", "college_label")) %>%
    mutate(
      n_shown = coalesce(n_shown, 0L),
      college = NA_character_, dept_code = NA_character_, is_own_unit = FALSE,
      # Distinct students cannot be added across unit rows; the college's own
      # count stands when the row is every unit of a college above the guard.
      n_students = if_else(n_shown == 0L & !band_pooled, band_students, NA_integer_),
      unit_label = paste0(n_pooled, if_else(n_shown > 0L, " other", ""),
                          if_else(n_pooled == 1L, " unit under ", " units, each under "), min_n, " students")
    )
  latest_units <- bind_rows(shown %>% mutate(n_pooled = 0L), pooled) %>%
    select(term, campus, in_progress, college_label, unit_label, dept_code, is_own_unit, n_pooled,
           n_students, n_registrations, share_of_registrations) %>%
    arrange(campus, desc(is_own_unit), n_pooled > 0L, college_label == other_colleges, desc(n_registrations))

  # The courses themselves, term by term: the seats another unit's schedule
  # supplies to these majors, and where two curricula overlap. Same members,
  # same registrations, one grain down; a course under min_n students in a
  # term has no row for it. The page ranks them over the term types its
  # reader ticks (prepare_major_course_units_course_history()).
  courses <- get_major_course_units(
    data_objects[["cedar_student_terms"]], data_objects[["cedar_registrations"]],
    list(dept_code = base$dept_code, campus = campus_filter, min_n = 1L, program_code = program_code,
         grain = "course", include_in_progress = TRUE, data_edges = data_objects[["cedar_edges"]])
  ) %>% filter(!is_own_unit)
  outside_courses <- courses %>%
    filter(n_students >= min_n) %>%
    left_join(unit_labels, by = "dept_code") %>%
    mutate(unit_label = case_when(is.na(dept_code) ~ no_unit, is.na(dept_name) ~ dept_code, TRUE ~ dept_name)) %>%
    select(term, campus, in_progress, subject_course, unit_label, dept_code,
           n_students, term_students, share_of_students) %>%
    arrange(term, campus, desc(n_students), subject_course)

  # A chart is drawn for a campus that has min_n members to read: in some
  # term for the series, in the latest term for its bars. A smaller campus is
  # in the tables.
  chart_campuses <- own_share %>% filter(students >= min_n) %>% distinct(campus) %>% pull(campus) %>% sort()
  top_units <- prepare_major_course_units_top_units(latest_rows, own_label = dept_name, min_n = min_n,
                                                    n_top = n_top, pooled_label = other_colleges)
  # The colours the page's colleges-over-time charts give the same campuses.
  college_colors <- major_course_units_college_colors(by_college %>% filter(campus %in% chart_campuses))

  list(
    tables = list(own_share = own_share, by_college = by_college, latest_units = latest_units,
                  top_units = top_units, outside_courses = outside_courses),
    plots = list(top_units = plot_major_course_units_top_units(top_units, college_colors)),
    meta = list(
      dept_code = base$dept_code,
      dept_name = dept_name,
      member_name = member_name,
      program_code = program_code,
      programs = programs,
      edge = attr(result, "edge"),
      window_end = window_end,
      latest_term = latest,
      latest_in_progress = latest > attr(result, "edge"),
      chart_campuses = chart_campuses,
      n_members = attr(result, "n_members"),
      n_member_student_terms = attr(result, "n_member_student_terms"),
      n_unmapped = attr(result, "n_unmapped"),
      min_n = min_n,
      n_outside = as.integer(n_outside),
      n_top = as.integer(n_top)
    )
  )
}

#' What the Courses Taken tab has to say before its charts, when anything
#'
#' The numbers are in the charts. This is only the sentence a chart cannot
#' carry: that no member holds a registration, or that the latest term read is
#' earlier than the data's last term.
#'
#' @param payload `compute_dept_course_units_tab()` output.
#' @return Character vector: empty, or one sentence.
dept_course_units_note <- function(payload) {
  meta <- payload$meta
  if (nrow(payload$tables$own_share) == 0L) {
    return(paste0("No enrolled ", meta$member_name, " major holds a registration to ", fmt_term(meta$window_end), "."))
  }
  if (meta$latest_term < meta$window_end) {
    return(paste0("No enrolled ", meta$member_name, " major holds a registration after ", fmt_term(meta$latest_term),
                  "; the data runs to ", fmt_term(meta$window_end), ", so that is the latest term read here."))
  }
  character(0)
}
