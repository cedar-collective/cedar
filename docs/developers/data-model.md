---
title: Data Model
nav_order: 3
parent: Developer Guide
---

# CEDAR Data Model

**Version:** 1.0
**Last Updated:** January 2026

## Overview

CEDAR uses a normalized data model designed for enrollment analytics in higher education. This model is **institution-agnostic** - while Cedar was built using MyReports data from UNM, any institution can map their data sources to these tables.

### Why a Standardized Model?

Instead of working directly with vendor-specific report formats (MyReports, Banner, Canvas, etc.), CEDAR defines its own data schema with only the columns needed for analytics. This approach:

- ✅ **Reduces memory usage** by 60-70% (loads only needed columns)
- ✅ **Speeds up startup** from 10-15 seconds to 3-5 seconds
- ✅ **Simplifies code** - all analytics reference consistent column names
- ✅ **Enables portability** - institutions can map their data without changing CEDAR code
- ✅ **Improves maintainability** - vendor changes don't break your analytics

---

## Core Tables

CEDAR requires 5 core tables. Each table is described below with:
- **Purpose**: What this table represents
- **Key columns**: Required fields
- **Optional columns**: Helpful but not required
- **Relationships**: How it connects to other tables

---

## 1. `cedar_sections` (Course Offerings)

**Purpose:** One row per course section per term (e.g., MATH 1350-001 in Fall 2025)

### Required Columns
**These columns are used throughout Cedar code - features will break without them**

| Column | Type | Description | Example | Usage Count |
|--------|------|-------------|---------|-------------|
| `term` | integer | Academic term code | 202580 | Core filter |
| `crn` | string | Course Reference Number | "12345" | Section identifier |
| `subject` | string | Subject code | "MATH" | Subject filter |
| `course_number` | string | Course number | "1350" | Course identifier |
| `subject_course` | string | Combined subject + course | "MATH 1350" | 239 references! |
| `section` | string | Section number | "001" | Section filter |
| `course_title` | string | Course title | "Calculus I" | Display |
| `campus` | string | Campus code | "Main", "ABQ", "Online" | Filter (34 uses) |
| `college` | string | College code | "AS" (Arts & Sciences) | Filter (30 uses) |
| `department` | string | Department code | "MATH" | Filter (58 uses) |
| `instructor_id` | string | Primary instructor ID | "123456" | FK to faculty |
| `instructor_name` | string | Instructor full name | "Smith, John" | Instructor filter |
| `enrolled` | integer | Current enrollment | 28 | Analytics (11 uses) |
| `capacity` | integer | Maximum enrollment | 30 | Seat analysis |
| `status` | string | Section status | "A" (Active), "C" (Cancelled) | Active filter |
| `delivery_method` | string | Delivery mode | "F2F", "Online", "Hybrid" | Method filter |
| `level` | string | Course level | "lower", "upper", "grad" | Level filter (75 uses!) |
| `term_type` | string | Term type | "fall", "spring", "summer" | Term-season grouping |
| `part_term` | string | Part of term | "1H", "2H", "FT" | Seatfinder analysis |
| `gen_ed_area` | integer | Gen Ed category code | 1, 2, 3, 4, 5, 7 | Gen Ed filter (19 uses) |
| `is_lab` | boolean | Lab section flag | TRUE/FALSE | Lab identification |
| `as_of_date` | date | When data was extracted | "2025-01-10" | Data freshness |

**Important Notes:**
- `subject_course` is created by combining `subject` + `course_number` (used 239 times!)
- `level`, `term_type`, `gen_ed_area`, `is_lab` are derived during parsing but heavily used
- `instructor_name` can be derived from first/last name fields if you have those

### Optional Columns
**Nice to have but not required for core functionality**

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `waitlist_count` | integer | Students on waitlist | 5 |
| `waitlist_capacity` | integer | Max waitlist size | 10 |
| `start_date` | date | Section start date | "2025-08-20" |
| `end_date` | date | Section end date | "2025-12-15" |
| `credits_min` | numeric | Minimum credits | 3.0 |
| `credits_max` | numeric | Maximum credits | 3.0 |
| `crosslist_primary` | boolean | Is primary crosslist section | TRUE/FALSE |
| `crosslist_group` | string | Crosslist group ID | "XL-12345" |
| `room` | string | Room number | "MESA 101" |
| `building` | string | Building code | "MESA" |
| `days` | string | Meeting days | "MWF" |
| `times` | string | Meeting times | "10:00AM-10:50AM" |

### Computed Columns (for reference)
**These are derived in parsers from other columns. Document how to compute them.**

| Column | How Computed | From |
|--------|--------------|------|
| `level` | Based on course_number | <300="lower", 300-499="upper", 500-699="grad", ≥1000="lower" |
| `is_lab` | Check for letter suffix | `grepl("[A-Z]$", course_number)` |
| `term_type` | From term code last 2 digits | 10="spring", 60="summer", 80="fall" |
| `gen_ed_area` | Map course to category | Check if subject_course in gen_ed lists |
| `instructor_name` | Combine name fields | `paste(last_name, first_name, sep=", ")` |

---

## 2. `cedar_students` (Student Registrations)

**Purpose:** One row per student per course section (class lists)

### Required Columns
**These columns are used throughout Cedar code - features will break without them**

| Column | Type | Description | Example | Usage Count |
|--------|------|-------------|---------|-------------|
| `enrollment_id` | string | Unique identifier | Auto-increment or hash | - |
| `crn` | string | Course reference number | "12345" | Join with `term` to sections when needed |
| `student_id` | string | **Encrypted** student ID | Hash of real ID | 19 uses |
| `term` | integer | Academic term code | 202580 | 113 uses! |
| `subject_course` | string | Course (denormalized) | "MATH 1350" | Pathway analysis |
| `course_title` | string | Course title | "Topics in History" | Display, distinguish same-number courses |
| `campus` | string | Course campus | "Main", "ABQ" | 72 uses! |
| `college` | string | Course college | "AS" | 45 uses! |
| `department` | string | Course department | "MATH" | Filtering |
| `registration_status` | string | Enrollment status | "Registered", "Dropped" | 3 uses |
| `registration_status_code` | string | Status code | "RE", "RS", "DR", "W" | 14 uses |
| `final_grade` | string | Final grade (if term complete) | "A", "B+", "W", "I" | 40 uses! |
| `student_level` | string | Student level | "UG", "GR" | 19 uses |
| `student_classification` | string | Class standing | "FR", "SO", "JR", "SR" | 3 uses |
| `major` | string | Student's major code | "MATH-BS" | Headcount |
| `student_college` | string | Student's college code | "AS" | 4 uses |
| `student_campus` | string | Student's campus | "Main" | 9 uses |
| `term_type` | string | Term type (denormalized) | "fall", "spring" | Rollcall analysis |
| `as_of_date` | date | When data was extracted | "2025-01-10" | Data freshness |

**Important Notes:**
- `student_id` **must be encrypted/hashed** - never store plaintext student IDs!
- `term` is most-used column (113 references) - absolutely critical. In `cedar_students`,
  it is derived from the Class Lists `Academic Period Code` field.
- `campus` (72 uses) and `college` (45 uses) are heavily filtered
- Some columns like `subject_course`, `campus`, `college`, `term_type` are denormalized from sections for query performance
- Analyses sometimes use `min(cedar_students$term)` as a student's **first observed
  class-list enrollment**. This is not a formal Banner matriculation/start-term field;
  it is only the first term CEDAR sees that student in a class-list enrollment row.

### Optional Columns
**Enhance functionality but not strictly required**

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `credits` | numeric | Credits student is taking | 3.0 |
| `registration_date` | date | When student registered | "2025-04-15" |
| `drop_date` | date | When student dropped | "2025-09-01" |
| `residency` | string | In-state/out-of-state | "Resident" |
| `dual_credit` | boolean | Dual credit student | TRUE/FALSE |

### Important Notes

- **Privacy:** `student_id` must be encrypted/hashed to protect student privacy
- **Relationship:** Links to `cedar_sections` via `term` + `crn`. The denormalized course, campus, and department fields avoid this join in most analyses.
- **Size:** This is typically the largest table (millions of rows)

---

## 2a. `cedar_student_term_credits` (Observed UNM Credits)

**Purpose:** One row per student per term, derived from `cedar_students`, for analyses that need an observed UNM credit timeline without re-summarizing class lists.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `student_id` | string | Encrypted student ID | Hash of real ID |
| `term` | integer | Academic term code | 202580 |
| `attempted_unm_credits` | numeric | Registered UNM credits observed in that term | 15 |
| `completed_unm_credits` | numeric | Credit-earning UNM credits observed in that term | 12 |
| `dfw_unm_credits` | numeric | Observed credits with a recorded nonpassing outcome under the canonical DFW policy | 3 |
| `w_unm_credits` | numeric | Observed W credits in that term | 3 |
| `registered_courses` | integer | Distinct registered courses observed in that term | 5 |
| `completed_courses` | integer | Distinct credit-earning courses observed in that term | 4 |
| `cumulative_attempted_unm_credits` | numeric | Running observed UNM attempted credits | 72 |
| `cumulative_completed_unm_credits` | numeric | Running observed UNM completed credits | 66 |

**Derivation:** `transform_students()` filters `cedar_students` to `registration_status_code %in% STATUS_REGISTERED` and non-missing `credits`, deduplicates by `student_id`, `term`, `subject_course`, `course_title`, `credits`, `final_grade`, and status, then summarizes and cumulatively sums by student. Completed credits use `passing_grades` from `R/lists/grades.R`.

**Pathways use:** Major Changes movement cards use `cumulative_completed_unm_credits` for the headline credit medians and `cumulative_attempted_unm_credits` in the detail table. This avoids treating Academic Studies cumulative UNM credit fields as a term-accurate credit timeline.

---

## 3. `cedar_programs` (Student Academic Programs)

**Purpose:** Student major, minor, concentration enrollment by term

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `student_id` | string | **Encrypted** student ID | Hash |
| `term` | integer | Academic term | 202580 |
| `program_type` | string | Type of program | "Major", "Minor", "Concentration" |
| `program_name` | string | Program full name | "Mathematics BS" |
| `college` | string | College offering program | "AS" |
| `department` | string | Department name from MyReports | "AS Anthropology", "Physics Astronomy" |
| `student_level` | string | Student academic level | "UG", "GR" |
| `student_college` | string | Student's home college | "AS" |
| `student_campus` | string | Student's campus | "Main" |
| `as_of_date` | date | When data was extracted | "2025-01-10" |

### Optional Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `degree` | string | Degree type | "BS", "BA", "MS", "PhD" |
| `classification` | string | Program classification | "Undergraduate", "Graduate" |
| `catalog_year` | integer | Catalog student follows | 202580 |
| `program_status` | string | Active, graduated, etc. | "Active" |
| `declared_date` | date | When program was declared | "2023-09-01" |
| `pell_eligible` | logical | Pell grant eligible this term | TRUE |
| `first_gen` | logical | First-generation college student | FALSE |
| `ipeds_race` | string | IPEDS race/ethnicity category | "Hispanic" |
| `gender` | string | Gender from Banner | "Female" |
| `time_status` | string | Full/half/less-than-half time | "FT", "HT", "LT" |
| `residency` | string | In-state / out-of-state / international | "Resident", "Non-Resident", "International" |
| `academic_standing` | string | Academic standing at term end | "Good Standing", "Academic Probation" |
| `inst_gpa` | numeric | Cumulative institution GPA | 3.42 |
| `inst_credits_attempted` | numeric | Cumulative UNM-only credits attempted | 90 |
| `overall_credits_attempted` | numeric | Cumulative credits attempted, UNM + transfer | 105 |
| `overall_credits_earned` | numeric | Cumulative credits earned, UNM + transfer | 96 |

> **Credit-hour notes:** All three are cumulative totals as reported on the Banner Academic Studies record. `inst_*` is UNM-only; `overall_*` includes transfer hours. These fields are useful for transfer-inclusive context and program-row metadata, but they should not be assumed to be a term-accurate UNM credit timeline. Use `cedar_student_term_credits` when an observed UNM credit progression is needed.

### Source-field notes for Pathways / Major Changes

Major Changes is intentionally explicit about CEDAR-to-Banner derivations:

| CEDAR field | Upstream MyReports/Banner field | Notes |
|-------------|----------------------------------|-------|
| `cedar_programs$term` | Academic Studies `Academic Period` | Converted to CEDAR `YYYYSS` term code via `academic_period_to_term()`. |
| `program_name` | Academic Studies `Major`, `Second Major`, minor/concentration name columns | `transform_programs()` expands wide program columns into one row per student-program-term. |
| `program_type` | Derived from which Academic Studies program column supplied the row | Examples: `Major`, `Second Major`, `First Minor`. |
| `major_code` | Academic Studies `Major Code`, `Second Major Code`, etc. | Used for mapping and disambiguation. |
| `program_code` | Academic Studies `Program Code` | Present primarily for primary major rows. |
| `is_pre_major` | CEDAR-computed | Derived from program naming/code patterns; not used as a separate major-change trigger when the program itself is unchanged. |
| `student_population` | Academic Studies `Student Population` | Used to label Native UNM vs Transfer in Pathways movement cards. |
| `inst_credits_attempted` | Academic Studies `Institution Credits Attempted` | Cumulative attempted UNM-only hours as recorded on the program row; not used for movement-card UNM medians. |
| `overall_credits_attempted` | Academic Studies `Overall Credits Attempted` | Cumulative attempted hours including transfer; used as transfer-inclusive context. |

When Pathways needs an enrollment anchor, it uses `min(cedar_students$term)`, derived
from Class Lists `Academic Period Code`. Treat that as first observed class-list
enrollment, not as a Banner start date. To avoid overstating entry timing, the
Major Changes headline entry cards exclude records already present at the data-start
term and records first observed with substantial prior UNM attempted credits; those
records remain available in the movement detail table. This entry-card eligibility
rule is separate from transfer classification: Transfer vs Always UNM comes from
the earliest available `cedar_programs$student_population` label, never from a
credit threshold. The attempted-UNM value used by the eligibility rule is
`cedar_student_term_credits$cumulative_attempted_unm_credits`, reconstructed from
Class Lists, not the frozen Academic Studies `inst_credits_attempted` field.

---

## 4. `cedar_degrees` (Graduates)

**Purpose:** Awarded degrees and pending graduates

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `degree_id` | string | Unique identifier | Auto-increment |
| `student_id` | string | **Encrypted** student ID | Hash |
| `term` | integer | Graduation term | 202510 |
| `degree` | string | Degree awarded | "BS", "BA", "MS", "PhD" |
| `program_name` | string | Program name | "Mathematics BS" |
| `college` | string | College | "AS" |
| `department` | string | Department | "MATH" |
| `graduation_status` | string | Status | "Conferred", "Pending", "Applied" |
| `as_of_date` | date | When data was extracted | "2025-01-10" |

### Optional Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `campus` | string | Campus | "Main" |
| `major` | string | Major name | "Mathematics" |
| `second_major` | string | Second major (if applicable) | "Physics" |
| `minor` | string | Minor | "Computer Science" |
| `cumulative_gpa` | numeric | Final GPA | 3.67 |
| `cumulative_credits` | numeric | Total credits earned | 128 |
| `honors` | string | Graduation honors | "Summa Cum Laude", "Cum Laude" |
| `admitted_term` | integer | When student first enrolled | 202180 |

---

## 5. `cedar_faculty` (Faculty HR Data)

**Purpose:** Faculty appointment and job category data for instructor analysis, particularly student-faculty ratios and instructor/outcome context.

**Source:** Transformed from HR reports via `transform-hr-to-cedar.R`

**Used by:** `sfr.R` (student-faculty ratios), course outcome and retention analyses

### Required Columns

| Column | Type | Description | Example | Usage Count |
|--------|------|-------------|---------|-------------|
| `instructor_id` | string | **Encrypted** UNM ID (matches cedar_students) | "abc123..." | Join key |
| `instructor_name` | string | Full name | "Smith, John D." | Display |
| `term` | integer | Academic term | 202580 | Join key (34 uses) |
| `department` | string | Home department code | "MATH" | Filter (28 uses) |
| `job_category` | string | Employment category | "Professor", "Lecturer", "Term Teacher" | Analytics (15 uses) |
| `appointment_pct` | numeric | Appointment percentage as decimal | 1.0 (100%), 0.5 (50%) | FTE calculation |
| `as_of_date` | date | When HR data was processed | "2025-01-10" | Data freshness |

**Important Notes:**
- `department` uses **department codes** from HR data (e.g., "MATH", "ANTH")
- `job_category` uses **Title Case** values from parse-HRreport.R (see values below)
- `appointment_pct` is stored as **decimal 0.0-1.0**, not percentage (e.g., 0.5 = 50%)
- `instructor_id` is **encrypted** to match the encryption used in cedar_sections

### Job Categories

The `job_category` field uses values from parse-HRreport.R:

| Category | Description | Counted in SFR? |
|----------|-------------|-----------------|
| `Professor` | Full professor | ✅ Yes (permanent) |
| `Associate Professor` | Associate professor | ✅ Yes (permanent) |
| `Assistant Professor` | Assistant professor | ✅ Yes (permanent) |
| `Lecturer` | Lecturer (non-tenure track) | ✅ Yes (permanent) |
| `Term Teacher` | Term teacher | ❌ No (temporary) |
| `TPT` | Temporary part-time | ❌ No (temporary) |
| `Grad` | Graduate assistant | ❌ No (temporary) |
| `Professor Emeritus` | Emeritus professor | ❌ No (non-active) |

**For SFR calculations**, only permanent faculty (Professor, Associate Professor, Assistant Professor, Lecturer) are counted as part of the faculty FTE denominator.

### Optional Columns (Retained for Reference)

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `academic_title` | string | Original academic title from HR | "Assistant Professor" |
| `job_title` | string | Job title from HR | "Assistant Professor" |
| `college` | string | Home organization description from HR | "AS Mathematics & Statistics" |

### Transformation Details

The `cedar_faculty` table is created by `transform-to-cedar.R` which:

1. **Loads** `hr_data.Rds` (output from `parse-HRreport.R`)
2. **Normalizes** column names to CEDAR conventions:
   - `UNM ID` → `instructor_id` (encrypted)
   - `term_code` → `term` (integer)
   - `DEPT` → `department` (department code)
   - `job_cat` → `job_category` (Title Case values)
   - `Appt %` → `appointment_pct` (decimal 0.0-1.0)
   - `Home Organization Desc` → `college`
3. **Saves** to `cedar_faculty.Rds`

### Example Queries

**Calculate permanent faculty FTE by department:**
```r
cedar_faculty %>%
  filter(job_category %in% c("professor", "associate_professor",
                              "assistant_professor", "lecturer")) %>%
  group_by(term, department) %>%
  summarize(fte = sum(appointment_pct))
```

**Count faculty by job category:**
```r
cedar_faculty %>%
  filter(term == 202580) %>%
  count(job_category, sort = TRUE)
```

**Merge with course attempts for instructor outcome context:**
```r
course_attempts %>%
  left_join(cedar_faculty, by = c("instructor_id", "term")) %>%
  group_by(subject_course, job_category) %>%
  summarize(n_attempts = n(), .groups = "drop")
```

---

## Relationships Between Tables

```
cedar_sections
    ├─► cedar_students (via term + crn)
    │       └─► cedar_programs (via student_id)
    │       └─► cedar_degrees (via student_id)
    └─► cedar_faculty (via instructor_id)
```

### Key Foreign Key Relationships

1. **sections → enrollments:** `cedar_sections.term + crn` = `cedar_students.term + crn`
2. **sections → faculty:** `cedar_sections.instructor_id` = `cedar_faculty.instructor_id`
3. **enrollments → programs:** `cedar_students.student_id` = `cedar_programs.student_id`
4. **enrollments → degrees:** `cedar_students.student_id` = `cedar_degrees.student_id`

---

## Data Size Expectations

Typical data volumes for a mid-sized university (~25,000 students):

| Table | Rows per Term | Total (5 years) | Memory (approx) |
|-------|--------------|-----------------|-----------------|
| `cedar_sections` | 5,000 - 8,000 | 40,000 - 60,000 | 5-10 MB |
| `cedar_students` | 100,000 - 150,000 | 750,000 - 1M | 60-100 MB |
| `cedar_programs` | 30,000 - 40,000 | 200,000 - 300,000 | 15-25 MB |
| `cedar_degrees` | 5,000 - 8,000 | 40,000 - 60,000 | 3-5 MB |
| `cedar_faculty` | 1,500 - 2,500 | 10,000 - 15,000 | 1-2 MB |
| **Total** | | | **~100 MB** |

Compare to current MyReports format: ~300MB for same data!

---

## Common Queries

### Get enrollment by department
```r
cedar_sections %>%
  filter(term == 202580, status == "A") %>%
  group_by(department) %>%
  summarize(total_enrollment = sum(enrolled))
```

### Get student's course history
```r
cedar_students %>%
  filter(student_id == "hashed_id") %>%
  select(term, subject_course, course_title, final_grade)
```

### Count majors by program
```r
cedar_programs %>%
  filter(term == 202580, program_type == "Major") %>%
  group_by(program_name) %>%
  summarize(headcount = n_distinct(student_id))
```

### DFW rates by course
```r
cedar_grades %>%
  filter(term >= 202080) %>%
  group_by(subject_course, campus) %>%
  summarize(
    dfw_count = sum(outcome == "dfw"),
    total_count = n(),
    .groups = "drop"
  ) %>%
  mutate(dfw_rate = dfw_count / total_count)
```

---

## Column Naming Conventions

CEDAR uses **snake_case** for all column names to ensure consistency:

- ✅ `student_id`, `course_title`, `enrollment_date`
- ❌ `StudentID`, `CourseTitle`, `Enrollment Date` (avoid)

### Standard Abbreviations

| Abbreviation | Meaning |
|--------------|---------|
| `id` | Identifier (primary key or foreign key) |
| `crn` | Course Reference Number |
| `term` | Academic term code (YYYYCC format) |
| `dept` | Department |
| `pct` | Percentage |
| `enrl` / `enrolled` | Enrollment |
| `max` | Maximum |
| `min` | Minimum |
| `avg` | Average |

---

## Data Types

Follow these conventions for consistency across institutions:

| Type | R type | Description | Example |
|------|--------|-------------|---------|
| **Identifiers** | `character` | Always string, even if numeric | "12345", not 12345 |
| **Term codes** | `integer` | 6-digit term code | 202580 (Fall 2025) |
| **Counts** | `integer` | Whole numbers | 28, 150 |
| **Percentages** | `numeric` | Decimals 0-1 | 0.93 (not 93) |
| **Dates** | `Date` | Standard date type | "2025-08-20" |
| **Flags** | `logical` | TRUE/FALSE | TRUE, not "Y" |

---

## Privacy & Security

### Student ID Encryption

**CRITICAL:** Never store plaintext student IDs. Always encrypt/hash before saving to CEDAR tables.

```r
# Example encryption (use stronger method in production)
library(digest)
encrypt_student_id <- function(id) {
  digest(paste0(id, Sys.getenv("CEDAR_SALT")), algo = "sha256")
}

# In transformation
cedar_students <- class_lists %>%
  mutate(student_id = encrypt_student_id(`Student ID`))
```

### Sensitive Columns

Mark these as optional or exclude entirely based on your institution's policies:
- Email addresses
- Student addresses
- Social Security Numbers (NEVER include)
- Detailed demographic data beyond aggregated reporting needs

---

## Next Steps

1. **Read the transformation guide:** See `data-transformation-myreports.md` for how to map MyReports → CEDAR
2. **Review sample data:** Check `data/samples/` for example CEDAR tables
3. **Run validation:** Use `validate_cedar_data()` function to check your tables
4. **Start using:** Load CEDAR tables instead of raw vendor data in your analytics

---

## Questions?

- **How do I map my data?** See institution-specific transformation guides in `docs/transformations/`
- **What if I don't have a column?** Many columns are optional - provide what you have
- **Can I add custom columns?** Yes! Add institution-specific columns as needed
- **How do I validate?** Run `source("R/data-validation.R"); validate_cedar_tables()`
