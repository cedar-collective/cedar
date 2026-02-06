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
hr_data.qs (varies)
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
cedar_students.qs (18 columns - streamlined)
cedar_programs.qs (10 columns)
cedar_degrees.qs (14 columns)
cedar_faculty.qs (8 columns)
```

**Purpose:** Normalized, institution-agnostic tables optimized for Cedar analytics

---

## MyReports → CEDAR Mapping

| MyReports Report | MyReports File | → | CEDAR Table |
|------------------|----------------|---|-------------|
| **DESR** (Department Enrollment Status Report) | DESRs.qs | → | `cedar_sections` |
| **Class Lists** | class_lists.qs | → | `cedar_students` |
| **Academic Study Detail** | academic_studies.qs | → | `cedar_programs` |
| **Graduates & Pending Graduates** | degrees.qs | → | `cedar_degrees` |
| **HR Report** (optional) | hr_data.qs | → | `cedar_faculty` |

---

## Running the Transformation

### Prerequisites

1. MyReports Excel files downloaded
2. `parse-data.R` has completed successfully (creates DESRs.qs, class_lists.qs, etc.)
3. R packages: `tidyverse`, `digest`, `qs`
4. Environment variable `CEDAR_STUDENT_SALT` set (for student ID encryption)

### Daily Workflow

```bash
# Step 1: Parse MyReports Excel → Aggregate files (existing process)
Rscript cedar.R -f parse-data

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

The complete transformation logic is in [R/data-parsers/transform-to-cedar.R](../R/data-parsers/transform-to-cedar.R).

### Key Transformations:

**1. DESRs → cedar_sections**
- Keeps: 21 of 73 columns
- Key changes:
  - `TERM` → `term` (lowercase)
  - `SUBJ_CRSE` → `subject_course` (parser-created field)
  - `total_enrl` → `enrolled` (parser-created field)
  - Includes computed fields: `level`, `term_type`, `gen_ed_area`, `is_lab`

**2. class_lists → cedar_students**
- Keeps: 18 of 74 columns
- Key changes:
  - `Academic Period Code` → `term` (no backticks!)
  - `Student ID` → `student_id` (encrypted with SHA-256)
  - `Course Campus Code` → `campus` (denormalized for performance)
  - `Final Grade` → `grade` (lowercase)

**3. academic_studies → cedar_programs**
- Expands majors/minors into separate rows
- Normalizes program types (Major, Minor)
- Keeps: 10 core columns

**4. degrees → cedar_degrees**
- Keeps: 14 of 46 columns
- Focuses on degree conferral essentials

**5. hr_data → cedar_faculty**
- Keeps: 8 core columns
- Instructor demographics and appointments

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
- Store only hashed IDs in cedar_students.qs

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
- [CEDAR-DATA-MODEL-SUMMARY.md](CEDAR-DATA-MODEL-SUMMARY.md) - Migration rationale and plan
- [R/data-parsers/transform-to-cedar.R](../R/data-parsers/transform-to-cedar.R) - Actual transformation code
