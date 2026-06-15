# CEDAR AI Reference

**For writing a new cone or asking focused questions about a specific analysis.** Paste the relevant sections into your AI chat along with your question. This file is intentionally compact — it covers the data model, cone pattern, and common code patterns, and nothing else.

**For broader codebase work** — debugging, adding features, navigating modules, understanding architecture — use `AGENTS.md` instead. It has the full picture: layer rules, coding standards, module patterns, test infrastructure, and refactoring status.

**Instructions for agents:** Verify every column name against the schema below before writing code — AI models commonly invent plausible-sounding column names that don't exist. Check join keys carefully: sections join students on `section_id`; cross-table student tracking uses `student_id`.

---

## CEDAR Data Model

CEDAR organizes institutional data into five standard tables. All column names use `snake_case`.

### `cedar_sections` — one row per course section per term

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `term` | integer | 6-digit term code (YYYYCC) | 202580 (Fall 2025) |
| `crn` | string | Course Reference Number | "12345" |
| `subject` | string | Subject code | "MATH" |
| `course_number` | string | Course number | "1350" |
| `subject_course` | string | Combined (used for filtering) | "MATH 1350" |
| `section` | string | Section number | "001" |
| `course_title` | string | Course title | "Calculus I" |
| `campus` | string | Campus | "Main", "Online" |
| `college` | string | College code | "AS" |
| `department` | string | Department code | "MATH" |
| `instructor_id` | string | Encrypted instructor ID | join key to cedar_faculty |
| `instructor_name` | string | Instructor name | "Smith, Jane" |
| `enrolled` | integer | Current enrollment count | 28 |
| `capacity` | integer | Section capacity | 30 |
| `status` | string | Section status | "A" (active), "C" (cancelled) |
| `delivery_method` | string | Mode of delivery | "F2F", "Online", "Hybrid" |
| `level` | string | Course level | "lower", "upper", "grad" |
| `term_type` | string | Term type | "fall", "spring", "summer" |
| `part_term` | string | Part of term | "FT" (full), "1H", "2H" |
| `is_combined` | logical | Combined lecture+lab (C-suffix course, e.g. BIOL 2110C) | TRUE/FALSE |
| `is_topics` | logical | Topics course with T: prefix in title | TRUE/FALSE |

**Key note:** Term codes end in 10 (spring), 60 (summer), 80 (fall). Course level: below 300 = "lower", 300–499 = "upper", 500+ = "grad".

---

### `cedar_students` — one row per student per section (class lists)

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `enrollment_id` | string | Unique row ID | — |
| `section_id` | string | FK to cedar_sections | "202580-12345" |
| `student_id` | string | Encrypted student ID | join key across tables |
| `term` | integer | Term code | 202580 |
| `subject_course` | string | Course (denormalized) | "MATH 1350" |
| `campus` | string | Course campus | "Main" |
| `college` | string | Course college | "AS" |
| `department` | string | Course department | "MATH" |
| `registration_status_code` | string | Status | "RE" (registered), "DR" (dropped), "W" (withdrawn) |
| `final_grade` | string | Final grade | "A", "B+", "C", "W", "F", "I" |
| `student_level` | string | Student level | "UG", "GR" |
| `student_classification` | string | Class standing | "FR", "SO", "JR", "SR" |
| `major` | string | Student's major code | "MATH-BS" |
| `student_college` | string | Student's college | "AS" |
| `term_type` | string | Term type | "fall", "spring", "summer" |

**Key note:** `student_id` is encrypted — never plaintext. Use it as a join key across tables to track the same student across terms. `major` stores the raw Banner program code (e.g. `"NURS"`), not a human-readable name — join against `cedar_programs` for program names or dept assignment. For course outcome rates, use `get_course_outcome_rates()` rather than hardcoding grade/status rules.

### Grade Data In Cones

Use the focused grade APIs instead of the legacy gradebook bundle:

- `get_course_outcome_rates(students, opt, group_cols, min_n)` for DFW, W, D/F, C-, below-C, and early-drop metrics.
- `get_grade_distribution(students, opt, group_cols, min_n)` for A/B/C/D/F/W/Other counts and percentages.
- `prepare_course_attempts(students, opt)` only when the cone needs row-level cleaned attempts.
- Avoid `get_grades()` in new cones unless you explicitly need the legacy report bundle.

`get_course_outcome_rates()` returns stable columns including `n_attempts`, `n_pass`, `n_c_minus`, `n_d`, `n_f`, `n_w`, `n_early_drop`, `dfw_pct`, `w_pct`, `df_pct`, and `below_c_pct`.

---

### `cedar_programs` — one row per student-program per term

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `student_id` | string | Encrypted student ID | join key |
| `term` | integer | Term code | 202580 |
| `program_type` | string | Type | "Major", "Minor", "Concentration" |
| `program_name` | string | Full program name | "Mathematics BS" |
| `college` | string | Program's college | "AS" |
| `department` | string | Program's department | "MATH" |
| `student_level` | string | UG or GR | "UG" |

---

### `cedar_degrees` — one row per degree awarded

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `student_id` | string | Encrypted student ID | join key |
| `term` | integer | Graduation term | 202510 |
| `degree` | string | Degree type | "BS", "BA", "MS", "PhD" |
| `program_name` | string | Program name | "Mathematics BS" |
| `college` | string | College | "AS" |
| `department` | string | Department | "MATH" |
| `graduation_status` | string | Status | "Conferred", "Pending" |

---

### `cedar_faculty` — one row per instructor per term

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `instructor_id` | string | Encrypted ID (matches cedar_sections) | join key |
| `instructor_name` | string | Full name | "Smith, Jane D." |
| `term` | integer | Term code | 202580 |
| `department` | string | Home department | "MATH" |
| `job_category` | string | Employment type | "Professor", "Associate Professor", "Assistant Professor", "Lecturer", "Term Teacher", "TPT", "Grad" |
| `appointment_pct` | numeric | Appointment percent, stored 0–100 | Divide by 100 for FTE: 100 = full-time, 50 = half-time |

**Key note:** Only "Professor", "Associate Professor", "Assistant Professor", and "Lecturer" count as permanent faculty for SFR calculations. `appointment_pct` is always 0.0–1.0, not a percentage.

---

### Table relationships

```
cedar_sections
    ├── cedar_students    (join on section_id)
    │       ├── cedar_programs   (join on student_id)
    │       └── cedar_degrees    (join on student_id)
    └── cedar_faculty     (join on instructor_id + term)
```

---

## Cone pattern

A cone is an R function that accepts CEDAR data, filters it via an options list, analyzes it, and returns a standardized result.

### Function signature

```r
my_cone <- function(students, courses, opt, additional_data = NULL) {
  # students        = cedar_students
  # courses         = cedar_sections
  # opt             = named list of filters and options
  # additional_data = optional: list with degrees, programs, faculty
}
```

### Standard options (`opt`)

```r
opt <- list(
  term     = 202580,      # integer term code; may be a vector for multi-term
  dept     = "MATH",      # department code filter (optional)
  college  = "AS",        # college code filter (optional)
  course   = "MATH 1350", # subject_course filter (optional)
  level    = "upper",     # course level filter (optional)
  status   = "A",         # section status filter; default "A" for active only
  uel      = TRUE         # use exclude list (ignore certain sections)
)
```

### Full cone template

```r
# [cone-name].R
# Question: [One sentence describing what question this cone answers]

#' [Function title]
#'
#' [Brief description of the approach and what the result contains]
#'
#' @param students cedar_students data frame
#' @param courses  cedar_sections data frame
#' @param opt      Named list of options (term required; dept, college, course optional)
#' @return Named list with: data (data frame), metadata (list)

my_cone <- function(students, courses, opt) {

  # 1. Validate required options
  if (is.null(opt$term)) stop("opt$term is required")

  # 2. Set defaults using %||% (defined in trunk/utils.R)
  status <- opt$status %||% "A"

  # 3. Filter sections using the trunk helper (handles campus/dept/college/term/level/etc.)
  sections <- filter_DESRs(courses, opt)

  # 4. Filter students to the same scope using the trunk helper
  enrolled <- filter_class_list(students, opt)

  # 5. [Your analysis here]
  result <- enrolled %>%
    group_by(subject_course, term) %>%
    summarize(
      n_students = n_distinct(student_id),
      # ...
      .groups = "drop"
    )

  # 6. Return standardized result
  return(list(
    data = result,
    metadata = list(
      function_name = "my_cone",
      options_used  = opt,
      row_count     = nrow(result)
    )
  ))
}
```

---

## Common patterns

### Track students across terms (course sequences)

```r
course_a_students <- cedar_students %>%
  filter(subject_course == "CHEM 1215", term == 202480) %>%
  select(student_id, grade_in_a = final_grade)

course_b_students <- cedar_students %>%
  filter(subject_course == "CHEM 1225", term == 202510) %>%
  select(student_id, grade_in_b = final_grade)

sequence <- course_a_students %>%
  inner_join(course_b_students, by = "student_id")
```

### DFW rate by group

```r
get_course_outcome_rates(
  cedar_students,
  opt = list(term = opt$term, dept = opt$dept),
  group_cols = "subject_course",
  min_n = 5
)
```

### Join sections to faculty

```r
sections %>%
  left_join(
    cedar_faculty %>% select(instructor_id, term, job_category, appointment_pct),
    by = c("instructor_id", "term")
  )
```

### Enrollment by level over time

```r
cedar_sections %>%
  filter(status == "A", department == opt$dept) %>%
  group_by(term, term_type, level) %>%
  summarize(
    sections  = n(),
    enrolled  = sum(enrolled),
    .groups = "drop"
  )
```

---

## Prompting tips

- **Be specific about the question:** "What predicts success in CHEM 1225 given prior CHEM 1215 grade?" is better than "analyze course outcomes."
- **Name the tables you need:** Most questions use `cedar_students` and `cedar_sections`; cross-term questions need joins on `student_id`.
- **Ask for the opt pattern:** Request that the cone accept `opt$dept`, `opt$term`, etc. so it's generalizable.
- **Verify column names:** AI models may invent plausible-sounding column names. Check every column reference against the schema above.
- **Check join keys:** The most common error is joining on the wrong column. Confirm: sections join students on `section_id`; student-level joins across tables use `student_id`.
