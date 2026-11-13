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

gg_profile_own <- function(min_n = 1L) {
  suppressMessages(get_gen_ed_grad_profile(
    gg_students_own, cedar_degrees_gg, gg_credits_own,
    opt = list(dept_code = "LING", campus = "ABQ", min_n = min_n, min_band_n = 1L,
               x_axis = "unm_credit_band")
  ))
}
