# declaration-context.R — Credits and prior coursework at first declaration
#
# Answers one question: where were students, academically and in coursework,
# at the moment they first declared the focal program?
#
# Split out of R/cones/major-changes.R, where it had accreted alongside the
# major-change analyses. It does not use major-change detection at all.
#
# Depends on: build_credit_timeline() (branches/credit-timeline.R),
#             term_diff() (trunk/utils.R)

# Credit position entering the declaration term, on the same basis and from the
# same source as the major-change figures, so the two are comparable.
.attach_declaration_credits <- function(first_decl, term_credits, programs) {
  if (is.null(term_credits) || nrow(first_decl) == 0) {
    if (is.null(term_credits)) {
      message("[declaration-context.R] No term_credits supplied — declaration credit ",
              "columns will be NA.")
    }
    first_decl$inst_credits    <- NA_real_
    first_decl$overall_credits <- NA_real_
    first_decl$credits_position_valid <- NA
    return(first_decl)
  }

  timeline <- build_credit_timeline(
    term_credits, programs,
    opt = list(student_ids = unique(first_decl$student_id))
  )
  first_decl %>%
    dplyr::left_join(
      timeline %>% dplyr::select(
        student_id, decl_term = term,
        inst_credits    = unm_credits_entering,
        overall_credits = total_credits_entering,
        credits_position_valid = timeline_valid),
      by = c("student_id", "decl_term")
    )
}


# ── Declaration context ───────────────────────────────────────────────────────

#' Snapshot of credits and prior course history at the moment students first
#' declared the focal program
#'
#' @param programs   cedar_programs filtered to population students
#' @param students   cedar_students (full, will be filtered internally)
#' @param population Population tibble from build_population() — needs
#'   first_unm_term for terms-to-declaration calculation
#' @param focal_subjects Character vector of subject codes that belong to the
#'   focal unit (e.g. c("HIST") for a History population). Used to split
#'   prior courses into in-unit vs outside.
#' @param opt        Options list; uses opt$min_n (default 5)
#' @return Named list: credits (summary tibble), courses_focal, courses_other,
#'   n_declarers, focal_subjects
get_declaration_context <- function(programs, students, population,
                                    focal_subjects = character(0),
                                    opt = list(), term_credits = NULL) {
  min_n <- opt$min_n %||% 5L

  focal_ids <- unique(population$student_id)

  # First declared term per student: earliest term as a non-pre-major Major
  first_decl <- programs %>%
    filter(student_id %in% focal_ids,
           program_type %in% c("Major", "Second Major"),
           !is_pre_major) %>%
    group_by(student_id) %>%
    slice_min(term, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(student_id, decl_term = term)

  # Credit position entering the declaration term. Sourced from the class-list
  # series rather than the cumulative columns beside decl_term on `programs`,
  # which are stamped at the pull and would report the student's total today.
  # See the field reliability contract in AGENTS.md.
  first_decl <- .attach_declaration_credits(first_decl, term_credits, programs)

  if (nrow(first_decl) == 0) {
    message("[declaration-context.R] get_declaration_context: no declared students found.")
    return(NULL)
  }

  n_declarers <- nrow(first_decl)
  message("[declaration-context.R] get_declaration_context: ", n_declarers, " declarers.")

  # Terms from first UNM enrollment to declaration
  if ("first_unm_term" %in% names(population)) {
    first_decl <- first_decl %>%
      left_join(population %>% select(student_id, first_unm_term),
                by = "student_id") %>%
      mutate(terms_to_decl = term_diff(first_unm_term, decl_term, include_summer = FALSE))
  }

  # Join pipeline classification from population (origin + entry_method + entry_status)
  pop_cols <- intersect(c("origin", "entry_method", "entry_status"), names(population))
  if (length(pop_cols) > 0) {
    first_decl <- first_decl %>%
      left_join(population %>% select(student_id, all_of(pop_cols)), by = "student_id") %>%
      mutate(pipeline = case_when(
        origin       == "transfer"      ~ "Transfer",
        entry_method == "switched_in"   ~ "Switched in (UNM)",
        entry_method == "first_program" ~ "Direct entry (UNM)",
        entry_method == "unclear"       ~ "Unclear",
        TRUE                            ~ "Other"
      ),
      entry_status_label = case_when(
        entry_status == "pre_major" ~ "First seen as pre-major",
        entry_status == "major" ~ "First seen as full major",
        TRUE ~ "First status unknown"
      ))
  }

  # Credit and terms summary
  credits <- first_decl %>%
    summarize(
      n               = n(),
      mean_inst       = round(mean(inst_credits,    na.rm = TRUE), 1),
      median_inst     = median(inst_credits,    na.rm = TRUE),
      mean_overall    = round(mean(overall_credits, na.rm = TRUE), 1),
      median_overall  = median(overall_credits, na.rm = TRUE),
      mean_terms      = if ("terms_to_decl" %in% names(.))
                          round(mean(terms_to_decl, na.rm = TRUE), 1) else NA_real_,
      median_terms    = if ("terms_to_decl" %in% names(.))
                          median(terms_to_decl, na.rm = TRUE) else NA_real_
    )

  # Pipeline breakdown: n, avg/med UNM credits, avg/med total credits, avg terms to declaration
  pipeline_summary <- if ("pipeline" %in% names(first_decl)) {
    first_decl %>%
      group_by(pipeline, entry_status_label) %>%
      summarize(
        n               = n(),
        mean_inst       = round(mean(inst_credits,      na.rm = TRUE), 0),
        median_inst     = round(median(inst_credits,    na.rm = TRUE), 0),
        mean_overall    = round(mean(overall_credits,   na.rm = TRUE), 0),
        median_overall  = round(median(overall_credits, na.rm = TRUE), 0),
        mean_terms      = if ("terms_to_decl" %in% names(.))
                            round(mean(terms_to_decl, na.rm = TRUE), 1) else NA_real_,
        .groups         = "drop"
      ) %>%
      arrange(desc(n))
  } else NULL

  # All courses taken in terms <= first declaration term
  prior_courses <- students %>%
    inner_join(first_decl %>% select(student_id, decl_term),
               by = "student_id") %>%
    filter(term <= decl_term,
           registration_status_code %in% STATUS_REGISTERED) %>%
    # CAMPUS_ROLLUP: prior curriculum history counts each student-course once,
    # regardless of where the course was delivered.
    dedup_enrollment(level = "course", group_campus = FALSE) %>%
    mutate(subject_code = sub(" .*", "", subject_course),
           in_unit      = subject_code %in% focal_subjects)

  make_counts <- function(df) {
    df %>%
      count(subject_course, course_title, name = "n_students", sort = TRUE) %>%
      filter(n_students >= min_n) %>%
      mutate(pct = round(n_students / n_declarers, 3)) %>%
      head(50)
  }

  list(
    credits          = credits,
    pipeline_summary = pipeline_summary,
    courses_focal    = make_counts(filter(prior_courses, in_unit)),
    courses_other    = make_counts(filter(prior_courses, !in_unit)),
    n_declarers      = n_declarers
  )
}
