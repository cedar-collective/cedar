# CEDAR Data Model Migration Summary

**Status:** Proposed for implementation before public release
**Impact:** High - Affects all analytics code, but provides major benefits
**Estimated Effort:** 3-4 weeks

---

## The Problem (Current State)

### Current Data Architecture Issues:

1. **Massive tables loaded into memory**
   - `DESRs.qs`: 43MB, **73 columns** (but most analytics use <20)
   - `class_lists.qs`: 218MB, **74 columns** (largest table!)
   - `academic_studies.qs`: 39MB, **83 columns**
   - Total: **~300MB** per user session

2. **MyReports-specific column names throughout code**
   ```r
   # Current code is tightly coupled to MyReports
   courses$TERM
   courses$ENROLLED
   students$`Academic Period Code`  # Backticks required!
   students$`Student ID`  # Privacy risk!
   ```

3. **Documentation nightmare**
   - Must document 73-column DESR format
   - Must document 74-column Class List format
   - UNM-specific field names confuse other institutions
   - No clear data model for contributors

4. **Performance issues**
   - 10-15 second startup (loading bloated tables)
   - Each Shiny user consumes 300-500MB RAM
   - Large tables slow down filtering/grouping

5. **Maintainability problems**
   - MyReports column name changes break code everywhere
   - Can't easily add non-MyReports data sources
   - Difficult to test (can't create simple fixture data)

---

## The Solution (CEDAR Data Model)

### Create 5 Normalized Tables:

| Table | Purpose | Columns | Size (est) |
|-------|---------|---------|------------|
| `cedar_sections` | Course offerings | 20-25 | 5-10 MB ↓77% |
| `cedar_enrollments` | Student registrations | 12-15 | 60-80 MB ↓63% |
| `cedar_programs` | Student majors/minors | 10-12 | 15-20 MB |
| `cedar_degrees` | Graduates | 12-15 | 3-5 MB |
| `cedar_faculty` | Instructor info | 8-10 | 1-2 MB |
| **Total** | | | **~100 MB** ↓67% |

### Key Improvements:

#### 1. **Performance Gains**
```
BEFORE: 300MB, 10-15 sec startup
AFTER:  100MB,  3-5 sec startup
```

#### 2. **Clean Column Names**
```r
# New CEDAR model
cedar_sections$term
cedar_sections$enrolled
cedar_enrollments$student_id  # Already encrypted!
cedar_enrollments$grade
```

#### 3. **Institution-Agnostic**
```r
# Other institutions document how THEIR data maps to CEDAR
# Example for Banner users:
banner_sections %>%
  transmute(
    term = TERM_CODE,
    crn = CRN,
    subject = SUBJ_CODE,
    # ... map Banner → CEDAR
  )
```

#### 4. **Easier Documentation**
```markdown
# Instead of documenting MyReports quirks:
"CEDAR requires these 5 tables (see data-model.md)

For MyReports: Run transform_myreports_to_cedar()
For Banner: Create your own transformation
For Canvas: Use Canvas API → CEDAR transformation
```

---

## Migration Plan

### Phase 1: Create Transformation Layer (Week 1)

**Tasks:**
- [x] Define CEDAR model schema → `docs/data-model.md` ✅
- [x] Document MyReports mapping → `docs/data-transformation-myreports.md` ✅
- [ ] Create transformation script → `R/data-parsers/transform-to-cedar.R`
- [ ] Test with current data
- [ ] Validate output tables

**Deliverables:**
- CEDAR tables saved in `data/cedar_*.qs`
- Validation script confirms data quality
- Can load both old and new formats

### Phase 2: Migrate Core Cones (Week 2)

**Strategy:** Update cones one at a time, test thoroughly

**Priority order:**
1. ✅ `enrl.R` (simplest, most used)
2. ✅ `headcount.R` (uses academic_studies)
3. ✅ `gradebook.R` / `outcomes.R` (uses grades)
4. ✅ `seatfinder.R`
5. ⏸️  More complex cones (forecast, course-report, etc.)

**Approach for each cone:**
```r
# OLD (current)
get_enrl <- function(courses, opt) {
  filtered <- courses %>%
    filter(STATUS == "A") %>%
    select(TERM, SUBJ, CRSE, ENROLLED, ...)
}

# NEW (CEDAR model)
get_enrl <- function(sections, opt) {
  filtered <- sections %>%
    filter(status == "A") %>%
    select(term, subject, course_number, enrolled, ...)
}
```

**Testing:**
- Compare old vs new results (should match exactly!)
- Benchmark performance (should be faster)
- Update tests

### Phase 3: Update Data Loading (Week 3)

**Update `global.R` and `data.R`:**

```r
# Add config flag
cedar_use_new_model <- TRUE  # Toggle between old/new

# Modified load function
load_global_data <- function(opt) {
  if (cedar_use_new_model) {
    # Load CEDAR model
    cedar_sections <- load_datafile("cedar_sections")
    cedar_enrollments <- load_datafile("cedar_enrollments")
    cedar_programs <- load_datafile("cedar_programs")
    cedar_degrees <- load_datafile("cedar_degrees")
    cedar_faculty <- load_datafile("cedar_faculty")

    # For backward compatibility
    courses <- cedar_sections
    students <- cedar_enrollments

  } else {
    # Load old MyReports format
    courses <- load_datafile("desrs")
    students <- load_datafile("class_lists")
    # ...
  }
}
```

**Backward Compatibility:**
- Keep old data loading for 2-3 releases
- Deprecation warning when using old format
- Eventually remove old code

### Phase 4: Documentation & Testing (Week 4)

**Documentation:**
- [ ] Update all cone documentation with new column names
- [ ] Create "Adapting Your Data to CEDAR" guide for non-MyReports
- [ ] Update README with data model overview
- [ ] Add data model diagram

**Testing:**
- [ ] Run full test suite
- [ ] Performance benchmarking
- [ ] User acceptance testing
- [ ] Create sample datasets for contributors

**Validation:**
- [ ] All analytics produce same results as before
- [ ] Startup time improved
- [ ] Memory usage reduced
- [ ] Code is cleaner

---

## Code Changes Required

### Estimated Impact:

| File Type | Files Affected | Effort |
|-----------|---------------|--------|
| Data loading | 2-3 files | Medium |
| Core cones | 15-18 files | High |
| Filter functions | 2-3 files | Low |
| UI/Server | 2 files | Low (mostly variable names) |
| Tests | 10-13 files | Medium |
| Documentation | 8-10 files | Medium |

### Example: Updating `enrl.R`

**BEFORE (current - 73 columns available):**
```r
get_enrl <- function(courses, opt) {
  # Filter 73-column table
  courses_filtered <- courses %>%
    filter(STATUS == "A") %>%
    filter(TERM >= opt$start_term)

  # Aggregate
  if ("TERM" %in% opt$group_cols) {
    summary <- courses_filtered %>%
      group_by(!!!syms(opt$group_cols)) %>%
      summarize(
        enrollment = sum(total_enrl),
        sections = n_distinct(CRN)
      )
  }

  return(summary)
}
```

**AFTER (CEDAR model - 20 columns, cleaner names):**
```r
get_enrl <- function(sections, opt) {
  # Filter 20-column table (faster!)
  sections_filtered <- sections %>%
    filter(status == "A") %>%
    filter(term >= opt$start_term)

  # Aggregate (same logic, cleaner column names)
  if ("term" %in% opt$group_cols) {
    summary <- sections_filtered %>%
      group_by(!!!syms(opt$group_cols)) %>%
      summarize(
        enrollment = sum(enrolled),
        sections = n_distinct(crn)
      )
  }

  return(summary)
}
```

**Changes:**
- `courses` → `sections` (parameter name)
- `STATUS` → `status`
- `TERM` → `term`
- `total_enrl` → `enrolled`
- `CRN` → `crn`

That's it! Logic stays the same.

---

## Benefits Summary

### For Users:
- ✅ **Faster startup:** 3-5 seconds instead of 10-15
- ✅ **Lower memory:** 100MB instead of 300MB per session
- ✅ **More responsive:** Smaller tables = faster filtering/aggregation

### For Contributors:
- ✅ **Clear data model:** Well-documented tables, not vendor quirks
- ✅ **Easier to extend:** Add new analytics without learning MyReports
- ✅ **Better tests:** Can create simple fixture data matching CEDAR schema

### For Other Institutions:
- ✅ **Institution-agnostic:** Map YOUR data to CEDAR model
- ✅ **No MyReports required:** Works with Banner, Colleague, Canvas, etc.
- ✅ **Clear transformation guide:** Template for your own data source

### For Maintainability:
- ✅ **Vendor independence:** MyReports changes don't break CEDAR
- ✅ **Consistent code:** All analytics use same column names
- ✅ **Easier debugging:** Smaller tables, clearer structure

---

## Risks & Mitigation

### Risk 1: Breaking existing code
**Mitigation:**
- Keep both old and new formats during migration
- Add `cedar_use_new_model` toggle flag
- Extensive testing before switching

### Risk 2: Migration taking longer than expected
**Mitigation:**
- Start with simplest cones
- Can release with partial migration
- Some cones stay on old format if needed

### Risk 3: Performance doesn't improve as expected
**Mitigation:**
- Benchmark early (Week 1)
- If no gains, can abort migration
- Likely to see 2-3x improvement based on size reduction

### Risk 4: Other institutions can't map their data
**Mitigation:**
- Provide template transformation scripts
- CEDAR model is flexible (many optional columns)
- Can adapt model if needed

---

## Decision Point

**Should we do this before public release?**

### Arguments FOR (Recommended):
- First impressions matter - clean data model signals quality
- Harder to change after people start using Cedar
- Performance is a key selling point
- Shows Cedar is institution-agnostic

### Arguments AGAINST:
- Delays release by 3-4 weeks
- Requires touching lots of code (risk of bugs)
- Could do incremental migration after release

### My Recommendation: **DO IT BEFORE RELEASE**

Why:
1. **Won't get easier later** - Existing users will rely on current structure
2. **Documentation is critical** - Better to document clean model than MyReports quirks
3. **Performance matters** - 3-5 sec startup vs 10-15 sec is noticeable
4. **Shows maturity** - Professional data architecture impresses potential adopters

---

## Next Steps

If approved, immediate actions:

1. **Week 1 (Now):**
   - Create `transform-to-cedar.R` script
   - Test transformation with your current data
   - Validate CEDAR tables match old data

2. **Week 2:**
   - Migrate `enrl.R` and `headcount.R`
   - Compare results (old vs new)
   - Fix any discrepancies

3. **Week 3:**
   - Migrate remaining cones
   - Update data loading logic
   - Performance benchmarking

4. **Week 4:**
   - Final testing
   - Documentation updates
   - Prepare for release

---

## Questions to Answer

Before proceeding:

1. **Confirm approach:** Does this data model meet your needs?
2. **Encrypted student IDs:** What hashing method should we use?
3. **Optional columns:** Any other fields you commonly use?
4. **Timeline:** Can we allocate 3-4 weeks before release?
5. **Testing:** Who will validate the migrated analytics?

---

## Files Created So Far

✅ `docs/data-model.md` - Complete CEDAR schema documentation
✅ `docs/data-transformation-myreports.md` - MyReports → CEDAR mapping
⏸️ `R/data-parsers/transform-to-cedar.R` - Transformation script (next)
⏸️ `R/data-validation.R` - Validation functions (next)

---

Want me to create the transformation script next?
