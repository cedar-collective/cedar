# What the tests in test-projection-refresh.R share: builders, option lists, constants.

projection_request_runner <- function() {
  env <- new.env(parent = globalenv())
  sys.source("../../scripts/build-enrollment-projections.R", envir = env)
  env$run_projection_rebuild_request
}

write_projection_request <- function(path) {
  yaml::write_yaml(list(
    target_term = 202710L, as_of_term = 202680L, group = "critical_courses"
  ), path)
}
