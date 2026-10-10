# CEDAR-PLATFORM: derives lookup vectors from institution data
# catalog_lookups.R
#
# Derives the runtime lookup VECTORS from the institution mapping files
# (cedar_institution_files, read by subj_dept_map.R). Source it after
# subj_dept_map.R.
#
# Since ADR-002 Stage 4 nothing here comes from program_map.qs, which is
# retired: every stored unit is written by the transform from the files
# (Stage 3), and these vectors are conveniences for code that needs a quick
# code -> unit lookup at runtime.
#
# Provides:
#   subj_to_dept       — subject_code → unit code: the first confirmed subjects.csv
#                        row for the code. A runtime convenience only; the
#                        transform uses resolve_course_units(), which also keys on
#                        the section's college and course level.
#   college_name_to_code — college name → code (colleges.csv). Prefer
#                        translate_source_college(), which also reads source_names.
#   dept_code_to_name  — unit code → unit name.
#   major_to_dept      — program_code → unit code: confirmed every-college
#                        programs.csv rows. College-specific rows (BADM and CRIM
#                        at the branch campuses) are not in it; resolve those with
#                        resolve_program_units().
#   premajor_leads_to  — pre-major program_code → the program code it leads to
#                        (programs.csv leads_to). Translation only, never history.
#
# To change a mapping, edit institution/<id>/*.csv — not this file.

# ── From subjects.csv, units.csv, colleges.csv (via subj_dept_map) ────────────

subj_to_dept           <- subj_dept_map$dept_code
names(subj_to_dept)    <- subj_dept_map$subject_code

.college_lu                <- dplyr::distinct(subj_dept_map, college_code, college_name)
college_name_to_code       <- .college_lu$college_code
names(college_name_to_code)<- .college_lu$college_name

.dept_lu                   <- dplyr::distinct(subj_dept_map, dept_code, dept_name)
dept_code_to_name          <- .dept_lu$dept_name
names(dept_code_to_name)   <- .dept_lu$dept_code

# ── From programs.csv ──────────────────────────────────────────────────────────

.programs <- cedar_institution_files$programs
.every    <- .programs[.programs$status == "confirmed" & !nzchar(.programs$in_college) &
                         nzchar(.programs$unit_code), ]
major_to_dept <- stats::setNames(.every$unit_code, .every$program_code)

.pre <- .programs[.programs$is_pre_major == "TRUE" & nzchar(.programs$leads_to) &
                    !nzchar(.programs$in_college), ]
premajor_leads_to <- stats::setNames(.pre$leads_to, .pre$program_code)

rm(.college_lu, .dept_lu, .programs, .every, .pre)
