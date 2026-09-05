# Entirely invented source records, not sampled or de-identified people.
# This reusable demo fixture is intentionally separate from unit fixtures:
# it needs a complete multi-year app world, with a stable 2026 current term.
# The production transforms, not this file, derive CEDAR analytical tables.
build_demo_sources <- function() {
  terms <- c(202310L, 202380L, 202410L, 202480L,
             202510L, 202580L, 202610L, 202660L, 202680L)
  catalog <- tibble::tribble(
    ~SUBJ, ~CRSE, ~SECT_TITLE, ~COLLEGE, ~n_registered,
    "HIST", "1110", "Survey of History", "AS", 24L,
    "HIST", "300", "Historical Methods", "AS", 18L,
    "MATH", "1215", "Intermediate Algebra", "AS", 28L,
    "MATH", "375", "Numerical Computing", "AS", 20L,
    "CS", "375", "Numerical Computing", "EN", 10L,
    "CS", "151", "Introduction to Computing", "EN", 22L,
    "ENGL", "1120", "Composition II", "AS", 26L
  )
  sections <- tidyr::crossing(TERM = terms, course_index = seq_len(nrow(catalog))) %>%
    left_join(mutate(catalog, course_index = row_number()), by = "course_index") %>%
    mutate(
      CRN = as.character(10000L + course_index), SECT = "001", PT = "1",
      CAMP = "ABQ", STATUS = "A", INST_METHOD = "Face to Face",
      PRIM_INST_ID = paste0("DEMO-FAC-", SUBJ),
      PRIM_INST_FIRST = "Synthetic", PRIM_INST_LAST = paste(SUBJ, "Instructor"),
      ENROLLED = n_registered, XL_ENRL = if_else(CRSE == "375", 30L, 0L),
      SECT_CAP = if_else(CRSE == "375", 35L, 40L), ROOM_CAP = SECT_CAP,
      SEATS_AVAIL = SECT_CAP - pmax(ENROLLED, XL_ENRL),
      XL_CODE = if_else(CRSE == "375", "D1", "0"),
      XL_SUBJ = case_when(SUBJ == "MATH" & CRSE == "375" ~ "CS",
                         SUBJ == "CS" & CRSE == "375" ~ "MATH", TRUE ~ ""),
      SHORT_TEXT = if_else(CRSE == "375", paste("MATH home", TERM), NA_character_),
      MIN_CR = 3, MAX_CR = 3, WAIT_COUNT = 2L, WAIT_CAPACITY = 10L,
      START_DATE = case_when(TERM %% 100L == 10L ~ paste0(TERM %/% 100L, "-01-15"),
                            TERM %% 100L == 60L ~ paste0(TERM %/% 100L, "-06-15"),
                            TRUE ~ paste0(TERM %/% 100L, "-08-15")),
      END_DATE = as.Date(START_DATE) + 100L,
      CENSUS1 = as.Date(START_DATE) + 14L,
      # Current registration is settled past census but ordinary grades have
      # not posted. This allows the two current late drops to be realistic.
      as_of_date = if_else(TERM == 202680L, as.Date("2026-09-01"), END_DATE + 30L)
    )

  # Every offering has n_registered + 1 late drop + 1 early drop + 2 WL rows.
  # MATH 375 IDs 1..24 and CS 375 IDs 41..54 never overlap, so crosslist
  # current = 20 + 10 = 30; reconstructed census = 21 + 11 = 32.
  roster <- sections %>%
    tidyr::uncount(n_registered + 4L, .id = "person") %>%
    mutate(
      person_id = person + if_else(SUBJ == "CS", 40L, 0L),
      student = sprintf("DEMO-STUDENT-%03d", person_id),
      status_code = case_when(person <= ENROLLED ~ "RE",
                              person == ENROLLED + 1L ~ "DW",
                              person == ENROLLED + 2L ~ "DR", TRUE ~ "WL"),
      grade = case_when(status_code == "DW" ~ "W",
                       status_code != "RE" | TERM == 202680L ~ NA_character_,
                       person %% 6L == 0L ~ "F", person %% 3L == 0L ~ "B", TRUE ~ "A"),
      major_code = c("HIST", "MATH", "CS", "ENGL")[(person_id - 1L) %% 4L + 1L],
      major_name = c(HIST = "History", MATH = "Mathematics",
                     CS = "Computer Science", ENGL = "English")[major_code],
      classification = c("Freshman", "Sophomore", "Junior", "Senior")[
        pmin(4L, (match(TERM, terms) + 1L) %/% 2L)],
      # Different new cohorts permit both graduates and continuing students.
      student = if_else(person <= 6L & TERM >= 202610L,
                        paste0(student, "-NEW"), student)
    )
  class_lists <- roster %>% transmute(
    `Academic Period Code` = TERM, `Course Reference Number` = CRN,
    `Student ID` = student, `Subject Code` = SUBJ, `Course Number` = CRSE,
    `Short Course Title` = SECT_TITLE, `Primary Instructor ID` = PRIM_INST_ID,
    `Primary Instructor Last Name` = PRIM_INST_LAST,
    `Primary Instructor First Name` = PRIM_INST_FIRST,
    `Course Campus Code` = CAMP, `Course College Code` = COLLEGE,
    `Registration Status Code` = status_code,
    `Registration Status` = case_when(status_code == "RE" ~ "Student Registered",
                                     status_code == "WL" ~ "Wait Listed",
                                     TRUE ~ "Dropped"),
    `Final Grade` = grade, `Course Credits` = 3, `Total Credits` = 12,
    `Student Level Code` = "UG", `Student Classification` = classification,
    `Major Code` = unname(major_code), Major = unname(major_name),
    `Student College Code` = if_else(major_code == "CS", "EN", "AS"),
    `Student Campus Code` = "ABQ", `Sub-Academic Period Code` = PT,
    Residency = "Resident", `Dual Credit` = "N", as_of_date
  )
  programs <- roster %>% distinct(student, TERM, .keep_all = TRUE) %>% transmute(
    ID = student, term_code = as.character(TERM),
    `Program Classification` = "Baccalaureate",
    Degree = if_else(major_code %in% c("CS", "MATH"), "Bachelor of Science", "Bachelor of Arts"),
    `Student Classification` = classification, `Student Level` = "Undergraduate",
    `Student Campus` = "Main", `Translated College` = if_else(major_code == "CS", "Engineering", "Arts and Sciences"),
    `Actual College` = if_else(major_code == "CS", "School of Engineering", "College of Arts and Sciences"),
    `Student Population` = if_else(TERM == 202310L, "First Time Freshman", "Continuing"),
    `Major Code` = unname(major_code), Major = unname(major_name),
    `Program Code` = paste0(if_else(major_code %in% c("CS", "MATH"), "BS", "BA"),
                          "-", major_code, if_else(major_code == "CS", "-EN", "-AS")),
    # Deliberately frozen pull-time totals; never used as historical positions.
    `Institution Credits Attempted` = 90, `Institution Credits Earned` = 81,
    `Overall Credits Attempted` = 120, `Overall Credits Earned` = 111,
    `Semester Credits Attempted` = 12, `Semester Credits Earned` = 9,
    `Semester GPA` = 3, `Institution GPA` = 3,
    `Pell Eligible Indicator` = if_else(person_id %% 2L == 0L, "Y", "N"),
    `First Generation Indicator` = if_else(person_id %% 3L == 0L, "Yes", "No"),
    `IPEDS Race` = NA_character_, Gender = NA_character_,
    `Current Time Status Code` = "FT", Residency = "Resident",
    `Academic Standing` = "Good Standing", as_of_date
  )
  degrees <- programs %>% filter(term_code == "202580", grepl("00[1-6]$", ID)) %>%
    transmute(ID, `Academic Period Code` = as.integer(term_code), Degree,
      `Actual College`, `Translated College`, `Program Code`, Program = Major,
      Department = `Major Code`, `Major Code`, Major,
      `Graduation Status` = "Awarded", Campus = "ABQ",
      `Award Category` = "Baccalaureate", `Cumulative GPA` = 3,
      `Cumulative Credits Earned` = 120, `Academic Period Admitted` = "202310",
      as_of_date)
  faculty <- sections %>% distinct(TERM, SUBJ, .keep_all = TRUE) %>% transmute(
    `UNM ID` = PRIM_INST_ID, term_code = as.character(TERM),
    Name = paste(PRIM_INST_LAST, PRIM_INST_FIRST, sep = ", "), DEPT = SUBJ,
    `Academic Title` = "Associate Professor", `Job Title` = "Associate Professor",
    job_cat = "Associate Professor", `Appt %` = 100,
    `Home Organization Desc` = if_else(SUBJ == "CS", "School of Engineering", "College of Arts and Sciences"),
    as_of_date
  )
  applicants <- programs %>% distinct(ID, .keep_all = TRUE) %>% transmute(
    ID, `Academic Period Code` = as.integer(term_code),
    as_of_date, `High School GPA` = 3.5
  )
  # The sections parser expects its date strings in source-report format.
  sections <- sections %>% mutate(
    START_DATE = format(as.Date(START_DATE), "%m/%d/%Y"),
    END_DATE = format(END_DATE, "%m/%d/%Y")) %>%
    select(-course_index)
  list(DESRs = sections, class_lists = class_lists, academic_studies = programs,
       degrees = degrees, hr_data = faculty, admissions_applicants = applicants)
}
