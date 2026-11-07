context("Transform status metadata")

# load_transform_helpers() is in helper-transform.R, shared with the gate's test.

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

test_that("student transform saves one class-list row per course-term and no classified outcomes", {
  env <- load_transform_helpers()
  output_dir <- tempfile("audit-transform-")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)
  env$transform_students(class_lists_audits, output_dir, ".qs",
                        maps = list(mapping_files = scaffold_mapping_files(),
                                    major_name_to_major_code = c(History = "HIST")))
  # Outcomes are classified at load (cedar_attempts), never saved.
  expect_false(file.exists(file.path(output_dir, "cedar_grades.qs")))
  # The saved rows carry Banner's course college as a key and no unit (ADR-001
  # step 3); attached through the same files, the course reports its unit's
  # college, with Banner's beside it.
  students <- qs2::qs_read(file.path(output_dir, "cedar_students.qs"))
  expect_false(any(c("department", "college", "college_basis") %in% names(students)))
  expect_equal(unique(students$source_college), "ARTS")
  attached <- attach_unit(students, scaffold_dims(), "subject")
  expect_equal(unique(attached$department), "HIST")
  expect_equal(unique(attached$college), "AS")
  expect_equal(unique(attached$college_basis), "mapped")
  # EC-09 is one row per student: nothing to collapse, and the loaded class
  # list's attempts carry the audit exclusions the saved outcomes used to.
  expect_equal(nrow(students), nrow(class_lists_audits))
  keyed <- attach_test_course_ids(attached, "students")
  attempts <- build_attempts(keyed, list(last_graded = 202110L))
  expect_equal(sum(attempts$outcome %in% "dfw"), 4L)
  expect_equal(sum(attempts$outcome %in% "pass"), 1L)
})

test_that("the class-list dedup keeps the row of record for each student-course-term", {
  env <- load_transform_helpers()
  # One student-course-term per case, on two or three CRNs; the expected row
  # is the one a reader of the loaded class list must see (ISSUES I50).
  rows <- tibble::tribble(
    ~student_id, ~crn,  ~registration_status_code, ~final_grade, ~want,
    "early-late", "201", "DR", NA,    FALSE,   # the late withdrawal is the outcome
    "early-late", "202", "DW", "W",   TRUE,
    "late-reg",   "211", "DG", "W",   FALSE,   # a seat held beats a withdrawal
    "late-reg",   "212", "RE", "B",   TRUE,
    "wl-reg",     "221", "WL", NA,    FALSE,   # enrolled, not waiting
    "wl-reg",     "222", "RS", NA,    TRUE,
    "early-wl",   "231", "DR", NA,    FALSE,   # still waiting is demand
    "early-wl",   "232", "WL", NA,    TRUE,
    "lab-lec",    "241", "RE", "",    FALSE,   # the graded lecture over the ungraded lab
    "lab-lec",    "242", "RE", "A",   TRUE,
    "aud-credit", "251", "RE", "AUD", FALSE,   # a credit attempt over an audit
    "aud-credit", "252", "RE", "C",   TRUE,
    "tie",        "262", "RE", "B",   FALSE,   # same status and grade: lowest CRN
    "tie",        "261", "RE", "A",   TRUE,
    "alone",      "271", "DR", NA,    TRUE
  ) %>% dplyr::mutate(term = 202080L, campus = "ABQ", subject_course = "HIST 1110")
  # Row order must not decide: the reversed input keeps the same rows.
  for (input in list(rows, rows[rev(seq_len(nrow(rows))), ])) {
    kept <- suppressMessages(env$dedup_class_list_rows(dplyr::select(input, -want)))
    expect_equal(nrow(kept), dplyr::n_distinct(rows$student_id))
    expect_setequal(paste(kept$student_id, kept$crn),
                    paste(rows$student_id, rows$crn)[rows$want])
  }
  # A second campus is a second delivery, never a duplicate.
  two_campus <- dplyr::bind_rows(rows[15, ], dplyr::mutate(rows[15, ], campus = "EA", crn = "272"))
  expect_equal(nrow(suppressMessages(env$dedup_class_list_rows(dplyr::select(two_campus, -want)))), 2L)
  expect_error(env$dedup_class_list_rows(dplyr::select(rows, -crn)), "lacks crn")
})

test_that("cedar-status writer emits valid JSON with null metadata", {
  env <- load_transform_helpers()
  status_file <- tempfile(fileext = ".json")

  saved_files <- list(
    students = list(
      filename = "cedar_students.qs", rows = 10L, size_mb = 1.2,
      as_of_date = "2026-02-04", min_term = "201980", max_term = "202610"
    ),
    applicants = list(
      filename = "cedar_applicants.qs", rows = NA_integer_, size_mb = 0,
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
# concentration takes its primary major's unit (I11). Since ADR-001 step 3
# the transform stores the keys (the code, Banner's two college values) and
# the loader attaches the unit; this test runs both, as a start does.
test_that("a program's unit comes from programs.csv; anything unconfirmed has none", {
  env <- load_transform_helpers()
  output_dir <- tempfile("programs-transform-")
  dir.create(output_dir)
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)

  # Scaffolding: programs.csv rows for the fixture's codes. ART is proposed.
  programs_csv <- data.frame(
    program_code = c("FPMD", "FOAN", "HIST", "ART"), in_college = "",
    program_name = c("Doctor of Pharmacy", "Forensic Anthropology", "History", "Art"),
    unit_code = c("PHRM", "ANTH", "HIST", "ARTS"), college_code = "",
    is_pre_major = c("TRUE", "FALSE", "FALSE", "FALSE"),
    leads_to = "", basis = c("decided", "decided", "source_department", "course_taking"),
    status = c("confirmed", "confirmed", "confirmed", "proposed"), evidence = "", notes = "")
  # History names a major, so the name-to-code fill could reach EC14-C's
  # History concentration if it applied to concentrations (I21).
  maps <- list(
    mapping_files = scaffold_mapping_files(programs_csv),
    dims = scaffold_dims(programs_csv),
    major_name_to_major_code = c(History = "HIST")
  )
  env$transform_programs(academic_studies_program_units, output_dir, ".qs", maps = maps)
  stored <- qs2::qs_read(file.path(output_dir, "cedar_programs.qs"))
  expect_false(any(c("dept_code", "program_college", "college_code", "college_basis",
                     "student_college") %in% names(stored)))
  expect_true(all(c("source_college", "source_college_code") %in% names(stored)))
  programs <- suppressMessages(attach_program_units(stored, scaffold_dims(programs_csv)))
  declared <- programs[!grepl("Concentration", programs$program_type), ]
  dept <- stats::setNames(declared$dept_code, declared$major_code)

  expect_equal(unname(dept[c("FPMD", "FOAN", "HIST")]), c("PHRM", "ANTH", "HIST"))
  expect_true(is.na(dept[["ART"]]))
  conc <- programs[grepl("Concentration", programs$program_type), ]
  conc <- conc[order(conc$program_name), ]
  expect_equal(conc$program_name, c("History", "Pre-Law", "Public Policy"))
  # Each takes its primary major's unit: none for EC14-C, whose ART is proposed.
  expect_equal(conc$dept_code, c(NA, "PHRM", "HIST"))

  # Stage 3b colleges. Each row keeps its own program's college; the student's
  # college is their primary major's, on every row; an undecided major takes
  # Banner's, labelled; Banner's values stay beside.
  row <- function(id, type) programs[programs$student_id == env$encrypt_if_needed(id) &
                                       programs$program_type == type, ]
  expect_equal(row("EC14-A", "Major")$program_college, "PH")
  expect_equal(row("EC14-A", "First Minor")$program_college, "AS")
  expect_equal(unique(programs$college_code[programs$student_id == env$encrypt_if_needed("EC14-A")]), "PH")
  expect_equal(row("EC14-A", "First Minor")$student_college, "Pharmacy")
  expect_true(is.na(row("EC14-B", "First Minor")$program_college))   # ART is proposed
  expect_equal(row("EC14-B", "First Concentration")$program_college, "AS")
  expect_equal(unique(programs$college_code[programs$student_id == env$encrypt_if_needed("EC14-B")]), "AS")
  expect_equal(unique(programs$college_basis[programs$student_id == env$encrypt_if_needed("EC14-B")]), "mapped")
  expect_equal(row("EC14-C", "Major")$college_code, "FA")
  expect_equal(row("EC14-C", "Major")$college_basis, "banner")
  expect_equal(row("EC14-C", "Major")$source_college, "College of Fine Arts")
  expect_equal(row("EC14-B", "Major")$source_college_code, "AS")

  # Stage 4: the pre-major flag is the file's, per code -- FPMD's name says
  # nothing of "Pre-" -- and a row with no programs.csv row (the concentration)
  # falls back to its name.
  expect_true(row("EC14-A", "Major")$is_pre_major)
  expect_equal(row("EC14-A", "Major")$pre_major_basis, "programs_csv")
  expect_false(row("EC14-B", "Major")$is_pre_major)
  expect_false(row("EC14-B", "First Concentration")$is_pre_major)

  # I21: concentrations are not majors. A pre-major's "Pre-Law" concentration
  # is not a pre-major and keeps Banner's name; the student's major row is
  # still one. A concentration named like a major gets no program code.
  pre_law <- row("EC14-A", "First Concentration")
  expect_equal(pre_law$program_name, "Pre-Law")
  expect_false(pre_law$is_pre_major)
  expect_true(is.na(pre_law$pre_major_basis))
  expect_true(row("EC14-A", "Major")$is_pre_major)
  expect_true(is.na(row("EC14-C", "First Concentration")$major_code))
  expect_true(all(is.na(conc$major_code)))
})

test_that("a transform without the mapping files stops instead of guessing", {
  env <- load_transform_helpers()
  expect_error(
    env$transform_programs(academic_studies_program_units, tempdir(), ".qs",
                           maps = list(major_name_to_major_code = character(0))),
    "maps\\$mapping_files must carry programs")
})

# ADR-001 step 2: the deploy gate builds cedar_student_terms when it is absent
# or older than a saved table it reads, by file time, and when the saved file
# lacks a column the builder now writes — the one staleness a file time cannot
# record (the completed-credit running total, 2026-11-04).
test_that("cedar_student_terms is stale when missing, older than a source, short a column, or built under an older rule", {
  env <- load_transform_helpers()
  dir <- withr::local_tempdir()
  full_row <- tibble::as_tibble(stats::setNames(as.list(rep(1, length(STUDENT_TERMS_COLUMNS))),
                                                STUDENT_TERMS_COLUMNS))
  attr(full_row, "cedar_student_terms_build_version") <- STUDENT_TERMS_BUILD_VERSION
  write_at <- function(name, when, data = tibble::tibble(x = 1)) {
    path <- file.path(dir, paste0(name, ".qs"))
    qs2::qs_save(data, path)
    Sys.setFileTime(path, when)
    path
  }
  t0 <- Sys.time() - 3600
  for (name in c("cedar_students", "cedar_programs", "cedar_degrees")) write_at(name, t0)
  expect_match(env$cedar_student_terms_staleness(dir), "not been built")
  write_at("cedar_student_terms", t0 + 60, full_row)
  expect_null(env$cedar_student_terms_staleness(dir))
  # Built by last week's builder: every column but the one added since.
  write_at("cedar_student_terms", t0 + 60,
           dplyr::select(full_row, -cumulative_completed_unm_credits))
  expect_match(env$cedar_student_terms_staleness(dir),
               "^saved cedar_student_terms lacks column\\(s\\) the builder now writes: cumulative_completed_unm_credits$")
  # Every column, but written before the builder stamped its rule version, or
  # under an earlier one: a value change no file time or column list records.
  unstamped <- full_row
  attr(unstamped, "cedar_student_terms_build_version") <- NULL
  write_at("cedar_student_terms", t0 + 60, unstamped)
  expect_match(env$cedar_student_terms_staleness(dir),
               "^saved cedar_student_terms was built under rule version 1 \\(unstamped\\); the builder is at ")
  older <- full_row
  attr(older, "cedar_student_terms_build_version") <- STUDENT_TERMS_BUILD_VERSION - 1L
  write_at("cedar_student_terms", t0 + 60, older)
  expect_match(env$cedar_student_terms_staleness(dir), "was built under rule version ")
  write_at("cedar_student_terms", t0 + 60, full_row)
  write_at("cedar_programs", t0 + 120)
  expect_match(env$cedar_student_terms_staleness(dir), "^cedar_programs newer than cedar_student_terms$")
  write_at("cedar_students", t0 + 180)
  expect_match(env$cedar_student_terms_staleness(dir), "^cedar_students, cedar_programs newer")
})
