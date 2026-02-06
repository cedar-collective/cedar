# =============================================================================
# CREDIT HOURS ANALYSIS FUNCTIONS
# =============================================================================
#
# This file contains functions for analyzing student credit hours (SCH).
#
# TERMINOLOGY GUIDE:
# -----------------
# The CEDAR data model uses specific terms that can be confusing. Here's a guide:
#
# In cedar_students (class enrollment data):
#   - department: The COURSE's home department code (e.g., "HIST" for History courses)
#   - major: The STUDENT's major program CODE (e.g., "HIST", "ANTH", "NOND")
#   - student_college: The student's college (e.g., "AS" for Arts & Sciences)
#   - level: Course level - "lower", "upper", or "grad"
#
# In d_params (department report parameters):
#   - dept_code: Department code for the report (e.g., "HIST")
#   - prog_codes: Program codes associated with the department (e.g., c("HIST"))
#                 These match values in cedar_students$major
#   - prog_names: Full program names (e.g., "History") - used for display
#
# COMMON MAPPINGS (defined in R/lists/mappings.R):
#   - program_code_to_name: Maps major codes to human-readable names
#                           e.g., "HIST" -> "History", "NOND" -> "Non-Degree"
#   - dept_code_to_name: Maps department codes to full names
#   - hr_org_desc_to_dept_map: Maps HR organization names to dept codes
#
# KEY DISTINCTION:
#   - A student taking HIST 101 has department="HIST" (the course's dept)
#   - That same student might have major="PSYC" (they're a Psychology major)
#   - The pie charts show what majors are TAKING courses in a department
#
# =============================================================================

#' Get Enrolled Credit Hours
#'
#' Analyzes credit hour enrollments for students.
#' Returns summary statistics on student enrollment credits.
#'
#' @param filtered_students Data frame of student enrollments (CEDAR format)
#'   Must contain columns: student_id, term, total_credits, term_type
#' @param courses List of course codes to filter (optional)
#' @param opt Options list (optional)
#'
#' @return Wide-format data frame with enrollment counts by term and credit load
#'
#' @details
#' CEDAR-only function - requires CEDAR column names:
#' - student_id (not `Student ID`)
#' - term (not `Academic Period Code`)
#' - total_credits (not `Total Credits`)
#' - term_type (must be present)
#'
#' @examples
#' \dontrun{
#' enrollment_stats <- get_enrolled_cr(students, courses, opt)
#' }
get_enrolled_cr <- function(filtered_students, courses, opt) {
  message("welcome to get_enrolled_cr!")

  # Validate CEDAR data structure
  required_cols <- c("student_id", "term", "total_credits", "term_type")
  missing_cols <- setdiff(required_cols, colnames(filtered_students))

  if (length(missing_cols) > 0) {
    stop("[credit-hours.R] Missing required CEDAR columns in filtered_students data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(filtered_students), collapse = ", "))
  }

  # uncomment for testing
  # filtered_students <- load_students()
  # courses <- list('HIST 491',"HIST 492")
  #opt[["course"]] <- cl_crits

  #opt <- list()
  #myopt <- opt

  # filter students by courses (all terms) and group
  message("computing summary stats...")
  filtered_students <- filtered_students %>%
    distinct(student_id, .keep_all=TRUE) %>%
    group_by(term, total_credits, term_type)

  summary <- filtered_students %>% summarize(count = n())

  summary_wide <- summary %>% pivot_wider(names_from = term, values_from = count)

  message("get_enrolled_cr now returning regstats...")
  return(summary_wide)
}



#' Get Credit Hours Summary
#'
#' Creates a summary of earned credit hours from class lists (CEDAR format).
#' Filters for passing grades and summarizes by term, campus, college, department, level, and subject.
#'
#' @param students Data frame of student enrollments (CEDAR class_lists format)
#'   Must contain columns: final_grade, term, campus, college, department, level, subject_code, credits
#'
#' @return Data frame with credit hours summarized by term, campus, college, department, subject, and level
#'   Includes a "total" level that aggregates across all course levels
#'
#' @details
#' CEDAR-only function - requires CEDAR column names:
#' - final_grade (not `Final Grade`)
#' - term (not `Academic Period Code`)
#' - campus (not `Course Campus Code`)
#' - college (not `Course College Code`)
#' - department (not DEPT)
#' - subject_code (not `Subject Code`)
#' - credits (not `Course Credits`)
#'
#' Only counts credit hours for passing grades (defined in passing_grades global).
#'
#' @examples
#' \dontrun{
#' credit_hours <- get_credit_hours(class_lists)
#' }
get_credit_hours <- function (students) {
  message("[credit-hours.R] Welcome to get_credit_hours!")

  # Validate CEDAR data structure - NO FALLBACKS
  required_cols <- c("final_grade", "term", "campus", "college", "department", "level", "subject_code", "credits")
  missing_cols <- setdiff(required_cols, colnames(students))

  if (length(missing_cols) > 0) {
    stop("[credit-hours.R] Missing required CEDAR columns in students data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(students), collapse = ", "),
         "\n  Run data transformation scripts to create CEDAR-formatted data.")
  }

  message("[credit-hours.R] filtering students by passing_grades...")
  filtered_students <- students %>% filter(final_grade %in% passing_grades)
  message("[credit-hours.R] Completed filtering, got ", nrow(filtered_students), " rows")

  message("[credit-hours.R] summarizing...")
  filtered_students_summary <- filtered_students %>%
    group_by(term, campus, college, department, level, subject_code) %>%
    summarize(total_hours = sum(credits), .groups="keep")
  message("[credit-hours.R] Completed summarizing, got ", nrow(filtered_students_summary), " rows")

  message("[credit-hours.R] creating totals across levels...")
  credit_hours_totals <- filtered_students %>%
    group_by(term, campus, college, department, subject_code) %>%
    summarize(level="total", total_hours = sum(credits), .groups="keep")
  message("[credit-hours.R] Completed creating totals, got ", nrow(credit_hours_totals), " rows")

  message("[credit-hours.R] adding totals to level data...")
  credit_hours_data <- rbind(filtered_students_summary, credit_hours_totals) %>%
    arrange(term, campus, college, department, subject_code, factor(level, levels=c("lower","upper","grad","total")))
  message("[credit-hours.R] Completed rbind and arrange, got ", nrow(credit_hours_data), " rows")

  message("[credit-hours.R] About to return credit_hours_data...")
  return(credit_hours_data)
}


#' Credit Hours By Major
#'
#' Analyzes earned credit hours broken down by student major.
#' Creates pie charts showing:
#' 1. What outside majors are taking courses in this department (top 9)
#' 2. Internal vs external majors split
#'
#' Creates separate plots for lower and upper division courses.
#'
#' @param students Data frame of student enrollments (CEDAR class_lists format)
#'   Must contain columns: department, term, final_grade, credits, major, student_college, level
#' @param d_params Department parameters list containing:
#'   - dept_code: Department code to filter
#'   - term_start: Starting term (inclusive)
#'   - term_end: Ending term (inclusive)
#'   - prog_codes: Vector of program codes for major comparison (home dept majors)
#'     These must match the values in cedar_students$major (e.g., "HIST", "POLS")
#'
#' @return d_params list with added elements:
#'   - tables$credit_hours_data_w: Wide-format credit hours by major and term
#'   - plots$sch_outside_pct_lower_plot: Pie chart of outside majors (lower division)
#'   - plots$sch_outside_pct_upper_plot: Pie chart of outside majors (upper division)
#'   - plots$sch_dept_pct_lower_plot: Internal vs external majors (lower division)
#'   - plots$sch_dept_pct_upper_plot: Internal vs external majors (upper division)
#'
#' @details
#' CEDAR-only function - requires CEDAR column names:
#' - department (not DEPT)
#' - term (not `Academic Period Code`)
#' - final_grade (not `Final Grade`)
#' - credits (not `Course Credits`)
#' - major (should be in CEDAR format)
#' - student_college (not `Student College`)
#' - level (lower, upper, grad)
#'
#' The plots show averages across all terms in the specified range.
#'
#' @examples
#' \dontrun{
#' d_params <- credit_hours_by_major(class_lists, d_params)
#' }
credit_hours_by_major <- function (students, d_params) {

  # Validate CEDAR data structure - NO FALLBACKS
  required_cols <- c("department", "term", "final_grade", "credits", "major", "student_college", "level")
  missing_cols <- setdiff(required_cols, colnames(students))

  if (length(missing_cols) > 0) {
    stop("[credit-hours.R] Missing required CEDAR columns in students data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(students), collapse = ", "),
         "\n  Run data transformation scripts to create CEDAR-formatted data.")
  }

  message("[credit-hours.R] Starting credit_hours_by_major for dept: ", d_params$dept_code)

  # Filter by department and term range
  filtered_students <- students %>%
    filter(department == d_params$dept_code) %>%
    filter(as.integer(term) >= d_params$term_start & as.integer(term) <= d_params$term_end)
  message("[credit-hours.R] After filtering by dept and term range, got ", nrow(filtered_students), " rows")

  # Filter for passing grades only
  filtered_students <- filtered_students %>% filter(final_grade %in% passing_grades)
  message("[credit-hours.R] After filtering by passing grades, got ", nrow(filtered_students), " rows")

  # Clean up major names - remove Pre prefix
  filtered_students <- filtered_students %>%
    mutate(
      pre = grepl("Pre", major),
      major = str_remove(major, "Pre "),
      major = str_remove(major, "Pre-"),
      student_college = str_replace(student_college, "College of Educ & Human Sci", "College of Education")
    )

  # Create summary table (all levels combined) for export
  message("[credit-hours.R] Creating summary table...")
  credit_hours_data <- filtered_students %>%
    group_by(term, student_college, major) %>%
    summarize(total_hours = sum(credits), .groups = "drop") %>%
    arrange(term, desc(total_hours))

  # Create wide view with periods as columns
  credit_hours_data_w <- credit_hours_data %>%
    pivot_wider(names_from = term, values_from = total_hours)

  # Get numeric column names (exclude first two character columns)
  if (ncol(credit_hours_data_w) > 2) {
    numeric_cols <- names(credit_hours_data_w)[3:ncol(credit_hours_data_w)]

    # Create totals row
    totals_row <- credit_hours_data_w %>%
      ungroup() %>%
      summarise(
        student_college = "Total",
        major = "Total",
        across(all_of(numeric_cols), ~ sum(.x, na.rm = TRUE))
      )

    credit_hours_data_w <- credit_hours_data_w %>%
      ungroup() %>%
      bind_rows(totals_row) %>%
      mutate(across(all_of(numeric_cols), ~ replace_na(as.numeric(.x), 0)))

    # Sort by most recent period
    last_period_col <- names(credit_hours_data_w)[ncol(credit_hours_data_w)]
    credit_hours_data_w <- credit_hours_data_w %>% arrange(desc(.data[[last_period_col]]))
  }

  d_params$tables[["credit_hours_data_w"]] <- credit_hours_data_w
  message("[credit-hours.R] Created credit_hours_data_w table with ", nrow(credit_hours_data_w), " rows")

  # Helper function to create pie charts for a specific course level
  # prog_codes: vector of program codes that belong to this department (e.g., c("HIST"))
  create_major_pie_charts <- function(data, level_filter, level_label, prog_codes) {

    # Filter by course level (level_filter can be a single value or vector)
    level_data <- data %>% filter(level %in% level_filter)

    if (nrow(level_data) == 0) {
      message("[credit-hours.R] No data for ", level_label, " courses")
      return(list(outside_plot = NULL, dept_plot = NULL))
    }

    # Summarize by major code (total across all terms in range)
    major_summary <- level_data %>%
      group_by(major) %>%
      summarize(total_hours = sum(credits, na.rm = TRUE), .groups = "drop") %>%
      arrange(desc(total_hours))

    # Convert major codes to human-readable names using program_code_to_name lookup
    # Falls back to the code if no name found
    major_summary <- major_summary %>%
      mutate(major_name = ifelse(
        !is.na(program_code_to_name[major]),
        program_code_to_name[major],
        major  # Keep code if no name mapping exists
      ))

    # Calculate totals
    total_all_hours <- sum(major_summary$total_hours, na.rm = TRUE)

    # Separate home majors from outside majors (using codes for matching)
    home_majors <- major_summary %>% filter(major %in% prog_codes)
    outside_majors <- major_summary %>% filter(!(major %in% prog_codes))

    home_hours <- sum(home_majors$total_hours, na.rm = TRUE)
    outside_hours <- sum(outside_majors$total_hours, na.rm = TRUE)

    message("[credit-hours.R] ", level_label, ": Home majors = ", home_hours,
            " hrs, Outside majors = ", outside_hours, " hrs")

    # Plot 1: Outside majors breakdown (top 9) - using human-readable names
    outside_plot <- NULL
    if (nrow(outside_majors) > 0) {
      top_outside <- outside_majors %>% slice_head(n = 9)

      # If there are more than 9, add "Other" category
      if (nrow(outside_majors) > 9) {
        other_hours <- sum(outside_majors$total_hours[10:nrow(outside_majors)], na.rm = TRUE)
        top_outside <- bind_rows(top_outside, tibble(major = "Other", major_name = "Other", total_hours = other_hours))
      }

      # Use major_name for display, ordered by total_hours
      top_outside <- top_outside %>% mutate(major_name = fct_reorder(major_name, total_hours))

      outside_plot <- plot_ly(top_outside, labels = ~major_name, values = ~total_hours,
                              marker = list(colorscale = 'Viridis')) %>%
        add_pie(hole = 0.6) %>%
        layout(title = paste0('Outside Majors (', level_label, ')'),
               legend = list(x = 1.05, y = 0.5),
               xaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE),
               yaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE))
    }

    # Plot 2: Internal vs External majors
    dept_plot <- NULL
    if (total_all_hours > 0) {
      dept_pct_data <- tibble(
        category = c("Department Majors", "Outside Majors"),
        hours = c(home_hours, outside_hours),
        pct = round(c(home_hours, outside_hours) / total_all_hours * 100, 1)
      )

      dept_plot <- plot_ly(dept_pct_data, labels = ~paste0(category, " (", pct, "%)"),
                           values = ~hours, type = 'pie',
                           marker = list(colors = c('#2E8B57', '#FF6B35'))) %>%
        layout(title = paste0('Majors vs Non-Majors (', level_label, ')'),
               legend = list(x = 1.05, y = 0.5),
               xaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE),
               yaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE))
    }

    return(list(outside_plot = outside_plot, dept_plot = dept_plot))
  }

  # Create plots for lower division courses
  message("[credit-hours.R] Creating lower division plots...")
  lower_plots <- create_major_pie_charts(filtered_students, "lower", "Lower Division", d_params$prog_codes)
  d_params$plots[["sch_outside_pct_lower_plot"]] <- lower_plots$outside_plot
  d_params$plots[["sch_dept_pct_lower_plot"]] <- lower_plots$dept_plot

  # Create plots for upper division courses
  message("[credit-hours.R] Creating upper division plots...")
  upper_plots <- create_major_pie_charts(filtered_students, "upper", "Upper Division", d_params$prog_codes)
  d_params$plots[["sch_outside_pct_upper_plot"]] <- upper_plots$outside_plot
  d_params$plots[["sch_dept_pct_upper_plot"]] <- upper_plots$dept_plot

  # Keep backward compatibility: create combined plots (all levels except grad)
  message("[credit-hours.R] Creating combined plots (all undergraduate levels)...")
  all_plots <- create_major_pie_charts(filtered_students, c("lower", "upper"), "All Undergrad", d_params$prog_codes)

  # For backward compatibility, also create the original plot names
  # But now the data is aggregated correctly across all terms
  d_params$plots[["sch_outside_pct_plot"]] <- all_plots$outside_plot
  d_params$plots[["sch_dept_pct_plot"]] <- all_plots$dept_plot

  message("[credit-hours.R] Returning d_params with new plot(s) and table(s)...")
  return(d_params)
}


#' Credit Hours By Faculty
#'
#' Analyzes credit hours taught by different faculty job categories.
#' Shows credit hour production broken down by faculty type (tenure track, lecturer, etc.).
#'
#' @param data_objects List containing:
#'   - class_lists: CEDAR student enrollments
#'   - cedar_faculty: CEDAR faculty data with job_category
#' @param d_params Department parameters list containing:
#'   - dept_code: Department code to filter
#'   - term_start: Starting term (inclusive)
#'   - term_end: Ending term (inclusive)
#'   - subj_codes: Subject codes for plot titles
#'   - palette: Color palette for plots
#'
#' @return d_params list with added plots:
#'   - chd_by_fac_facet_plot: Bar chart faceted by course level
#'   - chd_by_fac_plot: Stacked bar chart of total credit hours
#'
#' @details
#' CEDAR-only function - requires CEDAR column names:
#' - In class_lists: final_grade, term, department, campus, college, level, credits, instructor_id
#' - In cedar_faculty: term, instructor_id, department, job_category
#'
#' @examples
#' \dontrun{
#' d_params <- credit_hours_by_fac(data_objects, d_params)
#' }
credit_hours_by_fac <- function (data_objects, d_params) {
  message("[credit-hours.R] Welcome to credit_hours_by_fac!")

  students <- data_objects[["cedar_students"]]

  # load faculty data for associating title with person in course listings
  fac_by_term <- data_objects[["cedar_faculty"]]

  # Debug: Check what's in data_objects
  message("DEBUG: data_objects keys: ", paste(names(data_objects), collapse=", "))
  message("DEBUG: cedar_faculty class: ", class(fac_by_term))
  message("DEBUG: cedar_faculty is null: ", is.null(fac_by_term))


  if (is.null(fac_by_term)) {
    stop("[credit-hours.R] cedar_faculty is NULL in data_objects\n",
         "  Expected CEDAR format with cedar_faculty key.\n",
         "  Run transform-hr-to-cedar.R to create cedar_faculty from hr_data.\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  if (nrow(fac_by_term) == 0) {
    message("ERROR: cedar_faculty is empty")
    d_params$plots[["chd_by_fac_facet_plot"]] <- "No faculty data available"
    d_params$plots[["chd_by_fac_plot"]] <- "No faculty data available"
    return(d_params)
  }

  # Validate CEDAR data structure for students
  required_student_cols <- c("final_grade", "term", "department", "credits", "campus", "college", "level", "instructor_id")
  missing_student_cols <- setdiff(required_student_cols, colnames(students))

  if (length(missing_student_cols) > 0) {
    stop("[credit-hours.R] Missing required CEDAR columns in students data: ",
         paste(missing_student_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(students), collapse = ", "))
  }

  # Validate CEDAR data structure for faculty
  required_faculty_cols <- c("term", "instructor_id", "department", "job_category")
  missing_faculty_cols <- setdiff(required_faculty_cols, colnames(fac_by_term))

  if (length(missing_faculty_cols) > 0) {
    stop("[credit-hours.R] Missing required CEDAR columns in cedar_faculty data: ",
         paste(missing_faculty_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(fac_by_term), collapse = ", "))
  }

  message("DEBUG: Using faculty data from data_objects with ", nrow(fac_by_term), " rows")


  # for studio testing
  # d_params <- list(dept_code="CJ",subj_codes=c("CJ","COMM"),palette="Spectral")

  # filter out non credit earning students; passing_grades defined in includes/map_to_subj_code.R
  message("DEBUG: Filtering students by passing grades and dept...")
  filtered_students <- students %>% filter(final_grade %in% passing_grades & department == d_params$dept_code)
  message("DEBUG: After filtering by passing grades and dept, got ", nrow(filtered_students), " rows")

  # filter for term params
  filtered_students <- filtered_students %>%
    filter(term >= d_params$term_start & term <= d_params$term_end)
  message("DEBUG: After filtering by term range, got ", nrow(filtered_students), " rows")

  message("DEBUG: About to merge faculty data with student data...")
  # Remove as_of_date if it exists
  if ("as_of_date" %in% colnames(fac_by_term)) {
    fac_by_term <- fac_by_term %>% select(-c("as_of_date"))
  }
  merged <- merge(filtered_students, fac_by_term,
                  by.x = c("term", "instructor_id", "department"),
                  by.y = c("term", "instructor_id", "department"),
                  x.all = TRUE)
  message("DEBUG: After merge, got ", nrow(merged), " rows")

  # summarize total hours earned by job_category (in faculty data)
  message("DEBUG: Summarizing by job category...")
  credit_hours_data <- merged %>%
    group_by(term, campus, college, department, level, job_category) %>%
    summarize(total_hours = sum(credits), .groups="keep")
  message("DEBUG: After summarizing by job_category, got ", nrow(credit_hours_data), " rows")



  credit_hours_data_main <- credit_hours_data %>% filter(campus %in% c("ABQ","EA"))

  credit_hours_data_main <- credit_hours_data_main %>%
    group_by(term, college, department, level, job_category) %>%
    summarize(total_hours = sum(total_hours), .groups="keep")


  # create BAR PLOT (colored by job_category), and FACETED by course level
  if (nrow(credit_hours_data) > 0) {
  chd_by_fac_facet_plot <- credit_hours_data_main %>%
    mutate(term = as.factor(term)) %>%
    ggplot(aes(x=term, y=total_hours)) +
    ggtitle(paste0("using SUBJ codes: ",paste(d_params$subj_codes, collapse=", "))) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=job_category),stat="identity", position="dodge") +
    facet_wrap(~level) +
    theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1)) +
    scale_fill_brewer(palette=d_params$palette) +
    xlab("Academic Period") + ylab("Credit Hours")
  }
  else {
    chd_by_fac_facet_plot <- "insufficient data."
  }

  chd_by_fac_facet_plot

  d_params$plots[["chd_by_fac_facet_plot"]] <- chd_by_fac_facet_plot



  # remove level from summaries
  credit_hours_data_main <- credit_hours_data_main %>%
    group_by(term, college, department, job_category) %>%
    summarize(total_hours = sum(total_hours))

  # create BAR PLOT of CH TOTALS colored by job_category
  chd_by_fac_plot <-  credit_hours_data_main %>%
    mutate(term = as.factor(term)) %>%
    ggplot(aes(x=term, y=total_hours)) +
    ggtitle(paste0("using SUBJ codes: ",paste(d_params$subj_codes, collapse=", "))) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=job_category),stat="identity", position="stack") +
    scale_fill_brewer(palette=d_params$palette) +
    #scale_fill_discrete(limits=c("lower","upper","grad")) +
    xlab("Academic Period") + ylab("Credit Hours")

  chd_by_fac_plot
  d_params$plots[["chd_by_fac_plot"]] <- chd_by_fac_plot
  
  message("DEBUG: Successfully completed credit_hours_by_fac")
  message("returning d_params with new plot(s) and table(s)...")
  return(d_params)
  
} # end credit_hours_by_fac


###########################
#' Get Credit Hours for Department Report
#'
#' Main function for credit hours analysis in department reports.
#' Creates multiple plots and tables analyzing credit hour production.
#'
#' @param class_lists Data frame of student enrollments (CEDAR format)
#'   Must contain columns: final_grade, term, campus, college, department, level, subject_code, credits
#' @param d_params Department parameters list containing:
#'   - term_start: Starting term (inclusive)
#'   - term_end: Ending term (inclusive)
#'   - dept_code: Department code to filter
#'   - subj_codes: Subject codes for filtering
#'   - palette: Color palette for plots
#'
#' @return d_params list with added elements:
#'   - plots$college_credit_hours_plot: Bar chart of college credit hours
#'   - plots$college_credit_hours_comp_plot: Department vs college comparison
#'   - plots$college_dept_dual_plot: Dual y-axis comparison plot
#'   - plots$chd_by_year_facet_subj_plot: Credit hours faceted by subject
#'   - plots$chd_by_year_subj_plot: Credit hours stacked by subject
#'   - plots$chd_by_period_plot: Credit hours by course level
#'   - tables$chd_by_period_table: Credit hours table by period
#'
#' @details
#' CEDAR-only function - requires CEDAR column names:
#' - term (not `Academic Period Code`)
#' - campus (not `Course Campus Code`)
#' - college (not `Course College Code`)
#' - department (not DEPT)
#' - subject_code (not `Subject Code`)
#' - All lowercase with underscores
#'
#' @examples
#' \dontrun{
#' d_params <- get_credit_hours_for_dept_report(class_lists, d_params)
#' }
get_credit_hours_for_dept_report <- function (class_lists, d_params) {
  message("[credit-hours.R] Welcome to get_credit_hours_for_dept_report!")

  # TODO: basic filtering from d_params

  # get basic credit hours data
  message("[credit-hours.R] Getting credit hours data...")
  credit_hours_data <- get_credit_hours(class_lists)

  # TODO: add SUBJ to data?

  # filter for term params
  message("filtering for d_params terms...")
  credit_hours_data <- credit_hours_data %>%
    filter(term >= d_params$term_start & term <= d_params$term_end)



  # group by academic year and dept to create summary of college hours
  # FILTER FOR AS, ABQ (ABQ and EA have the same totals)
  # group only by period code and dept, so all campuses  (ABE and EA) and subject codes are included
  college_credit_hours <- credit_hours_data %>% filter(college == "AS") %>%
    filter(campus %in% c("ABQ","EA")) %>%
    group_by(term, department) %>%
    filter(level == "total") %>%
    summarize(total_hours = sum(total_hours))


  college_credit_hours_plot <- college_credit_hours %>%
    mutate(term = as.factor(term)) %>%
    ggplot(aes(x=term, y=total_hours)) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=department),stat="identity",position="stack") +
    scale_color_brewer(palette="Spectral") +
    theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1)) +
    xlab("Academic Period") + ylab("Credit Hours")

  college_credit_hours_plot <- ggplotly(college_credit_hours_plot)
  college_credit_hours_plot
  d_params$plots[["college_credit_hours_plot"]] <- college_credit_hours_plot

  # add term type col
  college_credit_hours <- add_term_type_col(college_credit_hours, "term") %>% distinct()

  # create totals for college, grouped by academic year
  college_credit_hours <- college_credit_hours %>% group_by(term) %>% mutate(college_total = sum(total_hours))

  # filter by dept code
  dept_credit_hours <- college_credit_hours %>% filter(department == d_params$dept_code)


  # compute per-year % change in dept compared to that of college
  diff_fr_college_hours <- dept_credit_hours %>%
    group_by(term_type, term, department) %>%
    arrange(department, term_type, term)

  # add percent diff from prev term_type
  diff_fr_college_hours <- diff_fr_college_hours %>%
    group_by(term_type) %>%
    mutate(diff_d = total_hours / lag(total_hours,n=1) * 100)





  # add percent diff from prev year
  diff_fr_college_hours <- diff_fr_college_hours %>%
    group_by(term_type) %>%
    mutate(diff_c = college_total / lag(college_total,n=1) * 100)

  # calc diff between college and department deltas
  diff_fr_college_hours <- diff_fr_college_hours %>%
    group_by(term_type) %>%
    mutate(diff_heavy = diff_d - diff_c)



  label <- paste0("period change for ",d_params$dept_code,": ")

  college_credit_hours_comp_plot <- diff_fr_college_hours %>%
    mutate(term = as.factor(term)) %>%
    ggplot(aes(x=term, y=diff_heavy)) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(),stat="identity",position="stack") +
    scale_color_brewer(palette=d_params$palette) +
    theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1)) +
    xlab("Academic Year") + ylab("% diff from College")

  college_credit_hours_comp_plot
  d_params$plots[["college_credit_hours_comp_plot"]] <- college_credit_hours_comp_plot



  # Create indexed growth comparison plot

  # Shows dept vs college growth relative to a baseline (first term = 100)
  # This answers: "Is this dept growing faster or slower than the college?"
  # - If dept line is ABOVE college line → dept is outpacing the college
  # - If dept line is BELOW college line → dept is falling behind

  # Get department totals by academic period (filter by level="total" to avoid double counting)
  dept_totals <- credit_hours_data %>%
    filter(department == d_params$dept_code) %>%
    filter(campus %in% c("ABQ", "EA")) %>%
    filter(level == "total") %>%
    group_by(term) %>%
    summarise(dept_total = sum(total_hours), .groups = 'drop') %>%
    arrange(term)

  # Get college totals by academic period (all departments in AS college)
  college_totals <- credit_hours_data %>%
    filter(college == "AS") %>%
    filter(campus %in% c("ABQ", "EA")) %>%
    filter(level == "total") %>%
    group_by(term) %>%
    summarise(college_total = sum(total_hours), .groups = 'drop') %>%
    arrange(term)

  # Combine the data
  indexed_data <- merge(dept_totals, college_totals, by = "term", all = TRUE)
  indexed_data <- indexed_data %>% arrange(term)
  indexed_data[is.na(indexed_data)] <- 0

  # Index both to first term = 100
  first_dept <- indexed_data$dept_total[1]
  first_college <- indexed_data$college_total[1]

  # Guard against division by zero
  if (is.na(first_dept) || first_dept == 0) first_dept <- 1
  if (is.na(first_college) || first_college == 0) first_college <- 1

  indexed_data <- indexed_data %>%
    mutate(
      dept_indexed = (dept_total / first_dept) * 100,
      college_indexed = (college_total / first_college) * 100,
      term = as.factor(term)
    )

  # Reshape for ggplot (long format)
  plot_data <- indexed_data %>%
    tidyr::pivot_longer(
      cols = c(dept_indexed, college_indexed),
      names_to = "series",
      values_to = "indexed_value"
    ) %>%
    mutate(series = ifelse(series == "dept_indexed",
                           paste0(d_params$dept_code, " Department"),
                           "AS College"))

  # Create the indexed comparison plot
  college_dept_dual_plot <- ggplot(plot_data, aes(x = term, y = indexed_value,
                                                   color = series, group = series)) +
    # Reference line at 100 (starting point)
    geom_hline(yintercept = 100, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    # Lines
    geom_line(linewidth = 1.5) +
    # Points
    geom_point(size = 3) +
    scale_color_manual(
      values = c("AS College" = "#2E8B57",
                 setNames("#FF6B35", paste0(d_params$dept_code, " Department")))
    ) +
    scale_y_continuous(
      name = "Indexed Credit Hours (First Term = 100)",
      labels = function(x) paste0(x)
    ) +
    labs(
      title = paste0("Credit Hour Growth: ", d_params$dept_code, " vs AS College"),
      subtitle = "Both indexed to 100 at first term. Above = growing faster, Below = falling behind.",
      x = "Academic Period",
      color = ""
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.title = element_text(face = "bold"),
      panel.grid.minor = element_blank()
    )

  d_params$plots[["college_dept_dual_plot"]] <- college_dept_dual_plot



  # since this is a unit report, filter by param$dept_code
  # TODO: enable filter by subj code or program code

  credit_hours_data_main <- credit_hours_data %>%
    filter(department == d_params$dept_code) %>%
    filter(campus %in% c("ABQ","EA")) %>%
    arrange(term, college, department, subject_code, level)

  # create period_hours column - removing acad_year aggregation
  # credit_hours_data_main <- credit_hours_data_main %>%
  #   group_by(term, college, department, subject_code, level) %>%
  #   mutate (period_hours = sum(total_hours))

  # remove level totals so we can facet by level
  chm_by_subj_level <- credit_hours_data_main %>%
    filter(level != "total") %>%
    mutate(term = as.factor(term))

  # create plot line plot of CREDIT HOURS FACETED BY SUBJECT
  chd_by_year_facet_subj_plot <- ggplot(chm_by_subj_level, aes(x=term, y=total_hours)) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=level),stat="identity",position="stack") +
    # geom_line(aes(group=level)) +
    # geom_point(aes(group=level)) +
    scale_color_brewer(palette=d_params$palette) +
    facet_wrap(~subject_code, ncol = 3) +
    theme(axis.text.x=element_text(angle = 75, hjust = 1)) +
    xlab("Academic Period Code") + ylab("Credit Hours")

  #chd_by_year_facet_subj_plot
  d_params$plots[["chd_by_year_facet_subj_plot"]] <- chd_by_year_facet_subj_plot



  # filter only totals to show TOTAL HOURS WITHOUT LEVELS
  chm_by_subj <- credit_hours_data_main %>%
    filter(level == "total") %>%
    mutate(term = as.factor(term))

  # create line plot of TOTAL CREDIT HOURS BY SUBJECT (no faceting)
  chd_by_year_subj_plot <- ggplot(chm_by_subj, aes(x=term, y=total_hours)) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=subject_code),stat="identity",position="stack") +
    theme(axis.text.x=element_text(angle = 75, hjust = 1)) +

    # geom_point(aes(group=subject_code)) +
    # geom_line(aes(group=subject_code)) +
    xlab("Academic Period Code") + ylab("Credit Hours")

  d_params$plots[["chd_by_year_subj_plot"]] <- chd_by_year_subj_plot

  # create tables for display
  chd_by_period_table <- chm_by_subj %>% mutate(level = factor(level, levels = unique(level))) %>% spread(key=level, value=total_hours)
  chd_by_period_table <- chd_by_period_table %>% ungroup() %>%
    select(term, department, 4:ncol(chd_by_period_table))
  d_params$tables[["chd_by_period_table"]] <- chd_by_period_table
  




  # create totals by academic period WITHOUT subject
  chd_by_period <- credit_hours_data_main %>%
    group_by(term, campus, college, department, level) %>%
    filter(level != "total") %>%
    mutate(period_hours = sum(total_hours),
           term = as.factor(term)) %>%
    arrange(term, college, department, level)


  # create plot of STACKED BAR showing credit hours colored by CREDIT HOURS BY COURSE LEVEL
  chd_by_period_plot <- ggplot(chd_by_period, aes(x=term, y=total_hours)) +
    ggtitle(paste0("using SUBJ codes: ",paste(d_params$subj_codes, collapse=", "))) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=level),stat="identity", position="stack") +
    theme(axis.text.x=element_text(angle = 75, hjust = 1)) +
    scale_fill_brewer(palette=d_params$palette) +
    xlab("Academic Period Code") + ylab("Credit Hours")

  chd_by_period_plot
  d_params$plots[["chd_by_period_plot"]] <- chd_by_period_plot


  message("returning d_params with new plot(s) and table(s)...")
  return(d_params)

}




