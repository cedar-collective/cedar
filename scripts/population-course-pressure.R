# population-course-pressure.R - the text-first preview of a population's path
# through its shared courses: who takes each course and when, DFW for the
# population beside everyone, when a DFW is retaken, and in which seasons and
# parts of term the course is offered with how full it starts.
#
#   Rscript --vanilla scripts/population-course-pressure.R \
#     --group "Health Professions (Clinical)" \
#     --plans "nursing-bsn-2026,medical-laboratory-bs-2026,population-health-bs-2026" \
#     [--courses "BIOL 2210,CHEM 1215"] [--campus ABQ] [--min-plans 2] [--min-n 10] \
#     [--years 3] [--level Undergraduate] [--output PATH]
#
# --group names an entry in institution/<id>/population_groups.csv; the
# population is build_population() over its programs (declared and pre-major,
# as that function lumps them). --plans names degree roadmap plans
# (degree_roadmap_plans.csv); the courses reported are those at least
# --min-plans of them require, unless --courses names them. Shared entry
# routes (catalog_id "*") are not a plan's requirement and are left out.
# --campus scopes the course campus (default ABQ); every other option has the
# feature's default. Output is the text preview, to stdout or --output.
#
# Run from the repository root with --vanilla, with the app stopped when it
# shares the machine: it loads the class list, programs, student terms and
# both measure tables. Analysis helper, not a test runner.

suppressMessages(library(dplyr))

.argument_value <- function(args, flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(NULL)
  args[[index + 1L]]
}
.split_arg <- function(value) {
  if (is.null(value)) return(NULL)
  parts <- trimws(strsplit(value, ",", fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

run_population_course_pressure <- function(args) {
  group_id <- .argument_value(args, "--group")
  plans <- .split_arg(.argument_value(args, "--plans"))
  courses <- .split_arg(.argument_value(args, "--courses"))
  campus <- .split_arg(.argument_value(args, "--campus")) %||% "ABQ"
  min_plans <- as.integer(.argument_value(args, "--min-plans") %||% "2")
  min_n <- as.integer(.argument_value(args, "--min-n") %||% "10")
  n_years <- as.integer(.argument_value(args, "--years") %||% "3")
  level <- .argument_value(args, "--level")
  output <- .argument_value(args, "--output")
  if (is.null(group_id)) stop("--group GROUP_ID is required.", call. = FALSE)
  if (is.null(plans) && is.null(courses)) {
    stop("--plans or --courses is required.", call. = FALSE)
  }

  repo_root <- getwd()
  source(file.path(repo_root, "scripts", "cedar-repl.R"))

  program_names <- population_group_program_names(group_id)
  population <- build_population(
    cedar_programs, cedar_degrees, cedar_student_terms,
    opt = list(type = "preset", program_names = program_names, student_level = level)
  )
  if (nrow(population) == 0L) stop("The population is empty for group ", group_id, call. = FALSE)
  edges <- cedar_data_edges(cedar_registrations, degrees = cedar_degrees)

  plan_courses <- NULL
  if (!is.null(plans)) {
    known <- CEDAR_DEGREE_ROADMAPS$plans$catalog_id
    unknown <- setdiff(plans, known)
    if (length(unknown) > 0) {
      stop("Unknown plan(s): ", paste(unknown, collapse = ", "), ". Known: ",
           paste(sort(known), collapse = ", "), call. = FALSE)
    }
    plan_courses <- CEDAR_DEGREE_ROADMAPS$courses %>%
      filter(catalog_id %in% plans) %>%
      distinct(catalog_id, subject_course)
  }

  payload <- build_population_course_pressure(
    population, cedar_registrations, cedar_attempts, cedar_course_terms,
    list(courses = courses, plan_courses = plan_courses, min_plans = min_plans,
         campus = campus, data_edges = edges, min_n = min_n, n_years = n_years,
         label = paste0(group_id, " (", paste(program_names, collapse = ", "), ")"))
  )
  text <- format_population_course_pressure(payload)
  if (is.null(output)) writeLines(text) else {
    writeLines(text, output)
    message("[population-course-pressure.R] Wrote ", output)
  }
  invisible(payload)
}

if (sys.nframe() == 0L) {
  run_population_course_pressure(commandArgs(trailingOnly = TRUE))
}
