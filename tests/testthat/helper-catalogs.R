# What the tests in test-catalogs.R do: skip without the catalogs, write a
# mapping or config directory to a temporary folder, resolve a UNM program's unit.

skip_if_no_catalogs <- function() {
  if (!exists("subj_dept_map") || !exists("cedar_institution_files")) {
    skip("subj_dept_map / cedar_institution_files not loaded — run load_funcs() first")
  }
}

skip_if_no_lookups <- function() {
  if (!exists("major_to_dept") || !exists("subj_to_dept")) {
    skip("catalog_lookups.R vectors not available")
  }
}

write_mapping_dir <- function(colleges, units, subjects, programs = mapping_program_row[0, ],
                              settings = unm_settings, code_history = mapping_history_row[0, ]) {
  dir <- tempfile("institution-")
  dir.create(dir)
  utils::write.csv(colleges, file.path(dir, "colleges.csv"), row.names = FALSE)
  utils::write.csv(units, file.path(dir, "units.csv"), row.names = FALSE)
  utils::write.csv(subjects, file.path(dir, "subjects.csv"), row.names = FALSE)
  utils::write.csv(programs, file.path(dir, "programs.csv"), row.names = FALSE)
  utils::write.csv(settings, file.path(dir, "settings.csv"), row.names = FALSE)
  utils::write.csv(code_history, file.path(dir, "code_history.csv"), row.names = FALSE)
  dir
}

unit_of <- function(code, college = rep("", length(code))) {
  resolve_program_units(code, college, unm_programs)
}

write_config_dir <- function(campuses, course_levels, student_levels = NULL) {
  dir <- tempfile("institution-config-")
  dir.create(dir)
  if (!"source_names" %in% names(campuses)) campuses$source_names <- ""
  utils::write.csv(campuses, file.path(dir, "campuses.csv"), row.names = FALSE)
  utils::write.csv(course_levels, file.path(dir, "course_levels.csv"), row.names = FALSE)
  if (!is.null(student_levels)) {
    utils::write.csv(student_levels, file.path(dir, "student_levels.csv"), row.names = FALSE)
  }
  dir
}
