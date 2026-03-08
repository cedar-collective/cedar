#' Department Dashboard Analytics
#'
#' Lightweight analytics for the "Explore Your Unit" dashboard.
#' Designed to load fast, display visually, and emphasize discovery over compliance.
#'
#' Key functions:
#' - `compute_trend()` — generalized slope-based trend helper (reusable across cones)
#' - `plot_metric_trendline()` — multi-series plotly line chart for any metric over time
#' - `get_headcount_summary()` — major/minor counts with trend arrows
#' - `plot_cross_dept_minors()` — donut: what other depts do your majors minor in?
#' - `plot_credit_hours_by_level()` — lower/upper/grad credit hour trendlines (5 years)
#' - `get_enrollment_momentum()` — courses sorted into growing vs. worth-a-look
#' - `create_dept_dashboard_data()` — main entry point called by server.R
#'
#' Data requirements (passed via data_objects):
#' - cedar_programs: student_id, term, department, program_type, program_name
#' - cedar_students: student_id, term, department, level, credits, final_grade, major
#' - cedar_sections: term, department, subject_course, course_title, total_enrl, crosslist_primary


# ── Generalized trend helper ──────────────────────────────────────────────────

#' Compute trend direction from an ordered numeric vector
#'
#' Fits a linear model and classifies direction. Can be applied to any metric
#' over time: enrollment, headcount, credit hours, DFW rates, etc.
#'
#' @param values Numeric vector ordered oldest to newest. NAs are dropped.
#' @param min_n Minimum number of non-NA values required (default 2).
#' @param threshold Minimum absolute slope to count as up/down (default 0).
#'   Increase to require a meaningful change before calling something "up" or "down".
#' @return Named list: slope (numeric), direction ("up"/"down"/"stable"/"unknown"),
#'   arrow (unicode character ↑/↓/→/—)
#' @examples
#'   compute_trend(c(45, 48, 52, 61))   # direction = "up"
#'   compute_trend(c(80, 74, 71, 65))   # direction = "down"
#'   compute_trend(c(50, 52, 49, 51))   # direction = "stable"
#'   compute_trend(c(50))               # direction = "unknown" (too few points)
compute_trend <- function(values, min_n = 2, threshold = 0) {
  values <- values[!is.na(values)]
  if (length(values) < min_n) {
    return(list(slope = NA_real_, direction = "unknown", arrow = "\u2014"))
  }
  slope <- coef(lm(values ~ seq_along(values)))[2]
  direction <- dplyr::case_when(
    slope >  threshold ~ "up",
    slope < -threshold ~ "down",
    TRUE               ~ "stable"
  )
  arrow <- switch(direction, up = "\u2191", down = "\u2193", stable = "\u2192", "\u2014")
  list(slope = slope, direction = direction, arrow = arrow)
}


# ── Credit hours by level trendlines ─────────────────────────────────────────

#' Plot credit hour production by course level over last N years
#'
#' Creates a multi-line plotly chart with one line per course level
#' (lower division, upper division, graduate). Useful for seeing whether
#' a department's instructional mix is shifting over time.
#'
#' @param cedar_students CEDAR students data frame (cedar_students).
#' @param dept_code Department code string (e.g., "HIST").
#' @param n_years Number of years to include (default 5). Filters to
#'   academic years >= current_year - (n_years - 1).
#' @return A plotly object, or NULL if insufficient data.
plot_credit_hours_by_level <- function(cedar_students, dept_code, n_years = 5) {
  message("[dept-dashboard.R] plot_credit_hours_by_level for ", dept_code)

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  cutoff_year  <- current_year - (n_years - 1)

  ch <- cedar_students %>%
    dplyr::filter(
      department   == dept_code,
      final_grade  %in% passing_grades,
      level        %in% c("lower", "upper", "grad"),
      floor(term / 100) >= cutoff_year
    ) %>%
    dplyr::group_by(term, level) %>%
    dplyr::summarize(credit_hours = sum(credits, na.rm = TRUE), .groups = "drop") %>%
    dplyr::mutate(
      level = factor(level,
                     levels = c("lower", "upper", "grad"),
                     labels = c("Lower Division", "Upper Division", "Graduate"))
    )

  if (nrow(ch) == 0) {
    message("[dept-dashboard.R] No credit hour data for ", dept_code)
    return(NULL)
  }

  p <- ch %>%
    ggplot2::ggplot(ggplot2::aes(
      x     = as.factor(term),
      y     = credit_hours,
      color = level,
      group = level,
      text  = paste0(level, "<br>Term: ", term, "<br>Credit hours: ", scales::comma(credit_hours))
    )) +
    ggplot2::geom_line(linewidth = 1.1) +
    ggplot2::geom_point(size = 2.5) +
    ggplot2::scale_color_brewer(palette = "Set2") +
    ggplot2::labs(
      title  = "Credit Hours by Course Level",
      x      = NULL,
      y      = "Credit Hours",
      color  = NULL
    ) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(
      axis.text.x  = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position = "top"
    )

  plotly::ggplotly(p, tooltip = "text")
}


# ── Headcount summary with trend arrows ──────────────────────────────────────

#' Summarize major and minor headcount with trend arrows
#'
#' Returns a small summary data frame with current counts and trend direction
#' for undergrad/grad majors and minors. Intended for display as stat cards
#' on the dashboard, not as a full table.
#'
#' @param cedar_programs CEDAR programs data frame.
#' @param dept_code Department code string.
#' @param n_trend_terms Number of most-recent terms of each type to use for
#'   trend calculation (default 4 = last ~4 falls or springs).
#' @return Data frame with columns: group, current_count, trend_direction, arrow.
get_headcount_summary <- function(cedar_programs, dept_code, n_trend_terms = 4) {
  message("[dept-dashboard.R] get_headcount_summary for ", dept_code)

  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  summarize_group <- function(prog_data, program_types, level_filter, label) {
    df <- prog_data %>%
      dplyr::filter(
        department   == dept_code,
        program_type %in% program_types,
        student_level == level_filter
      ) %>%
      dplyr::group_by(term) %>%
      dplyr::summarize(count = dplyr::n_distinct(student_id), .groups = "drop") %>%
      dplyr::arrange(term)

    if (nrow(df) == 0) {
      return(data.frame(group = label, current_count = 0,
                        trend_direction = "unknown", arrow = "\u2014"))
    }

    current_count <- dplyr::last(df$count)
    trend <- compute_trend(df$count)

    data.frame(
      group           = label,
      current_count   = current_count,
      trend_direction = trend$direction,
      arrow           = trend$arrow,
      stringsAsFactors = FALSE
    )
  }

  dplyr::bind_rows(
    summarize_group(cedar_programs, major_types, "Undergraduate", "Undergrad Majors"),
    summarize_group(cedar_programs, minor_types, "Undergraduate", "Undergrad Minors"),
    summarize_group(cedar_programs, major_types, "Graduate/GASM",  "Grad Majors"),
    summarize_group(cedar_programs, minor_types, "Graduate/GASM",  "Grad Minors")
  )
}


# ── Cross-dept minor donut ────────────────────────────────────────────────────

#' Donut chart: what minors do your majors declare?
#'
#' Finds students who declare a major in dept_code, then identifies what
#' minors those same students have declared in OTHER departments. Surfaces
#' intellectual cross-pollination and student interests beyond the home unit.
#'
#' @param cedar_programs CEDAR programs data frame.
#' @param dept_code Department code string.
#' @param top_n Number of departments to show individually; remainder grouped
#'   as "Other" (default 8).
#' @return A plotly donut chart, or NULL if no cross-dept minor data found.
plot_cross_dept_minors <- function(cedar_programs, dept_code, top_n = 8) {
  message("[dept-dashboard.R] plot_cross_dept_minors for ", dept_code)

  # Students who have declared a major in this department
  dept_major_ids <- cedar_programs %>%
    dplyr::filter(
      department   == dept_code,
      program_type %in% c("Major", "Second Major")
    ) %>%
    dplyr::pull(student_id) %>%
    unique()

  if (length(dept_major_ids) == 0) {
    message("[dept-dashboard.R] No majors found for ", dept_code)
    return(NULL)
  }

  # What minors have those students declared in OTHER departments?
  cross_minors <- cedar_programs %>%
    dplyr::filter(
      student_id   %in% dept_major_ids,
      program_type %in% c("First Minor", "Second Minor"),
      department   != dept_code
    ) %>%
    dplyr::group_by(department) %>%
    dplyr::summarize(n_students = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(n_students))

  if (nrow(cross_minors) == 0) {
    message("[dept-dashboard.R] No cross-dept minors found for ", dept_code)
    return(NULL)
  }

  # Group tail into "Other"
  if (nrow(cross_minors) > top_n) {
    top    <- cross_minors[1:top_n, ]
    other  <- data.frame(department = "Other", n_students = sum(cross_minors$n_students[(top_n + 1):nrow(cross_minors)]))
    cross_minors <- dplyr::bind_rows(top, other)
  }

  total <- sum(cross_minors$n_students)
  cross_minors <- cross_minors %>%
    dplyr::mutate(
      pct   = round(n_students / total * 100, 1),
      label = paste0(department, " (", pct, "%)")
    )

  plotly::plot_ly(
    cross_minors,
    labels  = ~department,
    values  = ~n_students,
    type    = "pie",
    hole    = 0.5,
    textinfo = "label+percent",
    hovertemplate = paste0(
      "<b>%{label}</b><br>",
      "%{value} students<br>",
      "%{percent}<extra></extra>"
    )
  ) %>%
    plotly::layout(
      title       = list(text = paste0("Where ", dept_code, " Majors Also Minor"),
                         font = list(size = 15)),
      showlegend  = FALSE,
      margin      = list(t = 50, b = 10)
    )
}


# ── Enrollment momentum ───────────────────────────────────────────────────────

#' Classify courses by enrollment trend: growing vs. worth a look
#'
#' For each course in the department, computes a trend slope across available
#' terms and classifies into "growing", "stable", or "worth a look" (declining).
#' Returns a list of two data frames for dashboard display.
#'
#' @param cedar_sections CEDAR sections data frame.
#' @param dept_code Department code string.
#' @param n_terms Number of most-recent terms to use for trend (default 6).
#' @param threshold Minimum absolute slope to call a trend up or down (default 1).
#' @return Named list: growing (data frame), investigate (data frame),
#'   each with columns: subject_course, course_title, trend_slope, n_terms.
get_enrollment_momentum <- function(cedar_sections, dept_code, n_terms = 6, threshold = 1) {
  message("[dept-dashboard.R] get_enrollment_momentum for ", dept_code)

  enrl <- cedar_sections %>%
    dplyr::filter(
      department        == dept_code,
      crosslist_primary == TRUE
    ) %>%
    dplyr::group_by(subject_course, course_title, term) %>%
    dplyr::summarize(total_enrl = sum(total_enrl, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(subject_course, term)

  if (nrow(enrl) == 0) return(list(growing = NULL, investigate = NULL))

  # Compute trend per course using the last n_terms offerings
  course_trends <- enrl %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::arrange(term) %>%
    dplyr::slice_tail(n = n_terms) %>%
    dplyr::summarize(
      n_terms    = dplyr::n(),
      trend_slope = {
        vals <- total_enrl
        if (length(vals) >= 2) coef(lm(vals ~ seq_along(vals)))[2] else NA_real_
      },
      avg_enrl   = round(mean(total_enrl, na.rm = TRUE), 1),
      .groups    = "drop"
    ) %>%
    dplyr::filter(!is.na(trend_slope), n_terms >= 2) %>%
    dplyr::mutate(
      direction = dplyr::case_when(
        trend_slope >  threshold ~ "growing",
        trend_slope < -threshold ~ "investigate",
        TRUE                     ~ "stable"
      )
    )

  list(
    growing     = course_trends %>%
      dplyr::filter(direction == "growing") %>%
      dplyr::arrange(dplyr::desc(trend_slope)),
    investigate = course_trends %>%
      dplyr::filter(direction == "investigate") %>%
      dplyr::arrange(trend_slope)
  )
}


# ── Main dashboard entry point ────────────────────────────────────────────────

#' Build all data for the Explore Your Unit dashboard
#'
#' Lightweight alternative to create_dept_report_data(). Focused on visual
#' summary cards and discovery-oriented analytics rather than exhaustive tables.
#'
#' @param data_objects Named list containing cedar_programs, cedar_students,
#'   cedar_sections (same structure as used by dept-report.R).
#' @param opt Named list. Required: opt[["dept"]] — department code string.
#' @return Named list with:
#'   - dept_code, dept_name
#'   - headcount_summary (data frame)
#'   - plots$cross_dept_minors (plotly donut)
#'   - plots$credit_hours_by_level (plotly line chart)
#'   - enrollment_momentum (list: growing, investigate)
create_dept_dashboard_data <- function(data_objects, opt) {
  dept_raw <- opt[["dept"]]
  message("[dept-dashboard.R] Building dashboard for: ", dept_raw)

  cedar_programs <- data_objects[["cedar_programs"]]
  cedar_students <- data_objects[["cedar_students"]]
  cedar_sections <- data_objects[["cedar_sections"]]

  # Resolve HR org description (e.g. "AS Anthropology") to short dept code
  # (e.g. "ANTH") used in cedar_students and cedar_sections.
  # cedar_programs uses the full description; the other tables use short codes.
  if (exists("hr_org_desc_to_dept_map") && dept_raw %in% names(hr_org_desc_to_dept_map)) {
    dept_code <- hr_org_desc_to_dept_map[[dept_raw]]
    message("[dept-dashboard.R] Resolved '", dept_raw, "' -> '", dept_code, "'")
  } else {
    dept_code <- dept_raw
    message("[dept-dashboard.R] No mapping found, using raw value: ", dept_code)
  }

  dept_name <- if (exists("dept_code_to_name") && dept_code %in% names(dept_code_to_name)) {
    dept_code_to_name[[dept_code]]
  } else {
    dept_raw
  }

  result <- list(
    dept_code = dept_code,
    dept_raw  = dept_raw,
    dept_name = dept_name,
    plots     = list()
  )

  # cedar_programs uses dept_raw (full HR description)
  result$headcount_summary <-
    get_headcount_summary(cedar_programs, dept_raw)

  result$plots$cross_dept_minors <-
    plot_cross_dept_minors(cedar_programs, dept_raw)

  # cedar_students and cedar_sections use short dept_code
  result$plots$credit_hours_by_level <-
    plot_credit_hours_by_level(cedar_students, dept_code, n_years = 5)

  result$enrollment_momentum <-
    get_enrollment_momentum(cedar_sections, dept_code)

  message("[dept-dashboard.R] Dashboard data ready for ", dept_code)
  result
}
