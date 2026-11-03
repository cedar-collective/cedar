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
# The population is every student enrolled in the term before the one in
# registration (the anchor term), registered or withdrawn after census; an
# early drop never attended and is not in it. Fall and Spring only: Summer is
# not a term students are expected to return for, so it is never a target, and
# the anchor of a Fall target is the Spring before it. Whether a student has
# registered is read UNM-wide, on every campus, as retention reads it
# (R/branches/retention-context.R): moving campus is not leaving.
#
# One row per anchor-term group: home campus, primary major's unit and college,
# level, classification, standing, and two warning signs known on the pull day.
# `late_withdrawal` is the share of the student's anchor courses dropped after
# census; `dfw_grades` counts the DFW grades posted so far, late drops left out
# because they have their own column, and reads "none posted" until the first
# grade lands. Values are kept as Banner recorded them, ungrouped: readers choose
# the bands. Students who will graduate at the end of the anchor term are in the
# population, their degree not yet recorded; a comparison with the same day a
# year earlier carries the same mix. No student ID leaves this function.

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


#' Build one return snapshot
#'
#' @param students `cedar_students` rows; only each target term and its anchor
#'   are read.
#' @param programs `cedar_programs` rows; only the anchor terms are read.
#' @param opt `terms` (required): the Fall or Spring terms in registration.
#' @return A tibble with `RETURN_SNAPSHOT_COLUMNS`, one row per anchor-term
#'   group. `students` is the group's size; `registered` holds a registered row
#'   for the target term, `waitlisted_only` only waitlist rows, `dropped_only`
#'   only drops. The rest of the group has no target-term row yet.
build_return_snapshot <- function(students, programs, opt = list()) {
  terms <- opt$terms
  if (is.null(terms) || length(terms) == 0L) {
    stop("[return-snapshots.R] opt$terms is required: the terms in registration.")
  }
  required_students <- c("term", "student_id", "registration_status_code",
                         "final_grade", "student_level", "student_classification",
                         "student_campus", "as_of_date")
  required_programs <- c("term", "student_id", "program_type", "major_code",
                         "dept_code", "college_code", "academic_standing",
                         "as_of_date")
  missing_students <- setdiff(required_students, names(students))
  missing_programs <- setdiff(required_programs, names(programs))
  if (length(missing_students) > 0L || length(missing_programs) > 0L) {
    stop("[return-snapshots.R] missing column(s): students [",
         paste(missing_students, collapse = ", "), "], programs [",
         paste(missing_programs, collapse = ", "), "]")
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
    .return_snapshot_term(students, programs, pairs$term[[i]], pairs$anchor_term[[i]])
  })) %>%
    arrange(term, student_campus, college_code, dept_code, major_code,
            student_level, student_classification, academic_standing,
            late_withdrawal, dfw_grades)
}


# The snapshot for one target term and its anchor.
.return_snapshot_term <- function(students, programs, term, anchor_term) {
  pulled <- function(rows, what, which_term) {
    dates <- as.Date(rows$as_of_date)
    if (nrow(rows) == 0L || all(is.na(dates))) {
      stop("[return-snapshots.R] no ", what, " pull date for term ", which_term, ".")
    }
    max(dates, na.rm = TRUE)
  }

  target_rows <- students %>% ungroup() %>% filter(as.integer(.data$term) == !!term)
  anchor_rows <- students %>% ungroup() %>%
    filter(as.integer(.data$term) == !!anchor_term,
           registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE))
  anchor_programs <- programs %>% ungroup() %>%
    filter(as.integer(.data$term) == !!anchor_term)
  if (nrow(target_rows) == 0L) {
    stop("[return-snapshots.R] no class-list rows for term ", term,
         ": registration has not opened, so there is nothing to snapshot.")
  }
  if (nrow(anchor_rows) == 0L) {
    stop("[return-snapshots.R] no enrolled students in anchor term ", anchor_term, ".")
  }
  classlist_as_of <- pulled(target_rows, "class-list", term)
  anchor_classlist_as_of <- pulled(anchor_rows, "class-list", anchor_term)
  programs_as_of <- pulled(anchor_programs, "programs", anchor_term)

  one_value <- function(rows, cols, what) {
    values <- rows %>% distinct(across(all_of(c("student_id", cols))))
    repeated <- values$student_id[duplicated(values$student_id)]
    if (length(repeated) > 0L) {
      stop("[return-snapshots.R] ", length(unique(repeated)), " student(s) carry more ",
           "than one ", what, " in term ", anchor_term, ".")
    }
    values
  }

  population <- anchor_rows %>%
    group_by(student_id) %>%
    summarize(courses = n(),
              late = sum(registration_status_code %in% STATUS_DROP_LATE),
              .groups = "drop") %>%
    left_join(one_value(anchor_rows,
                        c("student_campus", "student_level", "student_classification"),
                        "home campus, level or classification"),
              by = "student_id")

  # Posted grades only: a blank grade is unknown, never a pass or a fail
  # (AGENTS.md, right-edge policy). Late drops have their own column.
  graded <- anchor_rows %>%
    filter(!registration_status_code %in% STATUS_DROP_LATE) %>%
    classify_enrollment_outcomes() %>%
    group_by(student_id) %>%
    summarize(dfw = sum(outcome == "dfw"), .groups = "drop")

  # The primary major is the first Major row by code, the rule the transform
  # uses for a student's unit and college (transform-to-cedar.R).
  primary <- anchor_programs %>%
    filter(program_type == "Major") %>%
    arrange(student_id, major_code) %>%
    distinct(student_id, .keep_all = TRUE) %>%
    select(student_id, major_code, dept_code, college_code)
  standing <- one_value(filter(anchor_programs, !is.na(academic_standing)),
                        "academic_standing", "academic standing")

  target <- target_rows %>%
    group_by(student_id) %>%
    summarize(registered = any(registration_status_code %in% STATUS_REGISTERED),
              waitlisted = any(registration_status_code %in% STATUS_WAITLIST),
              rows = n(), .groups = "drop")

  snapshot <- population %>%
    left_join(graded, by = "student_id") %>%
    left_join(primary, by = "student_id") %>%
    left_join(standing, by = "student_id") %>%
    left_join(target, by = "student_id") %>%
    mutate(
      late_withdrawal = case_when(late == 0L ~ "none",
                                  late < courses ~ "some",
                                  TRUE ~ "all"),
      dfw_grades = case_when(is.na(dfw) ~ "none posted",
                             dfw == 0L ~ "0",
                             dfw == 1L ~ "1",
                             TRUE ~ "2+"),
      registered = coalesce(registered, FALSE),
      waitlisted_only = !registered & coalesce(waitlisted, FALSE),
      dropped_only = !registered & !waitlisted_only & coalesce(rows, 0L) > 0L,
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
