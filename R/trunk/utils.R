# this file provides miscellaneous functions used across CEDAR

# controller function for emulating CLI functionality from within RStudio
# all code and env variables should have been loaded by .Rprofile
cedar <- function(func="guide",...) {
  message("[utils.R] Welcome to cedar.R!")
  message("[utils.R] Working dir: ", getwd())
  
  opt <- list(...)
  opt$func <- func
  
  if (is.null(opt$guide)) {
    opt$guide <- FALSE
  }
  
  # display supplied option params
  print(opt)  
  
  message("[utils.R] reloading config.R...")
  source("config/config.R")
  
  message("[utils.R] reloading functions...")
  source("R/branches/load-funcs.R")
  load_funcs("./")
  
  resolve_conflicts() # defined in utils

  message("[utils.R] processing function: ", opt$func, "...")
  msg <- command_handler(opt)
  if (is.character(msg)) { 
    message(msg)
  }

  message("[utils.R] cedar controller done!")
}



resolve_conflicts <- function() {
  conflicted::conflicts_prefer(dplyr::filter())
  conflicted::conflicts_prefer(dplyr::lag())
  conflicted::conflicts_prefer(plotly::layout)
}


# TODO: way too hacky. 
update_codes <- function(df,col) {
  df[col][df[col] == "CCS"] <- "CCST"
  df[col][df[col] == "PSY"] <- "PSYC"
  df[col][df[col] == "SOC"] <- "SOCI"
  return(df)
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
  season <- dplyr::case_when(
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



# output_data is going to be a df/tibble or list
process_output <- function(output_data,filename,opt) {
  message("\nWelcome to process_output!")
  
  output_list <- list()
  
  if (is_tibble(output_data)) {
    message("incoming output_data is tibble.")
    output_list[[filename]] <- output_data
  } 
  else if (is.list(output_data )) {
    message("incoming output_data is list.")
    output_list <- output_data
  }
  
  # process each element of list
  for (i in seq_along(output_list)) {
    cur_name <- names(output_list)[i]
    message("current output list name: ", cur_name)
    
    cur_item <- as_tibble(output_list[[i]])
    
    # if arrange param set, use it
    if (!is.null(opt[["arrange"]])) {
      arrange_col <- opt[["arrange"]]
      cur_item <- cur_item %>%  arrange(get({{arrange_col}}) )
    }
    
    # if output csv flag set, print 5 rows as sample and save file 
    if (!is.null(opt[["output"]]) && opt[["output"]] == "csv") {
      
      message("output for ",cur_name,":")
      cur_item %>% tibble::as_tibble() %>% print(n = 5, width=Inf)
      
      filename <- paste0(cedar_output_dir,"csv/",cur_name,".csv")  
      message("saving CSV file with name: ", filename, "...")
      write.csv(cur_item, file = filename)
      message("file saved.")
    }
    else { # if not saving CSV, print all rows to terminal
      cur_item %>% tibble::as_tibble() %>% print(n = nrow(cur_item), width=Inf)  
    }
  }
  message("all done in process_output!\n")
}


# ---------------------------------------------------------------------------
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
#'             Correct unit for gradebook analytics ("what grade did the
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


# ---------------------------------------------------------------------------
# Categorical color mapping
# ---------------------------------------------------------------------------

#' CEDAR standard categorical color palette
#'
#' 15-color Matplotlib/D3 categorical palette. Used as the default for all
#' build_color_map() calls throughout CEDAR so all categorical charts share
#' a consistent visual language regardless of which module renders them.
#' Defined once here so it is never duplicated in individual files.
CEDAR_PALETTE <- c(
  "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
  "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
  "#aec7e8", "#ffbb78", "#98df8a", "#ff9896", "#c5b0d5"
)


#' Build a named color map for consistent cross-chart coloring
#'
#' Maps each unique label to a hex color from `palette` in the order given,
#' cycling if there are more labels than palette entries. "Other" (if present)
#' is always assigned "#cccccc" (neutral gray for collapsed remainder slices).
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
  map["Other"] <- "#cccccc"
  map
}
