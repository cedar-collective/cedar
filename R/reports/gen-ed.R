# Shared Gen Ed analytics for Explore and Department Profile views.

gen_ed_course_lookup <- function() {
  dplyr::bind_rows(
    tibble::tibble(subject_course = gen_ed_1_communication, area = 1L, area_label = "1: Communication"),
    tibble::tibble(subject_course = gen_ed_2_math_stat,     area = 2L, area_label = "2: Math & Stat"),
    tibble::tibble(subject_course = gen_ed_3_phys_nat_sci,  area = 3L, area_label = "3: Phys/Nat Sci"),
    tibble::tibble(subject_course = gen_ed_4_soc_behav_sci, area = 4L, area_label = "4: Soc/Behav Sci"),
    tibble::tibble(subject_course = gen_ed_5_humanities,    area = 5L, area_label = "5: Humanities"),
    tibble::tibble(subject_course = gen_ed_7_arts_design,   area = 7L, area_label = "7: Arts & Design")
  ) %>%
    dplyr::distinct(subject_course, .keep_all = TRUE)
}


filter_gen_ed_scope <- function(data, opt = list()) {
  campus <- opt$campus %||% NULL
  terms  <- opt$terms %||% opt$term %||% NULL
  area   <- opt$gen_ed_area %||% NULL
  college <- opt$college %||% NULL
  dept   <- opt$dept %||% NULL
  level  <- opt$level %||% NULL

  data %>%
    {
      if (is.null(campus) || length(campus) == 0) .
      else dplyr::filter(., campus %in% .env$campus)
    } %>%
    {
      if (is.null(terms) || length(terms) == 0) .
      else dplyr::filter(., term %in% as.integer(.env$terms))
    } %>%
    {
      if (is.null(area) || length(area) == 0) .
      else dplyr::filter(., gen_ed_area %in% as.integer(.env$area))
    } %>%
    {
      if (is.null(college) || length(college) == 0 || !"college" %in% names(.)) .
      else dplyr::filter(., college %in% .env$college)
    } %>%
    {
      if (is.null(dept) || length(dept) == 0 || !"department" %in% names(.)) .
      else dplyr::filter(., department %in% .env$dept)
    } %>%
    {
      if (is.null(level) || length(level) == 0 || !"level" %in% names(.)) .
      else dplyr::filter(., level %in% .env$level)
    }
}


get_gen_ed_profile <- function(students, sections, programs, degrees = NULL, opt = list()) {
  min_n <- suppressWarnings(as.integer(opt$min_n %||% 5L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 5L
  include_associations <- isTRUE(opt$include_associations %||% TRUE)
  include_instructor_dfw <- isTRUE(opt$include_instructor_dfw %||% FALSE)
  association_group_cols <- opt$association_group_cols %||% c("department", "subject_course")

  gen_ed_lu <- gen_ed_course_lookup()

  ge_sections <- sections %>%
    dplyr::filter(subject_course %in% gen_ed_lu$subject_course) %>%
    dplyr::left_join(gen_ed_lu, by = "subject_course", suffix = c("", "_lookup")) %>%
    dplyr::mutate(
      gen_ed_area = dplyr::coalesce(as.integer(gen_ed_area), area),
      gen_ed_area_label = area_label
    ) %>%
    dplyr::filter(is.na(crosslist_primary) | crosslist_primary) %>%
    filter_gen_ed_scope(opt)

  ge_courses <- unique(ge_sections$subject_course)

  ge_students <- students %>%
    dplyr::filter(
      registration_status_code %in% STATUS_REGISTERED,
      subject_course %in% .env$ge_courses
    ) %>%
    dplyr::left_join(
      gen_ed_lu %>% dplyr::select(subject_course, area, area_label),
      by = "subject_course"
    ) %>%
    dplyr::mutate(
      gen_ed_area = area,
      gen_ed_area_label = area_label
    ) %>%
    filter_gen_ed_scope(opt)

  enrl_by_term <- ge_sections %>%
    dplyr::filter(!is.na(term)) %>%
    dplyr::group_by(term) %>%
    dplyr::summarize(
      n_sections = dplyr::n(),
      total_enrl = sum(enrolled, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(term) %>%
    dplyr::mutate(term_label = vapply(term, fmt_term, character(1)))

  enrl_by_modality <- ge_sections %>%
    dplyr::filter(!is.na(term)) %>%
    dplyr::mutate(
      modality = dplyr::if_else(campus == "EA", "Online", "F2F"),
      term_type = dplyr::case_when(
        term %% 100 == 10 ~ "Spring",
        term %% 100 == 60 ~ "Summer",
        term %% 100 == 80 ~ "Fall",
        TRUE ~ "Other"
      )
    ) %>%
    dplyr::group_by(term, term_type, modality) %>%
    dplyr::summarize(enrl = sum(enrolled, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(term) %>%
    dplyr::mutate(term_label = vapply(term, fmt_term, character(1)))

  enrl_by_course <- ge_sections %>%
    dplyr::filter(!is.na(term)) %>%
    dplyr::group_by(term, department, subject_course, course_title, gen_ed_area, gen_ed_area_label) %>%
    dplyr::summarize(enrl = sum(enrolled, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(term, department, subject_course) %>%
    dplyr::mutate(term_label = vapply(term, fmt_term, character(1)))

  enrl_by_dept <- ge_sections %>%
    dplyr::group_by(department) %>%
    dplyr::summarize(
      n_courses = dplyr::n_distinct(subject_course),
      total_enrl = sum(enrolled, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(total_enrl))

  outcome_opt <- opt
  outcome_opt$course <- ge_courses

  outcome_rates <- get_course_outcome_rates(
    students, outcome_opt,
    group_cols = c("department", "subject_course"),
    min_n = min_n
  )

  if (nrow(outcome_rates) == 0) {
    dfw_by_course <- tibble::tibble(
      department = character(),
      subject_course = character(),
      n_enrolled = integer(),
      n_dfw = integer(),
      dfw_rate = numeric(),
      n_c_minus = integer(),
      n_d = integer(),
      n_f = integer(),
      n_w = integer(),
      n_early_drop = integer(),
      w_pct = numeric(),
      df_pct = numeric(),
      below_c_pct = numeric()
    )
  } else {
    dfw_by_course <- outcome_rates %>%
      dplyr::transmute(
        department,
        subject_course,
        n_enrolled = n_attempts,
        n_dfw,
        dfw_rate = dfw_pct / 100,
        n_c_minus,
        n_d,
        n_f,
        n_w,
        n_early_drop,
        w_pct,
        df_pct,
        below_c_pct
      ) %>%
      dplyr::arrange(dplyr::desc(n_dfw), dplyr::desc(dfw_rate))
  }

  grade_dist <- get_grade_distribution(
    students, outcome_opt,
    group_cols = c("department", "subject_course"),
    min_n = min_n
  )

  instructor_dfw <- NULL
  if (include_instructor_dfw) {
    instructor_rates <- get_course_outcome_rates(
      students, outcome_opt,
      group_cols = c("department", "subject_course", "instructor_name"),
      min_n = min_n
    )

    if (nrow(instructor_rates) == 0) {
      instructor_dfw <- tibble::tibble(
        department = character(),
        subject_course = character(),
        instructor_name = character(),
        n_attempts = integer(),
        n_dfw = integer(),
        dfw_rate = numeric(),
        course_dfw_rate = numeric(),
        dfw_diff_pp = numeric(),
        n_c_minus = integer(),
        n_d = integer(),
        n_f = integer(),
        n_w = integer(),
        n_early_drop = integer(),
        c_minus_pct = numeric(),
        d_pct = numeric(),
        f_pct = numeric(),
        w_pct = numeric(),
        early_drop_pct = numeric()
      )
    } else {
      course_rates <- dfw_by_course %>%
        dplyr::select(department, subject_course, course_dfw_rate = dfw_rate)

      instructor_terms <- prepare_course_attempts(students, outcome_opt) %>%
        dplyr::filter(!is.na(instructor_name), instructor_name != "") %>%
        dplyr::group_by(department, subject_course, instructor_name) %>%
        dplyr::summarize(n_terms = dplyr::n_distinct(term), .groups = "drop")

      instructor_dfw <- instructor_rates %>%
        dplyr::filter(!is.na(instructor_name), instructor_name != "") %>%
        dplyr::left_join(course_rates, by = c("department", "subject_course")) %>%
        dplyr::left_join(instructor_terms, by = c("department", "subject_course", "instructor_name")) %>%
        dplyr::transmute(
          department,
          subject_course,
          instructor_name,
          n_attempts,
          n_dfw,
          dfw_rate = dfw_pct / 100,
          course_dfw_rate,
          dfw_diff_pp = round(dfw_pct - 100 * course_dfw_rate, 1),
          n_c_minus,
          n_d,
          n_f,
          n_w,
          n_early_drop,
          c_minus_pct = dplyr::if_else(n_attempts > 0, round(100 * n_c_minus / n_attempts, 1), NA_real_),
          d_pct = dplyr::if_else(n_attempts > 0, round(100 * n_d / n_attempts, 1), NA_real_),
          f_pct = dplyr::if_else(n_attempts > 0, round(100 * n_f / n_attempts, 1), NA_real_),
          w_pct = dplyr::if_else(n_attempts > 0, round(100 * n_w / n_attempts, 1), NA_real_),
          early_drop_pct = dplyr::if_else(
            n_attempts + n_early_drop > 0,
            round(100 * n_early_drop / (n_attempts + n_early_drop), 1),
            NA_real_
          ),
          n_terms = dplyr::coalesce(n_terms, 0L)
        ) %>%
        dplyr::arrange(dplyr::desc(n_attempts), dplyr::desc(dfw_rate), subject_course, instructor_name)
    }
  }

  associations <- NULL
  if (include_associations && nrow(ge_sections) > 0) {
    dept_subjects <- ge_sections %>%
      dplyr::filter(!is.na(department), !is.na(subject)) %>%
      dplyr::distinct(department, subject) %>%
      dplyr::group_by(department) %>%
      dplyr::summarize(subject_codes = list(unique(subject)), .groups = "drop")

    assoc_parts <- lapply(seq_len(nrow(dept_subjects)), function(i) {
      dept <- dept_subjects$department[[i]]
      subjects <- dept_subjects$subject_codes[[i]]
      dept_courses <- ge_sections %>%
        dplyr::filter(department == .env$dept) %>%
        dplyr::pull(subject_course) %>%
        unique()

      get_course_major_associations(
        students, programs,
        opt = list(
          subject_code = subjects,
          dept_codes = dept,
          gen_ed_only = TRUE,
          gen_ed_courses = dept_courses,
          terms = opt$terms %||% opt$term %||% NULL,
          min_n = min_n,
          campus = opt$campus %||% NULL,
          level = opt$level %||% NULL,
          group_cols = association_group_cols
        )
      )
    })

    associations <- dplyr::bind_rows(assoc_parts)
    if (nrow(dept_subjects) > 1 && !is.null(associations) && "pct_of_eligible" %in% names(associations)) {
      associations$pct_of_eligible <- NULL
    }
  }

  total_ge_enrl <- sum(ge_sections$enrolled, na.rm = TRUE)
  overall_dfw <- if (nrow(dfw_by_course) > 0 && sum(dfw_by_course$n_enrolled, na.rm = TRUE) > 0) {
    round(100 * sum(dfw_by_course$n_dfw, na.rm = TRUE) /
            sum(dfw_by_course$n_enrolled, na.rm = TRUE), 1)
  } else {
    NA_real_
  }

  list(
    summary = tibble::tibble(
      n_courses = dplyr::n_distinct(ge_sections$subject_course),
      n_departments = dplyr::n_distinct(ge_sections$department),
      n_students = dplyr::n_distinct(ge_students$student_id),
      total_enrl = total_ge_enrl,
      registered_enrollments = nrow(ge_students),
      overall_dfw = overall_dfw
    ),
    enrl_by_term = enrl_by_term,
    enrl_by_modality = enrl_by_modality,
    enrl_by_course = enrl_by_course,
    enrl_by_dept = enrl_by_dept,
    dfw_by_course = dfw_by_course,
    grade_dist = grade_dist,
    instructor_dfw = instructor_dfw,
    associations = associations,
    courses = ge_sections %>%
      dplyr::distinct(department, subject, subject_course, course_title, gen_ed_area, gen_ed_area_label) %>%
      dplyr::arrange(department, subject_course),
    metadata = list(
      filters = opt,
      min_n = min_n,
      association_group_cols = association_group_cols
    )
  )
}
