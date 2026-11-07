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
# The id is attached to cedar_sections and cedar_students at every load by
# attach_course_ids(), beside `subject_course`, and never saved: a confirmed
# row in the file changes it at the next start, as a unit decision does. The
# code columns stay as the source wrote them (annotate, never mutate), so a
# reader that wants the code the registrar used that term still has it.
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

# The column attach_course_ids() writes on each fact table, which a loader
# drops before attaching so a stamped file and an unstamped one load the same.
CEDAR_ATTACHED_COURSE_COLUMNS <- list(
  cedar_sections = "course_id",
  cedar_students = "course_id"
)

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

#' Attach `course_id` to every fact table a loader holds
#'
#' @param tables A named list of loaded tables; one that is not loaded (NULL,
#'   or the empty tibble load_cedar_data() returns for a missing file) is left
#'   alone and named in a message.
#' @param courses The object build_cedar_courses() returns.
#' @return `tables` with `course_id` on cedar_sections and cedar_students,
#'   each table's attributes kept. A code the dimension does not know is a
#'   stop: the dimension is built from the same tables, so one can only mean
#'   the tables changed between the two calls.
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
    stamped <- intersect(CEDAR_ATTACHED_COURSE_COLUMNS[[name]], colnames(tbl))
    elapsed <- system.time({
      attached <- tbl[setdiff(colnames(tbl), stamped)]
      attached$course_id <- codes$course_id[match(attached$subject_course, codes$subject_course)]
      unknown <- unique(attached$subject_course[is.na(attached$course_id)])
      if (length(unknown)) {
        stop("[courses.R] ", name, " carries code(s) the course dimension does not know: ",
             paste(head(unknown, 10), collapse = ", "),
             ". Build the dimension from the tables it is attached to.")
      }
      attached <- .carry_attributes(attached, tbl)
    })[["elapsed"]]
    message(sprintf("[courses.R] %s: attached course_id in %.2f s%s", name, elapsed,
                    if (length(stamped)) " (a stamped column dropped first)" else ""))
    tables[[name]] <- attached
  }
  tables
}

#' Read a table by course rather than by code
#'
#' Returns `tbl` keyed on the course: `subject_course` carries each row's
#' `course_id` and the code the source wrote moves to `listed_code`. A reader
#' that filters, groups or joins on `subject_course` then follows every course
#' across the codes it has carried, its grouping unchanged — Course Dynamics
#' reads the class list and the sections this way, so SOCI 371's report
#' includes its SOC 371 terms and its feeders count SOC 250 and SOCI 2315 as
#' one course. This is a working frame, never a saved one (annotate, never
#' mutate): the loaded tables keep the registrar's code, and `listed_code`
#' keeps it here for any text that names it ("also listed as SOC 371"). A
#' frame already keyed is returned as it is. Every column is shared with
#' `tbl`; nothing is copied.
#'
#' @param tbl `cedar_sections` or `cedar_students` rows with `course_id`.
#' @param caller Named in the error when the id was never attached.
#' @return `tbl`, ungrouped, with `subject_course` set to `course_id` and the
#'   original code in `listed_code`.
key_on_course_id <- function(tbl, caller = "key_on_course_id") {
  if (!is.data.frame(tbl)) stop("[courses.R] ", caller, ": tbl must be a data frame")
  if ("listed_code" %in% names(tbl)) return(tbl)
  if (!"course_id" %in% names(tbl)) {
    stop("[courses.R] ", caller, "() needs column course_id on the table it reads; ",
         "attach it with attach_course_ids() (R/branches/courses.R), as every loader does.")
  }
  .courses_need(tbl, "subject_course", paste0(caller, "'s table"))
  tbl <- dplyr::ungroup(tbl)
  tbl$listed_code <- tbl$subject_course
  tbl$subject_course <- tbl$course_id
  tbl
}

#' The course a code belongs to
#'
#' @param tbl Rows with `course_id`, keyed with key_on_course_id() or not.
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
  if (!"course_id" %in% names(tbl)) {
    stop("[courses.R] ", caller, "() needs column course_id on the table it reads; ",
         "attach it with attach_course_ids() (R/branches/courses.R), as every loader does.")
  }
  listed <- if ("listed_code" %in% names(tbl)) tbl$listed_code else tbl$subject_course
  ids <- unique(tbl$course_id[!is.na(listed) & listed == code])
  if (length(ids) > 1L) {
    stop("[courses.R] ", caller, ": code ", code, " carries ", length(ids),
         " course ids (", paste(ids, collapse = ", "), "); the table was not attached by ",
         "attach_course_ids()")
  }
  if (length(ids) == 0L) return(code)
  ids
}

#' The codes a course has been listed under in a table
#'
#' @param tbl Rows with `course_id`, keyed or not.
#' @param course_id One course id, from course_id_of().
#' @return The codes in `tbl` with that id, sorted; the id itself when the
#'   table carries none of them.
course_codes_of <- function(tbl, course_id) {
  if (!"course_id" %in% names(tbl)) {
    stop("[courses.R] course_codes_of() needs column course_id; attach it with attach_course_ids()")
  }
  listed <- if ("listed_code" %in% names(tbl)) tbl$listed_code else tbl$subject_course
  codes <- sort(unique(listed[!is.na(tbl$course_id) & tbl$course_id == course_id]))
  if (length(codes) == 0L) course_id else codes
}

#' Every code a table carries under another course id
#'
#' One line per rename the table shows (`"SOC 371 > SOCI 371"`), sorted: the
#' fingerprint a cache key needs for a result read through key_on_course_id(),
#' so a confirmed row in code_history.csv is a miss, never a stale hit.
#'
#' @param tbl Rows with `course_id`, keyed or not.
#' @return A sorted character vector, empty when no code is renamed.
course_code_renames <- function(tbl) {
  if (!"course_id" %in% names(tbl)) {
    stop("[courses.R] course_code_renames() needs column course_id; attach it with attach_course_ids()")
  }
  listed <- if ("listed_code" %in% names(tbl)) tbl$listed_code else tbl$subject_course
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
#' @param ... Tables with `course_id` and `term`, keyed or not; a code is
#'   read from `listed_code` when the table is keyed, else `subject_course`.
#' @return A tibble with `subject_course` (the `course_id`) and
#'   `former_codes`; one row per course with a former code, none when none.
course_former_code_spans <- function(...) {
  pieces <- lapply(list(...), function(tbl) {
    if (!"course_id" %in% names(tbl)) {
      stop("[courses.R] course_former_code_spans() needs column course_id on every table; ",
           "attach it with attach_course_ids()")
    }
    .courses_need(tbl, c("term", "subject_course"), "course_former_code_spans()'s table")
    listed <- if ("listed_code" %in% names(tbl)) tbl$listed_code else tbl$subject_course
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
  new_subject_first <- sections %>%
    dplyr::mutate(subject = sub(" .*", "", subject_course)) %>%
    dplyr::group_by(subject) %>%
    dplyr::summarize(first_scheduled = min(term), .groups = "drop")
  subject_rows <- pairs %>%
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
