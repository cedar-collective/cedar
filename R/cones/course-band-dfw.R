# course-band-dfw.R — Which courses are harder on students with lower GPAs
# than those students' other courses are?
#
# One question: in each course, do the students of the lowest GPA band fail it
# by more than they fail their other courses that term, and is that excess
# larger than the same excess for the course's other students?
#
# A student with a low GPA does not pass more of everything, so a course's
# DFW rate by band says who takes the course before it says anything about
# the course. Each band's rate in the course is therefore set beside the same
# students' rate in the other courses they took that term (their excess), and
# the lowest band's excess beside the other bands' (the gap). General
# struggle is in both terms of the first difference and leaves it; a course
# hard for everyone is in both terms of the second and leaves that. What is
# left is a course that is harder, relative to the rest of their term, for
# students with lower GPAs than for its other students. A negative gap is the
# other finding: a course where they do about as well as, or better than, in
# the rest of their term.
#
# The band (`opt$band_by`):
#   "entering"  the GPA a continuing student brought into the term
#               (build_gpa_timeline()'s gpa_entering, entering_gpa_band()).
#               First-term students have none and are left out and counted.
#   "hs"        first-term students by high-school GPA band (hs_gpa_band()),
#               where one is on file; the rest are left out and counted.
# The lowest band is the first level of the band's scale.
#
# A candidate, never a verdict. The other courses are the student's own
# choice of a term, and a course taken beside easy ones has a larger excess
# for that reason. The standard error treats attempts as independent and the
# two rates of one band as unrelated; it is a floor. Each course is read on
# the campus that taught it; a student's other courses count wherever taught.
#
# Whose attempts (`opt$student_level`, `opt$student_campus`): the students
# enrolled that term at that level and home campus (scope_student_terms()).
# A student-term is in or out whole, so "their other courses" stays every
# course of the term, and "the course's other students" are the others in the
# same scope. This is not `opt$campus`, which is the campus that taught the
# course.
#
# Depends on: scope_student_terms() (branches/student-terms.R)
#             build_gpa_timeline() (branches/gpa-timeline.R)
#             entering_gpa_band(), hs_gpa_band(), applicant_hs_gpa()
#               (branches/comparison.R)

#' Each course's DFW excess for its lowest-GPA students against its other students
#'
#' @param attempts `cedar_attempts`: `student_id`, `term`, `campus`,
#'   `subject_course`, `outcome`.
#' @param student_terms `cedar_student_terms`, for build_gpa_timeline() and
#'   for the student scope.
#' @param opt `data_edges` (required; its `last_graded`), `term` (terms to
#'   read; NULL reads every graded term), `campus` (delivery campuses; NULL
#'   reads every campus, each apart), `student_level` and `student_campus`
#'   (the students to read, by their level and home campus that term; NULL
#'   reads everyone), `band_by` (`"entering"`, the default,
#'   or `"hs"`), `min_n` (attempts a course needs in the lowest band and in
#'   the others; default 30), `z_min` (how far beyond chance; default 2).
#' @param applicants `cedar_applicants`, for `band_by = "hs"`.
#' @return list(courses, bands, meta). `bands`: one row per `subject_course`,
#'   `campus` and `band`: `n_students`, `attempts`, `dfw_pct`,
#'   `other_attempts`, `other_dfw_pct`, `excess_pts`. `courses`: one row per
#'   course and campus at `min_n`: the lowest band's and the others' counts,
#'   rates and excess (`low_*`, `rest_*`), `gap_pts` (low excess less rest
#'   excess), `gap_se`, `z` and `verdict` (`"harder"`, `"easier"` or
#'   `"no_difference"`), widest gap first. `meta`: `edge`, `terms`,
#'   `band_by`, `low_band` (the first band of the scale, whether or not it
#'   has a student), `min_n`, `z_min`, the scope read (`campus`,
#'   `student_level`, `student_campus`), and the student-terms read and left
#'   out (`n_banded`, `n_no_band`, `n_invalid`, `n_out_of_scope`,
#'   `n_courses_small`). A scope with no student is an empty result.
get_course_band_dfw <- function(attempts, student_terms, opt = list(), applicants = NULL) {
  needed <- c("student_id", "term", "campus", "subject_course", "outcome")
  missing <- setdiff(needed, names(attempts))
  if (length(missing) > 0) {
    stop("[course-band-dfw.R] attempts lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- opt$data_edges[["last_graded"]]
  if (is.null(edge)) stop("[course-band-dfw.R] opt$data_edges has no graded edge (last_graded).", call. = FALSE)
  edge <- as.integer(edge)
  band_by <- opt$band_by %||% "entering"
  if (length(band_by) != 1L || !band_by %in% c("entering", "hs")) {
    stop("[course-band-dfw.R] opt$band_by must be \"entering\" or \"hs\".", call. = FALSE)
  }
  if (band_by == "hs" && is.null(applicants)) {
    stop("[course-band-dfw.R] applicants (cedar_applicants) is required for opt$band_by = \"hs\".", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 30L)
  z_min <- opt$z_min %||% 2

  graded <- attempts %>% filter(term <= edge, !is.na(outcome)) %>% mutate(term = as.integer(term))
  if (!is.null(opt$term)) graded <- graded %>% filter(term %in% as.integer(opt$term))
  if (nrow(graded) == 0L) stop("[course-band-dfw.R] no graded attempt in the terms asked for.", call. = FALSE)
  terms <- sort(unique(graded$term))

  # ── Whose attempts: the students of the level and home campus asked for ───
  n_out_of_scope <- 0L
  if (!is.null(opt$student_level) || !is.null(opt$student_campus)) {
    in_scope <- scope_student_terms(student_terms, opt$student_level, opt$student_campus) %>%
      transmute(student_id, term = as.integer(term))
    n_all <- nrow(distinct(graded, student_id, term))
    graded <- graded %>% semi_join(in_scope, by = c("student_id", "term"))
    n_out_of_scope <- n_all - nrow(distinct(graded, student_id, term))
  }

  # ── Each student-term's band ──────────────────────────────────────────────
  takers <- graded %>% distinct(student_id, term)
  timeline <- build_gpa_timeline(student_terms, list(student_ids = unique(takers$student_id))) %>%
    select(student_id, term, gpa_entering, timeline_valid) %>%
    inner_join(takers, by = c("student_id", "term"))
  n_invalid <- sum(!(timeline$timeline_valid %in% TRUE))
  valid <- timeline %>% filter(timeline_valid %in% TRUE)
  if (band_by == "entering") {
    banded <- valid %>% filter(!is.na(gpa_entering)) %>%
      transmute(student_id, term, band = entering_gpa_band(gpa_entering))
    n_no_band <- sum(is.na(valid$gpa_entering))
  } else {
    first_term <- valid %>% filter(is.na(gpa_entering)) %>%
      left_join(applicant_hs_gpa(applicants), by = "student_id")
    # The scale's own bands, whoever is in them: with nobody in the lowest
    # band it is still the lowest, and has no course to read.
    banded <- first_term %>% filter(!is.na(high_school_cum_gpa)) %>%
      transmute(student_id, term, band = hs_gpa_band(high_school_cum_gpa)) %>%
      mutate(band = factor(band, levels = setdiff(levels(band), "not on file")))
    n_no_band <- sum(is.na(first_term$high_school_cum_gpa))
  }
  low_band <- levels(banded$band)[[1]]
  cedar_debug("[course-band-dfw.R] ", nrow(banded), " banded student-terms by ", band_by, " to ", edge,
              "; ", n_out_of_scope, " outside the student scope")

  # ── A band's rate in the course and in the rest of the same students' term ─
  totals <- graded %>%
    group_by(student_id, term) %>%
    summarize(tot_att = n(), tot_dfw = sum(outcome == "dfw"), .groups = "drop")
  rows <- graded
  if (!is.null(opt$campus)) rows <- rows %>% filter(campus %in% opt$campus)
  rows <- rows %>%
    group_by(student_id, term, campus, subject_course) %>%
    summarize(att = n(), dfw = sum(outcome == "dfw"), .groups = "drop") %>%
    inner_join(banded, by = c("student_id", "term")) %>%
    inner_join(totals, by = c("student_id", "term")) %>%
    mutate(other_att = tot_att - att, other_dfw = tot_dfw - dfw, low = band == low_band)

  rate <- function(k, n) if_else(n > 0, 100 * k / n, NA_real_)
  bands <- rows %>%
    group_by(subject_course, campus, band) %>%
    summarize(n_students = n_distinct(student_id), attempts = sum(att), .dfw = sum(dfw),
              other_attempts = sum(other_att), .other_dfw = sum(other_dfw), .groups = "drop") %>%
    mutate(dfw_pct = rate(.dfw, attempts), other_dfw_pct = rate(.other_dfw, other_attempts),
           excess_pts = dfw_pct - other_dfw_pct) %>%
    select(subject_course, campus, band, n_students, attempts, dfw_pct, other_attempts, other_dfw_pct, excess_pts)

  var_of <- function(pct, n) if_else(n > 0, (pct / 100) * (1 - pct / 100) / n, NA_real_)
  side <- function(which, prefix) {
    rows %>% filter(low == which) %>%
      group_by(subject_course, campus) %>%
      summarize(n = sum(att), k = sum(dfw), on = sum(other_att), ok = sum(other_dfw), .groups = "drop") %>%
      mutate(dfw_pct = rate(k, n), other_dfw_pct = rate(ok, on), excess_pts = dfw_pct - other_dfw_pct,
             var = var_of(dfw_pct, n) + var_of(other_dfw_pct, on)) %>%
      select(subject_course, campus, attempts = n, dfw_pct, other_attempts = on, other_dfw_pct, excess_pts, var) %>%
      rename_with(~ paste0(prefix, .x), -c(subject_course, campus))
  }
  both <- inner_join(side(TRUE, "low_"), side(FALSE, "rest_"), by = c("subject_course", "campus"))
  read <- both %>% filter(low_attempts >= min_n, rest_attempts >= min_n, !is.na(low_excess_pts), !is.na(rest_excess_pts))
  courses <- read %>%
    mutate(gap_pts = low_excess_pts - rest_excess_pts,
           gap_se = 100 * sqrt(low_var + rest_var),
           z = if_else(gap_se > 0, gap_pts / gap_se, NA_real_),
           verdict = case_when(!is.na(z) & z >= z_min ~ "harder",
                               !is.na(z) & z <= -z_min ~ "easier",
                               TRUE ~ "no_difference")) %>%
    select(-low_var, -rest_var) %>%
    arrange(desc(gap_pts), subject_course, campus)

  list(courses = courses, bands = bands,
       meta = list(edge = edge, terms = terms, band_by = band_by, low_band = low_band,
                   min_n = min_n, z_min = z_min, campus = opt$campus,
                   student_level = opt$student_level, student_campus = opt$student_campus,
                   n_banded = nrow(banded), n_no_band = n_no_band, n_invalid = n_invalid,
                   n_out_of_scope = n_out_of_scope,
                   n_courses_small = nrow(both) - nrow(read)))
}
