# Major Change Detection and Analysis Functions
# Tracks student major changes across terms, analyzes pathways, and measures credits at transition

#' Detect major changes for each student across their academic timeline
#'
#' @param df Data frame (academic_studies) with student program data
#' @param major_col Character string, column name for primary major (default "Major")
#' @param id_col Character string, column name for student ID (default "ID")
#' @param term_col Character string, column name for term code (default "term_code")
#' @param credits_col Character string, column name for credits attempted (default "Credits Attempted")
#' @return Data frame with one row per major change event
#' 
#' @examples
#' changes <- detect_major_changes(academic_studies)
#' changes_filtered <- detect_major_changes(academic_studies, opt = list(college = "Arts and Sciences"))
detect_major_changes <- function(df, 
                                  major_col = "Major",
                                  id_col = "ID", 
                                  term_col = "term_code",
                                  credits_col = "Credits Attempted",
                                  opt = NULL) {
  
  message("[majors.R] Welcome to detect_major_changes!")
  message("[majors.R] Analyzing major changes across ", length(unique(df[[id_col]])), " students")
  
  # Apply filters if opt is provided
  if (!is.null(opt)) {
    if (!is.null(opt$campus) && length(opt$campus) > 0) {
      message("[majors.R] Filtering by campus: ", paste(opt$campus, collapse = ", "))
      df <- df %>% filter(`Student Campus` %in% opt$campus)
    }
    
    if (!is.null(opt$college) && length(opt$college) > 0) {
      message("[majors.R] Filtering by college: ", paste(opt$college, collapse = ", "))
      df <- df %>% filter(`Translated College` %in% opt$college)
    }
    
    if (!is.null(opt$dept) && length(opt$dept) > 0) {
      message("[majors.R] Filtering by department: ", paste(opt$dept, collapse = ", "))
      df <- df %>% filter(Department %in% opt$dept)
    }
  }
  
  # Normalize and prepare data
  df_clean <- df %>%
    select(
      student_id = all_of(id_col),
      term = all_of(term_col),
      major = all_of(major_col),
      credits_attempted = all_of(credits_col),
      college = `Actual College`,
      translated_college = `Translated College`,
      campus = `Student Campus`,
      department = Department,
      student_level = `Student Level`,
      degree = Degree
    ) %>%
    filter(!is.na(major) & major != "" & major != "Undeclared") %>%
    arrange(student_id, term)
  
  message("[majors.R] Cleaned data: ", nrow(df_clean), " student-term records")
  
  # Detect changes by comparing each term to previous term
  df_changes <- df_clean %>%
    group_by(student_id) %>%
    arrange(term) %>%
    mutate(
      prev_major = lag(major),
      prev_term = lag(term),
      major_changed = !is.na(prev_major) & major != prev_major
    ) %>%
    ungroup()
  
  # Extract only the change events
  changes_only <- df_changes %>%
    filter(major_changed) %>%
    select(
      student_id,
      change_term = term,
      prev_term,
      from_major = prev_major,
      to_major = major,
      credits_at_change = credits_attempted,
      college,
      translated_college,
      campus,
      department,
      student_level,
      degree
    ) %>%
    arrange(student_id, change_term)
  
  message("[majors.R] Detected ", nrow(changes_only), " major change events")
  message("[majors.R] Affecting ", length(unique(changes_only$student_id)), " unique students")
  
  return(changes_only)
}


#' Calculate average credits before entering each major (for first-time major changers)
#'
#' @param changes_df Data frame from detect_major_changes()
#' @param min_n Minimum number of observations to report (default 5)
#' @return Data frame summarizing avg credits by destination major
avg_credits_before_major <- function(changes_df, min_n = 5) {
  
  message("[majors.R] Calculating average credits before entering each major...")
  
  result <- changes_df %>%
    group_by(to_major) %>%
    summarize(
      avg_credits = mean(credits_at_change, na.rm = TRUE),
      median_credits = median(credits_at_change, na.rm = TRUE),
      min_credits = min(credits_at_change, na.rm = TRUE),
      max_credits = max(credits_at_change, na.rm = TRUE),
      n_changes = n(),
      n_students = n_distinct(student_id)
    ) %>%
    filter(n_changes >= min_n) %>%
    arrange(desc(avg_credits))
  
  message("[majors.R] Found ", nrow(result), " majors with at least ", min_n, " incoming changes")
  
  return(result)
}


#' Identify most common majors students move OUT OF
#'
#' @param changes_df Data frame from detect_major_changes()
#' @param min_n Minimum number of observations to report (default 5)
#' @return Data frame of source majors ranked by frequency
majors_moved_out_of <- function(changes_df, min_n = 5) {
  
  message("[majors.R] Identifying majors students move out of...")
  
  result <- changes_df %>%
    count(from_major, name = "n_exits", sort = TRUE) %>%
    filter(n_exits >= min_n)
  
  message("[majors.R] Found ", nrow(result), " majors with at least ", min_n, " exits")
  
  return(result)
}


#' Identify most common major change pathways (A → B)
#'
#' @param changes_df Data frame from detect_major_changes()
#' @param min_n Minimum number of observations to report (default 3)
#' @return Data frame of pathways ranked by frequency
major_change_pathways <- function(changes_df, min_n = 3) {
  
  message("[majors.R] Identifying common major change pathways...")
  
  result <- changes_df %>%
    count(from_major, to_major, name = "n_changes", sort = TRUE) %>%
    filter(n_changes >= min_n)
  
  message("[majors.R] Found ", nrow(result), " pathways with at least ", min_n, " occurrences")
  
  return(result)
}


#' Analyze major change pathways by college
#'
#' @param changes_df Data frame from detect_major_changes()
#' @param min_n Minimum number of observations to report (default 3)
#' @param use_translated Logical, use Translated College vs Actual College (default TRUE)
#' @return Data frame of pathways by college
pathways_by_college <- function(changes_df, min_n = 3, use_translated = TRUE) {
  
  college_col <- if (use_translated) "translated_college" else "college"
  message("[majors.R] Analyzing pathways by ", college_col, "...")
  
  result <- changes_df %>%
    group_by(across(all_of(college_col)), from_major, to_major) %>%
    summarize(
      n_changes = n(),
      n_students = n_distinct(student_id),
      avg_credits = mean(credits_at_change, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(n_changes >= min_n) %>%
    arrange(across(all_of(college_col)), desc(n_changes))
  
  message("[majors.R] Found ", nrow(result), " college-specific pathways")
  
  return(result)
}


#' Calculate time to first major change (in terms)
#'
#' @param df Data frame (academic_studies)
#' @param id_col Character string, column name for student ID (default "ID")
#' @param term_col Character string, column name for term code (default "term_code")
#' @param major_col Character string, column name for major (default "Major")
#' @return Data frame with student_id, first_term, first_change_term, terms_until_change
time_to_first_change <- function(df, 
                                  id_col = "ID",
                                  term_col = "term_code",
                                  major_col = "Major") {
  
  message("[majors.R] Calculating time to first major change...")
  
  # Detect all changes
  changes <- detect_major_changes(df, major_col = major_col, id_col = id_col, term_col = term_col)
  
  # Get first change per student
  first_changes <- changes %>%
    group_by(student_id) %>%
    summarize(
      first_change_term = min(change_term),
      from_major = first(from_major),
      to_major = first(to_major),
      .groups = "drop"
    )
  
  # Get each student's first term
  first_terms <- df %>%
    select(student_id = all_of(id_col), term = all_of(term_col)) %>%
    group_by(student_id) %>%
    summarize(first_term = min(term), .groups = "drop")
  
  # Join and calculate difference
  result <- first_changes %>%
    left_join(first_terms, by = "student_id") %>%
    mutate(
      terms_until_change = as.numeric(first_change_term) - as.numeric(first_term)
    ) %>%
    select(student_id, first_term, first_change_term, terms_until_change, from_major, to_major) %>%
    arrange(terms_until_change)
  
  message("[majors.R] Found ", nrow(result), " students who changed majors")
  message("[majors.R] Average terms until first change: ", 
          round(mean(result$terms_until_change, na.rm = TRUE), 1))
  
  return(result)
}


#' Identify students who changed major vs. those who didn't (cohort tagging)
#'
#' @param df Data frame (academic_studies)
#' @param id_col Character string, column name for student ID (default "ID")
#' @param term_col Character string, column name for term code (default "term_code")
#' @param major_col Character string, column name for major (default "Major")
#' @return Data frame with student_id, changed_major (boolean), n_changes, majors_held (comma-separated)
tag_major_changers <- function(df,
                                id_col = "ID",
                                term_col = "term_code", 
                                major_col = "Major") {
  
  message("[majors.R] Tagging students by major change behavior...")
  
  # Get unique majors per student across all terms
  student_majors <- df %>%
    select(student_id = all_of(id_col), major = all_of(major_col)) %>%
    filter(!is.na(major) & major != "" & major != "Undeclared") %>%
    distinct() %>%
    group_by(student_id) %>%
    summarize(
      n_majors_held = n_distinct(major),
      majors_held = paste(unique(major), collapse = " → "),
      .groups = "drop"
    )
  
  # Detect changes
  changes <- detect_major_changes(df, major_col = major_col, id_col = id_col, term_col = term_col)
  
  # Count changes per student
  change_counts <- changes %>%
    group_by(student_id) %>%
    summarize(n_changes = n(), .groups = "drop")
  
  # Combine
  result <- student_majors %>%
    left_join(change_counts, by = "student_id") %>%
    mutate(
      n_changes = replace_na(n_changes, 0),
      changed_major = n_changes > 0
    ) %>%
    select(student_id, changed_major, n_changes, n_majors_held, majors_held)
  
  n_changers <- sum(result$changed_major)
  n_total <- nrow(result)
  pct_changers <- round(100 * n_changers / n_total, 1)
  
  message("[majors.R] ", n_changers, " of ", n_total, " students (", pct_changers, "%) changed majors")
  
  return(result)
}


#' Generate comprehensive major change report
#'
#' @param df Data frame (academic_studies)
#' @param opt Optional list of filter parameters (campus, college, dept)
#' @param min_n Minimum observations for summaries (default 5)
#' @return Named list of analysis results
major_change_report <- function(df, opt = NULL, min_n = 5) {
  
  message("[majors.R] ======================================")
  message("[majors.R] Generating comprehensive major change report")
  message("[majors.R] ======================================")
  
  # Detect all changes
  changes <- detect_major_changes(df, opt = opt)
  
  # Run all analyses
  report <- list(
    changes = changes,
    avg_credits_by_major = avg_credits_before_major(changes, min_n = min_n),
    majors_exited = majors_moved_out_of(changes, min_n = min_n),
    pathways = major_change_pathways(changes, min_n = min_n),
    pathways_by_college = pathways_by_college(changes, min_n = min_n),
    time_to_change = time_to_first_change(df),
    student_tags = tag_major_changers(df)
  )
  
  message("[majors.R] Report complete!")
  message("[majors.R] - ", nrow(report$changes), " change events")
  message("[majors.R] - ", nrow(report$pathways), " unique pathways")
  message("[majors.R] - ", sum(report$student_tags$changed_major), " students changed majors")
  
  return(report)
}
