# What the tests in test-gen-ed-grads.R share: builders, option lists, constants.

gg_opt <- function(...) utils::modifyList(list(dept_code = "LING"), list(...))

gg_uptake <- function(...) {
  cohort <- get_gen_ed_grad_cohort(cedar_registrations_gg, cedar_degrees_gg, cedar_student_terms_gg, gg_opt())
  get_gen_ed_grad_uptake(cedar_registrations_gg, cohort, gen_ed_course_lookup(),
                         opt = utils::modifyList(
                           list(campus = "ABQ", dept_code = "LING", min_n = 1L),
                           list(...)))
}

gg_population <- function() {
  get_gen_ed_grad_cohort(cedar_registrations_gg, cedar_degrees_gg, cedar_student_terms_gg, gg_opt()) %>%
    dplyr::select(student_id, population_label)
}

# GG_IN1 and GG_IN2 both take a GG-taught gen ed course; GG_IN3 still takes none.
# Uses HIST 1160's slot in area 5 via a GG-owned section of a real catalog course
# so gen_ed_course_lookup() still matches it.
gg_students_own <- function() {
  dplyr::bind_rows(
    cedar_registrations_gg,
    .gg_row("GG_IN1", 202110, "PHIL 1115", "LING"),
    .gg_row("GG_IN2", 202110, "PHIL 1115", "LING")
  )
}

gg_credits_own <- function() {
  dplyr::bind_rows(
    cedar_student_terms_gg,
    tibble::tibble(student_id = "GG_IN2", term = 202110L,
                   completed_unm_credits = 3,
                   cumulative_completed_unm_credits = 3,
                   timeline_valid = TRUE,
                   student_classification = "Freshman", enrolled = TRUE)
  )
}

gg_profile_own <- function(min_n = 1L) {
  suppressMessages(get_gen_ed_grad_profile(
    gg_students_own(), cedar_degrees_gg, gg_credits_own(),
    opt = list(dept_code = "LING", campus = "ABQ", min_n = min_n, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))
}
