# course-topics.R: Course Dynamics > Topics
#
# A course number that carries many courses (FYEX 1110's seminars, a
# special-topics slot) read one topic at a time, and the topics set beside
# each other: sections, students at census, fill, DFW and return the next
# regular term, by term and pooled. Topics are compared only within the one
# course.
#
# This file assembles the page's payload from one cone and holds everything
# the page shows that is not layout:
#
#   build_course_topics()          the payload (get_course_topic_terms())
#   course_topics_term_types()     the term types the course was taught in
#   course_topics_term_table()     one row per campus, term and topic, with
#                                  every topic's total ("All topics")
#   course_topics_summary()        the same pooled over settled terms
#   course_topics_choices()        the topics, most students first
#   plot_course_topics()           one measure by term, a line per topic
#   course_topics_titles()         every title and the topic it counts under
#   course_topics_withheld_any()   whether the gate hides anything in scope
#   course_topics_scope_note()     which edges bound the page
#   format_course_topics()         the payload as text (text-first preview)
#
# Withheld rates. A topic taught by one instructor in a term has that
# instructor's DFW and return rates, so for a viewer without the instructor
# password (instructor_access) they are withheld:
#   1. a topic-term with fewer than two recorded instructors;
#   2. in a campus-term where exactly one topic is withheld by rule 1, the
#      smallest other topic too, since the course's total for the term is
#      shown to everyone (here as All topics, and on the DFW tab) and would
#      give the first back by subtraction;
#   3. pooled over terms, a topic's rates cover only its terms not withheld.
# Rule 3 makes a pooled row the sum of rows already shown, so subtracting it
# from the pooled total gives back only the withheld topic-terms' sum, which
# rule 2 leaves mixing instructors (or, for a campus-term with one topic,
# equal to the course's public total). Counts of students, sections and seats
# are never withheld.
#
# The payload is typed and unrounded; the module rounds once, in its column
# definitions. format_course_topics() is the one text rendering of it.
#
# Depends on: get_course_topic_terms() (cones/course-topics.R)
#             CEDAR_TOPIC_TITLES, topic_title_text() (lists/topic_titles.R)
#             fmt_term(), term_axis_factor(), mark_plotly_terms(),
#             build_color_map(), CEDAR_SEMANTIC_COLORS (trunk/utils.R)

COURSE_TOPICS_TERM_TYPES <- c("fall", "spring", "summer")

#' The label of each campus-term's (and campus's) total over every topic.
COURSE_TOPICS_ALL <- "All topics"

#' The measures the chart draws, and how each is named and read.
COURSE_TOPICS_MEASURES <- list(
  census_enrl = list(label = "Students at census", rate = FALSE),
  sections    = list(label = "Sections", rate = FALSE),
  fill_pct    = list(label = "Census fill", rate = TRUE),
  dfw_pct     = list(label = "DFW rate", rate = TRUE),
  return_pct  = list(label = "Returned next regular term", rate = TRUE)
)

.course_topics_check <- function(payload) {
  if (!inherits(payload, "course_topics")) {
    stop("[course-topics.R] payload must come from build_course_topics().", call. = FALSE)
  }
  invisible(payload)
}

.course_topics_n <- function(x) format(as.integer(x), big.mark = ",", scientific = FALSE, trim = TRUE)

.course_topics_pct <- function(x) {
  ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = 1), "%"))
}

#' The Topics payload
#'
#' @param sections,students,attempts,student_terms CEDAR tables.
#' @param opt Named list: `course` (one course id), `campus` (NULL for every
#'   campus), `data_edges` (required), `min_n` (smallest denominator a rate is
#'   shown for; default 10).
#' @param topic_titles The reviewed title merges; CEDAR_TOPIC_TITLES.
#' @return get_course_topic_terms()'s output with `min_n` and each topic-term
#'   marked `withheld_reason` (NA, "one_instructor" or "complement": rules 1
#'   and 2 above), classed `course_topics`.
build_course_topics <- function(sections, students, attempts, student_terms, opt = list(),
                                topic_titles = CEDAR_TOPIC_TITLES) {
  cone_opt <- opt[intersect(names(opt), c("course", "campus", "data_edges"))]
  result <- get_course_topic_terms(sections, students, attempts, student_terms, topic_titles, cone_opt)
  result$terms <- .course_topics_withhold(result$terms)
  structure(
    c(result, list(min_n = as.integer(opt[["min_n"]] %||% 10L))),
    class = c("course_topics", "list")
  )
}

# Rules 1 and 2, per campus-term, over the topic-terms that have an outcome
# to withhold.
.course_topics_withhold <- function(terms) {
  terms %>%
    arrange(campus, term, topic) %>%
    mutate(.has = coalesce(attempts, 0L) > 0L,
           .one = .has & n_instructors < 2L) %>%
    group_by(campus, term) %>%
    mutate(
      # The complement is the open topic with the fewest graded students, the
      # first by name on a tie.
      .order = if_else(.has & !.one, coalesce(attempts, 0L) + seq_along(topic) / (n() + 1), Inf),
      .complement = sum(.one) == 1L & is.finite(.order) & .order == min(.order)
    ) %>%
    ungroup() %>%
    mutate(withheld_reason = case_when(.one ~ "one_instructor",
                                       .complement ~ "complement",
                                       TRUE ~ NA_character_)) %>%
    select(-.has, -.one, -.order, -.complement)
}

#' The term types the course was taught in
#'
#' @param payload [build_course_topics()] output.
#' @return Character vector in fall, spring, summer order.
course_topics_term_types <- function(payload) {
  .course_topics_check(payload)
  intersect(COURSE_TOPICS_TERM_TYPES, unique(payload$terms$term_type))
}

.course_topics_types_arg <- function(payload, term_types) {
  if (is.null(term_types)) return(course_topics_term_types(payload))
  unknown <- setdiff(term_types, COURSE_TOPICS_TERM_TYPES)
  if (length(unknown) > 0L) {
    stop("[course-topics.R] Unknown term type: ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  term_types
}

# The rates from the counts, each under the payload's minimum, withheld where
# the viewer may not see them.
.course_topics_rates <- function(rows, unlocked, min_n) {
  rows %>%
    mutate(
      withheld = !isTRUE(unlocked) & !is.na(withheld_reason),
      fill_pct = if_else(seats_known & crosslisted_sections == 0L & seats > 0,
                         100 * census_enrl / seats, NA_real_),
      dfw_pct = if_else(!withheld & coalesce(attempts, 0L) >= min_n, 100 * dfw / attempts, NA_real_),
      return_pct = if_else(!withheld & coalesce(n_return_observable, 0L) >= min_n,
                           100 * n_returned / n_return_observable, NA_real_),
      passed = if_else(withheld, NA_integer_, passed),
      dfw = if_else(withheld, NA_integer_, dfw),
      n_returned = if_else(withheld, NA_integer_, n_returned)
    )
}

.course_topics_sum <- function(rows) {
  rows %>% summarize(
    sections = sum(sections),
    crosslisted_sections = sum(crosslisted_sections),
    seats = sum(seats, na.rm = TRUE),
    seats_known = all(seats_known),
    registered = sum(registered),
    dr_late = sum(dr_late),
    census_enrl = sum(census_enrl),
    attempts = if (all(is.na(attempts))) NA_integer_ else sum(attempts, na.rm = TRUE),
    passed = if (all(is.na(passed))) NA_integer_ else sum(passed, na.rm = TRUE),
    dfw = if (all(is.na(dfw))) NA_integer_ else sum(dfw, na.rm = TRUE),
    n_return_observable = if (all(is.na(n_return_observable))) NA_integer_ else sum(n_return_observable, na.rm = TRUE),
    n_returned = if (all(is.na(n_returned))) NA_integer_ else sum(n_returned, na.rm = TRUE),
    .groups = "drop"
  )
}

.course_topics_instructor_count <- function(payload, rows, by) {
  payload$instructors %>%
    semi_join(rows, by = c("campus", "term", "topic_key")) %>%
    group_by(across(all_of(by))) %>%
    summarize(n_instructors = n_distinct(instructor_id), .groups = "drop")
}

.course_topics_term_cols <- c(
  "campus", "term", "term_type", "topic_key", "topic", "is_total", "sections", "seats",
  "census_enrl", "fill_pct", "n_instructors", "attempts", "passed", "dfw", "dfw_pct",
  "n_return_observable", "n_returned", "return_pct", "in_progress", "withheld", "withheld_reason"
)

#' One row per campus, term and topic
#'
#' Each campus-term also has an All topics row (`is_total`), the sum of its
#' topics, which is never withheld: it is the course's own total.
#'
#' @param payload [build_course_topics()] output.
#' @param term_types Term types to keep; NULL keeps all.
#' @param unlocked TRUE when the viewer has the instructor password.
#' @param min_n Smallest denominator a rate is shown for; the payload's by
#'   default.
#' @return Columns `.course_topics_term_cols`, oldest term first, each
#'   campus-term's total before its topics (most students first).
#'   `withheld` is TRUE where this viewer sees no rate and no DFW or return
#'   count; `withheld_reason` says why for any viewer.
course_topics_term_table <- function(payload, term_types = NULL, unlocked = FALSE,
                                     min_n = payload$min_n) {
  .course_topics_check(payload)
  types <- .course_topics_types_arg(payload, term_types)
  rows <- payload$terms %>% filter(term_type %in% types)
  totals <- rows %>%
    group_by(campus, term, term_type, in_progress) %>%
    .course_topics_sum() %>%
    left_join(.course_topics_instructor_count(payload, rows, c("campus", "term")),
              by = c("campus", "term")) %>%
    mutate(topic_key = NA_character_, topic = COURSE_TOPICS_ALL, is_total = TRUE,
           n_instructors = coalesce(n_instructors, 0L), withheld_reason = NA_character_)
  bind_rows(mutate(rows, is_total = FALSE), totals) %>%
    .course_topics_rates(unlocked, min_n) %>%
    arrange(campus, term, desc(is_total), desc(census_enrl), topic) %>%
    select(all_of(.course_topics_term_cols))
}

#' Each topic pooled over the settled terms
#'
#' Students, sections and seats are pooled over every settled term. For a
#' viewer without the instructor password, a topic's DFW and return are
#' pooled over only its terms whose rates are shown, so the pooled row is the
#' sum of rows the term table already shows (`rate_terms` of `graded_terms`);
#' a topic with every graded term withheld has none.
#'
#' @inheritParams course_topics_term_table
#' @return One row per campus and topic, each campus's All topics row first,
#'   then its topics with the most students first: `campus`, `topic_key`,
#'   `topic`, `is_total`, `terms` (terms it was offered), `first_term`,
#'   `last_term`, `sections`, `census_enrl`, `avg_section`, `seats`,
#'   `fill_pct` (only when every term's fill is known), `n_instructors`
#'   (distinct over the terms), `graded_terms` (terms with a graded student),
#'   `withheld_terms` (of them, those whose rates a viewer without the
#'   password does not see), `rate_terms` (the terms this viewer's rates are
#'   pooled over), `attempts`, `passed`, `dfw`, `dfw_pct`,
#'   `n_return_observable`, `n_returned`, `return_pct`, `withheld` (this
#'   viewer sees no rate) and `partial` (this viewer's rates leave some
#'   graded terms out).
course_topics_summary <- function(payload, term_types = NULL, unlocked = FALSE,
                                  min_n = payload$min_n) {
  .course_topics_check(payload)
  types <- .course_topics_types_arg(payload, term_types)
  rows <- payload$terms %>%
    filter(term_type %in% types, !in_progress) %>%
    mutate(.graded = coalesce(attempts, 0L) > 0L,
           .shown = isTRUE(unlocked) | is.na(withheld_reason))
  outcome_cols <- c("attempts", "passed", "dfw", "n_return_observable", "n_returned")
  pool <- function(by, total) {
    # The instructor rows carry the topic's key, not its label.
    by_instructor <- setdiff(by, "topic")
    shown <- if (total) rows else rows %>% filter(.shown)
    counts <- rows %>%
      group_by(across(all_of(by))) %>%
      summarize(terms = n_distinct(term[sections > 0L]),
                first_term = as.integer(min(term)), last_term = as.integer(max(term)),
                graded_terms = n_distinct(term[.graded]),
                withheld_terms = if (total) 0L else n_distinct(term[.graded & !is.na(withheld_reason)]),
                .groups = "drop") %>%
      left_join(rows %>% group_by(across(all_of(by))) %>% .course_topics_sum() %>%
                  select(-all_of(outcome_cols)), by = by)
    outcomes <- shown %>%
      group_by(across(all_of(by))) %>%
      .course_topics_sum() %>%
      select(all_of(c(by, outcome_cols))) %>%
      left_join(shown %>% group_by(across(all_of(by))) %>%
                  summarize(rate_terms = n_distinct(term[.graded]), .groups = "drop"), by = by)
    counts %>%
      left_join(outcomes, by = by) %>%
      left_join(.course_topics_instructor_count(payload, rows, by_instructor), by = by_instructor)
  }
  bind_rows(
    pool(c("campus", "topic_key", "topic"), total = FALSE) %>% mutate(is_total = FALSE),
    pool("campus", total = TRUE) %>%
      mutate(topic_key = NA_character_, topic = COURSE_TOPICS_ALL, is_total = TRUE)
  ) %>%
    mutate(
      n_instructors = coalesce(n_instructors, 0L),
      rate_terms = coalesce(rate_terms, 0L),
      withheld = !isTRUE(unlocked) & withheld_terms > 0L & rate_terms == 0L,
      partial = !isTRUE(unlocked) & withheld_terms > 0L & rate_terms > 0L,
      fill_pct = if_else(seats_known & crosslisted_sections == 0L & seats > 0,
                         100 * census_enrl / seats, NA_real_),
      dfw_pct = if_else(coalesce(attempts, 0L) >= min_n, 100 * dfw / attempts, NA_real_),
      return_pct = if_else(coalesce(n_return_observable, 0L) >= min_n,
                           100 * n_returned / n_return_observable, NA_real_),
      avg_section = if_else(sections > 0L, census_enrl / sections, NA_real_)
    ) %>%
    arrange(campus, desc(is_total), desc(census_enrl), topic) %>%
    select(campus, topic_key, topic, is_total, terms, first_term, last_term, sections, census_enrl,
           avg_section, seats, fill_pct, n_instructors, graded_terms, withheld_terms, rate_terms,
           attempts, passed, dfw, dfw_pct, n_return_observable, n_returned, return_pct,
           withheld, partial)
}

#' The course's topics, most students first
#'
#' @inheritParams course_topics_term_table
#' @return A named character vector: topic keys, named by topic, ordered by
#'   students at census over the settled terms of `term_types` (every campus
#'   together), then topics taught only in progress.
course_topics_choices <- function(payload, term_types = NULL) {
  .course_topics_check(payload)
  types <- .course_topics_types_arg(payload, term_types)
  ranked <- payload$terms %>%
    filter(term_type %in% types) %>%
    group_by(topic_key, topic) %>%
    summarize(.settled = sum(census_enrl[!in_progress]), .all = sum(census_enrl), .groups = "drop") %>%
    arrange(desc(.settled), desc(.all), topic)
  stats::setNames(ranked$topic_key, ranked$topic)
}

#' One measure by term, a line per topic
#'
#' A line never joins a Fall term to a Spring one: each term type drawn has
#' its own line, its marker telling them apart. Topics differ by colour,
#' campuses by line style. For a rate, All topics is drawn in grey as the
#' course's own line to read the topics against. Withheld and under-minimum
#' rates are not drawn; an in-progress term is shaded.
#'
#' @inheritParams course_topics_term_table
#' @param measure One of names(COURSE_TOPICS_MEASURES).
#' @param topics Topic keys to draw.
#' @return A plotly object, or NULL when nothing has a value to draw.
plot_course_topics <- function(payload, measure, topics, term_types = NULL, unlocked = FALSE,
                               min_n = payload$min_n) {
  .course_topics_check(payload)
  if (!measure %in% names(COURSE_TOPICS_MEASURES)) {
    stop("[course-topics.R] Unknown measure: ", measure, call. = FALSE)
  }
  spec <- COURSE_TOPICS_MEASURES[[measure]]
  rows <- course_topics_term_table(payload, term_types, unlocked, min_n) %>%
    filter(topic_key %in% topics | (is_total & spec$rate)) %>%
    mutate(.y = .data[[measure]]) %>%
    filter(!is.na(.y))
  if (nrow(rows) == 0L) return(NULL)
  rows <- rows %>% arrange(term) %>% mutate(term_label = term_axis_factor(term))
  denominators <- list(census_enrl = NULL, sections = NULL, fill_pct = "seats",
                       dfw_pct = "attempts", return_pct = "n_return_observable")
  den <- denominators[[measure]]
  rows$.den <- if (is.null(den)) NA_real_ else as.numeric(rows[[den]])
  topic_labels <- unique(rows$topic[!rows$is_total])
  colors <- build_color_map(topic_labels)
  campuses <- sort(unique(rows$campus))
  dashes <- stats::setNames(rep_len(c("solid", "dot", "dash", "dashdot"), length(campuses)), campuses)
  symbols <- c(fall = "circle", spring = "square", summer = "diamond")
  types <- intersect(COURSE_TOPICS_TERM_TYPES, unique(rows$term_type))
  hover <- if (spec$rate) {
    paste0("%{x}<br>", spec$label, ": %{y:.1%} of %{customdata}<extra>%{fullData.name}</extra>")
  } else {
    paste0("%{x}<br>", spec$label, ": %{y:,}<extra>%{fullData.name}</extra>")
  }
  p <- plotly::plot_ly()
  for (label in c(topic_labels, if (spec$rate) COURSE_TOPICS_ALL)) {
    total <- identical(label, COURSE_TOPICS_ALL)
    color <- if (total) unname(CEDAR_SEMANTIC_COLORS["reference"]) else unname(colors[[label]])
    for (cmp in campuses) {
      for (type in types) {
        d <- rows[rows$topic == label & rows$campus == cmp & rows$term_type == type, , drop = FALSE]
        if (nrow(d) == 0L) next
        p <- plotly::add_trace(
          p, data = d, x = ~term_label, y = if (spec$rate) ~.y / 100 else ~.y, customdata = ~.den,
          type = "scatter", mode = "lines+markers",
          name = paste(c(label, if (length(campuses) > 1L) cmp,
                         if (length(types) > 1L) tools::toTitleCase(type)), collapse = ", "),
          legendgroup = label,
          line = list(color = color, dash = dashes[[cmp]], width = if (total) 3 else 2),
          marker = list(color = color, symbol = symbols[[type]]),
          hovertemplate = hover
        )
      }
    }
  }
  p <- plotly::layout(
    p,
    xaxis = list(title = "", tickangle = -45,
                 categoryorder = "array", categoryarray = levels(rows$term_label)),
    yaxis = if (spec$rate) list(title = spec$label, tickformat = ".0%", rangemode = "tozero")
            else list(title = spec$label, rangemode = "tozero"),
    legend = list(orientation = "h", x = 0, y = -0.3)
  )
  mark_plotly_terms(p, as.character(unique(rows$term_label[rows$in_progress])))
}

#' Every title the course's offered sections carried, and its topic
#'
#' @param payload [build_course_topics()] output.
#' @return One row per campus and title: `campus`, `topic`, `course_title`,
#'   `read_as` ("its own title", "the same words" when the wording-blind key
#'   matched it to a differently worded title, "topic_titles.csv", or "no
#'   title"), `sections`, `first_term`, `last_term`; grouped by topic.
course_topics_titles <- function(payload) {
  .course_topics_check(payload)
  payload$titles %>%
    mutate(read_as = case_when(
      topic_basis == "topic_titles" ~ "topic_titles.csv",
      topic_basis == "no_title" ~ "no title",
      topic_title_text(course_title) == topic ~ "its own title",
      TRUE ~ "the same words"
    )) %>%
    arrange(campus, topic, desc(read_as == "its own title"), course_title) %>%
    select(campus, topic, course_title, read_as, sections, first_term, last_term)
}

#' Does the instructor gate hide anything in this scope?
#'
#' @inheritParams course_topics_term_table
#' @return TRUE when some topic-term of `term_types` has a withheld outcome.
course_topics_withheld_any <- function(payload, term_types = NULL) {
  .course_topics_check(payload)
  types <- .course_topics_types_arg(payload, term_types)
  any(!is.na(payload$terms$withheld_reason[payload$terms$term_type %in% types]))
}

#' Which edges bound the page, in one sentence
#'
#' @param payload [build_course_topics()] output.
course_topics_scope_note <- function(payload) {
  .course_topics_check(payload)
  paste0(
    "Terms run through ", fmt_term(payload$last_enrolled), ". A term after ", fmt_term(payload$settled_edge),
    ", the most recent whose registration has settled, is in progress and counts current registration. ",
    "Grades are read through ", fmt_term(payload$graded_edge),
    ", and return to the next regular term once that term has settled."
  )
}

#' The Topics payload as plain text (the text-first preview)
#'
#' @inheritParams course_topics_term_table
#' @return Character vector of lines.
format_course_topics <- function(payload, term_types = NULL, unlocked = FALSE) {
  .course_topics_check(payload)
  n <- .course_topics_n
  pct <- .course_topics_pct
  types <- .course_topics_types_arg(payload, term_types)
  plural <- function(k, word) paste0(n(k), " ", word, if (k == 1L) "" else "s")
  rate <- function(k, d, p, r, none) {
    if (r$graded_terms == 0L) return("not graded yet")
    if (r$withheld) return("withheld")
    if (is.na(d) || d == 0L) return(none)
    paste0(pct(p), " (", n(k), " of ", n(d), ")",
           if (r$partial) paste0(", over ", r$rate_terms, " of its ", r$graded_terms, " graded terms"))
  }
  span <- function(first, last) {
    if (first == last) fmt_term(first) else paste0(fmt_term(first), " to ", fmt_term(last))
  }
  summary <- course_topics_summary(payload, types, unlocked)
  lines <- c(
    paste0(payload$course, " by topic, ", paste(tools::toTitleCase(types), collapse = " and "), " terms"),
    course_topics_scope_note(payload),
    paste0("A rate is shown for ", payload$min_n, " or more students.")
  )
  for (cmp in unique(summary$campus)) {
    s <- summary[summary$campus == cmp, , drop = FALSE]
    lines <- c(lines, "", paste0(payload$course, " taught on ", cmp))
    for (i in seq_len(nrow(s))) {
      r <- s[i, ]
      lines <- c(lines, paste0(
        "  ", r$topic, ": ", plural(r$terms, "term"), " (", span(r$first_term, r$last_term), "), ",
        plural(r$sections, "section"), ", ", n(r$census_enrl), " students at census, ",
        plural(r$n_instructors, "instructor"),
        "; DFW ", rate(r$dfw, r$attempts, r$dfw_pct, r, "none graded"),
        "; returned ", rate(r$n_returned, r$n_return_observable, r$return_pct, r,
                            "not observable yet")
      ))
    }
  }
  merged <- course_topics_titles(payload) %>% filter(read_as != "its own title")
  if (nrow(merged) > 0L) {
    lines <- c(lines, "", "Titles counted under a topic worded differently:",
               paste0("  ", merged$campus, " \"", merged$course_title, "\" -> ", merged$topic,
                      " (", merged$read_as, ")"))
  }
  unmatched <- payload$unmatched
  if (unmatched$students > 0L || unmatched$attempts > 0L) {
    lines <- c(lines, "", paste0(
      n(unmatched$students), " class-list rows and ", n(unmatched$attempts),
      " graded attempts carry a CRN no section of ", payload$course, " has, and are in no topic."))
  }
  lines
}
