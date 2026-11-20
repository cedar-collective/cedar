# Pathways branch helpers
#
# Pure helpers for calculation-affecting Pathways module behavior. These keep
# Shiny modules focused on wiring while making result-shaping rules testable
# without loading UI packages.


#' Translate Pathways course-level UI choice to CEDAR level values
#'
#' @param level_choice Character scalar from a Pathways level selector.
#' @return Character vector for opt$level, or NULL for all levels.
#' @keywords internal
pathways_level_filter <- function(level_choice) {
  level_choice <- level_choice %||% "all"
  if (length(level_choice) == 0 || is.na(level_choice) ||
      identical(level_choice, "") || identical(level_choice, "all")) {
    return(NULL)
  }
  if (identical(level_choice, "undergrad")) return(c("lower", "upper"))
  level_choice
}


#' Latest term whose outcomes are fully observable
#'
#' Right-censoring guard shared by the Pathways analyses: an outcome measured
#' by "what happened in later terms" (returned next term, later took course B,
#' later entered the major) is only observable for records with enough
#' complete regular terms after them. Records after this boundary would all
#' look like non-returns / non-entries simply because the data ends.
#'
#' @param latest_complete_term Integer term code of the last complete data
#'   term (`cedar_report_end_term`, the settled edge from
#'   [cedar_report_edges()]).
#' @param follow_up_terms Integer. How many complete regular (fall/spring)
#'   terms of follow-up the analysis needs. 1 for next-term outcomes
#'   (stop-out), the A-to-B gap for course pairs, etc.
#' @return Integer term code: the latest term with full follow-up. NULL if
#'   latest_complete_term is NULL/NA.
#' @keywords internal
pathways_observation_boundary <- function(latest_complete_term,
                                          follow_up_terms = 1L) {
  if (is.null(latest_complete_term) || is.na(latest_complete_term)) return(NULL)
  boundary <- as.integer(latest_complete_term)
  for (i in seq_len(max(0L, as.integer(follow_up_terms)))) {
    boundary <- subtract_term(boundary)
  }
  boundary
}


#' Apply Pathways analysis term and population membership window
#'
#' @param data Data frame with student_id and term columns.
#' @param population Population data frame from build_population().
#' @param analysis_through Optional maximum term to include.
#' @param term_col Name of the term column in data.
#' @return data filtered to analysis_through and relevant_until.
#' @keywords internal
apply_pathways_population_window <- function(data, population = NULL,
                                             analysis_through = NULL,
                                             term_col = "term") {
  if (is.null(data) || nrow(data) == 0) return(data)
  if (!term_col %in% names(data))
    stop("[pathways.R] data missing term column: ", term_col)

  out <- data
  if (!is.null(analysis_through)) {
    out <- dplyr::filter(out, .data[[term_col]] <= analysis_through)
  }

  if (is.null(population) || nrow(population) == 0 ||
      !"relevant_until" %in% names(population)) {
    return(out)
  }
  if (!"student_id" %in% names(out))
    stop("[pathways.R] data missing student_id column.")

  bounded <- population %>%
    dplyr::filter(!is.na(relevant_until)) %>%
    dplyr::select(student_id, relevant_until)

  if (nrow(bounded) == 0) return(out)

  out %>%
    dplyr::left_join(bounded, by = "student_id") %>%
    dplyr::filter(is.na(relevant_until) | .data[[term_col]] <= relevant_until) %>%
    dplyr::select(-relevant_until)
}


#' Apply Pathways analysis population subgroup filters
#'
#' @param population Population data frame from build_population().
#' @param split_by Population split mode; "entry" excludes unclear entry rows.
#' @param selected_label Optional population_label selected in the status bar.
#' @return Filtered population.
#' @keywords internal
filter_pathways_analysis_population <- function(population, split_by = "none",
                                                selected_label = "all") {
  if (is.null(population)) return(NULL)
  pop <- population

  if (identical(split_by, "entry") && "entry_method" %in% names(pop)) {
    pop <- dplyr::filter(pop, entry_method != "unclear")
  }

  selected_label <- selected_label %||% "all"
  if (length(selected_label) == 0 || identical(selected_label, "") ||
      identical(selected_label, "all") ||
      !"population_label" %in% names(pop) ||
      !selected_label %in% pop$population_label) {
    return(pop)
  }

  pop[pop$population_label == selected_label, , drop = FALSE]
}


#' Resolve focal program names for a Pathways population option
#'
#' The names the population's focal codes carry in cedar_programs, for the
#' analyses that compare a student's majors by name (Major Changes). The codes
#' come from resolve_focal_programs(), the population's own resolution, so a
#' renamed program's old name and its pre-majors' names are focal too.
#'
#' @param population_opt Option list used to build the population.
#' @param programs cedar_programs.
#' @param pop_programs Optional cedar_programs already filtered to population IDs.
#' @return Character vector of program names.
#' @keywords internal
resolve_pathways_focal_programs <- function(population_opt, programs,
                                            pop_programs = NULL) {
  population_type <- population_opt$type %||% "preset"

  if (population_type %in% c("major", "preset", "dept")) {
    codes <- resolve_focal_programs(programs, population_opt)$codes$program_code
    return(programs %>%
      dplyr::filter(program_type %in% c("Major", "Second Major"),
                    major_code %in% codes, !is.na(program_name)) %>%
      dplyr::distinct(program_name) %>%
      dplyr::pull(program_name))
  }

  # Demographic populations have no single focal program. Use all primary
  # majors observed among population members.
  if (is.null(pop_programs)) return(character(0))
  pop_programs %>%
    dplyr::filter(program_type == "Major") %>%
    dplyr::distinct(program_name) %>%
    dplyr::pull(program_name)
}


#' Resolve focal department codes for a Pathways population option
#'
#' @param population_opt Option list used to build the population.
#' @param programs cedar_programs.
#' @param pop_programs Optional cedar_programs already filtered to population IDs.
#' @return Character vector of dept_code values: the units of the focal
#'   declared codes (resolve_focal_programs()), or the department itself.
#' @keywords internal
resolve_pathways_focal_dept_codes <- function(population_opt, programs,
                                              pop_programs = NULL) {
  population_type <- population_opt$type %||% "preset"

  dept_codes <- if (identical(population_type, "dept")) {
    population_opt$dept_code %||% character(0)
  } else if (population_type %in% c("major", "preset")) {
    focal <- resolve_focal_programs(programs, population_opt)$codes
    declared <- focal$program_code[focal$role != "pre_major"]
    programs %>%
      dplyr::filter(
        program_type %in% c("Major", "Second Major"),
        major_code %in% declared,
        !is_pre_major
      ) %>%
      dplyr::pull(dept_code)
  } else if (!is.null(pop_programs)) {
    pop_programs %>%
      dplyr::filter(program_type == "Major", !is_pre_major) %>%
      dplyr::pull(dept_code)
  } else {
    character(0)
  }

  unique(stats::na.omit(dept_codes))
}


#' Resolve focal course subject prefixes for Pathways analyses
#'
#' @param population_opt Option list used to build the population.
#' @param programs cedar_programs.
#' @param dims The dimension tables (build_cedar_dims()); the subjects each
#'   unit teaches are read off them through subject_units().
#' @param pop_programs Optional cedar_programs already filtered to population IDs.
#' @return Character vector of subject_code values.
#' @keywords internal
resolve_pathways_focal_subjects <- function(population_opt, programs,
                                            dims,
                                            pop_programs = NULL) {
  dept_codes <- resolve_pathways_focal_dept_codes(
    population_opt, programs, pop_programs = pop_programs
  )
  if (length(dept_codes) == 0) return(character(0))

  subject_units(dims) %>%
    dplyr::filter(dept_code %in% dept_codes) %>%
    dplyr::pull(subject_code) %>%
    unique() %>%
    stats::na.omit()
}


#' Resolve department gen ed courses from focal subject prefixes
#'
#' @param focal_subjects Character vector of subject prefixes.
#' @param gen_ed_courses Character vector of gen ed subject_course codes.
#' @return Character vector of gen ed subject_course values.
#' @keywords internal
resolve_pathways_gen_ed_courses <- function(focal_subjects,
                                            gen_ed_courses = unlist(gen_ed_all)) {
  if (length(focal_subjects) == 0 || length(gen_ed_courses) == 0)
    return(character(0))

  gen_ed_courses[sub(" .*", "", gen_ed_courses) %in% focal_subjects]
}


#' Summarise what the data window can and cannot see about a population
#'
#' Pathways answers questions about student trajectories, and a trajectory is
#' only readable if its start and end are both inside the data. For a typical
#' department population neither holds for a large minority: measured on the
#' shared data, 41-44% of students were already enrolled in the first term CEDAR
#' has, and 27-39% are still enrolled in the last one.
#'
#' Those two facts bound every timing claim on the tab, and neither is visible
#' from the outcome counts — a left-truncated student looks like a first-semester
#' freshman, and a right-censored one looks like a continuing student. This
#' returns the counts so the page can state them rather than leaving the reader
#' to assume full coverage.
#'
#' @param population Data frame from `build_population()`. Uses `first_unm_term`
#'   and `last_record_term` when present.
#' @param min_data_term,max_data_term Integer term codes bounding the data.
#'
#' @return Named list: `n`, `n_truncated`, `pct_truncated`, `n_censored`,
#'   `pct_censored`, `n_complete` (students whose whole record is inside the
#'   window), `pct_complete`, plus the two boundary terms. Counts are NA when the
#'   population lacks the bookend columns, so callers can omit the note rather
#'   than print a confident zero.
#' @keywords internal
pathways_coverage_facts <- function(population, min_data_term, max_data_term) {
  n <- nrow(population)
  na_result <- list(
    n = n, n_truncated = NA_integer_, pct_truncated = NA_real_,
    n_censored = NA_integer_, pct_censored = NA_real_,
    n_complete = NA_integer_, pct_complete = NA_real_,
    min_data_term = min_data_term, max_data_term = max_data_term
  )
  if (n == 0) return(na_result)

  has_first <- "first_unm_term"   %in% names(population)
  has_last  <- "last_record_term" %in% names(population)
  if (!has_first && !has_last) return(na_result)

  # <= not <, deliberately. A student whose first record IS the first data term
  # may have started then or years earlier; the data cannot distinguish the two,
  # so they count as unreadable rather than as a clean start.
  truncated <- if (has_first) {
    !is.na(population$first_unm_term) & population$first_unm_term <= min_data_term
  } else rep(NA, n)
  censored <- if (has_last) {
    !is.na(population$last_record_term) & population$last_record_term >= max_data_term
  } else rep(NA, n)

  pct <- function(x) if (all(is.na(x))) NA_real_ else round(100 * mean(x, na.rm = TRUE))
  complete <- if (has_first && has_last) !truncated & !censored else rep(NA, n)

  list(
    n             = n,
    n_truncated   = if (has_first) sum(truncated, na.rm = TRUE) else NA_integer_,
    pct_truncated = pct(truncated),
    n_censored    = if (has_last) sum(censored, na.rm = TRUE) else NA_integer_,
    pct_censored  = pct(censored),
    n_complete    = if (has_first && has_last) sum(complete, na.rm = TRUE) else NA_integer_,
    pct_complete  = pct(complete),
    min_data_term = min_data_term,
    max_data_term = max_data_term
  )
}


#' Latest term whose grades are actually posted
#'
#' Thin wrapper over [cedar_data_edges()]'s `last_graded`. The shared helper is
#' the canonical one — see the right-edge policy in AGENTS.md — and this exists
#' so Pathways callers read in their own vocabulary.
#'
#' @inheritParams cedar_data_edges
#' @return Integer term code, or NULL when no term clears the threshold.
#' @keywords internal
latest_graded_term <- function(students, min_graded_share = 0.5, max_term = NULL) {
  if (is.null(students) || nrow(students) == 0) return(NULL)
  cedar_data_edges(students, min_graded_share = min_graded_share,
                   max_term = max_term)$last_graded
}


#' The Pathways population selector's Majors and Department choices
#'
#' Majors: one choice per program, valued by its program id (program_id_of():
#' a renamed program's newest code) and labelled with its programs.csv name
#' and every code it covers, so a program renamed in code_history.csv is one
#' choice ("Liberal Arts & Integrative Studies (LAIS, LIBA)") and two programs
#' that share a Banner name are two ("Architecture (ARCH)", "Architecture
#' (ARCT)"). Only codes declared as a major in cedar_programs are offered; a
#' pre-major joins its program through leads_to when the population is built.
#' A code programs.csv has no row for is offered as "[no programs.csv row]
#' (CODE)", never named after itself.
#' Departments: the units owning a declared major, named from units.csv.
#'
#' @param programs cedar_programs.
#' @param dims The dimension tables (build_cedar_dims()).
#' @param successions The confirmed program renames (default
#'   `program_successions`, from code_history.csv).
#' @return list(program_choices, dept_choices): named character vectors, label
#'   to value, in label order.
pathways_population_choice_lists <- function(programs, dims,
                                             successions = program_successions) {
  validate_cedar_dims(dims)
  required <- c("program_type", "major_code", "is_pre_major", "dept_code")
  missing <- setdiff(required, names(programs))
  if (length(missing))
    stop("[pathways.R] pathways_population_choice_lists: programs lacks ",
         paste(missing, collapse = ", "))

  rows <- programs[programs$program_type %in% c("Major", "Second Major"), , drop = FALSE]
  declared <- rows$major_code[!rows$is_pre_major]
  # Labelled with each program's degrees, campuses and years, so programs that
  # share a name can be told apart. First majors only: a second major's row
  # carries the student's primary program's degree.
  program_choices <- program_choices(declared, dims, successions,
                                     profile = rows[!rows$is_pre_major & rows$program_type == "Major", , drop = FALSE])

  depts <- sort(unique(stats::na.omit(rows$dept_code[!rows$is_pre_major])))
  depts <- depts[nzchar(depts)]
  units <- unit_names(dims)
  dept_names <- units$dept_name[match(depts, units$dept_code)]
  if (anyNA(dept_names))
    stop("[pathways.R] pathways_population_choice_lists: units.csv names no unit ",
         paste(depts[is.na(dept_names)], collapse = ", "),
         "; validate_mapping_files() should have refused programs.csv")
  dept_choices <- stats::setNames(depts, dept_names)[order(dept_names)]

  list(program_choices = program_choices, dept_choices = dept_choices)
}


#' The program codes a Pathways population counted, for its scope bar
#'
#' Every code build_population() matched, why it is in, its programs.csv name
#' and how many of the population's students hold it; and the code_history.csv
#' renames that joined codes. A page shows these as facts, so a reader can see
#' that "Liberal Arts" counted LAIS, LIBA and their pre-majors.
#'
#' @param population build_population() output, with attr(, "focal_programs").
#' @param programs cedar_programs.
#' @param dims The dimension tables (build_cedar_dims()).
#' @return NULL for a population with no focal programs (a demographic one);
#'   else list(codes, successions). `codes`: program_code, program_name, role
#'   ("selected", "succession", "pre_major"), leads_to, n_students.
#'   `successions`: from_code, to_code, effective_term.
pathways_focal_program_facts <- function(population, programs, dims) {
  focal <- attr(population, "focal_programs")
  if (is.null(focal)) return(NULL)
  validate_cedar_dims(dims)
  codes <- focal$codes
  held <- programs %>%
    dplyr::filter(program_type %in% c("Major", "Second Major"),
                  major_code %in% codes$program_code,
                  student_id %in% population$student_id) %>%
    dplyr::distinct(major_code, student_id) %>%
    dplyr::count(major_code, name = "n_students")
  names_of <- name_program_codes(codes$program_code, dims)
  codes <- codes %>%
    dplyr::mutate(program_name = unname(names_of[program_code])) %>%
    dplyr::left_join(held, by = c(program_code = "major_code")) %>%
    dplyr::mutate(n_students = dplyr::coalesce(n_students, 0L)) %>%
    dplyr::select(program_code, program_name, role, leads_to, n_students)
  list(codes = codes, successions = focal$successions)
}
