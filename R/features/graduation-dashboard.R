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
#   graduation_scope_parts()       the part of it the credit line does not change
#   graduation_default_scope(), graduation_page_scope(), graduation_page_opt()
#                                  the page's scope: where it opens, one form of it
#   graduation_headline()          the lead sentence
#   graduation_band_table()        each band with its standing counts
#   graduation_required_table()    each plan's required courses, counted
#   graduation_credit_source_note(), graduation_required_lead(), graduation_plan_note()
#   plot_exit_bands(), plot_exit_series(), plot_exit_required()
#   format_graduation_dashboard()  the text preview

GRADUATION_LINES <- c(90, 115, 120)

# The moments a fall class is read at: regular terms since entering.
GRADUATION_PACE_STEPS <- c("second" = 2L, "third" = 4L, "fourth" = 6L, "fifth" = 8L)
# How many regular terms each class is followed for (six years).
GRADUATION_PACE_TERMS <- 12L
# A class's parts at a step, in drawing order: the cone's column, the label.
# Transfer classes are followed by the credits they brought: lower edges.
GRADUATION_ARRIVAL_BREAKS <- c(30, 60)
GRADUATION_PACE_PARTS <- c(
  n_degree = "Awarded a degree",
  n_four_year = "Enrolled, on pace for four years",
  n_six_year = "Enrolled, on pace for six years",
  n_slower = "Enrolled, slower than that",
  n_credits_unknown = "Enrolled, earlier credits not on record",
  n_gone = "Not enrolled")

#' Each fall's entering classes, year by year: still here, and at what pace
#'
#' The first-time class, and the new transfer students in one table per band
#' of credits brought (`GRADUATION_ARRIVAL_BREAKS`), each followed
#' `GRADUATION_PACE_TERMS` regular terms by get_entering_class_retention()
#' with `DEGREE_PACE_TERM_CREDITS`.
#'
#' @param student_terms,degrees,programs The loaded tables.
#' @param opt `data_edges` (required), `student_level`, `campus`, `min_n`.
#' @return list(`pace` (the first-time classes), `transfer` (named by band)).
build_class_pace <- function(student_terms, degrees, programs, opt = list()) {
  scope <- list(term_type = "fall", student_level = opt$student_level, campus = opt$campus,
                n_terms = GRADUATION_PACE_TERMS, min_n = as.integer(opt$min_n %||% 30L),
                data_edges = opt$data_edges, pace = DEGREE_PACE_TERM_CREDITS)
  pace <- get_entering_class_retention(student_terms, degrees, c(scope, list(entry = "first_time")), programs)
  attr(pace, "started") <- "first_time"
  bands <- exit_credit_band_labels(GRADUATION_ARRIVAL_BREAKS)
  edges <- c(0, GRADUATION_ARRIVAL_BREAKS, Inf)
  transfer <- stats::setNames(lapply(seq_along(bands), function(i) {
    t <- get_entering_class_retention(student_terms, degrees,
                                      c(scope, list(entry = "transfer", arrival_credits = edges[c(i, i + 1L)])), programs)
    attr(t, "started") <- "transfer"
    attr(t, "arrival_band") <- bands[[i]]
    t
  }), bands)
  list(pace = pace, transfer = transfer)
}

#' The scope the Graduation page opens on
#'
#' The controls' starting values. The page's UI and the startup preload both
#' read them here, so what is built ahead is what the page first asks for.
#'
#' @param campuses The home campuses the page offers.
#' @return list(`level`, `campus`, `lines`: every credit line, the opening one
#'   first).
graduation_default_scope <- function(campuses) {
  list(level = names(CEDAR_STUDENT_LEVEL_LABELS)[[1]], campus = intersect(CEDAR_CAMPUS_MAIN, campuses),
       lines = GRADUATION_LINES)
}

#' One scope of the Graduation page, in one form
#'
#' The controls as the browser sends them, or as the preload names them: one
#' level, the home campuses sorted (none means every campus) and the credit
#' line as a number. The same campuses picked in another order are one scope,
#' so they share one result.
#'
#' @param level A student level code.
#' @param campus Home campus codes; NULL or empty for every campus.
#' @param line Credits that count as far along.
#' @return list(`level`, `campus` (character, or NULL for every campus), `line`).
graduation_page_scope <- function(level, campus = NULL, line = GRADUATION_LINES[[1]]) {
  level <- as.character(level)
  line <- suppressWarnings(as.numeric(line))
  if (length(level) != 1L || is.na(level) || !nzchar(level)) {
    stop("[graduation-dashboard.R] The Graduation page takes one student level.", call. = FALSE)
  }
  if (length(line) != 1L || !is.finite(line)) {
    stop("[graduation-dashboard.R] The Graduation page takes one credit line, a number.", call. = FALSE)
  }
  campus <- sort(unique(as.character(campus)))
  list(level = level, campus = if (length(campus) > 0L) campus else NULL, line = line)
}

#' The options the Graduation page builds a scope under
#'
#' @param scope [graduation_page_scope()].
#' @param edges The data edges.
#' @return The `opt` [build_graduation_dashboard()] and
#'   [graduation_scope_parts()] take.
graduation_page_opt <- function(scope, edges) {
  list(student_level = scope$level, campus = scope$campus, line = scope$line, data_edges = edges,
       class_pace = FALSE)
}

# The options the line-independent parts are built under: every option but the
# credit line and what is laid over it.
.graduation_scope_opt <- function(opt) {
  opt[sort(setdiff(names(opt), c("line", "min_list", "class_pace")))]
}

#' The parts of the Graduation payload the credit line does not change
#'
#' Who left and with how many credits ([get_exit_credits()]) and who passed
#' the attempted-credit ceiling ([get_credit_ceiling_crossings()]) depend on
#' the level and the home campuses, not on how many credits count as far
#' along. They are most of the build's time, so the page builds them once for
#' a level and its campuses and builds each credit line over them
#' (`build_graduation_dashboard(parts =)`).
#'
#' @param student_terms,programs,degrees,terms,opt As
#'   [build_graduation_dashboard()] takes them. `opt$line` is not read.
#' @return list(`exit`, `ceiling`, `scope`: the options they were built under).
graduation_scope_parts <- function(student_terms, programs, degrees, terms, opt = list()) {
  list(
    exit = get_exit_credits(student_terms, programs, degrees, terms, opt),
    # Students passing the attempted-credit ceiling with no degree yet.
    ceiling = get_credit_ceiling_crossings(student_terms, programs, degrees, list(
      student_level = opt$student_level, campus = opt$campus, data_edges = opt$data_edges,
      credit_ceiling = opt$credit_ceiling)),
    scope = .graduation_scope_opt(opt))
}

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
#'   10), `min_n`, `class_pace` (FALSE leaves `pace` and `transfer` NULL).
#' @param parts Optional: [graduation_scope_parts()] already built for this
#'   scope, to build another credit line without counting who left again.
#'   Parts built under another scope are refused.
#' @return list(`bands`, `series` (one row per last term: `n_left`, `n_far`,
#'   `n_done`: at 120 or more), `colleges`, `majors` (far-along students by
#'   group: `n`, `n_done`, `n_flagged`, `n_pell`; majors under `min_list`
#'   pooled), `required` (NULL without `attempts` and `boards`), `pace`
#'   (each fall's first-time class at each regular term for six years:
#'   `get_entering_class_retention()` with `DEGREE_PACE_TERM_CREDITS`),
#'   `transfer` (the same table for each fall's new transfer students, one
#'   per band of credits brought, named by band),
#'   `ceiling` (`get_credit_ceiling_crossings()` for the scope), `meta`).
build_graduation_dashboard <- function(student_terms, programs, degrees, terms, dims, opt = list(),
                                       attempts = NULL, boards = NULL, parts = NULL) {
  if (!"primary_college_code" %in% names(student_terms)) {
    stop("[graduation-dashboard.R] student_terms lacks primary_college_code (the loader attaches it).", call. = FALSE)
  }
  if (!"is_pre_major" %in% names(student_terms)) {
    stop("[graduation-dashboard.R] student_terms lacks is_pre_major.", call. = FALSE)
  }
  line <- as.numeric(opt$line %||% GRADUATION_LINES[[1]])
  min_list <- as.integer(opt$min_list %||% 10L)
  if (is.null(parts)) parts <- graduation_scope_parts(student_terms, programs, degrees, terms, opt)
  if (!identical(parts$scope, .graduation_scope_opt(opt))) {
    stop("[graduation-dashboard.R] `parts` were built under another scope than `opt`.", call. = FALSE)
  }
  exit <- parts$exit
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

  # Each fall's entering classes at each year: the Retention page reads them
  # on their own (build_class_pace()), and passes class_pace = FALSE here.
  class_pace <- if (isFALSE(opt$class_pace)) list(pace = NULL, transfer = NULL) else {
    build_class_pace(student_terms, degrees, programs, opt)
  }

  series <- students %>%
    group_by(exit_term) %>%
    summarize(n_left = n(), n_far = sum(credits >= line, na.rm = TRUE),
              n_done = sum(credits >= done_at, na.rm = TRUE), .groups = "drop") %>%
    arrange(exit_term)

  list(
    bands = exit$bands, series = series, colleges = colleges, majors = majors, required = required,
    pace = class_pace$pace, transfer = class_pace$transfer, ceiling = parts$ceiling,
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


#' The entering classes' pace as text
#'
#' @param pace `payload$pace`.
#' @return Character vector, one element per line.
format_graduation_pace <- function(pace) {
  head <- c("", paste0("## Each fall's ", .graduation_pace_words(pace)$who, ": still here, and at what pace"))
  rates <- attr(pace, "pace")
  fast <- if (identical(attr(pace, "started"), "transfer")) {
    c(paste0(rates[["four_year"]], "+"), paste0(rates[["six_year"]], "-", rates[["four_year"]] - 1))
  } else c("4-year", "6-year")
  blocks <- unlist(lapply(unname(GRADUATION_PACE_STEPS), function(step) {
    s <- graduation_pace_shares(pace, step)
    if (nrow(s) == 0L) return(c("", graduation_pace_lead(pace, step)))
    pct <- function(x) sprintf("%.1f%%", x)
    c("", graduation_pace_lead(pace, step),
      sprintf("  %-10s %8s %8s %8s %8s %8s %8s %8s", "Class", "Entered", "Degree", fast[[1]], fast[[2]], "Slower",
              "Unknown", "Gone"),
      sprintf("  %-10s %8s %8s %8s %8s %8s %8s %8s", s$class, fmt_count(s$n_entering), pct(s$degree_pct),
              pct(s$four_year_pct), pct(s$six_year_pct), pct(s$slower_pct), pct(s$credits_unknown_pct),
              pct(s$gone_pct)))
  }))
  middle <- pace[pace$step <= max(GRADUATION_PACE_STEPS) & !is.na(pace$credits_median) & !is.na(pace$here_pct), ]
  credits <- if (nrow(middle) == 0L) "  No class has credits on record." else {
    sprintf("  %-10s %s", vapply(sort(unique(middle$term)), fmt_term, character(1)),
            vapply(sort(unique(middle$term)), function(class) {
              paste(sprintf("%4.0f", middle$credits_median[middle$term == class]), collapse = "")
            }, character(1)))
  }
  c(head, blocks, "", "### Credits earned here by the middle enrolled student, before each regular term since entering",
    credits)
}

.format_graduation_required <- function(payload) {
  r <- payload$required
  t <- graduation_required_table(payload)
  n <- function(x) ifelse(is.na(x), "--", fmt_count(dplyr::coalesce(x, 0L)))
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
           fmt_count(r$meta$n_students_withheld), " students)."),
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
    "Of the ", fmt_count(m$n_left + m$n_with_degree), " students whose last term was between ",
    fmt_term(m$first_exit_term), " and ", fmt_term(m$last_exit_term), ", ",
    fmt_count(m$n_with_degree), if (m$n_with_degree == 1L) " holds" else " hold",
    " a degree and ", fmt_count(m$n_left),
    " left without one. ", fmt_count(m$n_far), " of those who left had ", m$line,
    " credits or more",
    if (m$line < m$done_at) paste0(", ", fmt_count(m$n_done), " of them ", m$done_at, " or more") else "",
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
    x = labels, y = b$n, type = "bar", text = fmt_count(b$n), textposition = "outside", cliponaxis = FALSE,
    marker = list(color = ifelse(far, CEDAR_PALETTE[[2]], CEDAR_SEMANTIC_COLORS[["reference"]])),
    hovertext = paste0(labels, " credits<br>", fmt_count(b$n), " students (",
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
         round(m$median_credits_here), " or fewer of them here. ", fmt_count(m$n_far_mostly_elsewhere), " of ",
         fmt_count(m$n_far_here_known), " earned most of their credits somewhere else, so a course with no ",
         "attempt here may have been met there.")
}

#' The sentence on how many of these students a degree plan covers
#' @param payload A `build_graduation_dashboard()` result holding `required`.
graduation_required_lead <- function(payload) {
  m <- payload$required$meta
  paste0(fmt_count(m$n_with_plan), " of the ", fmt_count(m$n_students),
         " students who left without a degree with ", payload$meta$line, " credits or more were in a program with a degree plan on file; ",
         fmt_count(m$n_without_plan), " were not.")
}

#' One plan's line: its students, and what of the plan is not read
#' @param payload A `build_graduation_dashboard()` result holding `required`.
#' @param catalog_id The plan.
graduation_plan_note <- function(payload, catalog_id) {
  r <- payload$required
  plan <- r$programs[r$programs$catalog_id == catalog_id, ]
  if (nrow(plan) != 1L || !plan$shown) stop("[graduation-dashboard.R] no listed plan ", catalog_id, call. = FALSE)
  unreadable <- sum(!r$courses$readable[r$courses$catalog_id == catalog_id])
  paste0(fmt_count(plan$n_students), " students in this program left without a degree with ",
         payload$meta$line, " credits or more, ", fmt_count(plan$n_pre_major),
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
  hover <- function(count, what) paste0(rows$subject_course, " · ", rows$title, "<br>", fmt_count(count), " ", what)
  bar <- function(fig, count, name, what, colour) {
    plotly::add_trace(fig, y = rows$subject_course, x = count, type = "bar", orientation = "h", name = name,
                      marker = list(color = colour), text = fmt_count(count), textposition = "inside",
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

# The words for a pace table: first-time students are read against the
# four-year and six-year paces to a degree; transfer students, who start
# part-way, by the credits a term they are earning here.
.graduation_pace_words <- function(pace) {
  rates <- attr(pace, "pace")
  if (identical(attr(pace, "started"), "transfer")) {
    band <- attr(pace, "arrival_band")
    brought <- paste0(tolower(substr(band, 1, 1)), substring(band, 2), " credits")
    list(who = paste0("new transfer students who brought ", brought),
         parts = c(n_degree = "Awarded a degree",
                   n_four_year = paste0("Enrolled, earning ", rates[["four_year"]], " or more credits a term here"),
                   n_six_year = paste0("Enrolled, earning ", rates[["six_year"]], " to ", rates[["four_year"]] - 1),
                   n_slower = paste0("Enrolled, earning fewer than ", rates[["six_year"]]),
                   n_credits_unknown = "Enrolled, earlier credits not on record", n_gone = "Not enrolled"),
         fast = paste0("were enrolled and earning ", rates[["four_year"]], " or more credits a term here"),
         year = "year here",
         lines = c(paste(rates[["four_year"]], "credits a term"), paste(rates[["six_year"]], "credits a term")))
  } else {
    list(who = "first-time students", parts = GRADUATION_PACE_PARTS,
         fast = "were enrolled on pace for four years", year = "year",
         lines = c(paste(rates[["four_year"]], "credits a term (four years)"),
                   paste(rates[["six_year"]], "credits a term (six years)")))
  }
}

#' How often two regular terms away was not the end, for the series' caveat
#'
#' @param meta `build_graduation_dashboard()$meta` (with `later_return`).
#' @return One sentence for the method note.
graduation_later_return_note <- function(meta) {
  r <- meta$later_return
  if (is.null(r) || r$n == 0L) {
    return("The newest bars will come down a little: some students away two regular terms enroll again later.")
  }
  paste0("The hatched bars, marked not final, will come down a little, because some students away two regular terms enroll again later. ",
         "Through ", fmt_term(r$through), ", a student was away that long with no degree ", fmt_count(r$n),
         " times, and ", fmt_count(r$n_returned), " of those (", sprintf("%.1f%%", 100 * r$n_returned / r$n),
         ") were followed by a later enrollment. An older bar has already lost those students; a new one has not.")
}

#' Which transfer classes are read by credits brought, and why some are not
#'
#' @param pace One of `build_graduation_dashboard()$transfer`.
#' @return One sentence for the method note.
graduation_transfer_record_note <- function(pace) {
  unknown <- attr(pace, "n_arrival_unknown")
  held <- attr(pace, "arrival_withheld")
  base <- paste0("A transfer student is grouped by the credit from elsewhere on their record. A new student's first ",
                 "record has none, a later one fills it in, and a student who has left gets no later one.")
  if (is.null(unknown) || nrow(unknown) == 0L) return(paste(base, "Every student in these classes has it on record."))
  classes <- paste0(vapply(unknown$term, fmt_term, character(1)), " (", fmt_count(unknown$n), " of ",
                    fmt_count(unknown$n_class), ")", collapse = ", ")
  paste0(base, " Students without it are in no group: ", classes, ".",
         if (length(held) > 0L) paste0(" Where that is more than a few, the students left in the groups are mostly ",
                                       "the ones who stayed, so the class is not shown by group: ",
                                       paste(vapply(held, fmt_term, character(1)), collapse = ", "), ".") else "")
}


#' Each entering class's parts at one moment, as shares of the class
#'
#' @param pace `payload$pace`.
#' @param step Regular terms since entering (one of `GRADUATION_PACE_STEPS`).
#' @return One row per class that can be read at that step (the step is
#'   settled and graded, the class at least `min_n`): `term`, `class`,
#'   `n_entering`, `here_pct`, then each part of `GRADUATION_PACE_PARTS` as a
#'   count and, with `_pct` for `n_`, a share.
graduation_pace_shares <- function(pace, step) {
  parts <- names(GRADUATION_PACE_PARTS)
  rows <- pace[pace$step == step & !is.na(pace$here_pct) & !is.na(pace$n_degree), ]
  shares <- stats::setNames(lapply(parts, function(part) 100 * rows[[part]] / rows$n_entering),
                            sub("^n_", "", paste0(parts, "_pct")))
  tibble::as_tibble(c(list(term = rows$term, class = vapply(rows$term, fmt_term, character(1)),
                           n_entering = rows$n_entering, here_pct = rows$here_pct),
                      as.list(rows[parts]), shares))
}

#' The sentence comparing the earliest and latest class at one moment
#' @param pace `payload$pace`.
#' @param step One of `GRADUATION_PACE_STEPS`.
graduation_pace_lead <- function(pace, step) {
  s <- graduation_pace_shares(pace, step)
  words <- .graduation_pace_words(pace)
  year <- paste(names(GRADUATION_PACE_STEPS)[match(step, GRADUATION_PACE_STEPS)], words$year)
  if (nrow(s) == 0L) return(paste0("No entering class of ", words$who, " can be read at the start of its ", year, " yet."))
  # A class whose enrolled students all lack a whole record says nothing about pace.
  enrolled <- s$n_entering - s$n_gone - s$n_degree
  known <- s[!(enrolled > 0 & s$n_credits_unknown == enrolled), ]
  one <- function(row) paste0(sprintf("%.1f%%", row$here_pct), " of the ", row$class,
                              " class were still enrolled or had a degree, and ",
                              sprintf("%.1f%%", row$four_year_pct), " ", words$fast)
  if (nrow(known) == 0L) return(paste0("At the start of their ", year, ", no class's credits are on record whole."))
  first <- known[1, ]; last <- known[nrow(known), ]
  paste0("At the start of their ", year, ", ", one(first),
         if (nrow(known) > 1L) paste0(". For the ", last$class, " class it was ", sprintf("%.1f%%", last$here_pct),
                                      " and ", sprintf("%.1f%%", last$four_year_pct)) else "", ".")
}

#' Each entering class at one moment: one stacked bar a class
#' @param pace `payload$pace`.
#' @param step One of `GRADUATION_PACE_STEPS`.
plot_class_pace <- function(pace, step) {
  s <- graduation_pace_shares(pace, step)
  if (nrow(s) == 0L) stop("[graduation-dashboard.R] no class can be read at step ", step, call. = FALSE)
  colours <- c(n_degree = CEDAR_SEMANTIC_COLORS[["positive"]], n_four_year = CEDAR_SEMANTIC_COLORS[["neutral"]],
               n_six_year = CEDAR_SEMANTIC_COLORS[["caution"]], n_slower = CEDAR_SEMANTIC_COLORS[["negative"]],
               n_credits_unknown = CEDAR_SEMANTIC_COLORS[["other"]], n_gone = CEDAR_SEMANTIC_COLORS[["reference"]])
  words <- .graduation_pace_words(pace)
  fig <- plotly::plot_ly()
  for (part in names(GRADUATION_PACE_PARTS)) {
    share <- s[[sub("^n_", "", paste0(part, "_pct"))]]
    fig <- plotly::add_trace(
      fig, x = s$class, y = share, type = "bar", name = words$parts[[part]],
      marker = list(color = unname(colours[[part]])),
      text = ifelse(share >= 4, sprintf("%.0f%%", share), ""), textposition = "inside", textangle = 0,
      hovertext = paste0(s$class, " class<br>", words$parts[[part]], ": ", fmt_count(s[[part]]),
                         " of ", fmt_count(s$n_entering), " (", sprintf("%.1f%%", share), ")"),
      hoverinfo = "text")
  }
  fig %>% plotly::layout(
    barmode = "stack",
    xaxis = list(title = paste0("Entering class (", words$who, ")"), type = "category", categoryorder = "array",
                 categoryarray = s$class),
    yaxis = list(title = "Share of the entering class", ticksuffix = "%", range = c(0, 100)),
    legend = list(orientation = "h", y = -0.25, traceorder = "normal"), margin = list(t = 20))
}

#' Credits earned here by the middle enrolled student, term by term, a line a class
#'
#' Read before each term begins, against the four-year and six-year paces.
#' Shown through the start of the fifth year: after it most of a class has
#' its degree and the students left are the slowest.
#' @param pace `payload$pace`.
plot_credit_accumulation <- function(pace) {
  last_step <- max(GRADUATION_PACE_STEPS)
  rows <- pace[pace$step <= last_step & !is.na(pace$credits_median) & !is.na(pace$here_pct), ]
  if (nrow(rows) == 0L) stop("[graduation-dashboard.R] no class has credits on record to draw.", call. = FALSE)
  classes <- sort(unique(rows$term))
  colours <- build_color_map(vapply(classes, fmt_term, character(1)))
  steps <- seq_len(last_step)
  rates <- DEGREE_PACE_TERM_CREDITS
  words <- .graduation_pace_words(pace)
  fig <- plotly::plot_ly() %>%
    plotly::add_trace(x = steps, y = rates[["four_year"]] * steps, type = "scatter", mode = "lines",
                      name = words$lines[[1]],
                      line = list(color = CEDAR_SEMANTIC_COLORS[["reference"]], dash = "dash"), hoverinfo = "name") %>%
    plotly::add_trace(x = steps, y = rates[["six_year"]] * steps, type = "scatter", mode = "lines",
                      name = words$lines[[2]],
                      line = list(color = CEDAR_SEMANTIC_COLORS[["reference"]], dash = "dot"), hoverinfo = "name")
  for (class in classes) {
    r <- rows[rows$term == class, ]
    label <- fmt_term(class)
    fig <- plotly::add_trace(
      fig, x = r$step, y = r$credits_median, type = "scatter", mode = "lines+markers", name = paste(label, "class"),
      line = list(color = unname(colours[[label]])), marker = list(color = unname(colours[[label]])),
      hovertext = paste0(label, " class, after ", r$step, if_else(r$step == 1L, " term", " terms"), "<br>",
                         "The middle enrolled student: ", round(r$credits_median), " credits<br>",
                         "Half are between ", round(r$credits_q1), " and ", round(r$credits_q3)),
      hoverinfo = "text")
  }
  fig %>% plotly::layout(
    xaxis = list(title = "Regular terms completed since entering", dtick = 1),
    yaxis = list(title = "Credits earned here", rangemode = "tozero"),
    legend = list(orientation = "h", y = -0.25), margin = list(t = 20))
}

# The parts of a student's attempted credits at the ceiling: column, label.
GRADUATION_CEILING_PARTS <- c(
  elsewhere = "Brought from elsewhere",
  completed_here = "Completed here",
  not_completed_here = "Attempted here, not completed")
# Fewest students followed to a step for it to be drawn.
GRADUATION_CEILING_MIN_N <- 30L

#' The average student's attempted credits at the ceiling, by where they came from
#'
#' Means, so the parts add to the total.
#' @param ceiling `payload$ceiling`.
#' @return One row per part of `GRADUATION_CEILING_PARTS`: `part`, `label`,
#'   `credits` (the mean), `share_pct`.
graduation_ceiling_parts <- function(ceiling) {
  parts <- names(GRADUATION_CEILING_PARTS)
  means <- vapply(parts, function(part) if (nrow(ceiling$students) == 0L) NA_real_ else mean(ceiling$students[[part]]),
                  numeric(1))
  tibble::tibble(part = parts, label = unname(GRADUATION_CEILING_PARTS), credits = unname(means),
                 share_pct = 100 * unname(means) / sum(means))
}

#' What had happened by each term after passing the ceiling, as shares
#'
#' @param ceiling `payload$ceiling`.
#' @param min_n Fewest students followed to a step for it to be kept.
#' @return One row per step kept: `step`, `when`, `n_observed`, the three
#'   counts and `degree_pct`, `enrolled_pct`, `gone_pct`.
graduation_ceiling_outcomes <- function(ceiling, min_n = GRADUATION_CEILING_MIN_N) {
  ceiling$outcomes %>%
    filter(n_observed >= min_n) %>%
    mutate(when = if_else(step == 0L, "The term they passed it",
                          paste0(step, if_else(step == 1L, " regular term later", " regular terms later"))),
           degree_pct = 100 * n_degree / n_observed, enrolled_pct = 100 * n_enrolled / n_observed,
           gone_pct = 100 * n_gone / n_observed) %>%
    select(step, when, n_observed, n_degree, n_enrolled, n_gone, degree_pct, enrolled_pct, gone_pct)
}

#' The section's lead: how many passed the ceiling, and where the credits came from
#' @param ceiling `payload$ceiling`.
graduation_ceiling_lead <- function(ceiling) {
  m <- ceiling$meta
  if (m$n_passed == 0L) return(paste0("No student in this scope passed ", m$ceiling, " attempted credits where it can be seen."))
  p <- graduation_ceiling_parts(ceiling)
  credits <- function(part) round(p$credits[p$part == part])
  paste0(fmt_count(m$n_passed), " students passed ", m$ceiling, " attempted credits between ",
         fmt_term(min(ceiling$by_term$term)), " and ", fmt_term(max(ceiling$by_term$term)),
         " with no degree yet. On average ", credits("elsewhere"), " of those credits were brought from elsewhere, ",
         credits("completed_here"), " were completed here and ", credits("not_completed_here"),
         " were attempted here and not completed.")
}

#' The sentence on what happened after
#' @param ceiling `payload$ceiling`.
graduation_ceiling_outcome_note <- function(ceiling) {
  o <- graduation_ceiling_outcomes(ceiling)
  if (nrow(o) == 0L) return("Too few of these students can be followed yet to say what happened next.")
  first <- o[1, ]; last <- o[nrow(o), ]
  pct <- function(x) sprintf("%.1f%%", x)
  paste0(pct(first$degree_pct), " were awarded a degree in the term they passed it. ",
         if (last$step > 0L) paste0("Of the ", fmt_count(last$n_observed), " who can be followed ", last$step,
                                    " regular terms on, ", pct(last$degree_pct), " had a degree, ",
                                    pct(last$enrolled_pct), " were still enrolled and ", pct(last$gone_pct),
                                    " were not enrolled.") else "")
}

#' Where the average student's credits came from: one bar in three parts
#' @param ceiling `payload$ceiling`.
plot_ceiling_parts <- function(ceiling) {
  p <- graduation_ceiling_parts(ceiling)
  if (anyNA(p$credits)) stop("[graduation-dashboard.R] no student passed the ceiling.", call. = FALSE)
  colours <- c(elsewhere = CEDAR_SEMANTIC_COLORS[["neutral"]], completed_here = CEDAR_SEMANTIC_COLORS[["positive"]],
               not_completed_here = CEDAR_PALETTE[[2]])
  fig <- plotly::plot_ly(height = 170)
  for (i in seq_len(nrow(p))) {
    fig <- plotly::add_trace(fig, y = "", x = p$credits[i], type = "bar", orientation = "h", name = p$label[i],
                             marker = list(color = unname(colours[[p$part[i]]])),
                             text = round(p$credits[i]), textposition = "inside",
                             insidetextanchor = "middle", textangle = 0,
                             hovertext = paste0(p$label[i], ": ", round(p$credits[i]), " credits on average (",
                                                sprintf("%.1f%%", p$share_pct[i]), ")"), hoverinfo = "text")
  }
  fig %>% plotly::layout(barmode = "stack",
                         legend = list(orientation = "h", y = 1.05, yanchor = "bottom", traceorder = "normal"),
                         xaxis = list(title = paste0("Attempted credits of the average student on passing ", ceiling$meta$ceiling)),
                         yaxis = list(title = ""), margin = list(t = 30, b = 40))
}

#' What had happened by each term after: one stacked bar a step
#' @param ceiling `payload$ceiling`.
plot_ceiling_outcomes <- function(ceiling) {
  o <- graduation_ceiling_outcomes(ceiling)
  if (nrow(o) == 0L) stop("[graduation-dashboard.R] too few students followed to draw.", call. = FALSE)
  bar <- function(fig, share, count, name, colour) {
    plotly::add_trace(fig, x = o$when, y = share, type = "bar", name = name, marker = list(color = colour),
                      text = sprintf("%.0f%%", share), textposition = "inside", textangle = 0,
                      hovertext = paste0(o$when, "<br>", name, ": ", fmt_count(count), " of ",
                                         fmt_count(o$n_observed), " (", sprintf("%.1f%%", share), ")"),
                      hoverinfo = "text")
  }
  plotly::plot_ly() %>%
    bar(o$degree_pct, o$n_degree, "Awarded a degree", CEDAR_SEMANTIC_COLORS[["positive"]]) %>%
    bar(o$enrolled_pct, o$n_enrolled, "Still enrolled, no degree", CEDAR_PALETTE[[2]]) %>%
    bar(o$gone_pct, o$n_gone, "Not enrolled, no degree", CEDAR_SEMANTIC_COLORS[["reference"]]) %>%
    plotly::layout(barmode = "stack",
                   xaxis = list(title = "", type = "category", categoryorder = "array", categoryarray = o$when),
                   yaxis = list(title = "Share of students followed that far", ticksuffix = "%",
                                range = c(0, 100)),
                   legend = list(orientation = "h", y = -0.15, traceorder = "normal"), margin = list(t = 20))
}

#' The ceiling section as text
#' @param ceiling `payload$ceiling`.
#' @return Character vector, one element per line.
format_graduation_ceiling <- function(ceiling) {
  m <- ceiling$meta
  head <- c("", paste0("## Passing ", m$ceiling, " attempted credits with no degree yet"),
            graduation_ceiling_lead(ceiling),
            paste0("Not placed: ", fmt_count(m$n_not_readable), " whose record began before the class lists or whose credit from elsewhere is not on record, ",
                   fmt_count(m$n_already_past), " already past it in their first term on record, ",
                   fmt_count(m$n_prior_degree), " who already held a degree."))
  if (m$n_passed == 0L) return(head)
  o <- graduation_ceiling_outcomes(ceiling, min_n = 1L)
  pct <- function(x) sprintf("%.1f%%", x)
  c(head, "", graduation_ceiling_outcome_note(ceiling),
    sprintf("  %-26s %9s %8s %9s %8s", "When", "Followed", "Degree", "Enrolled", "Gone"),
    sprintf("  %-26s %9s %8s %9s %8s", o$when, fmt_count(o$n_observed), pct(o$degree_pct), pct(o$enrolled_pct),
            pct(o$gone_pct)))
}

#' The last terms whose count is not final yet
#'
#' A last term is final once the terms after it have had time to show a
#' return: the terms `meta$later_return` could read (through its `through`).
#' The ones after it can still lose students who enroll again.
#' @param payload A `build_graduation_dashboard()` result.
#' @return The series' `exit_term`s still open to a return; none when no term has been read.
graduation_open_terms <- function(payload) {
  through <- payload$meta$later_return$through
  if (is.null(through) || is.na(through)) return(integer(0))
  payload$series$exit_term[payload$series$exit_term > through]
}

#' Far-along students who left, by last term
#'
#' The newest last terms (graduation_open_terms()) are drawn hatched and
#' shaded, and labelled: their counts come down as students enroll again.
plot_exit_series <- function(payload) {
  s <- payload$series
  labels <- vapply(s$exit_term, fmt_term, character(1))
  m <- payload$meta
  open <- s$exit_term %in% graduation_open_terms(payload)
  p <- plotly::plot_ly(
    x = labels, y = s$n_far, type = "bar", text = fmt_count(s$n_far), textposition = "outside", cliponaxis = FALSE,
    marker = list(color = CEDAR_PALETTE[[2]], opacity = ifelse(open, 0.55, 1),
                  pattern = list(shape = ifelse(open, "/", ""))),
    name = paste(m$line, "credits or more"),
    hovertext = paste0(labels, "<br>", fmt_count(s$n_far), " left with ", m$line, " credits or more<br>",
                       fmt_count(s$n_done), " with ", m$done_at, " or more<br>",
                       fmt_count(s$n_left), " left in all",
                       ifelse(open, "<br>Not final: some of these students will enroll again", "")),
    hoverinfo = "text", showlegend = FALSE) %>%
    plotly::layout(
      xaxis = list(title = "Last enrolled term", type = "category", categoryorder = "array",
                   categoryarray = labels),
      # Headroom, so a tall bar's count clears the "Not final" label above it.
      yaxis = list(title = paste0("Left with ", m$line, " credits or more"),
                   range = c(0, 1.2 * max(c(s$n_far, 1), na.rm = TRUE))),
      margin = list(t = 40))
  mark_plotly_terms(p, labels[open], text = "Not final")
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
  group_lines <- function(g) sprintf("  %-40s %6s %8s %10s %6s", substr(g$label, 1, 40), fmt_count(g$n),
                                     fmt_count(g$n_done), fmt_count(g$n_flagged), fmt_count(g$n_pell))
  group_head <- sprintf("  %-40s %6s %8s %10s %6s", "", "Left", paste0(m$done_at, "+"), "Standards", "Pell")
  c(
    "# Graduation: students who left without a degree",
    paste0("Enrollment settled through ", fmt_term(m$edge), "; degrees posted through ", fmt_term(m$degree_edge),
           ". ", fmt_count(m$n_not_judged), " last terms are too recent to judge (everyone still enrolled is among them)."),
    "", graduation_headline(payload), "",
    "## By credits when they stopped",
    sprintf("  %-14s %7s %7s %7s %10s %10s %8s", "Credits", "Left", "Share", "Pell", paste0("GPA <", m$gpa_floor),
            paste0(m$credit_ceiling, "+ att."), "Either"),
    sprintf("  %-14s %7s %7s %7s %10s %10s %8s", b$band, fmt_count(b$n), pct(b$share_pct), pct(b$pell_pct),
            pct(b$gpa_below_pct), pct(b$over_ceiling_pct), pct(b$flagged_pct)),
    paste0("  ", fmt_count(m$n_last_term_added), if (m$n_last_term_added == 1L) " total includes" else " totals include",
           " the last term's own credits, added because the record was pulled before the next term began."),
    "",
    paste0("## Left with ", m$line, " credits or more, by last term"),
    sprintf("  %-12s %6s %8s %8s", "Term", paste0(m$line, "+"), paste0(m$done_at, "+"), "All"),
    sprintf("  %-12s %6s %8s %8s", vapply(payload$series$exit_term, fmt_term, character(1)),
            fmt_count(payload$series$n_far), fmt_count(payload$series$n_done),
            fmt_count(payload$series$n_left)),
    "", "## By college", group_head, group_lines(payload$colleges),
    "", "## By major", group_head, group_lines(payload$majors),
    if (!is.null(payload$required)) .format_graduation_required(payload),
    if (!is.null(payload$pace)) format_graduation_pace(payload$pace),
    unlist(lapply(payload$transfer, format_graduation_pace)),
    format_graduation_ceiling(payload$ceiling)
  )
}
