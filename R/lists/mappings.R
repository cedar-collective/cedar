# mappings.R
#
# Hand-curated text/name lookup maps that cannot be derived from subj_dept_map or program_map.
#
# Contents:
#   major_name_to_major_code — Major name text → Banner major code.
#                             Used in transform-to-cedar.R to fill major_code when Banner
#                             exports provide a text name but no code column (old data formats).
#   hr_org_desc_to_dept      — HR "Home Organization Desc" text → dept_code.
#                             Used in parse-HRreport.R and dept-report.R.
#
# SUPERSEDED — do NOT re-add these; they are now derived automatically and loaded by
# catalog_lookups.R (sources subj_dept_map.R + reads data/program_map.qs):
#   subj_to_dept          → catalog_lookups.R (from subj_dept_map)
#   college_name_to_code  → catalog_lookups.R (from subj_dept_map)
#   dept_code_to_name     → catalog_lookups.R (from subj_dept_map dept_name)
#   major_to_dept         → catalog_lookups.R (from program_map)
#   major_college_to_dept → catalog_lookups.R (from program_map)
#   old_code_to_new_code  → subj_dept_map subject_code → dept_code mappings


# Maps major name text to Banner major codes.
# Used when Banner exports provide a program name but no major code column (e.g., some
# grad data, older export formats). Values are major codes, not dept codes.
major_name_to_major_code <- c(
  "American Studies"="AMST",
  "Africana Studies"="AFST",
  "African American Studies"="AFST",
  "Anthropology"="ANTH",
  "American Sign Language"="ASL",
  "Arabic"="ARBC",
  "Asian Studies"="EAS",
  "Astrophyics"="ASTR",
  "Biology"="BIOL",
  "Biology/Biological Sciences"="BIOL",
  "Biochemistry"="BIOC",
  "Chemistry"="CHEM",
  "Chicana and Chicano Studies"="CCS",
  "Chicana Chicano Studies"="CCS",
  "Chicana/o Studies"="CCS",
  "Chinese"="CHIN",
  "Classical Studies"="CLST",
  "Communication Journalism"="CJ",
  "Communication & Journalism"="CJ",
  "Communication"="COMM",
  "Comp Lit & Cultural Stds"="CLCS",
  "Comp Lit & Cultural Studies"="CLCS",
  "Comparative Literature"="CLCS",
  "Criminology"="CRIM",
  "Creative Writing"="CRWR",
  "Earth & Planetary Sciences"="EPS",
  "East Asian Studies"="EAS",
  "Economics"="ECON",
  "English"="ENGL",
  "English Studies"="ENGS",
  "English-Philosophy"="ENGP",
  "Environmental Science"="ENSC",
  "French"="FREN",
  "French Studies"="FRNS",
  "Foreign Languages Literatures"="LCL",
  "Forensic Anthropology"="ANTH",
  "Forensic Science"="ANTH",
  "Geography"="GEOG",
  "German"="GRMN",
  "German Studies"="GRMS",
  "Greek"="GREK",
  "Health,Medicine & Human Values"="HMHV",
  "History"="HIST",
  "International Studies"="ISI",
  "Italian"="ITAL",
  "Japanese"="JAPN",
  "Journal & Mass Comm"="JOUR",
  "Journalism"="JOUR",
  "Journalism & Mass Comm"="JOUR",
  "Languages Cultures & Literatures"="LCL",
  "Languages"="LANG",
  "Latin"="LATN",
  "Latin American Studies"="LTAM",
  "Linguistics"="LING",
  "Mass Communication"="COMM",
  "Mathematics"="MATH",
  "Mathematics Statistics"="MATH",
  "Museum Studies"="MSST",
  "Native American Studies"="NATV",
  "Navajo Language & Linguistics"="NVJO",
  "Philosophy"="PHIL",
  "Physics"="PHYS",
  "Physics & Astrophysics"="PHYS",
  "Physics Astronomy"="PHYS",
  "Astrophysics"="ASTR",
  "Political Science"="POLS",
  "Political Science Gen Admin"="POLS",
  "Portuguese"="PORT",
  "School of Public Admin"="PADM",
  "School of Public Administration"="PADM",
  "Public Administration"="PADM",
  "Psychology"="PSYC",
  "Religious Studies Prgm"="RELG",
  "Religious Studies"="RELG",
  "Russian"="RUSS",
  "Russian Studies"="RUSS",
  "Signed Language Interpreting"="SIGN",
  "Signed Language Interpret"="SIGN",
  "Sociology"="SOCI",
  "Spanish"="SPAN",
  "Spanish Portuguese"="SPAN",
  "Spanish & Portuguese"="SPAN",
  "Speech & Hearing Sciences"="SHS",
  "Speech and Hearing Sciences"="SHS",
  "Speech-Language Pathology"="SHS",
  "Statistics"="STAT",
  "Sustainability Studies"="SUST",
  "Sustainability Studies Program"="SUST",
  "Technical & Professional Comm"="TCOM",
  "Women Studies"="WGSS",
  "Womens Studies"="WGSS",
  "Wmn, Gndr, Sexlty Studies"="WGSS",
  "Women, Gndr, Sexuality Studies"="WGSS")


# Maps variant/historical program_name strings to the current canonical display name.
# Applied during transform_programs to consolidate Banner rename artifacts and
# X-prefix variant codes that carry a slightly different name text.
# Key   = the variant string as it appears in the Banner "Major" column
# Value = the canonical name to use in cedar_programs$program_name
#
# When Banner renames a program or introduces an X-prefix variant whose text
# differs from the primary code's text, add an entry here.
program_name_aliases <- c(
  # XCCS is Banner's X-prefix variant for CCS; its text differs from the primary CCS name
  "Chicana Chicano Studies"       = "Chicana and Chicano Studies",
  # Older Banner exports used "Chicana/o Studies" for the same program
  "Chicana/o Studies"             = "Chicana and Chicano Studies"
)


# Maps HR "Home Organization Desc" field to dept codes.
# Used in parse-HRreport.R and dept-report.R.
hr_org_desc_to_dept <- c(
  "American Studies"="AMST",
  "AS American Studies"="AMST",
  "Africana Studies"="AFST",
  "African American Studies"="AFST",
  "African American Studies Gen Admin"="AFST",
  "AS Anthropology"="ANTH",
  "Anthropology"="ANTH",
  "AS Biology"="BIOL",
  "AS Biology General Administrative"="BIOL",
  "AS BA/MD Program"="HMHV",
  "Biology"="BIOL",
  "Biology/Biological Sciences"="BIOL",
  "Biochemistry"="BIOC",
  "Chemistry"="CHEM",
  "AS Chemistry"="CHEM",
  "Chicana / Chicano Studies"="CCS",
  "Chicana and Chicano Studies"="CCS",
  "AS Chicana and Chicano Studies"="CCS",
  "Communication Journalism"="CJ",
  "Communication & Journalism"="CJ",
  "Earth & Planetary Sciences Dept"="EPS",
  "Earth and Planetary Sciences Dept"="EPS",
  "Earth and Planetary Sciences E PS"="EPS",
  "Earth & Planetary Sciences"="EPS",
  "AS Economics"="ECON",
  "Economics"="ECON",
  "English"="ENGL",
  "AS English"="ENGL",
  "English Studies"="ENGL",
  "English General Administrative"="ENGL",
  "Environmental Science"="EPS",
  "Geography"="GES",
  "Geography and Environmental Studies"="GES",
  "Health,Medicine & Human Values"="HMHV",
  "History"="HIST",
  "AS History"="HIST",
  "International Studies"="ISI",
  "International Studies Institute ISI"="ISI",
  "Mass Communication"="CJ",
  "Foreign Language Lit Gen Admin"="LCL",
  "Languages Cultures & Literatures"="LCL",
  "Languages Cultures & Lit Gen Admin"="LCL",
  "Foreign Languages Literatures"="LCL",
  "Latin American Studies"="LTAM",
  "Linguistics"="LING",
  "AS Linguistics"="LING",
  "Mathematics Statistics"="MATH",
  "AS Mathematics Statistics"="MATH",
  "Museum Studies"="MSST",
  "Native American Studies"="NATV",
  "AS Native American Studies"="NATV",
  "Philosophy"="PHIL",
  "AS Philosophy"="PHIL",
  "Physics"="PHYS",
  "Physics Astronomy"="PHYS",
  "AS Physics Astronomy"="PHYS",
  "CAS/CQuIC"="PHYS",
  "Physics Astronomy Gen Admin"="PHYS",
  "Political Science"="POLS",
  "AS Political Science"="POLS",
  "Political Science Gen Admin"="POLS",
  "School of Public Administration"="PADM",
  "Psychology"="PSYC",
  "AS Psychology"="PSYC",
  "Religious Studies Prgm"="RELG",
  "Religious Studies"="RELG",
  "Sociology"="SOCI",
  "AS Sociology"="SOCI",
  "Spanish Portuguese" = "SPAN",
  "Spanish & Portuguese" = "SPAN",
  "AS Spanish Portuguese" = "SPAN",
  "Speech and Hearing Sciences" = "SHS",
  "Speech & Hearing Sciences" = "SHS",
  "AS Speech and Hearing Sciences" = "SHS",
  "Speech Hearing Sciences Gen Admin" = "SHS",
  "Sustainability Studies Program" = "SUST",
  "Women Gender and Sexuality Studies" = "WGSS",
  "AS Women Gender and Sexuality Studies" = "WGSS",
  "Womens Studies"="WGSS")

