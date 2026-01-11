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
| `term_type` | string | Term type | "fall", "spring", "summer" | Forecasting (82 uses!) |
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

## 2. `cedar_enrollments` (Student Registrations)

**Purpose:** One row per student per course section (enrollment records)

### Required Columns
**These columns are used throughout Cedar code - features will break without them**

| Column | Type | Description | Example | Usage Count |
|--------|------|-------------|---------|-------------|
| `enrollment_id` | string | Unique identifier | Auto-increment or hash | - |
| `section_id` | string | **FK** to cedar_sections | "202580-12345" | Join key |
| `student_id` | string | **Encrypted** student ID | Hash of real ID | 19 uses |
| `term` | integer | Academic term code | 202580 | 113 uses! |
| `subject_course` | string | Course (denormalized) | "MATH 1350" | Pathway analysis |
| `campus` | string | Course campus | "Main", "ABQ" | 72 uses! |
| `college` | string | Course college | "AS" | 45 uses! |
| `department` | string | Course department | "MATH" | Filtering |
| `registration_status` | string | Enrollment status | "Registered", "Dropped" | 3 uses |
| `registration_status_code` | string | Status code | "RE", "RS", "DR", "W" | 14 uses |
| `grade` | string | Final grade (if term complete) | "A", "B+", "W", "I" | 40 uses! |
| `student_level` | string | Student level | "UG", "GR" | 19 uses |
| `student_classification` | string | Class standing | "FR", "SO", "JR", "SR" | 3 uses |
| `primary_major` | string | Student's major code | "MATH-BS" | Headcount |
| `student_college` | string | Student's college code | "AS" | 4 uses |
| `student_campus` | string | Student's campus | "Main" | 9 uses |
| `term_type` | string | Term type (denormalized) | "fall", "spring" | Rollcall analysis |
| `as_of_date` | date | When data was extracted | "2025-01-10" | Data freshness |

**Important Notes:**
- `student_id` **must be encrypted/hashed** - never store plaintext student IDs!
- `term` is most-used column (113 references) - absolutely critical
- `campus` (72 uses) and `college` (45 uses) are heavily filtered
- Some columns like `subject_course`, `campus`, `college`, `term_type` are denormalized from sections for query performance

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
- **Relationship:** Links to `cedar_sections` via `section_id`
- **Size:** This is typically the largest table (millions of rows)

---

## 3. `cedar_programs` (Student Academic Programs)

**Purpose:** Student major, minor, concentration enrollment by term

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `program_id` | string | Unique identifier | Auto-increment |
| `student_id` | string | **Encrypted** student ID | Hash |
| `term` | integer | Academic term | 202580 |
| `program_type` | string | Type of program | "Major", "Minor", "Concentration" |
| `program_code` | string | Program code | "MATH-BS" |
| `program_name` | string | Program full name | "Mathematics BS" |
| `college` | string | College offering program | "AS" |
| `department` | string | Department offering program | "MATH" |
| `as_of_date` | date | When data was extracted | "2025-01-10" |

### Optional Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `degree` | string | Degree type | "BS", "BA", "MS", "PhD" |
| `classification` | string | Program classification | "Undergraduate", "Graduate" |
| `catalog_year` | integer | Catalog student follows | 202580 |
| `program_status` | string | Active, graduated, etc. | "Active" |
| `declared_date` | date | When program was declared | "2023-09-01" |

---

## 4. `cedar_degrees` (Graduates)

**Purpose:** Awarded degrees and pending graduates

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `degree_id` | string | Unique identifier | Auto-increment |
| `student_id` | string | **Encrypted** student ID | Hash |
| `degree_term` | integer | Graduation term | 202510 |
| `degree_type` | string | Degree awarded | "BS", "BA", "MS", "PhD" |
| `program_code` | string | Program code | "MATH-BS" |
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

## 5. `cedar_faculty` (Instructor Information)

**Purpose:** Faculty/instructor metadata for linking to course sections

### Required Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `instructor_id` | string | Unique instructor ID | "123456" |
| `term` | integer | Academic term | 202580 |
| `instructor_name` | string | Full name | "Smith, John D." |
| `department` | string | Home department | "MATH" |
| `as_of_date` | date | When data was extracted | "2025-01-10" |

### Optional Columns

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `academic_title` | string | Academic rank | "Professor", "Associate Professor" |
| `job_title` | string | Administrative title | "Department Chair" |
| `job_category` | string | Employment category | "Professor", "Lecturer", "Adjunct" |
| `appt_percent` | numeric | Appointment % | 100, 50 |
| `email` | string | Email address | "jsmith@university.edu" |
| `college` | string | College affiliation | "AS" |

---

## Relationships Between Tables

```
cedar_sections
    ├─► cedar_enrollments (via section_id)
    │       └─► cedar_programs (via student_id)
    │       └─► cedar_degrees (via student_id)
    └─► cedar_faculty (via instructor_id)
```

### Key Foreign Key Relationships

1. **sections → enrollments:** `cedar_sections.section_id` = `cedar_enrollments.section_id`
2. **sections → faculty:** `cedar_sections.instructor_id` = `cedar_faculty.instructor_id`
3. **enrollments → programs:** `cedar_enrollments.student_id` = `cedar_programs.student_id`
4. **enrollments → degrees:** `cedar_enrollments.student_id` = `cedar_degrees.student_id`

---

## Data Size Expectations

Typical data volumes for a mid-sized university (~25,000 students):

| Table | Rows per Term | Total (5 years) | Memory (approx) |
|-------|--------------|-----------------|-----------------|
| `cedar_sections` | 5,000 - 8,000 | 40,000 - 60,000 | 5-10 MB |
| `cedar_enrollments` | 100,000 - 150,000 | 750,000 - 1M | 60-100 MB |
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
cedar_enrollments %>%
  left_join(cedar_sections, by = "section_id") %>%
  filter(student_id == "hashed_id") %>%
  select(term, subject, course_number, section, grade)
```

### Count majors by program
```r
cedar_programs %>%
  filter(term == 202580, program_type == "Major") %>%
  group_by(program_code) %>%
  summarize(headcount = n_distinct(student_id))
```

### DFW rates by course
```r
cedar_enrollments %>%
  left_join(cedar_sections, by = "section_id") %>%
  filter(term >= 202080, grade %in% c("D", "F", "W")) %>%
  group_by(subject, course_number) %>%
  summarize(
    dfw_count = n(),
    total_count = n_distinct(enrollment_id)
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
cedar_enrollments <- class_lists %>%
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
