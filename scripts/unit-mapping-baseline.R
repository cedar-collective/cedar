# unit-mapping-baseline.R — what unit does every program and subject land in?
#
#   Rscript --vanilla scripts/unit-mapping-baseline.R snapshot   # save today's
#   Rscript --vanilla scripts/unit-mapping-baseline.R compare    # diff against it
#
# The ADR-002 migration replaces how CEDAR assigns units, in stages. Each stage
# must change exactly the rows that were decided and nothing else, so each is
# compared against a snapshot taken before the first one (Stage 0).
#
# The snapshot records, from the stored CEDAR tables:
#   programs — student-term rows per (program_type, major_code, dept_code)
#   courses  — enrollment rows per (subject_code, college, department)
# and is written beside the data as unit_mapping_baseline.qs.

source("scripts/cedar-repl.R")
suppressMessages(library(dplyr))

mode <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(mode) || !mode %in% c("snapshot", "compare")) {
  stop("Usage: Rscript --vanilla scripts/unit-mapping-baseline.R snapshot|compare")
}
baseline_file <- file.path(cedar_data_dir, "unit_mapping_baseline.qs")

current_units <- function() {
  list(
    programs = cedar_programs %>%
      count(program_type, major_code, dept_code, name = "rows"),
    courses = cedar_students %>%
      count(subject_code, college, department, name = "rows"),
    taken = Sys.time()
  )
}

diff_units <- function(before, after, keys, unit_col) {
  b <- before %>% group_by(across(all_of(keys))) %>%
    summarize(before = paste(sort(unique(.data[[unit_col]])), collapse = "|"),
              rows = sum(rows), .groups = "drop")
  a <- after %>% group_by(across(all_of(keys))) %>%
    summarize(after = paste(sort(unique(.data[[unit_col]])), collapse = "|"),
              .groups = "drop")
  full_join(b, a, by = keys) %>%
    filter(is.na(before) | is.na(after) | before != after) %>%
    arrange(desc(rows))
}

if (mode == "snapshot") {
  snap <- current_units()
  qs2::qs_save(snap, baseline_file)
  message("Saved baseline: ", nrow(snap$programs), " program groups, ",
          nrow(snap$courses), " course groups -> ", baseline_file)
} else {
  if (!file.exists(baseline_file)) stop("No baseline at ", baseline_file, "; run snapshot first.")
  base <- qs2::qs_read(baseline_file)
  now <- current_units()
  message("Baseline taken ", format(base$taken), "\n")
  prog <- diff_units(base$programs, now$programs, c("program_type", "major_code"), "dept_code")
  crse <- diff_units(base$courses, now$courses, c("subject_code", "college"), "department")
  message("Programs whose unit changed: ", nrow(prog))
  if (nrow(prog)) print(as.data.frame(prog), right = FALSE)
  message("\nCourse subjects whose unit changed: ", nrow(crse))
  if (nrow(crse)) print(as.data.frame(crse), right = FALSE)
}
