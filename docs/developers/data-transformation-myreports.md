---
title: Data Transformation
nav_order: 8
parent: Developer Guide
---

# Transforming MyReports Data to CEDAR Model

**For institutions using MyReports** (common in higher education)

This guide explains how standard MyReports exports are transformed into CEDAR's normalized data model.

---

## Overview

Cedar uses a **two-phase data pipeline**:

### Phase 1: MyReports Aggregation (Existing Process)
Your existing `parse-data.R` script reads MyReports Excel files and creates aggregate tables with **ALL columns** preserved:

```
MyReports Excel Files
        ↓
parse-data.R (unchanged)
        ↓
DESRs.qs (73 columns - ALL fields including gender, ethnicity, etc.)
class_lists.qs (74 columns - FULL data preserved)
academic_studies.qs (83 columns)
degrees.qs (46 columns)
```

**Purpose:** Complete institutional data warehouse with all fields for future analytics

### Phase 2: CEDAR Transformation (New)
After aggregation, `transform-to-cedar.R` creates streamlined CEDAR tables:

```
Aggregate Files (DESRs.qs, etc.)
        ↓
transform-to-cedar.R (daily)
        ↓
cedar_sections.qs (21 columns - streamlined for performance)
cedar_registrations.qs (the class list; cedar_students.qs before 2026-11-09)
cedar_programs.qs (10 columns)
cedar_degrees.qs (14 columns)
```

**Purpose:** Normalized, institution-agnostic tables optimized for Cedar analytics

---

## MyReports → CEDAR Mapping

| Code | MyReports Report | Parsed file | → | CEDAR Table | Scheduled refresh |
|------|------------------|-------------|---|-------------|-------------------|
| `desr` | **DESR** (Department Enrollment Status Report) | DESRs.qs | → | `cedar_sections` | daily |
| `cl` | **Class Lists** | class_lists.qs | → | `cedar_registrations` | daily |
| `as` | **Academic Study Detail** | academic_studies.qs | → | `cedar_programs` | daily |
| `deg` | **Graduates & Pending Graduates** | degrees.qs | → | `cedar_degrees` | daily |
| `aa` | **Admissions Applicants Detail** | admissions_applicants.qs | → | `cedar_applicants` | only when named |
| `holds` | **Student Holds** | student_holds.qs | → | `cedar_holds` | only when named |

The code is what is typed on every command line. The list itself lives in
`R/data-parsers/report-specs.R` (for the parser) and
`scripts/report-registry.sh` (for the shell scripts); this table is a reading
aid.

---

## Adding a MyReports report

A report is fetched by mrgather, parsed by `parse-data.R` into an accumulated
file, and built into a `cedar_*` table by one stage of `transform-to-cedar.R`.
Adding one touches five files in two projects. The Student Holds report
(2026-11) is the worked example: search for `holds` in each file below.

### First, pull one term by hand

Run the report once in a browser, for one term, with every column, as Excel.
The file answers the questions the code depends on, and none of them can be
guessed from the form:

| Find out | Why | Student Holds |
|---|---|---|
| The download's file name | Files are matched to their report by a piece of the name every download carries | `S_Student_Holds_<date>_<time>.xlsx` |
| Which line holds the column names, and whether the export ends in lines that are not rows | A title above the table makes the file read as having no column names; a footer line is otherwise hashed as a person | title on line 1, names on line 3, a "ran on" line at the end |
| Which columns identify a person, and which are direct identifiers | The first are hashed, the second dropped, before anything is saved | `ID` and the username that placed the hold are hashed; name, email, phone dropped |
| What choosing a term selects | A new pull of a term replaces that term's rows and no others, so the term must mean the same thing in every pull | the students registered that term, each with their whole hold history |
| Any field the form needs beyond a term and columns | Left blank, MyReports opens a page asking for it and nothing downloads | "Hold From Date" |
| How the form's term list stores its values | The older reports' lists hold the term code; some hold a position in the list | positions (1 is the newest term) |
| What one row is, and what makes two rows of different pulls the same thing | The table's grain, and how a later pull replaces an earlier one | no id: student, hold code, start date, explanation and office |

Look at the file in aggregate (counts, column names, blanks). It holds names
and unhashed IDs: keep it out of the repository and delete it afterwards.

### Then, the five places

1. **mrgather** (`mrgather.js`, in its own repository,
   `cedar-collective/mrgather`). For a form with the usual
   Guided Adhoc layout, add an entry to `GUIDED_ADHOC_REPORTS` (the form's
   address, the download's file prefix, the ids of the term list, the add-all
   arrow, the Excel option and the run button) and a line to
   `REPORT_HANDLERS`. A form laid out differently needs its own function, as
   the DESR has. mrgather refuses a report code it does not have. Its Docker
   image bakes the source, so rebuild it wherever it runs
   (`docker compose build mrgather`), production included.
2. **`R/data-parsers/report-specs.R`**: the report's entry. Its header
   documents every field. `header_first_col` and `drop_na_col` are the two
   accommodations for a title above the table and footer lines below it.
3. **`scripts/report-registry.sh`**: the report's row, with the same code,
   file signature, stage and schedule as the spec.
   `test-data-update-pipeline.R` fails when the two disagree.
4. **`R/data-parsers/transform-to-cedar.R`**: a `transform_<name>()` that
   takes the parsed file and saves the table with `save_cedar_file()`; the
   stage's name in `CEDAR_TRANSFORM_STAGES`; its block in the orchestrator. A
   student ID goes through `encrypt_if_needed()`, as in every other table, or
   the new table joins nothing.
5. **Tests and docs.** The raw rows are a fixed object in
   `tests/testthat/fixtures/scenario_tables.R`, written to show what the
   stage must decide (a hold that changed between pulls, one listed twice,
   one that vanished), with the expected result beside them; the stage's test
   is in `test-transform-status.R`. Reintroduce the bug the fixture is for
   and confirm the test fails. The table is documented in
   [data-model.md](data-model.md) and its columns' sources in
   [source-to-cedar-manifest.md](source-to-cedar-manifest.md).

Nothing else names a report: the update script's arguments, its check for
today's files, the stages it asks the transform for and its usage text all
read the registry.

### Checking it

```bash
# The parser and the stage, on the file pulled by hand (put it where
# config/config.R's cedar_myreports_local_dir points; --keep leaves it there).
Rscript --vanilla R/data-parsers/parse-data.R -r holds --keep
Rscript --vanilla R/data-parsers/transform-to-cedar.R --tables holds

# What the whole run would do, without fetching anything.
scripts/update-data.sh --dry-run -s 202680 holds
```

Then check that the student IDs join. A table hashed any other way matches
no one. The transform checks programs, degrees, applicants and student-terms
against the class lists at every run, prints each table's verdict and every
term under **Student IDs** in its log, and stops on a table that joins in some
class-list terms and not at all in others (ISSUES I1). A table with no term
column, such as holds, is checked by hand:

```r
source("scripts/cedar-repl.R")
holds <- qs2::qs_read(file.path(cedar_data_dir, "cedar_holds.qs"))
mean(unique(holds$student_id) %in% cedar_student_terms$student_id)   # 0.998 for Fall 2026
```

### Catching up, and the scheduled refresh

A new report starts `named` in both lists: fetched only when asked for. Catch
up with one run over the terms wanted, from a terminal, since MyReports may
ask for a 2FA code:

```bash
CEDAR_FETCH_TIME_LIMIT=14400 scripts/update-data.sh -s 201980 -e 202680 holds
```

A requested report with no file from today fails the fetch
([ISSUES I43](https://github.com/cedar-collective/cedar/blob/main/ISSUES.md)),
so the report becomes `daily` (in the spec and the registry, together) only
once production mrgather has been rebuilt with its handler.

### When a page reads the table

A table no page reads is built and left on disk. When one does: load it in
`global.R`, `scripts/cedar-repl.R` and the cache-warming scripts; give it a
row in `CEDAR_FACT_SCHEMA_VERSIONS` if the app must not start on an old
shape; add it to the join-integrity check if it holds `student_id` and
`term`; and give it a row in `AGENTS.md`'s table of loaded tables.

---

## Running the Transformation

### Prerequisites

1. MyReports Excel files downloaded
2. `parse-data.R` has completed successfully (creates DESRs.qs, class_lists.qs, etc.)
3. R packages: `tidyverse`, `digest`, `qs2`, `data.table`
4. Environment variable `CEDAR_STUDENT_SALT` set (for student ID encryption;
   unset, the transform uses a built-in default: ISSUES I23)

### Daily Workflow

```bash
# Step 1: Parse MyReports Excel → Aggregate files (existing process)
Rscript R/data-parsers/parse-data.R

# Step 2: Transform Aggregate files → CEDAR model (new process)
Rscript R/data-parsers/transform-to-cedar.R
```

The transformation script will:
- Read the aggregate files (DESRs.qs, class_lists.qs, etc.)
- Extract only the columns needed for Cedar analytics
- Apply lowercase, consistent naming conventions
- Encrypt student IDs with SHA-256 hashing
- **Overwrite** existing cedar_* files with latest data
- Display progress and summary statistics

---

## Transformation Details

The complete transformation logic is in [R/data-parsers/transform-to-cedar.R](https://github.com/cedar-collective/cedar/blob/main/R/data-parsers/transform-to-cedar.R).

### Key Transformations:

**1. DESRs → cedar_sections**
- Keeps: 21 of 73 columns
- Key changes:
  - `TERM` → `term` (lowercase)
  - `SUBJ_CRSE` → `subject_course` (parser-created field)
  - `total_enrl` → `enrolled` (parser-created field)
  - Includes computed fields: `level`, `term_type`, `gen_ed_area`, `is_lab`
  - `PRIM_INST_ID` → `instructor_id`, md5-hashed as `parse-data.R` hashes the
    class list's (`hash_instructor_id()`, applied to both in the transform),
    so a section joins it (ISSUES I52).

**2. class_lists → cedar_registrations**
- Keeps: 18 of 74 columns
- Key changes:
  - `Academic Period Code` → `term` (no backticks!)
  - `Student ID` → `student_id` (encrypted with SHA-256)
  - `Course Campus Code` → `campus` (denormalized for performance)
  - `Final Grade` → `grade` (lowercase)
  - One row per student, course, campus and term (`dedup_class_list_rows()`):
    Banner's one row per CRN collapses to the row of record, the one
    `STATUS_PRECEDENCE` ranks first (registered, late drop, waitlist, early
    drop), a posted non-audit grade before none, then the lowest CRN. No
    classified outcome is saved; `cedar_attempts` classifies at load.
  - Analyses that need a student enrollment anchor use the minimum observed
    `cedar_registrations$term`, which means the first class-list term present in CEDAR.
    This is not a formal Banner matriculation/start-term field.
  - The student's description on the roster (level, classification, major,
    home college and campus, residency, dual credit) is saved once per
    student, term and pull as `cedar_class_list_descriptions`
    (`build_class_list_descriptions()`, with `rows`), and the class list is
    saved without it (`thin_class_list()`; ADR-001 step 5).

**2a. cedar_registrations and cedar_class_list_descriptions (+ programs, degrees) → cedar_student_terms**
- One row per `student_id + term` with any class-list row or declaration
  (`build_student_terms()`, ADR-001 step 2; contract in `student-terms.md`).
- Counts observed registered UNM credits from class-list rows with
  `registration_status_code %in% STATUS_REGISTERED` and non-missing `credits`,
  as term-level and cumulative attempted credits, and the same for completed
  credits under the canonical `passing_grades` list from `R/lists/grades.R`,
  with `unm_credits_entering` and `timeline_valid` beside them.
- Read by `build_credit_timeline()` and the Pathways / Major Changes movement
  cards for UNM credit timing, so the app does not rely on Academic Studies
  cumulative UNM credit fields as a historical credit timeline. Replaced
  `cedar_student_term_credits` on 2026-11-04.

**3. academic_studies → cedar_programs**
- Expands majors/minors into separate rows
- Normalizes program types (Major, Minor)
- Keeps: 10 core columns
- Key source fields used by Pathways / Major Changes:
  - `Academic Period` → `term`
  - `Major`, `Second Major`, and related program-name columns → `program_name`
  - `Major Code`, `Second Major Code`, and related code columns → `major_code`
  - `Program Code` → `program_code` for primary-major rows
  - `Student Population` → `student_population` for Native UNM vs Transfer labels
  - `Institution Credits Attempted` → `inst_credits_attempted`
  - `Overall Credits Attempted` → `overall_credits_attempted`
  - `is_pre_major` is computed by CEDAR from program naming/code patterns; it is
    not a raw Banner column.

**4. degrees → cedar_degrees**
- Keeps: 14 of 46 columns
- Focuses on degree conferral essentials

---

## Column Naming Conventions

CEDAR uses consistent, lowercase naming:

| Old (MyReports) | New (CEDAR) |
|----------------|-------------|
| `TERM` | `term` |
| `SUBJ` | `subject` |
| `CRSE` | `course_number` |
| `SUBJ_CRSE` | `subject_course` |
| `ENROLLED` | `enrolled` |
| `Academic Period Code` | `term` |
| `Student ID` | `student_id` (encrypted!) |
| `Final Grade` | `grade` |
| `Registration Status Code` | `registration_status_code` |

See [data-model.md](data-model.md) for complete schema.

---

## Student ID Encryption

**Critical:** Student IDs are encrypted using SHA-256 hashing to protect privacy.

Set your encryption salt as an environment variable:

```bash
# In ~/.Renviron or environment
CEDAR_STUDENT_SALT=your-random-secret-salt-here
```

The transformation script will:
- Check if IDs are already encrypted (64-char hex strings)
- If not encrypted, apply SHA-256 hash with your salt
- Store only hashed IDs in cedar_registrations.qs

**Never commit your salt to version control!**

---

## Data Preservation Strategy

**Why keep both aggregate and CEDAR files?**

1. **Full archive preserved** - Gender, ethnicity, GPA, and other fields remain in aggregate files
2. **Performance optimized** - CEDAR files are smaller, faster to load
3. **Future flexibility** - Want to add gender analysis? Just update the transformer to include it
4. **Backward compatible** - Existing workflows continue using aggregate files until migration complete

**Storage Impact:**
- Aggregate files: ~310 MB (all 73+ columns)
- CEDAR files: ~112 MB (streamlined)
- **Total: ~430 MB** (both formats during migration)

---

## For Non-MyReports Institutions

If your institution uses a different system (Banner, Colleague, Canvas, etc.):

1. Create your own data aggregation process (equivalent to `parse-data.R`)
2. Generate aggregate files with ALL your institutional data
3. Modify `transform-to-cedar.R` to map YOUR column names to CEDAR model
4. See [data-model.md](data-model.md) for required CEDAR columns

The CEDAR model is **institution-agnostic** - only the transformation layer is MyReports-specific.

---

## Troubleshooting

### Student IDs not encrypting
**Solution:** Set `CEDAR_STUDENT_SALT` environment variable:
```bash
export CEDAR_STUDENT_SALT=your-secret-salt
```

### Missing columns error
**Solution:** Ensure `parse-data.R` completed successfully and created computed columns like `SUBJ_CRSE`, `level`, `term_type`

### File not found errors
**Solution:** Check that aggregate files exist in your data directory:
```bash
ls -lh data/*.qs
```

### Transformation seems slow
**Note:** Should take ~10-30 seconds reading .qs files. If slower, check disk I/O or consider smaller test datasets.

---

## Next Steps

After transformation completes:

1. ✅ Verify cedar_* files created: `ls -lh data/cedar_*.qs`
2. ✅ Check file sizes are smaller than originals
3. ✅ Review transformation summary in console output
4. ⏸️ To use CEDAR model in Cedar app, set `cedar_use_new_model <- TRUE` in config.R
5. ⏸️ Migrate cone files to use new lowercase column names (see migration plan)

---

## See Also

- [data-model.md](data-model.md) - Complete CEDAR schema specification
- [Architecture Decisions](architecture-decisions.md) - why the data model is shaped as it is
- [R/data-parsers/transform-to-cedar.R](https://github.com/cedar-collective/cedar/blob/main/R/data-parsers/transform-to-cedar.R) - Actual transformation code

## DESR Input Schema (cedar_sections source)

Source: MyReports "Department Enrollment Status Report." Key fields:

## Identifiers
| Column | Description |
|--------|-------------|
| `TERM` | Term code (e.g., 202610 = Spring 2026) |
| `CRN` | Course Reference Number |
| `SUBJ` | Subject code (HIST, MATH, etc.) |
| `CRSE#` | Course number — may include trailing "L" for labs |
| `SECT#` | Section number |

## Enrollment
| Column | Description |
|--------|-------------|
| `ENROLLED` | Section-level enrollment |
| `MAX_ENROLLED` | Capacity |
| `XL_TOTAL_ENROLLMENT` | Combined XL group enrollment (crosslisted only) |
| `WAIT_COUNT` | Waitlist count |
| `CENSUS1`, `CENSUS2` | Census **dates** (mm/dd/yyyy), **not** enrollment counts — parser reads `CENSUS1` as a date (`census1`). No census-frozen headcount exists in the DESR; `ENROLLED` is always the count as of the file pull. See [Enrollment Measures](enrollment-measures.md). |

## Crosslist Fields
| Column | Description |
|--------|-------------|
| `XL_CODE` | 2-char crosslist group ID |
| `XL_SUBJ` | Subject code of partner section |
| `XL_CRN` | CRN of partner section |

**Crosslist quirk:** A section crosslisted with N partners has N rows (same CRN, different XL_SUBJ). `distinct()` does not deduplicate these. Downstream code must handle.

**SHORT_TEXT quirk:** `"HIST home 202610"` format signals home dept for cross-dept crosslists. Casing is inconsistent (`"home"` vs `"Home"`). Parser extracts subject case-insensitively.

## Parser-Added Columns (not in raw CSV)
| Column | Description |
|--------|-------------|
| `subject_course` | `paste(SUBJ, CRSE#)` → `"HIST 480"` |
| `total_enrl` | `max(ENROLLED, XL_TOTAL_ENROLLMENT)` |
| `level` | `"lower"` / `"upper"` / `"grad"` from course number |
| `term_type` | `"spring"` / `"fall"` / `"summer"` |
| `department` | Mapped from SUBJ via `subj_to_dept` |

---

