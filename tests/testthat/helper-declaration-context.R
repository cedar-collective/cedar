# What the tests in test-declaration-context.R share: builders, option lists, constants.

decl_hist_ids <- function() unique(test_programs$student_id[test_programs$dept_code == "HIST"])

decl_hist_population <- function() {
  tibble::tibble(
    student_id       = decl_hist_ids(),
    population_label = "HIST",
    first_unm_term   = 202010L
  )
}

decl_context <- function(population = decl_hist_population(), opt = list(min_n = 1L),
                         student_terms = NULL, focal_subjects = "HIST") {
  suppressMessages(get_declaration_context(
    programs       = test_programs,
    students       = test_students,
    population     = population,
    focal_subjects = focal_subjects,
    opt            = opt,
    student_terms  = student_terms
  ))
}
