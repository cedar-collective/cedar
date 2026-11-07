# CEDAR-PLATFORM: course × term measure table (ADR-001 step 4)
#
# cedar_course_terms: one row per course, term, delivery campus and part of
# term, counted once over the whole loaded class list under the canonical
# definitions. It is what a reader filters and joins instead of recounting
# 1.85M class-list rows: the course-term counts Regstats filters, the history
# Waitlists' census sparklines read, and the Department Dashboard's Regstats
# flags. Built at start (global.R, every loader that reads it), held at
# data_objects[["cedar_course_terms"]], saved beside the data as a cache only.
#
# Grain. The class list is one row per student, course, campus and term, so a
# student is in one part of term of a course-term-campus, never two (measured
# on the 2026-10-08 pull: none of 1,853,633). The part-of-term rows therefore
# sum exactly to course × term × campus: a reader that wants the ADR's grain
# sums over part_term. College is the course's (attach_default_units()), one
# per course-term-campus.
#
# It follows the course, not the code: it is counted over the keyed class
# list (attach_course_ids()), so subject_course is the course_id and a
# renumbered course's terms are one course's rows. The renames it was counted
# over are stamped on it, so a saved copy made before a code_history.csv row
# was confirmed is refused, as is one saved by an older build.
#
# It carries counts for each course-term and nothing pooled across terms: a
# mean or baseline is the reader's question (Regstats' baselines are
# strictly prior, Waitlists' exclude the viewed term), and a table that held
# one would hold a later term's counts in an earlier term's row.

#' Build version of cedar_course_terms. Bump when a column is added, renamed
#' or changes meaning, so a saved copy from the older build is rebuilt.
COURSE_TERMS_BUILD_VERSION <- 1L

#' The columns cedar_course_terms carries, in order.
COURSE_TERMS_COLUMNS <- c(
  "campus", "college", "term", "term_type", "subject_course", "part_term",
  "level", "department",
  "registered", "dr_early", "dr_late", "dr_all", "wl_all", "cl_total",
  "census_enrl"
)

#' Count the course-term measure table
#'
#' The class-list counts of calc_cl_enrls() by part of term, with census
#' enrollment (add_census_enrl()) and each course's level and department.
#' `registered` is still registered at the pull (final, for a past term);
#' `cl_total` is every non-waitlist registration (ever registered:
#' `registered + dr_all`); `census_enrl` is `registered + dr_late`; `wl_all`
#' counts waitlist rows, not true demand (`R/branches/waitlist-demand.R`).
#'
#' @param students `cedar_students` keyed on the course (attach_course_ids()).
#' @return One row per campus, college, term, course and part of term, with
#'   exactly COURSE_TERMS_COLUMNS, ungrouped, stamped with `code_renames`
#'   and `course_terms_build_version`.
build_course_terms <- function(students) {
  .listed_codes(students, "build_course_terms")
  missing <- setdiff(c("part_term", "level", "department"), names(students))
  if (length(missing) > 0) {
    stop("[course-terms.R] build_course_terms(): students lack ",
         paste(missing, collapse = ", "), ".")
  }
  renames <- course_code_renames(students)
  counts <- calc_cl_enrls(students, by_part_term = TRUE) %>%
    ungroup() %>%
    add_census_enrl()
  # One row per course for the level/department lookup; the first row stands
  # for the rare crosslisted course listed under more than one department.
  # CAMPUS_ROLLUP: a course's level and department do not vary by campus; the
  # counts this lookup joins onto are grouped by campus.
  course_meta <- students %>%
    ungroup() %>%
    distinct(subject_course, .keep_all = TRUE) %>%
    select(subject_course, level, department)
  course_terms <- counts %>%
    left_join(course_meta, by = "subject_course", relationship = "many-to-one") %>%
    select(all_of(COURSE_TERMS_COLUMNS))
  attr(course_terms, "code_renames") <- renames
  attr(course_terms, "course_terms_build_version") <- COURSE_TERMS_BUILD_VERSION
  course_terms
}

#' Was this course-term table counted by this build over this class list?
#'
#' TRUE when it carries the current build version, exactly its columns, and
#' the renames of the class list now loaded. FALSE for anything else,
#' including a table saved by an older build, a table counted by code, or
#' NULL: the loader rebuilds it, and a reader refuses it
#' (require_current_course_terms()).
#'
#' @param course_terms A saved cedar_course_terms, or anything else.
#' @param students `cedar_students` keyed on the course.
course_terms_is_current <- function(course_terms, students) {
  if (!is.data.frame(course_terms)) return(FALSE)
  if (!identical(attr(course_terms, "course_terms_build_version", exact = TRUE),
                 COURSE_TERMS_BUILD_VERSION)) return(FALSE)
  if (!identical(names(course_terms), COURSE_TERMS_COLUMNS)) return(FALSE)
  renames <- attr(course_terms, "code_renames", exact = TRUE)
  if (is.null(renames)) return(FALSE)
  identical(as.character(renames), course_code_renames(students))
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
         COURSE_TERMS_BUILD_VERSION, ", its course codes); build it as global.R does at start.",
         call. = FALSE)
  }
  invisible(course_terms)
}
