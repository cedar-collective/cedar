# What the tests in test-declaration-context.R share: builders, option lists, constants.

decl_context <- function(population = decl_hist_population, opt = list(min_n = 1L),
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
