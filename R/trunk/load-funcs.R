#' Load All CEDAR R Functions
#'
#' Loads all R source files in dependency order:
#'   1. lists/    — static constants and domain lookups
#'   2. trunk/    — pure infrastructure (filter, utils, cache, logging, data I/O)
#'   3. branches/ — reusable cedar domain computations (enrollment, grades, cohort)
#'   4. cones/    — single-question analyses; call trunk/branches, never other cones
#'   5. reports/  — orchestrators that call multiple branches/cones and render output
#'   6. modules/  — Shiny UI/server pairs
#'
#' @param cedar_base_dir Character. The base directory of the CEDAR project.
#' @export
load_funcs <- function(cedar_base_dir) {
  message("[load-funcs.R] Welcome to load_funcs! Loading R files...")
  message("[load-funcs.R] cedar_base_dir: ", cedar_base_dir)

  source_file <- function(relative_path) {
    full_path <- file.path(cedar_base_dir, "R", relative_path)
    if (!file.exists(full_path)) {
      stop("[load-funcs.R] File not found: ", full_path)
    }
    source(full_path)
  }

  # 1. Lists (static data, no dependencies)
  message("[load-funcs.R] Loading lists...")
  source_file("lists/excluded_courses.R")
  source_file("lists/gen_ed_courses.R")
  source_file("lists/grades.R")
  source_file("lists/unit_catalog.R")      # college → dept → subject hierarchy
  source_file("lists/major_dept_map.R")    # major_code + college_code → dept_code
  source_file("lists/catalog_lookups.R")   # derives lookup vectors from the two catalogs
  source_file("lists/mappings.R")          # text/name maps not derivable from catalogs
  source_file("lists/status_codes.R")

  # 2. Trunk (pure infrastructure — no cedar domain knowledge)
  message("[load-funcs.R] Loading trunk...")
  source_file("trunk/cache.R")
  source_file("trunk/changelog.R")
  source_file("trunk/data.R")
  source_file("trunk/datatable_helpers.R")
  source_file("trunk/filter.R")
  source_file("trunk/logging.R")
  source_file("trunk/utils.R")
  source_file("trunk/command-handler.R")
  source_file("trunk/reporting.R")

  # 3. Branches (reusable cedar domain computations — called by multiple cones/reports)
  message("[load-funcs.R] Loading branches...")
  source_file("branches/enrl.R")
  source_file("branches/credit-hours.R")
  source_file("branches/degrees.R")
  source_file("branches/gradebook.R")
  source_file("branches/headcount.R")
  source_file("branches/population.R")
  source_file("lists/population-presets.R")    # defines DEFAULT_HEALTH_PROGRAMS and COHORT_PRESETS

  # 4. Cones (single-question analyses — call trunk/branches, never other cones)
  message("[load-funcs.R] Loading cones...")
  source_file("cones/bottleneck.R")
  source_file("cones/course-neighbors.R")
  source_file("cones/major-changes.R")
  source_file("cones/stopout.R")
  source_file("cones/course-outcomes.R")
  source_file("cones/pathway.R")
  source_file("cones/population-trend.R")
  source_file("cones/course-demographics.R")
  source_file("cones/seatfinder.R")
  source_file("cones/sfr.R")
  source_file("cones/waitlist.R")

  # 4a. Forecast cones (depend on course-neighbors + enrl branches)
  message("[load-funcs.R] Loading forecast cones...")
  source_file("cones/forecast/forecast.R")
  source_file("cones/forecast/forecast-stats.R")

  # 5. Reports (orchestrators — call multiple branches/cones, render Rmd output)
  message("[load-funcs.R] Loading reports...")
  source_file("reports/course-report.R")
  source_file("reports/dept-dashboard.R")
  source_file("reports/dept-report.R")
  source_file("reports/regstats.R")

  # 6. Shiny modules (depend on branches + cones)
  message("[load-funcs.R] Loading Shiny modules...")
  source_file("modules/pathways.R")

  message("[load-funcs.R] All functions loaded successfully!")
  invisible(NULL)
}
