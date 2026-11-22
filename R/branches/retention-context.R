# retention-context.R — Shared retention computation (branch)
#
# Builds the context every retention question needs — the enrolled and
# graduated lookups, the observation edge, and the per-student retained_1 ..
# retained_n flags — and nothing that answers a question with it.
#
# Retention definition: a student is retained at T+N if they are:
#   (a) enrolled anywhere at UNM in the target term, OR
#   (b) recorded as having graduated between the anchor and target term.
# Enrolled is `cedar_student_terms$enrolled`: registered, or registered and
# withdrawn after census (a late drop). CEDAR's one definition of an enrolled
# student-term, the same column Pathways Roadblocks reads; this file never
# re-derives it from status codes (ISSUES.md I44; student-terms.md).
# Graduates are not counted as stop-outs — they successfully completed.
#
# Cells where the target term is beyond the available data are returned as NA,
# not 0%. A 0% would be misleading for recent terms where students could not yet
# have met the criterion.
#
# Campus policy (see AGENTS.md): .filter_campus() scopes the *cohort*, but
# .build_enrolled_lookup() is deliberately UNM-wide, because a student who
# transfers between campuses has been retained, not lost. That is the one
# intentional campus-blind aggregate in the retention code.
#
# Split out of R/cones/course-retention.R: the three get_*_retention_* cones all
# consume what this file produces, so it belongs below them rather than beside
# them.
#
# Depends on: advance_term() (branches/cedar-terms.R), cedar_student_terms
#             (branches/student-terms.R, built in the transform)

# =============================================================================
# Internal helpers
# =============================================================================

# Every entry point in this file groups by campus, so a students frame without
# a campus column cannot produce a correct result. Failing here is deliberate:
# quietly dropping campus from the grouping is precisely the silent-wrongness
# this policy exists to prevent (see AGENTS.md). Callers with a genuinely
# campus-free frame should add the column before calling.
.require_campus <- function(df, fn) {
  cedar_require_campus(df, paste0("course-retention.R ", fn))
}

# Restrict a students frame to the requested campuses.
#
# Per the CEDAR-wide campus policy in AGENTS.md, a course cohort is always
# campus-scoped: a student taking ENGL 1120 at Gallup is not in the same cohort
# as one taking it in Albuquerque. NULL means every campus, which callers should
# only pass when they intend a UNM-wide aggregate.
.filter_campus <- function(df, campus = NULL) {
  cedar_filter_campus(df, campus, fn = "course-retention.R")
}

.retention_observation_edge <- function(opt) {
  explicit <- opt[["observation_end_term"]]
  if (!is.null(explicit) && length(explicit) > 0) return(as.integer(explicit[[1]]))
  cedar_longitudinal_edge(opt[["data_edges"]], grade_dependent = FALSE)
}

.scope_retention_history <- function(df, observation_end) {
  if (is.null(df) || is.null(observation_end) || !"term" %in% names(df)) return(df)
  dplyr::filter(df, term <= .env$observation_end)
}

# Pre-build the "is enrolled at term T" lookup from the student-term table.
# Returns a tibble with (student_id, term) for every enrolled student-term.
#
# DELIBERATELY UNM-WIDE, and the one place in this file that is. Retention asks
# whether a student was still enrolled *anywhere at UNM*, so a student who takes
# a course at Gallup and later enrols in Albuquerque is retained, not a stop-out.
# Narrowing this lookup to the cohort's campus would silently redefine retention
# as "stayed on the same campus" and count every transfer as attrition.
# The cohort is campus-scoped (see .filter_campus); the outcome is not.
.build_enrolled_lookup <- function(student_terms) {
  missing <- setdiff(c("student_id", "term", "enrolled"), names(student_terms))
  if (length(missing) > 0L) {
    stop("[retention-context.R] student_terms is missing column(s): ",
         paste(missing, collapse = ", "), ". Pass cedar_student_terms.")
  }
  student_terms %>%
    filter(enrolled) %>%
    distinct(student_id, term = as.integer(term))
}

#' The degrees that count as awarded: one row per student and term
#'
#' CEDAR's one rule for "holds a degree" in a follow-up: the row's
#' `graduation_status` is "Awarded". A degree on hold, an application still
#' pending and a cleared record are not degrees (pending_degrees() reads the
#' applications). A degrees table with no status column is all awards.
#'
#' @param degrees `cedar_degrees`, or NULL (no awards).
#' @return A tibble of `student_id` and `degree_term` (integer).
awarded_degrees <- function(degrees) {
  if (is.null(degrees)) return(tibble::tibble(student_id = character(), degree_term = integer()))
  missing <- setdiff(c("student_id", "term"), names(degrees))
  if (length(missing) > 0L) {
    stop("[retention-context.R] degrees lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  awarded <- dplyr::ungroup(degrees)
  if ("graduation_status" %in% names(awarded)) awarded <- awarded %>% filter(graduation_status == "Awarded")
  awarded %>% filter(!is.na(term)) %>% distinct(student_id, degree_term = as.integer(term))
}

#' The graduation applications still pending: one row per student and term
#'
#' @param degrees `cedar_degrees` with `graduation_status`.
#' @return A tibble of `student_id` and `degree_term` for rows whose status is
#'   "Pending": the student has applied to graduate that term and the degree
#'   is not posted.
pending_degrees <- function(degrees) {
  missing <- setdiff(c("student_id", "term", "graduation_status"), names(degrees))
  if (length(missing) > 0L) {
    stop("[retention-context.R] degrees lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  dplyr::ungroup(degrees) %>%
    filter(graduation_status == "Pending", !is.na(term)) %>%
    distinct(student_id, degree_term = as.integer(term))
}

#' Every degree that counts to date: awarded, or applied for where not yet posted
#'
#' Degrees are posted a term or two behind enrollment. To `degree_edge` a
#' degree is one awarded (awarded_degrees()). Past it nothing is awarded yet,
#' and a pending application to graduate stands in, marked, so a follow-up
#' that reads enrollment past the degree edge does not count a student who
#' has just finished as gone.
#'
#' @param degrees `cedar_degrees`.
#' @param degree_edge `last_degree`.
#' @return `student_id`, `degree_term`, `basis` ("awarded" or "applied").
degrees_to_date <- function(degrees, degree_edge) {
  if (is.null(degree_edge)) {
    stop("[retention-context.R] degrees_to_date needs the degree edge (last_degree).", call. = FALSE)
  }
  bind_rows(
    awarded_degrees(degrees) %>% filter(degree_term <= degree_edge) %>% mutate(basis = "awarded"),
    if ("graduation_status" %in% names(degrees)) {
      pending_degrees(degrees) %>% filter(degree_term > degree_edge) %>% mutate(basis = "applied")
    }
  )
}

#' Students who finished between a term and the next regular term
#'
#' A spring student awarded a degree in the summer did not leave: they
#' finished, a term later than a spring graduate. This finds them: a degree
#' dated after the anchor term and before its next regular term (in a
#' fall/spring/summer calendar, only the summer after a spring). Where that
#' term's degrees are not posted yet (it is past `degree_edge`), a pending
#' application to graduate then stands in, marked `basis = "applied"`.
#'
#' @param anchors `student_id` and `term`: the student-terms to read.
#' @param degrees `cedar_degrees`.
#' @param degree_edge `last_degree`.
#' @return One row per anchor with such a degree: `student_id`, `term`,
#'   `finish_term`, `basis` ("awarded" or "applied").
between_term_finishers <- function(anchors, degrees, degree_edge) {
  found <- degrees_to_date(degrees, degree_edge)
  anchors %>%
    distinct(student_id, term = as.integer(term)) %>%
    mutate(next_regular = advance_term(term, 1L)) %>%
    inner_join(found, by = "student_id", relationship = "many-to-many") %>%
    filter(degree_term > term, degree_term < next_regular) %>%
    arrange(student_id, term, basis != "awarded", degree_term) %>%
    distinct(student_id, term, .keep_all = TRUE) %>%
    transmute(student_id, term, finish_term = degree_term, basis)
}

#' Where each student is at each regular term after a starting term
#'
#' The follow-up these analyses share (a class past 160 credits, a major's
#' entrants, an entering class): step 0 is the starting term and step k the k-th regular term
#' after it (summer is not a step, advance_term()). A step is returned only
#' where it can be read: its term is at or before the settled enrollment edge
#' and the degree edge, so a recent starter has the early steps and not the
#' later ones, and a caller's denominators are each step's own rows.
#'
#' @param starts `student_id` and `start` (the starting term), one row a student.
#' @param enrolled_terms `student_id` and `term`: every enrolled student-term,
#'   on any campus and at any level.
#' @param awarded awarded_degrees() output.
#' @param n_terms Steps after the start.
#' @param settled,degree_edge The two edges (`last_enrolled_complete`, `last_degree`).
#' @param since_start TRUE counts only a degree in or after the starting term:
#'   a class entering a level (a graduate student's bachelor's degree is not
#'   this class finishing). FALSE, the default, counts any earlier degree.
#' @return One row per student and readable step: `student_id`, `start`,
#'   `step`, `target_term`, `degree` (awarded a degree in or before the target
#'   term) and `enrolled` (enrolled in the target term).
follow_students <- function(starts, enrolled_terms, awarded, n_terms, settled, degree_edge,
                            since_start = FALSE) {
  if (anyDuplicated(starts$student_id) > 0L) {
    stop("[retention-context.R] follow_students: starts holds a student twice.", call. = FALSE)
  }
  here <- enrolled_terms %>% distinct(student_id, target_term = as.integer(term)) %>% mutate(enrolled = TRUE)
  counted <- awarded %>% select(student_id, degree_term)
  if (since_start) {
    counted <- counted %>%
      inner_join(starts %>% transmute(student_id, .start = as.integer(start)), by = "student_id",
                 relationship = "many-to-one") %>%
      filter(degree_term >= .start) %>%
      select(-.start)
  }
  first_degree <- counted %>% arrange(degree_term) %>% distinct(student_id, .keep_all = TRUE)
  bind_rows(lapply(0:as.integer(n_terms), function(k) {
    starts %>%
      transmute(student_id, start = as.integer(start), step = k,
                target_term = if (k == 0L) as.integer(start) else advance_term(start, k)) %>%
      # The opportunity edge: a step is read only where its term is settled.
      filter(target_term <= settled, target_term <= degree_edge)
  })) %>%
    left_join(here, by = c("student_id", "target_term"), relationship = "many-to-one") %>%
    left_join(first_degree, by = "student_id", relationship = "many-to-one") %>%
    mutate(degree = !is.na(degree_term) & degree_term <= target_term, enrolled = enrolled %in% TRUE) %>%
    select(student_id, start, step, target_term, degree, enrolled)
}

# Pre-build the graduated lookup: awarded_degrees() under this file's names.
# Returns a tibble with (student_id, grad_term), or NULL if degrees unavailable.
.build_graduated_lookup <- function(degrees) {
  if (is.null(degrees) || nrow(degrees) == 0) return(NULL)
  awarded_degrees(degrees) %>% rename(grad_term = degree_term)
}

# Prepare the shared, UNM-wide inputs used by every retention view. Course
# Dynamics requests a course trend plus department and college benchmarks in
# one click; without this context each view filters the full student history
# and rebuilds the same enrolled lookup independently.
#
# `student_terms` is cedar_student_terms, the full history: the lookup is read
# from its `enrolled` column, never rebuilt from class-list rows.
build_retention_context <- function(students, degrees = NULL, opt = list(),
                                    student_terms = NULL) {
  if (is.null(student_terms)) {
    stop("[retention-context.R] build_retention_context() needs student_terms ",
         "(cedar_student_terms): retention reads `enrolled` from it.")
  }
  observation_end <- .retention_observation_edge(opt)
  students      <- .scope_retention_history(students, observation_end)
  degrees       <- .scope_retention_history(degrees, observation_end)
  student_terms <- .scope_retention_history(student_terms, observation_end)

  structure(
    list(
      observation_end = observation_end,
      students = students,
      degrees = degrees,
      enrolled_lookup = .build_enrolled_lookup(student_terms),
      graduated_lookup = .build_graduated_lookup(degrees)
    ),
    class = "cedar_retention_context"
  )
}

.resolve_retention_context <- function(students, degrees, opt, context,
                                       student_terms = NULL) {
  if (is.null(context)) {
    return(build_retention_context(students, degrees, opt, student_terms = student_terms))
  }

  required <- c("observation_end", "students", "degrees",
                "enrolled_lookup", "graduated_lookup")
  if (!inherits(context, "cedar_retention_context") ||
      !all(required %in% names(context))) {
    stop("[course-retention.R] context must come from build_retention_context().")
  }

  observation_end <- .retention_observation_edge(opt)
  if (!identical(context$observation_end, observation_end)) {
    stop("[course-retention.R] context and opt must use the same observation edge.")
  }

  context
}

# Given a cohort tibble with columns (student_id, anchor_term), compute
# whether each student is retained at T+1 .. T+n_terms.
#
# Not follow_students(): a course's cohort holds a student once for each term
# they took it, a degree counts from that term on, and the callers read one
# wide row a cohort row with NA past the data. follow_students() is one start
# a student, long, and drops what cannot be read.
#
# A student is retained at T+N if:
#   - enrolled anywhere at UNM in the target term, OR
#   - has a graduation record at or after their anchor term and no later than
#     the target term being measured.
#
# Cells whose target term is beyond max(enrolled_lookup$term) are set to NA
# rather than FALSE — the data simply does not exist yet.
#
# Returns cohort with additional logical/NA columns retained_1 .. retained_n.
.compute_retention <- function(cohort, enrolled_lookup, n_terms,
                                graduated_lookup = NULL) {
  result         <- cohort
  unique_anchors <- unique(cohort$anchor_term)
  max_data_term  <- max(enrolled_lookup$term, na.rm = TRUE)

  # Keep the graduation term until each horizon is evaluated. Dropping it here
  # would let a future degree retroactively mark every earlier horizon retained.
  grad_retained_pairs <- if (!is.null(graduated_lookup) && nrow(graduated_lookup) > 0) {
    # Many-to-many is expected: a student can hold two degrees and anchor in
    # several terms. distinct() below leaves one row per pair.
    cohort %>%
      inner_join(graduated_lookup, by = "student_id", relationship = "many-to-many") %>%
      filter(grad_term >= anchor_term) %>%
      distinct(student_id, anchor_term, grad_term)
  } else {
    NULL
  }

  for (n in seq_len(n_terms)) {
    col_name <- paste0("retained_", n)

    # Map each anchor term to its T+N target
    term_map <- data.frame(
      anchor_term = unique_anchors,
      target_term = advance_term(unique_anchors, n_steps = n)
    )

    # Anchor terms whose target is beyond available data — return NA, not 0%
    future_anchors <- term_map %>%
      filter(target_term > max_data_term) %>%
      pull(anchor_term)

    # Students enrolled at the target term
    # Many-to-many is expected and harmless: several anchor terms can share a
    # target term, and every student enrolled in that target matches each of
    # them. The resulting (student_id, anchor_term) pairs are still distinct, so
    # the left_join below cannot duplicate a cohort row. Declared explicitly so
    # the warning does not read as a real fan-out.
    retained_enrolled <- term_map %>%
      inner_join(
        enrolled_lookup %>% rename(target_term = term),
        by = "target_term",
        relationship = "many-to-many"
      ) %>%
      select(student_id, anchor_term) %>%
      mutate(!!col_name := TRUE)

    # Union with students who had graduated by this target term. A degree earned
    # later remains a success, but cannot change the earlier historical state.
    if (!is.null(grad_retained_pairs)) {
      retained_enrolled <- bind_rows(
        retained_enrolled,
        grad_retained_pairs %>%
          inner_join(term_map, by = "anchor_term") %>%
          filter(grad_term <= target_term) %>%
          select(student_id, anchor_term) %>%
          mutate(!!col_name := TRUE)
      ) %>%
        distinct(student_id, anchor_term, .keep_all = TRUE)
    }

    result <- result %>%
      left_join(retained_enrolled, by = c("student_id", "anchor_term")) %>%
      mutate(!!col_name := if_else(
        anchor_term %in% future_anchors,
        NA,                          # target term not in data — leave blank
        !is.na(!!sym(col_name))      # FALSE = not retained; TRUE = retained
      ))
  }

  result
}

# Safe mean that returns NA_real_ when all inputs are NA (e.g. future terms)
# rather than NaN or 0.
.safe_mean <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) NA_real_ else mean(x)
}
