# CEDAR-PLATFORM: the lines the Graduation views read a departing student against
#
# Two general standards, not a record of anyone's aid: CEDAR's data holds no
# aid-eligibility field. A student below the GPA floor, or at or past the
# credit ceiling, would no longer meet the standing most aid asks for. A page
# that shows either says it is computed from these lines. A caller may pass
# its own in `opt`.
#
#   GPA floor       a cumulative GPA under 2.0
#   credit ceiling  160 attempted credits or more
#
# Credit bands for "how far along": the lower edge of each band after the
# first. 120 is the credits a bachelor's degree asks for.

# Pace: the credits a regular term that reach 120 in four years (eight
# regular terms) and in six (twelve), fastest first.
DEGREE_PACE_TERM_CREDITS <- c(four_year = 15, six_year = 10)

EXIT_GPA_FLOOR <- 2.0
EXIT_CREDIT_CEILING <- 160
EXIT_CREDIT_BREAKS <- c(30, 60, 90, 105, 120)

#' Band labels for a set of lower edges
#'
#' @param breaks Increasing lower edges, e.g. `EXIT_CREDIT_BREAKS`.
#' @return One label per band: "Under 30", "30 to 59", ..., "120 or more".
exit_credit_band_labels <- function(breaks = EXIT_CREDIT_BREAKS) {
  if (length(breaks) < 1L || is.unsorted(breaks, strictly = TRUE)) {
    stop("[aid_progress.R] breaks must be increasing lower edges.", call. = FALSE)
  }
  c(paste("Under", breaks[1]),
    if (length(breaks) > 1L) paste(breaks[-length(breaks)], "to", breaks[-1] - 1),
    paste(breaks[length(breaks)], "or more"))
}
