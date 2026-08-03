# gen-ed-grads.R — Cone: what Gen Ed do a department's graduates actually take?
#
# Answers one question, in two shapes:
#   get_gen_ed_grad_cohort()  — who counts as a graduate we can read completely
#   get_gen_ed_grad_uptake()  — which Gen Ed courses that group took, and how many
#
# THE SAMPLING RULE, AND WHY IT IS STRICT
#
# CEDAR's enrollment history starts at the first term in cedar_students. A
# student already enrolled in that term may have been a freshman or may have
# been a senior; the data cannot tell the difference, and their earlier Gen Ed
# coursework is simply absent. Counting them would understate every Gen Ed rate
# on the page, worst for the courses students take earliest.
#
# Note this is a CENSUS of a restricted group, not a sample of graduates. Every
# graduate meeting the conditions below is counted; none is drawn at random. The
# restriction is what limits generalisation, not sampling error.
#
# So this cone counts only students whose ENTIRE UNM record is visible: their
# first enrollment falls strictly after the first term in the data, that
# enrollment PRECEDES the degree, and the degree is an awarded one from the
# department. The middle condition is not redundant — cedar_degrees reaches
# further back than cedar_students, so a graduate who finished before the window
# and re-enrolled later would otherwise qualify on enrollment that has nothing to
# do with the degree being counted. That is a real restriction,
# not a rounding detail — it drops most graduates in the early years of the data
# window and grows as the window lengthens. Every number this cone returns
# carries `n_cohort` so the caller can say so out loud.
#
# Transfer students are kept. They started at UNM inside the window, so their UNM
# record is complete; their pre-UNM credits are not, which is why the timing
# x-axis this feeds (unm_credit_band) counts UNM credits rather than pretending
# to know a transfer total.


#' Build the Readable-Graduate Cohort for a Department
#'
#' Graduates of `opt$dept_code` whose whole UNM enrollment history is inside the
#' data window — see the sampling rule at the top of this file.
#'
#' @param students Data frame. The `cedar_students` table. Supplies the
#'   enrollment bookends that decide whether a graduate's record is complete.
#' @param degrees Data frame. The `cedar_degrees` table.
#' @param opt List of options:
#'   \describe{
#'     \item{`dept_code`}{Character. Department code (e.g. `"HIST"`). Required.}
#'     \item{`degree_abbr`}{Character vector. Restrict to these degree types
#'       (e.g. `"BA"`). Optional.}
#'     \item{`major_code`}{Character vector. Restrict to these programs within
#'       the department (e.g. `"ASTR"` inside `"PHYS"`). Optional.}
#'     \item{`undergraduate_only`}{Logical, default `TRUE`. Gen Ed is an
#'       undergraduate requirement, so a master's or doctoral graduate has no
#'       Gen Ed obligation and contributes a structural zero to every average.
#'       Measured on History: 16 of the 17 graduate degrees in the cohort had
#'       zero Gen Ed on record, pulling the mean down by roughly a fifth for a
#'       reason that has nothing to do with what undergraduates take.}
#'   }
#'
#' @return Tibble with one row per graduate and columns `student_id`,
#'   `population_label`, `grad_term`, `first_unm_term`. Shaped to be passed
#'   straight to a population-aware cone such as [get_course_timing()].
#'
#'   Carries a `cohort_meta` attribute: `dept_code`, `min_data_term`,
#'   `max_data_term`, `n_awarded` (all awarded graduates in scope),
#'   `n_no_records` (awarded graduates absent from `cedar_students`),
#'   `n_left_truncated` (awarded graduates whose first enrollment is the first
#'   term in the data, so their start is unreadable), `n_post_grad_entry`
#'   (graduates whose only visible enrollment postdates the degree — they
#'   finished before the window and came back later), and `n_cohort`.
get_gen_ed_grad_cohort <- function(students, degrees, opt = list()) {

  dept_code <- opt$dept_code
  if (is.null(dept_code) || length(dept_code) != 1 || !nzchar(dept_code)) {
    stop("[gen-ed-grads.R] opt$dept_code is required and must be a single code.")
  }

  needed_deg <- c("student_id", "term", "dept_code", "graduation_status")
  missing_deg <- setdiff(needed_deg, names(degrees))
  if (length(missing_deg) > 0) {
    stop("[gen-ed-grads.R] degrees is missing required column(s): ",
         paste(missing_deg, collapse = ", "))
  }
  missing_stu <- setdiff(c("student_id", "term"), names(students))
  if (length(missing_stu) > 0) {
    stop("[gen-ed-grads.R] students is missing required column(s): ",
         paste(missing_stu, collapse = ", "))
  }

  # "Awarded" only. Pending/Hold Pending/Record Clear are applications in
  # flight, not completions, and a Gen Ed profile of degrees that may never be
  # conferred is not a profile of graduates.
  grads <- degrees %>%
    dplyr::filter(
      dept_code == .env$dept_code,
      graduation_status == "Awarded"
    )

  if (!is.null(opt$degree_abbr) && length(opt$degree_abbr) > 0) {
    if (!"degree_abbr" %in% names(degrees))
      stop("[gen-ed-grads.R] opt$degree_abbr set but degrees has no degree_abbr column.")
    grads <- dplyr::filter(grads, degree_abbr %in% .env$opt$degree_abbr)
  }
  if (!is.null(opt$major_code) && length(opt$major_code) > 0) {
    if (!"major_code" %in% names(degrees))
      stop("[gen-ed-grads.R] opt$major_code set but degrees has no major_code column.")
    grads <- dplyr::filter(grads, major_code %in% .env$opt$major_code)
  }

  # Gen Ed is an undergraduate requirement. A master's graduate satisfies no Gen
  # Ed and takes none, so leaving them in adds structural zeros to every average.
  n_grad_degrees <- 0L
  if (isTRUE(opt$undergraduate_only %||% TRUE)) {
    if (!"award_category" %in% names(degrees)) {
      stop("[gen-ed-grads.R] undergraduate_only needs an award_category column on ",
           "degrees. Pass undergraduate_only = FALSE to count every award level.")
    }
    # grepl() drops NA, so an unknown award level would vanish without trace.
    # There are none in current data; say so if that ever changes rather than
    # letting graduates disappear from a count that is supposed to be a census.
    n_unknown_award <- sum(is.na(grads$award_category) | !nzchar(grads$award_category))
    if (n_unknown_award > 0) {
      message("[gen-ed-grads.R] ", n_unknown_award, " degree rows have no ",
              "award_category and are excluded by undergraduate_only.")
    }
    before <- dplyr::n_distinct(grads$student_id)
    grads <- dplyr::filter(grads, grepl("Baccalaureate|Associate", award_category))
    n_grad_degrees <- before - dplyr::n_distinct(grads$student_id)
  }

  min_data_term <- suppressWarnings(min(students$term, na.rm = TRUE))
  max_data_term <- suppressWarnings(max(students$term, na.rm = TRUE))

  # A student with two degrees from the unit graduates once, at the later term.
  # Guarded rather than piped straight through: max() over zero rows warns and
  # returns -Inf, and a department with no graduates is an ordinary state here,
  # not a data problem worth a warning.
  grads <- if (nrow(grads) == 0) {
    tibble::tibble(student_id = character(), grad_term = integer())
  } else {
    grads %>%
      dplyr::group_by(student_id) %>%
      dplyr::summarize(grad_term = as.integer(max(term, na.rm = TRUE)),
                       .groups = "drop")
  }

  grad_enrl <- dplyr::filter(students, student_id %in% grads$student_id)
  bookends <- if (nrow(grad_enrl) == 0) {
    tibble::tibble(student_id = character(), first_unm_term = integer())
  } else {
    grad_enrl %>%
      dplyr::group_by(student_id) %>%
      dplyr::summarize(first_unm_term = as.integer(min(term, na.rm = TRUE)),
                       .groups = "drop")
  }

  scoped <- grads %>% dplyr::left_join(bookends, by = "student_id")

  n_awarded      <- nrow(scoped)
  n_no_records   <- sum(is.na(scoped$first_unm_term))
  n_left_trunc   <- sum(!is.na(scoped$first_unm_term) &
                          scoped$first_unm_term <= min_data_term)

  # A degree conferred before the student's first visible enrollment describes a
  # career this data cannot see. cedar_degrees reaches further back than
  # cedar_students does (Fall 2018 vs Fall 2019 on current data), so a student
  # who finished before the enrollment window opened and re-enrolled later —
  # a second degree, a few non-degree courses — clears the first_unm_term test
  # on the strength of that later enrollment while none of it belongs to the
  # degree being counted. Measured on History: 13 of 112 cohort members, 10 of
  # them with no pre-graduation enrollment whatsoever.
  #
  # Requiring the first enrollment to PRECEDE graduation is what "we can see
  # this degree being earned" actually means; first_unm_term > min_data_term
  # alone only establishes that we can see them arrive.
  n_post_grad_entry <- sum(!is.na(scoped$first_unm_term) &
                             scoped$first_unm_term > min_data_term &
                             scoped$first_unm_term >= scoped$grad_term)

  # Standing in the student's FIRST term here. This is what separates a graduate
  # who did the whole degree at UNM from one who arrived with most of it done
  # elsewhere, and the two take entirely different amounts of Gen Ed here — on
  # History, 13.4 courses against 2.5. A single average over both describes
  # nobody.
  entry <- if (nrow(grad_enrl) == 0 || !"student_classification" %in% names(grad_enrl)) {
    tibble::tibble(student_id = character(), entry_standing = character())
  } else {
    grad_enrl %>%
      dplyr::group_by(student_id) %>%
      dplyr::slice_min(term, n = 1, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::transmute(student_id, entry_standing = dplyr::case_when(
        grepl("^Freshman",           student_classification) ~ "freshman",
        grepl("^Sophomore",          student_classification) ~ "sophomore",
        grepl("^Junior|^Senior",     student_classification) ~ "junior_senior",
        TRUE                                                 ~ "other"
      ))
  }

  cohort <- scoped %>%
    dplyr::filter(!is.na(first_unm_term), first_unm_term > min_data_term,
                  first_unm_term < grad_term) %>%
    dplyr::left_join(entry, by = "student_id") %>%
    dplyr::transmute(
      student_id,
      population_label = paste(dept_code, "graduates"),
      grad_term        = as.integer(grad_term),
      first_unm_term,
      entry_standing   = dplyr::coalesce(entry_standing, "other")
    ) %>%
    dplyr::arrange(student_id)

  cedar_debug("[gen-ed-grads.R] ", dept_code, " awarded=", n_awarded,
              " no_records=", n_no_records, " left_truncated=", n_left_trunc,
              " degree_precedes_enrollment=", n_post_grad_entry,
              " cohort=", nrow(cohort))

  attr(cohort, "cohort_meta") <- list(
    dept_code        = dept_code,
    degree_abbr      = opt$degree_abbr %||% NULL,
    major_code       = opt$major_code %||% NULL,
    min_data_term    = as.integer(min_data_term),
    max_data_term    = as.integer(max_data_term),
    n_awarded        = as.integer(n_awarded),
    n_no_records     = as.integer(n_no_records),
    n_left_truncated = as.integer(n_left_trunc),
    n_post_grad_entry = as.integer(n_post_grad_entry),
    n_graduate_degrees = as.integer(n_grad_degrees),
    n_cohort         = nrow(cohort)
  )
  cohort
}


#' Gen Ed Uptake Among a Graduate Cohort
#'
#' For a cohort from [get_gen_ed_grad_cohort()], what share took each Gen Ed
#' course and how many Gen Ed courses a graduate takes.
#'
#' A course is counted once per student no matter how many times they sat it, so
#' `pct_cohort` reads as "this share of graduates took this course at least
#' once" and the per-student count is distinct courses, not attempts. Retakes and
#' withdrawals are included: the question is what graduates take, and a course
#' that a third of graduates have to attempt twice is part of that answer. Only
#' enrollments up to and including each student's graduation term count — post-
#' degree coursework is not part of the degree these numbers describe.
#'
#' @param students Data frame. The `cedar_students` table.
#' @param cohort Data frame. Output of [get_gen_ed_grad_cohort()]; needs
#'   `student_id` and `grad_term`.
#' @param gen_ed_lu Data frame. Gen Ed course lookup with `subject_course`,
#'   `area`, `area_label` — from `gen_ed_course_lookup()`.
#' @param opt List of options:
#'   \describe{
#'     \item{`campus`}{Character vector of course-delivery campus codes. NULL
#'       includes every campus; pass NULL only for a deliberate UNM-wide
#'       aggregate.}
#'     \item{`dept_code`}{Character. When set, `by_course` gains an
#'       `is_dept_course` flag marking Gen Ed taught by the graduates' own unit.}
#'     \item{`min_n`}{Integer. Courses taken by fewer than this many cohort
#'       students are dropped from `by_course`. Default `1` (keep everything) —
#'       small-cell suppression is the caller's policy, not this cone's.}
#'   }
#'
#' @return Named list:
#'   \describe{
#'     \item{`by_course`}{One row per Gen Ed course: `subject_course`,
#'       `course_title`, `department`, `area`, `area_label`, `is_dept_course`,
#'       `n_students`, `pct_cohort`.}
#'     \item{`per_student`}{One row per cohort member who took any Gen Ed:
#'       `student_id`, `n_courses`, `n_areas`, `n_dept_courses`.}
#'     \item{`summary`}{Single-row tibble: `n_cohort`, `n_with_any`,
#'       `mean_courses`, `median_courses`, `mean_areas`. The two means divide by
#'       `n_cohort`, not `n_with_any`, so a graduate with no recorded Gen Ed
#'       counts as a zero rather than vanishing from the average.}
#'     \item{`summary_dept`}{The same shape, restricted to Gen Ed taught by the
#'       graduates' own unit, plus `dept_share_pct` — the share of all Gen Ed
#'       course-takings by this cohort that the unit taught itself. NULL when
#'       `opt$dept_code` is not set, because there is no own unit to restrict to.}
#'   }
get_gen_ed_grad_uptake <- function(students, cohort, gen_ed_lu, opt = list()) {

  missing_cohort <- setdiff(c("student_id", "grad_term"), names(cohort))
  if (length(missing_cohort) > 0) {
    stop("[gen-ed-grads.R] cohort is missing required column(s): ",
         paste(missing_cohort, collapse = ", "),
         ". Use get_gen_ed_grad_cohort().")
  }
  if (!all(c("subject_course", "area", "area_label") %in% names(gen_ed_lu))) {
    stop("[gen-ed-grads.R] gen_ed_lu must have subject_course, area, area_label. ",
         "Use gen_ed_course_lookup().")
  }
  cedar_require_campus(students, "gen-ed-grads.R get_gen_ed_grad_uptake")

  min_n     <- opt$min_n %||% 1L
  dept_code <- opt$dept_code %||% NULL
  n_cohort  <- dplyr::n_distinct(cohort$student_id)

  empty_result <- function() {
    list(
      by_course = tibble::tibble(
        subject_course = character(), course_title = character(),
        department = character(), area = integer(), area_label = character(),
        is_dept_course = logical(), n_students = integer(), pct_cohort = numeric()
      ),
      per_student = tibble::tibble(
        student_id = character(), n_courses = integer(), n_areas = integer(),
        n_dept_courses = integer()
      ),
      by_entry = tibble::tibble(
        entry_standing = character(), n_graduates = integer(),
        mean_dept_courses = numeric(), mean_other_courses = numeric(),
        mean_courses = numeric(), median_courses = numeric()
      ),
      summary = tibble::tibble(
        n_cohort = as.integer(n_cohort), n_with_any = 0L,
        mean_courses = NA_real_, median_courses = NA_real_, mean_areas = NA_real_
      ),
      summary_dept = if (is.null(dept_code)) NULL else tibble::tibble(
        n_cohort = as.integer(n_cohort), n_with_any = 0L,
        mean_courses = NA_real_, median_courses = NA_real_,
        dept_share_pct = NA_real_
      )
    )
  }

  if (n_cohort == 0) return(empty_result())

  taken <- students %>%
    dplyr::filter(registration_status_code %in% STATUS_REGISTERED) %>%
    cedar_filter_campus(opt$campus, fn = "gen-ed-grads.R") %>%
    dplyr::inner_join(dplyr::distinct(cohort, student_id, grad_term),
                      by = "student_id") %>%
    dplyr::filter(term <= grad_term) %>%
    dplyr::inner_join(dplyr::select(gen_ed_lu, subject_course, area, area_label),
                      by = "subject_course") %>%
    # Course identity is (student, course); campus and term are collapsed here on
    # purpose. "Did this graduate take ENGL 1120" is one fact whether they took it
    # in Albuquerque, online, or twice.
    dplyr::distinct(student_id, subject_course, course_title, department,
                    area, area_label)

  if (nrow(taken) == 0) return(empty_result())

  by_course <- taken %>%
    dplyr::group_by(subject_course, area, area_label) %>%
    dplyr::summarize(
      # A course can carry more than one recorded title or owning department
      # across terms; report the most common of each rather than an arbitrary one.
      course_title = names(sort(table(course_title), decreasing = TRUE))[1],
      department   = names(sort(table(department), decreasing = TRUE))[1],
      n_students   = dplyr::n_distinct(student_id),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      is_dept_course = if (is.null(dept_code)) NA else department == dept_code,
      pct_cohort     = round(100 * n_students / n_cohort, 1)
    ) %>%
    dplyr::filter(n_students >= min_n) %>%
    dplyr::select(subject_course, course_title, department, area, area_label,
                  is_dept_course, n_students, pct_cohort) %>%
    dplyr::arrange(dplyr::desc(n_students), subject_course)

  # Own-unit membership is decided by the same `department` value that by_course
  # reports as "Taught By". Deriving it from cedar_sections instead would be
  # defensible on its own, but then a course could read "Taught By: ENGL" in the
  # table while appearing in the History-only view, and neither number would be
  # wrong — the page would just contradict itself.
  per_student <- taken %>%
    # Branch rather than `!is.null(dept_code) & department == dept_code`: with a
    # NULL dept_code the comparison is zero-length, not FALSE, and mutate() fails
    # on the recycling rather than falling through.
    dplyr::mutate(is_dept_course = if (is.null(dept_code)) FALSE
                                   else department == dept_code) %>%
    dplyr::group_by(student_id) %>%
    dplyr::summarize(
      n_courses      = dplyr::n_distinct(subject_course),
      n_areas        = dplyr::n_distinct(area),
      n_dept_courses = dplyr::n_distinct(subject_course[is_dept_course]),
      .groups = "drop"
    )

  # Zero-filled to n_cohort: graduates with no Gen Ed on record are part of the
  # denominator. Dropping them would report the average among Gen Ed takers and
  # label it the average among graduates. The own-unit vector is zero-filled the
  # same way and to the same length, so the two averages stay comparable — a
  # graduate who took Gen Ed but none of it from their own unit is a zero in the
  # own-unit average, not an absence.
  pad <- function(x) c(x, rep(0L, n_cohort - nrow(per_student)))
  courses_all <- pad(per_student$n_courses)
  areas_all   <- pad(per_student$n_areas)
  courses_own <- pad(per_student$n_dept_courses)

  summary_dept <- if (is.null(dept_code)) NULL else tibble::tibble(
    n_cohort       = as.integer(n_cohort),
    n_with_any     = sum(courses_own > 0),
    mean_courses   = round(mean(courses_own), 2),
    median_courses = stats::median(courses_own),
    # Share of this cohort's Gen Ed course-takings that the unit taught itself.
    # Computed from the totals rather than as a ratio of the two means so it does
    # not inherit their rounding.
    dept_share_pct = if (sum(courses_all) > 0) {
      round(100 * sum(courses_own) / sum(courses_all), 1)
    } else NA_real_
  )

  cedar_debug("[gen-ed-grads.R] uptake: cohort=", n_cohort,
              " with_any=", nrow(per_student),
              " courses=", nrow(by_course),
              " own_unit_courses=", sum(by_course$is_dept_course, na.rm = TRUE))

  # Averages split by how the graduate arrived. This is the breakdown that makes
  # a low headline legible: a department whose graduates are mostly transfers
  # will show a small overall mean not because its majors skip Gen Ed but
  # because they did it somewhere CEDAR cannot see.
  by_entry <- if (!"entry_standing" %in% names(cohort)) NULL else {
    cohort %>%
      dplyr::distinct(student_id, entry_standing) %>%
      dplyr::left_join(per_student, by = "student_id") %>%
      dplyr::mutate(dplyr::across(c(n_courses, n_areas, n_dept_courses),
                                  ~dplyr::coalesce(.x, 0L))) %>%
      dplyr::group_by(entry_standing) %>%
      dplyr::summarize(
        n_graduates    = dplyr::n(),
        # Own-unit and everything-else are reported separately rather than as a
        # total the reader has to subtract from. A department asking whether its
        # majors take its own Gen Ed courses is asking about the first column;
        # the second is what they took everywhere else.
        mean_dept_courses  = round(mean(n_dept_courses), 2),
        mean_other_courses = round(mean(n_courses - n_dept_courses), 2),
        mean_courses   = round(mean(n_courses), 2),
        median_courses = stats::median(n_courses),
        .groups = "drop"
      ) %>%
      dplyr::arrange(match(entry_standing,
                           c("freshman", "sophomore", "junior_senior", "other")))
  }

  list(
    by_course   = by_course,
    per_student = per_student,
    by_entry    = by_entry,
    summary = tibble::tibble(
      n_cohort       = as.integer(n_cohort),
      n_with_any     = nrow(per_student),
      mean_courses   = round(mean(courses_all), 2),
      median_courses = stats::median(courses_all),
      mean_areas     = round(mean(areas_all), 2)
    ),
    summary_dept = summary_dept
  )
}
