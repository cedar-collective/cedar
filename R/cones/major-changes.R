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
#'   unm_credits_before_change, total_credits_before_change (lag-adjusted attempted
#'   hours, UNM-only and UNM + transfer), unm_credits_at_change,
#'   total_credits_at_change (raw cumulative attempted as recorded at change_term),
#'   student_college, student_campus, dept_code, student_level, degree
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
      # Lag-adjusted credits. A major change posts to Banner the term *after* the
      # student actually switches, so the cumulative credits recorded AT change_term
      # overstate credits-at-decision by roughly one term's load (~12-18). The prior
      # term's cumulative total (lag) is "credits attempted as of the last term before
      # the change posted" — the decision-point figure. Because these columns are
      # running totals, lag() subtracts exactly that student's lagged-term load rather
      # than a flat estimate. Both UNM-only and total (incl. transfer) are carried so
      # callers can show how far along switchers really were on either basis.
      prev_unm_credits   = lag(inst_credits_attempted),
      prev_total_credits = lag(overall_credits_attempted),
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
      # *_before_change = lag-adjusted (decision-point) credits, primary for display.
      # *_at_change     = raw cumulative attempted as Banner recorded it at change_term.
      # unm_* = UNM-only attempted; total_* = UNM + transfer attempted.
      unm_credits_before_change   = prev_unm_credits,
      total_credits_before_change = prev_total_credits,
      unm_credits_at_change       = inst_credits_attempted,
      total_credits_at_change     = overall_credits_attempted,
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
#' @return Tibble: to_major, avg_unm_credits, median_unm_credits,
#'   avg_total_credits, median_total_credits, n_changes, n_students.
#'   Credits are lag-adjusted attempted hours (see detect_major_changes()).
avg_credits_before_major <- function(changes, opt = list()) {
  min_n <- opt$min_n %||% 5L

  changes %>%
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
    group_by(from_major, to_major) %>%
    summarize(
      n_changes         = n(),
      avg_unm_credits   = round(mean(unm_credits_before_change,   na.rm = TRUE), 1),
      avg_total_credits = round(mean(total_credits_before_change, na.rm = TRUE), 1),
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
    group_by(student_college, from_major, to_major) %>%
    summarize(
      n_changes         = n(),
      avg_unm_credits   = round(mean(unm_credits_before_change,   na.rm = TRUE), 1),
      avg_total_credits = round(mean(total_credits_before_change, na.rm = TRUE), 1),
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
    dedup_enrollment(level = "course") %>%
    count(subject_course, course_title, name = "n_students", sort = TRUE) %>%
    filter(n_students >= min_n) %>%
    mutate(pct_of_changers = round(n_students / n_changers, 3))

  message("[major-changes.R] Found ", nrow(courses), " courses taken during change terms")
  return(courses)
}


# ── Declaration context ───────────────────────────────────────────────────────

#' Snapshot of credits and prior course history at the moment students first
#' declared the focal program
#'
#' @param programs   cedar_programs filtered to population students
#' @param students   cedar_students (full, will be filtered internally)
#' @param population Population tibble from build_population() — needs
#'   first_unm_term for terms-to-declaration calculation
#' @param focal_subjects Character vector of subject codes that belong to the
#'   focal unit (e.g. c("HIST") for a History population). Used to split
#'   prior courses into in-unit vs outside.
#' @param opt        Options list; uses opt$min_n (default 5)
#' @return Named list: credits (summary tibble), courses_focal, courses_other,
#'   n_declarers, focal_subjects
get_declaration_context <- function(programs, students, population,
                                    focal_subjects = character(0),
                                    opt = list()) {
  min_n <- opt$min_n %||% 5L

  focal_ids <- unique(population$student_id)

  # First declared term per student: earliest term as a non-pre-major Major
  first_decl <- programs %>%
    filter(student_id %in% focal_ids,
           program_type %in% c("Major", "Second Major"),
           !is_pre_major) %>%
    group_by(student_id) %>%
    slice_min(term, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    # Both on the attempted basis: inst_* = UNM-only, overall_* = UNM + transfer.
    # Attempted (not earned) keeps this consistent with the major-change credit
    # figures and avoids deflation from W/F grades.
    select(student_id,
           decl_term       = term,
           inst_credits    = inst_credits_attempted,
           overall_credits = overall_credits_attempted)

  if (nrow(first_decl) == 0) {
    message("[major-changes.R] get_declaration_context: no declared students found.")
    return(NULL)
  }

  n_declarers <- nrow(first_decl)
  message("[major-changes.R] get_declaration_context: ", n_declarers, " declarers.")

  # Terms from first UNM enrollment to declaration
  if ("first_unm_term" %in% names(population)) {
    first_decl <- first_decl %>%
      left_join(population %>% select(student_id, first_unm_term),
                by = "student_id") %>%
      mutate(terms_to_decl = term_diff(first_unm_term, decl_term, include_summer = FALSE))
  }

  # Join pipeline classification from population (origin + entry_method + entry_status)
  pop_cols <- intersect(c("origin", "entry_method", "entry_status"), names(population))
  if (length(pop_cols) > 0) {
    first_decl <- first_decl %>%
      left_join(population %>% select(student_id, all_of(pop_cols)), by = "student_id") %>%
      mutate(pipeline = case_when(
        origin       == "transfer"      ~ "Transfer",
        entry_method == "switched_in"   ~ "Switched in (UNM)",
        entry_method == "first_program" ~ "Direct entry (UNM)",
        entry_method == "unclear"       ~ "Unclear",
        TRUE                            ~ "Other"
      ),
      entry_status_label = case_when(
        entry_status == "pre_major" ~ "First seen as pre-major",
        entry_status == "major" ~ "First seen as full major",
        TRUE ~ "First status unknown"
      ))
  }

  # Credit and terms summary
  credits <- first_decl %>%
    summarize(
      n               = n(),
      mean_inst       = round(mean(inst_credits,    na.rm = TRUE), 1),
      median_inst     = median(inst_credits,    na.rm = TRUE),
      mean_overall    = round(mean(overall_credits, na.rm = TRUE), 1),
      median_overall  = median(overall_credits, na.rm = TRUE),
      mean_terms      = if ("terms_to_decl" %in% names(.))
                          round(mean(terms_to_decl, na.rm = TRUE), 1) else NA_real_,
      median_terms    = if ("terms_to_decl" %in% names(.))
                          median(terms_to_decl, na.rm = TRUE) else NA_real_
    )

  # Pipeline breakdown: n, avg/med UNM credits, avg/med total credits, avg terms to declaration
  pipeline_summary <- if ("pipeline" %in% names(first_decl)) {
    first_decl %>%
      group_by(pipeline, entry_status_label) %>%
      summarize(
        n               = n(),
        mean_inst       = round(mean(inst_credits,      na.rm = TRUE), 0),
        median_inst     = round(median(inst_credits,    na.rm = TRUE), 0),
        mean_overall    = round(mean(overall_credits,   na.rm = TRUE), 0),
        median_overall  = round(median(overall_credits, na.rm = TRUE), 0),
        mean_terms      = if ("terms_to_decl" %in% names(.))
                            round(mean(terms_to_decl, na.rm = TRUE), 1) else NA_real_,
        .groups         = "drop"
      ) %>%
      arrange(desc(n))
  } else NULL

  # All courses taken in terms <= first declaration term
  prior_courses <- students %>%
    inner_join(first_decl %>% select(student_id, decl_term),
               by = "student_id") %>%
    filter(term <= decl_term,
           registration_status_code %in% STATUS_REGISTERED) %>%
    dedup_enrollment(level = "course") %>%
    mutate(subject_code = sub(" .*", "", subject_course),
           in_unit      = subject_code %in% focal_subjects)

  make_counts <- function(df) {
    df %>%
      count(subject_course, course_title, name = "n_students", sort = TRUE) %>%
      filter(n_students >= min_n) %>%
      mutate(pct = round(n_students / n_declarers, 3)) %>%
      head(50)
  }

  list(
    credits          = credits,
    pipeline_summary = pipeline_summary,
    courses_focal    = make_counts(filter(prior_courses, in_unit)),
    courses_other    = make_counts(filter(prior_courses, !in_unit)),
    n_declarers      = n_declarers
  )
}


# ── GE Conversion ─────────────────────────────────────────────────────────────

#' Which courses in the focal unit converted students to declaring the major?
#'
#' For each course in focal_subjects, counts how many students (a) ever took the
#' course before declaring and (b) went on to declare. Returns the conversion rate.
#'
#' @param students       cedar_students data frame
#' @param programs       cedar_programs data frame
#' @param population     Population tibble from build_population()
#' @param focal_subjects Character vector of subject codes for the unit (e.g. c("HIST"))
#' @param opt            Options list:
#'   \itemize{
#'     \item \code{min_n}  — integer; min students who took course (default 10)
#'     \item \code{levels} — character vector; course levels to include:
#'                           "lower", "upper", "grad" (default c("lower", "upper"))
#'   }
#' @return Tibble: subject_course, course_title, course_level,
#'   n_took, n_declared, pct_declared; sorted by pct_declared descending
# Heatmap of courses taken by population students in the semesters before their
# first appearance in the focal major (pre-major or declared). Returns a named
# list with in_unit (courses from focal subjects) and out_unit (other depts).
#
# Each row in the output tibbles is one (course, lag) cell: lag=1 means the
# term immediately before entry, lag=2 two terms before, etc. Summers are
# excluded from the lag count by default so T-1 is always a fall or spring.
#
# Metrics:
#   n_became_major — population students who took this course at this lag
#   n_in_course    — ALL students enrolled in that course in those same terms
#   pct_of_majors  — n_became_major / total population (how common in cohort)
#   pct_converted  — n_became_major / n_in_course (gateway signal)
get_entry_heatmap <- function(students, programs, population,
                               focal_subjects = character(0),
                               opt = list()) {
  max_lag     <- opt$max_lag     %||% 3L
  min_n       <- opt$min_n       %||% 5L
  incl_summer <- opt$incl_summer %||% FALSE

  validate_population(population, "get_entry_heatmap")
  focal_ids <- unique(population$student_id)
  n_majors  <- length(focal_ids)
  message("[entry_heatmap] focal_ids: ", n_majors, " | focal_subjects: ",
          paste(focal_subjects, collapse = ", "))
  if (n_majors == 0L) return(NULL)

  # Use first_unit_term from population — already scoped to the focal programs.
  # Re-querying programs$min(term) would pick up ALL of a student's program history,
  # not just the focal major, so switchers from other programs would get lag terms
  # from their previous major rather than their Geography (or focal) entry point.
  entry_terms <- population %>%
    select(student_id, entry_term = first_unit_term) %>%
    filter(!is.na(entry_term))

  message("[entry_heatmap] entry_terms rows: ", nrow(entry_terms),
          " | unique entry_terms: ", paste(sort(unique(entry_terms$entry_term)), collapse = ", "))

  if (nrow(entry_terms) == 0L) {
    message("[entry_heatmap] first_unit_term is missing or all NA in population")
    return(NULL)
  }

  # Ordered term sequence from student records, summers optionally excluded
  all_terms <- sort(unique(students$term))
  if (!incl_summer) all_terms <- all_terms[all_terms %% 100L != 60L]
  term_pos  <- setNames(seq_along(all_terms), as.character(all_terms))

  message("[entry_heatmap] all_terms (", length(all_terms), "): ",
          paste(head(all_terms, 5), collapse = ", "), " ... ", paste(tail(all_terms, 3), collapse = ", "))

  # For each student, map entry_term to a position in all_terms.
  # If entry_term is a summer (excluded from all_terms) or predates the data,
  # snap forward to the nearest available term so those students aren't lost.
  snap_to_all_terms <- function(term_vec) {
    vapply(term_vec, function(t) {
      if (as.character(t) %in% names(term_pos)) return(t)
      # Find the smallest term in all_terms >= t
      candidates <- all_terms[all_terms >= t]
      if (length(candidates)) candidates[1L] else NA_integer_
    }, integer(1))
  }

  entry_pos <- entry_terms %>%
    mutate(
      snapped_entry = snap_to_all_terms(entry_term),
      pos           = term_pos[as.character(snapped_entry)]
    ) %>%
    filter(!is.na(pos), pos > 1L)

  message("[entry_heatmap] entry_pos after filtering: ", nrow(entry_pos),
          " (dropped ", nrow(entry_terms) - nrow(entry_pos), " students with entry_term not in students data or at pos 1)")

  lag_key <- lapply(seq_len(max_lag), function(l) {
    entry_pos %>%
      mutate(lag = l, prior_pos = pos - l) %>%
      filter(prior_pos >= 1L) %>%
      mutate(prior_term = all_terms[prior_pos]) %>%
      select(student_id, prior_term, lag)
  }) %>%
    bind_rows()

  message("[entry_heatmap] lag_key rows: ", nrow(lag_key))

  if (nrow(lag_key) == 0L) {
    message("[entry_heatmap] no prior terms found (population may all be in first available term)")
    return(NULL)
  }

  # Population students' enrollments at their lag terms
  pop_enrl_raw <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    select(student_id, term, subject_course, course_title) %>%
    inner_join(lag_key, by = c("student_id", "term" = "prior_term")) %>%
    mutate(subj = sub(" .*", "", subject_course))

  message("[entry_heatmap] pop_enrl_raw rows: ", nrow(pop_enrl_raw),
          " (unique students: ", n_distinct(pop_enrl_raw$student_id), ")")

  if (nrow(pop_enrl_raw) == 0L) {
    message("[entry_heatmap] no enrollment records matched population lag terms")
    message("[entry_heatmap] lag prior_terms: ", paste(head(sort(unique(lag_key$prior_term)), 6), collapse = ", "))
    return(NULL)
  }

  # Unique (term, course, lag) cells covered by population — denominator source
  lag_term_course <- pop_enrl_raw %>% distinct(term, subject_course, lag)

  # All students enrolled in those same (term, course) slots → n_in_course
  n_in_course_df <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    select(student_id, term, subject_course) %>%
    inner_join(lag_term_course, by = c("term", "subject_course")) %>%
    group_by(subject_course, lag) %>%
    summarize(n_in_course = n_distinct(student_id), .groups = "drop")

  # Deduplicate to one row per (population student, course, lag)
  pop_enrl <- pop_enrl_raw %>%
    group_by(student_id, subject_course, lag, subj) %>%
    summarize(course_title = first(course_title), .groups = "drop")

  summarize_hm <- function(df) {
    if (nrow(df) == 0L) return(tibble())
    df %>%
      group_by(subject_course, lag) %>%
      summarize(
        course_title   = first(course_title),
        n_became_major = n_distinct(student_id),
        .groups        = "drop"
      ) %>%
      left_join(n_in_course_df, by = c("subject_course", "lag")) %>%
      mutate(
        pct_of_majors = round(n_became_major / n_majors, 3),
        pct_converted = round(n_became_major / n_in_course, 3),
        lag_label     = paste0("T-", lag)
      ) %>%
      filter(n_became_major >= min_n)
  }

  in_unit  <- if (length(focal_subjects) > 0L)
    summarize_hm(filter(pop_enrl, subj %in% focal_subjects))
  else
    summarize_hm(pop_enrl)

  out_unit <- if (length(focal_subjects) > 0L)
    summarize_hm(filter(pop_enrl, !subj %in% focal_subjects))
  else
    tibble()

  list(in_unit = in_unit, out_unit = out_unit, n_majors = n_majors)
}
