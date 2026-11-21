# exit-credits.R — How far along were the students who left without a degree?
#
# One question: of the students whose last enrolled term is behind us and who
# hold no degree, how many credits had each earned when they stopped, and how
# many were below the GPA floor, past the credit ceiling, or ever Pell-eligible?
#
#   Last term     the student's last enrolled term at any level
#                 (cedar_student_terms' `enrolled`), to the settled edge. The
#                 level and home campus in scope are that term's. A student
#                 who moved on to another level did not leave it.
#   Left          no enrollment in the two regular terms after the last term
#                 (summer is not a step), and no degree of any kind. Two edges
#                 decide whether that can be seen: the second regular term
#                 after the last term is at or before the settled enrollment
#                 edge, and the last term is at or before the degree edge, so
#                 a finished student whose degree is not posted yet is never
#                 read as gone. A last term past either is not judged, and is
#                 counted (`meta$n_not_judged`): it holds everyone still here.
#   Credits       total earned credits, transfer and test credit included.
#                 THE ONE SANCTIONED READ OF A PULL-STAMPED FIELD FOR A PAST
#                 TERM (field-reliability.md, "A student who has stopped"):
#                 `overall_credits_earned` is the total as of the pull of the
#                 last term's record, and a student who stopped enrolling
#                 stops earning, so the stamp is the total they left with.
#                 Where that record was pulled before the next regular term
#                 began, the last term's own credits were not yet in it and
#                 the class list's completed credits for that term are added
#                 (`credits_basis = "recorded + last term"`). `inst_gpa` and
#                 `overall_credits_attempted` are read the same way, for the
#                 same students only. None of this may be done for a student
#                 who is still enrolled, or for any term but the last.
#   Not a claim   that anyone lost aid. The floor and the ceiling are general
#                 standards (R/lists/aid_progress.R); the data has no
#                 eligibility record. Nor that a student never finished: a
#                 degree earned elsewhere is not in CEDAR.
#
# A sibling of the retention cones, not an extension: they ask who came back
# the next term; this asks who never did, and where they stood.
#
# Depends on: advance_term() (branches/cedar-terms.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             EXIT_* (lists/aid_progress.R)

#' Students who left without a degree, by credits at their last term
#'
#' @param student_terms `cedar_student_terms`.
#' @param programs `cedar_programs`: the last term's stamped totals and Pell.
#' @param degrees `cedar_degrees`.
#' @param terms `cedar_terms` (`term`, `start_date`), to tell a record pulled
#'   before the next regular term began.
#' @param opt `data_edges` (required, with `last_enrolled_complete` and
#'   `last_degree`), `student_level` (level codes of the last term; NULL keeps
#'   all), `campus` (home campuses in the last term; NULL keeps all),
#'   `first_exit_term` (earliest last term kept; NULL keeps all), `breaks`
#'   (band lower edges), `gpa_floor`, `credit_ceiling`, `min_n` (smallest band
#'   given a rate; default 30).
#' @return list(`students` one row per student who left: `student_id`,
#'   `exit_term`, `primary_major_code`, `student_campus`, `credits`,
#'   `credits_basis`, `band`, `gpa`, `gpa_below`, `attempted`, `over_ceiling`,
#'   `flagged` (either line), `ever_pell`; `bands` one row per band, in order,
#'   then "Not recorded": `n`, `share_pct`, and for Pell, the floor, the
#'   ceiling and either a count, the number known and a rate, NA under
#'   `min_n`; `by_term` one row per last term and band: `n`; `meta`).
get_exit_credits <- function(student_terms, programs, degrees, terms, opt = list()) {
  need <- list(
    student_terms = c("student_id", "term", "enrolled", "student_level", "student_campus",
                      "primary_major_code", "completed_unm_credits", "attempted_unm_credits"),
    programs = c("student_id", "term", "overall_credits_earned", "overall_credits_attempted",
                 "inst_gpa", "pell_eligible", "as_of_date"),
    degrees = c("student_id", "term"),
    terms = c("term", "start_date")
  )
  have <- list(student_terms = student_terms, programs = programs, degrees = degrees, terms = terms)
  for (name in names(need)) {
    missing <- setdiff(need[[name]], names(have[[name]]))
    if (length(missing) > 0L) {
      stop("[exit-credits.R] ", name, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
    }
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  degree_edge <- opt$data_edges[["last_degree"]]
  if (is.null(edge) || is.null(degree_edge)) {
    stop("[exit-credits.R] opt$data_edges needs a settled enrollment edge and a degree edge.", call. = FALSE)
  }
  breaks <- opt$breaks %||% EXIT_CREDIT_BREAKS
  labels <- exit_credit_band_labels(breaks)
  gpa_floor <- opt$gpa_floor %||% EXIT_GPA_FLOOR
  ceiling <- opt$credit_ceiling %||% EXIT_CREDIT_CEILING
  min_n <- as.integer(opt$min_n %||% 30L)

  enrolled <- student_terms %>% filter(enrolled, term <= edge) %>% mutate(term = as.integer(term))
  if (nrow(enrolled) == 0L) {
    stop("[exit-credits.R] no enrolled student-term at or before the settled edge.", call. = FALSE)
  }
  last <- enrolled %>%
    arrange(student_id, desc(term)) %>%
    distinct(student_id, .keep_all = TRUE)
  if (!is.null(opt$student_level)) last <- last %>% filter(student_level %in% opt$student_level)
  if (!is.null(opt$campus)) last <- last %>% filter(student_campus %in% opt$campus)
  if (!is.null(opt$first_exit_term)) last <- last %>% filter(term >= opt$first_exit_term)

  # Opportunity edge: two regular terms of follow-up settled, and the last
  # term's degrees posted.
  judged <- advance_term(last$term, 2L) <= edge & last$term <= degree_edge
  n_not_judged <- sum(!judged)
  last <- last[judged, , drop = FALSE]
  awarded <- degrees %>% filter(term <= degree_edge) %>% distinct(student_id)
  n_with_degree <- sum(last$student_id %in% awarded$student_id)
  left <- last %>% anti_join(awarded, by = "student_id")
  cedar_debug("[exit-credits.R] ", nrow(left), " left without a degree; ", n_with_degree,
              " with one; ", n_not_judged, " not judged")

  first_known <- function(x) { x <- x[!is.na(x)]; if (length(x) == 0L) NA_real_ else as.numeric(max(x)) }
  stamped <- programs %>%
    mutate(term = as.integer(term)) %>%
    semi_join(left, by = c("student_id", "term")) %>%
    group_by(student_id, term) %>%
    summarize(recorded = first_known(overall_credits_earned),
              recorded_attempted = first_known(overall_credits_attempted),
              gpa = first_known(inst_gpa),
              as_of = max(as_of_date), .groups = "drop")
  pell <- programs %>%
    semi_join(left, by = "student_id") %>%
    group_by(student_id) %>%
    summarize(ever_pell = if (all(is.na(pell_eligible))) NA else any(pell_eligible %in% TRUE), .groups = "drop")
  next_start <- terms %>% transmute(next_term = as.integer(term), next_start = as.Date(start_date))

  students <- left %>%
    left_join(stamped, by = c("student_id", "term"), relationship = "one-to-one") %>%
    left_join(pell, by = "student_id", relationship = "one-to-one") %>%
    mutate(next_term = advance_term(term, 1L)) %>%
    left_join(next_start, by = "next_term", relationship = "many-to-one") %>%
    mutate(
      # The record predates the next regular term: the last term's own
      # credits were not in the stamp yet. An unknown start is not a reason
      # to add them.
      early = !is.na(as_of) & !is.na(next_start) & as.Date(as_of) < next_start,
      credits = recorded + if_else(early, coalesce(as.numeric(completed_unm_credits), 0), 0),
      attempted = recorded_attempted + if_else(early, coalesce(as.numeric(attempted_unm_credits), 0), 0),
      credits_basis = case_when(is.na(recorded) ~ NA_character_,
                                early ~ "recorded + last term",
                                TRUE ~ "recorded"),
      band = factor(if_else(is.na(credits), "Not recorded",
                            labels[findInterval(credits, breaks) + 1L]),
                    levels = c(labels, "Not recorded")),
      gpa_below = gpa < gpa_floor,
      over_ceiling = attempted >= ceiling,
      flagged = case_when(gpa_below %in% TRUE | over_ceiling %in% TRUE ~ TRUE,
                          is.na(gpa_below) | is.na(over_ceiling) ~ NA,
                          TRUE ~ FALSE)
    ) %>%
    transmute(student_id, exit_term = term, primary_major_code, student_campus, credits,
              credits_basis, band, gpa, gpa_below, attempted, over_ceiling, flagged, ever_pell)

  rate <- function(hit, known) if_else(known >= min_n, 100 * hit / known, NA_real_)
  bands <- students %>%
    group_by(band, .drop = FALSE) %>%
    summarize(
      n = n(),
      n_pell = sum(ever_pell %in% TRUE), n_pell_known = sum(!is.na(ever_pell)),
      n_gpa_below = sum(gpa_below %in% TRUE), n_gpa_known = sum(!is.na(gpa_below)),
      n_over_ceiling = sum(over_ceiling %in% TRUE), n_ceiling_known = sum(!is.na(over_ceiling)),
      n_flagged = sum(flagged %in% TRUE), n_flag_known = sum(!is.na(flagged)),
      .groups = "drop"
    ) %>%
    mutate(share_pct = if (nrow(students) > 0L) 100 * n / nrow(students) else NA_real_,
           pell_pct = rate(n_pell, n_pell_known),
           gpa_below_pct = rate(n_gpa_below, n_gpa_known),
           over_ceiling_pct = rate(n_over_ceiling, n_ceiling_known),
           flagged_pct = rate(n_flagged, n_flag_known)) %>%
    filter(band != "Not recorded" | n > 0L) %>%
    select(band, n, share_pct, n_pell, n_pell_known, pell_pct, n_gpa_below, n_gpa_known,
           gpa_below_pct, n_over_ceiling, n_ceiling_known, over_ceiling_pct, n_flagged,
           n_flag_known, flagged_pct)

  list(
    students = students,
    bands = bands,
    by_term = students %>% count(exit_term, band, name = "n") %>% arrange(exit_term, band),
    meta = list(
      edge = edge, degree_edge = degree_edge,
      first_exit_term = if (nrow(students) > 0L) min(students$exit_term) else NA_integer_,
      last_exit_term = if (nrow(students) > 0L) max(students$exit_term) else NA_integer_,
      n_left = nrow(students), n_with_degree = n_with_degree, n_not_judged = n_not_judged,
      n_last_term_added = sum(students$credits_basis %in% "recorded + last term"),
      breaks = breaks, gpa_floor = gpa_floor, credit_ceiling = ceiling, min_n = min_n
    )
  )
}
