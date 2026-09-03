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
#
# Depends on: term_code_to_axis_label() (trunk/utils.R)
# Requires:   cedar_programs$is_pre_major column (set by transform-to-cedar.R)


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
get_population_trend_data <- function(programs,
                                      dept_code,
                                      program_type = "Major",
                                      student_level = "Undergraduate") {
  if (!"student_population" %in% names(programs)) {
    stop("cedar_programs does not have a student_population column. ",
         "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
  }

  pop_levels <- c("First-Time Freshman", "Transfer", "Continuing", "Readmit", "Other", "Unknown")
  # Determine pre-major vs. declared-major from the is_pre_major column,
  # which is set at transform time by detecting the "Pre " / "Pre-" prefix.
  df <- programs %>%
    filter(dept_code == .env$dept_code) %>%
    mutate(major_status = if_else(is_pre_major, "Pre-Major", "Declared Major"))

  if (!is.null(program_type))
    df <- df %>% filter(program_type == .env$program_type)

  if (!is.null(student_level))
    df <- df %>% filter(startsWith(student_level, .env$student_level))

  if (nrow(df) == 0) {
    warning("No rows found for dept_code = ", dept_code)
    return(tibble::tibble())
  }

  message("[population-trend.R] ", n_distinct(df$student_id),
          " students across ", n_distinct(df$term), " terms")

  # Keep only each student's FIRST term in each major_status bucket.
  # A student can appear twice — once as a pre-major, once after declaring.
  df %>%
    group_by(student_id, major_status) %>%
    slice_min(order_by = term, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    mutate(
      population   = factor(.recode_population(student_population), levels = pop_levels),
      term_label   = term_code_to_axis_label(term),
      major_status = factor(major_status, levels = c("Pre-Major", "Declared Major"))
    ) %>%
    count(term, term_label, major_status, population) %>%
    group_by(term, major_status) %>%
    mutate(pct = n / sum(n)) %>%
    ungroup()
}

plot_population_trend_data <- function(plot_df, dept_code) {
  if (is.null(plot_df) || nrow(plot_df) == 0) {
    return(ggplot() + labs(title = paste("No data for", dept_code)))
  }

  pop_colors <- c(
    "First-Time Freshman" = "#0072B2",
    "Transfer"            = "#E69F00",
    "Continuing"          = "#009E73",
    "Readmit"             = "#CC79A7",
    "Other"               = "#999999",
    "Unknown"             = "#DDDDDD"
  )
  plot_df <- plot_df %>%
    mutate(
      population = factor(population, levels = names(pop_colors)),
      major_status = factor(major_status, levels = c("Pre-Major", "Declared Major")),
      term_label = factor(term_label, levels = unique(term_label[order(term)]))
    )

  message("[population-trend.R] Plot data: ", nrow(plot_df), " rows")

  ggplot(plot_df, aes(x = term_label, y = pct, fill = population)) +
    geom_col(width = 0.85) +
    facet_wrap(~ major_status, ncol = 1) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                       expand = expansion(mult = c(0, 0.02))) +
    scale_fill_manual(values = pop_colors, drop = TRUE) +
    labs(
      title = paste("Student Population Mix —", dept_code),
      x     = NULL,
      y     = "Share of New Entrants",
      fill  = "Entry Type"
    ) +
    theme_minimal() +
    theme(
      axis.text.x     = element_text(angle = 45, hjust = 1),
      legend.position = "right"
    )
}

make_population_trend <- function(programs,
                                  dept_code,
                                  program_type  = "Major",
                                  student_level = "Undergraduate") {
  message("[population-trend.R] Welcome to make_population_trend! dept_code = ", dept_code)
  plot_df <- get_population_trend_data(
    programs, dept_code, program_type, student_level
  )
  message("[population-trend.R] Plot data: ", nrow(plot_df), " rows")
  plot_population_trend_data(plot_df, dept_code)
}
