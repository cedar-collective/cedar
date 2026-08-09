# Shared Gen Ed analytics for Explore and Dept Trends views.

gen_ed_course_lookup <- function() {
  # CAMPUS_ROLLUP: this is the campus-neutral catalog membership lookup.
  dplyr::bind_rows(
    tibble::tibble(subject_course = gen_ed_1_communication, area = 1L, area_label = "1: Communication"),
    tibble::tibble(subject_course = gen_ed_2_math_stat,     area = 2L, area_label = "2: Math & Stat"),
    tibble::tibble(subject_course = gen_ed_3_phys_nat_sci,  area = 3L, area_label = "3: Phys/Nat Sci"),
    tibble::tibble(subject_course = gen_ed_4_soc_behav_sci, area = 4L, area_label = "4: Soc/Behav Sci"),
    tibble::tibble(subject_course = gen_ed_5_humanities,    area = 5L, area_label = "5: Humanities"),
    tibble::tibble(subject_course = gen_ed_7_arts_design,   area = 7L, area_label = "7: Arts & Design")
  ) %>%
    # CAMPUS_ROLLUP: de-duplicate the campus-neutral catalog lookup.
    dplyr::distinct(subject_course, .keep_all = TRUE)
}


filter_gen_ed_scope <- function(data, opt = list()) {
  campus <- opt$campus %||% NULL
  terms  <- opt$terms %||% opt$term %||% NULL
  area   <- opt$gen_ed_area %||% NULL
  college <- opt$college %||% NULL
  dept   <- opt$dept_code %||% NULL
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


gen_ed_modality_label <- function(campus) {
  campus <- as.character(campus)
  dplyr::case_when(
    campus == "ABQ" ~ "F2F / ABQ",
    campus == "EA" ~ "Online / EA",
    is.na(campus) | campus == "" ~ "Unknown",
    TRUE ~ paste0("Other / ", campus)
  )
}


top_gen_ed_courses <- function(enrl_by_course, top_n = 12L) {
  if (is.null(enrl_by_course) || nrow(enrl_by_course) == 0) return(character())

  totals <- enrl_by_course %>%
    # CAMPUS_ROLLUP: ranking chooses which course names to show; the plotted
    # series below remain separate by delivery campus.
    dplyr::group_by(subject_course) %>%
    dplyr::summarize(total = sum(enrl, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(total), subject_course)

  if (is.null(top_n) || identical(top_n, Inf)) {
    return(totals$subject_course)
  }

  top_n <- suppressWarnings(as.integer(top_n))
  if (length(top_n) == 0 || is.na(top_n) || top_n < 1L) return(character())
  utils::head(totals$subject_course, top_n)
}


plot_gen_ed_course_modality_trends <- function(enrl_by_course_modality, top_n = 12L) {
  courses <- top_gen_ed_courses(enrl_by_course_modality, top_n = top_n)
  ebc <- enrl_by_course_modality %>%
    dplyr::filter(subject_course %in% .env$courses) %>%
    dplyr::mutate(
      subject_course = factor(subject_course, levels = courses),
      modality = factor(
        modality,
        levels = unique(c("F2F / ABQ", "Online / EA", sort(unique(as.character(modality)))))
      )
    ) %>%
    dplyr::arrange(subject_course, modality, term)

  chrono <- unique(ebc$term_label[order(ebc$term)])
  course_colors <- build_color_map(courses)
  dash_map <- c("F2F / ABQ" = "solid", "Online / EA" = "dot")
  p <- plot_ly()

  for (course in courses) {
    for (mode in levels(ebc$modality)) {
      trace_data <- ebc %>%
        dplyr::filter(subject_course == .env$course, modality == .env$mode)
      if (nrow(trace_data) == 0) next

      trace_color <- unname(course_colors[[course]])
      trace_dash <- unname(dash_map[mode])
      if (is.na(trace_dash)) trace_dash <- "dash"

      p <- p %>%
        add_trace(
          data = trace_data,
          x = ~term_label,
          y = ~enrl,
          type = "scatter",
          mode = "lines+markers",
          name = paste(course, mode, sep = " - "),
          legendgroup = course,
          line = list(
            color = trace_color,
            width = 1.6,
            dash = trace_dash
          ),
          marker = list(size = 4, color = trace_color),
          hovertemplate = paste(
            paste(course, mode, sep = " - "),
            "%{x}: %{y}<extra></extra>",
            sep = "<br>"
          )
        )
    }
  }

  p %>%
    layout(
      xaxis = list(title = "", tickangle = -45, categoryorder = "array", categoryarray = chrono),
      yaxis = list(title = "Enrollment"),
      legend = list(orientation = "v", x = 1.02, y = 1),
      margin = list(t = 20, b = 70, l = 50, r = 160)
    )
}


get_gen_ed_profile <- function(students, sections, programs, degrees = NULL, opt = list()) {
  min_n <- suppressWarnings(as.integer(opt$min_n %||% 5L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 5L
  include_associations <- isTRUE(opt$include_associations %||% TRUE)
  include_instructor_dfw <- isTRUE(opt$include_instructor_dfw %||% FALSE)
  association_group_cols <- opt$association_group_cols %||%
    c("campus", "department", "subject_course")

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
    dplyr::mutate(term_label = term_code_to_axis_label(term))

  enrl_by_modality <- ge_sections %>%
    dplyr::filter(!is.na(term)) %>%
    dplyr::mutate(
      modality = gen_ed_modality_label(campus),
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
    dplyr::mutate(term_label = term_code_to_axis_label(term))

  enrl_by_course_modality <- ge_sections %>%
    dplyr::filter(!is.na(term)) %>%
    dplyr::mutate(modality = gen_ed_modality_label(campus)) %>%
    dplyr::group_by(term, campus, department, subject_course, course_title,
                    gen_ed_area, gen_ed_area_label, modality) %>%
    dplyr::summarize(enrl = sum(enrolled, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(term, department, subject_course, modality) %>%
    dplyr::mutate(term_label = term_code_to_axis_label(term))

  enrl_by_dept <- ge_sections %>%
    dplyr::group_by(department) %>%
    dplyr::summarize(
      n_courses = dplyr::n_distinct(subject_course),
      n_sections = dplyr::n(),
      total_enrl = sum(enrolled, na.rm = TRUE),
      avg_section_enrl = round(total_enrl / n_sections, 1),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(total_enrl))

  outcome_opt <- opt
  outcome_opt$course <- ge_courses

  # Campus is a grouping key, not just a filter. A course taught in ABQ and
  # online through EA is two different delivery contexts, and the default Gen Ed
  # scope covers both, so a single blended DFW rate hides the gap a chair is
  # looking for. Every downstream join below is keyed on campus to match.
  outcome_rates <- get_course_outcome_rates(
    students, outcome_opt,
    group_cols = c("campus", "department", "subject_course"),
    min_n = min_n
  )

  if (nrow(outcome_rates) == 0) {
    dfw_by_course <- tibble::tibble(
      campus = character(),
      department = character(),
      subject_course = character(),
      n_enrolled = integer(),
      n_dfw = integer(),
      dfw_rate = numeric(),
      dfw_pct_display = numeric(),
      n_c_minus = integer(),
      n_d = integer(),
      n_f = integer(),
      n_w = integer(),
      n_early_drop = integer(),
      early_drop_pct = numeric(),
      c_minus_pct = numeric(),
      d_pct = numeric(),
      f_pct = numeric(),
      w_pct = numeric(),
      below_c_no_w_pct = numeric()
    )
  } else {
    dfw_by_course <- outcome_rates %>%
      dplyr::transmute(
        campus,
        department,
        subject_course,
        n_enrolled = n_attempts,
        n_dfw,
        dfw_rate = dfw_pct / 100,
        # Same number as dfw_rate on a 0-100 scale, so the table can show it in
        # the same units as below_c_no_w_pct / w_pct — DFW % is the sum of those
        # two, and a unit mismatch between adjacent columns invites arithmetic
        # errors. dfw_rate (0-1) is kept for existing consumers.
        dfw_pct_display = round(dfw_pct, 2),
        n_c_minus,
        n_d,
        n_f,
        n_w,
        n_early_drop,
        early_drop_pct = dplyr::if_else(
          n_attempts + n_early_drop > 0,
          round(100 * n_early_drop / (n_attempts + n_early_drop), 2),
          NA_real_
        ),
        c_minus_pct = dplyr::if_else(n_attempts > 0, round(100 * n_c_minus / n_attempts, 2), NA_real_),
        d_pct = dplyr::if_else(n_attempts > 0, round(100 * n_d / n_attempts, 2), NA_real_),
        f_pct = dplyr::if_else(n_attempts > 0, round(100 * n_f / n_attempts, 2), NA_real_),
        w_pct,
        below_c_no_w_pct = dplyr::if_else(
          n_attempts > 0,
          round(100 * (n_c_minus + n_d + n_f + n_other_nonpassing) / n_attempts, 2),
          NA_real_
        )
      ) %>%
      dplyr::arrange(dplyr::desc(n_dfw), dplyr::desc(dfw_rate))
  }

  # Grouped by campus for the same reason as dfw_by_course above, and so the two
  # tables sit on one page with rows that line up.
  grade_dist <- get_grade_distribution(
    students, outcome_opt,
    group_cols = c("campus", "department", "subject_course"),
    min_n = min_n
  )

  major_mix <- get_course_major_mix(
    ge_students,
    programs,
    opt = list(min_n = min_n, top_n = opt$major_mix_top_n %||% 10L)
  )

  instructor_dfw <- NULL
  if (include_instructor_dfw) {
    instructor_rates <- get_course_outcome_rates(
      students, outcome_opt,
      group_cols = c("campus", "department", "subject_course", "instructor_name"),
      min_n = min_n
    )

    if (nrow(instructor_rates) == 0) {
      instructor_dfw <- tibble::tibble(
        campus = character(),
        department = character(),
        subject_course = character(),
        instructor_name = character(),
        n_attempts = integer(),
        n_dfw = integer(),
        dfw_rate = numeric(),
        dfw_pct_display = numeric(),
        course_dfw_rate = numeric(),
        course_dfw_pct_display = numeric(),
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
        below_c_no_w_pct = numeric(),
        early_drop_pct = numeric(),
        # n_terms was absent from this shape while the populated branch has
        # always produced it. The old renderer dropped unknown column defs
        # silently, so the mismatch never surfaced.
        n_terms = integer()
      )
    } else {
      # Keyed on campus so an instructor is compared against the course rate for
      # the campus they actually taught on, not a blended one.
      course_rates <- dfw_by_course %>%
        dplyr::select(campus, department, subject_course, course_dfw_rate = dfw_rate)

      instructor_terms <- prepare_course_attempts(students, outcome_opt) %>%
        dplyr::filter(!is.na(instructor_name), instructor_name != "") %>%
        dplyr::group_by(campus, department, subject_course, instructor_name) %>%
        dplyr::summarize(n_terms = dplyr::n_distinct(term), .groups = "drop")

      instructor_dfw <- instructor_rates %>%
        dplyr::filter(!is.na(instructor_name), instructor_name != "") %>%
        dplyr::left_join(course_rates, by = c("campus", "department", "subject_course")) %>%
        dplyr::left_join(instructor_terms,
                         by = c("campus", "department", "subject_course", "instructor_name")) %>%
        dplyr::transmute(
          campus,
          department,
          subject_course,
          instructor_name,
          n_attempts,
          n_dfw,
          dfw_rate = dfw_pct / 100,
          course_dfw_rate,
          # 0-100 twins of the two rates above, so every percentage this table
          # displays is on one scale and DFW % can be read against
          # Below C % + W %. The 0-1 forms are kept for existing consumers.
          dfw_pct_display = round(dfw_pct, 1),
          course_dfw_pct_display = round(100 * course_dfw_rate, 1),
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
          below_c_no_w_pct = dplyr::if_else(
            n_attempts > 0,
            round(100 * (n_c_minus + n_d + n_f + n_other_nonpassing) / n_attempts, 1),
            NA_real_
          ),
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
  total_ge_sections <- nrow(ge_sections)
  avg_ge_section_enrl <- if (total_ge_sections > 0) {
    round(total_ge_enrl / total_ge_sections, 1)
  } else {
    NA_real_
  }
  # Headline and per-department DFW come from their own unfiltered rate table
  # rather than from summing dfw_by_course. That table applies the small-cell
  # guard to every campus/course row, which is right for a published table but
  # would drop those students out of the totals as a side effect — and it would
  # make a headline number move whenever the table's grouping grain changed.
  # These totals aggregate thousands of students, where the guard protects
  # nothing.
  dept_outcome_rates <- get_course_outcome_rates(
    students, outcome_opt,
    group_cols = c("department"),
    min_n = 1L
  )

  overall_dfw <- if (nrow(dept_outcome_rates) > 0 &&
                     sum(dept_outcome_rates$n_attempts, na.rm = TRUE) > 0) {
    round(100 * sum(dept_outcome_rates$n_dfw, na.rm = TRUE) /
            sum(dept_outcome_rates$n_attempts, na.rm = TRUE), 1)
  } else {
    NA_real_
  }

  # Per-department version of the headline summary, so the UI can show one card
  # row per selected department alongside the overall row. Same metrics, same
  # definitions — each is recomputed within the department rather than
  # apportioned, so a department's DFW is its own students, not a share of the
  # total. `n_departments` is omitted (always 1 per row); `n_sections` takes its
  # place in the card row.
  students_by_dept <- ge_students %>%
    dplyr::filter(!is.na(department), nzchar(as.character(department))) %>%
    dplyr::group_by(department) %>%
    dplyr::summarize(n_students = dplyr::n_distinct(student_id), .groups = "drop")

  dfw_by_dept <- if (nrow(dept_outcome_rates) > 0) {
    dept_outcome_rates %>%
      dplyr::transmute(
        department,
        overall_dfw = dplyr::if_else(
          n_attempts > 0, round(100 * n_dfw / n_attempts, 1), NA_real_
        )
      )
  } else {
    tibble::tibble(department = character(), overall_dfw = numeric())
  }

  summary_by_dept <- enrl_by_dept %>%
    dplyr::left_join(students_by_dept, by = "department") %>%
    dplyr::left_join(dfw_by_dept, by = "department") %>%
    dplyr::mutate(n_students = dplyr::coalesce(n_students, 0L)) %>%
    dplyr::arrange(dplyr::desc(total_enrl))

  list(
    summary = tibble::tibble(
      n_courses = dplyr::n_distinct(ge_sections$subject_course),
      n_departments = dplyr::n_distinct(ge_sections$department),
      n_students = dplyr::n_distinct(ge_students$student_id),
      total_enrl = total_ge_enrl,
      n_sections = total_ge_sections,
      avg_section_enrl = avg_ge_section_enrl,
      registered_enrollments = nrow(ge_students),
      overall_dfw = overall_dfw
    ),
    summary_by_dept = summary_by_dept,
    enrl_by_term = enrl_by_term,
    enrl_by_modality = enrl_by_modality,
    enrl_by_course_modality = enrl_by_course_modality,
    enrl_by_dept = enrl_by_dept,
    major_mix = major_mix,
    dfw_by_course = dfw_by_course,
    grade_dist = grade_dist,
    instructor_dfw = instructor_dfw,
    associations = associations,
    # CAMPUS_ROLLUP: picker metadata lists catalog courses once; every measured
    # course series in this payload remains grouped by delivery campus.
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


# ── Gen Ed among a department's graduates ────────────────────────────────────
#
# Everything above this line describes Gen Ed as a teaching load: which sections
# a department offers and who sits in them. This section asks the opposite
# question — what Gen Ed do the department's OWN majors take, and when in their
# degree do they take it?
#
# That flips the population from "students in our courses" to "students who
# finished our degree", which forces the sampling rule in R/cones/gen-ed-grads.R:
# only graduates whose entire UNM record is inside the data window can answer it.
# The cohort is therefore much smaller than the department's graduate count, and
# every consumer of this function is expected to say so on screen.


#' Gen Ed Profile for a Department's Graduates
#'
#' Orchestrates the readable-graduate cohort, the Gen Ed course-timing heatmap,
#' and the Gen Ed uptake tables into one payload for Dept Trends > Gen Ed.
#'
#' Timing reuses [get_course_timing()] with the Gen Ed catalog as the course
#' filter, so the heatmap is the same calculation and the same
#' [plot_curriculum_map()] rendering as Pathways > Course Timing. It differs in
#' two deliberate ways: the population is fixed to department graduates rather
#' than user-selected, and the x-axis is `unm_credit_band` rather than the
#' program-record credit fields — see the `term_credits` docs in
#' `R/cones/pathway.R` for why those fields cannot answer this question.
#'
#' Enrollment rows are capped at each student's graduation term before timing
#' runs, so a graduate who kept taking courses afterward does not contribute
#' post-degree Gen Ed to the map.
#'
#' @param students Data frame. The `cedar_students` table.
#' @param degrees Data frame. The `cedar_degrees` table.
#' @param term_credits Data frame. The `cedar_student_term_credits` table.
#' @param opt List of options:
#'   \describe{
#'     \item{`dept_code`}{Character. Required.}
#'     \item{`campus`}{Character vector of course-delivery campus codes.}
#'     \item{`degree_abbr`, `major_code`}{Optional degree/program narrowing,
#'       passed through to [get_gen_ed_grad_cohort()].}
#'     \item{`min_n`}{Integer. Minimum cohort students per course for the course
#'       to appear in the uptake table, and per CELL for a tile to be drawn on
#'       the timing map. Default `3`.}
#'     \item{`x_axis`}{Character. `"relative_term"` (default) positions courses
#'       by how far into the student's time at UNM they were;
#'       `"unm_credit_band"` positions by UNM credits completed entering the
#'       term. `"overall_credit_band"` is rejected — see the note in the body.}
#'     \item{`min_band_n`}{Deprecated and ignored. It guarded the far end of the
#'       axis while `pct_pop` divided by per-band eligibility; the population
#'       denominator makes that guard unnecessary and, worse, made it hide real
#'       enrollment. Accepted so existing callers do not break.}
#'   }
#'
#' @return Named list with two parallel scopes over one cohort:
#'   \describe{
#'     \item{all Gen Ed}{`timing` (a [get_course_timing()] frame carrying its
#'       `x_axis` attribute), `by_course`, `summary`.}
#'     \item{the unit's own Gen Ed}{`timing_dept`, `by_course_dept`,
#'       `summary_dept` — the same three, restricted to Gen Ed the graduates'
#'       own department teaches.}
#'   }
#'   Plus `cohort_meta` and `n_cohort`, which describe the shared cohort and so
#'   belong to neither scope. When the cohort is empty every table is present but
#'   zero-row, so callers render an explanation rather than branching on NULL.
get_gen_ed_grad_profile <- function(students, degrees, term_credits, opt = list()) {

  min_n <- suppressWarnings(as.integer(opt$min_n %||% 3L))
  if (length(min_n) == 0 || is.na(min_n) || min_n < 1L) min_n <- 3L

  # Only these two. overall_credit_band is excluded on purpose — its source
  # totals are frozen per program record rather than per term, so it would look
  # like a well-populated axis while carrying no timing signal. The rationale
  # and the measurements are in R/modules/gen-ed.R next to GRAD_GEN_ED_AXES.
  x_axis <- match.arg(opt$x_axis %||% "relative_term",
                      c("relative_term", "unm_credit_band"))

  gen_ed_lu <- gen_ed_course_lookup()

  cohort <- get_gen_ed_grad_cohort(students, degrees, opt = list(
    dept_code   = opt$dept_code,
    degree_abbr = opt$degree_abbr %||% NULL,
    major_code  = opt$major_code %||% NULL
  ))
  cohort_meta <- attr(cohort, "cohort_meta")

  uptake <- get_gen_ed_grad_uptake(students, cohort, gen_ed_lu, opt = list(
    campus    = opt$campus %||% NULL,
    dept_code = opt$dept_code,
    min_n     = min_n
  ))

  if (nrow(cohort) == 0) {
    return(list(
      cohort_meta    = cohort_meta,
      timing         = tibble::tibble(),
      by_course      = uptake$by_course,
      summary        = uptake$summary,
      by_entry       = uptake$by_entry,
      timing_dept    = tibble::tibble(),
      by_course_dept = uptake$by_course,
      summary_dept   = uptake$summary_dept,
      n_cohort       = 0L,
      timing_guards  = list(
        min_n = min_n, x_axis = x_axis, denominator = "population",
        n_cohort = 0L, dropped_bands = integer(),
        band_eligible = tibble::tibble(relative_term = integer(),
                                       n_eligible = integer())
      )
    ))
  }

  # Cap each graduate's enrollment rows at their graduation term before timing.
  # get_course_timing() has no concept of a per-student ceiling, so it has to be
  # applied here — the same job relevant_until does for Pathways populations.
  students_pop <- students %>%
    dplyr::inner_join(dplyr::distinct(cohort, student_id, grad_term),
                      by = "student_id") %>%
    dplyr::filter(term <= grad_term) %>%
    dplyr::select(-grad_term)

  # min_n = 1 here, then the course set is taken from by_course below. Not
  # redundant: get_course_timing()'s own min_n sums n_students across every
  # (campus, band) cell, so on a cohort this small a course one student took in
  # three different cells clears a threshold of three. by_course counts distinct
  # students per course, which is what "taken by at least N graduates" means, and
  # using it for both keeps the heatmap and the table showing the same courses.
  # No start_classification filter on the relative_term axis, and that is a
  # deliberate departure from how Pathways uses it. Pathways has to force a
  # Freshman start because a student already enrolled when the data opens looks
  # like a first-semester student. This cohort cannot contain such a student:
  # get_gen_ed_grad_cohort() requires a first enrollment strictly after the
  # window opened, so relative term 1 is their real first term by construction.
  timing <- get_course_timing(
    students_pop,
    dplyr::select(cohort, student_id, population_label),
    opt = list(
      x_axis            = x_axis,
      subject_course    = gen_ed_lu$subject_course,
      campus            = opt$campus %||% NULL,
      group_campus      = FALSE,
      max_relative_term = opt$max_relative_term %||% 10L,
      # Share of the WHOLE counted cohort, not of the students who reached each
      # position. See the denominator note in get_course_timing() — under the
      # conditional denominator the far end of the axis was unreadable, because
      # eligibility there is a handful of students and one of them reports 25%.
      denominator       = "population",
      min_n             = 1L
    ),
    term_credits = term_credits
  )

  # Both scopes are cut from this one timing frame rather than computed by a
  # second get_course_timing() run, and the two are equivalent — not merely
  # close. get_course_timing() builds n_eligible BEFORE applying its course
  # filter (its Step 4 comment says why), so the denominator at each credit band
  # is the whole cohort regardless of which courses are in scope. n_students and
  # median_term are per course and cannot move either. Narrowing the course list
  # therefore only removes rows. Pinned by a test.
  timing_meta <- attr(timing, "timing_meta")
  timing_x    <- attr(timing, "x_axis")
  keep_attrs <- function(d) {
    attr(d, "x_axis")      <- timing_x
    attr(d, "timing_meta") <- timing_meta
    d
  }

  # ── No per-cell or per-band suppression ────────────────────────────────────
  # Both guards existed to stop the conditional denominator inflating a lone
  # student into a bold percentage — one student over the four who reached the
  # top credit band read as 25%. Dividing by the whole cohort removes the cause:
  # that student is now 1%, which is what they are, and every cell in the grid
  # is on the same scale.
  #
  # Suppressing them anyway would be the worse error, and was: on History, real
  # Gen Ed enrollment above 60 credits — 30 enrollments by 16 students at 61-90,
  # 10 by 6 at 91-120 — vanished entirely, because the largest single cell up
  # there is two students and the guard needed three. The chart showed nothing
  # where there was something, which is a stronger claim than it had any basis
  # for.
  #
  # The threshold that remains is at COURSE level, not cell level: a course needs
  # min_n distinct graduates overall to appear at all, which is the same rule the
  # table below uses. Once a course clears that bar, its whole distribution is
  # drawn rather than the parts of it that happen to be dense.
  band_eligibility <- timing %>%
    dplyr::distinct(relative_term, n_eligible)

  suppress <- function(d) keep_attrs(d)

  by_course_dept <- dplyr::filter(uptake$by_course, !is.na(is_dept_course),
                                  is_dept_course)

  timing_dept <- suppress(
    dplyr::filter(timing, subject_course %in% by_course_dept$subject_course))
  timing <- suppress(
    dplyr::filter(timing, subject_course %in% uptake$by_course$subject_course))

  list(
    cohort_meta    = cohort_meta,
    timing         = timing,
    by_course      = uptake$by_course,
    summary        = uptake$summary,
    by_entry       = uptake$by_entry,
    timing_dept    = timing_dept,
    by_course_dept = by_course_dept,
    summary_dept   = uptake$summary_dept,
    n_cohort       = nrow(cohort),
    # What the guards removed, so the page can say so instead of quietly
    # showing a shorter axis than the data has bands for.
    timing_guards  = list(
      min_n          = min_n,
      x_axis         = x_axis,
      denominator    = "population",
      n_cohort       = nrow(cohort),
      dropped_bands  = integer(),
      band_eligible  = dplyr::arrange(band_eligibility, relative_term)
    )
  )
}
