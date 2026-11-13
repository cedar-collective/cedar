# What the tests in test-catalogs.R share: builders, option lists, constants.

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

# Scaffolding: one programs.csv row per argument value, defaults filled in.
program_rows <- function(program_code, unit_code = "HIST", in_college = "",
                         college_code = "", is_pre_major = "FALSE", leads_to = "",
                         basis = "decided", status = "confirmed") {
  data.frame(program_code, in_college, program_name = program_code, unit_code,
             college_code, is_pre_major, leads_to, basis, status, evidence = "", notes = "")
}

unm_settings <- data.frame(
  setting = c("mapping_files_url", "source_files_url", "projection_history_start_term"),
  value   = c("https://github.com/org/repo/blob/main/institution/x",
              "https://github.com/org/repo/blob/main", "202210"))

# Scaffolding: subjects.csv rows, defaults filled in.
subject_rows <- function(subject_code, unit_code = "HIST", in_college = "AS", in_level = "",
                         college_code = "", status = "confirmed") {
  data.frame(subject_code, in_college, in_level, unit_code, college_code, status,
             evidence = "", notes = "")
}

write_mapping_dir <- function(colleges, units, subjects, programs = program_rows("X")[0, ],
                              settings = unm_settings, code_history = history_rows("X", "Y")[0, ]) {
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

# Scaffolding: code_history.csv rows, defaults filled in.
history_rows <- function(from_code, to_code, kind = "course", effective_term = "202080",
                         scope = "", basis = "catalog", status = "confirmed") {
  data.frame(kind, from_code, to_code, effective_term, scope, basis, status,
             evidence = "", notes = "")
}

one_unit <- list(
  colleges = data.frame(college_code = c("AS", "AD"), college_name = c("Arts and Sciences", "Branch"),
                        source_names = c("", "Branch Campuses|ED")),
  units    = data.frame(unit_code = c("HIST", "SOCI", "CJUS"),
                        unit_name = c("History", "Sociology", "Criminal Justice"),
                        college_code = c("AS", "AS", "AD"), kind = "department", notes = ""),
  subjects = subject_rows("HIST")
)

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

good_levels <- data.frame(leading_digit = as.character(0:9),
                          level = c(rep("lower", 3), rep("upper", 2), rep("grad", 5)))
