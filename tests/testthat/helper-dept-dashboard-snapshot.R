# What the tests in test-dept-dashboard-snapshot.R share: builders, option lists, constants.

# The dashboard's exact course_history build (create_dept_dashboard_data).
build_dashboard_course_history <- function(dept) {
  ch_opt <- list(dept_code = dept, status = "A", crosslist = "home", uel = TRUE,
                 group_cols = c("subject_course", "course_title", "campus", "term"))
  get_enrl(test_sections, ch_opt) %>% dplyr::filter(enrolled > 0)
}
