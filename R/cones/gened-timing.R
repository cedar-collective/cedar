# gened-timing.R — Cone for Gen Ed / Course Timing Heatmap
#
# Shows when (relative to academic career) majors in a dept take courses in that unit.
# Three x-axis modes tell different stories:
#
#   "classification" (default)
#       Freshman/Sophomore/Junior/Senior at time of enrollment.
#       Credit-hour based — correctly represents transfers.
#       Answers: "At what academic level do students take this course?"
#
#   "semester_index"
#       Semesters since the student first appears in CEDAR data (1 = first term).
#       Time-based — transfer students appear to take upper-div courses "early"
#       because their pre-UNM history isn't in the data.
#       Answers: "How many semesters after we first see them do students take this?"
#
#   "inst_credit_band"
#       UNM credits attempted at time of enrollment, binned into 30-credit bands.
#       Transfer credits NOT included — shows progression through UNM specifically.
#       Answers: "How far into their UNM career do students take this course?"
#
#   "overall_credit_band"
#       Total credits earned (UNM + transfer) at time of enrollment, binned into 30-credit bands.
#       Includes transfer credits — correctly places transfers in their academic career.
#       Compare with inst_credit_band to reveal transfer student behavior patterns.
#       Answers: "At what overall credit level do students take this course?"

# EXAMPLE USAGE:
#make_gened_timing_heatmap(students, "HIST")                                    # classification (default)
#make_gened_timing_heatmap(students, "HIST", x_axis = "semester_index")
#make_gened_timing_heatmap(students, "HIST", x_axis = "inst_credit_band",   programs = programs)
#make_gened_timing_heatmap(students, "HIST", x_axis = "overall_credit_band", programs = programs)

#
# Depends on: term_diff() from utils.R


#' Generate heatmap of course timing for a department's majors
#'
#' @param students   cedar_students data frame
#' @param dept_code  Department code (e.g., "HIST", "GES")
#' @param x_axis     One of "classification" (default), "semester_index", "inst_credit_band", "overall_credit_band"
#' @param programs   cedar_programs data frame — required for credit band modes
#' @param campuses   Campus codes to include; NULL = all campuses
#' @return ggplot heatmap
make_gened_timing_heatmap <- function(students, dept_code,
                                      x_axis   = "classification",
                                      programs = NULL,
                                      campuses = c("ABQ", "EA")) {

  x_axis <- match.arg(x_axis, c("classification", "semester_index", "inst_credit_band", "overall_credit_band"))

  # ── Students who ever declared a program in this dept ──────────────────────
  # major is a Banner program code (e.g., "GEOG", "GEOG-BA"); prgm_to_dept_map
  # translates it to a dept_code (e.g., "GES").
  ever_majors <- students %>%
    filter(prgm_to_dept_map[major] == dept_code) %>%
    distinct(student_id)

  # ── All lower+upper enrollments in this dept for those students ────────────
  course_enrls <- students %>%
    semi_join(ever_majors, by = "student_id") %>%
    filter(
      department == dept_code,
      level %in% c("lower", "upper"),
      if (!is.null(campuses)) campus %in% campuses else TRUE
    )

  # ── Derive x-axis variable ─────────────────────────────────────────────────
  if (x_axis == "classification") {

    course_enrls <- course_enrls %>%
      filter(!is.na(student_classification)) %>%
      mutate(
        x_val = case_when(
          startsWith(student_classification, "Freshman")  ~ "Freshman",
          startsWith(student_classification, "Sophomore") ~ "Sophomore",
          startsWith(student_classification, "Junior")    ~ "Junior",
          startsWith(student_classification, "Senior")    ~ "Senior",
          TRUE ~ NA_character_
        ),
        x_val = factor(x_val, levels = c("Freshman", "Sophomore", "Junior", "Senior"))
      ) %>%
      filter(!is.na(x_val))

    x_label <- "Student Classification at Time of Enrollment"

  } else if (x_axis == "semester_index") {

    entry_terms <- students %>%
      semi_join(ever_majors, by = "student_id") %>%
      group_by(student_id) %>%
      summarize(entry_term = min(term), .groups = "drop")

    course_enrls <- course_enrls %>%
      left_join(entry_terms, by = "student_id") %>%
      mutate(x_val = term_diff(entry_term, term) + 1L)

    x_label <- "Semesters Since First Appearance in Data (summers excluded)"

  } else {  # inst_credit_band or overall_credit_band

    if (is.null(programs)) {
      stop("Credit band modes require the programs argument (cedar_programs data frame).")
    }

    credit_col <- if (x_axis == "inst_credit_band") "inst_credits_attempted" else "overall_credits_earned"

    if (!credit_col %in% names(programs)) {
      stop("cedar_programs does not have a ", credit_col, " column. ",
           "Re-run transform-to-cedar.R to regenerate cedar_programs.qs.")
    }

    # One credit value per student per term; use only Major rows to avoid duplicates.
    credits_lu <- programs %>%
      dplyr::filter(program_type == "Major", !is.na(.data[[credit_col]])) %>%
      dplyr::distinct(student_id, term, .data[[credit_col]])

    course_enrls <- course_enrls %>%
      dplyr::left_join(credits_lu, by = c("student_id", "term")) %>%
      dplyr::filter(!is.na(.data[[credit_col]])) %>%
      dplyr::mutate(
        x_val = dplyr::case_when(
          .data[[credit_col]] <  31 ~ "0–30",
          .data[[credit_col]] <  61 ~ "31–60",
          .data[[credit_col]] <  91 ~ "61–90",
          .data[[credit_col]] < 121 ~ "91–120",
          TRUE                      ~ "121+"
        ),
        x_val = factor(x_val, levels = c("0–30", "31–60", "61–90", "91–120", "121+"))
      )

    x_label <- if (x_axis == "inst_credit_band")
      "Institution Credits Attempted at Time of Enrollment (UNM only)"
    else
      "Overall Credits Earned at Time of Enrollment (UNM + transfer)"
  }

  # ── Aggregate ──────────────────────────────────────────────────────────────
  heatmap_df <- course_enrls %>%
    dplyr::group_by(subject_course, level, x_val) %>%
    dplyr::summarize(count = dplyr::n(), .groups = "drop") %>%
    tidyr::complete(subject_course, x_val, fill = list(count = 0)) %>%
    dplyr::group_by(subject_course) %>%
    tidyr::fill(level, .direction = "downup") %>%
    dplyr::ungroup()

  # ── Y-axis order: upper-division at bottom, lower at top ──────────────────
  course_order <- heatmap_df %>%
    dplyr::distinct(subject_course, level) %>%
    dplyr::mutate(
      course_num = as.integer(sub("^[A-Z]+ ([0-9]+).*", "\\1", subject_course)),
      is_lower   = (level == "lower")
    ) %>%
    dplyr::arrange(is_lower, dplyr::desc(course_num)) %>%
    dplyr::pull(subject_course)

  heatmap_df <- heatmap_df %>%
    dplyr::mutate(subject_course = factor(subject_course, levels = course_order))

  # ── Plot ───────────────────────────────────────────────────────────────────
  x_scale <- if (x_axis == "semester_index") {
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(1))
  } else {
    ggplot2::scale_x_discrete()
  }

  ggplot2::ggplot(heatmap_df,
                  ggplot2::aes(x = x_val, y = subject_course, fill = count)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::scale_fill_gradient(low = "#f0f0f0", high = "#0072B2") +
    x_scale +
    ggplot2::labs(
      title = paste("Course Timing for", dept_code, "Majors"),
      x     = x_label,
      y     = "Course",
      fill  = "Enrollments"
    ) +
    ggplot2::theme_minimal()
}
