SEATFINDER_COURSE_KEYS <- c(
  "campus", "college", "part_term", "subject_course", "course_title", "gen_ed_area"
)


validate_seatfinder_course_keys <- function(df, label) {
  missing_cols <- setdiff(SEATFINDER_COURSE_KEYS, names(df))
  if (length(missing_cols) > 0) {
    stop("[seatfinder.R] ", label, " is missing required course identity columns: ",
         paste(missing_cols, collapse = ", "))
  }
  invisible(TRUE)
}


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
#'   campus, college, term, part_term, subject_course, course_title,
#'   gen_ed_area, enrolled
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

  cedar_debug("[seatfinder.R] Welcome to get_courses_common! Finding courses common to both terms...")
  validate_seatfinder_course_keys(term_courses[["start"]], "term_courses$start")
  validate_seatfinder_course_keys(term_courses[["end"]], "term_courses$end")
  validate_seatfinder_course_keys(enrl_summary, "enrl_summary")

  courses_intersect <- intersect(term_courses[["start"]], term_courses[["end"]])
  if (nrow(courses_intersect) == 0) return(enrl_summary[0, , drop = FALSE])
  courses_intersect <- merge(courses_intersect, enrl_summary,
                             by = SEATFINDER_COURSE_KEYS)

  cedar_debug("[seatfinder.R] Computing enrollment difference between terms...")
  courses_intersect <- courses_intersect %>%
    group_by(across(all_of(SEATFINDER_COURSE_KEYS))) %>%
    arrange(campus, college, part_term, subject_course, course_title, term) %>%
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

  cedar_debug("[seatfinder.R] Welcome to get_courses_diff! Finding differences between the terms...")
  validate_seatfinder_course_keys(term_courses[["start"]], "term_courses$start")
  validate_seatfinder_course_keys(term_courses[["end"]], "term_courses$end")

  previously_offered <- setdiff(term_courses[["start"]], term_courses[["end"]])
  newly_offered <- setdiff(term_courses[["end"]], term_courses[["start"]])

  courses_diff <- list()
  courses_diff[["prev"]] <- previously_offered
  courses_diff[["new"]] <- newly_offered

  cedar_debug("[seatfinder.R] Found ", nrow(previously_offered), " previously offered and ", nrow(newly_offered), " newly offered courses")
  return(courses_diff)
}


empty_seatfinder_result <- function() {
  empty <- tibble::tibble()
  list(
    type_summary    = empty,
    courses_common  = empty,
    courses_prev    = empty,
    courses_new     = empty,
    gen_ed_summary  = empty,
    gen_ed_likely   = empty,
    gen_ed_combined = empty
  )
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
#'   \item Merge DFW rates from shared course outcome data
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
#' \code{\link{get_courses_diff}} for new/discontinued courses
#'
#' @export
seatfinder <- function (students, courses, cedar_faculty, opt) {
  
  cedar_debug("[seatfinder.R] Welcome to seatfinder!")
  
  # set opt 
  cedar_debug("[seatfinder.R] Seatfinder always uses the exclude list, excludes AOP courses, includes only active courses, and aggregates section enrollments by course_type...")
  opt$uel <- TRUE
  opt$status <- "A"
  
  # standard behavior is to use specified term param and subtract one year for comparison
  # if term param has two terms separated by comma, compare those instead
  term_param <- opt[["term"]]
  
  # extract start and end codes
  if (grepl(",", term_param)) {
    opt[["term_start"]] <- substring(term_param, 1,6)
    opt[["term_end"]] <- substring(term_param, 8,13)
  } else {
    opt[["term_end"]] <- term_param
    opt[["term_start"]] <- as.character(as.numeric(term_param) - 100) # default to one year previous to specified term
    
    # adjust term param for course filtering
    opt[["term"]] <- paste0(opt[["term_start"]],",",opt[["term_end"]])
  }
  
  # list specified and implied options when debug logging is enabled
  if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
    cedar_debug("[seatfinder.R] Effective options:\n", paste(capture.output(str(opt)), collapse = "\n"))
  }
  
  # get enrollment summary (which does opt filtering)
  cedar_debug("[seatfinder.R] Getting enrollment summary...")
  # if no grouping specified, aggregate by course/method/part_term (not individual sections)
  if (is.null(opt[["group_cols"]]) || length(opt[["group_cols"]]) == 0) {
    opt[["group_cols"]] <- c("campus","college","term","subject_course","course_title","part_term","level","gen_ed_area")
  } else {
    # ensure required columns for downstream merging are always included
    required_cols <- c("campus", "college", "term", "subject_course", "gen_ed_area")
    opt[["group_cols"]] <- unique(c(required_cols, opt[["group_cols"]]))
  }
  cedar_debug("[seatfinder.R] Using group_cols: ", paste(opt[["group_cols"]], collapse = ", "))
  enrl_summary <- get_enrl(courses,opt)

  if (is.null(enrl_summary) || nrow(enrl_summary) == 0) {
    cedar_debug("[seatfinder.R] No enrollment rows match selected filters; returning empty result.")
    return(empty_seatfinder_result())
  }


  # Add mean DFW rate for course using the shared course outcome API.
  myopt <- opt
  # Use college/dept filters already in opt rather than enumerating every course code.
  # For a college-wide search, building a list of 200+ course codes causes
  # filter_class_list to scan all of cedar_students across all historical terms
  # for each code. The college/dept/subj filters already copied from opt are
  # single-value filters that cover the same scope and are much faster. The
  # left-join with enrl_summary keeps only the courses we need.
  myopt$course <- NULL
  myopt$term <- NULL # remove term param to get dfw rates across all historical terms

  # Safety: if no scope-limiting filter is present (college/dept/subj), removing the
  # term filter would force a full scan of all of cedar_students. Fall back to term in
  # that case to bound the query.
  has_scope <- isTRUE(nzchar(myopt$course_college %||% "")) ||
               isTRUE(nzchar(myopt$dept_code %||% "")) ||
               isTRUE(nzchar(myopt$subj %||% ""))
  if (!has_scope) {
    myopt$term <- opt$term
    cedar_debug("[seatfinder.R] No college/dept/subj filter set; using term filter for grade lookup.")
  }

  cedar_debug("[seatfinder.R] Getting DFW rates for courses in enrollment summary...")
  # get_course_outcome_rates() applies the authoritative graded-data edge. Pass
  # the original table so Open Seats does not allocate a near-full copy merely
  # to remove one term before the scoped outcome filtering begins.
  grades <- get_course_outcome_rates(
    students, myopt,
    group_cols = c("campus", "college", "subject_course"),
    min_n = 1L
  )

  # Check if grades data is empty (no students matched filters)
  if (is.null(grades) || nrow(grades) == 0) {
    cedar_debug("[seatfinder.R] No grades data available for the selected filters")
    cedar_debug("[seatfinder.R] This usually means:")
    cedar_debug("[seatfinder.R]   - No historical grade data for these courses")
    cedar_debug("[seatfinder.R]   - Filters are too restrictive (no students match)")
    cedar_debug("[seatfinder.R]   - Term is in-progress with no final grades yet")
    cedar_debug("[seatfinder.R] Continuing without DFW data...")

    # Add NA dfw_pct column to enrollment summary
    enrl_summary$dfw_pct <- NA_real_

    # Continue with rest of seatfinder logic (skip grade merging)
    cedar_debug("[seatfinder.R] Skipping grade data merge")
    # Jump to line 284 logic (after grade merge) by setting grades to NULL
    grades <- NULL
  } else {
    cedar_debug("[seatfinder.R] Grades data has rows: ", nrow(grades))
    cedar_debug("[seatfinder.R] Grades data columns: ", paste(colnames(grades), collapse = ", "))
  }


  # Select columns from grades data and merge (only if grades available)
  if (!is.null(grades)) {
    # get_course_outcome_rates() returns dfw_pct column directly
    cedar_debug("[seatfinder.R] Selecting needed columns from grades data...")

    # Enforce CEDAR column names - no fallback to old naming conventions
    required_cols <- c("campus", "college", "subject_course", "dfw_pct")
    missing_cols <- setdiff(required_cols, colnames(grades))

    if (length(missing_cols) > 0) {
      cedar_debug("[seatfinder.R] ERROR: Missing required CEDAR columns in grades data: ", paste(missing_cols, collapse = ", "))
      cedar_debug("[seatfinder.R] Available columns: ", paste(colnames(grades), collapse = ", "))
      stop("Grades data must use CEDAR column names. Missing: ", paste(missing_cols, collapse = ", "))
    }

    grades <- grades %>%
      select(campus, college, subject_course, dfw_pct)

    # merge grade data with enrl data
    cedar_debug("[seatfinder.R] Merging grade data with enrollment summary...")
    cedar_debug("[seatfinder.R] enrl_summary has ", nrow(enrl_summary), " rows")
    cedar_debug("[seatfinder.R] grades has ", nrow(grades), " rows")
    cedar_debug("[seatfinder.R] enrl_summary columns: ", paste(colnames(enrl_summary), collapse = ", "))
    cedar_debug("[seatfinder.R] grades columns: ", paste(colnames(grades), collapse = ", "))

    # Diagnostic: check which courses from enrl_summary are in grades (DEBUG only)
    if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
      enrl_keys <- enrl_summary %>%
        distinct(campus, college, subject_course) %>%
        arrange(campus, college, subject_course)
      grades_keys <- grades %>%
        distinct(campus, college, subject_course) %>%
        arrange(campus, college, subject_course)
      missing_in_grades <- anti_join(enrl_keys, grades_keys, by = c("campus", "college", "subject_course"))
      if (nrow(missing_in_grades) > 0) {
        cedar_debug("[seatfinder.R] WARNING: ", nrow(missing_in_grades), " courses in enrollment have NO matching grade data:")
        cedar_debug(paste(capture.output(print(missing_in_grades)), collapse = "\n"))
      } else {
        cedar_debug("[seatfinder.R] All courses in enrollment have matching grade data")
      }
    }

    enrl_summary <- merge(enrl_summary, grades, by = c("campus","college","subject_course"), all.x = TRUE)

    # Check how many NAs we have after merge (DEBUG only)
    if (exists("cedar_log_level") && cedar_log_level == "DEBUG") {
      na_count <- sum(is.na(enrl_summary$dfw_pct))
      if (na_count > 0) {
        cedar_debug("[seatfinder.R] After merge: ", na_count, " rows have NA for dfw_pct")
        missing_dfw <- enrl_summary %>%
          filter(is.na(dfw_pct)) %>%
          distinct(campus, college, subject_course) %>%
          arrange(campus, college, subject_course)
        cedar_debug(paste(capture.output(print(missing_dfw)), collapse = "\n"))
      }
    }
  } else {
    cedar_debug("[seatfinder.R] Skipping grade merge (no grades data available)")
  }

  # Clean up columns before creating output dataframes
  cedar_debug("[seatfinder.R] Removing unnecessary columns from enrollment summary...")
  enrl_summary <- enrl_summary %>%
    ungroup() %>%
    select(-any_of(c("xl_sections", "reg_sections", "delivery_method")))

  # get only core course data for diff and intersect comparison. Include
  # course_title and part_term so topic/seminar courses with the same catalog
  # number do not create many-to-many joins across years.
  cols <- c("campus", "college", "term", "part_term", "subject_course",
            "course_title", "gen_ed_area")
  cedar_debug("[seatfinder.R] Selecting needed columns from enrollment summary for course comparisons: ", paste(cols, collapse = ", "))
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
  cedar_debug("[seatfinder.R] Getting first and second term courses...")
  course_keys <- SEATFINDER_COURSE_KEYS
  term_courses[["start"]] <- start_term_courses %>%
    ungroup() %>%
    select(all_of(course_keys)) %>%
    distinct() %>%
    arrange(campus, college, part_term, subject_course, course_title)
  term_courses[["end"]] <- end_term_courses %>%
    ungroup() %>%
    select(all_of(course_keys)) %>%
    distinct() %>%
    arrange(campus, college, part_term, subject_course, course_title)
  
  
  # find enrollment differences compared to last year across course types
  cedar_debug("[seatfinder.R] Computing course type summary with enrollment differences...")

  # Split into start and end term, then join to compare availability
  start_data <- enrl_summary %>%
    filter(term == opt[["term_start"]]) %>%
    select(all_of(c("campus", "college", "part_term", "subject_course",
                    "course_title", "gen_ed_area")),
           avail_start = all_of("avail")) %>%
    group_by(across(all_of(course_keys))) %>%
    summarize(avail_start = sum(avail_start, na.rm = TRUE), .groups = "drop")

  # Carry sections/avg_size through so the Courses tab can show them like the
  # other subtabs (the module picks the final display columns).
  end_data <- enrl_summary %>%
    filter(term == opt[["term_end"]]) %>%
    select(all_of(c("campus", "college", "term", "part_term", "subject_course",
                    "course_title", "gen_ed_area", "avail", "sections",
                    "avg_size", "enrolled", "dfw_pct")))

  course_type_summary <- end_data %>%
    left_join(start_data,
              by = c("campus", "college", "part_term", "subject_course",
                     "course_title", "gen_ed_area")) %>%
    mutate(avail_diff = avail - coalesce(avail_start, 0L)) %>%
    select(all_of(c("campus", "college", "term", "part_term", "subject_course",
                    "course_title", "avail", "sections", "avg_size",
                    "dfw_pct", "avail_diff", "enrolled", "gen_ed_area"))) %>%
    arrange(campus, college, term, part_term, subject_course) %>%
    filter(avail > 0)


  # add to output list
  courses_list[["type_summary"]] <- course_type_summary
  
  # find common courses between two terms
  courses_common <- get_courses_common(term_courses, enrl_summary)

  # to clean up list, filter for just the target term
  courses_common <- courses_common %>%
    filter(term == opt[["term_end"]], avail > 0) %>%
    arrange(campus, college, subject_course, enrl_diff_from_last_year)

  courses_list[["courses_common"]] <- courses_common


  # find difference between terms (courses offered previously, and courses offered now)
  courses_diff <- get_courses_diff(term_courses)
  courses_list[["courses_prev"]] <- merge(courses_diff[["prev"]], enrl_summary, by = course_keys)
  courses_list[["courses_new"]] <- merge(courses_diff[["new"]], enrl_summary, by = course_keys) %>%
    filter(avail > 0)


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

  # combined view: open seats first, then likely-to-open (avail==0 & enrolled==0), with flag
  # Join start_data to add avail_diff (year-over-year availability change)
  gen_ed_combined <- bind_rows(
    gen_ed_summary %>% mutate(likely = FALSE),
    gen_ed_likely  %>% mutate(likely = TRUE)
  ) %>%
    left_join(start_data, by = SEATFINDER_COURSE_KEYS) %>%
    mutate(avail_diff = avail - coalesce(avail_start, 0L)) %>%
    select(-avail_start) %>%
    arrange(gen_ed_area, likely, desc(avail), campus, college, subject_course)

  courses_list[["gen_ed_combined"]] <- gen_ed_combined
  
  cedar_debug("[seatfinder.R] All done in seatfinder! Returning course_list...")
  return (courses_list)
}
