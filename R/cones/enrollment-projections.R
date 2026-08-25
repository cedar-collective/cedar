#' Project Class-List Demand and Section Need for Pressured Courses
#'
#' Answers one question: for an explicit target term and course scope, which
#' course markets show enrollment pressure, what unique class-list demand does
#' each candidate project, and which method has the best leakage-safe backtest
#' record?
#'
#' @param inputs Output of `prepare_enrollment_projection_inputs()`.
#' @param target_term Explicit YYYYSS target term.
#' @param scope_courses Courses eligible for pressure screening.
#' @param force_courses Courses included even when pressure thresholds do not fire.
#' @param opt Projection method and threshold options.
#' @return A list containing pressure screen, published projections, delivery
#'   components, all current candidates, historical backtests, recent audit
#'   history, and performance.
get_course_enrollment_projections <- function(inputs, target_term,
                                              scope_courses = NULL,
                                              force_courses = NULL,
                                              opt = list()) {
  required_inputs <- c(
    "enrollment_history", "section_history", "students", "target_courses",
    "target_campuses", "target_market_id", "delivery_components"
  )
  missing_inputs <- setdiff(required_inputs, names(inputs))
  if (length(missing_inputs) > 0) {
    stop("[enrollment-projections.R] inputs is missing: ",
         paste(missing_inputs, collapse = ", "), call. = FALSE)
  }
  if (is.null(target_term) || length(target_term) != 1 || is.na(target_term)) {
    stop("[enrollment-projections.R] One explicit target_term is required.",
         call. = FALSE)
  }

  target_term <- as.integer(target_term)
  opt <- enrollment_projection_model_config(opt)
  scope_courses <- scope_courses %||% inputs$target_courses
  pressure_screen <- build_projection_pressure_screen(
    inputs$enrollment_history,
    inputs$section_history,
    target_term = target_term,
    target_registration_snapshot = inputs$target_registration_snapshot %||% NULL,
    target_market_id = inputs$target_market_id,
    force_courses = force_courses,
    scope_courses = scope_courses,
    opt = opt
  )

  roster <- pressure_screen %>%
    dplyr::filter(included)
  if (nrow(roster) == 0) {
    return(list(
      pressure_screen = pressure_screen,
      projections = empty_enrollment_projections(),
      delivery_components = inputs$delivery_components,
      candidates = empty_projection_candidates(),
      backtests = tibble::tibble(),
      method_performance = empty_projection_performance(),
      recent_history = empty_projection_recent_history()
    ))
  }

  candidates <- dplyr::bind_rows(lapply(seq_len(nrow(roster)), function(i) {
    project_course_method_candidates(
      inputs, roster[i, , drop = FALSE], target_term, opt
    )
  }))

  backtests <- backtest_course_projection_methods(
    inputs, roster, target_term, opt
  )
  performance <- summarize_projection_backtests(backtests, opt)
  if (nrow(performance) == 0) performance <- empty_projection_performance()
  selected <- select_projection_methods(candidates, performance, backtests, opt)
  candidate_evidence <- attach_projection_performance(
    candidates, performance, opt
  ) %>%
    dplyr::left_join(
      selected %>%
        dplyr::transmute(
          market_id, subject_course, term_type, target_term,
          method_id, selected = TRUE
        ),
      by = c(
        "market_id", "subject_course", "term_type", "target_term", "method_id"
      )
    ) %>%
    dplyr::mutate(selected = dplyr::coalesce(selected, FALSE))
  projections <- add_projection_recommendations(
    selected, candidate_evidence, pressure_screen, inputs$enrollment_history,
    inputs$section_history, opt
  )
  recent_history <- build_projection_recent_history(
    projections, inputs$enrollment_history, inputs$section_history,
    backtests, opt,
    student_inputs = inputs$students,
    graded_through_term = inputs$graded_through_term %||% NULL
  )

  list(
    pressure_screen = pressure_screen,
    projections = projections,
    delivery_components = inputs$delivery_components,
    candidates = candidate_evidence,
    backtests = backtests,
    method_performance = performance,
    recent_history = recent_history
  )
}
