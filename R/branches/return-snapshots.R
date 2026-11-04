# Return snapshots: which of last term's students have registered for the next
# one, on the day the class lists were pulled.
#
# A student who has not registered for next term is the earliest sign CEDAR can
# see that they may not return, and the broadest: on Dec 1, 2025 a third of
# Fall 2025's undergraduates had not registered for Spring 2026, nearly every
# eventual non-returner among them, and 63% of the group came back on its own.
# So the count means something only beside the same day a year earlier, and a
# past day cannot be rebuilt: Banner overwrites a row's status date when the
# student drops, and a waiting student who got a seat leaves no waitlist row.
# The refresh keeps it instead, as R/branches/registration-snapshots.R keeps the
# course counts.
#
# Everything here is read off cedar_student_terms (ADR-001 step 2; contract in
# docs/developers/student-terms.md), one row per student-term, so the snapshot
# counts the same enrolled student, the same late withdrawal and the same DFW
# grade as Roadblocks, Retention and the credit timeline. The population is
# every student `enrolled` in the term before the one in registration (the
# anchor term): registered or withdrawn after census, CEDAR's one definition;
# an early drop never attended and is not in it. Fall and Spring only: Summer is
# not a term students are expected to return for, so it is never a target, and
# the anchor of a Fall target is the Spring before it. Whether a student has
# registered is read UNM-wide, on every campus, as retention reads it: moving
# campus is not leaving.
#
# One row per anchor-term group: home campus, primary major's unit and college,
# level, classification, standing (the table's description columns, academic
# studies' value where there is one and the class list's otherwise), and two
# warning signs known on the pull day. `late_withdrawal` is the share of the
# student's anchor courses dropped after census (`late_withdrawals` against
# `registered_courses`); `dfw_grades` counts the DFW grades posted so far, late
# drops left out because they have their own column, and reads "none posted"
# until the first grade lands (`graded_rows` of 0). Values are kept as recorded,
# ungrouped: readers choose the bands. Students who will graduate at the end of
# the anchor term are in the population, their degree not yet recorded; a
# comparison with the same day a year earlier carries the same mix. No student
# ID leaves this function.

RETURN_SNAPSHOT_SCHEMA_VERSION <- 1L

RETURN_SNAPSHOT_KEYS <- c(
  "term", "anchor_term", "student_campus", "college_code", "dept_code",
  "major_code", "student_level", "student_classification", "academic_standing",
  "late_withdrawal", "dfw_grades"
)

RETURN_SNAPSHOT_COLUMNS <- c(
  "schema_version", "term", "anchor_term", "classlist_as_of",
  "anchor_classlist_as_of", "programs_as_of",
  setdiff(RETURN_SNAPSHOT_KEYS, c("term", "anchor_term")),
  "students", "registered", "waitlisted_only", "dropped_only"
)

RETURN_SNAPSHOT_INPUT_COLUMNS <- c(
  "student_id", "term", "classlist_as_of", "programs_as_of",
  "class_list_rows", "enrolled", "registered_courses", "late_withdrawals",
  "waitlisted_only", "dfw_grades", "graded_rows",
  "student_campus", "student_level", "student_classification", "academic_standing",
  "primary_major_code", "primary_dept_code", "primary_college_code"
)


#' Build one return snapshot
#'
#' @param student_terms `cedar_student_terms`; only each target term and its
#'   anchor are read.
#' @param opt `terms` (required): the Fall or Spring terms in registration.
#' @return A tibble with `RETURN_SNAPSHOT_COLUMNS`, one row per anchor-term
#'   group. `students` is the group's size; `registered` has a registered
#'   course for the target term, `waitlisted_only` only waitlist rows,
#'   `dropped_only` only drops. The rest of the group has no target-term row yet.
build_return_snapshot <- function(student_terms, opt = list()) {
  terms <- opt$terms
  if (is.null(terms) || length(terms) == 0L) {
    stop("[return-snapshots.R] opt$terms is required: the terms in registration.")
  }
  missing_cols <- setdiff(RETURN_SNAPSHOT_INPUT_COLUMNS, names(student_terms))
  if (length(missing_cols) > 0L) {
    stop("[return-snapshots.R] student_terms is missing column(s): ",
         paste(missing_cols, collapse = ", "), ". Expected cedar_student_terms.")
  }

  pairs <- tibble(term = as.integer(terms)) %>%
    add_term_type_col(term) %>%
    add_prev_term_col(term, summer = FALSE) %>%
    transmute(term, anchor_term = as.integer(prev_term), term_type)
  not_regular <- pairs$term[!pairs$term_type %in% c("fall", "spring")]
  if (length(not_regular) > 0L) {
    stop("[return-snapshots.R] term(s) ", paste(not_regular, collapse = ", "),
         " are not Fall or Spring: only a regular term is one to return for.")
  }

  bind_rows(lapply(seq_len(nrow(pairs)), function(i) {
    .return_snapshot_term(student_terms, pairs$term[[i]], pairs$anchor_term[[i]])
  })) %>%
    arrange(term, student_campus, college_code, dept_code, major_code,
            student_level, student_classification, academic_standing,
            late_withdrawal, dfw_grades)
}


# The snapshot for one target term and its anchor.
.return_snapshot_term <- function(student_terms, term, anchor_term) {
  pulled <- function(dates, what, which_term) {
    dates <- as.Date(dates)
    if (length(dates) == 0L || all(is.na(dates))) {
      stop("[return-snapshots.R] no ", what, " pull date for term ", which_term, ".")
    }
    max(dates, na.rm = TRUE)
  }

  rows <- student_terms %>% ungroup()
  # A row for the target term exists for a declaration alone; registration is
  # a class-list row.
  target_rows <- rows %>%
    filter(as.integer(.data$term) == !!term, class_list_rows > 0L)
  anchor_rows <- rows %>%
    filter(as.integer(.data$term) == !!anchor_term, enrolled)
  if (nrow(target_rows) == 0L) {
    stop("[return-snapshots.R] no class-list rows for term ", term,
         ": registration has not opened, so there is nothing to snapshot.")
  }
  if (nrow(anchor_rows) == 0L) {
    stop("[return-snapshots.R] no enrolled students in anchor term ", anchor_term, ".")
  }
  classlist_as_of <- pulled(target_rows$classlist_as_of, "class-list", term)
  anchor_classlist_as_of <- pulled(anchor_rows$classlist_as_of, "class-list", anchor_term)
  programs_as_of <- pulled(anchor_rows$programs_as_of, "programs", anchor_term)

  target <- target_rows %>%
    transmute(student_id,
              registered = registered_courses > 0L,
              target_waitlisted_only = waitlisted_only,
              target_rows = class_list_rows)

  snapshot <- anchor_rows %>%
    transmute(
      student_id, student_campus, student_level, student_classification,
      academic_standing,
      major_code = primary_major_code, dept_code = primary_dept_code,
      college_code = primary_college_code,
      late_withdrawal = case_when(late_withdrawals == 0L ~ "none",
                                  registered_courses == 0L ~ "all",
                                  TRUE ~ "some"),
      # Posted grades only: a blank grade is unknown, never a pass or a fail
      # (AGENTS.md, right-edge policy). Late drops have their own column.
      dfw_grades = case_when(graded_rows == 0L ~ "none posted",
                             dfw_grades == 0L ~ "0",
                             dfw_grades == 1L ~ "1",
                             TRUE ~ "2+")
    ) %>%
    left_join(target, by = "student_id") %>%
    mutate(
      registered = coalesce(registered, FALSE),
      waitlisted_only = !registered & coalesce(target_waitlisted_only, FALSE),
      dropped_only = !registered & !waitlisted_only & coalesce(target_rows, 0L) > 0L,
      term = as.integer(term), anchor_term = as.integer(anchor_term)
    ) %>%
    group_by(across(all_of(RETURN_SNAPSHOT_KEYS))) %>%
    summarize(students = n(),
              registered = sum(registered),
              waitlisted_only = sum(waitlisted_only),
              dropped_only = sum(dropped_only),
              .groups = "drop") %>%
    mutate(schema_version = RETURN_SNAPSHOT_SCHEMA_VERSION,
           classlist_as_of = classlist_as_of,
           anchor_classlist_as_of = anchor_classlist_as_of,
           programs_as_of = programs_as_of) %>%
    select(all_of(RETURN_SNAPSHOT_COLUMNS))

  if (exists("cedar_log_level")) {
    cedar_debug("[return-snapshots.R] ", fmt_term(term), ": ", sum(snapshot$students),
                " students from ", fmt_term(anchor_term), ", ",
                sum(snapshot$registered), " registered, in ", nrow(snapshot), " rows")
  }
  snapshot
}


#' Check a return snapshot read back from disk
#'
#' @param snapshot A tibble read from a return snapshot file.
#' @param source A label for the error message, normally the file path.
#' @return `snapshot`, unchanged, or an error naming what is wrong.
validate_return_snapshot <- function(snapshot, source = "return snapshot") {
  missing <- setdiff(RETURN_SNAPSHOT_COLUMNS, names(snapshot))
  if (length(missing) > 0L) {
    stop("[return-snapshots.R] ", source, " is missing column(s): ",
         paste(missing, collapse = ", "))
  }
  versions <- unique(snapshot$schema_version)
  if (!identical(as.integer(versions), RETURN_SNAPSHOT_SCHEMA_VERSION)) {
    stop("[return-snapshots.R] ", source, " has schema version ",
         paste(versions, collapse = ", "), "; this code reads ",
         RETURN_SNAPSHOT_SCHEMA_VERSION, ".")
  }
  if (anyDuplicated(snapshot[RETURN_SNAPSHOT_KEYS]) > 0L) {
    stop("[return-snapshots.R] ", source, " repeats a group row.")
  }
  parts <- snapshot$registered + snapshot$waitlisted_only + snapshot$dropped_only
  if (any(parts > snapshot$students) || any(snapshot$students < 1L)) {
    stop("[return-snapshots.R] ", source, " has a group whose counts exceed its students.")
  }
  snapshot
}
