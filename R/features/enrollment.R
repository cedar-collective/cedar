# App-facing enrollment payloads ---------------------------------------------

#' Check whether an Enrollment request is scoped to an academic unit
#'
#' Explore > Enrollment can otherwise scan the full section and class-list
#' histories in one Shiny worker. Campus, term, level, subject, and course are
#' useful refinements, but the page intentionally requires a college or
#' department because those are the stable ownership boundaries used by its
#' section and student joins.
#'
#' @param college Selected college code(s).
#' @param dept_codes Selected department code(s).
#' @return A single logical value.
enrollment_scope_is_ready <- function(college = NULL, dept_codes = NULL) {
  has_value <- function(x) {
    x <- trimws(as.character(unlist(x, use.names = FALSE)))
    any(!is.na(x) & nzchar(x))
  }
  has_value(college) || has_value(dept_codes)
}

#' Expand the Enrollment page's convenient level groups
#'
#' The stored section levels remain `lower`, `upper`, and `grad`. The UI's
#' `undergrad` choice is a compact alias for the two undergraduate values so it
#' can be the safe default without changing the canonical data vocabulary.
#'
#' @param levels Selected UI level value(s).
#' @return Canonical section level values, or NULL when no level was selected.
resolve_enrollment_levels <- function(levels = NULL) {
  if (is.null(levels) || length(levels) == 0) return(NULL)
  levels <- trimws(as.character(unlist(levels, use.names = FALSE)))
  levels <- levels[!is.na(levels) & nzchar(levels)]
  if (length(levels) == 0) return(NULL)
  if ("undergrad" %in% levels) {
    levels <- c(setdiff(levels, "undergrad"), "lower", "upper")
  }
  unique(levels)
}

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
  scoped <- filter_classlist_to_sections(students, desr_sections)

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
