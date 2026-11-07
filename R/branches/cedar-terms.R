# cedar-terms.R — the term dimension: one row per term in the loaded data
#
# ADR-001 step 1 (docs/developers/architecture-decisions.md, ADR-001). Every fact
# about a term that CEDAR today recomputes at each use lives here once:
#
#   season, academic year, whether the term is a regular (Fall/Spring) one
#   the next and previous term, by the calendar and skipping Summer
#   the term's first day and census date, read from its sections
#   how many class-list rows, sections and awarded degrees it has
#   the four right edges of data-edges.R as per-term flags
#
# The flags are the same edges cedar_report_edges() computes at startup, so a
# reader may bound a longitudinal analysis with `filter(is_settled)` instead
# of carrying `cedar_report_end_term` as a parameter and comparing against it.
# They are never recomputed here: the edges are passed in, and an edge the data
# cannot determine (NULL) makes its flag NA on every row, never FALSE.
#
# Every Fall and Spring between the first and last term with a class list is a
# row, with a class list or without one, so next_regular_term always names a
# row and a reader filtering is_enrolled or is_settled never mistakes a gap
# for a term nobody attended. A gap means a pull is missing: it is reported
# at build time, never absorbed and never a stop (the synthetic institution
# has them by design; production has had none).
#
# Built once per load, in global.R, from the tables after cedar_min_term
# trimming; never saved, because it describes whatever data is loaded.

CEDAR_TERMS_COLUMNS <- c(
  "term", "label", "season", "acad_year", "is_regular",
  "prev_term", "next_term", "prev_regular_term", "next_regular_term",
  "start_date", "census_date",
  "enrollment_rows", "graded_share", "newest_pull",
  "section_rows", "degrees_awarded",
  "is_enrolled", "is_settled", "is_graded", "in_progress", "has_degrees",
  "is_upcoming"
)


#' Build the term dimension
#'
#' @param students `cedar_students`. Required; supplies the terms with
#'   enrollment and, through `edges`, the right edges.
#' @param sections `cedar_sections` or NULL. Supplies `section_rows`,
#'   `start_date` and `census_date` (each the most common value among the
#'   term's sections, so part-term and late-start sections do not move it)
#'   and the upcoming terms that have a schedule but no class list yet.
#' @param degrees `cedar_degrees` or NULL. Supplies `degrees_awarded`.
#' @param edges The result of [cedar_data_edges()] on the same tables. Defaults
#'   to computing it, so the function stands alone; the app passes the edges it
#'   already computed so the two cannot disagree.
#' @param opt Unused; present for the branch calling convention.
#' @return A tibble with `CEDAR_TERMS_COLUMNS`, one row per term in the data
#'   plus every Fall and Spring between the first and last term with a class
#'   list (a gap term has zero enrollment and is reported), oldest first.
#'   Flags: `is_enrolled` has class-list rows; `is_settled` is enrolled
#'   and at or before `last_enrolled_complete`; `is_graded` is enrolled and at
#'   or before `last_graded`; `in_progress` is enrolled after `last_graded`;
#'   `has_degrees` is at or before `last_degree`; `is_upcoming` has sections
#'   and no class list after `last_enrolled`. A flag whose edge is NULL is NA.
build_cedar_terms <- function(students, sections = NULL, degrees = NULL,
                              edges = cedar_data_edges(students, degrees = degrees),
                              opt = list()) {
  if (is.null(students) || nrow(students) == 0L) {
    stop("[cedar-terms.R] build_cedar_terms() needs a non-empty students table.")
  }
  if (!"term" %in% names(students)) {
    stop("[cedar-terms.R] students is missing required column: term")
  }
  if (!is.null(sections)) {
    missing <- setdiff(c("term", "start_date", "census1"), names(sections))
    if (length(missing) > 0L) {
      stop("[cedar-terms.R] sections is missing required column(s): ",
           paste(missing, collapse = ", "))
    }
  }
  if (!is.null(degrees) && !"term" %in% names(degrees)) {
    stop("[cedar-terms.R] degrees is missing required column: term")
  }
  by_term <- edges$graded_by_term
  if (is.null(by_term) || !all(c("term", "rows", "graded_share") %in% names(by_term))) {
    stop("[cedar-terms.R] edges$graded_by_term is missing; build edges with cedar_data_edges().")
  }

  awarded <- NULL
  if (!is.null(degrees) && nrow(degrees) > 0L) {
    awarded <- dplyr::ungroup(degrees)
    if ("graduation_status" %in% names(awarded)) {
      awarded <- dplyr::filter(awarded, graduation_status == "Awarded")
    }
    awarded <- awarded %>%
      dplyr::filter(!is.na(term)) %>%
      dplyr::count(term, name = "degrees_awarded")
  }

  terms <- unique(c(
    as.integer(students$term),
    if (!is.null(sections)) as.integer(sections$term),
    if (!is.null(awarded)) as.integer(awarded$term)
  ))
  terms <- sort(terms[!is.na(terms)])
  bad <- terms[!grepl("^[0-9]{4}(10|60|80)$", terms)]
  if (length(bad) > 0L) {
    stop("[cedar-terms.R] term code(s) are not YYYYSS with SS in 10/60/80: ",
         paste(bad, collapse = ", "))
  }
  # A Fall or Spring with no class list between the first and last term that
  # has one is a row with zero enrollment, so next_regular_term always names a
  # row; it is never settled or graded (both require is_enrolled), and
  # build_student_terms() judges no return into it. It is reported here
  # because it means a pull is missing.
  classlist_terms <- sort(unique(as.integer(students$term)))
  classlist_terms <- classlist_terms[!is.na(classlist_terms)]
  run <- regular_terms_between(min(classlist_terms), max(classlist_terms))
  gaps <- setdiff(run, classlist_terms)
  if (length(gaps) > 0L) {
    message(sprintf(
      "[cedar-terms.R] Fall/Spring term(s) with no class list between %s and %s: %s. Each is a row with zero enrollment, never settled or graded, and no return is judged into it.",
      fmt_term(min(classlist_terms)), fmt_term(max(classlist_terms)),
      paste(fmt_term(gaps), collapse = ", ")))
  }
  terms <- sort(unique(c(terms, run)))

  dim <- tibble::tibble(term = terms) %>%
    add_acad_year(term) %>%
    dplyr::mutate(label = fmt_term(term), season = get_term_type(term),
                  is_regular = season %in% c("fall", "spring"))
  # Calendar neighbours, then the regular (Fall/Spring) ones: a Summer term's
  # next regular term is the Fall, and Spring's is the Fall, skipping Summer.
  dim <- add_prev_term_col(dim, term, summer = TRUE)
  dim <- add_next_term_col(dim, term, summer = TRUE)
  dim <- dim %>%
    dplyr::mutate(prev_term = as.integer(prev_term), next_term = as.integer(next_term))
  regular <- tibble::tibble(term = terms)
  regular <- add_prev_term_col(regular, term, summer = FALSE) %>%
    dplyr::rename(prev_regular_term = prev_term)
  regular <- add_next_term_col(regular, term, summer = FALSE) %>%
    dplyr::rename(next_regular_term = next_term) %>%
    dplyr::mutate(prev_regular_term = as.integer(prev_regular_term),
                  next_regular_term = as.integer(next_regular_term))
  dim <- dplyr::left_join(dim, regular, by = "term")

  enrollment <- by_term %>%
    dplyr::transmute(term = as.integer(term), enrollment_rows = as.integer(rows),
                     graded_share = as.numeric(graded_share),
                     newest_pull = if ("newest_pull" %in% names(by_term)) as.Date(newest_pull)
                                   else as.Date(NA))
  dim <- dplyr::left_join(dim, enrollment, by = "term") %>%
    dplyr::mutate(enrollment_rows = dplyr::coalesce(enrollment_rows, 0L))

  if (!is.null(sections) && nrow(sections) > 0L) {
    per_term <- dplyr::ungroup(sections) %>%
      dplyr::filter(!is.na(term)) %>%
      dplyr::group_by(term = as.integer(term)) %>%
      dplyr::summarize(section_rows = dplyr::n(),
                       start_date = .modal_date(start_date),
                       census_date = .modal_date(census1),
                       .groups = "drop")
    dim <- dplyr::left_join(dim, per_term, by = "term")
  } else {
    dim <- dplyr::mutate(dim, section_rows = NA_integer_,
                         start_date = as.Date(NA), census_date = as.Date(NA))
  }
  dim <- dplyr::mutate(dim, section_rows = dplyr::coalesce(section_rows, 0L))

  if (!is.null(awarded)) {
    dim <- dplyr::left_join(dim, awarded, by = "term")
  } else {
    dim <- dplyr::mutate(dim, degrees_awarded = NA_integer_)
  }
  dim <- dplyr::mutate(dim, degrees_awarded = dplyr::coalesce(as.integer(degrees_awarded), 0L))

  flag <- function(edge, condition) {
    if (is.null(edge)) rep(NA, nrow(dim)) else condition(as.integer(edge))
  }
  dim <- dim %>%
    dplyr::mutate(
      is_enrolled = enrollment_rows > 0L,
      is_settled  = flag(edges$last_enrolled_complete, function(e) is_enrolled & term <= e),
      is_graded   = flag(edges$last_graded, function(e) is_enrolled & term <= e),
      in_progress = flag(edges$last_graded, function(e) is_enrolled & term > e &
                           term <= as.integer(edges$last_enrolled)),
      has_degrees = flag(edges$last_degree, function(e) term <= e),
      is_upcoming = !is_enrolled & section_rows > 0L & term > as.integer(edges$last_enrolled)
    ) %>%
    dplyr::select(dplyr::all_of(CEDAR_TERMS_COLUMNS)) %>%
    dplyr::arrange(term)

  validate_cedar_terms(dim)
}


# The most common non-NA date in a vector, or NA when there is none.
.modal_date <- function(x) {
  x <- as.Date(x)
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(as.Date(NA))
  counts <- table(as.character(x))
  as.Date(names(counts)[which.max(counts)])
}


#' Check a term dimension
#'
#' @param terms A tibble as built by [build_cedar_terms()].
#' @return `terms`, unchanged, or an error naming what is wrong: a missing
#'   column, a repeated term, a term code that is not YYYYSS, or no row for a
#'   Fall or Spring between the first and last enrolled term.
validate_cedar_terms <- function(terms) {
  missing <- setdiff(CEDAR_TERMS_COLUMNS, names(terms))
  if (length(missing) > 0L) {
    stop("[cedar-terms.R] term dimension is missing column(s): ",
         paste(missing, collapse = ", "))
  }
  if (anyDuplicated(terms$term) > 0L) {
    stop("[cedar-terms.R] term dimension repeats term(s): ",
         paste(unique(terms$term[duplicated(terms$term)]), collapse = ", "))
  }
  bad <- terms$term[!grepl("^[0-9]{4}(10|60|80)$", terms$term)]
  if (length(bad) > 0L) {
    stop("[cedar-terms.R] term code(s) are not YYYYSS with SS in 10/60/80: ",
         paste(bad, collapse = ", "))
  }
  # Every Fall and Spring between the first and last ENROLLED term has a row,
  # with a class list (is_enrolled) or without one (a reported gap), so that
  # next_regular_term always names a row. Summer is optional.
  regular <- sort(terms$term[terms$is_regular & terms$is_enrolled])
  if (length(regular) > 1L) {
    missing_rows <- setdiff(regular_terms_between(regular[[1]], regular[[length(regular)]]),
                            terms$term)
    if (length(missing_rows) > 0L) {
      stop("[cedar-terms.R] term dimension has no row for Fall/Spring term(s) between ",
           fmt_term(regular[[1]]), " and ", fmt_term(regular[[length(regular)]]), ": ",
           paste(fmt_term(missing_rows), collapse = ", "))
    }
  }
  terms
}
