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

seatfinder_grade_students <- function(sections = test_sections_sf) {
  active_sections <- sections %>%
    filter(status == "A") %>%
    mutate(.section_row = row_number())

  attempts <- active_sections[rep(seq_len(nrow(active_sections)), each = 5), ] %>%
    group_by(.section_row) %>%
    mutate(.attempt = row_number()) %>%
    ungroup()

  grade_pattern <- tibble(
    .attempt = 1:5,
    registration_status_code = c("RE", "RE", "RE", "RE", "DW"),
    final_grade = c("A", "B", "D", "F", "W")
  )

  students <- attempts %>%
    left_join(grade_pattern, by = ".attempt") %>%
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

# seatfinder() reads the attempt measure table (ADR-001 step 7): the designed
# class list above, loaded and built as the transform builds it, to the test
# edges' graded edge.
seatfinder_grade_attempts <- function(students = seatfinder_grade_students()) {
  keyed_attempts(students, edges = seatfinder_test_edges)
}

seatfinder_topic_sections <- function() {
  start_base <- test_sections_sf %>%
    filter(term == 202410, subject_course == "HIST 1110") %>%
    slice(1)
  end_base <- test_sections_sf %>%
    filter(term == 202510, subject_course == "HIST 1110") %>%
    slice(1)

  bind_rows(
    start_base %>% mutate(
      section_id = "TOPIC-S1", crn = "49101", section = "001",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Algebra", college = "HC", department = "HNRS",
      enrolled = 10L, total_enrl = 10L, capacity = 18L, available = 8L,
      gen_ed_area = 5L
    ),
    start_base %>% mutate(
      section_id = "TOPIC-S2", crn = "49102", section = "002",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Comedy", college = "HC", department = "HNRS",
      enrolled = 12L, total_enrl = 12L, capacity = 18L, available = 6L,
      gen_ed_area = 5L
    ),
    end_base %>% mutate(
      section_id = "TOPIC-E1", crn = "59101", section = "001",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Algebra", college = "HC", department = "HNRS",
      enrolled = 11L, total_enrl = 11L, capacity = 18L, available = 7L,
      gen_ed_area = 5L
    ),
    end_base %>% mutate(
      section_id = "TOPIC-E2", crn = "59102", section = "002",
      subject = "HNRS", course_number = "1120", subject_course = "HNRS 1120",
      course_title = "Sem: Legacy of Comedy", college = "HC", department = "HNRS",
      enrolled = 13L, total_enrl = 13L, capacity = 18L, available = 5L,
      gen_ed_area = 5L
    )
  )
}

seatfinder_gen_ed_sections <- function() {
  sections <- test_sections_sf %>%
    mutate(gen_ed_area = case_when(
      subject_course %in% c("HIST 1110", "HIST 1120") ~ 5L,
      subject_course == "ANTH 1110" ~ 4L,
      TRUE ~ gen_ed_area
    ))

  likely_to_open <- sections %>%
    filter(section_id == "SF20002") %>%
    slice(1) %>%
    mutate(
      section_id = "SF-GE-LIKELY",
      crn = "59999",
      subject = "HIST",
      course_number = "1999",
      subject_course = "HIST 1999",
      section = "001",
      course_title = "Topics in Public History",
      college = "ARTS",
      department = "HIST",
      instructor_id = "INS001",
      instructor_name = "Morgan, Rachel",
      enrolled = 0L,
      total_enrl = 0L,
      capacity = 0L,
      available = 0L,
      status = "A",
      delivery_method = "ENH",
      level = "lower",
      gen_ed_area = 5L,
      comments = NA_character_
    )

  bind_rows(sections, likely_to_open)
}
