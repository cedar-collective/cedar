# gened-fulfillment.R — Cone for Gen Ed Fulfillment by Department Graduates
#
# For students who graduated with a degree from a given department, shows how many
# gen ed courses they took at UNM (by area), and how many of those courses were from
# the department itself vs. from other units.
#
# Data limitations:
#   CEDAR enrollment data starts ~2019. Students who graduated before Spring 2023
#   (term 202310) may be missing early-career enrollments. Set min_grad_term to
#   control which cohorts are included; default is Spring 2023 to ensure 4 full years
#   of enrollment history are present for most students.
#
# Requires: gen_ed_* vectors from gen_ed_courses.R (loaded via load-funcs.R)
#

#The logic:
#Grads: find all students in cedar_degrees where department == dept_code and term >= min_grad_term, keeping their latest graduation term
#Enrollments: join those students to cedar_students, filter to term <= grad_term + campuses, then inner-join to the gen ed lookup (course → area)
#Dedup: distinct(student_id, subject_course, area, department) — each course counted once per student regardless of retakes
#Classify: department == dept_code → "Dept Gen Ed" vs "Other Gen Ed"
#Aggregate: n / n_grads gives average distinct courses per graduate per area
#One thing to watch: cedar_degrees.department — does it match the dept_code format (e.g., "HIST") or is it the verbose Banner string (e.g., "AS History")? If it's verbose, you may need to use prgm_to_dept_map[program_code] instead. Worth checking on first run

# EXAMPLE USAGE:
#make_gened_fulfillment(cedar_students, cedar_degrees, "HIST")
#make_gened_fulfillment(cedar_students, cedar_degrees, "ANTH", degree_abbr = "BA")
#make_gened_fulfillment(cedar_students, cedar_degrees, "ANTH", degree_abbr = "BS")
#make_gened_fulfillment(cedar_students, cedar_degrees, "PHYS", program_code = "ASTR")  # astrophysics only
#make_gened_fulfillment(cedar_students, cedar_degrees, "GES",  min_grad_term = 202410L)


#' Plot gen ed fulfillment for a department's graduates
#'
#' @param students     cedar_students data frame
#' @param degrees      cedar_degrees data frame
#' @param dept_code    Department code (e.g., "HIST", "GES")
#' @param degree_abbr  Optional degree filter (e.g., "BA", "BS"). NULL = all degrees.
#'   Useful when a dept offers both BA and BS to compare gen ed patterns by degree type.
#' @param program_code Optional program filter matching program_catalog$program_code
#'   (e.g., "ASTR" within dept "PHYS"). NULL = all programs in the dept.
#'   Useful when a dept contains distinct programs that have different gen ed patterns.
#' @param min_grad_term Earliest graduation term to include (default 202310 = Spring 2023).
#'   Students who graduated before this term may have incomplete enrollment histories.
#' @param campuses     Campus codes to include; NULL = all campuses
#' @param return_data  If TRUE, return a list of intermediate data frames instead of the plot.
#'   Useful for debugging: list contains $grads, $gen_ed_enrls, $plot_df.
#' @return ggplot stacked bar chart, or list of data frames if return_data = TRUE
make_gened_fulfillment <- function(students, degrees, dept_code,
                                   degree_abbr   = NULL,
                                   program_code  = NULL,
                                   min_grad_term = 202310L,
                                   campuses      = c("ABQ", "EA"),
                                   return_data   = FALSE) {

  # ── Gen ed course → area lookup ────────────────────────────────────────────
  gen_ed_lu <- bind_rows(
    tibble(subject_course = gen_ed_1_communication, area = "1: Communication"),
    tibble(subject_course = gen_ed_2_math_stat,     area = "2: Math & Stat"),
    tibble(subject_course = gen_ed_3_phys_nat_sci,  area = "3: Phys/Nat Sci"),
    tibble(subject_course = gen_ed_4_soc_behav_sci, area = "4: Soc/Behav Sci"),
    tibble(subject_course = gen_ed_5_humanities,    area = "5: Humanities"),
    tibble(subject_course = gen_ed_7_arts_design,   area = "7: Arts & Design")
  ) %>%
    distinct(subject_course, .keep_all = TRUE)   # courses listed in multiple areas kept once

  area_levels <- c("1: Communication", "2: Math & Stat", "3: Phys/Nat Sci",
                   "4: Soc/Behav Sci", "5: Humanities",  "7: Arts & Design")

  # ── Graduates of this dept at or after min_grad_term ──────────────────────
  # cedar_degrees$dept_code is set during transform (same lookup as cedar_programs).
  # Filter to "Awarded" only — excludes Pending, Hold, and Record Clear rows.
  grads <- degrees %>%
    filter(
      dept_code == .env$dept_code,
      graduation_status == "Awarded",
      term >= min_grad_term,
      if (!is.null(.env$degree_abbr))  degree_abbr == .env$degree_abbr  else TRUE,
      if (!is.null(.env$program_code)) program_code == .env$program_code else TRUE
    ) %>%
    group_by(student_id) %>%
    summarize(grad_term = max(term), .groups = "drop")

  if (nrow(grads) == 0) {
    warning("No graduates found for dept_code = ", dept_code, " from term ", min_grad_term)
    return(ggplot2::ggplot() +
             ggplot2::labs(title = paste("No graduates found for", dept_code)))
  }

  n_grads_total <- nrow(grads)

  # ── Gen ed enrollments for those graduates, up to their graduation term ───
  # Only grads who appear in cedar_students at all — those who enrolled before
  # CEDAR data starts (~2019) have no records and cannot be meaningfully analyzed.
  gen_ed_enrls <- students %>%
    inner_join(grads, by = "student_id") %>%
    filter(
      term <= grad_term,
      if (!is.null(campuses)) campus %in% campuses else TRUE
    ) %>%
    inner_join(gen_ed_lu, by = "subject_course") %>%
    mutate(
      course_type = if_else(department == dept_code, "Dept Gen Ed", "Other Gen Ed")
    ) %>%
    distinct(student_id, subject_course, area, course_type)

  # Denominator = graduates who have ANY enrollment record in cedar_students
  # (not all graduates — those who enrolled before data starts are excluded)
  n_grads_with_records <- students %>%
    filter(student_id %in% grads$student_id) %>%
    distinct(student_id) %>%
    nrow()

  n_grads <- n_grads_with_records

  if (n_grads == 0) {
    warning("No graduates with enrollment records found for dept_code = ", dept_code)
    return(ggplot2::ggplot() +
             ggplot2::labs(title = paste("No enrollment records found for", dept_code, "graduates")))
  }

  plot_df <- gen_ed_enrls %>%
    mutate(
      area        = factor(area, levels = area_levels),
      course_type = factor(course_type, levels = c("Dept Gen Ed", "Other Gen Ed"))
    ) %>%
    count(area, course_type) %>%
    mutate(avg_courses = n / n_grads)

  if (return_data) {
    return(list(
      grads              = grads,
      gen_ed_enrls       = gen_ed_enrls,
      plot_df            = plot_df,
      n_grads            = n_grads,
      n_grads_total      = n_grads_total,
      n_grads_no_records = n_grads_total - n_grads
    ))
  }

  # ── Plot ───────────────────────────────────────────────────────────────────
  ggplot2::ggplot(plot_df,
                  ggplot2::aes(x = area, y = avg_courses, fill = course_type)) +
    ggplot2::geom_col(width = 0.75) +
    ggplot2::scale_y_continuous(breaks = scales::breaks_width(0.5),
                                expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::scale_fill_manual(
      values = c("Dept Gen Ed" = "#0072B2", "Other Gen Ed" = "#BBBBBB")
    ) +
    ggplot2::labs(
      title    = paste("Gen Ed Courses Taken by",
                       if (!is.null(program_code)) program_code else dept_code,
                       if (!is.null(degree_abbr)) paste0("(", degree_abbr, ")") else NULL,
                       "Graduates"),
      subtitle = paste0("n = ", n_grads, " of ", n_grads_total, " graduates with UNM enrollment records",
                        " \u2022 terms ", fmt_term(min_grad_term), "\u2013present",
                        " \u2022 UNM enrollments only (excludes AP/IB/transfer credit)"),
      x        = NULL,
      y        = "Avg Gen Ed Courses per Graduate",
      fill     = NULL
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.x     = ggplot2::element_text(angle = 30, hjust = 1),
      legend.position = "top"
    )
}
