# unit_catalog.R
#
# SINGLE SOURCE OF TRUTH for UNM's organizational hierarchy:
#   College → Department → Subject Code
#
# Derived from: https://xmlschedule.unm.edu/docs/schedule-key.html
# Augmented with manual overrides for interdisciplinary and special programs.
#
# Columns:
#   college_code  — Banner 2-letter code (matches COLLEGE in DESRs)
#   college_name  — Full name (matches "Actual College" in academic_studies)
#   dept_code     — Short code used in cedar_sections$department and cedar_programs$dept_code
#   dept_name     — Human-readable label for the department (UI display)
#   subject_code  — Banner subject code from DESRs (many-to-one with dept_code)
#
# Usage in transform-to-cedar.R:
#   subj_to_dept is derived as: setNames(unit_catalog$dept_code, unit_catalog$subject_code)
#   college lookups are derived from distinct(college_code, college_name) pairs
#   dept_name lookup is derived from distinct(dept_code, dept_name) pairs
#
# Overrides (marked with # OVERRIDE) are intentional deviations from the
# official schedule key — e.g., aggregating sub-units, interdisciplinary programs.

unit_catalog <- tibble::tribble(
  ~college_code, ~college_name,                        ~dept_code, ~dept_name,                             ~subject_code,

  # ── Anderson Schools of Management (MG) ─────────────────────────────────────
  "MG", "Anderson Schools of Management",             "ACCT",  "Accounting",                              "ACCT",
  "MG", "Anderson Schools of Management",             "MGMT",  "Management",                              "MGMT",
  "MG", "Anderson Schools of Management",             "MGMT",  "Management",                              "BUSA",   # Business Admin courses fall under MGMT
  "MG", "Anderson Schools of Management",             "MKTG",  "Marketing",                               "MKTG",
  "MG", "Anderson Schools of Management",             "ENTR",  "Entrepreneurship",                        "ENTR",
  "MG", "Anderson Schools of Management",             "BCIS",  "Business Computer Info Systems",          "BCIS",

  # ── College of Arts and Sciences (AS) ───────────────────────────────────────
  "AS", "College of Arts and Sciences",               "AFST",  "Africana Studies",                        "AFST",
  "AS", "College of Arts and Sciences",               "AFST",  "Africana Studies",                        "SWAH",
  "AS", "College of Arts and Sciences",               "AMST",  "American Studies",                        "AMST",
  "AS", "College of Arts and Sciences",               "ANTH",  "Anthropology",                            "ANTH",
  "AS", "College of Arts and Sciences",               "BIOL",  "Biology",                                 "BIOL",
  "AS", "College of Arts and Sciences",               "CCS",   "Chicana and Chicano Studies",              "CCS",
  "AS", "College of Arts and Sciences",               "CCS",   "Chicana and Chicano Studies",              "CCST",   # older code
  "AS", "College of Arts and Sciences",               "CHEM",  "Chemistry",                               "CHEM",
  "AS", "College of Arts and Sciences",               "CJ",    "Communication and Journalism",             "CJ",
  "AS", "College of Arts and Sciences",               "CJ",    "Communication and Journalism",             "COMM",
  "AS", "College of Arts and Sciences",               "CJ",    "Communication and Journalism",             "JOUR",
  "AS", "College of Arts and Sciences",               "CJ",    "Communication and Journalism",             "JRMC",
  "AS", "College of Arts and Sciences",               "CJ",    "Communication and Journalism",             "MCOM",
  "AS", "College of Arts and Sciences",               "ECON",  "Economics",                               "ECON",
  "AS", "College of Arts and Sciences",               "ENGL",  "English",                                 "ENGL",
  "AS", "College of Arts and Sciences",               "ENGL",  "English",                                 "MDVL",
  "AS", "College of Arts and Sciences",               "EPS",   "Earth & Planetary Sciences",              "EPS",
  "AS", "College of Arts and Sciences",               "EPS",   "Earth & Planetary Sciences",              "ENVS",
  "AS", "College of Arts and Sciences",               "EPS",   "Earth & Planetary Sciences",              "GEOL",
  "AS", "College of Arts and Sciences",               "GES",   "Geography and Environmental Studies",     "GEOG",
  "AS", "College of Arts and Sciences",               "GES",   "Geography and Environmental Studies",     "SUST",
  "AS", "College of Arts and Sciences",               "HIST",  "History",                                 "HIST",
  "AS", "College of Arts and Sciences",               "HMHV",  "Health, Medicine & Human Values",         "HMHV",   # OVERRIDE: interdisciplinary, housed in AS
  "AS", "College of Arts and Sciences",               "ISI",   "International Studies",                   "INTS",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "ARBC",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "ARAB",   # pre-2020 code
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "CHIN",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "CLST",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "COMP",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "EAS",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "FREN",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "GREK",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "GRMN",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "ITAL",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "JAPN",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "LANG",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "LATN",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "LCL",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "MLNG",
  "AS", "College of Arts and Sciences",               "LCL",   "Languages, Cultures & Literatures",       "RUSS",
  "AS", "College of Arts and Sciences",               "LING",  "Linguistics",                             "LING",
  "AS", "College of Arts and Sciences",               "LING",  "Linguistics",                             "NAVA",
  "AS", "College of Arts and Sciences",               "LING",  "Linguistics",                             "NVJO",
  "AS", "College of Arts and Sciences",               "LING",  "Linguistics",                             "SIGN",
  "AS", "College of Arts and Sciences",               "LTAM",  "Latin American Studies",                  "LTAM",
  "AS", "College of Arts and Sciences",               "MATH",  "Mathematics and Statistics",              "MATH",
  "AS", "College of Arts and Sciences",               "MATH",  "Mathematics and Statistics",              "STAT",
  "AS", "College of Arts and Sciences",               "MSST",  "Museum Studies",                          "MSST",   # OVERRIDE: interdisciplinary program, listed as "*Interdisciplinary: A.S."
  "AS", "College of Arts and Sciences",               "NATV",  "Native American Studies",                 "NATV",
  "AS", "College of Arts and Sciences",               "PADM",  "Public Administration",                   "PADM",   # OVERRIDE: housed in AS for course listing purposes
  "AS", "College of Arts and Sciences",               "PHIL",  "Philosophy",                              "PHIL",
  "AS", "College of Arts and Sciences",               "PHYS",  "Physics and Astronomy",                   "PHYS",
  "AS", "College of Arts and Sciences",               "PHYS",  "Physics and Astronomy",                   "PHYC",
  "AS", "College of Arts and Sciences",               "PHYS",  "Physics and Astronomy",                   "ASTR",
  "AS", "College of Arts and Sciences",               "POLS",  "Political Science",                       "POLS",
  "AS", "College of Arts and Sciences",               "PSYC",  "Psychology",                              "PSYC",
  "AS", "College of Arts and Sciences",               "PSYC",  "Psychology",                              "PSY",    # old code → PSYC
  "AS", "College of Arts and Sciences",               "RELG",  "Religious Studies",                       "RELG",
  "AS", "College of Arts and Sciences",               "SHS",   "Speech and Hearing Sciences",             "SHS",
  "AS", "College of Arts and Sciences",               "SOCI",  "Sociology",                               "SOCI",
  "AS", "College of Arts and Sciences",               "SOCI",  "Sociology",                               "SOC",    # old code → SOCI
  "AS", "College of Arts and Sciences",               "SOCI",  "Sociology",                               "CRIM",
  "AS", "College of Arts and Sciences",               "SPAN",  "Spanish & Portuguese",                    "SPAN",
  "AS", "College of Arts and Sciences",               "SPAN",  "Spanish & Portuguese",                    "PORT",
  "AS", "College of Arts and Sciences",               "WGSS",  "Women, Gender & Sexuality Studies",       "WGSS",
  "AS", "College of Arts and Sciences",               "WGSS",  "Women, Gender & Sexuality Studies",       "WMST",   # old code → WGSS
  "AS", "College of Arts and Sciences",               "WGSS",  "Women, Gender & Sexuality Studies",       "GNDR",   # old code → WGSS

  # ── College of Education & Human Sciences (EH) ──────────────────────────────
  "EH", "College of Educ & Human Sci",                "EDUC",  "Education",                               "EDUC",
  "EH", "College of Educ & Human Sci",                "LEAD",  "Educational Leadership",                  "LEAD",
  "EH", "College of Educ & Human Sci",                "MSET",  "Math, Science & Technology Education",    "MSET",
  "EH", "College of Educ & Human Sci",                "ATED",  "Athletic Training Education",             "ATED",
  "EH", "College of Educ & Human Sci",                "HED",   "Health Education",                        "HED",
  "EH", "College of Educ & Human Sci",                "HED",   "Health Education",                        "HLED",
  "EH", "College of Educ & Human Sci",                "PHED",  "Physical Education",                      "PHED",
  "EH", "College of Educ & Human Sci",                "PHED",  "Physical Education",                      "PEP",
  "EH", "College of Educ & Human Sci",                "PHED",  "Physical Education",                      "PENP",
  "EH", "College of Educ & Human Sci",                "PHED",  "Physical Education",                      "PRPE",
  "EH", "College of Educ & Human Sci",                "COUN",  "Counselor Education",                     "COUN",
  "EH", "College of Educ & Human Sci",                "EDPY",  "Educational Psychology",                  "EDPY",
  "EH", "College of Educ & Human Sci",                "FCS",   "Family and Child Studies",                "FCS",
  "EH", "College of Educ & Human Sci",                "FCS",   "Family and Child Studies",                "FCST",
  "EH", "College of Educ & Human Sci",                "NUTR",  "Nutrition",                               "NUTR",
  "EH", "College of Educ & Human Sci",                "LLSS",  "Language, Literacy & Sociocultural Stds", "LLSS",
  "EH", "College of Educ & Human Sci",                "SPED",  "Special Education",                       "SPED",
  "EH", "College of Educ & Human Sci",                "SPED",  "Special Education",                       "SPCD",

  # ── College of Fine Arts (FA) ────────────────────────────────────────────────
  "FA", "College of Fine Arts",                       "ARTH",  "Art History",                             "ARTH",
  "FA", "College of Fine Arts",                       "ARTS",  "Art Studio",                              "ARTS",
  "FA", "College of Fine Arts",                       "ARTS",  "Art Studio",                              "ARTE",
  "FA", "College of Fine Arts",                       "FDMA",  "Film and Digital Arts",                   "FDMA",
  "FA", "College of Fine Arts",                       "MUS",   "Music",                                   "MUS",
  "FA", "College of Fine Arts",                       "MUS",   "Music",                                   "MUSC",
  "FA", "College of Fine Arts",                       "MUS",   "Music",                                   "MUSE",
  "FA", "College of Fine Arts",                       "MUS",   "Music",                                   "APMS",
  "FA", "College of Fine Arts",                       "DANC",  "Dance",                                   "DANC",
  "FA", "College of Fine Arts",                       "THEA",  "Theatre",                                 "THEA",

  # ── College of Nursing (NU) ──────────────────────────────────────────────────
  "NU", "College of Nursing",                         "NURS",  "Nursing",                                 "NURS",
  "NU", "College of Nursing",                         "NURS",  "Nursing",                                 "NMNC",

  # ── College of Pharmacy (PH) ─────────────────────────────────────────────────
  "PH", "College of Pharmacy",                        "PHRM",  "Pharmacy",                                "PHRM",

  # ── College of Population Health (PO) ───────────────────────────────────────
  "PO", "College of Population Health",               "HSCI",  "Health Sciences",                         "HSCI",
  "PO", "College of Population Health",               "HSCI",  "Health Sciences",                         "PH",
  "PO", "College of Population Health",               "IPEP",  "Interprofessional Education",             "IPEP",

  # ── Graduate Programs (GP) ───────────────────────────────────────────────────
  # Note: GP is a college code for students in interdisciplinary grad programs.
  # Their courses are typically listed under their home dept college.
  "GP", "Graduate Programs",                          "GLNS",  "Global & National Security",              "GLNS",
  "GP", "Graduate Programs",                          "OCTH",  "Occupational Therapy",                    "OCTH",

  # ── Honors College (HC) ──────────────────────────────────────────────────────
  "HC", "Honors College",                             "HNRS",  "Honors",                                  "HNRS",
  "HC", "Honors College",                             "HNRS",  "Honors",                                  "UHON",

  # ── School of Architecture and Planning (AP) ─────────────────────────────────
  "AP", "School of Arch. and Planning",               "ARCH",  "Architecture",                            "ARCH",
  "AP", "School of Arch. and Planning",               "CRP",   "Community & Regional Planning",           "CRP",
  "AP", "School of Arch. and Planning",               "CRP",   "Community & Regional Planning",           "PLAN",
  "AP", "School of Arch. and Planning",               "LA",    "Landscape Architecture",                  "LA",
  "AP", "School of Arch. and Planning",               "LA",    "Landscape Architecture",                  "LARC",

  # ── School of Engineering (EN) ───────────────────────────────────────────────
  "EN", "School of Engineering",                      "CS",    "Computer Science",                        "CS",
  "EN", "School of Engineering",                      "CS",    "Computer Science",                        "CSCI",   # OVERRIDE: CSCI courses belong to CS dept
  "EN", "School of Engineering",                      "ECE",   "Electrical & Computer Engineering",       "ECE",
  "EN", "School of Engineering",                      "ME",    "Mechanical Engineering",                  "ME",
  "EN", "School of Engineering",                      "CE",    "Civil Engineering",                       "CE",
  "EN", "School of Engineering",                      "CBE",   "Chemical & Biological Engineering",       "CBE",
  "EN", "School of Engineering",                      "NE",    "Nuclear Engineering",                     "NE",
  "EN", "School of Engineering",                      "NE",    "Nuclear Engineering",                     "NUCE",
  "EN", "School of Engineering",                      "CPE",   "Computer Engineering",                    "CPE",
  "EN", "School of Engineering",                      "BME",   "Biomedical Engineering",                  "BME",
  "EN", "School of Engineering",                      "ENG",   "Engineering (General)",                   "ENG",
  "EN", "School of Engineering",                      "NSME",  "Nanoscience & Microsystems Engineering",  "NSME",
  "EN", "School of Engineering",                      "NSME",  "Nanoscience & Microsystems Engineering",  "NSMS",
  "EN", "School of Engineering",                      "BCIS",  "Business Computer Info Systems",          "BCIS",   # also in MG; EN section
  "EN", "School of Engineering",                      "ECOP",  "Engineering Cooperative",                 "ECOP",

  # ── School of Law (LW) ───────────────────────────────────────────────────────
  "LW", "School of Law",                              "LAW",   "Law",                                     "LAW",

  # ── School of Medicine (ME) ──────────────────────────────────────────────────
  "ME", "School of Medicine",                         "ANES",  "Anesthesiology",                          "ANES",
  "ME", "School of Medicine",                         "BIOC",  "Biochemistry",                            "BIOC",
  "ME", "School of Medicine",                         "BIOM",  "Biomedical Sciences",                     "BIOM",
  "ME", "School of Medicine",                         "CLNS",  "Clinical Sciences",                       "CLNS",
  "ME", "School of Medicine",                         "DEHY",  "Dental Hygiene",                          "DEHY",
  "ME", "School of Medicine",                         "EMS",   "Emergency Medicine",                      "EMS",
  "ME", "School of Medicine",                         "MEDL",  "Medical Laboratory Sciences",             "MEDL",
  "ME", "School of Medicine",                         "MPHY",  "Medical Physics",                         "MPHY",
  "ME", "School of Medicine",                         "NUCM",  "Nuclear Medicine",                        "NUCM",
  "ME", "School of Medicine",                         "OCTH",  "Occupational Therapy",                    "OCTH",
  "ME", "School of Medicine",                         "PAST",  "Physician Assistant Studies",             "PAST",
  "ME", "School of Medicine",                         "PT",    "Physical Therapy",                        "PT",
  "ME", "School of Medicine",                         "RADS",  "Radiologic Sciences",                     "RADS",

  # ── University College (UC) ──────────────────────────────────────────────────
  "UC", "University College",                         "AFAS",  "Air Force Aerospace Studies",             "AFAS",
  "UC", "University College",                         "FYEX",  "First Year Experience",                   "FYEX",
  "UC", "University College",                         "LAIS",  "Liberal Arts & Integrative Studies",      "LAIS",
  "UC", "University College",                         "MLSL",  "Military Science & Leadership",           "MLSL",
  "UC", "University College",                         "NSE",   "National Student Exchange",               "NSE",
  "UC", "University College",                         "NVSC",  "Naval Science",                           "NVSC",
  "UC", "University College",                         "UNIV",  "University",                              "UNIV",
  "UC", "University College",                         "WR",    "Water Resources",                         "WR",
  "UC", "University College",                         "ISEP",  "International Studies Exchange",          "ISEP",
  "UC", "University College",                         "CELR",  "Continuing Education",                    "CELR",
  "UC", "University College",                         "GLNS",  "Global & National Security",              "GLNS",   # also in GP

  # ── University Libraries & Learning Science (LL) ─────────────────────────────
  "LL", "Univ Libraries & Learn Science",             "OILS",  "Org, Info & Learning Sciences",           "OILS",
  "LL", "Univ Libraries & Learn Science",             "IADL",  "Instructional & Learning Sciences",       "IADL",

  # ── Associate Degree / Branch Campuses (AD) ──────────────────────────────────
  # Branch campus programs — subject codes map to the campus-level org
  "AD", "Associate Degree",                           "APTE",  "Applied Technologies",                    "APTE",
  "AD", "Associate Degree",                           "ARTS",  "Art Studio",                              "ARTS",
  "AD", "Associate Degree",                           "ASPE",  "Pre-Engineering",                         "ASPE",
  "AD", "Associate Degree",                           "AUTT",  "Automotive Technology",                   "AUTT",
  "AD", "Associate Degree",                           "BSTC",  "Business Technology",                     "BSTC",
  "AD", "Associate Degree",                           "BUSA",  "Business Administration (Branch)",        "BUSA",
  "AD", "Associate Degree",                           "CART",  "Culinary Arts",                           "CART",
  "AD", "Associate Degree",                           "CDL",   "Commercial Driver License",               "CDL",
  "AD", "Associate Degree",                           "CJUS",  "Criminal Justice",                        "CJUS",
  "AD", "Associate Degree",                           "CJUS",  "Criminal Justice",                        "CRJS",
  "AD", "Associate Degree",                           "CNA",   "Certified Nursing Assistant",             "CNA",
  "AD", "Associate Degree",                           "CNST",  "Construction Technology",                 "CNST",
  "AD", "Associate Degree",                           "COSM",  "Cosmetology",                             "COSM",
  "AD", "Associate Degree",                           "DDM",   "Dental Assisting",                        "DDM",
  "AD", "Associate Degree",                           "DMA",   "Digital Media Arts",                      "DMA",
  "AD", "Associate Degree",                           "DRFT",  "Drafting",                                "DRFT",
  "AD", "Associate Degree",                           "ECED",  "Early Childhood Education",               "ECED",
  "AD", "Associate Degree",                           "EDUC",  "Education",                               "EDUC",
  "AD", "Associate Degree",                           "ELCT",  "Electronics",                             "ELCT",
  "AD", "Associate Degree",                           "ELTR",  "Electrical Technology",                   "ELTR",
  "AD", "Associate Degree",                           "EMS",   "Emergency Medicine",                      "EMS",
  "AD", "Associate Degree",                           "ENPD",  "Environmental Planning & Design",         "ENPD",
  "AD", "Associate Degree",                           "ENVS",  "Environmental Science (Branch)",           "ENVS",
  "AD", "Associate Degree",                           "FDMA",  "Film and Digital Arts",                   "FDMA",
  "AD", "Associate Degree",                           "FISC",  "Fire Science",                            "FISC",
  "AD", "Associate Degree",                           "FORS",  "Forensic Science (Branch)",               "FORS",
  "AD", "Associate Degree",                           "GAME",  "Game Design",                             "GAME",
  "AD", "Associate Degree",                           "GNST",  "General Studies",                         "GNST",
  "AD", "Associate Degree",                           "HCDA",  "Health Careers Dental Assisting",         "HCDA",
  "AD", "Associate Degree",                           "HCHT",  "Health Careers Health Info Tech",         "HCHT",
  "AD", "Associate Degree",                           "HCHS",  "Health Careers Health Sciences",          "HCHS",
  "AD", "Associate Degree",                           "HLED",  "Health Education (Branch)",               "HLED",
  "AD", "Associate Degree",                           "HMSV",  "Human Services",                          "HMSV",
  "AD", "Associate Degree",                           "HS",    "Human Services (Alt)",                    "HS",
  "AD", "Associate Degree",                           "HSMT",  "Health Science & Medical Tech",           "HSMT",
  "AD", "Associate Degree",                           "IT",    "Information Technology",                  "IT",
  "AD", "Associate Degree",                           "LART",  "Liberal Arts",                            "LART",
  "AD", "Associate Degree",                           "MAS",   "Medical Administrative Specialist",       "MAS",
  "AD", "Associate Degree",                           "MCHT",  "Mechatronics",                            "MCHT",
  "AD", "Associate Degree",                           "MFGT",  "Manufacturing",                           "MFGT",
  "AD", "Associate Degree",                           "MLT",   "Medical Laboratory Technology",           "MLT",
  "AD", "Associate Degree",                           "NFFW",  "Non-Credit / Community Ed",               "NFFW",
  "AD", "Associate Degree",                           "NWOB",  "Non-Credit / Workforce",                  "NWOB",
  "AD", "Associate Degree",                           "OBT",   "Office Business Technology",              "OBT",
  "AD", "Associate Degree",                           "PBT",   "Phlebotomy",                              "PBT",
  "AD", "Associate Degree",                           "PBST",  "Public Safety",                           "PBST",
  "AD", "Associate Degree",                           "PCA",   "Patient Care Assistant",                  "PCA",
  "AD", "Associate Degree",                           "PH",    "Public Health (Branch)",                  "PH",
  "AD", "Associate Degree",                           "PTEC",  "Process Technology",                      "PTEC",
  "AD", "Associate Degree",                           "RCTB",  "Recreation & Tourism",                    "RCTB",
  "AD", "Associate Degree",                           "ROBO",  "Robotics",                                "ROBO",
  "AD", "Associate Degree",                           "SLRT",  "Sign Language",                           "SLRT",
  "AD", "Associate Degree",                           "SOWK",  "Social Work",                             "SOWK",
  "AD", "Associate Degree",                           "STIN",  "STEM Integration",                        "STIN",
  "AD", "Associate Degree",                           "SUST",  "Sustainability (Branch)",                 "SUST",
  "AD", "Associate Degree",                           "TRST",  "Truck & Transport",                       "TRST",
  "AD", "Associate Degree",                           "WELD",  "Welding",                                 "WELD",
  "AD", "Associate Degree",                           "WLDT",  "Welding Technology",                      "WLDT",
  "AD", "Associate Degree",                           "WOOD",  "Woodworking",                             "WOOD",
  "AD", "Associate Degree",                           "WW",    "Water & Wastewater",                      "WW",
  "AD", "Associate Degree",                           "AAC",   "Academic Assistance Center",              "AAC",
  "AD", "Associate Degree",                           "ADOB",  "Adobe/Creative Suite",                    "ADOB",
  "AD", "Associate Degree",                           "AEEC",  "Automotive/Electrical",                   "AEEC",
  "AD", "Associate Degree",                           "ASFD",  "Automotive Service/Ford",                 "ASFD",
  "AD", "Associate Degree",                           "BFIN",  "Business Finance",                        "BFIN",
  "AD", "Associate Degree",                           "CADT",  "CAD Technology",                          "CADT",
  "AD", "Associate Degree",                           "CRT",   "Crisis Response Training",                "CRT",
  "AD", "Associate Degree",                           "CT",    "Construction Technology (Alt)",           "CT",

  # ── Provost / Public Admin (PA) ──────────────────────────────────────────────
  "PA", "Provost Academic/Admin",                     "AFAS",  "Air Force Aerospace Studies",             "AFAS",
  "PA", "Provost Academic/Admin",                     "MLSL",  "Military Science & Leadership",           "MLSL",
  "PA", "Provost Academic/Admin",                     "NVSC",  "Naval Science",                           "NVSC",
  "PA", "Provost Academic/Admin",                     "PADM",  "Public Administration",                   "PADM"
)
