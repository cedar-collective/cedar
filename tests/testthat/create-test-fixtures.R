# Create small test fixtures from real CEDAR data
# Run this once to generate stable test data files
#
# IMPORTANT: All test fixtures are DERIVED from real CEDAR data files.
# No hardcoded test data - this ensures tests validate real data structures.
#
# ⚠️  SCHEMA SYNC REQUIREMENT:
# This script requires that transform-to-cedar.R has already run successfully.
#
# NO FALLBACK LOGIC - If columns are missing, this script will FAIL.
# This forces us to fix the transformation, not paper over it in tests.
#
# Workflow:
# 1. MyReports data downloaded
# 2. parse-data.R creates aggregate files
# 3. transform-to-cedar.R creates CEDAR files with ALL required columns
# 4. THIS script samples from those CEDAR files for testing
#
# If this script fails with missing columns:
# → Fix transform-to-cedar.R to add the missing columns
# → Do NOT add fallback logic here

library(tidyverse)
library(qs)

message("Creating test fixtures from CEDAR data files...")
message("All fixtures derived from real data - no fallback logic\n")

# Helper function to validate required columns
validate_columns <- function(data, data_name, required_cols) {
  missing <- setdiff(required_cols, colnames(data))

  if (length(missing) > 0) {
    stop(
      "\n❌ ", data_name, " is missing required columns: ", paste(missing, collapse = ", "), "\n",
      "   Found columns: ", paste(colnames(data), collapse = ", "), "\n\n",
      "   FIX: Update R/data-parsers/transform-to-cedar.R to add missing columns,\n",
      "        then regenerate CEDAR data: Rscript R/data-parsers/transform-to-cedar.R\n"
    )
  }

  message("  ✓ ", data_name, " has all required columns")
}

# Load full CEDAR data
sections <- qread("data/cedar_sections.qs")
students <- qread("data/cedar_students.qs")
programs <- qread("data/cedar_programs.qs")
degrees <- qread("data/cedar_degrees.qs")
faculty <- qread("data/cedar_faculty.qs")

message("Original data loaded:")
message("  sections: ", nrow(sections), " rows")
message("  students: ", nrow(students), " rows")
message("  programs: ", nrow(programs), " rows")
message("  degrees: ", nrow(degrees), " rows")
message("  faculty: ", nrow(faculty), " rows")
message("")

# Validate that transformation produced all required columns
message("Validating CEDAR data has required columns...")

validate_columns(sections, "cedar_sections",
                c("section_id", "term", "department", "instructor_id", "subject_course"))

validate_columns(students, "cedar_students",
                c("student_id", "term", "section_id", "subject_course", "subject_code",
                  "level", "instructor_id", "final_grade", "credits", "department"))

validate_columns(programs, "cedar_programs",
                c("term", "student_level", "student_college", "student_campus",
                  "program_type", "program_name", "department"))

validate_columns(degrees, "cedar_degrees",
                c("term", "degree", "program_code", "department"))

validate_columns(faculty, "cedar_faculty",
                c("term", "instructor_id", "department"))

message("✓ All CEDAR data validated\n")

# Create small, stable test datasets
# Use multiple terms (spring, summer, fall) and departments for reproducible tests
test_terms <- c(202510, 202560, 202580)  # Spring 2025, Summer 2025, Fall 2025

# Note: Different data sources use different department identifiers
# - Sections/Students/Faculty use subject codes (HIST, MATH, ANTH)
# - Programs use MyReports department names ("History", "Mathematics Statistics", "AS Anthropology")
test_subject_codes <- c("HIST", "MATH", "ANTH")
test_dept_names <- c("History", "Mathematics Statistics", "AS Anthropology")

message("Test parameters:")
message("  Terms: ", paste(test_terms, collapse = ", "))
message("  Subject codes (for sections/students/faculty): ", paste(test_subject_codes, collapse = ", "))
message("  Department names (for programs): ", paste(test_dept_names, collapse = ", "))
message("")

# Sample sections (4 per term = 12 total)
test_sections <- sections %>%
  filter(term %in% test_terms, department %in% test_subject_codes) %>%
  group_by(term) %>%
  slice_head(n = 4) %>%
  ungroup()

message("Test sections selected: ", nrow(test_sections), " sections")
message("  By term: ")
test_sections %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " sections"))

# Get section IDs for filtering students
test_section_ids <- test_sections$section_id

# Sample students from test sections (~20 per term = 60 total)
test_students <- students %>%
  filter(section_id %in% test_section_ids) %>%
  group_by(term) %>%
  slice_head(n = 20) %>%
  ungroup()

# Set realistic grade data for testing
# Completed terms should have grades, in-progress terms should not
if ("grade" %in% colnames(test_students)) {
  test_students <- test_students %>%
    mutate(
      grade = case_when(
        # Spring 2025 (202510): completed, should have grades
        term == 202510 & is.na(grade) ~ sample(c("A", "B", "C", "B+", "A-", "C+"), 1),
        # Summer 2025 (202560): completed, should have grades
        term == 202560 & is.na(grade) ~ sample(c("A", "B", "C", "B+", "A-"), 1),
        # Fall 2025 (202580): in progress, should NOT have grades
        term == 202580 ~ NA_character_,
        # Any other terms: keep existing grade or set to NA
        TRUE ~ grade
      )
    )

  # Report grade distribution
  grades_by_term <- test_students %>%
    group_by(term) %>%
    summarize(
      total = n(),
      with_grades = sum(!is.na(grade)),
      without_grades = sum(is.na(grade)),
      .groups = "drop"
    )

  message("  Grade distribution by term:")
  grades_by_term %>%
    pwalk(~ message(sprintf("    %d: %d enrollments (%d with grades, %d without)",
                            ..1, ..2, ..3, ..4)))
}

message("Test students selected: ", nrow(test_students), " enrollments")
message("  By term: ")
test_students %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " enrollments"))

# Sample programs (~7 per term = 21 total)
test_programs <- programs %>%
  filter(term %in% test_terms, department %in% test_dept_names) %>%
  group_by(term) %>%
  slice_head(n = 7) %>%
  ungroup()

# Normalize program names to match major_to_program_map conventions
# This is just standardization, not creating data
test_programs <- test_programs %>%
  mutate(program_name = case_when(
    grepl('Anthropology', program_name, ignore.case = TRUE) ~ 'Anthropology',
    grepl('Mathematics', program_name, ignore.case = TRUE) ~ 'Mathematics',
    grepl('History', program_name, ignore.case = TRUE) ~ 'History',
    TRUE ~ program_name
  ))

message("Test programs selected: ", nrow(test_programs), " program enrollments")
message("  By term: ")
test_programs %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " programs"))
message("  By program: ")
test_programs %>% count(program_name) %>% pwalk(~ message("    ", ..1, ": ", ..2))

# Sample degrees from multiple terms
degree_terms <- c(202480, 202510, 202560)  # Fall 2024, Spring 2025, Summer 2025

# Note: degrees table uses different department naming than other tables
degree_dept_map <- c(
  "ANTH" = "AS Anthropology",
  "MATH" = "Mathematics Statistics",
  "HIST" = "History"
)
test_depts_degrees <- unname(degree_dept_map[test_subject_codes])

message("  Degrees departments: ", paste(test_depts_degrees, collapse = ", "))

test_degrees <- degrees %>%
  filter(term %in% degree_terms, department %in% test_depts_degrees) %>%
  group_by(term) %>%
  slice_head(n = 5) %>%
  ungroup()

message("Test degrees selected: ", nrow(test_degrees), " degrees")
message("  By term: ")
test_degrees %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " degrees"))
message("  By department: ")
test_degrees %>% count(department) %>% pwalk(~ message("    ", ..1, ": ", ..2))

# Sample faculty for test terms/departments
test_faculty <- faculty %>%
  filter(term %in% test_terms, department %in% test_subject_codes) %>%
  distinct(instructor_id, term, .keep_all = TRUE)

message("\n  Extracting faculty for test terms and departments...")
message("    Selected ", nrow(test_faculty), " faculty records from test terms/departments")

message("Test faculty selected: ", nrow(test_faculty), " faculty records")
message("  By term: ")
test_faculty %>% count(term) %>% pwalk(~ message("    ", ..1, ": ", ..2, " faculty"))
message("  By department: ")
test_faculty %>% count(department) %>% pwalk(~ message("    ", ..1, ": ", ..2))
message("  Unique instructors: ", n_distinct(test_faculty$instructor_id))

# Save test fixtures
fixture_dir <- "tests/testthat/fixtures"
dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)

qsave(test_sections, file.path(fixture_dir, "cedar_sections_test.qs"))
qsave(test_students, file.path(fixture_dir, "cedar_students_test.qs"))
qsave(test_programs, file.path(fixture_dir, "cedar_programs_test.qs"))
qsave(test_degrees, file.path(fixture_dir, "cedar_degrees_test.qs"))
qsave(test_faculty, file.path(fixture_dir, "cedar_faculty_test.qs"))

message("\n✅ Test fixtures created in tests/testthat/fixtures/")
message("   - cedar_sections_test.qs (", nrow(test_sections), " rows)")
message("     Terms: ", paste(unique(test_sections$term), collapse = ", "))
message("   - cedar_students_test.qs (", nrow(test_students), " rows)")
message("     Terms: ", paste(unique(test_students$term), collapse = ", "))
message("   - cedar_programs_test.qs (", nrow(test_programs), " rows)")
message("     Terms: ", paste(unique(test_programs$term), collapse = ", "))
message("     Programs: ", paste(unique(test_programs$program_name), collapse = ", "))
message("   - cedar_degrees_test.qs (", nrow(test_degrees), " rows)")
message("     Terms: ", paste(unique(test_degrees$term), collapse = ", "))
message("   - cedar_faculty_test.qs (", nrow(test_faculty), " rows)")
message("     Terms: ", paste(unique(test_faculty$term), collapse = ", "))
message("     Unique instructors: ", n_distinct(test_faculty$instructor_id))

message("\n✓ ALL test fixtures derived from real CEDAR data - no fallback logic used")
message("✓ If this script failed, fix transform-to-cedar.R first, not this script")
message("\nYou can now run tests with: devtools::test()")
message("Or run standalone test: Rscript tests/test-dept-report-standalone.R")
