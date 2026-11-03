# Keeping registration snapshots: one file per term per set of pulls.
#
# The refresh pipeline calls record_registration_snapshot() and
# record_return_snapshot() after each data refresh
# (scripts/record-registration-snapshot.R). The first keeps each course's
# counts for every term in registration or scheduled ahead of it
# (R/branches/registration-snapshots.R); the second keeps which of last term's
# students have registered for a Fall or Spring term in registration
# (R/branches/return-snapshots.R). A set of pulls already recorded is left
# alone, so a morning that brought no new class list writes nothing. The files
# are aggregates with no student ID; they live beside the projection bundles in
# output/, the only directory the refresh may write in production.

#' Terms still in registration, or scheduled and not yet open
#'
#' @param students,sections `cedar_students`, `cedar_sections`.
#' @return Every class-list or schedule term after the settled edge
#'   (`last_enrolled_complete`, see `cedar_data_edges()`), oldest first;
#'   `integer(0)` when there is none. Stops when the settled edge cannot be
#'   determined.
registration_snapshot_terms <- function(students, sections) {
  .terms_after_settled_edge(students, c(students$term, sections$term))
}


#' Fall and Spring terms whose registration has opened
#'
#' @param students `cedar_students`.
#' @return Every Fall or Spring class-list term after the settled edge, oldest
#'   first; `integer(0)` when there is none. Summer is never a term to return
#'   for, and a term with a draft schedule and no class list has had no
#'   registration yet. Stops when the settled edge cannot be determined.
return_snapshot_terms <- function(students) {
  terms <- .terms_after_settled_edge(students, students$term)
  types <- add_term_type_col(tibble(term = terms), term)$term_type
  terms[types %in% c("fall", "spring")]
}


# Terms after the settled edge (`last_enrolled_complete`), oldest first.
.terms_after_settled_edge <- function(students, terms) {
  edges <- cedar_data_edges(students)
  if (is.null(edges$last_enrolled_complete)) {
    stop("[registration-snapshots] The settled edge cannot be determined, so the ",
         "terms in registration are unknown.")
  }
  terms <- sort(unique(as.integer(terms)))
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
    status <- .save_snapshot_once(rows, path)
    tibble(term = term, classlist_as_of = classlist_as_of,
           sections_as_of = sections_as_of, path = path,
           rows = nrow(rows), status = status)
  })
  bind_rows(results)
}


# Write a snapshot unless its file already exists; atomic, so a failed write
# never leaves a partial file that a later run would take as recorded.
.save_snapshot_once <- function(rows, path) {
  if (file.exists(path)) {
    return("already recorded")
  }
  tmp <- tempfile(pattern = paste0(basename(path), ".tmp-"), tmpdir = dirname(path))
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  qs2::qs_save(rows, tmp)
  if (!file.rename(tmp, path)) {
    stop("[registration-snapshots] could not move ", tmp, " to ", path)
  }
  "written"
}


#' The file a term's return snapshot for one set of pulls is kept in
#'
#' Named by all three pull dates: the target term's class list (registration),
#' the anchor term's class list (withdrawals and grades) and the anchor term's
#' programs (unit and standing). A change in any one is a new snapshot.
#' @param output_dir Directory holding the snapshots.
#' @param term Target term code.
#' @param classlist_as_of,anchor_classlist_as_of,programs_as_of The pull dates.
return_snapshot_path <- function(output_dir, term, classlist_as_of,
                                 anchor_classlist_as_of, programs_as_of) {
  stamp <- function(date) format(as.Date(date))
  file.path(output_dir, paste0("return-", term, "-classlist-", stamp(classlist_as_of),
                               "-anchor-", stamp(anchor_classlist_as_of),
                               "-programs-", stamp(programs_as_of), ".qs2"))
}


#' Record today's return snapshot of every Fall or Spring term in registration
#'
#' @param students,programs `cedar_students`, `cedar_programs`.
#' @param output_dir Directory to write into; created if absent.
#' @param terms Target terms; default, the Fall and Spring terms whose
#'   registration has opened (`return_snapshot_terms()`).
#' @return One row per term: `term`, `anchor_term`, `classlist_as_of`, `path`,
#'   `rows`, `students`, `registered`, and `status` ("written" or
#'   "already recorded").
record_return_snapshot <- function(students, programs, output_dir,
                                   terms = return_snapshot_terms(students)) {
  if (length(terms) == 0L) {
    message("[registration-snapshots] No Fall or Spring term is in registration; no return snapshot recorded.")
    return(tibble(term = integer(0), anchor_term = integer(0),
                  classlist_as_of = as.Date(character(0)), path = character(0),
                  rows = integer(0), students = integer(0), registered = integer(0),
                  status = character(0)))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  snapshot <- build_return_snapshot(students, programs, list(terms = terms))

  results <- lapply(split(snapshot, snapshot$term), function(rows) {
    path <- return_snapshot_path(output_dir, rows$term[[1]], rows$classlist_as_of[[1]],
                                 rows$anchor_classlist_as_of[[1]], rows$programs_as_of[[1]])
    status <- .save_snapshot_once(rows, path)
    tibble(term = rows$term[[1]], anchor_term = rows$anchor_term[[1]],
           classlist_as_of = rows$classlist_as_of[[1]], path = path,
           students = sum(rows$students), registered = sum(rows$registered),
           rows = nrow(rows), status = status) %>%
      select(term, anchor_term, classlist_as_of, path, rows, students, registered, status)
  })
  bind_rows(results)
}


#' Read every return snapshot kept
#'
#' @param output_dir Directory holding the snapshots.
#' @param terms Optional target term codes to read; default, all.
#' @return All return snapshot rows, validated, oldest pull first. Zero rows
#'   when the directory holds none for the terms asked for; an error when the
#'   directory does not exist or a file is malformed.
read_return_snapshots <- function(output_dir, terms = NULL) {
  if (!dir.exists(output_dir)) {
    stop("[registration-snapshots] ", output_dir, " does not exist.")
  }
  files <- list.files(output_dir, pattern = "^return-[0-9]{6}-classlist-.*\\.qs2$",
                      full.names = TRUE)
  if (!is.null(terms)) {
    file_terms <- as.integer(sub("^return-([0-9]{6})-.*$", "\\1", basename(files)))
    files <- files[file_terms %in% as.integer(terms)]
  }
  rows <- lapply(files, function(path) {
    validate_return_snapshot(qs2::qs_read(path), source = path)
  })
  if (length(rows) == 0L) {
    return(as_tibble(setNames(
      rep(list(logical(0)), length(RETURN_SNAPSHOT_COLUMNS)),
      RETURN_SNAPSHOT_COLUMNS
    )))
  }
  bind_rows(rows) %>%
    arrange(term, classlist_as_of, anchor_classlist_as_of, programs_as_of)
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
