# catalog_lookups.R
#
# Derives all lookup VECTORS from unit_catalog and program_catalog tibbles.
# Source this file AFTER unit_catalog.R and program_catalog.R.
#
# Provides:
#   subj_to_dept_map       — subject_code → dept_code  (for cedar_sections)
#   college_name_to_code   — "College of Arts and Sciences" → "AS"  (for cedar_programs)
#   dept_code_to_name      — dept_code → human-readable dept name  (for display)
#   pc_dept_lu             — "program_code:college_code" → dept_code  (for cedar_programs,
#                             compound key handles same program_code in multiple colleges)
#   prgm_to_dept_map       — program_code → dept_code  (simple fallback; when college_code
#                             context is unavailable; first/main-campus mapping wins on ties)
#
# These replace the equivalent hand-coded vectors previously in mappings.R.
# To change a mapping, edit unit_catalog.R or program_catalog.R — not this file.

# ── From unit_catalog ─────────────────────────────────────────────────────────

# subject_code → dept_code (for matching DESR course sections to departments)
subj_to_dept_map           <- unit_catalog$dept_code
names(subj_to_dept_map)    <- unit_catalog$subject_code

# College text name → 2-letter Banner code (for cedar_programs college_code column)
.college_lu                <- dplyr::distinct(unit_catalog, college_code, college_name)
college_name_to_code       <- .college_lu$college_code
names(college_name_to_code)<- .college_lu$college_name

# dept_code → human-readable name (for display; unit_catalog dept_name is authoritative)
.dept_lu                   <- dplyr::distinct(unit_catalog, dept_code, dept_name)
dept_code_to_name          <- .dept_lu$dept_name
names(dept_code_to_name)   <- .dept_lu$dept_code

# ── From program_catalog ──────────────────────────────────────────────────────

# Compound key lookup: "program_code:college_code" → dept_code
# Use this in transform-to-cedar.R where college_code is known.
# Correctly disambiguates cases where the same program_code exists in multiple colleges
# (e.g., EDUC in EH vs AD, CRIM in AS/SOCI vs AD/CJUS, CS in EN vs AD).
.pc                        <- dplyr::distinct(program_catalog, program_code, college_code, .keep_all = TRUE)
pc_dept_lu                 <- .pc$dept_code
names(pc_dept_lu)          <- paste(.pc$program_code, .pc$college_code, sep = ":")

# Simple program_code → dept_code (no college context; first occurrence wins).
# program_catalog is ordered main-campus-first, so main campus depts take priority.
# Use pc_dept_lu (compound key) when college_code is available — it is more accurate.
.pc_simple                 <- dplyr::distinct(program_catalog, program_code, .keep_all = TRUE)
prgm_to_dept_map           <- .pc_simple$dept_code
names(prgm_to_dept_map)    <- .pc_simple$program_code

rm(.college_lu, .dept_lu, .pc, .pc_simple)
