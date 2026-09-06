# major-changes.R — Analyses over detected major changes
#
# Questions answered about students who changed their primary major: where they
# came from and went to, when the first change happened, and what coursework
# surrounded it.
#
# Detection itself lives in R/branches/major-change-detection.R. Functions here
# either take the `changes` tibble it returns, or call detect_major_changes()
# to build one. Program-type filtering to "Major" rows is handled in the branch;
# callers do not need to pre-filter.
#
# Population-aware: pass a build_population() tibble to restrict analysis to a
# student population. Population is optional in all functions.
#
# Depends on: detect_major_changes() (branches/major-change-detection.R),
#             STATUS_REGISTERED (lists/status_codes.R),
#             term_diff() (trunk/utils.R)

# ── Summary functions (take output of detect_major_changes) ──────────────────

#' Average credits at time of arriving in each major (via change)
#'
#' @param changes Tibble from detect_major_changes()
#' @param opt     Options list; uses opt$min_n (default 5)
#' @return Tibble: to_major, avg_unm_credits, median_unm_credits,
#'   avg_total_credits, median_total_credits, n_changes, n_students.
#'   Credits are lag-adjusted attempted hours (see detect_major_changes()).
avg_credits_before_major <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 5L

  # Only events with a trustworthy credit position count. A student whose UNM
  # history starts at the edge of the data has a running total that begins
  # mid-career at zero, and averaging that in understates every major they
  # arrive at. n_changes then reports what was actually averaged.
  usable <- changes %>%
    filter(!is.na(unm_credits_before_change),
           is.na(credits_position_valid) | credits_position_valid)

  # Reported per major so the caller can say how much of the change population
  # the average actually rests on. Dropping these rows is correct, but doing it
  # silently would let a major with three usable events out of forty read as a
  # settled figure.
  excluded <- changes %>%
    anti_join(usable, by = c("student_id", "change_term", "to_major")) %>%
    count(to_major, name = "n_excluded_position")

  usable %>%
    group_by(to_major) %>%
    summarize(
      avg_unm_credits      = mean(unm_credits_before_change,     na.rm = TRUE),
      median_unm_credits   = median(unm_credits_before_change,   na.rm = TRUE),
      avg_total_credits    = mean(total_credits_before_change,   na.rm = TRUE),
      median_total_credits = median(total_credits_before_change, na.rm = TRUE),
      n_changes      = n(),
      n_students     = n_distinct(student_id),
      .groups        = "drop"
    ) %>%
    left_join(excluded, by = "to_major") %>%
    mutate(n_excluded_position = coalesce(n_excluded_position, 0L)) %>%
    filter(n_changes >= min_n) %>%
    arrange(desc(avg_unm_credits))
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
#' @return Tibble: from_major, to_major, n_changes, avg_unm_credits,
#'   avg_total_credits. Credits are lag-adjusted attempted hours at the move.
major_change_pathways <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 3L

  changes %>%
    mutate(
      .credit_usable = !is.na(credits_position_valid) & credits_position_valid,
      .unm_for_mean = if_else(.credit_usable, unm_credits_before_change, NA_real_),
      .total_for_mean = if_else(.credit_usable, total_credits_before_change, NA_real_)
    ) %>%
    group_by(from_major, to_major) %>%
    summarize(
      n_changes         = n(),
      n_credit_positions = sum(.credit_usable),
      n_excluded_position = n_changes - n_credit_positions,
      avg_unm_credits   = if (n_credit_positions > 0L) round(mean(.unm_for_mean, na.rm = TRUE), 1) else NA_real_,
      avg_total_credits = if (n_credit_positions > 0L) round(mean(.total_for_mean, na.rm = TRUE), 1) else NA_real_,
      .groups     = "drop"
    ) %>%
    filter(n_changes >= min_n) %>%
    arrange(desc(n_changes))
}


#' Major change pathways broken out by college
#'
#' @param changes Tibble from detect_major_changes()
#' @param opt     Options list; uses opt$min_n (default 3)
#' @return Tibble: student_college, from_major, to_major, n_changes,
#'   avg_unm_credits, avg_total_credits (lag-adjusted attempted hours)
pathways_by_college <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 3L

  changes %>%
    mutate(
      .credit_usable = !is.na(credits_position_valid) & credits_position_valid,
      .unm_for_mean = if_else(.credit_usable, unm_credits_before_change, NA_real_),
      .total_for_mean = if_else(.credit_usable, total_credits_before_change, NA_real_)
    ) %>%
    group_by(student_college, from_major, to_major) %>%
    summarize(
      n_changes         = n(),
      n_credit_positions = sum(.credit_usable),
      n_excluded_position = n_changes - n_credit_positions,
      avg_unm_credits   = if (n_credit_positions > 0L) round(mean(.unm_for_mean, na.rm = TRUE), 1) else NA_real_,
      avg_total_credits = if (n_credit_positions > 0L) round(mean(.total_for_mean, na.rm = TRUE), 1) else NA_real_,
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
      majors_held   = paste(unique(program_name), collapse = " → "),
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
    # CAMPUS_ROLLUP: this is a changer-level curriculum summary, not a
    # delivery metric. Count whether each student took the course once.
    dedup_enrollment(level = "course", group_campus = FALSE) %>%
    count(subject_course, course_title, name = "n_students", sort = TRUE) %>%
    filter(n_students >= min_n) %>%
    mutate(pct_of_changers = round(n_students / n_changers, 3))

  message("[major-changes.R] Found ", nrow(courses), " courses taken during change terms")
  return(courses)
}


#' Courses students were taking in the term before a major switch appeared
#'
#' Answers "is there anything in common in what students were taking right
#' before they switched?" — and, just as importantly, gives the reader a way to
#' see when the answer is no.
#'
#' The anchor term is `prev_term`, not `change_term`. A switch posts to Banner
#' the term AFTER the student actually moves, so `prev_term` is the last term on
#' the old major: the term whose coursework was in progress while the decision
#' was being made. `get_major_change_courses()` uses `change_term` instead and
#' therefore describes the term after the move.
#'
#' Every course is reported against a baseline: its ordinary rate in this
#' population. Note the two denominators differ, and they are not both per
#' student. `pct_before_switch` is per *switch* — of the change events whose
#' prior term has visible coursework, how many included this course.
#' `pct_other_terms` is per *student-term* — of every (student, term) pair in
#' the whole population, switchers and stayers alike, minus the switch-adjacent
#' pairs, how many included this course. A student enrolled eight terms
#' contributes eight to that denominator.
#'
#' Without the baseline the table is just a ranking of large required courses,
#' and any list of common courses looks like a finding. `ratio` near 1 means the
#' course is no more common before a switch than at any other time.
#'
#' This is association only. The comparison does not adjust for when in a
#' career the terms fall, and switches cluster early, so lower-division courses
#' carry an upward bias in `ratio` that has nothing to do with switching.
#'
#' @param changes    Tibble from detect_major_changes(). Pre-filter to the
#'   direction of interest (e.g. departures from a unit) before passing in.
#' @param students   cedar_students data frame.
#' @param population Population tibble (needs `student_id`). Supplies the
#'   comparison universe for the baseline column: every student here, whether or
#'   not they switched, contributes their terms to `pct_other_terms`. Pass the
#'   full analysis population, not the changers — restricting it to switchers
#'   turns the baseline into a within-person comparison, which is a different
#'   (and much smaller) question.
#' @param opt        Options list:
#'   \itemize{
#'     \item \code{min_n} — integer; minimum switches per course (default 5)
#'   }
#' @return Named list:
#'   \itemize{
#'     \item \code{courses} — tibble: subject_course, course_title, n_switches,
#'       pct_before_switch, pct_other_terms, ratio, n_other_terms_with_course.
#'       The two shares are adjacent on purpose; comparing them is the analysis
#'     \item \code{n_switches} — change events with a usable prior term
#'     \item \code{n_switches_with_courses} — of those, how many have class-list
#'       enrollment in that term. This is the denominator of
#'       \code{pct_before_switch}
#'     \item \code{n_students} — distinct students behind those events
#'     \item \code{n_baseline_terms} — student-terms in the comparison baseline
#'   }
get_pre_change_courses <- function(changes, students, population, opt = list()) {
  message("[major-changes.R] Welcome to get_pre_change_courses!")

  min_n <- opt$min_n %||% 5L

  required <- list(
    changes    = c("student_id", "prev_term", "change_term"),
    students   = c("student_id", "term", "subject_course", "course_title",
                   "registration_status_code"),
    population = "student_id"
  )
  inputs <- list(changes = changes, students = students, population = population)
  for (nm in names(required)) {
    absent <- setdiff(required[[nm]], names(inputs[[nm]]))
    if (length(absent) > 0)
      stop("get_pre_change_courses: `", nm, "` is missing required column(s): ",
           paste(absent, collapse = ", "))
  }

  empty_courses <- tibble(
    subject_course            = character(),
    course_title              = character(),
    n_switches                = integer(),
    pct_before_switch         = numeric(),
    pct_other_terms           = numeric(),
    ratio                     = numeric(),
    n_other_terms_with_course = integer()
  )

  events <- changes %>%
    filter(!is.na(prev_term)) %>%
    distinct(student_id, prev_term)

  if (nrow(events) == 0L) {
    message("[major-changes.R] No change events with a usable prior term.")
    return(list(courses = empty_courses, n_switches = 0L,
                n_switches_with_courses = 0L, n_students = 0L,
                n_baseline_terms = 0L))
  }

  # CAMPUS_ROLLUP: the question is whether a student was in the course at all,
  # not where it was delivered, so campus is dropped from the key. One row per
  # student-term-course after this.
  pop_enrl <- students %>%
    filter(student_id %in% population$student_id,
           registration_status_code %in% STATUS_REGISTERED) %>%
    dedup_enrollment(level = "course", group_campus = FALSE) %>%
    select(student_id, term, subject_course, course_title)

  pre_switch <- pop_enrl %>%
    semi_join(events, by = c("student_id", "term" = "prev_term"))

  # Events with no class-list row in their prior term describe no coursework at
  # all, so they are not part of the denominator. Reported back to the caller
  # rather than dropped quietly — if the gap is large, every percentage here
  # rests on a smaller group than the switch count suggests.
  n_events        <- nrow(events)
  n_events_seen   <- nrow(distinct(pre_switch, student_id, term))
  n_students      <- n_distinct(events$student_id)

  if (n_events_seen == 0L) {
    message("[major-changes.R] No class-list enrollment found in any prior term.")
    return(list(courses = empty_courses, n_switches = n_events,
                n_switches_with_courses = 0L, n_students = n_students,
                n_baseline_terms = 0L))
  }

  # CAMPUS_ROLLUP: same key as pop_enrl above, and the baseline below has to
  # match it — two shares cut differently are not comparable.
  before <- pre_switch %>%
    count(subject_course, course_title, name = "n_switches") %>%
    mutate(pct_before_switch = n_switches / n_events_seen)

  # Baseline: the whole population's other terms — stayers included, not just
  # the students who switched. The question it answers is "how common is this
  # course in an ordinary term here", which needs the ordinary students in it.
  # Both switch-adjacent terms are held out — prev_term because it is the term
  # being described, change_term because by then the student is already recorded
  # in the new major.
  event_terms <- bind_rows(
    events  %>% transmute(student_id, term = prev_term),
    changes %>% filter(!is.na(change_term)) %>% transmute(student_id, term = change_term)
  ) %>%
    distinct()

  other_terms      <- pop_enrl %>% anti_join(event_terms, by = c("student_id", "term"))
  n_baseline_terms <- nrow(distinct(other_terms, student_id, term))

  # CAMPUS_ROLLUP: matches the pre-switch key above.
  baseline <- other_terms %>%
    count(subject_course, name = "n_other_terms_with_course") %>%
    mutate(pct_other_terms = n_other_terms_with_course / n_baseline_terms)

  courses <- before %>%
    left_join(baseline, by = "subject_course") %>%
    # A course absent from the baseline join genuinely appeared in no other
    # term of these students' records — a real zero, not a missing join.
    mutate(
      n_other_terms_with_course = coalesce(n_other_terms_with_course, 0L),
      pct_other_terms           = coalesce(pct_other_terms, 0),
      # Left NA rather than infinite when the course never appears outside a
      # pre-switch term. There is no multiple to report against zero. Computed
      # before rounding so the multiple is not a ratio of two rounded shares.
      ratio = if_else(pct_other_terms > 0,
                      round(pct_before_switch / pct_other_terms, 2),
                      NA_real_),
      pct_before_switch = round(pct_before_switch, 4),
      pct_other_terms   = round(pct_other_terms, 4)
    ) %>%
    filter(n_switches >= min_n) %>%
    # The two shares sit next to each other because comparing them IS the
    # analysis. They used to be separated by the raw baseline count, which put a
    # number between the only two figures a reader is meant to hold together.
    select(subject_course, course_title, n_switches,
           pct_before_switch, pct_other_terms, ratio,
           n_other_terms_with_course) %>%
    arrange(desc(n_switches), subject_course)

  message("[major-changes.R] ", nrow(courses), " courses met the threshold across ",
          n_events_seen, " of ", n_events, " switches; baseline is ",
          n_baseline_terms, " other student-terms")

  list(
    courses                 = courses,
    n_switches              = n_events,
    n_switches_with_courses = n_events_seen,
    n_students              = n_students,
    n_baseline_terms        = n_baseline_terms
  )
}
