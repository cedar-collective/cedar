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

# Set a file's date back and see that it stays back. A heartbeat loop whose
# holder has just gone may still have one beat on its way, which brings the
# date forward again: set it, wait, look, and repeat until it has stayed. TRUE
# when it did. A test that waited a fixed time instead failed on a busy
# machine (ISSUES M74).
set_file_time_back <- function(path, to, tries = 20L, wait = 2.5) {
  for (i in seq_len(tries)) {
    Sys.setFileTime(path, to)
    Sys.sleep(wait)
    if (abs(as.numeric(difftime(file.mtime(path), to, units = "secs"))) < 2) return(TRUE)
  }
  FALSE
}
