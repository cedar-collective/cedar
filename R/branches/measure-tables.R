# measure-tables.R — Load the measure tables the transform built, for every
# loader.
#
# The app never builds a measure table (ADR-001 step 6): global.R and the
# cache-warming scripts load cedar_attempts, cedar_course_terms and
# cedar_course_flows through this one function, each checked against the
# class list it was counted over, so a script reads exactly what the app
# reads (a copy of these checks in a script fell behind once: ISSUES I69).
#
# Depends on: cedar_load_measure_table() (trunk/data.R), attempts_is_current()
# (attempts.R), course_terms_is_current() (course-terms.R),
# course_flows_is_current() (course-flows.R)

#' Load every measure table, refused when stale
#'
#' @param students The class list as the app holds it (trimmed, thinned,
#'   keyed on the course): each table is checked against it.
#' @param data_dir The data directory.
#' @param edges cedar_report_edges()$edges.
#' @param dims_fingerprint cedar_dims_fingerprint() of the dimensions loaded.
#' @param min_term The first term loaded (cedar_min_term).
#' @param tables Which measure tables to load (default all).
#' @param ext The saved files' extension.
#' @return Named list of the tables, by name; the loader adds them to the
#'   tables it holds.
load_measure_tables <- function(students, data_dir, edges, dims_fingerprint, min_term,
                                tables = CEDAR_MEASURE_TABLES, ext = get_data_extension()) {
  if (is.null(students) || nrow(students) == 0L) {
    stop("[measure-tables.R] load_measure_tables(): the class list is not loaded.", call. = FALSE)
  }
  class_list_path <- file.path(data_dir, paste0(cedar_table_file("cedar_registrations"), ext))
  checks <- list(
    cedar_attempts = function(tbl) attempts_is_current(tbl, students, edges),
    cedar_course_terms = function(tbl) course_terms_is_current(tbl, students, graded_edge = edges$last_graded),
    cedar_course_flows = function(tbl) course_flows_is_current(tbl, students, edges)
  )
  loaded <- list()
  for (name in tables) {
    t <- system.time({
      loaded[[name]] <- cedar_load_measure_table(name, data_dir, class_list_path, checks[[name]],
                                                 dims_fingerprint, min_term, ext = ext)
    })
    message(sprintf("[measure-tables.R] %s loaded: %d rows (%.1fs)", name, nrow(loaded[[name]]), t["elapsed"]))
  }
  loaded
}
