# CEDAR-PLATFORM: course × term measure table (ADR-001 step 4)
#
# cedar_course_terms: one row per course, term, delivery campus and part of
# term, counted once over the whole loaded class list and schedule under the
# canonical definitions. It is what a reader filters and joins instead of
# recounting 1.85M class-list rows: the course-term counts Regstats screens,
# the census history Waitlists' sparklines read, the first-day seat pressure
# the planning history and Degree Explorer show, and the Department
# Dashboard's Regstats flags. Built by the transform (transform_measures(),
# ADR-001 step 6), loaded by every loader, held at
# data_objects[["cedar_course_terms"]], never built by the app.
#
# Grain. The class list is one row per student, course, campus and term, so a
# student is in one part of term of a course-term-campus, never two (measured
# on the 2026-10-08 pull: none of 1,853,633). The part-of-term rows therefore
# sum exactly to course × term × campus: a reader that wants the ADR's grain
# sums over part_term. College is the course's (attach_default_units()), one
# per course-term-campus.
#
# It follows the course, not the code: it is counted over the keyed class
# list and schedule (attach_course_ids()), so subject_course is the course_id
# and a renumbered course's terms are one course's rows. The renames it was
# counted over are stamped on it, so a saved copy made before a
# code_history.csv row was confirmed is refused, as is one saved by an older
# build.
#
# Two sources, joined in full. The class-list side is calc_cl_enrls() by part
# of term with census enrollment (add_census_enrl()) and the first-day count
# reconstructed from status dates (calc_first_day_enrl(), over the rows that
# sit in an active section). The schedule's side is the active offerings:
# sections with seats or students (a zero-seat, zero-enrollment active
# section is a placeholder, not an offering), each crosslisted section once,
# under its home listing (keep_home_sections(), the house rule the Department
# Dashboard and the registration snapshots apply), their scheduled seats
# (get_enrl(): enrolled + available), the DESR headcount at the pull, whether
# every section's capacity is known, and how many of them the class list has
# a row for. A partner listing's row therefore holds students and no
# section: the seats are the family's, counted once under the home code, and
# a fill read against them needs the family (the Course Report's crosslist
# payload), not one listing. **NA on one side means that source has no row
# for the course-term**: no class-list registration under the course
# (unknown, never zero enrollment: EC-11b), or no active offering in the
# schedule. A reader that compares the two reads both and says which is
# missing (Regstats' saturation coverage, the planning history's
# source_matched); it never fills one in from the other.
#
# Outcomes come from cedar_attempts (R/branches/attempts.R), classified once:
# `attempts` (the DFW denominator: passed + dfw), `passed`, `dfw` and
# `withdrawn` (late withdrawals, part of dfw). They are NA after the graded
# edge, where no grade has posted: unknown, never zero.
#
# It carries counts for each course-term and nothing pooled across terms: a
# mean or baseline is the reader's question (Regstats' baselines are
# strictly prior, Waitlists' exclude the viewed term), and a table that held
# one would hold a later term's counts in an earlier term's row.

#' Build version of cedar_course_terms. Bump when a column is added, renamed
#' or changes meaning, so a saved copy from the older build is rebuilt.
#' 3: first-day enrollment, the schedule's offerings and seats, subject_code.
#' 4: a crosslisted section is counted once, under its home listing.
COURSE_TERMS_BUILD_VERSION <- 4L

#' The row key: a course offered on a campus in a part of one term.
COURSE_TERMS_KEY <- c("campus", "college", "term", "subject_course", "part_term")

#' The columns cedar_course_terms carries, in order.
COURSE_TERMS_COLUMNS <- c(
  "campus", "college", "term", "term_type", "subject_course", "subject_code", "part_term",
  "level", "department",
  "registered", "dr_early", "dr_late", "dr_all", "wl_all", "cl_total", "census_enrl",
  "first_day_enrl", "first_day_basis", "first_day_started_enrl",
  "sections", "sections_matched", "seats", "seats_known", "desr_enrl",
  "attempts", "passed", "dfw", "withdrawn"
)

#' Count the course-term measure table
#'
#' The class-list counts of calc_cl_enrls() by part of term, with census
#' enrollment (add_census_enrl()) and the first-day count
#' (calc_first_day_enrl()), the schedule's active offerings and seats
#' (get_enrl()), and each course's subject, level and department.
#' `registered` is still registered at the pull (final, for a past term);
#' `cl_total` is every non-waitlist registration (ever registered:
#' `registered + dr_all`); `census_enrl` is `registered + dr_late`; `wl_all`
#' counts waitlist rows, not true demand (`R/branches/waitlist-demand.R`).
#' `first_day_enrl` is counted over the class-list rows in an active
#' section, NA with `first_day_basis` saying why when a status or start
#' date is missing or a session had not begun at the pull. `sections` counts
#' the active offerings (a crosslisted section once, under its home listing),
#' `sections_matched` those with a class-list row, `seats` their scheduled
#' seats (`enrolled + available`), `seats_known` whether every one has a
#' finite capacity, and `desr_enrl` the schedule's headcount at the pull. NA
#' on either side means that source has no row for the course-term. The
#' outcome counts are count_attempt_outcomes() over `attempts`.
#'
#' @param students `cedar_registrations` keyed on the course (attach_course_ids()),
#'   with `registration_date` and `as_of_date`.
#' @param attempts cedar_attempts built from the same class list
#'   (build_attempts()); its graded edge decides which terms carry outcomes.
#' @param sections `cedar_sections` keyed on the course, with `status`,
#'   `enrolled`, `available`, `total_enrl`, `crosslist_code`, `crosslist_group`,
#'   `crosslist_role` and `start_date`.
#' @return One row per campus, college, term, course and part of term, with
#'   exactly COURSE_TERMS_COLUMNS, ungrouped, stamped with `code_renames`,
#'   `graded_edge` and `course_terms_build_version`.
build_course_terms <- function(students, attempts, sections) {
  .listed_codes(students, "build_course_terms")
  .listed_codes(sections, "build_course_terms")
  need_students <- c("part_term", "level", "department", "subject_code", "crn", "student_id",
                     "registration_status_code", "registration_date", "as_of_date")
  missing <- setdiff(need_students, names(students))
  if (length(missing) > 0) {
    stop("[course-terms.R] build_course_terms(): students lack ",
         paste(missing, collapse = ", "), ".")
  }
  need_sections <- c(COURSE_TERMS_KEY, "crn", "status", "enrolled", "available", "total_enrl",
                     "crosslist_code", "crosslist_group", "crosslist_role", "start_date",
                     "level", "department", "subject")
  missing <- setdiff(need_sections, names(sections))
  if (length(missing) > 0) {
    stop("[course-terms.R] build_course_terms(): sections lack ",
         paste(missing, collapse = ", "), ".")
  }
  renames <- course_code_renames(students)
  graded_edge <- require_current_attempts(attempts, students, "build_course_terms")
  key <- COURSE_TERMS_KEY
  students <- ungroup(students)
  sections <- ungroup(sections)

  # The class list's side.
  counts <- calc_cl_enrls(students, by_part_term = TRUE) %>%
    ungroup() %>%
    add_census_enrl() %>%
    select(all_of(c(key, "registered", "dr_early", "dr_late", "dr_all", "wl_all",
                    "cl_total", "census_enrl")))

  # The schedule's side: the active offerings. A section with no seats and no
  # enrollment is a placeholder; one whose capacity is unknown still offers.
  # A crosslisted section is one offering, counted under its home listing
  # (keep_home_sections()): a partner listing's row has students and no section.
  active <- sections %>%
    filter(status == "A",
           !is.finite(enrolled + available) | enrolled + available > 0 | total_enrl > 0) %>%
    keep_home_sections()
  if (nrow(active) > 0) {
    supply <- get_enrl(active, list(status = "A", uel = FALSE, crosslist = "home",
                                    group_cols = key)) %>%
      ungroup() %>%
      transmute(across(all_of(key)),
                sections  = as.integer(sections),
                desr_enrl = as.integer(round(enrolled)),
                seats     = as.numeric(enrolled) + as.numeric(avail))
  } else {
    supply <- counts[integer(0), key] %>%
      mutate(sections = integer(), desr_enrl = integer(), seats = numeric())
  }
  quality <- active %>%
    group_by(across(all_of(key))) %>%
    summarize(seats_known = all(is.finite(enrolled) & is.finite(available) &
                                  enrolled + available > 0),
              .groups = "drop")
  # Which active sections the class list has a row for, by the section's own
  # key: a section with none leaves the course-term's first day unmatched.
  rostered <- students %>% distinct(across(all_of(c(key, "crn"))))
  matched <- active %>%
    distinct(across(all_of(c(key, "crn")))) %>%
    semi_join(rostered, by = c(key, "crn")) %>%
    count(across(all_of(key)), name = "sections_matched")

  # First day, over the class-list rows that sit in an active section, read
  # against each section's first class day.
  roster_cols <- c(key, "student_id", "crn", "registration_status_code",
                   "registration_date", "as_of_date")
  in_active <- students %>%
    select(all_of(roster_cols)) %>%
    filter_classlist_to_sections(active)
  first_day <- calc_first_day_enrl(in_active, active, by_part_term = TRUE)

  # One row per course for the subject/level/department lookup; the first row
  # stands for the rare crosslisted course listed under more than one
  # department. A course the class list never saw takes the schedule's.
  # CAMPUS_ROLLUP: a course's level and department do not vary by campus; the
  # counts this lookup joins onto are grouped by campus.
  course_meta <- students %>%
    distinct(subject_course, .keep_all = TRUE) %>%
    select(subject_course, level, department, subject_code)
  section_meta <- active %>%
    distinct(subject_course, .keep_all = TRUE) %>%
    select(subject_course, .level = level, .department = department, .subject_code = subject)

  # Attempts are a subset of the class-list rows these counts are taken over,
  # so every attempt's course-term is a row here; one that is not means the
  # two were built from different tables.
  outcomes <- count_attempt_outcomes(attempts)
  orphans <- anti_join(outcomes, counts, by = key)
  if (nrow(orphans) > 0) {
    stop("[course-terms.R] build_course_terms(): ", nrow(orphans), " course-terms have ",
         "attempts but no class-list counts (first: ", orphans$subject_course[1], " ",
         orphans$term[1], "); attempts and students must come from one class list")
  }
  outcome_cols <- c("attempts", "passed", "dfw", "withdrawn")
  course_terms <- full_join(counts, supply, by = key) %>%
    left_join(quality, by = key, relationship = "one-to-one") %>%
    left_join(matched, by = key, relationship = "one-to-one") %>%
    left_join(first_day, by = key, relationship = "one-to-one") %>%
    left_join(course_meta, by = "subject_course", relationship = "many-to-one") %>%
    left_join(section_meta, by = "subject_course", relationship = "many-to-one") %>%
    left_join(outcomes, by = key, relationship = "one-to-one") %>%
    mutate(
      # An offering with no class-list row in any of its sections has none matched.
      sections_matched = if_else(!is.na(sections) & is.na(sections_matched), 0L, sections_matched),
      level        = coalesce(level, .level),
      department   = coalesce(department, .department),
      subject_code = coalesce(subject_code, .subject_code),
      # A graded term with no attempt row has none (all early drops or
      # waitlists): zero. A term past the graded edge has no outcomes yet: NA.
      # A course-term the class list has no row for has no attempts: NA.
      across(all_of(outcome_cols),
             ~ if_else(as.integer(term) <= graded_edge & !is.na(registered),
                       coalesce(.x, 0L), NA_integer_))
    ) %>%
    add_term_type_col("term") %>%
    arrange(across(all_of(key))) %>%
    select(all_of(COURSE_TERMS_COLUMNS))
  attr(course_terms, "code_renames") <- renames
  attr(course_terms, "graded_edge") <- graded_edge
  attr(course_terms, "course_terms_build_version") <- COURSE_TERMS_BUILD_VERSION
  course_terms
}

#' Was this course-term table counted by this build over this class list?
#'
#' TRUE when it carries the current build version, exactly its columns, and
#' the renames of the class list now loaded. FALSE for anything else,
#' including a table saved by an older build, a table counted by code, or
#' NULL: the loader refuses it, and so does a reader
#' (require_current_course_terms()).
#'
#' @param course_terms A saved cedar_course_terms, or anything else.
#' @param students `cedar_registrations` keyed on the course.
#' @param graded_edge The loader's graded edge, to refuse a table whose
#'   outcome columns stop at another; NULL for a reader that does not read
#'   them.
course_terms_is_current <- function(course_terms, students, graded_edge = NULL) {
  if (!course_terms_is_build(course_terms)) return(FALSE)
  if (!is.null(graded_edge) &&
      !identical(attr(course_terms, "graded_edge", exact = TRUE), as.integer(graded_edge))) {
    return(FALSE)
  }
  renames <- attr(course_terms, "code_renames", exact = TRUE)
  if (is.null(renames)) return(FALSE)
  identical(as.character(renames), course_code_renames(students))
}

#' Does this table carry the current build's version and columns?
course_terms_is_build <- function(course_terms) {
  is.data.frame(course_terms) &&
    identical(attr(course_terms, "course_terms_build_version", exact = TRUE),
              COURSE_TERMS_BUILD_VERSION) &&
    identical(names(course_terms), COURSE_TERMS_COLUMNS)
}

#' Stop unless a course-term table is current for this class list
#'
#' @param course_terms cedar_course_terms as passed to a reader.
#' @param students The class list the reader also holds.
#' @param caller The reader's name, for the error.
require_current_course_terms <- function(course_terms, students, caller) {
  if (!course_terms_is_current(course_terms, students)) {
    stop("[course-terms.R] ", caller, "(): course_terms was not built by ",
         "build_course_terms() over this class list (build ",
         COURSE_TERMS_BUILD_VERSION, ", its course codes); ", CEDAR_MEASURES_REBUILD_HINT,
         call. = FALSE)
  }
  invisible(course_terms)
}

#' Stop unless a course-term table is this build's
#'
#' For a reader that holds the table and not the class list (the planning
#' history): the build version and columns are checked, the renames are the
#' loader's job (cedar_load_measure_table()).
#'
#' @param course_terms cedar_course_terms as passed to a reader.
#' @param caller The reader's name, for the error.
require_course_terms_build <- function(course_terms, caller) {
  if (!course_terms_is_build(course_terms)) {
    stop("[course-terms.R] ", caller, "(): course_terms was not built by build_course_terms() ",
         "(build ", COURSE_TERMS_BUILD_VERSION, "); ", CEDAR_MEASURES_REBUILD_HINT,
         call. = FALSE)
  }
  invisible(course_terms)
}
