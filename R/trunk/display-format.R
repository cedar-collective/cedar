# Display formatters shared by every layer.
#
# One way to write a count on a page, in a sentence, a hover or a note. Kept
# apart from trunk/utils.R, which is enrollment-projection model source: an
# edit there rebuilds both projection bundles at deploy.
#
# Exported functions:
#   fmt_count(x)

#' A count as text: a whole number with thousands separators
#'
#' @param x Numbers; rounded to whole.
#' @return Character, the same length: "1,234"; an em dash where `x` is NA.
#'   No padding, so a vector's values paste cleanly into sentences.
fmt_count <- function(x) {
  if (!is.numeric(x) && !is.logical(x)) {
    stop("[display-format.R] fmt_count() takes numbers, not ", class(x)[[1]], ".", call. = FALSE)
  }
  out <- rep("—", length(x))
  known <- !is.na(x)
  out[known] <- formatC(round(as.numeric(x[known])), format = "f", digits = 0, big.mark = ",")
  out
}
