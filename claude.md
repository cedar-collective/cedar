# Claude Context & Conversation Log

This file tracks ongoing issues, decisions, and important context for the Cedar project to help maintain continuity across conversations.

---

## Project Overview

**Project Name:** Cedar - Course Enrollment Data for Analytics & Reporting
**Location:** `/Users/fwgibbs/Dropbox/projects/cedar`
**Repository:** Git repository
**Current Branch:** `feature/cedar-data-model` (migration work in progress)
**Main Branch:** `main` (stable, using legacy MyReports format)

**Purpose:** R/Shiny application for higher education course enrollment analytics

---

## Active Issues & Tasks

### Current Work: CEDAR Data Model Migration

**Status:** Infrastructure complete, ready for cone migrations

**Branch:** `feature/cedar-data-model`

**Recent Commits:**
- `288477c` - Add CEDAR data model infrastructure
- `aeb4015` - Rename cedar_enrollments to cedar_students
- `4bb7258` - Update documentation for cedar_students rename and two-phase pipeline

**What's Complete:**
- ✅ Data model specification ([docs/data-model.md](docs/data-model.md))
- ✅ Transformation script ([R/data-parsers/transform-to-cedar.R](R/data-parsers/transform-to-cedar.R))
- ✅ Dual-mode data loader ([R/branches/data.R](R/branches/data.R))
- ✅ Complete documentation (data-model.md, data-transformation-myreports.md, CEDAR-DATA-MODEL-SUMMARY.md)
- ✅ MIT License added
- ✅ Interactive setup.R script

**What's Pending:**
- ⏸️ Test transformation with actual data
- ⏸️ Migrate cone files to use CEDAR column names (15-20 files)
- ⏸️ Update filter functions for new column names
- ⏸️ Full testing and validation

---

## Important Decisions & Context

### Architecture & Design Decisions

#### 1. **CEDAR Data Model** (2026-01-11)
**Decision:** Migrate from MyReports-specific format to normalized CEDAR data model

**Rationale:**
- Current: 300MB loaded per session, 10-15 sec startup, 73+ column tables
- Target: 100MB (67% reduction), 3-5 sec startup, 20-25 column tables
- Institution-agnostic design (not tied to MyReports)
- Clean column names (lowercase, no backticks, consistent)

**Approach:** Two-phase data pipeline
1. **Phase 1 (Existing):** MyReports → Aggregate files (DESRs.qs, class_lists.qs, etc.)
   - Preserves ALL columns (73+) including gender, ethnicity, GPA
   - Complete institutional data warehouse
2. **Phase 2 (New):** Aggregate files → CEDAR tables (cedar_sections.qs, cedar_students.qs, etc.)
   - Streamlined 18-25 columns per table
   - Optimized for Cedar analytics
   - Runs daily, overwrites existing files

**Benefits:**
- Full data archive preserved (can add columns to CEDAR later)
- Performance optimized (smaller tables, faster loading)
- Future flexibility (adjust CEDAR model without re-parsing Excel)
- Backward compatible (existing code continues working)

#### 2. **Table Naming: cedar_students (not cedar_enrollments)**
**Decision:** Use `cedar_students` for class lists table

**Rationale:**
- More intuitive - it's literally class lists of students
- `cedar_sections` already has enrollment counts
- Clearer distinction between section-level vs student-level data

#### 3. **Data Loading Strategy**
**Decision:** Dual-mode loader with config toggle

**Implementation:**
```r
# In config.R
cedar_use_new_model <- FALSE  # Default: use legacy format
cedar_use_new_model <- TRUE   # Enable CEDAR model
```

**Rationale:**
- Safe migration (can toggle back if issues found)
- Testing flexibility (compare old vs new results)
- No breaking changes until ready

#### 4. **License: MIT**
**Decision:** Use MIT license instead of GPL-3.0

**Rationale:**
- More permissive for educational use
- Easier for other institutions to adopt

### Dependencies & Tools

**R Packages:**
- tidyverse (data manipulation)
- shiny (web application framework)
- qs (fast serialization - faster than RDS)
- digest (SHA-256 hashing for student IDs)

**External Tools:**
- mrgather (Node.js/Puppeteer for MyReports data scraping)
- xlsx2csv (Excel → CSV conversion)
- Docker (mrgather runs in container)

**Data Flow:**
```
MyReports (Web)
  → mrgather.js (Docker)
  → Excel files
  → parse-data.R
  → Aggregate .qs files
  → transform-to-cedar.R
  → CEDAR .qs files
  → Cedar app
```

---

## CEDAR Data Model Details

### Tables & Schema

**5 Normalized Tables:**

1. **cedar_sections** (21 columns)
   - Course offerings by term
   - Source: DESRs.qs (73 columns → 21)
   - Key columns: term, crn, subject_course, instructor_name, enrolled, capacity

2. **cedar_students** (18 columns)
   - Student enrollments in sections (class lists)
   - Source: class_lists.qs (74 columns → 18)
   - Key columns: student_id (encrypted!), term, campus, college, grade
   - **Privacy:** Student IDs encrypted with SHA-256

3. **cedar_programs** (10 columns)
   - Student majors/minors by term
   - Source: academic_studies.qs (83 columns → 10)
   - Expands: One row per program (majors/minors separated)

4. **cedar_degrees** (14 columns)
   - Graduates and pending graduates
   - Source: degrees.qs (46 columns → 14)

5. **cedar_faculty** (8 columns)
   - Instructor information by term
   - Source: hr_data.qs

### Column Naming Conventions

**Old (MyReports) → New (CEDAR):**
- `TERM` → `term`
- `SUBJ_CRSE` → `subject_course`
- `ENROLLED` → `enrolled`
- `Academic Period Code` → `term` (no backticks!)
- `Student ID` → `student_id` (encrypted)
- `Final Grade` → `grade`

**Key Principles:**
- Lowercase, snake_case
- No backticks needed
- Consistent across tables
- Institution-agnostic names

### Required Columns (Code Dependencies)

**Most-Used Columns (from code analysis):**
- `subject_course`: 239 references (created by parser)
- `term`: 113 references in students table
- `term_type`: 82 references (forecasting)
- `level`: 75 references (upper/lower/grad)
- `campus`: 72 references (filtering)
- `college`: 45 references (filtering)
- `grade`: 40 references (DFW analysis)

See [docs/data-model.md](docs/data-model.md) for complete schema with usage counts.

---

## Recent Changes

### Data Model Migration (2026-01-11)

**Files Created:**
- `docs/data-model.md` - Complete CEDAR schema specification
- `docs/data-transformation-myreports.md` - Transformation guide
- `docs/CEDAR-DATA-MODEL-SUMMARY.md` - Migration plan and rationale
- `R/data-parsers/transform-to-cedar.R` - Transformation script (runs daily)
- `setup.R` - Interactive first-time setup
- `LICENSE` - MIT license

**Files Modified:**
- `R/branches/data.R` - Added dual-mode loading (legacy vs CEDAR)

**Key Functions:**
```r
# Transform aggregate files to CEDAR model (run daily)
transform_to_cedar()

# Load data (automatically chooses format based on config)
load_global_data(opt)
  ├── load_legacy_data(opt)        # MyReports format
  └── load_cedar_model_data(opt)   # CEDAR format
```

### Previous Work (Main Branch)

**Latest Commits:**
- `3ba5dbd` - Add seatfinder enhancements and major change analysis
- `2272677` - Update columns excluded in waitlist summaries
- `dd3c1f7` - Refactor and reorganize R project structure

---

## Known Issues

### Current Limitations

1. **CEDAR model not yet usable**
   - Infrastructure complete, but cone files not migrated
   - Turning on `cedar_use_new_model <- TRUE` will break everything
   - Need to update 15-20 cone files with new column names

2. **Student ID encryption**
   - Requires `CEDAR_STUDENT_SALT` environment variable
   - Must be set before running transformation
   - Default salt used if not set (not secure!)

3. **No validation script yet**
   - Need to compare old vs new format results
   - Ensure data integrity during transformation

### Technical Debt

- Forecasting code still uses old column names
- Data status reporting (get_data_status) partially broken for HR data
- Crosslist handling could be improved in transformation
- No automated testing for transformation script

---

## Migration Strategy

### Phase 1: Infrastructure ✅ COMPLETE
- [x] Design CEDAR data model
- [x] Create transformation script
- [x] Add dual-mode data loader
- [x] Document everything

### Phase 2: Testing (Next)
- [ ] Run transformation with actual data
- [ ] Verify cedar_* files created correctly
- [ ] Check file sizes and record counts
- [ ] Create validation script (compare old vs new)

### Phase 3: Cone Migrations (2-3 weeks)
- [ ] Migrate enrl.R (simplest)
- [ ] Migrate headcount.R
- [ ] Migrate gradebook.R / outcomes.R
- [ ] Migrate seatfinder.R
- [ ] Migrate remaining cones
- [ ] Update filter functions
- [ ] Update UI/server code

### Phase 4: Finalization (1 week)
- [ ] Full testing suite
- [ ] Performance benchmarking
- [ ] User acceptance testing
- [ ] Remove backward compatibility code
- [ ] Merge to main branch

---

## Daily Workflow (After Migration)

```bash
# 1. Download MyReports data (manual for now)

# 2. Parse MyReports → Aggregate files (existing, unchanged)
Rscript cedar.R -f parse-data

# 3. Transform Aggregate → CEDAR files (new, daily)
Rscript R/data-parsers/transform-to-cedar.R

# 4. Start Cedar app (automatically uses correct format)
Rscript cedar.R -f shiny
```

**Files Created:**
- Aggregate: `data/DESRs.qs`, `data/class_lists.qs`, etc. (full data)
- CEDAR: `data/cedar_sections.qs`, `data/cedar_students.qs`, etc. (streamlined)

**Storage:**
- Aggregate files: ~310 MB (all columns)
- CEDAR files: ~112 MB (streamlined)
- Total: ~430 MB (both formats during migration)

---

## Conversation History

### 2026-01-11 - CEDAR Data Model Migration
**Key Discussion Points:**
1. Identified data management as weakest part of Cedar
2. Analyzed current architecture (300MB tables, 73+ columns)
3. Designed CEDAR normalized model (5 tables, 67% size reduction)
4. Created complete infrastructure and documentation
5. Renamed cedar_enrollments → cedar_students (more intuitive)
6. Established two-phase pipeline (preserve full data + streamlined CEDAR)

**Important User Feedback:**
- User wants to preserve ALL MyReports fields (gender, etc.) for future analytics
- Transformation should run daily and overwrite cedar_* files
- Keep aggregate and CEDAR files separate during migration
- Cone migrations will happen gradually over weeks

### 2026-01-09
- Created claude.md file for future context awareness
- Fixed mrgather.js Docker container issue (added process.exit)

---

## Notes & Reminders

### Coding Conventions

**R Style:**
- Use tidyverse conventions (pipes, dplyr verbs)
- snake_case for variables and functions
- Global data loaded into .GlobalEnv for Shiny reactivity

**Git Workflow:**
- Feature branches for major changes
- Descriptive commit messages with Claude co-author tag
- Test before merging to main

### Project-Specific Guidelines

1. **Never commit sensitive data**
   - Student IDs must be encrypted
   - No CEDAR_STUDENT_SALT in version control
   - Use .gitignore for data/ directory

2. **Data file naming**
   - Aggregate files: lowercase with underscores (class_lists.qs)
   - CEDAR files: prefix with cedar_ (cedar_students.qs)
   - Use .qs format for speed (fallback to .Rds if qs package unavailable)

3. **Documentation priority**
   - Update docs/ when making schema changes
   - Include usage counts in data-model.md
   - Provide examples in transformation guides

4. **Backward compatibility during migration**
   - Keep both data formats available
   - Use config toggle (cedar_use_new_model)
   - Don't break existing functionality

---

## Questions & TODO

### Open Questions
- [ ] How to handle crosslisted courses in CEDAR model?
- [ ] Should we add indexes/keys to CEDAR tables for joins?
- [ ] What's the best way to version the CEDAR schema?

### Pending Tasks
- [ ] Test transform-to-cedar.R with actual UNM data
- [ ] Create validation script to compare old vs new results
- [ ] Benchmark performance (startup time, memory usage)
- [ ] Plan cone migration schedule (which order, how to test)
- [ ] Consider creating small test datasets for contributors

### Future Enhancements
- [ ] Add data quality checks to transformation
- [ ] Create summary statistics during transformation
- [ ] Add logging/monitoring for production use
- [ ] Consider incremental updates instead of full daily rebuild?

---

## Useful Commands

```bash
# Check current branch
git branch

# Switch to data model branch
git checkout feature/cedar-data-model

# Run transformation (manual for now)
Rscript R/data-parsers/transform-to-cedar.R

# Check data files
ls -lh data/*.qs

# View transformation output
Rscript R/data-parsers/transform-to-cedar.R 2>&1 | less

# Compare file sizes
du -h data/DESRs.qs data/cedar_sections.qs
```

---

## References

**Key Documentation:**
- [docs/data-model.md](docs/data-model.md) - CEDAR schema specification
- [docs/data-transformation-myreports.md](docs/data-transformation-myreports.md) - Transformation guide
- [docs/CEDAR-DATA-MODEL-SUMMARY.md](docs/CEDAR-DATA-MODEL-SUMMARY.md) - Migration plan

**Key Code Files:**
- [R/data-parsers/transform-to-cedar.R](R/data-parsers/transform-to-cedar.R) - Transformation logic
- [R/branches/data.R](R/branches/data.R) - Data loading (dual-mode)
- [R/branches/parse-data.R](R/branches/parse-data.R) - MyReports parsing (unchanged)

**Related Projects:**
- mrgather: `/Users/fwgibbs/Dropbox/projects/mrgather` (data collection)
- xanthan: `/Users/fwgibbs/Dropbox/projects/xanthan` (project website)
