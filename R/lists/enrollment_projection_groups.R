# CEDAR-INSTITUTION: monitored course groups and model config
# Curated course groups for enrollment projections.
#
# These are monitoring scopes. Projection rows use the named market and course;
# campus and part-term allocation remains in saved delivery components.

# 0.20.0: the spine / floor / delta model. Prior same-season is the spine; the
# adjusted candidate adds a saturation floor and two Fall-enrollment deltas and
# must beat the spine on rolling aftcasts. Every other candidate and the
# bias-correction path are retired. (0.19.0 introduced rolling selection, the
# census-based capacity signal, and census-equivalent section sizing.)
CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION <- "0.20.0"
CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION <- 20L
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

# Two candidates. Prior same-season is the spine and the default; the adjusted
# candidate adds a saturation floor and two Fall-enrollment deltas to it and
# must beat the spine on earlier rolling aftcasts before it is published.
#
# 0.20.0 retired the rest of the registry after the Spring 2027 audits: the
# seasonal median, the raw and blended preceding-term ratio, both Spring
# population methods and the anchored cohort blend sat within 0.3 WAPE points
# of the spine (correlation 0.999 to 1.000) or lost to it rolling, and the
# bias-correction path never fired on five Springs of history. The audit
# figures are in docs/developers/forecasting-lessons.md.
CEDAR_ENROLLMENT_PROJECTION_METHODS <- c(
  seasonal_last = "Prior same-season",
  spine_adjusted = "Prior same-season + floor + Fall deltas"
)

CEDAR_ENROLLMENT_PROJECTION_DEFAULT_METHOD <- "seasonal_last"

CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES <- c(
  seasonal_last = "observed_enrollment",
  spine_adjusted = "observed_enrollment"
)

# Canonical reader-facing distinctions between projection candidates. Keeping
# this beside the method registry makes additions fail visibly in tests instead
# of leaving an independently maintained UI explanation behind.
CEDAR_ENROLLMENT_PROJECTION_METHOD_FAMILIES <- data.frame(
  family_id = "observed_enrollment",
  family_label = "Observed enrollment",
  description = paste(
    "Both candidates start from the course's own prior same-season",
    "enrollment. The adjusted one raises it to a floor when that term was",
    "saturated and moves it by what changed in the term just finished."
  ),
  selection_note = paste(
    "Prior same-season is the default; the adjusted candidate replaces it only",
    "after beating it on earlier aftcasts."
  ),
  stringsAsFactors = FALSE
)

CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE <- data.frame(
  method_id = names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
  family_id = unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES),
  concept_id = c("latest_level", "adjusted_level"),
  basis = c(
    "Repeats enrollment from the most recent prior term of the same type.",
    paste(
      "Starts from the same number, raises it to census plus waitlist when",
      "that term was saturated, and adds the change in the course's own",
      "enrollment and in its feeder courses during the term just finished,",
      "each scaled by the share that historically carried into this course."
    )
  ),
  distinction = c(
    "The default. Within 6% when the schedule holds still; a year old by the time the target is scheduled, and blind to a saturated ceiling.",
    "Sees a saturated prior term and a Fall that moved. Uses Fall enrollments only, because grades are not posted when the schedule is built; the same terms can be re-read once they are."
  ),
  stringsAsFactors = FALSE
)
