#' Curriculum Bottleneck Analysis: Enrollment Demand
#'
#' @description
#' Identifies enrollment demand bottlenecks — courses where students in a
#' defined cohort are being shut out. A bottleneck here means a course where
#' students want seats they can't get, measured by CEDAR's class-list true
#' waitlist demand (`R/branches/waitlist-demand.R`): students waitlisted for a
#' course in a term who hold no registered seat in it that term.
#'
#' This cone focuses on access, not grade outcomes. For DFW analysis of a
#' cohort, use `get_course_outcome_rates()` with `opt$cohort_ids`. For stop-out
#' analysis after course failure, use `get_stopout()` from `stopout.R`.
#'
#' @section Cohort Input:
#' This cone does not build its own cohort. Pass a pre-built cohort from
#' `build_population()`. This keeps cohort definition and analysis separate —
#' the same cohort can be reused across multiple cones.
#'
#' If `opt$population_label` is provided and the cohort contains multiple labels
#' (e.g., from `include_pre_majors = "split"`), analysis runs separately for
#' each label. Otherwise, all students in the cohort are analyzed as one group.
#'
#' @section RStudio Exploration:
#'
#' ```r
#' library(qs2); library(dplyr)
#'
#' cedar_programs <- qs_read("data/cedar_programs.qs")
#' cedar_registrations <- qs_read("data/cedar_registrations.qs")
#'
#' # Build a health track cohort, then find enrollment bottlenecks
#' cohort <- build_population(cedar_programs, opt = list(type = "health"))
#' result <- get_bottlenecks(cohort, cedar_registrations, opt = list())
#' result$waitlist
#'
#' # Restrict to a single term
#' result <- get_bottlenecks(cohort, cedar_registrations, opt = list(term = 202510))
#'
#' # Analyze pre-major and declared major cohorts separately
#' cohort_split <- build_population(cedar_programs,
#'                              opt = list(type = "health",
#'                                         include_pre_majors = "split"))
#' result_split <- get_bottlenecks(cohort_split, cedar_registrations, opt = list())
#' result_split$by_label
#' ```
#'
#' @name bottleneck


#' Get Enrollment Demand Bottlenecks for a Cohort
#'
#' For each course and term, counts cohort students who are waitlisted but hold
#' no registered seat that term — the clearest signal of unmet demand. Results
#' are returned per campus, term and course, sorted by waitlist count. Terms
#' are never pooled: a seat won a term later does not erase the term spent
#' waiting, and a student waiting in two terms is waiting in each.
#'
#' If the cohort contains multiple labels (from `build_population()` with
#' `include_pre_majors = "split"`), a `$by_label` table is also returned
#' showing results broken out by cohort label.
#'
#' @param cohort Data frame. Output of `build_population()`. Must have columns
#'   `student_id` and `population_label`.
#' @param students Data frame. The `cedar_registrations` table.
#' @param sections Optional `cedar_sections`, used only when the class list
#'   has rows without a course title (the title is part of the waitlist grain).
#' @param opt List of options:
#'   \describe{
#'     \item{`term`}{Integer or character vector of term codes to restrict to.
#'       Optional; defaults to all terms.}
#'     \item{`campus`}{Character vector of campus codes. Optional.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{`waitlist`}{Data frame of enrollment bottlenecks, sorted
#'       descending by `n_waitlisted`. Columns: `campus`, `term`,
#'       `subject_course`, `n_waitlisted`.}
#'     \item{`population_size`}{Named integer vector: number of unique student
#'       IDs per cohort label.}
#'     \item{`by_label`}{Data frame breaking down waitlist counts by
#'       `population_label`. Only present when the cohort has more than one
#'       distinct label.}
#'   }
#'
#' @examples
#' \dontrun{
#' cedar_programs <- qs_read("data/cedar_programs.qs")
#' cedar_registrations <- qs_read("data/cedar_registrations.qs")
#'
#' cohort <- build_population(cedar_programs, opt = list(type = "health"))
#' result <- get_bottlenecks(cohort, cedar_registrations, opt = list())
#' result$waitlist
#' result$population_size
#' }
#'
#' @seealso [build_population()] to construct the cohort input,
#'   [compute_waitlist_pressure()] for the underlying calculation
#' @export
get_bottlenecks <- function(population, students, sections = NULL, opt = list()) {

  message("[bottleneck.R] Starting enrollment demand analysis...")

  validate_population(population, "get_bottlenecks")
  if (!is.null(sections) && !is.data.frame(sections)) {
    stop("[get_bottlenecks] `sections` must be cedar_sections or NULL; ",
         "pass options by name: get_bottlenecks(population, students, opt = list(...))",
         call. = FALSE)
  }

  # Apply term / campus filters to students
  filtered_students <- students
  if (!is.null(opt$term) && length(opt$term) > 0) {
    filtered_students <- filtered_students %>% filter(term %in% opt$term)
  }
  if (!is.null(opt$campus) && length(opt$campus) > 0) {
    filtered_students <- filtered_students %>% filter(campus %in% opt$campus)
  }

  all_ids    <- unique(population$student_id)
  label_counts <- population %>%
    group_by(population_label) %>%
    summarize(n = n_distinct(student_id), .groups = "drop")

  message("[bottleneck.R] Cohort: ",
          paste(label_counts$population_label, label_counts$n, sep = " = ",
                collapse = ", "))

  result <- list()
  result$population_size <- setNames(label_counts$n, label_counts$population_label)

  # Overall waitlist pressure across all cohort members
  message("[bottleneck.R] Computing waitlist pressure...")
  result$waitlist <- compute_waitlist_pressure(filtered_students, all_ids, sections)

  # If multiple labels, also break out by label
  labels <- unique(population$population_label)
  if (length(labels) > 1) {
    message("[bottleneck.R] Multiple cohort labels found — computing by-label breakdown...")
    by_label <- purrr::map_dfr(labels, function(lbl) {
      ids <- population$student_id[population$population_label == lbl]
      compute_waitlist_pressure(filtered_students, ids, sections) %>%
        mutate(population_label = lbl)
    })
    result$by_label <- by_label %>%
      select(population_label, campus, term, subject_course, n_waitlisted) %>%
      arrange(population_label, desc(n_waitlisted))
  }

  message("[bottleneck.R] Done.")
  return(result)
}


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

#' Compute Waitlist Pressure for a Student Cohort
#'
#' CEDAR's class-list true waitlist demand, restricted to a cohort: students
#' waitlisted for a course in a term who hold no registered seat for the same
#' course title, term, delivery campus, college and part of term
#' (`get_true_waitlisted_rows()`), counted once per campus, term and course.
#' A student who is both waitlisted and registered that term (hedging across
#' sections) is not waiting.
#'
#' @param students Data frame. The `cedar_registrations` table, optionally
#'   pre-filtered by term/campus.
#' @param population_ids Character vector of student IDs to include.
#' @param sections Optional `cedar_sections`, for course titles the class list
#'   lacks.
#'
#' @return Data frame sorted descending by `n_waitlisted`:
#'   \describe{
#'     \item{`campus`}{Course-delivery campus code.}
#'     \item{`term`}{Term code the students were waiting in.}
#'     \item{`subject_course`}{Course identifier, e.g., `"BIOL 2310"`.}
#'     \item{`n_waitlisted`}{Unique cohort students waitlisted and not
#'       registered for this course that term.}
#'   }
#'
#' @keywords internal
compute_waitlist_pressure <- function(students, population_ids, sections = NULL) {
  cedar_require_campus(students, "compute_waitlist_pressure")

  students %>%
    filter(student_id %in% population_ids) %>%
    get_true_waitlisted_rows(sections) %>%
    summarize_waitlist_demand(c("campus", "term", "subject_course"),
                              count_name = "n_waitlisted") %>%
    arrange(desc(n_waitlisted), campus, term, subject_course)
}
