# retention-summaries.R — Shaping over an already-computed retention result
#
# Every function here takes the wide tibble a retention cone returns and reshapes
# it: pooling like term types, comparing a course against dept/college
# benchmarks, ranking instructors, or applying the cohort-size floor. None of
# them recomputes retention, and none of them calls a retention cone — they
# operate on its output.
#
# Split out of R/cones/course-retention.R.
#
# Depends on: retention results from R/cones/course-retention.R

# Apply the same cohort-size rule to an already computed trend. This lets the
# app retain unsuppressed term rows for term-type pooling while deriving the
# ordinary course table without repeating the analytical calculation.
filter_retention_min_n <- function(retention_result, min_n) {
  if (is.null(retention_result) || nrow(retention_result) == 0L) {
    return(retention_result)
  }
  dplyr::filter(retention_result, n >= as.integer(.env$min_n))
}


#' Summarize term-level retention rates across like term types
#'
#' Converts the term rows returned by `get_retention_trend()` into stable
#' Fall/Spring/Summer summaries. Rates are weighted by the starting cohort size,
#' so a 100-student term contributes more than a 10-student term. Each horizon
#' uses only terms for which that future term is observable; `eligible_N`
#' records the corresponding denominator.
#'
#' Campus is always part of the grouping key. When `by_instructor` is TRUE,
#' instructor identity is preserved as well.
#'
#' @param retention_result Result from `get_retention_trend()` or
#'   `get_dept_retention_trend()`.
#' @param by_instructor Logical; aggregate separately by instructor.
#' @param min_n Integer; minimum pooled cohort size for a summary row and for
#'   each displayed horizon. Small individual terms may contribute to a pooled
#'   row as long as the pooled denominator meets this threshold.
#'
#' @return One row per campus and term type, optionally per instructor, with
#'   `terms`, `n`, `ret_1 ... ret_N`, and `eligible_1 ... eligible_N`.
summarize_retention_by_term_type <- function(retention_result,
                                              by_instructor = FALSE,
                                              min_n = 1L) {
  if (is.null(retention_result) || nrow(retention_result) == 0) {
    return(tibble::tibble())
  }

  required <- c("campus", "term", "n")
  missing_cols <- setdiff(required, names(retention_result))
  if (length(missing_cols) > 0) {
    stop(
      "[course-retention.R] summarize_retention_by_term_type: missing required columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  ret_cols <- grep("^ret_\\d+$", names(retention_result), value = TRUE)
  if (length(ret_cols) == 0) return(tibble::tibble())
  min_n <- max(1L, as.integer(min_n))

  instructor_cols <- character()
  if (isTRUE(by_instructor)) {
    if (!"instructor_id" %in% names(retention_result)) {
      stop(
        "[course-retention.R] summarize_retention_by_term_type: ",
        "instructor_id is required when by_instructor = TRUE."
      )
    }
    instructor_cols <- "instructor_key"
  }

  data <- retention_result %>%
    mutate(
      term_type = get_term_type(term),
      term_type_label = dplyr::recode(
        term_type,
        fall = "Fall",
        spring = "Spring",
        summer = "Summer",
        .default = NA_character_
      ),
      cohort_n = as.numeric(n)
    ) %>%
    filter(!is.na(term_type))

  if (isTRUE(by_instructor)) {
    if (!"instructor_name" %in% names(data)) {
      data$instructor_name <- NA_character_
    }
    data <- data %>%
      mutate(
        instructor_id = trimws(as.character(instructor_id)),
        instructor_name = trimws(as.character(instructor_name)),
        instructor_key = case_when(
          !is.na(instructor_id) & nzchar(instructor_id) ~ paste0("id:", instructor_id),
          !is.na(instructor_name) & nzchar(instructor_name) ~
            paste0("name:", tolower(instructor_name)),
          TRUE ~ "unknown"
        )
      )
  }

  group_cols <- c("campus", "term_type", "term_type_label", instructor_cols)
  summary <- data %>%
    group_by(across(all_of(group_cols))) %>%
    summarize(
      terms = n_distinct(term),
      n = sum(cohort_n, na.rm = TRUE),
      .groups = "drop"
    )

  # Instructor names can vary across terms (middle initials, capitalization,
  # trailing spaces). Aggregate on the stable ID and use the latest available
  # display name rather than fragmenting one person's history by label text.
  if (isTRUE(by_instructor)) {
    instructor_labels <- data %>%
      arrange(desc(term)) %>%
      group_by(across(all_of(group_cols))) %>%
      summarize(
        instructor_id = dplyr::first(instructor_id),
        instructor_name = dplyr::first(instructor_name),
        .groups = "drop"
      )
    summary <- summary %>%
      left_join(instructor_labels, by = group_cols)
  }

  # Build each horizon independently because recent anchor terms may be
  # observable at +1 but not +2 (and so on). This keeps both the weighted rate
  # and its denominator honest for every column.
  for (ret_col in ret_cols) {
    horizon <- sub("^ret_", "", ret_col)
    eligible_col <- paste0("eligible_", horizon)
    horizon_summary <- data %>%
      filter(!is.na(.data[[ret_col]]), !is.na(cohort_n), cohort_n > 0) %>%
      group_by(across(all_of(group_cols))) %>%
      summarize(
        !!ret_col := stats::weighted.mean(.data[[ret_col]], cohort_n),
        !!eligible_col := sum(cohort_n),
        .groups = "drop"
      )
    summary <- summary %>%
      left_join(horizon_summary, by = group_cols)
  }

  for (ret_col in ret_cols) {
    eligible_col <- paste0("eligible_", sub("^ret_", "", ret_col))
    summary <- summary %>%
      mutate(
        !!ret_col := if_else(
          !is.na(.data[[eligible_col]]) & .data[[eligible_col]] >= min_n,
          .data[[ret_col]],
          NA_real_
        )
      )
  }

  summary %>%
    filter(n >= min_n) %>%
    mutate(
      .term_type_order = match(term_type, c("fall", "spring", "summer")),
      n = as.integer(n),
      across(starts_with("eligible_"), as.integer)
    ) %>%
    arrange(campus, .term_type_order, across(any_of("instructor_name"))) %>%
    select(-.term_type_order, -any_of("instructor_key"))
}

compare_retention_to_benchmarks <- function(course_result, dept_result = NULL,
                                             college_result = NULL,
                                             n_terms = NULL) {
  if (is.null(course_result) || nrow(course_result) == 0) return(tibble::tibble())
  ret_cols <- grep("^ret_\\d+$", names(course_result), value = TRUE)
  if (length(ret_cols) == 0) return(tibble::tibble())
  if (!is.null(n_terms)) ret_cols <- intersect(ret_cols, paste0("ret_", seq_len(n_terms)))

  # Campus joins the key whenever both sides carry it. Without it a course row
  # for one campus matches the benchmark row for every campus in the same term,
  # fanning out and comparing a course against the wrong cohort.
  join_keys <- c("term", "horizon", "horizon_n")
  use_campus <- "campus" %in% names(course_result) &&
    all(vapply(list(dept_result, college_result), function(d) {
      is.null(d) || nrow(d) == 0 || "campus" %in% names(d)
    }, logical(1)))
  if (use_campus) join_keys <- c("campus", join_keys)

  course_long <- course_result %>%
    select(any_of("campus"), term, term_label, n_course = n, all_of(ret_cols)) %>%
    tidyr::pivot_longer(
      cols = all_of(ret_cols),
      names_to = "horizon",
      values_to = "course_retention"
    ) %>%
    mutate(horizon_n = as.integer(gsub("^ret_", "", horizon)))

  benchmark_long <- function(df, label) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    cols <- intersect(ret_cols, names(df))
    if (length(cols) == 0) return(NULL)
    df %>%
      select(any_of("campus"), term, n_benchmark = n, all_of(cols)) %>%
      tidyr::pivot_longer(
        cols = all_of(cols),
        names_to = "horizon",
        values_to = "benchmark_retention"
      ) %>%
      mutate(
        benchmark = label,
        horizon_n = as.integer(gsub("^ret_", "", horizon))
      )
  }

  benchmarks <- bind_rows(
    benchmark_long(dept_result, "Department"),
    benchmark_long(college_result, "College")
  )
  if (is.null(benchmarks) || nrow(benchmarks) == 0) return(tibble::tibble())

  compared <- course_long %>%
    inner_join(benchmarks, by = join_keys) %>%
    mutate(
      diff_pct = round((course_retention - benchmark_retention) * 100, 1),
      row_label = paste0(benchmark, " +", horizon_n),
      course_retention_pct = round(course_retention * 100, 1),
      benchmark_retention_pct = round(benchmark_retention * 100, 1)
    ) %>%
    filter(!is.na(diff_pct))

  if (use_campus) {
    compared %>% arrange(campus, term, benchmark, horizon_n)
  } else {
    compared %>% arrange(term, benchmark, horizon_n)
  }
}

summarize_instructor_retention_rows <- function(retention_result, top_n = 10L,
                                                min_n = 1L) {
  if (is.null(retention_result) || nrow(retention_result) == 0 ||
      !"instructor_id" %in% names(retention_result)) {
    return(list(top = NULL, bottom = NULL))
  }
  # The review list is intentionally based on stable instructor-by-term-type
  # summaries, not isolated semesters. Already-aggregated input is accepted so
  # callers can reuse a prepared table.
  if (!all(c("term_type", "terms") %in% names(retention_result))) {
    retention_result <- summarize_retention_by_term_type(
      retention_result,
      by_instructor = TRUE,
      min_n = min_n
    )
  }

  ret_cols <- grep("^ret_\\d+$", names(retention_result), value = TRUE)
  if (length(ret_cols) == 0) return(list(top = NULL, bottom = NULL))

  row_score <- vapply(seq_len(nrow(retention_result)), function(i) {
    rates <- as.numeric(unlist(retention_result[i, ret_cols], use.names = FALSE))
    eligible_cols <- paste0("eligible_", sub("^ret_", "", ret_cols))
    if (all(eligible_cols %in% names(retention_result))) {
      weights <- as.numeric(unlist(
        retention_result[i, eligible_cols],
        use.names = FALSE
      ))
      keep <- !is.na(rates) & !is.na(weights) & weights > 0
      if (!any(keep)) return(NA_real_)
      return(stats::weighted.mean(rates[keep], weights[keep]))
    }
    rates <- rates[!is.na(rates)]
    if (length(rates) == 0L) NA_real_ else mean(rates)
  }, numeric(1))

  ranked <- retention_result %>%
    mutate(avg_retention = row_score) %>%
    filter(!is.na(avg_retention)) %>%
    arrange(desc(avg_retention), desc(n))

  if (nrow(ranked) == 0) return(list(top = NULL, bottom = NULL))

  top_n <- max(1L, as.integer(top_n))
  list(
    top = ranked %>% slice_head(n = top_n),
    bottom = ranked %>% arrange(avg_retention, desc(n)) %>% slice_head(n = top_n)
  )
}
