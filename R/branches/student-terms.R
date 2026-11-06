# student-terms.R — one row per student per term
#
# ADR-001 step 2; the contract is docs/developers/student-terms.md, and this
# file is wrong where it departs from that page.
#
# Every fact about a student in a term that CEDAR otherwise re-derives from raw
# class-list rows, or reads off a column repeated on each of them, is here once:
# who they were that term (level, classification, home campus, standing,
# primary major), what they did (enrolled, courses, credits, DFW
# grades, late withdrawals), where they were in their degree (credits entering),
# and whether they came back (`returned_next_regular_term`).
#
# The rules that matter:
#   - `enrolled` is registered OR late-dropped: enrolled at census. This is
#     CEDAR's one definition of an enrolled student-term (ISSUES.md I44).
#   - A row exists for every student with any class-list row or any program
#     declaration that term, so waitlist-only, early-drop-only and declared-but-
#     not-registered students are visible with enrolled = FALSE.
#   - Where the class list and academic studies both describe the student, the
#     programs row wins, the disagreement is flagged, never coalesced silently.
#   - The class list codes level and campus (UG, ABQ); academic studies names
#     them (Undergraduate, Albuquerque/Main). The institution's files say which
#     is which (student_levels.csv, campuses.csv source_names); this table
#     stores the code. A name the file does not list is NA and is reported.
#   - A return is read only where the next regular term is settled AND has a
#     class list; past the edge, or into a Fall or Spring the data has no pull
#     for, it is NA, never FALSE.
#   - No pull-stamped field (inst_*, overall_*, inst_gpa) is on this table.
#   - The table stores the primary major's KEYS -- its code and the source's
#     college for it -- never its unit or college: those are attached at load
#     by attach_default_units() (R/branches/dims.R, ADR-001 step 3) as
#     `primary_dept_code`, `primary_college_code` and `primary_college_basis`,
#     so a mapping edit changes the next start and rebuilds nothing.

STUDENT_TERMS_BANNED_COLUMNS <- c("inst_credits_attempted", "inst_credits_earned",
                                  "overall_credits_attempted", "overall_credits_earned",
                                  "inst_gpa")

STUDENT_TERMS_COLUMNS <- c(
  # keys and provenance
  "student_id", "term", "classlist_as_of", "programs_as_of",
  "description_source", "description_conflict",
  # description
  "student_level", "student_classification", "student_campus", "academic_standing",
  "residency", "time_status", "primary_major_code", "primary_source_college_code",
  "primary_source_college", "is_pre_major", "n_declarations", "declared",
  # enrollment
  "class_list_rows", "enrolled", "registered_courses", "late_withdrawals",
  "early_drops", "waitlisted_only", "attempted_unm_credits", "completed_unm_credits",
  "dfw_grades", "graded_rows", "sem_gpa",
  # position
  "cumulative_attempted_unm_credits", "cumulative_completed_unm_credits",
  "unm_credits_entering", "timeline_valid",
  # return
  "next_regular_term", "returned_next_regular_term", "return_observable",
  "degree_awarded"
)

# Attached at load from the keys above, never stored (ADR-001 step 3):
# attach_student_term_units() in R/branches/dims.R writes them.
STUDENT_TERMS_ATTACHED_COLUMNS <- c("primary_dept_code", "primary_college_code",
                                    "primary_college_basis")

# Stamped on the built table as the attribute cedar_student_terms_build_version.
# Bump it when the builder's rules change the values it writes without adding
# a column: the deploy gate compares the saved stamp with this and rebuilds a
# table built under an older rule, a staleness neither a file time nor the
# column list records.
#   2 (2026-11-04): a primary major, unit, college and pre-major flag from the
#     class list where academic studies has no row.
STUDENT_TERMS_BUILD_VERSION <- 2L


#' Build the student-term table
#'
#' @param students `cedar_students`.
#' @param programs `cedar_programs`, or NULL for class lists alone: then no
#'   row is declared, every row is described by the class list, and the build
#'   says so.
#' @param degrees `cedar_degrees` or NULL; without it `degree_awarded` is FALSE
#'   everywhere and the build says so.
#' @param edges The result of [cedar_data_edges()] on the same tables. Required
#'   to carry `last_enrolled_complete`; the build stops without it.
#' @param files The institution's mapping files, as [read_institution_mappings()]
#'   returns them: a primary major the class list supplies takes its pre-major
#'   flag from `programs.csv`, as a programs row's flag is the file's in the
#'   transform. Its unit and college are not read here: the table stores the
#'   code and the roster's college as keys, and the loader attaches them.
#' @param opt Unused; present for the branch calling convention.
#' @return A tibble with `STUDENT_TERMS_COLUMNS`, one row per student-term,
#'   carrying `STUDENT_TERMS_BUILD_VERSION` as the attribute
#'   `cedar_student_terms_build_version`.
build_student_terms <- function(students, programs = NULL, degrees = NULL,
                                edges = cedar_data_edges(students, degrees = degrees),
                                files = read_institution_mappings(),
                                opt = list()) {
  required_students <- c("student_id", "term", "registration_status_code", "final_grade",
                         "credits", "subject_course", "course_title", "student_level",
                         "student_classification", "student_campus", "residency",
                         "major_code", "student_college", "as_of_date")
  required_programs <- c("student_id", "term", "program_type", "major_code",
                         "source_college_code", "source_college", "is_pre_major", "student_level",
                         "student_classification", "student_campus", "academic_standing",
                         "residency", "time_status", "sem_gpa", "as_of_date")
  if (is.null(programs)) {
    message("[student-terms.R] no programs supplied: no row is declared, and every row is described by the class list.")
    programs <- .empty_programs()
  }
  missing_s <- setdiff(required_students, names(students))
  missing_p <- setdiff(required_programs, names(programs))
  if (length(missing_s) > 0L || length(missing_p) > 0L) {
    stop("[student-terms.R] missing column(s): students [", paste(missing_s, collapse = ", "),
         "], programs [", paste(missing_p, collapse = ", "), "]")
  }
  if (is.null(edges$last_enrolled_complete)) {
    stop("[student-terms.R] The settled edge cannot be determined, so no return can be ",
         "judged observable. Not built.")
  }
  settled_edge <- as.integer(edges$last_enrolled_complete)

  students <- dplyr::ungroup(students) %>% dplyr::mutate(term = as.integer(term))
  programs <- dplyr::ungroup(programs) %>% dplyr::mutate(term = as.integer(term))

  # ── Class list: enrollment facts and the class list's description ────────
  enrollment <- .student_terms_enrollment(students)
  from_cl <- .student_terms_classlist_description(students)

  # ── Academic studies: description and declarations ───────────────────────
  from_programs <- .student_terms_programs_description(programs)

  # ── One row per student-term with any row in either source ───────────────
  keys <- dplyr::bind_rows(
    dplyr::distinct(students, student_id, term),
    dplyr::distinct(programs, student_id, term)
  ) %>% dplyr::distinct()

  st <- keys %>%
    dplyr::left_join(enrollment, by = c("student_id", "term")) %>%
    dplyr::left_join(from_cl, by = c("student_id", "term")) %>%
    dplyr::left_join(from_programs, by = c("student_id", "term")) %>%
    dplyr::mutate(
      class_list_rows = dplyr::coalesce(class_list_rows, 0L),
      enrolled = dplyr::coalesce(enrolled, FALSE),
      registered_courses = dplyr::coalesce(registered_courses, 0L),
      late_withdrawals = dplyr::coalesce(late_withdrawals, 0L),
      early_drops = dplyr::coalesce(early_drops, 0L),
      waitlisted_only = dplyr::coalesce(waitlisted_only, FALSE),
      attempted_unm_credits = dplyr::coalesce(attempted_unm_credits, 0),
      completed_unm_credits = dplyr::coalesce(completed_unm_credits, 0),
      dfw_grades = dplyr::coalesce(dfw_grades, 0L),
      graded_rows = dplyr::coalesce(graded_rows, 0L),
      n_declarations = dplyr::coalesce(n_declarations, 0L),
      declared = n_declarations > 0L
    )

  # ── Precedence: programs wins, class list fills, disagreement is flagged ──
  st <- .student_terms_resolve_description(st)

  # ── Primary major where academic studies has no row: the class list's ────
  # Banner stamps a major and home college on every roster row, and a fifth of
  # student-terms have no academic studies row at all (branch-campus associate
  # and non-degree students, mostly: 92,653 on the 2026-11-04 pull, every one
  # with a major on its class list). Their primary major fills in from the
  # class list: the roster's major code, with the roster's Student College
  # Code as the college key the loader resolves it under (as a programs row's
  # Actual College is), and the pre-major flag from programs.csv. The unit and
  # college themselves are attached at load from these keys, exactly as a
  # programs row's are. description_source already says "class_list" on these
  # rows. A row with a programs pull is never filled, even when that pull
  # holds no Major row.
  from_classlist <- is.na(st$programs_as_of) & !is.na(st$cl_major_code)
  if (any(from_classlist)) {
    code <- st$cl_major_code[from_classlist]
    st$primary_major_code[from_classlist]          <- code
    st$primary_source_college_code[from_classlist] <- st$cl_student_college[from_classlist]
    st$primary_source_college[from_classlist]      <- st$cl_student_college[from_classlist]
    st$is_pre_major[from_classlist] <- program_pre_major_flags(code, files$programs)
    message(sprintf(
      "[student-terms.R] %s student-terms take their primary major from the class list (no academic studies row); %s of them carry a roster college to resolve it under.",
      format(sum(from_classlist), big.mark = ","),
      format(sum(!is.na(st$primary_source_college_code[from_classlist])), big.mark = ",")))
  }

  # ── Position: the running total of attempted credits over the data ───────
  # The window opens where the CLASS LISTS open, not where the table's rows
  # do: academic studies reaches back further (UNM's programs start Fall 2018,
  # its class lists Fall 2019), and a student first registered in the first
  # class-list term has credits before it that no row can show. A declaration
  # before that term is the same evidence of earlier enrollment, so a
  # student's first row of any kind is what is compared.
  min_data_term <- min(students$term)
  st <- st %>%
    dplyr::arrange(student_id, term) %>%
    dplyr::group_by(student_id) %>%
    dplyr::mutate(
      cumulative_attempted_unm_credits = cumsum(attempted_unm_credits),
      cumulative_completed_unm_credits = cumsum(completed_unm_credits),
      unm_credits_entering = cumulative_attempted_unm_credits - attempted_unm_credits,
      timeline_valid = min(term) > min_data_term
    ) %>%
    dplyr::ungroup()

  # ── Return: enrolled in the next regular term, where that term is settled ─
  # ...and has a class list at all. A Fall or Spring with no pull between the
  # first and last term in the data would otherwise read as a term nobody
  # returned to. The same gaps are rows with zero enrollment on cedar_terms.
  classlist_terms <- sort(unique(students$term))
  gaps <- setdiff(regular_terms_between(min(classlist_terms), max(classlist_terms)),
                  classlist_terms)
  st <- add_next_term_col(st, term, summer = FALSE) %>%
    dplyr::rename(next_regular_term = next_term) %>%
    dplyr::mutate(next_regular_term = as.integer(next_regular_term))
  enrolled_terms <- st %>%
    dplyr::filter(enrolled) %>%
    dplyr::distinct(student_id, next_regular_term = term) %>%
    dplyr::mutate(.returned = TRUE)
  st <- st %>%
    dplyr::left_join(enrolled_terms, by = c("student_id", "next_regular_term")) %>%
    dplyr::mutate(
      return_observable = next_regular_term <= settled_edge &
        next_regular_term %in% classlist_terms,
      returned_next_regular_term = dplyr::if_else(return_observable,
                                                  dplyr::coalesce(.returned, FALSE), NA)
    ) %>%
    dplyr::select(-.returned)
  if (length(gaps) > 0L) {
    message(sprintf(
      "[student-terms.R] no class list for %s: the %s student-term(s) whose next regular term is one of them have return_observable FALSE, never a return of FALSE.",
      paste(fmt_term(gaps), collapse = ", "),
      format(sum(st$next_regular_term %in% gaps), big.mark = ",")))
  }

  # ── Degrees awarded that term ────────────────────────────────────────────
  if (!is.null(degrees) && nrow(degrees) > 0L) {
    awarded <- dplyr::ungroup(degrees)
    if ("graduation_status" %in% names(awarded)) {
      awarded <- dplyr::filter(awarded, graduation_status == "Awarded")
    }
    awarded <- awarded %>%
      dplyr::mutate(term = as.integer(term)) %>%
      dplyr::distinct(student_id, term) %>%
      dplyr::mutate(degree_awarded = TRUE)
    st <- dplyr::left_join(st, awarded, by = c("student_id", "term")) %>%
      dplyr::mutate(degree_awarded = dplyr::coalesce(degree_awarded, FALSE))
  } else {
    message("[student-terms.R] no degrees supplied: degree_awarded is FALSE on every row.")
    st <- dplyr::mutate(st, degree_awarded = FALSE)
  }

  st <- st %>%
    dplyr::select(dplyr::all_of(STUDENT_TERMS_COLUMNS)) %>%
    dplyr::arrange(student_id, term)

  n_conflict <- sum(st$description_conflict, na.rm = TRUE)
  message(sprintf(
    "[student-terms.R] %s student-terms: %s enrolled, %s declared without a class list, %s described by both sources (%s disagree), settled through %s",
    format(nrow(st), big.mark = ","), format(sum(st$enrolled), big.mark = ","),
    format(sum(st$declared & st$class_list_rows == 0L), big.mark = ","),
    format(sum(st$description_source %in% c("programs", "both_agree") &
                 !is.na(st$classlist_as_of)), big.mark = ","),
    format(n_conflict, big.mark = ","), fmt_term(settled_edge)))

  attr(st, "cedar_student_terms_build_version") <- STUDENT_TERMS_BUILD_VERSION
  validate_student_terms(st)
}


# Enrollment facts per student-term from the class list. The credit figures
# keep the definition the retired cedar_student_term_credits table used
# (registered rows with a credit value, de-duplicated the same way), so
# build_credit_timeline() reads the same numbers from this table as it did
# from that one.
.student_terms_enrollment <- function(students) {
  # CAMPUS_ROLLUP: these are a student's courses in a term, a curriculum count
  # and not a delivery metric; the same course on two campuses is one course.
  # Delivery campus lives on the attempt, never on the student-term.
  by_course <- students %>%
    dplyr::group_by(student_id, term, subject_course) %>%
    dplyr::summarize(
      .registered = any(registration_status_code %in% STATUS_REGISTERED),
      .late_only  = !.registered & any(registration_status_code %in% STATUS_DROP_LATE),
      .early_only = !.registered & !any(registration_status_code %in% STATUS_DROP_LATE) &
                    any(registration_status_code %in% STATUS_DROP_EARLY),
      .groups = "drop")
  courses <- by_course %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(registered_courses = sum(.registered),
                     late_withdrawals = sum(.late_only),
                     early_drops = sum(.early_only), .groups = "drop")

  rows <- students %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(
      class_list_rows = dplyr::n(),
      enrolled = any(registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)),
      waitlisted_only = !enrolled & any(registration_status_code %in% STATUS_WAITLIST),
      classlist_as_of = .newest_date(as_of_date),
      .groups = "drop")

  registered <- students %>%
    dplyr::filter(registration_status_code %in% STATUS_REGISTERED)
  # CAMPUS_ROLLUP: one curriculum credit load per student-term, not a delivery
  # metric; a repeated course counts once even if its campus changed.
  credits <- registered %>%
    dplyr::filter(!is.na(credits)) %>%
    dplyr::distinct(student_id, term, subject_course, course_title, credits,
                    final_grade, registration_status_code) %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(
      attempted_unm_credits = sum(credits),
      completed_unm_credits = sum(dplyr::if_else(final_grade %in% passing_grades, credits, 0)),
      .groups = "drop")
  # Posted grades only; a blank grade is unknown. Late drops are not here:
  # they have their own column, and classify_enrollment_outcomes() would
  # otherwise count them as DFW.
  graded <- registered %>%
    classify_enrollment_outcomes() %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(dfw_grades = sum(outcome == "dfw"), .groups = "drop")
  posted <- registered %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(graded_rows = sum(!is.na(final_grade) & nzchar(final_grade)),
                     .groups = "drop")

  rows %>%
    dplyr::left_join(courses, by = c("student_id", "term")) %>%
    dplyr::left_join(credits, by = c("student_id", "term")) %>%
    dplyr::left_join(graded, by = c("student_id", "term")) %>%
    dplyr::left_join(posted, by = c("student_id", "term"))
}


# The class list's description of the student that term: one value per
# column, from the newest pull. Two values inside one pull is an error, not a
# choice (ISSUES.md I44's neighbour: 111 student-terms carry two
# classifications, every one from rows pulled on two dates).
.student_terms_classlist_description <- function(students) {
  cols <- c("student_level", "student_classification", "student_campus", "residency")
  newest <- students %>%
    dplyr::mutate(.pull = as.Date(as_of_date)) %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::filter(.pull == .newest_date(.pull) | is.na(.pull)) %>%
    dplyr::ungroup()
  description <- newest %>%
    dplyr::distinct(student_id, term, dplyr::across(dplyr::all_of(cols)))
  .stop_on_repeated_keys(description, "class list", "level, classification, campus or residency")
  # The major and home college Banner stamped on the roster, read only where
  # academic studies has no row (see build_student_terms()). One pull can
  # carry two majors for a student, stamped on sections registered either
  # side of a change; where it does, the class list names no primary major
  # and the count is reported, never the first or the later one.
  one_value <- function(x) {
    x <- unique(x[!is.na(x) & nzchar(x)])
    if (length(x) == 1L) x else NA_character_
  }
  n_values <- function(x) length(unique(x[!is.na(x) & nzchar(x)]))
  major <- newest %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(cl_major_code = one_value(major_code),
                     cl_student_college = one_value(student_college),
                     .n_majors = n_values(major_code), .groups = "drop")
  if (any(major$.n_majors > 1L)) {
    message(sprintf(
      "[student-terms.R] %s student-term(s) carry two majors in one class-list pull; the class list names no primary major there.",
      format(sum(major$.n_majors > 1L), big.mark = ",")))
  }
  description %>%
    dplyr::rename_with(~ paste0("cl_", .x), dplyr::all_of(cols)) %>%
    dplyr::left_join(dplyr::select(major, -.n_majors), by = c("student_id", "term"))
}


# Academic studies' description of the student that term, its declarations,
# and the primary major (the first Major row by code, the transform's rule).
.student_terms_programs_description <- function(programs) {
  cols <- c("student_level", "student_classification", "student_campus", "residency",
            "academic_standing", "time_status")
  newest <- programs %>%
    dplyr::mutate(.pull = as.Date(as_of_date)) %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::filter(.pull == .newest_date(.pull) | is.na(.pull)) %>%
    dplyr::ungroup()
  description <- newest %>%
    dplyr::distinct(student_id, term, dplyr::across(dplyr::all_of(cols)))
  .stop_on_repeated_keys(description, "academic studies",
                         "level, classification, campus, residency, standing or time status")
  # The term GPA is the one description academic studies repeats with two
  # values in one pull: a program row duplicated with a 0.00 beside the real
  # figure (381 student-terms, 0.09%, on the 2026-10-27 pull). Where the rows
  # agree the value is kept; where they do not it is NA and counted, never
  # the larger or the later one.
  gpa <- newest %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(.n_gpa = dplyr::n_distinct(sem_gpa),
                     sem_gpa = dplyr::if_else(.n_gpa == 1L, dplyr::first(sem_gpa), NA_real_),
                     .groups = "drop")
  if (any(gpa$.n_gpa > 1L)) {
    message(sprintf("[student-terms.R] %s student-term(s) carry two term GPAs in one academic studies pull; sem_gpa is NA there.",
                    format(sum(gpa$.n_gpa > 1L), big.mark = ",")))
  }
  description <- dplyr::left_join(description, dplyr::select(gpa, -.n_gpa), by = c("student_id", "term"))
  # Names to codes, through the institution's files. An unlisted name is NA
  # and reported, never guessed.
  description <- description %>%
    dplyr::mutate(
      .level_code  = cedar_level_code_from_source(student_level),
      .campus_code = cedar_campus_code_from_source(student_campus))
  .report_unlisted(description$student_level[is.na(description$.level_code)], "student level",
                   "student_levels.csv")
  .report_unlisted(description$student_campus[is.na(description$.campus_code)], "home campus",
                   "campuses.csv source_names")
  description <- description %>%
    dplyr::transmute(student_id, term,
                     p_student_level = .level_code, p_student_classification = student_classification,
                     p_student_campus = .campus_code, p_residency = residency,
                     academic_standing, time_status, sem_gpa)

  declarations <- programs %>%
    dplyr::group_by(student_id, term) %>%
    dplyr::summarize(n_declarations = dplyr::n(),
                     programs_as_of = .newest_date(as_of_date),
                     .groups = "drop")
  primary <- programs %>%
    dplyr::filter(program_type == "Major") %>%
    dplyr::arrange(student_id, term, major_code) %>%
    dplyr::distinct(student_id, term, .keep_all = TRUE) %>%
    dplyr::transmute(student_id, term, primary_major_code = major_code,
                     primary_source_college_code = source_college_code,
                     primary_source_college = source_college,
                     is_pre_major = as.logical(is_pre_major))

  description %>%
    dplyr::full_join(declarations, by = c("student_id", "term")) %>%
    dplyr::left_join(primary, by = c("student_id", "term"))
}


# Programs wins where present; the class list fills where there is no
# programs row; both present and disagreeing on level, classification or
# home campus is flagged. Nothing is coalesced silently: the flag and the
# source column say what happened on every row.
.student_terms_resolve_description <- function(st) {
  has_p  <- !is.na(st$programs_as_of)
  has_cl <- !is.na(st$classlist_as_of)
  differs <- function(a, b) !is.na(a) & !is.na(b) & a != b
  conflict <- has_p & has_cl & (
    differs(st$p_student_level, st$cl_student_level) |
    differs(st$p_student_classification, st$cl_student_classification) |
    differs(st$p_student_campus, st$cl_student_campus))
  # Not named pick(): inside mutate() dplyr's own pick() shadows a local
  # function of that name and returns the two columns as a nested data frame.
  .prefer_programs <- function(p, cl) dplyr::if_else(has_p, p, cl)
  st %>%
    dplyr::mutate(
      description_source = dplyr::case_when(
        has_p & has_cl & !conflict ~ "both_agree",
        has_p ~ "programs",
        TRUE ~ "class_list"),
      description_conflict = conflict,
      student_level = .prefer_programs(p_student_level, cl_student_level),
      student_classification = .prefer_programs(p_student_classification, cl_student_classification),
      student_campus = .prefer_programs(p_student_campus, cl_student_campus),
      residency = .prefer_programs(p_residency, cl_residency)
    )
}


# A programs table with no rows, typed as the build requires, so class lists
# alone take the same path as class lists with academic studies.
.empty_programs <- function() {
  tibble::tibble(
    student_id = character(), term = integer(), program_type = character(),
    major_code = character(), source_college_code = character(), source_college = character(),
    is_pre_major = logical(), student_level = character(),
    student_classification = character(), student_campus = character(),
    academic_standing = character(), residency = character(), time_status = character(),
    sem_gpa = double(), as_of_date = as.Date(character())
  )
}


# The newest of a group's pull dates, or an NA date when the group has none.
# max(..., na.rm = TRUE) warns and returns -Inf on an empty or all-NA group,
# which dplyr evaluates once even for an empty programs table (programs = NULL).
.newest_date <- function(x) {
  x <- as.Date(x)
  if (all(is.na(x))) return(as.Date(NA))
  max(x, na.rm = TRUE)
}

.stop_on_repeated_keys <- function(df, source, what) {
  dup <- df[duplicated(df[c("student_id", "term")]), c("student_id", "term")]
  if (nrow(dup) > 0L) {
    stop("[student-terms.R] ", nrow(dup), " student-term(s) carry more than one ", what,
         " in the newest ", source, " pull, e.g. ", dup$student_id[[1]], " in ", dup$term[[1]],
         ". Two values in one pull is a data error, not a choice.")
  }
  invisible(df)
}


.report_unlisted <- function(values, what, file) {
  values <- values[!is.na(values)]
  if (length(values) == 0L) return(invisible(NULL))
  counts <- sort(table(values), decreasing = TRUE)
  message(sprintf("[student-terms.R] %s %s value(s) the institution's %s does not list, stored as NA: %s",
                  format(length(values), big.mark = ","), what, file,
                  paste0(names(counts), " (", counts, ")", collapse = ", ")))
}


#' Check a student-term table
#'
#' @param st A tibble as built by [build_student_terms()] or read from disk.
#' @return `st`, unchanged, or an error naming what is wrong: a missing or
#'   banned column, a repeated key, an enrolled row without class-list rows, or
#'   a return judged where it is not observable.
validate_student_terms <- function(st) {
  missing <- setdiff(STUDENT_TERMS_COLUMNS, names(st))
  if (length(missing) > 0L) {
    stop("[student-terms.R] student-term table is missing column(s): ",
         paste(missing, collapse = ", "))
  }
  banned <- intersect(STUDENT_TERMS_BANNED_COLUMNS, names(st))
  if (length(banned) > 0L) {
    stop("[student-terms.R] pull-stamped column(s) on the student-term table: ",
         paste(banned, collapse = ", "), ". They describe the pull, not the term ",
         "(field reliability contract).")
  }
  nested <- STUDENT_TERMS_COLUMNS[!vapply(STUDENT_TERMS_COLUMNS, function(c) is.atomic(st[[c]]), logical(1))]
  if (length(nested) > 0L) {
    stop("[student-terms.R] column(s) are not plain vectors: ", paste(nested, collapse = ", "))
  }
  if (anyDuplicated(st[c("student_id", "term")]) > 0L) {
    stop("[student-terms.R] student-term table repeats a (student_id, term) key.")
  }
  if (any(st$enrolled & st$class_list_rows == 0L)) {
    stop("[student-terms.R] an enrolled student-term has no class-list rows.")
  }
  if (any(!st$return_observable & !is.na(st$returned_next_regular_term)) ||
      any(st$return_observable & is.na(st$returned_next_regular_term))) {
    stop("[student-terms.R] returned_next_regular_term must be NA exactly where ",
         "return_observable is FALSE.")
  }
  st
}


#' Attach student-term columns to any rows keyed by student and term
#'
#' @param rows A tibble with `student_id` and `term`.
#' @param student_terms The student-term table.
#' @param cols Character. Columns of `student_terms` to attach.
#' @return `rows` with `cols` joined on; stops if `rows` already has one of them.
#' Name program codes for display
#'
#' One name per code, the same everywhere a table's `primary_major_code` is
#' shown: the name `programs` records for the code first (the mapping file's,
#' with a pre-major's "Pre" already taken off), then `major_code_to_name` (the
#' class list's own spelling, which keeps it: "Pre Biology") for a code
#' `programs` never carries, such as a class-list-only associate program, then
#' the code itself. Used by the Gen Ed major mix and Dept Trends' SCH by major.
#'
#' @param codes Character vector of program codes; `NA` and blanks are dropped.
#' @param programs Data frame with `major_code`, `program_name`, `program_type`
#'   (`cedar_programs`, or any subset of it).
#' @param major_code_to_name Named character vector (`cedar_lookups`' table of
#'   the same name), or `NULL`.
#' @param is_pre_major Logical vector parallel to `codes` (the student-term
#'   table's flag on the same rows), or `NULL`. A code flagged on any row is
#'   suffixed " (pre-major)", so a pre-major and the major it leads to never
#'   share a label ("Psychology (pre-major)" beside "Psychology").
#' @return Named character vector, code to name, one entry per distinct code.
name_program_codes <- function(codes, programs, major_code_to_name = NULL,
                               is_pre_major = NULL) {
  needed <- c("major_code", "program_name", "program_type")
  missing_cols <- setdiff(needed, names(programs))
  if (length(missing_cols) > 0L) {
    stop("[student-terms.R] name_program_codes() needs programs with: ",
         paste(missing_cols, collapse = ", "))
  }
  if (!is.null(is_pre_major) && length(is_pre_major) != length(codes)) {
    stop("[student-terms.R] name_program_codes(): is_pre_major must be parallel to codes.")
  }
  keep <- !is.na(codes) & nzchar(codes)
  flagged <- if (is.null(is_pre_major)) character(0) else unique(codes[keep & !is.na(is_pre_major) & is_pre_major])
  codes <- unique(codes[keep])
  labels <- stats::setNames(codes, codes)
  if (length(codes) == 0L) return(labels)
  named <- programs %>%
    dplyr::filter(major_code %in% .env$codes, !is.na(program_name), program_name != "") %>%
    dplyr::arrange(major_code, dplyr::desc(program_type == "Major")) %>%
    dplyr::distinct(major_code, .keep_all = TRUE)
  labels[named$major_code] <- named$program_name
  unnamed <- setdiff(codes, named$major_code)
  if (length(unnamed) > 0L && !is.null(major_code_to_name) && length(major_code_to_name) > 0L) {
    translated <- unname(major_code_to_name[unnamed])
    has_translation <- !is.na(translated) & translated != ""
    labels[unnamed[has_translation]] <- translated[has_translation]
  }
  labels[flagged] <- paste0(labels[flagged], " (pre-major)")
  labels
}

attach_student_term <- function(rows, student_terms, cols) {
  if (!all(c("student_id", "term") %in% names(rows))) {
    stop("[student-terms.R] attach_student_term() needs student_id and term on rows.")
  }
  unknown <- setdiff(cols, names(student_terms))
  if (length(unknown) > 0L) {
    stop("[student-terms.R] not on the student-term table: ", paste(unknown, collapse = ", "))
  }
  clash <- intersect(cols, names(rows))
  if (length(clash) > 0L) {
    stop("[student-terms.R] rows already carry: ", paste(clash, collapse = ", "),
         ". Drop them first, so the student-term value is the one read.")
  }
  dplyr::left_join(rows,
                   dplyr::select(student_terms, student_id, term, dplyr::all_of(cols)),
                   by = c("student_id", "term"))
}
