# major-changes.R — Major Change Detection and Analysis
#
# Detects when students change their primary major across terms, analyzes
# common change pathways, and associates course enrollments with change events.
#
# All functions take cedar_programs as primary input. Program-type filtering
# to "Major" rows is handled internally — callers do not need to pre-filter.
#
# Cohort-aware: pass a tibble(student_id, cohort_label) to restrict analysis
# to a specific student population. Cohort is optional in all functions.
#
# Functions that need course enrollment data additionally take cedar_students.
#
# Depends on: STATUS_REGISTERED (lists/status_codes.R),
#             dedup_enrollment(), term_diff() (trunk/utils.R)


# ── Core detection ────────────────────────────────────────────────────────────

#' Detect major changes for each student across their academic timeline
#'
#' Compares each student's primary major term-over-term. A change is recorded
#' when program_name differs from the prior term. Each row in the output
#' represents one change event.
#'
#' @param programs cedar_programs data frame.
#' @param cohort   Optional tibble(student_id, cohort_label). If provided,
#'   only students in the cohort are analyzed.
#' @param opt      Options list:
#'   \itemize{
#'     \item \code{campus}  — character; filter by student_campus
#'     \item \code{college} — character; filter by student_college
#'     \item \code{dept}    — character; filter by dept_code
#'   }
#' @return Tibble with one row per major change event:
#'   student_id, change_term, prev_term, from_major, to_major,
#'   credits_at_change, student_college, student_campus, dept_code,
#'   student_level, degree
detect_major_changes <- function(programs, population = NULL, opt = list()) {

  message("[major-changes.R] Welcome to detect_major_changes!")

  majors <- programs %>%
    filter(program_type == "Major", !is.na(program_name), program_name != "")

  # Cohort filter
  if (!is.null(population)) {
    majors <- majors %>% filter(student_id %in% population$student_id)
    message("[major-changes.R] Cohort applied: ", n_distinct(majors$student_id), " students")
  }

  # opt filters
  if (!is.null(opt$campus)  && length(opt$campus)  > 0)
    majors <- majors %>% filter(student_campus  %in% opt$campus)
  if (!is.null(opt$college) && length(opt$college) > 0)
    majors <- majors %>% filter(student_college %in% opt$college)
  if (!is.null(opt$dept)    && length(opt$dept)    > 0)
    majors <- majors %>% filter(dept_code       %in% opt$dept)

  message("[major-changes.R] Analyzing ", n_distinct(majors$student_id), " students")

  changes <- majors %>%
    arrange(student_id, term) %>%
    group_by(student_id) %>%
    mutate(
      prev_major = lag(program_name),
      prev_term  = lag(term),
      prev_level = lag(student_level),
      changed    = !is.na(prev_major) & program_name != prev_major
    ) %>%
    ungroup() %>%
    # Exclude level transitions: undergrad → grad school is not a major change.
    # A History BA student enrolling in law school appears as History → JD here;
    # filtering to same-level changes removes these cross-level artifacts.
    filter(changed, is.na(prev_level) | student_level == prev_level) %>%
    select(
      student_id,
      change_term       = term,
      prev_term,
      from_major        = prev_major,
      to_major          = program_name,
      credits_at_change = inst_credits_attempted,
      student_college,
      student_campus,
      dept_code,
      student_level,
      degree
    ) %>%
    arrange(student_id, change_term)

  message("[major-changes.R] Detected ", nrow(changes), " change events across ",
          n_distinct(changes$student_id), " students")
  return(changes)
}


# ── Summary functions (take output of detect_major_changes) ──────────────────

#' Average credits at time of arriving in each major (via change)
#'
#' @param changes Tibble from detect_major_changes()
#' @param opt     Options list; uses opt$min_n (default 5)
#' @return Tibble: to_major, avg_credits, median_credits, n_changes, n_students
avg_credits_before_major <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 5L

  changes %>%
    group_by(to_major) %>%
    summarize(
      avg_credits    = mean(credits_at_change,   na.rm = TRUE),
      median_credits = median(credits_at_change, na.rm = TRUE),
      n_changes      = n(),
      n_students     = n_distinct(student_id),
      .groups        = "drop"
    ) %>%
    filter(n_changes >= min_n) %>%
    arrange(desc(avg_credits))
}


#' Most common majors students leave
#'
#' @param changes Tibble from detect_major_changes()
#' @param opt     Options list; uses opt$min_n (default 5)
#' @return Tibble: from_major, n_exits, ranked by frequency
majors_moved_out_of <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 5L

  changes %>%
    count(from_major, name = "n_exits", sort = TRUE) %>%
    filter(n_exits >= min_n)
}


#' Most common A → B major change pathways
#'
#' @param changes Tibble from detect_major_changes()
#' @param opt     Options list; uses opt$min_n (default 3)
#' @return Tibble: from_major, to_major, n_changes, avg_credits_at_change
major_change_pathways <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 3L

  changes %>%
    group_by(from_major, to_major) %>%
    summarize(
      n_changes   = n(),
      avg_credits = round(mean(credits_at_change, na.rm = TRUE), 1),
      .groups     = "drop"
    ) %>%
    filter(n_changes >= min_n) %>%
    arrange(desc(n_changes))
}


#' Major change pathways broken out by college
#'
#' @param changes Tibble from detect_major_changes()
#' @param opt     Options list; uses opt$min_n (default 3)
#' @return Tibble: student_college, from_major, to_major, n_changes, avg_credits
pathways_by_college <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 3L

  changes %>%
    group_by(student_college, from_major, to_major) %>%
    summarize(
      n_changes   = n(),
      avg_credits = round(mean(credits_at_change, na.rm = TRUE), 1),
      .groups     = "drop"
    ) %>%
    filter(n_changes >= min_n) %>%
    arrange(student_college, desc(n_changes))
}


# ── Functions that take cedar_programs directly ───────────────────────────────

#' Terms from first enrollment to first major change
#'
#' Uses term_diff() for accurate term counting (summers excluded by default).
#'
#' @param programs cedar_programs data frame
#' @param cohort   Optional tibble(student_id, cohort_label)
#' @param opt      Options list (passed through to detect_major_changes)
#' @return Tibble: student_id, first_term, first_change_term,
#'   terms_until_change, from_major, to_major
time_to_first_change <- function(programs, population = NULL, opt = list()) {
  message("[major-changes.R] Calculating time to first major change...")

  changes <- detect_major_changes(programs, population = population, opt = opt)

  first_changes <- changes %>%
    group_by(student_id) %>%
    summarize(
      first_change_term = min(change_term),
      from_major        = first(from_major),
      to_major          = first(to_major),
      .groups           = "drop"
    )

  first_terms <- programs %>%
    filter(program_type == "Major") %>%
    { if (!is.null(population)) filter(., student_id %in% population$student_id) else . } %>%
    group_by(student_id) %>%
    summarize(first_term = min(term), .groups = "drop")

  result <- first_changes %>%
    left_join(first_terms, by = "student_id") %>%
    mutate(
      terms_until_change = term_diff(first_term, first_change_term)
    ) %>%
    select(student_id, first_term, first_change_term,
           terms_until_change, from_major, to_major) %>%
    arrange(terms_until_change)

  message("[major-changes.R] Median terms until first change: ",
          median(result$terms_until_change, na.rm = TRUE))
  return(result)
}


#' Tag students by whether they ever changed major
#'
#' @param programs cedar_programs data frame
#' @param cohort   Optional tibble(student_id, cohort_label)
#' @param opt      Options list (passed through to detect_major_changes)
#' @return Tibble: student_id, changed_major, n_changes, n_majors_held,
#'   majors_held (comma-separated sequence)
tag_major_changers <- function(programs, population = NULL, opt = list()) {
  message("[major-changes.R] Tagging students by major change behavior...")

  majors_base <- programs %>%
    filter(program_type == "Major", !is.na(program_name), program_name != "")

  if (!is.null(population))
    majors_base <- majors_base %>% filter(student_id %in% population$student_id)

  student_summary <- majors_base %>%
    group_by(student_id) %>%
    summarize(
      n_majors_held = n_distinct(program_name),
      majors_held   = paste(unique(program_name), collapse = " \u2192 "),
      .groups       = "drop"
    )

  changes <- detect_major_changes(programs, population = population, opt = opt)

  change_counts <- changes %>%
    count(student_id, name = "n_changes")

  result <- student_summary %>%
    left_join(change_counts, by = "student_id") %>%
    mutate(
      n_changes     = replace_na(n_changes, 0L),
      changed_major = n_changes > 0L
    ) %>%
    select(student_id, changed_major, n_changes, n_majors_held, majors_held)

  pct <- round(100 * mean(result$changed_major), 1)
  message("[major-changes.R] ", sum(result$changed_major), " of ", nrow(result),
          " students (", pct, "%) changed majors at least once")
  return(result)
}


# ── Course association ────────────────────────────────────────────────────────

#' Courses students were enrolled in during the term they changed majors
#'
#' Joins major change events to cedar_students by student_id + change_term.
#' Useful for identifying courses correlated with leaving or arriving in a major.
#'
#' To analyze departures from a major, filter changes to from_major == X before
#' calling. To analyze arrivals, filter to to_major == X.
#'
#' @param changes  Tibble from detect_major_changes(). Pre-filter to the
#'   from_major or to_major of interest before passing in.
#' @param students cedar_students data frame
#' @param opt      Options list:
#'   \itemize{
#'     \item \code{min_n} — integer; minimum students per course (default 5)
#'   }
#' @return Tibble: subject_course, course_title, n_students, pct_of_changers,
#'   sorted by n_students descending
get_major_change_courses <- function(changes, students, opt = list()) {
  message("[major-changes.R] Welcome to get_major_change_courses!")

  min_n      <- opt$min_n %||% 5L
  n_changers <- n_distinct(changes$student_id)

  if (n_changers == 0L) {
    message("[major-changes.R] No change events to process.")
    return(tibble())
  }

  message("[major-changes.R] Finding courses for ", n_changers, " students in change terms...")

  # Students enrolled in their change term
  change_keys <- changes %>%
    distinct(student_id, term = change_term)

  courses <- students %>%
    semi_join(change_keys,   by = c("student_id", "term")) %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    dedup_enrollment(level = "course") %>%
    count(subject_course, course_title, name = "n_students", sort = TRUE) %>%
    filter(n_students >= min_n) %>%
    mutate(pct_of_changers = round(n_students / n_changers, 3))

  message("[major-changes.R] Found ", nrow(courses), " courses taken during change terms")
  return(courses)
}
