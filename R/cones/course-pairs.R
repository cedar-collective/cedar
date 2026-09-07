# course-pairs.R — Ordered A→B course sequences for a student population
#
# Answers one question: of the population students who took course A, what
# fraction later took course B, and how many terms apart?
#
# Split out of R/cones/pathway.R.
#
# Campus policy (see AGENTS.md): this cone scopes by campus but deliberately
# does NOT put campus in the pair key. A pair is a statement about one student
# taking two courses, and those can legitimately sit on different campuses — an
# Albuquerque student taking the follow-on online is an ordinary path.
#
# Depends on: assign_relative_terms() (branches/relative-terms.R),
#             cedar_filter_campus() (lists/campuses.R)

#' Get Ordered Course Pairs for a Student Population
#'
#' Identifies the most common ordered course sequences — cases where a
#' student took course A in one term and course B in a later term. This
#' captures the implicit prerequisite chains that students actually follow,
#' as opposed to the formally catalogued ones.
#'
#' Only courses taken by at least `opt$min_n` population students are included.
#' Only pairs where the A→B pattern occurred at least `opt$min_pair_n` times
#' are returned.
#'
#' @param students Data frame. The `cedar_students` table.
#' @param cohort Data frame. Output of `build_population()`. Defines the student
#'   population to analyze — a program-based filter, not an entry-term cohort.
#' @param opt List of options:
#'   \describe{
#'     \item{`min_n`}{Integer. Minimum population students who took course A
#'       for it to be included as a pair source. Default: `15`.}
#'     \item{`min_pair_n`}{Integer. Minimum population students exhibiting the
#'       A→B pattern for the pair to appear in results. Default: `10`.}
#'     \item{`max_term_gap`}{Integer. Maximum number of relative terms between
#'       A and B. Default: `4` (pairs more than 4 terms apart are unlikely to
#'       be meaningfully sequential).}
#'     \item{`campus`}{Character vector of course-delivery campus codes. Scopes
#'       which enrollment rows are counted. This is the campus that taught the
#'       section, not the student's home campus — the two differ on roughly 28%
#'       of enrollment rows, so a population scoped by home campus still pulls in
#'       branch-delivered course rows without it. NULL includes every campus;
#'       pass NULL only for a deliberate UNM-wide aggregate.}
#'     \item{`subject_code`}{Character vector. Restrict to courses in these
#'       subjects. Optional.}
#'     \item{`censor_term`}{Integer term code of the last complete data term.
#'       When supplied, A-side enrollments (and the `pct_a_to_b` denominator)
#'       are restricted to terms with `max_term_gap` complete regular terms of
#'       follow-up, so recently-taken courses don't show deflated follow-on
#'       rates purely because the data ends (right-censoring). Optional;
#'       NULL preserves uncensored behavior.}
#'   }
#'
#' @return Data frame sorted by `n_students` descending, with columns:
#'   \describe{
#'     \item{`course_a`}{First course in the pair.}
#'     \item{`course_b`}{Second course (taken after A).}
#'     \item{`n_students`}{Population students who took A and then took B.}
#'     \item{`n_took_a`}{Total population students who took course A (denominator).}
#'     \item{`pct_a_to_b`}{`n_students / n_took_a`: of students who took A,
#'       what fraction went on to take B?}
#'     \item{`median_term_gap`}{Median number of relative terms between taking
#'       A and taking B.}
#'   }
#'
#' @examples
#' \dontrun{
#' population <- build_population(cedar_programs,
#'                            opt = list(type = "health",
#'                                       health_programs = "Radiologic Sciences"))
#' pairs <- get_course_pairs(cedar_students, population, opt = list())
#' # Top transitions out of BIOL 2310
#' pairs %>% filter(course_a == "BIOL 2310")
#' }
#'
#' @seealso [get_course_timing()]
#' @export
get_course_pairs <- function(students, population, opt = list()) {

  message("[pathway.R] Computing ordered course pairs...")

  # --- Read options ---
  min_n        <- opt$min_n        %||% 15L   # minimum students in course A to include it
  min_pair_n   <- opt$min_pair_n   %||% 10L   # minimum A→B occurrences to show the pair
  max_term_gap <- opt$max_term_gap %||% 4L    # ignore pairs more than this many terms apart
  pop_ids      <- unique(population$student_id)

  cedar_require_campus(students, "pathway.R get_course_pairs")

  # --- Step 1: Pull registered enrollment rows for population students ---
  enrolled <- students %>%
    filter(
      student_id %in% pop_ids,
      registration_status_code %in% STATUS_REGISTERED
    ) %>%
    cedar_filter_campus(opt$campus, fn = "get_course_pairs")

  if (!is.null(opt$level) && length(opt$level) > 0) {
    enrolled <- enrolled %>% filter(level %in% opt$level)
  }

  # One row per student per course per term (deduplicated).
  #
  # Campus scopes which rows enter the self-join but is deliberately NOT part of
  # the pair key. A pair is a statement about one student taking two courses, and
  # those two can legitimately sit on different campuses — an Albuquerque student
  # taking the follow-on online through EA is an ordinary path, not a data error.
  # Forcing a single campus onto the row would either drop those pairs or label
  # them with a campus only half the pair belongs to. The scope is reported
  # alongside the table instead. This is the deliberate exception the campus
  # policy allows; see AGENTS.md.
  enrolled <- enrolled %>%
    select(student_id, term, subject_course) %>%
    distinct()

  # Optional subject filter — applied before the self-join to keep it small
  if (!is.null(opt$subject_code) && length(opt$subject_code) > 0) {
    enrolled <- enrolled %>%
      filter(sub(" .*", "", subject_course) %in% opt$subject_code)
  }

  # --- Step 2: Assign relative term numbers ---
  # Same logic as get_course_timing: summer doesn't advance the counter.
  enrolled <- assign_relative_terms(enrolled, include_summer = FALSE)

  # --- Step 2b: Observation-window censoring (A side only) ---
  # An A-enrollment only gets a fair chance to show a follow-on B if the data
  # contains max_term_gap complete regular terms after it. Without this,
  # recently-taken courses drag pct_a_to_b down purely because the data ends
  # (right-censoring), not because students skip the follow-on.
  # opt$censor_term = last complete data term (the Pathways module passes it);
  # A-side rows — and the pct denominator — are restricted to calendar terms
  # with a full follow-up window. B-side rows are never censored.
  # NULL censor_term (e.g. standalone RStudio use) preserves old behavior.
  a_pool <- enrolled
  a_boundary <- NULL
  if (!is.null(opt$censor_term) && !is.na(opt$censor_term)) {
    a_boundary <- pathways_observation_boundary(opt$censor_term, max_term_gap)
    a_pool <- a_pool %>% filter(term <= a_boundary)
    message("[pathway.R] Censoring A-side enrollments after ", a_boundary,
            " (", max_term_gap, " regular terms of follow-up required; data through ",
            opt$censor_term, ").")
  }

  # --- Step 3: Pre-filter to qualifying course_a candidates before the self-join ---
  # This is the key scaling fix. A full enrolled × enrolled self-join is O(N²) in
  # enrollment rows. Computing n_took_a first and restricting the left side to
  # qualifying courses reduces the left factor significantly — typically 5–10× for
  # large populations where most courses fall below the min_n threshold.
  # The right side (course_b) stays unrestricted: any course can follow a qualifying A.
  # n_took_a comes from the censored A pool so the pct_a_to_b denominator matches
  # the numerator's observation window.
  # CAMPUS_ROLLUP: course pairs describe institution-wide student trajectories
  # within the selected campus scope, not performance of a delivery campus.
  n_took_a <- a_pool %>%
    group_by(subject_course) %>%
    summarize(n_took_a = n_distinct(student_id), .groups = "drop") %>%
    filter(n_took_a >= min_n)

  enrolled_a <- a_pool %>%
    filter(subject_course %in% n_took_a$subject_course)

  message("[pathway.R] Pair search: ", nrow(enrolled_a), " A-side rows × ",
          nrow(enrolled), " B-side rows (", n_distinct(enrolled_a$subject_course),
          " qualifying courses at min_n = ", min_n, ").")

  # --- Step 4: Find all ordered pairs (A, B) where B is taken after A ---
  # Only courses meeting min_n appear on the A side; all courses can appear on B.
  # max_term_gap prevents counting distant pairs like "ENGL 1110 → HIST 4800"
  # (8 terms apart) as meaningful sequences.
  pairs <- enrolled_a %>%
    rename(course_a = subject_course, term_a = relative_term) %>%
    inner_join(
      enrolled %>% rename(course_b = subject_course, term_b = relative_term),
      by = "student_id", relationship = "many-to-many"
    ) %>%
    filter(
      term_b > term_a,                       # B is strictly after A
      term_b - term_a <= max_term_gap,        # not too far apart
      course_a != course_b                   # not the same course twice
    ) %>%
    select(student_id, course_a, course_b, term_a, term_b) %>%
    distinct()

  # --- Step 5: Aggregate pair counts and compute the A→B rate ---
  # n_students = distinct students who took A and then took B
  # pct_a_to_b = of everyone who took A, what fraction also took B afterward?
  # median_term_gap = typical number of terms between taking A and taking B
  result <- pairs %>%
    group_by(course_a, course_b) %>%
    summarize(
      n_students      = n_distinct(student_id),
      median_term_gap = median(term_b - term_a),
      .groups = "drop"
    ) %>%
    inner_join(n_took_a %>% rename(course_a = subject_course), by = "course_a") %>%
    mutate(pct_a_to_b = round(n_students / n_took_a, 3)) %>%
    filter(n_students >= min_pair_n) %>%
    arrange(desc(n_students)) %>%
    select(course_a, course_b, n_students, n_took_a, pct_a_to_b, median_term_gap)

  message("[pathway.R] Returning ", nrow(result), " course pairs.")

  attr(result, "pair_meta") <- list(
    n_qualifying = n_distinct(enrolled_a$subject_course),
    n_a_rows     = nrow(enrolled_a),
    n_b_rows     = nrow(enrolled),
    min_n        = min_n,
    min_pair_n   = min_pair_n,
    n_pairs      = nrow(result),
    a_boundary   = a_boundary
  )
  return(result)
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
