# Where does a population's path through its shared courses bind?
#
# The text-first preview behind the degree-map question "where are the
# blockages, where are the overlaps, where could a second-half or summer
# section smooth the path". For one population (a named group of programs,
# built by build_population()) and the courses several of its degree plans
# require, it assembles, per course and campus:
#
#   - how many of the population took the course, and when relative to
#     entering the unit (get_population_course_uptake());
#   - the DFW rate for the population beside the rate for every student
#     (get_course_outcome_rates(), twice);
#   - after a DFW, when the student sat in the course again
#     (get_course_retake_timing());
#   - in which seasons and parts of term the course is offered, with seats
#     and first-day fill (get_course_offering_pattern());
#   - how many of the plans require it.
#
# The payload is typed; format_population_course_pressure() is the one text
# rendering, and the only place a number is rounded. A Shiny surface, if one
# follows, reads the payload and never the text.

#' Build the population course pressure payload
#'
#' @param population `build_population()` output for the focal programs.
#' @param registrations `cedar_registrations`, keyed on the course.
#' @param attempts `cedar_attempts`.
#' @param course_terms `cedar_course_terms`.
#' @param opt `data_edges` (`cedar_data_edges()` output, required); `courses`
#'   (the courses to report) or, when NULL, `plan_courses` with `min_plans`
#'   (default 2) picks the courses at least that many plans require;
#'   `plan_courses` (optional tibble with `catalog_id`, `subject_course`: one
#'   row per plan and course it requires); `campus` (course campuses; NULL
#'   keeps every campus as its own row); `min_n` (small-cell guard for every
#'   table; default 10); `n_years` (offering window; default 3); `label`.
#' @return A list of class `population_course_pressure`: `courses` (one row
#'   per course and campus), `offerings` (the offering pattern rows) and
#'   `meta`.
build_population_course_pressure <- function(population, registrations, attempts, course_terms,
                                             opt = list()) {
  validate_population(population, "build_population_course_pressure")
  edges <- opt$data_edges
  if (is.null(edges) || !is.list(edges)) {
    stop("[population-course-pressure.R] opt$data_edges (cedar_data_edges() output) is required.",
         call. = FALSE)
  }
  settled_edge <- cedar_longitudinal_edge(edges)
  graded_edge <- cedar_longitudinal_edge(edges, grade_dependent = TRUE)
  if (is.null(settled_edge) || is.null(graded_edge)) {
    stop("[population-course-pressure.R] data_edges must carry last_enrolled_complete and ",
         "last_graded.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 10L)
  if (length(min_n) != 1L || is.na(min_n) || min_n < 1L) {
    stop("[population-course-pressure.R] opt$min_n must be a whole number of at least 1.",
         call. = FALSE)
  }
  n_years <- as.integer(opt$n_years %||% 3L)
  min_plans <- as.integer(opt$min_plans %||% 2L)

  plan_courses <- opt$plan_courses
  if (!is.null(plan_courses)) {
    missing <- setdiff(c("catalog_id", "subject_course"), names(plan_courses))
    if (length(missing) > 0) {
      stop("[population-course-pressure.R] opt$plan_courses lacks ",
           paste(missing, collapse = ", "), ".", call. = FALSE)
    }
    plan_courses <- plan_courses %>%
      distinct(catalog_id = as.character(catalog_id), subject_course = as.character(subject_course))
  }

  courses <- unique(as.character(opt$courses))
  if (length(courses) == 0L || all(is.na(courses))) {
    if (is.null(plan_courses)) {
      stop("[population-course-pressure.R] opt$courses or opt$plan_courses is required.",
           call. = FALSE)
    }
    courses <- plan_courses %>%
      # CAMPUS_ROLLUP: a catalog requirement names a course, not a campus.
      count(subject_course, name = "n_plans") %>%
      filter(n_plans >= min_plans) %>%
      arrange(desc(n_plans), subject_course) %>%
      pull(subject_course)
    if (length(courses) == 0L) {
      stop("[population-course-pressure.R] No course is required by ", min_plans,
           " or more of the plans given.", call. = FALSE)
    }
  }
  campus <- opt$campus

  # Which plans require each course; every requested course gets a row.
  plan_overlap <- tibble::tibble(subject_course = courses) %>%
    mutate(n_plans = 0L, plans = NA_character_)
  if (!is.null(plan_courses)) {
    counted <- plan_courses %>%
      filter(subject_course %in% courses) %>%
      # CAMPUS_ROLLUP: a catalog requirement names a course, not a campus.
      group_by(subject_course) %>%
      summarize(n_plans = dplyr::n_distinct(catalog_id),
                plans = paste(sort(unique(catalog_id)), collapse = ", "),
                .groups = "drop")
    plan_overlap <- plan_overlap %>%
      select(subject_course) %>%
      left_join(counted, by = "subject_course") %>%
      mutate(n_plans = as.integer(dplyr::coalesce(n_plans, 0L)))
  }

  uptake <- get_population_course_uptake(
    registrations, population,
    list(course = courses, campus = campus, data_edges = edges, min_n = min_n)
  )
  uptake_suppressed <- attr(uptake, "suppressed", exact = TRUE)
  n_population <- if (nrow(uptake)) uptake$n_population[[1]] else
    sum(!is.na(unique(population[, c("student_id", "first_unit_term")])$first_unit_term))

  pop_ids <- unique(population$student_id)
  rate_cols <- c("campus", "subject_course")
  rate_opt <- list(course = courses, course_campus = campus, data_edges = edges)
  pop_rates <- get_course_outcome_rates(
    attempts, c(rate_opt, list(population_ids = pop_ids)), group_cols = rate_cols, min_n = min_n
  )
  all_rates <- get_course_outcome_rates(attempts, rate_opt, group_cols = rate_cols, min_n = min_n)
  pick_rates <- function(rates, prefix) {
    out <- tibble::tibble(subject_course = character(), campus = character(),
                          n_attempts = integer(), n_dfw = integer(), dfw_pct = numeric())
    if (nrow(rates) > 0L) {
      out <- rates %>%
        transmute(subject_course, campus, n_attempts = as.integer(n_attempts),
                  n_dfw = as.integer(n_dfw), dfw_pct)
    }
    stats::setNames(out, c("subject_course", "campus",
                           paste0(prefix, c("n_attempts", "n_dfw", "dfw_pct"))))
  }

  retakes <- get_course_retake_timing(
    attempts, registrations,
    c(rate_opt, list(population_ids = pop_ids, min_n = min_n))
  )
  retake_suppressed <- attr(retakes, "suppressed", exact = TRUE)

  offerings <- get_course_offering_pattern(
    course_terms, list(course = courses, campus = campus, data_edges = edges, n_years = n_years)
  )

  # The grain: every course and campus any of the four saw, including the
  # suppressed ones, so the text can say "suppressed" instead of nothing.
  keys <- bind_rows(
    uptake[, c("subject_course", "campus")],
    uptake_suppressed[, c("subject_course", "campus")],
    all_rates[, intersect(c("subject_course", "campus"), names(all_rates))],
    retakes[, c("subject_course", "campus")],
    retake_suppressed[, c("subject_course", "campus")],
    offerings[, c("subject_course", "campus")]
  ) %>%
    distinct() %>%
    filter(subject_course %in% courses)

  courses_tbl <- keys %>%
    left_join(plan_overlap, by = "subject_course") %>%
    left_join(
      uptake %>% select(subject_course, campus, n_takers, share, n_before_entry, n_after_entry,
                        median_terms_after_entry, p75_terms_after_entry),
      by = c("subject_course", "campus")
    ) %>%
    left_join(
      uptake_suppressed %>% transmute(subject_course, campus, uptake_suppressed_n = n_takers),
      by = c("subject_course", "campus")
    ) %>%
    left_join(pick_rates(pop_rates, "pop_"), by = c("subject_course", "campus")) %>%
    left_join(pick_rates(all_rates, "all_"), by = c("subject_course", "campus")) %>%
    left_join(
      retakes %>% select(subject_course, campus, n_dfw_judged = n_dfw, n_next_regular, n_summer,
                         n_within_year_other, n_none_within_year, n_unobservable),
      by = c("subject_course", "campus")
    ) %>%
    left_join(
      retake_suppressed %>% transmute(subject_course, campus, retake_suppressed_n = n_dfw),
      by = c("subject_course", "campus")
    ) %>%
    mutate(
      n_population = as.integer(n_population),
      uptake_suppressed = !is.na(uptake_suppressed_n),
      retake_suppressed = !is.na(retake_suppressed_n)
    ) %>%
    arrange(factor(subject_course, levels = courses), campus) %>%
    select(subject_course, campus, n_plans, plans, n_population, n_takers, share, n_before_entry,
           n_after_entry, median_terms_after_entry, p75_terms_after_entry, uptake_suppressed,
           pop_n_attempts, pop_n_dfw, pop_dfw_pct, all_n_attempts, all_n_dfw, all_dfw_pct,
           n_dfw_judged, n_next_regular, n_summer, n_within_year_other, n_none_within_year,
           n_unobservable, retake_suppressed)

  window <- attr(offerings, "window", exact = TRUE)
  structure(
    list(
      courses = courses_tbl,
      offerings = offerings,
      meta = list(
        label = opt$label %||% unique(population$population_label)[[1]],
        n_population = as.integer(n_population),
        n_without_entry = attr(uptake, "n_without_entry", exact = TRUE),
        courses = courses,
        not_taken = attr(uptake, "not_taken", exact = TRUE),
        campus = campus,
        settled_edge = as.integer(settled_edge),
        graded_edge = as.integer(graded_edge),
        window = window,
        n_years = n_years,
        min_n = min_n,
        n_plans = if (is.null(plan_courses)) NA_integer_ else
          as.integer(dplyr::n_distinct(plan_courses$catalog_id))
      )
    ),
    class = "population_course_pressure"
  )
}


#' The text preview of a population course pressure payload
#'
#' The one text rendering and the only place a number is rounded: counts
#' whole, shares and rates one decimal, fill as a whole percent.
#'
#' @param payload `build_population_course_pressure()` output.
#' @return A character vector, one line each.
format_population_course_pressure <- function(payload) {
  if (!inherits(payload, "population_course_pressure")) {
    stop("[population-course-pressure.R] payload must come from build_population_course_pressure().",
         call. = FALSE)
  }
  meta <- payload$meta
  n <- function(x) ifelse(is.na(x), "—", format(as.integer(round(x)), big.mark = ","))
  pct <- function(x) ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = 1), "%"))
  share_pct <- function(x) pct(100 * x)
  whole_pct <- function(x) ifelse(is.na(x), "unknown", paste0(round(100 * x), "%"))
  # A median of whole numbers is whole or ends in .5: one decimal only then.
  num <- function(x) {
    ifelse(is.na(x), "—",
           ifelse(x == round(x), format(round(x), big.mark = ","), formatC(x, format = "f", digits = 1)))
  }
  terms <- function(x) ifelse(is.na(x), "—", ifelse(x == 1, "1 term", paste0(num(x), " terms")))
  season_label <- function(term_type) {
    paste0(toupper(substr(term_type, 1, 1)), substr(term_type, 2, nchar(term_type)))
  }
  part_label <- function(part_term) ifelse(part_term %in% "1", "full term", part_term)

  lines <- c(
    paste0("Population course pressure: ", meta$label),
    paste0(
      "Population: ", n(meta$n_population), " students with a unit entry term",
      if (isTRUE(meta$n_without_entry > 0)) paste0(" (", n(meta$n_without_entry), " without one left out)") else "",
      "; courses: ", length(meta$courses),
      if (!is.na(meta$n_plans)) paste0("; plans: ", meta$n_plans) else "",
      "; campus: ", if (is.null(meta$campus)) "each campus its own row" else paste(meta$campus, collapse = ", ")
    ),
    paste0(
      "Edges: enrollment settled through ", fmt_term(meta$settled_edge),
      "; grades through ", fmt_term(meta$graded_edge),
      "; offerings over ",
      if (all(is.na(meta$window))) "no covered terms" else
        paste0(fmt_term(meta$window[["first"]]), " to ", fmt_term(meta$window[["last"]])),
      " (", meta$n_years, if (meta$n_years == 1) " year)" else " years)"
    ),
    paste0("Small cells: a course-campus row needs ", meta$min_n,
           " takers, attempts or judged DFWs to be shown.")
  )

  courses <- payload$courses
  offerings <- payload$offerings
  for (i in seq_len(nrow(courses))) {
    row <- courses[i, ]
    plans_line <- if (is.na(row$n_plans) || is.na(row$plans)) {
      ""
    } else if (row$n_plans == 0L) {
      " — required by none of the plans"
    } else {
      paste0(" — required by ", row$n_plans, if (row$n_plans == 1L) " plan: " else " plans: ", row$plans)
    }
    lines <- c(lines, "", paste0(row$subject_course, " (", row$campus, ")", plans_line))

    if (isTRUE(row$uptake_suppressed)) {
      lines <- c(lines, paste0("  Taken by fewer than ", meta$min_n, " of ", n(row$n_population),
                               "; uptake suppressed"))
    } else if (!is.na(row$n_takers)) {
      lines <- c(lines, paste0(
        "  Taken by ", n(row$n_takers), " of ", n(row$n_population), " (", share_pct(row$share), "); ",
        n(row$n_before_entry), " before entering the unit; of the ", n(row$n_after_entry),
        " at or after entry, median ", terms(row$median_terms_after_entry),
        " after entry (75th percentile ", terms(row$p75_terms_after_entry), ")"
      ))
    } else {
      lines <- c(lines, "  Taken by no one in the population")
    }

    lines <- c(lines, paste0(
      "  DFW: population ",
      if (is.na(row$pop_n_attempts)) "suppressed or none" else
        paste0(pct(row$pop_dfw_pct), " of ", n(row$pop_n_attempts), " attempts"),
      "; all students ",
      if (is.na(row$all_n_attempts)) "suppressed or none" else
        paste0(pct(row$all_dfw_pct), " of ", n(row$all_n_attempts), " attempts")
    ))

    if (isTRUE(row$retake_suppressed)) {
      lines <- c(lines, paste0("  After a DFW: fewer than ", meta$min_n, " judged; retake timing suppressed"))
    } else if (!is.na(row$n_dfw_judged)) {
      lines <- c(lines, paste0(
        "  After a DFW (population): ", n(row$n_dfw_judged), " judged; retook next regular term ",
        share_pct(row$n_next_regular / row$n_dfw_judged), ", in a summer ",
        share_pct(row$n_summer / row$n_dfw_judged), ", later within the year ",
        share_pct(row$n_within_year_other / row$n_dfw_judged), ", not within a year ",
        share_pct(row$n_none_within_year / row$n_dfw_judged),
        if (isTRUE(row$n_unobservable > 0)) paste0("; ", n(row$n_unobservable), " too recent to judge") else ""
      ))
    }

    offered <- offerings %>% filter(subject_course == row$subject_course, campus == row$campus)
    if (nrow(offered) == 0L) {
      lines <- c(lines, "  Offered: not in the window")
    } else {
      parts <- vapply(seq_len(nrow(offered)), function(j) {
        o <- offered[j, ]
        paste0(
          season_label(o$term_type), " ", part_label(o$part_term), " ",
          o$n_terms_offered, " of ", o$n_terms_in_window,
          " (median ", num(o$median_sections), if (o$median_sections == 1) " section, " else " sections, ",
          n(o$median_seats), " seats; day-1 fill ",
          if (o$n_terms_fill_known == 0L) "unknown" else
            paste0(whole_pct(o$median_first_day_fill), " median, full ", o$n_terms_full, " of ",
                   o$n_terms_fill_known, ", near full ", o$n_terms_near_full, " of ", o$n_terms_fill_known),
          ")"
        )
      }, character(1))
      lines <- c(lines, paste0("  Offered: ", paste(parts, collapse = "; ")))
    }
  }

  not_taken <- setdiff(meta$not_taken, courses$subject_course)
  if (length(not_taken) > 0) {
    lines <- c(lines, "", paste0("Not taken by anyone in the population and not offered in the window: ",
                                 paste(not_taken, collapse = ", ")))
  }
  lines
}
