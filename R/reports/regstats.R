#' Identify High-Enrollment Fall Sophomore Courses
#'
#' Finds fall courses with high sophomore enrollment (100+ students) that could be
#' considered for summer offerings. This helps with planning summer schedules by
#' identifying courses with strong demand from students who will be juniors in fall.
#'
#' @param students Data frame of student enrollments from cedar_students table.
#'   Must include columns: campus, college, term, term_type, student_classification,
#'   subject_course, course_title, level
#' @param courses Data frame of course sections (currently unused but kept for consistency)
#' @param opt Options list (currently unused - function uses hardcoded filters)
#'
#' @return Data frame with single column:
#'   \itemize{
#'     \item \code{subject_course} - Course identifiers with 100+ fall sophomores
#'   }
#'
#' @details
#' The function:
#' \enumerate{
#'   \item Filters for "Sophomore, 2nd Yr" classification
#'   \item Filters for fall term only
#'   \item Uses \code{get_course_demographics()} to calculate mean enrollment by course
#'   \item Returns courses with mean > 100 sophomores
#' }
#'
#' The 100-student threshold is somewhat arbitrary and could be refined based on
#' institutional capacity for summer offerings.
#'
#' @examples
#' \dontrun{
#' # Find popular sophomore fall courses
#' opt <- list()
#' high_soph_courses <- get_high_fall_sophs(cedar_students, cedar_sections, opt)
#'
#' # These courses could be summer offerings
#' print(high_soph_courses$subject_course)
#' }
#'
#' @seealso \code{\link{get_course_demographics}} for enrollment counting logic
get_high_fall_sophs <- function (students,courses,opt) {

  cedar_debug("[regstats.R] Getting fall courses with 100+ sophomores for potential summer offerings...")
  myopt <- list()
  myopt[["group_cols"]] <- c("campus", "college","term", "term_type", "student_classification", "subject_course","course_title","level")
  myopt[["classification"]] <- "Sophomore, 2nd Yr"
  myopt[["term"]] <- "fall"
  demo_out <- get_course_demographics(students,myopt)

  # 100 is a bit arbitrary; not sure how to calc would what be a better threshold
  demo_out <- demo_out %>% filter(mean > 100)

  # grab just subject_course col
  high_fall_sophs <- tibble(subject_course = unique(demo_out$subject_course))

  cedar_debug("[regstats.R] Done getting high fall sophs.")

  return(as_tibble(high_fall_sophs))
}


#' Identify Courses Taken After Enrollment Bumps
#'
#' For courses experiencing enrollment bumps (unusually high registration), identifies
#' the top 5 courses that students take next. This helps with capacity planning by
#' anticipating downstream enrollment pressure from bump courses.
#'
#' @param bumps Data frame of bump courses (output from get_reg_stats()$bumps).
#'   Must include column: subject_course
#' @param students Data frame of student enrollments from cedar_students table
#' @param courses Data frame of course sections from cedar_sections table
#' @param opt Options list passed through to \code{get_course_destinations()} for filtering
#'
#' @return Data frame with single column:
#'   \itemize{
#'     \item \code{subject_course} - Unique courses frequently taken after bump courses
#'   }
#'
#' @details
#' For each bump course, the function:
#' \enumerate{
#'   \item Calls \code{get_course_destinations()} to find courses students take next
#'   \item Ranks by average contribution to those next courses
#'   \item Selects top 5 downstream courses
#'   \item Aggregates across all bump courses and returns unique list
#' }
#'
#' This is useful for enrollment forecasting - if MATH 1430 has a bump and students
#' typically take MATH 1440 next, MATH 1440 will likely see increased demand next term.
#'
#' @examples
#' \dontrun{
#' # Get bump courses and their downstream effects
#' opt <- list(term = "202510", course_college = "AS")
#' flagged <- get_reg_stats(cedar_students, cedar_sections, opt)
#' after_bumps <- get_after_bumps(flagged$bumps, cedar_students, cedar_sections, opt)
#'
#' # These courses may need capacity increases next term
#' print(after_bumps$subject_course)
#' }
#'
#' @seealso \code{\link{get_course_destinations}} for next-course analysis, \code{\link{get_reg_stats}} for bump detection
get_after_bumps <- function (bumps, students, courses, opt) {

  bumps <- bumps$subject_course
  after_bumps <- c()

  # reset temp opt params
  myopt <- opt

  # loop through bumps to see what courses students take next, and add those to the list
  for (course in bumps) {

    # for studio testing...
    #course <- bumps[1]
    #message("now processing: ",course,"...")

    myopt[["course"]] <- course

    # get top 5 courses where students go after a bump course (than than normal enrollment)
    where_tos <- get_course_destinations(students, myopt) %>%
      arrange(desc(avg_contrib))
    next_courses <- head(where_tos,n=5)
    after_bumps <- c(after_bumps, next_courses$subject_course)

  } # end loop through bumps to find next courses

  after_bumps <- unique(tibble(subject_course = after_bumps))

  cedar_debug("[regstats.R] Done assembling after bumps.")

  return(after_bumps)
}



# Helper function to create cache filename following CEDAR patterns
create_regstats_cache_filename <- function(opt) {
  cedar_debug("[regstats.R] Creating cache filename from opt parameters...")
  
  # Extract key filtering parameters for common dashboard use
  filename_parts <- c("regstats")
  
  # Add college filter (most common)
  if (!is.null(opt[["course_college"]]) && length(opt[["course_college"]]) > 0) {
    college_part <- paste(sort(opt[["course_college"]]), collapse = "-")
    college_part <- gsub("[^A-Za-z0-9-]", "", college_part)
    filename_parts <- c(filename_parts, college_part)
  } else {
    filename_parts <- c(filename_parts, "all-colleges")
  }

  # Add dept filter
  if (!is.null(opt[["dept"]]) && length(opt[["dept"]]) > 0) {
    dept_part <- paste(sort(opt[["dept"]]), collapse = "-")
    dept_part <- gsub("[^A-Za-z0-9-]", "", dept_part)
    filename_parts <- c(filename_parts, dept_part)
  }

  # Add term filter (very common)
  if (!is.null(opt[["term"]]) && length(opt[["term"]]) > 0) {
    term_part <- paste(sort(opt[["term"]]), collapse = "-")
    filename_parts <- c(filename_parts, term_part)
  } else {
    filename_parts <- c(filename_parts, "all-terms")
  }
  
  # Add level filter if specified
  if (!is.null(opt[["level"]]) && length(opt[["level"]]) > 0) {
    level_part <- paste(sort(opt[["level"]]), collapse = "-")
    # Clean level names for filesystem safety
    level_part <- gsub("[^A-Za-z0-9-]", "", level_part)
    filename_parts <- c(filename_parts, level_part)
  }
  
  # Add campus if specified (common filter)
  if (!is.null(opt[["course_campus"]]) && length(opt[["course_campus"]]) > 0) {
    campus_part <- paste(sort(opt[["course_campus"]]), collapse = "-")
    campus_part <- gsub("[^A-Za-z0-9-]", "", campus_part)
    filename_parts <- c(filename_parts, campus_part)
  }

  # Add part-of-term filter. This MUST be in the key: pt changes the computed
  # result (it filters which enrollments count), so two requests that differ
  # only by PoT would otherwise collide on one cache file and the second would
  # silently receive the first's result — making the PoT filter appear dead.
  # Prefixed so the value ("1H") is unambiguous next to campus/level parts.
  if (!is.null(opt[["pt"]]) && length(opt[["pt"]]) > 0) {
    pt_part <- paste(sort(opt[["pt"]]), collapse = "-")
    pt_part <- gsub("[^A-Za-z0-9-]", "", pt_part)
    filename_parts <- c(filename_parts, paste0("pt", pt_part))
  }

  # Join with underscores and add extension
  cache_filename <- paste(filename_parts, collapse = "_") 
  cache_filename <- paste0(cache_filename, ".Rds")
  
  cedar_debug("[regstats.R] Generated cache filename: ", cache_filename)
  return(cache_filename)
}


# Helper function to check if cache file exists and is fresh.
# Cache is valid only if written today (after midnight) — data refreshes each morning,
# so any cache from a prior calendar day is stale regardless of how many hours ago.
load_regstats_cache <- function(opt) {
  # tryCatch is intentional (exempt from the no-fallback rule): an unreadable or
  # corrupt cache file is semantically a cache miss — NULL triggers a recompute.
  tryCatch({
    cache_dir <- file.path(cedar_data_dir, "regstats")
    cache_filename <- create_regstats_cache_filename(opt)
    cache_path <- file.path(cache_dir, cache_filename)

    if (file.exists(cache_path)) {
      cache_mtime <- file.info(cache_path)$mtime
      cache_age <- difftime(Sys.time(), cache_mtime, units = "hours")
      cache_written_today <- as.Date(cache_mtime) >= Sys.Date()

      if (cache_written_today) {
        cedar_debug("[regstats.R] Loading cached regstats: ", cache_filename,
                " (", round(cache_age, 2), " hours old)")

        cached_data <- readRDS(cache_path)

        # Add cache metadata
        cached_data[["cache_info"]] <- list(
          cached = TRUE,
          loaded_from_cache = TRUE,
          cache_filename = cache_filename,
          cache_age_hours = as.numeric(cache_age),
          generated_at = cache_mtime,
          using_standard_thresholds = TRUE
        )

        return(cached_data)
      } else {
        cedar_debug("[regstats.R] Cache from prior day, expired: ", cache_filename)
      }
    } else {
      cedar_debug("[regstats.R] No cache file found: ", cache_filename)
    }

    return(NULL)
  }, error = function(e) {
    message("[regstats.R] Error loading regstats cache: ", e$message)
    return(NULL)
  })
}





# Function to assign concern tiers based on standard deviation ranges
# Context-aware concern tier assignment
# - "high" anomalies (bumps, drops): Only flag values ABOVE normal (more than expected)
# - "low" anomalies (dips): Only flag values BELOW normal (less than expected)  
# - Critical: ±1.5 SD (urgent attention needed)
# - Moderate: ±1.0 SD (notable change)
# - Marginal: ±0.5 SD (slight change worth monitoring)
assign_concern_tier <- function(actual_value, mean_value, sd_value, anomaly_direction = "high") {
  # Calculate how many standard deviations away from mean
  deviation <- (actual_value - mean_value) / sd_value
  
  # Handle cases where sd_value is 0, NA, or deviation is NA/Inf (vectorized)
  deviation <- ifelse(is.na(deviation) | is.infinite(deviation) | is.na(sd_value) | sd_value == 0, 
                     0, deviation)
  
  # Context-specific concern tiers based on what actually matters for each anomaly type
  case_when(
    # For HIGH anomalies (bumps): Only care about values above normal
    anomaly_direction == "high" & deviation >= 1.5 ~ "critical_high",
    anomaly_direction == "high" & deviation >= 1.0 ~ "moderate_high",
    anomaly_direction == "high" & deviation >= 0.5 ~ "marginally_high",
    anomaly_direction == "high"                    ~ "normal",

    # For LOW anomalies (dips): Only care about values below normal
    anomaly_direction == "low" & deviation <= -1.5 ~ "critical_low",
    anomaly_direction == "low" & deviation <= -1.0 ~ "moderate_low",
    anomaly_direction == "low" & deviation <= -0.5 ~ "marginally_low",
    anomaly_direction == "low"                     ~ "normal",

    # For BOTH directions (drops): flag anomalies in either direction
    anomaly_direction == "both" & deviation >=  1.5 ~ "critical_high",
    anomaly_direction == "both" & deviation >=  1.0 ~ "moderate_high",
    anomaly_direction == "both" & deviation >=  0.5 ~ "marginally_high",
    anomaly_direction == "both" & deviation <= -1.5 ~ "critical_low",
    anomaly_direction == "both" & deviation <= -1.0 ~ "moderate_low",
    anomaly_direction == "both" & deviation <= -0.5 ~ "marginally_low",
    anomaly_direction == "both"                     ~ "normal",

    TRUE ~ "normal"
  )
}

# Function to create a summary of concerns by tier for dashboard display
create_tiered_summary <- function(flagged_data) {
  summary_data <- tibble()
  
  # Process each anomaly type that has concern_tier column
  anomaly_types <- c("early_drops", "late_drops", "dips", "bumps")
  
  for (type in anomaly_types) {
    if (!is.null(flagged_data[[type]]) && "concern_tier" %in% names(flagged_data[[type]])) {
      type_summary <- flagged_data[[type]] %>%
        ungroup() %>%
        count(concern_tier, name = "count") %>%
        mutate(anomaly_type = type) %>%
        select(anomaly_type, concern_tier, count)
      
      summary_data <- bind_rows(summary_data, type_summary)
    }
  }
  
  # Create a pivot table for dashboard display
  if (nrow(summary_data) > 0) {
    tier_summary <- summary_data %>%
      pivot_wider(names_from = concern_tier, values_from = count, values_fill = 0)
    
    # Ensure all expected columns exist with default values
    expected_cols <- c("critical_high", "critical_low", "moderate_high", "moderate_low", 
                      "marginally_high", "marginally_low", "normal")
    for (col in expected_cols) {
      if (!col %in% names(tier_summary)) {
        tier_summary[[col]] <- 0
      }
    }
    
    # Now safely calculate totals
    tier_summary <- tier_summary %>%
      mutate(
        total_flagged = critical_high + critical_low + moderate_high + moderate_low + 
                       marginally_high + marginally_low + normal,
        critical_total = critical_high + critical_low,
        moderate_total = moderate_high + moderate_low,
        marginal_total = marginally_high + marginally_low
      ) %>%
      arrange(desc(critical_total), desc(moderate_total), desc(marginal_total))
    
    return(tier_summary)
  } else {
    return(tibble(anomaly_type = character(), message = "No tiered anomalies found"))
  }
}

# Helper function to format concern tier labels for display
format_concern_tier <- function(tier) {
  case_when(
    tier == "critical_high" ~ "🔴 Critical High",
    tier == "critical_low" ~ "🔴 Critical Low", 
    tier == "moderate_high" ~ "🟡 Moderate High",
    tier == "moderate_low" ~ "🟡 Moderate Low",
    tier == "normal" ~ "🟢 Normal",
    TRUE ~ tier
  )
}


#' Detect Registration Anomalies and Enrollment Concerns
#'
#' Analyzes historical enrollment patterns to identify courses with unusual registration
#' behavior including bumps (higher than normal), dips (lower than normal), drops
#' (higher early/late withdrawal), squeezes (high enrollment with low capacity), and
#' waitlists. This is the primary tool for identifying enrollment concerns that need
#' administrative attention.
#'
#' @param students Data frame of student enrollments from cedar_students table.
#'   Must include columns: campus, college, term, term_type, subject_course,
#'   course_title, level, student_id, registration_status
#' @param courses Data frame of course sections from cedar_sections table.
#'   Must include columns: campus, college, term, subject_course, gen_ed_area,
#'   enrolled, waiting, avail
#' @param opt Options list for filtering and thresholds:
#'   \itemize{
#'     \item \code{term} - Term code(s) to analyze (e.g., 202510)
#'     \item \code{course} - Course identifier(s) to analyze (e.g., "MATH 1430")
#'     \item \code{course_college} - College code(s) to filter (e.g., "AS")
#'     \item \code{course_campus} - Campus code(s) to filter (e.g., "MAIN")
#'     \item \code{level} - Course level(s) to filter (e.g., "undergrad")
#'     \item \code{thresholds} - Custom threshold list (see Details)
#'   }
#'
#' @return Named list with anomaly data frames and metadata:
#'   \itemize{
#'     \item \code{early_drops} - Courses with unusually high early drops
#'     \item \code{late_drops} - Courses with unusually high late drops
#'     \item \code{dips} - Courses with unusually low enrollment
#'     \item \code{bumps} - Courses with unusually high enrollment
#'     \item \code{waits} - Courses with significant waitlists
#'     \item \code{emerging_sat} - Courses whose fill rate is significantly above their own historical baseline
#'     \item \code{chronic_sat} - Courses above the absolute fill rate ceiling for 3+ past same-type terms
#'     \item \code{all_flagged_courses} - Character vector of all flagged course identifiers
#'     \item \code{tiered_summary} - Summary of concerns by severity tier
#'     \item \code{high_fall_sophs} - Popular fall sophomore courses (non-Shiny only)
#'     \item \code{thresholds} - Thresholds used for detection
#'     \item \code{cache_info} - Cache metadata including age and parameters
#'   }
#'
#' @details
#' ## Detection Methodology
#' The function uses population standard deviation to identify statistical anomalies:
#' \itemize{
#'   \item \strong{Bumps/Drops:} Flags values >= +1 SD above mean ("high" anomalies)
#'   \item \strong{Dips:} Flags values <= -1 SD below mean ("low" anomalies)
#'   \item \strong{Concern Tiers:}
#'     \itemize{
#'       \item Critical: ±1.5 SD (immediate attention needed)
#'       \item Moderate: ±1.0 SD (notable change)
#'       \item Marginal: ±0.5 SD (minor change worth monitoring)
#'     }
#' }
#'
#' ## Default Thresholds
#' Default thresholds from \code{cedar_regstats_thresholds}:
#' \itemize{
#'   \item \code{min_impacted} = 20 (minimum student impact for bumps/dips/drops)
#'   \item \code{pct_sd} = 1 (minimum standard deviations for flagging)
#'   \item \code{chronic_fill_rate} = 0.90 (fill rate above which a course is chronically capacity-constrained)
#'   \item \code{min_wait} = 20 (minimum waitlist size)
#'   \item \code{section_proximity} = 0.3 (proximity threshold for sections)
#' }
#'
#' ## Custom Thresholds
#' Custom thresholds can be provided via \code{opt$thresholds}. If custom thresholds
#' differ from defaults, caching is bypassed to ensure fresh calculations.
#'
#' ## Caching
#' Results are cached for 24 hours when using standard thresholds. Cache files are
#' stored in \code{cedar_data_dir/regstats/} with names based on filtering parameters
#' (college, term, level, campus). Old cache files are automatically cleaned up,
#' keeping only the 20 most recent files.
#'
#' ## Anomaly Types Explained
#' \itemize{
#'   \item \strong{Early Drops:} High withdrawal before census (dr_early)
#'   \item \strong{Late Drops:} High withdrawal after census (dr_late)
#'   \item \strong{Dips:} Lower than normal registration (may indicate declining interest)
#'   \item \strong{Bumps:} Higher than normal registration (may indicate unmet demand)
#'   \item \strong{Waits:} Significant waitlists (definite capacity shortage)
#'   \item \strong{Emerging saturation:} Fill rate significantly above the course's own historical baseline (SD-based)
#'   \item \strong{Chronic saturation:} Fill rate above absolute ceiling for 3+ past same-type terms
#' }
#'
#' @examples
#' \dontrun{
#' # Analyze all Arts & Sciences courses for Fall 2025
#' opt <- list(term = "202510", course_college = "AS")
#' flagged <- get_reg_stats(cedar_students, cedar_sections, opt)
#'
#' # View courses with enrollment bumps
#' head(flagged$bumps)
#'
#' # Check waitlist concerns
#' print(flagged$waits)
#'
#' # See all flagged courses
#' print(flagged$all_flagged_courses)
#'
#' # View summary by concern tier
#' print(flagged$tiered_summary)
#'
#' # Use custom thresholds (bypasses cache)
#' custom_opt <- list(
#'   term = "202510",
#'   thresholds = list(
#'     min_impacted = 30,
#'     pct_sd = 1.5,
#'     min_wait          = 30,
#'     chronic_fill_rate = 0.85
#'   )
#' )
#' custom_flagged <- get_reg_stats(cedar_students, cedar_sections, custom_opt)
#' }
#'
#' @seealso
#' \code{\link{calc_cl_enrls}} for enrollment statistics calculation,
#' \code{\link{assign_concern_tier}} for severity classification,
#' \code{\link{create_tiered_summary}} for dashboard summaries,
#' \code{\link{get_enrl}} for current enrollment data
#'
#' @export
get_reg_stats <- function(students, courses, opt) {
  cedar_debug("[regstats.R] Welcome to get_reg_stats!")

  # cedar_cl_enrls_base is an OPTIONAL precomputed enrollment base table built in
  # global.R as a performance cache. In the running app it is always defined (the
  # table, or NULL when caching is disabled). Outside the app (tests, CLI scripts)
  # the name is absent entirely, so reference it through exists()/get() and treat
  # absence the same as the NULL "no precomputed base" case the logic below already
  # handles by recomputing via calc_cl_enrls(). This is not a silent fallback — NULL
  # is a documented, supported state, not a masked error.
  cl_enrls_base <- if (exists("cedar_cl_enrls_base", inherits = TRUE)) {
    get("cedar_cl_enrls_base", inherits = TRUE)
  } else {
    NULL
  }

  # For studio testing
  #opt <- list()
  #opt[["term"]] <- "202510"
  #opt[["course"]] <- "HIST 1160"

  default_thresholds <- cedar_regstats_thresholds

  if (is.null(default_thresholds) || length(default_thresholds) == 0) {
    message("[regstats.R] WARNING: cedar_regstats_thresholds is NULL or empty! Using fallback values...")
    default_thresholds <- list(
      min_impacted      = 20,
      pct_sd            = 1,
      chronic_fill_rate = 0.90,
      min_wait          = 20,
      section_proximity = 0.3
    )
  }

  using_custom_thresholds <- FALSE

  if (!is.null(opt[["thresholds"]])) {
    custom_thresholds <- opt[["thresholds"]]

    thresholds_differ <- FALSE
    common_names <- intersect(names(custom_thresholds), names(default_thresholds))
    for (name in common_names) {
      if (!isTRUE(all.equal(custom_thresholds[[name]], default_thresholds[[name]]))) {
        thresholds_differ <- TRUE
        break
      }
    }

    if (thresholds_differ) {
      using_custom_thresholds <- TRUE
      cedar_debug("[regstats.R] Custom thresholds differ from defaults - bypassing cache.")
      thresholds <- custom_thresholds
    } else {
      thresholds <- default_thresholds
    }
  } else {
    thresholds <- default_thresholds
  }

  # Only check cache if using standard thresholds and bypass not requested
  if (!using_custom_thresholds && !isTRUE(opt[["bypass_cache"]])) {
    cedar_debug("[regstats.R] Checking for cached regstats (standard thresholds)...")
    cached_results <- load_regstats_cache(opt)
    if (!is.null(cached_results)) {
      cedar_debug("[regstats.R] Found valid cached regstats!")
      # Patch summary onto old cache files that pre-date the summary feature.
      if (is.null(cached_results[["summary"]]) && !is.null(opt[["term"]]) &&
          !is.null(cl_enrls_base)) {
        tgt_raw <- convert_param_to_list(opt[["term"]])
        tgt     <- suppressWarnings(as.integer(tgt_raw))
        tgt     <- tgt[!is.na(tgt) & nchar(as.character(tgt)) == 6L]
        base <- cl_enrls_base
        if (!is.null(opt[["course_campus"]]) && length(opt[["course_campus"]]) > 0)
          base <- base %>% filter(campus     %in% opt[["course_campus"]])
        if (!is.null(opt[["course_college"]]) && length(opt[["course_college"]]) > 0)
          base <- base %>% filter(college    %in% opt[["course_college"]])
        if (!is.null(opt[["level"]]) && length(opt[["level"]]) > 0)
          base <- base %>% filter(level      %in% opt[["level"]])
        if (!is.null(opt[["dept"]]) && length(opt[["dept"]]) > 0)
          base <- base %>% filter(department %in% opt[["dept"]])
        curr <- base %>% filter(term %in% tgt, registered > 0)
        if (nrow(curr) > 0) {
          n_hist <- n_distinct(base$term[!base$term %in% tgt])
          cached_results[["summary"]] <- list(
            n_sections        = n_distinct(curr$subject_course),
            total_enrolled    = as.integer(sum(curr$registered)),
            expected_enrolled = as.integer(round(sum(curr$registered_mean, na.rm = TRUE))),
            avg_size          = round(mean(curr$registered), 1),
            avg_size_hist     = round(mean(curr$registered_mean, na.rm = TRUE), 1),
            n_waitlisted      = sum(curr$wl_all > 0),
            pct_waitlisted    = round(100 * mean(curr$wl_all > 0), 1),
            n_hist_terms      = n_hist,
            target_terms      = tgt,
            baseline_scope    = "exact target term excluded from historical means",
            snapshot_scope_note = paste(
              "Overview cards count active section rows and distinct courses by lower/upper level;",
              "they intentionally show both levels even when the anomaly table is level-filtered."
            )
          )
        }
      }
      return(cached_results)
    }
  } else {
    cedar_debug("[regstats.R] Skipping cache check due to custom thresholds.")
  }

  # Build myopt without term so downstream code (waits, get_high_fall_sophs) has it.
  myopt <- opt
  myopt[["term"]] <- NULL

  # Use the precomputed base table when possible — avoids re-running calc_cl_enrls()
  # on raw student rows on every request. Falls back for per-student filters (pt, im,
  # inst, classification, major) that change which students count toward enrollment
  # and therefore can't be applied post-hoc to the aggregated base.
  student_level_filters <- c("pt", "im", "inst", "classification", "major",
                              "student_campus", "student_college")
  has_student_filters <- any(vapply(student_level_filters, function(f) {
    v <- opt[[f]]
    !is.null(v) && length(v) > 0 && !identical(v, "")
  }, logical(1)))

  if (!is.null(cl_enrls_base) && !has_student_filters) {
    cedar_debug("[regstats.R] Using precomputed enrollment base table...")
    regstats <- cl_enrls_base
    if (!is.null(opt[["course_college"]]) && length(opt[["course_college"]]) > 0) {
      regstats <- regstats %>% filter(college %in% opt[["course_college"]])
    }
    if (!is.null(opt[["course_campus"]]) && length(opt[["course_campus"]]) > 0) {
      regstats <- regstats %>% filter(campus %in% opt[["course_campus"]])
    }
    if (!is.null(opt[["level"]]) && length(opt[["level"]]) > 0) {
      regstats <- regstats %>% filter(level %in% opt[["level"]])
    }
    if (!is.null(opt[["dept"]]) && length(opt[["dept"]]) > 0) {
      regstats <- regstats %>% filter(department %in% opt[["dept"]])
    }
    if (!is.null(opt[["course"]]) && !identical(opt[["course"]], "")) {
      course_list <- convert_param_to_list(opt[["course"]])
      regstats <- regstats %>% filter(subject_course %in% course_list)
    }
    # Remove lookup columns — they're not expected by downstream anomaly detection code.
    regstats <- regstats %>% select(-any_of(c("level", "department")))
    # Apply excluded_courses list so dissertations/independent-study don't skew stats.
    if (exists("excluded_courses")) {
      excl <- stringr::str_squish(toupper(excluded_courses))
      regstats <- regstats %>%
        filter(!stringr::str_squish(toupper(subject_course)) %in% excl)
    }
    cedar_debug("[regstats.R] Precomputed base filtered to ", nrow(regstats), " rows.")
  } else {
    cedar_debug("[regstats.R] Falling back to filter_class_list + calc_cl_enrls (student-level filters active)...")
    filtered_students <- filter_class_list(students, myopt)
    regstats <- calc_cl_enrls(filtered_students, by_part_term = TRUE)
  }

  # Replace biased _mean columns (which include the target term) with historical-only means.
  # Compute directly from already-aggregated regstats rows — avoids a second full calc_cl_enrls() pass.
  if (!is.null(opt[["term"]])) {
    target_terms <- convert_param_to_list(opt[["term"]])
    hist_rows <- regstats %>% filter(!term %in% target_terms)

    if (nrow(hist_rows) > 0) {
      cedar_debug("[regstats.R] Replacing means with historical-only values (excluding ", paste(target_terms, collapse = ", "), ")...")
      # Baselines are matched on part_term as well as term_type, so a 2H section's
      # enrollment is compared against the history of 2H offerings of that course,
      # not diluted by the full-term sections.
      hist_means <- hist_rows %>%
        group_by(campus, college, subject_course, term_type, part_term) %>%
        summarize(
          registered_mean = round(mean(registered), digits = 2),
          dr_early_mean   = round(mean(dr_early),   digits = 2),
          dr_late_mean    = round(mean(dr_late),     digits = 2),
          dr_all_mean     = round(mean(dr_all),      digits = 2),
          cl_total_mean   = round(mean(cl_total),    digits = 2),
          n_hist_terms    = dplyr::n(),
          .groups = "drop"
        )

      regstats <- regstats %>%
        select(-registered_mean, -dr_early_mean, -dr_late_mean, -dr_all_mean, -cl_total_mean,
               -any_of("n_hist_terms")) %>%
        left_join(hist_means, by = c("campus", "college", "subject_course", "term_type", "part_term"))

      cedar_debug("[regstats.R] Mean columns replaced with historical-only values.")
    } else {
      cedar_debug("[regstats.R] No historical terms found; using all-term means.")
    }
  }

  # find potential registration anomalies
  # use biased SD calc, since we're not really sampling from a population
  cedar_debug("[regstats.R] Finding courses of interest...")
  flagged <- list()
  std_fields <- c("campus", "college","subject_course","part_term","term","term_type","registered")
  std_group_cols <- c("campus", "college","subject_course","term_type","part_term")
  #std_arrange_cols <- c("campus","term","impacted")
  std_arrange_cols <- c("campus", "college")
  
  
  ##### EARLY DROPS - Fixed with proper population SD
  cedar_debug("[regstats.R] Finding early drops...")
  drops <- regstats %>% select(all_of(std_fields), registered_mean, any_of("n_hist_terms"), drop_early=dr_early, dr_early_mean)
  drops <- drops %>% group_by(across(all_of(std_group_cols)))
  drops <- drops %>% mutate(
    # Population SD using conversion method
    # pop_sd = sd(drop_early) / sqrt(n()/(n()-1)),
    
    # using direct calculation (equivalent result)
    pop_sd = round(sqrt(sum((drop_early - dr_early_mean)^2) / n()), digits = 2),
    
    # Calculate deviation in SD units
    sd_deviation = round((drop_early - dr_early_mean) / pop_sd, digits = 2),
    
    # Students beyond the SD boundary: raw diff minus the expected normal variance.
    # Shows only truly anomalous students above the flagging threshold.
    impacted = round(drop_early - dr_early_mean - thresholds[["pct_sd"]] * pop_sd, digits=2),

    # Concern tier assignment
    concern_tier = assign_concern_tier(drop_early, dr_early_mean, pop_sd, "both")
  )

  # min_impacted filters on the raw difference so it stays independent of pct_sd.
  drops <- drops %>% filter(
    abs(sd_deviation)              >= thresholds[["pct_sd"]] &
    abs(drop_early - dr_early_mean) > thresholds[["min_impacted"]]
  )

  drops <- drops %>% arrange(across(all_of(std_arrange_cols)))
  flagged[["early_drops"]] <- drops


##### LATE DROPS
cedar_debug("[regstats.R] Finding late drops...")
late_drops <- regstats %>% select(all_of(std_fields), registered_mean, any_of("n_hist_terms"), drop_late=dr_late, dr_late_mean)
late_drops <- late_drops %>% group_by(across(all_of(std_group_cols)))
late_drops <- late_drops %>% mutate(
  # Population SD using direct calculation (matching early drops)
  pop_sd = round(sqrt(sum((drop_late - dr_late_mean)^2) / n()), digits = 2),
  
  # Calculate deviation in SD units
  sd_deviation = round((drop_late - dr_late_mean) / pop_sd, digits = 2),
  
  # Students beyond the SD boundary: raw diff minus the expected normal variance.
  impacted = round(drop_late - dr_late_mean - thresholds[["pct_sd"]] * pop_sd, digits=2),

  # Concern tier assignment for high anomalies
  concern_tier = assign_concern_tier(drop_late, dr_late_mean, pop_sd, "both")
)

late_drops <- late_drops %>% filter(
  abs(sd_deviation)             >= thresholds[["pct_sd"]] &
  abs(drop_late - dr_late_mean)  > thresholds[["min_impacted"]]
)

flagged[["late_drops"]] <- late_drops %>% arrange(across(all_of(std_arrange_cols)))


##### DIPS
cedar_debug("[regstats.R] Finding dips...")
dips <- regstats %>% select(all_of(std_fields), registered, registered_mean, any_of("n_hist_terms"))
dips <- dips %>% group_by(across(all_of(std_group_cols)))
dips <- dips %>% mutate(
  # Population SD using direct calculation
  pop_sd = round(sqrt(sum((registered - registered_mean)^2) / n()), digits = 2),
  
  # Calculate deviation in SD units
  sd_deviation = round((registered - registered_mean) / pop_sd, digits = 2),
  
  # Students beyond the SD boundary: raw diff minus the expected normal variance.
  impacted = round(registered_mean - registered - thresholds[["pct_sd"]] * pop_sd, digits=2),

  # Concern tier assignment for low anomalies
  concern_tier = assign_concern_tier(registered, registered_mean, pop_sd, "low")
)

dips <- dips %>% filter(
  sd_deviation                    <= -thresholds[["pct_sd"]] &
  (registered_mean - registered)   >  thresholds[["min_impacted"]]
)

flagged[["dips"]] <- dips %>% arrange(across(all_of(std_arrange_cols)))



##### BUMPS
cedar_debug("[regstats.R] Finding bumps...")
bumps <- regstats %>% select(all_of(std_fields), registered, registered_mean, any_of("n_hist_terms"))
bumps <- bumps %>% group_by(across(all_of(std_group_cols)))
bumps <- bumps %>% mutate(
  # Population SD using direct calculation
  pop_sd = round(sqrt(sum((registered - registered_mean)^2) / n()), digits = 2),
  
  # Calculate deviation in SD units
  sd_deviation = round((registered - registered_mean) / pop_sd, digits = 2),

  # Students beyond the SD boundary: raw diff minus the expected normal variance.
  impacted = round(registered - registered_mean - thresholds[["pct_sd"]] * pop_sd, digits=2),

  # Concern tier assignment for high anomalies
  concern_tier = assign_concern_tier(registered, registered_mean, pop_sd, "high")
)

bumps <- bumps %>% filter(
  sd_deviation                  >= thresholds[["pct_sd"]] &
  (registered - registered_mean) >  thresholds[["min_impacted"]]
)

flagged[["bumps"]] <- bumps %>% arrange(across(all_of(std_arrange_cols)))


##### WAITS
  cedar_debug("[regstats.R] Finding waits...")
  myopt <- opt
  myopt[["uel"]] <- TRUE
  myopt[["group_cols"]] <- c("campus","college","term", "subject_course", "part_term", "gen_ed_area")
  enrls <- get_enrl(courses, myopt)
  waits <-  enrls %>% filter (waiting > thresholds[["min_wait"]]) %>% arrange (desc(waiting))
  # No rename needed - already using CEDAR column name 'term'
  flagged[["waits"]] <- waits
  
  
  ##### CAPACITY SATURATION (replaces squeeze)
  # Fill rate is measured at the CENSUS lifecycle point so the current term and the
  # historical baseline are compared like-for-like. See AGENTS.md "Enrollment
  # Measures: DESR enrolled vs Classlist registered" for the full rationale. In brief:
  #   - DESR `enrolled` is the still-registered (RE/RS/RR) headcount at the moment the
  #     file was pulled. For a completed term that snapshot is post-term, so `enrolled`
  #     is the FINAL (post-drop) count; for the upcoming term it is the live pre-census
  #     count.
  #   - Late drops (DG/DW) were present at census but gone by term end. Adding them back
  #     recovers the census headcount:  census = enrolled + dr_late.  (For the upcoming
  #     term dr_late = 0, so census == live count — consistent across terms.)
  # Basing the baseline on census fill keeps drops from making historical terms look
  # artificially unsaturated (which would inflate emerging and suppress chronic flags).
  # We expose BOTH: fill_rate (census, primary) and fill_rate_final (end-of-term).
  cedar_debug("[regstats.R] Computing fill-rate saturation (census-based)...")

  chronic_threshold      <- thresholds[["chronic_fill_rate"]] %||% 0.90
  # Fixed lower baseline for counting historical near-full terms. Decoupled from
  # chronic_threshold so the UI slider controls what's flagged now, not whether
  # historical evidence is found.
  chronic_hist_threshold <- 0.80
  min_sat_terms          <- 3L

  # Seats/capacity come from the DESR sections (crosslist-corrected by get_enrl).
  # enrls above is term-filtered (current term only); saturation baselines need the
  # full history, so call get_enrl() again without the term filter.
  sat_opt <- opt
  sat_opt[["term"]] <- NULL
  sat_opt[["uel"]] <- TRUE
  sat_opt[["group_cols"]] <- c("campus", "college", "term", "subject_course", "part_term")
  sat_enrls <- get_enrl(courses, sat_opt)
  message("[regstats.R] sat_enrls: ", nrow(sat_enrls), " rows, terms: ",
          paste(sort(unique(sat_enrls$term)), collapse = ", "))

  # Late-drop counts (DG/DW) come from the classlist `regstats` table, keyed
  # identically to sat_enrls. These are the students who were present at census but
  # dropped before term end — the difference between census and final headcount.
  late_drop_lookup <- regstats %>%
    dplyr::group_by(campus, college, subject_course, term, part_term) %>%
    dplyr::summarize(dr_late = sum(dr_late, na.rm = TRUE), .groups = "drop")

  sat_all <- sat_enrls %>%
    add_term_type_col("term") %>%
    dplyr::left_join(late_drop_lookup,
                     by = c("campus", "college", "subject_course", "term", "part_term")) %>%
    mutate(
      dr_late         = dplyr::coalesce(dr_late, 0),
      capacity        = enrolled + avail,
      # census headcount = final enrolled + students who late-dropped after census
      enrolled_census = enrolled + dr_late,
      # PRIMARY: census (initial/peak) fill — comparable across terms
      fill_rate       = if_else(capacity > 0, round(enrolled_census / capacity, 3), NA_real_),
      # SECONDARY: final (end-of-term) fill — "what we end up with" after melt
      fill_rate_final = if_else(capacity > 0, round(enrolled        / capacity, 3), NA_real_)
    ) %>%
    filter(!is.na(fill_rate), enrolled_census >= thresholds[["min_impacted"]])
  message("[regstats.R] sat_all after fill_rate filter: ", nrow(sat_all), " rows")
  message("[regstats.R] sat_all census fill_rate range: ", min(sat_all$fill_rate, na.rm=TRUE),
          " – ", max(sat_all$fill_rate, na.rm=TRUE))

  # Historical-only baseline — exclude target term to avoid inflating the mean
  target_terms_sat <- if (!is.null(opt[["term"]])) convert_param_to_list(opt[["term"]]) else character(0)
  hist_sat <- if (length(target_terms_sat) > 0) {
    sat_all %>% filter(!term %in% as.integer(target_terms_sat))
  } else {
    sat_all
  }
  message("[regstats.R] hist_sat (excluding current term): ", nrow(hist_sat), " rows, terms: ",
          paste(sort(unique(hist_sat$term)), collapse = ", "))

  # Baselines are computed on census fill so history matches the current-term point.
  fill_baselines <- hist_sat %>%
    group_by(campus, college, subject_course, term_type, part_term) %>%
    summarize(
      fill_rate_mean  = round(mean(fill_rate, na.rm = TRUE), 3),
      fill_rate_sd    = round(sd(fill_rate,   na.rm = TRUE), 3),
      n_hist_terms    = n(),
      n_chronic_terms = sum(fill_rate >= chronic_hist_threshold, na.rm = TRUE),
      .groups = "drop"
    )
  message("[regstats.R] fill_baselines: ", nrow(fill_baselines), " course×term_type combinations")
  message("[regstats.R] n_hist_terms distribution: ",
          paste(names(table(fill_baselines$n_hist_terms)),
                table(fill_baselines$n_hist_terms), sep="=", collapse=", "))

  sat <- sat_all %>%
    left_join(fill_baselines, by = c("campus", "college", "subject_course", "term_type", "part_term")) %>%
    mutate(
      fill_rate_delta = round(fill_rate - fill_rate_mean, 3),
      sd_above_mean   = if_else(
        !is.na(fill_rate_sd) & fill_rate_sd > 0,
        round((fill_rate - fill_rate_mean) / fill_rate_sd, 2),
        NA_real_
      )
    )

  # Focus diagnostics on the current term rows
  sat_current <- sat %>% filter(term %in% as.integer(target_terms_sat))
  message("[regstats.R] sat rows for current term: ", nrow(sat_current))
  message("[regstats.R]   fill_rate >= chronic_threshold (",chronic_threshold,"): ",
          sum(sat_current$fill_rate >= chronic_threshold, na.rm=TRUE))
  message("[regstats.R]   n_chronic_terms >= ",min_sat_terms,": ",
          sum(!is.na(sat_current$n_chronic_terms) & sat_current$n_chronic_terms >= min_sat_terms, na.rm=TRUE))
  message("[regstats.R]   n_hist_terms >= 2: ",
          sum(!is.na(sat_current$n_hist_terms) & sat_current$n_hist_terms >= 2L, na.rm=TRUE))
  message("[regstats.R]   sd_above_mean >= pct_sd (",thresholds[["pct_sd"]],"): ",
          sum(!is.na(sat_current$sd_above_mean) & sat_current$sd_above_mean >= thresholds[["pct_sd"]], na.rm=TRUE))

  # EMERGING: current census fill significantly above course's own historical baseline
  emerging_sat <- sat %>%
    filter(
      !is.na(fill_rate_mean),
      n_hist_terms >= 2L,
      !is.na(sd_above_mean),
      sd_above_mean >= thresholds[["pct_sd"]]
    ) %>%
    arrange(desc(sd_above_mean))

  # CHRONIC: at/above absolute census fill ceiling for N+ past same-type terms, and currently above it
  chronic_sat <- sat %>%
    filter(
      fill_rate >= chronic_threshold,
      !is.na(n_chronic_terms),
      n_chronic_terms >= min_sat_terms
    ) %>%
    arrange(desc(fill_rate))
  message("[regstats.R] emerging_sat (all terms, pre-term-filter): ", nrow(emerging_sat))
  message("[regstats.R] chronic_sat  (all terms, pre-term-filter): ", nrow(chronic_sat))

  flagged[["emerging_sat"]] <- emerging_sat
  flagged[["chronic_sat"]]  <- chronic_sat
  flagged[["sat"]]          <- dplyr::bind_rows(emerging_sat, chronic_sat) %>%
    dplyr::distinct() %>%
    dplyr::arrange(dplyr::desc(fill_rate))
  
  
  # filter report data for supplied term
  if (!is.null(opt[["term"]])) {
    cedar_debug("[regstats.R] Filtering flagged data by term...")
    flagged <- lapply(flagged, function(x) filter_by_term(x, opt[["term"]], "term"))
  }

  # Attach course_title to all anomaly tables via join from courses (cedar_sections).
  title_lookup <- courses %>%
    dplyr::distinct(campus, college, subject_course, term, course_title)
  for (nm in c("bumps", "dips", "early_drops", "late_drops", "waits", "sat")) {
    df <- flagged[[nm]]
    if (!is.null(df) && nrow(df) > 0 && all(c("campus","college","subject_course","term") %in% names(df))) {
      flagged[[nm]] <- dplyr::left_join(df, title_lookup,
                                        by = c("campus","college","subject_course","term"))
    }
  }

  # Attach each flagged saturation course's own census-fill history (same term type)
  # for the Fill Trend sparkline. Built from sat_all (all terms) so the current-term
  # rows carry their longitudinal series. fill_trend_slope = linear pts-per-term over
  # the series (needs 3+ points); positive = getting more saturated over time.
  if (!is.null(flagged[["sat"]]) && nrow(flagged[["sat"]]) > 0) {
    # Provide the course's full same-term-type census-fill series (ordered by term); the
    # UI marks the target term in place and derives the trend(s) from it. For a
    # retrospective run this deliberately keeps terms after the target — post-facto
    # context is the point of looking back, not distortion. For the common next-term run
    # the target is the latest term, so it sits at the end of the series.
    fill_history <- sat_all %>%
      dplyr::arrange(campus, college, subject_course, part_term, term_type, term) %>%
      dplyr::group_by(campus, college, subject_course, part_term, term_type) %>%
      dplyr::summarize(
        fill_hist       = list(fill_rate),
        fill_hist_terms = list(term),
        .groups = "drop"
      )
    # fill_history is unique per course×term_type (grouped summary), so this is
    # many-to-one: several flagged rows may share one history, never the reverse.
    flagged[["sat"]] <- dplyr::left_join(
      flagged[["sat"]], fill_history,
      by = c("campus", "college", "subject_course", "part_term", "term_type"),
      relationship = "many-to-one"
    )
  }

  # Attach each anomaly table's flagged-metric history (same term type + part of term) so
  # the module can draw a Trend sparkline — same mechanism as saturation's fill history.
  # Bumps/dips trend on enrollment; early/late drops trend on their own drop counts. This
  # is what lets a user tell a one-term blip from a developing trend.
  trend_metric <- c(bumps = "registered", dips = "registered",
                    early_drops = "dr_early", late_drops = "dr_late")
  for (nm in names(trend_metric)) {
    df <- flagged[[nm]]
    metric <- trend_metric[[nm]]
    if (is.null(df) || nrow(df) == 0 || !metric %in% names(regstats)) next
    metric_history <- regstats %>%
      dplyr::arrange(campus, college, subject_course, part_term, term_type, term) %>%
      dplyr::group_by(campus, college, subject_course, part_term, term_type) %>%
      dplyr::summarize(
        trend_hist  = list(.data[[metric]]),
        trend_terms = list(term),
        .groups = "drop"
      )
    flagged[[nm]] <- dplyr::left_join(
      df, metric_history,
      by = c("campus", "college", "subject_course", "part_term", "term_type"),
      relationship = "many-to-one"
    )
  }

  ##### COURSES AFTER BUMPS (if not from shiny)
  if (as.logical(Sys.getenv("shiny")) == FALSE) {
    # message("finding courses students take after bumps...")
    # disabling until we have a better way of using these...
    #flagged[["courses_after_bumps"]] <- get_after_bumps(flagged[["bumps"]], students, courses, opt)
  }

  # gather subject_course col into separate list
  cedar_debug("[regstats.R] Gathering flagged courses...")
  flagged_courses <- c()
  for (flag in flagged) {
    if (!is.null(flag$subject_course)) {
      flagged_courses <- c(flagged_courses, as.character(flag$subject_course))
    }
  }

  cedar_debug("[regstats.R] Filtered flagged_courses has ", length(flagged_courses), " courses.")

  flagged[["all_flagged_courses"]] <- sort(unique(flagged_courses))

  # save thresholds for adding to report
  flagged[["thresholds"]] <- thresholds 
  
  # Create tiered summary for dashboard
  flagged[["tiered_summary"]] <- create_tiered_summary(flagged)
  
  # keep separate from flagged courses since we don't need to forecast for this all the time
  if (as.logical(Sys.getenv("shiny")) == FALSE) {
    flagged[["high_fall_sophs"]] <- get_high_fall_sophs(students, courses, myopt)
  }

  if (!using_custom_thresholds) {

# Save flagged data to cache following CEDAR patterns
  # tryCatch is intentional (exempt from the no-fallback rule): a failed cache
  # write must not discard the successfully computed results being returned.
  tryCatch({
    # Create cache directory if it doesn't exist
    cache_dir <- file.path(cedar_data_dir, "regstats")
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    
    # Generate cache filename based on opt parameters
    cache_filename <- create_regstats_cache_filename(opt)
    cache_path <- file.path(cache_dir, cache_filename)
    
    # Add metadata to flagged object
    flagged[["cache_info"]] <- list(
      cached = FALSE,
      loaded_from_cache = FALSE,
      cache_filename = cache_filename,
      generated_at = Sys.time(),
      opt_params = opt,
      cedar_version = if (exists("cedar_version")) cedar_version else "unknown",
      using_standard_thresholds = TRUE
    )
    
    cedar_debug("[regstats.R] Saving flagged data to: ", cache_filename)
    saveRDS(flagged, cache_path)

    # Clean up old cache files (keep last 20 for common queries)
    existing_files <- list.files(cache_dir, pattern = "^regstats.*\\.Rds$", full.names = TRUE)
    if (length(existing_files) > 20) {
      file_info <- file.info(existing_files)
      old_files <- existing_files[order(file_info$mtime)[1:(length(existing_files) - 20)]]
      unlink(old_files)
      cedar_debug("[regstats.R] Cleaned up ", length(old_files), " old cache files")
    }

  }, error = function(e) {
    message("[regstats.R] Warning: Failed to save regstats cache: ", e$message)
  })

  } else {
    cedar_debug("[regstats.R] Not caching results due to custom thresholds.")
    # Still add metadata for transparency
    flagged[["cache_info"]] <- list(
      cached = FALSE,
      loaded_from_cache = FALSE,
      cache_filename = NULL,
      generated_at = Sys.time(),
      opt_params = opt,
      using_standard_thresholds = FALSE,
      custom_thresholds = thresholds,
      reason_no_cache = "Custom thresholds used"
    )
  }  

  # Snapshot summary: aggregate current-term stats for the registration overview cards.
  # Only computed when a specific numeric term code is selected (not term-type strings
  # like "fall"); convert_param_to_list can return those too so filter them out.
  if (!is.null(opt[["term"]])) {
    tgt_raw <- convert_param_to_list(opt[["term"]])
    tgt     <- suppressWarnings(as.integer(tgt_raw))
    tgt     <- tgt[!is.na(tgt) & nchar(as.character(tgt)) == 6L]
    curr <- regstats %>% filter(term %in% tgt, registered > 0)
    if (nrow(curr) > 0) {
      n_hist <- n_distinct(regstats$term[!regstats$term %in% tgt])

      # Section-level stats for snapshot cards — no level filter so we can split by level.
      snap_secs <- courses %>% dplyr::filter(term %in% tgt)
      if ("status" %in% names(snap_secs))
        snap_secs <- snap_secs %>% dplyr::filter(status == "A")
      if (!is.null(opt$course_campus)  && length(opt$course_campus)  > 0)
        snap_secs <- snap_secs %>% dplyr::filter(campus     %in% opt$course_campus)
      if (!is.null(opt$course_college) && length(opt$course_college) > 0)
        snap_secs <- snap_secs %>% dplyr::filter(college    %in% opt$course_college)
      if (!is.null(opt$dept)           && length(opt$dept)           > 0)
        snap_secs <- snap_secs %>% dplyr::filter(department %in% opt$dept)
      if (exists("excluded_courses")) {
        excl <- stringr::str_squish(toupper(excluded_courses))
        snap_secs <- snap_secs %>%
          dplyr::filter(!stringr::str_squish(toupper(subject_course)) %in% excl)
      }

      make_level_snap <- function(secs) {
        if (is.null(secs) || nrow(secs) == 0) return(NULL)
        has_credits <- "credits_min" %in% names(secs) && any(!is.na(secs$credits_min))
        ch <- if (has_credits)
          as.integer(round(sum(secs$enrolled * secs$credits_min, na.rm = TRUE)))
        else NA_integer_
        list(
          n_sections         = nrow(secs),
          n_courses          = dplyr::n_distinct(secs$subject_course),
          total_enrolled     = as.integer(sum(secs$enrolled, na.rm = TRUE)),
          avg_size           = round(mean(secs$enrolled, na.rm = TRUE), 1),
          total_credit_hours = ch
        )
      }

      # Historical trend for sparklines: all same-type terms, all levels
      tgt_types     <- regstats %>% dplyr::filter(term %in% tgt) %>% dplyr::pull(term_type) %>% unique()
      trend_by_term <- regstats %>%
        dplyr::filter(term_type %in% tgt_types) %>%
        dplyr::group_by(term) %>%
        dplyr::summarize(
          total_enrolled = sum(registered),
          avg_size       = round(mean(registered), 1),
          .groups = "drop"
        ) %>%
        dplyr::arrange(term) %>%
        dplyr::mutate(term = as.character(term))

      # Add credit hours trend from sections data (same scope filters as snap_secs)
      if ("credits_min" %in% names(courses) && any(!is.na(courses$credits_min))) {
        ch_trend <- courses %>% dplyr::filter(term_type %in% tgt_types)
        if (!is.null(opt$course_campus)  && length(opt$course_campus)  > 0)
          ch_trend <- ch_trend %>% dplyr::filter(campus     %in% opt$course_campus)
        if (!is.null(opt$course_college) && length(opt$course_college) > 0)
          ch_trend <- ch_trend %>% dplyr::filter(college    %in% opt$course_college)
        if (!is.null(opt$dept)           && length(opt$dept)           > 0)
          ch_trend <- ch_trend %>% dplyr::filter(department %in% opt$dept)
        if (exists("excluded_courses")) {
          excl <- stringr::str_squish(toupper(excluded_courses))
          ch_trend <- ch_trend %>%
            dplyr::filter(!stringr::str_squish(toupper(subject_course)) %in% excl)
        }
        ch_by_term <- ch_trend %>%
          dplyr::group_by(term) %>%
          dplyr::summarize(
            total_credit_hours = as.integer(round(sum(enrolled * credits_min, na.rm = TRUE))),
            .groups = "drop"
          ) %>%
          dplyr::mutate(term = as.character(term))
        trend_by_term <- trend_by_term %>% dplyr::left_join(ch_by_term, by = "term")
      }

      flagged[["summary"]] <- list(
        n_waitlisted      = sum(curr$wl_all > 0),
        pct_waitlisted    = round(100 * mean(curr$wl_all > 0), 1),
        n_hist_terms      = n_hist,
        target_terms      = tgt,
        trend_by_term     = trend_by_term,
        baseline_scope    = "exact target term excluded from historical means",
        snapshot_scope_note = paste(
          "Overview cards count active section rows and distinct courses by lower/upper level;",
          "they intentionally show both levels even when the anomaly table is level-filtered."
        ),
        lower             = make_level_snap(snap_secs %>% dplyr::filter(level == "lower")),
        upper             = make_level_snap(snap_secs %>% dplyr::filter(level == "upper"))
      )
    }
  }

  cedar_debug("[regstats.R] Returning flagged courses...")
  return(flagged)
}



#' Generate Registration Statistics Report
#'
#' Creates a comprehensive PDF/HTML report of registration anomalies and enrollment
#' concerns by calling \code{get_reg_stats()} and rendering the regstats Rmd template.
#'
#' @param students Data frame of student enrollments from cedar_students table
#' @param courses Data frame of course sections from cedar_sections table
#' @param opt Options list passed through to \code{get_reg_stats()} and report rendering:
#'   \itemize{
#'     \item \code{term} - Term code(s) to analyze
#'     \item \code{course_college} - College code(s) to filter
#'     \item \code{arrange} - Optional column name for custom sorting
#'     \item Other filtering options (see \code{\link{get_reg_stats}})
#'   }
#'
#' @return NULL (side effect: renders report to output directory)
#'
#' @details
#' The function:
#' \enumerate{
#'   \item Calls \code{get_reg_stats()} to detect anomalies
#'   \item Optionally sorts results by \code{opt$arrange} column
#'   \item Packages data into format expected by Rmd template
#'   \item Calls \code{create_report()} to render regstats-report.Rmd
#'   \item Saves output to \code{cedar_output_dir/regstats-reports/}
#' }
#'
#' Report includes:
#' \itemize{
#'   \item Summary of flagged courses by anomaly type
#'   \item Detailed tables for bumps, dips, drops, waits, squeezes
#'   \item Tiered concern summaries (critical/moderate/marginal)
#'   \item Thresholds used for detection
#' }
#'
#' @examples
#' \dontrun{
#' # Generate report for Fall 2025 Arts & Sciences
#' opt <- list(term = "202510", course_college = "AS")
#' create_regstat_report(cedar_students, cedar_sections, opt)
#'
#' # Report saved to: cedar_output_dir/regstats-reports/output.pdf
#' }
#'
#' @seealso
#' \code{\link{get_reg_stats}} for anomaly detection,
#' \code{\link{create_report}} for Rmd rendering
#'
#' @export
create_regstat_report <- function(students,courses,opt) {
  cedar_debug("[regstats.R] Welcome to create_regstat_report!")
  
  # get flagged courses
  flagged <- get_reg_stats(students,courses,opt)
  
  # if arrange param set, use it
  if (!is.null(opt[["arrange"]])) {
    arrange_col <- opt[["arrange"]]
    flagged <- flagged %>%  arrange(get({{arrange_col}}) )
  }
  
  # payload
  d_params <- list("opt" = opt,
                    "tables" = list(
                      "flagged" = flagged
                    )
                  )

  # message("[regstats.R] Setting filename based on opt params...")
  # good_opts <- c("course_campus","course_college","course","term","pt","im")
  # output_filename <- "regstats"
  
  # # loop through opt params to build output filename
  # for (i in 1:length(opt)) {
  #   message(names(opt[i]))
  #   if (names(opt[i]) %in% good_opts) {
  #     output_filename <- paste0(output_filename,"-",opt[i])
  #   }
  # }
  # message("output_filename is now: ",output_filename)
  # d_params$output_filename <- output_filename

  d_params$output_filename <- "output"
  d_params$rmd_file <- file.path(cedar_base_dir, "Rmd", "regstats-report.Rmd")
  d_params$output_dir_base <- file.path(cedar_output_dir, "regstats-reports")

  cedar_debug("[regstats.R] Calling create_report to render regstats report...")
  create_report(opt,d_params)

  cedar_debug("[regstats.R] All done creating regstats report!")
}


# ---------------------------------------------------------------------------
# Next Term Signals
# ---------------------------------------------------------------------------

#' Compute historical enrollment flows from source courses to destination courses
#'
#' For each source course, finds which courses students historically took in the
#' following non-summer term. Uses a single vectorized join across all source
#' courses so cost is independent of the number of inputs.
#'
#' @param source_courses Character vector of subject_course values to analyze.
#' @param students       Cedar students data frame (must include student_id,
#'   term, subject_course columns).
#' @return Tibble with columns including campus, source_course, dest_course,
#'   term, next_term, and n_students.
#'   Returns an empty tibble if no flows are found.
get_downstream_course_flows <- function(source_courses, students, campus = NULL) {
  # Fast path: filter the pre-computed global summary table (set in global.R).
  # This avoids a raw student join entirely — just a filter on a small table.
  if (exists("cedar_course_flows") && !is.null(cedar_course_flows)) {
    flows <- cedar_course_flows %>% filter(source_course %in% source_courses)
    if (!is.null(campus) && length(campus) > 0 && "campus" %in% names(flows)) {
      flows <- flows %>% filter(campus %in% .env$campus)
    }
    return(flows)
  }

  get_next_course_pairs(
    students,
    opt = list(summer = FALSE, campus = campus),
    source_courses = source_courses
  )
}


#' Compute next-term downstream signals from a regstats flagged list
#'
#' Answers "which courses are likely to face extra demand next term?" by
#' identifying courses downstream of enrollment bumps (students tend to take
#' them after bump courses) and courses with drop anomalies (unmet demand —
#' students who dropped will try to re-enroll).
#'
#' @param flagged  Named list returned by get_reg_stats().
#' @param students Cedar students data frame passed to get_downstream_course_flows().
#' @return Named list:
#'   downstream — tibble(dest_course, reason, top_feeders); one row per
#'                (dest_course, reason) pair. reason is "Bump" or "Drop".
#'                top_feeders lists up to 3 upstream courses (Bump) or drop
#'                signal types (Drop). Empty tibble if no signals or no flow data.
get_next_term_signals <- function(flagged, students, campus = NULL) {

  flow_terms <- if (exists("cedar_course_flows") && !is.null(cedar_course_flows)) {
    flows_for_terms <- cedar_course_flows
    if (!is.null(campus) && length(campus) > 0 && "campus" %in% names(flows_for_terms)) {
      flows_for_terms <- flows_for_terms %>% filter(campus %in% .env$campus)
    }
    flows_for_terms$term
  } else {
    cedar_debug("[regstats.R] cedar_course_flows not available — computing downstream signals from source-course rows.")
    term_students <- students
    if (!is.null(campus) && length(campus) > 0 && "campus" %in% names(term_students)) {
      term_students <- term_students %>% filter(campus %in% .env$campus)
    }
    term_students$term
  }

  all_main_terms <- sort(unique(flow_terms[flow_terms %% 100L != 60L]))
  if (length(all_main_terms) == 0L) return(list(downstream = tibble()))
  recent_terms <- tail(all_main_terms, 2L)

  .win_avg <- function(vals, terms) {
    v <- vals[terms %in% recent_terms]
    if (length(v) == 0L) NA_real_ else mean(v)
  }

  # ---- BUMP rows: courses downstream of bump courses -------------------------
  # Rank by recent_avg (absolute student flow volume), not a normalized ratio.
  # Normalized scores inflate small-enrollment courses — dividing by a tiny
  # registered_mean makes 2-3 students look like a large contribution.
  # Absolute flow naturally demotes low-enrollment feeders.
  # Top 3 feeders per dest by recent_avg → top 30 dest_courses by total flow.
  bump_rows <- tibble()
  if (!is.null(flagged$bumps) && nrow(flagged$bumps) > 0L) {
    bump_sources <- unique(flagged$bumps$subject_course)
    flows <- get_downstream_course_flows(bump_sources, students, campus = campus)
    if (nrow(flows) > 0L) {
      pair_avgs <- flows %>%
        filter(term %in% all_main_terms) %>%
        group_by(campus, source_course, dest_course) %>%
        summarize(recent_avg = .win_avg(n_students, term), .groups = "drop") %>%
        filter(!is.na(recent_avg), recent_avg >= 2)

      bump_rows <- pair_avgs %>%
        group_by(campus, dest_course) %>%
        slice_max(order_by = recent_avg, n = 3L, with_ties = FALSE) %>%
        summarize(
          reason      = "Bump",
          top_feeders = paste(source_course, collapse = ", "),
          .rank_key   = sum(recent_avg),
          .groups     = "drop"
        ) %>%
        slice_max(order_by = .rank_key, n = 30L, with_ties = FALSE) %>%
        arrange(desc(.rank_key)) %>%
        select(-.rank_key)
    }
  }

  # ---- DROP rows: flagged courses with drops have unmet demand ---------------
  # The flagged course itself is the downstream concern — dropped students may
  # re-enroll next term. Top 20 by max impacted across drop types per course.
  drop_parts <- list()
  if (!is.null(flagged$early_drops) && nrow(flagged$early_drops) > 0L &&
      "registered_mean" %in% names(flagged$early_drops))
    drop_parts[["early"]] <- flagged$early_drops %>%
      filter(grepl("_high$", concern_tier), impacted > 0) %>%
      group_by(dplyr::across(dplyr::any_of(c("campus", "subject_course")))) %>%
      slice_max(order_by = impacted, n = 1L, with_ties = FALSE) %>%
      ungroup() %>%
      select(any_of(c("campus", "subject_course")), impacted) %>%
      mutate(drop_type = "early drops")
  if (!is.null(flagged$late_drops) && nrow(flagged$late_drops) > 0L &&
      "registered_mean" %in% names(flagged$late_drops))
    drop_parts[["late"]] <- flagged$late_drops %>%
      filter(grepl("_high$", concern_tier), impacted > 0) %>%
      group_by(dplyr::across(dplyr::any_of(c("campus", "subject_course")))) %>%
      slice_max(order_by = impacted, n = 1L, with_ties = FALSE) %>%
      ungroup() %>%
      select(any_of(c("campus", "subject_course")), impacted) %>%
      mutate(drop_type = "late drops")

  drop_rows <- tibble()
  if (length(drop_parts) > 0L) {
    drop_rows <- bind_rows(drop_parts) %>%
      group_by(dplyr::across(dplyr::any_of("campus")), dest_course = subject_course) %>%
      summarize(
        reason      = "Drop",
        top_feeders = paste(sort(unique(drop_type)), collapse = ", "),
        .rank_key   = max(impacted),
        .groups     = "drop"
      ) %>%
      slice_max(order_by = .rank_key, n = 20L, with_ties = FALSE) %>%
      arrange(desc(.rank_key)) %>%
      select(-.rank_key)
  }

  downstream <- bind_rows(bump_rows, drop_rows) %>%
    arrange(reason, dest_course)

  list(downstream = downstream)
}


#' Filter a downstream signals table to destinations within a department
#'
#' Given a downstream signals data frame (source_course → dest_course pairs)
#' and a vector of department codes, keeps only rows whose dest_course subject
#' prefix matches a subject taught by one of those departments.
#'
#' Returns the full data frame unchanged when dept is empty (no dept filter
#' selected), so callers can always apply this unconditionally.
#'
#' Reusable across any tab or report that displays downstream registration
#' signals — regstats UI summary, regstats datatable, future comparison views.
#'
#' @param downstream_df Data frame with at least a \code{dest_course} column
#'   (e.g. "HIST 480"). May be empty; function returns it unchanged in that case.
#' @param dept Character vector of department codes to filter to (e.g.
#'   \code{c("HIST", "AMST")}). Pass \code{character(0)} or \code{NULL} to
#'   skip filtering and return all rows.
#' @param sections Data frame of course sections (cedar_sections). Must include
#'   \code{department}, \code{subject_course}, and \code{status} columns.
#'   Used to derive the set of subject prefixes taught by \code{dept}.
#'
#' @return Filtered (or unchanged) data frame with the same columns as
#'   \code{downstream_df}.
#'
#' @examples
#' # In a dept-scoped view — keep only destinations in HIST's subjects
#' downstream_df <- filter_downstream_by_dept(signals$downstream, c("HIST"), cedar_sections)
#'
#' # College-wide view -- pass NULL/empty to return everything
#' downstream_df <- filter_downstream_by_dept(signals$downstream, character(0), cedar_sections)
filter_downstream_by_dept <- function(downstream_df, dept, sections) {
  if (is.null(downstream_df) || nrow(downstream_df) == 0) return(downstream_df)
  if (length(dept) == 0) return(downstream_df)

  dept_subj <- sections %>%
    filter(department %in% dept, status == "A") %>%
    pull(subject_course) %>%
    sub(" .*", "", .) %>%
    unique()

  downstream_df %>%
    filter(sub(" .*", "", dest_course) %in% dept_subj)
}
