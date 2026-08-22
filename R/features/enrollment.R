# App-facing enrollment payloads ---------------------------------------------

#' Prepare the Classlist table shown on Explore > Enrollment
#'
#' Keeps the registration-status audit columns beside the three canonical
#' lifecycle counts so users can see exactly how census and the outer proxies
#' were reconstructed. Cross-term mean columns are intentionally omitted from
#' this term-level table; they are not lifecycle snapshots.
#'
#' @param classlist_enrl Output from \code{calc_cl_enrls()}.
#' @return A display-ready tibble with stable, human-readable lifecycle fields.
prepare_enrollment_classlist_table <- function(classlist_enrl) {
  if (is.null(classlist_enrl) || nrow(classlist_enrl) == 0) {
    return(tibble::tibble())
  }

  cedar_require_campus(classlist_enrl, "prepare_enrollment_classlist_table")

  lifecycle <- if (all(c(
    "first_day_proxy", "census_enrl", "last_day_or_current_enrl"
  ) %in% names(classlist_enrl))) {
    classlist_enrl
  } else {
    add_classlist_lifecycle_enrl(classlist_enrl)
  }

  lifecycle %>%
    dplyr::ungroup() %>%
    dplyr::select(
      campus, college, term, term_type, subject_course,
      first_day_proxy, census_enrl, last_day_or_current_enrl,
      early_drops = dr_early,
      late_drops = dr_late,
      waitlisted = wl_all
    ) %>%
    dplyr::arrange(campus, subject_course, dplyr::desc(term))
}
