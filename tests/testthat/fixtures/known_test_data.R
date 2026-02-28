# Hand-crafted test fixtures with KNOWN expected values
# This file is version-controlled and should NEVER be auto-generated
#
# IMPORTANT: When writing tests, use the "Expected values" comments below
# to know exactly what results to expect from filtering operations.
#
# Usage in tests:
#   source("fixtures/known_test_data.R")
#   # Then use known_sections, known_students, etc.

library(tibble)

# =============================================================================
# KNOWN SECTIONS (course offerings)
# =============================================================================
# 19 sections total across 3 departments and 5 terms (includes previous year for seatfinder)
#
# Terms included:
#   202410 (Spring 2024): 5 sections - previous year comparison for 202510
#   202480 (Fall 2024): 3 sections - previous year comparison for 202580
#   202510 (Spring 2025): 5 sections
#   202560 (Summer 2025): 3 sections
#   202580 (Fall 2025): 4 sections
#
# Expected values for filtering:
#   - By department (2025 terms only):
#       HIST: 4 sections
#       MATH: 5 sections
#       ANTH: 3 sections
#
#   - By term:
#       202410 (Spring 2024): 5 sections
#       202480 (Fall 2024): 3 sections
#       202510 (Spring 2025): 5 sections
#       202560 (Summer 2025): 3 sections
#       202580 (Fall 2025): 4 sections
#
#   - By campus (all terms):
#       Main: 11 sections
#       Online: 6 sections
#       Valencia: 2 sections
#
#   - By status:
#       A (Active): 18 sections
#       C (Cancelled): 1 section
#
# Expected values for seatfinder (year-over-year comparison):
#   - Spring comparison (202410 vs 202510):
#       Common courses: HIST 1110, HIST 1120, MATH 1215, ANTH 1110 (4 courses)
#       Discontinued (in 202410 only): PHYS 1010 (1 course)
#       New (in 202510 only): MATH 1220 (1 course)
#       Enrollment changes (202510 vs 202410):
#         HIST 1110: 25 vs 22 = +3
#         HIST 1120: 30 vs 28 = +2
#         MATH 1215: 35 vs 30 = +5
#         ANTH 1110: 40 vs 38 = +2
#
#   - Fall comparison (202480 vs 202580):
#       Common courses: HIST 3010, MATH 3140 (2 courses)
#       Discontinued (in 202480 only): CHEM 1010 (1 course)
#       New (in 202580 only): MATH 4310, ANTH 2050 (2 courses)

known_sections <- tibble(
  # New columns added in order that matches cedar_sections schema after transform-to-cedar.R:
  #   course_number  — string course number extracted from subject_course
  #   crosslist_code — raw XL code from source data ("" for non-crosslisted)
  #   crosslist_group — NA for non-crosslisted, code string for crosslisted
  #   crosslist_primary — TRUE for home/primary section of a crosslist group
  #   total_enrl — total enrollment across all XL partners (= enrolled for non-XL)
  # All 20 base sections are non-crosslisted so defaults are straightforward.
  # See known_sections_xl below for explicit crosslist/split test scenarios.

  section_id = c(
    # 202410 (Spring 2024) - 5 sections
    "SEC101", "SEC102", "SEC103", "SEC104", "SEC105",
    # 202480 (Fall 2024) - 3 sections
    "SEC106", "SEC107", "SEC108",
    # 202510 (Spring 2025) - 5 sections
    "SEC001", "SEC002", "SEC005", "SEC006", "SEC010",
    # 202560 (Summer 2025) - 3 sections
    "SEC003", "SEC007", "SEC011",
    # 202580 (Fall 2025) - 4 sections
    "SEC004", "SEC008", "SEC009", "SEC012"
  ),
  crn = c(
    # 202410
    20001, 20002, 20003, 20004, 20005,
    # 202480
    20006, 20007, 20008,
    # 202510
    10001, 10002, 10005, 10006, 10010,
    # 202560
    10003, 10007, 10011,
    # 202580
    10004, 10008, 10009, 10012
  ),
  term = c(
    # 202410
    rep(202410, 5),
    # 202480
    rep(202480, 3),
    # 202510
    rep(202510, 5),
    # 202560
    rep(202560, 3),
    # 202580
    rep(202580, 4)
  ),
  department = c(
    # 202410
    "HIST", "HIST", "MATH", "PHYS", "ANTH",
    # 202480
    "HIST", "MATH", "CHEM",
    # 202510
    "HIST", "HIST", "MATH", "MATH", "ANTH",
    # 202560
    "HIST", "MATH", "ANTH",
    # 202580
    "HIST", "MATH", "MATH", "ANTH"
  ),
  subject = c(
    # 202410
    "HIST", "HIST", "MATH", "PHYS", "ANTH",
    # 202480
    "HIST", "MATH", "CHEM",
    # 202510
    "HIST", "HIST", "MATH", "MATH", "ANTH",
    # 202560
    "HIST", "MATH", "ANTH",
    # 202580
    "HIST", "MATH", "MATH", "ANTH"
  ),
  subject_course = c(
    # 202410 - includes PHYS 1010 (discontinued), missing MATH 1220 (new in 2025)
    "HIST 1110", "HIST 1120", "MATH 1215", "PHYS 1010", "ANTH 1110",
    # 202480 - includes CHEM 1010 (discontinued), missing MATH 4310/ANTH 2050 (new in 2025)
    "HIST 3010", "MATH 3140", "CHEM 1010",
    # 202510
    "HIST 1110", "HIST 1120", "MATH 1215", "MATH 1220", "ANTH 1110",
    # 202560
    "HIST 2010", "MATH 1430", "ANTH 3020",
    # 202580
    "HIST 3010", "MATH 3140", "MATH 4310", "ANTH 2050"
  ),
  course_title = c(
    # 202410
    "US History I", "US History II", "College Algebra", "Intro Physics", "Intro Anthropology",
    # 202480
    "Colonial America", "Linear Algebra", "Intro Chemistry",
    # 202510
    "US History I", "US History II", "College Algebra", "Trigonometry", "Intro Anthropology",
    # 202560
    "World Civ", "Calculus I", "Cultural Anth",
    # 202580
    "Colonial America", "Linear Algebra", "Abstract Algebra", "Archaeology"
  ),
  campus = c(
    # 202410
    "Main", "Online", "Main", "Main", "Main",
    # 202480
    "Online", "Main", "Main",
    # 202510
    "Main", "Online", "Main", "Valencia", "Main",
    # 202560
    "Main", "Main", "Online",
    # 202580
    "Online", "Main", "Online", "Main"
  ),
  college = c(rep("AS", 20)),
  status = c(
    # 202410
    "A", "A", "A", "A", "A",
    # 202480
    "A", "A", "A",
    # 202510
    "A", "A", "A", "A", "A",
    # 202560
    "A", "A", "A",
    # 202580
    "A", "A", "C", "A"
  ),
  part_term = c(
    # 202410
    "FT", "2H", "FT", "FT", "FT",
    # 202480
    "FT", "FT", "FT",
    # 202510
    "FT", "2H", "FT", "2H", "FT",
    # 202560
    "FT", "FT", "2H",
    # 202580
    "FT", "FT", "FT", "FT"
  ),
  instructor_id = c(
    # 202410
    "INS001", "INS002", "INS004", "INS009", "INS007",
    # 202480
    "INS003", "INS006", "INS010",
    # 202510
    "INS001", "INS002", "INS004", "INS005", "INS007",
    # 202560
    "INS001", "INS004", "INS008",
    # 202580
    "INS003", "INS006", "INS006", "INS007"
  ),
  instructor_name = c(
    # 202410
    "Smith, John", "Jones, Mary", "Brown, David", "Taylor, Alex", "Wilson, Carol",
    # 202480
    "Williams, Pat", "Miller, James", "Anderson, Kim",
    # 202510
    "Smith, John", "Jones, Mary", "Brown, David", "Davis, Sarah", "Wilson, Carol",
    # 202560
    "Smith, John", "Brown, David", "Moore, Robert",
    # 202580
    "Williams, Pat", "Miller, James", "Miller, James", "Wilson, Carol"
  ),
  delivery_method = c(
    # 202410
    "In Person", "Online", "In Person", "In Person", "In Person",
    # 202480
    "Online", "Hybrid", "In Person",
    # 202510
    "In Person", "Online", "In Person", "In Person", "In Person",
    # 202560
    "Hybrid", "In Person", "Online",
    # 202580
    "Online", "Hybrid", "Online", "In Person"
  ),
  level = c(
    # 202410
    "lower", "lower", "lower", "lower", "lower",
    # 202480
    "upper", "upper", "lower",
    # 202510
    "lower", "lower", "lower", "lower", "lower",
    # 202560
    "upper", "lower", "upper",
    # 202580
    "upper", "upper", "upper", "upper"
  ),
  enrolled = c(
    # 202410 - previous year enrollment (for year-over-year comparison)
    22, 28, 30, 25, 38,
    # 202480
    20, 12, 30,
    # 202510 - current year enrollment
    25, 30, 35, 28, 40,
    # 202560
    18, 32, 12,
    # 202580
    22, 15, 0, 20
  ),
  capacity = c(
    # 202410
    30, 35, 35, 30, 45,
    # 202480
    25, 20, 35,
    # 202510
    30, 35, 40, 30, 45,
    # 202560
    25, 35, 20,
    # 202580
    25, 20, 25, 25
  ),
  gen_ed_area = c(
    # 202410
    "Humanities", "Humanities", "Math", "Science", "Social Science",
    # 202480
    NA, NA, "Science",
    # 202510
    "Humanities", "Humanities", "Math", "Math", "Social Science",
    # 202560
    NA, "Math", NA,
    # 202580
    NA, NA, NA, "Social Science"
  ),
  term_type = c(
    # 202410
    rep("spring", 5),
    # 202480
    rep("fall", 3),
    # 202510
    rep("spring", 5),
    # 202560
    rep("summer", 3),
    # 202580
    rep("fall", 4)
  ),
  # Available seats (capacity - enrolled) for regstats/enrl testing
  # Note: enrl.R expects column name "available" (not "avail")
  available = c(
    # 202410: 30-22=8, 35-28=7, 35-30=5, 30-25=5, 45-38=7
    8, 7, 5, 5, 7,
    # 202480: 25-20=5, 20-12=8, 35-30=5
    5, 8, 5,
    # 202510: 30-25=5, 35-30=5, 40-35=5, 30-28=2, 45-40=5
    5, 5, 5, 2, 5,
    # 202560: 25-18=7, 35-32=3, 20-12=8
    7, 3, 8,
    # 202580: 25-22=3, 20-15=5, 25-0=25, 25-20=5
    3, 5, 25, 5
  ),
  # Waitlist counts for regstats/enrl testing
  # Note: enrl.R expects column name "waitlist_count" (not "waiting")
  waitlist_count = c(
    # 202410: varying waitlist
    2, 0, 5, 0, 8,
    # 202480: some waitlist
    3, 0, 10,
    # 202510: significant waitlist on some courses
    12, 5, 25, 0, 15,
    # 202560: lower waitlist
    2, 8, 0,
    # 202580: mixed waitlist
    5, 0, 0, 10
  ),
  job_cat = c(
    # 202410
    "TT", "NTT", "TT", "TT", "TT",
    # 202480
    "TT", "TT", "NTT",
    # 202510
    "TT", "NTT", "TT", "NTT", "TT",
    # 202560
    "TT", "TT", "NTT",
    # 202580
    "TT", "TT", "TT", "TT"
  ),
  # Course number string (extracted from subject_course, e.g. "HIST 1110" → "1110")
  # Order mirrors section_id sequence above (SEC101..SEC105, SEC106..SEC108, SEC001..SEC010, SEC003..SEC011, SEC004..SEC012)
  course_number = c(
    "1110", "1120", "1215", "1010", "1110",   # 202410
    "3010", "3140", "1010",                   # 202480
    "1110", "1120", "1215", "1220", "1110",   # 202510
    "2010", "1430", "3020",                   # 202560
    "3010", "3140", "4310", "2050"            # 202580
  ),
  # crosslist_code: blank for all base sections (non-crosslisted)
  crosslist_code = rep("", 20),
  # crosslist_group: NA for non-crosslisted
  crosslist_group = rep(NA_character_, 20),
  # crosslist_primary: always TRUE for non-crosslisted sections
  crosslist_primary = rep(TRUE, 20),
  # total_enrl: same as enrolled for non-crosslisted sections
  total_enrl = c(
    22, 28, 30, 25, 38,   # 202410
    20, 12, 30,            # 202480
    25, 30, 35, 28, 40,   # 202510
    18, 32, 12,            # 202560
    22, 15, 0, 20          # 202580
  ),
  # is_split: FALSE for all non-crosslisted sections
  is_split = rep(FALSE, 20),
  # split_sections: NA for non-crosslisted sections
  split_sections = rep(NA_character_, 20)
)

# =============================================================================
# KNOWN SECTIONS — CROSSLIST / SPLIT-LEVEL SCENARIOS
# =============================================================================
# Synthetic fixture for testing crosslist_group, crosslist_primary, and split
# level detection.  All rows are in term 202510.
#
# Scenarios:
#
#   XL01 — Standard same-level cross-dept crosslist (HIST 480 + ANTH 480)
#     Both are upper-division.  HIST 480 has enrollment, so it is primary.
#     Expected: crosslist_primary TRUE for XLSEC01, FALSE for XLSEC02
#     Expected: level = "upper" for both, is_split = FALSE
#
#   XL02 — Same-dept split-level crosslist (HIST 484 + HIST 584)
#     HIST 484 is upper (484 < 500), HIST 584 is grad (584 ≥ 500).
#     HIST 484 has enrollment, so it is primary.
#     Expected: is_split = TRUE for both, level preserved (upper/grad)
#     Expected: crosslist_primary TRUE for XLSEC03, FALSE for XLSEC04
#
#   XL03 — Split-level where the GRAD section is primary (AMST 499 + AMST 599)
#     AMST 499 is upper (enrolled=0), AMST 599 is grad (enrolled=5).
#     The grad section has higher enrollment, so it is primary.
#     Expected: is_split = TRUE for both, level preserved (upper/grad)
#     Expected: crosslist_primary TRUE for XLSEC06 (AMST 599), FALSE for XLSEC05
#
#   XL04 — Zero-enrollment tie-break (ANTH 490 + HIST 490)
#     Both upper-division, both enrolled=0.  ANTH < HIST alphabetically → ANTH primary.
#     Expected: level = "upper" for both, is_split = FALSE
#     Expected: crosslist_primary TRUE for XLSEC07 (ANTH 490), FALSE for XLSEC08
#
#   XL05 — Three-way split crosslist (HIST 475 + AMST 475 + HIST 575)
#     HIST 475 and AMST 475 are upper (< 500); HIST 575 is grad (≥ 500).
#     HIST 475 has enrollment (10) → it is primary.
#     Expected: is_split = TRUE for all three, level preserved (upper/upper/grad)
#     Expected: crosslist_primary TRUE for XLSEC09 (HIST 475) only
#
# Total XL sections: 11 (2+2+2+2+3)
# Total split sections: 7 (XL02:2 + XL03:2 + XL05:3)
# crosslist_primary TRUE: 5 (one per group)

known_sections_xl <- tibble(
  section_id = c(
    "XLSEC01", "XLSEC02",           # XL01: HIST 480 + ANTH 480
    "XLSEC03", "XLSEC04",           # XL02: HIST 484 + HIST 584
    "XLSEC05", "XLSEC06",           # XL03: AMST 499 + AMST 599
    "XLSEC07", "XLSEC08",           # XL04: ANTH 490 + HIST 490
    "XLSEC09", "XLSEC10", "XLSEC11" # XL05: HIST 475 + AMST 475 + HIST 575
  ),
  crn = c(
    30001, 30002,
    30003, 30004,
    30005, 30006,
    30007, 30008,
    30009, 30010, 30011
  ),
  term = rep(202510, 11),
  department = c(
    "HIST", "ANTH",   # XL01
    "HIST", "HIST",   # XL02
    "AMST", "AMST",   # XL03
    "ANTH", "HIST",   # XL04
    "HIST", "AMST", "HIST"  # XL05
  ),
  subject = c(
    "HIST", "ANTH",
    "HIST", "HIST",
    "AMST", "AMST",
    "ANTH", "HIST",
    "HIST", "AMST", "HIST"
  ),
  subject_course = c(
    "HIST 480", "ANTH 480",
    "HIST 484", "HIST 584",
    "AMST 499", "AMST 599",
    "ANTH 490", "HIST 490",
    "HIST 475", "AMST 475", "HIST 575"
  ),
  course_number = c(
    "480", "480",
    "484", "584",
    "499", "599",
    "490", "490",
    "475", "475", "575"
  ),
  course_title = c(
    "Hist Topics", "Anth Topics",
    "Hist Seminar", "Hist Grad Seminar",
    "Am Studies Topics", "Am Studies Grad",
    "Anth Field Methods", "Hist Field Methods",
    "Hist Colloquium", "Am Studies Colloquium", "Hist Grad Colloquium"
  ),
  campus = rep("Main", 11),
  college = rep("AS", 11),
  status = rep("A", 11),
  part_term = rep("FT", 11),
  instructor_id = c(
    "INS001", "INS007",   # XL01
    "INS001", "INS001",   # XL02
    "INS008", "INS008",   # XL03
    "INS007", "INS001",   # XL04
    "INS001", "INS008", "INS001"  # XL05
  ),
  instructor_name = c(
    "Smith, John", "Wilson, Carol",
    "Smith, John", "Smith, John",
    "Moore, Robert", "Moore, Robert",
    "Wilson, Carol", "Smith, John",
    "Smith, John", "Moore, Robert", "Smith, John"
  ),
  delivery_method = rep("In Person", 11),
  # level: original academic level (upper for < 500, grad for >= 500). NOT overwritten for split groups.
  level = c(
    "upper", "upper",   # XL01: both upper
    "upper", "grad",    # XL02: HIST 484 (upper) + HIST 584 (grad)
    "upper", "grad",    # XL03: AMST 499 (upper) + AMST 599 (grad)
    "upper", "upper",   # XL04: both upper
    "upper", "upper", "grad"  # XL05: HIST 475 + AMST 475 (upper) + HIST 575 (grad)
  ),
  # is_split: TRUE for crosslist groups spanning undergrad/grad boundary
  is_split = c(
    FALSE, FALSE,   # XL01: both upper, not split
    TRUE,  TRUE,    # XL02: upper + grad → split
    TRUE,  TRUE,    # XL03: upper + grad → split
    FALSE, FALSE,   # XL04: both upper, not split
    TRUE,  TRUE, TRUE  # XL05: upper + grad → split
  ),
  # split_sections: display string showing all courses in a split-level group
  split_sections = c(
    NA_character_, NA_character_,                  # XL01: not split
    "HIST 484 / HIST 584", "HIST 484 / HIST 584", # XL02
    "AMST 499 / AMST 599", "AMST 499 / AMST 599", # XL03
    NA_character_, NA_character_,                   # XL04: not split
    "AMST 475 / HIST 475 / HIST 575",              # XL05
    "AMST 475 / HIST 475 / HIST 575",
    "AMST 475 / HIST 475 / HIST 575"
  ),
  enrolled = c(
    12, 0,   # XL01: HIST 480 has students, ANTH 480 does not
     8, 0,   # XL02: HIST 484 has students
     0, 5,   # XL03: AMST 599 (grad) has students — grad section is primary
     0, 0,   # XL04: neither has students — tiebreak by subject alphabetically
    10, 0, 0 # XL05: HIST 475 has students
  ),
  capacity = rep(25, 11),
  gen_ed_area = rep(NA_character_, 11),
  term_type = rep("spring", 11),
  available = c(
    13, 25,
    17, 25,
    25, 20,
    25, 25,
    15, 25, 25
  ),
  waitlist_count = rep(0L, 11),
  job_cat = rep("TT", 11),
  crosslist_code = c(
    "XL01", "XL01",
    "XL02", "XL02",
    "XL03", "XL03",
    "XL04", "XL04",
    "XL05", "XL05", "XL05"
  ),
  crosslist_group = c(
    "XL01", "XL01",
    "XL02", "XL02",
    "XL03", "XL03",
    "XL04", "XL04",
    "XL05", "XL05", "XL05"
  ),
  # crosslist_primary: TRUE for the home section of each group
  #   XL01: HIST 480 (XLSEC01) — higher enrolled (12 vs 0)
  #   XL02: HIST 484 (XLSEC03) — higher enrolled (8 vs 0)
  #   XL03: AMST 599 (XLSEC06) — higher enrolled (5 vs 0); grad section is home
  #   XL04: ANTH 490 (XLSEC07) — tied at 0; ANTH < HIST alphabetically
  #   XL05: HIST 475 (XLSEC09) — highest enrolled (10 vs 0 vs 0)
  crosslist_primary = c(
    TRUE,  FALSE,   # XL01
    TRUE,  FALSE,   # XL02
    FALSE, TRUE,    # XL03 (grad section is primary)
    TRUE,  FALSE,   # XL04 (ANTH wins tiebreak)
    TRUE,  FALSE, FALSE  # XL05
  ),
  # total_enrl: combined enrollment across all sections in the XL group
  total_enrl = c(
    12, 12,   # XL01
     8,  8,   # XL02
     5,  5,   # XL03
     0,  0,   # XL04
    10, 10, 10 # XL05
  )
)

# =============================================================================
# KNOWN STUDENTS (enrollments)
# =============================================================================
# 24 student enrollments across 6 sections
#
# Expected values for filtering:
#   - By department:
#       HIST: 8 enrollments (students in SEC001, SEC002)
#       MATH: 10 enrollments (students in SEC005, SEC007)
#       ANTH: 6 enrollments (students in SEC010, SEC012)
#
#   - By term:
#       202510: 14 enrollments (SEC001, SEC002, SEC005, SEC010)
#       202560: 4 enrollments (SEC007)
#       202580: 6 enrollments (SEC012)
#
#   - By level:
#       lower: 18 enrollments
#       upper: 6 enrollments
#
#   - By grade (for completed terms):
#       With grades: 14 (all 202510 enrollments)
#       Without grades (NA): 10 (202560 + 202580)
#
#   - Grade counts for 202510 (for DFW testing):
#       Passing: A: 2, B: 3, C: 2, B+: 1, A-: 1 (9 total)
#       Failing: F: 2, D: 1 (3 total)
#       Late drops: W: 2 (included in failed)
#       Early drops: Drop: 2 (excluded from DFW calculation)
#
#   - DFW calculation for 202510 (by course, Main campus):
#       HIST 1110: passed=2, failed=2, early_dropped=0 -> DFW % = 2/(2+2)*100 = 50%
#       HIST 1120: passed=2, failed=2, early_dropped=1 -> DFW % = 2/(2+2)*100 = 50%
#       MATH 1215: passed=3, failed=1, early_dropped=1 -> DFW % = 1/(3+1)*100 = 25%
#       ANTH 1110: passed=2, failed=0, early_dropped=0 -> DFW % = 0/(2+0)*100 = 0%

known_students <- tibble(
  student_id = c("STU001", "STU002", "STU003", "STU004",  # SEC001 (HIST 1110, 202510)
                 "STU005", "STU006", "STU007", "STU008", "STU025",  # SEC002 (HIST 1120, 202510) - 5 students
                 "STU009", "STU010", "STU011", "STU012", "STU013",  # SEC005 (MATH 1215, 202510) - 5 students
                 "STU015", "STU016", "STU017", "STU018",  # SEC007 (MATH, 202560)
                 "STU019", "STU020", "STU021", "STU022",  # SEC010 (ANTH, 202510)
                 "STU023", "STU024"),                     # SEC012 (ANTH, 202580)
  section_id = c(rep("SEC001", 4), rep("SEC002", 5), rep("SEC005", 5),
                 rep("SEC007", 4), rep("SEC010", 4), rep("SEC012", 2)),
  crn = c(rep(10001, 4), rep(10002, 5), rep(10005, 5),
          rep(10007, 4), rep(10010, 4), rep(10012, 2)),
  term = c(rep(202510, 4), rep(202510, 5), rep(202510, 5),
           rep(202560, 4), rep(202510, 4), rep(202580, 2)),
  department = c(rep("HIST", 9), rep("MATH", 9), rep("ANTH", 6)),
  subject = c(rep("HIST", 9), rep("MATH", 9), rep("ANTH", 6)),
  subject_course = c(rep("HIST 1110", 4), rep("HIST 1120", 5), rep("MATH 1215", 5),
                     rep("MATH 1430", 4), rep("ANTH 1110", 4), rep("ANTH 2050", 2)),
  subject_code = c(rep("HIST", 9), rep("MATH", 9), rep("ANTH", 6)),
  level = c(rep("lower", 9), rep("lower", 9), rep("lower", 4), rep("upper", 2)),
  instructor_id = c(rep("INS001", 4), rep("INS002", 5), rep("INS004", 5),
                    rep("INS004", 4), rep("INS007", 4), rep("INS007", 2)),
  instructor_name = c(rep("Smith, John", 4), rep("Jones, Mary", 5), rep("Brown, David", 5),
                      rep("Brown, David", 4), rep("Wilson, Carol", 4), rep("Wilson, Carol", 2)),
  # Extract last name for gradebook compatibility
  instructor_last_name = c(rep("Smith", 4), rep("Jones", 5), rep("Brown", 5),
                           rep("Brown", 4), rep("Wilson", 4), rep("Wilson", 2)),
  # Grades with failing grades for DFW testing:
  # SEC001 (HIST 1110): 2 pass (A, B), 2 fail (F, W) -> DFW = 50%
  # SEC002 (HIST 1120): 2 pass (A-, B), 1 fail (F), 1 late drop (W), 1 early drop (Drop) -> DFW = 50%
  # SEC005 (MATH 1215): 3 pass (A, B, C), 1 fail (D), 1 early drop (Drop) -> DFW = 25%
  # SEC010 (ANTH 1110): 2 pass (A, B), 2 in progress (NA) -> treated as no grade yet
  final_grade = c("A", "B", "F", "W",                 # SEC001 (HIST 1110): 2 pass, 2 fail
                  "A-", "B", "F", "W", "Drop",        # SEC002 (HIST 1120): 2 pass, 2 fail, 1 early drop
                  "A", "B", "C", "D", "Drop",         # SEC005 (MATH 1215): 3 pass, 1 fail, 1 early drop
                  NA, NA, NA, NA,                     # SEC007 (Summer - in progress)
                  "A", "B", NA, NA,                   # SEC010 (ANTH): 2 pass, 2 in progress
                  NA, NA),                            # SEC012 (Fall - in progress)
  # Registration status: RE = registered, DR = dropped early
  registration_status_code = c(rep("RE", 4),         # SEC001
                               "RE", "RE", "RE", "RE", "DR",  # SEC002 (1 early drop)
                               "RE", "RE", "RE", "RE", "DR",  # SEC005 (1 early drop)
                               rep("RE", 4),         # SEC007
                               rep("RE", 4),         # SEC010
                               rep("RE", 2)),        # SEC012
  credits = c(rep(3, 24)),
  campus = c(rep("Main", 4), rep("Main", 5), rep("Main", 5),
             rep("Main", 4), rep("Main", 4), rep("Main", 2)),
  college = c(rep("AS", 24)),
  student_campus = c(rep("Main", 14), rep("Online", 4), rep("Main", 6)),
  student_college = c(rep("AS", 18), rep("ED", 6)),
  student_classification = c(rep("Freshman", 9), rep("Sophomore", 9),
                             rep("Junior", 4), rep("Senior", 2)),
  major = c(rep("History", 9), rep("Mathematics", 5),
                    rep("Computer Science", 4), rep("Anthropology", 6)),
  delivery_method = c(rep("In Person", 4), rep("In Person", 5), rep("In Person", 5),
                      rep("In Person", 4), rep("In Person", 4), rep("In Person", 2)),
  # term_type derived from term code: 10=spring, 60=summer, 80=fall
  term_type = c(rep("spring", 4), rep("spring", 5), rep("spring", 5),
                rep("summer", 4), rep("spring", 4), rep("fall", 2)),
  # course_title matching known_sections
  course_title = c(rep("US History I", 4), rep("US History II", 5), rep("College Algebra", 5),
                   rep("Calculus I", 4), rep("Intro Anthropology", 4), rep("Archaeology", 2))
)

# =============================================================================
# KNOWN PROGRAMS (major/minor/concentration enrollments)
# =============================================================================
# 26 program enrollment records for 12 unique students across 3 terms
# INCLUDES CONCENTRATIONS for testing all filter combinations
#
# Student distribution:
#   STU201 - HIST Major + Latin America Concentration (UG) - terms 202510, 202560, 202580
#   STU202 - HIST Major + MATH Minor (UG) - terms 202510, 202560
#   STU203 - MATH Major + Statistics Concentration (UG) - terms 202510, 202560, 202580
#   STU204 - MATH Major + Applied Mathematics Concentration (Grad) - terms 202510, 202580
#   STU205 - ANTH Major (UG, no minor/conc) - terms 202510, 202560
#   STU206 - ANTH Major + HIST Minor (UG) - term 202510
#   STU207 - HIST Major (UG, no minor/conc) - term 202580
#   STU208 - MATH Major (Grad, no concentration) - term 202580
#   STU209 - HIST Second Major (UG) - term 202560
#   STU210 - ANTH Major (UG) - term 202580
#
# Expected values for get_headcount():
#   - By department (term 202510):
#       HIST: 4 unique students (STU201, STU202, STU203[second minor], STU206[first minor])
#       MATH: 4 unique students (STU202[first minor], STU203[major+conc], STU204[major+conc])
#       ANTH: 2 unique students (STU205, STU206)
#
#   - By program_type (all terms):
#       Major: 15 records
#       First Minor: 3 records (STU202 MATH minor x2, STU206 HIST minor x1)
#       Second Minor: 1 record (STU203 HIST minor in 202510)
#       Second Major: 1 record (STU209 in 202560)
#       First Concentration: 6 records (STU201 x3 terms, STU203 x3 terms, STU204 x2 terms)
#
#   - By program_name filtering:
#       Major "History": 5 records across all terms (STU201, STU202x2, STU207, STU209)
#       Minor "Mathematics": 2 records (STU202 in 202510, 202560)
#       Concentration "Statistics": 3 records (STU203 in all 3 terms)
#       Concentration "Latin America": 3 records (STU201 in all 3 terms)
#
#   - By student_level (term 202510):
#       Undergraduate: 5 unique students
#       Graduate: 1 unique student (STU204)
#
#   - Combined filters (HIST dept + History major + term 202510):
#       2 unique students (STU201, STU202)
#
#   - Students with NO concentrations (term 202510):
#       STU202, STU205, STU206 = 3 students
#
#   - Distinct student counts by term:
#       202510: 6 unique students (9 major/minor + 3 concentration records)
#       202560: 5 unique students (6 major/minor + 2 concentration records)
#       202580: 6 unique students (6 major/minor + 2 concentration records)

known_programs <- tibble(
  student_id = c(
    # Term 202510 (6 students, 12 program records: 9 major/minor + 3 concentrations)
    "STU201", "STU201", "STU202", "STU202", "STU203", "STU203", "STU203", "STU204", "STU204", "STU205", "STU206", "STU206",
    # Term 202560 (5 students, 8 program records: 6 major/minor + 2 concentrations)
    "STU201", "STU201", "STU202", "STU202", "STU203", "STU203", "STU205", "STU209",
    # Term 202580 (6 students, 8 program records: 6 major + 2 concentrations)
    "STU201", "STU201", "STU203", "STU203", "STU204", "STU207", "STU208", "STU210"
  ),
  term = c(
    rep(202510, 12),
    rep(202560, 8),
    rep(202580, 8)
  ),
  department = c(
    # 202510 (12 records)
    "HIST", "HIST", "HIST", "MATH", "MATH", "MATH", "MATH", "MATH", "MATH", "ANTH", "ANTH", "HIST",
    # 202560 (8 records)
    "HIST", "HIST", "HIST", "MATH", "MATH", "MATH", "ANTH", "HIST",
    # 202580 (8 records)
    "HIST", "HIST", "MATH", "MATH", "MATH", "HIST", "MATH", "ANTH"
  ),
  program_name = c(
    # 202510
    "History", "Latin America", "History", "Mathematics", "Mathematics", "Statistics", "History", "Mathematics", "Applied Mathematics", "Anthropology", "Anthropology", "History",
    # 202560
    "History", "Latin America", "History", "Mathematics", "Mathematics", "Statistics", "Anthropology", "History",
    # 202580
    "History", "Latin America", "Mathematics", "Statistics", "Mathematics", "History", "Mathematics", "Anthropology"
  ),
  program_code = c(
    # 202510
    "HIST-BA", "LATAM-CN", "HIST-BA", "MATH-MN", "MATH-BS", "STAT-CN", "HIST-MN", "MATH-MS", "APMATH-CN", "ANTH-BA", "ANTH-BA", "HIST-MN",
    # 202560
    "HIST-BA", "LATAM-CN", "HIST-BA", "MATH-MN", "MATH-BS", "STAT-CN", "ANTH-BA", "HIST-BA",
    # 202580
    "HIST-BA", "LATAM-CN", "MATH-BS", "STAT-CN", "MATH-MS", "HIST-BA", "MATH-MS", "ANTH-BA"
  ),
  program_type = c(
    # 202510
    "Major", "First Concentration", "Major", "First Minor", "Major", "First Concentration", "Second Minor", "Major", "First Concentration", "Major", "Major", "First Minor",
    # 202560
    "Major", "First Concentration", "Major", "First Minor", "Major", "First Concentration", "Major", "Second Major",
    # 202580
    "Major", "First Concentration", "Major", "First Concentration", "Major", "Major", "Major", "Major"
  ),
  degree = c(
    # 202510
    "BA", NA, "BA", NA, "BS", NA, NA, "MS", NA, "BA", "BA", NA,
    # 202560
    "BA", NA, "BA", NA, "BS", NA, "BA", "BA",
    # 202580
    "BA", NA, "BS", NA, "MS", "BA", "MS", "BA"
  ),
  student_level = c(
    # 202510
    "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Graduate/GASM", "Graduate/GASM", "Undergraduate", "Undergraduate", "Undergraduate",
    # 202560
    "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate",
    # 202580
    "Undergraduate", "Undergraduate", "Undergraduate", "Undergraduate", "Graduate/GASM", "Undergraduate", "Graduate/GASM", "Undergraduate"
  ),
  student_college = c(
    # 202510
    "AS", "AS", "AS", "AS", "AS", "AS", "AS", "AS", "AS", "AS", "AS", "AS",
    # 202560
    "AS", "AS", "AS", "AS", "AS", "AS", "AS", "ED",
    # 202580
    "AS", "AS", "AS", "AS", "AS", "AS", "AS", "AS"
  ),
  student_campus = c(
    # 202510
    "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Online", "Main", "Main",
    # 202560
    "Main", "Main", "Main", "Main", "Main", "Main", "Main", "Main",
    # 202580
    "Main", "Main", "Main", "Main", "Main", "Online", "Main", "Main"
  ),
  college = student_college,
  campus = student_campus
)

# =============================================================================
# KNOWN DEGREES (awarded degrees)
# =============================================================================
# 12 degrees awarded
#
# Expected values for filtering:
#   - By term:
#       202480 (Fall 2024): 4 degrees
#       202510 (Spring 2025): 5 degrees
#       202560 (Summer 2025): 3 degrees
#
#   - By department:
#       AS Anthropology: 4 degrees
#       History: 4 degrees
#       Mathematics Statistics: 4 degrees
#
#   - By degree type:
#       BA: 8
#       BS: 3
#       MA: 1
#
#   - By major (for count_degrees filtering):
#       History: 4 degrees
#       Mathematics: 2 degrees
#       Anthropology: 4 degrees
#       Applied Mathematics: 1 degree
#       Statistics: 1 degree
#
#   - By award_category:
#       Bachelor: 11
#       Master: 1

known_degrees <- tibble(
  term = c(202480, 202480, 202480, 202480,
           202510, 202510, 202510, 202510, 202510,
           202560, 202560, 202560),
  student_id = c("STU101", "STU102", "STU103", "STU104",
                 "STU105", "STU106", "STU107", "STU108", "STU109",
                 "STU110", "STU111", "STU112"),
  student_college = c("AS", "AS", "AS", "AS",
                      "AS", "AS", "AS", "AS", "AS",
                      "AS", "AS", "AS"),
  department = c("History", "History", "Mathematics Statistics", "AS Anthropology",
                 "History", "Mathematics Statistics", "Mathematics Statistics", "AS Anthropology", "AS Anthropology",
                 "History", "Mathematics Statistics", "AS Anthropology"),
  program_code = c("HIST", "HIST", "MATH", "ANTH",
                   "HIST", "MATH", "AMATH", "ANTH", "ANTH",
                   "HIST", "STAT", "ANTH"),
  award_category = c("Bachelor", "Bachelor", "Bachelor", "Bachelor",
                     "Bachelor", "Bachelor", "Bachelor", "Bachelor", "Bachelor",
                     "Master", "Bachelor", "Bachelor"),
  degree = c("BA", "BA", "BS", "BA",
             "BA", "BS", "BA", "BA", "BA",
             "MA", "BS", "BA"),
  major = c("History", "History", "Mathematics", "Anthropology",
            "History", "Mathematics", "Applied Mathematics", "Anthropology", "Anthropology",
            "History", "Statistics", "Anthropology"),
  major_code = c("HIST", "HIST", "MATH", "ANTH",
                 "HIST", "MATH", "AMATH", "ANTH", "ANTH",
                 "HIST", "STAT", "ANTH"),
  second_major = c(NA, NA, NA, NA,
                   NA, "Computer Science", NA, NA, "Forensic Science",
                   NA, NA, NA),
  first_minor = c(NA, "Political Science", NA, "History",
                  NA, NA, NA, NA, NA,
                  NA, NA, "Biology"),
  second_minor = c(NA, NA, NA, NA,
                   NA, NA, NA, NA, NA,
                   NA, NA, NA)
)

# =============================================================================
# KNOWN FACULTY
# =============================================================================
# 8 unique instructors across terms
#
# Expected values:
#   - Unique instructors: 8
#   - By department:
#       HIST: 3 instructors (INS001, INS002, INS003)
#       MATH: 3 instructors (INS004, INS005, INS006)
#       ANTH: 2 instructors (INS007, INS008)

known_faculty <- tibble(
  instructor_id = c("INS001", "INS002", "INS003", "INS004", "INS005", "INS006", "INS007", "INS008",
                    "INS001", "INS004", "INS007", "INS008",
                    "INS001", "INS003", "INS004", "INS006", "INS007"),
  term = c(rep(202510, 8), rep(202560, 4), rep(202580, 5)),
  department = c("HIST", "HIST", "HIST", "MATH", "MATH", "MATH", "ANTH", "ANTH",
                 "HIST", "MATH", "ANTH", "ANTH",
                 "HIST", "HIST", "MATH", "MATH", "ANTH"),
  instructor_name = c("Smith, John", "Jones, Mary", "Williams, Pat", "Brown, David",
                      "Davis, Sarah", "Miller, James", "Wilson, Carol", "Moore, Robert",
                      "Smith, John", "Brown, David", "Wilson, Carol", "Moore, Robert",
                      "Smith, John", "Williams, Pat", "Brown, David", "Miller, James", "Wilson, Carol"),
  job_category = c("TT", "NTT", "TT", "TT", "NTT", "TT", "TT", "NTT",
                   "TT", "TT", "TT", "NTT",
                   "TT", "TT", "TT", "TT", "TT")
)

# =============================================================================
# Backward compatibility alias
# =============================================================================
known_courses <- known_sections

message("Loaded known test fixtures:")
message("  known_sections:    ", nrow(known_sections), " rows (non-crosslisted base sections)")
message("  known_sections_xl: ", nrow(known_sections_xl), " rows (crosslist/split-level scenarios)")
message("  known_students:    ", nrow(known_students), " rows")
message("  known_programs:    ", nrow(known_programs), " rows")
message("  known_degrees:     ", nrow(known_degrees), " rows")
message("  known_faculty:     ", nrow(known_faculty), " rows")
