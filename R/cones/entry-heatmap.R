# entry-heatmap.R — Courses taken before students entered the focal major
#
# Answers one question: which courses, and how long before entry, did students
# take in the terms leading up to their first appearance in the focal major?
#
# Split out of R/cones/major-changes.R. It does not use major-change detection.
#
# Depends on: validate_population() (trunk/utils.R),
#             cedar_filter_campus() (lists/campuses.R)

#' Courses taken in the terms before students entered the focal major
#'
#' Heatmap of courses taken by population students in the semesters before their
#' first appearance in the focal major (pre-major or declared), split into
#' courses the focal unit teaches and everything else.
#'
#' Each row of the returned tibbles is one (course, lag) cell: `lag = 1` is the
#' term immediately before entry, `lag = 2` two terms before, and so on. Summers
#' are excluded from the lag count by default, so T-1 is always a fall or spring.
#'
#' Entry terms come from `population$first_unit_term`, which is already scoped to
#' the focal programs. Re-deriving them from `programs` would pick up a student's
#' entire program history, so switchers would be measured from their previous
#' major rather than their entry into the focal one.
#'
#' @param students       cedar_students data frame. Must carry `campus`.
#' @param programs       cedar_programs data frame
#' @param population     Population tibble from build_population(); needs
#'   `first_unit_term`
#' @param focal_subjects Character vector of subject codes the unit teaches
#'   (e.g. c("HIST")). Splits the result into in_unit and out_unit
#' @param opt            Options list:
#'   \itemize{
#'     \item \code{max_lag}     — integer; how many terms back to look (default 3)
#'     \item \code{min_n}       — integer; minimum students per (course, lag) cell (default 5)
#'     \item \code{incl_summer} — logical; count summer terms toward the lag (default FALSE)
#'     \item \code{campus}      — character; restrict to delivery campuses
#'   }
#' @return Named list, or NULL when the population is empty or has no usable
#'   `first_unit_term`:
#'   \itemize{
#'     \item \code{in_unit}  — tibble of (course, lag) cells from focal_subjects
#'     \item \code{out_unit} — tibble of cells from all other subjects; empty
#'       tibble when focal_subjects is empty
#'     \item \code{n_majors} — distinct students in the population
#'   }
#'   Each cell tibble carries: n_became_major (population students who took the
#'   course at that lag), n_in_course (ALL students enrolled in that course in
#'   those same terms), pct_of_majors (n_became_major / n_majors — how common in
#'   the cohort), and pct_converted (n_became_major / n_in_course — the gateway
#'   signal).
get_entry_heatmap <- function(students, programs, population,
                               focal_subjects = character(0),
                               opt = list()) {
  max_lag     <- opt$max_lag     %||% 3L
  min_n       <- opt$min_n       %||% 5L
  incl_summer <- opt$incl_summer %||% FALSE
  campus      <- opt$campus

  validate_population(population, "get_entry_heatmap")
  cedar_require_campus(students, "get_entry_heatmap")
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
    cedar_filter_campus(campus, fn = "get_entry_heatmap") %>%
    select(student_id, term, campus, subject_course, course_title) %>%
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
  lag_term_course <- pop_enrl_raw %>%
    distinct(term, campus, subject_course, lag)

  # All students enrolled in those same (term, course) slots → n_in_course
  n_in_course_df <- students %>%
    filter(registration_status_code %in% STATUS_REGISTERED) %>%
    cedar_filter_campus(campus, fn = "get_entry_heatmap") %>%
    select(student_id, term, campus, subject_course) %>%
    inner_join(lag_term_course, by = c("term", "campus", "subject_course")) %>%
    group_by(campus, subject_course, lag) %>%
    summarize(n_in_course = n_distinct(student_id), .groups = "drop")

  # Deduplicate to one row per (population student, course, lag)
  pop_enrl <- pop_enrl_raw %>%
    group_by(student_id, campus, subject_course, lag, subj) %>%
    summarize(course_title = first(course_title), .groups = "drop")

  summarize_hm <- function(df) {
    if (nrow(df) == 0L) return(tibble())
    df %>%
      group_by(campus, subject_course, lag) %>%
      summarize(
        course_title   = first(course_title),
        n_became_major = n_distinct(student_id),
        .groups        = "drop"
      ) %>%
      left_join(n_in_course_df, by = c("campus", "subject_course", "lag")) %>%
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
