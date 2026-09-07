# course-adjacency.R — Courses adjacent to a student entry or exit event
#
# Answers one question: which courses do population students take in the terms
# immediately around an event (entry into the unit, or departure from it),
# compared with everyone else?
#
# Split out of R/cones/pathway.R.
#
# Depends on: cedar_filter_campus() (lists/campuses.R)

#' Get Courses Adjacent to Student Entry or Exit Events
#'
#' Finds courses taken in the term(s) immediately before a population-level
#' change event and compares their frequency across two groups. For entry
#' events: converters (pre-majors who eventually declared) vs. non-converters
#' (pre-majors who left without declaring). For exit events: students who left
#' vs. students who stayed.
#'
#' Lift > 1 means the course appears disproportionately in the primary group
#' (converters for entry, leavers for exit) relative to the comparison group.
#' This is a correlation, not evidence of causation.
#'
#' @param students   Data frame. The `cedar_students` table.
#' @param population Data frame. Output of `build_population()`. Must have
#'   columns `student_id`, `outcome`, `first_unit_term`, `last_unit_term`.
#'   `entry_status` is not required — groups are assigned by outcome alone,
#'   so all entry paths (pre_major, switched_in, undecided) are included.
#' @param event      Character. `"entry"` (default) or `"exit"`.
#' @param window     Integer. Number of non-summer terms to look back from the
#'   event term. Default: `1L` (the single term immediately preceding).
#' @param include_event_term Logical. Whether to include the event term itself.
#'   Default: `FALSE`. Setting `TRUE` mixes gateway courses with first-term
#'   required courses.
#' @param min_n      Integer. Minimum students per group for a course to appear.
#'   Default: `5L`.
#' @param campus     Character vector of course-delivery campus codes. Scopes
#'   which enrollment rows are counted and is part of the output grouping. NULL
#'   includes every campus — pass NULL only for a deliberate UNM-wide aggregate.
#'   Note this is the campus that taught the section, not the student's home
#'   campus; the two differ on roughly 28% of enrollment rows.
#'
#' @return Wide data frame with one row per course and columns for each group's
#'   student count (`n_students_*`), group size (`n_group_*`), rate (`pct_*`),
#'   and `lift`. Attributes include `ep_meta` (list with n per group, n excluded
#'   for no prior term). Returns an empty data frame if no qualifying students
#'   are found.
#'
#' @seealso [get_course_timing()], [get_course_pairs()]
#' @export
get_event_adjacent_courses <- function(students, population,
                                        event              = "entry",
                                        window             = 1L,
                                        include_event_term = FALSE,
                                        min_n              = 5L,
                                        campus             = NULL) {

  needed <- c("student_id", "outcome", "first_unit_term", "last_unit_term")
  missing_cols <- setdiff(needed, names(population))
  if (length(missing_cols) > 0)
    stop("[pathway.R] population missing columns for event analysis: ",
         paste(missing_cols, collapse = ", "),
         ". Ensure build_population() was called with students= provided.")

  # ── Assign groups and anchor event terms ──────────────────────────────────

  if (event == "entry") {
    # Groups are based on outcome, not entry path. This includes switched_in
    # students (who took courses in the target major before switching, which
    # may have precipitated the switch) and students from undecided/general
    # pools who are not pre-majors in any formal sense. All are anchored at
    # first_unit_term — the semester before that window is what we examine.
    pop_grp <- population %>%
      mutate(
        event_term = first_unit_term,
        group = case_when(
          outcome %in% c("ongoing", "graduated",
                         "switched_out", "stopped_out") ~ "entered",
          outcome %in% c("chose_elsewhere",
                         "left_undeclared")             ~ "did_not_enter",
          TRUE ~ NA_character_
        )
      ) %>%
      filter(!is.na(group))

  } else if (event == "exit") {
    pop_grp <- population %>%
      mutate(
        event_term = last_unit_term,
        group = case_when(
          outcome %in% c("switched_out", "stopped_out",
                         "chose_elsewhere", "left_undeclared") ~ "left",
          outcome %in% c("ongoing", "graduated")               ~ "stayed",
          TRUE ~ NA_character_
        )
      ) %>%
      filter(!is.na(group))

  } else {
    stop("[pathway.R] event must be 'entry' or 'exit', got: '", event, "'")
  }

  if (nrow(pop_grp) == 0) {
    message("[pathway.R] No qualifying students for event='", event,
            "' (entry_status filter may have removed everyone).")
    return(data.frame())
  }

  message("[pathway.R] Event-adjacent courses: event='", event, "', ",
          n_distinct(pop_grp$student_id), " students in ",
          n_distinct(pop_grp$group), " groups.")

  # ── Build per-student term windows in absolute calendar space ─────────────
  #
  # Position-based lookup: find each event_term's index in the ordered list of
  # non-summer terms, then take the N terms before it. This correctly handles
  # the irregular YYYYSS gaps (spring=10, summer=60, fall=80).
  all_main_terms <- sort(unique(students$term[
    substr(as.character(students$term), 5, 6) != "60"
  ]))

  unique_event_terms <- unique(pop_grp$event_term[!is.na(pop_grp$event_term)])

  window_df <- purrr::map_dfr(unique_event_terms, function(et) {
    idx       <- match(et, all_main_terms)
    if (is.na(idx)) return(NULL)
    start_idx <- max(1L, idx - window)
    end_idx   <- if (include_event_term) idx else idx - 1L
    if (end_idx < start_idx) return(NULL)   # no prior term exists for this student
    tibble(event_term = et, term = all_main_terms[start_idx:end_idx])
  })

  if (nrow(window_df) == 0) {
    message("[pathway.R] No prior-term windows found ",
            "(all students may have entered in the earliest data term).")
    return(data.frame())
  }

  student_windows <- pop_grp %>%
    select(student_id, group, event_term) %>%
    inner_join(window_df, by = "event_term", relationship = "many-to-many")

  n_no_prior <- n_distinct(pop_grp$student_id) - n_distinct(student_windows$student_id)
  if (n_no_prior > 0)
    message("[pathway.R] ", n_no_prior,
            " student(s) excluded: no prior term on record before their event term.")

  # ── Join enrollment records for those windows ─────────────────────────────

  enrolled_in_window <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    cedar_filter_campus(campus, fn = "get_event_adjacent_courses") %>%
    select(student_id, term, campus, subject_course, course_title) %>%
    distinct() %>%
    inner_join(student_windows %>% select(student_id, group, term),
               by = c("student_id", "term"))

  if (nrow(enrolled_in_window) == 0) {
    message("[pathway.R] No enrollment records found in event windows.")
    return(data.frame())
  }

  # ── Aggregate: courses per group, percentage of group ─────────────────────

  group_sizes <- student_windows %>%
    distinct(student_id, group) %>%
    count(group, name = "n_group")

  course_counts <- enrolled_in_window %>%
    # Campus joins the key: this table names courses, and a branch-delivered
    # section merged into a main-campus row reads as the same offering.
    group_by(group, campus, subject_course) %>%
    summarize(
      n_students   = n_distinct(student_id),
      course_title = first(course_title),
      .groups      = "drop"
    ) %>%
    left_join(group_sizes, by = "group") %>%
    mutate(
      pct          = round(n_students / n_group, 3),
      subject_code = sub(" .*", "", subject_course)
    ) %>%
    filter(n_students >= min_n)

  if (nrow(course_counts) == 0) {
    message("[pathway.R] No courses met min_n = ", min_n, " threshold.")
    return(data.frame())
  }

  # ── Pivot wide: one row per course ────────────────────────────────────────

  result <- course_counts %>%
    select(subject_course, subject_code, course_title,
           group, n_students, n_group, pct) %>%
    tidyr::pivot_wider(
      names_from  = group,
      values_from = c(n_students, n_group, pct),
      values_fill = list(n_students = 0L, pct = 0)
    )

  # ── Lift: ratio of primary group rate to comparison group rate ─────────────
  # > 1 = disproportionately associated with the primary group

  if (event == "entry" &&
      all(c("pct_entered", "pct_did_not_enter") %in% names(result))) {
    result <- result %>%
      mutate(lift = ifelse(pct_did_not_enter > 0,
                           round(pct_entered / pct_did_not_enter, 2),
                           NA_real_))
  } else if (event == "exit" &&
             all(c("pct_left", "pct_stayed") %in% names(result))) {
    result <- result %>%
      mutate(lift = ifelse(pct_stayed > 0,
                           round(pct_left / pct_stayed, 2),
                           NA_real_))
  }

  # Attach group-size metadata so callers can surface n_group without re-computing
  attr(result, "ep_meta") <- list(
    event      = event,
    n_groups   = as.list(setNames(group_sizes$n_group, group_sizes$group)),
    n_no_prior = n_no_prior,
    n_courses  = nrow(result),
    min_n      = min_n
  )

  message("[pathway.R] Returning ", nrow(result), " courses with event adjacency data.")
  result
}


# Null-coalescing operator - define only if not already loaded.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
