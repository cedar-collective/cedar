# course-outcomes.R — Course Outcome and Persistence Analysis
#
# For a specific course (or set of courses), breaks down what happened to
# students after each grade outcome: did they return next term? How has the
# DFW rate changed over time? How do instructors compare to the course average?
#
# This is course-first analysis. For cohort-first stop-out analysis (which
# courses are bleeding a specific student population?), see stopout.R.
#
# All functions take cedar_students as primary input.
#
# DFW calculations delegate to get_grades() (gradebook.R) for a consistent
# DFW formula across the app. cedar_faculty is required for those analyses;
# without it, dfw_trend and instructor_dfw are returned as empty tibbles.
#
# Depends on: STATUS_REGISTERED, STATUS_DROP_EARLY (lists/status_codes.R)
#             GRADES_DFW, GRADES_PASS (lists/grades.R)
#             get_grades() (branches/gradebook.R)
#             dedup_enrollment(), add_next_term_col() (trunk/utils.R)


# ── Main wrapper ──────────────────────────────────────────────────────────────

#' Analyze outcomes for one or more courses
#'
#' Runs all three outcome analyses — persistence, DFW trend, and instructor
#' comparison — and returns them as a named list.
#'
#' DFW trend and instructor comparison delegate to get_grades() so that the
#' DFW formula (failed / (passed + failed), early drops excluded) matches the
#' rest of the app. cedar_faculty is required for those two analyses.
#'
#' Persistence filtering and deduplication are handled internally.
#'
#' @param students cedar_students data frame.
#' @param cedar_faculty cedar_faculty data frame, or NULL to skip DFW analyses.
#' @param opt Options list:
#'   \itemize{
#'     \item \code{course}  — character vector of subject_course values (required)
#'     \item \code{term}    — integer vector; restrict to these terms (optional)
#'     \item \code{campus}  — character vector; restrict by campus (optional)
#'     \item \code{min_n}   — integer; minimum graded students per group (default 5)
#'   }
#' @return Named list:
#'   \describe{
#'     \item{persistence}{Tibble from \code{next_term_persistence()}}
#'     \item{dfw_trend}{Tibble: campus, college, subject_course, term, dfw_pct (from gradebook)}
#'     \item{instructor_dfw}{Tibble: campus, college, subject_course, instructor_last_name,
#'       dfw_pct, course_avg_dfw, dfw_diff (from gradebook)}
#'     \item{courses}{Character vector of courses analyzed}
#'   }
get_course_outcomes <- function(students, cedar_faculty = NULL, opt = list()) {

  message("[course-outcomes.R] Welcome to get_course_outcomes!")

  courses <- opt$course %||% opt$courses
  if (is.null(courses) || length(courses) == 0) {
    stop("[course-outcomes.R] opt$course is required.")
  }
  courses <- as.character(courses)
  message("[course-outcomes.R] Courses: ", paste(courses, collapse = ", "))

  # Pre-filter for persistence analysis (needs registration_status + grade info).
  # DFW analyses re-filter internally via get_grades().
  filtered <- students %>%
    filter(
      subject_course %in% courses,
      registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_EARLY, STATUS_DROP_LATE)
    )

  if (!is.null(opt$term) && length(opt$term) > 0)
    filtered <- filtered %>% filter(term %in% opt$term)
  if (!is.null(opt$campus) && length(opt$campus) > 0)
    filtered <- filtered %>% filter(campus %in% opt$campus)

  filtered <- dedup_enrollment(filtered, level = "course")

  if (nrow(filtered) == 0) {
    message("[course-outcomes.R] No records after filtering.")
    return(list(
      persistence    = tibble(),
      dfw_trend      = tibble(),
      instructor_dfw = tibble(),
      courses        = courses
    ))
  }

  message("[course-outcomes.R] ", n_distinct(filtered$student_id),
          " students across ", n_distinct(filtered$term), " terms.")

  # ── DFW analyses via get_grades() ───────────────────────────────────────────
  # get_grades() uses: failed/(passed+failed), early drops excluded from denominator.
  # Call once and extract both tables to avoid running the pipeline twice.

  dfw_trend_out      <- tibble()
  instructor_dfw_out <- tibble()

  grades <- get_grades(students, opt)

  if (!is.null(grades) && length(grades) > 0) {

    dfw_trend_out <- grades[["course_avg_by_term"]] %||% tibble()
    message("[course-outcomes.R] DFW trend: ", nrow(dfw_trend_out), " term rows.")

    ci <- grades[["course_inst_avg"]]
    ca <- grades[["course_avg"]]

    if (!is.null(ci) && nrow(ci) > 0 && !is.null(ca) && nrow(ca) > 0) {
      instructor_dfw_out <- ci %>%
        left_join(
          ca %>% select(campus, college, subject_course, course_avg_dfw = dfw_pct),
          by = c("campus", "college", "subject_course")
        ) %>%
        mutate(dfw_diff = round(dfw_pct - course_avg_dfw, 3)) %>%
        arrange(subject_course, dfw_diff)
      message("[course-outcomes.R] Instructor comparison: ", nrow(instructor_dfw_out), " rows.")
    }
  }

  list(
    persistence    = next_term_persistence(filtered, students, opt),
    dfw_trend      = dfw_trend_out,
    instructor_dfw = instructor_dfw_out,
    courses        = courses
  )
}


# ── Persistence analysis ──────────────────────────────────────────────────────

#' Next-term persistence by grade outcome
#'
#' For each grade outcome (pass / dfw / drop), reports how many students
#' returned to any course the following term. Gives a course-level view of
#' whether bad outcomes actually drive students away.
#'
#' Uses the full \code{all_students} table (not pre-filtered) as the enrollment
#' source when checking whether a student returned — so next-term returns
#' outside the filtered course set are detected correctly.
#'
#' Early drops get their own "drop" outcome here, separate from academic DFW,
#' because the persistence question is different for each group.
#'
#' @param filtered Deduplicated cedar_students rows for the target course(s).
#' @param all_students Full cedar_students table.
#' @param opt Options list; uses \code{opt$min_n} (default 5).
#' @return Tibble: subject_course, outcome, n_students, n_returned,
#'   pct_returned; sorted by subject_course, outcome.
next_term_persistence <- function(filtered, all_students, opt = list()) {
  min_n <- opt$min_n %||% 5L

  message("[course-outcomes.R] Computing next-term persistence by outcome...")

  # Respect caller-supplied passing grades (e.g. from a DFW threshold selector).
  # Defaults to GRADES_PASS (C or better). Any grade that isn't passing, isn't a
  # drop, and isn't a W is classified as "fail" — no need to enumerate fail grades.
  custom_pass <- opt$passing_grades %||% GRADES_PASS

  graded <- filtered %>%
    mutate(
      outcome = case_when(
        registration_status_code %in% STATUS_DROP_EARLY  ~ "early drop",
        registration_status_code %in% STATUS_DROP_LATE   ~ "late drop",
        final_grade == "W"                               ~ "late drop",
        final_grade %in% custom_pass                     ~ "pass",
        !is.na(final_grade) & nzchar(final_grade)        ~ "fail",
        TRUE                                             ~ NA_character_
      ),
      outcome = factor(outcome, levels = c("early drop", "late drop", "fail", "pass"))
    ) %>%
    filter(!is.na(outcome))

  if (nrow(graded) == 0) return(tibble())

  # Next-term lookup: for each student-term, did they enroll the following term?
  all_terms <- all_students %>%
    select(student_id, term) %>%
    distinct()

  next_terms <- graded %>%
    select(student_id, term) %>%
    distinct() %>%
    add_next_term_col("term", summer = FALSE) %>%   # adds next_term column
    left_join(
      all_terms %>% rename(next_term = term) %>% mutate(returned = TRUE),
      by = c("student_id", "next_term")
    ) %>%
    mutate(returned = replace_na(returned, FALSE)) %>%
    select(student_id, term, returned)

  result <- graded %>%
    left_join(next_terms, by = c("student_id", "term")) %>%
    group_by(subject_course, outcome) %>%
    summarize(
      n_students   = n_distinct(student_id),
      n_returned   = sum(returned, na.rm = TRUE),
      pct_returned = round(n_returned / n_students, 3),
      .groups      = "drop"
    ) %>%
    filter(n_students >= min_n) %>%
    arrange(subject_course, outcome) %>%
    mutate(outcome = as.character(outcome))

  message("[course-outcomes.R] Persistence table: ", nrow(result), " outcome groups.")
  result
}
