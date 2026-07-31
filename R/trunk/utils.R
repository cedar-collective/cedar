# this file provides miscellaneous functions used across CEDAR



resolve_conflicts <- function() {
  conflicted::conflicts_prefer(dplyr::filter())
  conflicted::conflicts_prefer(dplyr::lag())
  conflicted::conflicts_prefer(plotly::layout)
}


#' Validate that a population data frame has the required columns
#'
#' Throws a descriptive error if `population` is missing `student_id` or
#' `population_label`. Call at the top of any cone function that accepts a
#' population argument to fail fast with a clear message.
#'
#' @param population Data frame. Must have columns `student_id` and
#'   `population_label`. Use `build_population()` to create it.
#' @param caller Character. Name of the calling function for the error message
#'   (e.g., "get_stopout").
#' @return Invisible NULL. Called for its side-effect (stops on bad input).
validate_population <- function(population, caller) {
  if (!all(c("student_id", "population_label") %in% names(population))) {
    stop("[", caller, "] population must have columns: student_id, population_label. ",
         "Use build_population() to create it.")
  }
  invisible(NULL)
}


#' Add academic year column based on term codes
#'
#' This function takes a data frame and a column containing term codes (e.g., "202380" for Fall 2023)
#' and adds a new column `acad_year` representing the academic year (e.g., "2023-2024").
#' The academic year is determined by the semester code:
#'   - "80" (fall): academic year starts with the term year
#'   - "10" (spring) and "60" (summer): academic year ends with the term year
#' If the semester code is not recognized, NA is assigned.
#'
#' @param df Data frame containing term codes
#' @param term_col Column name (unquoted or quoted) containing term codes
#' @return Data frame with added `acad_year` column
add_acad_year <- function(df, term_col) {
  # Convert column name to symbol for robust referencing
  term_col_sym <- rlang::ensym(term_col)
  # Extract term codes as character vector
  term_vals <- as.character(df[[as.character(term_col_sym)]])
  # Get year (first 4 digits) and semester (last 2 digits)
  year <- substr(term_vals, 1, 4)
  sem <- substr(term_vals, 5, 6)
  # Assign academic year based on semester code
  acad_year <- dplyr::case_when(
    sem == "80" ~ paste0(year, "-", as.integer(year) + 1),   # Fall: year-year+1
    sem == "10" ~ paste0(as.integer(year) - 1, "-", year),   # Spring: year-1-year
    sem == "60" ~ paste0(as.integer(year) - 1, "-", year),   # Summer: year-1-year
    TRUE ~ NA_character_                                        # Unrecognized code: NA
  )
  # Add acad_year column to data frame
  df$acad_year <- acad_year
  return(df)
}


# Function to check if running in Docker
is_docker <- function() {
  file.exists("/.dockerenv") ||
    (file.exists("/proc/1/cgroup") && any(grepl("docker|containerd", readLines("/proc/1/cgroup"))))
}


# add prev term col
add_prev_term_col <- function(df, term_col_name, summer = FALSE) {
  term_col <- rlang::ensym(term_col_name)
  term_str <- as.character(df[[as.character(term_col)]])
  term_part <- substr(term_str, 5, 6)
  term_int <- as.integer(term_str)
  
  if (summer) {
    df$prev_term <- ifelse(
      term_part == "80", term_int - 20,
      ifelse(term_part == "10", term_int - 30,
      ifelse(term_part == "60", term_int - 50, NA_integer_))
    )
  } else {
    df$prev_term <- ifelse(
      term_part == "80", term_int - 70,
      ifelse(term_part == "10", term_int - 30,
      ifelse(term_part == "60", term_int - 50, NA_integer_))
    )
  }
  return(df)
}

# add next term col
add_next_term_col <- function(df, term_col_name, summer = FALSE) {
  # Term codes are YYYYSS integers where SS = 10 (Spring), 60 (Summer), 80 (Fall).
  # The offsets below are SS-delta arithmetic: adding to YYYYSS rolls into the next
  # year when the suffix exceeds 99 (e.g., YYYY80 + 30 = YYYY110 = (YYYY+1)10).
  #   Fall(80)   → Spring:        +30  (80+30 = 110 → next year Spring)
  #   Spring(10) → Summer:        +50  (10+50 = 60)
  #   Spring(10) → Fall:          +70  (10+70 = 80)
  #   Summer(60) → Fall:          +20  (60+20 = 80)
  term_col <- rlang::ensym(term_col_name)
  term_str <- as.character(df[[as.character(term_col)]])
  term_part <- substr(term_str, 5, 6)
  term_int <- as.integer(term_str)

  if (summer) {
    df$next_term <- ifelse(
      term_part == "80", term_int + 30,   # Fall   → Spring (next year)
      ifelse(term_part == "10", term_int + 50,   # Spring → Summer
      ifelse(term_part == "60", term_int + 20,   # Summer → Fall
      NA_integer_))
    )
  } else {
    df$next_term <- ifelse(
      term_part == "80", term_int + 30,   # Fall   → Spring (next year)
      ifelse(term_part == "10", term_int + 70,   # Spring → Fall (skip summer)
      ifelse(term_part == "60", term_int + 20,   # Summer → Fall
      NA_integer_))
    )
  }
  return(df)
}


# find the previous semester code
# default to ignoring summer terms
subtract_term <- function (term_code, summer = FALSE) {
  
  # separate year and semester code from given term code
  year <- as.integer(substring(term_code,1,4))
  term <- as.integer(substring(term_code,5,6))
  
  if (term == 80) {
    if (summer) {
      prev_term <- as.integer(paste0(year,"60"))
    }
    else {
      prev_term <- as.integer(paste0(year,"10"))
    }
  } 
  else if (term == 60) {
    prev_term <- as.integer(paste0(year,"10"))
  } 
  else if (term == 10) {
    prev_term <- as.integer(paste0(year-1,"80"))
  }
  
  return(prev_term)
  
} # end subtract_term


# determine next term code; default is to ignore summer terms
add_term <- function (term_code,summer=F) {
  term <- as.integer(substring(term_code,5,6))
  year <- as.integer(substring(term_code,1,4))
  
  if (summer) {
    if (term == 80) {
      term_m1 <- as.integer(paste0(year+1,"10",sep=""))
    } 
    else if (term == 60) {
      term_m1 <- as.integer(paste0(year,"80",sep=""))
    } 
    else if (term == 10) {
      term_m1 <- as.integer(paste0(year,"60",sep=""))
    }
  }
  else {
    if (term == 80) {
      term_m1 <- as.integer(paste0(year+1,"10",sep=""))
    } else {
      term_m1 <- as.integer(paste0(year,"80",sep=""))
    }
  }

  return(term_m1)
}


# Default term for the registration-facing tabs (Open Seats, Waitlists,
# Cancellations, Regstats). These all want to open on the same term so users
# don't have to re-pick it per tab.
#
# Until registration for the next term is actually underway, they default to
# the current term: a schedule can be built (and its sections loaded) months
# before registration opens, so defaulting to next term early would present
# preliminary, half-built data as if it were real. `registration_underway` is
# the manual switch (cedar_registration_underway) the admin flips once
# registration opens.
#
# The only ambiguous step is Spring -> (Summer vs Fall): both open for
# registration at the same time in the spring. Summer is the default until
# summer registration effectively closes in mid-June (`summer_cutoff`), after
# which Fall becomes the default. Every other step (Summer -> Fall,
# Fall -> next Spring) is unambiguous.
#
# summer_cutoff is an "MM-DD" string; the comparison year comes from the term
# being registered for, not the wall clock, so stale config degrades sanely.
get_default_reg_term <- function(current_term,
                                 registration_underway,
                                 today = Sys.Date(),
                                 summer_cutoff = "06-15") {
  current_term <- as.integer(current_term)
  if (!isTRUE(registration_underway)) return(current_term)

  season <- current_term %% 100L

  if (season == 10L) {                              # Spring: Summer and Fall both open
    term_year <- current_term %/% 100L
    cutoff    <- as.Date(sprintf("%d-%s", term_year, summer_cutoff))
    if (today > cutoff) {
      return(add_term(current_term))                # Spring -> Fall (skips summer)
    }
    return(add_term(current_term, summer = TRUE))   # Spring -> Summer
  }

  # Summer -> Fall and Fall -> next Spring: keep the summer link so Summer
  # advances to Fall rather than being skipped.
  add_term(current_term, summer = TRUE)
}

resolve_default_term_choice <- function(available_terms = NULL,
                                        default_term = NULL,
                                        fallback_term = NULL) {
  coerce_term <- function(x) {
    if (is.null(x) || length(x) == 0) return(NA_integer_)
    suppressWarnings(as.integer(unname(x)[[1]]))
  }

  terms <- suppressWarnings(as.integer(unname(available_terms)))
  terms <- sort(unique(terms[!is.na(terms)]))

  for (candidate in c(coerce_term(default_term), coerce_term(fallback_term))) {
    if (is.na(candidate)) next
    if (length(terms) == 0 || candidate %in% terms) return(candidate)
  }

  if (length(terms) > 0) return(max(terms))
  NULL
}


add_term_type_col <- function(df, term_col_name) {
  message("adding term type col...")
  term_col <- rlang::ensym(term_col_name)
  term_vals <- as.character(df[[as.character(term_col)]])
  sem <- substr(term_vals, 5, 6)
  df$term_type <- dplyr::case_when(
    sem == "80" ~ "fall",
    sem == "10" ~ "spring",
    sem == "60" ~ "summer",
    TRUE ~ NA_character_
  )
  return(df)
}


#' Convert a Banner "Academic Period" text label to an integer term code
#'
#' Parses the human-readable label produced by MyReports/Banner academic studies
#' exports (e.g. "Fall 2025", "Spring 2026", "Summer 2025") and returns the
#' corresponding integer term code used throughout CEDAR (e.g. 202580, 202610,
#' 202560).  Vectorised; NA is returned for unrecognised input.
#'
#' This is the canonical conversion; call it from transform-to-cedar.R instead
#' of duplicating the regex + case_when there.
#'
#' @param academic_period Character vector of Academic Period labels.
#' @return Integer vector of term codes.
#'
#' @examples
#' academic_period_to_term(c("Fall 2025", "Spring 2026", "Summer 2025"))
#' # [1] 202580 202610 202560
academic_period_to_term <- function(academic_period) {
  year   <- as.integer(sub(".*(\\d{4})$", "\\1", academic_period))
  season <- sub("^(\\w+)\\s.*", "\\1", academic_period)
  suffix <- dplyr::case_when(
    season == "Fall"   ~ 80L,
    season == "Spring" ~ 10L,
    season == "Summer" ~ 60L,
    TRUE               ~ NA_integer_
  )
  dplyr::if_else(!is.na(year) & !is.na(suffix), year * 100L + suffix, NA_integer_)
}


# determine term type from term code
get_term_type <- function (term_code) {
  term_type <- case_when(
    substring(term_code,5,6) == 80 ~ "fall",
    substring(term_code,5,6) == 10 ~ "spring",
    substring(term_code,5,6) == 60 ~ "summer"
  )
  return (term_type)
}


#' Format a term code as a readable label
#'
#' Converts an integer term code (e.g. 202280) to a human-readable string
#' (e.g. "Fall 2022"). Used throughout the dashboard UI for display.
#'
#' @param term_code Integer or numeric term code in YYYYTT format.
#' @return Character string like "Fall 2022", "Spring 2023", "Summer 2023".
fmt_term <- function(term_code) {
  yr  <- floor(term_code / 100)
  tt  <- term_code %% 100
  season <- case_when(
    tt == 10 ~ "Spring",
    tt == 60 ~ "Summer",
    tt == 80 ~ "Fall",
    TRUE     ~ as.character(tt)
  )
  paste(season, yr)
}


# Add sequential term bin column (1 = earliest term in df, 2 = next, etc.)
# Useful for creating linear models over time.
# include_summer = TRUE matches the calendar (Spring=1, Summer=2, Fall=3 within a year gap).
add_term_bins <- function(df, term_col_name) {
  term_vals <- as.integer(df[[term_col_name]])
  min_term  <- min(term_vals, na.rm = TRUE)
  df$term_bin <- term_diff(min_term, term_vals, include_summer = TRUE) + 1L
  return(df)
}


#' Generate a named vector of term codes → term labels for a year range
#'
#' Returns a named character vector where names are term codes (e.g. "202510")
#' and values are human-readable labels (e.g. "Spring 2025").
#'
#' @param start_year First calendar year to include (integer, e.g. 2017).
#' @param end_year   Last calendar year to include (integer, e.g. 2032).
#' @param include_summer Logical. When TRUE (default) summer terms are included.
#' @return Named character vector: code → label, ordered chronologically.
#' @examples
#' seq <- make_term_sequence(2023, 2025)
#' names(seq)   # "202310" "202360" "202380" "202410" ...
#' seq[["202510"]]  # "Spring 2025"
make_term_sequence <- function(start_year, end_year, include_summer = TRUE) {
  years  <- seq.int(start_year, end_year)
  ss     <- if (include_summer) c(10L, 60L, 80L) else c(10L, 80L)
  season <- if (include_summer) c("Spring", "Summer", "Fall") else c("Spring", "Fall")
  n_ss   <- length(ss)
  codes  <- as.character(
    rep(years, each = n_ss) * 100L + rep(ss, times = length(years))
  )
  labels <- paste(
    rep(season, times = length(years)),
    rep(years,  each  = n_ss)
  )
  stats::setNames(labels, codes)
}


# Convert a term code to a human-readable label.
term_code_to_str <- function(term_code) {
  fmt_term(as.integer(term_code))
}


# Convert a term code to a short abbreviated label (e.g. 202680 → "Fa26").
abbr_term <- function(term_code) {
  tc <- as.integer(term_code)
  yr <- floor(tc / 100) %% 100
  tt <- tc %% 100
  season <- dplyr::case_when(
    tt == 10 ~ "Sp",
    tt == 60 ~ "Su",
    tt == 80 ~ "Fa",
    TRUE     ~ as.character(tt)
  )
  paste0(season, sprintf("%02d", yr))
}

# Convert term codes to the standard compact plot-axis label.
term_code_to_axis_label <- function(term_code) {
  tc <- suppressWarnings(as.integer(as.character(term_code)))
  yr <- floor(tc / 100) %% 100
  tt <- tc %% 100
  season <- dplyr::case_when(
    tt == 10 ~ "Sp",
    tt == 60 ~ "Su",
    tt == 80 ~ "Fa",
    TRUE     ~ as.character(tt)
  )
  ifelse(
    is.na(tc),
    as.character(term_code),
    paste(season, sprintf("%02d", yr))
  )
}

# Ordered compact labels for term axes.
term_axis_levels <- function(term) {
  term_chr <- as.character(term)
  term_chr <- term_chr[!is.na(term_chr) & term_chr != ""]
  term_num <- suppressWarnings(as.integer(term_chr))

  if (length(term_chr) == 0) {
    return(character(0))
  }

  if (all(!is.na(term_num))) {
    return(term_code_to_axis_label(sort(unique(term_num))))
  }

  sort(unique(term_chr))
}

term_axis_factor <- function(term) {
  factor(term_code_to_axis_label(term), levels = term_axis_levels(term), ordered = TRUE)
}


# Lookup data frame of all standard term codes.
# Used for merging with MyReports data that stores term labels as text.
# example: merged <- merge(term_code_lookup, table_w_term_text, by = 'term_code')
.tseq <- make_term_sequence(2015, 2035)
term_code_lookup <- data.frame(term_code = names(.tseq), Semester = unname(.tseq))
rm(.tseq)


#' Count terms between two term codes
#'
#' Converts each YYYYSS code to a linear term index and returns the difference.
#' Does not depend on num.labs, so it works for any valid term code.
#'
#' Without summer (default): Spring = 0, Fall = 1 within each year (2 per year).
#' With summer:              Spring = 0, Summer = 1, Fall = 2 (3 per year).
#'
#' @param from Integer term code (YYYYSS), e.g. 202510.
#' @param to   Integer term code (YYYYSS), e.g. 202580.
#' @param include_summer Logical. When FALSE (default), summer terms are
#'   excluded so Spring→Fall = 1 and Fall→Spring = 1.
#'   When TRUE, each summer counts as an additional term.
#' @return Integer vector (vectorized). NA when from or to is NA.
#' @examples
#' term_diff(202510, 202580)          # 1  (Spring → Fall, no summer)
#' term_diff(202580, 202610)          # 1  (Fall → next Spring)
#' term_diff(202510, 202610)          # 2  (Spring → next Spring)
#' term_diff(202510, 202580, TRUE)    # 2  (Spring → Fall, counting summer)
term_diff <- function(from, to, include_summer = FALSE) {
  .term_index <- function(t) {
    t    <- as.integer(t)
    yr   <- t %/% 100L
    ss   <- t %% 100L
    if (include_summer) {
      yr * 3L + dplyr::case_when(ss == 10L ~ 0L, ss == 60L ~ 1L, ss == 80L ~ 2L, TRUE ~ NA_integer_)
    } else {
      yr * 2L + dplyr::case_when(ss == 10L ~ 0L, ss == 80L ~ 1L, TRUE ~ NA_integer_)
    }
  }
  .term_index(to) - .term_index(from)
}


# convert a term code to a date object
# expects something like 202280 or 2023101H or 2020602H
term_code_to_date <- function(term) {
  year <- substring(term,1,4)
  semester <- substring(term,5,6)
  month <- case_when(
    semester == "80" ~ "09",
    semester == "10" ~ "02",
    semester == "60" ~ "06"
  )
  
  #always use 10th of month; maybe there's a better date for employment or enrollment checking
  date <- make_date(year,month,10)
  return(date)
}


# extract dept from course param
get_dept_from_course <- function (course) {
  dept <- subj_to_dept[[substring(course, 1, gregexpr(pattern = " ",course)[[1]] -1 ) ]]
  message("returning dept: ", dept)
  return(dept)
}





# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Trend direction
# ---------------------------------------------------------------------------

#' Compute trend direction from an ordered numeric vector
#'
#' Fits a linear model and classifies direction. Can be applied to any metric
#' over time: enrollment, headcount, credit hours, DFW rates, etc. The single
#' canonical slope helper — call this instead of hand-rolling
#' \code{coef(lm(v ~ seq_along(v)))}.
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


# Windowed trend comparison
# ---------------------------------------------------------------------------

#' Compute windowed trend statistics for a single time series
#'
#' Generalizes the windowed comparison used in compute_major_sch_trends():
#' compares the average of the most recent `top_n_terms` main (non-summer) terms
#' against equally sized windows from 1, 2, and 4 years ago.
#'
#' Intended to be called inside dplyr::group_modify() so that comparison window
#' positions are anchored to the full dataset's term range, not the individual
#' group's observed terms.
#'
#' @param series        Data frame with integer `term` and numeric `value` cols.
#' @param all_main_terms Sorted integer vector of non-summer terms from the full
#'   dataset (not just this series — keeps window positions aligned across groups).
#' @param top_n_terms   Window width in terms (default 2L = fall + spring).
#' @return Named list:
#'   recent_avg     — mean value in the most recent `top_n_terms` window
#'   pct_1yr        — integer % change vs 1 year ago; NA if insufficient history
#'   pct_2yr        — integer % change vs 2 years ago; NA if insufficient history
#'   pct_4yr        — integer % change vs 4 years ago; NA if insufficient history
#'   abs_change_1yr — recent_avg minus year-ago avg, integer; NA if insufficient
#'   is_emerging    — TRUE when year-ago avg was 0/absent but recent_avg > 0
compute_windowed_trend <- function(series, all_main_terms, top_n_terms = 2L) {

  # Average of series$value for a given set of term codes.
  .win_avg <- function(terms_set) {
    vals <- series$value[series$term %in% terms_set]
    if (length(vals) == 0L) return(NA_real_)
    mean(vals, na.rm = TRUE)
  }

  # % change comparing the most recent window vs. the window n_years ago.
  # Returns NA_integer_ when there aren't enough terms in all_main_terms.
  .pct_change <- function(n_years) {
    step <- n_years * top_n_terms
    if (length(all_main_terms) < top_n_terms + step) return(NA_integer_)
    n         <- length(all_main_terms)
    r_avg     <- .win_avg(tail(all_main_terms, top_n_terms))
    ago_terms <- all_main_terms[seq(n - step - top_n_terms + 1L, n - step)]
    a_avg     <- .win_avg(ago_terms)
    if (is.na(a_avg) || a_avg == 0 || is.na(r_avg) || is.nan(r_avg)) return(NA_integer_)
    as.integer(round((r_avg - a_avg) / a_avg * 100))
  }

  r_avg <- .win_avg(tail(all_main_terms, top_n_terms))

  step_1yr        <- 1L * top_n_terms
  has_1yr_history <- length(all_main_terms) >= top_n_terms + step_1yr
  a_avg_1yr <- if (has_1yr_history) {
    n <- length(all_main_terms)
    .win_avg(all_main_terms[seq(n - step_1yr - top_n_terms + 1L, n - step_1yr)])
  } else {
    NA_real_
  }

  list(
    recent_avg     = r_avg,
    pct_1yr        = .pct_change(1L),
    pct_2yr        = .pct_change(2L),
    pct_4yr        = .pct_change(4L),
    abs_change_1yr = if (is.na(r_avg) || is.na(a_avg_1yr)) NA_integer_
                     else as.integer(round(r_avg - a_avg_1yr)),
    is_emerging    = has_1yr_history &&
                       !is.na(r_avg) && !is.nan(r_avg) && r_avg > 0 &&
                       (is.na(a_avg_1yr) || is.nan(a_avg_1yr) || a_avg_1yr == 0)
  )
}


# ---------------------------------------------------------------------------
# Enrollment deduplication
# ---------------------------------------------------------------------------

#' Deduplicate enrollment records
#'
#' Two levels of deduplication are supported:
#'
#'   "course"  One row per student × term × subject_course combination.
#'             Correct unit for pathway/timing/pairs analytics ("did the
#'             student take this course?"). Retains the row with the most
#'             informative final_grade (non-NA preferred, else first row).
#'
#'   "crn"     One row per student × term × crn combination.
#'             Correct unit for section-level grade analytics ("what grade did the
#'             student earn in this specific section?"). Handles students
#'             enrolled in multiple sections of the same subject_course
#'             (e.g., two sections of HIST 300 Topics).
#'
#' @param students A tibble containing at minimum: student_id, term,
#'   subject_course, crn, final_grade.
#' @param level Character. Either "course" (default) or "crn".
#' @return Deduplicated tibble with one row per the chosen grouping key.
dedup_enrollment <- function(students, level = c("course", "crn")) {
  level <- match.arg(level)

  if (level == "course") {
    students %>%
      dplyr::group_by(student_id, term, subject_course) %>%
      dplyr::arrange(dplyr::desc(!is.na(final_grade)), .by_group = TRUE) %>%
      dplyr::slice(1) %>%
      dplyr::ungroup()
  } else {
    students %>%
      dplyr::group_by(student_id, term, crn) %>%
      dplyr::arrange(dplyr::desc(!is.na(final_grade)), .by_group = TRUE) %>%
      dplyr::slice(1) %>%
      dplyr::ungroup()
  }
}


# ---------------------------------------------------------------------------
# Grade classification
# ---------------------------------------------------------------------------

#' Classify final grades into DFW / pass / incomplete outcome categories
#'
#' Uses the shared GRADES_DFW and GRADES_PASS constants from lists/grades.R.
#' Rows with a final_grade of NA or not found in either list are classified
#' as "unknown".
#'
#' Requires that lists/grades.R has been sourced before calling this function.
#'
#' @param students A tibble with a final_grade column.
#' @return The input tibble with a new `grade_outcome` column:
#'   "dfw"     — grade in GRADES_DFW
#'   "pass"    — grade in GRADES_PASS
#'   "unknown" — grade is NA or not in either list
classify_grades <- function(students) {
  students %>%
    dplyr::mutate(
      grade_outcome = dplyr::case_when(
        final_grade %in% GRADES_DFW  ~ "dfw",
        final_grade %in% GRADES_PASS ~ "pass",
        TRUE                          ~ "unknown"
      )
    )
}


#' Canonical pass/DFW classification of enrollment records
#'
#' The single source of truth for turning class-list rows into pass/DFW
#' outcomes (see "CEDAR-wide DFW policy" in AGENTS.md). Used by the
#' cedar_grades pre-computation in transform-to-cedar.R and by
#' classify_outcomes() in cones/stopout.R — do not re-implement this
#' classification inline elsewhere.
#'
#' Policy:
#' - DFW = D/F/W final grades (GRADES_DFW) plus late drops (STATUS_DROP_LATE,
#'   the registration-status form of a W — most W outcomes are recorded as
#'   DG/DW status rows, not as W grades under a registered status).
#' - Early drops (STATUS_DROP_EARLY) are NEVER DFW. A drop before the deadline
#'   posts no grade; it is registration churn, not an academic outcome. Early
#'   drops are tracked separately (dr_early, n_early_drop, early-drop rates).
#' - Rows that are neither registered nor late-dropped, and registered rows
#'   with no classifiable grade (incomplete, audit, blank), are excluded.
#'
#' Requires lists/grades.R and lists/status_codes.R to be sourced.
#'
#' @param students A tibble with registration_status_code and final_grade.
#' @return The input rows restricted to registered + late-drop records that
#'   have a classifiable outcome, with an added `outcome` column
#'   ("pass" or "dfw"). All other input columns are preserved.
classify_enrollment_outcomes <- function(students) {
  students %>%
    dplyr::filter(
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)
    ) %>%
    dplyr::mutate(
      outcome = dplyr::case_when(
        registration_status_code %in% STATUS_DROP_LATE ~ "dfw",
        final_grade %in% GRADES_DFW                    ~ "dfw",
        final_grade %in% GRADES_PASS                   ~ "pass",
        TRUE                                            ~ NA_character_
      )
    ) %>%
    dplyr::filter(!is.na(outcome))
}


# ---------------------------------------------------------------------------
# Categorical color mapping
# ---------------------------------------------------------------------------

#' CEDAR standard categorical color palette
#'
#' CEDAR nature categorical palette. These colors mirror the CSS design tokens
#' in www/cedar-custom.css and are used as the default for all build_color_map()
#' calls throughout CEDAR so categorical charts share a consistent visual
#' language regardless of which module renders them.
#'
#' Kept to medium-lightness, earthy tones on purpose: near-black/near-white
#' entries read as heavy or foreboding when they land on a data series (bar
#' fill, line) rather than their usual UI role (deep background, body text).
#'
#' ORDER MATTERS more than membership. Most CEDAR charts show 2-5 categories,
#' so the first five slots set the impression of the whole product. They are
#' ordered to stay inside one warm earth family (green -> brown -> olive ->
#' ochre -> terracotta, a 132-degree hue span) rather than leading with the
#' maximum-contrast green/blue/brown/gold/red spread, which spanned 207 degrees
#' and read as a generic spectral palette instead of cedar. Juniper blue is
#' still here as the sixth slot, where it lands as a deliberate accent.
#'
#' The three entries below 3:1 contrast on white (gold, light blue, tan) are
#' parked in slots 13-15 so a chart has to reach twelve categories before it
#' draws one. Every slot a normal chart touches clears WCAG 1.4.11 for
#' graphical objects.
CEDAR_PALETTE <- c(
  "#3F5E4B", "#6B4A2A", "#6B7F4F", "#B08D57", "#A15D4E",
  "#4D6FA8", "#6F8B78", "#523A20", "#4a6a55", "#6B7F8C",
  "#344D77", "#7a8a80", "#C7A96B", "#A8BDD9", "#c8bfb0"
)

CEDAR_COLORS <- c(
  green = "#3F5E4B",
  green_dark = "#2D4336",
  green_mid = "#4a6a55",
  green_light = "#6F8B78",
  blue = "#4D6FA8",
  blue_dark = "#344D77",
  blue_light = "#A8BDD9",
  brown = "#6B4A2A",
  brown_dark = "#523A20",
  gold = "#C7A96B",
  red = "#A15D4E",
  neutral = "#7a8a80",
  gray = "#cccccc",
  text = "#232826"
)

CEDAR_SEMANTIC_COLORS <- c(
  positive = unname(CEDAR_COLORS["green"]),
  neutral = unname(CEDAR_COLORS["blue"]),
  warning = unname(CEDAR_COLORS["brown"]),
  caution = unname(CEDAR_COLORS["gold"]),
  negative = unname(CEDAR_COLORS["red"]),
  reference = unname(CEDAR_COLORS["neutral"]),
  other = unname(CEDAR_COLORS["gray"])
)

#' Light background tints for conditional cell fills and callout surfaces
#'
#' These are FILLS sat behind dark body text, not data-series colors — use
#' CEDAR_PALETTE / CEDAR_SEMANTIC_COLORS for lines, bars, and slices.
#'
#' Each value mirrors an `--alert-*-bg` token in www/cedar-custom.css, so a
#' red/amber/green table cell and a `.alert-box--*` callout are the same color.
#' They replace the stock Bootstrap `#f8d7da / #fff3cd / #d4edda` ramp, which
#' was cold and sat outside the Cedar palette. All keep body text (#232826)
#' above 11:1.
CEDAR_SURFACE_TINTS <- c(
  critical      = "#F2E3DE",   # --alert-critical-bg
  warning       = "#F4E9D2",   # --alert-warning-bg
  warning_light = "#FAF3E4",   # lighter gold, for narrow-band "near zero" cells
  success       = "#E4EEE7",   # --alert-success-bg
  info          = "#E6EDF6"    # --alert-info-bg
)


#' Canonical label orders for small, fixed-vocabulary categorical dimensions
#'
#' `cedar_plotly_palette()`'s default behavior colors by first-appearance
#' order in whatever data frame a given chart happens to receive. For an
#' open-ended dimension (major code, department, course) that is fine and
#' often desirable (see build_color_map()'s "sort by frequency" pattern), but
#' for a small fixed vocabulary that recurs across many unrelated charts and
#' tabs — course level, program type, faculty job category — first-appearance
#' order silently varies with how each chart's data pipeline happened to sort
#' or group rows, so "grad" (or "Majors", or "Lecturer") ends up a different
#' color in every chart. Passing one of these as `label_order` pins each
#' known value to a fixed CEDAR_PALETTE slot everywhere it is used.
CEDAR_LEVEL_ORDER <- c("lower", "upper", "grad")
CEDAR_MAJOR_MINOR_ORDER <- c("Majors", "Minors")
CEDAR_PROGRAM_TYPE_ORDER <- c("Major", "Second Major", "First Minor", "Second Minor",
                              "First Concentration", "Second Concentration", "Third Concentration")
CEDAR_JOB_CATEGORY_ORDER <- c("Professor", "Associate Professor", "Assistant Professor",
                              "Lecturer", "Term Teacher", "TPT", "Professor Emeritus")


#' Build a named color map for consistent cross-chart coloring
#'
#' Maps each unique label to a hex color from `palette` in the order given,
#' cycling if there are more labels than palette entries. "Other" (if present)
#' is always assigned the shared neutral gray for collapsed remainder slices.
#'
#' Pre-sort `labels` by importance or frequency before calling — the most
#' visually distinct colors go to the first entries.
#'
#' @param labels Character vector of labels (duplicates silently removed).
#' @param palette Optional character vector of hex colors.
#'   Defaults to CEDAR_PALETTE.
#' @return Named character vector: label → hex color.
#' @examples
#' # Sort by frequency first so most common category gets most distinct color:
#' build_color_map(names(sort(table(df$major), decreasing = TRUE)))
#'
#' # Consistent colors across two charts with overlapping labels:
#' map <- build_color_map(union(labels_a, labels_b))
#' plotly::plot_ly(marker = list(colors = unname(map[labels_a])))
build_color_map <- function(labels, palette = NULL) {
  labels  <- unique(labels)
  palette <- palette %||% CEDAR_PALETTE
  colors  <- rep_len(palette, length(labels))
  map     <- setNames(colors, labels)
  map["Other"] <- unname(CEDAR_SEMANTIC_COLORS["other"])
  map
}


#' Get ColorBrewer colors without minimum-palette warnings
#'
#' RColorBrewer palettes such as Set2 require at least three requested colors.
#' Plotly often requests the exact number of observed groups, so one- and
#' two-group charts can otherwise flood logs with harmless warnings. This helper
#' asks Brewer for a valid base palette and then returns exactly `n` colors.
#'
#' @param n Number of colors needed.
#' @param palette Brewer palette name or an explicit character vector of colors.
#' @param fallback Character vector used if Brewer is unavailable or unknown.
#' @return Character vector of `n` colors.
cedar_brewer_palette <- function(n, palette = CEDAR_PALETTE, fallback = CEDAR_PALETTE) {
  n <- suppressWarnings(as.integer(n %||% 0L))
  if (length(n) == 0 || is.na(n) || n <= 0L) return(character(0))

  if (length(palette) > 1L) {
    return(rep_len(as.character(palette), n))
  }

  palette <- as.character(palette %||% "")
  if (requireNamespace("RColorBrewer", quietly = TRUE) &&
      palette %in% rownames(RColorBrewer::brewer.pal.info)) {
    max_colors <- RColorBrewer::brewer.pal.info[palette, "maxcolors"]
    base_n <- min(max(n, 3L), max_colors)
    base_colors <- RColorBrewer::brewer.pal(base_n, palette)
    if (n <= length(base_colors)) {
      return(base_colors[seq_len(n)])
    }
    return(grDevices::colorRampPalette(base_colors)(n))
  }

  rep_len(fallback, n)
}


#' Build a Plotly-ready categorical color map
#'
#' @param labels Category labels to color.
#' @param palette Brewer palette name or explicit colors.
#' @param label_order Optional canonical order (e.g. CEDAR_LEVEL_ORDER) for a
#'   small fixed-vocabulary dimension. When supplied, known values are pinned
#'   to that order (so the same value always gets the same palette color
#'   across every chart) and any value not in `label_order` is appended after,
#'   in first-appearance order, so nothing is silently dropped.
#' @return Named character vector suitable for Plotly's `colors` argument.
cedar_plotly_palette <- function(labels, palette = CEDAR_PALETTE, label_order = NULL) {
  labels <- unique(as.character(stats::na.omit(labels)))
  if (!is.null(label_order)) {
    labels <- c(intersect(label_order, labels), setdiff(labels, label_order))
  }
  stats::setNames(cedar_brewer_palette(length(labels), palette), labels)
}
