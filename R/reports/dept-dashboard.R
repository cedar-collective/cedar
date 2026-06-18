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
#' - `plot_dept_student_donuts()` — 8 donuts: major + class standing by course level, current + 5yr avg
#' - `get_enrollment_momentum()` — courses sorted into growing vs. worth-a-look
#' - `create_dept_dashboard_data()` — main entry point called by server.R
#'
#' Data requirements (passed via data_objects):
#' - cedar_programs: student_id, term, dept_code, program_type, program_name
#' - cedar_students: student_id, term, department, level, credits, final_grade, major
#' - cedar_sections: term, department, subject_course, course_title, enrolled, crosslist_primary


# Topics courses have titles prefixed with "T:" — centralised so the pattern only lives in one place
is_topics_course <- function(course_title) {
  grepl("^T:", trimws(course_title))
}


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
    return(list(slope = NA_real_, direction = "unknown", arrow = "—"))
  }
  slope <- coef(lm(values ~ seq_along(values)))[2]
  direction <- dplyr::case_when(
    slope >  threshold ~ "up",
    slope < -threshold ~ "down",
    TRUE               ~ "stable"
  )
  arrow <- switch(direction, up = "↑", down = "↓", stable = "→", "—")
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
plot_credit_hours_by_level <- function(cedar_students, dept_code, n_years = 5, campus = NULL) {
  message("[dept-dashboard.R] plot_credit_hours_by_level for ", dept_code)

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  cutoff_year  <- current_year - (n_years - 1)

  ch <- cedar_students %>%
    dplyr::filter(
      department   == dept_code,
      final_grade  %in% passing_grades,
      level        %in% c("lower", "upper", "grad"),
      floor(term / 100) >= cutoff_year,
      if (!is.null(campus)) .data$campus %in% campus else TRUE
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

#' Summarize major and minor headcount with trend arrows and historical comparisons
#'
#' Returns a summary data frame with current counts, trend direction, and
#' headcount changes vs. 3 years ago and 6 years ago for undergrad/grad
#' majors and minors. Intended for display as stat cards on the dashboard.
#'
#' Year comparisons use annual average headcount (averaging all terms within
#' a calendar year) to smooth out seasonal variation and avoid single-term
#' anomalies. If no data exists for the target year, the comparison is NA.
#'
#' @param cedar_programs CEDAR programs data frame.
#' @param dept_code Department code string.
#' @param n_trend_terms Number of most-recent terms of each type to use for
#'   trend calculation (default 4 = last ~4 falls or springs).
#' @return Data frame with columns: group, current_count, trend_direction, arrow,
#'   count_3yr, count_6yr, change_3yr, change_6yr, pct_change_3yr, pct_change_6yr.
get_headcount_summary <- function(cedar_programs, dept_code, n_trend_terms = 4) {
  message("[dept-dashboard.R] get_headcount_summary for ", dept_code)

  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  summarize_group <- function(prog_data, program_types, level_filter, label, group_by_degree = FALSE) {
    df <- prog_data %>%
      dplyr::filter(
        dept_code     == .env$dept_code,
        program_type  %in% program_types,
        student_level == level_filter,
        !is.na(term)
      )
    if (group_by_degree) {
      df <- df %>% dplyr::group_by(term, degree) %>%
        dplyr::summarize(count = dplyr::n_distinct(student_id), .groups = "drop") %>%
        dplyr::arrange(term, degree)
    } else {
      df <- df %>% dplyr::group_by(term) %>%
        dplyr::summarize(count = dplyr::n_distinct(student_id), .groups = "drop") %>%
        dplyr::arrange(term)
    }

    if (nrow(df) == 0) {
      if (group_by_degree) {
        return(data.frame(
          group = paste(label, c("Masters", "PhD")), degree = c("Masters", "PhD"),
          current_count = 0,
          trend_direction = "unknown", arrow = "—",
          count_1yr = NA_real_, count_3yr = NA_real_, count_6yr = NA_real_,
          change_1yr = NA_integer_, change_3yr = NA_integer_, change_6yr = NA_integer_,
          pct_change_1yr = NA_integer_, pct_change_3yr = NA_integer_, pct_change_6yr = NA_integer_,
          stringsAsFactors = FALSE
        ))
      } else {
        return(data.frame(
          group = label, current_count = 0,
          trend_direction = "unknown", arrow = "—",
          count_1yr = NA_real_, count_3yr = NA_real_, count_6yr = NA_real_,
          change_1yr = NA_integer_, change_3yr = NA_integer_, change_6yr = NA_integer_,
          pct_change_1yr = NA_integer_, pct_change_3yr = NA_integer_, pct_change_6yr = NA_integer_,
          stringsAsFactors = FALSE
        ))
      }
    }

    # Group by degree for grad majors
    if (group_by_degree) {
      out <- lapply(unique(df$degree), function(deg) {
        ddeg <- df[df$degree == deg, ]
        # Display count: most recent term.
        current_count <- dplyr::last(ddeg$count)
        trend <- compute_trend(ddeg$count)
        # Trend percentages: fall-to-fall only.
        deg_falls <- dplyr::filter(ddeg, term %% 100L == 80L)
        if (nrow(deg_falls) > 0) {
          latest_fall      <- max(deg_falls$term)
          latest_fall_year <- floor(latest_fall / 100L)
          latest_fall_count <- deg_falls$count[deg_falls$term == latest_fall]
          get_fall_count <- function(target_year) {
            target_term <- as.integer(target_year) * 100L + 80L
            row <- deg_falls[deg_falls$term == target_term, ]
            if (nrow(row) == 0) NA_real_ else row$count
          }
          count_1yr <- get_fall_count(latest_fall_year - 1L)
          count_3yr <- get_fall_count(latest_fall_year - 3L)
          count_6yr <- get_fall_count(latest_fall_year - 6L)
        } else {
          latest_fall_count <- current_count
          count_1yr <- NA_real_; count_3yr <- NA_real_; count_6yr <- NA_real_
        }
        change_1yr <- if (!is.na(count_1yr)) as.integer(round(latest_fall_count - count_1yr)) else NA_integer_
        change_3yr <- if (!is.na(count_3yr)) as.integer(round(latest_fall_count - count_3yr)) else NA_integer_
        change_6yr <- if (!is.na(count_6yr)) as.integer(round(latest_fall_count - count_6yr)) else NA_integer_
        pct_change_1yr <- if (!is.na(count_1yr) && count_1yr > 0)
          as.integer(round((latest_fall_count - count_1yr) / count_1yr * 100)) else NA_integer_
        pct_change_3yr <- if (!is.na(count_3yr) && count_3yr > 0)
          as.integer(round((latest_fall_count - count_3yr) / count_3yr * 100)) else NA_integer_
        pct_change_6yr <- if (!is.na(count_6yr) && count_6yr > 0)
          as.integer(round((latest_fall_count - count_6yr) / count_6yr * 100)) else NA_integer_
        data.frame(
          group           = paste(label, deg),
          degree          = deg,
          current_count   = current_count,
          trend_direction = trend$direction,
          arrow           = trend$arrow,
          count_1yr       = count_1yr,
          count_3yr       = count_3yr,
          count_6yr       = count_6yr,
          change_1yr      = change_1yr,
          change_3yr      = change_3yr,
          change_6yr      = change_6yr,
          pct_change_1yr  = pct_change_1yr,
          pct_change_3yr  = pct_change_3yr,
          pct_change_6yr  = pct_change_6yr,
          stringsAsFactors = FALSE
        )
      })
      return(do.call(rbind, out))
    } else {
      # Display count: most recent term (may be spring — shows current snapshot).
      current_count <- dplyr::last(df$count)
      trend <- compute_trend(df$count)
      # Trend percentages: fall-to-fall only, to avoid fall/spring seasonal noise.
      # Uses the most recent fall as the "from" point, regardless of current term type.
      df_falls <- dplyr::filter(df, term %% 100L == 80L)
      if (nrow(df_falls) > 0) {
        latest_fall      <- max(df_falls$term)
        latest_fall_year <- floor(latest_fall / 100L)
        latest_fall_count <- df_falls$count[df_falls$term == latest_fall]
        get_fall_count <- function(target_year) {
          target_term <- as.integer(target_year) * 100L + 80L
          row <- df_falls[df_falls$term == target_term, ]
          if (nrow(row) == 0) NA_real_ else row$count
        }
        count_1yr <- get_fall_count(latest_fall_year - 1L)
        count_3yr <- get_fall_count(latest_fall_year - 3L)
        count_6yr <- get_fall_count(latest_fall_year - 6L)
      } else {
        latest_fall_count <- current_count
        count_1yr <- NA_real_; count_3yr <- NA_real_; count_6yr <- NA_real_
      }
      change_1yr <- if (!is.na(count_1yr)) as.integer(round(latest_fall_count - count_1yr)) else NA_integer_
      change_3yr <- if (!is.na(count_3yr)) as.integer(round(latest_fall_count - count_3yr)) else NA_integer_
      change_6yr <- if (!is.na(count_6yr)) as.integer(round(latest_fall_count - count_6yr)) else NA_integer_
      pct_change_1yr <- if (!is.na(count_1yr) && count_1yr > 0)
        as.integer(round((latest_fall_count - count_1yr) / count_1yr * 100)) else NA_integer_
      pct_change_3yr <- if (!is.na(count_3yr) && count_3yr > 0)
        as.integer(round((latest_fall_count - count_3yr) / count_3yr * 100)) else NA_integer_
      pct_change_6yr <- if (!is.na(count_6yr) && count_6yr > 0)
        as.integer(round((latest_fall_count - count_6yr) / count_6yr * 100)) else NA_integer_
      data.frame(
        group           = label,
        current_count   = current_count,
        trend_direction = trend$direction,
        arrow           = trend$arrow,
        count_1yr       = count_1yr,
        count_3yr       = count_3yr,
        count_6yr       = count_6yr,
        change_1yr      = change_1yr,
        change_3yr      = change_3yr,
        change_6yr      = change_6yr,
        pct_change_1yr  = pct_change_1yr,
        pct_change_3yr  = pct_change_3yr,
        pct_change_6yr  = pct_change_6yr,
        stringsAsFactors = FALSE
      )
    }
  }

  # Degree-type breakdown uses only primary majors so the degree reflects the
  # dept's own degrees, not degrees from other depts held by double-majors.
  primary_major_types <- c("Major")

  dplyr::bind_rows(
    # Undergrad total card (prominent) — all UG majors incl. second majors
    summarize_group(cedar_programs, major_types, "Undergraduate", "Undergrad Majors (incl. 2nd)") %>%
      dplyr::mutate(tier = "undergrad", is_total = TRUE),
    # Undergrad degree-type cards (BA, BS, BFA, …) — primary majors only
    summarize_group(cedar_programs, primary_major_types, "Undergraduate", "UG", group_by_degree = TRUE) %>%
      dplyr::mutate(tier = "undergrad", is_total = FALSE, group = degree),
    # Second major card — students for whom this dept is a second major
    summarize_group(cedar_programs, c("Second Major"), "Undergraduate", "2nd Major") %>%
      dplyr::mutate(tier = "undergrad", is_total = FALSE, group = "2nd Major"),
    # Grad total card (prominent) — all grad majors incl. second majors
    summarize_group(cedar_programs, major_types, "Graduate/GASM", "Grad Majors (incl. 2nd)") %>%
      dplyr::mutate(tier = "grad", is_total = TRUE),
    # Grad degree-type cards (PhD, MA, MS, …) — primary majors only
    summarize_group(cedar_programs, primary_major_types, "Graduate/GASM", "Grad", group_by_degree = TRUE) %>%
      dplyr::mutate(tier = "grad", is_total = FALSE, group = degree)
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
      dept_code    == .env$dept_code,
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
      dept_code    != .env$dept_code
    ) %>%
    dplyr::group_by(dept_code) %>%
    dplyr::summarize(n_students = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(n_students))

  if (nrow(cross_minors) == 0) {
    message("[dept-dashboard.R] No cross-dept minors found for ", dept_code)
    return(NULL)
  }

  # Group tail into "Other"
  if (nrow(cross_minors) > top_n) {
    top    <- cross_minors[1:top_n, ]
    other  <- data.frame(dept_code = "Other", n_students = sum(cross_minors$n_students[(top_n + 1):nrow(cross_minors)]))
    cross_minors <- dplyr::bind_rows(top, other)
  }

  total <- sum(cross_minors$n_students)
  cross_minors <- cross_minors %>%
    dplyr::mutate(
      pct   = round(n_students / total * 100, 1),
      label = paste0(dept_code, " (", pct, "%)")
    )

  plotly::plot_ly(
    cross_minors,
    labels  = ~dept_code,
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


# ── Majors of dept minors donut ───────────────────────────────────────────────

#' Donut chart: what majors do students who minor in this dept declare?
#'
#' Inverse of plot_cross_dept_minors. Finds students who declare a minor in
#' dept_code, then identifies what majors those students hold in OTHER
#' departments. Surfaces which programs feed students into this dept as a minor.
#'
#' @param cedar_programs CEDAR programs data frame.
#' @param dept_code Department code string.
#' @param top_n Number of departments to show individually; remainder grouped
#'   as "Other" (default 8).
#' @return A plotly donut chart, or NULL if no data found.
plot_majors_with_dept_minor <- function(cedar_programs, dept_code, top_n = 8) {
  message("[dept-dashboard.R] plot_majors_with_dept_minor for ", dept_code)

  dept_minor_ids <- cedar_programs %>%
    dplyr::filter(
      dept_code    == .env$dept_code,
      program_type %in% c("First Minor", "Second Minor")
    ) %>%
    dplyr::pull(student_id) %>%
    unique()

  if (length(dept_minor_ids) == 0) {
    message("[dept-dashboard.R] No minors found for ", dept_code)
    return(NULL)
  }

  cross_majors <- cedar_programs %>%
    dplyr::filter(
      student_id   %in% dept_minor_ids,
      program_type %in% c("Major", "Second Major"),
      dept_code    != .env$dept_code
    ) %>%
    dplyr::group_by(dept_code) %>%
    dplyr::summarize(n_students = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(n_students))

  if (nrow(cross_majors) == 0) {
    message("[dept-dashboard.R] No cross-dept majors found for ", dept_code)
    return(NULL)
  }

  if (nrow(cross_majors) > top_n) {
    top    <- cross_majors[1:top_n, ]
    other  <- data.frame(dept_code = "Other",
                         n_students = sum(cross_majors$n_students[(top_n + 1):nrow(cross_majors)]))
    cross_majors <- dplyr::bind_rows(top, other)
  }

  total <- sum(cross_majors$n_students)
  cross_majors <- cross_majors %>%
    dplyr::mutate(
      pct   = round(n_students / total * 100, 1),
      label = paste0(dept_code, " (", pct, "%)")
    )

  plotly::plot_ly(
    cross_majors,
    labels  = ~dept_code,
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
      title      = list(text = paste0("Who Minors in ", dept_code),
                        font = list(size = 15)),
      showlegend = FALSE,
      margin     = list(t = 50, b = 10)
    )
}


# ── Enrollment momentum ───────────────────────────────────────────────────────

#' Classify courses by enrollment trend: growing vs. worth a look
#'
#' For each course in the department, computes a trend slope across available
#' terms and classifies into "growing", "stable", or "worth a look" (declining).
#' Adds early/recent average enrollment and absolute/percent change so the
#' display can show *how much* things have changed, not just that they have.
#'
#' Accepts pre-built course enrollment history from
#' \code{get_dept_course_enrl_history()} (recommended, avoids re-querying
#' cedar_sections) or falls back to building it from cedar_sections directly.
#'
#' @param course_history Data frame returned by \code{get_dept_course_enrl_history()}.
#'   Columns: subject_course, course_title, term, enrolled.
#' @param n_terms Number of most-recent terms per course to use for trend (default 6).
#' @param threshold Minimum absolute slope to call a trend up or down (default 1).
#' @return Named list: growing (data frame), investigate (data frame),
#'   each with columns: subject_course, course_title, n_terms, avg_enrl,
#'   avg_enrl_early, avg_enrl_recent, change_abs, change_pct, trend_slope.
get_enrollment_momentum <- function(course_history, n_terms = 6, threshold = 1) {
  message("[dept-dashboard.R] get_enrollment_momentum")

  if (is.null(course_history) || nrow(course_history) == 0) {
    return(list(growing = NULL, investigate = NULL))
  }

  # Compute trend per course using the last n_terms offerings.
  # avg_enrl_early = avg of first half of the window (baseline)
  # avg_enrl_recent = avg of second half (current)
  course_trends <- course_history %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::arrange(term) %>%
    dplyr::slice_tail(n = n_terms) %>%
    dplyr::summarize(
      n_terms          = dplyr::n(),
      avg_enrl         = round(mean(enrolled, na.rm = TRUE), 1),
      avg_enrl_early   = round(mean(utils::head(enrolled, max(1, floor(dplyr::n() / 2))),
                                   na.rm = TRUE), 1),
      avg_enrl_recent  = round(mean(utils::tail(enrolled, max(1, ceiling(dplyr::n() / 2))),
                                   na.rm = TRUE), 1),
      trend_slope      = {
        vals <- enrolled
        if (length(vals) >= 2) coef(lm(vals ~ seq_along(vals)))[2] else NA_real_
      },
      .groups = "drop"
    ) %>%
    dplyr::filter(!is.na(trend_slope), n_terms >= 2) %>%
    dplyr::mutate(
      change_abs  = as.integer(round(avg_enrl_recent - avg_enrl_early)),
      change_pct  = dplyr::if_else(
        avg_enrl_early > 0,
        as.integer(round((avg_enrl_recent - avg_enrl_early) / avg_enrl_early * 100)),
        NA_integer_
      ),
      direction   = dplyr::case_when(
        trend_slope >  threshold ~ "growing",
        trend_slope < -threshold ~ "investigate",
        TRUE                     ~ "stable"
      )
    )

  list(
    growing     = course_trends %>%
      dplyr::filter(direction == "growing") %>%
      dplyr::arrange(dplyr::desc(change_pct)),
    investigate = course_trends %>%
      dplyr::filter(direction == "investigate") %>%
      dplyr::arrange(change_pct)
  )
}


# ── New courses ───────────────────────────────────────────────────────────────

#' Find courses first offered within the last N years
#'
#' Uses department course enrollment history to identify courses whose first
#' appearance in the data falls within the recency window. Useful for surfacing
#' new additions to the curriculum on the dashboard.
#'
#' @param course_history Data frame returned by \code{get_dept_course_enrl_history()}.
#' @param new_within_years Courses first offered within this many years count as
#'   "new" (default 2).
#' @return Data frame with columns: subject_course, course_title, first_term,
#'   last_term, n_terms, avg_enrl. Ordered by first_term ascending.
#'   Returns NULL if no new courses found.
get_new_courses <- function(course_history, new_within_years = 2) {
  message("[dept-dashboard.R] get_new_courses (within ", new_within_years, " years)")

  if (is.null(course_history) || nrow(course_history) == 0) return(NULL)

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  # Convert year cutoff to a term lower bound (e.g., 2 years ago → 202200)
  new_term_cutoff <- (current_year - new_within_years) * 100

  result <- course_history %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::summarize(
      first_term = min(term),
      last_term  = max(term),
      n_terms    = dplyr::n(),
      avg_enrl   = round(mean(enrolled, na.rm = TRUE), 1),
      .groups    = "drop"
    ) %>%
    dplyr::filter(first_term >= new_term_cutoff) %>%
    dplyr::arrange(first_term)

  if (nrow(result) == 0) NULL else result
}


# ── Dormant courses ───────────────────────────────────────────────────────────

#' Find courses not taught recently but with prior history
#'
#' Identifies courses that have not appeared in the most-recent N terms of the
#' history window but were offered at least \code{min_history_terms} times
#' before that. Surfaces courses that may have been quietly dropped, suspended,
#' or are overdue for a revival.
#'
#' @param course_history Data frame returned by \code{get_dept_course_enrl_history()}.
#' @param dormant_terms Number of most-recent terms that define the "recent"
#'   window. A course absent from all of these is considered dormant (default 4).
#' @param min_history_terms Minimum prior offerings required to qualify
#'   (avoids flagging one-off experimental courses, default 2).
#' @return Data frame with columns: subject_course, course_title, last_term,
#'   first_term, n_terms, avg_enrl. Ordered by last_term descending (most
#'   recently dormant first). Returns NULL if no dormant courses found.
get_dormant_courses <- function(course_history, dormant_terms = 4, min_history_terms = 2) {
  message("[dept-dashboard.R] get_dormant_courses (absent from last ", dormant_terms, " terms)")

  if (is.null(course_history) || nrow(course_history) == 0) return(NULL)

  all_terms <- sort(unique(course_history$term))
  if (length(all_terms) <= dormant_terms) return(NULL)

  # The cutoff is the oldest of the recent terms; dormant courses must have
  # their last offering BEFORE this term.
  cutoff_term <- all_terms[length(all_terms) - dormant_terms + 1]

  result <- course_history %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::summarize(
      last_term  = max(term),
      first_term = min(term),
      n_terms    = dplyr::n(),
      avg_enrl   = round(mean(enrolled, na.rm = TRUE), 1),
      .groups    = "drop"
    ) %>%
    dplyr::filter(n_terms >= min_history_terms, last_term < cutoff_term) %>%
    dplyr::arrange(dplyr::desc(last_term))

  if (nrow(result) == 0) NULL else result
}


# ── Current-term snapshot functions ──────────────────────────────────────────
# These replace the historical trend lists on the dashboard with a snapshot
# of *right now*: which courses are running above/below their historical
# average, what's new this term, and what ran last year but isn't running now.
# Historical trend lists (growing/declining) live on the Enrollment page.

#' Compare current-term enrollment to historical averages
#'
#' For each course offered in \code{current_term}, computes the historical
#' average enrollment across prior terms of the \emph{same term type} (fall vs.
#' spring vs. summer) and flags courses running above or below that baseline.
#' Requires at least 2 prior same-type offerings for a meaningful comparison.
#'
#' Term type is derived from the term code's last two digits: 10 = spring,
#' 60 = summer, 80 = fall. This ensures fall courses are only compared against
#' prior falls, not against spring or summer offerings.
#'
#' @param course_history Data frame from \code{get_dept_course_enrl_history()}.
#' @param current_term Integer term code (e.g. \code{cedar_current_term}).
#' @return Named list: \code{above} and \code{below}, each a data frame with
#'   columns: subject_course, course_title, enrolled, hist_avg_enrl,
#'   diff, pct_diff. Returns \code{list(above = NULL, below = NULL)} if no data.
get_current_enrl_vs_avg <- function(course_history, current_term) {
  message("[dept-dashboard.R] get_current_enrl_vs_avg for term ", current_term)

  if (is.null(course_history) || nrow(course_history) == 0) {
    return(list(above = NULL, below = NULL))
  }

  current <- course_history %>% dplyr::filter(term == current_term)
  if (nrow(current) == 0) {
    message("[dept-dashboard.R] No courses found for current term ", current_term)
    return(list(above = NULL, below = NULL))
  }

  # Derive season from term code (last two digits: 10=spring, 60=summer, 80=fall)
  # and restrict prior history to the same season so fall compares to prior falls, etc.
  current_season <- current_term %% 100

  # Use total_enrl (crosslist-adjusted) so history and current-term comparison
  # are consistent with the total_enrl label shown in the dashboard display.
  # Using enrolled (home-section-only) would give a correct internal diff but
  # a label mismatch for crosslisted courses (e.g. home enrolled=8, total=15).
  hist_avg <- course_history %>%
    dplyr::filter(term != current_term, term %% 100 == current_season) %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::summarize(
      hist_avg_enrl = round(mean(total_enrl, na.rm = TRUE), 1),
      n_hist        = dplyr::n(),
      .groups       = "drop"
    ) %>%
    dplyr::filter(n_hist >= 2)  # need at least 2 prior same-season terms for a meaningful avg

  comparison <- current %>%
    dplyr::inner_join(hist_avg, by = c("subject_course", "course_title")) %>%
    dplyr::mutate(
      diff     = as.integer(round(total_enrl - hist_avg_enrl)),
      pct_diff = dplyr::if_else(
        hist_avg_enrl > 0,
        as.integer(round(diff / hist_avg_enrl * 100)),
        NA_integer_
      )
    ) %>%
    dplyr::filter(diff != 0)

  list(
    above = comparison %>% dplyr::filter(diff > 0) %>% dplyr::arrange(dplyr::desc(pct_diff)),
    below = comparison %>% dplyr::filter(diff < 0) %>% dplyr::arrange(pct_diff)
  )
}


#' Find courses whose course number has never appeared before
#'
#' Identifies courses in \code{current_term} whose \code{subject_course} has
#' no prior appearance in the history window — genuinely new to the curriculum
#' (or returning after a gap long enough to fall outside the history window).
#'
#' For regular courses, matches on \code{subject_course}. For topics courses,
#' matches on \code{(subject_course, course_title)} — a new title under an
#' established course number counts as a new course. Recurring topics are also
#' surfaced separately by \code{get_repeated_topics_courses()}.
#'
#' @param course_history Data frame from \code{get_dept_course_enrl_history()}.
#' @param current_term Integer term code.
#' @return Data frame with columns: subject_course, course_title, enrolled,
#'   slot_avg_enrl (NA for non-topics; average enrollment across all prior T:
#'   offerings under same course number), n_slot_prior (count of those prior
#'   offerings). Ordered alphabetically. Returns NULL if none found.
get_new_this_term <- function(course_history, current_term) {
  message("[dept-dashboard.R] get_new_this_term for term ", current_term)

  if (is.null(course_history) || nrow(course_history) == 0) {
    message("[dept-dashboard.R] get_new_this_term: no course history (returning NULL)")
    return(NULL)
  }

  current_courses <- course_history %>%
    dplyr::filter(term == current_term) %>%
    dplyr::select(subject_course, course_title, enrolled, dplyr::any_of("total_enrl"))

  if (nrow(current_courses) == 0) {
    message("[dept-dashboard.R] get_new_this_term: no courses in current term ", current_term, " (returning NULL)")
    return(NULL)
  }

  prior_history <- course_history %>% dplyr::filter(term != current_term)
  prior_subjects <- prior_history %>% dplyr::distinct(subject_course)

  # Regular courses: new if subject_course never appeared before (ignores title drift).
  genuinely_new <- current_courses %>%
    dplyr::anti_join(prior_subjects, by = "subject_course") %>%
    dplyr::mutate(slot_avg_enrl = NA_real_, n_slot_prior = NA_integer_)

  # Topics courses (T: prefix): new if this exact (subject_course, course_title)
  # has never appeared before — each distinct topic is its own course.
  # Almost all genuinely new curriculum additions arrive as topics first.
  topics_in_current <- current_courses %>%
    dplyr::semi_join(prior_subjects, by = "subject_course") %>%
    dplyr::filter(is_topics_course(course_title))

  topics_new <- NULL
  if (nrow(topics_in_current) > 0) {
    prior_topic_keys <- prior_history %>%
      dplyr::filter(is_topics_course(course_title)) %>%
      dplyr::distinct(subject_course, course_title)
    topics_new <- topics_in_current %>%
      dplyr::anti_join(prior_topic_keys, by = c("subject_course", "course_title"))

    # Slot average: avg enrollment across ALL prior T: offerings for same course number,
    # regardless of title — tells the chair what demand for this slot typically looks like.
    if (nrow(topics_new) > 0) {
      slot_avgs <- prior_history %>%
        dplyr::filter(is_topics_course(course_title)) %>%
        dplyr::group_by(subject_course) %>%
        dplyr::summarize(
          slot_avg_enrl = round(mean(enrolled, na.rm = TRUE), 1),
          n_slot_prior  = dplyr::n(),
          .groups = "drop"
        )
      topics_new <- topics_new %>%
        dplyr::left_join(slot_avgs, by = "subject_course")
    } else {
      topics_new <- NULL
    }
  }

  result <- dplyr::bind_rows(genuinely_new, topics_new) %>%
    dplyr::arrange(subject_course)

  if (nrow(result) == 0) NULL else result
}


# ── Term label helper ────────────────────────────────────────────────────────

#' Convert a term integer to a short display label
#'
#' NOTE: This is intentionally separate from term_code_to_str() in utils.R.
#' term_code_to_str() returns full strings like "Fall 2025" / "Spring 2026" via
#' a lookup table (num.labs / term_text). term_label() returns compact labels
#' like "F25" / "Sp26" used in sparkline tooltips and recent-history strings
#' where space is limited and brevity improves readability.
#'
#' @param term Integer term code (e.g. 202610, 202580).
#' @return Character string like "Sp26", "F25", "Su25".
term_label <- function(term) {
  season <- term %% 100
  yr     <- (term %/% 100) %% 100
  prefix <- switch(as.character(season), "10" = "Sp", "60" = "Su", "80" = "F", "?")
  paste0(prefix, yr)
}


# Format last N offerings of each course as a compact history string, e.g. "F24:28 • Sp24:31 • F23:25"
# topics_only: if TRUE, restrict to courses with "T:" titles (topics courses).
# Using an explicit flag instead of ... avoids NSE scoping issues when course_title
# is only available as a data column, not a standalone variable in the caller's scope.
.recent_history_str <- function(course_history, current_term, topics_only = FALSE) {
  data <- course_history %>% dplyr::filter(term != current_term)
  if (topics_only) data <- data %>% dplyr::filter(is_topics_course(course_title))
  data %>%
    dplyr::arrange(dplyr::desc(term)) %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::slice_head(n = 3) %>%
    dplyr::summarize(
      recent_history = paste(paste0(sapply(term, term_label), ":", enrolled), collapse = " • "),
      .groups = "drop"
    )
}


#' Find home-dept courses offered N years ago that are not running this term
#'
#' Compares the same term type \code{years_back} years prior and returns courses
#' that appeared then but are absent from \code{current_term}. Surfaces possible
#' scheduling gaps, sabbaticals, or quietly dropped courses.
#'
#' Crosslist filtering (home-dept only) is applied upstream in
#' \code{get_dept_course_enrl_history()} via \code{crosslist = "home"} — this
#' function trusts that \code{course_history} already contains only home-dept
#' sections and does no additional crosslist logic.
#'
#' @param course_history Data frame from \code{get_dept_course_enrl_history()}.
#' @param current_term Integer term code.
#' @param years_back Number of years back to compare (default 2). Term code
#'   arithmetic: \code{current_term - years_back * 100}.
#' @return Data frame with columns: subject_course, course_title, prior_enrl
#'   (enrollment in the comparison term), recent_history (last 3 prior
#'   appearances as a formatted string, e.g. "F24:28 • Sp22:31 • F20:24").
#'   Returns NULL if none found or if the comparison term has no data.
get_missing_from_earlier <- function(course_history, current_term, years_back = 2) {
  prior_term <- current_term - (years_back * 100L)
  message("[dept-dashboard.R] get_missing_from_earlier: comparing ",
          current_term, " vs ", prior_term, " (", years_back, " years back)")

  if (is.null(course_history) || nrow(course_history) == 0) {
    message("[dept-dashboard.R] get_missing_from_earlier: no course history (returning NULL)")
    return(NULL)
  }

  comparison_term_data <- course_history %>%
    dplyr::filter(term == prior_term) %>%
    dplyr::select(subject_course, course_title, prior_enrl = enrolled)

  if (nrow(comparison_term_data) == 0) {
    message("[dept-dashboard.R] No data for comparison term ", prior_term)
    return(NULL)
  }

  current_course_keys <- course_history %>%
    dplyr::filter(term == current_term) %>%
    dplyr::distinct(subject_course, course_title)

  result <- comparison_term_data %>%
    dplyr::anti_join(current_course_keys, by = c("subject_course", "course_title")) %>%
    dplyr::arrange(subject_course)

  if (nrow(result) == 0) {
    message("[dept-dashboard.R] get_missing_from_earlier: no courses missing from earlier term (returning NULL)")
    return(NULL)
  }

  # Add recent_history: last 3 prior appearances per course across all history
  recent <- .recent_history_str(course_history, current_term)

  result %>% dplyr::left_join(recent, by = c("subject_course", "course_title"))
}


# ── Headcount time series for sparkline ──────────────────────────────────────

#' Per-term headcount series for sparkline display
#'
#' Returns a tidy data frame of student counts by term for each headcount group
#' (UG Majors, UG Minors, Grad Majors, Grad Minors). Summer terms are excluded
#' so the chart stays readable. Intended as the data source for
#' \code{make_headcount_sparklines()} in headcount.R.
#'
#' @param cedar_programs CEDAR programs data frame.
#' @param dept_raw Department value as it appears in cedar_programs$department
#'   (the full HR org description, e.g. "AS History").
#' @return Data frame with columns: term, group, student_level, program_cat, count.
#'   Returns NULL if no data found.
get_headcount_series <- function(cedar_programs, dept_code) {
  message("[dept-dashboard.R] get_headcount_series for ", dept_code)

  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  df <- cedar_programs %>%
    dplyr::filter(
      dept_code == .env$dept_code,
      program_type %in% c(major_types, minor_types),
      term %% 100 != 60  # exclude summer
    ) %>%
    dplyr::mutate(
      program_cat  = dplyr::if_else(program_type %in% major_types, "Majors", "Minors"),
      student_level_clean = dplyr::if_else(
        grepl("^Grad", student_level, ignore.case = TRUE), "Graduate", "Undergraduate"
      ),
      group = paste(student_level_clean, program_cat)
    ) %>%
    dplyr::group_by(term, group, student_level_clean, program_cat) %>%
    dplyr::summarize(count = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::arrange(term)

  if (nrow(df) == 0) NULL else df
}


# ── Repeated topics courses ───────────────────────────────────────────────────

#' Find topics courses running this term that have been offered before
#'
#' Returns "T:" courses currently running that have appeared under the same
#' (subject_course, course_title) key at least \code{min_prior} times in prior
#' terms. Surfaces recurring topics — established enough to have a track record
#' but still rotating content.
#'
#' @param course_history Data frame from \code{get_dept_course_enrl_history()}.
#' @param current_term Integer term code.
#' @param min_prior Minimum prior offerings required (default 2).
#' @return Data frame with columns: subject_course, course_title, enrolled,
#'   prior_offerings, avg_prior_enrl. Returns NULL if none found.
get_repeated_topics_courses <- function(course_history, current_term, min_prior = 2) {
  message("[dept-dashboard.R] get_repeated_topics_courses for term ", current_term)

  if (is.null(course_history) || nrow(course_history) == 0) {
    message("[dept-dashboard.R] get_repeated_topics_courses: no course history (returning NULL)")
    return(NULL)
  }

  current_topics <- course_history %>%
    dplyr::filter(term == current_term, is_topics_course(course_title)) %>%
    dplyr::select(subject_course, course_title, enrolled, dplyr::any_of("total_enrl"))

  if (nrow(current_topics) == 0) {
    message("[dept-dashboard.R] get_repeated_topics_courses: no topics courses in current term ", current_term, " (returning NULL)")
    return(NULL)
  }

  prior_counts <- course_history %>%
    dplyr::filter(term != current_term, is_topics_course(course_title)) %>%
    dplyr::group_by(subject_course, course_title) %>%
    dplyr::summarize(
      prior_offerings  = dplyr::n(),
      avg_prior_enrl   = round(mean(enrolled, na.rm = TRUE), 1),
      .groups          = "drop"
    ) %>%
    dplyr::filter(prior_offerings >= min_prior)

  result <- current_topics %>%
    dplyr::inner_join(prior_counts, by = c("subject_course", "course_title")) %>%
    dplyr::arrange(dplyr::desc(prior_offerings), subject_course)

  if (nrow(result) == 0) {
    message("[dept-dashboard.R] get_repeated_topics_courses: no topics courses meet min_prior threshold (returning NULL)")
    return(NULL)
  }

  # Add last 3 prior appearances with enrollment (mirrors get_missing_from_earlier)
  recent <- .recent_history_str(course_history, current_term, topics_only = TRUE)

  result %>% dplyr::left_join(recent, by = c("subject_course", "course_title"))
}


# ── Diagnostic helper ────────────────────────────────────────────────────────

#' Diagnose why courses are flagged as "new this term"
#'
#' For each course returned by \code{get_new_this_term()}, prints all
#' course_title values that appear for that subject_course across all terms
#' in the history window. Reveals title-string mismatches (the most common
#' cause of false positives) and confirms whether prior-term records exist.
#'
#' Call this from the server during debugging when common courses appear as new:
#' \code{diagnose_new_this_term(course_history, current_term)}
#'
#' @param course_history Data frame from \code{get_dept_course_enrl_history()}.
#' @param current_term Integer term code.
#' @return Invisible NULL. Diagnosis printed via message().
diagnose_new_this_term <- function(course_history, current_term) {
  new_courses <- get_new_this_term(course_history, current_term)

  if (is.null(new_courses) || nrow(new_courses) == 0) {
    message("[diagnose_new_this_term] No new courses flagged.")
    return(invisible(NULL))
  }

  message("[diagnose_new_this_term] ", nrow(new_courses),
          " course(s) flagged as new in term ", current_term, ":")

  for (i in seq_len(nrow(new_courses))) {
    sc <- new_courses$subject_course[i]
    ct <- new_courses$course_title[i]
    message("\n  Flagged: ", sc, " | '", ct, "'")

    all_titles <- course_history %>%
      dplyr::filter(subject_course == sc) %>%
      dplyr::distinct(term, course_title) %>%
      dplyr::arrange(term)

    if (nrow(all_titles) == 0) {
      message("    -> No history at all for ", sc, " in this window")
    } else {
      for (j in seq_len(nrow(all_titles))) {
        t     <- all_titles$term[j]
        title <- all_titles$course_title[j]
        exact <- title == ct
        message("    term=", t, " | '", title, "'",
                if (exact) "  [EXACT MATCH]" else "")
      }
      if (!any(all_titles$course_title == ct & all_titles$term != current_term)) {
        message("    -> No prior term has this exact title — likely a title string change")
      }
    }
  }

  invisible(NULL)
}


# ── Drop rate stats for current term ─────────────────────────────────────────

#' Compare current-term drop rates to historical averages
#'
#' For each course offered in \code{current_term}, computes early drop (DR) and
#' late drop (DG/DW) rates as a percentage of total class list, then compares
#' each course against (a) its own historical term-type average and (b) the
#' department-wide average for the same term type.
#'
#' Reuses \code{calc_cl_enrls()} and \code{filter_class_list()} from the
#' existing Cedar infrastructure. Uses rate (drops / class list total) rather
#' than raw counts so courses of different sizes are comparable.
#'
#' Requires at least 2 prior offerings of the same term type per course to
#' compute a meaningful historical baseline.
#'
#' @param cedar_students CEDAR student class list data frame.
#' @param cedar_sections CEDAR sections data frame (used for course titles).
#' @param dept_code Short department code string (e.g., "HIST").
#' @param current_term Integer term code (e.g. \code{cedar_current_term}).
#' @return Named list with two elements, each a named list of \code{above},
#'   \code{below}, and \code{dept_avg_rate}:
#'   \itemize{
#'     \item \code{early_drops} — pre-census (DR) drop rate comparison
#'     \item \code{late_drops}  — post-census (DG/DW) drop rate comparison
#'   }
#'   Columns in above/below data frames: subject_course, course_title,
#'   early_rate (or late_rate), hist_early_rate (or hist_late_rate),
#'   dept_avg_rate, diff. Returns NULL elements if insufficient data.
get_dept_drop_stats <- function(cedar_students, cedar_sections, dept_code, current_term,
                                campus = NULL, min_cl_total = 10, min_drops = 3,
                                min_abs_diff = 5) {
  message("[dept-dashboard.R] get_dept_drop_stats for ", dept_code, " term ", current_term)

  cl_opt <- list(dept = dept_code)
  if (!is.null(campus)) cl_opt$course_campus <- campus
  dept_students <- filter_class_list(cedar_students, cl_opt)
  if (is.null(dept_students) || nrow(dept_students) == 0) {
    return(list(early_drops = NULL, late_drops = NULL))
  }

  # Restrict to home-dept CRNs only — exclude CRNs where this dept is a crosslist
  # partner. Mirrors the crosslist_role filter in get_dept_course_enrl_history.
  if ("crosslist_role" %in% names(cedar_sections)) {
    home_crns <- cedar_sections %>%
      dplyr::filter(
        department == dept_code,
        is.na(crosslist_role) | crosslist_role == "home"
      ) %>%
      dplyr::pull(crn) %>%
      unique()
    dept_students <- dept_students %>% dplyr::filter(crn %in% home_crns)
    if (nrow(dept_students) == 0) return(list(early_drops = NULL, late_drops = NULL))
  }

  # Get course level (lower/upper/grad) from current-term student data.
  # Use the modal level per course — stable since course numbers don't typically
  # change division across terms.
  course_levels <- dept_students %>%
    dplyr::filter(term == current_term, !is.na(level), level != "") %>%
    dplyr::count(subject_course, level) %>%
    dplyr::group_by(subject_course) %>%
    dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(subject_course, course_level = level)

  # calc_cl_enrls groups by campus+college, producing multiple rows per course when
  # sections span campuses or colleges. Aggregate to one row per (subject_course, term,
  # term_type) so each course appears exactly once in the comparison.
  regstats_raw <- calc_cl_enrls(dept_students)
  if (nrow(regstats_raw) == 0) return(list(early_drops = NULL, late_drops = NULL))

  regstats <- regstats_raw %>%
    dplyr::group_by(subject_course, term, term_type) %>%
    dplyr::summarize(
      registered = sum(registered, na.rm = TRUE),
      dr_early   = sum(dr_early,   na.rm = TRUE),
      dr_late    = sum(dr_late,    na.rm = TRUE),
      cl_total   = sum(cl_total,   na.rm = TRUE),
      .groups    = "drop"
    )

  # Drop rate as % of class list total — comparable across courses of different sizes
  regstats <- regstats %>%
    dplyr::mutate(
      early_rate = dplyr::if_else(cl_total > 0, round(dr_early / cl_total * 100, 1), NA_real_),
      late_rate  = dplyr::if_else(cl_total > 0, round(dr_late  / cl_total * 100, 1), NA_real_)
    )

  current_courses <- regstats %>% dplyr::filter(term == current_term)
  if (nrow(current_courses) == 0) return(list(early_drops = NULL, late_drops = NULL))

  current_term_type <- current_courses$term_type[1]

  # Prior terms of same type only — keeps fall vs. fall, spring vs. spring
  prior_same_type <- regstats %>%
    dplyr::filter(term != current_term, term_type == current_term_type)

  # Per-course historical mean rates for same term type (prior terms only)
  course_hist_means <- prior_same_type %>%
    dplyr::group_by(subject_course) %>%
    dplyr::summarize(
      n_prior         = dplyr::n(),
      hist_early_rate = round(mean(early_rate, na.rm = TRUE), 1),
      hist_late_rate  = round(mean(late_rate,  na.rm = TRUE), 1),
      .groups         = "drop"
    )

  # Course-level (lower/upper/grad) historical avg rates for same term type.
  # Used to show how a course compares to others in its division, not just itself.
  level_hist_means <- prior_same_type %>%
    dplyr::left_join(course_levels, by = "subject_course") %>%
    dplyr::filter(!is.na(course_level)) %>%
    dplyr::group_by(course_level) %>%
    dplyr::summarize(
      level_avg_early_rate = round(mean(early_rate, na.rm = TRUE), 1),
      level_avg_late_rate  = round(mean(late_rate,  na.rm = TRUE), 1),
      .groups              = "drop"
    )

  # Course titles from current term sections
  current_titles <- cedar_sections %>%
    dplyr::filter(department == dept_code, term == current_term) %>%
    dplyr::select(subject_course, course_title) %>%
    dplyr::distinct(subject_course, .keep_all = TRUE)

  comparison <- current_courses %>%
    dplyr::left_join(course_hist_means, by = "subject_course") %>%
    dplyr::left_join(course_levels,     by = "subject_course") %>%
    dplyr::left_join(level_hist_means,  by = "course_level") %>%
    dplyr::left_join(current_titles,    by = "subject_course") %>%
    dplyr::filter(
      !is.na(hist_early_rate),
      n_prior >= 2,
      cl_total >= min_cl_total,          # skip tiny courses (< 10 students)
      (dr_early + dr_late) >= min_drops  # skip trivial drop counts (< 3 total)
    ) %>%
    dplyr::mutate(
      diff_early       = round(early_rate - hist_early_rate,       1),
      diff_late        = round(late_rate  - hist_late_rate,        1),
      diff_early_level = round(early_rate - level_avg_early_rate,  1),
      diff_late_level  = round(late_rate  - level_avg_late_rate,   1)
    )

  if (nrow(comparison) == 0) return(list(early_drops = NULL, late_drops = NULL))

  make_split <- function(df, diff_col) {
    above <- df %>% dplyr::filter(.data[[diff_col]] >= min_abs_diff) %>% dplyr::arrange(dplyr::desc(.data[[diff_col]]))
    below <- df %>% dplyr::filter(.data[[diff_col]] <= -min_abs_diff) %>% dplyr::arrange(.data[[diff_col]])
    list(
      above = if (nrow(above) > 0) above else NULL,
      below = if (nrow(below) > 0) below else NULL
    )
  }

  early_split <- make_split(comparison, "diff_early")
  late_split  <- make_split(comparison, "diff_late")

  list(
    early_drops = early_split,
    late_drops  = late_split
  )
}


# ── Student composition donuts ────────────────────────────────────────────────

#' Donut plots: who takes this department's courses?
#'
#' Produces up to 8 plotly donuts showing the major and class-standing
#' breakdown of students enrolled in lower- and upper-division home-dept
#' sections. For each combination of level × dimension (major / class standing)
#' two donuts are returned: a current-term snapshot and a rolling average over
#' the last \code{n_years} terms of the same term type (e.g., spring avg).
#'
#' Only home-dept sections are counted (crosslist partner sections excluded),
#' matching the filter applied in \code{get_dept_drop_stats}.
#'
#' @param cedar_students CEDAR student class-list data frame.
#' @param cedar_sections CEDAR sections data frame (used for home-CRN lookup).
#' @param dept_code Department code string (e.g., "HIST").
#' @param current_term Integer term code for the current-term snapshot.
#' @param n_years Number of years of history for the rolling average (default 5).
#' @param campus Optional character vector of campus codes (e.g., \code{c("ABQ")}).
#'   Passed as \code{opt$course_campus} to \code{filter_class_list}.
#' @return Named list of up to 8 plotly donuts (NULL for any with no data):
#'   \code{lower_major_current}, \code{lower_major_avg},
#'   \code{upper_major_current}, \code{upper_major_avg},
#'   \code{lower_class_current}, \code{lower_class_avg},
#'   \code{upper_class_current}, \code{upper_class_avg}
plot_dept_student_donuts <- function(cedar_students, cedar_sections, dept_code,
                                     current_term, n_years = 5, campus = NULL) {
  message("[dept-dashboard.R] plot_dept_student_donuts for ", dept_code)

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  cutoff_year  <- current_year - (n_years - 1)

  # Home-dept CRNs only — excludes sections where this dept is a crosslist partner.
  # Mirrors the crosslist guard in get_dept_drop_stats and get_dept_course_enrl_history.
  home_crns <- cedar_sections %>%
    dplyr::filter(
      department == dept_code,
      is.na(crosslist_role) | crosslist_role == "home"
    ) %>%
    dplyr::pull(crn) %>%
    unique()

  cl_opt <- list(dept = dept_code, status = "A")
  if (!is.null(campus) && length(campus) > 0) cl_opt$course_campus <- campus

  students <- filter_class_list(cedar_students, cl_opt) %>%
    dplyr::filter(
      crn %in% home_crns,
      level %in% c("lower", "upper"),
      floor(term / 100) >= cutoff_year
    )

  if (nrow(students) == 0) {
    message("[dept-dashboard.R] No student data found for donut plots")
    return(list())
  }

  # Term type of the current term — historical avg uses same type (spring vs fall).
  cur_term_type <- students %>%
    dplyr::filter(term == current_term) %>%
    dplyr::pull(term_type) %>%
    unique()
  cur_term_type <- if (length(cur_term_type) > 0) cur_term_type[1] else NA_character_

  # Translate a vector of major codes to human-readable names using
  # major_code_to_name (overridden at startup with data-derived cedar_lookups$major_code_to_name
  # if available; falls back to hand-coded mappings.R).
  # Unknown codes are kept as-is so the donut still shows something useful.
  translate_major <- function(codes) {
    if (exists("major_code_to_name") && length(major_code_to_name) > 0) {
      translated <- major_code_to_name[as.character(codes)]
      ifelse(is.na(translated), as.character(codes), translated)
    } else {
      as.character(codes)
    }
  }

  # build_color_map() is the shared utility in utils.R. Pre-sort by frequency
  # so the most-common category gets the most visually distinct color. Colors
  # are assigned from ALL students across both levels so current and avg donuts
  # for the same dimension (major or class standing) share a consistent mapping.
  major_color_map <- build_color_map(
    names(sort(table(translate_major(students$major_code)), decreasing = TRUE))
  )
  class_color_map <- build_color_map(
    names(sort(table(abbreviate_classification(students$student_classification)), decreasing = TRUE))
  )

  # Build a single donut from a two-column data frame (label, value).
  # Top top_n slices kept; remainder collapsed into "Other".
  # color_map: named character vector mapping labels to hex colors; ensures
  # the same category has the same color across current and avg donuts.
  make_donut <- function(df, label_col, value_col, title, color_map = NULL, top_n = 8) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    df <- df %>%
      dplyr::filter(!is.na(.data[[label_col]]), .data[[value_col]] > 0) %>%
      dplyr::arrange(dplyr::desc(.data[[value_col]]))
    if (nrow(df) == 0) return(NULL)
    if (nrow(df) > top_n) {
      other_val <- sum(df[[value_col]][(top_n + 1):nrow(df)], na.rm = TRUE)
      df <- df[seq_len(top_n), ]
      extra <- tibble::tibble(!!label_col := "Other", !!value_col := other_val)
      df <- dplyr::bind_rows(df, extra)
    }
    marker_spec <- if (!is.null(color_map)) {
      slice_colors <- color_map[as.character(df[[label_col]])]
      slice_colors[is.na(slice_colors)] <- "#aaaaaa"
      list(colors = unname(slice_colors), line = list(color = "#fff", width = 1))
    } else {
      list(line = list(color = "#fff", width = 1))
    }
    plotly::plot_ly(
      df,
      labels = ~.data[[label_col]],
      values = ~.data[[value_col]],
      type   = "pie",
      hole   = 0.55,
      textinfo      = "percent",
      hovertemplate = "%{label}: %{value:.1f} (%{percent})<extra></extra>",
      marker = marker_spec
    ) %>%
      plotly::layout(
        title      = list(text = title, font = list(size = 12)),
        showlegend = TRUE,
        legend     = list(font = list(size = 9), orientation = "v"),
        margin     = list(t = 36, b = 4, l = 4, r = 4)
      )
  }

  # TODO: The four data-prep blocks inside the loop (major_cur, class_cur,
  # major_avg, class_avg) are partially duplicated across lower/upper iterations.
  # Extracting helpers is non-trivial because:
  #   - major vs. class use different distinct() keys and label-transform timing
  #   - avg uses round(sum(n)/n_hist, 1) rather than mean(n), with n_hist from
  #     the outer scope — a generic helper would change the averaging behavior
  # Refactor only when the aggregation logic can be unified without behavior change.

  # Collapse a label+value data frame to top_n rows, merging the rest into "Other".
  # Returns data frame with the same two columns (label, value_col).
  collapse_top_n <- function(df, value_col, top_n = 8) {
    df <- df %>% dplyr::arrange(dplyr::desc(.data[[value_col]]))
    if (nrow(df) > top_n) {
      other_val <- sum(df[[value_col]][(top_n + 1):nrow(df)], na.rm = TRUE)
      df <- dplyr::bind_rows(
        df[seq_len(top_n), ],
        tibble::tibble(label = "Other", !!value_col := other_val)
      )
    }
    df
  }

  # Build a comparison table df: label, current_n, avg_n, pct_change, color.
  # Used for the right-column DT replacing the avg donut.
  make_comparison_df <- function(cur_df,    # label, n
                                  avg_df,    # label, avg_n
                                  color_map,
                                  top_n = 8) {
    # Collapse each side independently then full-join so any label on either
    # side appears in the table.
    cur_c <- if (!is.null(cur_df) && nrow(cur_df) > 0)
      collapse_top_n(cur_df, "n", top_n) else tibble::tibble(label = character(), n = numeric())
    avg_c <- if (!is.null(avg_df) && nrow(avg_df) > 0)
      collapse_top_n(avg_df, "avg_n", top_n) else tibble::tibble(label = character(), avg_n = numeric())

    dplyr::full_join(cur_c, avg_c, by = "label") %>%
      dplyr::mutate(
        n     = dplyr::coalesce(as.numeric(n),     0),
        avg_n = dplyr::coalesce(as.numeric(avg_n), NA_real_),
        pct_change = dplyr::if_else(
          !is.na(avg_n) & avg_n > 0,
          as.integer(round((n - avg_n) / avg_n * 100)),
          NA_integer_
        ),
        color = dplyr::coalesce(color_map[label], "#aaaaaa")
      ) %>%
      dplyr::arrange(dplyr::desc(dplyr::coalesce(avg_n, n)))
  }

  result <- list(
    major_color_map = major_color_map,
    class_color_map = class_color_map,
    cur_term_type   = cur_term_type
  )

  for (lvl in c("lower", "upper")) {
    lvl_label <- if (lvl == "lower") "Lower Div" else "Upper Div"
    lvl_stu   <- students %>% dplyr::filter(level == lvl)

    # ── Current term donut (kept as-is) ─────────────────────────────────────
    cur <- lvl_stu %>% dplyr::filter(term == current_term)
    major_cur <- NULL
    class_cur <- NULL
    if (nrow(cur) > 0) {
      major_cur <- cur %>%
        dplyr::distinct(student_id, major_code) %>%
        dplyr::mutate(major_code = translate_major(major_code)) %>%
        dplyr::count(major_code, name = "n") %>%
        dplyr::rename(label = major_code)
      result[[paste0(lvl, "_major_current")]] <-
        make_donut(major_cur, "label", "n",
                   paste0(lvl_label, " Majors — Current"), major_color_map)

      class_cur <- cur %>%
        dplyr::distinct(student_id, student_classification) %>%
        dplyr::mutate(student_classification =
                        abbreviate_classification(student_classification)) %>%
        dplyr::count(student_classification, name = "n") %>%
        dplyr::rename(label = student_classification)
      result[[paste0(lvl, "_class_current")]] <-
        make_donut(class_cur, "label", "n",
                   paste0(lvl_label, " Class Standing — Current"), class_color_map)
    }

    # ── N-year rolling average — used for comparison table (not plotted) ────
    hist <- lvl_stu
    if (!is.na(cur_term_type)) hist <- hist %>% dplyr::filter(term_type == cur_term_type)
    n_hist <- dplyr::n_distinct(hist$term)

    major_avg <- NULL
    class_avg <- NULL
    if (n_hist > 0) {
      major_avg <- hist %>%
        dplyr::group_by(term, major_code) %>%
        dplyr::summarize(n = dplyr::n_distinct(student_id), .groups = "drop") %>%
        dplyr::group_by(major_code) %>%
        dplyr::summarize(avg_n = round(sum(n) / n_hist, 1), .groups = "drop") %>%
        dplyr::mutate(major_code = translate_major(major_code)) %>%
        dplyr::rename(label = major_code)

      class_avg <- hist %>%
        dplyr::group_by(term, student_classification) %>%
        dplyr::summarize(n = dplyr::n_distinct(student_id), .groups = "drop") %>%
        dplyr::group_by(student_classification) %>%
        dplyr::summarize(avg_n = round(sum(n) / n_hist, 1), .groups = "drop") %>%
        dplyr::mutate(student_classification =
                        abbreviate_classification(student_classification)) %>%
        dplyr::rename(label = student_classification)
    }

    result[[paste0(lvl, "_n_hist")]]         <- n_hist
    result[[paste0(lvl, "_major_table_df")]] <- make_comparison_df(major_cur, major_avg, major_color_map)
    result[[paste0(lvl, "_class_table_df")]] <- make_comparison_df(class_cur, class_avg, class_color_map)
  }

  result
}


# ── Main dashboard entry point ────────────────────────────────────────────────

#' Build all data for the Explore Your Unit dashboard
#'
#' Lightweight alternative to create_dept_report_data(). Focused on visual
#' summary cards and discovery-oriented analytics rather than exhaustive tables.
#'
#' Course enrollment history is computed once via get_dept_course_enrl_history()
#' and then reused by get_enrollment_momentum(), get_new_courses(), and
#' get_dormant_courses() to avoid redundant data passes.
#'
#' @param data_objects Named list containing cedar_programs, cedar_students,
#'   cedar_sections (same structure as used by dept-report.R).
#' @param opt Named list. Required: opt[["dept"]] — department code string.
#'   Optional: opt[["campus"]] — campus code(s) applied once at the top of this
#'   function to cedar_programs (student_campus), cedar_students (campus), and
#'   cedar_sections (campus). All downstream functions receive pre-filtered data.
#'   NULL or "" means no campus filter.
#' @return Named list with:
#'   - dept_code, dept_name
#'   - headcount_summary (data frame with 3yr comparisons)
#'   - headcount_series (data frame for sparkline, or NULL)
#'   - plots$cross_dept_minors (plotly donut)
#'   - plots$credit_hours_by_level (plotly line chart)
#'   - enrollment_momentum (list: growing, investigate)
#'   - new_courses (data frame or NULL)
#'   - dormant_courses (data frame or NULL)
#'   - drop_stats (list: early_drops, late_drops — each with above, below, dept_avg_rate)
#' Get current-term section count and total enrollment for a subject
#'
#' Returns the number of active home sections and total enrollment for a given
#' subject prefix in a given term. Crosslist partner rows are excluded so each
#' course is counted once; total_enrl is used (correct for combined C-suffix
#' courses after crosslist deduplication).
#'
#' Designed to be reusable wherever a lightweight "right now" enrollment
#' snapshot is needed — dashboard headcount cards, comparison views, API
#' endpoints, etc. — without running the full dept dashboard pipeline.
#'
#' @param sections Data frame of course sections (cedar_sections). Must include:
#'   subject, term, crosslist_group, crosslist_primary, total_enrl.
#' @param subject Character scalar — subject prefix to filter to (e.g. "HIST").
#' @param term Integer term code (e.g. 202610L). Typically \code{cedar_current_term}.
#'
#' @return Named list with:
#'   \itemize{
#'     \item \code{n_sections} — integer count of active home sections
#'     \item \code{total_enrl} — integer sum of total_enrl across those sections
#'   }
#'
#' @examples
#' stats <- get_subject_current_stats(cedar_sections, "HIST", cedar_current_term)
#' stats$n_sections  # 12
#' stats$total_enrl  # 347
get_subject_current_stats <- function(sections, subject, term) {
  rows <- sections[
    !is.na(sections$subject) & sections$subject == subject &
    !is.na(sections$term)    & sections$term    == term    &
    !is.na(sections$status)  & sections$status  == "A",
  ]
  home <- rows[is.na(rows$crosslist_group) | rows$crosslist_role %in% c("home", "internal"), ]
  list(
    n_sections = nrow(home),
    total_enrl = if (nrow(home) > 0 && "total_enrl" %in% names(home))
                   sum(home$total_enrl, na.rm = TRUE) else 0L
  )
}


create_dept_dashboard_data <- function(data_objects, opt) {
  dept_raw <- opt[["dept"]]
  campus   <- opt[["campus"]]
  if (is.null(campus) || length(campus) == 0) campus <- NULL
  message("[dept-dashboard.R] Building dashboard for: ", dept_raw,
          if (!is.null(campus)) paste0(" [campus: ", paste(campus, collapse = ","), "]") else "")

  cedar_programs <- data_objects[["cedar_programs"]]
  cedar_students <- data_objects[["cedar_students"]]
  cedar_sections <- data_objects[["cedar_sections"]]

  # Campus is passed through each function's opt as course_campus (the Cedar standard
  # key for the campus column in cedar_sections and cedar_students). Headcount functions
  # use cedar_programs which tracks student home campus separately — not filtered here.

  # dept is already a short code (e.g. "HIST", "CS") from the dropdown,
  # which is populated from cedar_sections$department.
  dept_code <- dept_raw
  message("[dept-dashboard.R] dept_code: ", dept_code)

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

  # Cap at cedar_current_term: future terms have sparse pre-registration data that
  # distorts headcount cards and sparklines. cedar_current_term is the latest
  # term with meaningful enrollment; anything beyond it is excluded.
  max_hc_term <- if (exists("cedar_current_term")) cedar_current_term else max(cedar_programs$term, na.rm = TRUE)
  programs_for_hc <- dplyr::filter(cedar_programs, term <= max_hc_term)

  result$headcount_summary <-
    get_headcount_summary(programs_for_hc, dept_code)

  result$headcount_series <-
    get_headcount_series(programs_for_hc, dept_code)

  result$plots$cross_dept_minors <-
    plot_cross_dept_minors(cedar_programs, dept_code)

  result$plots$majors_with_minor <-
    plot_majors_with_dept_minor(cedar_programs, dept_code)

  result$plots$credit_hours_by_level <-
    plot_credit_hours_by_level(cedar_students, dept_code, n_years = 5, campus = campus)

  # Build course enrollment history via get_enrl (one row per course per term, enrolled > 0).
  # crosslist = "home" keeps only home-dept sections; uel = TRUE drops thesis/dissertation/honors.
  ch_opt <- list(dept = dept_code, status = "A", crosslist = "home", uel = TRUE,
                 group_cols = c("subject_course", "course_title", "term"))
  if (!is.null(campus) && length(campus) > 0) ch_opt$course_campus <- campus
  course_history <- get_enrl(cedar_sections, ch_opt) %>% dplyr::filter(enrolled > 0)

  # Current-term snapshot — reads cedar_current_term from global config.
  # Falls back to max term in history if not defined (e.g. in testing).
  current_term <- if (exists("cedar_current_term")) cedar_current_term else max(course_history$term, na.rm = TRUE)

  result$current_enrl_vs_avg    <- get_current_enrl_vs_avg(course_history, current_term)
  result$new_this_term          <- get_new_this_term(course_history, current_term)
  result$missing_from_earlier   <- get_missing_from_earlier(course_history, current_term)
  result$repeated_topics        <- get_repeated_topics_courses(course_history, current_term)
  result$drop_stats             <- get_dept_drop_stats(cedar_students, cedar_sections, dept_code, current_term, campus = campus)
  result$plots$student_donuts   <- plot_dept_student_donuts(cedar_students, cedar_sections, dept_code, current_term, campus = campus)

  message("[dept-dashboard.R] Dashboard data ready for ", dept_code)
  result
}


# Render SCH trend cards (growing / declining / emerging programs).
# trends: named list with $growing, $declining, $emerging tibbles from
#         compute_major_sch_trends(); may be NULL when data is insufficient.
# label:  section heading, e.g. "Lower Division"
render_sch_trend_cards <- function(trends, label) {
  if (is.null(trends)) {
    return(div(
      class = "dd-trend-empty", style = "padding:6px 0;",
      paste0(label, ": insufficient term history to compute trends.")
    ))
  }

  fmt_pct <- function(x) {
    if (is.na(x)) return("—")
    paste0(if (x >= 0) "+" else "", round(x, 1), "%")
  }
  fmt_sch <- function(x) if (is.na(x)) "—" else round(x)

  pct_class <- function(x, invert = FALSE) {
    if (is.na(x)) return("num text-muted")
    positive <- (!invert && x > 0) || (invert && x < 0)
    paste("num fw-semibold", if (positive) "text-success" else "text-critical")
  }

  make_rows <- function(df, show_pct = TRUE) {
    if (is.null(df) || nrow(df) == 0) return(tags$em(class = "dd-trend-empty", "None"))
    rows <- lapply(seq_len(nrow(df)), function(i) {
      r <- df[i, ]
      cells <- list(
        tags$td(r$major_name),
        tags$td(class = "num", paste0(fmt_sch(r$avg_sch), " avg"))
      )
      if (show_pct) {
        cells <- c(cells, list(
          tags$td(class = pct_class(r$pct_1yr), fmt_pct(r$pct_1yr)),
          tags$td(class = pct_class(r$pct_2yr), fmt_pct(r$pct_2yr)),
          tags$td(class = pct_class(r$pct_4yr), fmt_pct(r$pct_4yr))
        ))
      }
      do.call(tags$tr, cells)
    })
    header_cells <- list(
      tags$th("Program"),
      tags$th(class = "num", "Avg SCH")
    )
    if (show_pct) {
      header_cells <- c(header_cells, list(
        tags$th(class = "num", "1yr %"),
        tags$th(class = "num", "2yr %"),
        tags$th(class = "num", "4yr %")
      ))
    }
    tags$table(class = "dd-trend-table",
      do.call(tags$tr, header_cells),
      tagList(rows)
    )
  }

  section <- function(title, content, title_class = "text-success") {
    div(class = "dd-trend-card",
      div(class = paste("dd-trend-card-title", title_class), title),
      content
    )
  }

  div(
    div(class = "dd-trend-label", label),
    section("Growing",      make_rows(trends$growing),                   "text-success"),
    section("Declining",    make_rows(trends$declining),                 "text-critical"),
    section("New Programs", make_rows(trends$emerging, show_pct = FALSE), "text-amber")
  )
}
