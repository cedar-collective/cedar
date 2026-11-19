# course-pair-dfw.R — Is a course harder for students who take another course
# the same term?
#
# For one course A on each campus: among A's continuing students (those with
# an entering GPA), is A's DFW rate higher for the students who also took
# course B that term than for A's students of the same term and entering-GPA
# band who did not? Each B is compared within term and band cells, so a B
# that strong or weak students take does not look harder or easier for that
# reason alone; the expected rate is the B-takers' own mix of cells at the
# rates of A's students without B.
#
# A pair is a candidate, never a verdict: a course taken together with A may
# mark a heavy term, a program's sequence or a schedule, not the pairing. The
# screen lists it as `harder_together` only when the gap is beyond chance
# (`z_min`), holds in at least `min_terms` terms that have `min_term_n`
# co-takers each, and holds in most such terms. Same-family pairs (a lecture
# and its lab, the two halves of a stretch course: codes that differ only in
# a final letter) are left out, and so are first-term students, whose
# entering GPA is unknown and whose placement courses would top any list for
# who takes them (ROADMAP, decided 2026-11-19).
#
# Reads `cedar_attempts` (A's outcome, B's attempts) and the GPA timeline of
# `cedar_student_terms` (build_gpa_timeline()); bounded at `last_graded`.
#
# Depends on: build_gpa_timeline() (branches/gpa-timeline.R),
#             entering_gpa_band() (branches/comparison.R), get_term_type() (trunk/utils.R)

#' The family a course code belongs to: the code without a final letter
#'
#' "ENGL 1110X" and "ENGL 1110Y" are one stretch course; "CHEM 1215" and
#' "CHEM 1215L" a lecture and its lab.
#' @noRd
.course_pair_family <- function(code) sub("[A-Z]$", "", code)

#' A course's DFW rate with and without each course taken alongside it
#'
#' @param attempts `cedar_attempts`: `student_id`, `term`, `campus`,
#'   `subject_course`, `outcome`.
#' @param student_terms `cedar_student_terms`, for build_gpa_timeline().
#' @param opt `course` (A's course id; required), `data_edges` (required; its
#'   `last_graded`), `campus` (delivery campuses; NULL reads every campus,
#'   each apart), `term_type` (NULL keeps every term type), `min_n`
#'   (co-taking student-terms a pair needs to be read; default 30),
#'   `min_term_n` (co-takers a term needs to count toward replication; default
#'   5), `min_terms` (terms the gap must hold in; default 3), `z_min` (how far
#'   beyond chance; default 2).
#' @return list(pairs, meta). `pairs`: one row per `campus` and
#'   `other_course` with `n_student_terms` (A's continuing students who also
#'   took it), `n_terms`, `n_terms_read` (terms with `min_term_n`),
#'   `n_terms_worse` (of those, terms where A's rate with it was above
#'   expected), `dfw_with_pct`, `dfw_expected_pct`, `gap_pts`, `z` and
#'   `harder_together`; candidates first, then by gap. Pairs under `min_n`
#'   are left out and counted per campus in `meta$n_pairs_small`. `meta`: the
#'   options, `edge`, `terms`, and per campus A's graded student-terms,
#'   continuing ones, first-term ones and ones with an invalid timeline.
get_course_pair_dfw <- function(attempts, student_terms, opt = list()) {
  course <- opt$course
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-pair-dfw.R] opt$course (one course id) is required.", call. = FALSE)
  }
  needed <- c("student_id", "term", "campus", "subject_course", "outcome")
  missing <- setdiff(needed, names(attempts))
  if (length(missing) > 0L) {
    stop("[course-pair-dfw.R] attempts lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- opt$data_edges[["last_graded"]]
  if (is.null(edge)) {
    stop("[course-pair-dfw.R] opt$data_edges has no graded edge (last_graded).", call. = FALSE)
  }
  edge <- as.integer(edge)
  min_n <- as.integer(opt$min_n %||% 30L)
  min_term_n <- as.integer(opt$min_term_n %||% 5L)
  min_terms <- as.integer(opt$min_terms %||% 3L)
  z_min <- as.numeric(opt$z_min %||% 2)

  # A graded attempt is a pass or a DFW; an early drop and an ungraded
  # registration have no outcome and take no part.
  scoped <- attempts %>% filter(term <= edge, !is.na(outcome))
  if (!is.null(opt$campus)) scoped <- scoped %>% filter(campus %in% opt$campus)
  if (!is.null(opt$term_type)) scoped <- scoped %>% filter(get_term_type(term) %in% opt$term_type)

  a_rows <- scoped %>%
    filter(subject_course == .env$course) %>%
    distinct(student_id, term, campus, outcome)
  if (anyDuplicated(a_rows[c("student_id", "term", "campus")])) {
    stop("[course-pair-dfw.R] attempts holds more than one outcome for a student in ", course,
         " in one term and campus.", call. = FALSE)
  }
  gpa <- build_gpa_timeline(student_terms, list(student_ids = unique(a_rows$student_id))) %>%
    select(student_id, term, gpa_entering, timeline_valid)
  a_rows <- a_rows %>% left_join(gpa, by = c("student_id", "term"), relationship = "many-to-one")
  counts <- a_rows %>%
    group_by(campus) %>%
    summarize(
      n_graded = n(),
      n_first_term = sum(is.na(gpa_entering)),
      n_invalid = sum(!is.na(gpa_entering) & !(timeline_valid %in% TRUE)),
      .groups = "drop"
    )
  # Continuing students: an entering GPA on a valid timeline (fail closed).
  a_rows <- a_rows %>%
    filter(!is.na(gpa_entering), timeline_valid %in% TRUE) %>%
    transmute(student_id, term, campus, band = entering_gpa_band(gpa_entering), dfw = outcome == "dfw")
  counts <- counts %>%
    left_join(a_rows %>% count(campus, name = "n_continuing"), by = "campus") %>%
    mutate(n_continuing = coalesce(n_continuing, 0L))
  cedar_debug("[course-pair-dfw.R] ", nrow(a_rows), " continuing student-terms in ", course, " to ", fmt_term(edge))

  # Every other course the same students took that term on the same campus,
  # outside A's own family.
  b_rows <- scoped %>%
    semi_join(a_rows, by = c("student_id", "term", "campus")) %>%
    filter(.course_pair_family(subject_course) != .course_pair_family(.env$course)) %>%
    distinct(student_id, term, campus, other_course = subject_course)

  base <- a_rows %>%
    group_by(campus, term, band) %>%
    summarize(n_a = n(), d_a = sum(dfw), .groups = "drop")
  cells <- a_rows %>%
    inner_join(b_rows, by = c("student_id", "term", "campus"), relationship = "one-to-many") %>%
    group_by(campus, other_course, term, band) %>%
    summarize(n_ab = n(), d_ab = sum(dfw), .groups = "drop") %>%
    inner_join(base, by = c("campus", "term", "band"), relationship = "many-to-one") %>%
    mutate(n_without = n_a - n_ab, d_without = d_a - d_ab) %>%
    # A cell where every A student also took B has no one to compare with.
    filter(n_without > 0L) %>%
    mutate(expected = n_ab * d_without / n_without)

  by_term <- cells %>%
    group_by(campus, other_course, term) %>%
    summarize(n_ab = sum(n_ab), d_ab = sum(d_ab), expected = sum(expected), .groups = "drop") %>%
    mutate(read = n_ab >= min_term_n, worse = read & d_ab > expected)
  pairs <- by_term %>%
    group_by(campus, other_course) %>%
    summarize(
      n_student_terms = sum(n_ab),
      n_terms = n(),
      n_terms_read = sum(read),
      n_terms_worse = sum(worse),
      dfw_with = sum(d_ab) / sum(n_ab),
      dfw_expected = sum(expected) / sum(n_ab),
      .groups = "drop"
    )
  small <- pairs %>% filter(n_student_terms < min_n) %>% count(campus, name = "n_pairs_small")
  pairs <- pairs %>%
    filter(n_student_terms >= min_n) %>%
    mutate(
      gap_pts = 100 * (dfw_with - dfw_expected),
      se = sqrt(dfw_expected * (1 - dfw_expected) / n_student_terms),
      z = if_else(se > 0, (dfw_with - dfw_expected) / se, NA_real_),
      harder_together = !is.na(z) & z >= z_min & n_terms_worse >= min_terms &
        n_terms_worse > n_terms_read / 2,
      dfw_with_pct = 100 * dfw_with,
      dfw_expected_pct = 100 * dfw_expected
    ) %>%
    select(campus, other_course, n_student_terms, n_terms, n_terms_read, n_terms_worse,
           dfw_with_pct, dfw_expected_pct, gap_pts, z, harder_together) %>%
    arrange(campus, desc(harder_together), desc(gap_pts))

  list(
    pairs = pairs,
    meta = list(
      course = course, campus = opt$campus, term_type = opt$term_type, edge = edge,
      terms = sort(unique(a_rows$term)),
      counts = counts %>%
        left_join(small, by = "campus") %>%
        mutate(n_pairs_small = coalesce(n_pairs_small, 0L)),
      min_n = min_n, min_term_n = min_term_n, min_terms = min_terms, z_min = z_min,
      gpa_bands = CEDAR_ENTERING_GPA_BANDS
    )
  )
}
