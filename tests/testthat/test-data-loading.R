# Tests for data serialization and CEDAR model loading.

context("Data Loading")

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

test_that("load_cedar_data reads RDS files and returns empty tibble for missing files", {
  expected <- tibble::tibble(term = 202510L, value = "loaded")
  path <- tempfile(fileext = ".Rds")
  saveRDS(expected, path)

  expect_equal(load_cedar_data(path, use_qs = FALSE), expected)
  expect_s3_class(load_cedar_data(tempfile(fileext = ".Rds"), use_qs = FALSE), "tbl_df")
  expect_equal(nrow(load_cedar_data(tempfile(fileext = ".Rds"), use_qs = FALSE)), 0L)
})

test_that("load_cedar_data falls back from missing qs path to matching RDS file", {
  expected <- tibble::tibble(term = 202510L, value = "fallback")
  qs_path <- tempfile(fileext = ".qs")
  rds_path <- sub("\\.qs$", ".Rds", qs_path)
  saveRDS(expected, rds_path)

  expect_equal(load_cedar_data(qs_path, use_qs = TRUE), expected)
})

test_that("load_datafile respects configured data directory and small-data preference", {
  with_temp_cedar_data_dir({
    regular <- tibble::tibble(term = 202510L, source = "regular")
    small <- tibble::tibble(term = 202510L, source = "small")
    saveRDS(regular, file.path(cedar_data_dir, "cedar_students.Rds"))
    saveRDS(small, file.path(cedar_data_dir, "cedar_students_small.Rds"))

    cedar_use_small_data <<- TRUE
    expect_equal(load_datafile("cedar_students"), small)

    cedar_use_small_data <<- FALSE
    expect_equal(load_datafile("cedar_students"), regular)
  })
})

test_that("load_global_data loads all required CEDAR model objects from configured files", {
  # Scaffolding, not a fixture: these one-row files exist only so the loader has
  # something on disk to find. Their contents are irrelevant — what is under test
  # is which files load_global_data() reaches for. See AGENTS.md.
  with_temp_cedar_data_dir({
    cedar_files <- c(
      "cedar_sections", "cedar_students", "cedar_student_terms",
      "cedar_programs", "cedar_degrees", "cedar_faculty", "cedar_applicants"
    )

    # The loader attaches the unit columns from the mapping files (ADR-001
    # step 3), so each attached table carries the key columns attach_unit()
    # reads; an NA key resolves to no unit, which is all this test needs.
    attach_keys <- list(
      cedar_sections = c("subject", "source_college", "level", "campus", "crosslist_group", "subject_course"),
      cedar_students = c("subject_code", "source_college", "level"),
      cedar_programs = c("student_id", "program_type", "major_code", "source_college_code", "source_college"),
      cedar_degrees = c("major_code", "source_student_college", "source_college"),
      cedar_student_terms = c("primary_major_code", "primary_source_college_code", "primary_source_college")
    )
    # The course dimension (step 4) reads a code, a title and a level from
    # the sections and the class lists; a code must look like "SUBJ NUMBER".
    for (name in cedar_files) {
      row <- tibble::tibble(term = 202510L, as_of_date = as.Date("2026-07-30"), dataset = name)
      for (key in attach_keys[[name]]) row[[key]] <- NA_character_
      if (name %in% c("cedar_sections", "cedar_students")) {
        row$subject_course <- "HIST 101"
        row$course_title <- "History"
        row$level <- "lower"
      }
      saveRDS(row, file.path(cedar_data_dir, paste0(name, ".Rds")))
    }

    suppressMessages(load_global_data(list(func = "course-report")))

    expect_true(exists("data_objects", envir = .GlobalEnv))
    expect_setequal(names(data_objects), c(cedar_files, "cedar_dims", "cedar_courses", "cedar_course_codes"))
    expect_true("department" %in% names(data_objects$cedar_sections))
    expect_equal(data_objects$cedar_sections$course_id, "HIST 101")
    expect_equal(data_objects$cedar_students$course_id, "HIST 101")
    expect_true("dept_code" %in% names(programs))
    expect_equal(data_objects$cedar_sections$dataset, "cedar_sections")
    expect_equal(sections$dataset, "cedar_sections")
    expect_equal(students$dataset, "cedar_students")
    expect_equal(programs$dataset, "cedar_programs")
    expect_equal(degrees$dataset, "cedar_degrees")
    expect_equal(faculty$dataset, "cedar_faculty")
    expect_equal(applicants$dataset, "cedar_applicants")
  })
})
