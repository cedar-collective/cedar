# CEDAR-PLATFORM: text → code maps from institution/<id>/ (program names, aliases, HR organisations)
# mappings.R
#
# Hand-curated text lookups for exports that carry a name but no code. Which
# names map to what is the institution's, in three files read and validated
# here at load; this file names no program, code or organisation.
#
#   major_name_to_major_code — program_names.csv. Program name text → program
#                             code, used by the transform to fill major_code
#                             when an export has a name column but no code
#                             column (old formats, some graduate data).
#   program_name_aliases     — program_name_aliases.csv. Variant or historical
#                             program_name → the canonical name stored in
#                             cedar_programs (Banner rename artifacts, X-prefix
#                             variants whose text differs).
#   hr_org_desc_to_dept      — source_organizations.csv. HR "Home Organization
#                             Desc" → unit code, used by parse-HRreport.R and
#                             Dept Trends. Every unit it names is in units.csv.
#
# SUPERSEDED — do NOT re-add these; they are derived from the mapping files by
# catalog_lookups.R: subj_to_dept, college_name_to_code, dept_code_to_name,
# major_to_dept (major_college_to_dept and old_code_to_new_code were retired at
# ADR-002 Stage 4; use resolve_program_units() and subj_dept_map).

.cedar_text_maps <- validate_text_maps(
  read_institution_file("program_names"),
  read_institution_file("program_name_aliases"),
  read_institution_file("source_organizations"),
  known_units = read_institution_file("units")$unit_code
)

major_name_to_major_code <- stats::setNames(.cedar_text_maps$program_names$program_code,
                                            .cedar_text_maps$program_names$program_name)

program_name_aliases <- stats::setNames(.cedar_text_maps$aliases$program_name,
                                        .cedar_text_maps$aliases$source_name)

hr_org_desc_to_dept <- stats::setNames(.cedar_text_maps$organizations$unit_code,
                                       .cedar_text_maps$organizations$source_name)
