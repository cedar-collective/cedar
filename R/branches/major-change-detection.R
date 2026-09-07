# major-change-detection.R — Major change detection (branch)
#
# Detects when students change their primary major across terms and attaches
# the credit position at each change. This is the shared computation that the
# major-change cones consume: every one of them takes the `changes` tibble this
# file produces, so it belongs below them rather than beside them.
#
# Split out of R/cones/major-changes.R. Callers and return contract unchanged.
#
# Depends on: STATUS_REGISTERED (lists/status_codes.R),
#             build_credit_timeline() (branches/credit-timeline.R),
#             term_diff() (trunk/utils.R)

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
#' @param term_credits Optional. `cedar_student_term_credits`. Supplies the
#'   credit position at each change via [build_credit_timeline()]. When NULL the
#'   credit columns are returned as NA rather than being read off the frozen
#'   cumulative columns on `programs` — see the note below.
#' @param opt      Options list:
#'   \itemize{
#'     \item \code{campus}  — character; filter by student_campus
#'     \item \code{college} — character; filter by student_college
#'     \item \code{dept_code} — character; filter by dept_code
#'     \item \code{observation_end_term} — integer; exclude program records
#'       after the settled longitudinal enrollment edge
#'   }
#' @return Tibble with one row per major change event:
#'   student_id, change_term, prev_term, from_major, to_major,
#'   unm_credits_before_change, total_credits_before_change (credits entering the
#'   term before the change posted, UNM-only and UNM + transfer),
#'   credits_position_valid, student_college, student_campus, dept_code,
#'   student_level, degree
#'
#' @section Why credits do not come from cedar_programs:
#'
#' This function used to read `inst_credits_attempted` / `overall_credits_attempted`
#' at the change term and lag them by one term, on the stated reasoning that
#' "because these columns are running totals, lag() subtracts exactly that
#' student's lagged-term load". They are not running totals. Academic Studies
#' stamps the student's total as of the pull onto every historical row, so within
#' one full re-pull the value moves across a student's own terms only 16% of the
#' time. `lag()` on a frozen column subtracts zero, and the reported
#' "credits before the change" was approximately the student's FINAL credit
#' total — overstating the position at a student's first term by a median of 84
#' credits. See the field reliability contract in AGENTS.md.
detect_major_changes <- function(programs, population = NULL, opt = list(),
                                 term_credits = NULL) {

  message("[major-change-detection.R] Welcome to detect_major_changes!")

  majors <- programs %>%
    filter(program_type == "Major", !is.na(program_name), program_name != "")

  observation_end <- opt$observation_end_term
  if (!is.null(observation_end)) {
    majors <- majors %>% filter(term <= .env$observation_end)
  }

  # Cohort filter
  if (!is.null(population)) {
    majors <- majors %>% filter(student_id %in% population$student_id)
    message("[major-change-detection.R] Cohort applied: ", n_distinct(majors$student_id), " students")
  }

  # opt filters
  if (!is.null(opt$campus)  && length(opt$campus)  > 0)
    majors <- majors %>% filter(student_campus  %in% opt$campus)
  if (!is.null(opt$college) && length(opt$college) > 0)
    majors <- majors %>% filter(student_college %in% opt$college)
  if (!is.null(opt$dept_code) && length(opt$dept_code) > 0)
    majors <- majors %>% filter(dept_code %in% opt$dept_code)

  message("[major-change-detection.R] Analyzing ", n_distinct(majors$student_id), " students")

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
      student_college,
      student_campus,
      dept_code,
      student_level,
      degree
    ) %>%
    arrange(student_id, change_term)

  # Credit position at the decision point. A major change posts to Banner the
  # term AFTER the student actually switches, so the figure that describes the
  # decision is the credits they had entering `prev_term`, not `change_term`.
  changes <- .attach_change_credits(changes, term_credits, programs)

  message("[major-change-detection.R] Detected ", nrow(changes), " change events across ",
          n_distinct(changes$student_id), " students")
  return(changes)
}


# Attach the credit position at the decision point to change events.
#
# Kept out of the main pipeline above so the change-detection logic stays
# readable, and so the NULL path is obviously a deliberate "we cannot know"
# rather than a missing join. Returns NA credit columns when term_credits is
# absent: a caller that has not supplied the trustworthy series gets no number,
# never a number read off the frozen columns.
.attach_change_credits <- function(changes, term_credits, programs) {
  na_cols <- function(d) {
    d$unm_credits_before_change   <- NA_real_
    d$total_credits_before_change <- NA_real_
    d$credits_position_valid      <- NA
    d
  }
  if (is.null(term_credits) || nrow(changes) == 0) {
    if (is.null(term_credits)) {
      message("[major-change-detection.R] No term_credits supplied — credit columns will be NA. ",
              "Pass term_credits = cedar_student_term_credits for credit positions.")
    }
    return(na_cols(changes))
  }

  timeline <- build_credit_timeline(
    term_credits, programs,
    opt = list(student_ids = unique(changes$student_id))
  )
  if (nrow(timeline) == 0) return(na_cols(changes))

  # Joined on prev_term — the last term the student was still in the old major —
  # and taking the position AFTER it. That is how far along they were when they
  # switched, which is what the original lag was reaching for; the change itself
  # does not post to Banner until the following term.
  changes %>%
    dplyr::left_join(
      timeline %>% dplyr::select(
        student_id, prev_term = term,
        unm_credits_before_change   = unm_credits_after,
        total_credits_before_change = total_credits_after,
        credits_position_valid      = timeline_valid),
      by = c("student_id", "prev_term")
    )
}
