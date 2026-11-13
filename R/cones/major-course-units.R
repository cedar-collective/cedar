# major-course-units.R — Which units teach the courses a major's students take?
#
# One question: in each term, the students whose primary major belongs to a
# unit sat in courses taught by which units, and how much of their
# course-taking was outside their own unit. The inverse question (which majors
# fill a unit's seats) is Dept Trends' student-credit-hour breakdown in
# R/branches/credit-hours.R; this cone looks out from the major, not in at
# the course.
#
# A member is a student-term on cedar_student_terms whose primary major's
# unit (`primary_dept_code`, attached at load from programs.csv) is the one
# asked for, and which the table calls enrolled: CEDAR's one definition. A
# pre-major student-term is a member unless opt$include_pre_majors is FALSE.
# The courses are the member's registration rows that term, registered at
# the pull or withdrawn late (a seat held past census); an early drop or a
# waitlist row is not course-taking. The teaching unit is the registration
# row's `department`, the subject's unit from subjects.csv, with NA for a
# subject no mapping row has decided: such rows are kept as a row of their
# own, never dropped and never given a unit.
#
# A row is a term, teaching campus, college and unit, because a course
# metric is grouped by campus (campus-policy.md): a student taking courses on
# two campuses in one term is in both campus rows. Shares are within the
# term and campus over every member registration there, computed before any
# small cell is suppressed, so a page's headline does not move with its
# display grain.
#
# Terms stop at the settled enrollment edge (last_enrolled_complete). With
# opt$include_in_progress, terms up to last_enrolled are added. A row's
# `in_progress` is cedar_term_in_progress(): its grades have not posted, the
# right-edge policy's label for current registration, so a settled term not
# yet graded is in progress too (I58).
#
# opt$grain = "course" answers the same question one level down: the rows
# are the courses themselves, each under its teaching unit, with the share of
# the term and campus's members who sat in it. The members, the
# registrations and every total are the same; only the grouping is finer.
# opt$grain = "college" is the same one level up: one row per teaching
# college, with the distinct members who sat in any of its units' courses,
# which the unit rows cannot give (a student in two units of one college is
# one student). A subject no mapping row has decided has no unit, so its
# college is not asserted either: those registrations are one row of their
# own (`unit_decided` FALSE, `college` NA).
#
# This is a filter and a join over two tables (ADR-001): the cone counts
# nothing a table already holds.
#
# Depends on: STATUS_REGISTERED, STATUS_DROP_LATE (lists/status_codes.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             cedar_filter_campus() (lists/campuses.R)

#' Which units teach the courses a major's students take
#'
#' @param student_terms `cedar_student_terms`, with its units attached
#'   (`primary_dept_code`).
#' @param registrations `cedar_registrations`, with its units attached
#'   (`department`, `college`).
#' @param opt `dept_code` (the major's unit; required), `program_code` (one
#'   or more program codes to narrow the members to; default every program
#'   of the unit), `include_pre_majors` (default TRUE), `term` (terms to
#'   keep; default every term to the edge), `campus` (teaching campuses to
#'   keep; NULL keeps every campus, each its own row), `min_n` (the smallest
#'   distinct-student count a unit row needs; default 10),
#'   `include_in_progress` (default FALSE: rows stop at the settled edge),
#'   `grain` (`"unit"`, the default;
#'   `"course"`: one row per course under its teaching unit, with
#'   `subject_course` and `share_of_students`, `n_students / term_students`;
#'   or `"college"`: one row per teaching college, with `unit_decided` in
#'   place of `dept_code` and `is_own_unit`),
#'   `data_edges` (`cedar_data_edges()` output, required; it must name
#'   `last_graded`, NULL when no term is graded).
#' @return One row per `term`, `campus`, `college` and `dept_code` (the
#'   teaching unit; NA for a subject with no mapping row), with
#'   `is_own_unit`, `in_progress` (`cedar_term_in_progress()`: the term's
#'   grades have not posted), `n_registrations` (distinct student ×
#'   course), `n_students` (distinct students), `term_registrations` and
#'   `term_students` (the same over every unit in that term and campus) and
#'   `share_of_registrations` (`n_registrations / term_registrations`).
#'   Attributes: `edge` (the settled term the rows stop at), `latest_term`
#'   (the last term included), `n_member_student_terms`, `n_members`
#'   (distinct students), `member_programs` (the unit's members before
#'   `program_code` narrows them: `primary_major_code`, `is_pre_major`,
#'   `n_students`), `n_unmapped` (member registrations whose subject
#'   has no unit), `suppressed` (the unit rows under `min_n`, as a tibble of
#'   `term`, `campus`, `dept_code`, `n_students`).
get_major_course_units <- function(student_terms, registrations, opt = list()) {
  dept_code <- opt$dept_code
  if (is.null(dept_code) || length(dept_code) != 1L || is.na(dept_code) || !nzchar(dept_code)) {
    stop("[major-course-units.R] opt$dept_code (one unit code) is required.", call. = FALSE)
  }
  needed_st <- c("student_id", "term", "enrolled", "primary_major_code", "primary_dept_code", "is_pre_major")
  missing_st <- setdiff(needed_st, names(student_terms))
  if (length(missing_st) > 0) {
    stop("[major-course-units.R] student_terms lacks ", paste(missing_st, collapse = ", "),
         "; attach its units with attach_default_units().", call. = FALSE)
  }
  needed_reg <- c("student_id", "term", "subject_course", "campus", "college", "department",
                  "registration_status_code")
  missing_reg <- setdiff(needed_reg, names(registrations))
  if (length(missing_reg) > 0) {
    stop("[major-course-units.R] registrations lacks ", paste(missing_reg, collapse = ", "),
         "; attach its units with attach_default_units().", call. = FALSE)
  }

  include_pre_majors  <- isTRUE(opt$include_pre_majors %||% TRUE)
  include_in_progress <- isTRUE(opt$include_in_progress %||% FALSE)
  min_n <- as.integer(opt$min_n %||% 10L)
  grain <- opt$grain %||% "unit"
  if (!grain %in% c("unit", "course", "college")) {
    stop("[major-course-units.R] opt$grain must be \"unit\", \"course\" or \"college\", not ", grain,
         call. = FALSE)
  }

  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[major-course-units.R] opt$data_edges has no settled enrollment edge (last_enrolled_complete).",
         call. = FALSE)
  }
  # A row's in-progress label reads the graded edge, so the edges must say
  # where it is (NULL when nothing is graded).
  if (!"last_graded" %in% names(opt$data_edges)) {
    stop("[major-course-units.R] opt$data_edges names no last_graded edge, which labels a term in progress.",
         call. = FALSE)
  }
  latest <- edge
  if (include_in_progress) {
    # `[[`, not `$`: on a list, `$last_enrolled` partial-matches `last_enrolled_complete`.
    latest <- opt$data_edges[["last_enrolled"]]
    if (is.null(latest)) {
      stop("[major-course-units.R] opt$data_edges has no last_enrolled edge for include_in_progress.",
           call. = FALSE)
    }
    latest <- max(as.integer(latest), edge)
  }

  members <- student_terms %>%
    filter(enrolled, !is.na(primary_dept_code), primary_dept_code == dept_code, term <= latest)
  if (!include_pre_majors) members <- members %>% filter(!is_pre_major %in% TRUE)
  if (!is.null(opt$term)) members <- members %>% filter(term %in% as.integer(opt$term))
  # The programs a caller may narrow to, counted before it does.
  member_programs <- members %>%
    group_by(primary_major_code, is_pre_major = is_pre_major %in% TRUE) %>%
    summarize(n_students = n_distinct(student_id), .groups = "drop") %>%
    arrange(desc(n_students), primary_major_code)
  if (!is.null(opt$program_code)) members <- members %>% filter(primary_major_code %in% opt$program_code)
  members <- members %>% distinct(student_id, term)
  cedar_debug("[major-course-units.R] ", nrow(members), " member student-terms of ", dept_code,
              " to ", latest)

  taken <- registrations %>%
    filter(registration_status_code %in% c(STATUS_REGISTERED, STATUS_DROP_LATE)) %>%
    select(student_id, term, subject_course, campus, college, department) %>%
    inner_join(members, by = c("student_id", "term"))
  taken <- cedar_filter_campus(taken, opt$campus, "get_major_course_units")

  totals <- taken %>%
    group_by(term, campus) %>%
    summarize(
      term_registrations = n_distinct(student_id, subject_course),
      term_students      = n_distinct(student_id),
      .groups = "drop"
    )

  n_unmapped <- sum(is.na(taken$department))
  taken <- taken %>% rename(dept_code = department)
  if (grain == "college") {
    taken <- taken %>%
      mutate(unit_decided = !is.na(dept_code),
             college = if_else(unit_decided, college, NA_character_))
  }
  # What a row is, after its term and campus.
  key_cols <- switch(grain,
    unit    = c("college", "dept_code"),
    course  = c("college", "dept_code", "subject_course"),
    college = c("college", "unit_decided")
  )
  id_cols <- if (grain == "college") key_cols else setdiff(key_cols, "college")

  by_unit <- taken %>%
    group_by(across(all_of(c("term", "campus", key_cols)))) %>%
    summarize(
      n_registrations = n_distinct(student_id, subject_course),
      n_students      = n_distinct(student_id),
      .groups = "drop"
    ) %>%
    inner_join(totals, by = c("term", "campus")) %>%
    mutate(
      in_progress = cedar_term_in_progress(term, opt$data_edges),
      share_of_registrations = n_registrations / term_registrations,
      share_of_students = n_students / term_students
    )
  if (grain != "college") {
    by_unit <- by_unit %>% mutate(is_own_unit = !is.na(dept_code) & dept_code == .env$dept_code)
  }
  by_unit <- by_unit %>%
    select(all_of(c("term", "campus", key_cols,
                    if (grain != "college") "is_own_unit",
                    "in_progress", "n_registrations", "n_students",
                    "term_registrations", "term_students", "share_of_registrations",
                    if (grain == "course") "share_of_students"))) %>%
    arrange(across(all_of(c("term", "campus"))), desc(n_registrations), across(all_of(id_cols)))

  suppressed <- by_unit %>%
    filter(n_students < min_n) %>%
    select(all_of(c("term", "campus", id_cols, "n_students")))
  result <- by_unit %>% filter(n_students >= min_n)

  attr(result, "edge")        <- edge
  attr(result, "latest_term") <- latest
  attr(result, "n_member_student_terms") <- nrow(members)
  attr(result, "n_members")   <- n_distinct(members$student_id)
  attr(result, "member_programs") <- member_programs
  attr(result, "n_unmapped")  <- n_unmapped
  attr(result, "suppressed")  <- suppressed
  cedar_debug("[major-course-units.R] ", nrow(result), " unit rows (", nrow(suppressed),
              " under min_n ", min_n, ")")
  result
}


# ── Plot preparation ────────────────────────────────────────────────────────
# Shapes rows the cone returned; nothing is recounted from a table.

#' One term's teaching units as bars: the own unit, the top outside units, the rest by college
#'
#' @param unit_rows One term's `get_major_course_units()` unit rows (every row,
#'   before any small-cell guard) with a `unit_label` and a `college_label`:
#'   the label the college chart draws the unit's college under in that term
#'   and campus, so the bars under one label add up to that chart's segment.
#' @param own_label The label of the members' own unit, for a campus where it
#'   taught them nothing: its bar is still drawn, at zero.
#' @param min_n The smallest distinct-student count a campus needs to be drawn
#'   at all, and an outside unit needs for a bar of its own.
#' @param n_top How many outside units get a bar per campus.
#' @param pooled_label The `college_label` holding every college under the
#'   guard, whose bar is drawn last; NULL when the rows carry no such label.
#' @return One row per `campus` and bar, in drawing order: `unit_label`,
#'   `college_label` (NA for an own-unit bar at zero), `kind` (`"own"`,
#'   `"outside"`, `"undecided"` for subjects with no unit, `"rest"` for one
#'   college's units without a bar of their own), `n_units` (the units the
#'   bar holds), `n_registrations`, `share` (of the campus's member
#'   registrations that term), `term_students` and `term_registrations`. A
#'   campus's shares sum to 1, and its bars under one `college_label` to
#'   that college's registrations: an own unit teaching under two colleges
#'   has a bar under each.
prepare_major_course_units_top_units <- function(unit_rows, own_label, min_n = 10L, n_top = 8L,
                                                 pooled_label = NULL) {
  needed <- c("campus", "dept_code", "unit_label", "college_label", "is_own_unit", "n_students",
              "n_registrations", "term_students", "term_registrations")
  missing <- setdiff(needed, names(unit_rows))
  if (length(missing) > 0) {
    stop("[major-course-units.R] unit_rows lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if ("term" %in% names(unit_rows) && n_distinct(unit_rows$term) > 1L) {
    stop("[major-course-units.R] prepare_major_course_units_top_units() reads one term's rows.", call. = FALSE)
  }
  min_n <- as.integer(min_n)
  unit_rows <- unit_rows %>% filter(term_students >= min_n) %>% mutate(.row = row_number())

  totals <- unit_rows %>%
    group_by(campus) %>%
    summarize(term_students = first(term_students), term_registrations = first(term_registrations),
              .groups = "drop")
  # The own unit's bar, under its college; one under each where it teaches
  # under two, named by the college; and one at zero, under no college, on a
  # campus where it taught these majors nothing.
  own <- unit_rows %>%
    filter(is_own_unit) %>%
    group_by(campus, college_label) %>%
    summarize(n_registrations = sum(n_registrations), .groups = "drop") %>%
    right_join(totals %>% select(campus), by = "campus") %>%
    group_by(campus) %>%
    mutate(unit_label = if (n() > 1L) paste0(own_label, " (own courses, ", college_label, ")")
                        else paste0(own_label, " (own courses)")) %>%
    ungroup() %>%
    transmute(campus, unit_label, college_label, kind = "own", n_units = 1L,
              n_registrations = coalesce(n_registrations, 0L))
  picked <- unit_rows %>%
    filter(!is_own_unit, n_students >= min_n) %>%
    group_by(campus) %>%
    arrange(desc(n_registrations), unit_label, .by_group = TRUE) %>%
    slice_head(n = as.integer(n_top)) %>%
    # Two rows may carry one unit name (a unit teaching under two colleges):
    # the college tells them apart, so neither bar is stacked on the other.
    mutate(unit_label = if_else(duplicated(unit_label) | duplicated(unit_label, fromLast = TRUE),
                                paste0(unit_label, " (", college_label, ")"), unit_label)) %>%
    ungroup()
  outside <- picked %>%
    transmute(campus, unit_label, college_label, kind = if_else(is.na(dept_code), "undecided", "outside"),
              n_units = 1L, n_registrations)
  # Every unit without a bar of its own, one bar per college, so the bars under
  # a college's label add up to that college's share of the term: a single bar
  # for all of them hid most of a college whose units are each small.
  has_bar <- bind_rows(picked %>% distinct(campus, college_label),
                       unit_rows %>% filter(is_own_unit) %>% distinct(campus, college_label)) %>%
    distinct() %>%
    mutate(has_bar = TRUE)
  rest <- unit_rows %>%
    filter(!is_own_unit, !.row %in% picked$.row) %>%
    group_by(campus, college_label) %>%
    summarize(n_units = n(), n_registrations = sum(n_registrations), .groups = "drop") %>%
    left_join(has_bar, by = c("campus", "college_label")) %>%
    mutate(kind = "rest",
           unit_label = paste0(college_label, ": ", n_units, if_else(has_bar %in% TRUE, " other", ""),
                               if_else(n_units == 1L, " unit", " units"))) %>%
    select(-has_bar)

  bind_rows(own, outside, rest) %>%
    inner_join(totals %>% select(campus, term_students, term_registrations), by = "campus") %>%
    mutate(share = n_registrations / term_registrations) %>%
    arrange(campus, case_when(kind == "own" ~ 0L, kind == "rest" ~ 2L, TRUE ~ 1L),
            kind == "rest" & college_label %in% pooled_label,
            desc(n_registrations), unit_label) %>%
    select(campus, unit_label, college_label, kind, n_units, n_registrations, share, term_students,
           term_registrations)
}

#' The outside courses a major's students sit in, term by term
#'
#' @param course_rows One row per `term`, `campus` and outside course that
#'   cleared the guard, with `subject_course`, `unit_label`, `n_students`,
#'   `term_students`, `share_of_students` and `in_progress`, as
#'   `compute_dept_course_units_tab()` prepares them (`outside_courses`).
#' @param terms Every term to give a column, whether or not a course cleared
#'   the guard in it: the terms the members hold a registration in.
#' @param term_types The term types to keep; NULL keeps every term.
#' @param n_top How many courses per campus are marked `top`, for the chart.
#' @return A list: `terms` (the terms kept, in order), `courses` (one row per
#'   `campus` and course: `rank` within the campus by `student_terms`, the
#'   majors counted in the course over the terms kept, with `n_terms`, the
#'   terms it cleared the guard in, and `top`), `cells` (the rows of
#'   `course_rows` in the terms kept) and `table` (`courses` with one
#'   `t_<term>` column per term kept, the majors in the course that term; NA
#'   where it did not clear the guard).
prepare_major_course_units_course_history <- function(course_rows, terms, term_types = NULL, n_top = 15L) {
  needed <- c("term", "campus", "subject_course", "unit_label", "n_students", "term_students",
              "share_of_students", "in_progress")
  missing <- setdiff(needed, names(course_rows))
  if (length(missing) > 0) {
    stop("[major-course-units.R] course_rows lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  terms <- sort(unique(as.integer(terms)))
  if (!all(course_rows$term %in% terms)) {
    stop("[major-course-units.R] course_rows holds a term that `terms` does not.", call. = FALSE)
  }
  if (!is.null(term_types)) terms <- terms[get_term_type(terms) %in% term_types]
  cells <- course_rows %>% filter(term %in% terms)
  if (anyDuplicated(cells[c("term", "campus", "subject_course", "unit_label")]) > 0L) {
    stop("[major-course-units.R] course_rows repeats a term, campus, course and unit.", call. = FALSE)
  }
  courses <- cells %>%
    group_by(campus, subject_course, unit_label) %>%
    summarize(n_terms = n(), student_terms = sum(n_students), .groups = "drop") %>%
    group_by(campus) %>%
    arrange(desc(student_terms), subject_course, unit_label, .by_group = TRUE) %>%
    mutate(rank = row_number(), top = rank <= as.integer(n_top)) %>%
    ungroup() %>%
    select(campus, rank, subject_course, unit_label, n_terms, student_terms, top)
  wide <- cells %>%
    mutate(term = factor(term, levels = terms)) %>%
    select(campus, subject_course, unit_label, term, n_students) %>%
    tidyr::pivot_wider(names_from = term, values_from = n_students, names_prefix = "t_",
                       names_expand = TRUE)
  list(terms = terms, courses = courses, cells = cells,
       table = courses %>% left_join(wide, by = c("campus", "subject_course", "unit_label")))
}


# ── Plots ───────────────────────────────────────────────────────────────────
# Prepared rows in, plotly out; no table is re-read here.

#' Share of a major's registrations in its own unit's courses, a line per campus
#'
#' @param own_share One row per `term` and `campus` with `students`,
#'   `registrations`, `own_registrations` and `own_share`, as
#'   `compute_dept_course_units_tab()` prepares them.
#' @param min_n A term and campus with fewer members than this has no point.
#' @param term_types The term types to draw (`"fall"`, `"spring"`,
#'   `"summer"`); NULL draws every term. Summer course-taking is a different,
#'   smaller mix, so a line through every term rises or falls every third
#'   point for no reason of the department's.
#' @return A plotly, or NULL when no term and campus drawn has `min_n` members.
plot_major_course_units_own_share <- function(own_share, min_n = 10L, term_types = NULL) {
  needed <- c("term", "campus", "students", "registrations", "own_registrations", "own_share")
  missing <- setdiff(needed, names(own_share))
  if (length(missing) > 0) {
    stop("[major-course-units.R] own_share lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!is.null(term_types)) own_share <- own_share %>% filter(get_term_type(term) %in% term_types)
  shown <- own_share %>% filter(students >= as.integer(min_n))
  if (nrow(shown) == 0L) return(NULL)
  # A campus under the guard in some term keeps the term, with no point, so
  # its line breaks there instead of bridging the gap.
  rows <- own_share %>%
    filter(campus %in% shown$campus) %>%
    mutate(
      own_share = if_else(students >= as.integer(min_n), own_share, NA_real_),
      term_label = term_axis_factor(term),
      detail = paste0(format(own_registrations, big.mark = ",", trim = TRUE), " of ",
                      format(registrations, big.mark = ",", trim = TRUE), " registrations, ",
                      format(students, big.mark = ",", trim = TRUE), " majors")
    ) %>%
    arrange(campus, term)
  plotly::plot_ly(
    rows,
    x = ~term_label, y = ~own_share, color = ~campus, colors = cedar_plotly_palette(rows$campus),
    type = "scatter", mode = "lines+markers", connectgaps = FALSE,
    customdata = ~detail,
    hovertemplate = "%{x}<br>%{fullData.name}: %{y:.1%} in own courses<br>%{customdata}<extra></extra>"
  ) %>%
    plotly::layout(
      xaxis = list(title = "", tickangle = -45, categoryorder = "array",
                   categoryarray = levels(rows$term_label)),
      yaxis = list(title = "Share of registrations in own courses", tickformat = ".0%", rangemode = "tozero"),
      legend = list(orientation = "h", x = 0, y = -0.25)
    )
}

#' Share of a major's registrations by teaching college, stacked by term
#'
#' @param by_college One row per `term`, `campus`, `college_label` with
#'   `share` (of the term and campus's member registrations),
#'   `n_registrations` and `pooled` (the row holding every college under the
#'   guard), as `compute_dept_course_units_tab()` prepares them.
#' @param term_types The term types to draw; NULL draws every term.
#' @param campuses The campuses to draw; NULL draws every campus.
#' @return A named list, one plotly per campus drawn (`names` are the
#'   campuses). Colleges stack in the order of
#'   `major_course_units_college_colors()` over every term of the campuses
#'   drawn, so a college keeps its colour and place from chart to chart and
#'   whatever term types are ticked; the pooled row is last and grey.
plot_major_course_units_by_college <- function(by_college, term_types = NULL, campuses = NULL) {
  needed <- c("term", "campus", "college_label", "share", "n_registrations", "pooled")
  missing <- setdiff(needed, names(by_college))
  if (length(missing) > 0) {
    stop("[major-course-units.R] by_college lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!is.null(campuses)) by_college <- by_college %>% filter(campus %in% campuses)
  colors <- major_course_units_college_colors(by_college)
  if (!is.null(term_types)) by_college <- by_college %>% filter(get_term_type(term) %in% term_types)
  if (nrow(by_college) == 0L) return(list())
  drawn <- sort(unique(by_college$campus))
  stats::setNames(lapply(drawn, function(cmp) {
    rows <- by_college %>%
      filter(campus == cmp) %>%
      mutate(term_label = term_axis_factor(term),
             college_label = factor(college_label, levels = intersect(names(colors), college_label))) %>%
      arrange(term, college_label)
    plotly::plot_ly(
      rows,
      x = ~term_label, y = ~share, color = ~college_label, colors = colors,
      type = "bar",
      customdata = ~n_registrations,
      hovertemplate = "%{x}<br>%{fullData.name}: %{y:.1%} (%{customdata} registrations)<extra></extra>"
    ) %>%
      plotly::layout(
        barmode = "stack",
        xaxis = list(title = "", tickangle = -45, categoryorder = "array",
                     categoryarray = levels(rows$term_label)),
        yaxis = list(title = "Share of registrations", tickformat = ".0%", range = c(0, 1)),
        legend = list(orientation = "h", x = 0, y = -0.25, traceorder = "normal")
      )
  }), drawn)
}

#' The colour each teaching college keeps on the Courses Taken charts
#'
#' @param by_college Rows with `college_label`, `n_registrations` and `pooled`,
#'   as `compute_dept_course_units_tab()` prepares them.
#' @return Colours named by college label, in the order of the colleges'
#'   registrations over every row given; the pooled label is last and grey.
#'   The latest term's unit bars and the colleges over time read the same
#'   colours, so a college is one colour in both.
major_course_units_college_colors <- function(by_college) {
  needed <- c("college_label", "n_registrations", "pooled")
  missing <- setdiff(needed, names(by_college))
  if (length(missing) > 0) {
    stop("[major-course-units.R] by_college lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  label_order <- by_college %>%
    group_by(college_label, pooled) %>%
    summarize(n = sum(n_registrations), .groups = "drop") %>%
    arrange(pooled, desc(n), college_label)
  colors <- cedar_plotly_palette(label_order$college_label, label_order = label_order$college_label)
  colors[label_order$college_label[label_order$pooled]] <- CEDAR_SEMANTIC_COLORS[["other"]]
  colors
}

#' One term's teaching units, a horizontal bar per unit and a chart per campus
#'
#' @param top_units `prepare_major_course_units_top_units()` output.
#' @param colors Colours named by `college_label`
#'   (`major_course_units_college_colors()`), so a bar is its college's colour
#'   on the colleges-over-time chart.
#' @return A named list, one plotly per campus (`names` are the campuses): the
#'   own unit's bar first, the outside units below it in order of
#'   registrations, then each college's remaining units as one paler bar. A
#'   bar is coloured by its teaching college, and the legend names them.
plot_major_course_units_top_units <- function(top_units, colors) {
  needed <- c("campus", "unit_label", "college_label", "kind", "n_registrations", "share")
  missing <- setdiff(needed, names(top_units))
  if (length(missing) > 0) {
    stop("[major-course-units.R] top_units lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (nrow(top_units) == 0L) return(list())
  uncoloured <- setdiff(stats::na.omit(top_units$college_label), names(colors))
  if (length(uncoloured) > 0) {
    stop("[major-course-units.R] colors names no colour for ", paste(uncoloured, collapse = ", "), call. = FALSE)
  }
  campuses <- sort(unique(top_units$campus))
  stats::setNames(lapply(campuses, function(cmp) {
    rows <- top_units %>%
      filter(campus == cmp) %>%
      mutate(share_label = sprintf("%.1f%%", 100 * share),
             detail = paste0(format(n_registrations, big.mark = ",", trim = TRUE), " registrations"))
    plot <- plotly::plot_ly()
    # One trace per college, in the colleges' own order, so the legend reads
    # as the colleges chart's does. An own-unit bar at zero has no college.
    for (label in c(intersect(names(colors), rows$college_label), if (anyNA(rows$college_label)) NA)) {
      part <- rows[rows$college_label %in% label, ]
      plot <- plotly::add_trace(
        plot, data = part,
        x = ~share, y = ~unit_label, type = "bar", orientation = "h",
        name = if (is.na(label)) "" else label, showlegend = !is.na(label),
        marker = list(color = if (is.na(label)) CEDAR_SEMANTIC_COLORS[["other"]] else colors[[label]],
                      # The remaining units of a college are paler than a unit's own bar.
                      opacity = ifelse(part$kind == "rest", 0.45, 1)),
        text = ~share_label, textposition = "outside", cliponaxis = FALSE,
        customdata = ~detail,
        hovertemplate = "%{y}<br>%{text} of registrations (%{customdata})<extra>%{fullData.name}</extra>"
      )
    }
    plot %>%
      plotly::layout(
        barmode = "overlay",
        xaxis = list(title = "Share of registrations", tickformat = ".0%",
                     range = c(0, max(rows$share) * 1.15)),
        yaxis = list(title = "", categoryorder = "array", categoryarray = rev(rows$unit_label),
                     automargin = TRUE),
        legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", traceorder = "normal")
      )
  }), campuses)
}

#' The outside courses a major's students sit in most, a term-by-course grid per campus
#'
#' @param history `prepare_major_course_units_course_history()` output.
#' @param campuses The campuses to draw; NULL draws every campus with a course.
#' @return A named list, one plotly per campus with a `top` course (`names`
#'   are the campuses): a row per course, the most-taken first, and a column
#'   per term; a cell holds the majors in the course that term and is shaded
#'   by their share of that term's majors on the campus, and is blank where
#'   the course did not clear the guard.
plot_major_course_units_course_history <- function(history, campuses = NULL) {
  needed <- c("terms", "courses", "cells")
  missing <- setdiff(needed, names(history))
  if (length(missing) > 0) {
    stop("[major-course-units.R] history lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  top <- history$courses %>% filter(top)
  if (!is.null(campuses)) top <- top %>% filter(campus %in% campuses)
  if (nrow(top) == 0L) return(list())
  term_labels <- term_code_to_axis_label(history$terms)
  drawn <- sort(unique(top$campus))
  stats::setNames(lapply(drawn, function(cmp) {
    listed <- top %>% filter(campus == cmp) %>% arrange(rank)
    # Two units may teach one course code: the unit tells the rows apart.
    listed <- listed %>%
      mutate(course_label = if_else(duplicated(subject_course) | duplicated(subject_course, fromLast = TRUE),
                                    paste0(subject_course, " (", unit_label, ")"), subject_course))
    grid <- tidyr::expand_grid(listed %>% select(campus, subject_course, unit_label, course_label),
                               term = history$terms) %>%
      left_join(history$cells, by = c("campus", "subject_course", "unit_label", "term")) %>%
      mutate(
        term_label = term_code_to_axis_label(term),
        count_label = if_else(is.na(n_students), "", format(n_students, big.mark = ",", trim = TRUE)),
        hover = if_else(
          is.na(n_students),
          paste0(course_label, ", ", term_label, "<br>under the guard, or not taken"),
          paste0(course_label, " (", unit_label, "), ", term_label, "<br>",
                 format(n_students, big.mark = ",", trim = TRUE), " of ",
                 format(term_students, big.mark = ",", trim = TRUE), " majors (",
                 sprintf("%.1f%%", 100 * share_of_students), ")")
        )
      )
    plotly::plot_ly(
      grid,
      x = ~term_label, y = ~course_label, z = ~share_of_students, type = "heatmap",
      text = ~count_label, texttemplate = "%{text}", hovertext = ~hover, hoverinfo = "text",
      colors = c(CEDAR_SURFACE_TINTS[["success"]], CEDAR_PALETTE[[1]]),
      # The shading starts at zero, so a pale cell is a small share on every campus.
      zauto = FALSE, zmin = 0, zmax = max(grid$share_of_students, na.rm = TRUE),
      xgap = 2, ygap = 2,
      colorbar = list(title = "Share of majors", tickformat = ".0%")
    ) %>%
      plotly::layout(
        xaxis = list(title = "", tickangle = -45, categoryorder = "array", categoryarray = term_labels,
                     showgrid = FALSE),
        yaxis = list(title = "", categoryorder = "array", categoryarray = rev(listed$course_label),
                     automargin = TRUE, showgrid = FALSE)
      )
  }), drawn)
}
