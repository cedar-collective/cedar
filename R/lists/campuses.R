# Campus codes and the CEDAR-wide default scope.
#
# UNM is not one campus. `cedar_students` carries ten campus codes, and roughly
# 15% of enrollment rows come from branch campuses. 21% of courses are taught on
# more than one campus, concentrated in the high-enrollment Gen Ed courses people
# actually analyse — the largest run on six campuses and draw a quarter to a
# third of their rows from branches.
#
# See the CEDAR-wide campus policy in AGENTS.md: any analytic grouped by course
# must also be grouped by campus. These constants exist so the default scope is
# defined once rather than as a `c("ABQ", "EA")` literal in every filter bar,
# which is how the app ends up with controls that quietly disagree.

CEDAR_CAMPUS_MAIN   <- "ABQ"
CEDAR_CAMPUS_ONLINE <- "EA"

# Branch campuses. GA/LA/TA/VA are the four named branches (see
# program_code_maps.R); the remainder are small codes that appear in the data
# without a documented expansion, kept here so "branch" means the same thing
# everywhere it is tested.
CEDAR_CAMPUS_BRANCH <- c("GA", "VA", "TA", "LA", "EW", "EF", "ELA", "TAQ")

# The default scope for a filter bar: main campus plus online. This is normally a
# display scope, not a substitute for grouping. The named ABQ+EA enrollment-
# projection market is a documented exception that retains delivery components.
CEDAR_CAMPUS_DEFAULT <- c(CEDAR_CAMPUS_MAIN, CEDAR_CAMPUS_ONLINE)

# Display labels for the codes whose expansion is documented. Codes absent from
# this map fall back to the bare code rather than a guessed name.
CEDAR_CAMPUS_LABELS <- c(
  ABQ = "ABQ — Main",
  EA  = "EA — Online",
  GA  = "GA — Gallup",
  LA  = "LA — Los Alamos",
  TA  = "TA — Taos",
  VA  = "VA — Valencia"
)


#' Campus choices for a selectInput, labelled where a label is known
#'
#' @param df Optional data frame with a `campus` column. When supplied, only
#'   campuses actually present are offered, so a filter bar cannot advertise a
#'   campus the loaded data has no rows for. When NULL, every known code is
#'   offered.
#' @return Named character vector suitable for `choices =`.
cedar_campus_choices <- function(df = NULL) {
  codes <- if (!is.null(df) && "campus" %in% names(df)) {
    sort(unique(df$campus[!is.na(df$campus) & nzchar(df$campus)]))
  } else {
    c(CEDAR_CAMPUS_MAIN, CEDAR_CAMPUS_ONLINE, CEDAR_CAMPUS_BRANCH)
  }
  if (length(codes) == 0) return(character(0))
  stats::setNames(codes, unname(ifelse(
    codes %in% names(CEDAR_CAMPUS_LABELS),
    CEDAR_CAMPUS_LABELS[codes],
    codes
  )))
}


#' The default campus selection, restricted to what the data actually contains
#'
#' @param df Optional data frame with a `campus` column.
#' @return Character vector of campus codes.
cedar_campus_default <- function(df = NULL) {
  if (is.null(df) || !"campus" %in% names(df)) return(CEDAR_CAMPUS_DEFAULT)
  intersect(CEDAR_CAMPUS_DEFAULT, unique(df$campus))
}


#' Require a campus column before a campus-grouped analytic runs
#'
#' Failing here is deliberate. Quietly dropping campus from a grouping produces
#' a plausible number that silently blends branch and main campus data — the
#' exact failure the campus policy exists to prevent — so a campus-free frame is
#' an error rather than a fallback to campus-blind output.
#'
#' @param df Data frame that must carry a `campus` column.
#' @param fn Calling function name, used in the error message.
cedar_require_campus <- function(df, fn) {
  if (!"campus" %in% names(df)) {
    stop("[", fn, "] the data has no `campus` column. This analysis is grouped ",
         "by campus (see the campus policy in AGENTS.md); add a campus column ",
         "rather than computing a campus-blind result.")
  }
  invisible(df)
}


#' Restrict a frame to the requested campuses
#'
#' @param df Data frame with a `campus` column.
#' @param campus Character vector of campus codes, or NULL for every campus.
#'   NULL should only be passed for a deliberate UNM-wide aggregate.
#' @param fn Calling function name, used in the error message.
cedar_filter_campus <- function(df, campus = NULL, fn = "cedar_filter_campus") {
  if (is.null(campus) || length(campus) == 0) return(df)
  cedar_require_campus(df, fn)
  df[df$campus %in% campus, , drop = FALSE]
}
