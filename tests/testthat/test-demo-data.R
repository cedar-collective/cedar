# The app institution and unit regressions share the same authored scenarios.
source("../../dev/demo-data.R")

test_that("the institution preserves its original cohort and copies complete histories", {
  raw <- build_demo_sources(cohorts = 2L, fixture_path = "fixtures/designed_test_data.R")
  expect_identical(raw, build_demo_sources(cohorts = 2L,
    fixture_path = "fixtures/designed_test_data.R"))
  cl <- raw$class_lists
  original <- cl %>% filter(grepl("^FIX-base:", `Course Reference Number`))
  expect_equal(original$`Student ID`, test_students$student_id)
  expect_equal(original$`Final Grade`, test_students$final_grade)
  expect_equal(original$`Academic Period Code`, test_students$term)
  copied <- cl %>% filter(grepl("^COHORT2-FIX-base:", `Course Reference Number`))
  expect_equal(sub("^COHORT2-", "", copied$`Student ID`), original$`Student ID`)
  expect_equal(copied$`Final Grade`, original$`Final Grade`)
  expect_equal(copied$`Academic Period Code`, original$`Academic Period Code`)
  expect_equal(nrow(anti_join(cl, raw$DESRs,
    by = c("Academic Period Code" = "TERM", "Course Reference Number" = "CRN"))), 0L)
  expect_setequal(raw$DESRs$CAMP, c("ABQ", "EA", "GA"))
  # HIST 1110's hand-worked grade scenario: 21 registered and nine late drops.
  hist <- original %>% filter(`Academic Period Code` == 202010L,
                             `Subject Code` == "HIST", `Course Number` == "1110")
  expect_equal(sum(hist$`Registration Status Code` %in% STATUS_REGISTERED), 21L)
  expect_equal(sum(hist$`Registration Status Code` %in% STATUS_DROP_LATE), 9L)
  expect_error(build_demo_sources(cohorts = 0), "cohorts")
})

test_that("fixture institution survives production transforms with usable provenance", {
  root <- normalizePath("../..")
  target <- tempfile("cedar-fixture-institution-")
  dir.create(target)
  on.exit(unlink(target, recursive = TRUE), add = TRUE)
  # The real exporter isolates parser globals and exercises safe publication too.
  log <- tempfile("cedar-fixture-export-", fileext = ".log")
  on.exit(unlink(log), add = TRUE)
  rc <- withr::with_dir(root, system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "dev/generate-demo.R", shQuote(target)), stdout = log, stderr = log))
  expect_equal(rc, 0, info = paste(tail(readLines(log), 30), collapse = "\n"))
  if (rc != 0) return(invisible(NULL))
  students <- qs2::qs_read(file.path(target, "cedar_students.qs"))
  sections <- qs2::qs_read(file.path(target, "cedar_sections.qs"))
  programs <- qs2::qs_read(file.path(target, "cedar_programs.qs"))
  grades <- qs2::qs_read(file.path(target, "cedar_grades.qs"))
  expect_identical(attr(grades, "cedar_outcome_policy_version"), CEDAR_OUTCOME_POLICY_VERSION)
  expect_equal(nrow(anti_join(students, sections, by = c("term", "crn"))), 0L)
  expect_false(anyNA(students$synthetic_cohort))
  expect_setequal(students$synthetic_cohort, 1:5)
  original <- students %>% filter(synthetic_cohort == 1L, fixture_source == "base")
  expect_setequal(original$fixture_student_id, test_students$student_id)
  hist <- calc_cl_enrls(original) %>%
    filter(subject_course == "HIST 1110", term == 202010L, campus == "ABQ")
  expect_equal(hist$registered, 21L)
  expect_equal(hist$census_enrl, 30L)
  xl <- sections %>% filter(synthetic_cohort == 1L, fixture_source == "base",
                            term == 202080L, subject_course == "BIOL 2305")
  expect_equal(get_enrl(xl, list(uel = FALSE,
    group_cols = c("term", "campus", "subject_course")))$total_enrl, 71)
  # Replicated ordinary sections must never become one giant crosslist.
  regular <- sections %>% filter(fixture_section_id == "S10001")
  expect_true(all(is.na(regular$crosslist_group)))
  expect_equal(nrow(regular), 5L)
  # EC-10 has four concurrent History/English students in Spring 2020 and
  # one in Fall 2020, before replication. Different-term declarations do not
  # qualify; the malformed records stay out of the generated institution.
  concurrent <- programs %>% filter(fixture_source == "concurrent_programs")
  expect_setequal(concurrent$fixture_student_id, paste0("EC10-", LETTERS[1:7]))
  combined <- get_headcount(concurrent,
    list(major = "History", minor = "English"), group_by = "term")$data
  expect_equal(combined %>% arrange(term) %>% pull(student_count), c(20L, 5L))
})

test_that("developer launcher is syntactically valid and isolated from production", {
  expect_equal(system2("bash", c("-n", "../../scripts/dev.sh")), 0)
  expect_equal(system2("bash", c("-n", "../../dev/init.sh")), 0)
  compose <- paste(readLines("../../compose.dev.yml"), collapse = "\n")
  script <- paste(readLines("../../scripts/dev.sh"), collapse = "\n")
  expect_false(grepl("CEDAR_DATA_DIR|external: true|container_name:", compose))
  expect_true(grepl("127.0.0.1:", compose, fixed = TRUE))
  expect_true(grepl("--env-file /dev/null -p cedar-demo -f compose.dev.yml", script, fixed = TRUE))
})
