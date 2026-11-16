# Bird's Eye > DFW: how is UNM doing on DFW rates, and where is action needed?
#
# One payload for the page, assembled from three cones over cedar_attempts,
# lower-division courses by default, one term type at a time:
#   overall, by_campus, by_college   get_dfw_term_series()   the rate term by
#                                    term and its trend
#   courses                          get_dfw_course_board()  which courses hold
#                                    the DFW grades, and how each is moving
#   sections                         get_dfw_section_spread() whether a
#                                    course's sections agree
# format_dfw_dashboard() is the one text rendering of it (text-first preview).
# The payload is typed and unrounded; a page rounds once, in its display.
#
# Exported functions:
#   build_dfw_dashboard(attempts, dims, opt)
#   format_dfw_dashboard(payload, n_list)
#   dfw_trend_sentence(trend_row, min_terms)
#
# Depends on: get_dfw_term_series() (cones/dfw-term-series.R)
#             get_dfw_course_board() (cones/dfw-course-board.R)
#             get_dfw_section_spread() (cones/dfw-section-spread.R)
#             college_code_names() (branches/dims.R), fmt_term() (trunk/utils.R)

DFW_COLLEGE_UNDECIDED <- "College not decided"

# A term whose NR grades are at least this share of its attempts is named.
DFW_NR_NOTE_SHARE <- 0.01

.dfw_dash_college_names <- function(codes, dims) {
  names <- college_code_names(dims)[codes]
  unname(dplyr::coalesce(names, ifelse(is.na(codes), DFW_COLLEGE_UNDECIDED, codes)))
}

#' The DFW dashboard payload
#'
#' @param attempts The attempt measure table (`cedar_attempts`).
#' @param dims The dimension tables (`cedar_dims`), for college names.
#' @param opt `term_type` (required), `level` (default "lower"), `campus`
#'   (NULL for every campus), `data_edges`, and the cones' thresholds
#'   (`n_window`, `min_window_n`, `min_term_n`, `min_trend_terms`,
#'   `min_section_n`, `min_sections`, `alpha`).
#' @return A list of class `dfw_dashboard`: `overall`, `by_campus`,
#'   `by_college` (get_dfw_term_series() output; `by_college` carries
#'   `college_name`), `courses` (get_dfw_course_board(), with
#'   `college_name`), `sections` (get_dfw_section_spread()), `meta`.
build_dfw_dashboard <- function(attempts, dims, opt = list()) {
  opt$level <- opt$level %||% "lower"
  overall <- get_dfw_term_series(attempts, opt)
  by_campus <- get_dfw_term_series(attempts, opt, "campus")
  by_college <- get_dfw_term_series(attempts, opt, "college")
  by_college$terms$college_name <- .dfw_dash_college_names(by_college$terms$college, dims)
  by_college$trend$college_name <- .dfw_dash_college_names(by_college$trend$college, dims)
  courses <- get_dfw_course_board(attempts, opt)
  courses$courses$college_name <- .dfw_dash_college_names(courses$courses$college, dims)
  sections <- get_dfw_section_spread(attempts, opt)
  structure(list(
    overall = overall, by_campus = by_campus, by_college = by_college,
    courses = courses, sections = sections,
    meta = list(term_type = opt$term_type, level = opt$level, campus = opt$campus,
                graded_edge = overall$meta$graded_edge, window_terms = courses$meta$window_terms)
  ), class = "dfw_dashboard")
}

# ── Text preview ──────────────────────────────────────────────────────────────

.dfw_dash_n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
.dfw_dash_pct <- function(x) ifelse(is.na(x), "—", sprintf("%.1f%%", x))
.dfw_dash_terms <- function(terms) paste(vapply(terms, fmt_term, character(1)), collapse = ", ")
.dfw_dash_direction <- c(rising = "rising (worse)", falling = "falling (better)", steady = "steady",
                         too_few_terms = "too few terms for a trend")

# A group's trend line in one sentence: its first and last rate, the slope a
# year, and what chance and the terms' scatter give. Shared with the page.
dfw_trend_sentence <- function(t, min_terms) {
  if (t$direction == "too_few_terms") {
    return(paste0("A trend is read from ", min_terms, " or more terms; ", t$n_terms, " have enough attempts."))
  }
  paste0(.dfw_dash_pct(t$first_pct), " for ", fmt_term(t$first_term), ", ", .dfw_dash_pct(t$last_pct), " for ",
         fmt_term(t$last_term), ". Across the ", t$n_terms, " terms the fitted line moves ",
         sprintf("%+.1f", t$slope), " points a year, where chance and the terms' own scatter give about ",
         sprintf("%.1f", 2 * t$slope_se), ": ", .dfw_dash_direction[[t$direction]], ".")
}

.dfw_dash_overall <- function(p) {
  s <- p$overall
  terms <- s$terms
  lines <- sprintf("  %-12s %6s  %s of %s DFW  (W %s, F %s, D or C- %s, other %s)",
                   vapply(terms$term, fmt_term, character(1)), .dfw_dash_pct(terms$dfw_pct),
                   .dfw_dash_n(terms$n_dfw), .dfw_dash_n(terms$n_attempts), .dfw_dash_n(terms$n_w),
                   .dfw_dash_n(terms$n_f), .dfw_dash_n(terms$n_d + terms$n_c_minus),
                   .dfw_dash_n(terms$n_other_nonpassing))
  nr <- terms[terms$n_nr / terms$n_attempts >= DFW_NR_NOTE_SHARE, , drop = FALSE]
  c("1. How UNM is doing", lines,
    paste0("  Trend: ", dfw_trend_sentence(s$trend[1, ], s$meta$min_trend_terms)),
    if (nrow(nr)) paste0("  Not reported: ", fmt_term(nr$term), " holds ", .dfw_dash_n(nr$n_nr),
                         " NR grades (", .dfw_dash_pct(100 * nr$n_nr / nr$n_attempts),
                         " of its attempts), each counted as DFW."))
}

.dfw_dash_course_label <- function(d) paste0(d$subject_course, " (", d$campus, ")")

.dfw_dash_courses <- function(p, n_list) {
  b <- p$courses
  tot <- b$totals
  listed <- utils::head(b$courses[b$courses$listed, , drop = FALSE], n_list)
  rows <- sprintf("  %3d  %-18s %-30s %7s %6s %6s %6s %6s  %s%s",
                  listed$rank, .dfw_dash_course_label(listed), substr(listed$college_name, 1, 30),
                  .dfw_dash_n(listed$n_attempts), .dfw_dash_n(listed$n_dfw), .dfw_dash_pct(listed$dfw_pct),
                  .dfw_dash_pct(100 * listed$dfw_share), .dfw_dash_pct(100 * listed$cum_share),
                  dplyr::coalesce(unname(.dfw_dash_direction[listed$direction]), "no trend"),
                  ifelse(listed$swings, ", swings", ""))
  c(paste0("2. Where the DFW grades are (", .dfw_dash_terms(b$meta$window_terms), ")"),
    paste0("  ", .dfw_dash_n(tot$n_dfw), " DFW grades in ", .dfw_dash_n(tot$n_attempts), " attempts (",
           .dfw_dash_pct(tot$dfw_pct), ") over ", .dfw_dash_n(tot$n_courses), " campus-courses. The top ",
           tot$courses_for_quarter, " hold a quarter of them; the top ", tot$courses_for_half, " hold half."),
    sprintf("  %3s  %-18s %-30s %7s %6s %6s %6s %6s  %s", "#", "course", "college", "tries", "DFW",
            "rate", "share", "cum", "trend"),
    rows)
}

.dfw_dash_changing <- function(p, n_list) {
  b <- p$courses
  c_listed <- b$courses[b$courses$listed, , drop = FALSE]
  one <- function(dir, title) {
    d <- utils::head(c_listed[c_listed$direction %in% dir, , drop = FALSE], n_list)
    n_all <- sum(c_listed$direction %in% dir)
    c(paste0("  ", title, ": ", n_all, " listed course", if (n_all == 1L) "" else "s",
             if (nrow(d)) ", most DFW grades first:" else "."),
      if (nrow(d)) sprintf("    %-18s %6s -> %6s (%s to %s), %+.1f points a year",
                           .dfw_dash_course_label(d), .dfw_dash_pct(d$first_pct), .dfw_dash_pct(d$last_pct),
                           vapply(d$first_term, fmt_term, character(1)),
                           vapply(d$last_term, fmt_term, character(1)), d$slope))
  }
  sw <- utils::head(c_listed[c_listed$swings, , drop = FALSE], n_list)
  c(paste0("3. What is changing (every ", p$meta$term_type, " term with ", b$meta$min_term_n,
           " or more attempts; the courses listed in 2)"),
    one("rising", "Rising"), one("falling", "Falling"),
    paste0("  Swinging more than courses usually do (a typical course moves ",
           sprintf("%.1f", b$meta$typical_extra_sd), " points a term beyond chance; ",
           .dfw_dash_n(b$meta$n_swing_tests), " courses tested at once): ", sum(c_listed$swings),
           if (nrow(sw)) ", most DFW grades first:" else "."),
    if (nrow(sw)) sprintf("    %-18s %4.1f points a term around its line", .dfw_dash_course_label(sw), sw$resid_sd))
}

.dfw_dash_sections <- function(p, n_list) {
  s <- p$sections
  ct <- s$course_terms
  repeat_uneven <- utils::head(s$courses[s$courses$terms_uneven >= 2L, , drop = FALSE], n_list)
  detail <- vapply(seq_len(nrow(repeat_uneven)), function(i) {
    r <- repeat_uneven[i, ]
    u <- ct[ct$campus == r$campus & ct$subject_course == r$subject_course & ct$uneven, , drop = FALSE]
    paste0("    ", sprintf("%-18s", .dfw_dash_course_label(r)), " uneven in ", r$terms_uneven, " of ",
           r$terms_tested, " terms: ",
           paste0(vapply(u$term, fmt_term, character(1)), " ", sprintf("%.0f-%.0f%%", u$lo_pct, u$hi_pct),
                  " across ", u$n_sections, collapse = "; "))
  }, character(1))
  c(paste0("4. Sections that disagree (", .dfw_dash_terms(s$meta$window_terms), ")"),
    paste0("  ", .dfw_dash_n(nrow(ct)), " course-terms had ", s$meta$min_sections, " or more sections of ",
           s$meta$min_section_n, "+ attempts; in ", .dfw_dash_n(sum(ct$uneven)),
           " the sections' rates differed more than chance allows."),
    paste0("  Uneven in two or more terms: ", sum(s$courses$terms_uneven >= 2L), " course",
           if (sum(s$courses$terms_uneven >= 2L) == 1L) "" else "s", if (length(detail)) ":" else "."),
    detail)
}

.dfw_dash_groups <- function(series, label_col, title) {
  # Every group with a term, largest last term first (dfw_group_table(), the
  # page's table too); a group with too few terms of enough attempts has no
  # line and says so.
  groups <- dfw_group_table(series, label_col)
  c(title,
    sprintf("  %-36s %6s -> %6s  %s", substr(groups$label, 1, 36), .dfw_dash_pct(groups$first_pct),
            .dfw_dash_pct(groups$last_pct),
            ifelse(is.na(groups$direction), paste0("fewer than ", series$meta$min_trend_terms, " terms of ",
                                                   series$meta$min_term_n, "+ attempts"),
                   unname(.dfw_dash_direction[groups$direction]))))
}

#' The DFW dashboard as text
#'
#' @param payload build_dfw_dashboard() output.
#' @param n_list How many courses each list shows.
#' @return One character string.
format_dfw_dashboard <- function(payload, n_list = 15L) {
  if (!inherits(payload, "dfw_dashboard")) {
    stop("[dfw-dashboard.R] payload must come from build_dfw_dashboard().", call. = FALSE)
  }
  m <- payload$meta
  head <- paste0("DFW: ", m$level, "-division courses, ", m$term_type, " terms, ",
                 if (is.null(m$campus)) "every campus" else paste(m$campus, collapse = ", "),
                 ", graded through ", fmt_term(m$graded_edge),
                 ". DFW is every grade but A+ to C and CR, plus late withdrawals; early drops are left out.")
  paste(c(head, "",
          .dfw_dash_overall(payload), "",
          .dfw_dash_courses(payload, n_list), "",
          .dfw_dash_changing(payload, n_list), "",
          .dfw_dash_sections(payload, n_list), "",
          .dfw_dash_groups(payload$by_campus, "campus", "5. By campus (first term -> last, trend)"), "",
          .dfw_dash_groups(payload$by_college, "college_name", "6. By college (first term -> last, trend)")),
        collapse = "\n")
}
