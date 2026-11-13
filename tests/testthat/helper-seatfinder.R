# What the tests in test-seatfinder.R share: builders, option lists, constants.

prepare_term_courses <- function(sections, start_term, end_term) {
  cols <- SEATFINDER_COURSE_KEYS

  start_courses <- sections %>%
    filter(term == start_term, status == "A") %>%
    select(all_of(cols)) %>%
    distinct()

  end_courses <- sections %>%
    filter(term == end_term, status == "A") %>%
    select(all_of(cols)) %>%
    distinct()

  list(start = start_courses, end = end_courses)
}

# Helper to prepare enrollment summary from known_sections
# Uses CEDAR column names: available (not avail as input)
prepare_enrl_summary <- function(sections, terms) {
  sections %>%
    filter(term %in% terms, status == "A") %>%
    # Use 'available' column from fixture, rename to 'avail' for seatfinder output format
    select(campus, college, term, part_term, subject_course, course_title,
           gen_ed_area, enrolled, capacity, avail = available)
}

with_seatfinder_test_terms <- function(expr) {
  had_current_term <- exists("cedar_current_term", envir = .GlobalEnv, inherits = FALSE)
  old_current_term <- if (had_current_term) get("cedar_current_term", envir = .GlobalEnv) else NULL
  old_report_end_term <- cedar_report_end_term

  cedar_current_term <<- 202680L
  cedar_report_end_term <<- 202580L

  on.exit({
    if (had_current_term) {
      cedar_current_term <<- old_current_term
    } else if (exists("cedar_current_term", envir = .GlobalEnv, inherits = FALSE)) {
      rm("cedar_current_term", envir = .GlobalEnv)
    }
    cedar_report_end_term <<- old_report_end_term
  }, add = TRUE)

  eval.parent(substitute(expr))
}

# The class list seatfinder's grade tests read: five attempts in every active
# section (seatfinder_grade_pattern), described from the section's own row.
seatfinder_students_for <- function(sections) {
  active_sections <- sections %>%
    filter(status == "A") %>%
    mutate(.section_row = row_number())

  attempts <- active_sections[rep(seq_len(nrow(active_sections)), each = 5), ] %>%
    group_by(.section_row) %>%
    mutate(.attempt = row_number()) %>%
    ungroup()

  students <- attempts %>%
    left_join(seatfinder_grade_pattern, by = ".attempt") %>%
    transmute(
      enrollment_id = paste0("SF-ENR-", section_id, "-", .attempt),
      section_id,
      student_id = paste0("SF-STU-", section_id, "-", .attempt),
      term,
      subject_course,
      campus,
      college,
      department,
      registration_status_code,
      final_grade,
      credits = credits_min,
      term_type,
      student_level = if_else(level == "grad", "Graduate", "Undergraduate"),
      crn,
      subject_code = subject,
      course_title,
      level,
      instructor_id,
      instructor_last_name = sub(",.*$", "", instructor_name),
      instructor_first_name = sub("^.*,\\s*", "", instructor_name),
      instructor_name,
      registration_status = if_else(registration_status_code == "DW",
                                    "Late Drop", "Student Registered"),
      registration_date = start_date,
      total_credits = credits_min,
      student_classification = student_level,
      major_code = department,
      student_college = college,
      student_campus = campus,
      residency = "Resident",
      dual_credit = FALSE,
      part_term,
      as_of_date
    )

  bind_rows(test_students[0, ], students)
}
