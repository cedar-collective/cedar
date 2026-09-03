# App-facing enrollment payloads ---------------------------------------------

#' Match class-list records to the Enrollment page's DESR scope
#'
#' The Enrollment page establishes its shared course scope from active DESR
#' section rows before applying DESR-only crosslist views, grouping, or
#' enrollment thresholds. Matching on CRN and term keeps Classlist aligned with
#' the base course filters while leaving its student-count grain independent of
#' those DESR display controls. Department is applied again because crosslisted
#' course records can share a CRN across department representations.
#'
#' @param students Student-level class-list records.
#' @param desr_sections Section rows returned for the page's base DESR scope.
#' @param dept_codes Optional department codes from the page filter.
#' @return Class-list rows in the base Enrollment scope.
filter_enrollment_classlist_scope <- function(students, desr_sections,
                                              dept_codes = NULL) {
  required <- c("crn", "term")
  missing_students <- setdiff(required, names(students))
  missing_sections <- setdiff(required, names(desr_sections))
  if (length(missing_students) > 0 || length(missing_sections) > 0) {
    stop(
      "[enrollment.R] filter_enrollment_classlist_scope() requires crn and term ",
      "in both students and DESR sections"
    )
  }
  if (is.null(desr_sections) || nrow(desr_sections) == 0) {
    return(students[integer(0), , drop = FALSE])
  }

  keys <- desr_sections %>%
    dplyr::ungroup() %>%
    dplyr::distinct(crn, term)
  scoped <- students %>%
    dplyr::semi_join(keys, by = c("crn", "term"))

  dept_codes <- dept_codes[!is.na(dept_codes) & nzchar(dept_codes)]
  if (length(dept_codes) > 0 && "department" %in% names(scoped)) {
    scoped <- scoped %>% dplyr::filter(department %in% dept_codes)
  }
  scoped
}

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
