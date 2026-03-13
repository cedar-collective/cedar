# population-trend.R — Cone for Student Population Trend
#
# Shows how the mix of entry types (First-Time Freshman, Transfer, Readmit, etc.)
# for NEW majors in a department has changed over time.
# Each student is counted once — at the term they first appear as a major in the dept.
#
# Visualization: proportional stacked bar chart (each bar = one term, sums to 100%).
# This makes it easy to spot if e.g. transfer share is growing while FTF shrinks.
#
# Requires: cedar_programs with student_population column.
# Re-run transform-to-cedar.R to regenerate cedar_programs.qs after the schema change.


#' Recode verbose Banner student_population strings to concise categories
#'
#' @param x Character vector of raw student_population values.
#' @return Character vector of simplified category labels.
.recode_population <- function(x) {
  case_when(
    grepl("First Time.*Freshman|Beginning Freshman", x, ignore.case = TRUE) ~ "First-Time Freshman",
    grepl("Transfer",         x, ignore.case = TRUE)                        ~ "Transfer",
    grepl("Branch to Main",   x, ignore.case = TRUE)                        ~ "Transfer",      # branch→main = internal transfer
    grepl("Readmit",          x, ignore.case = TRUE)                        ~ "Readmit",
    grepl("Continuing",       x, ignore.case = TRUE)                        ~ "Continuing",
    grepl("Level Change",     x, ignore.case = TRUE)                        ~ "Other",
    grepl("Concurrent",       x, ignore.case = TRUE)                        ~ "Other",
    is.na(x) | x == ""                                                      ~ "Unknown",
    TRUE                                                                     ~ "Other"
  )
}


#' Plot student population mix over time for a department's majors
#'
#' @param programs cedar_programs data frame (must include student_population).
#' @param dept_code Department code (e.g., "HIST", "GES").
#' @param program_type Which program type to include. Default "Major" (primary majors only).
#'   Pass NULL to include all types (majors + minors + concentrations).
#' @param student_level Filter to "Undergraduate" (default) or NULL for all levels.
#' @return A ggplot proportional stacked bar chart.
make_population_trend <- function(programs,
                                  dept_code,
                                  program_type  = "Major",
                                  student_level = "Undergraduate") {

  if (!"student_population" %in% names(programs)) {
    stop("cedar_programs does not have a student_population column. ",
         "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
  }

  pop_levels <- c("First-Time Freshman", "Transfer", "Continuing", "Readmit", "Other", "Unknown")
  pop_colors <- c(
    "First-Time Freshman" = "#0072B2",
    "Transfer"            = "#E69F00",
    "Continuing"          = "#009E73",
    "Readmit"             = "#CC79A7",
    "Other"               = "#999999",
    "Unknown"             = "#DDDDDD"
  )

  # Build pre-major vs. declared-major lookup from program_catalog.
  # program_catalog$program_type is "degree", "pre_major", or "variant".
  pc_status <- program_catalog %>%
    dplyr::distinct(program_code, program_type) %>%
    dplyr::mutate(major_status = dplyr::case_when(
      program_type == "pre_major" ~ "Pre-Major",
      program_type == "degree"    ~ "Declared Major",
      TRUE                        ~ NA_character_   # variants excluded below
    )) %>%
    dplyr::select(program_code, major_status)

  df <- programs %>%
    dplyr::filter(dept_code == .env$dept_code) %>%
    dplyr::left_join(pc_status, by = "program_code") %>%
    dplyr::filter(!is.na(major_status))   # drop variant codes

  if (!is.null(program_type))
    df <- df %>% dplyr::filter(program_type == .env$program_type)

  if (!is.null(student_level))
    df <- df %>% dplyr::filter(startsWith(student_level, .env$student_level))

  if (nrow(df) == 0) {
    warning("No rows found for dept_code = ", dept_code)
    return(ggplot2::ggplot() + ggplot2::labs(title = paste("No data for", dept_code)))
  }

  # Keep only each student's FIRST term in each major_status bucket.
  # A student can appear twice — once as a pre-major, once after declaring.
  plot_df <- df %>%
    dplyr::group_by(student_id, major_status) %>%
    dplyr::slice_min(order_by = term, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      population  = factor(.recode_population(student_population), levels = pop_levels),
      term_label  = fmt_term(term),
      major_status = factor(major_status, levels = c("Pre-Major", "Declared Major"))
    ) %>%
    dplyr::count(term, term_label, major_status, population) %>%
    dplyr::group_by(term, major_status) %>%
    dplyr::mutate(pct = n / sum(n)) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(term_label = factor(term_label, levels = unique(term_label[order(term)])))

  ggplot2::ggplot(plot_df,
                  ggplot2::aes(x = term_label, y = pct, fill = population)) +
    ggplot2::geom_col(width = 0.85) +
    ggplot2::facet_wrap(~ major_status, ncol = 1) +
    ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                                expand = ggplot2::expansion(mult = c(0, 0.02))) +
    ggplot2::scale_fill_manual(values = pop_colors, drop = TRUE) +
    ggplot2::labs(
      title = paste("Student Population Mix —", dept_code),
      x     = NULL,
      y     = "Share of New Entrants",
      fill  = "Entry Type"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.x     = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position = "right"
    )
}
