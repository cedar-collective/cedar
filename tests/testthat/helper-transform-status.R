# What the tests in test-transform-status.R share: builders, option lists, constants.

# Scaffolding: the ADR-002 mapping files a transform reads, as small frames.
# Only HIST courses have a subject row; programs are passed per test.
scaffold_mapping_files <- function(programs = NULL) {
  if (is.null(programs)) {
    programs <- as.data.frame(stats::setNames(
      rep(list(character()), length(CEDAR_MAPPING_FILE_SPECS$programs)),
      CEDAR_MAPPING_FILE_SPECS$programs))
  }
  list(
    colleges = data.frame(college_code = c("AS", "FA", "PH"),
                          college_name = c("Arts and Sciences", "Fine Arts", "Pharmacy"),
                          source_names = c("College of Arts & Sciences", "College of Fine Arts", "")),
    units    = data.frame(unit_code = c("HIST", "ANTH", "PHRM", "ARTS"),
                          unit_name = c("History", "Anthropology", "Pharmacy", "Art Studio"),
                          college_code = c("AS", "AS", "PH", "FA"), kind = "department", notes = ""),
    subjects = data.frame(subject_code = "HIST", in_college = "", in_level = "", unit_code = "HIST",
                          college_code = "", status = "confirmed", evidence = "", notes = ""),
    programs = programs,
    code_history = as.data.frame(stats::setNames(
      rep(list(character()), length(CEDAR_MAPPING_FILE_SPECS$code_history)),
      CEDAR_MAPPING_FILE_SPECS$code_history)),
    settings = data.frame(setting = character(), value = character())
  )
}

# The same files as the loader reads them: the transform stores keys, and
# attach_unit() (R/branches/dims.R) resolves them at every start.
scaffold_dims <- function(programs = NULL) build_cedar_dims(scaffold_mapping_files(programs))
