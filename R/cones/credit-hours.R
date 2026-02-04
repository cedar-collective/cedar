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
#' Shows which majors are earning credit hours in department courses.
#'
#' @param students Data frame of student enrollments (CEDAR class_lists format)
#'   Must contain columns: department, term, final_grade, credits, major, student_college
#' @param d_params Department parameters list containing:
#'   - dept_code: Department code to filter
#'   - term_start: Starting term (inclusive)
#'   - term_end: Ending term (inclusive)
#'   - prog_names: Vector of program names for major comparison
#'
#' @return d_params list with added elements:
#'   - tables$credit_hours_data_w: Wide-format credit hours by major and term
#'   - plots$sch_outside_pct_plot: Pie chart of non-major credit hour distribution
#'   - plots$sch_dept_pct_plot: Pie chart comparing major vs non-major credit hours
#'
#' @details
#' CEDAR-only function - requires CEDAR column names:
#' - department (not DEPT)
#' - term (not `Academic Period Code`)
#' - final_grade (not `Final Grade`)
#' - credits (not `Course Credits`)
#' - major (should be in CEDAR format)
#' - student_college (not `Student College`)
#'
#' @examples
#' \dontrun{
#' d_params <- credit_hours_by_major(class_lists, d_params)
#' }
credit_hours_by_major <- function (students, d_params) {

  # Validate CEDAR data structure - NO FALLBACKS
  required_cols <- c("department", "term", "final_grade", "credits", "major", "student_college")
  missing_cols <- setdiff(required_cols, colnames(students))

  if (length(missing_cols) > 0) {
    stop("[credit-hours.R] Missing required CEDAR columns in students data: ",
         paste(missing_cols, collapse = ", "),
         "\n  Expected CEDAR format with lowercase column names.",
         "\n  Found columns: ", paste(colnames(students), collapse = ", "),
         "\n  Run data transformation scripts to create CEDAR-formatted data.")
  }

  message("DEBUG: Starting credit_hours_by_major for dept: ", d_params$dept_code)
  message("filtering students by d_params...")
  filtered_students <- students %>% filter(department == d_params$dept_code)
  message("DEBUG: After filtering by dept, got ", nrow(filtered_students), " rows")

  filtered_students <- filtered_students %>%
    filter(as.integer(term) >= d_params$term_start & as.integer(term) <= d_params$term_end)
  message("DEBUG: After filtering by term range (", d_params$term_start, "-", d_params$term_end, "), got ", nrow(filtered_students), " rows")

  # filter out non credit earning students; passing_grades defined in includes/map_to_subj_code.R
  message("filtering students by passing grades...")
  filtered_students <- filtered_students %>% filter(final_grade %in% passing_grades)
  message("DEBUG: After filtering by passing grades, got ", nrow(filtered_students), " rows")

  # remove Pre from major and add boolean flag in separate column
  message("integrating pre-majors...")
  filtered_students$pre <- ifelse(grepl("Pre", filtered_students$major), TRUE, FALSE)
  filtered_students$major <- str_remove(filtered_students$major, "Pre ")
  filtered_students$major <- str_remove(filtered_students$major, "Pre-")

  message("standardizing data ...")
  filtered_students$student_college <- str_replace(filtered_students$student_college, "College of Educ & Human Sci", "College of Education")
  

  # find students in SUBJ courses who are NOT majoring (first) in any programs of that dept
  #prgm_to_dept_map[[major_to_program_map[["East Asian Studies"]]]]
  #message("finding non-majors ...")

  # create col to indicate "home" program of student based on major col
  #filtered_students$student_major_dept <-  prgm_to_dept_map[major_to_program_map[filtered_students$major]]
  #non_majors <- filtered_students %>% filter (is.na(student_major_dept) | student_major_dept != opt$dept)
  #non_majors <- filtered_students %>% filter (prgm_to_dept_map[major_to_program_map[major]] != opt$dept)

  # summarize by academic period code, student's home college, and major
  message("summarizing credit hours by student college and major...")
  credit_hours_data <- filtered_students %>%
    group_by(term, student_college, major) %>%
    summarize(total_hours = sum(credits)) %>%
    arrange(term, desc(total_hours))
  message("DEBUG: After summarizing, got ", nrow(credit_hours_data), " rows")

  # create wide view with periods as columns
  message("DEBUG: About to pivot wider...")
  credit_hours_data_w <- credit_hours_data %>% pivot_wider(names_from = term, values_from = total_hours)
  message("DEBUG: After pivot_wider, got ", nrow(credit_hours_data_w), " rows and ", ncol(credit_hours_data_w), " columns")
  message("DEBUG: Column names after pivot: ", paste(names(credit_hours_data_w), collapse=", "))

  # create totals line
  message("DEBUG: Creating totals row...")
  # Get numeric column names (exclude the first two character columns)
  numeric_cols <- names(credit_hours_data_w)[3:ncol(credit_hours_data_w)]
  message("DEBUG: Numeric columns for totals: ", paste(numeric_cols, collapse=", "))

  # Create totals row by summing numeric columns
  totals_row <- credit_hours_data_w %>%
    ungroup() %>%
    summarise(
      student_college = "Total",
      major = "Total",
      across(all_of(numeric_cols), ~ sum(.x, na.rm = TRUE))
    )
  message("DEBUG: Successfully created totals row")

  credit_hours_data_w <- credit_hours_data_w %>% ungroup() %>%
    bind_rows(totals_row)
  message("DEBUG: After adding totals row, got ", nrow(credit_hours_data_w), " rows")
  
  message("DEBUG: About to convert columns to numeric...")
  credit_hours_data_w <- credit_hours_data_w %>% mutate_at(c(3:ncol(credit_hours_data_w)), as.numeric)
  credit_hours_data_w[is.na(credit_hours_data_w)] <- 0
  message("DEBUG: Completed numeric conversion and NA replacement")
  
  # Sort by the most recent academic period (last column)
  if (ncol(credit_hours_data_w) > 2) {
    last_period_col <- names(credit_hours_data_w)[ncol(credit_hours_data_w)]
    message("DEBUG: Sorting by last period column: ", last_period_col)
    credit_hours_data_w <- credit_hours_data_w %>% arrange(desc(.data[[last_period_col]]))
  } 
  
  # save data for report
  message("DEBUG: Saving credit_hours_data_w table to d_params")
  d_params$tables[["credit_hours_data_w"]] <- credit_hours_data_w 
  
  
  # prep data for pie chart for NON-MAJORS
  message("finding non-majors' share of total credit hours ...")
  message("DEBUG: Available columns in credit_hours_data_w: ", paste(names(credit_hours_data_w), collapse=", "))

  sch_outside_pct <- credit_hours_data_w %>% filter(!(major %in% d_params$prog_names))
  sch_outside_pct <- sch_outside_pct %>% filter(major != "Total") %>% slice_head(n=9)
  message("DEBUG: sch_outside_pct has ", nrow(sch_outside_pct), " rows")

  # Check if we have data and get the most recent period column
  if (nrow(sch_outside_pct) > 0 && ncol(credit_hours_data_w) > 2) {
    recent_period_col <- names(credit_hours_data_w)[ncol(credit_hours_data_w)]
    message("DEBUG: Using period column: ", recent_period_col)

    # reorder majors in order of credit hours using the most recent period
    sch_outside_pct <- sch_outside_pct %>% mutate(major = fct_reorder(major, .data[[recent_period_col]]))

    message("creating plot...")
    sch_outside_pct_plot <- plot_ly(sch_outside_pct, labels = ~major, values = as.formula(paste0("~`", recent_period_col, "`")), marker = list(colorscale = 'Viridis'))
    sch_outside_pct_plot <- sch_outside_pct_plot %>%
      add_pie(hole = 0.6) %>%
      layout(title = '',
             legend = list(x = 100, y = 0.5),
             xaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE),
             yaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE))

    message("DEBUG: Successfully created sch_outside_pct_plot")
  } else {
    message("DEBUG: Insufficient data for sch_outside_pct plot")
    sch_outside_pct_plot <- NULL
  }

  message("saving plot in d_params...")
  d_params$plots[["sch_outside_pct_plot"]] <- sch_outside_pct_plot


  # prep data for pie chart of DEPT HOURS COMPARED AS PART OF TOTAL
  # this is way faster than making the filter an OR test
  message("finding majors' share of total credit hours ...")
  message("DEBUG: About to create department percentage chart...")

  sch_dept_pct_total <- credit_hours_data_w %>% filter(major == "Total") %>% mutate(major = "Non-majors")
  sch_dept_pct_program <- credit_hours_data_w %>% filter(major %in% d_params$prog_names)
  sch_dept_pct <- rbind(sch_dept_pct_total, sch_dept_pct_program)
  message("DEBUG: sch_dept_pct has ", nrow(sch_dept_pct), " rows")

  # Check if we have data and create plot using dynamic period column
  if (nrow(sch_dept_pct) > 0 && ncol(credit_hours_data_w) > 2) {
    recent_period_col <- names(credit_hours_data_w)[ncol(credit_hours_data_w)]
    message("DEBUG: Creating dept pct plot with period column: ", recent_period_col)

    message("creating plot...")
    sch_dept_pct_plot <- plot_ly(sch_dept_pct, labels = ~major, values = as.formula(paste0("~`", recent_period_col, "`")), type = 'pie', marker = list(colorscale = 'Viridis'))
    sch_dept_pct_plot <- sch_dept_pct_plot %>%
      layout(legend = list(x = 100, y = 0.5),
             xaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE),
             yaxis = list(showgrid = FALSE, zeroline = FALSE, showticklabels = FALSE))

    message("DEBUG: Successfully created sch_dept_pct_plot")
  } else {
    message("DEBUG: Insufficient data for sch_dept_pct plot")
    sch_dept_pct_plot <- NULL
  }
  message("saving plot...")
  #save(sch_dept_pct_plot, file="credit-hours/sch_dept_pct_plot.Rda")
  d_params$plots[["sch_dept_pct_plot"]] <- sch_dept_pct_plot
  
  message("returning d_params with new plot(s) and table(s)...")
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
    #mutate(job_category = fct_reorder(job_category, total_hours)) %>%
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
    #mutate(job_category = fct_reorder(job_category, total_hours)) %>%
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


  college_credit_hours_plot <- ggplot(college_credit_hours, aes(x=term, y=total_hours)) +
    #ggtitle(d_params$prog_name) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(fill=department),stat="identity",position="stack") +
    scale_color_brewer(palette="Spectral") +
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

  college_credit_hours_comp_plot <- ggplot(diff_fr_college_hours, aes(x=term, y=diff_heavy)) +
    #ggtitle(d_params$prog_name) +
    theme(legend.position="bottom") +
    guides(color = guide_legend(title = "")) +
    geom_bar(aes(),stat="identity",position="stack") +
    scale_color_brewer(palette=d_params$palette) +
    xlab("Academic Year") + ylab("% diff from College")

  college_credit_hours_comp_plot
  d_params$plots[["college_credit_hours_comp_plot"]] <- college_credit_hours_comp_plot



  # Create dual y-axis comparison plot
  # Get department totals by academic period
  dept_totals <- credit_hours_data %>%
    filter(department == d_params$dept_code) %>%
    filter(campus %in% c("ABQ","EA")) %>%
    group_by(term) %>%
    summarise(dept_total = sum(total_hours), .groups = 'drop')

  # Get college totals by academic period
  college_totals <- credit_hours_data %>%
    filter(college == "AS") %>%
    filter(campus %in% c("ABQ","EA")) %>%
    group_by(term) %>%
    summarise(college_total = sum(total_hours), .groups = 'drop')

  # Combine the data
  dual_axis_data <- merge(dept_totals, college_totals, by = "term", all = TRUE)
  dual_axis_data[is.na(dual_axis_data)] <- 0

  # Calculate scaling factor to normalize department data to college scale
  max_college <- max(dual_axis_data$college_total, na.rm = TRUE)
  max_dept <- max(dual_axis_data$dept_total, na.rm = TRUE)
  scale_factor <- max_college / max_dept

  # Create the dual axis plot
  college_dept_dual_plot <- ggplot(dual_axis_data, aes(x = term)) +
    # College bars (primary y-axis)
    geom_col(aes(y = college_total, fill = "College Total"), alpha = 0.7, width = 0.6) +
    # Department line (scaled to college axis)
    geom_line(aes(y = dept_total * scale_factor, color = paste0(d_params$dept_code, " Department")),
              size = 2, group = 1) +
    geom_point(aes(y = dept_total * scale_factor, color = paste0(d_params$dept_code, " Department")),
               size = 3) +
    # Primary y-axis (college)
    scale_y_continuous(
      name = "College Credit Hours",
      labels = scales::comma,
      sec.axis = sec_axis(~ . / scale_factor,
                         name = paste0(d_params$dept_code, " Department Credit Hours"),
                         labels = scales::comma)
    ) +
    scale_fill_manual(values = c("College Total" = "#2E8B57")) +
    scale_color_manual(values = setNames("#FF6B35", paste0(d_params$dept_code, " Department"))) +
    labs(
      title = paste0("Credit Hours Comparison: AS College vs ", d_params$dept_code, " Department"),
      subtitle = "College bars (left axis) vs Department line (right axis)",
      x = "Academic Period Code",
      fill = "",
      color = ""
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.title.y.left = element_text(color = "#2E8B57"),
      axis.title.y.right = element_text(color = "#FF6B35"),
      axis.text.y.left = element_text(color = "#2E8B57"),
      axis.text.y.right = element_text(color = "#FF6B35"),
      axis.text.x = element_text(angle = 45, hjust = 1)
    ) +
    guides(fill = guide_legend(order = 1), color = guide_legend(order = 2))

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
  chm_by_subj_level <- credit_hours_data_main %>% filter(level != "total")

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
  chm_by_subj <- credit_hours_data_main %>% filter(level == "total")

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
    mutate(period_hours = sum(total_hours)) %>%
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




