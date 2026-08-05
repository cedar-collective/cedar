# Source → CEDAR Field Manifest

**Audience:** a database administrator who has institutional student data and
needs to know exactly what to produce so CEDAR can ingest it.

This is the complete contract. Every CEDAR column is listed with where its value
comes from: a source field, a computation, or a lookup. If you can produce the
**Required** fields below with the stated vocabulary, CEDAR will run.

Generated from `R/data-parsers/transform-to-cedar.R` on 2026-07-31. When that
file changes, update this one in the same commit — see
[Rule 1](#rule-1-one-vocabulary-per-concept).

---

## 0. The source extracts

**CEDAR is a student-data platform.** Four extracts carry the product; a fifth
(faculty) is frozen and slated for retirement.

| CEDAR table | source file (in `data/`) | UNM origin | rows | status |
|---|---|---|---|---|
| `cedar_students` | `class_lists` | MyReports class lists | 1,687,084 | **core** — enrollment backbone |
| `cedar_programs` | `academic_studies` | MyReports academic studies | 464,011 | **core** — declared programs |
| `cedar_degrees` | `degrees` | Degrees awarded | 63,284 | **core** — completions |
| `cedar_sections` | `DESRs` | Dept Enrollment Status Report | 241,941 | **core** — the schedule students enroll in |
| `cedar_faculty` | `hr_data` | HR appointments | 37,675 | ⚠ **frozen / deprecated** — see §5 |

Note the two naming conventions: **DESRs uses UPPERCASE Banner codes**
(`SUBJ`, `CAMP`, `DEPT`); **the three student extracts use Title Case MyReports
labels** (`Student Campus Code`, `Translated College`). This is a source-system
artifact, not a CEDAR requirement — what matters is that you map to the right
CEDAR column with the right vocabulary.

### The student-data path at a glance

```
class_lists      → cedar_students   ─┐ student_id + term
academic_studies → cedar_programs   ─┤────────────────────→ one student's
degrees          → cedar_degrees    ─┘                       full record
                                     
DESRs            → cedar_sections   ←── section_id / subject_course + term
```

A student's story is assembled by joining `cedar_students` (what they enrolled
in) to `cedar_programs` (what they declared) on `student_id + term`, then to
`cedar_degrees` (what they finished) on `student_id`. Those three joins are
safe. **The joins that are not safe are on campus, college, and student level —
see §6a.**

---

## 1. `cedar_sections` ← `DESRs`

The course schedule. One row per section per term.

### Direct from source

| CEDAR column | source field | notes |
|---|---|---|
| `term` | `TERM` | integer, e.g. `202580` |
| `crn` | `CRN` | |
| `subject` | `SUBJ` | **code** (`HIST`) |
| `course_number` | `CRSE` | |
| `subject_course` | `SUBJ_CRSE` | `"HIST 1105"` |
| `section` | `SECT` | |
| `course_title` | `SECT_TITLE` | |
| `part_term` | `PT` | optional |
| `campus` | `CAMP` | **code** (`ABQ`) |
| `college` | `COLLEGE` | **code** (`AS`) |
| `department` | `DEPT` | **code** (`HIST`) |
| `instructor_id` | `PRIM_INST_ID` | |
| `instructor_name` | `INST_NAME` | |
| `enrolled` | `ENROLLED` | |
| `capacity` | `SECT_CAP`, else `ROOM_CAP` | |
| `available` | `SEATS_AVAIL` | |
| `status` | `STATUS` | `A` active, `C` cancelled |
| `delivery_method` | `INST_METHOD` | |
| `crosslist_code` | `XL_CODE` | optional, default `"0"` |
| `crosslist_subject` | `XL_SUBJ` | optional |
| `waitlist_count` | `WAIT_COUNT` | optional |
| `waitlist_capacity` | `WAIT_CAPACITY` | optional |
| `start_date` / `end_date` | `START_DATE` / `END_DATE` | `%m/%d/%Y` |
| `census1` | first of `CENSUS1`, `CENSUS_1`, `CENSUS1_DATE`, `census1` | census date; any one spelling |
| `comments` | first of `COMMENTS`, `Comments`, `comments`, `COMMENT` | any one spelling |
| `credits_min` / `credits_max` | `MIN_CR` / `MAX_CR` | |
| `as_of_date` | `as_of_date` | extract date |

### Derived by CEDAR (do not supply)

| column | how |
|---|---|
| `section_id` | `TERM-CRN` |
| `level` | from course number (lower / upper / grad) |
| `term_type` | from term code (fall / spring / summer) |
| `gen_ed_area` | lookup: `gen_ed_courses.R` |
| `is_combined` | `CRSE` ends in `C` |
| `is_topics` | title begins `T:` |
| `total_enrl` | crosslist-aware combined enrollment |
| `crosslist_group`, `crosslist_primary`, `crosslist_role`, `crosslist_partners`, `crosslist_external`, `is_split`, `split_sections` | crosslist resolution |

---

## 2. `cedar_students` ← `class_lists`

Enrollment records. One row per student per section per term. **The largest
table and the backbone of most analysis.**

### Direct from source

| CEDAR column | source field | vocabulary |
|---|---|---|
| `crn` | `Course Reference Number` | |
| `student_id` | `Student ID` | encrypted on ingest |
| `term` | `Academic Period Code` | integer |
| `subject_course` | `SUBJ_CRSE` | |
| `course_title` | `Short Course Title` | |
| `instructor_id` | `Primary Instructor ID` | |
| `campus` | `Course Campus Code` | **CODE** |
| `college` | `Course College Code` | **CODE** |
| `department` | `DEPT`, else `Department` | **CODE** |
| `registration_status` | `Registration Status` | |
| `registration_status_code` | `Registration Status Code` | `RE`, `DW`… |
| `registration_date` | `Registration Status Date` | |
| `final_grade` | `Final Grade` | |
| `credits` | `Course Credits` | |
| `total_credits` | `Total Credits` | |
| `student_level` | `Student Level Code` | **CODE** ⚠ |
| `student_classification` | `Student Classification` | |
| `major_code` | `Major Code` | **CODE** |
| `major_name` | `Major` | name |
| `student_college` | `Student College Code` | **CODE** ⚠ |
| `student_campus` | `Student Campus Code` | **CODE** ⚠ |
| `residency` | `Residency` | |
| `dual_credit` | `Dual Credit` | `Y` → TRUE |
| `part_term` | `Sub-Academic Period Code` | |

### Derived

| column | how |
|---|---|
| `enrollment_id` | row number |
| `subject_code` | first token of `SUBJ_CRSE` |
| `level`, `term_type` | as in sections |
| `instructor_name` | assembled from first/last |

⚠ **`student_campus`, `student_college`, and `student_level` here are CODES.**
The same three column names in `cedar_programs` hold NAMES. See §6a and
[Rule 1](#rule-1-one-vocabulary-per-concept).

---

## 3. `cedar_programs` ← `academic_studies`

Declared programs. One row per student per program per term. Drives headcount,
Pathways populations, and demographics.

### Direct from source

| CEDAR column | source field | vocabulary |
|---|---|---|
| `student_id` | `ID` | encrypted |
| `term` | `term_code` | integer |
| `program_classification` | `Program Classification` | |
| `degree` | `Degree` | |
| `student_classification` | `Student Classification` | |
| `student_level` | `Student Level` | **NAME** ⚠ |
| `student_campus` | `Student Campus` | **NAME** ⚠ |
| `student_college` | `Translated College` | **NAME** ⚠ |
| `student_population` | `Student Population` | |
| `inst_credits_attempted` | `Institution Credits Attempted` | |
| `overall_credits_attempted` | `Overall Credits Attempted` | |
| `overall_credits_earned` | `Overall Credits Earned` | |
| `pell_eligible` | `Pell Eligible Indicator` | `Y` → TRUE |
| `first_gen` | `First Generation Indicator` | `Yes` → TRUE |
| `ipeds_race` | `IPEDS Race` | |
| `gender` | `Gender` | |
| `time_status` | `Current Time Status Code` | |
| `residency` | `Residency` | |
| `academic_standing` | `Academic Standing` | |
| `inst_gpa` | `Institution GPA` | |

### Derived / lookup

| column | how |
|---|---|
| `program_type` | Major / Second Major / First Minor / … (pivoted from source columns) |
| `program_name`, `major_code`, `program_code` | resolved per program slot |
| `college_code` | **lookup** `college_name_to_code[student_college]` — **CODE** |
| `dept_code` | **lookup** chain: `major_college_to_dept` → `subj_to_dept` → `major_to_dept` |
| `is_pre_major` | `program_name` starts with `Pre-` |

⚠ **`student_campus`, `student_college`, and `student_level` here are NAMES**
(`Albuquerque/Main`, `College of Arts and Sciences`, `Undergraduate`) while the
same columns in `cedar_students` hold codes. For campus this is forced —
`academic_studies` exposes **no** `Student Campus Code` column. For level and
college the source offers both forms and this transform chose the label. See
§6a.

---

## 4. `cedar_degrees` ← `degrees`

Completions. One row per student per awarded program.

| CEDAR column | source field | vocabulary |
|---|---|---|
| `student_id` | `ID` | encrypted |
| `term` | `Academic Period Code` | |
| `student_college` | `Actual College` | **NAME** ⚠ |
| `degree` | `Degree` | |
| `award_category` | `Award Category` | |
| `program_code` | `Program Code` | |
| `program_name` | `Program` | |
| `college` | `Translated College` | **NAME** ⚠ |
| `department` | `Department` | |
| `graduation_status` | `Graduation Status` | |
| `campus` | `Campus` | **NAME** ⚠ |
| `major` | `Major` | name |
| `major_code` | `Major Code`, else parsed from `Program Code` | **CODE** |
| `second_major`, `first_minor`, `second_minor` | same-named fields | |
| `cumulative_gpa` | `Cumulative GPA` | |
| `cumulative_credits` | `Cumulative Credits Earned` | |
| `honors` | `Honor` | |
| `admitted_term` | `Academic Period Admitted` | |

### Derived / lookup

| column | how |
|---|---|
| `degree_id` | `term-ID-ProgramCode` |
| `dept_code` | same three-tier lookup as programs |
| `degree_abbr` | leading token of `program_code` |

⚠ `college`, `student_college`, and `campus` are all **NAMES** here, so they do
not join to `cedar_sections` / `cedar_students`, which use codes.

---

## 5. `cedar_faculty` ← `hr_data` — FROZEN, slated for retirement

**Do not build against this table.** HR appointment data is no longer available
to the project. The shipped snapshot is frozen at `as_of_date 2025-04-07`
(terms 201780–202580) and cannot be refreshed.

| CEDAR column | source field |
|---|---|
| `instructor_id` | `UNM ID` |
| `term` | `term_code` |
| `instructor_name` | `Name` |
| `department` | `DEPT` |
| `academic_title` | `Academic Title` |
| `job_title` | `Job Title` |
| `job_category` | `job_cat` |
| `appointment_pct` | `Appt %` |
| `college` | `Home Organization Desc` |

> **Transform drift (2026-07-31):** `transform_faculty()` emits `college`, but
> the shipped `cedar_faculty.qs` carries `home_org` — a name that appears
> nowhere else in the codebase. The current transform cannot reproduce the
> current data file. Given the retirement below, resolve by deleting rather
> than repairing.

### Retirement scope (verified 2026-07-31)

Smaller than it looks. Only **one user-facing surface** consumes it:

- **Dept Trends → Credit Hours**, two plots: `chd_by_fac_facet_plot` and
  `chd_by_fac_plot` (registered in `dept-trends.R`'s `plot_map`).

Everything else is either already absence-tolerant or dead:

- `credit_hours_by_fac()` already returns `"No faculty data available"` when the
  table is empty — the graceful path exists and is exercised.
- `R/cones/sfr.R` (student-faculty ratio) has **no UI surface at all** — no
  module, `ui.R`, or `server.R` reference. Dead code; retire with faculty.
- `data.R` exports `.GlobalEnv$faculty` / `fac_by_term`, `global.R` counts rows
  at startup, and `seatfinder.R` / `course-outcomes.R` / `course-report.R`
  reference it defensively.

Retiring means: drop the two Credit Hours plots, delete `sfr.R` and
`transform_faculty()`, remove the startup load and globals, and drop
`cedar_faculty` from `required_datasets`. `job_cat` on `cedar_sections` is
populated at transform time from HR and would become `NA` — check whether
anything reads it before removing the join.

---

## 6a. The overlap: one MyReports concept, several CEDAR tables

MyReports exposes the same student attribute on more than one extract, so the
same concept lands in several CEDAR tables. **Whether those copies agree is not
guaranteed by anything — it depends entirely on which source field each
transform reached for.** Measured agreement (share of the union of observed
values present in both):

| concept | students | programs | degrees | agreement | |
|---|---|---|---|---|---|
| Student Classification | ✅ 32 | ✅ 32 | — | **100%** | safe |
| Degree | — | ✅ 70 | ✅ 66 | 94% | safe |
| Residency | ✅ 6 | ✅ 5 | — | 83% | safe |
| Major Code | ✅ 393 | ✅ 406 | ✅ 261 | 75% / 53% | ⚠ population differences, same vocabulary |
| **Student Level** | ✅ 9 | ✅ 8 | — | **0%** | ❌ **different vocabularies** |
| **Campus** | ✅ codes | ✅ names | ✅ names | **0%** | ❌ **different vocabularies** |
| **College** | ✅ codes | ✅ names | ✅ names | **0%** | ❌ **different vocabularies** |

### The three broken ones, in source terms

This is the whole defect, visible in the mapping:

```
cedar_students.student_level   ←  `Student Level Code`   →  UG, GR, AD, LW …
cedar_programs.student_level   ←  `Student Level`        →  Undergraduate, Graduate/GASM …

cedar_students.student_campus  ←  `Student Campus Code`  →  ABQ, GA, LA, TA, VA
cedar_programs.student_campus  ←  `Student Campus`       →  Albuquerque/Main, Gallup …

cedar_students.student_college ←  `Student College Code` →  AS, EH, FA …
cedar_programs.student_college ←  `Translated College`   →  College of Arts and Sciences …
```

One transform took the `... Code` field; the other took the bare label. Same
CEDAR column name, incompatible values, no declaration anywhere that they
differ.

### What that costs today

The application compensates per call site instead of the schema being right.
From `R/cones/health-whatif.R`, two adjacent lines filtering the same concept:

```r
programs <- programs %>% filter(student_level == "Undergraduate")   # NAME
students <- students %>% filter(student_level == "UG")              # CODE
```

Every author who touches these tables has to know this. Nothing enforces it,
nothing errors when it is violated — a cross-vocabulary filter returns zero
rows, which reads as "no data" rather than "wrong join."

### For a new institution

If your warehouse exposes both a code and a label for an attribute, **pick one
and use it in every table.** Store the code; resolve the label at display time
through a lookup. Where an extract offers only the label (as UNM's
`academic_studies` does for campus), convert at ingest — do not store the label
under the same column name another table uses for a code.

---

## 6. How the tables join

| from → to | key | safe? |
|---|---|---|
| `students` → `sections` | `term` + `crn` | ✅ |
| `students` → `programs` | `student_id` + `term` | ✅ |
| `programs` → `degrees` | `student_id` | ✅ |
| `sections` → `faculty` | `instructor_id` + `term` | ✅ |
| `students` → `sections` | `subject_course` + `term` | ✅ |
| **any → any on `campus`** | — | ❌ two vocabularies |
| **any → any on `college`** | — | ❌ two vocabularies |
| `programs`/`degrees` → others on `dept_code` vs `department` | — | ⚠ same concept, two column names, 39–58% value overlap |

---

## 7. Vocabulary rules

### Rule 1: one vocabulary per concept

A concept must use the same representation everywhere. CEDAR's convention is
**store codes; resolve names for display via a lookup**, as `dept_code_to_name`
already does.

**Currently violated.** Measured overlap is 0% — a cross-vocabulary filter
returns zero rows rather than an error:

| concept | CODE columns | NAME columns |
|---|---|---|
| campus | `sections.campus`, `students.campus`, `students.student_campus` | `programs.student_campus`, `degrees.campus` |
| college | `sections.college`, `students.college`, `students.student_college`, `programs.college_code` | `programs.student_college`, `degrees.college`, `degrees.student_college` |
| student level | `students.student_level` | `programs.student_level` |

The campus label↔code map is derivable from data (`student_id` + `term` join),
clean 1:1: `Albuquerque/Main↔ABQ`, `Valencia↔VA`, `Gallup↔GA`,
`Los Alamos↔LA`, `Taos↔TA`.

### Rule 2: never reuse a column name for a different vocabulary

`student_campus` and `student_college` each mean one thing in `cedar_students`
(code) and another in `cedar_programs` (name). If two columns cannot hold the
same values, they must not share a name.

### Rule 3: distinguish "student's college" from "program's college"

`programs.student_college` (student's home college) and `programs.college_code`
(the program's college) are **different concepts**, not a vocabulary split. One
student legitimately produces `College of Arts and Sciences` / `GP`. Do not
"fix" this by aligning them.

### Rule 4: one name per concept across tables

`department` (sections, students, faculty) and `dept_code` (programs, degrees)
are the same concept. Pick one.

---

## 8. Validation checklist for a new institution

1. **Field coverage** — supply every Required field above. Missing optional
   fields become `NA`; missing required fields fail the transform.
2. **Vocabulary** — decide code-or-name per concept and apply it to *every*
   table. If your warehouse only exposes labels for one extract (as UNM's
   `academic_studies` does for campus), convert at ingest rather than storing
   both forms under one name.
3. **Term codes** — integer `YYYYPP`, sortable, with `term_type` derivable.
4. **Lookups** — populate `subj_to_dept`, `major_to_dept`, `dept_code_to_name`,
   `college_name_to_code` for your institution. Run
   `Rscript scripts/audit-mappings.R` and confirm coverage; unmapped values
   surface in Admin → Data & Usage via `cedar_mapping_issues`.
5. **Round-trip** — re-run the transform and diff column names against the
   previous output. The faculty drift in §5 is what happens when this step is
   skipped.

---

## 9. What this manifest would have prevented

Of the mapping defects found in the 2026-07 audit
([mapping-audit-2026-07.md](mapping-audit-2026-07.md)):

**Would have been caught** — these are source→column decisions, visible the
moment two rows sit next to each other in a table like §2/§3:

- `cedar_students.student_campus ← Student Campus Code` vs
  `cedar_programs.student_campus ← Student Campus`
- the same split for `student_college`
- `cedar_degrees` shipping names for `college`/`campus`
- the Pathways campus default that selected nothing
- the faculty `college` / `home_org` drift

**Would not have been caught** — these are lookup *content* and internal API
problems that a field manifest does not describe. They need
`scripts/audit-mappings.R` and startup assertions:

- `subj_to_dept`'s 5 silently shadowed duplicate keys
- `dept_code_to_name` at 61% coverage
- `opt$dept` vs `opt$dept_code` in the warm scripts

A manifest locks the **ingest contract**. The audit script locks the **lookup
content**. Both are required.
