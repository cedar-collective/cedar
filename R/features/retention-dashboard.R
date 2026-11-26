# retention-dashboard.R — Bird's Eye > Retention: are students coming back?
#
# Settled return first (decided 2026-11-19): one term type at a time, how
# often enrolled students came back the next regular term and whether that is
# rising or falling; who is not coming back, by the warning signs known by the
# end of the term; each classification and college; and the courses where a
# DFW grade goes with not coming back the most. The return watch (this term's
# students not yet registered, against the same day a year earlier) joins it
# as the top section once the snapshots allow exact comparisons (ROADMAP).
#
# Every rate is get_return_rates() (cones/return-rates.R) over
# cedar_student_terms; the trend is compute_rate_trend(); the courses are
# get_stopout() (cones/stopout.R) over the latest terms' students. The payload
# is typed; format_retention_dashboard() is its one text rendering.
#
# Each entering class followed one to four regular terms on
# (get_entering_class_retention(), cones/entering-class-retention.R) sits
# beside the one-step return: where a class is lost, not only how many.
#
# Who the rates count is stated with them: retention_scope_facts() counts the
# latest term's students by how the record says they arrived (first-time, a
# new transfer, or neither) and the students at another level, who are left
# out; describe_retention_scope() words it for the page's data scope bar.
#
# Depends on: get_return_rates(), get_stopout(), compute_rate_trend(),
#             get_entering_class_retention(), student_arrival_as_of()

RETENTION_SIGNS <- c(late_withdrawal = "A late withdrawal", dfw = "A DFW grade")

#' Build the retention dashboard payload
#'
#' @param student_terms `cedar_student_terms`.
#' @param attempts `cedar_attempts`, for the courses section.
#' @param degrees `cedar_degrees`, so a degree counts as completion there.
#' @param opt `term_type` (one anchor term type; required), `student_level`
#'   (level codes; NULL keeps every level), `campus` (home campuses; NULL
#'   keeps every campus), `data_edges` (required), `min_n` (observable
#'   student-terms a group-term needs for a rate; default 30), `course_terms`
#'   (how many of the latest anchor terms the courses section reads; default
#'   3), `course_min_n` / `course_min_dfw_n` (get_stopout()'s guards; default
#'   100 and 20).
#' @param programs `cedar_programs`, or NULL: then `who` and `milestones`
#'   (which read how the record says a student arrived) are left out.
#' @return A `retention_dashboard` list: `meta`; `who` (retention_scope_facts()
#'   for the latest term read: the students counted, how they started, and
#'   the levels left out); `series` (one row per anchor
#'   term: the counts and `return_pct`); `trend` (compute_rate_trend() of the
#'   series); `signs` (per sign and term: with and without the sign, and the
#'   share of the term's non-returners who had it); `signs_latest` (each
#'   sign's latest term); `groups` (per dimension,
#'   classification or college, and group read in the latest term: its series
#'   and trend; `meta$n_groups_past` counts the others); `courses`
#'   (get_stopout()'s `by_course` over the latest `course_terms` anchors with
#'   posted grades, its `terms` and coverage, and `listed`: the 25 gaps beyond
#'   chance that stand for the most students, `excess_not_back`);
#'   `milestones` (get_entering_class_retention() for the scope's entering
#'   classes, four steps). A scope
#'   with no readable return has an empty `series` and NULL elsewhere.
build_retention_dashboard <- function(student_terms, attempts, degrees, opt = list(), programs = NULL) {
  term_type <- opt$term_type
  if (length(term_type) != 1L || is.na(term_type)) {
    stop("[retention-dashboard.R] opt$term_type (one term type) is required.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 30L)
  scope <- list(term_type = term_type, student_level = opt$student_level, campus = opt$campus,
                data_edges = opt$data_edges, min_n = min_n)
  rates <- function(group_cols) get_return_rates(student_terms, c(scope, list(group_cols = group_cols)), degrees)

  overall <- rates(character(0))
  series <- overall$rates %>% filter(n_observable > 0L)
  meta <- list(term_type = term_type, student_level = opt$student_level, campus = opt$campus,
               min_n = min_n, edge = overall$meta$edge, graded_edge = overall$meta$graded_edge,
               n_enrolled = sum(overall$rates$n_enrolled), n_graduated = sum(overall$rates$n_graduated),
               n_finished_between = sum(overall$rates$n_finished_between),
               n_applied_between = sum(overall$rates$n_applied_between),
               n_unobservable = sum(overall$rates$n_unobservable), n_groups_past = 0L)
  # A scope with no student whose return can be read (a campus with none at
  # this level, say) is an answer, not an error: an empty payload says so.
  if (nrow(series) == 0L) {
    return(structure(list(meta = meta, who = NULL, series = series, trend = NULL, signs = NULL, signs_latest = NULL,
                          groups = NULL, courses = list(terms = integer(0), by_course = NULL, listed = NULL),
                          milestones = NULL),
                     class = "retention_dashboard"))
  }
  trend <- compute_rate_trend(series %>% transmute(term, k = n_returned, n = n_observable))

  # Each sign apart (a student may carry both): with it, without it, and the
  # share of the term's non-returners who had it. An unknown DFW sign (no
  # posted grade) is neither.
  signs <- bind_rows(lapply(names(RETENTION_SIGNS), function(sign) {
    r <- rates(sign)$rates %>% filter(!is.na(.data[[sign]]), n_observable > 0L)
    r %>%
      group_by(term) %>%
      summarize(
        n_with = sum(n_observable[.data[[sign]]]),
        returned_with = sum(n_returned[.data[[sign]]]),
        n_without = sum(n_observable[!.data[[sign]]]),
        returned_without = sum(n_returned[!.data[[sign]]]),
        .groups = "drop"
      ) %>%
      mutate(sign = sign,
             return_with_pct = if_else(n_with >= min_n, 100 * returned_with / n_with, NA_real_),
             return_without_pct = if_else(n_without >= min_n, 100 * returned_without / n_without, NA_real_),
             nonreturners = (n_with - returned_with) + (n_without - returned_without),
             share_of_nonreturners_pct = if_else(nonreturners > 0,
                                                 100 * (n_with - returned_with) / nonreturners, NA_real_))
  })) %>%
    select(sign, term, n_with, returned_with, return_with_pct, n_without, returned_without,
           return_without_pct, nonreturners, share_of_nonreturners_pct)

  # Each classification and college: its series and trend, over the terms
  # it had min_n observable. A group not read in the latest term (a
  # classification retired, a college merged) is left out and counted.
  latest <- max(series$term)
  groups <- bind_rows(lapply(c(classification = "student_classification", college = "primary_college_code"),
                             function(col) {
    r <- rates(col)$rates %>%
      filter(!is.na(.data[[col]]), nzchar(.data[[col]]), n_observable >= min_n) %>%
      transmute(group = .data[[col]], term, n_observable, n_returned, return_pct)
    tr <- compute_rate_trend(r %>% transmute(group, term, k = n_returned, n = n_observable), group_cols = "group")
    r %>%
      group_by(group) %>%
      summarize(terms = list(term), rates = list(return_pct), .groups = "drop") %>%
      inner_join(tr, by = "group") %>%
      mutate(dimension = if (col == "student_classification") "classification" else "college")
  }))
  meta$n_groups_past <- sum(groups$last_term < latest)
  groups <- groups %>% filter(last_term == latest)

  # The slowest part; the page reads it on its own (opt$courses = FALSE).
  courses <- if (isFALSE(opt$courses)) NULL else retention_dashboard_course_list(student_terms, attempts, degrees, series, opt)

  structure(list(
    meta = meta,
    who = if (is.null(programs)) NULL else retention_scope_facts(student_terms, programs, opt, latest),
    series = series, trend = trend, signs = signs,
    signs_latest = signs %>% group_by(sign) %>% filter(term == max(term)) %>% ungroup(),
    groups = groups, courses = courses,
    milestones = if (isFALSE(opt$milestones)) NULL else retention_dashboard_milestones(student_terms, degrees, opt, programs)
  ), class = "retention_dashboard")
}

RETENTION_ARRIVALS <- c(first_time = "First-time students", transfer = "Transfer students",
                        not_recorded = "Start not on record")

#' Who the page's return rates count, in one term
#'
#' The enrolled students of the scope's level and home campus in `term`, as
#' get_return_rates() picks them; how the record says each most recently
#' arrived by then (student_arrival_as_of()); and the students of the same
#' term and home campus at another level, who are not counted.
#'
#' @param student_terms `cedar_student_terms`.
#' @param programs `cedar_programs`, for `student_population`.
#' @param opt The dashboard's scope: `student_level`, `campus`.
#' @param term The term to describe (the latest the page reads).
#' @return list(`term`, `student_level`, `campus`, `n_counted`, `arrivals`
#'   (a count for each of `RETENTION_ARRIVALS`, adding to `n_counted`),
#'   `other_levels` (`student_level`, `n`; largest first, empty when the scope
#'   names no level)).
retention_scope_facts <- function(student_terms, programs, opt = list(), term) {
  missing <- setdiff(c("student_id", "term", "enrolled", "student_level", "student_campus"), names(student_terms))
  if (length(missing) > 0L) {
    stop("[retention-dashboard.R] student_terms lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  as_of <- as.integer(term)
  in_term <- student_terms %>% filter(enrolled, term == as_of) %>% select(student_id, student_level, student_campus)
  if (!is.null(opt$campus)) in_term <- in_term %>% filter(student_campus %in% opt$campus)
  at_level <- if (is.null(opt$student_level)) rep(TRUE, nrow(in_term)) else in_term$student_level %in% opt$student_level
  counted <- in_term[at_level, ] %>% distinct(student_id)
  arrived <- counted %>%
    left_join(student_arrival_as_of(programs, as_of), by = "student_id", relationship = "one-to-one") %>%
    mutate(arrival = dplyr::coalesce(entry_type, "not_recorded"))
  arrivals <- vapply(names(RETENTION_ARRIVALS), function(a) sum(arrived$arrival == a), integer(1))
  list(term = as_of, student_level = opt$student_level, campus = opt$campus,
       n_counted = nrow(counted), arrivals = arrivals,
       other_levels = in_term[!at_level, ] %>%
         distinct(student_id, student_level) %>%
         count(student_level, name = "n") %>%
         arrange(desc(n), student_level))
}

#' Who the page counts, as short labelled facts for its data scope bar
#'
#' @param who retention_scope_facts() output.
#' @return A named character vector, in display order: the students counted,
#'   how many of them started each way, and the levels not counted (absent
#'   when no other level has a student in the term).
describe_retention_scope <- function(who) {
  level_name <- function(code) ifelse(is.na(code), "no level recorded",
                                      dplyr::coalesce(unname(CEDAR_STUDENT_LEVEL_LABELS[code]), code))
  level <- if (is.null(who$student_level)) "students at every level"
           else paste(paste(level_name(who$student_level), collapse = " and "), "students")
  campus <- if (is.null(who$campus)) "every home campus" else paste("home campus", paste(who$campus, collapse = ", "))
  described <- c(paste0(fmt_count(who$n_counted), " ", level, ", ", campus),
                 paste(fmt_count(who$arrivals), "of them"))
  names(described) <- c(paste0("Counted, ", fmt_term(who$term)), unname(RETENTION_ARRIVALS[names(who$arrivals)]))
  if (nrow(who$other_levels) > 0L) {
    described[["Not counted"]] <- paste0(
      "students at another level: ",
      paste0(level_name(who$other_levels$student_level), " ", fmt_count(who$other_levels$n), collapse = "; "))
  }
  described
}

#' Who is counted, as the rule: for the first section's "How this is counted"
#'
#' @param who retention_scope_facts() output, or NULL when the payload has none.
#' @return One sentence group: how a transfer student and a student at another
#'   level are treated, with the latest term's counts when they are known.
retention_who_note <- function(who) {
  rule <- paste0("A transfer student is counted like any other, from their first term here. A student at another ",
                 "level is not counted: choose that level above to read them.")
  if (is.null(who)) return(rule)
  a <- who$arrivals
  paste0(rule, " Of the ", fmt_count(who$n_counted), " counted in ", fmt_term(who$term), ", the record calls ",
         fmt_count(a[["first_time"]]), " first-time students and ", fmt_count(a[["transfer"]]),
         " new transfers in the term they arrived; the other ", fmt_count(a[["not_recorded"]]),
         " it never calls new in the terms on record (readmitted after time away, moved from another campus or ",
         "level, or here before the records begin). A student who arrived more than once is read by the latest.")
}

#' The courses where a DFW goes with not coming back, and the 25 listed
#'
#' @param series The dashboard's `series` (its terms set which are read).
#' @param opt The dashboard's scope.
#' @return retention_dashboard_courses()'s list with `listed`: a gap beyond
#'   chance (unadjusted across courses), ranked by the students it stands
#'   for, the DFW students who did not come back beyond the passers' rate
#'   (Roadblocks' impact with no baseline): a large course with a moderate
#'   gap ahead of a small one with a wide gap.
retention_dashboard_course_list <- function(student_terms, attempts, degrees, series, opt = list()) {
  courses <- retention_dashboard_courses(student_terms, attempts, degrees, series, opt)
  # Nothing to list when no term is graded (NULL) or the scope's students hold
  # no graded attempt in the terms (get_stopout()'s table with no columns).
  courses$listed <- if (NROW(courses$by_course) == 0L) NULL else courses$by_course %>%
    filter(!is.na(pop_p_value), pop_p_value < 0.05, pop_stopout_gap > 0) %>%
    mutate(excess_not_back = pop_n_dfw * pop_stopout_gap) %>%
    arrange(desc(excess_not_back)) %>%
    utils::head(25L)
  courses
}

#' The page's entering classes: its scope handed to get_entering_class_retention()
#'
#' Its own function so the page can change who an entering class holds
#' without rebuilding the rest (`opt$milestones = FALSE` leaves it out of
#' build_retention_dashboard()).
#'
#' @param opt The dashboard's scope (`term_type`, `student_level`, `campus`,
#'   `data_edges`, `min_n`), with `entry` and `entry_time_status`.
#' @return get_entering_class_retention()'s rows, four semesters on.
retention_dashboard_milestones <- function(student_terms, degrees, opt = list(), programs = NULL) {
  get_entering_class_retention(student_terms, degrees, list(
    term_type = opt$term_type, student_level = opt$student_level, campus = opt$campus,
    data_edges = opt$data_edges, min_n = as.integer(opt$min_n %||% 30L), n_terms = 4L,
    entry = opt$entry %||% "all", time_status = opt$entry_time_status), programs)
}

#' The courses where a DFW grade goes with not coming back the most
#'
#' get_stopout() over the student-terms of the latest `course_terms` anchor
#' terms whose grades are posted and whose return is observable.
#' @noRd
retention_dashboard_courses <- function(student_terms, attempts, degrees, series, opt) {
  graded_edge <- opt$data_edges[["last_graded"]]
  terms <- utils::tail(sort(series$term[series$term <= graded_edge]), as.integer(opt$course_terms %||% 3L))
  if (length(terms) == 0L) return(list(terms = integer(0), by_course = NULL, observation_info = NULL))
  members <- scope_student_terms(student_terms, opt$student_level, opt$campus) %>% filter(term %in% terms)
  population <- members %>% distinct(student_id) %>% mutate(population_label = "Population")
  # The population's own outcome rows in those terms (its membership window).
  window <- attempts %>% semi_join(members %>% select(student_id, term), by = c("student_id", "term"))
  r <- get_stopout(NULL, population, degrees = degrees, opt = list(
    term = terms, min_n = as.integer(opt$course_min_n %||% 100L),
    min_dfw_n = as.integer(opt$course_min_dfw_n %||% 20L),
    graded_through = graded_edge, observation_end_term = cedar_longitudinal_edge(opt$data_edges)
  ), attempts = window, student_terms = student_terms)
  list(terms = terms, by_course = r$by_course, observation_info = r$observation_info)
}

RETENTION_DIRECTION_WORDS <- c(rising = "rising (better)", falling = "falling (worse)", steady = "steady",
                               too_few_terms = "too few terms for a trend")

#' A return trend in one sentence
#'
#' Its first and last rate, the fitted line's slope a year, and what chance
#' and the terms' own scatter give.
#' @param t One row of compute_rate_trend() output.
retention_trend_sentence <- function(t) {
  pct <- function(x) ifelse(is.na(x), "\u2014", sprintf("%.1f%%", x))
  if (t$direction == "too_few_terms") {
    return(paste0("A trend is read from 3 or more terms; ", t$n_terms, " can be read."))
  }
  paste0(pct(t$first_pct), " for ", fmt_term(t$first_term), ", ", pct(t$last_pct), " for ",
         fmt_term(t$last_term), ". ", retention_trend_arithmetic(t))
}

#' How a return trend's verdict was reached: the slope beside what chance gives
#' @param t One row of compute_rate_trend() output.
retention_trend_arithmetic <- function(t) {
  if (t$direction == "too_few_terms") {
    return(paste0("A trend is read from 3 or more terms; ", t$n_terms, " can be read."))
  }
  paste0("Across the ", t$n_terms, " terms the fitted line moves ",
         sprintf("%+.1f", t$slope), " points a year, where chance and the terms' own scatter give about ",
         sprintf("%.1f", 2 * t$slope_se), ": ", RETENTION_DIRECTION_WORDS[[t$direction]], ".")
}

# The verdict in the lead sentence's words.
# Steady is a verdict about the line, not a claim that no term moved.
RETENTION_LEAD_WORDS <- c(rising = "rising", falling = "falling", steady = "not clearly rising or falling")

#' The section's answer in one sentence: the verdict over the terms, and its two ends
#'
#' The chart's trend label says the same verdict; the arithmetic behind it is
#' retention_trend_arithmetic(), in the method note.
#' @param t One row of compute_rate_trend() output.
#' @param type The term type in words ("fall", "spring").
retention_lead_sentence <- function(t, type) {
  pct <- function(x) ifelse(is.na(x), "\u2014", sprintf("%.1f%%", x))
  if (t$direction == "too_few_terms") {
    return(paste0("Too few ", type, " terms can be read to say whether the share coming back is rising or falling: ",
                  t$n_terms, " of the 3 a trend needs."))
  }
  paste0("The share of ", type, " students who came back the next regular term is ",
         RETENTION_LEAD_WORDS[[t$direction]], ": ", pct(t$first_pct), " for ", fmt_term(t$first_term), ", ",
         pct(t$last_pct), " for ", fmt_term(t$last_term),
         if (t$direction == "steady") ", a difference within the terms' usual swings."
         else paste0(", about ", sprintf("%.1f", abs(t$slope)), " points a year."))
}

#' How a step after an entering term is named: the semester it is, and its season
#'
#' The entering term is the 1st semester, so one regular term later is the
#' 2nd and a year later the 3rd, the one retention is usually quoted at.
#'
#' @param step Regular terms after the entering term.
#' @param target_term The term that step lands on.
#' @return "2nd semester (spring)", "3rd semester (fall)", and so on.
retention_milestone_label <- function(step, target_term) {
  k <- as.integer(step) + 1L
  suffix <- ifelse(k %% 100L %in% 11:13, "th", c("th", "st", "nd", "rd", rep("th", 6))[k %% 10L + 1L])
  paste0(k, suffix, " semester (", get_term_type(target_term), ")")
}

# The entering students a class holds, in the sentence's words.
RETENTION_ENTRY_WORDS <- c(all = "students new at this level", first_time = "first-time students",
                           transfer = "new transfer students")

#' The entering classes in a sentence: the range over every class read, then
#' the newest class with a year behind it
#'
#' @param payload `build_retention_dashboard()` output.
#' @return One or two sentences, or `character(0)` when no class has a rate a
#'   semester on.
retention_milestone_sentence <- function(payload) {
  m <- payload$milestones
  if (is.null(m) || nrow(m) == 0L) return(character(0))
  known <- m %>% filter(!is.na(here_pct))
  if (nrow(known) == 0L) return(character(0))
  # The 3rd semester (a year on) leads when any class has one; the 2nd follows.
  steps <- intersect(c(2L, 1L), known$step)
  if (length(steps) == 0L) steps <- min(known$step)
  who <- RETENTION_ENTRY_WORDS[[attr(m, "entry") %||% "all"]]
  pct <- function(x) sprintf("%.1f%%", x)
  semester <- function(rows) sub(" \\(.*$", "", retention_milestone_label(rows$step[[1]], rows$target_term[[1]]))
  lead <- known %>% filter(step == steps[[1]]) %>% arrange(term)
  span <- function(rows) if (nrow(rows) == 1L || min(rows$here_pct) == max(rows$here_pct)) pct(rows$here_pct[[1]])
                         else paste0("between ", pct(min(rows$here_pct)), " and ", pct(max(rows$here_pct)))
  rows_at <- function(step_k) known %>% filter(step == step_k)
  when <- function(step_k) if (step_k == 2L) paste0("a year on (their ", semester(rows_at(step_k)), ")")
                           else paste0("in their ", semester(rows_at(step_k)))
  upper <- function(x) paste0(toupper(substring(x, 1, 1)), substring(x, 2))
  rest <- if (length(steps) > 1L) paste0("; ", when(steps[[2]]), ", ", span(rows_at(steps[[2]]))) else ""
  newest <- lead[nrow(lead), ]
  if (nrow(lead) == 1L) {
    return(paste0(upper(when(steps[[1]])), ", ", span(lead), " of the ", fmt_count(newest$n_entering), " ", who,
                  " who entered in ", fmt_term(newest$term), " were enrolled or had graduated", rest, "."))
  }
  paste0(upper(when(steps[[1]])), ", ", span(lead), " of the ", who, " in each of the ", nrow(lead), " classes from ",
         fmt_term(min(lead$term)), " to ", fmt_term(max(lead$term)), " were enrolled or had graduated", rest,
         ". The newest of those classes, ", fmt_term(newest$term), " (", fmt_count(newest$n_entering),
         " students), is at ", pct(newest$here_pct), ".")
}

#' The retention dashboard as text
#'
#' @param payload `build_retention_dashboard()` output.
#' @return A character vector, one line each.
format_retention_dashboard <- function(payload) {
  if (!inherits(payload, "retention_dashboard")) stop("[retention-dashboard.R] not a retention_dashboard payload")
  m <- payload$meta
  n <- fmt_count
  pct <- function(x) ifelse(is.na(x), "—", paste0(formatC(x, format = "f", digits = 1), "%"))
  t <- payload$trend
  lines <- c(
    paste0("Return to the next regular term, ", m$term_type, " terms",
           if (!is.null(m$student_level)) paste0(", level ", paste(m$student_level, collapse = "/")) else "",
           if (!is.null(m$campus)) paste0(", home campus ", paste(m$campus, collapse = "/")) else "",
           "; settled through ", fmt_term(m$edge), ", grades through ", fmt_term(m$graded_edge), "."),
    paste0("Left out: ", n(m$n_graduated), " awarded a degree that term or before the next regular term (",
           n(m$n_finished_between), " in between, ", n(m$n_applied_between), " applied for one not yet posted); ",
           n(m$n_unobservable),
           " whose next regular term is not yet settled."),
    if (nrow(payload$series) > 0L) paste0("Overall: ", retention_trend_sentence(t))
    else "Overall: no student in this scope has a settled next term."
  )
  if (nrow(payload$series) == 0L) return(lines)
  if (!is.null(payload$who)) {
    described <- describe_retention_scope(payload$who)
    lines <- c(lines, paste0("  ", names(described), ": ", described))
  }
  for (i in seq_len(nrow(payload$series))) {
    s <- payload$series[i, ]
    lines <- c(lines, paste0("  ", fmt_term(s$term), ": ", n(s$n_returned), " of ", n(s$n_observable),
                             " returned, ", pct(s$return_pct), "."))
  }
  last <- payload$signs_latest
  for (i in seq_len(nrow(last))) {
    g <- last[i, ]
    lines <- c(lines, paste0(RETENTION_SIGNS[[g$sign]], ", ", fmt_term(g$term), ": ", n(g$n_with),
                             " students, ", pct(g$return_with_pct), " returned against ", pct(g$return_without_pct),
                             " without; ", pct(g$share_of_nonreturners_pct), " of those who did not return."))
  }
  if (m$n_groups_past > 0L) lines <- c(lines, paste0("Groups not read in the latest term, left out: ", m$n_groups_past, "."))
  for (i in seq_len(nrow(payload$groups))) {
    g <- payload$groups[i, ]
    lines <- c(lines, paste0(tools::toTitleCase(g$dimension), " ", g$group, ": ", pct(g$last_pct), " in ",
                             fmt_term(g$last_term), "; ", g$direction, "."))
  }
  ms <- payload$milestones
  for (class_term in unique(ms$term)) {
    rows <- ms[ms$term == class_term, ]
    lines <- c(lines, paste0("Entered ", fmt_term(class_term), " (", n(rows$n_entering[[1]]), "): ",
                             paste0(pct(rows$here_pct), " ", retention_milestone_label(rows$step, rows$target_term),
                                    collapse = "; "), "."))
  }
  for (i in seq_len(NROW(payload$courses$listed))) {
    c <- payload$courses$listed[i, ]
    lines <- c(lines, paste0("Course ", c$subject_course, " (", c$campus, "): ", n(c$pop_n_dfw), " with a DFW, ",
                             pct(100 * (1 - c$pop_dfw_stopout_rate)), " back against ",
                             pct(100 * (1 - c$pop_pass_stopout_rate)), " after passing; ",
                             formatC(c$excess_not_back, format = "f", digits = 1), " beyond the passers' rate."))
  }
  lines
}

# ── Plotting ─────────────────────────────────────────────────────────────────

#' Each anchor term's return rate as a line, labelled with its rate
#'
#' @param payload `build_retention_dashboard()` output.
plot_return_series <- function(payload) {
  s <- payload$series
  t <- payload$trend[1, , drop = FALSE]
  labels <- vapply(s$term, fmt_term, character(1))
  p <- plotly::plot_ly(
    x = labels, y = s$return_pct, type = "scatter", mode = "lines+markers+text",
    text = sprintf("%.1f%%", s$return_pct), textposition = "top center",
    line = list(color = CEDAR_PALETTE[[2]], width = 3), marker = list(color = CEDAR_PALETTE[[2]], size = 8),
    hovertext = paste0(labels, "<br>", format(s$n_returned, big.mark = ","), " of ",
                       format(s$n_observable, big.mark = ","), " came back"),
    hoverinfo = "text", showlegend = FALSE, name = "Came back")
  # The fitted trend, drawn from compute_rate_trend()'s own line, labelled at
  # its end with its slope and verdict (the colour says which way, when it is
  # a trend at all).
  trend_label <- NULL
  if (!is.na(t$slope)) {
    p <- plotly::add_trace(p, x = vapply(c(t$first_term, t$last_term), fmt_term, character(1)),
                           y = c(t$fit_first_pct, t$fit_last_pct), type = "scatter", mode = "lines",
                           line = list(color = CEDAR_SEMANTIC_COLORS[["reference"]], width = 2, dash = "dash"),
                           text = NULL, hoverinfo = "skip", showlegend = FALSE, name = "Trend",
                           inherit = FALSE)
    tone <- switch(t$direction, falling = "negative", rising = "positive", "reference")
    trend_label <- list(list(
      x = fmt_term(t$last_term), y = t$fit_last_pct, xref = "x", yref = "y",
      text = paste0("<b>", sprintf("%+.1f", t$slope), " points a year</b><br>",
                    RETENTION_DIRECTION_WORDS[[t$direction]]),
      showarrow = FALSE, xanchor = "left", xshift = 12, align = "left",
      font = list(color = CEDAR_SEMANTIC_COLORS[[tone]], size = 13)))
  }
  plotly::layout(p,
    xaxis = list(title = "", type = "category", categoryorder = "array", categoryarray = labels),
    yaxis = list(title = "Came back the next regular term", ticksuffix = "%",
                 range = c(max(0, min(s$return_pct, na.rm = TRUE) - 8), 100)),
    annotations = trend_label,
    margin = list(r = if (is.null(trend_label)) 20 else 150))
}


#' Each entering class's share still enrolled, one line per step
#'
#' The x axis is the entering class; each line is a distance from entry, so a
#' line that falls says later classes are being kept less well at that
#' distance, and the space between two lines is the loss between those steps.
#' A line stops where its target term has not settled.
#'
#' @param payload `build_retention_dashboard()` output with `milestones`.
plot_entering_class_milestones <- function(payload) {
  m <- payload$milestones %>% filter(!is.na(here_pct))
  classes <- sort(unique(payload$milestones$term))
  labels <- vapply(classes, fmt_term, character(1))
  steps <- sort(unique(m$step))
  # One name per step: every class of one term type lands on the same season.
  names_by_step <- vapply(steps, function(k) retention_milestone_label(k, m$target_term[m$step == k][[1]]), character(1))
  colours <- cedar_plotly_palette(names_by_step)
  p <- plotly::plot_ly()
  for (i in seq_along(steps)) {
    rows <- m[m$step == steps[[i]], ]
    p <- plotly::add_trace(
      p, x = vapply(rows$term, fmt_term, character(1)), y = rows$here_pct, type = "scatter", mode = "lines+markers",
      name = names_by_step[[i]], line = list(color = colours[[i]], width = 3), marker = list(color = colours[[i]], size = 8),
      hovertext = paste0("Entered ", vapply(rows$term, fmt_term, character(1)), "<br>", names_by_step[[i]], ", in ",
                         vapply(rows$target_term, fmt_term, character(1)), ": ",
                         format(rows$n_here, big.mark = ","), " of ", format(rows$n_entering, big.mark = ","),
                         sprintf(" (%.1f%%)", rows$here_pct)),
      hoverinfo = "text")
  }
  plotly::layout(p,
    xaxis = list(title = "Entering class", type = "category", categoryorder = "array", categoryarray = labels),
    yaxis = list(title = "Still enrolled, or graduated", ticksuffix = "%",
                 range = c(max(0, min(m$here_pct) - 8), 100)),
    legend = list(orientation = "h", y = -0.2))
}

# ── Courses by GPA band ───────────────────────────────────────────────────────

# Who each band choice reads, in the page's words.
RETENTION_BAND_WORDS <- c(
  entering = "continuing students who entered the term with a GPA",
  hs = "first-term students with a high-school GPA of"
)

#' The courses harder, and easier, on the lowest-GPA students than the rest of their term
#'
#' get_course_band_dfw() over the latest `band_terms` graded terms of the
#' page's term type, for the page's students, with the two lists the page
#' shows and how many courses chance alone would put on each.
#'
#' @param opt The dashboard's scope: `term_type` (required), `student_level`
#'   and `campus` (the students' level and home campus that term, as every
#'   section of the page reads them; NULL reads everyone), `data_edges`
#'   (required). Each course is read on every campus that taught it to those
#'   students, each apart. Also `band_by` (`"entering"` or `"hs"`),
#'   `band_terms` (terms pooled; default 5), `min_n`, `z_min`.
#' @return get_course_band_dfw()'s list with `harder` and `easier` (the
#'   courses of each verdict, by the attempts the gap stands for, 15 at most)
#'   and `meta$n_courses`, `meta$n_by_chance` (the courses read times the
#'   one-sided chance of a gap beyond `z_min`).
retention_dashboard_band_courses <- function(attempts, student_terms, applicants = NULL, opt = list()) {
  if (length(opt$term_type) != 1L || is.na(opt$term_type)) {
    stop("[retention-dashboard.R] opt$term_type (one term type) is required.", call. = FALSE)
  }
  edge <- opt$data_edges[["last_graded"]]
  if (is.null(edge)) stop("[retention-dashboard.R] opt$data_edges has no graded edge (last_graded).", call. = FALSE)
  terms <- sort(unique(as.integer(attempts$term)))
  terms <- terms[terms <= as.integer(edge) & get_term_type(terms) %in% opt$term_type]
  terms <- utils::tail(terms, as.integer(opt$band_terms %||% 5L))
  if (length(terms) == 0L) stop("[retention-dashboard.R] no graded ", opt$term_type, " term to read.", call. = FALSE)
  # The page's campus is the student's home campus (opt$campus), never the
  # campus that taught the course: the cone is given it as the student scope.
  r <- get_course_band_dfw(attempts, student_terms,
                           c(opt[intersect(names(opt), c("student_level", "data_edges", "band_by", "min_n", "z_min"))],
                             list(term = terms, student_campus = opt$campus)), applicants)
  listed <- function(which) r$courses %>%
    filter(verdict == which) %>%
    mutate(excess_dfw = low_attempts * gap_pts / 100) %>%
    arrange(desc(abs(excess_dfw)))
  # Every course with the verdict is counted; the 15 that stand for the most
  # attempts are shown.
  r$meta$n_harder <- nrow(listed("harder"))
  r$meta$n_easier <- nrow(listed("easier"))
  r$harder <- utils::head(listed("harder"), 15L)
  r$easier <- utils::head(listed("easier"), 15L)
  r$meta$n_courses <- nrow(r$courses)
  r$meta$n_by_chance <- nrow(r$courses) * stats::pnorm(-r$meta$z_min)
  r
}

#' The by-band course result in a sentence
#'
#' @param result `retention_dashboard_band_courses()` output.
#' @return One sentence: how many courses were read, how many fell on each
#'   list, and how many chance alone would put there.
retention_band_sentence <- function(result) {
  m <- result$meta
  who <- paste0(RETENTION_BAND_WORDS[[m$band_by]], " ", m$low_band)
  if (m$n_courses == 0L) {
    return(paste0("No course had ", m$min_n, " graded attempts by ", who, " and ", m$min_n,
                  " by its other students over these terms."))
  }
  n <- fmt_count
  paste0("Of the ", n(m$n_courses), if (m$n_courses == 1L) " course" else " courses", " read, ", n(m$n_harder),
         if (m$n_harder == 1L) " was" else " were", " harder on ", who,
         " than the rest of their own term was, by more than for the course's other students, and ",
         n(m$n_easier), " easier",
         if (max(m$n_harder, m$n_easier) > 15L) " (the 15 that stand for the most attempts are listed)" else "",
         ". Chance alone would put ",
         if (m$n_by_chance < 0.5) "fewer than 1" else paste0("about ", sprintf("%.0f", m$n_by_chance)),
         " on each list, so a course here is a place to look, not a finding.")
}
