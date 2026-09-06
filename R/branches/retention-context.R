# retention-context.R — Shared retention computation (branch)
#
# Builds the context every retention question needs — the registered and
# graduated lookups, the observation edge, and the per-student retained_1 ..
# retained_n flags — and nothing that answers a question with it.
#
# Retention definition: a student is retained at T+N if they are:
#   (a) registered anywhere at UNM in the target term, OR
#   (b) recorded as having graduated between the anchor and target term.
# Graduates are not counted as stop-outs — they successfully completed.
#
# Cells where the target term is beyond the available data are returned as NA,
# not 0%. A 0% would be misleading for recent terms where students could not yet
# have met the criterion.
#
# Campus policy (see AGENTS.md): .filter_campus() scopes the *cohort*, but
# .build_registered_lookup() is deliberately UNM-wide, because a student who
# transfers between campuses has been retained, not lost. That is the one
# intentional campus-blind aggregate in the retention code.
#
# Split out of R/cones/course-retention.R: the three get_*_retention_* cones all
# consume what this file produces, so it belongs below them rather than beside
# them.
#
# Depends on: STATUS_REGISTERED (lists/status_codes.R),
#             add_next_term_col() (trunk/utils.R)

# =============================================================================
# Internal helpers
# =============================================================================

# Advance a vector of term codes by exactly n_steps semesters (skipping summer
# by default). Each element is advanced independently.
.advance_term_n <- function(term_codes, n_steps, summer = FALSE) {
  result <- as.integer(term_codes)
  for (i in seq_len(n_steps)) {
    tmp    <- data.frame(term = result)
    result <- add_next_term_col(tmp, "term", summer = summer)$next_term
  }
  result
}

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

# Pre-build the "is registered at term T" lookup.
# Returns a tibble with (student_id, term) for all registered rows.
#
# DELIBERATELY UNM-WIDE, and the one place in this file that is. Retention asks
# whether a student was still enrolled *anywhere at UNM*, so a student who takes
# a course at Gallup and later enrols in Albuquerque is retained, not a stop-out.
# Narrowing this lookup to the cohort's campus would silently redefine retention
# as "stayed on the same campus" and count every transfer as attrition.
# The cohort is campus-scoped (see .filter_campus); the outcome is not.
.build_registered_lookup <- function(students) {
  students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    distinct(student_id, term)
}

# Pre-build the graduated lookup.
# Returns a tibble with (student_id, grad_term), or NULL if degrees unavailable.
.build_graduated_lookup <- function(degrees) {
  if (is.null(degrees) || nrow(degrees) == 0) return(NULL)
  degrees %>%
    distinct(student_id, grad_term = term)
}

# Prepare the shared, UNM-wide inputs used by every retention view. Course
# Dynamics requests a course trend plus department and college benchmarks in
# one click; without this context each view filters the full student history
# and rebuilds the same registration lookup independently.
build_retention_context <- function(students, degrees = NULL, opt = list()) {
  observation_end <- .retention_observation_edge(opt)
  students <- .scope_retention_history(students, observation_end)
  degrees  <- .scope_retention_history(degrees, observation_end)

  structure(
    list(
      observation_end = observation_end,
      students = students,
      degrees = degrees,
      registered_lookup = .build_registered_lookup(students),
      graduated_lookup = .build_graduated_lookup(degrees)
    ),
    class = "cedar_retention_context"
  )
}

.resolve_retention_context <- function(students, degrees, opt, context) {
  if (is.null(context)) {
    return(build_retention_context(students, degrees, opt))
  }

  required <- c("observation_end", "students", "degrees",
                "registered_lookup", "graduated_lookup")
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
# A student is retained at T+N if:
#   - registered anywhere at UNM in the target term, OR
#   - has a graduation record at or after their anchor term and no later than
#     the target term being measured.
#
# Cells whose target term is beyond max(registered_lookup$term) are set to NA
# rather than FALSE — the data simply does not exist yet.
#
# Returns cohort with additional logical/NA columns retained_1 .. retained_n.
.compute_retention <- function(cohort, registered_lookup, n_terms,
                                graduated_lookup = NULL) {
  result         <- cohort
  unique_anchors <- unique(cohort$anchor_term)
  max_data_term  <- max(registered_lookup$term, na.rm = TRUE)

  # Keep the graduation term until each horizon is evaluated. Dropping it here
  # would let a future degree retroactively mark every earlier horizon retained.
  grad_retained_pairs <- if (!is.null(graduated_lookup) && nrow(graduated_lookup) > 0) {
    cohort %>%
      inner_join(graduated_lookup, by = "student_id") %>%
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
      target_term = .advance_term_n(unique_anchors, n_steps = n)
    )

    # Anchor terms whose target is beyond available data — return NA, not 0%
    future_anchors <- term_map %>%
      filter(target_term > max_data_term) %>%
      pull(anchor_term)

    # Students registered at the target term
    # Many-to-many is expected and harmless: several anchor terms can share a
    # target term, and every student registered in that target matches each of
    # them. The resulting (student_id, anchor_term) pairs are still distinct, so
    # the left_join below cannot duplicate a cohort row. Declared explicitly so
    # the warning does not read as a real fan-out.
    retained_enrolled <- term_map %>%
      inner_join(
        registered_lookup %>% rename(target_term = term),
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
