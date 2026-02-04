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


# determine term type from term code
get_term_type <- function (term_code) {
  term_type <- case_when(
    substring(term_code,5,6) == 80 ~ "fall",
    substring(term_code,5,6) == 10 ~ "spring",
    substring(term_code,5,6) == 60 ~ "summer"
  )
  return (term_type)
}


# useful for creating linear models over time
add_term_bins <- function(df,term_col_name) {
  
  # remove summer from termcode list
  #bins <- num.labs[!grepl('60', num.labs)]
  
  bins <- num.labs
  
  # add basic time series for term codes
  df <- df %>% mutate (term_bin = match(get({{term_col_name}}),bins))
  min_bin <- min(df$term_bin)
  
  df <- df %>% mutate (term_bin = term_bin - min_bin + 1)
  
  return(df)
}


# covert term codes to term strings (see mappings.R)
term_code_to_str <- function (term_code) {
  term_str <- term_text[which(num.labs == term_code)]
  ifelse (length(term_str) == 0,term_code,term_str)
}


# see lists.R for num.labs (term codes, like 202410) and term_text (Spring 2024) definitions
# this can be used by merging this DF with any MyReports DF with only names instead of codes
# example: merged <- (merge(term_code_lookup, table_w_term_text, by = 'term_code'))
term_code_lookup <- data.frame(term_code=num.labs,Semester=term_text)


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
