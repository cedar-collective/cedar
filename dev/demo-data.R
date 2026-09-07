# The synthetic institution is assembled from the existing analytical fixtures.
# No institutional records or independently authored demo population are used.
# Cohort 1 retains the original identities; additional cohorts copy whole histories.
build_demo_sources <- function(cohorts = 5L,
                               fixture_path = "tests/testthat/fixtures/designed_test_data.R") {
  if (length(cohorts) != 1L || is.na(cohorts) || cohorts < 1L ||
      cohorts != as.integer(cohorts) || cohorts > 20L) {
    stop("cohorts must be an integer from 1 to 20")
  }
  fixture <- new.env(parent = globalenv())
  sys.source(fixture_path, envir = fixture)
  # Deliberately corrupt ID/grade fixtures and stand-alone intermediate credit
  # tables remain unit-test inputs. They do not describe a complete institution.
  collect <- function(spec) {
    bind_rows(lapply(names(spec), function(name) {
      mutate(fixture[[spec[[name]]]], fixture_source = name)
    }))
  }
  sections <- collect(c(base = "cedar_sections", regstats = "cedar_sections_regstats",
    seatfinder = "cedar_sections_sf", topics = "cedar_sections_topics",
    gen_ed = "gen_ed_assoc_sections"))
  students <- collect(c(base = "cedar_students", regstats = "cedar_students_regstats",
    gen_ed = "gen_ed_assoc_students", campus = "cedar_students_mc",
    retention = "cedar_students_mcret", graduates = "cedar_students_gg",
    major_entry = "cedar_students_pcc"))
  programs <- collect(c(base = "cedar_programs", gen_ed = "gen_ed_assoc_programs",
    campus = "cedar_programs_mc", major_entry = "cedar_programs_pcc"))
  # EC-10 contains valid simultaneous declarations alongside deliberately
  # unidentifiable records. Include the valid people so the demo can exercise
  # major/minor intersections; preserve the malformed rows for unit tests only.
  concurrent <- fixture$cedar_programs_concurrent %>%
    filter(!is.na(student_id), nzchar(student_id), !is.na(term)) %>% distinct() %>%
    mutate(fixture_source = "concurrent_programs", major_code = dept_code,
           is_pre_major = FALSE)
  programs <- bind_rows(programs, concurrent)
  degrees <- collect(c(base = "cedar_degrees", graduates = "cedar_degrees_gg"))
  faculty <- collect(c(base = "cedar_faculty"))

  term_start <- function(term) as.Date(paste0(term %/% 100L,
    case_when(term %% 100L == 10L ~ "-01-15", term %% 100L == 60L ~ "-06-01",
              TRUE ~ "-08-15")))
  college_code <- function(x) {
    codes <- c(ARTS = "AS", STEM = "AS", SOSC = "AS", NURS = "NR", BUS = "BA",
               EDU = "ED", POPH = "PH")
    coalesce(unname(codes[x]), x, "AS")
  }
  # Different scenario files may reuse a CRN. The app needs unique section keys
  # across their union, while fixture_section_id records the original key.
  sections <- sections %>% mutate(
    fixture_section_id = section_id,
    section_key = paste(fixture_source, term, section_id, sep = ":"),
    synthetic_completion = FALSE)
  students <- students %>% mutate(
    fixture_student_id = student_id,
    section_key = paste(fixture_source, term, section_id, sep = ":"))

  # Some analytical fixtures contain enrollments only. Supply their missing
  # section metadata from those enrollments; never fabricate extra registrations
  # to force the separately authored DESR snapshots to match class-list counts.
  missing_sections <- students %>% anti_join(sections, by = "section_key") %>%
    group_by(section_key, fixture_source, section_id, term, subject_course, campus) %>%
    summarize(college = first(college), department = first(department),
      course_title = first(course_title), part_term = first(part_term),
      instructor_id = first(instructor_id), instructor_name = first(instructor_name),
      enrolled = sum(registration_status_code %in% c("RE", "RS", "RR")),
      waitlist_count = sum(registration_status_code == "WL"),
      credits_min = first(credits), .groups = "drop") %>%
    mutate(fixture_section_id = section_id, subject = sub(" .*", "", subject_course),
      course_number = sub(".* ", "", subject_course), total_enrl = enrolled,
      capacity = pmax(enrolled, 1L) + 5L, available = capacity - enrolled,
      status = "A", delivery_method = "ENH", credits_max = credits_min,
      synthetic_completion = TRUE)
  sections <- bind_rows(sections, missing_sections) %>% mutate(
    crn = paste0("FIX-", section_key),
    college = college_code(college), part_term = coalesce(part_term, "1"),
    course_title = coalesce(course_title, subject_course),
    instructor_id = coalesce(instructor_id, paste0("FIX-FAC-", department)),
    instructor_name = coalesce(instructor_name, paste0("Instructor, ", department)),
    start_date = term_start(term), end_date = term_start(term) + 100L,
    as_of_date = end_date + 30L)
  students <- students %>% select(-any_of(c("crn", "course_title", "instructor_id",
    "instructor_name", "instructor_first_name", "instructor_last_name", "part_term"))) %>%
    left_join(sections %>% select(section_key, crn, course_title, instructor_id,
                                  instructor_name, part_term), by = "section_key")

  # Enrollment-only people remain explicitly undeclared. Do not infer a major
  # from the subject they took, or add declarations to a known student's history.
  missing_programs <- students %>% anti_join(programs, by = "student_id") %>%
    distinct(student_id, term, .keep_all = TRUE) %>% transmute(
      student_id, term, fixture_source, program_type = "Major", program_name = "Undeclared",
      major_code = "UNDC", dept_code = "UNDC", degree = "BA", is_pre_major = FALSE,
      student_level, student_classification, student_campus = campus,
      student_college = college, student_population = "Continuing Student",
      synthetic_completion = TRUE)
  programs <- programs %>% mutate(synthetic_completion = FALSE) %>%
    bind_rows(missing_programs) %>% mutate(
      fixture_student_id = student_id,
      college_code = college_code(student_college),
      major_code = sub("-(BA|BS|MA|MS|BBA|MN)$", "", major_code),
      program_name = coalesce(program_name, major_code),
      as_of_date = term_start(term) + 130L)
  degrees <- degrees %>% mutate(fixture_student_id = student_id,
    program_name = coalesce(program_name, major_code),
    student_college = college_code(student_college),
    as_of_date = term_start(term) + 130L)
  faculty <- faculty %>% mutate(synthetic_completion = FALSE)
  missing_faculty <- sections %>% anti_join(faculty, by = c("instructor_id", "term")) %>%
    distinct(instructor_id, term, .keep_all = TRUE) %>% transmute(
      instructor_id, instructor_name, term, department, college,
      academic_title = "Instructor", job_title = "Instructor", job_category = "Term Teacher",
      appointment_pct = 1, fixture_source, synthetic_completion = TRUE)
  faculty <- bind_rows(faculty, missing_faculty)

  replicate_table <- function(df, identity_columns) {
    bind_rows(lapply(seq_len(cohorts), function(cohort) {
      out <- mutate(df, synthetic_cohort = cohort)
      if (cohort > 1L) for (column in intersect(identity_columns, names(out))) {
        keep <- is.na(out[[column]]) |
          (column == "crosslist_code" & out[[column]] %in% c("", "0"))
        out[[column]] <- ifelse(keep, out[[column]],
          paste0("COHORT", cohort, "-", out[[column]]))
      }
      out
    }))
  }
  sections <- replicate_table(sections, c("crn", "instructor_id", "crosslist_code"))
  students <- replicate_table(students, c("student_id", "crn", "instructor_id"))
  programs <- replicate_table(programs, "student_id")
  degrees <- replicate_table(degrees, "student_id")
  faculty <- replicate_table(faculty, "instructor_id")

  DESRs <- sections %>% transmute(
    TERM = term, CRN = crn, SUBJ = subject, CRSE = course_number,
    SECT_TITLE = course_title, SECT = coalesce(section, "001"), PT = part_term,
    CAMP = campus, COLLEGE = college, STATUS = status, INST_METHOD = delivery_method,
    PRIM_INST_ID = instructor_id, PRIM_INST_FIRST = sub(".*, *", "", instructor_name),
    PRIM_INST_LAST = sub(",.*", "", instructor_name),
    ENROLLED = enrolled, XL_ENRL = total_enrl, SECT_CAP = capacity, ROOM_CAP = capacity,
    SEATS_AVAIL = available, XL_CODE = coalesce(crosslist_code, "0"),
    XL_SUBJ = coalesce(crosslist_partners, ""),
    SHORT_TEXT = if_else(coalesce(crosslist_primary, FALSE), paste(subject, "home", term), NA_character_),
    MIN_CR = credits_min, MAX_CR = credits_max, WAIT_COUNT = waitlist_count,
    WAIT_CAPACITY = coalesce(waitlist_capacity, waitlist_count, 0L),
    START_DATE = format(start_date, "%m/%d/%Y"), END_DATE = format(end_date, "%m/%d/%Y"),
    CENSUS1 = start_date + 14L, as_of_date)
  class_lists <- students %>% transmute(
    `Academic Period Code` = term, `Course Reference Number` = crn,
    `Student ID` = student_id, `Subject Code` = sub(" .*", "", subject_course),
    `Course Number` = sub(".* ", "", subject_course), `Short Course Title` = course_title,
    `Primary Instructor ID` = instructor_id,
    `Primary Instructor Last Name` = sub(",.*", "", instructor_name),
    `Primary Instructor First Name` = sub(".*, *", "", instructor_name),
    `Course Campus Code` = campus, `Course College Code` = college_code(college),
    `Registration Status Code` = registration_status_code,
    `Registration Status` = case_when(registration_status_code %in% c("RE", "RS", "RR") ~ "Student Registered",
      registration_status_code == "WL" ~ "Wait Listed", TRUE ~ "Dropped"),
    `Final Grade` = final_grade, `Course Credits` = credits, `Total Credits` = total_credits,
    `Student Level Code` = if_else(student_level %in% c("Graduate", "GR"), "GR", "UG"),
    `Student Classification` = student_classification,
    `Major Code` = major_code, Major = NA_character_,
    `Student College Code` = college_code(student_college), `Student Campus Code` = student_campus,
    `Sub-Academic Period Code` = part_term, Residency = residency,
    `Dual Credit` = if_else(coalesce(dual_credit, FALSE), "Y", "N"),
    as_of_date = term_start(term) + 130L)
  # Restore program names on exact student/term matches only. Later declarations
  # must not leak backward into a historical class-list record.
  majors <- programs %>% filter(program_type == "Major") %>%
    distinct(student_id, term, .keep_all = TRUE) %>%
    select(student_id, term, major_code, program_name)
  class_lists <- class_lists %>% select(-`Major Code`, -Major) %>%
    left_join(majors, by = c("Student ID" = "student_id", "Academic Period Code" = "term")) %>%
    rename(`Major Code` = major_code, Major = program_name)

  academic_studies <- programs %>% transmute(
    ID = student_id, term_code = as.character(term),
    `Program Classification` = coalesce(program_classification, "Baccalaureate"),
    Degree = degree, `Student Classification` = student_classification,
    `Student Level` = student_level, `Student Campus` = student_campus,
    `Translated College` = student_college, `Actual College` = college_code,
    `Student Population` = student_population,
    `Institution Credits Attempted` = inst_credits_attempted,
    `Overall Credits Attempted` = overall_credits_attempted,
    `Overall Credits Earned` = overall_credits_earned,
    `Institution GPA` = inst_gpa,
    `Pell Eligible Indicator` = if_else(pell_eligible, "Y", "N"),
    `First Generation Indicator` = if_else(first_gen, "Yes", "No"),
    `IPEDS Race` = ipeds_race, Gender = gender, `Current Time Status Code` = time_status,
    Residency = residency, `Academic Standing` = academic_standing, as_of_date,
    `Program Code` = paste(degree, major_code, college_code, sep = "-"))
  # Each fixture row contributes only its own declaration type. The production
  # wide-to-long transform then preserves majors, minors, and concentrations.
  for (type in c("Major", "Second Major", "First Minor", "Second Minor",
                 "First Concentration", "Second Concentration", "Third Concentration")) {
    selected <- programs$program_type == type
    academic_studies[[type]] <- ifelse(selected,
      ifelse(coalesce(programs$is_pre_major, FALSE), paste0("Pre-", programs$program_name),
             programs$program_name), NA_character_)
    if (!grepl("Concentration", type)) {
      academic_studies[[paste(type, "Code")]] <- ifelse(selected, programs$major_code, NA_character_)
    }
  }
  degree_sources <- degrees %>% transmute(
    ID = student_id, `Academic Period Code` = term, Degree = degree,
    `Actual College` = student_college, `Translated College` = student_college,
    `Program Code` = coalesce(program_code, paste(degree, major_code, student_college, sep = "-")),
    Program = program_name, Department = department, `Major Code` = major_code, Major = program_name,
    `Graduation Status` = graduation_status, Campus = campus,
    `Award Category` = award_category, `Cumulative GPA` = cumulative_gpa,
    `Cumulative Credits Earned` = cumulative_credits, `Academic Period Admitted` = admitted_term,
    as_of_date)
  hr_data <- faculty %>% transmute(
    `UNM ID` = instructor_id, term_code = as.character(term), Name = instructor_name,
    DEPT = department, `Academic Title` = academic_title, `Job Title` = job_title,
    job_cat = job_category, `Appt %` = 100 * appointment_pct,
    `Home Organization Desc` = college, as_of_date = term_start(term) + 130L)
  # The old fixtures do not invent applicants. Preserve that absence explicitly.
  applicants <- tibble::tibble(ID = character(), `Academic Period Code` = integer(),
    `High School GPA` = numeric(), as_of_date = as.Date(character()))
  raw <- list(DESRs = DESRs, class_lists = class_lists, academic_studies = academic_studies,
    degrees = degree_sources, hr_data = hr_data, admissions_applicants = applicants)
  attr(raw, "provenance") <- list(
    students = bind_rows(students, programs, degrees) %>%
      distinct(student_id, fixture_student_id, synthetic_cohort, fixture_source),
    sections = sections %>% select(term, crn, fixture_section_id, synthetic_cohort,
                                  fixture_source, synthetic_completion))
  raw
}

# Add traceable fixture identities after the production transforms. Analytical
# columns still come exclusively from those transforms.
write_demo_provenance <- function(raw, target) {
  provenance <- attr(raw, "provenance")
  people <- provenance$students %>% mutate(student_id = encrypt_if_needed(student_id))
  if (anyDuplicated(people$student_id)) stop("Fixture identities overlap between scenarios")
  for (name in c("students", "programs", "degrees", "grades", "student_term_credits", "next_term")) {
    path <- file.path(target, paste0("cedar_", name, ".qs"))
    data <- qs2::qs_read(path)
    policy <- attr(data, "cedar_outcome_policy_version")
    data <- left_join(data, people, by = "student_id")
    if (!is.null(policy)) attr(data, "cedar_outcome_policy_version") <- policy
    qs2::qs_save(data, path)
  }
  path <- file.path(target, "cedar_sections.qs")
  sections <- left_join(qs2::qs_read(path), provenance$sections, by = c("term", "crn"))
  qs2::qs_save(sections, path)
  utils::write.csv(people, file.path(target, "fixture-people.csv"), row.names = FALSE)
  utils::write.csv(provenance$sections, file.path(target, "fixture-sections.csv"), row.names = FALSE)
  summary <- list(source = "tests/testthat/fixtures/designed_test_data.R",
    cohorts = max(people$synthetic_cohort), students = nrow(people),
    enrollments = nrow(raw$class_lists), sections = nrow(sections),
    courses = dplyr::n_distinct(sections$subject_course),
    campuses = sort(unique(sections$campus)), terms = sort(unique(sections$term)),
    scenarios = sort(unique(people$fixture_source)),
    note = "Cohort 1 preserves the original people; other cohorts copy complete histories. Synthetic completions supply missing metadata, not extra enrollments.")
  jsonlite::write_json(summary, file.path(target, "synthetic-institution.json"),
                       pretty = TRUE, auto_unbox = TRUE)
  invisible(summary)
}
