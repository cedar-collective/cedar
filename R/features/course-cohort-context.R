# course-cohort-context.R — Is a course's takers-against-non-takers gap unusual?
#
# The text-first preview behind "are students better served in this course
# than in an average course of the college?". get_course_cohort_effect()
# gives one course's passed, DFW'd and never-took groups with their return
# and next-term DFW share. This feature runs it once over the focal course
# and every course of a college (and level) the population took, and reads
# the focal course against the distribution: the median passed-group return
# and the median passed-minus-never gap across the college's courses, with
# where the focal course's gap sits among them. The population's own rates
# are the floor everything is read against.
#
# A course is in the benchmark for a term and campus when both its passed
# and its never-took groups clear min_n. The focal course is never in its own
# benchmark. The gap is descriptive on both sides: passing any course goes
# with returning, so the median gap is the college's selection effect and the
# focal course's distance from it is the number worth reading.
#
# The payload is typed; format_course_cohort_context() is the one text
# rendering, and the only place a number is rounded. A Shiny surface, if one
# follows, reads the payload and never the text.
#
# Depends on: get_course_cohort_effect() (cones/course-cohort-effect.R)

#' Build the course cohort context payload
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param opt `course` (the focal course id; required), `classification`
#'   (required), `college` (the benchmark's college codes, as the attempt
#'   rows carry them; required), `level` (the benchmark's course levels;
#'   NULL keeps every level), `campus` (home campuses; NULL keeps every
#'   campus), `term` (anchor terms; NULL keeps every term to the settled
#'   edge), `min_n` (smallest group a row needs, and the smallest passed and
#'   never-took groups a benchmark course needs; default 10), `data_edges`
#'   (required), `college_label` (how the text names the college; default
#'   the codes).
#' @return A `course_cohort_context` list: `meta`; `population` (the cone's,
#'   per term and campus); `focal` (per term and campus: the focal course's
#'   three groups side by side, `lift_return` and `lift_next_dfw` as passed
#'   minus never-took, in points); `benchmark` (per term and campus:
#'   `n_courses`, the median and quartiles of the benchmark courses'
#'   passed-group return, return gap, passed-group next-term DFW share and
#'   next-term DFW gap, and the share of benchmark courses whose gap is
#'   strictly below the focal course's); `courses` (every course's row,
#'   `in_benchmark` flagged); `left_out` (the focal course's early drops and
#'   ungraded takers).
build_course_cohort_context <- function(student_terms, attempts, opt = list()) {
  course <- opt$course
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-cohort-context.R] opt$course (one focal course id) is required.", call. = FALSE)
  }
  college <- opt$college
  if (is.null(college) || length(college) == 0L) {
    stop("[course-cohort-context.R] opt$college (the benchmark's college codes) is required.", call. = FALSE)
  }
  for (col in c("college", "level")) {
    if (!col %in% names(attempts)) stop("[course-cohort-context.R] attempts lacks ", col, call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[course-cohort-context.R] opt$data_edges has no settled enrollment edge.", call. = FALSE)
  }

  # The benchmark candidates: the college's courses anyone took in the anchor
  # terms, with enough takers to possibly clear min_n in a group.
  candidates <- attempts %>% filter(college %in% .env$college, term <= edge)
  if (!is.null(opt$level)) candidates <- candidates %>% filter(level %in% opt$level)
  if (!is.null(opt$term)) candidates <- candidates %>% filter(term %in% as.integer(opt$term))
  # CAMPUS_ROLLUP: a pre-filter on how many students took the course at all;
  # the cone then counts each course by the student's home campus.
  candidates <- candidates %>%
    group_by(subject_course) %>%
    summarize(n = n_distinct(student_id), .groups = "drop") %>%
    filter(n >= min_n) %>%
    pull(subject_course)
  courses <- unique(c(course, candidates))
  cedar_debug("[course-cohort-context.R] ", length(candidates), " benchmark candidates in ",
              paste(college, collapse = "/"))

  cone_opt <- opt[intersect(names(opt), c("classification", "campus", "term", "min_n", "data_edges"))]
  cone_opt$course <- courses
  res <- get_course_cohort_effect(student_terms, attempts, cone_opt)

  # One wide row per course, term and campus. A group under min_n keeps its
  # count (from the cone's suppressed rows) and has no rate; a group nobody is
  # in counts 0.
  key <- c("course", "term", "student_campus")
  counts <- bind_rows(
    res$rates %>% select(all_of(key), group, n_students),
    res$suppressed %>% select(all_of(key), group, n_students)
  ) %>%
    tidyr::pivot_wider(id_cols = all_of(key), names_from = group, values_from = n_students,
                       names_glue = "{group}_n_students")
  group_rates <- res$rates %>%
    tidyr::pivot_wider(id_cols = all_of(key), names_from = group,
                       values_from = c(return_pct, next_dfw_pct), names_glue = "{group}_{.value}")
  wide <- counts %>%
    left_join(group_rates, by = key) %>%
    inner_join(res$population %>% select(term, student_campus, population, next_outcomes_observable),
               by = c("term", "student_campus"))
  for (col in c("passed_n_students", "dfw_n_students", "none_n_students",
                "passed_return_pct", "dfw_return_pct", "none_return_pct",
                "passed_next_dfw_pct", "dfw_next_dfw_pct", "none_next_dfw_pct")) {
    if (!col %in% names(wide)) wide[[col]] <- if (grepl("n_students$", col)) NA_integer_ else NA_real_
  }
  wide <- wide %>%
    mutate(
      passed_n_students = coalesce(passed_n_students, 0L),
      dfw_n_students    = coalesce(dfw_n_students, 0L),
      none_n_students   = coalesce(none_n_students, 0L),
      lift_return   = passed_return_pct - none_return_pct,
      lift_next_dfw = passed_next_dfw_pct - none_next_dfw_pct,
      in_benchmark  = course != .env$course & passed_n_students >= min_n & none_n_students >= min_n
    ) %>%
    select(course, term, student_campus, population, in_benchmark,
           passed_n_students, passed_return_pct, passed_next_dfw_pct,
           dfw_n_students, dfw_return_pct, dfw_next_dfw_pct,
           none_n_students, none_return_pct, none_next_dfw_pct,
           lift_return, lift_next_dfw, next_outcomes_observable) %>%
    arrange(term, student_campus, course)

  focal <- wide %>% filter(course == .env$course) %>% select(-in_benchmark)

  q <- function(x, p) if (all(is.na(x))) NA_real_ else unname(stats::quantile(x, p, na.rm = TRUE))
  share_below <- function(x, focal_value) {
    if (length(focal_value) != 1L || is.na(focal_value) || all(is.na(x))) return(NA_real_)
    mean(x[!is.na(x)] < focal_value)
  }
  benchmark <- wide %>%
    filter(in_benchmark) %>%
    group_by(term, student_campus) %>%
    summarize(
      n_courses = n(),
      passed_return_median = q(passed_return_pct, 0.5),
      passed_return_q1 = q(passed_return_pct, 0.25),
      passed_return_q3 = q(passed_return_pct, 0.75),
      lift_return_median = q(lift_return, 0.5),
      lift_return_q1 = q(lift_return, 0.25),
      lift_return_q3 = q(lift_return, 0.75),
      passed_next_dfw_median = q(passed_next_dfw_pct, 0.5),
      lift_next_dfw_median = q(lift_next_dfw, 0.5),
      lift_next_dfw_q1 = q(lift_next_dfw, 0.25),
      lift_next_dfw_q3 = q(lift_next_dfw, 0.75),
      lifts_return = list(lift_return),
      lifts_next_dfw = list(lift_next_dfw),
      .groups = "drop"
    ) %>%
    left_join(focal %>% select(term, student_campus, focal_lift_return = lift_return,
                               focal_lift_next_dfw = lift_next_dfw),
              by = c("term", "student_campus")) %>%
    mutate(
      share_below_return   = mapply(share_below, lifts_return, focal_lift_return),
      share_below_next_dfw = mapply(share_below, lifts_next_dfw, focal_lift_next_dfw)
    ) %>%
    select(-lifts_return, -lifts_next_dfw, -focal_lift_return, -focal_lift_next_dfw)

  structure(list(
    meta = list(
      course = course,
      classification = opt$classification,
      college = college,
      college_label = opt$college_label %||% paste(college, collapse = "/"),
      level = opt$level,
      campus = opt$campus,
      terms = sort(unique(res$population$term)),
      min_n = min_n,
      edge = res$edge,
      graded_edge = res$graded_edge,
      n_population_student_terms = res$n_population_student_terms,
      n_benchmark_candidates = length(candidates)
    ),
    population = res$population,
    focal = focal,
    benchmark = benchmark,
    courses = wide,
    left_out = res$left_out %>% filter(course == .env$course)
  ), class = "course_cohort_context")
}


#' The course cohort context in plain words
#'
#' @param payload `build_course_cohort_context()` output.
#' @return Character vector of lines.
format_course_cohort_context <- function(payload) {
  if (!inherits(payload, "course_cohort_context")) {
    stop("[course-cohort-context.R] payload must come from build_course_cohort_context().", call. = FALSE)
  }
  meta <- payload$meta
  n <- function(x) ifelse(is.na(x), "—", format(as.integer(round(x)), big.mark = ","))
  pct <- function(x) ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = 1), "%"))
  pts <- function(x) ifelse(is.na(x), "—", paste0(ifelse(x >= 0, "+", ""), formatC(x, format = "f", digits = 1), " points"))
  share <- function(x) ifelse(is.na(x), "—", paste0(round(100 * x), "%"))
  iqr <- function(a, b) ifelse(is.na(a) | is.na(b), "", paste0(" (quartiles ", pct(a), " to ", pct(b), ")"))
  iqr_pts <- function(a, b) ifelse(is.na(a) | is.na(b), "", paste0(" (quartiles ", pts(a), " to ", pts(b), ")"))
  plural <- function(k, noun) paste0(n(k), " ", noun, if (k == 1) "" else "s")

  lines <- c(
    paste0(meta$course, " against the ", meta$college_label,
           if (!is.null(meta$level)) paste0(" ", paste(meta$level, collapse = "/"), "-division") else "",
           " courses: ", paste(meta$classification, collapse = ", "),
           if (is.null(meta$campus)) ", each home campus its own row" else
             paste0(", home campus ", paste(meta$campus, collapse = ", "))),
    paste0("Population: ", n(meta$n_population_student_terms), " student-terms; enrollment settled through ",
           fmt_term(meta$edge), ", grades through ", fmt_term(meta$graded_edge),
           "; a group needs ", plural(meta$min_n, "student"), ", and a benchmark course ", meta$min_n,
           " in both its passed and its never-took groups; ", plural(meta$n_benchmark_candidates, "candidate course"), "."),
    "Return is enrollment the next regular term; the next-term DFW share is DFW over that term's classified attempts. Both gaps are passed minus never took, in points, and describe who takes the course before they describe the course."
  )

  pop <- payload$population
  for (i in seq_len(nrow(pop))) {
    p <- pop[i, ]
    f <- payload$focal %>% filter(term == p$term, student_campus == p$student_campus)
    b <- payload$benchmark %>% filter(term == p$term, student_campus == p$student_campus)
    lo <- payload$left_out %>% filter(term == p$term, student_campus == p$student_campus)
    lines <- c(lines, "", paste0(
      fmt_term(p$term), ", ", p$student_campus, ": ", plural(p$population, "student"), "; ",
      if (p$n_return_observable > 0) paste0(pct(p$return_pct), " returned") else "return not yet observable",
      "; next-term DFW share ",
      if (!isTRUE(p$next_outcomes_observable)) "not yet observable"
      else if (is.na(p$next_attempts) || p$next_attempts == 0L) "has no classified attempt"
      else paste0(pct(p$next_dfw_pct), " over ", plural(p$next_attempts, "attempt")), "."
    ))
    if (nrow(f) == 0L) {
      lines <- c(lines, paste0("  ", meta$course, ": no group clears ", meta$min_n, " students."))
    } else {
      lines <- c(lines, paste0(
        "  ", meta$course, ": passed ", n(f$passed_n_students),
        " (", share(f$passed_n_students / f$population), " of the population), returned ", pct(f$passed_return_pct),
        "; never took it ", n(f$none_n_students), ", returned ", pct(f$none_return_pct),
        ": ", pts(f$lift_return), ". DFW'd it ", n(f$dfw_n_students), ", returned ", pct(f$dfw_return_pct), "."
      ))
      if (isTRUE(f$next_outcomes_observable) && !is.na(p$next_attempts) && p$next_attempts > 0L) {
        lines <- c(lines, paste0(
          "  Next-term DFW share: passed ", pct(f$passed_next_dfw_pct), ", never took it ",
          pct(f$none_next_dfw_pct), ": ", pts(f$lift_next_dfw), "; DFW'd it ", pct(f$dfw_next_dfw_pct), "."
        ))
      }
      if (nrow(lo) > 0L && (lo$n_early_drops > 0L || lo$n_unclassified > 0L)) {
        lines <- c(lines, paste0("  In no group: ", n(lo$n_early_drops), " early drops, ",
                                 n(lo$n_unclassified), " registered with no posted grade."))
      }
    }
    if (nrow(b) == 0L) {
      lines <- c(lines, paste0("  Benchmark: no ", meta$college_label, " course clears ", meta$min_n,
                               " in both groups."))
    } else {
      lines <- c(lines, paste0(
        "  Benchmark: ", plural(b$n_courses, paste(meta$college_label, "course")),
        ". Passing one: median return ", pct(b$passed_return_median), iqr(b$passed_return_q1, b$passed_return_q3),
        "; median gap ", pts(b$lift_return_median), iqr_pts(b$lift_return_q1, b$lift_return_q3),
        if (nrow(f) > 0L && !is.na(b$share_below_return))
          paste0("; ", meta$course, "'s gap is above ", share(b$share_below_return), " of them.")
        else "."
      ))
      if (!is.na(b$lift_next_dfw_median)) {
        lines <- c(lines, paste0(
          "  Next-term DFW share after passing one: median ", pct(b$passed_next_dfw_median),
          "; median gap ", pts(b$lift_next_dfw_median), iqr_pts(b$lift_next_dfw_q1, b$lift_next_dfw_q3),
          if (nrow(f) > 0L && !is.na(b$share_below_next_dfw))
            paste0("; ", meta$course, "'s gap is above ", share(b$share_below_next_dfw),
                   " of them (a larger gap is worse).")
          else "."
        ))
      }
    }
  }
  lines
}
