# catalog_lookups.R
#
# Derives all lookup VECTORS from unit_catalog and major_dept_map tibbles.
# Source this file AFTER unit_catalog.R and major_dept_map.R.
#
# Provides:
#   subj_to_dept       — subject_code → dept_code  (for cedar_sections)
#   college_name_to_code   — "College of Arts and Sciences" → "AS"  (for cedar_programs)
#   dept_code_to_name      — dept_code → human-readable dept name  (for display)
#   major_college_to_dept          — "major_code:college_code" → dept_code  (for cedar_programs,
#                             compound key handles same major_code in multiple colleges)
#   major_to_dept      — major_code → dept_code  (simple fallback; when college_code
#                             context is unavailable; first/main-campus mapping wins on ties)
#
# These replace the equivalent hand-coded vectors previously in mappings.R.
# To change a mapping, edit unit_catalog.R or major_dept_map.R — not this file.

# ── From unit_catalog ─────────────────────────────────────────────────────────

# subject_code → dept_code (for matching DESR course sections to departments)
subj_to_dept           <- unit_catalog$dept_code
names(subj_to_dept)    <- unit_catalog$subject_code

# College text name → 2-letter Banner code (for cedar_programs college_code column)
.college_lu                <- dplyr::distinct(unit_catalog, college_code, college_name)
college_name_to_code       <- .college_lu$college_code
names(college_name_to_code)<- .college_lu$college_name

# dept_code → human-readable name (for display; unit_catalog dept_name is authoritative)
.dept_lu                   <- dplyr::distinct(unit_catalog, dept_code, dept_name)
dept_code_to_name          <- .dept_lu$dept_name
names(dept_code_to_name)   <- .dept_lu$dept_code

# ── From major_dept_map ────────────────────────────────────────────────────────

# Compound key lookup: "major_code:college_code" → dept_code
# Use this in transform-to-cedar.R where college_code is known.
# Correctly disambiguates cases where the same major_code exists in multiple colleges
# (e.g., EDUC in EH vs AD, CRIM in AS/SOCI vs AD/CJUS, CS in EN vs AD).
.pc                        <- dplyr::distinct(major_dept_map, major_code, college_code, .keep_all = TRUE)
major_college_to_dept              <- .pc$dept_code
names(major_college_to_dept)       <- paste(.pc$major_code, .pc$college_code, sep = ":")

# Simple major_code → dept_code (no college context; first occurrence wins).
# major_dept_map is ordered main-campus-first, so main campus depts take priority.
# Use major_college_to_dept (compound key) when college_code is available — it is more accurate.
.pc_simple                 <- dplyr::distinct(major_dept_map, major_code, .keep_all = TRUE)
major_to_dept          <- .pc_simple$dept_code
names(major_to_dept)   <- .pc_simple$major_code

rm(.college_lu, .dept_lu, .pc, .pc_simple)
