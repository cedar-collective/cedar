#' Load All CEDAR R Functions
#'
#' Loads all R source files for the CEDAR application in the correct
#' dependency order: lists first, then branches (utilities), then cones
#' (analysis functions).
#'
#' @param cedar_base_dir Character. The base directory of the CEDAR project.
#'   All source paths are constructed relative to this directory.
#'
#' @return NULL (invisibly). Called for side effect of loading functions.
#'
#' @details
#' Loading order:
#' 1. **lists/** - Static data: column mappings, term codes, grade definitions
#' 2. **branches/** - Core utilities: caching, filtering, data loading
#' 3. **cones/** - Analysis functions: headcount, degrees, enrollment, etc.
#'
#' @examples
#' \dontrun{
#' # From project root
#' load_funcs(getwd())
#'
#' # From Shiny app
#' load_funcs(cedar_base_dir)
#' }
#'
#' @export
load_funcs <- function(cedar_base_dir) {
  message("[load-funcs.R] Welcome to load_funcs! Loading R files...")
  message("[load-funcs.R] cedar_base_dir: ", cedar_base_dir)

  # Helper to source with absolute path
  source_file <- function(relative_path) {
    full_path <- file.path(cedar_base_dir, "R", relative_path)
    if (!file.exists(full_path)) {
      stop("[load-funcs.R] File not found: ", full_path)
    }
    source(full_path)
  }

  # 1. Lists (static data, no dependencies)
  message("[load-funcs.R] Loading lists...")
  source_file("lists/drop_cols.R")
  source_file("lists/excluded_courses.R")
  source_file("lists/gen_ed_courses.R")
  source_file("lists/grades.R")
  source_file("lists/mappings.R")
  source_file("lists/terms.R")

  # 2. Branches (utilities, depend on lists)
  message("[load-funcs.R] Loading branches...")
  source_file("branches/cache.R")
  source_file("branches/changelog.R")
  source_file("branches/data.R")
  source_file("branches/datatable_helpers.R")
  source_file("branches/filter.R")
  source_file("branches/logging.R")
  source_file("branches/utils.R")
  source_file("branches/command-handler.R")
  source_file("branches/reporting.R")

  # 3. Cones (analysis functions, depend on branches)
  message("[load-funcs.R] Loading cones...")
  source_file("cones/course-report.R")
  source_file("cones/credit-hours.R")
  source_file("cones/degrees.R")
  source_file("cones/dept-report.R")
  source_file("cones/enrl.R")
  source_file("cones/gradebook.R")
  source_file("cones/headcount.R")
  source_file("cones/lookout.R")
  source_file("cones/majors.R")
  # source_file("cones/offramp.R")  # still in development
  source_file("cones/outcomes.R")
  source_file("cones/regstats.R")
  source_file("cones/rollcall.R")
  source_file("cones/seatfinder.R")
  source_file("cones/sfr.R")
  source_file("cones/waitlist.R")

  # 4. Forecasting functions
  message("[load-funcs.R] Loading forecast functions...")
  source_file("cones/forecast/forecast.R")
  source_file("cones/forecast/forecast-stats.R")

  message("[load-funcs.R] All functions loaded successfully!")
  invisible(NULL)
}
