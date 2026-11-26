# exit-requirements.R — Which required courses had the students who left passed here?
#
# One question: for a set of students who left without a degree, and for each
# course their program's degree plan names as required, how many passed it
# here, how many tried it here and never passed, and how many have no attempt
# on record?
#
#   Program       the student's Banner program on their last term's
#                 declaration (`BA-HIST-AS`), matched to a degree plan through
#                 the plan's own program codes. A pre-major code belongs to the
#                 plan it leads to. A student with two majors that term is
#                 counted under each plan.
#   Course        each course a plan names is counted by itself: a lecture
#                 and lab required together are two rows, so a student who
#                 passed one and never took the other is not read as failing.
#   Passed here   a passing attempt (cedar_attempts' `outcome`, the default
#                 pass policy), on any campus, at or before the last term.
#   Tried here    a graded attempt or late withdrawal, and never a pass.
#   No attempt    nothing graded here. NOT "still required": most students who
#                 leave far along brought credit from elsewhere, and a record
#                 that began before the data did is not seen whole, so the
#                 course may have been met by transfer, test credit or an
#                 earlier term. Only "tried here" says a student met the
#                 course and did not get through it.
#   Not readable  a course no one had a grade in by the latest last term
#                 among these students (a number the catalog introduced after
#                 they left, with no confirmed rename in code_history.csv):
#                 its counts are NA, never zero.
#   Not an audit  the plan is the current catalog's, not the one a student
#                 entered under; choices, elective space, Gen Ed, grade
#                 minimums and substitutions are not read. This counts
#                 students by course; it says nothing about one student.
#
# Depends on: course_id_of() (branches/courses.R)

#' Students who left, by what they did in each course their plan requires
#'
#' @param students One row per student who left: `student_id`, `exit_term`
#'   (`get_exit_credits()$students`, narrowed by the caller).
#' @param programs `cedar_programs`: `student_id`, `term`, `program_code`.
#' @param attempts `cedar_attempts`.
#' @param requirements One row per plan and required course: `catalog_id`,
#'   `title`, `semester`, `subject_course` (the catalog's code);
#'   `degree_named_requirements()$courses`.
#' @param program_catalogs One row per plan and Banner program code:
#'   `catalog_id`, `program_code`, `is_pre_major`.
#' @param opt `min_n` (fewest students for a plan to be shown; default 10).
#' @return list(`programs` one row per plan with a student: `catalog_id`,
#'   `n_students`, `n_pre_major`, `shown`; `courses` one row per shown plan
#'   and course, in plan order: `catalog_id`, `subject_course`, `title`,
#'   `semester`, `readable`, `n_students`, `n_passed`, `n_tried`, `n_none`
#'   (the three NA where not readable); `meta`).
get_exit_requirement_progress <- function(students, programs, attempts, requirements, program_catalogs,
                                          opt = list()) {
  need <- list(
    students = c("student_id", "exit_term"),
    programs = c("student_id", "term", "program_code"),
    attempts = c("student_id", "term", "subject_course", "listed_code", "outcome"),
    requirements = c("catalog_id", "title", "semester", "subject_course"),
    program_catalogs = c("catalog_id", "program_code", "is_pre_major")
  )
  have <- list(students = students, programs = programs, attempts = attempts, requirements = requirements,
               program_catalogs = program_catalogs)
  for (name in names(need)) {
    missing <- setdiff(need[[name]], names(have[[name]]))
    if (length(missing) > 0L) {
      stop("[exit-requirements.R] ", name, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
    }
  }
  if (anyDuplicated(students$student_id)) {
    stop("[exit-requirements.R] students must hold one row per student.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)

  # Each student's plans: the programs declared in their last term.
  declared <- programs %>%
    filter(!is.na(program_code)) %>%
    transmute(student_id, exit_term = as.integer(term), program_code) %>%
    inner_join(students %>% transmute(student_id, exit_term = as.integer(exit_term)),
               by = c("student_id", "exit_term")) %>%
    inner_join(program_catalogs %>% select(catalog_id, program_code, is_pre_major),
               by = "program_code", relationship = "many-to-many") %>%
    group_by(student_id, exit_term, catalog_id) %>%
    summarize(is_pre_major = all(is_pre_major), .groups = "drop")
  program_rows <- declared %>%
    group_by(catalog_id) %>%
    summarize(n_students = n(), n_pre_major = sum(is_pre_major), .groups = "drop") %>%
    mutate(shown = n_students >= min_n) %>%
    arrange(desc(n_students), catalog_id)
  shown_ids <- program_rows$catalog_id[program_rows$shown]

  # The catalog's code, as the course the loaded tables key on.
  # CAMPUS_ROLLUP: a plan requires the course, not one campus's offering of
  # it; the codes and the plan's course list carry no campus.
  known <- distinct(tibble::tibble(course_id = attempts$subject_course, listed_code = attempts$listed_code))
  required <- requirements %>%
    filter(catalog_id %in% shown_ids) %>%
    group_by(catalog_id, subject_course) %>%
    arrange(semester) %>%
    summarize(title = first(title), semester = first(semester), .groups = "drop")
  required$course_id <- vapply(required$subject_course, course_id_of, character(1), tbl = known,
                               caller = "get_exit_requirement_progress")
  # A course can be read if it was graded by the last term anyone left in.
  # With no student there is no such term, and nothing can be read (max() of
  # nothing warns and gives -Inf; ISSUES M64).
  exit_terms <- as.integer(students$exit_term)
  graded_by_last_exit <- if (length(exit_terms) == 0L) {
    character(0)
  } else {
    attempts$subject_course[attempts$outcome %in% c("pass", "dfw") &
                              as.integer(attempts$term) <= max(exit_terms)]
  }
  required$readable <- required$course_id %in% graded_by_last_exit

  # CAMPUS_ROLLUP: a student passed the course wherever it was taught; the
  # requirement is the course, not a campus's offering of it.
  graded <- attempts %>%
    filter(outcome %in% c("pass", "dfw"), subject_course %in% required$course_id) %>%
    inner_join(declared %>% distinct(student_id, exit_term), by = "student_id") %>%
    filter(as.integer(term) <= exit_term) %>%
    group_by(student_id, course_id = subject_course) %>%
    summarize(passed = any(outcome == "pass"), .groups = "drop")

  per_student <- declared %>%
    filter(catalog_id %in% shown_ids) %>%
    select(student_id, catalog_id) %>%
    inner_join(required %>% select(catalog_id, course_id), by = "catalog_id",
               relationship = "many-to-many") %>%
    left_join(graded, by = c("student_id", "course_id"), relationship = "many-to-one")
  counts <- per_student %>%
    group_by(catalog_id, course_id) %>%
    summarize(n_students = n(), n_passed = sum(passed %in% TRUE), n_tried = sum(passed %in% FALSE),
              n_none = sum(is.na(passed)), .groups = "drop")
  cedar_debug("[exit-requirements.R] ", nrow(declared), " student-plans in ", nrow(program_rows),
              " plans; ", length(shown_ids), " shown")

  courses <- required %>%
    left_join(counts, by = c("catalog_id", "course_id"), relationship = "many-to-one") %>%
    mutate(across(c(n_passed, n_tried, n_none), ~ if_else(readable, .x, NA_integer_))) %>%
    arrange(match(catalog_id, shown_ids), semester, subject_course) %>%
    select(catalog_id, subject_course, title, semester, readable, n_students, n_passed, n_tried, n_none)

  list(
    programs = program_rows, courses = courses,
    meta = list(n_students = nrow(students),
                n_with_plan = dplyr::n_distinct(declared$student_id),
                n_without_plan = nrow(students) - dplyr::n_distinct(declared$student_id),
                n_plans_withheld = sum(!program_rows$shown),
                n_students_withheld = sum(program_rows$n_students[!program_rows$shown]),
                min_n = min_n)
  )
}
