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

## Colleges: reported and source (ADR-002 Stage 3b)

Every college a report reads comes from the institution mapping files; the
value Banner recorded stays beside it for audit. Since ADR-001 step 3 only
Banner's values are in the saved files: the reported columns below, the
`department` / `dept_code` beside them, `college_basis`, and the crosslist
columns that follow a department, are attached when a loader starts
(`attach_default_units()`, `R/branches/dims.R`) from the keys each table
stores, so a mapping edit changes the next start and rebuilds nothing.

| Table | Reported college | Banner's value | Rule |
|---|---|---|---|
| `cedar_programs` | `college_code`, `student_college` (name) | `source_college_code` (Actual College), `source_college` (Translated College) | The student's college that term: their primary major's `program_college`, on every row they have |
| `cedar_programs` | `program_college` | — | Each row's own program: program → unit → college; a concentration takes its primary major's |
| `cedar_sections`, `cedar_students` | `college` | `source_college` | The subject row's `college_code`, else the unit's home college |
| `cedar_degrees` | `college_code`, `college`, `student_college` | `source_college` (Translated), `source_student_college` (Actual) | The degree program's college |

`college_basis` on each says where the reported value came from: `mapped` (the
files), `banner` (the code is not yet decided, so Banner's value, translated
through `colleges.csv`), or `NA` (nothing names one, as for Non-Degree). Read
the reported columns; only the mapping audit reads the source ones.

## 0. `cedar_terms` (The Term Dimension)

**Purpose:** One row per term in the loaded data, built at startup by `build_cedar_terms()` (`R/branches/cedar-terms.R`) and held as `data_objects[["cedar_terms"]]`; never saved, because it describes whatever is loaded. ADR-001 step 1: everything about a term that readers otherwise recompute, in one place.

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `term` | integer | Term code | 202580 |
| `label` | string | Readable label | "Fall 2025" |
| `season` | string | `fall` / `spring` / `summer` | "fall" |
| `acad_year` | string | Academic year | "2025-2026" |
| `is_regular` | boolean | Fall or Spring | TRUE |
| `prev_term`, `next_term` | integer | Calendar neighbours, Summer included | 202560, 202610 |
| `prev_regular_term`, `next_regular_term` | integer | Neighbours skipping Summer; Summer's next is the Fall | 202510, 202610 |
| `start_date`, `census_date` | date | Most common `start_date` / `census1` among the term's sections; NA without sections | 2025-08-18, 2025-09-05 |
| `enrollment_rows` | integer | Class-list rows; 0 for a term with sections only | 129043 |
| `graded_share` | numeric | Share of class-list rows with a posted grade; NA when none | 0.91 |
| `newest_pull` | date | Newest class-list `as_of_date` | 2026-03-07 |
| `section_rows` | integer | Sections scheduled | 12048 |
| `degrees_awarded` | integer | Degrees with `graduation_status == "Awarded"` | 2150 |
| `is_enrolled` | boolean | `enrollment_rows > 0` | TRUE |
| `is_settled` | boolean | Enrolled and at or before `last_enrolled_complete` | TRUE |
| `is_graded` | boolean | Enrolled and at or before `last_graded` | TRUE |
| `in_progress` | boolean | Enrolled, after `last_graded` | FALSE |
| `has_degrees` | boolean | At or before `last_degree` | TRUE |
| `is_upcoming` | boolean | Sections but no class list, after `last_enrolled` | FALSE |

The flags are the startup edges from `cedar_data_edges()` passed in, never recomputed here; an edge the data cannot determine is NA on every row, never FALSE. Every Fall and Spring between the first and last term with a class list is a row, with a class list or without one: a gap term has zero enrollment (`is_enrolled` FALSE, so never settled or graded), is named in a message at build time, and `next_regular_term` always names a row. A gap means a pull is missing; the synthetic institution has several by design, and production has had none. A schedule-only term outside that run is an old DESR or an upcoming term, not a gap. `validate_cedar_terms()` rejects a repeated term, a code that is not YYYYSS, and a dimension with no row for a Fall or Spring inside the enrolled run.

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

## 2a. `cedar_student_term_credits` (retired)

Retired 2026-11-04. Its columns — per-term and running attempted and completed UNM credits, counted from registered class-list rows with a credit value and de-duplicated the same way — are columns of `cedar_student_terms` (2b), which `build_credit_timeline()` and the Pathways credit cards now read. The transform no longer writes the file, and the app no longer loads it; a copy left in a data directory is ignored.

---

## 2b. `cedar_student_terms` (One Row per Student-Term)

**Purpose:** Every fact about a student in a term, stored once (ADR-001 step 2). Built in the transform by `build_student_terms()` (`R/branches/student-terms.R`) from the saved students, programs and degrees, whenever any of them is rebuilt. The full contract, column by column, is [student-terms.md](student-terms.md); the rules that matter most:

- One row per `(student_id, term)` for every student with any class-list row **or** any declaration that term, so waitlist-only, early-drop-only and declared-but-not-registered students are rows with `enrolled = FALSE`.
- `enrolled` is registered **or** late-dropped (enrolled at census): CEDAR's one definition of an enrolled student-term. `returned_next_regular_term` reads it in the next Fall or Spring; it is `NA` where `return_observable` is FALSE (the next regular term is past the settled edge, or has no class list at all), never FALSE.
- The description columns (`student_level`, `student_classification`, `student_campus`, `residency`) take the academic-studies value where there is one and the class list's otherwise; `description_source` says which, and `description_conflict` flags the two disagreeing. Level and home campus are stored as codes; academic studies' names are translated through `institution/<id>/student_levels.csv` and `campuses.csv` `source_names`, and an unlisted name is `NA` and reported.
- The pull-stamped fields (`inst_*`, `overall_*`, `inst_gpa`) are banned from the table; `validate_student_terms()` rejects them.
- `attempted_unm_credits`, `completed_unm_credits` and their running totals `cumulative_attempted_unm_credits` / `cumulative_completed_unm_credits` keep the definition the retired `cedar_student_term_credits` used, with `unm_credits_entering` and `timeline_valid` beside them; `build_credit_timeline()` and the Pathways credit medians read them from here.

On the 2026-10-27 pull: 518,889 rows (452,021 enrolled; 53,053 declared without a class list), 126 MB in memory, 5,442 student-terms where the two sources disagree (4,210 of them in Fall 2025, whose programs were pulled in November 2025 and whose class list in March 2026).

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

> **Credit-hour notes:** All three are cumulative totals as reported on the Banner Academic Studies record. `inst_*` is UNM-only; `overall_*` includes transfer hours. These fields are useful for transfer-inclusive context and program-row metadata, but they should not be assumed to be a term-accurate UNM credit timeline. Use the credit columns of `cedar_student_terms` (through `build_credit_timeline()`) when an observed UNM credit progression is needed.

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
`cedar_student_terms$cumulative_attempted_unm_credits`, reconstructed from
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

Validate the saved outcome policy before using `cedar_grades`. AUD is excluded
even under DG/DW late-drop status. Unversioned or obsolete tables must be rebuilt
from the current parsed class lists with `transform_to_cedar(tables = "students")`.
Do not reconstruct this table from `cedar_students`: its earlier course-level
deduplication has already removed some separate CRN outcomes.
Check the data location too: Docker mounts `CEDAR_DATA_DIR`, which may differ
from the repository's `data/` copy used by RStudio. A manual refresh must update
the files each runtime actually reads, followed by an app restart.

```r
validate_cedar_grades_policy(cedar_grades)
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

- **How do I map my data?** See the institution transformation guide, [data-transformation-myreports.md](data-transformation-myreports.md) (UNM's MyReports exports), and the mapping files described in [ADR-002](https://github.com/cedar-collective/cedar/blob/main/docs/developers/architecture-decisions.md#adr-002-explicit-mapping-files-replace-runtime-department-inference)
- **What if I don't have a column?** Many columns are optional - provide what you have
- **Can I add custom columns?** Yes! Add institution-specific columns as needed
- **How do I validate?** Run `source("R/data-validation.R"); validate_cedar_tables()`

## Loaded tables, units and course ids

How each loaded table is built, and how every row gets its unit and its course at load. Moved from `AGENTS.md` on 2026-11-07, which keeps the rules.

| Table | Rows | What it is / most-used columns |
|-------|------|-------------------------------|
| `cedar_sections` | ~50k | One row per DESR section row. `term`, `crn`, `subject_course`, `campus`, `department`, `enrolled`, `total_enrl`, `is_combined`, `is_topics` |
| `cedar_students` | ~1.9M | One row per student-course-term. `student_id`, `term`, `subject_course`, `campus`, `level`, `final_grade`, `registration_status_code`, `student_classification`, `student_campus`, `major_code` |
| `cedar_programs` | ~200k | One row per student-term program declaration. `program_name`, `program_code`, `dept_code`, `college_code`, `student_campus`, `pell_eligible`, `first_gen`, `ipeds_race`, `gender`, `time_status`. Its `*_credits_*` columns are pull-stamped — see the field reliability contract |
| `cedar_degrees` | ~20k | Awarded degrees. `degree`, `program_name`, `dept_code`, `cumulative_gpa`, `cumulative_credits` |
| `cedar_faculty` | ~5k × terms | `instructor_id`, `instructor_name`, `department`, `job_category`, `appointment_pct` (0–100; divide by 100 for FTE), `college` |
| `cedar_student_terms` | ~520k | One row per student-term with any class-list row or declaration. Built by `build_student_terms()` in the transform from students, programs and degrees (ADR-001 step 2; contract [student-terms.md](student-terms.md)). `enrolled` (registered or late-dropped: **CEDAR's one definition of an enrolled student-term**), `returned_next_regular_term` / `return_observable`, description columns in code vocabulary with the source and any conflict flagged, per-term and running (`cumulative_*`) attempted and completed UNM credits with `unm_credits_entering` and `timeline_valid`, `dfw_grades`, `degree_awarded`. Loaded by the app, which stops without it. Roadblocks reads its return, Course Dynamics retention its `enrolled` (I44 closed), every credit position its running totals through `build_credit_timeline()` (`cedar_student_term_credits` is retired) and the Gen Ed major mix its `primary_major_code`, Pathways' classification axis and the Gen Ed graduate cohort its `student_classification`, Dept Trends' SCH by major its `primary_major_code` (named through `name_program_codes()`), Course Dynamics' rollcall and the Waitlists splits its `student_classification` and `primary_major_code` (`attach_student_descriptions()`); the remaining readers move in ADR-001's order |
| `cedar_courses` / `cedar_course_codes` | ~7.5k / ~7.6k | **The course dimension** (ADR-001 step 4), built at startup by `build_cedar_courses()` (`R/branches/courses.R`) from the sections, the class lists and `code_history.csv`; never saved. `cedar_courses` is one row per `course_id`: the last code of a confirmed succession chain (`SOC 371` → `SOCI 371`; `SOC 250` → `SOCI 250` → `SOCI 2315`) or the code itself, with the current `subject` and `course_number`, `level`, latest `course_title`, `first_term` / `last_term` over every code, `n_codes` and `former_codes`. `cedar_course_codes` is one row per code in the data with its `course_id`, where it appears (`in_sections`, `in_class_lists`) and `steps`. **Every loader keys the tables on the course** (decided 2026-11-07): `attach_course_ids()` sets `subject_course` on the loaded `cedar_sections`, `cedar_students` and `cedar_grades` to the `course_id`, keeps the code the registrar used that term as `listed_code`, and writes `course_id` beside them (one shared vector). **So `subject_course` on a loaded table is the course**: a reader that filters, groups or joins on it follows a renamed or renumbered course across its codes with nothing to remember, and a reader that names the term's code (a section listing; "also listed as SOC 371") reads `listed_code`. The saved files keep the registrar's code. A picked code, current or former, resolves through `course_id_of()` / `course_ids_of()` or the shared `course` filter (`filter_DESRs()`, `filter_class_list()`), and the pickers whose readers resolve offer both (`course_picker_choices()`). Readers name a course's former codes from `course_former_code_spans()` (Regstats, Waitlists, the Dashboard), `course_former_codes_note()` (Course Dynamics) and Low Enrollment's history text (`"2 (Sp20); also as SOC 250"`). A cache over the loaded tables records `course_code_renames()` in its key or on its payload (Regstats v6, `cedar_course_terms`, the course flows, the neighbors cache). The enrollment projections read by course from model 0.28.0. The code-level functions alone read the registrar's code (`build_cedar_courses()`, `detect_course_renamings()`). `cedar_attempts` and `cedar_course_terms` are the measure tables (rows below) (ISSUES I37, I45) |
| `cedar_course_terms` | ~61k | **The course-term measure table** (ADR-001 step 4), counted at startup by `build_course_terms()` (`R/branches/course-terms.R`) from the keyed class list and held at `data_objects[["cedar_course_terms"]]`; the copy saved beside the data is a cache, rebuilt unless `course_terms_is_current()` finds its build version (`COURSE_TERMS_BUILD_VERSION`), its columns and the class list's renames. One row per `campus`, `college`, `term`, `subject_course` (the course) and `part_term`, with `level`, `department` and the class-list counts: `registered` (final), `dr_early`, `dr_late`, `dr_all`, `wl_all` (waitlist rows, not true demand), `cl_total` (ever registered) and `census_enrl`. A student is in one part of term of a course-term-campus, so the part-of-term rows sum exactly to course × term × campus. It holds no mean or baseline across terms: that is the reader's question. A reader takes it as a parameter and refuses one not current for its class list (`require_current_course_terms()`): Regstats, the Department Dashboard's Regstats flags and Waitlists' census history read it. Build 2 adds the outcome counts from `cedar_attempts`: `attempts` (the DFW denominator, `passed + dfw`), `passed`, `dfw` and `withdrawn` (late withdrawals, part of `dfw`), zero for a graded course-term with no attempt and **NA after `last_graded`**, where nothing has posted; it is stamped with the `graded_edge` it was counted to, and the loader rebuilds a copy counted to another. First-day enrollment, fill and waitlist demand join it as their readers move |
| `cedar_attempts` | ~1.4M | **The attempt measure table** (ADR-001 step 4), built at startup by `build_attempts()` (`R/branches/attempts.R`) from the keyed class list and the graded edge, held at `data_objects[["cedar_attempts"]]`; the saved copy is a cache, rebuilt unless `attempts_is_current()` finds its build version (`ATTEMPTS_BUILD_VERSION`), `cedar_outcome_policy_version`, columns, `graded_edge` and the class list's renames. One row per `student_id`, `term`, `campus` and `subject_course` (the course; `listed_code` the term's code), with `college`, `part_term`, `level`, `department`, `crn`, `registration_status_code`, `final_grade` as the classifier read it (an early drop is `Drop`, a late drop with no grade `W`), `outcome_category` (pass, c_minus, d, f, other_nonpassing, w_late_withdrawal, early_drop, missing) and `outcome` under the default policy: `pass`, `dfw`, or NA for an early drop or a registered row with no grade. The rows are `prepare_course_attempts()`'s: registered, early-drop and late-drop rows, audits excluded, terms up to `last_graded`; a duplicate student-course-campus-term stops the build. Its per-course-term counts equal `get_course_outcome_rates()` on the same class list. It replaces per-request classification; the readers of saved `cedar_grades` move to it next |
| `cedar_dims` | — | The mapping files as dimension tables (`colleges`, `units`, `subjects`, `programs`, `settings`), built once at startup by `build_cedar_dims()` (`R/branches/dims.R`) and held at `data_objects[["cedar_dims"]]`. Never saved. A cone that needs a dimension by name takes it as `dims`; `attach_unit()` reads it (ADR-001 step 3). Every lookup the retired `cedar_lookups.qs` used to carry is read off it: `unit_names(dims)`, `college_code_names(dims)`, `subject_units(dims)`, and `name_program_codes(codes, dims)` for a program code's display name (programs.csv's, which names every code the data carries, the class-list-only ones as proposed rows; a code with no row is shown as itself and listed by the mapping audit). A department's program names are counted from the programs table by `headcount_program_names()` |

**Every unit is attached at load, by one function (ADR-001 step 3, 2026-11-06).** No saved table stores a unit or a college. `cedar_sections` and `cedar_students` carry the subject and Banner's section college (`source_college`); `cedar_programs` and `cedar_degrees` carry the program code and Banner's two college values (`source_college` and `source_college_code` / `source_student_college`); `cedar_student_terms` carries its primary major's code and the source's college for it (`primary_source_college_code`, `primary_source_college`). The in-memory `department` / `college` / `college_basis` on sections and class-list rows, `dept_code` / `program_college` / `college_code` / `college_basis` / `student_college` on programs and degrees, `primary_dept_code` / `primary_college_code` / `primary_college_basis` on student-terms, and the `crosslist_external` / `crosslist_partners` that follow a department, are written by `attach_default_units()` in `R/branches/dims.R` at every start (`global.R`, the cache-warming scripts, `cedar-repl.R`) through `attach_unit(rows, dims, hierarchy)`: the only code that resolves a unit, wrapping the two rules in `R/lists/institution_files.R`. `tests/testthat/test-architecture.R` ratchets every other resolution site, the transform included. A file stamped by an older transform loads the same way: the loader drops its copy first. The default columns always mean the subject's unit (sections, class lists) or the program's unit (declarations, degrees, student-terms); a reader that wants another hierarchy calls `attach_unit()` with its own `cols`, never into those names. Measured on the 2026-10-08 pull: every value the transform used to stamp is reproduced on all five tables.

**Every course code gets its id at load the same way (ADR-001 step 4, 2026-11-06).** `build_cedar_courses(sections, students, dims)` in `R/branches/courses.R` gives every `subject_course` in either table one `course_id`, following the confirmed rows of `institution/<id>/code_history.csv` step by step (a subject row renames every number under it; a course row renumbers one course; a chain may mix the two), and `attach_course_ids()` keys `cedar_sections`, `cedar_students` and `cedar_grades` on it at every loader beside the units. A proposed row assigns nothing: it is `detect_course_renamings()`'s candidate, written by `scripts/propose-code-history.R --write` with its evidence, and the dimension keeps the two codes as two courses until someone confirms it, exactly as a proposed unit mapping assigns no unit. The saved files are never rewritten (annotate, never mutate): in memory `subject_course` is the course and `listed_code` the term's code. Measured on the 2026-10-08 pull: 7,450 courses from 7,641 codes, the two confirmed subject renames (PSY, SOC) and the 61 CCST → CCS course rows (CCST is the lower-division prefix, CCS still the upper-division one) joining 216 codes; SOCI 371's history now begins Fall 2018 instead of Fall 2021. Build 8 s, attach under a second. A course that splits into two codes has no row by design: the validator refuses a confirmed code with two successors, because one code cannot have two ids.

**The mapping files decide every unit (ADR-002 Stage 3).** A program's unit is the one its row in `institution/<id>/programs.csv` names: the confirmed row for (code, college), else the code's every-college row. Concentrations take the unit of the student's primary major that term. A course's unit comes the same way from `subjects.csv`, keyed on subject, section college (translated through `colleges.csv`, so a renamed college still matches) and level. **A code with no confirmed row has no unit (`NA`)** and is listed on Admin > Data & Usage > Mappings and in the end-of-transform mapping audit: the designed state for a code awaiting a decision, never a department named after itself. Programs no department owns (Non-Degree, Undecided) are `basis = no_unit`. A decision is an edit to the file, through a pull request; it takes effect at the next start, and the deploy restarts the app. Nothing is rebuilt for it. The deploy gate (`scripts/rebuild-programs-if-mappings-changed.R`, also run by every refresh; the name is historical) now builds only `cedar_student_terms`: when it is missing, older than the students, programs or degrees file it reads (by file time), short a column the builder now writes, or stamped with an older rule version than `STUDENT_TERMS_BUILD_VERSION` (bump it when the builder's rules change the values it writes), it is built in its own R process (`--tables student_terms`), so the app never starts without it. The transform keeps every stage's heap until it exits, and one process carrying four tables into the student-term stage was killed for memory on an 8.6 GB host.

**Colleges come from the files too (Stage 3b).** A student counts under their primary major's college that term, on all their rows (`college_code`, `student_college`; each row's own is `program_college`); a course under its subject row's `college_code`, else its unit's home college; a degree under its program's. A code not yet decided reports Banner's college, labelled `college_basis = "banner"`. Banner's values stay beside as `source_college` (and `source_college_code`): the mapping audit reads those, reports never should.

**The self-named fallback is gone and must not return.** The old chain ended at `major_code` itself, giving an unmapped program a department named after its own code that no report could tell from a real one — which is how Radiologic Sciences reported 35 students at department level when it had 229 (ISSUES.md I7). EC-14 in `tests/testthat/test-transform-status.R` fails if it comes back. `program_map.qs` and `R/lists/program_code_maps.R` were retired at Stage 4: the runtime lookups in `catalog_lookups.R` come from the files too, and a pre-major's flag and target are the file's (`is_pre_major`, `leads_to`), never inferred from an F prefix. A department's rows are the rows whose own `dept_code` it is — `filter_programs_to_dept()` in `R/branches/headcount.R`, shared by Headcount, Dept Trends and the Dept Dashboard — never rows matched by program name (ISSUES.md I15).
