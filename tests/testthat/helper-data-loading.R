# What the tests in test-data-loading.R share: builders, option lists, constants.

with_temp_cedar_data_dir <- function(code) {
  old_data_dir <- cedar_data_dir
  old_use_qs <- if (exists("cedar_use_qs", inherits = TRUE)) cedar_use_qs else NULL
  old_use_small <- if (exists("cedar_use_small_data", inherits = TRUE)) cedar_use_small_data else NULL
  global_names <- c(
    "sections", "courses", "students", "cedar_student_terms", "programs", "degrees", "faculty", "fac_by_term",
    "applicants", "data_objects"
  )
  old_globals <- stats::setNames(vector("list", length(global_names)), global_names)
  old_global_exists <- stats::setNames(logical(length(global_names)), global_names)
  for (name in global_names) {
    old_global_exists[[name]] <- exists(name, envir = .GlobalEnv, inherits = FALSE)
    if (old_global_exists[[name]]) old_globals[[name]] <- get(name, envir = .GlobalEnv)
  }

  cedar_data_dir <<- tempfile("cedar-data-")
  dir.create(cedar_data_dir)
  cedar_use_qs <<- FALSE
  cedar_use_small_data <<- FALSE

  on.exit({
    cedar_data_dir <<- old_data_dir
    if (is.null(old_use_qs)) {
      if (exists("cedar_use_qs", inherits = TRUE)) rm(cedar_use_qs, envir = .GlobalEnv)
    } else {
      cedar_use_qs <<- old_use_qs
    }
    if (is.null(old_use_small)) {
      if (exists("cedar_use_small_data", inherits = TRUE)) rm(cedar_use_small_data, envir = .GlobalEnv)
    } else {
      cedar_use_small_data <<- old_use_small
    }
    for (name in global_names) {
      if (old_global_exists[[name]]) {
        assign(name, old_globals[[name]], envir = .GlobalEnv)
      } else if (exists(name, envir = .GlobalEnv, inherits = FALSE)) {
        rm(list = name, envir = .GlobalEnv)
      }
    }
  }, add = TRUE)

  force(code)
}
