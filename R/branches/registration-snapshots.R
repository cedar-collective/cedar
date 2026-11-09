# Registration snapshots: what the class lists and the schedule say about a term
# still in registration, on the day they were pulled.
#
# CEDAR keeps one class list and one schedule per term, overwritten by every
# refresh, so the registration-to-date count a course had in week 3 of Spring
# registration is gone by week 4. A status date cannot rebuild it: a student who
# registered and later dropped carries only the date of the drop, and a waiting
# student who got a seat leaves no waitlist row. Revising a Spring projection by
# pace -- this week's registrations against the same week a year earlier -- needs
# those counts kept as they were (ROADMAP, enrollment projections). The draft
# schedule moves the same way before registration opens, so a term with a
# schedule and no class list yet is kept too, its class-list counts unknown.
#
# One row per term, delivery campus, college, course and part of term, the
# grain of cedar_course_terms (R/branches/course-terms.R) and the canonical
# waitlist rule. The registrations, drops, sections and seats are that table's
# (ADR-001 step 7: the refresh rebuilds it from the same pull before this runs,
# and a table not current for the class list is refused); the waitlist count
# is class-list true demand, which the table does not carry. Part of term is
# kept so a reader can leave out intersession, as projections do. The class
# list holds one row per student, course, campus and term, so the part-of-term
# rows sum to the course. A crosslisted section and its seats are counted once,
# under its home listing; students who registered under a partner listing stay
# on the partner's row, which can therefore hold students and no section. No
# student ID leaves this function.

REGISTRATION_SNAPSHOT_SCHEMA_VERSION <- 1L

REGISTRATION_SNAPSHOT_COLUMNS <- c(
  "schema_version", "term", "campus", "college", "subject_course", "part_term",
  "classlist_as_of", "sections_as_of", "registered", "waitlisted", "dr_early",
  "dr_late", "sections", "seats"
)


#' Build one registration snapshot
#'
#' @param students `cedar_registrations` rows (all terms are accepted; only
#'   `opt$terms` are read): the waitlist count and the class list's pull date.
#' @param sections `cedar_sections` rows: the schedule's pull date and the
#'   waitlist rule's section scope.
#' @param course_terms `cedar_course_terms`, current for `students`: the
#'   registrations, drops, sections and seats.
#' @param opt `terms` (required): the terms to snapshot, normally those still
#'   in registration (see `registration_snapshot_terms()`).
#' @return A tibble with `REGISTRATION_SNAPSHOT_COLUMNS`. `classlist_as_of` and
#'   `sections_as_of` are each term's newest pull date, `NA` for a source with
#'   no rows for the term. Within a source that has the term, a course it does
#'   not list is a measured zero (nobody registered yet, no active section);
#'   for a source without the term, that source's counts are `NA`, unknown.
build_registration_snapshot <- function(students, sections, course_terms, opt = list()) {
  terms <- opt$terms
  if (is.null(terms) || length(terms) == 0L) {
    stop("[registration-snapshots.R] opt$terms is required: the terms to snapshot.")
  }
  terms <- as.integer(terms)
  required_students <- c("term", "term_type", "campus", "college", "subject_course",
                         "part_term", "student_id", "registration_status_code",
                         "course_title", "as_of_date")
  required_sections <- c("term", "campus", "college", "subject_course", "part_term",
                         "status", "as_of_date")
  missing_students <- setdiff(required_students, names(students))
  missing_sections <- setdiff(required_sections, names(sections))
  if (length(missing_students) > 0L || length(missing_sections) > 0L) {
    stop("[registration-snapshots.R] missing column(s): students [",
         paste(missing_students, collapse = ", "), "], sections [",
         paste(missing_sections, collapse = ", "), "]")
  }

  require_current_course_terms(course_terms, students, "build_registration_snapshot")

  keys <- c("term", "campus", "college", "subject_course", "part_term")
  term_students <- students %>%
    ungroup() %>%
    mutate(term = as.integer(term)) %>%
    filter(term %in% terms)
  term_sections <- sections %>%
    ungroup() %>%
    mutate(term = as.integer(term)) %>%
    filter(term %in% terms)

  absent <- setdiff(terms, union(term_students$term, term_sections$term))
  if (length(absent) > 0L) {
    stop("[registration-snapshots.R] no class-list or section rows for term(s) ",
         paste(absent, collapse = ", "), ": nothing to snapshot.")
  }

  # Each source's newest pull per term; a term with rows but no pull date
  # cannot be placed in time, so it stops here.
  newest_pull <- function(rows, name) {
    if (nrow(rows) == 0L) {
      return(tibble(term = integer(0), !!name := as.Date(character(0))))
    }
    pulled <- rows %>%
      group_by(term) %>%
      summarize(!!name := suppressWarnings(max(as.Date(as_of_date), na.rm = TRUE)),
                .groups = "drop")
    undated <- pulled$term[!is.finite(pulled[[name]])]
    if (length(undated) > 0L) {
      stop("[registration-snapshots.R] no pull date (as_of_date) for term(s) ",
           paste(undated, collapse = ", "), ".")
    }
    pulled
  }
  pulls <- tibble(term = terms) %>%
    left_join(newest_pull(term_students, "classlist_as_of"), by = "term") %>%
    left_join(newest_pull(term_sections, "sections_as_of"), by = "term")

  # The two sides of the course-term table for these terms: the class list's
  # registrations and drops, and the schedule's active sections and seats
  # (every active section, crosslists counted once under the home listing,
  # nothing left out by the exclusion list: the snapshot is a record, and its
  # readers choose a scope). A side the table has no row for is NA there and
  # is decided below by whether the source has a pull for the term.
  term_rows <- course_terms %>%
    filter(term %in% terms) %>%
    mutate(term = as.integer(term))
  classlist <- term_rows %>%
    filter(!is.na(registered)) %>%
    select(all_of(keys), registered, dr_early, dr_late)
  scheduled <- term_rows %>%
    filter(!is.na(sections)) %>%
    transmute(across(all_of(keys)), sections = as.integer(sections), seats = pmax(0, seats))

  waitlisted <- if (nrow(term_students) == 0L) {
    tibble(term = integer(0), campus = character(0), college = character(0),
           subject_course = character(0), part_term = character(0), waitlisted = integer(0))
  } else {
    get_true_waitlisted_rows(term_students, sections = term_sections) %>%
      summarize_waitlist_demand(group_cols = keys, count_name = "waitlisted")
  }

  snapshot <- classlist %>%
    full_join(waitlisted, by = keys) %>%
    full_join(scheduled, by = keys) %>%
    left_join(pulls, by = "term") %>%
    # A course one source does not list is a measured zero on that source's
    # pull; a source with no pull for the term leaves its counts unknown.
    mutate(
      across(c(registered, waitlisted, dr_early, dr_late),
             ~ if_else(is.na(classlist_as_of), NA_integer_,
                       as.integer(dplyr::coalesce(.x, 0L)))),
      sections = if_else(is.na(sections_as_of), NA_integer_,
                         as.integer(dplyr::coalesce(sections, 0L))),
      seats = if_else(is.na(sections_as_of), NA_real_, dplyr::coalesce(seats, 0))
    ) %>%
    mutate(schema_version = REGISTRATION_SNAPSHOT_SCHEMA_VERSION) %>%
    select(all_of(REGISTRATION_SNAPSHOT_COLUMNS)) %>%
    arrange(term, campus, subject_course, part_term, college)
  # A record of its own, not the measure table: its stamps do not travel.
  for (stamp in c("code_renames", "graded_edge", "course_terms_build_version")) {
    attr(snapshot, stamp) <- NULL
  }

  if (exists("cedar_log_level")) {
    cedar_debug("[registration-snapshots.R] ", nrow(snapshot), " rows for term(s) ",
                paste(terms, collapse = ", "))
  }
  snapshot
}


#' Check a snapshot read back from disk
#'
#' @param snapshot A tibble read from a snapshot file.
#' @param source A label for the error message, normally the file path.
#' @return `snapshot`, unchanged, or an error naming what is wrong.
validate_registration_snapshot <- function(snapshot, source = "snapshot") {
  missing <- setdiff(REGISTRATION_SNAPSHOT_COLUMNS, names(snapshot))
  if (length(missing) > 0L) {
    stop("[registration-snapshots.R] ", source, " is missing column(s): ",
         paste(missing, collapse = ", "))
  }
  versions <- unique(snapshot$schema_version)
  if (!identical(as.integer(versions), REGISTRATION_SNAPSHOT_SCHEMA_VERSION)) {
    stop("[registration-snapshots.R] ", source, " has schema version ",
         paste(versions, collapse = ", "), "; this code reads ",
         REGISTRATION_SNAPSHOT_SCHEMA_VERSION, ".")
  }
  if (anyDuplicated(snapshot[c("term", "campus", "college", "subject_course",
                               "part_term")]) > 0L) {
    stop("[registration-snapshots.R] ", source, " repeats a course row.")
  }
  snapshot
}
