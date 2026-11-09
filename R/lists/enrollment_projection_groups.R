# CEDAR-PLATFORM: projection model registry; monitored course groups from institution/<id>/
# The model registry (versions, candidates, reader-facing method guide) is
# CEDAR's. The monitoring scopes -- which courses, on which campuses, in which
# market, with which per-course window overrides -- are the institution's, in
# projection_groups.csv and projection_courses.csv, with the history window
# start in settings.csv (projection_history_start_term) and the course
# sequences in projection_sequences.csv. This file names no course, campus or
# term.
#
# Groups are monitoring scopes. Projection rows use the named market and course;
# campus and part-term allocation remains in saved delivery components.

# 0.30.0 (schema 27): a pooled feeder must earn its place by lift. A course is
# a feeder only when its students take the course next at feeder_min_lift (3)
# times the market's rate, from at least 20 transitions, and the four carrying
# the most such students are kept (feeder_max_courses, was eight with no
# floor). The pooled rate is unchanged in kind. Candidates and published rows
# carry each feeder's lift and the market rate it is measured against, so a
# reader sees why each feeder is one. Stricter rules forecast worse
# (forecasting-lessons.md).
# 0.29.0 (schema 26): each student-term's classification and major are read
# off cedar_student_terms (ADR-001 step 5): the classification Banner recorded
# for that term, and the primary major, where the class list stamped a late
# pull's classification (I47) and was summarised by its most common value.
# 0.28.0 (schema 26): reads by course (ADR-001 step 4). The class list, the
# sections, the scope and the listed sequences are keyed on course_id, so a
# renamed or renumbered course's earlier offerings are its own history.
# 0.27.0 (schema 25): the plan's feeder adjustment applies to Spring targets
# only (plan_feeder_seasons). On past forecasts, Fall feeder changes improved
# Spring forecasts and did not improve Fall ones: a Spring feeder change
# pointed the way the Fall course moved no more often than chance. The
# adjusted candidate still carries its deltas, because selection guards it.
# 0.26.0 (schema 25): the plan follows the term just finished. A course's listed
# predecessor (projection_sequences.csv) carries its enrollment change in at
# that pair's own rate, and is taken out of the pooled feeders so no student
# counts twice. The plan adds that sequence change every time, and the pooled
# feeders' change only when they moved 5% or more, unless the published
# projection already includes them. The pressure bump is 5%, not 10%, and
# feeders no longer cancel it. The adjusted candidate splits its feeder delta
# the same way, sequence from pooled; the selection rule is unchanged.
# 0.25.0 (schema 24): a term pulled before one of its later sessions began
# (ISSUES.md I28) is no longer read as undated. Its begun sessions' first day
# is a lower bound on fill, so it settles saturation, the pressure bump and the
# expansion response only where it already reaches their level, and an
# unsettled term's note names the session not yet begun. The recent history is
# saved by delivery campus too, so a campus full on the first day beside one
# with room is flagged rather than pooled away; a prior term full on the first
# day is flagged full, not near full; and an unknown prior fill says why.
# 0.24.0 (schema 23): intersession sections (settings.csv
# intersession_parts_of_term) are left out of every projection input. Their
# seats made a course's first day unknown until December (ISSUES.md I28), and
# their students read the Fall spine from a partial Fall (I35). Pressure seat
# gaps compare with a floating-point tolerance (I34).
# 0.23.0 (schema 23): the saved bundle also carries what the reader needs to
# judge a projection -- each aftcast's seat and data conditions and its error
# source, a seat-consistency axis beside Reliability, and when the target
# term's draft schedule was pulled. No calculation changed.
# 0.23.0 (schema 22): planning sections, the seat gap and the recommendation
# are sized for registrations, not expected first-day seats. Registrations run
# a median 8% above the first day, and that margin is kept on purpose: sized on
# the first day, 61% of 207 past aftcasts planned fewer seats than were filled
# on day one; sized on registrations, 32%. A course near full in every recent
# same-season term is planned for a pressure bump on top (10%, or the students
# left waiting if more) unless its feeders just fell; the forecast itself is
# unchanged.
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
CEDAR_ENROLLMENT_PROJECTION_MODEL_VERSION <- "0.30.0"

# Schema 27: candidates and projections carry each pooled feeder's lift and
# the market rate behind it (feeder_lifts, feeder_base_rate). Schema 26 added
# the students left waiting in the term just finished (waitlisted_preceding).
CEDAR_ENROLLMENT_PROJECTION_SCHEMA_VERSION <- 27L
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
# Parts of term the projections leave out (settings.csv
# intersession_parts_of_term, `|`-separated; UNM's December INT), or none.
CEDAR_INTERSESSION_PARTS_OF_TERM <- local({
  s <- cedar_institution_files$settings
  v <- s$value[s$setting == "intersession_parts_of_term"]
  if (length(v) == 1) strsplit(v, "|", fixed = TRUE)[[1]] else character(0)
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
# Course sequences (projection_sequences.csv): a listed predecessor's
# enrollment change carries into the next course at that pair's own rate.
CEDAR_ENROLLMENT_PROJECTION_SEQUENCES <- validate_projection_sequences(
  read_institution_file("projection_sequences")
)

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
# Reader-facing names, in the page's words: no "spine", "floor" or "delta".
# The adjusted forecast is named for what it adds, whatever the season of the
# term just finished (a Spring for a Fall target read one step ahead,
# ISSUES.md I41).
CEDAR_ENROLLMENT_PROJECTION_METHODS <- c(
  seasonal_last = "Last year's registrations",
  spine_adjusted = "Last year's registrations, adjusted"
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
    "Both forecasts start from the course's registrations in the same season",
    "last year. The adjusted one adds the students still waiting when that",
    "term was near full, and the enrollment changes in the term just finished."
  ),
  selection_note = paste(
    "Last year's registrations is the default; the adjusted forecast replaces",
    "it only after beating it on earlier past forecasts."
  ),
  stringsAsFactors = FALSE
)

CEDAR_ENROLLMENT_PROJECTION_METHOD_GUIDE <- data.frame(
  method_id = names(CEDAR_ENROLLMENT_PROJECTION_METHODS),
  family_id = unname(CEDAR_ENROLLMENT_PROJECTION_METHOD_ROLES),
  concept_id = c("latest_level", "adjusted_level"),
  basis = c(
    "Repeats the course's registrations from the same season last year.",
    paste(
      "Starts from the same number, adds the students still waiting when that",
      "term was near full, and adds the change in the course's own",
      "enrollment, in the course taken just before it, and in its other",
      "feeder courses during the term just finished, each scaled by the share",
      "that historically carried into this course."
    )
  ),
  distinction = c(
    "The default. Closest when the schedule holds still; a year old by the time the target is scheduled, and it cannot see that a full course would have drawn more students.",
    "Sees a near-full prior term and a term just finished that moved. Uses that term's enrollments only, because grades are not posted when the schedule is built; the same terms can be re-read once they are."
  ),
  stringsAsFactors = FALSE
)
