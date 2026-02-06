#' Department Report Generation for CEDAR
#'
#' @description
#' This file contains functions for generating comprehensive department reports.
#' Reports include headcount, degrees, credit hours, grades (DFW), enrollment, and SFR analysis.
#'
#' @section Functions:
#'
#' **Core Functions:**
#' - `set_payload()` - Initialize d_params structure with department metadata
#' - `create_dept_report_data()` - Generate all plots/tables for interactive reports (used by Shiny)
#' - `create_dept_report()` - Generate full RMarkdown HTML reports (batch processing)
#'
#' @section Data Requirements:
#'
#' **data_objects list must contain:**
#' - `academic_studies` - Student program enrollment data (for headcount)
#' - `degrees` - Graduate data with CEDAR naming (for degrees analysis)
#' - `class_lists` - Course enrollment data (for credit hours, grades)
#' - `cedar_faculty` - Faculty HR data with CEDAR naming (for SFR, DFW by instructor type)
#' - `DESRs` - Demand-enrollment data (for enrollment trends)
#'
#' @section Usage:
#'
#' ```r
#' # Interactive report (for Shiny)
#' opt <- list(dept = "HIST", prog = NULL, shiny = TRUE)
#' d_params <- create_dept_report_data(data_objects, opt)
#'
#' # HTML report (RMarkdown)
#' opt <- list(dept = "HIST", output = "html")
#' create_dept_report(data_objects, opt)
#' ```
#'
#' @name dept-report
NULL

#' Initialize Department Report Parameters
#'
#' @description
#' Creates the d_params structure with department metadata, program mappings,
#' and empty containers for tables and plots. This is the first step in
#' department report generation.
#'
#' @param dept_code Character. Department code (e.g., "HIST", "MATH")
#' @param prog_focus Character or NULL. Optional program code to focus on
#'   a specific program within the department (e.g., "HIST" for History major only)
#'
#' @return List containing:
#'   - `dept_code` - Department code
#'   - `dept_name` - Full department name
#'   - `subj_codes` - Subject codes associated with department
#'   - `prog_focus` - Program focus (if specified)
#'   - `prog_names` - Program names from major_to_program_map
#'   - `prog_codes` - Program codes
#'   - `tables` - Empty list (will be populated by cone functions)
#'   - `plots` - Empty list (will be populated by cone functions)
#'   - `term_start` - Start term from config
#'   - `term_end` - End term from config
#'   - `palette` - Color palette from config
#'
#' @details
#' Uses global mapping variables:
#' - `prgm_to_dept_map` - Maps program codes to departments
#' - `major_to_program_map` - Maps major names to program codes
#' - `subj_to_dept_map` - Maps subject codes to departments
#' - `dept_code_to_name` - Maps department codes to full names
#'
#' @examples
#' \dontrun{
#' # All programs in History department
#' d_params <- set_payload("HIST")
#'
#' # Focus on specific program
#' d_params <- set_payload("HIST", prog_focus = "HIST")
#' }
#'
#' @export
set_payload <- function (dept_code, prog_focus = NULL) {
  message("[dept-report.R] Welcome to set_payload!")
  message("[dept-report.R] Received dept_code: ", dept_code)
  
  # set program codes
  message("[dept-report.R] Setting program codes and names from mappings.R...")

# if program focus specified
  if (!is.null(prog_focus)) {
    prog_codes <- prog_focus
  } else {
    # get all program codes associated with the dept; use prgm_to_dept_map
    prog_codes <- names(prgm_to_dept_map[which(prgm_to_dept_map == dept_code)])
    message("[dept-report.R] prog_codes: ", paste(prog_codes, collapse=", "))
  }
  
  
  # to get program name variants that appear in MyReports
  # TODO: any reason to use prog_names rather than prog_codes to filter MyReports data?
  prog_names <- names(major_to_program_map[which(major_to_program_map %in% prog_codes)])
  message("[dept-report.R] prog_names: ", paste(prog_names, collapse=", "))

  # set d_params object
  message("[dept-report.R] setting d_params object...")
  d_params <- list("dept_code" = dept_code,
                   "dept_name" = dept_code_to_name[dept_code],
                   "subj_codes" = names(subj_to_dept_map[which(subj_to_dept_map == dept_code)]),
                   "prog_focus" = prog_focus,
                   "prog_names" = prog_names,
                   "prog_codes" = prog_codes,
                   "tables" = list(),
                   "plots" = list(),
                   "term_start" = cedar_report_start_term,
                   "term_end"  = cedar_report_end_term,
                   "palette" = cedar_report_palette
  )
  
  message("[dept-report.R] returning d_params set as:\n", 
        paste(capture.output(str(d_params, max.level = 1)), collapse = "\n"))

  return (d_params)
}


#' Generate Department Report Data (Interactive)
#'
#' @description
#' Generates all tables and plots for department reports by calling individual
#' cone functions (headcount, degrees, credit hours, grades, enrollment, SFR).
#' This function is used by the Shiny app for interactive report generation.
#'
#' @param data_objects List containing required data sources:
#'   - `academic_studies` - Student program enrollment (headcount)
#'   - `degrees` - Graduate data with CEDAR naming (cedar_degrees)
#'   - `class_lists` - Course enrollment data (credit hours, grades)
#'   - `cedar_faculty` - Faculty HR data with CEDAR naming (SFR, DFW analysis)
#'   - `DESRs` - Demand-enrollment data (enrollment trends)
#' @param opt Options list with:
#'   - `dept` (required) - Department code (e.g., "HIST")
#'   - `prog` (optional) - Program focus code
#'   - `shiny` (optional) - Boolean indicating Shiny context
#'
#' @return d_params list with populated tables and plots:
#'   - All fields from `set_payload()`
#'   - `tables` - Named list of data frames from all analyses
#'   - `plots` - Named list of plotly/ggplot objects from all analyses
#'
#' @details
#' **Processing workflow:**
#' 1. Calls `set_payload()` to initialize structure
#' 2. Headcount: `get_headcount_data_for_dept_report()`
#' 3. Degrees: `get_degrees_for_dept_report()`
#' 4. Credit Hours: `get_credit_hours_for_dept_report()`, `credit_hours_by_major()`, `credit_hours_by_fac()`
#' 5. Grades: `get_grades_for_dept_report()` (DFW analysis)
#' 6. Enrollment: `get_enrl_for_dept_report()`
#' 7. SFR: `get_sfr_data_for_dept_report()`
#'
#' **CEDAR Migration Notes:**
#' - Uses CEDAR dataset keys exclusively: cedar_faculty, cedar_students, cedar_programs, cedar_sections, cedar_degrees
#' - No legacy fallbacks; all data must be in CEDAR format with lowercase column names
#' - Requires `department` column (CEDAR) in cedar_students for filtering
#'
#' **Typical outputs include:**
#' - Headcount tables/plots by program and level
#' - Degree award trends by major and type
#' - Credit hour production by term
#' - DFW rates by course and instructor type
#' - Enrollment trends by term type
#' - Student-faculty ratios over time
#'
#' @examples
#' \dontrun{
#' # Load data (CEDAR naming only)
#' data_objects <- list(
#'   cedar_programs = readRDS(paste0(cedar_data_dir, "cedar_programs.Rds")),
#'   cedar_degrees = readRDS(paste0(cedar_data_dir, "cedar_degrees.Rds")),
#'   cedar_students = readRDS(paste0(cedar_data_dir, "cedar_students.Rds")),
#'   cedar_faculty = readRDS(paste0(cedar_data_dir, "cedar_faculty.Rds")),
#'   cedar_sections = readRDS(paste0(cedar_data_dir, "cedar_sections.Rds"))
#' )
#'
#' # Generate report data
#' opt <- list(dept = "HIST", shiny = TRUE)
#' d_params <- create_dept_report_data(data_objects, opt)
#'
#' # Access outputs
#' names(d_params$tables)
#' names(d_params$plots)
#' d_params$plots$degree_summary_faceted_by_major_plot
#' }
#'
#' @seealso
#' \code{\link{set_payload}}, \code{\link{create_dept_report}} for HTML generation
#'
#' @export
create_dept_report_data <- function(data_objects, opt) {
  message("[dept-report.R] Welcome to create_dept_report_data!")

  # Validate CEDAR data structure (CEDAR naming only, no legacy fallbacks)
  message("[dept-report.R] Validating CEDAR data objects...")
  required_datasets <- c("cedar_students", "cedar_degrees", "cedar_sections", "cedar_faculty", "cedar_programs")
  missing_datasets <- setdiff(required_datasets, names(data_objects))

  if (length(missing_datasets) > 0) {
    stop("[dept-report.R] Missing required CEDAR datasets: ", paste(missing_datasets, collapse = ", "),
         "\n  Found data_objects keys: ", paste(names(data_objects), collapse = ", "),
         "\n  All CEDAR datasets must be loaded before generating reports.")
  }

  message("[dept-report.R] All required CEDAR datasets present")
  message("[dept-report.R] cedar_faculty rows: ", nrow(data_objects[["cedar_faculty"]]))

  
  # try to resolve incoming dept to dept code
  # originally, dept code was passed in, like "HIST"
  # but now may be value from Department column, like "History" or "AS Anthropology"
  # look up dept code from dept name if needed
  incoming_dept <- opt[["dept"]]
  if (incoming_dept %in% names(hr_org_desc_to_dept_map)) {
    dept_code <- hr_org_desc_to_dept_map[[incoming_dept]]
    message("[dept-report.R] Resolved incoming HR org desc '", incoming_dept, "' to dept code '", dept_code, "'")
  }
  else {
    message("[dept-report.R] WARNING: Using raw incoming dept code: ", incoming_dept)
    dept_code <- opt[["dept"]]
  }
  
  # set prog_focus in case report should focus on specific program
  prog_focus <- opt[["prog"]]

  # initialize payload
  d_params <- set_payload(dept_code, prog_focus)

  # Store raw department for downstream filtering (cedar tables have raw values like "AS Anthropology")
  d_params[["dept_raw"]] <- incoming_dept

  ####### HEADCOUNT
  message("[dept-report.R] About to call get_headcount_data_for_dept_report...")
  d_params <- get_headcount_data_for_dept_report(data_objects[["cedar_programs"]], d_params)
  message("[dept-report.R] Completed headcount data processing")

  ####### DEGREES
  message("[dept-report.R] About to call get_degrees_for_dept_report...")
  d_params <- get_degrees_for_dept_report(data_objects[["cedar_degrees"]], d_params)
  message("[dept-report.R] Completed degrees data processing")

  ####### CREDIT HOURS
  message("[dept-report.R] About to filter cedar_students by dept_code...")
  # CEDAR naming required - no fallbacks
  if (!"department" %in% colnames(data_objects[["cedar_students"]])) {
    stop("[dept-report.R] cedar_students missing required CEDAR column: 'department'\n",
         "  Expected CEDAR format with lowercase column names.\n",
         "  Found columns: ", paste(colnames(data_objects[["cedar_students"]]), collapse = ", "))
  }

  # cedar_students.department uses DEPT codes (e.g., "ANTH"), not raw Department names
  message("[dept-report.R] Using CEDAR column: department, filtering by dept_code: ", dept_code)
  filtered_cl_by_dept <- data_objects[["cedar_students"]] %>%
    filter(department == dept_code)

  # NOTE: get_credit_hours_for_dept_report needs UNFILTERED data to compare dept vs college
  # It will filter by dept_code internally using d_params$dept_code
  message("[dept-report.R] About to call get_credit_hours_for_dept_report...")
  d_params <- get_credit_hours_for_dept_report(data_objects[["cedar_students"]], d_params)
  message("[dept-report.R] Completed credit hours data processing")

  ####### CREDIT HOURS BY MAJOR
  message("[dept-report.R] About to call credit_hours_by_major...")
  d_params <- credit_hours_by_major(filtered_cl_by_dept, d_params)
  message("[dept-report.R] Completed credit_hours_by_major processing")

  ####### CREDIT HOURS BY FACULTY
  message("[dept-report.R] About to call credit_hours_by_fac...")
  d_params <- credit_hours_by_fac(data_objects, d_params)
  message("[dept-report.R] Completed credit_hours_by_fac processing")

  ####### GRADES
  message("[dept-report.R] About to call get_grades_for_dept_report...")
  # CEDAR naming required - no fallbacks
  if (!"cedar_faculty" %in% names(data_objects)) {
    stop("[dept-report.R] data_objects missing required 'cedar_faculty' dataset\n",
         "  Expected CEDAR format with cedar_faculty key.\n",
         "  Run transform-hr-to-cedar.R to create cedar_faculty from hr_data.\n",
         "  Found data_objects keys: ", paste(names(data_objects), collapse = ", "))
  }

  if (is.null(data_objects[["cedar_faculty"]])) {
    stop("[dept-report.R] cedar_faculty dataset is NULL\n",
         "  Load cedar_faculty.Rds or run transform-hr-to-cedar.R")
  }

  message("[dept-report.R] Using CEDAR faculty data: cedar_faculty")
  d_params <- get_grades_for_dept_report(filtered_cl_by_dept,
                                         data_objects[["cedar_faculty"]], opt, d_params)
  message("[dept-report.R] Completed grades data processing")

  ####### ENROLLMENT
  message("[dept-report.R] About to call get_enrl_for_dept_report...")
  d_params <- get_enrl_for_dept_report(data_objects[["cedar_sections"]], d_params)
  message("[dept-report.R] Completed enrollment data processing")

  ####### SFRs
  message("[dept-report.R] About to call get_sfr_data_for_dept_report...")
  d_params <- get_sfr_data_for_dept_report(data_objects, d_params)
  message("[dept-report.R] Completed SFR data processing")
  
  message("[dept-report.R] About to return d_params from create_dept_report_data")
  return(d_params)
}



create_dept_report <- function (data_objects,opt) {
  
  message("[dept-report.R] Welcome to create_dept_report!")

  gc()  # clean up memory before starting

  # for studio testing...
  #opt <- list()
  #opt$output <- "html"
  #opt$dept <- "LCL"
  #opt$prog <- ""
  
# convert dept param to dept_list for processing
  dept_list <- convert_param_to_list(opt[["dept"]]) 
  
  # loop through each unit in dept list
  for (dept in dept_list) {
    # for studio testing a single dept
    #dept <- "AMST"
    message("[dept-report.R] looking at dept: ", dept)
    message("[dept-report.R] length: ", length(dept))

    dept_code <- ""
    prog_focus <- NULL
    
    if (length(dept) == 2) {
      dept_code <- unlist(dept)[1]
      prog_focus <- unlist(dept)[2]
    } else {
      dept_code <- dept
      prog_focus <- NULL
    }
  
    # set dept_code and prog_focus
    opt[["dept"]] <- dept_code
    opt[["prog"]] <- prog_focus

    # get dept report data
    message("[dept-report.R] about to call create_dept_report_data...")
    d_params <- create_dept_report_data(data_objects, opt)

    # set output_filename using raw incoming dept (not resolved dept_code)
    # This ensures filename matches what was passed from UI/CLI
    message("[dept-report.R] setting output filename...")
    if (!is.null(d_params$prog_focus) && !is.na(d_params$prog_focus)) {
      output_filename <- paste0(d_params$dept_raw, "-", d_params$prog_focus)
    } else {
      output_filename <- d_params$dept_raw
    }
    # Sanitize filename (replace spaces/special chars)
    output_filename <- gsub(" ", "_", output_filename)
    message("[dept-report.R] output_filename: ", output_filename)
    
    d_params$output_filename <- output_filename
    d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "dept-report.Rmd")
    d_params$output_dir_base <- file.path(cedar_output_dir, "dept-reports")
    
    # create report (defined in utils.R)
    create_report(opt, d_params)
  
  } # end of dept loop
  message("[dept-report.R] Completed create_dept_report for all departments!")
  return("dept-report success!")
}

