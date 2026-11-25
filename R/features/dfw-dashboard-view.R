# Bird's Eye > DFW Rates: what the page draws and lists, from
# build_dfw_dashboard()'s payload (features/dfw-dashboard.R).
#
# Every count, label and series the page shows is computed here; the module
# (modules/dfw-rates.R) only lays them out. Rates stay unrounded; the plots
# and the module's columns round once, for display.
#
#   calculation   dfw_overall_finding(), dfw_concentration_parts(),
#                 dfw_change_counts(), dfw_spread_finding(),
#                 dfw_spread_direction_parts(), dfw_course_table(),
#                 dfw_swing_table(), dfw_spread_course_table(),
#                 dfw_group_table()
#   plot prep     prepare_dfw_overall_plot_data(), prepare_dfw_course_bars(),
#                 prepare_dfw_slope_plot_data(), prepare_dfw_spread_term_plot_data(),
#                 prepare_dfw_spread_course_bars()
#   plotting      plot_dfw_overall(), plot_dfw_course_bars(), plot_dfw_slopes(),
#                 plot_dfw_spread_terms(), plot_dfw_spread_course_bars()
#
# Depends on: dfw_trend_sentence(), dfw_spread_direction_phrase(),
#             DFW_SPREAD_DIRECTIONS, DFW_NR_NOTE_SHARE (features/dfw-dashboard.R),
#             fmt_term(), term_axis_factor(), CEDAR_PALETTE,
#             CEDAR_SEMANTIC_COLORS (trunk/utils.R)

# What the DFW grades were, in the order they stack: the counts
# summarize_attempt_outcomes() returns (D and C- drawn together).
DFW_GRADE_KIND_LABELS <- c(n_w = "Withdrew (W)", n_f = "F", n_dc = "D or C-",
                           n_other_nonpassing = "Other nonpassing")

DFW_DIRECTION_LABELS <- c(rising = "Rising", falling = "Falling", steady = "Steady",
                          too_few_terms = "Too few terms", none = "No trend")

# The directions a spread between sections can take, in the order drawn
# (get_dfw_section_spread()'s `direction`).
DFW_SPREAD_DIRECTION_CODES <- c("rising", "falling", "steady")

.dfw_view_check <- function(payload) {
  if (!inherits(payload, "dfw_dashboard")) {
    stop("[dfw-dashboard-view.R] payload must come from build_dfw_dashboard().", call. = FALSE)
  }
}

.dfw_view_label <- function(course, campus) paste0(course, " (", campus, ")")
.dfw_view_direction <- function(x) {
  factor(unname(DFW_DIRECTION_LABELS[dplyr::coalesce(x, "none")]), levels = unname(DFW_DIRECTION_LABELS))
}
.dfw_view_direction_colors <- function() {
  stats::setNames(unname(CEDAR_SEMANTIC_COLORS[c("negative", "positive", "reference", "other", "other")]),
                  unname(DFW_DIRECTION_LABELS))
}

# A spread's direction as the page names it: DFW_SPREAD_DIRECTIONS' words,
# opening a cell or a legend entry.
.dfw_view_spread_direction <- function(x) {
  word <- unname(DFW_SPREAD_DIRECTIONS[x])
  paste0(toupper(substr(word, 1, 1)), substring(word, 2))
}

# The courses the page lists: read in enough terms for a direction, widest
# first. A course read in fewer is one or two terms, not an average.
.dfw_view_spread_listed <- function(payload) {
  courses <- payload$sections$spread_courses
  courses[courses$direction != "too_few_terms", , drop = FALSE]
}

# Each course's rates, oldest term first, over the terms its trend reads.
.dfw_view_series <- function(terms, rows) {
  keyed <- split(terms$dfw_pct[terms$in_trend], paste(terms$campus, terms$subject_course)[terms$in_trend])
  unname(lapply(paste(rows$campus, rows$subject_course), function(k) keyed[[k]] %||% numeric()))
}

# ── Calculation ──────────────────────────────────────────────────────────────

#' The latest term's rate and the series' verdict
#'
#' @param payload build_dfw_dashboard() output.
#' @return A list: `term`, `dfw_pct`, `n_dfw`, `n_attempts` (the latest term),
#'   `direction`, `slope`, `sentence` (dfw_trend_sentence()), and `nr_terms`
#'   (the terms whose NR grades are DFW_NR_NOTE_SHARE or more of their
#'   attempts: `term`, `n_nr`, `n_attempts`).
dfw_overall_finding <- function(payload) {
  .dfw_view_check(payload)
  s <- payload$overall
  terms <- s$terms[order(s$terms$term), , drop = FALSE]
  last <- terms[nrow(terms), , drop = FALSE]
  tr <- s$trend[1, , drop = FALSE]
  list(term = last$term, dfw_pct = last$dfw_pct, n_dfw = last$n_dfw, n_attempts = last$n_attempts,
       direction = tr$direction, slope = tr$slope,
       sentence = dfw_trend_sentence(tr, s$meta$min_trend_terms),
       nr_terms = terms[terms$n_nr / terms$n_attempts >= DFW_NR_NOTE_SHARE, c("term", "n_nr", "n_attempts")])
}

#' The window's DFW grades split by how few courses hold them
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row per part (`quarter`, `half`, `rest`): `part`, `n` (DFW
#'   grades), `n_courses`, `label`, `detail`. No rows when the window holds no
#'   DFW grade.
dfw_concentration_parts <- function(payload) {
  .dfw_view_check(payload)
  tot <- payload$courses$totals
  cc <- payload$courses$courses
  if (tot$n_dfw == 0L) return(data.frame(part = character(), n = integer(), n_courses = integer(),
                                         label = character(), detail = character()))
  q <- tot$courses_for_quarter
  h <- tot$courses_for_half
  n <- c(sum(cc$n_dfw[seq_len(q)]), sum(cc$n_dfw[seq_len(h)]) - sum(cc$n_dfw[seq_len(q)]))
  n <- c(n, tot$n_dfw - sum(n))
  k <- c(q, h - q, tot$n_courses - h)
  data.frame(
    part = c("quarter", "half", "rest"), n = as.integer(n), n_courses = as.integer(k),
    label = c(paste0("in the ", fmt_count(k[1]), " courses with the most"),
              paste0("in the next ", fmt_count(k[2])),
              paste0("in the other ", fmt_count(k[3]))),
    detail = sprintf("%.1f%% of the DFW grades", 100 * n / tot$n_dfw),
    stringsAsFactors = FALSE
  )
}

#' How many listed courses are rising, falling and swinging
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row each for `rising`, `falling`, `swings`: `what`, `n`, and
#'   `n_listed` (listed courses), `n_with_trend` (of them, with a trend).
dfw_change_counts <- function(payload) {
  .dfw_view_check(payload)
  l <- payload$courses$courses[payload$courses$courses$listed, , drop = FALSE]
  data.frame(what = c("rising", "falling", "swings"),
             n = c(sum(l$direction %in% "rising"), sum(l$direction %in% "falling"), sum(l$swings)),
             n_listed = nrow(l),
             n_with_trend = sum(l$direction %in% c("rising", "falling", "steady")),
             stringsAsFactors = FALSE)
}

#' How far apart sections are, over every course and term in scope
#'
#' @param payload build_dfw_dashboard() output.
#' @return A list: `n_courses` and `n_course_terms` read (0 when no course in
#'   scope has enough sections to compare, and the rest NA), `first_term`,
#'   `last_term`, `spread_pts` (points, beyond chance), `lo_pct`, `hi_pct`
#'   (the lowest and highest section, averaged over the course-terms), and
#'   `direction_phrase` (dfw_spread_direction_phrase() of the term-by-term
#'   series).
dfw_spread_finding <- function(payload) {
  .dfw_view_check(payload)
  s <- payload$sections
  avg <- s$overall$average
  if (nrow(avg) == 0L) {
    return(list(n_courses = 0L, n_course_terms = 0L, first_term = NA_integer_, last_term = NA_integer_,
                spread_pts = NA_real_, lo_pct = NA_real_, hi_pct = NA_real_, direction_phrase = NA_character_))
  }
  list(n_courses = avg$n_courses, n_course_terms = avg$n_course_terms,
       first_term = min(s$overall$terms$term), last_term = max(s$overall$terms$term),
       spread_pts = avg$spread_pts, lo_pct = avg$lo_pct, hi_pct = avg$hi_pct,
       direction_phrase = dfw_spread_direction_phrase(s$overall$trend))
}

#' The listed courses split by where their sections are heading
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row each for `rising` (spreading), `falling` (consolidating)
#'   and `steady` (no clear change): `part`, `n` (courses), `label`;
#'   attributes `n_short` (courses read in too few terms for a direction, not
#'   listed) and `min_trend_terms`.
dfw_spread_direction_parts <- function(payload) {
  .dfw_view_check(payload)
  s <- payload$sections
  out <- data.frame(part = DFW_SPREAD_DIRECTION_CODES,
                    n = vapply(DFW_SPREAD_DIRECTION_CODES, function(d) sum(s$spread_courses$direction == d), integer(1)),
                    label = unname(DFW_SPREAD_DIRECTIONS[DFW_SPREAD_DIRECTION_CODES]),
                    row.names = NULL, stringsAsFactors = FALSE)
  attr(out, "n_short") <- sum(s$spread_courses$direction == "too_few_terms")
  attr(out, "min_trend_terms") <- s$meta$min_trend_terms
  out
}

#' The listed courses, most DFW grades first
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row per listed campus-course: `rank`, `subject_course`,
#'   `campus`, `college_name`, `n_attempts`, `n_dfw`, `dfw_pct`, `share_pct`,
#'   `cum_pct` (0-100), `direction`, `slope`, `swings`, and `series` (a list:
#'   the rates its trend reads, oldest first).
dfw_course_table <- function(payload) {
  .dfw_view_check(payload)
  b <- payload$courses
  rows <- b$courses[b$courses$listed, , drop = FALSE]
  tibble::tibble(rank = rows$rank, subject_course = rows$subject_course, campus = rows$campus,
                 college_name = rows$college_name, n_attempts = rows$n_attempts, n_dfw = rows$n_dfw,
                 dfw_pct = rows$dfw_pct, share_pct = 100 * rows$dfw_share, cum_pct = 100 * rows$cum_share,
                 direction = rows$direction, slope = rows$slope, swings = rows$swings,
                 series = .dfw_view_series(b$terms, rows))
}

#' The listed courses that swing more than courses usually do
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row per swinging listed course: `subject_course`, `campus`,
#'   `college_name`, `n_dfw` (the window), `pooled_pct` (every term of its
#'   trend), `resid_sd` (points a term around its line), `n_terms`, `series`.
dfw_swing_table <- function(payload) {
  .dfw_view_check(payload)
  b <- payload$courses
  rows <- b$courses[b$courses$listed & b$courses$swings, , drop = FALSE]
  tibble::tibble(subject_course = rows$subject_course, campus = rows$campus,
                 college_name = rows$college_name, n_dfw = rows$n_dfw, pooled_pct = rows$pooled_pct,
                 resid_sd = rows$resid_sd, n_terms = rows$n_terms,
                 series = .dfw_view_series(b$terms, rows))
}

#' The listed courses' sections, furthest apart first
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row per campus-course read in enough terms for a direction:
#'   `subject_course`, `campus`, `spread_pts` (points, beyond chance, its
#'   terms pooled), `lo_pct`, `hi_pct` (its lowest and highest section,
#'   averaged over its terms), `direction` (as the page names it), `dfw_pct`
#'   (over the terms read), `terms_read`, `sections_per_term`, `n_attempts`,
#'   and `series` (a list: its spread each term, oldest first).
dfw_spread_course_table <- function(payload) {
  .dfw_view_check(payload)
  rows <- .dfw_view_spread_listed(payload)
  terms <- payload$sections$spread_terms
  keyed <- split(terms$spread_pts, paste(terms$campus, terms$subject_course))
  tibble::tibble(subject_course = rows$subject_course, campus = rows$campus, spread_pts = rows$spread_pts,
                 lo_pct = rows$lo_pct, hi_pct = rows$hi_pct,
                 direction = .dfw_view_spread_direction(rows$direction), dfw_pct = rows$dfw_pct,
                 terms_read = rows$terms_read, sections_per_term = rows$sections_per_term,
                 n_attempts = rows$n_attempts,
                 series = unname(keyed[paste(rows$campus, rows$subject_course)]))
}

#' One row per group of a term series: where it started, ended and is heading
#'
#' @param series get_dfw_term_series() output (with `label_col` on its terms).
#' @param label_col The column that names a group.
#' @return One row per group with a term, largest last term first: the group
#'   columns, `label`, `last_n` (attempts its last term), `first_term`,
#'   `first_pct`, `last_term`, `last_pct`, `slope`, `direction` (NA without a
#'   trend), `series` (the rates its trend reads, oldest first).
dfw_group_table <- function(series, label_col) {
  g <- series$meta$group_cols
  terms <- series$terms %>% dplyr::arrange(dplyr::across(dplyr::all_of(g)), term)
  groups <- terms %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(g, label_col)))) %>%
    dplyr::summarize(last_n = dplyr::last(n_attempts),
                     series = list(dfw_pct[in_trend]), .groups = "drop") %>%
    dplyr::left_join(dplyr::select(series$trend, dplyr::all_of(g), first_term, first_pct, last_term, last_pct,
                                   slope, direction), by = g) %>%
    dplyr::arrange(dplyr::desc(last_n))
  groups$label <- groups[[label_col]]
  dplyr::relocate(groups, label, .after = dplyr::all_of(label_col))
}

# ── Plot prep ────────────────────────────────────────────────────────────────

#' Each term's DFW rate, split by what the DFW grades were
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row per term and kind (DFW_GRADE_KIND_LABELS order): `term`,
#'   `term_label`, `kind`, `n` (grades of that kind), `n_attempts`, `pts` (its
#'   points of the rate), `dfw_pct`, `n_dfw`. A term's `pts` sum to its rate.
prepare_dfw_overall_plot_data <- function(payload) {
  .dfw_view_check(payload)
  d <- payload$overall$terms
  d$n_dc <- d$n_d + d$n_c_minus
  long <- dplyr::bind_rows(lapply(names(DFW_GRADE_KIND_LABELS), function(k) {
    tibble::tibble(term = d$term, kind = DFW_GRADE_KIND_LABELS[[k]], n = d[[k]], n_attempts = d$n_attempts,
                   pts = 100 * d[[k]] / d$n_attempts, dfw_pct = d$dfw_pct, n_dfw = d$n_dfw)
  }))
  long$kind <- factor(long$kind, levels = unname(DFW_GRADE_KIND_LABELS))
  long$term_label <- term_axis_factor(long$term)
  dplyr::arrange(long, term, kind)
}

#' The courses with the most DFW grades, for a bar each
#'
#' @param payload build_dfw_dashboard() output.
#' @param n How many listed courses.
#' @return One row per course, most DFW grades first: `label`, `n_dfw`,
#'   `n_attempts`, `dfw_pct`, `share_pct`, `direction` (a factor of
#'   DFW_DIRECTION_LABELS), `swings`.
prepare_dfw_course_bars <- function(payload, n = 15L) {
  .dfw_view_check(payload)
  rows <- utils::head(payload$courses$courses[payload$courses$courses$listed, , drop = FALSE], n)
  tibble::tibble(label = .dfw_view_label(rows$subject_course, rows$campus), n_dfw = rows$n_dfw,
                 n_attempts = rows$n_attempts, dfw_pct = rows$dfw_pct, share_pct = 100 * rows$dfw_share,
                 direction = .dfw_view_direction(rows$direction), swings = rows$swings)
}

#' The rising and falling listed courses with the most DFW grades
#'
#' @param payload build_dfw_dashboard() output.
#' @param n How many of each direction.
#' @return One row per course, steepest rise first: `label`, `slope` (points
#'   a year), `direction`, `first_term`, `first_pct`, `last_term`,
#'   `last_pct`, `n_dfw`.
prepare_dfw_slope_plot_data <- function(payload, n = 10L) {
  .dfw_view_check(payload)
  l <- payload$courses$courses[payload$courses$courses$listed, , drop = FALSE]
  rows <- dplyr::bind_rows(utils::head(l[l$direction %in% "rising", , drop = FALSE], n),
                           utils::head(l[l$direction %in% "falling", , drop = FALSE], n))
  tibble::tibble(label = .dfw_view_label(rows$subject_course, rows$campus), slope = rows$slope,
                 direction = .dfw_view_direction(rows$direction), first_term = rows$first_term,
                 first_pct = rows$first_pct, last_term = rows$last_term, last_pct = rows$last_pct,
                 n_dfw = rows$n_dfw) %>%
    dplyr::arrange(dplyr::desc(slope))
}

#' How far apart sections were each term, every course pooled
#'
#' @param payload build_dfw_dashboard() output.
#' @return One row per term with a spread to read: `term`, `term_label`,
#'   `spread_pts` (points, beyond chance), `n_courses`.
prepare_dfw_spread_term_plot_data <- function(payload) {
  .dfw_view_check(payload)
  terms <- payload$sections$overall$terms
  tibble::tibble(term = terms$term, term_label = term_axis_factor(terms$term),
                 spread_pts = terms$spread_pts, n_courses = terms$n_courses)
}

#' The listed courses whose sections are furthest apart, for a bar each
#'
#' @param payload build_dfw_dashboard() output.
#' @param n How many courses.
#' @return One row per course, furthest apart first: `label`, `spread_pts`,
#'   `lo_pct`, `hi_pct`, `dfw_pct`, `terms_read`, `direction` (a factor, in
#'   DFW_SPREAD_DIRECTION_CODES' order, as the page names each).
prepare_dfw_spread_course_bars <- function(payload, n = 15L) {
  .dfw_view_check(payload)
  rows <- utils::head(.dfw_view_spread_listed(payload), n)
  tibble::tibble(label = .dfw_view_label(rows$subject_course, rows$campus), spread_pts = rows$spread_pts,
                 lo_pct = rows$lo_pct, hi_pct = rows$hi_pct, dfw_pct = rows$dfw_pct, terms_read = rows$terms_read,
                 direction = factor(.dfw_view_spread_direction(rows$direction),
                                    levels = .dfw_view_spread_direction(DFW_SPREAD_DIRECTION_CODES)))
}

# ── Plotting ─────────────────────────────────────────────────────────────────

.dfw_plot_legend <- list(orientation = "h", x = 0, y = -0.12)

#' Each term's DFW rate as a stacked bar of what the grades were
#'
#' @param plot_data prepare_dfw_overall_plot_data() output.
plot_dfw_overall <- function(plot_data) {
  kinds <- levels(plot_data$kind)
  colors <- stats::setNames(CEDAR_PALETTE[2:5], kinds)
  p <- plotly::plot_ly()
  for (k in kinds) {
    rows <- plot_data[plot_data$kind == k, , drop = FALSE]
    p <- plotly::add_trace(
      p, x = as.character(rows$term_label), y = rows$pts, type = "bar", name = k,
      marker = list(color = colors[[k]], line = list(color = "#FFFFFF", width = 1)),
      hovertext = paste0(rows$term_label, "<br>", k, ": ", fmt_count(rows$n), " of ",
                         fmt_count(rows$n_attempts), " attempts (", sprintf("%.1f", rows$pts), " points)"),
      hoverinfo = "text"
    )
  }
  totals <- dplyr::distinct(plot_data, term_label, dfw_pct, n_dfw, n_attempts)
  plotly::layout(
    p, barmode = "stack",
    xaxis = list(title = "", type = "category", categoryorder = "array",
                 categoryarray = as.character(levels(droplevels(plot_data$term_label)))),
    yaxis = list(title = "DFW rate", ticksuffix = "%", rangemode = "tozero"),
    legend = .dfw_plot_legend,
    annotations = lapply(seq_len(nrow(totals)), function(i) list(
      x = as.character(totals$term_label[[i]]), y = totals$dfw_pct[[i]], yshift = 10, showarrow = FALSE,
      text = sprintf("%.1f%%", totals$dfw_pct[[i]]), font = list(size = 12)))
  )
}

#' The courses with the most DFW grades, a bar each, coloured by trend
#'
#' @param bars prepare_dfw_course_bars() output.
plot_dfw_course_bars <- function(bars) {
  colors <- .dfw_view_direction_colors()
  order <- rev(bars$label)
  p <- plotly::plot_ly()
  for (d in intersect(levels(bars$direction), as.character(bars$direction))) {
    rows <- bars[bars$direction == d, , drop = FALSE]
    p <- plotly::add_trace(
      p, x = rows$n_dfw, y = rows$label, type = "bar", orientation = "h", name = d,
      marker = list(color = colors[[d]]),
      hovertext = paste0(rows$label, "<br>", fmt_count(rows$n_dfw), " DFW of ", fmt_count(rows$n_attempts),
                         " attempts (", sprintf("%.1f%%", rows$dfw_pct), ")<br>",
                         sprintf("%.1f%%", rows$share_pct), " of all DFW grades<br>Trend: ", d,
                         ifelse(rows$swings, ", swings", "")),
      hoverinfo = "text"
    )
  }
  plotly::layout(p, barmode = "overlay",
                 xaxis = list(title = "DFW grades", separatethousands = TRUE),
                 yaxis = list(title = "", categoryorder = "array", categoryarray = order),
                 legend = .dfw_plot_legend, margin = list(l = 140))
}

#' Rising and falling courses by how fast, in points a year
#'
#' @param slopes prepare_dfw_slope_plot_data() output.
plot_dfw_slopes <- function(slopes) {
  colors <- .dfw_view_direction_colors()
  p <- plotly::plot_ly()
  for (d in intersect(levels(slopes$direction), as.character(slopes$direction))) {
    rows <- slopes[slopes$direction == d, , drop = FALSE]
    p <- plotly::add_trace(
      p, x = rows$slope, y = rows$label, type = "bar", orientation = "h", name = d,
      marker = list(color = colors[[d]]),
      hovertext = paste0(rows$label, "<br>", sprintf("%.1f%%", rows$first_pct), " (",
                         vapply(rows$first_term, fmt_term, character(1)), ") to ",
                         sprintf("%.1f%%", rows$last_pct), " (", vapply(rows$last_term, fmt_term, character(1)),
                         ")<br>", sprintf("%+.1f", rows$slope), " percentage points a year along its trend"),
      hoverinfo = "text"
    )
  }
  plotly::layout(p, barmode = "overlay",
                 xaxis = list(title = "Change in DFW rate per year (percentage points)", zeroline = TRUE),
                 yaxis = list(title = "", categoryorder = "array", categoryarray = rev(slopes$label)),
                 legend = .dfw_plot_legend, margin = list(l = 140))
}

#' How far apart sections were, term by term
#'
#' @param plot_data prepare_dfw_spread_term_plot_data() output.
plot_dfw_spread_terms <- function(plot_data) {
  labels <- as.character(plot_data$term_label)
  p <- plotly::plot_ly()
  p <- plotly::add_trace(
    p, x = labels, y = plot_data$spread_pts, type = "scatter", mode = "lines+markers", name = "Every course",
    line = list(color = unname(CEDAR_SEMANTIC_COLORS["neutral"]), width = 2),
    marker = list(color = unname(CEDAR_SEMANTIC_COLORS["neutral"]), size = 8),
    hovertext = paste0(labels, "<br>", sprintf("%.1f", plot_data$spread_pts),
                       " points between a section's DFW rate and its course's, beyond chance<br>",
                       fmt_count(plot_data$n_courses), " courses read"),
    hoverinfo = "text"
  )
  plotly::layout(p, showlegend = FALSE,
                 xaxis = list(title = "", type = "category", categoryorder = "array", categoryarray = labels),
                 yaxis = list(title = "Points apart, beyond chance", rangemode = "tozero"))
}

#' The courses whose sections are furthest apart, a bar each, coloured by direction
#'
#' @param bars prepare_dfw_spread_course_bars() output.
plot_dfw_spread_course_bars <- function(bars) {
  colors <- stats::setNames(unname(CEDAR_SEMANTIC_COLORS[c("warning", "positive", "reference")]),
                            levels(bars$direction))
  p <- plotly::plot_ly()
  for (d in intersect(levels(bars$direction), as.character(bars$direction))) {
    rows <- bars[bars$direction == d, , drop = FALSE]
    p <- plotly::add_trace(
      p, x = rows$spread_pts, y = rows$label, type = "bar", orientation = "h", name = d,
      marker = list(color = colors[[d]]),
      hovertext = paste0(rows$label, "<br>", sprintf("%.1f", rows$spread_pts), " points apart, beyond chance, over ",
                         rows$terms_read, " terms<br>Lowest section ", sprintf("%.1f%%", rows$lo_pct), ", highest ",
                         sprintf("%.1f%%", rows$hi_pct), " on average; the course ", sprintf("%.1f%%", rows$dfw_pct),
                         "<br>Direction: ", d),
      hoverinfo = "text"
    )
  }
  plotly::layout(p, barmode = "overlay",
                 xaxis = list(title = "Points between a section's DFW rate and its course's, beyond chance"),
                 yaxis = list(title = "", categoryorder = "array", categoryarray = rev(bars$label)),
                 legend = .dfw_plot_legend, margin = list(l = 140))
}
