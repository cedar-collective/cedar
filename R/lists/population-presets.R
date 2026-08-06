# population-presets.R — Named major-group presets for the population builder.
#
# Each preset pre-populates the program selectizeInput when the user picks it
# from the "Program Group" dropdown. Pre-major programs are auto-derived from
# major_dept_map using F-prefix codes — no manual list needed.
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
  "Medical Lab Technology", "Physician Assistant Studies",
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

PATHWAYS_MAJOR_GROUP_PRESETS <- list(

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
