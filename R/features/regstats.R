#' Identify High-Enrollment Fall Sophomore Courses
#'
#' Finds fall courses with high sophomore enrollment (100+ students) that could be
#' considered for summer offerings. This helps with planning summer schedules by
#' identifying courses with strong demand from students who will be juniors in fall.
#'
#' A standalone screen, not part of `get_reg_stats()`'s report: nothing on the
#' page reads it.
#'
#' @param students Data frame of student enrollments from cedar_registrations table.
#'   Must include columns: campus, college, term, term_type,
#'   subject_course, course_title, level
#' @param student_terms The `cedar_student_terms` table: the classification
#'   that selects sophomores is the student-term's, never the class list's,
#'   which a late pull stamps a step ahead (ISSUES.md I47).
#' @param course_terms `cedar_course_terms`, the course enrollment the shares
#'   are taken against.
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
#' high_soph_courses <- get_high_fall_sophs(cedar_registrations, cedar_student_terms,
#'                                          cedar_course_terms, opt)
#'
#' # These courses could be summer offerings
#' print(high_soph_courses$subject_course)
#' }
#'
#' @seealso \code{\link{get_course_demographics}} for enrollment counting logic
get_high_fall_sophs <- function(students, student_terms, course_terms, opt = list()) {

  cedar_debug("[regstats.R] Getting fall courses with 100+ sophomores for potential summer offerings...")
  myopt <- list()
  # Sophomores are selected by the classification filter, which
  # get_course_demographics() reads off the student-term table; the count needs
  # no grouping by classification.
  myopt[["group_cols"]] <- c("campus", "college","term", "term_type", "subject_course","course_title","level")
  myopt[["classification"]] <- "Sophomore, 2nd Yr"
  myopt[["term"]] <- "fall"
  demo_out <- get_course_demographics(students, student_terms, course_terms, myopt)

  # 100 is a bit arbitrary; not sure how to calc would what be a better threshold
  demo_out <- demo_out %>% filter(mean > 100)

  # grab just subject_course col
  high_fall_sophs <- tibble(subject_course = unique(demo_out$subject_course))

  cedar_debug("[regstats.R] Done getting high fall sophs.")

  return(as_tibble(high_fall_sophs))
}


# Helper function to create cache filename following CEDAR patterns
create_regstats_cache_filename <- function(opt) {
  cedar_debug("[regstats.R] Creating cache filename from opt parameters...")
  
  # Extract key filtering parameters for common dashboard use
  filename_parts <- c("regstats", paste0("v", cedar_regstats_cache_version))

  threshold_profile <- opt[["threshold_profile"]] %||% "standard"
  if (!identical(threshold_profile, "standard")) {
    profile_part <- gsub("[^A-Za-z0-9-]", "", threshold_profile)
    filename_parts <- c(filename_parts, paste0("profile-", profile_part))
  }
  
  # Add college filter (most common)
  if (!is.null(opt[["course_college"]]) && length(opt[["course_college"]]) > 0) {
    college_part <- paste(sort(opt[["course_college"]]), collapse = "-")
    college_part <- gsub("[^A-Za-z0-9-]", "", college_part)
    filename_parts <- c(filename_parts, college_part)
  } else {
    filename_parts <- c(filename_parts, "all-colleges")
  }

  # Add dept filter
  if (!is.null(opt[["dept_code"]]) && length(opt[["dept_code"]]) > 0) {
    dept_part <- paste(sort(opt[["dept_code"]]), collapse = "-")
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
#
# `code_renames` is the renames the loaded class list carries
# (course_code_renames()); a payload counted over others — saved before a
# code_history.csv row was confirmed — is a miss, never a stale hit.
load_regstats_cache <- function(opt, code_renames = character(0)) {
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
        if (!identical(as.character(cached_data[["code_renames"]]), as.character(code_renames))) {
          cedar_debug("[regstats.R] Cache was counted over other course codes, expired: ", cache_filename)
          return(NULL)
        }

        # Add cache metadata
        cached_data[["cache_info"]] <- list(
          cached = TRUE,
          loaded_from_cache = TRUE,
          cache_filename = cache_filename,
          cache_age_hours = as.numeric(cache_age),
          generated_at = cache_mtime,
          using_standard_thresholds = identical(opt[["threshold_profile"]] %||% "standard", "standard"),
          threshold_profile = opt[["threshold_profile"]] %||% "standard"
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

get_dashboard_regstats_thresholds <- function(base_thresholds = NULL) {
  if (is.null(base_thresholds) || length(base_thresholds) == 0) {
    base_thresholds <- list(
      min_impacted      = 20,
      pct_sd            = 1,
      chronic_fill_rate = CEDAR_NEAR_FULL_FILL,
      min_wait          = 20,
      min_sat_terms     = 3,
      section_proximity = 0.3
    )
  }

  utils::modifyList(base_thresholds, list(
    min_impacted      = 5,
    pct_sd            = 0.5,
    chronic_fill_rate = 0.85,
    min_wait          = 2,
    min_sat_terms     = 2
  ))
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

# Scope/coverage metadata for the UI and saved results. Counts describe
# course-term comparison groups, not students or statistically tested hypotheses.
get_regstats_baseline_info <- function(enrollment, saturation, opt,
                                       saturation_coverage = NULL) {
  current <- function(df) {
    if (is.null(opt$term)) df else filter_by_term(df, opt$term, "term")
  }
  enrl <- current(enrollment)
  sat <- current(saturation)
  usable <- function(sd) is.finite(sd) & sd > 0
  unscored <- c(enrollment = sum(!usable(enrl$census_enrl_sd)),
                early_drops = sum(!usable(enrl$dr_early_hist_sd)),
                late_drops = sum(!usable(enrl$dr_late_hist_sd)),
                fill = sum(!usable(sat$fill_rate_sd)))
  earlier <- enrollment %>%
    select(campus, college, subject_course, term_type, part_term, history_term = term) %>%
    semi_join(enrl %>% select(campus, college, subject_course, term_type, part_term, target_term = term),
      by = join_by(campus, college, subject_course, term_type, part_term, history_term < target_term))
  saturation_note <- if (is.null(saturation_coverage)) "" else paste0(
    " Saturation source coverage: ", saturation_coverage$matched,
    " target groups matched class-list census to DESR capacity; ",
    saturation_coverage$unmatched, " unmatched, ",
    saturation_coverage$invalid_capacity, " with unusable capacity, and ",
    saturation_coverage$below_minimum, " below Min Impacted."
  )
  list(
    scope = "strictly earlier same-season/part-of-term means and population SD",
    n_hist_terms = n_distinct(earlier$history_term),
    unscored = unscored,
    saturation_coverage = saturation_coverage,
    coverage_note = paste0(
      "Unscored SD comparisons: enrollment ", unscored[["enrollment"]],
      ", early drops ", unscored[["early_drops"]], ", late drops ", unscored[["late_drops"]],
      ", fill ", unscored[["fill"]],
      " course-term groups (fewer than two prior observations or no historical variation).",
      saturation_note)
  )
}


# Build display-only course titles without changing the Regstats reporting grain.
# Several sections can share one course/term/campus/college/part-of-term group and
# carry different titles. Choose the most frequent nonblank title; resolve ties
# alphabetically so the result is stable across input order.
build_regstats_title_lookup <- function(courses) {
  keys <- c("campus", "college", "subject_course", "term", "part_term")
  required <- c(keys, "course_title")
  missing <- setdiff(required, names(courses))
  if (length(missing) > 0L) {
    stop("Regstats title lookup is missing required columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  courses %>%
    dplyr::transmute(
      dplyr::across(dplyr::all_of(keys)),
      course_title = dplyr::na_if(trimws(as.character(course_title)), "")
    ) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(keys, "course_title"))),
                    .drop = FALSE) %>%
    dplyr::summarize(title_rows = dplyr::n(), .groups = "drop") %>%
    dplyr::arrange(
      dplyr::across(dplyr::all_of(keys)),
      is.na(course_title),
      dplyr::desc(title_rows),
      course_title
    ) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) %>%
    dplyr::slice_head(n = 1L) %>%
    dplyr::ungroup() %>%
    dplyr::select(dplyr::all_of(keys), course_title)
}


attach_regstats_titles <- function(flagged, courses) {
  keys <- c("campus", "college", "subject_course", "term", "part_term")
  title_tables <- lapply(c("bumps", "dips", "early_drops", "late_drops", "sat"),
    function(nm) {
      df <- flagged[[nm]]
      if (is.null(df) || nrow(df) == 0L || !all(keys %in% names(df))) return(NULL)
      dplyr::select(df, dplyr::all_of(keys))
    })
  title_keys <- dplyr::bind_rows(title_tables) %>% dplyr::distinct()

  # Title enrichment is display-only. Restrict the DESR work to the analytical
  # groups that survived the anomaly screens instead of rebuilding a title
  # lookup across the full section history for every uncached request.
  title_lookup <- if (nrow(title_keys) > 0L) {
    courses %>%
      dplyr::semi_join(title_keys, by = keys) %>%
      build_regstats_title_lookup()
  } else {
    build_regstats_title_lookup(courses[0, , drop = FALSE])
  }

  for (nm in c("bumps", "dips", "early_drops", "late_drops", "waits", "sat")) {
    df <- flagged[[nm]]
    if (is.null(df) || nrow(df) == 0L || !all(keys %in% names(df))) next
    # Shared class-list waitlist demand already carries the title as part of its
    # analytical grain. Replacing it with a DESR display lookup would collapse
    # topics offerings that Waitlists keeps separate.
    if (identical(nm, "waits") && "course_title" %in% names(df)) next
    flagged[[nm]] <- df %>%
      dplyr::select(-dplyr::any_of("course_title")) %>%
      dplyr::left_join(title_lookup, by = keys, relationship = "many-to-one")
  }

  flagged
}


# Name the former codes behind each flagged course (ADR-001 step 4). Display
# enrichment like the titles: one text per course, read off both keyed frames
# (course_former_code_spans()), NA for a course that has carried one code.
attach_regstats_former_codes <- function(flagged, students, courses) {
  spans <- course_former_code_spans(students, courses)
  for (nm in c("bumps", "dips", "early_drops", "late_drops", "waits", "sat")) {
    df <- flagged[[nm]]
    if (is.null(df) || !"subject_course" %in% names(df)) next
    flagged[[nm]] <- df %>%
      dplyr::select(-dplyr::any_of("former_codes")) %>%
      dplyr::left_join(spans, by = "subject_course", relationship = "many-to-one")
  }
  flagged
}


# What the page says about following courses across their codes: how many
# flagged courses also ran under another code. The module renders
# the sentence; the counts stay typed beside it.
regstats_course_key_info <- function(flagged) {
  renamed <- unique(unlist(lapply(c("bumps", "dips", "early_drops", "late_drops", "waits", "sat"),
    function(nm) {
      df <- flagged[[nm]]
      if (is.null(df) || !all(c("subject_course", "former_codes") %in% names(df))) return(character(0))
      as.character(df$subject_course[!is.na(df$former_codes)])
    })))
  n <- length(renamed)
  note <- if (n == 0L) {
    "Each course is followed across the codes it has carried; no flagged course ran under another code."
  } else {
    paste0("Each course is followed across the codes it has carried: ", n, " flagged course",
           if (n == 1L) "" else "s", " also ran under another code, named in the Course column.")
  }
  list(keyed_on = "course_id", n_renamed_courses = n, renamed_courses = sort(renamed), note = note)
}


#' Detect Registration Anomalies and Enrollment Concerns
#'
#' Analyzes historical enrollment patterns to identify courses with unusual registration
#' behavior including bumps (higher than normal), dips (lower than normal), drops
#' (higher early/late withdrawal), squeezes (high enrollment with low capacity), and
#' waitlists. This is the primary tool for identifying enrollment concerns that need
#' administrative attention.
#'
#' @param students Data frame of student enrollments from cedar_registrations table,
#'   with \code{course_id} attached (as every loader does).
#'   Must include columns: campus, college, term, term_type, subject_course,
#'   course_title, level, student_id, registration_status
#' @param courses Data frame of course sections from cedar_sections table,
#'   with \code{course_id} attached.
#'   Must include columns: campus, college, term, subject_course, gen_ed_area,
#'   enrolled, waiting, avail
#' @param opt Options list for filtering and thresholds:
#'   \itemize{
#'     \item \code{term} - Term code(s) to analyze (e.g., 202510)
#'     \item \code{course} - Course identifier(s) to analyze (e.g., "MATH 1430"),
#'       current or former: each resolves to its course
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
#'     \item \code{running_hot_sat} - "Running hot" courses: fill above their own prior pattern by the configured SD band
#'     \item \code{chronic_sat} - "Chronically full" courses: above the selected fill ceiling for the required number of prior same-type terms
#'     \item \code{all_flagged_courses} - Character vector of all flagged course identifiers
#'     \item \code{course_key_info} - How many flagged courses ran under another code, and the sentence the page shows
#'     \item \code{code_renames} - The renames the class list carried when this was counted (the cache compares them)
#'     \item \code{tiered_summary} - Summary of concerns by severity tier
#'     \item \code{thresholds} - Thresholds used for detection
#'     \item \code{cache_info} - Cache metadata including age and parameters
#'   }
#'
#' @details
#' ## The course, not the code
#' Both tables are read keyed on \code{course_id} (ADR-001 step 4), so every
#' \code{subject_course} in the result is a course id: a course's strictly
#' earlier offerings under a former code are its own baseline, the schedule's
#' capacity for a section the class list names by the newer code joins its
#' census, and each flagged row's \code{former_codes} names the other codes
#' the course has carried with their terms.
#'
#' ## Detection Methodology
#' Each target uses strictly earlier offerings of the same course, campus, college,
#' season, and part of term. Means and population SD use that identical history;
#' the SD denominator is n. SD screens require at least two observations and
#' positive variation. Unscored group counts are returned in baseline_info.
#' These are descriptive screens, not statistical significance tests:
#' \itemize{
#'   \item \strong{Bumps/Dips:} Directional deviation minus pct_sd times prior SD must exceed min_impacted.
#'   \item \strong{Drops:} Absolute drop-count deviation minus the same SD band must exceed min_impacted; either direction can flag. Lifecycle-denominator rates are returned as interpretation context but do not decide the flag.
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
#'   \item \code{chronic_fill_rate} = CEDAR_NEAR_FULL_FILL (fill rate above which a course is chronically capacity-constrained)
#'   \item \code{min_sat_terms} = 3 (minimum prior same-type terms at/above chronic_fill_rate to flag chronic)
#'   \item \code{min_wait} = 20 (minimum waitlist size)
#'   \item \code{section_proximity} = 0.3 (proximity threshold for sections)
#' }
#'
#' ## Custom Thresholds
#' Custom thresholds can be provided via \code{opt$thresholds}. If custom thresholds
#' differ from defaults, caching is bypassed to ensure fresh calculations.
#'
#' ## Caching
#' Results are cached for the current calendar day under a versioned key when using named threshold profiles. Cache files are
#' stored in \code{cedar_data_dir/regstats/} with names based on filtering parameters
#' (college, term, level, campus). Old cache files are automatically cleaned up,
#' keeping only the 20 most recent files.
#'
#' ## Anomaly Types Explained
#' \itemize{
#'   \item \strong{Early Drops:} Unusually high or low early-drop counts (dr_early), with rates over the class-list first-day proxy for context
#'   \item \strong{Late Drops:} Unusually high or low late-drop counts (dr_late), with rates over reconstructed class-list census enrollment for context
#'   \item \strong{Dips:} Lower than normal registration (may indicate declining interest)
#'   \item \strong{Bumps:} Higher than normal registration (may indicate unmet demand)
#'   \item \strong{Waits:} Waitlist count above the configured threshold
#'   \item \strong{Running hot:} Fill above its prior mean by the configured population-SD threshold, not registration speed
#'   \item \strong{Chronically full:} Fill rate above absolute ceiling for 3+ past same-type terms
#' }
#'
#' @param course_terms \code{cedar_course_terms} (\code{\link{build_course_terms}}),
#'   required: the course-term counts and the schedule's seats it filters
#'   (ADR-001 step 7). A table not counted by this build over \code{students}'
#'   course codes is refused. An option about one section or one student
#'   (\code{inst}, \code{im}, \code{classification}, ...) is an error: the
#'   table counts every section and every student of a course-term.
#'
#' @examples
#' \dontrun{
#' # Analyze all Arts & Sciences courses for Fall 2025
#' opt <- list(term = "202510", course_college = "AS")
#' flagged <- get_reg_stats(cedar_registrations, cedar_sections, opt)
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
#' custom_flagged <- get_reg_stats(cedar_registrations, cedar_sections, custom_opt)
#' }
#'
#' @seealso
#' \code{\link{build_course_terms}} for the counts and seats it screens,
#' \code{\link{assign_concern_tier}} for severity classification,
#' \code{\link{create_tiered_summary}} for dashboard summaries
#'
#' @export
get_reg_stats <- function(students, courses, opt, course_terms) {
  cedar_debug("[regstats.R] Welcome to get_reg_stats!")
  if (missing(course_terms) || is.null(course_terms)) {
    stop("[regstats.R] get_reg_stats(): course_terms (cedar_course_terms, as the loader ",
         "holds it) is required.", call. = FALSE)
  }

  # Regstats follows the course, not the code (ADR-001 step 4): both tables are
  # read keyed on course_id, so a course's strictly earlier offerings under a
  # former code are its own baseline, the schedule's capacity for a section the
  # class list names by the newer code joins its census, and a code asked for,
  # current or former, resolves to its course once. The renames in the class
  # list fingerprint the result: the cache and course_terms must have been
  # counted over the same ones.
  if (!is.null(opt[["course"]]) && !identical(opt[["course"]], "")) {
    opt[["course"]] <- course_ids_of(opt[["course"]], students, courses, caller = "get_reg_stats")
  }
  code_renames <- course_code_renames(students)

  # course_terms is checked against the class list before either is cut, so a
  # table counted over other course codes is refused, not filtered.
  require_current_course_terms(course_terms, students, "get_reg_stats")

  # The excluded-course list by course, read once over both whole tables: a
  # course the list names under any code it has carried is excluded in every
  # term and from course_terms, counted by course (drop_excluded_courses(), M39).
  # Every pass below then reads the same courses.
  excluded_ids <- if (exists("excluded_courses")) excluded_course_ids(students, courses) else character(0)
  if (length(excluded_ids) > 0) {
    students <- students[!course_code_in(students$subject_course, excluded_ids), ]
    courses <- courses[!course_code_in(courses$subject_course, excluded_ids), ]
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
      chronic_fill_rate = CEDAR_NEAR_FULL_FILL,
      min_wait          = 20,
      min_sat_terms     = 3,
      section_proximity = 0.3
    )
  }

  threshold_profile <- opt[["threshold_profile"]] %||% "standard"
  if (!threshold_profile %in% c("standard", "dashboard")) {
    stop("[regstats.R] Unknown threshold_profile: ", threshold_profile)
  }

  profile_thresholds <- if (identical(threshold_profile, "dashboard")) {
    get_dashboard_regstats_thresholds(default_thresholds)
  } else {
    default_thresholds
  }

  using_custom_thresholds <- FALSE

  if (!is.null(opt[["thresholds"]])) {
    custom_thresholds <- opt[["thresholds"]]

    thresholds_differ <- FALSE
    common_names <- intersect(names(custom_thresholds), names(profile_thresholds))
    for (name in common_names) {
      if (!isTRUE(all.equal(custom_thresholds[[name]], profile_thresholds[[name]]))) {
        thresholds_differ <- TRUE
        break
      }
    }

    if (thresholds_differ) {
      thresholds <- custom_thresholds
      using_custom_thresholds <- TRUE
      cedar_debug("[regstats.R] Custom thresholds differ from ", threshold_profile, " profile - bypassing cache.")
    } else {
      thresholds <- profile_thresholds
    }
  } else {
    thresholds <- profile_thresholds
  }

  # Only check cache if using a named threshold profile and bypass not requested.
  if (!using_custom_thresholds && !isTRUE(opt[["bypass_cache"]])) {
    cedar_debug("[regstats.R] Checking for cached regstats (", threshold_profile, " thresholds)...")
    cached_results <- load_regstats_cache(opt, code_renames)
    if (!is.null(cached_results)) {
      cedar_debug("[regstats.R] Found valid cached regstats!")
      return(cached_results)
    }
  } else {
    cedar_debug("[regstats.R] Skipping cache check due to custom thresholds.")
  }

  # Build myopt without term so downstream code (waits) has it.
  myopt <- opt
  myopt[["term"]] <- NULL

  # The course-term measure table, scoped by the request's options
  # (filter_course_terms(): an option about one section or one student is an
  # error, never ignored) and cut to the courses the exclusion list leaves,
  # by course, as the class list and the schedule were above (M39). Every
  # term is kept: each target term's baseline is its own earlier offerings.
  cedar_debug("[regstats.R] Filtering cedar_course_terms...")
  course_terms <- filter_course_terms(course_terms, myopt)
  if (length(excluded_ids) > 0) {
    course_terms <- course_terms %>%
      filter(!normalize_course_code(subject_course) %in% excluded_ids)
  }
  cedar_debug("[regstats.R] course_terms filtered to ", nrow(course_terms), " rows.")
  # The schedule's side of every row, for the saturation pass: the active
  # offerings and their seats. The class-list side screens only the
  # course-terms the class list has a row for (NA counts: the schedule offered
  # it and nobody registered under it, unknown rather than zero).
  schedule <- course_terms %>%
    select(campus, college, subject_course, term, part_term,
           sections, sections_matched, seats, seats_known, desr_enrl)
  regstats <- course_terms %>%
    filter(!is.na(registered)) %>%
    select(-any_of(c("level", "department", "subject_code",
                     "first_day_enrl", "first_day_basis", "first_day_started_enrl",
                     "sections", "sections_matched", "seats", "seats_known", "desr_enrl",
                     "attempts", "passed", "dfw", "withdrawn")))

  # Every reported term has its own strictly earlier, same-season baseline.
  # Preserve the full observations for sparklines, but never use the target or
  # a later term to estimate its comparison mean or spread.
  history_keys <- c("campus", "college", "subject_course", "term_type", "part_term")
  regstats <- regstats %>% ungroup() %>%
    select(-any_of(c("registered_mean", "dr_early_mean", "dr_late_mean",
                    "dr_all_mean", "cl_total_mean", "n_hist_terms",
                    "early_drop_rate_mean", "late_drop_rate_mean"))) %>%
    add_classlist_lifecycle_enrl() %>%
    mutate(
      early_drop_rate = if_else(first_day_proxy > 0,
                                dr_early / first_day_proxy, NA_real_),
      late_drop_rate = if_else(census_enrl > 0,
                               dr_late / census_enrl, NA_real_)
    ) %>%
    add_prior_history_stats(c("registered", "dr_early", "dr_late", "dr_all", "cl_total",
                              "early_drop_rate", "late_drop_rate"),
                            history_keys, "term") %>%
    rename(registered_mean = registered_hist_mean,
           dr_early_mean = dr_early_hist_mean, dr_late_mean = dr_late_hist_mean,
           dr_all_mean = dr_all_hist_mean, cl_total_mean = cl_total_hist_mean,
           early_drop_rate_mean = early_drop_rate_hist_mean,
           late_drop_rate_mean = late_drop_rate_hist_mean)

  # Use the canonical census helper in prior-only mode. Its term key is essential:
  # multiple selected terms must not share a pooled comparison baseline.
  census_bl <- calc_census_enrl_baselines(regstats, keys = history_keys, prior_only = TRUE) %>%
    select(all_of(c(history_keys, "term")), census_enrl_mean = census_mean,
           census_enrl_sd = census_sd, n_hist_terms)
  regstats <- left_join(regstats, census_bl, by = c(history_keys, "term"),
                        relationship = "one-to-one")

  # find potential registration anomalies
  # Population SD describes observed prior offerings; this is not a significance test.
  cedar_debug("[regstats.R] Finding courses of interest...")
  flagged <- list()
  std_fields <- c("campus", "college","subject_course","part_term","term","term_type","census_enrl")
  #std_arrange_cols <- c("campus","term","impacted")
  std_arrange_cols <- c("campus", "college")
  
  
  ##### EARLY DROPS
  cedar_debug("[regstats.R] Finding early drops...")
  drops <- regstats %>% select(
    all_of(std_fields), census_enrl_mean, any_of("n_hist_terms"),
    drop_early = dr_early, dr_early_mean, pop_sd = dr_early_hist_sd,
    drop_denominator = first_day_proxy, drop_rate = early_drop_rate,
    drop_rate_mean = early_drop_rate_mean,
    rate_hist_terms = early_drop_rate_hist_n
  )
  drops <- drops %>% mutate(
    # Calculate deviation in SD units
    sd_deviation = (drop_early - dr_early_mean) / pop_sd,
    
    # Students outside the SD band (either direction): |raw diff| minus the noise
    # band. Direction is carried by concern_tier; this is the magnitude.
    impacted = abs(drop_early - dr_early_mean) - thresholds[["pct_sd"]] * pop_sd,

    # Count screens answer operational volume; rate context separates a larger
    # course from a higher probability of early withdrawal.
    drop_rate_change_pp = 100 * (drop_rate - drop_rate_mean),

    # Concern tier assignment
    concern_tier = assign_concern_tier(drop_early, dr_early_mean, pop_sd, "both")
  )

  # One test: students outside the SD band must exceed min_impacted. Because
  # impacted > min_impacted >= 0 forces |deviation| past pct_sd, this subsumes
  # the old SD gate.
  drops <- drops %>% filter(is.finite(sd_deviation), pop_sd > 0,
                             impacted > thresholds[["min_impacted"]])

  drops <- drops %>% arrange(across(all_of(std_arrange_cols)))
  flagged[["early_drops"]] <- drops


##### LATE DROPS
cedar_debug("[regstats.R] Finding late drops...")
late_drops <- regstats %>% select(
  all_of(std_fields), census_enrl_mean, any_of("n_hist_terms"),
  drop_late = dr_late, dr_late_mean, pop_sd = dr_late_hist_sd,
  drop_denominator = census_enrl, drop_rate = late_drop_rate,
  drop_rate_mean = late_drop_rate_mean,
  rate_hist_terms = late_drop_rate_hist_n
)
late_drops <- late_drops %>% mutate(
  # Calculate deviation in SD units
  sd_deviation = (drop_late - dr_late_mean) / pop_sd,
  
  # Students outside the SD band (either direction); direction is in concern_tier.
  impacted = abs(drop_late - dr_late_mean) - thresholds[["pct_sd"]] * pop_sd,

  # The late-drop rate uses the population that reached census. It is context
  # for the count-selected alert, not a second significance test.
  drop_rate_change_pp = 100 * (drop_rate - drop_rate_mean),

  # Concern tier assignment for high anomalies
  concern_tier = assign_concern_tier(drop_late, dr_late_mean, pop_sd, "both")
)

late_drops <- late_drops %>% filter(is.finite(sd_deviation), pop_sd > 0,
                                     impacted > thresholds[["min_impacted"]])

flagged[["late_drops"]] <- late_drops %>% arrange(across(all_of(std_arrange_cols)))


##### DIPS
cedar_debug("[regstats.R] Finding dips...")
dips <- regstats %>% select(all_of(std_fields), census_enrl_mean, n_hist_terms, pop_sd = census_enrl_sd)
dips <- dips %>% mutate(
  # Calculate deviation in SD units
  sd_deviation = (census_enrl - census_enrl_mean) / pop_sd,

  # Students beyond the SD boundary: raw diff minus the expected normal variance.
  impacted = census_enrl_mean - census_enrl - thresholds[["pct_sd"]] * pop_sd,

  # Concern tier assignment for low anomalies
  concern_tier = assign_concern_tier(census_enrl, census_enrl_mean, pop_sd, "low")
)

dips <- dips %>% filter(is.finite(sd_deviation), pop_sd > 0,
                           impacted > thresholds[["min_impacted"]])

flagged[["dips"]] <- dips %>% arrange(across(all_of(std_arrange_cols)))



##### BUMPS
cedar_debug("[regstats.R] Finding bumps...")
bumps <- regstats %>% select(all_of(std_fields), census_enrl_mean, n_hist_terms, pop_sd = census_enrl_sd)
bumps <- bumps %>% mutate(
  # Calculate deviation in SD units
  sd_deviation = (census_enrl - census_enrl_mean) / pop_sd,

  # Students beyond the SD boundary: raw diff minus the expected normal variance.
  impacted = census_enrl - census_enrl_mean - thresholds[["pct_sd"]] * pop_sd,

  # Concern tier assignment for high anomalies
  concern_tier = assign_concern_tier(census_enrl, census_enrl_mean, pop_sd, "high")
)

bumps <- bumps %>% filter(is.finite(sd_deviation), pop_sd > 0,
                           impacted > thresholds[["min_impacted"]])

flagged[["bumps"]] <- bumps %>% arrange(across(all_of(std_arrange_cols)))


  ##### WAITS
  cedar_debug("[regstats.R] Finding waits...")
  wait_opt <- opt
  wait_opt[["uel"]] <- TRUE
  wait_group_cols <- c("campus", "college", "term", "part_term",
                       "subject_course", "course_title")
  wait_scoped_students <- filter_class_list(students, wait_opt) %>%
    ensure_waitlist_course_title(courses)
  wait_demand <- get_true_waitlisted_rows(wait_scoped_students) %>%
    summarize_waitlist_demand(wait_group_cols, count_name = "waiting")
  wait_eligible_groups <- wait_scoped_students %>%
    dplyr::ungroup() %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(wait_group_cols))) %>%
    dplyr::left_join(wait_demand, by = wait_group_cols, relationship = "one-to-one") %>%
    dplyr::mutate(waiting = dplyr::coalesce(waiting, 0L))
  waits <- wait_demand %>%
    dplyr::filter(waiting >= thresholds[["min_wait"]]) %>%
    dplyr::arrange(dplyr::desc(waiting))
  flagged[["waits"]] <- waits
  
  
  ##### CAPACITY SATURATION (replaces squeeze)
  # Align the numerator to one lifecycle source: class-list census enrollment is
  # registered + late drops. DESR contributes scheduled capacity only. The DESR
  # snapshot fill remains secondary source context, never part of the headline
  # calculation. Neither extract reconstructs a frozen census roster.
  cedar_debug("[regstats.R] Computing fill-rate saturation (census-based)...")

  # Single chronic ceiling (UI slider) governs BOTH the current-term flag and the
  # count of prior near-full terms. A course is chronic only if it's genuinely maxed
  # (>= this fill) now AND in min_sat_terms+ past same-type terms — filters out noise.
  chronic_threshold      <- thresholds[["chronic_fill_rate"]] %||% CEDAR_NEAR_FULL_FILL
  min_sat_terms          <- as.integer(thresholds[["min_sat_terms"]] %||% 3L)

  # Seats come from the schedule's side of the measure table (the active
  # offerings, crosslist-aware through get_enrl() in build_course_terms()),
  # over every term, so each target term has its own prior fill history. A
  # course-term whose capacity is not known on every section (`seats_known`)
  # has no capacity: unknown, never the headcount standing in for the seats.
  # The class-list side is joined back so an offering nobody registered under
  # is reported as unmatched, never as empty.
  sat_enrls <- schedule %>% filter(!is.na(sections), sections > 0)
  message("[regstats.R] sat_enrls: ", nrow(sat_enrls), " rows, terms: ",
          paste(sort(unique(sat_enrls$term)), collapse = ", "))

  lifecycle_lookup <- regstats %>%
    dplyr::select(campus, college, subject_course, term, part_term,
                  census_enrl, classlist_registered = registered, dr_late)

  sat_candidates <- sat_enrls %>%
    add_term_type_col("term") %>%
    dplyr::left_join(
      lifecycle_lookup,
      by = c("campus", "college", "subject_course", "term", "part_term"),
      relationship = "one-to-one"
    ) %>%
    mutate(
      source_matched = !is.na(census_enrl),
      enrolled = desr_enrl,
      capacity = if_else(seats_known, seats, NA_real_)
    ) %>%
    select(-seats, -seats_known, -desr_enrl, -sections_matched)
  sat_candidates <- dplyr::bind_cols(
    sat_candidates,
    capacity_saturation_metrics(
      sat_candidates$census_enrl,
      sat_candidates$capacity,
      constrained_threshold = chronic_threshold
    )
  ) %>%
    mutate(
      # PRIMARY: class-list lifecycle numerator over DESR scheduled capacity.
      fill_rate = census_fill,
      # SECONDARY: the independently timed DESR snapshot, for source comparison.
      desr_snapshot_fill = if_else(capacity > 0, enrolled / capacity, NA_real_)
    )

  sat_target_candidates <- if (is.null(opt[["term"]])) {
    sat_candidates
  } else {
    filter_by_term(sat_candidates, opt[["term"]], "term")
  }
  saturation_coverage <- list(
    matched = sum(sat_target_candidates$source_matched),
    unmatched = sum(!sat_target_candidates$source_matched),
    invalid_capacity = sum(sat_target_candidates$source_matched &
                             !sat_target_candidates$capacity_usable),
    below_minimum = sum(sat_target_candidates$source_matched &
                          sat_target_candidates$capacity_usable &
                          sat_target_candidates$census_enrl < thresholds[["min_impacted"]],
                        na.rm = TRUE)
  )

  sat_all <- sat_candidates %>%
    filter(source_matched, capacity_usable,
           census_enrl >= thresholds[["min_impacted"]])
  message("[regstats.R] sat_all after fill_rate filter: ", nrow(sat_all), " rows")
  if (nrow(sat_all) > 0L && any(is.finite(sat_all$fill_rate))) {
    message("[regstats.R] sat_all census fill_rate range: ",
            min(sat_all$fill_rate, na.rm = TRUE), " – ",
            max(sat_all$fill_rate, na.rm = TRUE))
  } else {
    message("[regstats.R] sat_all has no source-matched groups with usable fill.")
  }

  # Identical prior-only population-SD policy for fill and enrollment/drop counts.
  # An at-cap indicator gives the prior count without counting the target itself.
  sat <- sat_all %>%
    mutate(at_cap = as.integer(fill_rate >= chronic_threshold)) %>%
    add_prior_history_stats(c("fill_rate", "at_cap"), history_keys, "term") %>%
    rename(fill_rate_mean = fill_rate_hist_mean, fill_rate_sd = fill_rate_hist_sd,
           n_hist_terms = fill_rate_hist_n, n_chronic_terms = at_cap_hist_sum) %>%
    select(-starts_with("at_cap"), -fill_rate_hist_sum) %>%
    mutate(
      fill_rate_delta = fill_rate - fill_rate_mean,
      sd_above_mean = if_else(is.finite(fill_rate_sd) & fill_rate_sd > 0,
                             (fill_rate - fill_rate_mean) / fill_rate_sd,
                             NA_real_)
    )

  # Focus diagnostics on the current term rows
  sat_current <- if (is.null(opt[["term"]])) sat else filter_by_term(sat, opt[["term"]], "term")
  message("[regstats.R] sat rows for current term: ", nrow(sat_current))
  message("[regstats.R]   fill_rate >= chronic_threshold (",chronic_threshold,"): ",
          sum(sat_current$fill_rate >= chronic_threshold, na.rm=TRUE))
  message("[regstats.R]   n_chronic_terms >= ",min_sat_terms,": ",
          sum(!is.na(sat_current$n_chronic_terms) & sat_current$n_chronic_terms >= min_sat_terms, na.rm=TRUE))
  message("[regstats.R]   n_hist_terms >= 2: ",
          sum(!is.na(sat_current$n_hist_terms) & sat_current$n_hist_terms >= 2L, na.rm=TRUE))
  message("[regstats.R]   sd_above_mean >= pct_sd (",thresholds[["pct_sd"]],"): ",
          sum(!is.na(sat_current$sd_above_mean) & sat_current$sd_above_mean >= thresholds[["pct_sd"]], na.rm=TRUE))

  # RUNNING HOT: selected-term fill above its prior mean by the configured SD band.
  running_hot_sat <- sat %>%
    filter(
      !is.na(fill_rate_mean),
      n_hist_terms >= 2L,
      !is.na(sd_above_mean),
      sd_above_mean >= thresholds[["pct_sd"]]
    ) %>%
    arrange(desc(sd_above_mean))

  # HISTORIC: at/above the census fill ceiling in min_sat_terms+ past same-type terms,
  # REGARDLESS of current fill. Surfaces both courses maxed right now and those usually
  # packed but soft this particular term (which the current-fill gate on chronic hides).
  historic_sat <- sat %>%
    filter(
      !is.na(n_chronic_terms),
      n_chronic_terms >= min_sat_terms
    ) %>%
    arrange(desc(n_chronic_terms), desc(fill_rate))

  # CHRONIC (back-compat subset): historic evidence AND currently at/above the ceiling.
  chronic_sat <- historic_sat %>% filter(fill_rate >= chronic_threshold)

  message("[regstats.R] running_hot_sat (all terms, pre-term-filter): ", nrow(running_hot_sat))
  message("[regstats.R] historic_sat (all terms, pre-term-filter): ", nrow(historic_sat))
  message("[regstats.R] chronic_sat  (all terms, pre-term-filter): ", nrow(chronic_sat))

  flagged[["running_hot_sat"]] <- running_hot_sat
  flagged[["chronic_sat"]]  <- chronic_sat
  flagged[["historic_sat"]] <- historic_sat
  # Combined saturation view: one row per course, tagged with which signals it trips so the
  # UI can badge "Full now" / "Chronically full" / "Running hot" and sort by current vs historic
  # fill. Flags are recomputed on the deduped rows (identical predicates to the filters above)
  # so a course appearing in both the running-hot and historic sets stays a single row.
  flagged[["sat"]] <- dplyr::bind_rows(running_hot_sat, historic_sat) %>%
    dplyr::distinct() %>%
    dplyr::mutate(
      is_full_now     = !is.na(fill_rate) & fill_rate >= chronic_threshold,
      is_chronic_hist = !is.na(n_chronic_terms) & n_chronic_terms >= min_sat_terms,
      is_running_hot  = !is.na(fill_rate_mean) & n_hist_terms >= 2L &
                        !is.na(sd_above_mean) & sd_above_mean >= thresholds[["pct_sd"]]
    ) %>%
    dplyr::arrange(dplyr::desc(fill_rate))
  
  
  # filter report data for supplied term
  if (!is.null(opt[["term"]])) {
    cedar_debug("[regstats.R] Filtering flagged data by term...")
    flagged <- lapply(flagged, function(x) filter_by_term(x, opt[["term"]], "term"))
  }

  # Titles are display enrichment. Preserve one row per analytical reporting
  # group even when its source sections carry multiple titles.
  flagged <- attach_regstats_titles(flagged, courses)
  flagged <- attach_regstats_former_codes(flagged, students, courses)
  flagged[["course_key_info"]] <- regstats_course_key_info(flagged)
  flagged[["waitlist_info"]] <- list(
    source = "classlist_true_demand",
    definition_id = "waitlist",
    reporting_grain = paste(wait_group_cols, collapse = ", "),
    threshold_rule = "waiting >= min_wait"
  )

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
  trend_metric <- c(bumps = "census_enrl", dips = "census_enrl",
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

  # gather subject_course col into separate list
  cedar_debug("[regstats.R] Gathering flagged courses...")
  flagged_courses <- c()
  for (flag in flagged) {
    if (is.data.frame(flag) && "subject_course" %in% names(flag)) {
      flagged_courses <- c(flagged_courses, as.character(flag$subject_course))
    }
  }

  cedar_debug("[regstats.R] Filtered flagged_courses has ", length(flagged_courses), " courses.")

  flagged[["all_flagged_courses"]] <- sort(unique(flagged_courses))

  # save thresholds for adding to report, and the renames this was counted over
  flagged[["thresholds"]] <- thresholds
  flagged[["code_renames"]] <- code_renames
  flagged[["baseline_info"]] <- get_regstats_baseline_info(
    regstats, sat, opt, saturation_coverage
  )
  
  # Create tiered summary for dashboard
  flagged[["tiered_summary"]] <- create_tiered_summary(flagged)
  
  # Snapshot summary: aggregate current-term stats for the registration overview cards.
  # Only computed when a specific numeric term code is selected (not term-type strings
  # like "fall"); convert_param_to_list can return those too so filter them out.
  if (!is.null(opt[["term"]])) {
    tgt_raw <- convert_param_to_list(opt[["term"]])
    tgt     <- suppressWarnings(as.integer(tgt_raw))
    tgt     <- tgt[!is.na(tgt) & nchar(as.character(tgt)) == 6L]
    curr <- regstats %>% filter(term %in% tgt, registered > 0)
    if (nrow(curr) > 0) {
      n_hist <- flagged$baseline_info$n_hist_terms

      # Section-level stats for snapshot cards — no level filter so we can split by level.
      snap_secs <- courses %>% dplyr::filter(term %in% tgt)
      if ("status" %in% names(snap_secs))
        snap_secs <- snap_secs %>% dplyr::filter(status == "A")
      if (!is.null(opt$course_campus)  && length(opt$course_campus)  > 0)
        snap_secs <- snap_secs %>% dplyr::filter(campus     %in% opt$course_campus)
      if (!is.null(opt$course_college) && length(opt$course_college) > 0)
        snap_secs <- snap_secs %>% dplyr::filter(college    %in% opt$course_college)
      if (!is.null(opt$dept_code)      && length(opt$dept_code)      > 0)
        snap_secs <- snap_secs %>% dplyr::filter(department %in% opt$dept_code)
      if (exists("excluded_courses")) {
        snap_secs <- snap_secs %>%
          dplyr::filter(!normalize_course_code(subject_course) %in% excluded_ids)
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
        if (!is.null(opt$dept_code)      && length(opt$dept_code)      > 0)
          ch_trend <- ch_trend %>% dplyr::filter(department %in% opt$dept_code)
        if (exists("excluded_courses")) {
          ch_trend <- ch_trend %>%
            dplyr::filter(!normalize_course_code(subject_course) %in% excluded_ids)
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

      target_wait_groups <- wait_eligible_groups %>% dplyr::filter(term %in% tgt)
      flagged[["summary"]] <- list(
        n_waitlisted      = sum(target_wait_groups$waiting > 0),
        pct_waitlisted    = if (nrow(target_wait_groups) > 0) {
          round(100 * mean(target_wait_groups$waiting > 0), 1)
        } else {
          NA_real_
        },
        n_hist_terms      = n_hist,
        target_terms      = tgt,
        trend_by_term     = trend_by_term,
        baseline_scope    = flagged$baseline_info$scope,
        snapshot_scope_note = paste(
          "Overview cards count active section rows and distinct courses by lower/upper level;",
          "they intentionally show both levels even when the anomaly table is level-filtered."
        ),
        lower             = make_level_snap(snap_secs %>% dplyr::filter(level == "lower")),
        upper             = make_level_snap(snap_secs %>% dplyr::filter(level == "upper"))
      )
    }
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
      using_standard_thresholds = identical(threshold_profile, "standard"),
      threshold_profile = threshold_profile
    )

    cedar_debug("[regstats.R] Saving flagged data to: ", cache_filename)
    cache_tmp <- tempfile(
      pattern = paste0(basename(cache_path), ".tmp-", Sys.getpid(), "-"),
      tmpdir = dirname(cache_path)
    )
    on.exit(unlink(cache_tmp), add = TRUE)
    saveRDS(flagged, cache_tmp)
    if (!file.rename(cache_tmp, cache_path)) {
      stop("Could not atomically replace Regstats cache: ", cache_filename)
    }

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
      threshold_profile = threshold_profile,
      custom_thresholds = thresholds,
      reason_no_cache = "Custom thresholds used"
    )
  }

  cedar_debug("[regstats.R] Returning flagged courses...")
  return(flagged)
}


# ---------------------------------------------------------------------------
# Next Term Signals
# ---------------------------------------------------------------------------

#' The next-term destinations of some source courses
#'
#' A filter on cedar_course_flows (build_course_flows()), which global.R counts
#' once over the keyed class list, to the longitudinal edge.
#'
#' @param source_courses Character vector of subject_course values (courses).
#' @param course_flows cedar_course_flows.
#' @param campus Optional campuses to keep.
#' @return The flows rows for those sources: campus, source_course,
#'   dest_course, term, next_term, n_students and the rest of
#'   build_course_flows()'s columns.
get_downstream_course_flows <- function(source_courses, course_flows, campus = NULL) {
  require_course_flows(course_flows, "get_downstream_course_flows")
  flows <- course_flows %>% filter(source_course %in% source_courses)
  if (!is.null(campus) && length(campus) > 0) {
    flows <- flows %>% filter(campus %in% .env$campus)
  }
  flows
}

# A course-flow table is required, never recomputed here: an absent one is a
# start-up failure to report, not a reason to count the class list again.
require_course_flows <- function(course_flows, caller) {
  needed <- c("campus", "source_course", "dest_course", "term", "next_term", "n_students")
  if (!is.data.frame(course_flows) || length(setdiff(needed, names(course_flows))) > 0L ||
      is.null(attr(course_flows, "enrolled_edge", exact = TRUE))) {
    stop("[regstats.R] ", caller, "(): course_flows must be cedar_course_flows as ",
         "build_course_flows() counts it (global.R holds it in data_objects).", call. = FALSE)
  }
  invisible(course_flows)
}


#' Compute next-term downstream signals from a regstats flagged list
#'
#' Answers "which courses are likely to face extra demand next term?" by
#' identifying courses downstream of enrollment bumps (students tend to take
#' them after bump courses) and courses with drop anomalies (unmet demand —
#' students who dropped will try to re-enroll). A bump's destinations are
#' ranked by their average flow over the two most recent regular source terms
#' in cedar_course_flows, whose pairs stop at the longitudinal edge, so a
#' destination term still registering never lowers that average.
#'
#' @param flagged  Named list returned by get_reg_stats().
#' @param course_flows cedar_course_flows (build_course_flows()).
#' @param campus Optional campuses to keep.
#' @return Named list:
#'   downstream — tibble(dest_course, reason, top_feeders); one row per
#'                (dest_course, reason) pair. reason is "Bump" or "Drop".
#'                top_feeders lists up to 3 upstream courses (Bump) or drop
#'                signal types (Drop). Empty tibble if no signals or no flow data.
#'   enrolled_edge — the last source-pair term the flows could observe.
get_next_term_signals <- function(flagged, course_flows, campus = NULL) {
  require_course_flows(course_flows, "get_next_term_signals")
  flows_for_terms <- course_flows
  if (!is.null(campus) && length(campus) > 0) {
    flows_for_terms <- flows_for_terms %>% filter(campus %in% .env$campus)
  }
  flow_terms <- flows_for_terms$term

  all_main_terms <- sort(unique(flow_terms[flow_terms %% 100L != 60L]))
  edge <- attr(course_flows, "enrolled_edge", exact = TRUE)
  if (length(all_main_terms) == 0L) return(list(downstream = tibble(), enrolled_edge = edge))
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
    flows <- get_downstream_course_flows(bump_sources, course_flows, campus = campus)
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
      "census_enrl_mean" %in% names(flagged$early_drops))
    drop_parts[["early"]] <- flagged$early_drops %>%
      filter(grepl("_high$", concern_tier), impacted > 0) %>%
      group_by(dplyr::across(dplyr::any_of(c("campus", "subject_course")))) %>%
      slice_max(order_by = impacted, n = 1L, with_ties = FALSE) %>%
      ungroup() %>%
      select(any_of(c("campus", "subject_course")), impacted) %>%
      mutate(drop_type = "early drops")
  if (!is.null(flagged$late_drops) && nrow(flagged$late_drops) > 0L &&
      "census_enrl_mean" %in% names(flagged$late_drops))
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

  list(downstream = downstream, enrolled_edge = edge)
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
