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
#'   ungraded takers); `balance` (with `programs`: the cone's balance table
#'   for the focal course's takers against its never-takers, else NULL).
#' @param programs `cedar_programs`, for the balance table; NULL skips it.
build_course_cohort_context <- function(student_terms, attempts, opt = list(), programs = NULL) {
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

  payload <- structure(list(
    meta = list(
      course = course,
      classification = opt$classification,
      college = college,
      college_label = opt$college_label %||% paste(college, collapse = "/"),
      level = opt$level,
      campus = opt$campus,
      terms = sort(unique(res$population$term)),
      anchor_terms = opt$term,
      data_edges = opt$data_edges,
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
    left_out = res$left_out %>% filter(course == .env$course),
    balance = NULL
  ), class = "course_cohort_context")
  if (!is.null(programs)) {
    payload <- course_cohort_context_balance(payload, student_terms, attempts, programs)
  }
  payload
}


#' Attach the focal course's balance table to a payload
#'
#' The balance table is one course's (the cone refuses several), so it is a
#' second, focal-only run of the cone with `programs`. Separate from the
#' build so a page can show the groups when the programs table lacks the
#' demographic columns the balance needs, and say why the table is missing.
#'
#' @param payload `build_course_cohort_context()` output.
#' @param student_terms,attempts,programs The tables the payload was built from.
#' @return The payload with `balance` set.
course_cohort_context_balance <- function(payload, student_terms, attempts, programs) {
  if (!inherits(payload, "course_cohort_context")) {
    stop("[course-cohort-context.R] payload must come from build_course_cohort_context().", call. = FALSE)
  }
  if (is.null(programs)) stop("[course-cohort-context.R] programs is required for the balance table.", call. = FALSE)
  meta <- payload$meta
  opt <- list(course = meta$course, classification = meta$classification, campus = meta$campus,
              term = meta$anchor_terms, min_n = meta$min_n, data_edges = meta$data_edges)
  payload$balance <- get_course_cohort_effect(student_terms, attempts, opt, programs = programs)$balance
  payload
}


#' Where a page starts: the focal course's own classification, college, level and terms
#'
#' The controls a page opens with, read off the data rather than written into
#' it: every term to the settled edge of the term type most of the course's
#' takers took it in (a Fall cohort and a Spring one are different
#' populations, and a gap is read across many terms of one type), the
#' classification most of those terms' takers held, and the college and level
#' their attempt rows carry. An institution's names never appear in platform
#' code.
#'
#' @param course The focal course id.
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`.
#' @param edges `cedar_data_edges()` output.
#' @param opt `term_type` (one or more of `fall`, `spring`, `summer`; default
#'   the type holding most of the course's taker student-terms, Fall before
#'   Spring before Summer on a tie), `campus` (a page's campus selection, kept
#'   where it is a home campus).
#' @return A list: `classification` (one value), `college` (the college that
#'   taught most of the recent takers' other same-level courses, else the
#'   course's own), `level`, `term_type`, `terms` (every anchor term of
#'   `term_type` to the settled edge, oldest first), `campus` (NULL when none
#'   of `opt$campus` is a home campus), and `choices` (`classifications`,
#'   `campuses`, `term_types`, `terms`: every value the controls may offer,
#'   each with the enrolled student-terms behind it where that is a count).
course_cohort_context_defaults <- function(course, student_terms, attempts, edges, opt = list()) {
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-cohort-context.R] course (one focal course id) is required.", call. = FALSE)
  }
  for (col in c("student_id", "term", "subject_course", "college", "level")) {
    if (!col %in% names(attempts)) stop("[course-cohort-context.R] attempts lacks ", col, call. = FALSE)
  }
  for (col in c("student_id", "term", "enrolled", "student_classification", "student_campus")) {
    if (!col %in% names(student_terms)) stop("[course-cohort-context.R] student_terms lacks ", col, call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(edges)
  if (is.null(edge)) {
    stop("[course-cohort-context.R] edges has no settled enrollment edge.", call. = FALSE)
  }

  enrolled <- student_terms %>% filter(enrolled, term <= edge)
  all_terms <- sort(unique(enrolled$term))
  term_types <- intersect(c("fall", "spring", "summer"), get_term_type(all_terms))

  takers <- attempts %>% filter(subject_course == .env$course, term <= edge)
  if (nrow(takers) == 0L) {
    stop("[course-cohort-context.R] ", course, " has no graded attempt to ", edge, ".", call. = FALSE)
  }
  term_type <- opt$term_type
  if (is.null(term_type)) {
    # which.max() takes the first of a tie, and term_types is in season order.
    taker_terms <- takers %>% distinct(student_id, term)
    per_type <- vapply(term_types, function(type) sum(get_term_type(taker_terms$term) == type), integer(1))
    term_type <- term_types[[which.max(per_type)]]
  }
  unknown <- setdiff(term_type, term_types)
  if (length(unknown) > 0L) {
    stop("[course-cohort-context.R] opt$term_type names no term in the data: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  terms <- all_terms[get_term_type(all_terms) %in% term_type]
  modal <- function(x) {
    x <- x[!is.na(x)]
    if (length(x) == 0L) return(NA_character_)
    names(sort(table(x), decreasing = TRUE))[[1]]
  }
  recent <- takers %>% filter(term %in% terms)
  if (nrow(recent) == 0L) recent <- takers
  recent_takers <- recent %>% distinct(student_id, term)
  classification <- recent_takers %>%
    inner_join(enrolled %>% select(student_id, term, student_classification), by = c("student_id", "term")) %>%
    pull(student_classification) %>%
    modal()
  level <- modal(recent$level)
  # "An average course" for these students is one of the courses they were
  # taking alongside this one: the college that taught most of the takers'
  # other same-level courses those terms, not the college that owns this one.
  alongside <- attempts %>%
    semi_join(recent_takers, by = c("student_id", "term")) %>%
    filter(subject_course != .env$course, level %in% .env$level)
  college <- modal(alongside$college)
  if (is.na(college)) college <- modal(recent$college)

  campuses <- sort(unique(enrolled$student_campus[!is.na(enrolled$student_campus)]))
  campus <- intersect(as.character(opt$campus %||% character(0)), campuses)

  list(
    classification = classification,
    college = college,
    level = level,
    term_type = term_type,
    terms = terms,
    campus = if (length(campus) > 0L) campus else NULL,
    choices = list(
      classifications = enrolled %>% count(student_classification, name = "n_student_terms") %>%
        filter(!is.na(student_classification)) %>% arrange(desc(n_student_terms)),
      campuses = campuses,
      term_types = term_types,
      terms = all_terms
    )
  )
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
