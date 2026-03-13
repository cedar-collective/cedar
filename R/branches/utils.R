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

# get a course list based on opt params
# increasingly useful as more funcs become vectorized and can accept course list as input
get_course_list <- function(courses,opt) {
  
  # for testing
  # opt <- list()
  # opt$group_by <- "course"
  # opt$term <- "202160"
  # opt$level <- "lower"
  # opt$uel <- TRUE

  # TODO: set standard opts if null
  # TODO: extend to grab a CSV file (created by CEDAR or externally)
  
  enrls <- get_enrl(courses,opt)
  course_list <- unique(enrls$SUBJ_CRSE)
  
  return(course_list)
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
  term_col <- rlang::ensym(term_col_name)
  term_str <- as.character(df[[as.character(term_col)]])
  term_part <- substr(term_str, 5, 6)
  term_int <- as.integer(term_str)
  
  if (summer) {
    df$next_term <- ifelse(
      term_part == "80", term_int + 30,
      ifelse(term_part == "10", term_int + 50,
      ifelse(term_part == "60", term_int + 20, NA_integer_))
    )
  } else {
    df$next_term <- ifelse(
      term_part == "80", term_int + 30,
      ifelse(term_part == "10", term_int + 70,
      ifelse(term_part == "60", term_int + 20, NA_integer_))
    )
  }
  df$next_term <- as.character(df$next_term)
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
  dept <- subj_to_dept_map[[substring(course, 1, gregexpr(pattern = " ",course)[[1]] -1 ) ]]
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
  for (i in 1: length(output_list)) {
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
