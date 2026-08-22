# Curated course groups for enrollment projections.
#
# These are monitoring scopes. Projection rows use the named market and course;
# campus and part-term allocation remains in saved delivery components.

CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION <- "0.11.0"
CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION <- 12L
CEDAR_ENROLLMENT_PROJECTION_CALIBRATION_FACTOR_BOUNDS <- c(0.75, 1.25)
CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM <- 202210L
CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS <- c(
  "MATH 1215" = 202580L
)
CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS <- c(
  "MATH 1215" = 1L
)

CEDAR_ENROLLMENT_PROJECTION_ALWAYS_MONITORED_COURSES <- c(
  "FYEX 1010", "FYEX 1030", "FYEX 1110",
  "MATH 1215", "MATH 1220", "MATH 1350",
  "BIOL 1140",
  "CHEM 1215", "CHEM 1215L",
  "ENGL 1110", "ENGL 1120"
)

CEDAR_ENROLLMENT_PROJECTION_GROUPS <- list(
  critical_courses = list(
    label = "Gen Ed + critical courses",
    description = paste(
      "Canonical Gen Ed courses, selected gateway additions, and three FYEX",
      "courses monitored on the Albuquerque and online campuses."
    ),
    market_id = "abq_ea_course_market",
    campuses = CEDAR_CAMPUS_DEFAULT,
    always_monitored_courses =
      CEDAR_ENROLLMENT_PROJECTION_ALWAYS_MONITORED_COURSES,
    courses = sort(unique(c(
      unlist(gen_ed_all, use.names = FALSE),
      CEDAR_ENROLLMENT_PROJECTION_ALWAYS_MONITORED_COURSES
    )))
  )
)

CEDAR_ENROLLMENT_PROJECTION_METHODS <- c(
  seasonal_last = "Prior same-season",
  seasonal_median = "Seasonal median",
  seasonal_trend = "Seasonal trend",
  spring_population_growth = "Spring population growth",
  spring_cohort_flow = "Spring cohort flow",
  feeder = "Feeder transitions"
)

CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES <- c(
  seasonal_last = "observed_enrollment",
  seasonal_median = "observed_enrollment",
  seasonal_trend = "observed_enrollment",
  spring_population_growth = "structural_demand",
  spring_cohort_flow = "structural_demand",
  feeder = "structural_demand"
)
