context("Transform status metadata")

load_transform_helpers <- function() {
  env <- new.env(parent = .GlobalEnv)
  env$SOURCED_FROM_PARSE_DATA <- TRUE
  old_wd <- getwd()
  setwd(cedar_base_dir)
  on.exit(setwd(old_wd), add = TRUE)
  sys.source(file.path(cedar_base_dir, "R/data-parsers/transform-to-cedar.R"),
             envir = env)
  env
}

# Scaffolding: the ADR-002 mapping files a transform reads, as small frames.
# Only HIST courses have a subject row; programs are passed per test.
scaffold_mapping_files <- function(programs = NULL) {
  list(
    colleges = data.frame(college_code = "AS", college_name = "Arts and Sciences", source_names = ""),
    units    = data.frame(unit_code = c("HIST", "ANTH", "PHRM", "ARTS"),
                          unit_name = c("History", "Anthropology", "Pharmacy", "Art Studio"),
                          college_code = "AS", kind = "department", notes = ""),
    subjects = data.frame(subject_code = "HIST", in_college = "", in_level = "", unit_code = "HIST",
                          college_code = "", status = "confirmed", evidence = "", notes = ""),
    programs = programs
  )
}

test_that("student transform saves audit-free outcomes with a persistent policy stamp", {
  env <- load_transform_helpers()
  output_dir <- tempfile("audit-transform-")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)
  env$transform_students(class_lists_audits, output_dir, ".qs",
                        maps = list(mapping_files = scaffold_mapping_files(),
                                    major_name_to_major_code = c(History = "HIST")))
  saved <- qs2::qs_read(file.path(output_dir, "cedar_grades.qs"))
  expect_silent(validate_cedar_grades_policy(saved))
  expect_equal(nrow(saved), 5L)
  expect_equal(sum(saved$outcome == "dfw"), 4L)
  expect_equal(sum(saved$outcome == "pass"), 1L)
})

test_that("cedar-status writer emits valid JSON with null metadata", {
  env <- load_transform_helpers()
  status_file <- tempfile(fileext = ".json")

  saved_files <- list(
    students = list(
      filename = "cedar_students.qs", rows = 10L, size_mb = 1.2,
      as_of_date = "2026-02-04", min_term = "201980", max_term = "202610"
    ),
    lookups = list(
      filename = "cedar_lookups.qs", rows = NA_integer_, size_mb = 0,
      as_of_date = NA_character_, min_term = NA_character_, max_term = NA_character_
    )
  )

  env$write_cedar_status_file(saved_files, status_file,
                              generated = "2026-07-27 10:31:41")

  json_text <- paste(readLines(status_file, warn = FALSE), collapse = "\n")
  expect_true(jsonlite::validate(json_text))
  expect_match(json_text, '"rows": null', fixed = TRUE)
  expect_match(json_text, '"as_of_date": null', fixed = TRUE)

  parsed <- jsonlite::fromJSON(status_file)
  expect_equal(parsed$generated, "2026-07-27 10:31:41")
  expect_equal(parsed$tables$students$rows, 10L)
})

test_that("applicant transform keeps only runtime comparison covariates", {
  env <- load_transform_helpers()
  captured <- NULL
  env$save_cedar_file <- function(data, ...) {
    captured <<- data
    list(filename = "cedar_applicants.qs", rows = nrow(data))
  }

  applicants <- data.frame(
    `Academic Period Code` = 202580L,
    ID = "test-student",
    as_of_date = as.Date("2026-08-05"),
    `Admissions Population` = "First-time freshman",
    `High School Cum GPA` = 3.5,
    `UNM ACT Combined Score` = 24,
    `Transfer GPA` = 3.2,
    `High School Self Reported GPA` = 3.6,
    `Current Age` = 18,
    `State Admit` = "NM",
    `Unused Source Field` = "do not retain",
    check.names = FALSE
  )

  env$transform_applicants(applicants, tempdir(), ".qs")

  expect_setequal(names(captured), c(
    "student_id", "term", "as_of_date", "admissions_population",
    "high_school_cum_gpa", "unm_act_combined_score", "transfer_gpa",
    "high_school_self_reported_gpa", "current_age", "state_admit"
  ))
  expect_false("unused_source_field" %in% names(captured))
})


# EC-14: a program's unit comes from programs.csv alone (ADR-002 Stage 3). A
# confirmed row decides it, minors included; a proposed row or no row leaves
# none -- never a department named after the code (ISSUES.md I7); and a
# concentration takes its primary major's unit (I11).
test_that("a program's unit comes from programs.csv; anything unconfirmed has none", {
  env <- load_transform_helpers()
  output_dir <- tempfile("programs-transform-")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)

  # Scaffolding: programs.csv rows for the fixture's codes. ART is proposed.
  programs_csv <- data.frame(
    program_code = c("FPMD", "FOAN", "HIST", "ART"), in_college = "",
    program_name = c("Doctor of Pharmacy", "Forensic Anthropology", "History", "Art"),
    unit_code = c("PHRM", "ANTH", "HIST", "ARTS"), college_code = "", is_pre_major = "FALSE",
    leads_to = "", basis = c("decided", "decided", "source_department", "course_taking"),
    status = c("confirmed", "confirmed", "confirmed", "proposed"), evidence = "", notes = "")
  maps <- list(
    mapping_files = scaffold_mapping_files(programs_csv),
    major_name_to_major_code = character(0),
    college_name_to_code = c("College of Arts & Sciences" = "AS")
  )
  env$transform_programs(academic_studies_program_units, output_dir, ".qs", maps = maps)
  programs <- qs2::qs_read(file.path(output_dir, "cedar_programs.qs"))
  declared <- programs[!grepl("Concentration", programs$program_type), ]
  dept <- stats::setNames(declared$dept_code, declared$major_code)

  expect_equal(unname(dept[c("FPMD", "FOAN", "HIST")]), c("PHRM", "ANTH", "HIST"))
  expect_true(is.na(dept[["ART"]]))
  conc <- programs[grepl("Concentration", programs$program_type), ]
  expect_equal(conc$program_name, "Public Policy")
  expect_equal(conc$dept_code, "HIST")
})

test_that("a transform without the mapping files stops instead of guessing", {
  env <- load_transform_helpers()
  expect_error(
    env$transform_programs(academic_studies_program_units, tempdir(), ".qs",
                           maps = list(college_name_to_code = c("College of Arts & Sciences" = "AS"))),
    "maps\\$mapping_files must carry programs")
})
