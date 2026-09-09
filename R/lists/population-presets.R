# CEDAR-INSTITUTION: named population groups
# population-presets.R — Named population groups, shared across CEDAR.
#
# These are NOT specific to any one tab. Pathways pre-populates its program
# selectizeInput from them; the enrollment-projection growth scenario resolves
# them to Banner major codes. Anything that needs "health professions" to mean
# one thing reads this list, so the definition cannot drift between tabs.
#
# Groups are declared as PROGRAM NAMES, not Banner codes, and resolved to codes
# against cedar_programs by population_group_major_codes() in
# R/branches/population.R. Names are the right declaration because a pre-major
# usually carries the same program_name as the major it leads to (FRAD and RADS
# are both "Radiologic Sciences"), so declared and pre-major students resolve
# together without a hand-maintained code list going stale every time Banner
# adds a variant.
#
# Where a pre-major's name has drifted from its major's, BOTH spellings are
# listed — "Medical Laboratory Science" (FMDL) beside "Medical Laboratory
# Sciences" (MEDL). population_group_audit() reports near-miss names precisely
# so that drift is found rather than silently dropped. See ISSUES.md I7.
#
# Structure of each entry:
#   programs    — character vector of program_name values
#   description — one-line description (shown as a selectize option label)

DEFAULT_MAJOR_GROUP_PROGRAMS <- c(
  "Nursing", "Family Nurse Practitioner", "Nurse Admin Leadership",
  "Nurse Midwifery", "Nursing Administration", "Nursing Education",
  "Nursing Exec. Org. Leadership", "Nursing Practice",
  "Pediatric Nurse Prac-PC PNP-PC", "Psychiatric Mental Health NP",
  "Clinical Laboratory Sciences", "Medical Laboratory Sciences",
  "Medical Laboratory Science", "Medical Lab Technology",
  "Physician Assistant Studies", "Occupational Therapy",
  "Physical Therapy", "Radiologic Sciences", "Medical Imaging",
  "Nuclear Medicine", "Dental Hygiene", "Dental Assisting",
  "Emergency Medical Services", "Emergency Med Svcs EMT-Basic",
  "Doctor of Pharmacy", "Pharmaceutical Sciences",
  "BS Pharmaceutical Sciences", "Toxicol & Pharmaceu Sciences",
  "Public Health", "Community Health", "Community Health Education",
  "Community Health Intervention", "School Health Education",
  "Maternal Child Health", "Population Health", "Health Education",
  "Health Administration", "Health Policy", "Health Policy and Admin",
  "Health Systems Svcs & Policy", "General Healthcare Admin",
  "Health Information Technology", "Biomedical Sciences",
  "Prof Health Sciences", "Health Professions",
  "Health Equity Sciences", "Health Scholars"
)

CEDAR_POPULATION_GROUPS <- list(

  "Top 10 by Enrollment" = list(
    programs = c(
      "Nursing",
      "Dental Hygiene",
      "Emergency Medical Services",
      "Doctor of Pharmacy",
      "Radiologic Sciences",
      "Medical Laboratory Sciences",
      "Population Health",
      "Biomedical Sciences",
      "Physical Therapy",
      "Nursing Practice"
    ),
    description = "Ten largest health programs by avg fall headcount (declared majors)"
  ),

  "All Health Programs" = list(
    programs    = DEFAULT_MAJOR_GROUP_PROGRAMS,
    description = "All health-related programs"
  ),

  # The licensure track: programs that produce licensed clinicians. This is the
  # group a "grow health care workers by N%" question means, and it is
  # deliberately narrower than "All Health Programs", which also counts public
  # health, health administration, and health-sciences students.
  "Health Professions (Clinical)" = list(
    programs = c(
      "Nursing", "Family Nurse Practitioner", "Nurse Admin Leadership",
      "Nurse Midwifery", "Nursing Administration", "Nursing Education",
      "Nursing Exec. Org. Leadership", "Nursing Practice",
      "Pediatric Nurse Prac-PC PNP-PC", "Psychiatric Mental Health NP",
      "Clinical Laboratory Sciences", "Medical Laboratory Sciences",
      "Medical Laboratory Science", "Medical Lab Technology",
      "Physician Assistant Studies", "Physical Therapy", "Occupational Therapy",
      "Radiologic Sciences", "Medical Imaging", "Nuclear Medicine",
      "Dental Hygiene", "Dental Assisting",
      "Emergency Medical Services", "Emergency Med Svcs EMT-Basic",
      "Doctor of Pharmacy", "Pharmaceutical Sciences",
      "BS Pharmaceutical Sciences"
    ),
    description = "Clinical and licensure programs that produce practitioners"
  ),

  "Nursing" = list(
    programs = c(
      "Nursing",
      "Family Nurse Practitioner",
      "Nurse Admin Leadership",
      "Nurse Midwifery",
      "Nursing Administration",
      "Nursing Education",
      "Nursing Exec. Org. Leadership",
      "Nursing Practice",
      "Pediatric Nurse Prac-PC PNP-PC",
      "Psychiatric Mental Health NP"
    ),
    description = "Nursing programs only"
  ),

  "Allied Health & Clinical" = list(
    programs = c(
      "Clinical Laboratory Sciences",
      "Medical Laboratory Sciences",
      "Medical Lab Technology",
      "Physician Assistant Studies",
      "Physical Therapy",
      "Radiologic Sciences",
      "Medical Imaging",
      "Nuclear Medicine",
      "Dental Hygiene",
      "Dental Assisting",
      "Emergency Medical Services",
      "Emergency Med Svcs EMT-Basic"
    ),
    description = "Allied health and clinical programs"
  ),

  "Pharmacy" = list(
    programs = c(
      "Doctor of Pharmacy",
      "Pharmaceutical Sciences",
      "BS Pharmaceutical Sciences",
      "Toxicol & Pharmaceu Sciences"
    ),
    description = "Pharmacy and pharmaceutical sciences"
  ),

  "Public Health" = list(
    programs = c(
      "Public Health",
      "Community Health",
      "Community Health Education",
      "Community Health Intervention",
      "School Health Education",
      "Maternal Child Health",
      "Population Health",
      "Health Education"
    ),
    description = "Public and community health programs"
  ),

  "Health Administration & Policy" = list(
    programs = c(
      "Health Administration",
      "Health Policy",
      "Health Policy and Admin",
      "Health Systems Svcs & Policy",
      "General Healthcare Admin",
      "Health Information Technology"
    ),
    description = "Health administration and policy programs"
  ),

  "Health Sciences" = list(
    programs = c(
      "Biomedical Sciences",
      "Prof Health Sciences",
      "Health Professions",
      "Health Equity Sciences",
      "Health Scholars"
    ),
    description = "Health sciences and biomedical programs"
  )

)
