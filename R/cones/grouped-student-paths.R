# Observed course-group participation, with concurrent categories preserved.
# This is neither a prerequisite graph nor a degree audit.

#' When does a population take each kind of coursework?
#' @param students cedar_registrations; all history is needed to anchor the clock.
#' @param population build_population() output, including relevant_until.
#' @param groups A grouping by subject (`subject_code`, the institution's
#'   pathway_subject_groups.csv) or by course (`subject_course`,
#'   course_path_roles()); attach_pathway_groups() reads either.
#' @param opt data_edges (required), campus, max_terms, min_n, min_band_n.
#' @param arrivals Optional: `student_id`, `term`, `entry_type` ("first_time"
#'   or "transfer"), as student_term_entry_type() returns them. Given, each
#'   student's term 1 is the first term they enrolled from their first arrival
#'   on record (a term recorded both ways reads first-time), earlier courses
#'   are left out, a student with a course on the chosen campuses and no
#'   arrival before their last course is left out (`meta$n_no_arrival`), and
#'   every table is also keyed by `entry_type`.
#' @return Suppressed group/campus/relative-term cells, safe course and
#'   subject detail, and metadata. A cell's `n_courses` and `n_subjects` count
#'   every course and subject its students took, those too small to list
#'   included; NA where the cell is suppressed.
get_grouped_student_paths <- function(students, population, groups, opt = list(), arrivals = NULL) {
  validate_population(population, "get_grouped_student_paths")
  needed <- c("student_id", "term", "campus", "subject_course", "registration_status_code", "level")
  missing <- setdiff(needed, names(students))
  if (length(missing)) stop("[grouped-student-paths.R] Grouped paths missing: ", paste(missing, collapse = ", "))
  if (!"relevant_until" %in% names(population)) stop("[grouped-student-paths.R] Population needs relevant_until")
  edge <- cedar_longitudinal_edge(opt$data_edges, grade_dependent = FALSE)
  if (is.null(edge)) stop("[grouped-student-paths.R] A settled enrollment edge is required for observed paths")
  max_terms <- opt$max_terms %||% 8L
  min_n <- opt$min_n %||% 10L; min_band_n <- opt$min_band_n %||% 20L
  if (length(max_terms) != 1L || !is.finite(max_terms) || max_terms < 1 || max_terms > 16 ||
      max_terms != floor(max_terms)) stop("[grouped-student-paths.R] max_terms must be a whole number from 1 to 16")
  if (length(min_n) != 1L || !is.finite(min_n) || min_n < 1 ||
      length(min_band_n) != 1L || !is.finite(min_band_n) || min_band_n < 1) stop("[grouped-student-paths.R] Invalid small-cell guards")
  rows <- apply_pathways_population_window(students, population, edge) %>%
    filter(student_id %in% population$student_id, level %in% c("lower", "upper"),
                  registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE))
  if (!nrow(rows)) stop("[grouped-student-paths.R] No observed undergraduate course participation for this population")
  keys <- "campus"
  n_no_arrival <- NA_integer_
  # A population none of whom has a start on record has no path: empty
  # tables and the count left out, a finding rather than an error.
  none_started <- FALSE
  if (!is.null(arrivals)) {
    missing <- setdiff(c("student_id", "term", "entry_type"), names(arrivals))
    if (length(missing)) stop("[grouped-student-paths.R] Arrivals missing: ", paste(missing, collapse = ", "))
    if (!all(arrivals$entry_type %in% c("first_time", "transfer"))) {
      stop("[grouped-student-paths.R] An arrival is neither first_time nor transfer")
    }
    # "first_time" sorts before "transfer": a term recorded both ways reads first-time.
    first_arrival <- arrivals %>%
      filter(student_id %in% rows$student_id) %>%
      transmute(student_id, arrived_term = as.integer(term), entry_type) %>%
      arrange(student_id, arrived_term, entry_type) %>%
      distinct(student_id, .keep_all = TRUE)
    # Counted on the chosen campuses, as the students kept are.
    on_campus <- unique(cedar_filter_campus(rows, opt$campus, "get_grouped_student_paths")$student_id)
    rows <- rows %>%
      inner_join(first_arrival, by = "student_id", relationship = "many-to-one") %>%
      filter(term >= arrived_term) %>%
      select(-arrived_term)
    n_no_arrival <- sum(!on_campus %in% rows$student_id)
    none_started <- !nrow(rows)
    keys <- c("campus", "entry_type")
  }
  # Clock precedes campus filtering: changing delivery campus cannot restart a path.
  rows <- assign_relative_terms(rows, include_summer = TRUE)
  first <- rows %>% distinct(student_id, term) %>% arrange(student_id, term) %>%
    distinct(student_id, .keep_all = TRUE) %>% transmute(student_id, first_term = term)
  rows <- cedar_filter_campus(rows, opt$campus, "get_grouped_student_paths") %>%
    filter(relative_term <= max_terms)
  if (!nrow(rows) && !none_started) stop("[grouped-student-paths.R] No course participation at the selected delivery campuses")
  n_left <- sum(first$student_id %in% rows$student_id &
                  first$first_term <= opt$data_edges$first_enrolled, na.rm = TRUE)
  # Retain campus in course keys. Repeated rows/CRNs do not multiply participation.
  rows <- rows %>% distinct(pick(all_of(c("student_id", "term", "relative_term", "campus", setdiff(keys, "campus"),
                                          "subject_course"))))
  rows <- attach_pathway_groups(rows, groups) %>%
    mutate(subject_code = sub(" .*", "", subject_course))
  term_keys <- c(keys, "relative_term")
  bands <- rows %>% group_by(pick(all_of(term_keys))) %>%
    summarize(n_eligible = n_distinct(student_id), .groups = "drop")
  counts <- rows %>% group_by(pick(all_of(c(term_keys, "group_id", "group_label")))) %>%
    summarize(n_students = n_distinct(student_id), n_courses = n_distinct(subject_course),
              n_subjects = n_distinct(subject_code), .groups = "drop")
  labels <- rows %>% distinct(group_id, group_label)
  cells <- merge(bands, labels, by = NULL) %>%
    left_join(counts, by = c(term_keys, "group_id", "group_label")) %>%
    mutate(n_students = coalesce(n_students, 0L), n_courses = coalesce(n_courses, 0L),
      n_subjects = coalesce(n_subjects, 0L),
      band_suppressed = n_eligible < min_band_n,
      cell_suppressed = n_students > 0 & n_students < min_n,
      suppressed = band_suppressed | cell_suppressed,
      pct_students = if_else(suppressed, NA_real_, 100 * n_students / n_eligible),
      n_students = if_else(suppressed, NA_integer_, n_students),
      n_courses = if_else(suppressed, NA_integer_, n_courses),
      n_subjects = if_else(suppressed, NA_integer_, n_subjects),
      n_eligible = if_else(band_suppressed, NA_integer_, n_eligible)) %>%
    tibble::as_tibble() %>%
    arrange(pick(all_of(keys)), group_label, relative_term)
  # A course, or a subject, past both small-cell guards: its share of the term's students.
  detail <- function(item) {
    rows %>% group_by(pick(all_of(c(term_keys, "group_id", "group_label", item)))) %>%
      summarize(n_students = n_distinct(student_id), .groups = "drop") %>%
      left_join(bands, by = term_keys) %>%
      filter(n_students >= min_n, n_eligible >= min_band_n) %>%
      mutate(pct_students = 100 * n_students / n_eligible) %>%
      arrange(pick(all_of(c(term_keys, "group_label", item))))
  }
  by_entry <- if (is.null(arrivals)) NULL else
    vapply(c(first_time = "first_time", transfer = "transfer"),
           function(e) n_distinct(rows$student_id[rows$entry_type == e]), integer(1))
  list(cells = cells, courses = detail("subject_course"), subjects = detail("subject_code"), groups = labels,
       meta = list(n_population = nrow(population), n_observed = n_distinct(rows$student_id),
         n_observed_by_entry = by_entry, n_no_arrival = n_no_arrival, split_entry = !is.null(arrivals),
         n_left_boundary = n_left, n_unmapped_rows = sum(rows$group_id == "unmapped"),
         n_course_rows = nrow(rows), n_suppressed = sum(cells$suppressed),
         analysis_through = edge, min_n = min_n, min_band_n = min_band_n, max_terms = max_terms))
}
