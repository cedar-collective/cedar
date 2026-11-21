# graduation-dashboard.R — the payload for Bird's Eye > Graduation
#
# Where do students leave without a degree, and how far along were they?
# get_exit_credits() (cones/exit-credits.R) answers it; this file scopes it
# for the page, picks out the students who were far along (`opt$line`
# credits or more), counts them by last term, college and major, and holds
# the page's sentences, tables and charts. One text rendering,
# format_graduation_dashboard(), is the only place a number is rounded.
#
# The credits are each departed student's stamped total on their last term's
# row: the one sanctioned read of that field (field-reliability.md, "A student
# who has stopped"). Nothing here reads it for anyone else.
#
#   build_graduation_dashboard()   the payload
#   graduation_headline()          the lead sentence
#   graduation_band_table()        each band with its standing counts
#   graduation_required_table()    each plan's required courses, counted
#   graduation_credit_source_note(), graduation_required_lead(), graduation_plan_note()
#   plot_exit_bands(), plot_exit_series(), plot_exit_required()
#   format_graduation_dashboard()  the text preview

GRADUATION_LINES <- c(90, 115, 120)

#' The payload for Bird's Eye > Graduation
#'
#' @param student_terms,programs,degrees,terms As `get_exit_credits()` takes
#'   them; `student_terms` also carries `primary_college_code`, the
#'   college of the student's primary major that term.
#' @param dims The dimension tables, to name majors and colleges.
#' @param attempts,boards Optional: `cedar_attempts` and the degree boards
#'   (`publish_degree_drafts()`: `catalog`, `roadmaps`). With both, the
#'   payload holds `required`: the far-along students by what they did in each
#'   course their program's plan names (`get_exit_requirement_progress()`).
#' @param opt `data_edges` (required), `student_level`, `campus`,
#'   `first_exit_term`, `line` (credits that count as far along; default 90),
#'   `min_list` (fewest students for a major to be listed by name; default
#'   10), `min_n`.
#' @return list(`bands`, `series` (one row per last term: `n_left`, `n_far`,
#'   `n_done`: at 120 or more), `colleges`, `majors` (far-along students by
#'   group: `n`, `n_done`, `n_flagged`, `n_pell`; majors under `min_list`
#'   pooled), `required` (NULL without `attempts` and `boards`), `meta`).
build_graduation_dashboard <- function(student_terms, programs, degrees, terms, dims, opt = list(),
                                       attempts = NULL, boards = NULL) {
  if (!"primary_college_code" %in% names(student_terms)) {
    stop("[graduation-dashboard.R] student_terms lacks primary_college_code (the loader attaches it).", call. = FALSE)
  }
  if (!"is_pre_major" %in% names(student_terms)) {
    stop("[graduation-dashboard.R] student_terms lacks is_pre_major.", call. = FALSE)
  }
  line <- as.numeric(opt$line %||% GRADUATION_LINES[[1]])
  min_list <- as.integer(opt$min_list %||% 10L)
  exit <- get_exit_credits(student_terms, programs, degrees, terms, opt)
  done_at <- max(exit$meta$breaks)
  students <- exit$students %>%
    left_join(student_terms %>% transmute(student_id, exit_term = as.integer(term), college = primary_college_code,
                                          is_pre_major),
              by = c("student_id", "exit_term"), relationship = "one-to-one")
  far <- students %>% filter(!is.na(credits), credits >= line)

  count_group <- function(rows, col) {
    rows %>%
      group_by(group = .data[[col]]) %>%
      summarize(n = n(), n_done = sum(credits >= done_at), n_flagged = sum(flagged %in% TRUE),
                n_pell = sum(ever_pell %in% TRUE), .groups = "drop") %>%
      arrange(desc(n), group)
  }
  colleges <- count_group(far, "college")
  college_names <- college_code_names(dims)
  colleges$label <- dplyr::coalesce(unname(college_names[colleges$group]), colleges$group, "No college on record")

  majors <- count_group(far, "primary_major_code")
  # `group` is the major code, which the page shows beside the name: two
  # programs may share a name, and a pre-major is labelled as one.
  major_names <- name_program_codes(far$primary_major_code, dims, far$is_pre_major)
  majors$label <- dplyr::coalesce(unname(major_names[majors$group]), "No major on record")
  # A major with few such students is not listed by name: pooled, counted.
  small <- majors$n < min_list
  n_pooled <- sum(small)
  if (any(small)) {
    pooled <- majors[small, ] %>%
      summarize(group = NA_character_, n = sum(n), n_done = sum(n_done), n_flagged = sum(n_flagged),
                n_pell = sum(n_pell), label = paste0("All other majors (", n_pooled, ")"))
    majors <- dplyr::bind_rows(majors[!small, ], pooled)
  }

  required <- NULL
  if (!is.null(attempts) && !is.null(boards)) {
    plans <- degree_named_requirements(boards$roadmaps, boards$catalog$catalogs$catalog_id)
    required <- get_exit_requirement_progress(far, programs, attempts, plans$courses,
                                              boards$catalog$program_codes, list(min_n = min_list))
    at <- match(required$programs$catalog_id, boards$catalog$catalogs$catalog_id)
    required$programs$label <- boards$catalog$catalogs$degree_label[at]
    required$programs$n_not_read <- dplyr::coalesce(
      plans$not_read$n_not_read[match(required$programs$catalog_id, plans$not_read$catalog_id)], 0L)
  }
  # How much of a far-along student's total was earned here; the rest came
  # from elsewhere, and its courses are not on record.
  both <- far %>% filter(!is.na(credits_here))

  series <- students %>%
    group_by(exit_term) %>%
    summarize(n_left = n(), n_far = sum(credits >= line, na.rm = TRUE),
              n_done = sum(credits >= done_at, na.rm = TRUE), .groups = "drop") %>%
    arrange(exit_term)

  list(
    bands = exit$bands, series = series, colleges = colleges, majors = majors, required = required,
    meta = c(exit$meta, list(line = line, done_at = done_at, n_far = nrow(far),
                             n_done = sum(far$credits >= done_at),
                             n_far_flagged = sum(far$flagged %in% TRUE),
                             n_far_pell = sum(far$ever_pell %in% TRUE),
                             n_not_recorded = sum(is.na(students$credits)),
                             n_far_here_known = nrow(both),
                             median_credits = stats::median(both$credits),
                             median_credits_here = stats::median(both$credits_here),
                             n_far_mostly_elsewhere = sum(both$credits_here < both$credits / 2),
                             min_list = min_list, n_majors_pooled = n_pooled))
  )
}

.graduation_n <- function(x) format(as.integer(round(x)), big.mark = ",", trim = TRUE)

.format_graduation_required <- function(payload) {
  r <- payload$required
  t <- graduation_required_table(payload)
  n <- function(x) ifelse(is.na(x), "--", .graduation_n(dplyr::coalesce(x, 0L)))
  shown <- r$programs[r$programs$shown, ]
  plans <- unlist(lapply(seq_len(nrow(shown)), function(i) {
    rows <- t[t$plan == shown$label[i], ]
    c("", paste0("### ", shown$label[i]), graduation_plan_note(payload, shown$catalog_id[i]),
      sprintf("  %-22s %8s %8s %8s", "Course", "Passed", "Tried", "None"),
      sprintf("  %-22s %8s %8s %8s", substr(rows$course, 1, 22), n(rows$n_passed), n(rows$n_tried), n(rows$n_none)))
  }))
  c("", "## The courses their plan names, and what they did in them here",
    graduation_credit_source_note(payload),
    paste0(graduation_required_lead(payload), " Plans with fewer than ", r$meta$min_n,
           " such students are not listed: ", r$meta$n_plans_withheld, " (",
           .graduation_n(r$meta$n_students_withheld), " students)."),
    "Passed: a passing grade here in the course. Tried: a grade or late withdrawal here, never a pass.",
    "None: no attempt here, which is not the same as still required. -- : no one had taken a course under this code by then.",
    plans)
}

#' The page's lead sentence: who left, and how many were far along
#' @param payload A `build_graduation_dashboard()` result.
graduation_headline <- function(payload) {
  m <- payload$meta
  if (m$n_left == 0L) return("No student in this scope has a last term that can be judged yet.")
  paste0(
    "Of the ", .graduation_n(m$n_left + m$n_with_degree), " students whose last term was between ",
    fmt_term(m$first_exit_term), " and ", fmt_term(m$last_exit_term), ", ",
    .graduation_n(m$n_with_degree), if (m$n_with_degree == 1L) " holds" else " hold",
    " a degree and ", .graduation_n(m$n_left),
    " left without one. ", .graduation_n(m$n_far), " of those who left had ", m$line,
    " credits or more",
    if (m$line < m$done_at) paste0(", ", .graduation_n(m$n_done), " of them ", m$done_at, " or more") else "",
    "."
  )
}

#' Each credit band with its standing counts, for display
#'
#' @param payload A `build_graduation_dashboard()` result.
#' @return A tibble: `band`, `n`, `share_pct`, then `pell_pct`,
#'   `gpa_below_pct`, `over_ceiling_pct`, `flagged_pct` (each NA under the
#'   guard or where nothing is on record).
graduation_band_table <- function(payload) {
  payload$bands %>%
    transmute(band = as.character(band), n, share_pct, pell_pct, gpa_below_pct, over_ceiling_pct, flagged_pct)
}

# ── Plots ────────────────────────────────────────────────────────────────────

#' Students who left, by credits at their last term
#'
#' One bar a band, labelled with its count; the bands at or past the page's
#' line are the page's subject and take the accent colour.
plot_exit_bands <- function(payload) {
  b <- payload$bands
  labels <- as.character(b$band)
  floor_of <- c(0, payload$meta$breaks, NA)[seq_along(labels)]
  far <- !is.na(floor_of) & floor_of >= payload$meta$line & labels != "Not recorded"
  plotly::plot_ly(
    x = labels, y = b$n, type = "bar", text = .graduation_n(b$n), textposition = "outside", cliponaxis = FALSE,
    marker = list(color = ifelse(far, CEDAR_PALETTE[[2]], CEDAR_SEMANTIC_COLORS[["reference"]])),
    hovertext = paste0(labels, " credits<br>", .graduation_n(b$n), " students (",
                       sprintf("%.1f%%", b$share_pct), ")"),
    hoverinfo = "text", showlegend = FALSE) %>%
    plotly::layout(
      xaxis = list(title = "Credits earned when they stopped", type = "category",
                   categoryorder = "array", categoryarray = labels),
      yaxis = list(title = "Students who left without a degree"),
      margin = list(t = 30))
}

#' Each plan's required courses with their counts, for display
#'
#' @param payload A `build_graduation_dashboard()` result holding `required`.
#' @return A tibble, plans by size and courses in plan order: `plan`,
#'   `n_students`, `course` (the catalog's code), `title`, `semester`,
#'   `readable`, `n_passed`, `n_tried`, `n_none`.
graduation_required_table <- function(payload) {
  r <- payload$required
  if (is.null(r)) stop("[graduation-dashboard.R] the payload holds no required-course counts.", call. = FALSE)
  r$courses %>%
    mutate(plan = r$programs$label[match(catalog_id, r$programs$catalog_id)]) %>%
    transmute(plan, n_students, course = subject_course, title, semester, readable, n_passed, n_tried, n_none)
}

#' The sentence on where far-along students' credits were earned
#' @param payload A `build_graduation_dashboard()` result.
graduation_credit_source_note <- function(payload) {
  m <- payload$meta
  if (m$n_far_here_known == 0L) return("Where these students earned their credits is not on record.")
  paste0("Half of these students left with ", round(m$median_credits), " credits or more, and half had earned ",
         round(m$median_credits_here), " or fewer of them here. ", .graduation_n(m$n_far_mostly_elsewhere), " of ",
         .graduation_n(m$n_far_here_known), " earned most of their credits somewhere else, so a course with no ",
         "attempt here may have been met there.")
}

#' The sentence on how many of these students a degree plan covers
#' @param payload A `build_graduation_dashboard()` result holding `required`.
graduation_required_lead <- function(payload) {
  m <- payload$required$meta
  paste0(.graduation_n(m$n_with_plan), " of the ", .graduation_n(m$n_students),
         " students who left without a degree with ", payload$meta$line, " credits or more were in a program with a degree plan on file; ",
         .graduation_n(m$n_without_plan), " were not.")
}

#' One plan's line: its students, and what of the plan is not read
#' @param payload A `build_graduation_dashboard()` result holding `required`.
#' @param catalog_id The plan.
graduation_plan_note <- function(payload, catalog_id) {
  r <- payload$required
  plan <- r$programs[r$programs$catalog_id == catalog_id, ]
  if (nrow(plan) != 1L || !plan$shown) stop("[graduation-dashboard.R] no listed plan ", catalog_id, call. = FALSE)
  unreadable <- sum(!r$courses$readable[r$courses$catalog_id == catalog_id])
  paste0(.graduation_n(plan$n_students), " students in this program left without a degree with ",
         payload$meta$line, " credits or more, ", .graduation_n(plan$n_pre_major),
         " of them pre-majors. Not read: ", plan$n_not_read, " choices and elective slots",
         if (unreadable > 0L) paste0("; ", unreadable, if (unreadable == 1L) " course" else " courses",
                                     " no one had taken under the plan's number by then") else "", ".")
}

#' One plan's required courses: tried and never passed, passed, no attempt
#'
#' One bar a course, in plan order from the top. "Tried here, never passed"
#' sits first so its lengths compare across courses.
#' @param payload A `build_graduation_dashboard()` result holding `required`.
#' @param catalog_id The plan.
plot_exit_required <- function(payload, catalog_id) {
  r <- payload$required
  rows <- r$courses[r$courses$catalog_id == catalog_id & r$courses$readable, ]
  if (nrow(rows) == 0L) stop("[graduation-dashboard.R] plan ", catalog_id, " has no readable course.", call. = FALSE)
  hover <- function(count, what) paste0(rows$subject_course, " · ", rows$title, "<br>", .graduation_n(count), " ", what)
  bar <- function(fig, count, name, what, colour) {
    plotly::add_trace(fig, y = rows$subject_course, x = count, type = "bar", orientation = "h", name = name,
                      marker = list(color = colour), text = .graduation_n(count), textposition = "inside",
                      insidetextanchor = "middle", textangle = 0, hovertext = hover(count, what), hoverinfo = "text")
  }
  plotly::plot_ly(height = 140 + 26 * nrow(rows)) %>%
    bar(rows$n_tried, "Tried here, never passed", "tried it here and never passed", CEDAR_PALETTE[[2]]) %>%
    bar(rows$n_passed, "Passed here", "passed it here", CEDAR_SEMANTIC_COLORS[["positive"]]) %>%
    bar(rows$n_none, "No attempt here", "have no attempt here", CEDAR_SEMANTIC_COLORS[["reference"]]) %>%
    plotly::layout(
      barmode = "stack",
      yaxis = list(title = "", type = "category", categoryorder = "array",
                   categoryarray = rev(rows$subject_course)),
      xaxis = list(title = paste0("Students who left without a degree with ", payload$meta$line, " credits or more")),
      legend = list(orientation = "h", y = 1.02, yanchor = "bottom", traceorder = "normal"),
      margin = list(t = 40, b = 60))
}

#' Far-along students who left, by last term
plot_exit_series <- function(payload) {
  s <- payload$series
  labels <- vapply(s$exit_term, fmt_term, character(1))
  m <- payload$meta
  plotly::plot_ly(
    x = labels, y = s$n_far, type = "bar", text = .graduation_n(s$n_far), textposition = "outside", cliponaxis = FALSE,
    marker = list(color = CEDAR_PALETTE[[2]]), name = paste(m$line, "credits or more"),
    hovertext = paste0(labels, "<br>", .graduation_n(s$n_far), " left with ", m$line, " credits or more<br>",
                       .graduation_n(s$n_done), " with ", m$done_at, " or more<br>",
                       .graduation_n(s$n_left), " left in all"),
    hoverinfo = "text", showlegend = FALSE) %>%
    plotly::layout(
      xaxis = list(title = "Last enrolled term", type = "category", categoryorder = "array",
                   categoryarray = labels),
      yaxis = list(title = paste0("Left with ", m$line, " credits or more")),
      margin = list(t = 30))
}

# ── Text preview ─────────────────────────────────────────────────────────────

#' The Graduation payload as text
#'
#' @param payload A `build_graduation_dashboard()` result.
#' @return Character vector, one element per line.
format_graduation_dashboard <- function(payload) {
  m <- payload$meta
  pct <- function(x) ifelse(is.na(x), "--", sprintf("%.1f%%", x))
  b <- graduation_band_table(payload)
  group_lines <- function(g) sprintf("  %-40s %6s %8s %10s %6s", substr(g$label, 1, 40), .graduation_n(g$n),
                                     .graduation_n(g$n_done), .graduation_n(g$n_flagged), .graduation_n(g$n_pell))
  group_head <- sprintf("  %-40s %6s %8s %10s %6s", "", "Left", paste0(m$done_at, "+"), "Standards", "Pell")
  c(
    "# Graduation: students who left without a degree",
    paste0("Enrollment settled through ", fmt_term(m$edge), "; degrees posted through ", fmt_term(m$degree_edge),
           ". ", .graduation_n(m$n_not_judged), " last terms are too recent to judge (everyone still enrolled is among them)."),
    "", graduation_headline(payload), "",
    "## By credits when they stopped",
    sprintf("  %-14s %7s %7s %7s %10s %10s %8s", "Credits", "Left", "Share", "Pell", paste0("GPA <", m$gpa_floor),
            paste0(m$credit_ceiling, "+ att."), "Either"),
    sprintf("  %-14s %7s %7s %7s %10s %10s %8s", b$band, .graduation_n(b$n), pct(b$share_pct), pct(b$pell_pct),
            pct(b$gpa_below_pct), pct(b$over_ceiling_pct), pct(b$flagged_pct)),
    paste0("  ", .graduation_n(m$n_last_term_added), if (m$n_last_term_added == 1L) " total includes" else " totals include",
           " the last term's own credits, added because the record was pulled before the next term began."),
    "",
    paste0("## Left with ", m$line, " credits or more, by last term"),
    sprintf("  %-12s %6s %8s %8s", "Term", paste0(m$line, "+"), paste0(m$done_at, "+"), "All"),
    sprintf("  %-12s %6s %8s %8s", vapply(payload$series$exit_term, fmt_term, character(1)),
            .graduation_n(payload$series$n_far), .graduation_n(payload$series$n_done),
            .graduation_n(payload$series$n_left)),
    "", "## By college", group_head, group_lines(payload$colleges),
    "", "## By major", group_head, group_lines(payload$majors),
    if (!is.null(payload$required)) .format_graduation_required(payload)
  )
}
