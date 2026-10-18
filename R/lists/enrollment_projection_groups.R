# CEDAR-PLATFORM: projection model registry; monitored course groups from institution/<id>/
# The model registry (versions, candidates, reader-facing method guide) is
# CEDAR's. The monitoring scopes -- which courses, on which campuses, in which
# market, with which per-course window overrides -- are the institution's, in
# projection_groups.csv and projection_courses.csv, with the history window
# start in settings.csv (projection_history_start_term). This file names no
# course, campus or term.
#
# Groups are monitoring scopes. Projection rows use the named market and course;
# campus and part-term allocation remains in saved delivery components.

# 0.22.0: the saturation floor is the spine plus the students still waiting who
# are on no campus's class list in the market. It was first-day enrollment
# plus the waitlist, which the early-drop churn absorbed (ISSUES.md I27).
# 0.21.0: seats are judged and sized on the first day of classes. Saturation,
# capacity reached, and section sizing read reconstructed first-day enrollment
# (calc_first_day_enrl()) instead of census; a term whose first day cannot be
# reconstructed is not judged. Capacity reached is 98% first-day fill, not 100%.
# 0.20.0 introduced the spine / floor / delta
# model: prior same-season is the spine; the adjusted candidate adds a
# saturation floor and two Fall-enrollment deltas and must beat the spine on
# rolling aftcasts. (0.19.0 introduced rolling selection and the
# occupancy-based capacity signal.)
CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION <- "0.22.0"
CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION <- 21L
# Capacity is reached at CEDAR_FULL_FILL first-day fill and a prior term is
# saturated at CEDAR_NEAR_FULL_FILL; both levels live in R/lists/seat_fill.R.
# The first term the model reads history from (settings.csv
# projection_history_start_term), or NA when the institution has not set one:
# the app loads, the projection builder stops.
CEDAR_ENROLLMENT_PROJECTION_HISTORY_START_TERM <- local({
  s <- cedar_institution_files$settings
  v <- s$value[s$setting == "projection_history_start_term"]
  if (length(v) == 1) as.integer(v) else NA_integer_
})

.cedar_projection <- validate_projection_groups(
  read_institution_file("projection_groups"),
  read_institution_file("projection_courses"),
  known_campuses = c(CEDAR_CAMPUS_MAIN, CEDAR_CAMPUS_ONLINE, CEDAR_CAMPUS_BRANCH)
)

# Per-course overrides, named by course, from the rows that set one.
.cedar_projection_override <- function(col) {
  rows <- .cedar_projection$courses[!is.na(.cedar_projection$courses[[col]]), ]
  rows <- rows[!duplicated(rows$subject_course), ]
  stats::setNames(as.integer(rows[[col]]), rows$subject_course)
}
CEDAR_ENROLLMENT_PROJECTION_COURSE_HISTORY_START_TERMS <- .cedar_projection_override("history_start_term")
CEDAR_ENROLLMENT_PROJECTION_COURSE_RETENTION_MIN_TERMS <- .cedar_projection_override("retention_min_terms")

# Every always-monitored course in any group: the core that skips the pressure
# screen and is aftcast on every build.
CEDAR_ENROLLMENT_PROJECTION_ALWAYS_MONITORED_COURSES <- unique(
  .cedar_projection$courses$subject_course[.cedar_projection$courses$always_monitored]
)

CEDAR_ENROLLMENT_PROJECTION_GROUPS <- local({
  g <- .cedar_projection$groups
  stats::setNames(lapply(seq_len(nrow(g)), function(i) {
    rows <- .cedar_projection$courses[.cedar_projection$courses$group_id == g$group_id[[i]], ]
    list(
      label = g$label[[i]],
      description = g$description[[i]],
      market_id = g$market_id[[i]],
      campuses = g$campuses[[i]],
      always_monitored_courses = rows$subject_course[rows$always_monitored],
      courses = sort(unique(c(
        if (g$include_gen_ed[[i]]) unlist(gen_ed_all, use.names = FALSE) else character(0),
        rows$subject_course
      )))
    )
  }), g$group_id)
})

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
      "Starts from the same number, adds the students still waiting when that",
      "term was saturated, and adds the change in the course's own",
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
