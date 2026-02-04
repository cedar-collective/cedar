#' Get Courses Common to Both Terms
#'
#' Finds courses offered in both comparison terms and calculates year-over-year
#' enrollment changes. This helps identify enrollment trends and capacity needs.
#'
#' @param term_courses Named list with two data frames:
#'   \itemize{
#'     \item \code{start} - Courses from starting term
#'     \item \code{end} - Courses from ending term
#'   }
#' @param enrl_summary Data frame of enrollment summary data with columns:
#'   campus, college, term, subject_course, gen_ed_area, enrolled
#'
#' @return Data frame of courses common to both terms with enrollment difference
#'   calculated. Includes column \code{enrl_diff_from_last_year} showing change
#'   in enrollment between terms.
#'
#' @details
#' Uses set intersection to find courses in both terms, merges with enrollment
#' data, and computes year-over-year enrollment differences using lag().
#'
#' @seealso \code{\link{seatfinder}} for the main seatfinder workflow
get_courses_common <- function(term_courses, enrl_summary) {

  message("[seatfinder.R] Welcome to get_courses_common! Finding courses common to both terms...")
  courses_intersect <- intersect(term_courses[["start"]], term_courses[["end"]])
  courses_intersect <- merge(courses_intersect, enrl_summary, by = c("campus", "college", "subject_course", "gen_ed_area"))

  message("[seatfinder.R] Computing enrollment difference between terms...")
  courses_intersect <- courses_intersect %>% group_by(subject_course) %>% arrange(campus, college, term, subject_course) %>%
    mutate(enrl_diff_from_last_year = enrolled - lag(enrolled))

  return(courses_intersect)
}



#' Get Course Differences Between Terms
#'
#' Identifies courses offered in one term but not the other, helping track
#' new course offerings and discontinued courses.
#'
#' @param term_courses Named list with two data frames:
#'   \itemize{
#'     \item \code{start} - Courses from starting term
#'     \item \code{end} - Courses from ending term
#'   }
#'
#' @return Named list with two elements:
#'   \itemize{
#'     \item \code{prev} - Courses offered in start term but NOT in end term (discontinued)
#'     \item \code{new} - Courses offered in end term but NOT in start term (new offerings)
#'   }
#'
#' @details
#' Uses set difference (setdiff) to find courses unique to each term.
#' This helps identify:
#' \itemize{
#'   \item New course offerings that need capacity planning
#'   \item Discontinued courses that may affect student progression
#'   \item Changes in gen ed course availability
#' }
#'
#' @seealso \code{\link{seatfinder}} for the main seatfinder workflow
get_courses_diff <- function (term_courses) {

  message ("[seatfinder.R] Welcome to get_courses_diff! Finding differences between the terms...")
  previously_offered <- setdiff(term_courses[["start"]], term_courses[["end"]])
  newly_offered <- setdiff(term_courses[["end"]], term_courses[["start"]])

  courses_diff <- list()
  courses_diff[["prev"]] <- previously_offered
  courses_diff[["new"]] <- newly_offered

  message("[seatfinder.R] Found ", nrow(previously_offered), " previously offered and ", nrow(newly_offered), " newly offered courses")
  return(courses_diff)
}



#' Normalize Delivery Method Codes
#'
#' Standardizes delivery method codes by grouping variants of face-to-face
#' instruction under a single "f2f" category.
#'
#' @param courses Data frame with delivery_method column
#'
#' @return Data frame with added \code{method} column containing normalized values
#'
#' @details
#' Creates a new \code{method} column that normalizes delivery_method by:
#' \itemize{
#'   \item "0" → "f2f"
#'   \item "ENH" (Enhanced) → "f2f"
#'   \item "HYB" (Hybrid) → "f2f"
#'   \item All other values preserved as-is
#' }
#'
#' This grouping helps aggregate enrollment across similar delivery modes.
#'
#' @note TODO: move to misc_functions? TODO: also change NA to 0 (or vice versa)
#' @seealso \code{\link{seatfinder}} for usage context
normalize_inst_method <- function (courses) {
  courses$method <- courses$delivery_method
  courses$method[courses$delivery_method == "0"] <- "f2f"
  courses$method[courses$delivery_method == "ENH"] <- "f2f"
  courses$method[courses$delivery_method == "HYB"] <- "f2f"

  return(courses)
}


#' Analyze Course Seat Availability Across Terms
#'
#' Main seatfinder function that performs comprehensive seat availability analysis
#' by comparing course offerings between terms (typically year-over-year). Helps
#' identify capacity needs, enrollment trends, and gen ed course availability.
#'
#' @param students Data frame from cedar_students table (used for DFW rate calculation)
#' @param courses Data frame from cedar_sections table with enrollment and capacity data
#' @param cedar_faculty Data frame from cedar_faculty table (used for instructor job category in grades)
#' @param opt Options list with required and optional parameters:
#'   \itemize{
#'     \item \code{term} - (Required) Term code or range (e.g., "202510" or "202410,202510")
#'       If single term, compares to same term previous year (term - 100)
#'     \item \code{part_term} - (Optional) Part of term filter (e.g., "1H", "2H", "FT")
#'     \item \code{department} - (Optional) Department filter
#'     \item \code{subject} - (Optional) Subject filter
#'     \item \code{group_cols} - (Optional) Custom grouping columns
#'       Defaults to: campus, college, term, subject_course, part_term, level, gen_ed_area
#'   }
#'
#' @return Named list with six data frames:
#'   \describe{
#'     \item{type_summary}{Courses with availability differences by part_term.
#'       Columns: campus, college, term, part_term, subject_course, avail,
#'       dfw_pct, avail_diff (change from previous year), enrolled, gen_ed_area}
#'     \item{courses_common}{Courses offered in both terms with enrollment changes.
#'       Includes enrl_diff_from_last_year showing YoY enrollment trends}
#'     \item{courses_prev}{Courses offered in start term but NOT in end term (discontinued)}
#'     \item{courses_new}{Courses offered in end term but NOT in start term (new offerings)}
#'     \item{gen_ed_summary}{Gen ed courses with available seats, sorted by area and availability}
#'     \item{gen_ed_likely}{Gen ed courses currently at zero capacity (may open later)}
#'   }
#'
#' @details
#' Seatfinder workflow:
#' \enumerate{
#'   \item Parse term parameter (single term vs comparison range)
#'   \item Get enrollment summary with configurable grouping (via get_enrl)
#'   \item Merge DFW rates from grades data (via get_grades)
#'   \item Identify courses common to both terms (via get_courses_common)
#'   \item Identify new and discontinued courses (via get_courses_diff)
#'   \item Pivot to calculate availability changes (avail_diff)
#'   \item Filter and sort gen ed courses by availability
#' }
#'
#' Use cases for seatfinder:
#' \itemize{
#'   \item **Semester Planning**: Which courses need additional sections?
#'   \item **Capacity Analysis**: How does seat availability compare to last year?
#'   \item **Gen Ed Management**: Which gen ed courses have open seats?
#'   \item **Enrollment Forecasting**: What are enrollment trends by course type?
#'   \item **New Course Planning**: Which courses are new this term?
#' }
#'
#' **Important**: Always uses the exclude list (opt$uel = TRUE) and active courses
#' only (opt$status = "A"). Aggregates section enrollments by course type.
#'
#' @examples
#' \dontrun{
#' # Compare Fall 2025 to Fall 2024 (default one-year comparison)
#' opt <- list(term = "202580", part_term = "FT", department = "MATH")
#' results <- seatfinder(cedar_students, cedar_sections, cedar_faculty, opt)
#'
#' # View courses with largest availability decreases
#' head(results$type_summary %>% arrange(avail_diff))
#'
#' # Compare specific terms
#' opt <- list(term = "202410,202510")  # Spring 2024 vs Spring 2025
#' results <- seatfinder(cedar_students, cedar_sections, cedar_faculty, opt)
#'
#' # Check gen ed availability
#' head(results$gen_ed_summary)
#' }
#'
#' @seealso
#' \code{\link{get_enrl}} for enrollment aggregation,
#' \code{\link{get_courses_common}} for term comparison,
#' \code{\link{get_courses_diff}} for new/discontinued courses,
#' \code{\link{create_seatfinder_report}} for report generation
#'
#' @export
seatfinder <- function (students, courses, cedar_faculty, opt) {
  
  ########## for studio testing
  # opt <- list()
  # opt$term <- "202510"
  # opt$pt <- "2H"
  # opt$dept <- "HIST"
  # courses <- load_courses()
  # students <- load_students()
  
  message("[seatfinder.R] Welcome to seatfinder!")
  
  # set opt 
  message ("[seatfinder.R] Seatfinder always uses the exclude list, excludes AOP courses, includes only active courses, and aggregates section enrollments by course_type...")
  opt$uel <- TRUE
  opt$status <- "A"
  
  # standard behavior is to use specified term param and subtract one year for comparison
  # if term param has two terms separated by comma, compare those instead
  term <- opt[["term"]]
  
  # extract start and end codes
  if (grepl(",", term)) {
    opt[["term_start"]] <- substring(term, 1,6)
    opt[["term_end"]] <- substring(term, 8,13)
  } else {
    opt[["term_end"]] <- term
    opt[["term_start"]] <- as.character(as.numeric(term) - 100) # default to one year previous to specified term
    
    # adjust term param for course filtering
    opt[["term"]] <- paste0(opt[["term_start"]],",",opt[["term_end"]])
  }
  
  # list specified and implied options
  print(opt)
  
  # get enrollment summary (which does opt filtering)
  message("[seatfinder.R] Getting enrollment summary...")
  # if no grouping specified, aggregate by course/method/part_term (not individual sections)
  if (is.null(opt[["group_cols"]]) || length(opt[["group_cols"]]) == 0) {
    opt[["group_cols"]] <- c("campus","college","term","subject_course","part_term","level","gen_ed_area")
  } else {
    # ensure required columns for downstream merging are always included
    required_cols <- c("campus", "college", "term", "subject_course", "gen_ed_area")
    opt[["group_cols"]] <- unique(c(required_cols, opt[["group_cols"]]))
  }
  message("[seatfinder.R] Using group_cols: ", paste(opt[["group_cols"]], collapse = ", "))
  enrl_summary <- get_enrl(courses,opt)


  # add mean DFW rate for course
  # make sure grades match course params (part_term, method, etc)
  # set params for get_grades
  myopt <- opt
  myopt$course <- as.list(enrl_summary$subject_course)
  myopt$term <- NULL # remove term param to get dfw rates across all terms, not just seatfinder terms
  
  #TODO: document what get_grades is doing & getting
  message("[seatfinder.R] Getting grades data for courses in enrollment summary...")
  grades_list <- get_grades(students, cedar_faculty, myopt)

  # Check if grades data is empty (no students matched filters)
  if (is.null(grades_list) || length(grades_list) == 0 ||
      is.null(grades_list[["course_avg"]]) || nrow(grades_list[["course_avg"]]) == 0) {
    message("[seatfinder.R] WARNING: No grades data available for the selected filters")
    message("[seatfinder.R] This usually means:")
    message("[seatfinder.R]   - No historical grade data for these courses")
    message("[seatfinder.R]   - Filters are too restrictive (no students match)")
    message("[seatfinder.R]   - Term is in-progress with no final grades yet")
    message("[seatfinder.R] Continuing without DFW data...")

    # Add NA dfw_pct column to enrollment summary
    enrl_summary$dfw_pct <- NA_real_

    # Continue with rest of seatfinder logic (skip grade merging)
    message("[seatfinder.R] Skipping grade data merge")
    # Jump to line 284 logic (after grade merge) by setting grades to NULL
    grades <- NULL
  } else {
    # Extract course_avg from grades list
    grades <- grades_list[["course_avg"]]

    message("[seatfinder.R] Grades data has rows: ", nrow(grades))
    message("[seatfinder.R] Grades data columns: ", paste(colnames(grades), collapse = ", "))
    message("[seatfinder.R] Sample of grades data:")
    message(head(grades))
  }


  # Select columns from grades data and merge (only if grades available)
  if (!is.null(grades)) {
    # get_grades() returns dfw_pct column directly
    message("[seatfinder.R] Selecting needed columns from grades data...")

    # Enforce CEDAR column names - no fallback to old naming conventions
    required_cols <- c("campus", "college", "subject_course", "dfw_pct")
    missing_cols <- setdiff(required_cols, colnames(grades))

    if (length(missing_cols) > 0) {
      message("[seatfinder.R] ERROR: Missing required CEDAR columns in grades data: ", paste(missing_cols, collapse = ", "))
      message("[seatfinder.R] Available columns: ", paste(colnames(grades), collapse = ", "))
      stop("Grades data must use CEDAR column names. Missing: ", paste(missing_cols, collapse = ", "))
    }

    grades <- grades %>%
      select(campus, college, subject_course, dfw_pct)

    # merge grade data with enrl data
    message("[seatfinder.R] Merging grade data with enrollment summary...")
    message("[seatfinder.R] enrl_summary columns: ", paste(colnames(enrl_summary), collapse = ", "))
    message("[seatfinder.R] grades columns: ", paste(colnames(grades), collapse = ", "))
    enrl_summary <- merge(enrl_summary, grades, by = c("campus","college","subject_course"), all.x = TRUE)
  } else {
    message("[seatfinder.R] Skipping grade merge (no grades data available)")
  }

  # Clean up columns before creating output dataframes
  message("[seatfinder.R] Removing unnecessary columns from enrollment summary...")
  enrl_summary <- enrl_summary %>% select(-any_of(c("xl_sections", "reg_sections", "delivery_method")))

  # get only core course data for diff and intersect comparison
  cols <- c("campus", "college", "term", "subject_course", "gen_ed_area")
  message("[seatfinder.R] Selecting needed columns from enrollment summary for course comparisons: ", paste(cols, collapse = ", "))
  course_names <- enrl_summary %>%
    ungroup() %>%
    select(all_of(cols))

  # create separate DFs for start and end terms
  start_term_courses <- course_names %>% filter(term == opt[["term_start"]])
  end_term_courses <- course_names %>% filter(term == opt[["term_end"]])

  # prep new container lists
  term_courses <- list()
  courses_list <- list()

  # need to subtract out the term col for the intersection and setdiffs
  message("[seatfinder.R] Getting first and second term courses...")
  term_courses[["start"]] <- start_term_courses %>% ungroup() %>% select(-term) %>% arrange(campus, college, subject_course)
  term_courses[["end"]] <- end_term_courses %>% ungroup() %>% select(-term) %>% arrange(campus, college, subject_course)
  
  
  # find enrollment differences compared to last year across course types
  message("[seatfinder.R] Computing course type summary with enrollment differences...")

  # pivot to compare start vs end term availability
  course_type_summary <- enrl_summary %>%
    select(campus, college, term, part_term, subject_course, gen_ed_area, avail, dfw_pct) %>%
    pivot_wider(names_from = term, values_from = avail, names_prefix = "avail_") %>%
    mutate(
      avail_diff = .data[[paste0("avail_", opt[["term_end"]])]] - .data[[paste0("avail_", opt[["term_start"]])]]
    ) %>%
    # merge back with full end term data to get enrolled count and current avail
    left_join(
      enrl_summary %>% filter(term == opt[["term_end"]]) %>% select(campus, college, part_term, subject_course, gen_ed_area, enrolled, avail, term),
      by = c("campus", "college", "subject_course", "gen_ed_area", "part_term")
    ) %>%

    # keep only courses that exist in end term (have non-NA term after join)
    filter(!is.na(term)) %>%
    select(-starts_with("avail_202")) %>%  # remove the pivoted columns
    ungroup() %>%
    select(campus, college = college, term, part_term, subject_course, avail, dfw_pct, avail_diff, enrolled = enrolled, gen_ed_area = gen_ed_area) %>%
    arrange(campus, college, term, part_term, subject_course) %>%
    filter(avail > 0)


  # add to output list
  courses_list[["type_summary"]] <- course_type_summary
  
  # find common courses between two terms
  courses_common <- get_courses_common(term_courses, enrl_summary)

  # to clean up list, filter for just the target term
  courses_common <- courses_common %>%
    filter(term == opt[["term_end"]]) %>%
    arrange(campus, college, subject_course, enrl_diff_from_last_year)

  courses_list[["courses_common"]] <- courses_common


  # find difference between terms (courses offered previously, and courses offered now)
  courses_diff <- get_courses_diff(term_courses)
  courses_list[["courses_prev"]] <- merge(courses_diff[["prev"]], enrl_summary, by = c("campus","college", "subject_course","gen_ed_area"))
  courses_list[["courses_new"]] <- merge(courses_diff[["new"]], enrl_summary, by = c("campus","college","subject_course","gen_ed_area"))


  # make list of only gen ed courses
  gen_ed_summary <- enrl_summary %>% group_by(campus, college, term, subject_course, part_term) %>%
    filter(!is.na(gen_ed_area)) %>%
    filter(avail > 0) %>%
    filter(term == opt[["term_end"]]) %>%
    arrange(gen_ed_area, desc(avail), campus, college, subject_course)

  courses_list[["gen_ed_summary"]] <- gen_ed_summary

  # find courses that are active but likely capped at 0 for now
  gen_ed_likely <- enrl_summary %>% group_by(campus, college, term, subject_course, part_term) %>%
    filter(!is.na(gen_ed_area)) %>%
    filter(term == opt[["term_end"]]) %>%
    filter(avail == 0 & enrolled == 0) %>%
    arrange(gen_ed_area, campus, college, subject_course)

  courses_list[["gen_ed_likely"]] <- gen_ed_likely
  
  message("[seatfinder.R] All done in seatfinder! Returning course_list...")
  return (courses_list)
}




#' Create Seatfinder Report
#'
#' Generates a formatted seatfinder report by calling seatfinder() and passing
#' results to an R Markdown template for rendering.
#'
#' @param students Data frame from cedar_students table
#' @param courses Data frame from cedar_sections table
#' @param cedar_faculty Data frame from cedar_faculty table
#' @param opt Options list passed to seatfinder (see \code{\link{seatfinder}} for details)
#'   Must include: term, and optionally part_term (aliased as "pt" for filenames)
#'
#' @return Invisibly returns the report file path (via create_report)
#'
#' @details
#' This wrapper function:
#' \enumerate{
#'   \item Calls seatfinder() to generate all analyses
#'   \item Packages results into d_params for R Markdown
#'   \item Sets output filename and directory
#'   \item Generates report via create_report()
#' }
#'
#' Output filename format: `seatfinder-{term}-{part_term}.html`
#' Default output directory: `{cedar_output_dir}/seatfinder-reports/`
#'
#' @examples
#' \dontrun{
#' # Generate report for Fall 2025 full term MATH courses
#' opt <- list(term = "202580", pt = "FT", department = "MATH")
#' create_seatfinder_report(cedar_students, cedar_sections, cedar_faculty, opt)
#' # Creates: seatfinder-202580-FT.html
#' }
#'
#' @seealso
#' \code{\link{seatfinder}} for the core analysis function,
#' \code{\link{create_report}} for the report generation engine
#'
#' @export
create_seatfinder_report <- function (students, courses, cedar_faculty, opt) {

  message("[seatfinder.R] Welcome to create_seatfinder_report!")

  # begin setting payload for Rmd file
  d_params <- list("term"  = opt[["term"]],
                   "opt" = opt,
                   "tables" = list()
  )

  # call basic seatfinder
  courses_list <- seatfinder(students, courses, cedar_faculty, opt)

  d_params$tables[["type_summary"]] <- courses_list[["type_summary"]]
  d_params$tables[["courses_common"]] <- courses_list[["courses_common"]]
  d_params$tables[["courses_prev"]] <- courses_list[["prev"]]
  d_params$tables[["courses_new"]] <- courses_list[["new"]]

  # store in d_params to send to Rmd
  d_params$tables[["gen_ed_summary"]] <- courses_list[["gen_ed_summary"]]
  d_params$tables[["gen_ed_likely"]] <- courses_list[["gen_ed_likely"]]

  # set output data
  d_params$output_filename <- paste0("seatfinder-",opt[["term"]],"-",opt[["pt"]])
  d_params$rmd_file <- "Rmd/seatfinder-report.Rmd"
  d_params$output_dir_base <- paste0(cedar_output_dir,"seatfinder-reports/")

  # generate report
  message("[seatfinder.R] Generating seatfinder report...")
  create_report(opt,d_params)

  message("[seatfinder.R] Seatfinder report complete!")
} # end create_seatfinder_report

