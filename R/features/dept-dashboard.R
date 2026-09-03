#' Department Dashboard Analytics
#'
#' Lightweight analytics for the "Explore Your Unit" dashboard.
#' Designed to load fast, display visually, and emphasize discovery over compliance.
#'
#' Key functions:
#' - `plot_metric_trendline()` — multi-series plotly line chart for any metric over time
#' - `get_headcount_summary()` — major/minor counts with trend arrows
#' - `plot_cross_dept_minors()` — donut: what other depts do your majors minor in?
#' - `get_dashboard_credit_hour_shifts()` — notable selected-term SCH departures
#' - `plot_credit_hours_by_level()` — lower/upper/grad credit hour trendlines for Dept Trends
#' - `plot_dept_student_donuts()` — selected-term major + class standing by course level
#' - `create_dept_dashboard_data()` — main entry point called by server.R
#'
#' Data requirements (passed via data_objects):
#' - cedar_programs: student_id, term, dept_code, program_type, program_name
#' - cedar_students: student_id, term, department, level, credits, final_grade, major
#' - cedar_sections: term, department, subject_course, course_title, enrolled, crosslist_primary

# compute_trend() — the canonical slope/direction helper — now lives in
# R/trunk/utils.R so branches, cones, and modules can all call it.


# ── Credit hours by level trendlines ─────────────────────────────────────────

get_credit_hours_by_level_data <- function(cedar_students, dept_code, n_years = 5,
                                           campus = NULL) {
  current_year <- as.integer(format(Sys.Date(), "%Y"))
  cutoff_year  <- current_year - (n_years - 1)

  cedar_students %>%
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
      level = factor(
        level,
        levels = c("lower", "upper", "grad"),
        labels = c("Lower Division", "Upper Division", "Graduate")
      )
    )
}

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

  ch <- get_credit_hours_by_level_data(cedar_students, dept_code, n_years, campus)

  plot_credit_hours_by_level_data(ch)
}

plot_credit_hours_by_level_data <- function(ch) {

  if (nrow(ch) == 0) {
    message("[dept-dashboard.R] No credit hour data for requested scope")
    return(NULL)
  }

  # Native plotly, matching build_dept_enrollment_history()'s make_line(). This
  # was previously built in ggplot2 and handed to ggplotly() — a redundant
  # second charting path for a plain multi-line trend the app already draws
  # natively, and one that silently dropped the CEDAR palette if the manual
  # scale was ever removed.
  plotly::plot_ly(
    ch %>% dplyr::mutate(term_label = term_axis_factor(term)),
    x      = ~term_label,
    y      = ~credit_hours,
    color  = ~level,
    colors = cedar_plotly_palette(ch$level, label_order = CEDAR_LEVEL_ORDER),
    type   = "scatter",
    mode   = "lines+markers",
    line   = list(width = 2),
    marker = list(size = 6),
    hovertemplate = paste0(
      "%{fullData.name}<br>Term: %{x}<br>Credit hours: %{y:,.0f}<extra></extra>"
    )
  ) %>%
    plotly::layout(
      xaxis  = list(title = "", tickangle = -45),
      yaxis  = list(title = "Credit Hours"),
      legend = list(orientation = "h", x = 0, y = 1.12)
    )
}

get_dashboard_credit_hour_shifts <- function(cedar_students, dept_code, current_term,
                                             campus = NULL, n_years = 5L,
                                             hist_terms = 3L,
                                             min_abs_diff = 25,
                                             min_pct_diff = 10) {
  message("[dept-dashboard.R] get_dashboard_credit_hour_shifts for ", dept_code,
          " term ", current_term)
  empty <- tibble::tibble(
    level = character(),
    current_credit_hours = numeric(),
    hist_avg_credit_hours = numeric(),
    diff = numeric(),
    pct_diff = numeric(),
    n_hist_terms = integer()
  )
  if (is.null(current_term) || length(current_term) == 0 || is.na(current_term)) {
    return(empty)
  }
  current_term <- as.integer(current_term[[1]])
  current_type <- get_term_type(current_term)

  ch <- get_credit_hours_by_level_data(cedar_students, dept_code, n_years, campus)
  if (nrow(ch) == 0 || !any(ch$term == current_term)) return(empty)

  ch <- ch %>%
    dplyr::mutate(
      level = as.character(level),
      term_type = vapply(term, get_term_type, character(1))
    )

  prior_terms <- ch %>%
    dplyr::filter(term < current_term, term_type == current_type) %>%
    dplyr::distinct(term) %>%
    dplyr::arrange(dplyr::desc(term)) %>%
    dplyr::slice_head(n = hist_terms) %>%
    dplyr::pull(term)
  if (length(prior_terms) < 2) return(empty)

  current <- ch %>%
    dplyr::filter(term == current_term) %>%
    dplyr::select(level, current_credit_hours = credit_hours)
  hist <- ch %>%
    dplyr::filter(term %in% prior_terms) %>%
    tidyr::complete(
      term = prior_terms,
      level = unique(c(level, current$level)),
      fill = list(credit_hours = 0)
    ) %>%
    dplyr::group_by(level) %>%
    dplyr::summarize(
      hist_avg_credit_hours = round(mean(credit_hours, na.rm = TRUE), 1),
      n_hist_terms = dplyr::n_distinct(term),
      .groups = "drop"
    )

  dplyr::full_join(current, hist, by = "level") %>%
    dplyr::mutate(
      current_credit_hours = dplyr::coalesce(current_credit_hours, 0),
      hist_avg_credit_hours = dplyr::coalesce(hist_avg_credit_hours, 0),
      diff = round(current_credit_hours - hist_avg_credit_hours, 1),
      pct_diff = dplyr::if_else(
        hist_avg_credit_hours > 0,
        round(diff / hist_avg_credit_hours * 100, 1),
        NA_real_
      )
    ) %>%
    dplyr::filter(
      n_hist_terms >= 2,
      abs(diff) >= min_abs_diff,
      is.na(pct_diff) | abs(pct_diff) >= min_pct_diff
    ) %>%
    dplyr::arrange(dplyr::desc(abs(diff)))
}


# ── Headcount summary with trend arrows ──────────────────────────────────────

#' Summarize major and minor headcount with trend arrows and historical comparisons
#'
#' Returns a summary data frame with selected-term counts, trend direction, and
#' headcount changes vs. 3 years ago and 6 years ago for undergrad/grad
#' majors and minors. Intended for display as stat cards on the dashboard.
#'
#' Year comparisons use the same term type as the selected term (for example,
#' Fall 2026 vs. Fall 2025/Fall 2023/Fall 2020). If no data exists for the
#' target term, the comparison is NA.
#'
#' @param cedar_programs CEDAR programs data frame.
#' @param dept_code Department code string.
#' @param n_trend_terms Number of most-recent terms of each type to use for
#'   trend calculation (default 4 = last ~4 falls or springs).
#' @param current_term Selected snapshot term. Defaults to the latest term in
#'   \code{cedar_programs} for backward compatibility.
#' @return Data frame with columns: group, current_count, trend_direction, arrow,
#'   count_3yr, count_6yr, change_3yr, change_6yr, pct_change_3yr, pct_change_6yr.
get_headcount_summary <- function(cedar_programs, dept_code, n_trend_terms = 4, current_term = NULL) {
  message("[dept-dashboard.R] get_headcount_summary for ", dept_code)
  if (is.null(current_term) || length(current_term) == 0 || is.na(current_term)) {
    current_term <- max(cedar_programs$term, na.rm = TRUE)
  }
  current_term <- as.integer(current_term)

  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  count_at_term <- function(df, term) {
    row <- df[df$term == term, ]
    if (nrow(row) == 0) 0 else row$count[1]
  }

  comparison_counts <- function(df) {
    selected_count <- count_at_term(df, current_term)
    target_count <- function(years_back) {
      row <- df[df$term == current_term - years_back * 100L, ]
      if (nrow(row) == 0) NA_real_ else row$count[1]
    }
    count_1yr <- target_count(1L)
    count_3yr <- target_count(3L)
    count_6yr <- target_count(6L)
    change_1yr <- if (!is.na(count_1yr)) as.integer(round(selected_count - count_1yr)) else NA_integer_
    change_3yr <- if (!is.na(count_3yr)) as.integer(round(selected_count - count_3yr)) else NA_integer_
    change_6yr <- if (!is.na(count_6yr)) as.integer(round(selected_count - count_6yr)) else NA_integer_
    pct_change_1yr <- if (!is.na(count_1yr) && count_1yr > 0)
      as.integer(round((selected_count - count_1yr) / count_1yr * 100)) else NA_integer_
    pct_change_3yr <- if (!is.na(count_3yr) && count_3yr > 0)
      as.integer(round((selected_count - count_3yr) / count_3yr * 100)) else NA_integer_
    pct_change_6yr <- if (!is.na(count_6yr) && count_6yr > 0)
      as.integer(round((selected_count - count_6yr) / count_6yr * 100)) else NA_integer_
    list(
      selected_count = selected_count,
      count_1yr = count_1yr, count_3yr = count_3yr, count_6yr = count_6yr,
      change_1yr = change_1yr, change_3yr = change_3yr, change_6yr = change_6yr,
      pct_change_1yr = pct_change_1yr, pct_change_3yr = pct_change_3yr,
      pct_change_6yr = pct_change_6yr
    )
  }

  summarize_group <- function(prog_data, program_types, level_filter, label, group_by_degree = FALSE) {
    df <- prog_data %>%
      dplyr::filter(
        dept_code     == .env$dept_code,
        program_type  %in% program_types,
        student_level == level_filter,
        !is.na(term),
        term <= .env$current_term
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
        counts <- comparison_counts(ddeg)
        current_count <- counts$selected_count
        trend <- compute_trend(ddeg$count)
        data.frame(
          group           = paste(label, deg),
          degree          = deg,
          current_count   = current_count,
          trend_direction = trend$direction,
          arrow           = trend$arrow,
          count_1yr       = counts$count_1yr,
          count_3yr       = counts$count_3yr,
          count_6yr       = counts$count_6yr,
          change_1yr      = counts$change_1yr,
          change_3yr      = counts$change_3yr,
          change_6yr      = counts$change_6yr,
          pct_change_1yr  = counts$pct_change_1yr,
          pct_change_3yr  = counts$pct_change_3yr,
          pct_change_6yr  = counts$pct_change_6yr,
          stringsAsFactors = FALSE
        )
      })
      return(do.call(rbind, out))
    } else {
      counts <- comparison_counts(df)
      current_count <- counts$selected_count
      trend <- compute_trend(df$count)
      data.frame(
        group           = label,
        current_count   = current_count,
        trend_direction = trend$direction,
        arrow           = trend$arrow,
        count_1yr       = counts$count_1yr,
        count_3yr       = counts$count_3yr,
        count_6yr       = counts$count_6yr,
        change_1yr      = counts$change_1yr,
        change_3yr      = counts$change_3yr,
        change_6yr      = counts$change_6yr,
        pct_change_1yr  = counts$pct_change_1yr,
        pct_change_3yr  = counts$pct_change_3yr,
        pct_change_6yr  = counts$pct_change_6yr,
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
#' @param term Optional term code. When supplied, both the focal majors and
#'   their minors are scoped to that single term; when NULL, uses all data.
#' @return A plotly donut chart, or NULL if no cross-dept minor data found.
get_cross_dept_minors_data <- function(cedar_programs, dept_code, top_n = 8, term = NULL) {
  if (!is.null(term) && length(term) > 0 && !is.na(term)) {
    term <- as.integer(term[[1]])
    cedar_programs <- cedar_programs %>% dplyr::filter(term == .env$term)
  }

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
    return(tibble::tibble())
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
    return(cross_minors)
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

  cross_minors
}

plot_cross_dept_program_donut <- function(data) {
  if (is.null(data) || nrow(data) == 0) return(NULL)
  plotly::plot_ly(
    data,
    labels  = ~dept_code,
    values  = ~n_students,
    type    = "pie",
    hole    = 0.5,
    textinfo = "label+percent",
    marker = list(colors = cedar_plotly_palette(data$dept_code)),
    hovertemplate = paste0(
      "<b>%{label}</b><br>",
      "%{value} students<br>",
      "%{percent}<extra></extra>"
    )
  ) %>%
    plotly::layout(
      showlegend  = FALSE,
      margin      = list(t = 10, b = 10)
    )
}

plot_cross_dept_minors <- function(cedar_programs, dept_code, top_n = 8, term = NULL) {
  message("[dept-dashboard.R] plot_cross_dept_minors for ", dept_code)
  plot_cross_dept_program_donut(
    get_cross_dept_minors_data(cedar_programs, dept_code, top_n, term)
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
#' @param term Optional term code. When supplied, both the focal minors and
#'   their majors are scoped to that single term; when NULL, uses all data.
#' @return A plotly donut chart, or NULL if no data found.
get_majors_with_dept_minor_data <- function(cedar_programs, dept_code, top_n = 8, term = NULL) {
  if (!is.null(term) && length(term) > 0 && !is.na(term)) {
    term <- as.integer(term[[1]])
    cedar_programs <- cedar_programs %>% dplyr::filter(term == .env$term)
  }

  dept_minor_ids <- cedar_programs %>%
    dplyr::filter(
      dept_code    == .env$dept_code,
      program_type %in% c("First Minor", "Second Minor")
    ) %>%
    dplyr::pull(student_id) %>%
    unique()

  if (length(dept_minor_ids) == 0) {
    message("[dept-dashboard.R] No minors found for ", dept_code)
    return(tibble::tibble())
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
    return(cross_majors)
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

  cross_majors
}

plot_majors_with_dept_minor <- function(cedar_programs, dept_code, top_n = 8, term = NULL) {
  message("[dept-dashboard.R] plot_majors_with_dept_minor for ", dept_code)
  plot_cross_dept_program_donut(
    get_majors_with_dept_minor_data(cedar_programs, dept_code, top_n, term)
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

  .assert_history_has_campus(course_history, "get_new_courses")
  result <- course_history %>%
    dplyr::group_by(subject_course, course_title, campus) %>%
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

  .assert_history_has_campus(course_history, "get_dormant_courses")
  result <- course_history %>%
    dplyr::group_by(subject_course, course_title, campus) %>%
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
#
# CAMPUS RULE: campuses are never merged. course_history must carry a campus
# column (built with campus in group_cols), and every comparison here is
# per-campus — an ABQ offering compares only to prior ABQ offerings. Merging
# would sum campuses in "all campuses" views (e.g. a course that once ran at
# two campuses would inflate its own historical average — issue #32 follow-up).

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
#' @param course_history Per-campus course enrollment history (campus column
#'   required). Newness is judged course-level — a course that ever ran at ANY
#'   campus is not "new" — but enrollment is reported per campus, never summed
#'   across campuses.
#' @param current_term Integer term code.
#' @return Data frame with columns: subject_course, course_title, campus,
#'   enrolled, slot_avg_enrl (NA for non-topics; average enrollment across all
#'   prior T: offerings under same course number at the same campus),
#'   n_slot_prior (count of those prior offerings). Ordered alphabetically.
#'   Returns NULL if none found.
get_new_this_term <- function(course_history, current_term) {
  message("[dept-dashboard.R] get_new_this_term for term ", current_term)

  if (is.null(course_history) || nrow(course_history) == 0) {
    message("[dept-dashboard.R] get_new_this_term: no course history (returning NULL)")
    return(NULL)
  }
  .assert_history_has_campus(course_history, "get_new_this_term")

  current_courses <- course_history %>%
    dplyr::filter(term == current_term) %>%
    dplyr::select(subject_course, course_title, campus, enrolled, dplyr::any_of("total_enrl"))

  if (nrow(current_courses) == 0) {
    message("[dept-dashboard.R] get_new_this_term: no courses in current term ", current_term, " (returning NULL)")
    return(NULL)
  }

  # "Prior" means strictly before the selected term (term < current). With term !=,
  # a course selected in a past term would look un-new if it ran again later.
  prior_history <- course_history %>% dplyr::filter(term < current_term)
  # CAMPUS_ROLLUP: curriculum newness is institution-wide. A course previously
  # offered at any campus is not new, while current enrollment stays per campus.
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
    # CAMPUS_ROLLUP: a recurring topic title is not new merely because its
    # delivery moved campuses; the reported current rows still retain campus.
    prior_topic_keys <- prior_history %>%
      dplyr::filter(is_topics_course(course_title)) %>%
      dplyr::distinct(subject_course, course_title)
    topics_new <- topics_in_current %>%
      dplyr::anti_join(prior_topic_keys, by = c("subject_course", "course_title"))

    # Slot average: avg enrollment across ALL prior T: offerings for same course number,
    # regardless of title — tells the chair what demand for this slot typically looks
    # like. Per campus: demand at one campus says nothing about another.
    if (nrow(topics_new) > 0) {
      slot_avgs <- prior_history %>%
        dplyr::filter(is_topics_course(course_title)) %>%
        dplyr::group_by(subject_course, campus) %>%
        dplyr::summarize(
          slot_avg_enrl = round(mean(enrolled, na.rm = TRUE), 1),
          n_slot_prior  = dplyr::n(),
          .groups = "drop"
        )
      topics_new <- topics_new %>%
        dplyr::left_join(slot_avgs, by = c("subject_course", "campus"))
    } else {
      topics_new <- NULL
    }
  }

  result <- dplyr::bind_rows(genuinely_new, topics_new) %>%
    dplyr::arrange(subject_course)

  if (nrow(result) == 0) NULL else result
}

# Format last N offerings of each course as a compact history string,
# e.g. "28, 31, 25 (Fa23, Sp24, Fa24)"
# topics_only: if TRUE, restrict to courses with "T:" titles (topics courses).
# Using an explicit flag instead of ... avoids NSE scoping issues when course_title
# is only available as a data column, not a standalone variable in the caller's scope.
.recent_history_str <- function(course_history, current_term, topics_only = FALSE) {
  # Prior appearances only (term < selected) — "recent history" should look back
  # from the selected term, never forward into later terms.
  data <- course_history %>% dplyr::filter(term < current_term)
  if (topics_only) data <- data %>% dplyr::filter(is_topics_course(course_title))
  data %>%
    dplyr::arrange(dplyr::desc(term)) %>%
    dplyr::group_by(subject_course, course_title, campus) %>%
    dplyr::slice_head(n = 3) %>%
    dplyr::arrange(term, .by_group = TRUE) %>%
    dplyr::summarize(
      recent_history = format_term_history(term, enrolled),
      .groups = "drop"
    )
}


#' Find compact current-term enrollment flags for the department dashboard
#'
#' Produces two small current-term concern lists: high waitlist demand and low
#' enrollment risk. Rows are aggregated to course x campus, mirroring the rest
#' of the dashboard's campus-scoped comparisons.
#'
#' @param cedar_sections CEDAR sections data frame.
#' @param course_history Per-campus enrollment history from `get_enrl()`.
#' @param dept_code Department code.
#' @param current_term Selected term.
#' @param campus Optional campus filter.
#' @param cedar_students Optional class-list rows. When supplied, high-waitlist
#'   flags use the shared true-demand definition; otherwise the section snapshot
#'   count is retained as an explicitly reported fallback.
#' @param low_thresholds Named low-enrollment thresholds for lower, upper, split,
#'   and grad sections. Defaults match the Enrollment tab controls.
#' @return Named list with `high_waitlist` and `low_enrollment` data frames.
get_dashboard_enrollment_flags <- function(cedar_sections, course_history, dept_code,
                                           current_term, campus = NULL,
                                           low_thresholds = NULL,
                                           perennial_threshold = 0.70,
                                           min_prior_terms = 3L,
                                           cedar_students = NULL) {
  message("[dept-dashboard.R] get_dashboard_enrollment_flags for ", dept_code,
          " term ", current_term)

  if (is.null(cedar_sections) || nrow(cedar_sections) == 0) {
    return(list(
      high_waitlist = NULL,
      low_enrollment = NULL,
      waitlist_info = list(source = "unavailable", definition_id = "waitlist")
    ))
  }

  campus_filter <- if (is.null(campus)) character(0) else as.character(campus)
  campus_filter <- campus_filter[nzchar(campus_filter)]

  high_waitlist <- build_high_waitlist_review(
    cedar_sections, course_history, dept_code, current_term, campus = campus_filter,
    students = cedar_students
  )

  low_opt <- list(
    term          = current_term,
    course_campus = campus_filter,
    dept_code     = dept_code,
    status        = "A",
    uel           = TRUE
  )
  if (length(campus_filter) == 0) low_opt$course_campus <- NULL

  low_enrollment <- build_low_enrollment_review(
    cedar_sections, low_opt,
    thresholds           = low_thresholds,
    include_buffer       = FALSE,
    add_history          = TRUE,
    history_limit        = 200L,
    max_term             = if (exists("cedar_current_term")) cedar_current_term else current_term,
    add_perennial        = TRUE,
    min_prior_terms      = min_prior_terms,
    perennial_threshold  = perennial_threshold
  )

  waitlist_source <- if (is.null(cedar_students)) {
    "desr_snapshot_fallback"
  } else {
    "classlist_true_demand"
  }
  list(
    high_waitlist = high_waitlist,
    low_enrollment = low_enrollment,
    waitlist_info = list(source = waitlist_source, definition_id = "waitlist")
  )
}

format_dashboard_low_enrollment_review <- function(flags) {
  if (is.null(flags) || nrow(flags) == 0) {
    return(tibble(
      campus = character(),
      course = character(),
      section = character(),
      title = character(),
      sections = integer(),
      level = character(),
      enrolled = integer(),
      course_total = integer(),
      threshold = numeric(),
      priority = character(),
      repeated = character(),
      recent_history = character(),
      .priority_rank = integer()
    ))
  }

  flags %>%
    mutate(
      priority = case_when(
        severity == "critical" ~ "Critical",
        severity == "warning"  ~ "Warning",
        severity == "watch"    ~ "Watch",
        severity == "buffer"   ~ "Buffer",
        TRUE                   ~ as.character(severity)
      ),
      repeated = if_else(coalesce(perennial_low, FALSE), "Y", "N"),
      recent_history = coalesce(enrl_history, ""),
      .priority_rank = match(severity, c("critical", "warning", "watch", "buffer"))
    ) %>%
    transmute(
      campus,
      course = subject_course,
      section = as.character(section),
      title = course_title,
      sections = n_sections,
      level,
      enrolled,
      course_total = course_enrl,
      threshold = .threshold,
      priority,
      repeated,
      recent_history,
      .priority_rank
    )
}

format_dashboard_early_drop_watch <- function(regstats_flags) {
  empty <- tibble(
    campus = character(),
    subject_course = character(),
    course_title = character(),
    drop_early = integer(),
    hist_avg = numeric(),
    diff = numeric(),
    drop_rate = numeric(),
    hist_rate = numeric(),
    rate_diff_pp = numeric(),
    sd_deviation = numeric(),
    tier = character(),
    .tier_rank = integer()
  )

  drops <- regstats_flags[["early_drops"]]
  if (is.null(drops) || nrow(drops) == 0) return(empty)

  drops %>%
    ungroup() %>%
    filter(grepl("_high$", concern_tier)) %>%
    mutate(
      hist_avg = dr_early_mean,
      diff = round(drop_early - hist_avg, 1),
      hist_rate = drop_rate_mean,
      rate_diff_pp = drop_rate_change_pp,
      tier = case_when(
        concern_tier == "critical_high"   ~ "Critical",
        concern_tier == "moderate_high"   ~ "Moderate",
        concern_tier == "marginally_high" ~ "Watch",
        TRUE                              ~ as.character(concern_tier)
      ),
      .tier_rank = match(tier, c("Critical", "Moderate", "Watch"))
    ) %>%
    arrange(.tier_rank, desc(drop_early), desc(sd_deviation), subject_course) %>%
    transmute(
      campus,
      subject_course,
      course_title,
      drop_early,
      hist_avg,
      diff,
      drop_rate,
      hist_rate,
      rate_diff_pp,
      sd_deviation,
      tier,
      .tier_rank
    )
}

format_dashboard_late_drop_watch <- function(regstats_flags) {
  empty <- tibble(
    campus = character(),
    subject_course = character(),
    course_title = character(),
    drop_late = integer(),
    hist_avg = numeric(),
    diff = numeric(),
    drop_rate = numeric(),
    hist_rate = numeric(),
    rate_diff_pp = numeric(),
    sd_deviation = numeric(),
    tier = character(),
    .tier_rank = integer()
  )

  drops <- regstats_flags[["late_drops"]]
  if (is.null(drops) || nrow(drops) == 0) return(empty)

  drops %>%
    ungroup() %>%
    filter(grepl("_high$", concern_tier)) %>%
    mutate(
      hist_avg = dr_late_mean,
      diff = round(drop_late - hist_avg, 1),
      hist_rate = drop_rate_mean,
      rate_diff_pp = drop_rate_change_pp,
      tier = case_when(
        concern_tier == "critical_high"   ~ "Critical",
        concern_tier == "moderate_high"   ~ "Moderate",
        concern_tier == "marginally_high" ~ "Watch",
        TRUE                              ~ as.character(concern_tier)
      ),
      .tier_rank = match(tier, c("Critical", "Moderate", "Watch"))
    ) %>%
    arrange(.tier_rank, desc(drop_late), desc(sd_deviation), subject_course) %>%
    transmute(
      campus,
      subject_course,
      course_title,
      drop_late,
      hist_avg,
      diff,
      drop_rate,
      hist_rate,
      rate_diff_pp,
      sd_deviation,
      tier,
      .tier_rank
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
#' @param course_history Per-campus course enrollment history (campus column
#'   required). Absence is judged per campus: a course that ran at ABQ and EA
#'   two years ago but runs only at ABQ now is reported missing at EA.
#' @param current_term Integer term code.
#' @param years_back Number of years back to compare (default 2). Term code
#'   arithmetic: \code{current_term - years_back * 100}.
#' @return Data frame with columns: subject_course, course_title, campus,
#'   prior_enrl (enrollment in the comparison term at that campus),
#'   recent_history (last 3 prior appearances at that campus as a formatted
#'   string, e.g. "24, 31, 28 (Fa20, Sp22, Fa24)").
#'   Returns NULL if none found or if the comparison term has no data.
get_missing_from_earlier <- function(course_history, current_term, years_back = 2) {
  prior_term <- current_term - (years_back * 100L)
  message("[dept-dashboard.R] get_missing_from_earlier: comparing ",
          current_term, " vs ", prior_term, " (", years_back, " years back)")

  if (is.null(course_history) || nrow(course_history) == 0) {
    message("[dept-dashboard.R] get_missing_from_earlier: no course history (returning NULL)")
    return(NULL)
  }
  .assert_history_has_campus(course_history, "get_missing_from_earlier")

  comparison_term_data <- course_history %>%
    dplyr::filter(term == prior_term) %>%
    dplyr::select(subject_course, course_title, campus, prior_enrl = enrolled)

  if (nrow(comparison_term_data) == 0) {
    message("[dept-dashboard.R] No data for comparison term ", prior_term)
    return(NULL)
  }

  current_course_keys <- course_history %>%
    dplyr::filter(term == current_term) %>%
    dplyr::distinct(subject_course, course_title, campus)

  result <- comparison_term_data %>%
    dplyr::anti_join(current_course_keys, by = c("subject_course", "course_title", "campus")) %>%
    dplyr::arrange(subject_course)

  if (nrow(result) == 0) {
    message("[dept-dashboard.R] get_missing_from_earlier: no courses missing from earlier term (returning NULL)")
    return(NULL)
  }

  # Add recent_history: last 3 prior appearances per course+campus across all history
  recent <- .recent_history_str(course_history, current_term)

  result %>% dplyr::left_join(recent, by = c("subject_course", "course_title", "campus"))
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
#' @param current_term Selected snapshot term. Defaults to the latest term in
#'   \code{cedar_programs}.
#' @return Data frame with columns: term, group, student_level, program_cat, count.
#'   Returns NULL if no data found.
get_headcount_series <- function(cedar_programs, dept_code, current_term = NULL) {
  message("[dept-dashboard.R] get_headcount_series for ", dept_code)
  if (is.null(current_term) || length(current_term) == 0 || is.na(current_term)) {
    current_term <- max(cedar_programs$term, na.rm = TRUE)
  }
  current_term <- as.integer(current_term)

  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")

  df <- cedar_programs %>%
    dplyr::filter(
      dept_code == .env$dept_code,
      program_type %in% c(major_types, minor_types),
      term <= .env$current_term,
      term %% 100 != 60 | term == .env$current_term
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
#' @param course_history Per-campus course enrollment history (campus column
#'   required). Prior offerings and averages are counted per campus.
#' @param current_term Integer term code.
#' @param min_prior Minimum prior offerings required (default 2).
#' @return Data frame with columns: subject_course, course_title, campus,
#'   enrolled, prior_offerings, avg_prior_enrl. Returns NULL if none found.
get_repeated_topics_courses <- function(course_history, current_term, min_prior = 2) {
  message("[dept-dashboard.R] get_repeated_topics_courses for term ", current_term)

  if (is.null(course_history) || nrow(course_history) == 0) {
    message("[dept-dashboard.R] get_repeated_topics_courses: no course history (returning NULL)")
    return(NULL)
  }
  .assert_history_has_campus(course_history, "get_repeated_topics_courses")

  current_topics <- course_history %>%
    dplyr::filter(term == current_term, is_topics_course(course_title)) %>%
    dplyr::select(subject_course, course_title, campus, enrolled, dplyr::any_of("total_enrl"))

  if (nrow(current_topics) == 0) {
    message("[dept-dashboard.R] get_repeated_topics_courses: no topics courses in current term ", current_term, " (returning NULL)")
    return(NULL)
  }

  # Prior offerings only (term < selected) so counts/averages look back from the
  # selected term rather than including later offerings.
  prior_counts <- course_history %>%
    dplyr::filter(term < current_term, is_topics_course(course_title)) %>%
    dplyr::group_by(subject_course, course_title, campus) %>%
    dplyr::summarize(
      prior_offerings  = dplyr::n(),
      avg_prior_enrl   = round(mean(enrolled, na.rm = TRUE), 1),
      .groups          = "drop"
    ) %>%
    dplyr::filter(prior_offerings >= min_prior)

  result <- current_topics %>%
    dplyr::inner_join(prior_counts, by = c("subject_course", "course_title", "campus")) %>%
    dplyr::arrange(dplyr::desc(prior_offerings), subject_course)

  if (nrow(result) == 0) {
    message("[dept-dashboard.R] get_repeated_topics_courses: no topics courses meet min_prior threshold (returning NULL)")
    return(NULL)
  }

  # Add last 3 prior appearances with enrollment (mirrors get_missing_from_earlier)
  recent <- .recent_history_str(course_history, current_term, topics_only = TRUE)

  result %>% dplyr::left_join(recent, by = c("subject_course", "course_title", "campus"))
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


# ── Student composition donuts ────────────────────────────────────────────────

#' Donut plots: who takes this department's courses?
#'
#' Produces up to 8 plotly donuts showing the major and class-standing
#' breakdown of students enrolled in lower- and upper-division home-dept
#' sections in the selected term. For each combination of level × dimension
#' (major / class standing), returns a donut and table data.
#'
#' Only home-dept sections are counted (crosslist partner sections excluded),
#' matching the home-department filtering used throughout the dashboard.
#'
#' @param cedar_students CEDAR student class-list data frame.
#' @param cedar_sections CEDAR sections data frame (used for home-CRN lookup).
#' @param dept_code Department code string (e.g., "HIST").
#' @param current_term Integer term code for the selected-term snapshot.
#' @param n_years Retained for backward compatibility; no longer used.
#' @param campus Optional character vector of campus codes (e.g., \code{c("ABQ")}).
#'   Passed as \code{opt$course_campus} to \code{filter_class_list}.
#' @return Named list of up to 4 plotly donuts plus table data frames (NULL for
#'   any with no data): \code{lower_major_current},
#'   \code{upper_major_current}, \code{lower_class_current},
#'   \code{upper_class_current}.
plot_dept_student_donuts <- function(cedar_students, cedar_sections, dept_code,
                                     current_term, n_years = 5, campus = NULL) {
  message("[dept-dashboard.R] plot_dept_student_donuts for ", dept_code)

  # Home-dept CRNs only — excludes sections where this dept is a crosslist partner.
  # Mirrors the crosslist guard in get_dept_course_enrl_history.
  home_crns <- cedar_sections %>%
    dplyr::filter(
      department == dept_code,
      is.na(crosslist_role) | crosslist_role == "home"
    ) %>%
    dplyr::pull(crn) %>%
    unique()

  cl_opt <- list(dept_code = dept_code, status = "A")
  if (!is.null(campus) && length(campus) > 0) cl_opt$course_campus <- campus

  students <- filter_class_list(cedar_students, cl_opt) %>%
    dplyr::filter(
      crn %in% home_crns,
      level %in% c("lower", "upper"),
      term == current_term
    )

  if (nrow(students) == 0) {
    message("[dept-dashboard.R] No student data found for donut plots")
    return(list())
  }

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
  # are assigned from selected-term students across both levels so the same
  # dimension (major or class standing) has a consistent mapping.
  major_color_map <- build_color_map(
    names(sort(table(translate_major(students$major_code)), decreasing = TRUE))
  )
  class_color_map <- build_color_map(
    names(sort(table(abbreviate_classification(students$student_classification)), decreasing = TRUE))
  )

  # Build a single donut from a two-column data frame (label, value).
  # Top top_n slices kept; remainder collapsed into "Other".
  # color_map: named character vector mapping labels to hex colors; ensures
  # the same category has the same color across lower/upper selected-term donuts.
  make_donut <- function(df, label_col, value_col, color_map = NULL, top_n = 8) {
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
        showlegend = FALSE,
        margin     = list(t = 8, b = 4, l = 4, r = 4)
      )
  }

  # TODO: The data-prep blocks inside the loop are partially duplicated across
  # lower/upper iterations.
  # Extracting helpers is non-trivial because:
  #   - major vs. class use different distinct() keys and label-transform timing
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

  # Build selected-term table df: label, n, pct, color.
  make_current_df <- function(cur_df, color_map, top_n = 8) {
    if (is.null(cur_df) || nrow(cur_df) == 0) {
      return(tibble::tibble(label = character(), n = numeric(), pct = numeric(), color = character()))
    }
    cur_c <- collapse_top_n(cur_df, "n", top_n)
    total <- sum(cur_c$n, na.rm = TRUE)
    cur_c %>%
      dplyr::mutate(
        pct = if (total > 0) round(n / total * 100, 1) else NA_real_,
        color = dplyr::coalesce(color_map[label], unname(CEDAR_SEMANTIC_COLORS["other"]))
      ) %>%
      dplyr::arrange(dplyr::desc(n))
  }

  result <- list(
    major_color_map = major_color_map,
    class_color_map = class_color_map
  )

  for (lvl in c("lower", "upper")) {
    lvl_label <- if (lvl == "lower") "Lower Div" else "Upper Div"
    lvl_stu   <- students %>% dplyr::filter(level == lvl)

    major_cur <- NULL
    class_cur <- NULL
    if (nrow(lvl_stu) > 0) {
      major_cur <- lvl_stu %>%
        dplyr::distinct(student_id, major_code) %>%
        dplyr::mutate(major_code = translate_major(major_code)) %>%
        dplyr::count(major_code, name = "n") %>%
        dplyr::rename(label = major_code)
      result[[paste0(lvl, "_major_current")]] <-
        make_donut(major_cur, "label", "n", major_color_map)

      class_cur <- lvl_stu %>%
        dplyr::distinct(student_id, student_classification) %>%
        dplyr::mutate(student_classification =
                        abbreviate_classification(student_classification)) %>%
        dplyr::count(student_classification, name = "n") %>%
        dplyr::rename(label = student_classification)
      result[[paste0(lvl, "_class_current")]] <-
        make_donut(class_cur, "label", "n", class_color_map)
    }

    result[[paste0(lvl, "_major_table_df")]] <- make_current_df(major_cur, major_color_map)
    result[[paste0(lvl, "_class_table_df")]] <- make_current_df(class_cur, class_color_map)
  }

  result
}

get_dashboard_composition_shifts <- function(cedar_students, cedar_sections,
                                             cedar_programs, dept_code,
                                             current_term, campus = NULL,
                                             n_years = 3L, min_current = 5L,
                                             min_abs_diff = 10) {
  message("[dept-dashboard.R] get_dashboard_composition_shifts for ", dept_code,
          " term ", current_term)

  empty <- tibble::tibble(
    signal = character(),
    group = character(),
    category = character(),
    current_share = numeric(),
    hist_avg_share = numeric(),
    diff_pp = numeric(),
    current_n = integer(),
    n_hist_terms = integer()
  )
  if (is.null(current_term) || length(current_term) == 0 || is.na(current_term)) {
    return(empty)
  }
  current_term <- as.integer(current_term[[1]])
  current_type <- get_term_type(current_term)

  recent_same_season_terms <- function(terms) {
    typed <- tibble::tibble(term = sort(unique(as.integer(terms)))) %>%
      dplyr::mutate(term_type = vapply(term, get_term_type, character(1)))
    typed %>%
      dplyr::filter(term < current_term, term_type == current_type) %>%
      dplyr::arrange(dplyr::desc(term)) %>%
      dplyr::slice_head(n = n_years) %>%
      dplyr::pull(term)
  }

  compare_distribution <- function(dist, signal, group_label) {
    hist_terms <- recent_same_season_terms(dist$term)
    if (length(hist_terms) == 0 || !any(dist$term == current_term)) return(empty)

    current <- dist %>%
      dplyr::filter(term == current_term) %>%
      dplyr::select(category, current_share = share, current_n = n)

    hist <- dist %>%
      dplyr::filter(term %in% hist_terms) %>%
      tidyr::complete(
        term = hist_terms,
        category = unique(c(category, current$category)),
        fill = list(n = 0L, share = 0)
      ) %>%
      dplyr::group_by(category) %>%
      dplyr::summarize(
        hist_avg_share = mean(share, na.rm = TRUE),
        n_hist_terms = dplyr::n_distinct(term),
        .groups = "drop"
      )

    dplyr::full_join(current, hist, by = "category") %>%
      dplyr::mutate(
        current_share = dplyr::coalesce(current_share, 0),
        current_n = dplyr::coalesce(current_n, 0L),
        hist_avg_share = dplyr::coalesce(hist_avg_share, 0),
        n_hist_terms = dplyr::coalesce(n_hist_terms, 0L),
        diff_pp = round(current_share - hist_avg_share, 1),
        signal = signal,
        group = group_label
      ) %>%
      dplyr::filter(
        abs(diff_pp) >= min_abs_diff,
        current_n >= min_current | hist_avg_share >= min_abs_diff
      ) %>%
      dplyr::select(signal, group, category, current_share, hist_avg_share,
                    diff_pp, current_n, n_hist_terms)
  }

  distribution_by_term <- function(data, group_cols) {
    if (is.null(data) || nrow(data) == 0) {
      return(tibble::tibble(term = integer(), category = character(),
                            n = integer(), share = numeric()))
    }
    data %>%
      dplyr::count(dplyr::across(dplyr::all_of(c("term", group_cols))),
                   name = "n") %>%
      dplyr::group_by(term) %>%
      dplyr::mutate(share = round(n / sum(n, na.rm = TRUE) * 100, 1)) %>%
      dplyr::ungroup() %>%
      dplyr::rename(category = dplyr::all_of(group_cols))
  }

  major_types <- c("Major", "Second Major")
  minor_types <- c("First Minor", "Second Minor")
  program_terms <- unique(cedar_programs$term)

  program_overlap_dist <- function(kind) {
    terms <- c(current_term, recent_same_season_terms(program_terms))
    rows <- lapply(terms, function(term_value) {
      term_programs <- cedar_programs %>% dplyr::filter(term == term_value)
      if (kind == "major_minors") {
        ids <- term_programs %>%
          dplyr::filter(dept_code == .env$dept_code, program_type %in% major_types) %>%
          dplyr::pull(student_id) %>%
          unique()
        out <- term_programs %>%
          dplyr::filter(student_id %in% ids, program_type %in% minor_types,
                        dept_code != .env$dept_code)
      } else {
        ids <- term_programs %>%
          dplyr::filter(dept_code == .env$dept_code, program_type %in% minor_types) %>%
          dplyr::pull(student_id) %>%
          unique()
        out <- term_programs %>%
          dplyr::filter(student_id %in% ids, program_type %in% major_types,
                        dept_code != .env$dept_code)
      }
      if (length(ids) == 0 || nrow(out) == 0) return(NULL)
      out %>%
        dplyr::distinct(student_id, dept_code) %>%
        dplyr::mutate(term = term_value, category = dept_code)
    })
    dplyr::bind_rows(rows) %>% distribution_by_term("category")
  }

  translate_major <- function(codes) {
    if (exists("major_code_to_name") && length(major_code_to_name) > 0) {
      translated <- major_code_to_name[as.character(codes)]
      ifelse(is.na(translated), as.character(codes), translated)
    } else {
      as.character(codes)
    }
  }

  home_crns <- cedar_sections %>%
    dplyr::filter(
      department == dept_code,
      is.na(crosslist_role) | crosslist_role == "home"
    ) %>%
    dplyr::pull(crn) %>%
    unique()

  cl_opt <- list(dept_code = dept_code, status = "A")
  if (!is.null(campus) && length(campus) > 0) cl_opt$course_campus <- campus
  students <- filter_class_list(cedar_students, cl_opt) %>%
    dplyr::filter(crn %in% home_crns, level %in% c("lower", "upper")) %>%
    dplyr::mutate(
      major_label = translate_major(major_code),
      class_label = abbreviate_classification(student_classification)
    )

  course_shifts <- dplyr::bind_rows(lapply(c("lower", "upper"), function(level_value) {
    level_students <- students %>% dplyr::filter(level == level_value)
    level_label <- if (level_value == "lower") "Lower Division" else "Upper Division"

    major_dist <- level_students %>%
      dplyr::distinct(term, student_id, major_label) %>%
      distribution_by_term("major_label")
    class_dist <- level_students %>%
      dplyr::distinct(term, student_id, class_label) %>%
      distribution_by_term("class_label")

    dplyr::bind_rows(
      compare_distribution(major_dist, "Course Major Mix", level_label),
      compare_distribution(class_dist, "Class Standing Mix", level_label)
    )
  }))

  overlap_shifts <- dplyr::bind_rows(
    compare_distribution(
      program_overlap_dist("major_minors"),
      "Program Overlap",
      "Minors Declared by Dept Majors"
    ),
    compare_distribution(
      program_overlap_dist("minor_majors"),
      "Program Overlap",
      "Majors of Dept Minors"
    )
  )

  dplyr::bind_rows(overlap_shifts, course_shifts) %>%
    dplyr::arrange(dplyr::desc(abs(diff_pp)), signal, group, category)
}


# ── Main dashboard entry point ────────────────────────────────────────────────

#' Build all data for the Explore Your Unit dashboard
#'
#' Lightweight companion to the Dept Trends profile. Focused on visual
#' summary cards and discovery-oriented analytics rather than exhaustive tables.
#'
#' Course enrollment history is computed once via get_dept_course_enrl_history()
#' and then reused by get_new_courses() and get_dormant_courses() to avoid
#' redundant data passes.
#'
#' @param data_objects Named list containing cedar_programs, cedar_students,
#'   cedar_sections (same structure as used by dept-trends.R).
#' @param opt Named list. Required: opt[["dept_code"]] — department code string.
#'   Optional: opt[["campus"]] — campus code(s) applied once at the top of this
#'   function to cedar_programs (student_campus), cedar_students (campus), and
#'   cedar_sections (campus). All downstream functions receive pre-filtered data.
#'   NULL or "" means no campus filter.
#' @return Named list with:
#'   - dept_code, dept_name
#'   - headcount_summary (data frame with 3yr comparisons)
#'   - headcount_series (data frame for sparkline, or NULL)
#'   - plots$cross_dept_minors (plotly donut)
#'   - credit_hour_shifts (data frame of selected-term SCH departures)
#'   - new_courses (data frame or NULL)
#'   - dormant_courses (data frame or NULL)
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
  home <- keep_home_sections(rows)
  list(
    n_sections = nrow(home),
    total_enrl = if (nrow(home) > 0 && "total_enrl" %in% names(home))
                   sum(home$total_enrl, na.rm = TRUE) else 0L
  )
}


create_dept_dashboard_data <- function(data_objects, opt) {
  dept_raw <- opt[["dept_code"]]
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

  # Selected-term snapshot. The term picker (opt$term) drives every single-term
  # section below. Falls back to cedar_current_term, then to the max term in
  # history, when no term is supplied (tests, API, older callers).
  current_term <- opt[["term"]]
  if (is.null(current_term) || length(current_term) == 0 || is.na(current_term)) {
    current_term <- if (exists("cedar_current_term")) cedar_current_term else max(cedar_programs$term, na.rm = TRUE)
  }
  current_term <- as.integer(current_term)
  message("[dept-dashboard.R] snapshot term: ", current_term)
  # Record the resolved term so the UI can label the snapshot and flag
  # in-progress (current/future) semesters, independent of later input changes.
  result$current_term <- current_term

  programs_for_hc <- dplyr::filter(cedar_programs, term <= current_term)

  result$headcount_summary <-
    get_headcount_summary(programs_for_hc, dept_code, current_term = current_term)

  result$headcount_series <-
    get_headcount_series(programs_for_hc, dept_code, current_term)

  result$credit_hour_shifts <- get_dashboard_credit_hour_shifts(
    cedar_students, dept_code, current_term, campus = campus
  )

  # Build course enrollment history via get_enrl (one row per course per campus per
  # term, enrolled > 0). crosslist = "home" keeps only home-dept sections; uel = TRUE
  # drops thesis/dissertation/honors. campus is in group_cols because campuses are
  # never merged: in "all campuses" views each campus compares to its own history
  # (see the CAMPUS RULE note above the snapshot functions).
  ch_opt <- list(dept_code = dept_code, status = "A", crosslist = "home", uel = TRUE,
                 group_cols = c("subject_course", "course_title", "campus", "term", "is_topics"))
  if (!is.null(campus) && length(campus) > 0) ch_opt$course_campus <- campus
  # ungroup: get_enrl returns grouped data (see filter/dplyr gotchas in AGENTS.md)
  course_history <- get_enrl(cedar_sections, ch_opt) %>%
    dplyr::ungroup() %>% dplyr::filter(enrolled > 0)

  result$current_enrl_vs_avg    <- get_current_enrl_vs_avg(course_history, current_term)
  result$enrollment_flags       <- get_dashboard_enrollment_flags(
    cedar_sections, course_history, dept_code, current_term, campus = campus,
    cedar_students = cedar_students
  )
  result$regstats_flags         <- get_reg_stats(
    cedar_students, cedar_sections,
    list(
      shiny = TRUE,
      dept_code = dept_code,
      course_campus = campus,
      term = current_term,
      threshold_profile = "dashboard"
    )
  )
  result$new_this_term          <- get_new_this_term(course_history, current_term)
  result$missing_from_earlier   <- get_missing_from_earlier(course_history, current_term)
  result$repeated_topics        <- get_repeated_topics_courses(course_history, current_term)
  result$composition_shifts     <- get_dashboard_composition_shifts(
    cedar_students, cedar_sections, cedar_programs, dept_code, current_term, campus = campus
  )

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
