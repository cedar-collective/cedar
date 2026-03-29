# major_dept_map.R
#
# Maps Banner major codes to department codes for UNM programs.
# Used at transform time to stamp dept_code onto cedar_programs rows.
#
# Only three columns are used by downstream code; dead metadata columns
# (degree_abbr, degree_level, program_type, canonical_code) are stripped
# at the end of this file with distinct() + select().
#
# Columns (after stripping):
#   college_code  — Banner 2-letter college code (home dept's college, not 'GP' for grad students)
#   dept_code     — Links to subj_dept_map$dept_code
#   major_code    — Banner major code (e.g., "HIST", "FNAP", "PHRD")
#
# Multiple rows per major_code are common (same code offered at BA and MA level, etc.).
# catalog_lookups.R deduplicates when building the lookup vectors:
#   major_college_to_dept       — "major_code:college_code" → dept_code  (compound key, used in transform)
#   major_to_dept   — major_code → dept_code               (simple fallback; main campus wins)
#
# Notes:
#   - Graduate students appear under 'Graduate Programs' (GP) in Banner, but college_code here
#     reflects the home academic unit, not GP, for consistent department-level filtering.
#   - UNDC = undecided students; included for completeness but not a real academic program.
#   - Branch campus programs use college_code = "AD"; compound key (major_college_to_dept) disambiguates
#     cases where the same major_code appears in both AS and AD (e.g., CRIM → SOCI vs CJUS).
#
# The tribble below retains legacy metadata columns so the file can be regenerated from
# scripts/gen-program-catalog.R without data loss. Only the first three columns are used.
#
# Auto-generated from academic_studies.qs; review and edit edge cases as needed.
# To regenerate: run scripts/gen-program-catalog.R

major_dept_map <- tibble::tribble(
  ~college_code, ~dept_code, ~major_code, ~degree_abbr, ~degree_level, ~program_type, ~canonical_code,

  # ── School of Arch. and Planning (AP) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # ARCH
  "AP", "ARCH", "ARCH", "BAA", "Undergraduate", "degree", NA,
  "AP", "ARCH", "ARCT", "BAA", "Undergraduate", "degree", NA,
  "AP", "ARCH", "ARCH", "MARCH", "Graduate", "degree", NA,
  "AP", "ARCH", "ARCH", "MS", "Graduate", "degree", NA,
  # pre-majors:
  "AP", "ARCH", "FARC", "BAA", "Undergraduate", "pre_major", "ARCH",
  "AP", "ARCH", "HPR", "PDCERT", "Certificate", "degree", NA,
  # CRP
  "AP", "CRP", "ENVD", "BEPD", "Undergraduate", "degree", NA,
  "AP", "CRP", "CRP", "MCRP", "Graduate", "degree", NA,
  "AP", "CRP", "URBI", "PDCERT", "Certificate", "degree", NA,
  # pre-majors:
  "AP", "CRP", "FENV", "BEPD", "Undergraduate", "pre_major", "ENVD",
  # LA
  "AP", "LA", "LA", "B", "Undergraduate", "degree", NA,
  "AP", "LA", "LA", "MLA", "Graduate", "degree", NA,
  # ── College of Arts and Sciences (AS) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # AFST
  "AS", "AFST", "AFST", "BA", "Undergraduate", "degree", NA,
  # pre-majors:
  "AS", "AFST", "FAFS", "BA", "Undergraduate", "pre_major", "AFST",
  # AMST
  "AS", "AMST", "AMST", "BA", "Undergraduate", "degree", NA,
  "AS", "AMST", "AMST", "MA", "Graduate", "degree", NA,
  "AS", "AMST", "AMST", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "AMST", "FAMS", "BA", "Undergraduate", "pre_major", "AMST",
  # ANTH
  "AS", "ANTH", "ANTH", "BA", "Undergraduate", "degree", NA,
  "AS", "ANTH", "ANTH", "BS", "Undergraduate", "degree", NA,
  "AS", "ANTH", "ANTH", "MA", "Graduate", "degree", NA,
  "AS", "ANTH", "ANTH", "MS", "Graduate", "degree", NA,
  "AS", "ANTH", "ANTH", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "ANTH", "FANT", "BA", "Undergraduate", "pre_major", "ANTH",
  "AS", "ANTH", "FANT", "BS", "Undergraduate", "pre_major", "ANTH",
  # BIOL
  "AS", "BIOL", "BIOL", "BA", "Undergraduate", "degree", NA,
  "AS", "BIOL", "BIOL", "BS", "Undergraduate", "degree", NA,
  "AS", "BIOL", "CHBI", "BS", "Undergraduate", "degree", NA,
  "AS", "BIOL", "BIOL", "MS", "Graduate", "degree", NA,
  "AS", "BIOL", "BIOL", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "BIOL", "FBIO", "BA", "Undergraduate", "pre_major", "BIOL",
  "AS", "BIOL", "FBIO", "BS", "Undergraduate", "pre_major", "BIOL",
  "AS", "BIOL", "FCHB", "BS", "Undergraduate", "pre_major", "CHBI",
  # CCS
  "AS", "CCS", "CCS", "BA", "Undergraduate", "degree", NA,
  "AS", "CCS", "CCS", "MA", "Graduate", "degree", NA,
  "AS", "CCS", "CCS", "PHD", "Graduate", "degree", NA,
  "AS", "CCS", "CCS", "GCERT", "Certificate", "degree", NA,
  # variants (X-prefix / extended campus):
  "AS", "CCS", "XFCC", "BA", "Undergraduate", "variant", "CCS",
  "AS", "CCS", "XCCS", "BA", "Undergraduate", "variant", "CCS",
  "AS", "CCS", "XCCS", "GCERT", "Certificate", "variant", "CCS",
  # pre-majors:
  "AS", "CCS", "FCCS", "BA", "Undergraduate", "pre_major", "CCS",
  # CHEM
  "AS", "CHEM", "CHEM", "BA", "Undergraduate", "degree", NA,
  "AS", "CHEM", "CHEM", "BS", "Undergraduate", "degree", NA,
  "AS", "CHEM", "CHEM", "MS", "Graduate", "degree", NA,
  "AS", "CHEM", "CHEM", "PHD", "Graduate", "degree", NA,
  "AS", "CHEM", "CTS", "GCERT", "Certificate", "degree", NA,
  # pre-majors:
  "AS", "CHEM", "FCHM", "BA", "Undergraduate", "pre_major", "CHEM",
  "AS", "CHEM", "FCHM", "BS", "Undergraduate", "pre_major", "CHEM",
  # CJ
  "AS", "CJ", "JRMC", "BA", "Undergraduate", "degree", NA,
  "AS", "CJ", "COM", "BA", "Undergraduate", "degree", NA,
  "AS", "CJ", "JOUR", "BA", "Undergraduate", "degree", NA,
  "AS", "CJ", "COM", "MA", "Graduate", "degree", NA,
  "AS", "CJ", "COM", "PHD", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "AS", "CJ", "XFJM", "BA", "Undergraduate", "variant", "JRMC",
  "AS", "CJ", "XJMC", "BA", "Undergraduate", "variant", "JRMC",
  # pre-majors:
  "AS", "CJ", "FJMC", "BA", "Undergraduate", "pre_major", "JRMC",
  "AS", "CJ", "FCOM", "BA", "Undergraduate", "pre_major", "COM",
  "AS", "CJ", "FMCO", "BA", "Undergraduate", "pre_major", "MCOM",
  # ECON
  "AS", "ECON", "ECON", "BA", "Undergraduate", "degree", NA,
  "AS", "ECON", "ECON", "MA", "Graduate", "degree", NA,
  "AS", "ECON", "ECON", "PHD", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "AS", "ECON", "XECO", "BA", "Undergraduate", "variant", "ECON",
  "AS", "ECON", "XFEC", "BA", "Undergraduate", "variant", "ECON",
  # pre-majors:
  "AS", "ECON", "FECO", "BA", "Undergraduate", "pre_major", "ECON",
  # ENGL
  "AS", "ENGL", "ENGS", "BA", "Undergraduate", "degree", NA,
  "AS", "ENGL", "ENGP", "BA", "Undergraduate", "degree", NA,
  "AS", "ENGL", "ENGL", "BA", "Undergraduate", "degree", NA,
  "AS", "ENGL", "ENGL", "MA", "Graduate", "degree", NA,
  "AS", "ENGL", "CRWR", "MFA", "Graduate", "degree", NA,
  "AS", "ENGL", "ENGL", "PHD", "Graduate", "degree", NA,
  "AS", "ENGL", "TPC", "GCERT", "Certificate", "degree", NA,
  # pre-majors:
  "AS", "ENGL", "FENS", "BA", "Undergraduate", "pre_major", "ENGS",
  "AS", "ENGL", "FENP", "BA", "Undergraduate", "pre_major", "ENGP",
  # EPS
  "AS", "EPS", "EPS", "BA", "Undergraduate", "degree", NA,
  "AS", "EPS", "ENSC", "BS", "Undergraduate", "degree", NA,
  "AS", "EPS", "EPS", "BS", "Undergraduate", "degree", NA,
  "AS", "EPS", "ENSC", "BS", "Undergraduate", "degree", NA,
  "AS", "EPS", "EPS", "MS", "Graduate", "degree", NA,
  "AS", "EPS", "EPS", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "EPS", "FEPS", "BA", "Undergraduate", "pre_major", "EPS",
  "AS", "EPS", "FESC", "BS", "Undergraduate", "pre_major", "ENSC",
  "AS", "EPS", "FEPS", "BS", "Undergraduate", "pre_major", "EPS",
  # GES
  "AS", "GES", "GEOG", "BA", "Undergraduate", "degree", NA,
  "AS", "GES", "GEOG", "BS", "Undergraduate", "degree", NA,
  "AS", "GES", "GEOG", "MS", "Graduate", "degree", NA,
  "AS", "GES", "GESP", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "GES", "FGEO", "BA", "Undergraduate", "pre_major", "GEOG",
  "AS", "GES", "FGEO", "BS", "Undergraduate", "pre_major", "GEOG",
  # HIST
  "AS", "HIST", "HIST", "BA", "Undergraduate", "degree", NA,
  "AS", "HIST", "HIST", "MA", "Graduate", "degree", NA,
  "AS", "HIST", "HIST", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "HIST", "FHIS", "BA", "Undergraduate", "pre_major", "HIST",
  # HMHV
  "AS", "HMHV", "HMHV", "BA", "Undergraduate", "degree", NA,
  # ISI
  "AS", "ISI", "INTS", "BA", "Undergraduate", "degree", NA,
  # pre-majors:
  "AS", "ISI", "FINT", "BA", "Undergraduate", "pre_major", "INTS",
  # LCL
  "AS", "LCL", "CLST", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "EAST", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "LANG", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "FREN", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "GRMN", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "RUSL", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "CLCS", "BA", "Undergraduate", "degree", NA,
  "AS", "LCL", "CLCS", "MA", "Graduate", "degree", NA,
  "AS", "LCL", "FREN", "MA", "Graduate", "degree", NA,
  "AS", "LCL", "GERS", "MA", "Graduate", "degree", NA,
  "AS", "LCL", "FRST", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "LCL", "FCLS", "BA", "Undergraduate", "pre_major", "CLST",
  "AS", "LCL", "FCLC", "BA", "Undergraduate", "pre_major", "CLCS",
  "AS", "LCL", "FEAS", "BA", "Undergraduate", "pre_major", "EAS",
  "AS", "LCL", "FLNG", "BA", "Undergraduate", "pre_major", "LANG",
  "AS", "LCL", "FFRE", "BA", "Undergraduate", "pre_major", "FREN",
  "AS", "LCL", "FGRM", "BA", "Undergraduate", "pre_major", "GRMN",
  "AS", "LCL", "FRUS", "BA", "Undergraduate", "pre_major", "RUSL",
  # LING
  "AS", "LING", "LING", "BA", "Undergraduate", "degree", NA,
  "AS", "LING", "SIGN", "BS", "Undergraduate", "degree", NA,
  "AS", "LING", "LING", "MA", "Graduate", "degree", NA,
  "AS", "LING", "LING", "PHD", "Graduate", "degree", NA,
  "AS", "LING", "ELNG", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "LING", "FLIN", "BA", "Undergraduate", "pre_major", "LING",
  "AS", "LING", "FSIG", "BS", "Undergraduate", "pre_major", "SIGN",
  # LTAM
  "AS", "LTAM", "LTAM", "BA", "Undergraduate", "degree", NA,
  "AS", "LTAM", "LTAM", "MA", "Graduate", "degree", NA,
  "AS", "LTAM", "LTAM", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "LTAM", "FLTA", "BA", "Undergraduate", "pre_major", "LTAM",
  # MATH
  "AS", "MATH", "MATH", "BS", "Undergraduate", "degree", NA,
  "AS", "MATH", "STAT", "BS", "Undergraduate", "degree", NA,
  "AS", "MATH", "MATH", "MS", "Graduate", "degree", NA,
  "AS", "MATH", "STAT", "MS", "Graduate", "degree", NA,
  "AS", "MATH", "MATH", "PHD", "Graduate", "degree", NA,
  "AS", "MATH", "STAT", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "MATH", "FMAT", "BS", "Undergraduate", "pre_major", "MATH",
  "AS", "MATH", "FSTA", "BS", "Undergraduate", "pre_major", "STAT",
  # MSST  (Museum Studies: has BA-track concentration but no standalone BA/BS degree;
  #         CERT-MSST-AS is the formal undergrad program; MA/MS for graduate)
  "AS", "MSST", "MSST", "MA", "Graduate", "degree", NA,
  "AS", "MSST", "MSST", "MS", "Graduate", "degree", NA,
  "AS", "MSST", "MSST", "CERT", "Certificate", "degree", NA,  # undergrad cert; also offered as BA concentration
  # NATV
  "AS", "NATV", "NATV", "BA", "Undergraduate", "degree", NA,
  "AS", "NATV", "NATV", "MA", "Graduate", "degree", NA,
  "AS", "NATV", "NATV", "PHD", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "AS", "NATV", "XFNA", "BA", "Undergraduate", "variant", "NATV",
  "AS", "NATV", "XNAT", "BA", "Undergraduate", "variant", "NATV",
  # pre-majors:
  "AS", "NATV", "FNAT", "BA", "Undergraduate", "pre_major", "NATV",
  # PADM
  "AS", "PADM", "PADM", "MPA", "Graduate", "degree", NA,
  "AS", "PADM", "PUPO", "MPP", "Graduate", "degree", NA,
  "AS", "PADM", "PUPO", "GCERT", "Certificate", "degree", NA,
  # PHIL
  "AS", "PHIL", "PHIL", "BA", "Undergraduate", "degree", NA,
  "AS", "PHIL", "PHIL", "MA", "Graduate", "degree", NA,
  "AS", "PHIL", "PHIL", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "PHIL", "FPHI", "BA", "Undergraduate", "pre_major", "PHIL",
  # PHYS
  "AS", "PHYS", "PAP", "BA", "Undergraduate", "degree", NA,
  "AS", "PHYS", "ASPH", "BS", "Undergraduate", "degree", NA,
  "AS", "PHYS", "PHYC", "BS", "Undergraduate", "degree", NA,
  "AS", "PHYS", "OPEN", "MS", "Graduate", "degree", NA,
  "AS", "PHYS", "PHYC", "MS", "Graduate", "degree", NA,
  "AS", "PHYS", "OPEN", "PHD", "Graduate", "degree", NA,
  "AS", "PHYS", "PHYC", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "PHYS", "FPAP", "BA", "Undergraduate", "pre_major", "PAP",
  "AS", "PHYS", "FASP", "BS", "Undergraduate", "pre_major", "ASPH",
  "AS", "PHYS", "FPHY", "BS", "Undergraduate", "pre_major", "PHYC",
  # POLS
  "AS", "POLS", "POLS", "BA", "Undergraduate", "degree", NA,
  "AS", "POLS", "POLS", "MA", "Graduate", "degree", NA,
  "AS", "POLS", "POLS", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "POLS", "FPOL", "BA", "Undergraduate", "pre_major", "POLS",
  # PSYC
  "AS", "PSYC", "PSY", "BA", "Undergraduate", "degree", NA,
  "AS", "PSYC", "PSY", "BS", "Undergraduate", "degree", NA,
  "AS", "PSYC", "PSY", "PHD", "Graduate", "degree", NA,
  "AS", "PSYC", "ABA", "GCERT", "Certificate", "degree", NA,
  "AS", "PSYC", "ASD", "GCERT", "Certificate", "degree", NA,
  # variants (X-prefix / extended campus):
  "AS", "PSYC", "XFPY", "BA", "Undergraduate", "variant", "PSY",
  "AS", "PSYC", "XPSY", "BA", "Undergraduate", "variant", "PSY",
  # pre-majors:
  "AS", "PSYC", "FPSY", "BA", "Undergraduate", "pre_major", "PSY",
  "AS", "PSYC", "FPSY", "BS", "Undergraduate", "pre_major", "PSY",
  # RELG
  "AS", "RELG", "RLST", "BA", "Undergraduate", "degree", NA,
  # pre-majors:
  "AS", "RELG", "FRLS", "BA", "Undergraduate", "pre_major", "RLST",
  # SHS
  "AS", "SHS", "SHS", "BA", "Undergraduate", "degree", NA,
  "AS", "SHS", "SPLP", "MS", "Graduate", "degree", NA,
  "AS", "SHS", "CSD", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "SHS", "FSHS", "BA", "Undergraduate", "pre_major", "SHS",
  # SOCI
  "AS", "SOCI", "CRIM", "BA", "Undergraduate", "degree", NA,
  "AS", "SOCI", "SOC", "BA", "Undergraduate", "degree", NA,
  "AS", "SOCI", "SOC", "PHD", "Graduate", "degree", NA,
  "AS", "SOCI", "RSJ", "GCERT", "Certificate", "degree", NA,
  # pre-majors:
  "AS", "SOCI", "FCRI", "BA", "Undergraduate", "pre_major", "CRIM",
  "AS", "SOCI", "FSOC", "BA", "Undergraduate", "pre_major", "SOC",
  # SPAN
  "AS", "SPAN", "PORT", "BA", "Undergraduate", "degree", NA,
  "AS", "SPAN", "SPAN", "BA", "Undergraduate", "degree", NA,
  "AS", "SPAN", "PORT", "MA", "Graduate", "degree", NA,
  "AS", "SPAN", "SPAN", "MA", "Graduate", "degree", NA,
  "AS", "SPAN", "SPPR", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "AS", "SPAN", "FSPA", "BA", "Undergraduate", "pre_major", "SPAN",
  "AS", "SPAN", "FPOR", "BA", "Undergraduate", "pre_major", "PORT",
  # UNDC
  "AS", "UNDC", "UNDC", "BA", "Undergraduate", "degree", NA,
  # WGSS
  "AS", "WGSS", "WGSS", "BA", "Undergraduate", "degree", NA,
  "AS", "WGSS", "WMST", "BA", "Undergraduate", "degree", NA,
  # pre-majors:
  "AS", "WGSS", "FWGS", "BA", "Undergraduate", "pre_major", "WGSS",
  "AS", "WGSS", "FWMS", "BA", "Undergraduate", "pre_major", "WMST",
  # ── College of Educ & Human Sci (EH) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # ATED
  "EH", "ATED", "AT", "BS", "Undergraduate", "degree", NA,
  "EH", "ATED", "AT", "MS", "Graduate", "degree", NA,
  # pre-majors:
  "EH", "ATED", "FAT", "BS", "Undergraduate", "pre_major", "ATED",
  # COUN
  "EH", "COUN", "COUN", "MA", "Graduate", "degree", NA,
  "EH", "COUN", "COED", "PHD", "Graduate", "degree", NA,
  "EH", "COUN", "AGC", "GCERT", "Certificate", "degree", NA,
  # EDPY
  "EH", "EDPY", "EDPY", "MA", "Graduate", "degree", NA,
  "EH", "EDPY", "EDPY", "PHD", "Graduate", "degree", NA,
  "EH", "EDPY", "EDAG", "GCERT", "Certificate", "degree", NA,
  # EDUC
  "EH", "EDUC", "SED", "BAED", "Undergraduate", "degree", NA,
  "EH", "EDUC", "SED", "BAED", "Undergraduate", "degree", NA,
  "EH", "EDUC", "ELED", "BSED", "Undergraduate", "degree", NA,
  "EH", "EDUC", "SED", "BSED", "Undergraduate", "degree", NA,
  "EH", "EDUC", "ELED", "BSED", "Undergraduate", "degree", NA,
  "EH", "EDUC", "SED", "BSED", "Undergraduate", "degree", NA,
  "EH", "EDUC", "MCTC", "EDD", "Graduate", "degree", NA,
  "EH", "EDUC", "TLTE", "EDD", "Graduate", "degree", NA,
  "EH", "EDUC", "ELED", "MA", "Graduate", "degree", NA,
  "EH", "EDUC", "SED", "MA", "Graduate", "degree", NA,
  "EH", "EDUC", "EDUC", "MA", "Graduate", "degree", NA,
  "EH", "EDUC", "MCTC", "PHD", "Graduate", "degree", NA,
  "EH", "EDUC", "TLTE", "PHD", "Graduate", "degree", NA,
  "EH", "EDUC", "ELED", "GCERT", "Certificate", "degree", NA,
  "EH", "EDUC", "SED", "GCERT", "Certificate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EH", "EDUC", "XELE", "MA", "Graduate", "variant", "EDUC",
  "EH", "EDUC", "XSED", "MA", "Graduate", "variant", "SED",
  "EH", "EDUC", "XEDU", "MA", "Graduate", "variant", "EDUC",
  # pre-majors:
  "EH", "EDUC", "FSEC", "BAED", "Undergraduate", "pre_major", "SED",
  "EH", "EDUC", "FSEC", "BAED", "Undergraduate", "pre_major", "SED",
  "EH", "EDUC", "FELE", "BSED", "Undergraduate", "pre_major", "EDUC",
  "EH", "EDUC", "FSEC", "BSED", "Undergraduate", "pre_major", "SED",
  "EH", "EDUC", "FELE", "BSED", "Undergraduate", "pre_major", "EDUC",
  "EH", "EDUC", "FSEC", "BSED", "Undergraduate", "pre_major", "SED",
  # FCS
  "EH", "FCS", "HDFR", "BS", "Undergraduate", "degree", NA,
  # pre-majors:
  "EH", "FCS", "FCST", "BA", "Undergraduate", "pre_major", "FCS",
  "EH", "FCS", "FFCS", "BA", "Undergraduate", "pre_major", "FCS",
  "EH", "FCS", "FCST", "BS", "Undergraduate", "pre_major", "FCS",
  "EH", "FCS", "FFCS", "BS", "Undergraduate", "pre_major", "FCS",
  "EH", "FCS", "FCST", "BS", "Undergraduate", "pre_major", "FCS",
  "EH", "FCS", "FFCS", "BS", "Undergraduate", "pre_major", "FCS",
  "EH", "FCS", "FCS", "BSCS", "Undergraduate", "pre_major", "CS",
  "EH", "FCS", "FCST", "MA", "Graduate", "pre_major", "FCS",
  "EH", "FCS", "FCST", "PHD", "Graduate", "pre_major", "FCS",
  # HED
  "EH", "HED", "CHED", "BS", "Undergraduate", "degree", NA,
  "EH", "HED", "CHED", "BS", "Undergraduate", "degree", NA,
  "EH", "HED", "HED", "MS", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EH", "HED", "XFCH", "BS", "Undergraduate", "variant", "HED",
  "EH", "HED", "XCHE", "BS", "Undergraduate", "variant", "HED",
  # pre-majors:
  "EH", "HED", "FCHE", "BS", "Undergraduate", "pre_major", "HED",
  "EH", "HED", "FCHE", "BS", "Undergraduate", "pre_major", "HED",
  "EH", "HED", "FCHE", "BS", "Undergraduate", "pre_major", "HED",
  "EH", "HED", "FHED", "BS", "Undergraduate", "pre_major", "HED",
  # LEAD
  "EH", "LEAD", "LEAD", "EDD", "Graduate", "degree", NA,
  "EH", "LEAD", "LEAD", "EDD", "Graduate", "degree", NA,
  "EH", "LEAD", "LEAD", "MA", "Graduate", "degree", NA,
  "EH", "LEAD", "LEAD", "EDSPC", "Certificate", "degree", NA,
  # LLSS
  "EH", "LLSS", "LLSS", "MA", "Graduate", "degree", NA,
  "EH", "LLSS", "LLSS", "PHD", "Graduate", "degree", NA,
  "EH", "LLSS", "TESL", "GCERT", "Certificate", "degree", NA,
  "EH", "LLSS", "TESL", "GCERT", "Certificate", "degree", NA,
  # NUTR
  "EH", "NUTR", "NDIT", "BS", "Undergraduate", "degree", NA,
  "EH", "NUTR", "NDIT", "BS", "Undergraduate", "degree", NA,
  "EH", "NUTR", "NUTR", "MS", "Graduate", "degree", NA,
  # pre-majors:
  "EH", "NUTR", "FNDI", "BS", "Undergraduate", "pre_major", "NDIT",
  "EH", "NUTR", "FNDI", "BS", "Undergraduate", "pre_major", "NDIT",
  # PHED
  "EH", "PHED", "ES", "BS", "Undergraduate", "degree", NA,
  "EH", "PHED", "ES", "BS", "Undergraduate", "degree", NA,
  "EH", "PHED", "PE", "BSED", "Undergraduate", "degree", NA,
  "EH", "PHED", "PE", "BSED", "Undergraduate", "degree", NA,
  "EH", "PHED", "PE", "MS", "Graduate", "degree", NA,
  "EH", "PHED", "PESE", "PHD", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EH", "PHED", "XPE", "MS", "Graduate", "variant", "PHED",
  # pre-majors:
  "EH", "PHED", "FES", "BS", "Undergraduate", "pre_major", "PHED",
  "EH", "PHED", "FES", "BS", "Undergraduate", "pre_major", "PHED",
  "EH", "PHED", "FPE", "BSED", "Undergraduate", "pre_major", "PHED",
  "EH", "PHED", "FPE", "BSED", "Undergraduate", "pre_major", "PHED",
  # SPED
  "EH", "SPED", "SPCD", "BSED", "Undergraduate", "degree", NA,
  "EH", "SPED", "SPCD", "BSED", "Undergraduate", "degree", NA,
  "EH", "SPED", "SPCD", "MA", "Graduate", "degree", NA,
  "EH", "SPED", "SPCD", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "EH", "SPED", "FSPC", "BSED", "Undergraduate", "pre_major", "SPCD",
  "EH", "SPED", "FSPC", "BSED", "Undergraduate", "pre_major", "SPCD",
  # ── School of Engineering (EN) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # BME
  "EN", "BME", "BME", "MS", "Graduate", "degree", NA,
  "EN", "BME", "BME", "MS", "Graduate", "degree", NA,
  # CBE
  "EN", "CBE", "CHE", "BSCHE", "Undergraduate", "degree", NA,
  "EN", "CBE", "CHE", "MS", "Graduate", "degree", NA,
  # pre-majors:
  "EN", "CBE", "FCH", "BSCHE", "Undergraduate", "pre_major", "CBE",
  # CE
  "EN", "CE", "CE", "BSCE", "Undergraduate", "degree", NA,
  "EN", "CE", "CONM", "BSCM", "Undergraduate", "degree", NA,
  "EN", "CE", "CE", "MENG", "Graduate", "degree", NA,
  "EN", "CE", "CE", "MS", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EN", "CE", "XCMG", "MCM", "Graduate", "variant", "CE",
  "EN", "CE", "XCE", "MENG", "Graduate", "variant", "CE",
  # pre-majors:
  "EN", "CE", "FCE", "BSCE", "Undergraduate", "pre_major", "CE",
  "EN", "CE", "FCON", "BSCM", "Undergraduate", "pre_major", "CE",
  # CPE
  "EN", "CPE", "CPE", "BSCPE", "Undergraduate", "degree", NA,
  "EN", "CPE", "CPE", "MS", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EN", "CPE", "XCPE", "MS", "Graduate", "variant", "CPE",
  # pre-majors:
  "EN", "CPE", "FCP", "BSCPE", "Undergraduate", "pre_major", "CPE",
  # CS
  "EN", "CS", "CS", "BSCS", "Undergraduate", "degree", NA,
  "EN", "CS", "CS", "MS", "Graduate", "degree", NA,
  "EN", "CS", "CS", "PHD", "Graduate", "degree", NA,
  "EN", "CS", "CSCE", "PDCERT", "Certificate", "degree", NA,
  # ECE
  "EN", "ECE", "EE", "BSEE", "Undergraduate", "degree", NA,
  "EN", "ECE", "EE", "MS", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EN", "ECE", "XEE", "MS", "Graduate", "variant", "ECE",
  # pre-majors:
  "EN", "ECE", "FEE", "BSEE", "Undergraduate", "pre_major", "ECE",
  # ENG
  "EN", "ENG", "ENG", "PHD", "Graduate", "degree", NA,
  # ME
  "EN", "ME", "ME", "BSME", "Undergraduate", "degree", NA,
  "EN", "ME", "MFGE", "MEME", "Graduate", "degree", NA,
  "EN", "ME", "ME", "MS", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "EN", "ME", "XME", "MS", "Graduate", "variant", "ME",
  # pre-majors:
  "EN", "ME", "FME", "BSME", "Undergraduate", "pre_major", "ME",
  # NE
  "EN", "NE", "NE", "BSNE", "Undergraduate", "degree", NA,
  "EN", "NE", "NE", "MS", "Graduate", "degree", NA,
  # pre-majors:
  "EN", "NE", "FNE", "BSNE", "Undergraduate", "pre_major", "NE",
  # NSME
  "EN", "NSME", "NSME", "MS", "Graduate", "degree", NA,
  "EN", "NSME", "NSMS", "MS", "Graduate", "degree", NA,
  "EN", "NSME", "NSME", "PHD", "Graduate", "degree", NA,
  "EN", "NSME", "NSMS", "PHD", "Graduate", "degree", NA,
  # ── College of Fine Arts (FA) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # ARTH
  "FA", "ARTH", "ARTH", "BA", "Undergraduate", "degree", NA,
  "FA", "ARTH", "ARTH", "MA", "Graduate", "degree", NA,
  "FA", "ARTH", "ARTH", "PHD", "Graduate", "degree", NA,
  # pre-majors:
  "FA", "ARTH", "FAHI", "BA", "Undergraduate", "pre_major", "ARTH",
  # ARTS
  "FA", "ARTS", "ARTE", "BA", "Undergraduate", "degree", NA,
  "FA", "ARTS", "ARTS", "BA", "Undergraduate", "degree", NA,
  "FA", "ARTS", "ARTS", "BFA", "Undergraduate", "degree", NA,
  "FA", "ARTS", "ARTE", "MA", "Graduate", "degree", NA,
  "FA", "ARTS", "ARTS", "MFA", "Graduate", "degree", NA,
  # pre-majors:
  "FA", "ARTS", "FRTE", "BA", "Undergraduate", "pre_major", "ARTE",
  "FA", "ARTS", "FAST", "BA", "Undergraduate", "pre_major", "ARTS",
  "FA", "ARTS", "FAST", "BFA", "Undergraduate", "pre_major", "ARTS",
  # DANC
  "FA", "DANC", "DANC", "BA", "Undergraduate", "degree", NA,
  "FA", "DANC", "DANC", "MFA", "Graduate", "degree", NA,
  # pre-majors:
  "FA", "DANC", "FDAN", "BA", "Undergraduate", "pre_major", "DANC",
  # FDMA
  "FA", "FDMA", "FDMA", "BA", "Undergraduate", "degree", NA,
  "FA", "FDMA", "IDAR", "BA", "Undergraduate", "degree", NA,
  "FA", "FDMA", "MA", "BA", "Undergraduate", "degree", NA,
  "FA", "FDMA", "IFDM", "BFA", "Undergraduate", "degree", NA,
  "FA", "FDMA", "FDMA", "BFA", "Undergraduate", "degree", NA,
  # pre-majors:
  "FA", "FDMA", "FFDA", "BA", "Undergraduate", "pre_major", "FDMA",
  "FA", "FDMA", "FIDA", "BA", "Undergraduate", "pre_major", "FDMA",
  "FA", "FDMA", "FMAR", "BA", "Undergraduate", "pre_major", "FDMA",
  "FA", "FDMA", "FFDA", "BFA", "Undergraduate", "pre_major", "FDMA",
  "FA", "FDMA", "FFDM", "BFA", "Undergraduate", "pre_major", "FDMA",
  # MUS
  "FA", "MUS", "MUS", "BA", "Undergraduate", "degree", NA,
  "FA", "MUS", "MUS", "BM", "Undergraduate", "degree", NA,
  "FA", "MUS", "MUSE", "BME", "Undergraduate", "degree", NA,
  "FA", "MUS", "MUS", "MMU", "Graduate", "degree", NA,
  "FA", "MUS", "MUSP", "GCERT", "Certificate", "degree", NA,
  # variants (X-prefix / extended campus):
  "FA", "MUS", "XMUS", "MMU", "Graduate", "variant", "MUS",
  # pre-majors:
  "FA", "MUS", "FMUS", "BA", "Undergraduate", "pre_major", "MUS",
  "FA", "MUS", "FMUS", "BM", "Undergraduate", "pre_major", "MUS",
  "FA", "MUS", "FMUE", "BME", "Undergraduate", "pre_major", "MUS",
  # THEA
  "FA", "THEA", "THEA", "BA", "Undergraduate", "degree", NA,
  "FA", "THEA", "DTP", "BFA", "Undergraduate", "degree", NA,
  "FA", "THEA", "THTD", "MA", "Graduate", "degree", NA,
  "FA", "THEA", "DRAM", "MFA", "Graduate", "degree", NA,
  # pre-majors:
  "FA", "THEA", "FTHR", "BA", "Undergraduate", "pre_major", "THEA",
  "FA", "THEA", "FDTP", "BFA", "Undergraduate", "pre_major", "THEA",
  # ── Graduate Programs (GP) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # FCS
  "GP", "FCS", "FS", "MA", "Graduate", "degree", NA,
  "GP", "FCS", "FS", "PHD", "Graduate", "degree", NA,
  # GLNS
  "GP", "GLNS", "GLNS", "PMS", "Graduate", "degree", NA,
  # HED
  "GP", "HED", "HLAD", "MHA", "Graduate", "degree", NA,
  # OCTH
  "GP", "OCTH", "OCTH", "MOT", "Graduate", "degree", NA,
  "GP", "OCTH", "OCTH", "MOT", "Graduate", "degree", NA,
  "GP", "OCTH", "OCTH", "OTD", "Professional", "degree", NA,
  # ── Honors College (HC) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # HNRS
  "HC", "HNRS", "HILA", "BA", "Undergraduate", "degree", NA,
  "HC", "HNRS", "IDLA", "BA", "Undergraduate", "degree", NA,
  # pre-majors:
  "HC", "HNRS", "FHIL", "BA", "Undergraduate", "pre_major", "HNRS",
  # ── Univ Libraries & Learn Science (LL) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # IADL
  "LL", "IADL", "ITT", "BS", "Undergraduate", "degree", NA,
  "LL", "IADL", "TTR", "BS", "Undergraduate", "degree", NA,
  "LL", "IADL", "OLIT", "PHD", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "LL", "IADL", "XITT", "BS", "Undergraduate", "variant", "IADL",
  "LL", "IADL", "XFIT", "BS", "Undergraduate", "variant", "IADL",
  # pre-majors:
  "LL", "IADL", "FITT", "BS", "Undergraduate", "pre_major", "IADL",
  # OILS
  "LL", "OILS", "OILS", "MA", "Graduate", "degree", NA,
  "LL", "OILS", "OILS", "PHD", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "LL", "OILS", "XOIL", "MA", "Graduate", "variant", "OILS",
  # ── School of Law (LW) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # LAW
  "LW", "LAW", "STLW", "MSL", "Graduate", "degree", NA,
  "LW", "LAW", "LAW", "JD", "Professional", "degree", NA,
  # ── School of Medicine (ME) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # ANES
  "ME", "ANES", "ANES", "MS", "Graduate", "degree", NA,
  # BIOC
  "ME", "BIOC", "BIOC", "BA", "Undergraduate", "degree", NA,
  "ME", "BIOC", "BIOC", "BS", "Undergraduate", "degree", NA,
  # pre-majors:
  "ME", "BIOC", "FBIC", "BA", "Undergraduate", "pre_major", "BIOC",
  "ME", "BIOC", "FBIC", "BS", "Undergraduate", "pre_major", "BIOC",
  # BIOM
  "ME", "BIOM", "BIOM", "MS", "Graduate", "degree", NA,
  "ME", "BIOM", "BIOM", "PHD", "Graduate", "degree", NA,
  "ME", "BIOM", "MED", "DM", "Professional", "degree", NA,
  # DEHY
  "ME", "DEHY", "DEHY", "BSDH", "Undergraduate", "degree", NA,
  "ME", "DEHY", "DEHY", "BSDH", "Undergraduate", "degree", NA,
  "ME", "DEHY", "DEHY", "MS", "Graduate", "degree", NA,
  # variants (X-prefix / extended campus):
  "ME", "DEHY", "XDEH", "BSDH", "Undergraduate", "variant", "DEHY",
  "ME", "DEHY", "XDEH", "BSDH", "Undergraduate", "variant", "DEHY",
  "ME", "DEHY", "XDEH", "MS", "Graduate", "variant", "DEHY",
  # EMS
  "ME", "EMS", "EMS", "BS", "Undergraduate", "degree", NA,
  "ME", "EMS", "EMS", "BS", "Undergraduate", "degree", NA,
  # MEDL
  "ME", "MEDL", "MEDL", "BSML", "Undergraduate", "degree", NA,
  "ME", "MEDL", "MEDL", "BSML", "Undergraduate", "degree", NA,
  # PAST
  "ME", "PAST", "PAST", "MS", "Graduate", "degree", NA,
  "ME", "PAST", "PAST", "MS", "Graduate", "degree", NA,
  # PT
  "ME", "PT", "PT", "DPT", "Professional", "degree", NA,
  "ME", "PT", "PT", "DPT", "Professional", "degree", NA,
  # RADS
  "ME", "RADS", "RADS", "BS", "Undergraduate", "degree", NA,
  "ME", "RADS", "RADS", "BS", "Undergraduate", "degree", NA,
  "ME", "RADS", "AMRI", "CERT", "Certificate", "degree", NA,
  "ME", "RADS", "SCTO", "CERT", "Certificate", "degree", NA,
  "ME", "RADS", "SMRI", "CERT", "Certificate", "degree", NA,
  "ME", "RADS", "MRI", "CERT", "Certificate", "degree", NA,
  "ME", "RADS", "ACTI", "CERT", "Certificate", "degree", NA,
  "ME", "RADS", "CTOM", "CERT", "Certificate", "degree", NA,
  # ── Anderson Schools of Management (MG) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # ACCT
  "MG", "ACCT", "ACCT", "MACCT", "Graduate", "degree", NA,
  # MGMT
  "MG", "MGMT", "BADM", "BBA", "Undergraduate", "degree", NA,
  "MG", "MGMT", "BADM", "MBA", "Graduate", "degree", NA,
  "MG", "MGMT", "EMBA", "MBA", "Graduate", "degree", NA,
  "MG", "MGMT", "CBA", "MS", "Graduate", "degree", NA,
  "MG", "MGMT", "ISA", "MS", "Graduate", "degree", NA,
  "MG", "MGMT", "PJMG", "MS", "Graduate", "degree", NA,
  "MG", "MGMT", "MGMT", "GCERT", "Certificate", "degree", NA,
  "MG", "MGMT", "BADM", "MGTCP", "Certificate", "degree", NA,
  # variants (X-prefix / extended campus):
  "MG", "MGMT", "XBAD", "BBA", "Undergraduate", "variant", "BADM",
  "MG", "MGMT", "XFBA", "BBA", "Undergraduate", "variant", "BADM",
  "MG", "MGMT", "XBAM", "MBA", "Graduate", "variant", "BADM",
  "MG", "MGMT", "XCBA", "MS", "Graduate", "variant", "CBA",
  "MG", "MGMT", "XPJM", "MS", "Graduate", "variant", "BADP",
  "MG", "MGMT", "XMGM", "GCERT", "Certificate", "variant", "MGMT",
  # pre-majors:
  "MG", "MGMT", "FBAD", "BBA", "Undergraduate", "pre_major", "BADM",
  # ── College of Nursing (NU) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # NURS
  "NU", "NURS", "NUAP", "BSN", "Undergraduate", "degree", NA,
  "NU", "NURS", "NURS", "BSN", "Undergraduate", "degree", NA,
  "NU", "NURS", "NURS", "BSN", "Undergraduate", "degree", NA,
  "NU", "NURS", "NURS", "MSN", "Graduate", "degree", NA,
  "NU", "NURS", "NUR", "PHD", "Graduate", "degree", NA,
  "NU", "NURS", "NURP", "DNP", "Professional", "degree", NA,
  "NU", "NURS", "NURS", "NURCP", "Certificate", "degree", NA,
  # pre-majors:
  "NU", "NURS", "FNAP", "BSN", "Undergraduate", "pre_major", "NURS",
  "NU", "NURS", "FNRS", "BSN", "Undergraduate", "pre_major", "NURS",
  # ── College of Pharmacy (PH) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # PHRM
  "PH", "PHRM", "PHRS", "BS", "Undergraduate", "degree", NA,
  "PH", "PHRM", "PHRS", "MS", "Graduate", "degree", NA,
  "PH", "PHRM", "PHRS", "PHD", "Graduate", "degree", NA,
  "PH", "PHRM", "PHRD", "PHARMD", "Professional", "degree", NA,
  # pre-majors:
  "PH", "PHRM", "PHRS", "BS", "Undergraduate", "pre_major", NA,
  "PH", "PHRM", "FPHS", "BS", "Undergraduate", "pre_major", "PHRM",
  "PH", "PHRM", "UC", "FPMD", "Professional", "pre_major", NA,
  "PH", "PHRM", "UC", "PHARMD", "Professional", "pre_major", NA,
  #
  # ⚠️  PHRD dual-use anomaly (confirmed in data, 201880–202580):
  # Banner used PHRD for BOTH actual PharmD students (student_level = "PH")
  # AND undergraduate pre-pharmacy students (student_level = "UG") completing
  # prerequisites before admission. The UG population (~800–900 enrollments/term)
  # dwarfs the real PharmD cohort (~40–55/term) and would otherwise appear as
  # doctoral students taking lower-division intro courses — which is impossible.
  # UNM introduced FPHS as the proper pre-pharmacy code starting in 202580;
  # before that, PHRD was the only code used for both groups.
  # Fix: transform-to-cedar.R overrides is_pre_major = TRUE for PHRD where
  # student_level is UG or NG. See is_pre_major derivation in cedar_programs build.
  # ── College of Population Health (PO) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # HSCI  (NOTE: program_code "PH" = Public Health MPH; conflicts with AD branch campus subject "PH" — correctly mapped here)
  "PO", "HSCI", "PH", "MPH", "Graduate", "degree", NA,
  "PO", "HSCI", "POHE", "BS", "Undergraduate", "degree", NA,
  "PO", "HSCI", "HES", "PHD", "Graduate", "degree", NA,
  "PO", "HSCI", "MCH", "GCERT", "Certificate", "degree", NA,
  # pre-majors:
  "PO", "HSCI", "FPOH", "BS", "Undergraduate", "pre_major", "POHE",
  "PO", "HSCI", "PHSC", "GCERT", "Certificate", "pre_major", NA,
  # ── University College (UC) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # LAIS
  "UC", "LAIS", "LIBA", "BLA", "Undergraduate", "degree", NA,
  # UNDC
  "UC", "UNDC", "UNDC", "BA", "Undergraduate", "degree", NA,
  # WR
  "UC", "WR", "WR", "MWR", "Graduate", "degree", NA,
  # ── Associate Degree / Branch Campuses (AD) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  # Branch campus associate degree programs (Gallup, Los Alamos, Taos, Valencia).
  # Program codes are the middle segment of the Banner program code (e.g., AA-AAHS-GA → AAHS).
  # college_code is always "AD" regardless of dept_code origin.
  # APTE
  "AD", "APTE", "APTE", "AAS", "Associate", "degree", NA,
  # ARTS / FA
  "AD", "ARTS", "ARTS", "AA", "Associate", "degree", NA,
  "AD", "ARTS", "FA", "AFA", "Associate", "degree", NA,
  # ASPE
  "AD", "ASPE", "ASPE", "AS", "Associate", "degree", NA,
  # AUTT
  "AD", "AUTT", "AUTT", "AAS", "Associate", "degree", NA,
  # BSTC
  "AD", "BSTC", "ACCT", "AAS", "Associate", "degree", NA,
  # BUSA
  "AD", "BUSA", "BADM", "AA", "Associate", "degree", NA,
  "AD", "BUSA", "BUAD", "AA", "Associate", "degree", NA,
  "AD", "BUSA", "BUSN", "AAS", "Associate", "degree", NA,
  "AD", "BUSA", "PBA", "AA", "Associate", "degree", NA,
  # CJUS
  "AD", "CJUS", "CRIM", "AA", "Associate", "degree", NA,
  "AD", "CJUS", "CRJS", "AA", "Associate", "degree", NA,
  # CNST
  "AD", "CNST", "CNST", "AAS", "Associate", "degree", NA,
  # CS (branch campus; college_code AD distinguishes from EN/CS)
  "AD", "CS", "CS", "AS", "Associate", "degree", NA,
  # DMA
  "AD", "DMA", "DMA", "AA", "Associate", "degree", NA,
  "AD", "DMA", "DMA", "AAS", "Associate", "degree", NA,
  # DRFT
  "AD", "DRFT", "ARDT", "AAS", "Associate", "degree", NA,
  # ECED
  "AD", "ECED", "ECED", "AA", "Associate", "degree", NA,
  "AD", "ECED", "ECME", "AA", "Associate", "degree", NA,
  # EDUC
  "AD", "EDUC", "EDUC", "AA", "Associate", "degree", NA,
  "AD", "EDUC", "EDUC", "AS", "Associate", "degree", NA,
  "AD", "EDUC", "ELTE", "AS", "Associate", "degree", NA,
  "AD", "EDUC", "PPED", "AA", "Associate", "degree", NA,
  "AD", "EDUC", "SCTE", "AA", "Associate", "degree", NA,
  # ENGL (branch campus; college_code AD distinguishes from AS/ENGL)
  "AD", "ENGL", "ENGL", "AA", "Associate", "degree", NA,
  # EMS
  "AD", "EMS", "EMS", "AS", "Associate", "degree", NA,
  # ENPD
  "AD", "ENPD", "ENPD", "AA", "Associate", "degree", NA,
  # ENVS
  "AD", "ENVS", "ENVS", "AS", "Associate", "degree", NA,
  # FDMA
  "AD", "FDMA", "FDMA", "AA", "Associate", "degree", NA,
  # FISC
  "AD", "FISC", "FISC", "AAS", "Associate", "degree", NA,
  # GAME
  "AD", "GAME", "GDS", "AAS", "Associate", "degree", NA,
  # GNST
  "AD", "GNST", "GNST", "AAS", "Associate", "degree", NA,
  "AD", "GNST", "GSCI", "AS", "Associate", "degree", NA,
  "AD", "GNST", "INGV", "AIS", "Associate", "degree", NA,
  "AD", "GNST", "PRSC", "AS", "Associate", "degree", NA,
  "AD", "GNST", "SCI", "AS", "Associate", "degree", NA,
  # HCHS
  "AD", "HCHS", "APHS", "AS", "Associate", "degree", NA,
  # HCHT
  "AD", "HCHT", "HIT", "AS", "Associate", "degree", NA,
  # HLED
  "AD", "HLED", "HED", "AS", "Associate", "degree", NA,
  # HMSV
  "AD", "HMSV", "AAHS", "AA", "Associate", "degree", NA,
  # IT
  "AD", "IT", "INCS", "AAS", "Associate", "degree", NA,
  "AD", "IT", "IT", "AAS", "Associate", "degree", NA,
  # LART
  "AD", "LART", "LART", "AA", "Associate", "degree", NA,
  # MATH (branch campus; college_code AD distinguishes from AS/MATH)
  "AD", "MATH", "MATH", "AS", "Associate", "degree", NA,
  # MLT
  "AD", "MLT", "MDLA", "AS", "Associate", "degree", NA,
  # NURS (branch campus; college_code AD distinguishes from NU/NURS)
  "AD", "NURS", "AASN", "AAS", "Associate", "degree", NA,
  "AD", "NURS", "ASNU", "AS", "Associate", "degree", NA,
  "AD", "NURS", "NURS", "AS", "Associate", "degree", NA,
  # WELD
  "AD", "WELD", "WELD", "AAS", "Associate", "degree", NA
)

# Strip dead metadata columns and deduplicate.
# Downstream code only needs college_code, dept_code, and major_code.
major_dept_map <- dplyr::distinct(dplyr::select(major_dept_map, college_code, dept_code, major_code))
