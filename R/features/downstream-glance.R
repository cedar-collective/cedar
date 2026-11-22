# Course Dynamics > Downstream > At a Glance: the story of a course's
# students in five steps, one row each, read off the results the other views
# already computed. No step is recomputed here: each reads one payload.
#
#   in_course     the course's DFW rate across its terms and its trend
#                 (get_course_outcome_rates() by campus and term, the DFW tab's)
#   coming_back   next-semester return, passed against did not pass
#                 (get_course_persistence(), Coming Back's chart)
#   non_takers    return against similar students who did not take it
#                 (build_course_similar_students(), Against Non-Takers)
#   next_courses  took the later course, and passed it
#                 (build_later_course(), Next Courses)
#   prepared      DFW in the later course, passed this one first against not
#                 (get_course_sequence_effect(), Prepared for It)
#
# A step whose payload has not arrived yet is "pending"; one that cannot be
# read for this course says why ("none"). Each ready step names the one
# campus it reads, the one with the most students, so its numbers are one
# campus's and never a blend (AGENTS.md, Campus).
#
# Exported: downstream_glance(), DOWNSTREAM_GLANCE_STEPS.

DOWNSTREAM_GLANCE_STEPS <- c(
  in_course = "In the Course", coming_back = "Coming Back", non_takers = "Against Non-Takers",
  next_courses = "Next Courses", prepared = "Did Passing It First Help?"
)

.glance_pct <- function(x) sprintf("%.1f%%", x)

.glance_row <- function(step, status, sentence, bars = NULL, verdict = NA_character_,
                        tone = NA_character_, scope = NA_character_) {
  list(step = step, title = DOWNSTREAM_GLANCE_STEPS[[step]], status = status, sentence = sentence,
       bars = bars, verdict = verdict, tone = tone, scope = scope)
}

.glance_bars <- function(label, pct, n, of, reference = c(FALSE, TRUE)) {
  tibble::tibble(label = label, share = pct / 100,
                 text = sprintf("%s (%s of %s)", .glance_pct(pct), fmt_count(n), fmt_count(of)),
                 reference = reference[seq_along(label)])
}

.glance_need <- function(df, cols, what) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0) {
    stop("[downstream-glance.R] ", what, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

# The DFW rate over every term on the campus with the most attempts, and the
# fitted line through the term type with the most attempts there.
.glance_in_course <- function(course, dfw_by_term) {
  .glance_need(dfw_by_term, c("campus", "term", "n_attempts", "n_dfw"), "the DFW-by-term table")
  by_term <- dfw_by_term %>%
    dplyr::filter(!is.na(n_attempts), n_attempts > 0) %>%
    dplyr::group_by(campus, term) %>%
    dplyr::summarize(n = sum(n_attempts), k = sum(n_dfw), .groups = "drop")
  if (nrow(by_term) == 0L) return(.glance_row("in_course", "none", "No graded attempt of this course to read."))
  campus_n <- by_term %>% dplyr::count(campus, wt = n, sort = TRUE)
  main <- campus_n$campus[[1]]
  rows <- by_term %>% dplyr::filter(campus == main) %>% dplyr::mutate(term_type = get_term_type(term))
  type <- rows %>% dplyr::count(term_type, wt = n, sort = TRUE) %>% dplyr::pull(term_type)
  type <- type[[1]]
  trend <- compute_rate_trend(rows %>% dplyr::filter(term_type == type), "term_type")
  pooled <- 100 * sum(rows$k) / sum(rows$n)
  .glance_row(
    "in_course", "ready",
    paste0(.glance_pct(pooled), " of the ", fmt_count(sum(rows$n)), " graded attempts at ", course,
           " across ", nrow(rows), " terms ended in DFW. ", tools::toTitleCase(type), " to ", type,
           if (trend$direction == "too_few_terms") ", there are too few terms to read a trend."
           else paste0(", the rate was ", .glance_pct(trend$first_pct), " in ", fmt_term(trend$first_term),
                       " and ", .glance_pct(trend$last_pct), " in ", fmt_term(trend$last_term), ": ",
                       c(rising = "an upward trend", falling = "a downward trend",
                         steady = "no trend beyond chance")[[trend$direction]], ".")),
    bars = .glance_bars("DFW", pooled, sum(rows$k), sum(rows$n), reference = FALSE),
    verdict = c(rising = "DFW rising", falling = "DFW falling", steady = "DFW steady",
                too_few_terms = NA_character_)[[trend$direction]],
    tone = c(rising = "worse", falling = "better", steady = NA, too_few_terms = NA)[[trend$direction]],
    scope = main
  )
}

# Next-semester return, students who passed against those who did not (a
# failing grade or a late withdrawal; an early drop is neither).
.glance_coming_back <- function(course, persistence) {
  .glance_need(persistence, c("campus", "outcome", "n_students", "n_returned"), "the persistence table")
  rows <- persistence %>%
    dplyr::filter(outcome != "early drop") %>%
    dplyr::mutate(passed = outcome == "pass") %>%
    dplyr::group_by(campus, passed) %>%
    dplyr::summarize(n = sum(n_students), k = sum(n_returned), .groups = "drop")
  if (nrow(rows) == 0L) return(.glance_row("coming_back", "none", "Too few graded students to read who came back."))
  main <- rows %>% dplyr::count(campus, wt = n, sort = TRUE) %>% dplyr::pull(campus)
  main <- main[[1]]
  p <- rows %>% dplyr::filter(campus == main, passed)
  f <- rows %>% dplyr::filter(campus == main, !passed)
  if (nrow(p) == 0L || nrow(f) == 0L) {
    return(.glance_row("coming_back", "none",
                       paste0("Students on ", main, " either all passed or none did, so the two cannot be compared."),
                       scope = main))
  }
  gap <- 100 * (p$k / p$n - f$k / f$n)
  .glance_row(
    "coming_back", "ready",
    paste0(.glance_pct(100 * p$k / p$n), " of the students who passed ", course, " came back the next semester, against ",
           .glance_pct(100 * f$k / f$n), " of those who did not pass."),
    bars = .glance_bars(c("Passed", "Did not pass"), 100 * c(p$k / p$n, f$k / f$n), c(p$k, f$k), c(p$n, f$n)),
    verdict = sprintf("%+.1f points for passing", gap),
    scope = main
  )
}

.glance_non_takers <- function(similar) {
  findings <- course_similar_students_findings(similar)
  r <- findings[findings$outcome == "return", , drop = FALSE]
  if (nrow(r) == 0L) {
    return(.glance_row("non_takers", "none", "Too few takers had similar students to compare with."))
  }
  # When the two groups differed before the course on a measure outside the
  # matching, the gap is not the course's: say so and colour nothing.
  alike <- course_similar_students_alike(similar)
  not_alike <- alike$status %in% c("somewhat_apart", "apart")
  .glance_row(
    "non_takers", "ready",
    paste0(r$sentence[[1]], if (not_alike) paste0(
      " The two groups were not alike before the course (ACT ", sprintf("%.1f", abs(alike$gap)), " points ",
      if (alike$gap < 0) "lower" else "higher", " for takers), so this is not the course's doing alone.")),
    bars = tibble::tibble(label = c("Took it", "Similar students"), share = c(r$taker, r$similar) / 100,
                          text = .glance_pct(c(r$taker, r$similar)), reference = c(FALSE, TRUE)),
    verdict = if (not_alike) "Not a like-for-like comparison" else
      c(better = "Better than similar students", worse = "Worse than similar students",
        same = "About the same as similar students", unclear = "Too few to judge")[[r$verdict]],
    tone = if (not_alike) NA_character_ else c(better = "better", worse = "worse", same = NA, unclear = NA)[[r$verdict]]
  )
}

.glance_next_courses <- function(later) {
  heads <- later_course_headline(later)
  if (length(heads) == 0L) return(.glance_row("next_courses", "none", "No student could have taken the later course yet."))
  main <- heads[[which.max(vapply(heads, function(h) as.numeric(h$n_eligible), numeric(1)))]]
  y <- later$course_y_label
  if (is.na(main$pct_took_y)) {
    return(.glance_row("next_courses", "none",
                       paste0("Fewer than ", later$min_n, " students on ", main$campus, " could have taken ", y, "."),
                       scope = main$campus))
  }
  window <- paste0(later$window_terms, " regular term", if (later$window_terms == 1L) "" else "s")
  .glance_row(
    "next_courses", "ready",
    paste0("Of the ", fmt_count(main$n_eligible), " students who could have taken ", y, ", ",
           .glance_pct(main$pct_took_y), " took it within ", window,
           if (is.na(main$pct_pass)) "; too few have a grade in it yet." else
             paste0(", and ", .glance_pct(main$pct_pass), " of those with a grade passed it.")),
    bars = .glance_bars(c(paste("Took", y), paste("Passed", y)),
                        c(main$pct_took_y, main$pct_pass %||% NA_real_),
                        c(main$n_took_y, main$n_pass), c(main$n_eligible, main$n_graded),
                        reference = c(TRUE, FALSE))[if (is.na(main$pct_pass)) 1L else 1:2, ],
    scope = main$campus
  )
}

.glance_prepared <- function(sequence) {
  rates <- course_sequence_rates(sequence)
  x <- sequence$course_x
  y <- paste(sequence$course_y, collapse = " or ")
  gap <- rates$pct[[1]] - rates$pct[[2]]
  band <- sequence$balance$overall_balance %||% "unavailable"
  .glance_row(
    "prepared", "ready",
    paste0("Students who passed ", x, " first did not pass ", y, " ", .glance_pct(rates$pct[[1]]),
           " of the time, against ", .glance_pct(rates$pct[[2]]), " of those without a prior pass. ",
           c(substantial = "The two groups differed substantially before the course, so the gap describes who took each path.",
             review = "The two groups differed somewhat before the course; read the gap with that in mind.",
             small = "The two groups looked alike on what was measured.",
             unavailable = "How alike the two groups were could not be measured.")[[band]]),
    bars = .glance_bars(c(paste0("Passed ", x, " first"), "No prior pass"), rates$pct, rates$dfw, rates$total),
    verdict = if (abs(gap) < 0.05) "No gap in DFW" else sprintf("%+.1f points DFW", gap),
    tone = if (abs(gap) < 0.05) NA_character_ else if (gap < 0) "better" else "worse"
  )
}

#' The five steps of At a Glance
#'
#' @param course The analysed course's code, for the sentences.
#' @param dfw_by_term `get_course_outcome_rates()` by campus and term, or NULL.
#' @param persistence `get_course_persistence()` output, or NULL.
#' @param similar `build_course_similar_students()` output, or NULL.
#' @param similar_available FALSE when the institution has no admissions
#'   records, so Against Non-Takers can never read similar students.
#' @param later `build_later_course()` output, or NULL.
#' @param sequence `get_course_sequence_effect()` output, or NULL.
#' @return A list of five rows in story order, each a list: `step`, `title`,
#'   `status` ("ready", "pending" or "none"), `sentence`, `bars` (a tibble for
#'   cedar_compare_bars(), or NULL), `verdict`, `tone` ("better", "worse" or
#'   NA) and `scope` (the campus read, or NA).
downstream_glance <- function(course, dfw_by_term = NULL, persistence = NULL, similar = NULL,
                              similar_available = TRUE, later = NULL, sequence = NULL) {
  pending <- function(step, what) .glance_row(step, "pending", paste0(what, "…"))
  list(
    if (is.null(dfw_by_term)) pending("in_course", "Reading the course's grades")
    else .glance_in_course(course, dfw_by_term),
    if (is.null(persistence)) pending("coming_back", "Following its students to the next semester")
    else .glance_coming_back(course, persistence),
    if (!isTRUE(similar_available)) .glance_row("non_takers", "none", "Needs admissions records, which this installation does not have.")
    else if (is.null(similar)) pending("non_takers", "Matching its students with similar students")
    else .glance_non_takers(similar),
    if (is.null(later)) pending("next_courses", "Following its students into the later course")
    else .glance_next_courses(later),
    if (is.null(sequence)) pending("prepared", "Comparing the later course's students")
    else .glance_prepared(sequence)
  )
}
