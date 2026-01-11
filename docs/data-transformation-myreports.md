# Transforming MyReports Data to CEDAR Model

**For institutions using MyReports** (common in higher education)

This guide shows how to transform standard MyReports exports into the CEDAR data model. If you use a different system (Banner, Canvas, Colleague, etc.), use this as a template for your own transformation.

---

## Overview

MyReports provides 4 main reports that map to CEDAR's 5 tables:

| MyReports Report | → | CEDAR Table |
|------------------|---|-------------|
| **DESR** (Department Enrollment Status Report) | → | `cedar_sections` + partial `cedar_faculty` |
| **Class Lists** | → | `cedar_enrollments` |
| **Academic Study Detail** | → | `cedar_programs` |
| **Graduates & Pending Graduates** | → | `cedar_degrees` |
| **HR Report** (optional) | → | `cedar_faculty` (enriched) |

---

## Prerequisites

1. Download MyReports exports as Excel files
2. Place in your data archive directory (configured in `config.R`)
3. Have `xlsx2csv` utility installed for parsing
4. R packages: `tidyverse`, `digest` (for student ID hashing)

---

## Automated Transformation

CEDAR provides an automated transformation script:

```r
# After downloading MyReports files
Rscript cedar.R -f parse-data
```

This script:
1. Finds Excel files in your archive
2. Converts to CSV
3. Applies transformations below
4. Saves as CEDAR model tables in `data/`

---

## Manual Transformation (for reference)

If you need to customize the transformation, here's the mapping for each table:

---

## 1. DESR → `cedar_sections`

### MyReports DESR Required Columns

| MyReports Column | Type | Notes |
|-----------------|------|-------|
| `TERM` | integer | Term code |
| `CRN` | string | Course Reference Number |
| `SUBJ` | string | Subject code |
| `CRSE#` | string | Course number |
| `SECT#` | string | Section number |
| `SECT_TITLE` | string | Section title |
| `CAMP` | string | Campus |
| `COLLEGE` | string | College code |
| `DEPT` | string | Department |
| `PRIM_INST_ID` | string | Instructor ID |
| `PRIM_INST_FIRST` | string | Instructor first name |
| `PRIM_INST_LAST` | string | Instructor last name |
| `ENROLLED` | integer | Current enrollment |
| `MAX_ENROLLED` | integer | Capacity |
| `STATUS` | string | Section status (A/C/X) |
| `INST_METHOD` | string | Delivery method |

### Transformation Code

```r
library(tidyverse)
library(digest)

# Read DESR CSV (after xlsx2csv conversion)
desr_raw <- read_csv("path/to/DESR.csv")

# Transform to cedar_sections
cedar_sections <- desr_raw %>%
  transmute(
    # Identifiers
    section_id = paste0(TERM, "-", CRN),
    term = as.integer(TERM),
    crn = as.character(CRN),

    # Course info
    subject = SUBJ,
    course_number = `CRSE#`,
    section = `SECT#`,
    course_title = SECT_TITLE,

    # Organizational
    campus = CAMP,
    college = COLLEGE,
    department = DEPT,

    # Instructor
    instructor_id = as.character(PRIM_INST_ID),
    instructor_name = paste(PRIM_INST_LAST, PRIM_INST_FIRST, sep = ", "),

    # Enrollment
    enrolled = as.integer(ENROLLED),
    capacity = as.integer(MAX_ENROLLED),

    # Status
    status = STATUS,

    # Optional fields
    delivery_method = INST_METHOD,
    start_date = as.Date(START_DATE, format = "%m/%d/%Y"),
    end_date = as.Date(END_DATE, format = "%m/%d/%Y"),
    credits_min = as.numeric(MIN_CR),
    credits_max = as.numeric(MAX_CR),
    waitlist_count = as.integer(coalesce(WAIT_COUNT, 0)),
    waitlist_capacity = as.integer(coalesce(WAIT_CAPACITY, 0)),

    # Metadata
    as_of_date = as.Date(Sys.time())
  ) %>%
  # Add computed columns
  mutate(
    # Course level
    course_number_numeric = as.integer(str_extract(course_number, "\\d+")),
    level = case_when(
      course_number_numeric < 300 ~ "lower",
      course_number_numeric >= 500 & course_number_numeric < 700 ~ "grad",
      course_number_numeric >= 300 & course_number_numeric < 500 ~ "upper",
      TRUE ~ "lower"
    ),

    # Lab flag
    is_lab = str_detect(course_number, "[A-Z]$"),

    # Term type
    term_suffix = term %% 100,
    term_type = case_when(
      term_suffix == 10 ~ "spring",
      term_suffix == 60 ~ "summer",
      term_suffix == 80 ~ "fall",
      TRUE ~ "unknown"
    )
  ) %>%
  # Remove temp columns
  select(-course_number_numeric, -term_suffix)

# Handle crosslisted courses
cedar_sections <- cedar_sections %>%
  mutate(
    crosslist_group = if_else(!is.na(XL_CODE), paste0("XL-", XL_CODE), NA_character_),
    crosslist_primary = if_else(!is.na(XL_CODE) & XL_ENRL > ENROLLED, FALSE, TRUE)
  )

# Save
saveRDS(cedar_sections, "data/cedar_sections.Rds")
# Or with qs for faster loading:
# qs::qsave(cedar_sections, "data/cedar_sections.qs")
```

---

## 2. Class Lists → `cedar_enrollments`

### MyReports Class Lists Required Columns

| MyReports Column | Type | Notes |
|-----------------|------|-------|
| `Academic Period Code` | integer | Term code |
| `Course Reference Number` | string | CRN |
| `Student ID` | string | **Will be encrypted!** |
| `Registration Status` | string | Enrolled, Dropped, etc. |
| `Final Grade` | string | Grade (if term complete) |
| `Student Classification` | string | FR, SO, JR, SR, GR |
| `Major Code` | string | Primary major |
| `Student College Code` | string | Student's college |
| `Student Campus Code` | string | Student's campus |

### Transformation Code

```r
classlist_raw <- read_csv("path/to/ClassList.csv")

# CRITICAL: Encrypt student IDs
encrypt_student_id <- function(id) {
  # Use your institution's preferred hashing method
  # Add a secret salt from environment variable
  digest(paste0(id, Sys.getenv("CEDAR_STUDENT_SALT")), algo = "sha256")
}

cedar_enrollments <- classlist_raw %>%
  transmute(
    # Identifiers (ENCRYPT student ID!)
    enrollment_id = row_number(),
    section_id = paste0(`Academic Period Code`, "-", `Course Reference Number`),
    student_id = encrypt_student_id(`Student ID`),
    term = as.integer(`Academic Period Code`),

    # Enrollment status
    registration_status = `Registration Status`,
    registration_date = as.Date(`Registration Status Date`, format = "%m/%d/%Y"),

    # Academic performance
    grade = `Final Grade`,
    credits = as.numeric(`Course Credits`),

    # Student demographics
    student_level = `Student Level Code`,
    student_classification = `Student Classification`,
    primary_major = `Major Code`,
    student_college = `Student College Code`,
    student_campus = `Student Campus Code`,
    residency = Residency,
    dual_credit = if_else(`Dual Credit` == "Y", TRUE, FALSE),

    # Metadata
    as_of_date = as.Date(Sys.time())
  )

saveRDS(cedar_enrollments, "data/cedar_enrollments.Rds")
```

---

## 3. Academic Study → `cedar_programs`

### MyReports Academic Study Required Columns

| MyReports Column | Type | Notes |
|-----------------|------|-------|
| `term_code` | integer | Added by parser |
| `ID` | string | Student ID |
| `Program Code` | string | Program code |
| `Program` | string | Program name |
| `Degree` | string | Degree type |
| `Translated College` | string | College |
| `Department` | string | Department |

### Transformation Code

```r
academic_study_raw <- read_csv("path/to/AcademicStudy.csv")

cedar_programs <- academic_study_raw %>%
  # Process majors
  transmute(
    program_id = row_number(),
    student_id = encrypt_student_id(ID),
    term = as.integer(term_code),
    program_type = "Major",
    program_code = `Program Code`,
    program_name = Program,
    college = `Translated College`,
    department = Department,
    degree = Degree,
    classification = `Program Classification`,
    as_of_date = as.Date(Sys.time())
  ) %>%
  # Add second majors if they exist
  bind_rows(
    academic_study_raw %>%
      filter(!is.na(`Second Major Code`)) %>%
      transmute(
        program_id = row_number() + max(row_number()),
        student_id = encrypt_student_id(ID),
        term = as.integer(term_code),
        program_type = "Major",
        program_code = `Second Major Code`,
        program_name = `Second Major`,
        college = `Translated College`,  # May need adjustment
        department = sec_major_DEPT,     # Added by parser
        degree = Degree,
        classification = `Second Program Classification`,
        as_of_date = as.Date(Sys.time())
      )
  ) %>%
  # Add minors
  bind_rows(
    academic_study_raw %>%
      filter(!is.na(`First Minor Code`)) %>%
      transmute(
        program_id = row_number() + max(row_number()) * 2,
        student_id = encrypt_student_id(ID),
        term = as.integer(term_code),
        program_type = "Minor",
        program_code = `First Minor Code`,
        program_name = `First Minor`,
        college = `Translated College`,
        department = minor_DEPT,  # Added by parser
        degree = NA_character_,
        classification = NA_character_,
        as_of_date = as.Date(Sys.time())
      )
  ) %>%
  # Add second minors if they exist
  bind_rows(
    academic_study_raw %>%
      filter(!is.na(`Second Minor Code`)) %>%
      transmute(
        program_id = row_number() + max(row_number()) * 3,
        student_id = encrypt_student_id(ID),
        term = as.integer(term_code),
        program_type = "Minor",
        program_code = `Second Minor Code`,
        program_name = `Second Minor`,
        college = `Translated College`,
        department = sec_minor_DEPT,  # Added by parser
        degree = NA_character_,
        classification = NA_character_,
        as_of_date = as.Date(Sys.time())
      )
  )

saveRDS(cedar_programs, "data/cedar_programs.Rds")
```

---

## 4. Graduates → `cedar_degrees`

### MyReports Graduates Required Columns

| MyReports Column | Type | Notes |
|-----------------|------|-------|
| `Academic Period Code` | integer | Graduation term |
| `ID` | string | Student ID |
| `Degree` | string | Degree type |
| `Program Code` | string | Program code |
| `Program` | string | Program name |
| `Translated College` | string | College |
| `Department` | string | Department |
| `Graduation Status` | string | Conferred, Pending, etc. |

### Transformation Code

```r
degrees_raw <- read_csv("path/to/Graduates.csv")

cedar_degrees <- degrees_raw %>%
  transmute(
    degree_id = row_number(),
    student_id = encrypt_student_id(ID),
    degree_term = as.integer(`Academic Period Code`),
    degree_type = Degree,
    program_code = `Program Code`,
    program_name = Program,
    college = `Translated College`,
    department = Department,
    graduation_status = `Graduation Status`,

    # Optional fields
    campus = Campus,
    major = Major,
    second_major = `Second Major`,
    minor = `First Minor`,
    cumulative_gpa = as.numeric(`Cumulative GPA`),
    cumulative_credits = as.numeric(`Cumulative Credits Earned`),
    honors = Honor,
    admitted_term = as.integer(`Academic Period Admitted`),

    as_of_date = as.Date(Sys.time())
  )

saveRDS(cedar_degrees, "data/cedar_degrees.Rds")
```

---

## 5. HR Report → `cedar_faculty`

### MyReports HR Report Required Columns

| MyReports Column | Type | Notes |
|-----------------|------|-------|
| `term_code` | integer | Term |
| `UNM ID` | string | Employee ID |
| `Name` | string | Full name |
| `DEPT` | string | Department |

### Transformation Code

```r
hr_raw <- read_csv("path/to/HR_Report.csv")

cedar_faculty <- hr_raw %>%
  transmute(
    instructor_id = as.character(`UNM ID`),
    term = as.integer(term_code),
    instructor_name = Name,
    department = DEPT,

    # Optional fields
    academic_title = `Academic Title`,
    job_title = `Job Title`,
    job_category = job_cat,
    appt_percent = as.numeric(`Appt %`),
    college = `Home Organization Desc`,  # May need mapping

    as_of_date = as.Date(Sys.time())
  )

saveRDS(cedar_faculty, "data/cedar_faculty.Rds")
```

---

## Complete Transformation Script

CEDAR includes a complete transformation script at `R/data-parsers/transform-to-cedar.R`:

```r
# Run complete transformation
source("R/data-parsers/transform-to-cedar.R")
transform_myreports_to_cedar()
```

This script:
1. ✅ Finds all MyReports Excel files
2. ✅ Converts to CSV
3. ✅ Applies all transformations above
4. ✅ Validates data quality
5. ✅ Saves CEDAR model tables
6. ✅ Creates small test datasets
7. ✅ Generates data status report

---

## Validation

After transformation, validate your data:

```r
source("R/data-validation.R")

# Validate all tables
validation_results <- validate_cedar_tables()

# Check for issues
if (validation_results$all_valid) {
  message("✅ All CEDAR tables are valid!")
} else {
  print(validation_results$issues)
}
```

---

## Testing with Small Datasets

For development and testing, create small subsets:

```r
# Create small versions (last 2 terms only)
create_small_cedar_datasets <- function() {
  recent_terms <- c(202510, 202580)

  cedar_sections_small <- cedar_sections %>%
    filter(term %in% recent_terms)
  saveRDS(cedar_sections_small, "data/cedar_sections_small.Rds")

  # Repeat for other tables...
}
```

Then in `config.R`:
```r
cedar_use_small_data <- TRUE  # Use small datasets for development
```

---

## Troubleshooting

### Issue: Student IDs not encrypting
**Solution:** Ensure `CEDAR_STUDENT_SALT` environment variable is set:
```r
# In .Renviron
CEDAR_STUDENT_SALT=your-secret-salt-here-make-it-random
```

### Issue: Column names don't match
**Solution:** MyReports column names may vary. Check your actual export and adjust transformation:
```r
# Example: Your column might be "CRSE" not "CRSE#"
course_number = CRSE,  # Instead of `CRSE#`
```

### Issue: Memory errors with large datasets
**Solution:** Process in chunks:
```r
# Read and transform by term
for (term in terms_to_process) {
  term_data <- classlist_raw %>% filter(`Academic Period Code` == term)
  # ... transform
  # ... save individually
}
```

---

## Next Steps

1. ✅ **Run transformation:** `Rscript cedar.R -f parse-data`
2. ✅ **Validate data:** `validate_cedar_tables()`
3. ✅ **Test analytics:** Try running enrollment reports
4. ✅ **Update code:** Gradually migrate cones to use CEDAR model

---

## Questions?

- **What if my MyReports columns are different?** Adjust the transformation script for your institution
- **How often should I re-transform?** After each MyReports data pull (weekly/monthly)
- **Can I automate this?** Yes! Add to cron job after mrgather runs
- **What about other institutions?** Create similar transformation for your data source
