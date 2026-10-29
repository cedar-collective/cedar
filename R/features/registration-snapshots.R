# Keeping registration snapshots: one file per term per pair of pulls.
#
# The refresh pipeline calls record_registration_snapshot() after each data
# refresh (scripts/record-registration-snapshot.R), for every term in
# registration or scheduled ahead of it. A pair of pulls already recorded is
# left alone, so a morning that brought no new class list or schedule writes
# nothing. The files are aggregates with no student ID; they live beside the
# projection bundles in output/, the only directory the refresh may write in
# production.

#' Terms still in registration, or scheduled and not yet open
#'
#' @param students,sections `cedar_students`, `cedar_sections`.
#' @return Every class-list or schedule term after the settled edge
#'   (`last_enrolled_complete`, see `cedar_data_edges()`), oldest first;
#'   `integer(0)` when there is none. Stops when the settled edge cannot be
#'   determined.
registration_snapshot_terms <- function(students, sections) {
  edges <- cedar_data_edges(students)
  if (is.null(edges$last_enrolled_complete)) {
    stop("[registration-snapshots] The settled edge cannot be determined, so the ",
         "terms in registration are unknown.")
  }
  terms <- sort(unique(c(as.integer(students$term), as.integer(sections$term))))
  terms[!is.na(terms) & terms > edges$last_enrolled_complete]
}


#' The file a term's snapshot for one pair of pulls is kept in
#'
#' Named by both pull dates, so a new schedule with an unchanged class list,
#' or the reverse, is a new snapshot. "none" stands for a source with no pull.
#' @param output_dir Directory holding the snapshots.
#' @param term Term code.
#' @param classlist_as_of,sections_as_of The two pull dates (Date or NA).
registration_snapshot_path <- function(output_dir, term, classlist_as_of, sections_as_of) {
  stamp <- function(date) if (is.na(date)) "none" else format(as.Date(date))
  file.path(output_dir, paste0("registration-", term, "-classlist-", stamp(classlist_as_of),
                               "-schedule-", stamp(sections_as_of), ".qs2"))
}


#' Record today's snapshot of every term in registration
#'
#' @param students,sections `cedar_students`, `cedar_sections`.
#' @param output_dir Directory to write into; created if absent.
#' @param terms Terms to record; default, those still in registration or
#'   scheduled and not yet open.
#' @return One row per term: `term`, `classlist_as_of`, `sections_as_of`,
#'   `path`, `rows`, and `status` ("written" or "already recorded").
record_registration_snapshot <- function(students, sections, output_dir,
                                         terms = registration_snapshot_terms(students, sections)) {
  if (length(terms) == 0L) {
    message("[registration-snapshots] No term is in registration or scheduled ahead; nothing recorded.")
    return(tibble(term = integer(0), classlist_as_of = as.Date(character(0)),
                  sections_as_of = as.Date(character(0)), path = character(0),
                  rows = integer(0), status = character(0)))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  snapshot <- build_registration_snapshot(students, sections, list(terms = terms))

  results <- lapply(split(snapshot, snapshot$term), function(rows) {
    term <- rows$term[[1]]
    classlist_as_of <- rows$classlist_as_of[[1]]
    sections_as_of <- rows$sections_as_of[[1]]
    path <- registration_snapshot_path(output_dir, term, classlist_as_of, sections_as_of)
    status <- if (file.exists(path)) {
      "already recorded"
    } else {
      tmp <- tempfile(pattern = paste0(basename(path), ".tmp-"), tmpdir = output_dir)
      on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
      qs2::qs_save(rows, tmp)
      if (!file.rename(tmp, path)) {
        stop("[registration-snapshots] could not move ", tmp, " to ", path)
      }
      "written"
    }
    tibble(term = term, classlist_as_of = classlist_as_of,
           sections_as_of = sections_as_of, path = path,
           rows = nrow(rows), status = status)
  })
  bind_rows(results)
}


#' Read every snapshot kept
#'
#' @param output_dir Directory holding the snapshots.
#' @param terms Optional term codes to read; default, all.
#' @return All snapshot rows, validated, oldest pull first. Zero rows when the
#'   directory holds none for the terms asked for; an error when the directory
#'   does not exist or a file is malformed.
read_registration_snapshots <- function(output_dir, terms = NULL) {
  if (!dir.exists(output_dir)) {
    stop("[registration-snapshots] ", output_dir, " does not exist.")
  }
  files <- list.files(output_dir, pattern = "^registration-[0-9]{6}-classlist-.*\\.qs2$",
                      full.names = TRUE)
  if (!is.null(terms)) {
    file_terms <- as.integer(sub("^registration-([0-9]{6})-.*$", "\\1", basename(files)))
    files <- files[file_terms %in% as.integer(terms)]
  }
  rows <- lapply(files, function(path) {
    validate_registration_snapshot(qs2::qs_read(path), source = path)
  })
  if (length(rows) == 0L) {
    empty <- as_tibble(setNames(
      rep(list(logical(0)), length(REGISTRATION_SNAPSHOT_COLUMNS)),
      REGISTRATION_SNAPSHOT_COLUMNS
    ))
    return(empty)
  }
  bind_rows(rows) %>%
    arrange(term, classlist_as_of, sections_as_of, campus, subject_course, part_term)
}
