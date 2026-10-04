# CEDAR-PLATFORM: builds subj_dept_map from the institution's mapping files
# subj_dept_map.R
#
# The college → unit → subject hierarchy now lives in plain CSV files under
# institution/<id>/ (colleges.csv, units.csv, subjects.csv), read and validated
# by R/lists/institution_files.R. This file only assembles them into the table
# every CEDAR lookup is derived from, with the column names CEDAR has always
# used:
#
#   college_code  — Banner 2-letter code (matches COLLEGE in DESRs)
#   college_name  — Full name (matches "Actual College" in academic_studies)
#   dept_code     — unit_code: cedar_sections$department, cedar_programs$dept_code
#   dept_name     — unit_name, for display
#   subject_code  — course subject (many-to-one with dept_code)
#
# To change a mapping, edit the CSV, not this file.
# See docs/developers/adr-002-explicit-mapping-files.md.

# Kept whole as well: Admin > Mappings lists the programs.csv rows awaiting a
# decision, and links each to its line using settings.csv.
cedar_institution_files <- read_institution_mappings()
subj_dept_map <- build_subj_dept_map(cedar_institution_files)
