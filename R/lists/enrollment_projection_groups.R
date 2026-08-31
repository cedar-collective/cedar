# Curated course groups for enrollment projections.
#
# These are monitoring scopes. Projection rows use the named market and course;
# campus and part-term allocation remains in saved delivery components.

# 0.17.0 rebuilds DFW/repeat-demand signals with late-drop audits excluded.
CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION <- "0.17.0"
CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION <- 16L
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
  feeder = "Feeder transitions",
  anchored_population = "Prior season + population change",
  anchored_cohort = "Prior season + cohort change",
  anchored_feeder = "Prior season + feeder change"
)

CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES <- c(
  seasonal_last = "observed_enrollment",
  seasonal_median = "observed_enrollment",
  seasonal_trend = "observed_enrollment",
  spring_population_growth = "structural_demand",
  spring_cohort_flow = "structural_demand",
  feeder = "structural_demand",
  anchored_population = "anchored_upstream",
  anchored_cohort = "anchored_upstream",
  anchored_feeder = "anchored_upstream"
)

# Canonical reader-facing distinctions between projection candidates. Keeping
# this beside the method registry makes additions fail visibly in tests instead
# of leaving an independently maintained UI explanation behind.
CEDAR_ENROLLMENT_PROJECTION_METHOD_FAMILIES <- data.frame(
  family_id = c(
    "observed_enrollment", "structural_demand", "anchored_upstream"
  ),
  family_label = c(
    "Observed enrollment baselines",
    "Upstream indicators",
    "Anchored upstream candidates"
  ),
  description = c(
    paste(
      "Use only the course's recorded same-season enrollment. They differ in",
      "whether they favor the latest level, a stable center, or a continuing trend."
    ),
    paste(
      "Estimate demand from the students or pathways upstream of the course.",
      "They remain visible as diagnostic evidence but cannot be selected directly."
    ),
    paste(
      "Blend 50% prior same-season enrollment with 50% of one upstream estimate.",
      "They preserve the latest course level while allowing structural change to move it."
    )
  ),
  selection_note = c(
    "Eligible for selection; CEDAR first finds the best-performing baseline.",
    "Diagnostic only; these raw estimates explain the upstream signal and never become the published projection by themselves.",
    "Eligible only when aftcast volume, source coverage, and error gates pass."
  ),
  stringsAsFactors = FALSE
)

CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE <- data.frame(
  method_id = names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
  family_id = unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES),
  concept_id = c(
    "latest_level", "historical_center", "historical_direction",
    "population_change", "cohort_change", "feeder_change",
    "population_change", "cohort_change", "feeder_change"
  ),
  basis = c(
    "Repeats enrollment from the most recent prior term of the same type.",
    "Takes the median enrollment across recent terms of the same type.",
    "Extends the linear direction of recent same-season enrollment.",
    "Applies broad preceding-Fall population growth to the prior Spring course cohort.",
    "Applies empirically shrunk major/classification growth to the prior Spring course cohort.",
    "Uses learned student transitions from feeder courses, adjusted for historical feeder coverage.",
    "Averages prior same-season enrollment with the broad-population estimate.",
    "Averages prior same-season enrollment with the major/classification cohort estimate.",
    "Averages prior same-season enrollment with the feeder-transition estimate."
  ),
  distinction = c(
    "Most responsive to the latest course level, but also most exposed to a one-term anomaly or seat ceiling.",
    "Most resistant to an unusual term, but deliberately ignores whether demand is rising or falling.",
    "The only historical baseline that carries direction forward; it needs enough history and can overreact to a short trend.",
    "The broadest structural signal; it asks whether the total source population changed, not whether its academic mix changed.",
    "The composition-sensitive structural signal; it follows the majors and classifications represented in the course.",
    "The pathway-specific structural signal; it follows observed next-course behavior rather than population size alone.",
    "The level-preserving version of Spring population growth.",
    "The level-preserving version of Spring cohort flow.",
    "The level-preserving version of feeder transitions."
  ),
  stringsAsFactors = FALSE
)
