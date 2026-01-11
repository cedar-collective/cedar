# this function inspects and parses a param to a vector (not list as it did originally)
# named vectors/lists should returned with their value
# commma separated strings should be converted to a list
# char vectors should be returned as is

# TODO: fix list vs vector throughout code
# TODO: handle a list/vector of named lists/vectors

convert_param_to_list <- function(param) {
  #message("\nWelcome to convert_param_to_list!")
  #print(str(param))
  
  # check if list type already; if so, return it
  if (is.list(param)) {
    #message("param is already list. returning it...")
    param_to_list <- param
    return(param_to_list)
  }
  #check for comma in param
  else if (length(param) == 1 && grepl(",", param)) {
    message("comma string detected...")
    param <- str_replace(param, ", ", ",")
    param <- strsplit(param, ",")[[1]]
    message("converting to list and returning...")
    param_to_list <- as.list(param)
    return(param_to_list)
  }
  # check if param is a named object (probably defined in includes/lists.R) 
  # TODO: need to be explicit about where to look; this sometimes finds an R-level entity
  else if (length(param) == 1 && exists(get("param"))) { 
    message("param already defined: ", get("param"))
    message(str(get(param)))
    if (param == "as" || param =="CJ") { # hack for now
     return (as.list(param))
    } 
    else return(get(param))
  }
  else if (is.character(param)) {
    #message("param is character. returning as list...")
    param_to_list <- as.list(param)
    return(param_to_list)
  }
  # quit if unsure what to do to prevent weird errors down the line
  else {
    stop(paste0("covert_param_to_list not sure what to do with supplied param: ", str(param)))
  }
}




#' Filter a data frame by a column and value(s)
#'
#' This function filters a data frame by a specified column and value(s). The column name is provided as a string,
#' and the value can be a vector, list, or comma-separated string. The function uses \code{convert_param_to_list}
#' to standardize the value input and then filters the data frame to rows where the column matches any of the values.
#'
#' @param data A data frame to filter.
#' @param col A string specifying the column name to filter by.
#' @param val The value(s) to filter for. Can be a vector, list, or comma-separated string.
#'
#' @return A filtered data frame containing only rows where \code{col} matches \code{val}.
#' @examples
#' filter_by_col(df, "Course Campus Code", "ABQ")
#' filter_by_col(df, "Course College Code", c("A", "B"))
#' filter_by_col(df, "SUBJ_CRSE", "MATH 1430,ENGL 1110")

filter_by_col <- function(data, col, val) {
  message("[filter.R] Filtering by ",col, "=", val)

  param_to_list <- convert_param_to_list(val)
  
  # use get instead of {{ }} because col is passed in as a string, rather than a variable
  data <- data %>% filter (get(col) %in% param_to_list)
    
  return(data)
}


#' Filter a Data Frame by Term(s)
#'
#' Filters rows in a data frame to include only those matching the specified term or terms in a given column.
#'
#' @param df A data frame to filter.
#' @param term A single term value or a vector of term values to filter by (e.g., "202510" or c("202510", "202520")).
#' @param term_col The name of the column in `df` containing term values. Default is "TERM".
#'
#' @return A filtered data frame containing only rows where `term_col` matches one of the values in `term`.
#'
#' @examples
#' # Filter for a single term:
#' filter_by_term(df, "202510")
#' # Filter for multiple terms:
#' filter_by_term(df, c("202510", "202520"))
#' # Specify a custom term column:
#' filter_by_term(df, "202510", term_col = "Academic Period Code")
filter_by_term <- function(data, term, term_col_name) {
  message("[filter.R] Welcome to filter_by_term!")
  
  # if term is not a list, convert to string
  if (!is.list(term)) {
    term <- as.character(term)
  }
  
  if (length(term) > 0 || !is.null(term)) {     
    # check for single string and dash to indicate range
    if (length(term) == 1 && grepl("-",term)) {
      message("[filter.R] Parsing term code range...")
      terms <- unlist(str_split(term,"-"))
      message("[filter.R] terms: ",terms)

      # for terms like 202280-
      if (terms[2] == "") {
        term_str <- paste0("`",term_col_name,"` >= ",terms[1])
      }
      else {
        term_str <- paste0(term_col_name," >= ",terms[1], " & ", term_col_name , " <= ",terms[2])
      }
      
      message("term_str: ",term_str)
      
      data <- data %>% filter (!!rlang::parse_expr(term_str))
    } # end if not list        
    else if (length(term) == 1 && term == "fall") {
      data <- data %>% filter (substring(get({{term_col_name}}),5,6) == 80)
    } 
    else if (length(term) == 1 && term == "spring") {
      data <- data %>% filter (substring(get({{term_col_name}}),5,6) == 10)
    }
    else if (length(term) == 1 && term == "summer") {
      data <- data %>% filter (substring(get({{term_col_name}}),5,6) == 60)
    }
    else {  # convert param to list and filter
      term_list <- convert_param_to_list(term)
      message("[filter.R] About to filter ", term_col_name, " by ", term_list)
      data <- data %>% filter (get(term_col_name) %in% term_list)
    }
  } # end if term is not null

  message("[filter.R] Term filtering done! Returning ",nrow(data)," rows.")
  return (data)
}



# this function filters a simple subject_course list according to opt params
# select_courses should be a 1xn tibble or list
filter_course_list <- function(all_courses,select_courses,opt) {
  message("welcome to filter_course list!")

  # for studio testing...
  #all_courses <- load_courses()
  #select_courses <- as_tibble(next_courses$subject_course)

  # filter all courses to just supplied selected
  courses <- all_courses %>% filter (subject_course %in% unlist(select_courses))

  # get all enrollment data for course to
  enrls <- get_enrl(courses,opt)

  # grab just course list
  course_list <- unique(enrls$subject_course)

  message("all done in filter_course_list.")
  return(course_list)
}


# filter out summer from DF
filter_out_summer <- function (data,term_col_name) {
  data <- data %>% filter (substring(get({{term_col_name}}),5,6) != 60)
  return(data)
}


#' Generic filter for a MyReports data frame.
#'
#' @param df The data frame to filter (DESRs or class list).
#' @param opt The options list.
#' @param opt_col_map Named list mapping opt param names to column names in df.
#' @param special_filters (Optional) Named list of functions for special-case filtering.
#' @return Filtered data frame.
filter_data <- function(df, opt, opt_col_map, special_filters = list()) {
  for (opt_name in names(opt_col_map)) {
    #message("[filter.R] Checking filter option: ", opt_name)
    col_name <- opt_col_map[[opt_name]]
    #message("[filter.R] Column name: ", col_name)
    if (!is.null(opt[[opt_name]])) {
      message("[filter.R] Filtering by ", opt_name, " with value: ", opt[[opt_name]])
      # Use special filter if defined, otherwise default to filter_by_col
      if (opt_name %in% names(special_filters)) {
        message("Using special filter for ", opt_name)
        # Check if the special filter is a function
        if (!is.function(special_filters[[opt_name]])) {
          stop(paste0("[filter.R] ERROR: Special filter for ", opt_name, " is not a function."))
        }
        # Call the special filter function with df and the option value
        # Check if the special filter function takes two arguments    
        if (length(formals(special_filters[[opt_name]])) == 2) {
          df <- special_filters[[opt_name]](df, opt[[opt_name]])
        } else {
          stop(paste0("[filter.R] ERROR: Special filter for ", opt_name, " has an unexpected number of arguments."))
        }
        # Run the special filter function
        df <- special_filters[[opt_name]](df, opt[[opt_name]])
      } else {
        # Default to filter_by_col
        df <- filter_by_col(df, col_name, opt[[opt_name]])
      }
    }
  }
  # Display the number of rows after filtering
  message("[filter.R] Returning filtered data with ", nrow(df), " rows.")

  return(df)
}

# CEDAR sections filter options map
# Maps user-facing filter option names to cedar_sections column names
opt_col_map_desr <- list(
  dept          = "department",
  subj          = "subject",
  crn           = "crn",
  course        = "subject_course",
  term          = "term",
  term_type     = "term_type",
  course_campus = "campus",
  course_college = "college",
  status         = "status",
  pt            = "pt",
  inst          = "instructor_name",
  gen_ed        = "gen_ed_area",
  level         = "level",
  im            = "delivery_method",
  job_cat       = "job_cat",
  enrl_min      = "enrolled",
  enrl_max      = "enrolled",
  uel           = "",
  crosslist     = ""
)

# CEDAR students filter options map
# Maps user-facing filter option names to cedar_students column names
opt_col_map_classlist <- list(
  crn               = "crn",
  course            = "subject_course",
  subj              = "subject",
  dept              = "department",
  term              = "term",
  inst              = "instructor_name",
  course_campus      = "campus",
  course_college     = "college",
  student_campus     = "student_campus",
  student_college    = "student_college",
  classification    = "student_classification",
  level             = "level",
  pt                = "pt",
  major             = "primary_major",
  gen_ed            = "gen_ed_area",
  reg_status_code   = "registration_status_code",
  im                = "delivery_method",
  uel               = ""
)


special_filters_desr <- list(
  term = function(df, value) filter_by_term(df, value, "term"),
  crosslist = function(df, value) .xlist_filter(df, value),
  enrl_min = function(df, value) df %>% filter(enrolled >= as.integer(value)),
  enrl_max = function(df, value) df %>% filter(enrolled <= as.integer(value)),
  uel = function(df, value) df %>% subset(!(subject_course %in% excluded_courses))
)

special_filters_classlist <- list(
  term = function(df, value) filter_by_term(df, value, "term"),
  uel = function(df, value) df %>% subset(!(subject_course %in% excluded_courses))
)

# Filter DESRs based on provided options
filter_DESRs <- function(courses, opt) {
  message("[filter.R] Filtering DESRs with supplied options...")
  message("[filter.R] Starting with ", nrow(courses), " rows.")

  # Check for at least one filter option
  if (!length(opt)){
    print_help(opt_parser)
    stop("[filter.R] ERROR in filter_DESRs: Please supply at least one filter parameter", call.=FALSE)
  }
  
  # Use the generic filter_data function with the DESR mapping and special filters
  courses <- filter_data(courses, opt, opt_col_map_desr, special_filters_desr)
  
  # display available columns
  message("[filter.R] Available columns: ", paste(colnames(courses), collapse = ", "))

  # Set default groupings for output
  groups <- c("term", "subject_course", "course_title", "pt", "delivery_method", "level", "instructor_name")
  message("[filter.R] Setting default groupings for output: ", paste(groups, collapse = ", "))
  courses <- courses %>% group_by(across(all_of(groups))) %>% arrange(term, subject_course)
  
  # many courses are listed multiple times because of crosslisting info;
  # there is a row for each XLed section.
  # could reduce rows here to keep just unique courses, 
  # but generic filtering should preserve xl info for xl filtering
  message("[filter.R] Done filtering DESRs! Returning ", nrow(courses), " rows...")
  return(courses)
}



# Filter class lists based on provided options 
filter_class_list <- function(students, opt) {
  message("[filter.R] Filtering class lists with supplied options...")
  message("[filter.R] Starting with ", nrow(students), " rows.")

  # Check for at least one filter option
  if (!length(opt)){
    print_help(opt_parser)
    stop("[filter.R] Error in filter_class_list: Please supply at least one filter parameter", call.=FALSE)
  }
  
  # Use the generic filter_data function with the DESR mapping and special filters
  students <- filter_data(students, opt, opt_col_map_classlist, special_filters_classlist)

  message("[filter.R] Done filtering class lists! Returning ", nrow(students), " students...")

  return(students)
}
  

# CROSSLIST FILTER
.xlist_filter <- function(df,action) {
  message("[filter.R] Welcome to xlist_filter.R!")

  # Studio testing
  #df <- courses
  #action <- "home"

  # home will filter out all xled rows of a course except the one that matches dept filtering
  # enrolled will be section enrollment; crosslist data in CEDAR model TBD
  if (action == "home") {
    message("[filter.R] Filtering cross-listed courses to keep only home dept entries...")

    # Check if we have crosslist fields from CEDAR model
    if ("crosslist_group" %in% colnames(df)) {
      # CEDAR model approach: filter by crosslist_primary flag
      non_xl <- df %>% filter(is.na(crosslist_group))
      xl_primary <- df %>% filter(!is.na(crosslist_group) & crosslist_primary == TRUE)

      df <- bind_rows(non_xl, xl_primary)
    } else {
      # Legacy fallback (if crosslist fields not in CEDAR model yet)
      message("[filter.R] WARNING: crosslist fields not found in data model, skipping crosslist filter")
    }

    message("[filter.R] Filtered to ", nrow(df), " courses (home dept entries only)")
    return(df)
  }


  # EXCLUDE ignores all crosslisted courses
  else if (action == "exclude") {
    message("[filter.R] Excluding cross-listed courses...")

    if ("crosslist_group" %in% colnames(df)) {
      df <- df %>% filter(is.na(crosslist_group))
    } else {
      message("[filter.R] WARNING: crosslist fields not found in data model, skipping crosslist filter")
    }
    return(df)
  }

  # Error out to make sure this gets noticed.
  else {
    stop("[filter.R] ERROR: unknown crosslist filter setting (action=", action, ")!")
  }
}
