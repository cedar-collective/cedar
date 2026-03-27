# =============================================================================
# test-credit-hours.R
#
# Inspect credit-hours output without running the Shiny app.
# Calls credit_hours_by_major() directly — same as dept-report.R does.
#
# HOW TO RUN:
#   1. Set WD to the cedar project root (Session > Set Working Directory), or
#      uncomment the setwd() line below.
#   2. Change TARGET_DEPT to the department you want to test.
#   3. Source the file (Ctrl+Shift+Enter).
#
# OBJECTS CREATED:
#   result — return value of credit_hours_by_major():
#     $tables$credit_hours_data_w    — SCH by term/college/major (wide)
#     $tables$sch_major_trends_lower — list(growing, declining) for lower div
#     $tables$sch_major_trends_upper — list(growing, declining) for upper div
#     $tables$sch_outside_full_lower — full ranked outside-major list, lower div
#     $tables$sch_outside_full_upper — full ranked outside-major list, upper div
#     $plots$...                     — 8 ggplot objects
# =============================================================================

# setwd("/Users/fwgibbs/Dropbox/projects/cedar")
stopifnot(file.exists("config/shiny_config.R"))

TARGET_DEPT <- "BIOL"   # ← change this

# ── Setup ─────────────────────────────────────────────────────────────────────
source("config/shiny_config.R")
suppressPackageStartupMessages(library(tidyverse))
library(qs)

suppressMessages({
  source("R/trunk/load-funcs.R")
  load_funcs(cedar_base_dir)
})

cedar_students <- qs::qread(file.path(cedar_data_dir, "cedar_students.qs"))

d_params <- suppressMessages(set_payload(TARGET_DEPT))

cat("dept:", d_params$dept_code, "—", d_params$dept_name, "\n")
cat("major_codes:", paste(d_params$prog_codes, collapse = ", "), "\n")
cat("terms:", d_params$term_start, "–", d_params$term_end, "\n\n")

# ── Filter by department (term/grade filtering happens inside the function) ───
dept_students <- cedar_students %>% filter(department == d_params$dept_code)
cat("dept rows:", nrow(dept_students), "\n\n")

# ── Run ───────────────────────────────────────────────────────────────────────
result <- suppressMessages(
  credit_hours_by_major(
    dept_students,
    d_params$dept_code,
    d_params$prog_codes,
    d_params$term_start,
    d_params$term_end
  )
)

# ── Summary ───────────────────────────────────────────────────────────────────
cat("Tables:", paste(names(result$tables), collapse = ", "), "\n")
cat("Plots: ", paste(names(result$plots),  collapse = ", "), "\n\n")

cat("=================================================================\n")
cat(" Lower Division — outside majors (full ranked list)\n")
cat("=================================================================\n")
print(result$tables$sch_outside_full_lower, n = Inf)

cat("\n=================================================================\n")
cat(" Upper Division — outside majors (full ranked list)\n")
cat("=================================================================\n")
print(result$tables$sch_outside_full_upper, n = Inf)

cat("\n=================================================================\n")
cat(" Lower Division — growing/declining outside majors\n")
cat("=================================================================\n")
cat("Growing:\n");   print(result$tables$sch_major_trends_lower$growing,   n = Inf)
cat("Declining:\n"); print(result$tables$sch_major_trends_lower$declining, n = Inf)

cat("\n=================================================================\n")
cat(" Upper Division — growing/declining outside majors\n")
cat("=================================================================\n")
cat("Growing:\n");   print(result$tables$sch_major_trends_upper$growing,   n = Inf)
cat("Declining:\n"); print(result$tables$sch_major_trends_upper$declining, n = Inf)

# ── Name stability check ─────────────────────────────────────────────────────
# Checks whether any major code has had more than one display name across terms.
# Name drift (Banner renaming a code mid-dataset) would fracture time-series grouping.
if (FALSE) {

  cat("=================================================================\n")
  cat(" MAJOR CODE NAME STABILITY ACROSS TERMS\n")
  cat("=================================================================\n")

  name_variants <- cedar_students %>%
    filter(!is.na(major), major != "", !is.na(major_name), major_name != "") %>%
    group_by(major) %>%
    summarize(
      n_names = n_distinct(major_name),
      names   = paste(sort(unique(major_name)), collapse = " | "),
      .groups = "drop"
    ) %>%
    filter(n_names > 1) %>%
    arrange(desc(n_names))

  cat(sprintf("%d codes have more than one display name across terms:\n", nrow(name_variants)))
  if (nrow(name_variants) > 0) {
    print(name_variants, n = Inf)
  } else {
    cat("All codes have a single consistent name. Safe to group by major_name.\n")
  }

  cat("\n--- Name variants for codes seen in lower-division", TARGET_DEPT, "---\n")
  dept_variants <- dept_students %>%
    filter(level == "lower", !is.na(major_name), major_name != "") %>%
    group_by(major) %>%
    summarize(n_names = n_distinct(major_name),
              names   = paste(sort(unique(major_name)), collapse = " | "),
              .groups = "drop") %>%
    filter(n_names > 1)
  if (nrow(dept_variants) == 0) {
    cat("No name variants. All codes stable.\n")
  } else {
    print(dept_variants, n = Inf)
  }
}
