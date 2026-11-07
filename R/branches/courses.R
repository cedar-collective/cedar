# courses.R — the course dimension: one row per course in the loaded data
#
# ADR-001 step 4 (docs/developers/adr-001-domain-data-model.md). A course is
# the thing a department teaches across the years; a course code is what the
# registrar calls it in one term. The two part company when a subject is
# renamed (SOC became SOCI, ISSUES I45) or a course is renumbered (MGMT 340
# became ACCT 3401, I37): every reader that groups on `subject_course` then
# sees two courses, the old one dying and the new one arriving from nowhere.
#
# The dimension gives every code in the data one `course_id`: the last code of
# its confirmed succession chain in institution/<id>/code_history.csv, or the
# code itself when nothing succeeds it. A chain may mix kinds — SOC 250 takes
# the subject's rename to SOCI 250, then that course's renumbering to SOCI
# 2315 — and is followed step by step. Only confirmed rows are followed: a
# proposed row is a candidate from detect_course_renamings(), and the
# dimension keeps its two codes as two courses until someone confirms it.
#
#   cedar_courses       one row per course_id: subject, number and level of
#                       the current code, the latest title, first and last
#                       term over every code, how many codes and which
#   cedar_course_codes  one row per code in the data: its course_id, where
#                       and when the code appears, how many successions it
#                       took to reach the id
#
# Every loader keys its tables on the course once, in attach_course_ids()
# (decided 2026-11-07): `subject_course` on the loaded cedar_sections,
# cedar_students and cedar_grades carries each row's `course_id`, and the code
# the registrar used that term moves to `listed_code`. A reader that filters,
# groups or joins on `subject_course` therefore follows the course across its
# codes with nothing to remember, and a reader that names the term's code (a
# section listing, "also listed as SOC 371") reads `listed_code`. Nothing is
# saved: the files keep the registrar's code, and a confirmed row in
# code_history.csv changes the ids at the next start, as a unit decision does.
# The two code-level functions, build_cedar_courses() and
# detect_course_renamings(), read the registrar's code (.registrar_codes()).
#
# CAMPUS_ROLLUP: a course is one course wherever it is taught; the dimension
# has no campus, and attaching an id to a row takes nothing from the row's
# campus. The campus policy applies to the measures grouped by course_id,
# exactly as it applies to those grouped by subject_course.

CEDAR_COURSES_COLUMNS <- c(
  "course_id", "subject", "course_number", "level", "course_title",
  "first_term", "last_term", "n_codes", "former_codes",
  "in_sections", "in_class_lists"
)

CEDAR_COURSE_CODES_COLUMNS <- c(
  "subject_course", "course_id", "subject", "course_number",
  "first_term", "last_term", "in_sections", "in_class_lists", "steps"
)

# The columns attach_course_ids() writes on each fact table, which a loader
# drops before attaching so a stamped file and an unstamped one load the same.
CEDAR_ATTACHED_COURSE_COLUMNS <- list(
  cedar_sections = c("course_id", "listed_code"),
  cedar_students = c("course_id", "listed_code"),
  cedar_grades = c("course_id", "listed_code")
)

# A loaded table as the registrar wrote it: `subject_course` the term's code.
# For the code-level functions only (the dimension and the renaming screen),
# which are called on saved tables and on loaded ones alike.
.registrar_codes <- function(tbl) {
  if (!"listed_code" %in% names(tbl)) return(tbl)
  tbl$subject_course <- tbl$listed_code
  tbl[setdiff(names(tbl), c("listed_code", "course_id"))]
}

# The registrar's codes on a loaded table, which every loader keys.
.listed_codes <- function(tbl, caller) {
  if (!all(c("course_id", "listed_code") %in% names(tbl))) {
    stop("[courses.R] ", caller, "() needs columns course_id and listed_code on the table it ",
         "reads; every loader writes them with attach_course_ids() (R/branches/courses.R).")
  }
  tbl$listed_code
}

.courses_need <- function(df, cols, what) {
  if (!is.data.frame(df)) stop("[courses.R] ", what, " must be a data frame")
  missing <- setdiff(cols, names(df))
  if (length(missing)) {
    stop("[courses.R] ", what, " lacks column(s): ", paste(missing, collapse = ", "))
  }
}

#' Follow every code to the end of its confirmed succession chain
#'
#' @param codes Character: course codes as `subject_course` writes them
#'   (`SOCI 371`).
#' @param code_history The institution's `code_history.csv` as a table.
#' @return A tibble with `subject_course`, `course_id` (the chain's last code)
#'   and `steps` (how many confirmed rows were followed; 0 when the code is its
#'   own id). A course row names the code itself; a subject row renames every
#'   code of the subject, keeping the number. At each step a course row is
#'   taken before the subject's, so a course renumbered under its old subject
#'   still joins its subject's rename afterwards.
resolve_course_codes <- function(codes, code_history) {
  .courses_need(code_history, CEDAR_MAPPING_FILE_SPECS$code_history, "code_history")
  codes <- as.character(codes)
  bad <- unique(codes[is.na(codes) | !grepl("^[^ ]+ [^ ]+$", codes)])
  if (length(bad)) {
    stop("[courses.R] A course code must be 'SUBJECT NUMBER'; got: ",
         paste(head(bad, 10), collapse = ", "))
  }
  live <- code_history[code_history$status == "confirmed", , drop = FALSE]
  by_course  <- live[live$kind == "course", , drop = FALSE]
  by_subject <- live[live$kind == "subject", , drop = FALSE]
  if (anyDuplicated(by_course$from_code) || anyDuplicated(by_subject$from_code)) {
    stop("[courses.R] code_history gives a confirmed code more than one successor; ",
         "validate_mapping_files() should have refused it")
  }
  succ_course  <- stats::setNames(by_course$to_code, by_course$from_code)
  succ_subject <- stats::setNames(by_subject$to_code, by_subject$from_code)
  current <- codes
  steps <- integer(length(codes))
  # A chain cannot be longer than the rows that could form it; one more step
  # than that is a cycle the validator missed.
  limit <- nrow(live) + 1L
  repeat {
    via_course <- unname(succ_course[current])
    subject <- sub(" .*", "", current)
    number <- sub("^[^ ]+ ", "", current)
    renamed <- unname(succ_subject[subject])
    via_subject <- ifelse(is.na(renamed), NA_character_, paste(renamed, number))
    nxt <- dplyr::coalesce(via_course, via_subject)
    moving <- !is.na(nxt)
    if (!any(moving)) break
    current[moving] <- nxt[moving]
    steps[moving] <- steps[moving] + 1L
    if (any(steps > limit)) {
      stop("[courses.R] Confirmed successions cycle through ",
           paste(unique(codes[steps > limit]), collapse = ", "))
    }
  }
  tibble::tibble(subject_course = codes, course_id = current, steps = steps)
}

#' Build the course dimension
#'
#' @param sections `cedar_sections` as loaded (keys only or attached; the unit
#'   columns are not read).
#' @param students `cedar_students` as loaded.
#' @param dims The object build_cedar_dims() returns; its `code_history` is
#'   the crosswalk.
#' @return An object of class `cedar_courses`: a list with `courses` (one row
#'   per course_id, CEDAR_COURSES_COLUMNS) and `codes` (one row per code in
#'   either table, CEDAR_COURSE_CODES_COLUMNS). Both ordered by code. A code
#'   that appears in the class lists and never on the schedule (the renamed
#'   subjects' early terms, I45) is a row with `in_sections = FALSE`, never
#'   dropped.
build_cedar_courses <- function(sections, students, dims) {
  validate_cedar_dims(dims)
  sections <- .registrar_codes(sections)
  students <- .registrar_codes(students)
  key_cols <- c("term", "subject_course", "course_title", "level")
  .courses_need(sections, key_cols, "sections")
  .courses_need(students, key_cols, "students")

  # Where and when each code appears, and what it was called there. Counted
  # per (code, term, title, level) so the latest title can be the one most
  # sections carried; the class list's title stands in where a code has no
  # section row.
  # CAMPUS_ROLLUP: a course code is one course on every campus; see the header.
  appearances <- dplyr::bind_rows(
    sections %>%
      dplyr::count(subject_course, term, course_title, level, name = "n_rows") %>%
      dplyr::mutate(source = "sections"),
    students %>%
      dplyr::count(subject_course, term, course_title, level, name = "n_rows") %>%
      dplyr::mutate(source = "class_lists")
  ) %>% dplyr::ungroup()
  if (any(is.na(appearances$subject_course) | !nzchar(appearances$subject_course))) {
    stop("[courses.R] A row has no subject_course; the transform should have refused it")
  }

  # CAMPUS_ROLLUP: one row per code, on every campus it is taught.
  codes <- appearances %>%
    dplyr::group_by(subject_course) %>%
    dplyr::summarize(
      first_term = min(term), last_term = max(term),
      in_sections = any(source == "sections"),
      in_class_lists = any(source == "class_lists"),
      .groups = "drop"
    )
  resolved <- resolve_course_codes(codes$subject_course, dims$code_history)
  codes <- codes %>%
    dplyr::mutate(course_id = resolved$course_id, steps = resolved$steps,
                  subject = sub(" .*", "", subject_course),
                  course_number = sub("^[^ ]+ ", "", subject_course)) %>%
    dplyr::arrange(subject_course)

  # The course's title and level: from its latest term, the schedule before
  # the class list, the title most sections carried before any other.
  latest <- appearances %>%
    dplyr::inner_join(codes[c("subject_course", "course_id")], by = "subject_course") %>%
    dplyr::arrange(course_id, dplyr::desc(term), source != "sections", dplyr::desc(n_rows), course_title) %>%
    dplyr::distinct(course_id, .keep_all = TRUE) %>%
    dplyr::select(course_id, course_title, level)
  former <- codes %>%
    dplyr::filter(subject_course != course_id) %>%
    dplyr::arrange(course_id, first_term, subject_course) %>%
    dplyr::group_by(course_id) %>%
    dplyr::summarize(former_codes = paste(subject_course, collapse = ", "), .groups = "drop")
  courses <- codes %>%
    dplyr::group_by(course_id) %>%
    dplyr::summarize(
      first_term = min(first_term), last_term = max(last_term),
      n_codes = dplyr::n(),
      in_sections = any(in_sections), in_class_lists = any(in_class_lists),
      .groups = "drop"
    ) %>%
    dplyr::left_join(latest, by = "course_id") %>%
    dplyr::left_join(former, by = "course_id") %>%
    dplyr::mutate(subject = sub(" .*", "", course_id),
                  course_number = sub("^[^ ]+ ", "", course_id)) %>%
    dplyr::select(dplyr::all_of(CEDAR_COURSES_COLUMNS)) %>%
    dplyr::arrange(course_id)
  codes <- codes %>% dplyr::select(dplyr::all_of(CEDAR_COURSE_CODES_COLUMNS))

  out <- structure(list(courses = courses, codes = codes), class = c("cedar_courses", "list"))
  validate_cedar_courses(out)
  message(sprintf("[courses.R] course dimension: %d courses from %d codes (%d codes resolved through code_history.csv)",
                  nrow(courses), nrow(codes), sum(codes$steps > 0L)))
  out
}

#' Check a course dimension's shape
#'
#' @return `courses`, invisibly; stops on a repeated course or code, a code
#'   whose id is not a course, or a missing column.
validate_cedar_courses <- function(courses) {
  if (!inherits(courses, "cedar_courses")) {
    stop("[courses.R] courses must be built by build_cedar_courses()")
  }
  .courses_need(courses$courses, CEDAR_COURSES_COLUMNS, "courses$courses")
  .courses_need(courses$codes, CEDAR_COURSE_CODES_COLUMNS, "courses$codes")
  if (anyDuplicated(courses$courses$course_id)) {
    stop("[courses.R] course_id repeats in cedar_courses")
  }
  if (anyDuplicated(courses$codes$subject_course)) {
    stop("[courses.R] subject_course repeats in cedar_course_codes")
  }
  orphan <- setdiff(courses$codes$course_id, courses$courses$course_id)
  if (length(orphan)) {
    stop("[courses.R] code(s) resolve to a course_id with no course row: ",
         paste(head(orphan, 10), collapse = ", "))
  }
  invisible(courses)
}

#' Key every fact table a loader holds on the course
#'
#' Writes each row's `course_id`, moves the code the registrar used that term
#' to `listed_code`, and sets `subject_course` to the `course_id`, on
#' cedar_sections, cedar_students and cedar_grades. Every loader calls it once
#' (global.R, R/trunk/data.R, the cache-warming scripts, cedar-repl.R), so every
#' reader groups, filters and joins by course on `subject_course`. A table
#' already keyed is keyed again from its `listed_code`, so attaching twice, or
#' after a code_history.csv row changed, gives the same table. `course_id`
#' stays beside `subject_course` as the explicit name; the two share one vector.
#'
#' @param tables A named list of loaded tables; one that is not loaded (NULL,
#'   or the empty tibble load_cedar_data() returns for a missing file) is left
#'   alone and named in a message.
#' @param courses The object build_cedar_courses() returns.
#' @return `tables` keyed on the course, each table's attributes kept and its
#'   rows ungrouped. A code the dimension does not know is a stop: the
#'   dimension is built from the same tables, so one can only mean the tables
#'   changed between the two calls.
attach_course_ids <- function(tables, courses) {
  validate_cedar_courses(courses)
  if (!is.list(tables)) stop("[courses.R] attach_course_ids: tables must be a list")
  codes <- courses$codes
  for (name in names(CEDAR_ATTACHED_COURSE_COLUMNS)) {
    tbl <- tables[[name]]
    if (is.null(tbl) || !is.data.frame(tbl) || ncol(tbl) == 0L) {
      message("[courses.R] ", name, " is not loaded; no course_id attached")
      next
    }
    .courses_need(tbl, "subject_course", name)
    rekeyed <- "listed_code" %in% colnames(tbl)
    stamped <- intersect(CEDAR_ATTACHED_COURSE_COLUMNS[[name]], colnames(tbl))
    elapsed <- system.time({
      listed <- if (rekeyed) tbl$listed_code else tbl$subject_course
      attached <- dplyr::ungroup(tbl[setdiff(colnames(tbl), stamped)])
      ids <- codes$course_id[match(listed, codes$subject_course)]
      unknown <- unique(listed[is.na(ids)])
      if (length(unknown)) {
        stop("[courses.R] ", name, " carries code(s) the course dimension does not know: ",
             paste(head(unknown, 10), collapse = ", "),
             ". Build the dimension from the tables it is attached to.")
      }
      attached$subject_course <- ids
      attached$course_id <- ids
      attached$listed_code <- listed
      attached <- .carry_attributes(attached, tbl)
    })[["elapsed"]]
    message(sprintf("[courses.R] %s: keyed on course_id in %.2f s%s", name, elapsed,
                    if (rekeyed) " (keyed again from listed_code)"
                    else if (length(stamped)) " (a stamped column dropped first)" else ""))
    tables[[name]] <- attached
  }
  tables
}

#' The course a code belongs to
#'
#' @param tbl A loaded table (keyed by attach_course_ids()), or any frame with
#'   `course_id` and `listed_code`.
#' @param code One course code as a picker or a URL names it: the current
#'   code or any former one (`SOC 371` finds SOCI 371's course).
#' @param caller Named in the errors.
#' @return The code's `course_id` in `tbl`. A code `tbl` does not carry is its
#'   own course, with no history to follow. Stops on a code that maps to two
#'   ids, which no table attach_course_ids() wrote can do.
course_id_of <- function(tbl, code, caller = "course_id_of") {
  code <- as.character(code)
  if (length(code) != 1L || is.na(code) || !nzchar(code)) {
    stop("[courses.R] ", caller, ": code must be one course code")
  }
  listed <- .listed_codes(tbl, caller)
  ids <- unique(tbl$course_id[!is.na(listed) & listed == code])
  if (length(ids) > 1L) {
    stop("[courses.R] ", caller, ": code ", code, " carries ", length(ids),
         " course ids (", paste(ids, collapse = ", "), "); the table was not attached by ",
         "attach_course_ids()")
  }
  if (length(ids) == 0L) return(code)
  ids
}

#' Every code and course id a loaded table names, with its course
#'
#' A row per registrar's code (`SOC 371` -> `SOCI 371`) and per course id
#' (`SOCI 371` -> `SOCI 371`), so rows that name either one join to their
#' course: a list that arrives with the registrar's code (a waitlist row, a
#' requested history) and one that arrives with the course both find it. The
#' two agree because a course id is the last code of its chain.
#'
#' @param tbl A loaded table.
#' @param caller Named in the errors.
#' @return A tibble of `code` and `course_id`, one row per code. Stops on a
#'   code that names two courses, which no table attach_course_ids() keyed can
#'   carry.
course_code_lookup <- function(tbl, caller = "course_code_lookup") {
  listed <- .listed_codes(tbl, caller)
  lookup <- dplyr::distinct(dplyr::bind_rows(
    tibble::tibble(code = listed, course_id = tbl$course_id),
    tibble::tibble(code = tbl$course_id, course_id = tbl$course_id)
  ))
  if (anyDuplicated(lookup$code)) {
    stop("[courses.R] ", caller, "(): a course code names two course ids; the table was ",
         "not keyed by attach_course_ids()")
  }
  lookup
}

#' A course picker's choices: every course and every code it has carried
#'
#' For a picker whose reader resolves a picked code to its course (the shared
#' `course` filter in filter.R, course_id_of(), course_ids_of()), so a reader
#' can find a course by the code it knows: SOC 371 and SOCI 371 both pick the
#' one course.
#'
#' @param tbl A loaded table.
#' @return The sorted course ids and registrar's codes, each once.
course_picker_choices <- function(tbl) {
  sort(unique(c(tbl$subject_course, .listed_codes(tbl, "course_picker_choices"))))
}

#' The courses a list of picked codes belongs to
#'
#' What a picker or a URL sends (one code or a comma-separated list, each
#' current or former) as the course ids of the tables a reader keys on
#' course_id: course_id_of() over the codes both tables carry, each id once.
#'
#' @param codes Picked codes; NULL or "" is no pick.
#' @param ... The reader's loaded tables.
#' @param caller Named in the errors.
#' @return The ids, in pick order; NULL for no pick.
course_ids_of <- function(codes, ..., caller = "course_ids_of") {
  if (is.null(codes) || length(codes) == 0L || identical(codes, "")) return(NULL)
  known <- dplyr::bind_rows(lapply(list(...), function(tbl) {
    listed <- .listed_codes(tbl, caller)
    dplyr::distinct(tibble::tibble(course_id = tbl$course_id, listed_code = listed))
  }))
  unique(vapply(convert_param_to_list(codes), course_id_of, character(1),
                tbl = known, caller = caller))
}

#' The codes a course has been listed under in a table
#'
#' @param tbl A loaded table.
#' @param course_id One course id, from course_id_of().
#' @return The codes in `tbl` with that id, sorted; the id itself when the
#'   table carries none of them.
course_codes_of <- function(tbl, course_id) {
  listed <- .listed_codes(tbl, "course_codes_of")
  codes <- sort(unique(listed[!is.na(tbl$course_id) & tbl$course_id == course_id]))
  if (length(codes) == 0L) course_id else codes
}

#' Every code a table carries under another course id
#'
#' One line per rename the table shows (`"SOC 371 > SOCI 371"`), sorted: the
#' fingerprint a cache key needs for any result computed over a loaded table,
#' so a confirmed row in code_history.csv is a miss, never a stale hit.
#'
#' @param tbl A loaded table.
#' @return A sorted character vector, empty when no code is renamed.
course_code_renames <- function(tbl) {
  listed <- .listed_codes(tbl, "course_code_renames")
  renamed <- !is.na(listed) & !is.na(tbl$course_id) & listed != tbl$course_id
  if (!any(renamed)) return(character(0))
  sort(unique(paste(listed[renamed], ">", tbl$course_id[renamed])))
}

#' Name each course's former codes with the terms they covered
#'
#' One row per course the tables list under more than one code: every code
#' other than its `course_id`, each with the terms it ran under, oldest first
#' (`"HIST 320 (Spring 2020 to Fall 2020)"`). The text a scan over many
#' courses puts beside a course it follows across its codes, as
#' course_former_codes_note() does for one course.
#'
#' @param ... Loaded tables (with `term`).
#' @return A tibble with `subject_course` (the `course_id`) and
#'   `former_codes`; one row per course with a former code, none when none.
course_former_code_spans <- function(...) {
  pieces <- lapply(list(...), function(tbl) {
    .courses_need(tbl, "term", "course_former_code_spans()'s table")
    listed <- .listed_codes(tbl, "course_former_code_spans")
    tibble::tibble(course_id = tbl$course_id, listed_code = listed, term = tbl$term) %>%
      dplyr::filter(!is.na(course_id), !is.na(listed_code), listed_code != course_id) %>%
      dplyr::distinct()
  })
  former <- dplyr::bind_rows(pieces)
  if (nrow(former) == 0L) {
    return(tibble::tibble(subject_course = character(), former_codes = character()))
  }
  former %>%
    dplyr::group_by(course_id, listed_code) %>%
    dplyr::summarize(first = min(term), last = max(term), .groups = "drop") %>%
    dplyr::arrange(course_id, first, listed_code) %>%
    dplyr::mutate(span = paste0(
      listed_code, " (",
      ifelse(first == last, fmt_term(first), paste(fmt_term(first), "to", fmt_term(last))),
      ")"
    )) %>%
    # CAMPUS_ROLLUP: which codes a course has carried is a fact about the
    # course, the same on every campus; the rows this text joins keep theirs.
    dplyr::group_by(subject_course = course_id) %>%
    dplyr::summarize(former_codes = paste(span, collapse = ", "), .groups = "drop")
}

#' Screen the data for codes that look like successions of other codes
#'
#' Candidates for code_history.csv, with the evidence; never verdicts. Two
#' screens, named by the `basis` each would be recorded with:
#'
#' * `section_crn` (kind `subject`): a section the schedule lists under one
#'   subject and the class list under another, the number unchanged. Banner
#'   applies a subject's rename to old class lists but not to old schedules,
#'   so the pair appears on hundreds of sections (I45).
#' * `title_match` (kind `course`): a title whose only retired code stopped
#'   before its only new code began, inside the data window. Codes are first
#'   resolved through the confirmed rows already in the file, so a pair the
#'   file already joins is not a candidate, and a retired code and its
#'   successor under a renamed subject are compared as one. Rotating-topics
#'   titles (`T:`) and blank titles are never matched. Many-to-many title
#'   groups are left out: they need a person, not a screen.
#'
#' @param sections,students The loaded tables (`term`, `crn`, `subject_course`,
#'   `course_title`).
#' @param files The institution's mapping files (read_institution_mappings()),
#'   for `code_history`.
#' @return A tibble, one row per candidate: `kind`, `from_code`, `to_code`,
#'   `effective_term` (the first term the new code appears), `basis`,
#'   `n_evidence` (sections carrying the pair, or the retired and new codes'
#'   rows), `evidence` (one line, ready for the file), `in_file` (the file's
#'   status for the pair, NA when it has no row). Strongest evidence first.
detect_course_renamings <- function(sections, students, files) {
  sections <- .registrar_codes(sections)
  students <- .registrar_codes(students)
  .courses_need(sections, c("term", "crn", "subject_course", "course_title"), "sections")
  .courses_need(students, c("term", "crn", "subject_course", "course_title"), "students")
  history <- files$code_history
  .courses_need(history, CEDAR_MAPPING_FILE_SPECS$code_history, "files$code_history")
  span <- function(first, last) {
    if (first == last) fmt_term(first) else paste0(fmt_term(first), "–", fmt_term(last))
  }

  # CAMPUS_ROLLUP: a succession of codes is institution-wide; see the header.
  # 1. The same section under two subjects.
  on_schedule <- sections %>% dplyr::distinct(term, crn, schedule_code = subject_course)
  on_class_list <- students %>% dplyr::distinct(term, crn, class_list_code = subject_course)
  pairs <- on_schedule %>%
    dplyr::inner_join(on_class_list, by = c("term", "crn"), relationship = "many-to-many") %>%
    dplyr::filter(schedule_code != class_list_code) %>%
    dplyr::mutate(from_code = sub(" .*", "", schedule_code), to_code = sub(" .*", "", class_list_code),
                  from_number = sub("^[^ ]+ ", "", schedule_code),
                  to_number = sub("^[^ ]+ ", "", class_list_code)) %>%
    dplyr::filter(from_code != to_code, from_number == to_number)
  # A pair the file already joins course by course is not a subject rename:
  # UNM's class lists carry CCST on 3-digit CCS sections, and CCS stays the
  # upper-division prefix beside CCST's 4-digit courses, so code_history.csv
  # joins each CCST nnn to its CCS nnn rather than renaming the subject.
  pair_ids <- resolve_course_codes(unique(c(pairs$schedule_code, pairs$class_list_code)), history)
  pair_id <- function(code) pair_ids$course_id[match(code, pair_ids$subject_course)]
  subject_in_file <- paste(history$from_code, history$to_code)[history$kind == "subject"]
  pairs <- pairs %>%
    dplyr::filter(pair_id(schedule_code) != pair_id(class_list_code) |
                    paste(from_code, to_code) %in% subject_in_file)
  new_subject_first <- sections %>%
    dplyr::mutate(subject = sub(" .*", "", subject_course)) %>%
    dplyr::group_by(subject) %>%
    dplyr::summarize(first_scheduled = min(term), .groups = "drop")
  subject_rows <- if (nrow(pairs) == 0L) {
    tibble::tibble(kind = character(), from_code = character(), to_code = character(),
                   effective_term = integer(), basis = character(), n_evidence = integer(),
                   evidence = character())
  } else pairs %>%
    dplyr::group_by(from_code, to_code) %>%
    dplyr::summarize(n_evidence = dplyr::n_distinct(term, crn), first = min(term), last = max(term),
                     .groups = "drop") %>%
    dplyr::left_join(new_subject_first, by = c(to_code = "subject")) %>%
    dplyr::mutate(
      kind = "subject", basis = "section_crn",
      effective_term = dplyr::coalesce(first_scheduled, first),
      evidence = sprintf("%d sections (%s) carry %s on the schedule and %s on the class list%s",
                         n_evidence, mapply(span, first, last), from_code, to_code,
                         ifelse(is.na(first_scheduled), "; the new subject is never on the schedule",
                                paste0("; ", to_code, " is scheduled from ", fmt_term(first_scheduled))))
    ) %>%
    dplyr::select(kind, from_code, to_code, effective_term, basis, n_evidence, evidence)

  # 2. A title that stopped under one code and began under another.
  norm <- function(x) gsub("[^A-Z0-9]+", " ", toupper(trimws(x)))
  resolved <- resolve_course_codes(unique(c(sections$subject_course, students$subject_course)), history)
  # CAMPUS_ROLLUP: a code's title and terms, institution-wide; see the header.
  appearances <- dplyr::bind_rows(
    sections %>% dplyr::count(subject_course, term, course_title, name = "n_rows"),
    students %>% dplyr::count(subject_course, term, course_title, name = "n_rows")
  ) %>%
    dplyr::inner_join(resolved[c("subject_course", "course_id")], by = "subject_course") %>%
    dplyr::filter(!is.na(course_title), nzchar(trimws(course_title)), !grepl("^T:", trimws(course_title)))
  window <- range(c(sections$term, students$term))
  by_course <- appearances %>%
    dplyr::group_by(course_id) %>%
    dplyr::summarize(first_term = min(term), last_term = max(term), n_rows = sum(n_rows),
                     modal_title = trimws(course_title[which.max(n_rows)]), .groups = "drop") %>%
    dplyr::mutate(title = norm(modal_title))
  retired <- by_course %>% dplyr::filter(last_term < window[2]) %>%
    dplyr::rename(from_code = course_id, from_last = last_term, from_rows = n_rows) %>%
    dplyr::select(title, modal_title, from_code, from_last, from_rows)
  begun <- by_course %>% dplyr::filter(first_term > window[1]) %>%
    dplyr::rename(to_code = course_id, to_first = first_term, to_rows = n_rows) %>%
    dplyr::select(title, to_code, to_first, to_rows)
  course_rows <- retired %>%
    dplyr::inner_join(begun, by = "title", relationship = "many-to-many") %>%
    dplyr::filter(from_code != to_code, to_first > from_last) %>%
    dplyr::group_by(title) %>%
    dplyr::filter(dplyr::n_distinct(from_code) == 1L, dplyr::n_distinct(to_code) == 1L) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      kind = "course", basis = "title_match", effective_term = to_first,
      n_evidence = from_rows + to_rows,
      evidence = sprintf("%s retired as %s after %s and began as %s in %s (%d and %d section and class-list rows)",
                         modal_title, from_code, fmt_term(from_last),
                         to_code, fmt_term(to_first), from_rows, to_rows)
    ) %>%
    dplyr::select(kind, from_code, to_code, effective_term, basis, n_evidence, evidence)

  out <- dplyr::bind_rows(subject_rows, course_rows) %>%
    dplyr::mutate(effective_term = as.integer(effective_term)) %>%
    dplyr::arrange(kind != "subject", dplyr::desc(n_evidence), from_code)
  filed <- paste(history$kind, history$from_code, history$to_code)
  out$in_file <- history$status[match(paste(out$kind, out$from_code, out$to_code), filed)]
  out
}
