# Demo records are a reusable, fully invented multi-year fixture in dev/demo-data.R.
# Unlike the smaller unit fixtures they must also boot the entire Shiny app.
source("../../dev/demo-data.R")

test_that("the synthetic world is deterministic and has a known crosslist", {
  demo <- build_demo_sources()
  expect_identical(demo, build_demo_sources())
  cl <- demo$class_lists
  expect_true(all(grepl("^DEMO-STUDENT-", cl$`Student ID`)))
  expect_equal(sort(unique(cl$`Academic Period Code`)),
               c(202310L, 202380L, 202410L, 202480L, 202510L, 202580L,
                 202610L, 202660L, 202680L))
  xl <- cl %>% filter(`Academic Period Code` == 202680L, `Course Number` == "375")
  expect_equal(sum(xl$`Registration Status Code` %in% STATUS_REGISTERED), 30)
  expect_equal(sum(xl$`Registration Status Code` %in% STATUS_DROP_LATE), 2)
  expect_equal(sum(xl$`Registration Status Code` %in% STATUS_DROP_EARLY), 2)
  expect_equal(sum(xl$`Registration Status Code` %in% STATUS_WAITLIST), 4)
  expect_equal(n_distinct(xl$`Student ID`), nrow(xl))
  expect_true(all(is.na(cl$`Final Grade`[cl$`Academic Period Code` == 202680L &
                                        cl$`Registration Status Code` == "RE"])))
  expect_true(all(demo$degrees$ID %in% cl$`Student ID`))
  expect_equal(nrow(demo$degrees), 6)
})

test_that("demo sources survive the production transformation pipeline", {
  root <- normalizePath("../..")
  target <- tempfile("cedar-demo-test-")
  dir.create(target)
  on.exit(unlink(target, recursive = TRUE), add = TRUE)
  # A separate vanilla R process keeps the parser and its globals out of the
  # suite. docker=TRUE disables the parser's optional local-data copy step.
  code <- paste0(
    "setwd(", deparse(root), "); ",
    "Sys.setenv(docker='TRUE', CEDAR_STUDENT_SALT='public-synthetic-demo-only'); ",
    "library(tidyverse); source('dev/demo-data.R'); ",
    "SOURCED_FROM_PARSE_DATA <- TRUE; source('R/data-parsers/transform-to-cedar.R'); ",
    "target <- ", deparse(target), "; raw <- build_demo_sources(); ",
    "for (nm in names(raw)) qs2::qs_save(raw[[nm]], file.path(target, paste0(nm, '.qs'))); ",
    "file.copy('data/program_map.qs', file.path(target, 'program_map.qs')); ",
    "transform_to_cedar(data_dir=target, use_qs=TRUE)"
  )
  log <- file.path(target, "transform.log")
  rc <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e", shQuote(code)),
                stdout = log, stderr = log)
  expect_equal(rc, 0, info = paste(tail(readLines(log), 30), collapse = "\n"))
  if (rc != 0) return(invisible(NULL))
  students <- qs2::qs_read(file.path(target, "cedar_students.qs"))
  sections <- qs2::qs_read(file.path(target, "cedar_sections.qs"))
  grades <- qs2::qs_read(file.path(target, "cedar_grades.qs"))
  expect_identical(attr(grades, "cedar_outcome_policy_version"), CEDAR_OUTCOME_POLICY_VERSION)
  expect_equal(nrow(anti_join(students, sections, by = c("term", "crn"))), 0)
  expect_equal(cedar_data_edges(students)$last_graded, 202660L)
  expect_equal(cedar_data_edges(students)$last_enrolled_complete, 202680L)
  xl <- sections %>% filter(term == 202680L, course_number == "375")
  expect_equal(sum(xl$crosslist_primary), 1)
  expect_true(all(xl$crosslist_external))
  expect_equal(xl$subject[xl$crosslist_primary], "MATH")
  expect_equal(sum(keep_home_sections(xl)$total_enrl), 30)
  enrollment <- assemble_course_enrollment_payload(students, sections,
    list(course = "MATH 375", campus = "ABQ", uel = FALSE))
  latest <- enrollment$overview$lifecycle %>% filter(term == 202680L)
  expect_equal(sum(latest$current_enrl), 30)
  expect_equal(sum(latest$census_enrl), 32)
  expect_equal(sum(latest$selected_current_enrl), 20)
  for (name in c("programs", "degrees", "faculty", "lookups", "next_term", "student_term_credits", "applicants")) {
    expect_true(file.exists(file.path(target, paste0("cedar_", name, ".qs"))))
  }
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
