# Observed course-group participation, with concurrent categories preserved.
# This is neither a prerequisite graph nor a degree audit.

#' When does a population take each kind of coursework?
#' @param students cedar_students; all history is needed to anchor the clock.
#' @param population build_population() output, including relevant_until.
#' @param groups Validated subject-to-descriptive-group table.
#' @param opt data_edges (required), campus, max_terms, min_n, min_band_n.
#' @return Suppressed group/campus/relative-term cells, safe course detail and metadata.
get_grouped_student_paths <- function(students, population, groups, opt = list()) {
  validate_population(population, "get_grouped_student_paths")
  needed <- c("student_id", "term", "campus", "subject_course", "registration_status_code", "level")
  missing <- setdiff(needed, names(students))
  if (length(missing)) stop("Grouped paths missing: ", paste(missing, collapse = ", "))
  if (!"relevant_until" %in% names(population)) stop("Population needs relevant_until")
  edge <- cedar_longitudinal_edge(opt$data_edges, grade_dependent = FALSE)
  if (is.null(edge)) stop("A settled enrollment edge is required for observed paths")
  max_terms <- opt$max_terms %||% 8L
  min_n <- opt$min_n %||% 10L; min_band_n <- opt$min_band_n %||% 20L
  if (length(max_terms) != 1L || !is.finite(max_terms) || max_terms < 1 || max_terms > 16 ||
      max_terms != floor(max_terms)) stop("max_terms must be a whole number from 1 to 16")
  if (length(min_n) != 1L || !is.finite(min_n) || min_n < 1 ||
      length(min_band_n) != 1L || !is.finite(min_band_n) || min_band_n < 1) stop("Invalid small-cell guards")
  rows <- apply_pathways_population_window(students, population, edge) %>%
    dplyr::filter(student_id %in% population$student_id, level %in% c("lower", "upper"),
                  registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE))
  if (!nrow(rows)) stop("No observed undergraduate course participation for this population")
  # Clock precedes campus filtering: changing delivery campus cannot restart a path.
  rows <- assign_relative_terms(rows, include_summer = TRUE)
  first <- rows %>% dplyr::group_by(student_id) %>% dplyr::summarize(first_term = min(term), .groups = "drop")
  rows <- cedar_filter_campus(rows, opt$campus, "get_grouped_student_paths") %>%
    dplyr::filter(relative_term <= max_terms)
  if (!nrow(rows)) stop("No course participation at the selected delivery campuses")
  n_left <- sum(first$student_id %in% rows$student_id &
                  first$first_term <= opt$data_edges$first_enrolled, na.rm = TRUE)
  # Retain campus in course keys. Repeated rows/CRNs do not multiply participation.
  rows <- rows %>% dplyr::distinct(student_id, term, relative_term, campus, subject_course)
  rows <- attach_pathway_groups(rows, groups)
  bands <- rows %>% dplyr::group_by(campus, relative_term) %>%
    dplyr::summarize(n_eligible = dplyr::n_distinct(student_id), .groups = "drop")
  counts <- rows %>% dplyr::group_by(campus, relative_term, group_id, group_label) %>%
    dplyr::summarize(n_students = dplyr::n_distinct(student_id), .groups = "drop")
  labels <- rows %>% dplyr::distinct(group_id, group_label)
  cells <- merge(bands, labels, by = NULL) %>%
    dplyr::left_join(counts, by = c("campus", "relative_term", "group_id", "group_label")) %>%
    dplyr::mutate(n_students = dplyr::coalesce(n_students, 0L),
      band_suppressed = n_eligible < min_band_n,
      cell_suppressed = n_students > 0 & n_students < min_n,
      suppressed = band_suppressed | cell_suppressed,
      pct_students = dplyr::if_else(suppressed, NA_real_, 100 * n_students / n_eligible),
      n_students = dplyr::if_else(suppressed, NA_integer_, n_students),
      n_eligible = dplyr::if_else(band_suppressed, NA_integer_, n_eligible)) %>%
    dplyr::arrange(campus, group_label, relative_term)
  courses <- rows %>% dplyr::group_by(campus, relative_term, group_id, group_label, subject_course) %>%
    dplyr::summarize(n_students = dplyr::n_distinct(student_id), .groups = "drop") %>%
    dplyr::left_join(bands, by = c("campus", "relative_term")) %>%
    dplyr::filter(n_students >= min_n, n_eligible >= min_band_n) %>%
    dplyr::mutate(pct_students = 100 * n_students / n_eligible) %>%
    dplyr::arrange(campus, relative_term, group_label, subject_course)
  list(cells = cells, courses = courses, groups = labels,
       meta = list(n_population = nrow(population), n_observed = dplyr::n_distinct(rows$student_id),
         n_left_boundary = n_left, n_unmapped_rows = sum(rows$group_id == "unmapped"),
         n_course_rows = nrow(rows), n_suppressed = sum(cells$suppressed),
         analysis_through = edge, min_n = min_n, min_band_n = min_band_n, max_terms = max_terms))
}
