# Legacy Dept Report Rmd entry points.
#
# The full department RMarkdown report is retired. Active Dept Trends web
# support lives in R/reports/dept-trends.R and R/modules/dept-trends.R.

create_dept_report_data <- function(data_objects, opt) {
  stop(
    "[dept-report.R] Legacy Rmd department reports are retired. ",
    "Use create_dept_report_base() plus the per-tab compute_dept_* helpers ",
    "for the active Dept Trends web profile."
  )
}

compute_dept_dfw_tab <- function(base, opt = list()) {
  stop(
    "[dept-report.R] The legacy Dept Trends DFW/SFR tab is retired. ",
    "Use course-outcomes or Gen Ed DFW views for maintained DFW analysis."
  )
}

create_dept_report <- function(data_objects, opt) {
  stop(
    "[dept-report.R] Legacy Rmd department reports are retired. ",
    "Use the active Dept Trends web profile instead."
  )
}
