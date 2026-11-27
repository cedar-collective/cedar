# data-integrity.R — Cross-table student ID space checks
#
# Answers one question: can the stored CEDAR tables actually be joined to each
# other on student_id?
#
# That is not rhetorical. Student IDs are MD5-hashed once, at ingest, and frozen
# into the stored file forever (R/data-parsers/parse-data.R). If a MyReports pull
# presents the raw ID in a different surface form than an earlier pull — a
# numeric read that drops leading zeros, say — the hash differs and the rows for
# the same person can never be joined again. The pre-hash values are gone, so
# nothing downstream can repair it and no crosswalk can be recovered.
#
# The failure is invisible in every ordinary check. Row counts are right, terms
# are right, IDs look like well-formed hashes, and each table is internally
# coherent. Only a join reveals it, and a join that silently returns fewer rows
# looks like sparse data rather than a broken key. This is what let
# cedar_programs and cedar_degrees sit split at term 202480 — see ISSUES.md I1.
#
# Depends on: nothing outside dplyr. No other cones.


#' Check whether CEDAR tables share one student ID space
#'
#' Compares each table's student IDs, term by term, against a spine table whose
#' ID space is treated as canonical.
#'
#' @section Reading the result:
#'
#' The diagnostic signature of a broken ID space is a term with records and
#' \emph{exactly zero} matches. A table covering a genuinely different population
#' — applicants who never enrolled, say — lands somewhere in the middle in every
#' term and never at zero. A hash mismatch is all-or-nothing per term, because
#' every row in that term came from the same ingest.
#'
#' So a table is reported as \code{"split"} when it has both zero-match terms
#' and full-match terms. That mixture cannot be explained by population
#' differences: the same table joins perfectly in some terms and not at all in
#' others, which means it holds two ID spaces. A table that never joins fully
#' (applicants, degrees) is \code{"split"} too when one of its terms has no
#' match while others have some: it should land partway in every term.
#' Only a table with no match in any term is \code{"no overlap"}.
#'
#' A term the spine does not hold is \code{"unjudged"} when none of its IDs
#' match: its students may not have registered yet (an entering term's
#' applicants), or have left before the spine begins, so zero is not evidence
#' of a second ID space there. Such terms count toward no verdict. A term the
#' spine does not hold that has matches is judged as any other.
#'
#' @param spine  Data frame whose ID space is canonical. Pass `cedar_registrations`:
#'   the class lists are the only source ingested as one continuous series, and
#'   every other student table is meant to join to them.
#' @param tables Named list of data frames to check. Names are used as labels.
#' @param opt    Options list:
#'   \itemize{
#'     \item \code{id_col}     — character; default "student_id"
#'     \item \code{term_col}   — character; default "term"
#'     \item \code{spine_name} — character; label for the spine, default "spine"
#'   }
#' @return Named list:
#'   \itemize{
#'     \item \code{by_term} — tibble: table, term, n_ids, n_matched, pct_matched,
#'       term_status ("full", "partial", "none", "unjudged")
#'     \item \code{by_table} — tibble: table, n_terms, n_terms_full,
#'       n_terms_partial, n_terms_none, n_terms_unjudged, n_ids, n_ids_matched,
#'       pct_ids_matched, verdict ("split", "no overlap", "consistent", or
#'       "not judged" when every term is unjudged)
#'     \item \code{spine} — list(name, n_ids, n_terms)
#'     \item \code{n_tables_split} — count of tables with verdict "split"
#'   }
check_student_id_integrity <- function(spine, tables, opt = list()) {
  id_col     <- opt$id_col     %||% "student_id"
  term_col   <- opt$term_col   %||% "term"
  spine_name <- opt$spine_name %||% "spine"

  if (!is.data.frame(spine))
    stop("check_student_id_integrity: `spine` must be a data frame")
  if (!id_col %in% names(spine))
    stop("check_student_id_integrity: spine is missing the id column `", id_col, "`")
  if (!term_col %in% names(spine))
    stop("check_student_id_integrity: spine is missing the term column `", term_col, "`")
  if (!is.list(tables) || is.data.frame(tables))
    stop("check_student_id_integrity: `tables` must be a named list of data frames")
  if (length(tables) == 0L)
    stop("check_student_id_integrity: `tables` is empty — nothing to check")
  if (is.null(names(tables)) || any(names(tables) == ""))
    stop("check_student_id_integrity: every element of `tables` must be named")

  # Checked up front and all at once. A table silently skipped for a missing
  # column is the same class of bug this function exists to catch.
  for (nm in names(tables)) {
    tbl <- tables[[nm]]
    if (!is.data.frame(tbl))
      stop("check_student_id_integrity: `", nm, "` is not a data frame")
    absent <- setdiff(c(id_col, term_col), names(tbl))
    if (length(absent) > 0)
      stop("check_student_id_integrity: `", nm, "` is missing column(s): ",
           paste(absent, collapse = ", "))
  }

  spine_ids   <- unique(spine[[id_col]])
  spine_terms <- unique(spine[[term_col]])

  by_term <- lapply(names(tables), function(nm) {
    tables[[nm]] %>%
      distinct(.id = .data[[id_col]], .term = .data[[term_col]]) %>%
      group_by(.term) %>%
      summarize(
        n_ids     = n(),
        n_matched = sum(.id %in% spine_ids),
        .groups   = "drop"
      ) %>%
      mutate(
        table       = nm,
        pct_matched = round(100 * n_matched / n_ids, 1),
        # "none" is the signature worth naming: records exist for this term and
        # not one of them joins. Population differences never produce it.
        term_status = case_when(
          # Nobody in a term the spine does not hold may have registered yet.
          n_matched == 0L & !.term %in% spine_terms ~ "unjudged",
          n_matched == 0L     ~ "none",
          n_matched == n_ids  ~ "full",
          TRUE                ~ "partial"
        )
      ) %>%
      rename(term = .term) %>%
      select(table, term, n_ids, n_matched, pct_matched, term_status)
  }) %>%
    bind_rows() %>%
    arrange(table, term)

  by_table <- lapply(names(tables), function(nm) {
    ids     <- unique(tables[[nm]][[id_col]])
    terms   <- by_term %>% filter(table == nm)
    n_none  <- sum(terms$term_status == "none")
    n_full  <- sum(terms$term_status == "full")
    n_unjudged <- sum(terms$term_status == "unjudged")

    tibble(
      table           = nm,
      n_terms         = nrow(terms),
      n_terms_full    = n_full,
      n_terms_partial = sum(terms$term_status == "partial"),
      n_terms_none    = n_none,
      n_terms_unjudged = n_unjudged,
      n_ids           = length(ids),
      n_ids_matched   = sum(ids %in% spine_ids),
      pct_ids_matched = round(100 * sum(ids %in% spine_ids) / length(ids), 1),
      verdict = case_when(
        n_unjudged == nrow(terms) ~ "not judged",
        # Both extremes present: the table joins perfectly in some terms and not
        # at all in others. Only a hash change explains that.
        n_none > 0 & n_full > 0 ~ "split",
        # Nothing joins anywhere. Either an entirely separate ID space, or a
        # population with no overlap by design. Named distinctly because the
        # evidence does not distinguish them.
        n_none == nrow(terms) - n_unjudged ~ "no overlap",
        n_none > 0              ~ "split",
        TRUE                    ~ "consistent"
      )
    )
  }) %>%
    bind_rows() %>%
    arrange(desc(n_terms_none), table)

  list(
    by_term        = by_term,
    by_table       = by_table,
    spine          = list(name    = spine_name,
                          n_ids   = length(spine_ids),
                          n_terms = n_distinct(spine[[term_col]])),
    n_tables_split = sum(by_table$verdict == "split")
  )
}


#' The check's result as lines for a log
#'
#' One line for the spine, one per table with its verdict and term counts, then
#' every table-term, failures first. The transform prints it at every run
#' (`check_stored_student_ids()`), so a refresh log shows what the retired
#' Admin > Join Integrity page showed.
#'
#' @param res `check_student_id_integrity()` output.
#' @return Character vector, one line each.
format_student_id_integrity <- function(res) {
  tables <- res$by_table
  terms <- res$by_term[order(match(res$by_term$term_status, c("none", "partial", "unjudged", "full")),
                             res$by_term$table, res$by_term$term), ]
  c(sprintf("Student IDs against %s: %s IDs in %d terms.", res$spine$name,
            format(res$spine$n_ids, big.mark = ","), res$spine$n_terms),
    sprintf("%-22s %-11s %d terms: %d full, %d partial, %d with no match, %d not judged; %.1f%% of its IDs match",
            tables$table, tables$verdict, tables$n_terms, tables$n_terms_full, tables$n_terms_partial,
            tables$n_terms_none, tables$n_terms_unjudged, tables$pct_ids_matched),
    "By term (a term the class lists do not hold, with no match, is not judged):",
    utils::capture.output(print(data.frame(table = terms$table, term = as.character(terms$term),
      ids = terms$n_ids, matched = terms$n_matched, pct = sprintf("%.1f", terms$pct_matched),
      status = terms$term_status), row.names = FALSE)))
}
