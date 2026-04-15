# =============================================================================
# CEDAR DESIGNED TEST FIXTURES
# =============================================================================
# Hand-crafted minimal test data for Cedar unit tests.
# Replaces cedar_*_test.qs binary fixtures with transparent, inspectable data.
#
# Design philosophy: every expected value is traceable to explicit rows here.
# No sampling, no random seeds — failures are diagnosable without running the
# full data pipeline.
#
# REGENERATE: not applicable — this file IS the source of truth.
# All expected values listed below match what Cedar functions compute on this data.
#
# =============================================================================
# EXPECTED VALUES (hard-coded in test files — update tests when changing this data)
# =============================================================================
#
# === CEDAR_SECTIONS (85 total: 71 base + 14 XL rows merged in) ===
#
# Base sections (non-XL):
#   Active by dept:    HIST=15  MATH=10  ANTH=7  NURS=8  PSYC=5  BIOL=3  MGMT=4
#                      ENGL=8   POLS=1
#     (SVAR03=PSYC active, SVAR04=HIST T: active, SVAR05=ENGL active)
#   Active by term:    202010=17  202060=12  202080=15  202110=17  total=61
#   Active by campus:  ABQ=53  EA=7  GA=1
#   Active by delivery: ENH=32  ONL=22  MOPS=6  NA=1
#   Active by level:   lower=46  upper=12  grad=3
#   Active by part_term: 1=45  1H=4  2H=3  NF=8  NA=1
#   Active by term_type: spring=34  summer=12  fall=15
#   Cancelled (status=C): 8
#   Removed  (status=R): 1  (SVAR01)
#   Suspended (status=S): 1  (SVAR02)
#
# Variety rows (SVAR01-SVAR05):
#   SVAR01 — status="R", HIST 200 202080 (removed)
#   SVAR02 — status="S", MATH 300 202110 (suspended)
#   SVAR03 — delivery_method=NA, PSYC 2210 202010 (active)
#   SVAR04 — is_topics=TRUE ("T: Black Sports History"), HIST 395 202080 (active)
#   SVAR05 — part_term=NA, ENGL 2210 202110 (active)
#
# Active dept × term combos:
#   HIST×202010=4    HIST×202060=2    MATH×202010=3  NURS×202060=2
#   ANTH×202060=1
#
# filter_by_term (base sections, all statuses):
#   "202010-202060" = 34    "202010-202110" = 71
#   "spring" = 40  "summer" = 14  "fall" = 17
#
# XL rows (14 rows, built as cedar_sections_xl below then merged in):
#
# Five crosslist/split scenarios for test-crosslist-split.R:
#   XL01 — cross-dept, same level: HIST 480 (primary,12) + ANTH 480 (0)
#   XL02 — same-dept split-level:  HIST 484 (primary,8) + HIST 584 (3)
#   XL03 — split-level, grad primary: AMST 499 (0) + AMST 599 (primary,5)
#   XL04 — zero-enrl alpha tiebreak:  ANTH 490 (primary) + HIST 490 (both 0)
#   XL05 — three-way split-level: HIST 475 (primary,10) + AMST 475 (0) + HIST 575 (0)
#   XL06 — combined C-suffix: ANTH 2190C (3 CRNs, primary enrolled=16, total_enrl=47)
#   EC-04 — Pattern A non-crosslisted C: BIOL 2110C (4 CRNs, enrolled=22/22/23/22, total_enrl=89)
#   EC-05 — Pattern B non-crosslisted C: BIOL 304C  (4 CRNs, enrolled=25/22/22/20, total_enrl=same)
#   EC-06 — Pattern C internal crosslist C: BIOL 300C (2 groups × 3 CRNs; group 6G sum=92, group 62 sum=138)
# XL crosslist_primary=TRUE: 6  |  is_split=TRUE: 7  |  crosslist_external=TRUE: 6
# is_combined=TRUE: 17 (XL06=3, EC-04=4, EC-05=4, EC-06=6)
# Tests filter with filter(!is.na(crosslist_group)) to get this subset.
#
# === CEDAR_STUDENTS ===
#
# Enrolled (sections.enrolled sum) per term:
#   202010=406  202060=217  202080=308  202110=328
# Student rows per term (RE + drops):
#   202010=440  202060=219  202080=322  202110=330  (+19 in 202010, +9 in 202080: named pipeline rows)
# Student rows by dept:
#   HIST=279  MATH=280  ANTH=219  (+28 named pipeline enrollment rows)
# Student rows by course (PSYC 1110 all terms): 91
# HIST dept × 202010: sections=4, enrolled=76
# HIST 1110 registered (RE) per term: 21+15+22+19=77 across all terms
#
# === CEDAR_SECTIONS regstats design ===
#
# BUMP:    ANTH 2175 (spring only)
#          202010 registered=62 → sd_deviation=1.0, impacted=20.5, concern_tier=moderate_high
#          202110 registered=21 → baseline
# SQUEEZE: MATH 1215Z — 202010 avail=0, dr_all_mean_SP=(3+1)/2=2.0 → squeeze=0.0
# SQUEEZE: HIST 327   — 202010 avail=0, dr_all_mean_SP=(3+1)/2=2.0 → squeeze=0.0
#
# === CEDAR_STUDENTS grade design (HIST 1110 202010, test-grades.R) ===
#
# 3×A + 8×B + 6×C + 2×D + 2×F (RE, enrolled)  = 17 passed, 4 failed-RE
# 9×W (DW, dropped)                              = 9 late_dropped
# early_dropped = 0  (no DR students)
# dfw_pct = 13/30 × 100 = 43.33
#
# === CEDAR_PROGRAMS ===
#
# HIST dept headcount 202010:  64 students (25 pre-major + 39 declared)
# MATH dept headcount 202010:   5 students
# ANTH dept headcount 202010:  12 students (10 majors + 2 Arch concentration)
# History major distinct students (all terms): 73
#   (66 original + 3 SWOUT + 2 ENGL-HIST + 2 PREDECL)
# Psychology minor rows (all terms): 10
# Archaeology concentration rows (all terms): 4
# Population trend HIST 202010:
#   Pre-Major  = 25  (21 Continuing, 2 Transfer, 1 Readmit, 1 Other)
#   Declared   = 39  (38 Continuing, 1 Readmit)
# Population trend HIST total declared (all terms): 39+8+10+9 = 66  (original cohorts only)
#
# Major change events (non-HIST changers): 4  (CHANGER_A, CHANGER_B, MGMT_CHG1, MGMT_CHG2)
#
# HIST population outcome/pathway matrix:
#   ongoing    + direct     : STU-HD-SP2-001..009
#   ongoing    + switched_in: STU-ENGL-HIST-001/002  (came from ENGL)
#   ongoing    + pre_major  : STU-HIST-PREDECL-001
#   graduated  + direct     : STU-HD-SP1-001..004
#   graduated  + pre_major  : STU-HIST-PREDECL-002   (DEG011)
#   switched_out + direct   : STU-HIST-SWOUT-001/002 (→POLS), STU-HIST-SWOUT-003 (→BIOL)
#   stopped_out + direct    : STU-HD-SP1-005..039    (implicit: 202010 only, no degree, no other major)
#   never_declared          : STU-HP-FA1-001..008, STU-HP-SU1-001
#
# Major-changes cone (HIST focal):
#   HIST → POLS: 2 students (STU-HIST-SWOUT-001/002) — testable pair at min_n=2
#   HIST → BIOL: 1 student  (STU-HIST-SWOUT-003)
#   ENGL → HIST: 2 students (STU-ENGL-HIST-001/002) — testable pair at min_n=2
#
# graduation_status values: "Awarded" (formerly Conferred), "Pending" (formerly Applied)
#   These match production cedar_degrees schema. DEG001-007 = Awarded, DEG008-011 = Pending/Awarded.

suppressPackageStartupMessages({
  library(tibble)
  library(dplyr)
})

# =============================================================================
# NAMED IDs — referenced in test files
# =============================================================================
# (These must match the constants in test-major-changes.R and
#  test-headcount-comprehensive.R after updating those files.)

# =============================================================================
# CEDAR_SECTIONS
# =============================================================================

cedar_sections <- tribble(
  ~section_id,       ~term,  ~crn,    ~subject, ~course_number, ~subject_course, ~section,
  ~course_title,               ~part_term, ~campus, ~college, ~department,
  ~instructor_id, ~instructor_name,
  ~enrolled, ~total_enrl, ~capacity, ~available,
  ~status, ~delivery_method, ~level,   ~term_type,
  ~waitlist_count, ~waitlist_capacity,
  ~crosslist_primary, ~is_split,
  ~credits_min, ~credits_max,
  ~start_date,    ~end_date,

  # --- 202010 (Spring 2020) — 16 active ---
  "S10001", 202010L, "10001", "HIST", "1110", "HIST 1110", "001",
  "History of the Western World",          "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  21L, 21L, 25L, 4L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10002", 202010L, "10002", "HIST", "327", "HIST 327", "001",
  "Modern European History",               "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  28L, 28L, 28L, 0L,
  "A", "ENH", "upper", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10003", 202010L, "10003", "HIST", "490", "HIST 490", "001",
  "Senior Seminar in History",             "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  15L, 15L, 20L, 5L,
  "A", "ONL", "upper", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10004", 202010L, "10004", "HIST", "601", "HIST 601", "001",
  "Graduate Colloquium in History",        "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  12L, 12L, 15L, 3L,
  "A", "ENH", "grad", "SP",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10005", 202010L, "10005", "MATH", "1215Z","MATH 1215Z","001",
  "College Algebra with Lab",              "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  35L, 35L, 35L, 0L,
  "A", "ENH", "lower", "SP",
  3L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10006", 202010L, "10006", "MATH", "1430", "MATH 1430", "001",
  "Calculus I",                            "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  28L, 28L, 35L, 7L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10007", 202010L, "10007", "MATH", "1430", "MATH 1430", "002",
  "Calculus I",                            "1",  "EA",  "STEM", "MATH",
  "INS002", "Chen, David",
  22L, 22L, 35L, 13L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10008", 202010L, "10008", "ANTH", "2175", "ANTH 2175", "001",
  "World Cultures",                        "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  62L, 62L, 70L, 8L,
  "A", "ENH", "lower", "SP",
  0L, 10L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10009", 202010L, "10009", "ANTH", "1140", "ANTH 1140", "001",
  "Introduction to Anthropology",          "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  30L, 30L, 35L, 5L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10010", 202010L, "10010", "PSYC", "1110", "PSYC 1110", "001",
  "Introduction to Psychology",            "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  25L, 25L, 30L, 5L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10011", 202010L, "10011", "BIOL", "1140", "BIOL 1140", "001",
  "Biology for Non-Majors",                "1",  "ABQ", "STEM", "BIOL",
  "INS005", "Rodriguez, Maria",
  24L, 24L, 30L, 6L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10012", 202010L, "10012", "NURS", "2010", "NURS 2010", "001",
  "Foundations of Nursing",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  22L, 22L, 25L, 3L,
  "A", "MOPS", "lower", "SP",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10013", 202010L, "10013", "NURS", "3020", "NURS 3020", "001",
  "Adult Health Nursing I",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  20L, 20L, 24L, 4L,
  "A", "MOPS", "upper", "SP",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10014", 202010L, "10014", "MGMT", "2010", "MGMT 2010", "001",
  "Principles of Management",              "1",  "ABQ", "BUS",  "MGMT",
  "INS007", "Davis, Robert",
  20L, 20L, 25L, 5L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10015", 202010L, "10015", "ENGL", "1110", "ENGL 1110", "001",
  "Composition I",                         "1H", "ABQ", "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  22L, 22L, 24L, 2L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-03-13"),

  "S10016", 202010L, "10016", "ENGL", "1110", "ENGL 1110", "002",
  "Composition I",                         "2H", "EA",  "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  20L, 20L, 24L, 4L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-03-16"), as.Date("2020-05-08"),

  # --- Cancelled 202010 (2) ---
  "S10C01", 202010L, "10901", "HIST", "395",  "HIST 395",  "001",
  "Topics in History",                     "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  0L, 0L, 20L, 20L,
  "C", "ENH", "upper", "SP",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  "S10C02", 202010L, "10902", "MATH", "2530", "MATH 2530", "001",
  "Introduction to Linear Algebra",        "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  0L, 0L, 30L, 30L,
  "C", "ENH", "lower", "SP",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  # --- 202060 (Summer 2020) — 12 active ---
  "S60001", 202060L, "60001", "HIST", "1110", "HIST 1110", "050",
  "History of the Western World",          "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  15L, 15L, 20L, 5L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60002", 202060L, "60002", "HIST", "327",  "HIST 327",  "050",
  "Modern European History",               "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  18L, 18L, 25L, 7L,
  "A", "ONL", "upper", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60003", 202060L, "60003", "MATH", "1215Z","MATH 1215Z","050",
  "College Algebra with Lab",              "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  28L, 28L, 35L, 7L,
  "A", "ENH", "lower", "SU",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60004", 202060L, "60004", "MATH", "1430", "MATH 1430", "050",
  "Calculus I",                            "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  20L, 20L, 35L, 15L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60005", 202060L, "60005", "ANTH", "1140", "ANTH 1140", "050",
  "Introduction to Anthropology",          "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  18L, 18L, 25L, 7L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60006", 202060L, "60006", "PSYC", "1110", "PSYC 1110", "050",
  "Introduction to Psychology",            "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  20L, 20L, 25L, 5L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60007", 202060L, "60007", "BIOL", "1140", "BIOL 1140", "050",
  "Biology for Non-Majors",                "1",  "ABQ", "STEM", "BIOL",
  "INS005", "Rodriguez, Maria",
  16L, 16L, 25L, 9L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60008", 202060L, "60008", "NURS", "2010", "NURS 2010", "050",
  "Foundations of Nursing",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  18L, 18L, 20L, 2L,
  "A", "MOPS", "lower", "SU",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60009", 202060L, "60009", "NURS", "3020", "NURS 3020", "050",
  "Adult Health Nursing I",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  16L, 16L, 20L, 4L,
  "A", "MOPS", "upper", "SU",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60010", 202060L, "60010", "MGMT", "2010", "MGMT 2010", "050",
  "Principles of Management",              "1",  "ABQ", "BUS",  "MGMT",
  "INS007", "Davis, Robert",
  14L, 14L, 20L, 6L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60011", 202060L, "60011", "ENGL", "1110", "ENGL 1110", "050",
  "Composition I",                         "1H", "EA",  "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  16L, 16L, 20L, 4L,
  "A", "ENH", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60012", 202060L, "60012", "POLS", "1110", "POLS 1110", "050",
  "Introduction to Political Science",     "1",  "GA",  "SOSC", "POLS",
  "INS009", "Wilson, Brian",
  18L, 18L, 25L, 7L,
  "A", "ONL", "lower", "SU",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  # --- Cancelled 202060 (2) ---
  "S60C01", 202060L, "60901", "ANTH", "3500", "ANTH 3500", "050",
  "Archaeological Field Methods",          "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  0L, 0L, 20L, 20L,
  "C", "ENH", "upper", "SU",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  "S60C02", 202060L, "60902", "CHEM", "1215", "CHEM 1215", "050",
  "General Chemistry I",                   "1",  "EA",  "STEM", "CHEM",
  "INS005", "Rodriguez, Maria",
  0L, 0L, 24L, 24L,
  "C", "ENH", "lower", "SU",
  0L, 0L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-06-01"), as.Date("2020-07-31"),

  # --- 202080 (Fall 2020) — 14 active ---
  "S80001", 202080L, "80001", "HIST", "1110", "HIST 1110", "080",
  "History of the Western World",          "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  22L, 22L, 25L, 3L,
  "A", "ENH", "lower", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80002", 202080L, "80002", "HIST", "327",  "HIST 327",  "080",
  "Modern European History",               "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  20L, 20L, 28L, 8L,
  "A", "ENH", "upper", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80003", 202080L, "80003", "HIST", "490",  "HIST 490",  "080",
  "Senior Seminar in History",             "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  12L, 12L, 20L, 8L,
  "A", "ONL", "upper", "FA",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80004", 202080L, "80004", "HIST", "601",  "HIST 601",  "080",
  "Graduate Colloquium in History",        "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  10L, 10L, 15L, 5L,
  "A", "ENH", "grad", "FA",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80005", 202080L, "80005", "MATH", "1215Z","MATH 1215Z","080",
  "College Algebra with Lab",              "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  30L, 30L, 35L, 5L,
  "A", "ENH", "lower", "FA",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80006", 202080L, "80006", "MATH", "1430", "MATH 1430", "080",
  "Calculus I",                            "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  30L, 30L, 35L, 5L,
  "A", "ENH", "lower", "FA",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80007", 202080L, "80007", "ANTH", "2175", "ANTH 2175", "080",
  "World Cultures",                        "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  35L, 35L, 70L, 35L,
  "A", "ENH", "lower", "FA",
  0L, 10L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80008", 202080L, "80008", "ANTH", "1140", "ANTH 1140", "080",
  "Introduction to Anthropology",          "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  25L, 25L, 35L, 10L,
  "A", "ONL", "lower", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80009", 202080L, "80009", "PSYC", "1110", "PSYC 1110", "080",
  "Introduction to Psychology",            "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  22L, 22L, 30L, 8L,
  "A", "ONL", "lower", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80010", 202080L, "80010", "NURS", "2010", "NURS 2010", "080",
  "Foundations of Nursing",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  24L, 24L, 25L, 1L,
  "A", "ENH", "lower", "FA",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80011", 202080L, "80011", "NURS", "3020", "NURS 3020", "080",
  "Adult Health Nursing I",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  20L, 20L, 24L, 4L,
  "A", "ENH", "upper", "FA",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80012", 202080L, "80012", "MGMT", "2010", "MGMT 2010", "080",
  "Principles of Management",              "1",  "EA",  "BUS",  "MGMT",
  "INS007", "Davis, Robert",
  18L, 18L, 25L, 7L,
  "A", "ONL", "lower", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80013", 202080L, "80013", "ENGL", "1110", "ENGL 1110", "080",
  "Composition I",                         "1H", "ABQ", "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  21L, 21L, 24L, 3L,
  "A", "ENH", "lower", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-10-09"),

  "S80014", 202080L, "80014", "ENGL", "1110", "ENGL 1110", "081",
  "Composition I",                         "2H", "ABQ", "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  19L, 19L, 24L, 5L,
  "A", "ENH", "lower", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-10-12"), as.Date("2020-12-11"),

  # --- Cancelled 202080 (2) ---
  "S80C01", 202080L, "80901", "ANTH", "3500", "ANTH 3500", "080",
  "Archaeological Field Methods",          "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  0L, 0L, 20L, 20L,
  "C", "ENH", "upper", "FA",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  "S80C02", 202080L, "80902", "PSYC", "3200", "PSYC 3200", "080",
  "Abnormal Psychology",                   "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  0L, 0L, 25L, 25L,
  "C", "ONL", "upper", "FA",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  # --- 202110 (Spring 2021) — 16 active ---
  "S11001", 202110L, "11001", "HIST", "1110", "HIST 1110", "110",
  "History of the Western World",          "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  19L, 19L, 25L, 6L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11002", 202110L, "11002", "HIST", "327",  "HIST 327",  "110",
  "Modern European History",               "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  22L, 22L, 28L, 6L,
  "A", "ENH", "upper", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11003", 202110L, "11003", "HIST", "490",  "HIST 490",  "110",
  "Senior Seminar in History",             "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  14L, 14L, 20L, 6L,
  "A", "ONL", "upper", "SP",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11004", 202110L, "11004", "HIST", "601",  "HIST 601",  "110",
  "Graduate Colloquium in History",        "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  8L, 8L, 15L, 7L,
  "A", "ENH", "grad", "SP",
  0L, 3L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11005", 202110L, "11005", "MATH", "1215Z","MATH 1215Z","110",
  "College Algebra with Lab",              "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  32L, 32L, 35L, 3L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11006", 202110L, "11006", "MATH", "1430", "MATH 1430", "110",
  "Calculus I",                            "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  26L, 26L, 35L, 9L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11007", 202110L, "11007", "MATH", "1430", "MATH 1430", "111",
  "Calculus I",                            "1",  "EA",  "STEM", "MATH",
  "INS002", "Chen, David",
  20L, 20L, 35L, 15L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11008", 202110L, "11008", "ANTH", "2175", "ANTH 2175", "110",
  "World Cultures",                        "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  21L, 21L, 70L, 49L,
  "A", "ENH", "lower", "SP",
  0L, 10L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11009", 202110L, "11009", "ANTH", "1140", "ANTH 1140", "110",
  "Introduction to Anthropology",          "1",  "ABQ", "SOSC", "ANTH",
  "INS003", "Williams, Patricia",
  28L, 28L, 35L, 7L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11010", 202110L, "11010", "PSYC", "1110", "PSYC 1110", "110",
  "Introduction to Psychology",            "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  24L, 24L, 30L, 6L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11011", 202110L, "11011", "BIOL", "1140", "BIOL 1140", "110",
  "Biology for Non-Majors",                "1",  "ABQ", "STEM", "BIOL",
  "INS005", "Rodriguez, Maria",
  22L, 22L, 30L, 8L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11012", 202110L, "11012", "NURS", "2010", "NURS 2010", "110",
  "Foundations of Nursing",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  20L, 20L, 25L, 5L,
  "A", "MOPS", "lower", "SP",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11013", 202110L, "11013", "NURS", "3020", "NURS 3020", "110",
  "Adult Health Nursing I",                "NF", "ABQ", "NURS", "NURS",
  "INS006", "Johnson, Lisa",
  18L, 18L, 24L, 6L,
  "A", "MOPS", "upper", "SP",
  0L, 3L, FALSE, FALSE, 4.0, 4.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11014", 202110L, "11014", "MGMT", "2010", "MGMT 2010", "110",
  "Principles of Management",              "1",  "EA",  "BUS",  "MGMT",
  "INS007", "Davis, Robert",
  16L, 16L, 25L, 9L,
  "A", "ONL", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11015", 202110L, "11015", "ENGL", "1110", "ENGL 1110", "110",
  "Composition I",                         "1H", "ABQ", "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  20L, 20L, 24L, 4L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-03-19"),

  "S11016", 202110L, "11016", "ENGL", "1110", "ENGL 1110", "111",
  "Composition I",                         "2H", "EA",  "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  18L, 18L, 24L, 6L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-03-22"), as.Date("2021-05-14"),

  # --- Cancelled 202110 (2) ---
  "S11C01", 202110L, "11901", "HIST", "395",  "HIST 395",  "110",
  "Topics in History",                     "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  0L, 0L, 20L, 20L,
  "C", "ENH", "upper", "SP",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  "S11C02", 202110L, "11902", "PSYC", "3200", "PSYC 3200", "110",
  "Abnormal Psychology",                   "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  0L, 0L, 25L, 25L,
  "C", "ONL", "upper", "SP",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  # --- Variety rows: edge cases not present in base sections ---

  # SVAR01 — status="R" (removed): validates non-C cancelled status handling
  "SVAR01", 202080L, "80951", "HIST", "200",  "HIST 200",  "080",
  "Introduction to Historical Methods",    "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  0L, 0L, 25L, 25L,
  "R", "ENH", "lower", "FA",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  # SVAR02 — status="S" (suspended): validates non-A/non-C status handling
  "SVAR02", 202110L, "11953", "MATH", "300",  "MATH 300",  "110",
  "Mathematical Foundations",              "1",  "ABQ", "STEM", "MATH",
  "INS002", "Chen, David",
  0L, 0L, 30L, 30L,
  "S", "ENH", "lower", "SP",
  0L, 0L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14"),

  # SVAR03 — delivery_method=NA: real data has ~75 rows with no delivery code
  "SVAR03", 202010L, "10951", "PSYC", "2210", "PSYC 2210", "001",
  "Research Methods in Psychology",        "1",  "ABQ", "SOSC", "PSYC",
  "INS004", "Thompson, James",
  18L, 18L, 25L, 7L,
  "A", NA_character_, "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-01-13"), as.Date("2020-05-08"),

  # SVAR04 — is_topics=TRUE: course_title starts with "T:" (Banner rotating-topics convention)
  "SVAR04", 202080L, "80952", "HIST", "395",  "HIST 395",  "081",
  "T: Black Sports History",               "1",  "ABQ", "ARTS", "HIST",
  "INS001", "Morgan, Rachel",
  15L, 15L, 25L, 10L,
  "A", "ENH", "upper", "FA",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2020-08-17"), as.Date("2020-12-11"),

  # SVAR05 — part_term=NA: real data has 1 row with no sub-term code
  "SVAR05", 202110L, "11952", "ENGL", "2210", "ENGL 2210", "110",
  "Intermediate Composition",              NA_character_, "ABQ", "ARTS", "ENGL",
  "INS008", "Martinez, Anna",
  16L, 16L, 25L, 9L,
  "A", "ENH", "lower", "SP",
  0L, 5L, FALSE, FALSE, 3.0, 3.0,
  as.Date("2021-01-19"), as.Date("2021-05-14")
)

# Add columns present in real cedar_sections that are NA or derived for non-XL sections.
# Also fixes crosslist_primary: non-crosslisted sections are always TRUE.
cedar_sections <- cedar_sections %>%
  dplyr::mutate(
    crosslist_primary  = TRUE,                # non-XL sections are always primary (override tribble FALSE)
    crosslist_group    = NA_character_,       # NA for non-crosslisted
    crosslist_code     = NA_character_,       # NA for non-crosslisted
    crosslist_role     = NA_character_,       # NA for non-crosslisted
    crosslist_external = NA,                  # NA for non-crosslisted
    crosslist_partners = NA_character_,       # NA for non-crosslisted
    split_sections     = NA_character_,       # NA for non-split
    is_combined        = FALSE,                # TRUE only for C-suffix courses; added in XL block
    is_topics          = grepl("^T:", course_title),  # TRUE when title starts "T:" (Banner convention)
    job_cat            = NA_character_,       # from HR merge; NA in designed data
    gen_ed_area        = NA_integer_,         # gen ed area code; NA in designed data
    as_of_date         = as.Date(dplyr::case_when(
      term == 202010L ~ "2020-01-13",
      term == 202060L ~ "2020-06-01",
      term == 202080L ~ "2020-08-17",
      term == 202110L ~ "2021-01-19"
    ))
  )

# =============================================================================
# CEDAR_SECTIONS_XL — crosslist/split scenario fixture
# =============================================================================
# Five explicit crosslist/split scenarios for test-crosslist-split.R.
# All sections use term 202010L (Spring 2020) and status "A".
#
# Column order matches cedar_sections after the mutate above.

cedar_sections_xl <- tribble(
  ~section_id,        ~term,    ~crn,    ~subject, ~course_number, ~subject_course, ~section,
  ~course_title,      ~part_term, ~campus, ~college, ~department,
  ~instructor_id,     ~instructor_name,
  ~enrolled, ~total_enrl, ~capacity, ~available,
  ~status, ~delivery_method, ~level, ~term_type,
  ~waitlist_count, ~waitlist_capacity,
  ~crosslist_primary, ~is_split,
  ~credits_min, ~credits_max, ~start_date, ~end_date,
  ~crosslist_code, ~crosslist_group, ~crosslist_role,
  ~crosslist_external, ~crosslist_partners, ~split_sections,
  ~is_combined, ~is_topics, ~job_cat, ~gen_ed_area, ~as_of_date,

  # --- XL01: HIST 480 (primary, 12 enrolled) + ANTH 480 (partner, 0) ---
  # Cross-dept (HIST+ANTH), same level (upper), non-split.
  # primary determined by enrollment (HIST>ANTH).
  "XL0101", 202010L, "XL001", "HIST","480","HIST 480","001",
  "Advanced Topics in History",      "1","ABQ","ARTS","HIST",
  "INS001","Morgan, Rachel",
  12L,12L,20L, 8L,
  "A","ENH","upper","SP",
  0L,5L,
  TRUE,  FALSE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL01","XL01","home",
  TRUE,"ANTH 480 / HIST 480",NA_character_,
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  "XL0102", 202010L, "XL002", "ANTH","480","ANTH 480","001",
  "Advanced Topics in Anthropology", "1","ABQ","SOSC","ANTH",
  "INS003","Williams, Patricia",
  0L,12L,20L,20L,
  "A","ENH","upper","SP",
  0L,5L,
  FALSE, FALSE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL01","XL01","partner",
  TRUE,"ANTH 480 / HIST 480",NA_character_,
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  # --- XL02: HIST 484 (upper, primary) + HIST 584 (grad, partner) ---
  # Same dept (HIST+HIST), split-level (upper+grad), internal (not external).
  # primary determined by enrollment (484>584).
  "XL0201", 202010L, "XL003", "HIST","484","HIST 484","001",
  "History Methods Seminar",         "1","ABQ","ARTS","HIST",
  "INS001","Morgan, Rachel",
  8L,11L,20L,12L,
  "A","ENH","upper","SP",
  0L,5L,
  TRUE,  TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL02","XL02","home",
  FALSE,NA_character_,"HIST 484 / HIST 584",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  "XL0202", 202010L, "XL004", "HIST","584","HIST 584","001",
  "History Methods Seminar (Grad)",  "1","ABQ","ARTS","HIST",
  "INS001","Morgan, Rachel",
  3L,11L,15L,12L,
  "A","ENH","grad","SP",
  0L,3L,
  FALSE, TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL02","XL02","partner",
  FALSE,NA_character_,"HIST 484 / HIST 584",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  # --- XL03: AMST 499 (upper, partner) + AMST 599 (grad, primary) ---
  # Same dept (AMST+AMST), split-level. grad section is primary (has enrollment).
  "XL0301", 202010L, "XL005", "AMST","499","AMST 499","001",
  "American Studies Capstone",       "1","ABQ","ARTS","AMST",
  "INS001","Morgan, Rachel",
  0L, 5L,20L,20L,
  "A","ENH","upper","SP",
  0L,5L,
  FALSE, TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL03","XL03","partner",
  FALSE,NA_character_,"AMST 499 / AMST 599",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  "XL0302", 202010L, "XL006", "AMST","599","AMST 599","001",
  "American Studies Seminar (Grad)", "1","ABQ","ARTS","AMST",
  "INS001","Morgan, Rachel",
  5L, 5L,15L,10L,
  "A","ENH","grad","SP",
  0L,3L,
  TRUE,  TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL03","XL03","home",
  FALSE,NA_character_,"AMST 499 / AMST 599",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  # --- XL04: ANTH 490 (primary by alpha) + HIST 490 (partner) ---
  # Cross-dept, same level (upper), non-split, both 0 enrolled.
  # primary = ANTH because "ANTH" < "HIST" alphabetically (tiebreak rule).
  "XL0401", 202010L, "XL007", "ANTH","490","ANTH 490","001",
  "Archaeological Research Methods", "1","ABQ","SOSC","ANTH",
  "INS003","Williams, Patricia",
  0L, 0L,20L,20L,
  "A","ENH","upper","SP",
  0L,5L,
  TRUE,  FALSE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL04","XL04","home",
  TRUE,"ANTH 490 / HIST 490",NA_character_,
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  "XL0402", 202010L, "XL008", "HIST","490","HIST 490","001",
  "Historical Research Methods",     "1","ABQ","ARTS","HIST",
  "INS001","Morgan, Rachel",
  0L, 0L,20L,20L,
  "A","ENH","upper","SP",
  0L,5L,
  FALSE, FALSE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL04","XL04","partner",
  TRUE,"ANTH 490 / HIST 490",NA_character_,
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  # --- XL05: HIST 475 (primary) + AMST 475 (partner) + HIST 575 (partner) ---
  # Cross-dept (HIST+AMST), three-way, split-level (upper+upper+grad).
  # primary = HIST 475 (highest enrollment).
  "XL0501", 202010L, "XL009", "HIST","475","HIST 475","001",
  "Issues in Modern History",        "1","ABQ","ARTS","HIST",
  "INS001","Morgan, Rachel",
  10L,10L,20L,10L,
  "A","ENH","upper","SP",
  0L,5L,
  TRUE,  TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL05","XL05","home",
  TRUE,"AMST 475 / HIST 475 / HIST 575","AMST 475 / HIST 475 / HIST 575",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  "XL0502", 202010L, "XL010", "AMST","475","AMST 475","001",
  "Issues in American Studies",      "1","ABQ","ARTS","AMST",
  "INS001","Morgan, Rachel",
  0L,10L,20L,20L,
  "A","ENH","upper","SP",
  0L,5L,
  FALSE, TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL05","XL05","partner",
  TRUE,"AMST 475 / HIST 475 / HIST 575","AMST 475 / HIST 475 / HIST 575",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  "XL0503", 202010L, "XL011", "HIST","575","HIST 575","001",
  "Issues in Modern History (Grad)", "1","ABQ","ARTS","HIST",
  "INS001","Morgan, Rachel",
  0L,10L,15L,15L,
  "A","ENH","grad","SP",
  0L,3L,
  FALSE, TRUE,
  3.0,3.0, as.Date("2020-01-13"),as.Date("2020-05-08"),
  "XL05","XL05","partner",
  TRUE,"AMST 475 / HIST 475 / HIST 575","AMST 475 / HIST 475 / HIST 575",
  FALSE,FALSE,NA_character_,NA_integer_,as.Date("2020-01-13"),

  # --- XL06: ANTH 2190C — combined lecture+lab (3 CRNs, 1 crosslist group) ---
  # Mimics the real ANTH 2190C that caused Keith's enrollment bug.
  # Three lab section CRNs sharing one crosslist group. Each has enrolled = per-lab
  # count (16, 16, 15) but total_enrl = 47 (correct course-level enrollment).
  # Only CRN XL012 is crosslist_primary.
  # Without the combined-course correction in get_enrl(), the primary CRN's
  # enrolled (16) would be used instead of total_enrl (47).
  "XL0601", 202080L, "XL012", "ANTH","2190C","ANTH 2190C","002",
  "Forensic Anthropology",           "1","ABQ","SOSC","ANTH",
  "INS003","Williams, Patricia",
  16L,47L,48L,1L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE,  FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "XL06","XL06","home",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "XL0602", 202080L, "XL013", "ANTH","2190C","ANTH 2190C","003",
  "Forensic Anthropology",           "1","ABQ","SOSC","ANTH",
  "INS003","Williams, Patricia",
  16L,47L,48L,1L,
  "A","ENH","lower","FA",
  0L,0L,
  FALSE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "XL06","XL06","partner",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "XL0603", 202080L, "XL014", "ANTH","2190C","ANTH 2190C","004",
  "Forensic Anthropology",           "1","ABQ","SOSC","ANTH",
  "INS003","Williams, Patricia",
  15L,47L,48L,1L,
  "A","ENH","lower","FA",
  0L,0L,
  FALSE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "XL06","XL06","partner",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  # --- EC-04: BIOL 2110C — Pattern A non-crosslisted combined course (XL_ENRL present) ---
  # 4 lab CRNs, no crosslist_group. Banner populates XL_ENRL = 89 (course total) on
  # every lab row, so total_enrl=89 while enrolled holds per-lab count (22/22/23/22).
  # Without correction + dedup: C-course fix sets enrolled=89 per row → sum = 4×89 = 356.
  # With fix: dedup to 1 row, enrolled = 89.
  "EC-202080-A01", 202080L, "ECA01", "BIOL","2110C","BIOL 2110C","001",
  "Intro Biology Lab",         "1","ABQ","AS","BIOL",
  "INS004","Lab, Instructor",
  22L,89L,25L,3L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-A02", 202080L, "ECA02", "BIOL","2110C","BIOL 2110C","002",
  "Intro Biology Lab",         "1","ABQ","AS","BIOL",
  "INS004","Lab, Instructor",
  22L,89L,25L,3L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-A03", 202080L, "ECA03", "BIOL","2110C","BIOL 2110C","003",
  "Intro Biology Lab",         "1","ABQ","AS","BIOL",
  "INS004","Lab, Instructor",
  23L,89L,25L,2L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-A04", 202080L, "ECA04", "BIOL","2110C","BIOL 2110C","004",
  "Intro Biology Lab",         "1","ABQ","AS","BIOL",
  "INS004","Lab, Instructor",
  22L,89L,25L,3L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  # --- EC-05: BIOL 304C — Pattern B non-crosslisted combined course (no XL_ENRL) ---
  # 4 lab CRNs, no crosslist_group. XL_ENRL absent → total_enrl = enrolled (per-lab).
  # Natural sum (25+22+22+20=89) is already correct. Dedup must NOT fire here —
  # it would discard sections and show only the first lab's count (25).
  "EC-202080-B01", 202080L, "ECB01", "BIOL","304C","BIOL 304C","001",
  "Organismal Physiology Lab", "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  25L,25L,26L,1L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-B02", 202080L, "ECB02", "BIOL","304C","BIOL 304C","002",
  "Organismal Physiology Lab", "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  22L,22L,26L,4L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-B03", 202080L, "ECB03", "BIOL","304C","BIOL 304C","003",
  "Organismal Physiology Lab", "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  22L,22L,26L,4L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-B04", 202080L, "ECB04", "BIOL","304C","BIOL 304C","004",
  "Organismal Physiology Lab", "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  20L,20L,26L,6L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  NA_character_,NA_character_,NA_character_,
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  # --- EC-06: BIOL 300C — Pattern C internal crosslist combined course ---
  # 2 internal crosslist groups, 3 CRNs each (1 lecture + 2 labs).
  # Group 6G: enrolled = 0/45/47, sum = 92 = total_enrl (all rows).
  # Group 62: enrolled = 0/68/70, sum = 138 = total_enrl (all rows).
  # Individual rows have total_enrl > enrolled, which would falsely trigger
  # Pattern A. The fix must exclude internal-crosslist rows from the tag.
  # Correct result: natural sum = 92 + 138 = 230.
  "EC-202080-C01", 202080L, "ECC01", "BIOL","300C","BIOL 300C","001",
  "Organismal Physiology",     "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  0L,92L,100L,100L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "6G","6G","internal",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-C02", 202080L, "ECC02", "BIOL","300C","BIOL 300C","002",
  "Organismal Physiology",     "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  45L,92L,50L,5L,
  "A","ENH","lower","FA",
  0L,0L,
  FALSE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "6G","6G","internal",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-C03", 202080L, "ECC03", "BIOL","300C","BIOL 300C","003",
  "Organismal Physiology",     "1","ABQ","AS","BIOL",
  "INS005","Physio, Instructor",
  47L,92L,50L,3L,
  "A","ENH","lower","FA",
  0L,0L,
  FALSE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "6G","6G","internal",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-C04", 202080L, "ECC04", "BIOL","300C","BIOL 300C","004",
  "Organismal Physiology",     "1","ABQ","AS","BIOL",
  "INS006","Physio2, Instructor",
  0L,138L,150L,150L,
  "A","ENH","lower","FA",
  0L,0L,
  TRUE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "62","62","internal",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-C05", 202080L, "ECC05", "BIOL","300C","BIOL 300C","005",
  "Organismal Physiology",     "1","ABQ","AS","BIOL",
  "INS006","Physio2, Instructor",
  68L,138L,70L,2L,
  "A","ENH","lower","FA",
  0L,0L,
  FALSE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "62","62","internal",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17"),

  "EC-202080-C06", 202080L, "ECC06", "BIOL","300C","BIOL 300C","006",
  "Organismal Physiology",     "1","ABQ","AS","BIOL",
  "INS006","Physio2, Instructor",
  70L,138L,70L,0L,
  "A","ENH","lower","FA",
  0L,0L,
  FALSE, FALSE,
  4.0,4.0, as.Date("2020-08-17"),as.Date("2020-12-12"),
  "62","62","internal",
  FALSE,NA_character_,NA_character_,
  TRUE,FALSE,NA_character_,NA_integer_,as.Date("2020-08-17")
)

# Merge XL sections into the main table. In production, crosslisted sections live
# alongside regular sections in cedar_sections — there is no separate XL table.
# Tests that exercise crosslist logic filter from test_sections directly.
cedar_sections <- dplyr::bind_rows(cedar_sections, cedar_sections_xl)
rm(cedar_sections_xl)

# =============================================================================
# CEDAR_SECTIONS_SF — seatfinder year-over-year comparison fixture
# =============================================================================
# Separate from cedar_sections (exposed as test_sections_sf in setup.R).
# Used exclusively by test-seatfinder.R for get_courses_diff / get_courses_common.
#
# Spring 2024 (202410) vs Spring 2025 (202510):
#   Discontinued: PHYS 1010 (in 202410 only) → result$prev = 1 row
#   New:          MATH 1220 (in 202510 only) → result$new  = 1 row
#   Common (4):   HIST 1110, HIST 1120, MATH 1215, ANTH 1110
#   Enrollment changes → 202510 vs 202410:
#     HIST 1110: 25 − 22 = +3
#     MATH 1215: 35 − 30 = +5
#     ANTH 1110: 40 − 38 = +2
#   202510 has 5 active courses total (all statuses A).
#
# Fall 2024 (202480) vs Fall 2025 (202580):
#   Discontinued: CHEM 1010 (in 202480 only) → result$prev = 1 row
#   New:          ANTH 2050 (in 202580 only, active) → result$new = 1 row
#   Cancelled (not new): MATH 4310 in 202580 with status="C" — excluded
#   Common (2):   HIST 3010, MATH 3140
#   Enrollment changes → 202580 vs 202480:
#     HIST 3010: 22 − 20 = +2
#     MATH 3140: 15 − 12 = +3
#
cedar_sections_sf <- tibble::tibble(
  section_id       = c("SF10001","SF10002","SF10003","SF10004","SF10005",
                       "SF20001","SF20002","SF20003","SF20004","SF20005",
                       "SF30001","SF30002","SF30003",
                       "SF40001","SF40002","SF40003","SF40004"),
  term             = c(202410L,202410L,202410L,202410L,202410L,
                       202510L,202510L,202510L,202510L,202510L,
                       202480L,202480L,202480L,
                       202580L,202580L,202580L,202580L),
  crn              = c("40001","40002","40003","40004","40005",
                       "50001","50002","50003","50004","50005",
                       "48001","48002","48003",
                       "58001","58002","58003","58004"),
  subject          = c("PHYS","HIST","HIST","MATH","ANTH",
                       "HIST","HIST","MATH","ANTH","MATH",
                       "CHEM","HIST","MATH",
                       "HIST","MATH","MATH","ANTH"),
  course_number    = c("1010","1110","1120","1215","1110",
                       "1110","1120","1215","1110","1220",
                       "1010","3010","3140",
                       "3010","3140","4310","2050"),
  subject_course   = c("PHYS 1010","HIST 1110","HIST 1120","MATH 1215","ANTH 1110",
                       "HIST 1110","HIST 1120","MATH 1215","ANTH 1110","MATH 1220",
                       "CHEM 1010","HIST 3010","MATH 3140",
                       "HIST 3010","MATH 3140","MATH 4310","ANTH 2050"),
  section          = rep("001", 17),
  course_title     = c("Intro to Physics","History of the Western World","History of the Americas",
                       "Introduction to Statistics","Human Origins",
                       "History of the Western World","History of the Americas",
                       "Introduction to Statistics","Human Origins","Precalculus",
                       "Chemistry for Non-Majors","History of New Mexico","Linear Algebra",
                       "History of New Mexico","Linear Algebra","Abstract Algebra",
                       "New World Archaeology"),
  part_term        = rep("1", 17),
  campus           = rep("ABQ", 17),
  college          = c("STEM","ARTS","ARTS","STEM","SOSC",
                       "ARTS","ARTS","STEM","SOSC","STEM",
                       "STEM","ARTS","STEM",
                       "ARTS","STEM","STEM","SOSC"),
  department       = c("PHYS","HIST","HIST","MATH","ANTH",
                       "HIST","HIST","MATH","ANTH","MATH",
                       "CHEM","HIST","MATH",
                       "HIST","MATH","MATH","ANTH"),
  instructor_id    = c("INS010","INS001","INS001","INS002","INS003",
                       "INS001","INS001","INS002","INS003","INS002",
                       "INS009","INS001","INS002",
                       "INS001","INS002","INS002","INS003"),
  instructor_name  = c("Davis, Robert","Morgan, Rachel","Morgan, Rachel",
                       "Chen, David","Williams, Patricia",
                       "Morgan, Rachel","Morgan, Rachel","Chen, David",
                       "Williams, Patricia","Chen, David",
                       "Brown, Kevin","Morgan, Rachel","Chen, David",
                       "Morgan, Rachel","Chen, David","Chen, David",
                       "Williams, Patricia"),
  enrolled         = c(20L,22L,18L,30L,38L,
                       25L,20L,35L,40L,22L,
                       18L,20L,12L,
                       22L,15L,0L,15L),
  total_enrl       = c(20L,22L,18L,30L,38L,
                       25L,20L,35L,40L,22L,
                       18L,20L,12L,
                       22L,15L,0L,15L),
  capacity         = c(25L,30L,25L,35L,45L,
                       30L,25L,40L,45L,30L,
                       25L,25L,20L,
                       25L,20L,20L,25L),
  available        = c(5L,8L,7L,5L,7L,
                       5L,5L,5L,5L,8L,
                       7L,5L,8L,
                       3L,5L,20L,10L),
  # available = capacity - enrolled (verified above)
  status           = c("A","A","A","A","A",
                       "A","A","A","A","A",
                       "A","A","A",
                       "A","A","C","A"),  # MATH 4310 is cancelled
  delivery_method  = c("ENH","ENH","ENH","ENH","ONL",
                       "ENH","ENH","ENH","ONL","ENH",
                       "ENH","ENH","ENH",
                       "ENH","ENH","ENH","ONL"),
  level            = c("lower","lower","lower","lower","lower",
                       "lower","lower","lower","lower","lower",
                       "lower","upper","upper",
                       "upper","upper","upper","lower"),
  term_type        = c("SP","SP","SP","SP","SP",
                       "SP","SP","SP","SP","SP",
                       "FA","FA","FA",
                       "FA","FA","FA","FA"),
  is_combined      = rep(FALSE, 17),
  waitlist_count   = rep(0L, 17),
  waitlist_capacity = rep(5L, 17),
  crosslist_primary = rep(TRUE, 17),
  is_split         = rep(FALSE, 17),
  credits_min      = rep(3.0, 17),
  credits_max      = rep(3.0, 17),
  start_date       = as.Date(c(rep("2024-01-15",5), rep("2025-01-13",5),
                               rep("2024-08-19",3), rep("2025-08-18",4))),
  end_date         = as.Date(c(rep("2024-05-10",5), rep("2025-05-09",5),
                               rep("2024-12-13",3), rep("2025-12-12",4))),
  crosslist_group    = NA_character_,
  crosslist_code     = NA_character_,
  crosslist_role     = NA_character_,
  crosslist_external = NA,
  crosslist_partners = NA_character_,
  split_sections     = NA_character_,
  is_topics        = FALSE,
  job_cat          = NA_character_,
  gen_ed_area      = NA_integer_,
  as_of_date       = as.Date(c(rep("2024-01-15",5), rep("2025-01-13",5),
                               rep("2024-08-19",3), rep("2025-08-18",4)))
)

# =============================================================================
# CEDAR_STUDENTS — explicit hand-coded fixture (~102 rows)
# =============================================================================
# Only HIST, MATH, ANTH, BIOL, NURS have student rows.
# PSYC, ENGL, MGMT, POLS exist only in cedar_sections (section-level tests).
# student_level uses full words: "Undergraduate" / "Graduate" (matches cedar_programs).
#
# Row purposes:
#   HIST 1110 202010 (30)  — grade test: 3A+8B+6C+2D+2F RE + 9 DW
#   HIST 327  202010 (22)  — stopout (named SP1/SP2) + DW rows for squeeze dr_all_mean
#   HIST 490  202080 (9)   — stopout return proof (SP2 re-appear in FA term)
#   HIST variety (18)      — 2 RE each: 601 grad, other terms, upper/lower coverage
#   HIST 327  202110 (3)   — squeeze: 1 DW for dr_all_mean spring baseline
#   MATH 1215Z 202010 (5)  — squeeze trigger (avail=0, lab): 2 RE + 3 DW
#   MATH 1215Z 202110 (3)  — squeeze spring baseline: 2 RE + 1 DW
#   MATH 1430  202010 (2)  — non-lab calculus variety
#   ANTH 1140  202010 (2)  — intro lower-div variety
#   ANTH 2175  202080 (2)  — large-lecture fall variety
#   ANTH 2175  202010 (62) / 202110 (21)  — bump trigger (SP, added via bind_rows below tribble)
#   BIOL 1140  202010 (2)  — BIOL dept variety
#   NURS 2010  202010 (2)  — NF part_term, MOPS delivery variety
#   NURS 3020  202010 (2)  — NF part_term, MOPS, upper-level variety

cedar_students <- tribble(
  ~enrollment_id,        ~section_id, ~student_id,           ~term,
  ~subject_course,       ~campus,     ~college,    ~department,
  ~registration_status_code, ~final_grade, ~credits, ~term_type, ~student_level,

  # ── HIST 1110 202010 — grade distribution test ──────────────────────────
  # Drives test-grades.R: dfw_pct = 13/30×100, passed=17, dfw=13 (4 RE-fail + 9 DW)
  # RE: 3A + 8B + 6C + 2D + 2F = 21 registered
  "H11-SP10-001", "S10001", "H11-SP10-001", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "H11-SP10-002", "S10001", "H11-SP10-002", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "H11-SP10-003", "S10001", "H11-SP10-003", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "H11-SP10-004", "S10001", "H11-SP10-004", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-005", "S10001", "H11-SP10-005", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-006", "S10001", "H11-SP10-006", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-007", "S10001", "H11-SP10-007", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-008", "S10001", "H11-SP10-008", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-009", "S10001", "H11-SP10-009", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-010", "S10001", "H11-SP10-010", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-011", "S10001", "H11-SP10-011", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP10-012", "S10001", "H11-SP10-012", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "SP", "Undergraduate",
  "H11-SP10-013", "S10001", "H11-SP10-013", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "SP", "Undergraduate",
  "H11-SP10-014", "S10001", "H11-SP10-014", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "SP", "Undergraduate",
  "H11-SP10-015", "S10001", "H11-SP10-015", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "SP", "Undergraduate",
  "H11-SP10-016", "S10001", "H11-SP10-016", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "SP", "Undergraduate",
  "H11-SP10-017", "S10001", "H11-SP10-017", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "SP", "Undergraduate",
  "H11-SP10-018", "S10001", "H11-SP10-018", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "D", 3.0, "SP", "Undergraduate",
  "H11-SP10-019", "S10001", "H11-SP10-019", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "D", 3.0, "SP", "Undergraduate",
  "H11-SP10-020", "S10001", "H11-SP10-020", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  "H11-SP10-021", "S10001", "H11-SP10-021", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  # DW: 9 late drops
  "H11-SP10-022", "S10001", "H11-SP10-022", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-023", "S10001", "H11-SP10-023", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-024", "S10001", "H11-SP10-024", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-025", "S10001", "H11-SP10-025", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-026", "S10001", "H11-SP10-026", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-027", "S10001", "H11-SP10-027", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-028", "S10001", "H11-SP10-028", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-029", "S10001", "H11-SP10-029", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H11-SP10-030", "S10001", "H11-SP10-030", 202010L, "HIST 1110", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",

  # ── HIST 327 202010 — stopout detection + squeeze DW baseline ───────────
  # Named IDs bridge to cedar_programs SP1/SP2 cohorts (pipeline integration).
  # SP1-005..009: B grade → pass=5, dfw=0; no 202080 enrollment → stopped_out
  # SP1-010..014: F grade → pass=0, dfw=5; stopped_out
  # SP2-001..009: A grade → pass=9; return to HIST 490 202080 → not stopped_out
  # 3 anon DW → squeeze: dr_all_mean_SP = (3 DW here + 1 DW in 202110) / 2 = 2.0
  "STU-HD-SP1-005",   "S10002", "STU-HD-SP1-005",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-006",   "S10002", "STU-HD-SP1-006",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-007",   "S10002", "STU-HD-SP1-007",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-008",   "S10002", "STU-HD-SP1-008",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-009",   "S10002", "STU-HD-SP1-009",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-010",   "S10002", "STU-HD-SP1-010",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-011",   "S10002", "STU-HD-SP1-011",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-012",   "S10002", "STU-HD-SP1-012",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-013",   "S10002", "STU-HD-SP1-013",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  "STU-HD-SP1-014",   "S10002", "STU-HD-SP1-014",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "F", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-001",   "S10002", "STU-HD-SP2-001",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-002",   "S10002", "STU-HD-SP2-002",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-003",   "S10002", "STU-HD-SP2-003",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-004",   "S10002", "STU-HD-SP2-004",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-005",   "S10002", "STU-HD-SP2-005",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-006",   "S10002", "STU-HD-SP2-006",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-007",   "S10002", "STU-HD-SP2-007",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-008",   "S10002", "STU-HD-SP2-008",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "STU-HD-SP2-009",   "S10002", "STU-HD-SP2-009",   202010L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "H327-SP10-DW-001", "S10002", "H327-SP10-DW-001", 202010L, "HIST 327", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H327-SP10-DW-002", "S10002", "H327-SP10-DW-002", 202010L, "HIST 327", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",
  "H327-SP10-DW-003", "S10002", "H327-SP10-DW-003", 202010L, "HIST 327", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",

  # ── HIST 490 202080 — stopout return (SP2 cohort) ───────────────────────
  # SP2-001..009 return to HIST 490 fall 202080 → returned_next_term=TRUE.
  # Next term after 202010 spring = 202080 fall (add_next_term_col summer=FALSE).
  "STU-HD-SP2-001-R", "S80003", "STU-HD-SP2-001",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-002-R", "S80003", "STU-HD-SP2-002",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-003-R", "S80003", "STU-HD-SP2-003",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-004-R", "S80003", "STU-HD-SP2-004",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-005-R", "S80003", "STU-HD-SP2-005",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-006-R", "S80003", "STU-HD-SP2-006",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-007-R", "S80003", "STU-HD-SP2-007",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-008-R", "S80003", "STU-HD-SP2-008",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",
  "STU-HD-SP2-009-R", "S80003", "STU-HD-SP2-009",   202080L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Undergraduate",

  # ── HIST variety — 2 RE per section ─────────────────────────────────────
  # Covers upper/lower/grad levels across all 4 terms. No filler — each pair
  # exercises a distinct section type not covered above.
  # HIST 490 202010 (upper, spring)
  "H490-SP10-001",  "S10003", "H490-SP10-001",  202010L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H490-SP10-002",  "S10003", "H490-SP10-002",  202010L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  # HIST 601 202010 (grad, spring)
  "H601-SP10-001",  "S10004", "H601-SP10-001",  202010L, "HIST 601", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Graduate",
  "H601-SP10-002",  "S10004", "H601-SP10-002",  202010L, "HIST 601", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Graduate",
  # HIST 1110 202060 (lower, summer)
  "H11-SU10-001",   "S60001", "H11-SU10-001",   202060L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SU", "Undergraduate",
  "H11-SU10-002",   "S60001", "H11-SU10-002",   202060L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SU", "Undergraduate",
  # HIST 327 202060 (upper, summer)
  "H327-SU10-001",  "S60002", "H327-SU10-001",  202060L, "HIST 327",  "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SU", "Undergraduate",
  "H327-SU10-002",  "S60002", "H327-SU10-002",  202060L, "HIST 327",  "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SU", "Undergraduate",
  # HIST 1110 202080 (lower, fall)
  "H11-FA10-001",   "S80001", "H11-FA10-001",   202080L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "FA", "Undergraduate",
  "H11-FA10-002",   "S80001", "H11-FA10-002",   202080L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "C", 3.0, "FA", "Undergraduate",
  # HIST 327 202080 (upper, fall — preserves 14-course HIST coverage for calc_cl_enrls)
  "H327-FA10-001",  "S80002", "H327-FA10-001",  202080L, "HIST 327",  "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "FA", "Undergraduate",
  "H327-FA10-002",  "S80002", "H327-FA10-002",  202080L, "HIST 327",  "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "FA", "Undergraduate",
  # HIST 601 202080 (grad, fall)
  "H601-FA10-001",  "S80004", "H601-FA10-001",  202080L, "HIST 601", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Graduate",
  "H601-FA10-002",  "S80004", "H601-FA10-002",  202080L, "HIST 601", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "FA", "Graduate",
  # HIST 1110 202110 (lower, spring 2021)
  "H11-SP11-001",   "S11001", "H11-SP11-001",   202110L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H11-SP11-002",   "S11001", "H11-SP11-002",   202110L, "HIST 1110", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  # HIST 490 202110 (upper, spring 2021)
  "H490-SP11-001",  "S11003", "H490-SP11-001",  202110L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  "H490-SP11-002",  "S11003", "H490-SP11-002",  202110L, "HIST 490", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Undergraduate",
  # HIST 601 202110 (grad, spring 2021)
  "H601-SP11-001",  "S11004", "H601-SP11-001",  202110L, "HIST 601", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Graduate",
  "H601-SP11-002",  "S11004", "H601-SP11-002",  202110L, "HIST 601", "ABQ", "ARTS", "HIST", "RE", "A", 3.0, "SP", "Graduate",

  # ── HIST 327 202110 — squeeze dr_all_mean spring baseline ───────────────
  # 3 DW in 202010 + 1 DW here → dr_all_mean_SP = (3+1)/2 = 2.0
  # squeeze(202010) = avail(0) / 2.0 = 0.0 < 0.3 → flagged
  "H327-SP11-001",     "S11002", "H327-SP11-001",     202110L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H327-SP11-002",     "S11002", "H327-SP11-002",     202110L, "HIST 327", "ABQ", "ARTS", "HIST", "RE", "B", 3.0, "SP", "Undergraduate",
  "H327-SP11-DW-001",  "S11002", "H327-SP11-DW-001",  202110L, "HIST 327", "ABQ", "ARTS", "HIST", "DW", "W", 3.0, "SP", "Undergraduate",

  # ── MATH 1215Z 202010 — squeeze trigger (avail=0, lab section) ──────────
  # 3 DW → dr_all_mean_SP = (3+1)/2 = 2.0; avail=0 → squeeze = 0/2.0 = 0 < 0.3
  "MA1215-SP10-001",    "S10005", "MA1215-SP10-001",    202010L, "MATH 1215Z", "ABQ", "STEM", "MATH", "RE", "B", 4.0, "SP", "Undergraduate",
  "MA1215-SP10-002",    "S10005", "MA1215-SP10-002",    202010L, "MATH 1215Z", "ABQ", "STEM", "MATH", "RE", "C", 4.0, "SP", "Undergraduate",
  "MA1215-SP10-DW-001", "S10005", "MA1215-SP10-DW-001", 202010L, "MATH 1215Z", "ABQ", "STEM", "MATH", "DW", "W", 4.0, "SP", "Undergraduate",
  "MA1215-SP10-DW-002", "S10005", "MA1215-SP10-DW-002", 202010L, "MATH 1215Z", "ABQ", "STEM", "MATH", "DW", "W", 4.0, "SP", "Undergraduate",
  "MA1215-SP10-DW-003", "S10005", "MA1215-SP10-DW-003", 202010L, "MATH 1215Z", "ABQ", "STEM", "MATH", "DW", "W", 4.0, "SP", "Undergraduate",

  # ── MATH 1215Z 202110 — squeeze spring baseline ──────────────────────────
  "MA1215-SP11-001",    "S11005", "MA1215-SP11-001",    202110L, "MATH 1215Z", "ABQ", "STEM", "MATH", "RE", "B", 4.0, "SP", "Undergraduate",
  "MA1215-SP11-002",    "S11005", "MA1215-SP11-002",    202110L, "MATH 1215Z", "ABQ", "STEM", "MATH", "RE", "C", 4.0, "SP", "Undergraduate",
  "MA1215-SP11-DW-001", "S11005", "MA1215-SP11-DW-001", 202110L, "MATH 1215Z", "ABQ", "STEM", "MATH", "DW", "W", 4.0, "SP", "Undergraduate",

  # ── MATH 1430 202010 — non-lab calculus variety ──────────────────────────
  "MA1430-SP10-001",    "S10006", "MA1430-SP10-001",    202010L, "MATH 1430", "ABQ", "STEM", "MATH", "RE", "B", 4.0, "SP", "Undergraduate",
  "MA1430-SP10-002",    "S10006", "MA1430-SP10-002",    202010L, "MATH 1430", "ABQ", "STEM", "MATH", "RE", "C", 4.0, "SP", "Undergraduate",

  # ── ANTH 1140 202010 — intro lower-div variety ───────────────────────────
  "AN1140-SP10-001",    "S10009", "AN1140-SP10-001",    202010L, "ANTH 1140", "ABQ", "SOSC", "ANTH", "RE", "B", 3.0, "SP", "Undergraduate",
  "AN1140-SP10-002",    "S10009", "AN1140-SP10-002",    202010L, "ANTH 1140", "ABQ", "SOSC", "ANTH", "RE", "C", 3.0, "SP", "Undergraduate",

  # ── ANTH 2175 202080 — large-lecture fall variety ────────────────────────
  "AN2175-FA10-001",    "S80007", "AN2175-FA10-001",    202080L, "ANTH 2175", "ABQ", "SOSC", "ANTH", "RE", "B", 3.0, "FA", "Undergraduate",
  "AN2175-FA10-002",    "S80007", "AN2175-FA10-002",    202080L, "ANTH 2175", "ABQ", "SOSC", "ANTH", "RE", "C", 3.0, "FA", "Undergraduate",

  # ── BIOL 1140 202010 — BIOL dept variety ────────────────────────────────
  "BIO1140-SP10-001",   "S10011", "BIO1140-SP10-001",   202010L, "BIOL 1140", "ABQ", "STEM", "BIOL", "RE", "B", 3.0, "SP", "Undergraduate",
  "BIO1140-SP10-002",   "S10011", "BIO1140-SP10-002",   202010L, "BIOL 1140", "ABQ", "STEM", "BIOL", "RE", "C", 3.0, "SP", "Undergraduate",

  # ── NURS 2010 202010 — NF part_term, MOPS delivery variety ──────────────
  "NUR2010-SP10-001",   "S10012", "NUR2010-SP10-001",   202010L, "NURS 2010", "ABQ", "NURS", "NURS", "RE", "B", 4.0, "SP", "Undergraduate",
  "NUR2010-SP10-002",   "S10012", "NUR2010-SP10-002",   202010L, "NURS 2010", "ABQ", "NURS", "NURS", "RE", "B", 4.0, "SP", "Undergraduate",

  # ── NURS 3020 202010 — NF part_term, MOPS, upper-level variety ──────────
  "NUR3020-SP10-001",   "S10013", "NUR3020-SP10-001",   202010L, "NURS 3020", "ABQ", "NURS", "NURS", "RE", "B", 4.0, "SP", "Undergraduate",
  "NUR3020-SP10-002",   "S10013", "NUR3020-SP10-002",   202010L, "NURS 3020", "ABQ", "NURS", "NURS", "RE", "C", 4.0, "SP", "Undergraduate"
)

# ── ANTH 2175 spring rows for bump detection ──────────────────────────────
# Design: 62 RE in 202010 and 21 RE in 202110 (same term_type=SP).
# registered_mean=(62+21)/2=41.5, pop_sd=20.5, sd_deviation@202010=1.0,
# impacted@202010=20.5 → flags as moderate_high bump when term=202010 filtered.
cedar_students <- dplyr::bind_rows(
  cedar_students,
  tibble::tibble(
    enrollment_id            = sprintf("AN2175-SP10-%03d", 1:62),
    section_id               = "S10008",
    student_id               = sprintf("AN2175-SP10-%03d", 1:62),
    term                     = 202010L,
    subject_course           = "ANTH 2175",
    campus                   = "ABQ",
    college                  = "SOSC",
    department               = "ANTH",
    registration_status_code = "RE",
    final_grade              = "B",
    credits                  = 3.0,
    term_type                = "SP",
    student_level            = "Undergraduate"
  ),
  tibble::tibble(
    enrollment_id            = sprintf("AN2175-SP21-%03d", 1:21),
    section_id               = "S11008",
    student_id               = sprintf("AN2175-SP21-%03d", 1:21),
    term                     = 202110L,
    subject_course           = "ANTH 2175",
    campus                   = "ABQ",
    college                  = "SOSC",
    department               = "ANTH",
    registration_status_code = "RE",
    final_grade              = "B",
    credits                  = 3.0,
    term_type                = "SP",
    student_level            = "Undergraduate"
  )
)

# Add columns present in real cedar_students that are derived or NA in designed data.
cedar_students <- cedar_students %>%
  dplyr::mutate(
    crn                   = NA_character_,
    subject_code          = sub(" .*", "", subject_course),
    course_title          = NA_character_,
    level                 = dplyr::case_when(
      grepl("^[A-Z]+ [0-2][0-9]", subject_course)    ~ "lower",
      grepl("^[A-Z]+ [3-4][0-9]{2}", subject_course) ~ "upper",
      grepl("^[A-Z]+ [5-9][0-9]{2}", subject_course) ~ "grad",
      TRUE                                            ~ "unknown"
    ),
    instructor_id         = NA_character_,
    instructor_last_name  = NA_character_,
    instructor_first_name = NA_character_,
    instructor_name       = NA_character_,
    registration_status   = dplyr::if_else(
      registration_status_code == "RE", "Student Registered", "Dropped Without Penalty"
    ),
    registration_date     = as.Date(NA),
    total_credits         = NA_real_,
    student_classification = dplyr::case_when(
      student_level == "Graduate"                         ~ "Graduate",
      grepl("^[A-Z]+ [3-4][0-9]{2}", subject_course)     ~ "Junior",
      TRUE                                                ~ "Sophomore"
    ),
    major_code            = NA_character_,
    student_college       = college,
    student_campus        = campus,
    residency             = "Resident",
    dual_credit           = FALSE,
    part_term             = NA_character_,
    as_of_date            = as.Date(dplyr::case_when(
      term == 202010L ~ "2020-01-13",
      term == 202060L ~ "2020-06-01",
      term == 202080L ~ "2020-08-17",
      term == 202110L ~ "2021-01-19"
    ))
  )


# =============================================================================
# CEDAR_PROGRAMS
# =============================================================================
# Student IDs used in tests (update test constants to match these):
#   CHANGER_A     = "STU-CHANGER-A"
#   CHANGER_B     = "STU-CHANGER-B"
#   NON_CHANGER   = "STU-NON-CHANGER"
#   PSYCH_MINOR_STUDENT = "STU-PSYCH-MINOR"
#   ARCH_CONC_STUDENT   = "STU-ARCH-CONC"

# =============================================================================
# CEDAR_PROGRAMS — explicit hand-coded fixture
# =============================================================================
# student_level: "Undergraduate" / "Graduate" (matches cedar_students).
#
# HIST population design (for pathway/stopout pipeline tests):
#   202010 declared (14): SP1-001..004 (graduated), SP1-005..014 (stopped_out)
#   202010 pre-major (4):  HP-SP1-001 (Continuing), HP-SP1-002 (Transfer),
#                          HP-SP1-003 (Readmit),    HP-SP1-004 (Level Change)
#   202010 grad (2):       HGRAD-SP10-001/002 (Graduate level, HIST 601 cohort)
#   202060 declared (2):   HD-SU1-001/002
#   202060 pre-major (1):  HP-SU1-001
#   202080 declared (2):   HD-FA1-001/002
#   202080 pre-major (2):  HP-FA1-001/002
#   202110 declared (9):   SP2-001..009 (ongoing cohort — return from stopout test)
#   202110 pre-major (2):  HP-SP2-001/002
# MATH design: 2 students per term (small but enough for pathway tests with min_n=1)
# ANTH design: 3 students per term
# Outcome/pathway matrix (HIST focal):
#   ongoing    + direct     : STU-HD-SP2-001..009
#   ongoing    + switched_in: STU-ENGL-HIST-001/002
#   ongoing    + pre_major  : STU-HIST-PREDECL-001
#   graduated  + direct     : STU-HD-SP1-001..004
#   graduated  + pre_major  : STU-HIST-PREDECL-002 (DEG011)
#   switched_out + direct   : STU-HIST-SWOUT-001/002 (→POLS), STU-HIST-SWOUT-003 (→BIOL)
#   stopped_out + direct    : STU-HD-SP1-005..014 (202010 only, no degree, no later major)
#   never_declared          : STU-HP-FA1-001/002, STU-HP-SU1-001

cedar_programs <- bind_rows(

  # ── HIST declared 202010 (14: 4 will graduate, 10 will stop out) ─────────
  tibble(
    student_id             = sprintf("STU-HD-SP1-%03d", 1:14),
    term                   = 202010L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = c(rep("Continuing Student", 13), "Readmit Student"),
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.45, 3.20, 2.95, 3.60,  # SP1-001..004: graduated
                                rep(2.8, 5),              # SP1-005..009: stopped_out, pass
                                rep(2.5, 5)),             # SP1-010..014: stopped_out, dfw
    inst_credits_attempted = c(rep(90L, 4), rep(60L, 10))
  ),

  # ── HIST pre-majors 202010 (4: one of each population type) ─────────────
  tibble(
    student_id             = sprintf("STU-HP-SP1-%03d", 1:4),
    term                   = 202010L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = TRUE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = c("Continuing Student","Transfer Student","Readmit Student","Level Change"),
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(2.5, 2.3, 2.7, 2.4),
    inst_credits_attempted = c(15L, 10L, 5L, 5L)
  ),

  # ── HIST graduate students 202010 (2) ───────────────────────────────────
  # Fixes critical gap: HIST 601 enrollment rows exist but no program rows.
  # student_level "Graduate" matches cedar_students grad rows.
  tibble(
    student_id             = c("STU-HGRAD-SP10-001", "STU-HGRAD-SP10-002"),
    term                   = 202010L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-MA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = FALSE,
    student_level          = "Graduate",
    degree                 = "MA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.7, 3.5),
    inst_credits_attempted = c(12L, 18L)
  ),

  # ── HIST 202060 (2 declared + 1 pre-major) ───────────────────────────────
  tibble(
    student_id             = c("STU-HD-SU1-001","STU-HD-SU1-002","STU-HP-SU1-001"),
    term                   = 202060L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = c(FALSE, FALSE, TRUE),
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.0, 3.1, 2.6),
    inst_credits_attempted = c(45L, 45L, 10L)
  ),

  # ── HIST 202080 (2 declared + 2 pre-major; pre-majors = never_declared) ──
  tibble(
    student_id             = c("STU-HD-FA1-001","STU-HD-FA1-002",
                               "STU-HP-FA1-001","STU-HP-FA1-002"),
    term                   = 202080L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = c(FALSE, FALSE, TRUE, TRUE),
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.2, 3.0, 2.4, 2.5),
    inst_credits_attempted = c(75L, 75L, 20L, 20L)
  ),

  # ── HIST declared 202110 (9: ongoing cohort, returns from stopout test) ──
  # These are the SP2 students: enrolled HIST 327 202010, returned HIST 490 202080.
  tibble(
    student_id             = sprintf("STU-HD-SP2-%03d", 1:9),
    term                   = 202110L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = rep(3.2, 9),
    inst_credits_attempted = rep(90L, 9)
  ),

  # ── HIST pre-majors 202110 (2) ───────────────────────────────────────────
  tibble(
    student_id             = c("STU-HP-SP2-001","STU-HP-SP2-002","STU-HP-SP2-003"),
    term                   = 202110L,
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = TRUE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(2.6, 2.7, 2.5),
    inst_credits_attempted = c(12L, 12L, 12L)
  ),

  # ── MATH declared majors (2 per term) ───────────────────────────────────
  tibble(
    student_id             = c("STU-MA-001","STU-MA-002",
                               "STU-MA-011","STU-MA-012",
                               "STU-MA-021","STU-MA-022",
                               "STU-MA-031","STU-MA-032"),
    term                   = c(202010L,202010L, 202060L,202060L,
                               202080L,202080L, 202110L,202110L),
    program_type           = "Major",
    program_name           = "Mathematics",
    major_code             = "MATH-BS",
    student_college        = "STEM",
    student_campus         = "ABQ",
    dept_code              = "MATH",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BS",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.7,3.5, 3.6,3.4, 3.8,3.6, 3.9,3.7),
    inst_credits_attempted = c(45L,45L, 60L,60L, 75L,75L, 90L,90L)
  ),

  # ── ANTH declared majors (3 per term) ───────────────────────────────────
  tibble(
    student_id             = c("STU-AN-001","STU-AN-002","STU-AN-003",
                               "STU-AN-011","STU-AN-012","STU-AN-013",
                               "STU-AN-021","STU-AN-022","STU-AN-023",
                               "STU-AN-031","STU-AN-032","STU-AN-033"),
    term                   = c(rep(202010L,3), rep(202060L,3),
                               rep(202080L,3), rep(202110L,3)),
    program_type           = "Major",
    program_name           = "Anthropology",
    major_code             = "ANTH-BA",
    student_college        = "SOSC",
    student_campus         = "ABQ",
    dept_code              = "ANTH",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.1,2.9,3.2, 3.0,3.1,3.3, 3.2,3.0,3.1, 3.3,3.1,3.2),
    inst_credits_attempted = c(rep(45L,3), rep(60L,3), rep(75L,3), rep(90L,3))
  ),

  # ── Archaeology concentration (4 rows in ANTH dept) ─────────────────────
  # STU-ARCH-CONC and 3 others: in 202010 (2 students) + 202060 (1) + 202110 (1)
  tibble(
    student_id             = c("STU-ARCH-CONC","STU-AN-CON-002","STU-AN-CON-003","STU-AN-CON-004"),
    term                   = c(202010L, 202010L, 202060L, 202110L),
    program_type           = "First Concentration",
    program_name           = "Archaeology",
    major_code             = "ARCH-CONC",
    student_college        = "SOSC",
    student_campus         = "ABQ",
    dept_code              = "ANTH",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.2, 2.9, 3.1, 3.0),
    inst_credits_attempted = c(60L, 45L, 75L, 90L)
  ),

  # --- Psychology minor (10 rows): STU-PSYCH-MINOR + 4 others, each in 2 terms ---
  tibble(
    student_id             = c("STU-PSYCH-MINOR","STU-PSYCH-MINOR",
                               "STU-PM-002","STU-PM-002",
                               "STU-PM-003","STU-PM-003",
                               "STU-PM-004","STU-PM-004",
                               "STU-PM-005","STU-PM-005"),
    term                   = c(202010L, 202110L,
                               202010L, 202080L,
                               202060L, 202110L,
                               202010L, 202060L,
                               202080L, 202110L),
    program_type           = "First Minor",
    program_name           = "Psychology",
    major_code             = "PSYC-MIN",
    student_college        = "SOSC",
    student_campus         = "ABQ",
    dept_code              = "PSYC",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = NA_character_,
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = 3.1,
    inst_credits_attempted = 60L
  ),

  # --- Major changers ---

  # CHANGER_A: Political Science → Secondary Education in 202110
  tibble(
    student_id             = c("STU-CHANGER-A","STU-CHANGER-A","STU-CHANGER-A"),
    term                   = c(202010L, 202080L, 202110L),
    program_type           = "Major",
    program_name           = c("Political Science","Political Science","Secondary Education"),
    major_code             = c("POLS-BA","POLS-BA","FSEC-BS"),
    student_college        = c("SOSC","SOSC","EDU"),
    student_campus         = "ABQ",
    dept_code              = c("POLS","POLS","FSEC"),
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(2.8, 3.0, 3.1),
    inst_credits_attempted = c(100L, 150L, 185L)
  ),

  # CHANGER_B: Biology → Nursing in 202110 (prev_term = 202060)
  tibble(
    student_id             = c("STU-CHANGER-B","STU-CHANGER-B","STU-CHANGER-B"),
    term                   = c(202010L, 202060L, 202110L),
    program_type           = "Major",
    program_name           = c("Biology","Biology","Nursing"),
    major_code             = c("BIOL-BS","BIOL-BS","NURS-BS"),
    student_college        = c("STEM","STEM","NURS"),
    student_campus         = "ABQ",
    dept_code              = c("BIOL","BIOL","NURS"),
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BS",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.2, 3.3, 3.4),
    inst_credits_attempted = c(50L, 75L, 93L)
  ),

  # NON_CHANGER: Business Administration, pre-major→declared (same program_name)
  tibble(
    student_id             = rep("STU-NON-CHANGER", 4),
    term                   = c(202010L, 202060L, 202080L, 202110L),
    program_type           = "Major",
    program_name           = "Business Administration",
    major_code             = "BUSA-BBA",
    student_college        = "BUS",
    student_campus         = "ABQ",
    dept_code              = "MGMT",
    is_pre_major           = c(TRUE, FALSE, FALSE, FALSE),
    student_level          = "Undergraduate",
    degree                 = "BBA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(2.5, 2.7, 2.9, 3.0),
    inst_credits_attempted = c(30L, 45L, 60L, 75L)
  ),

  # MGMT_CHG1: Business Analytics → Business Management (within MGMT dept)
  tibble(
    student_id             = c("STU-MGMT-CHG1","STU-MGMT-CHG1"),
    term                   = c(202010L, 202080L),
    program_type           = "Major",
    program_name           = c("Business Analytics","Business Management"),
    major_code             = c("BUAN-BBA","BUMG-BBA"),
    student_college        = "BUS",
    student_campus         = "ABQ",
    dept_code              = "MGMT",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BBA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.1, 3.2),
    inst_credits_attempted = c(55L, 90L)
  ),

  # MGMT_CHG2: Accounting → Finance (within MGMT dept)
  tibble(
    student_id             = c("STU-MGMT-CHG2","STU-MGMT-CHG2"),
    term                   = c(202010L, 202080L),
    program_type           = "Major",
    program_name           = c("Accounting","Finance"),
    major_code             = c("ACCT-BBA","FINC-BBA"),
    student_college        = "BUS",
    student_campus         = "ABQ",
    dept_code              = "MGMT",
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BBA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.5, 3.6),
    inst_credits_attempted = c(48L, 96L)
  ),

  # --- HIST switched-out students (were HIST declared, now in another major at max_data_term) ---
  # Entry pathway: direct  |  Outcome: switched_out
  # STU-HIST-SWOUT-001/002: HIST → POLS (2 students; enough for a testable pair in major-changes cone)
  # STU-HIST-SWOUT-003:     HIST → BIOL (1 student)
  tibble(
    student_id             = c("STU-HIST-SWOUT-001","STU-HIST-SWOUT-001",
                               "STU-HIST-SWOUT-002","STU-HIST-SWOUT-002",
                               "STU-HIST-SWOUT-003","STU-HIST-SWOUT-003"),
    term                   = c(202010L, 202110L, 202010L, 202110L, 202010L, 202110L),
    program_type           = "Major",
    program_name           = c("History","Political Science",
                               "History","Political Science",
                               "History","Biology"),
    major_code             = c("HIST-BA","POLS-BA",
                               "HIST-BA","POLS-BA",
                               "HIST-BA","BIOL-BS"),
    student_college        = c("ARTS","SOSC","ARTS","SOSC","ARTS","STEM"),
    student_campus         = "ABQ",
    dept_code              = c("HIST","POLS","HIST","POLS","HIST","BIOL"),
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = c("BA","BA","BA","BA","BA","BS"),
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(2.8, 3.0, 2.9, 3.1, 3.0, 3.2),
    inst_credits_attempted = c(60L, 120L, 60L, 120L, 60L, 120L)
  ),

  # --- Switched-in HIST students (were ENGL declared, now HIST at max_data_term) ---
  # Entry pathway: switched_in  |  Outcome: ongoing
  # 2 students from ENGL → HIST; testable ENGL→HIST pair in major-changes cone
  tibble(
    student_id             = c("STU-ENGL-HIST-001","STU-ENGL-HIST-001",
                               "STU-ENGL-HIST-002","STU-ENGL-HIST-002"),
    term                   = c(202010L, 202110L, 202010L, 202110L),
    program_type           = "Major",
    program_name           = c("English","History","English","History"),
    major_code             = c("ENGL-BA","HIST-BA","ENGL-BA","HIST-BA"),
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = c("ENGL","HIST","ENGL","HIST"),
    is_pre_major           = FALSE,
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(3.0, 3.2, 3.1, 3.3),
    inst_credits_attempted = c(60L, 90L, 60L, 90L)
  ),

  # --- Pre-major → declared HIST students ---
  # STU-HIST-PREDECL-001: pre_major pathway, ongoing outcome
  #   202010 pre-major → 202080 declared → 202110 declared (at max_data_term)
  # STU-HIST-PREDECL-002: pre_major pathway, graduated outcome
  #   202010 pre-major → 202060 declared → degree at 202080 (see DEG011 in cedar_degrees)
  tibble(
    student_id             = c(
      "STU-HIST-PREDECL-001","STU-HIST-PREDECL-001","STU-HIST-PREDECL-001",
      "STU-HIST-PREDECL-002","STU-HIST-PREDECL-002"
    ),
    term                   = c(202010L, 202080L, 202110L, 202010L, 202060L),
    program_type           = "Major",
    program_name           = "History",
    major_code             = "HIST-BA",
    student_college        = "ARTS",
    student_campus         = "ABQ",
    dept_code              = "HIST",
    is_pre_major           = c(TRUE, FALSE, FALSE, TRUE, FALSE),
    student_level          = "Undergraduate",
    degree                 = "BA",
    student_population     = "Continuing Student",
    residency              = "Resident",
    academic_standing      = "Good Standing",
    inst_gpa               = c(2.9, 3.1, 3.2, 3.0, 3.3),
    inst_credits_attempted = c(12L, 60L, 90L, 12L, 45L)
  )
)

# Add columns present in real cedar_programs that are derived or demographic.
# student_classification derived from inst_credits_attempted (UG only).
# Demographic fields (pell_eligible, first_gen, ipeds_race, gender) set to NA —
# not meaningful in designed data but needed for schema compatibility.
cedar_programs <- cedar_programs %>%
  dplyr::mutate(
    program_id = paste0(term, "-", student_id, "-", program_type),
    program_classification = dplyr::case_when(
      degree %in% c("BA", "BS") ~ "Baccalaureate",
      degree == "BBA"           ~ "Business Baccalaureate",
      degree == "MA"            ~ "Master of Arts",
      degree == "MS"            ~ "Master of Science",
      is.na(degree)             ~ NA_character_,
      TRUE                      ~ "Other"
    ),
    student_classification = dplyr::case_when(
      student_level == "Graduate"            ~ "Graduate",
      inst_credits_attempted < 30            ~ "Freshman",
      inst_credits_attempted < 60            ~ "Sophomore",
      inst_credits_attempted < 90            ~ "Junior",
      TRUE                                   ~ "Senior"
    ),
    # Banner 2-letter college code (matches COLLEGE in cedar_sections)
    college_code = dplyr::case_when(
      student_college == "ARTS" ~ "AS",
      student_college == "STEM" ~ "SC",
      student_college == "SOSC" ~ "AS",
      student_college == "NURS" ~ "NR",
      student_college == "BUS"  ~ "AD",
      student_college == "EDU"  ~ "ED",
      TRUE                      ~ NA_character_
    ),
    overall_credits_earned = as.numeric(inst_credits_attempted) * 0.9,
    pell_eligible          = NA,
    first_gen              = NA,
    ipeds_race             = NA_character_,
    gender                 = NA_character_,
    time_status            = "FT",
    as_of_date             = as.Date(dplyr::case_when(
      term == 202010L ~ "2020-01-13",
      term == 202060L ~ "2020-06-01",
      term == 202080L ~ "2020-08-17",
      term == 202110L ~ "2021-01-19"
    ))
  )


# =============================================================================
# CEDAR_DEGREES
# =============================================================================

cedar_degrees <- tribble(
  ~degree_id, ~student_id,    ~term,   ~degree, ~program_name,
  ~college,   ~department,    ~graduation_status,   ~campus,
  ~cumulative_gpa, ~cumulative_credits,

  "DEG001", "STU-HD-SP1-001", 202060L, "BA", "History",
  "ARTS",   "HIST", "Awarded",  "ABQ", 3.45, 120,

  "DEG002", "STU-HD-SP1-002", 202060L, "BA", "History",
  "ARTS",   "HIST", "Awarded",  "ABQ", 3.20, 122,

  "DEG003", "STU-MA-001",     202060L, "BS", "Mathematics",
  "STEM",   "MATH", "Awarded",  "ABQ", 3.70, 128,

  "DEG004", "STU-MA-002",     202080L, "BS", "Mathematics",
  "STEM",   "MATH", "Awarded",  "ABQ", 3.55, 130,

  "DEG005", "STU-AN-001",     202060L, "BA", "Anthropology",
  "SOSC",   "ANTH", "Awarded",  "ABQ", 3.10, 120,

  "DEG006", "STU-AN-002",     202080L, "BA", "Anthropology",
  "SOSC",   "ANTH", "Awarded",  "ABQ", 3.30, 124,

  "DEG007", "STU-HD-SP1-003", 202080L, "BA", "History",
  "ARTS",   "HIST", "Awarded",  "ABQ", 2.95, 125,

  "DEG008", "STU-MA-003",     202110L, "BS", "Mathematics",
  "STEM",   "MATH", "Pending",  "ABQ", 3.80, 128,

  "DEG009", "STU-AN-003",     202110L, "BA", "Anthropology",
  "SOSC",   "ANTH", "Pending",  "ABQ", 3.15, 121,

  "DEG010", "STU-HD-SP1-004", 202110L, "BA", "History",
  "ARTS",   "HIST", "Pending",  "ABQ", 3.60, 123,

  # DEG011: pre_major pathway, graduated outcome (STU-HIST-PREDECL-002)
  "DEG011", "STU-HIST-PREDECL-002", 202080L, "BA", "History",
  "ARTS",   "HIST", "Awarded",  "ABQ", 3.30, 120
)

# Add columns present in real cedar_degrees that are missing from the tribble.
# program_code: Banner compound code used to derive degree_abbr (e.g., "BA-HIST-AS").
# major_code: catalog key (e.g., "HIST") — matches major_dept_map$major_code.
# degree_id format fixed to match real data: term-student_id-program_code.
cedar_degrees <- cedar_degrees %>%
  dplyr::mutate(
    student_college     = college,    # student home college same as translated college here
    award_category      = dplyr::if_else(degree %in% c("BA", "BS"), "Baccalaureate", "Other"),
    program_code        = paste0(degree, "-", department, "-AS"),  # e.g., "BA-HIST-AS"
    major_code          = department,    # major code (e.g., "HIST") matches major_dept_map keys
    major               = program_name,
    second_major        = NA_character_,
    first_minor         = NA_character_,
    second_minor        = NA_character_,
    honors              = NA_character_,
    admitted_term       = term - 20L,    # rough approximation: ~2 years before degree term
    dept_code           = department,
    degree_abbr         = degree,        # "BA" or "BS" — first segment of program_code
    as_of_date          = as.Date("2021-06-01"),
    # Fix degree_id to match real format: term-student_id-program_code
    degree_id           = paste0(term, "-", student_id, "-", department)
  )


# =============================================================================
# CEDAR_FACULTY
# =============================================================================

cedar_faculty <- tribble(
  ~instructor_id, ~instructor_name,     ~term,   ~department,
  ~job_category,              ~appointment_pct, ~college,

  "INS001", "Morgan, Rachel",   202010L, "HIST", "Associate Professor", 1.0, "AS History",
  "INS002", "Chen, David",      202010L, "MATH", "Assistant Professor", 1.0, "AS Mathematics",
  "INS003", "Williams, Patricia",202010L,"ANTH", "Professor",           1.0, "AS Anthropology",
  "INS004", "Thompson, James",  202010L, "PSYC", "Lecturer",            1.0, "AS Psychology",
  "INS005", "Rodriguez, Maria", 202010L, "BIOL", "Assistant Professor", 1.0, "AS Biology",
  "INS006", "Johnson, Lisa",    202010L, "NURS", "Associate Professor", 1.0, "College of Nursing",
  "INS007", "Davis, Robert",    202010L, "MGMT", "Term Teacher",        1.0, "Anderson School",
  "INS008", "Martinez, Anna",   202010L, "ENGL", "Lecturer",            1.0, "AS English",
  "INS009", "Wilson, Brian",    202010L, "POLS", "Term Teacher",        0.5, "AS Political Science",

  "INS001", "Morgan, Rachel",   202060L, "HIST", "Associate Professor", 1.0, "AS History",
  "INS002", "Chen, David",      202060L, "MATH", "Assistant Professor", 1.0, "AS Mathematics",
  "INS003", "Williams, Patricia",202060L,"ANTH", "Professor",           1.0, "AS Anthropology",
  "INS004", "Thompson, James",  202060L, "PSYC", "Lecturer",            1.0, "AS Psychology",
  "INS005", "Rodriguez, Maria", 202060L, "BIOL", "Assistant Professor", 1.0, "AS Biology",
  "INS006", "Johnson, Lisa",    202060L, "NURS", "Associate Professor", 1.0, "College of Nursing",
  "INS007", "Davis, Robert",    202060L, "MGMT", "Term Teacher",        1.0, "Anderson School",
  "INS008", "Martinez, Anna",   202060L, "ENGL", "Lecturer",            1.0, "AS English",
  "INS009", "Wilson, Brian",    202060L, "POLS", "Term Teacher",        0.5, "AS Political Science",

  "INS001", "Morgan, Rachel",   202080L, "HIST", "Associate Professor", 1.0, "AS History",
  "INS002", "Chen, David",      202080L, "MATH", "Assistant Professor", 1.0, "AS Mathematics",
  "INS003", "Williams, Patricia",202080L,"ANTH", "Professor",           1.0, "AS Anthropology",
  "INS004", "Thompson, James",  202080L, "PSYC", "Lecturer",            1.0, "AS Psychology",
  "INS005", "Rodriguez, Maria", 202080L, "BIOL", "Assistant Professor", 1.0, "AS Biology",
  "INS006", "Johnson, Lisa",    202080L, "NURS", "Associate Professor", 1.0, "College of Nursing",
  "INS007", "Davis, Robert",    202080L, "MGMT", "Term Teacher",        1.0, "Anderson School",
  "INS008", "Martinez, Anna",   202080L, "ENGL", "Lecturer",            1.0, "AS English",

  "INS001", "Morgan, Rachel",   202110L, "HIST", "Associate Professor", 1.0, "AS History",
  "INS002", "Chen, David",      202110L, "MATH", "Assistant Professor", 1.0, "AS Mathematics",
  "INS003", "Williams, Patricia",202110L,"ANTH", "Professor",           1.0, "AS Anthropology",
  "INS004", "Thompson, James",  202110L, "PSYC", "Lecturer",            1.0, "AS Psychology",
  "INS005", "Rodriguez, Maria", 202110L, "BIOL", "Assistant Professor", 1.0, "AS Biology",
  "INS006", "Johnson, Lisa",    202110L, "NURS", "Associate Professor", 1.0, "College of Nursing",
  "INS007", "Davis, Robert",    202110L, "MGMT", "Term Teacher",        1.0, "Anderson School",
  "INS008", "Martinez, Anna",   202110L, "ENGL", "Lecturer",            1.0, "AS English"
)

# Add columns present in real cedar_faculty that are missing from the tribble.
cedar_faculty <- cedar_faculty %>%
  dplyr::mutate(
    academic_title = job_category,   # Banner academic rank; same as job_category in designed data
    job_title      = paste(job_category, "of", department),  # e.g., "Associate Professor of HIST"
    as_of_date     = as.Date(dplyr::case_when(
      term == 202010L ~ "2020-01-13",
      term == 202060L ~ "2020-06-01",
      term == 202080L ~ "2020-08-17",
      term == 202110L ~ "2021-01-19"
    ))
  )
