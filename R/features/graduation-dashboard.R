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
#   plot_exit_bands(), plot_exit_series()
#   format_graduation_dashboard()  the text preview

GRADUATION_LINES <- c(90, 115, 120)

#' The payload for Bird's Eye > Graduation
#'
#' @param student_terms,programs,degrees,terms As `get_exit_credits()` takes
#'   them; `student_terms` also carries `college`, the college of the
#'   student's primary major that term.
#' @param dims The dimension tables, to name majors and colleges.
#' @param opt `data_edges` (required), `student_level`, `campus`,
#'   `first_exit_term`, `line` (credits that count as far along; default 90),
#'   `min_list` (fewest students for a major to be listed by name; default
#'   10), `min_n`.
#' @return list(`bands`, `series` (one row per last term: `n_left`, `n_far`,
#'   `n_done`: at 120 or more), `colleges`, `majors` (far-along students by
#'   group: `n`, `n_done`, `n_flagged`, `n_pell`; majors under `min_list`
#'   pooled), `meta`).
build_graduation_dashboard <- function(student_terms, programs, degrees, terms, dims, opt = list()) {
  if (!"college" %in% names(student_terms)) {
    stop("[graduation-dashboard.R] student_terms lacks college (the loader attaches it).", call. = FALSE)
  }
  line <- as.numeric(opt$line %||% GRADUATION_LINES[[1]])
  min_list <- as.integer(opt$min_list %||% 10L)
  exit <- get_exit_credits(student_terms, programs, degrees, terms, opt)
  done_at <- max(exit$meta$breaks)
  students <- exit$students %>%
    left_join(student_terms %>% transmute(student_id, exit_term = as.integer(term), college),
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
  major_names <- name_program_codes(majors$group, dims)
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

  series <- students %>%
    group_by(exit_term) %>%
    summarize(n_left = n(), n_far = sum(credits >= line, na.rm = TRUE),
              n_done = sum(credits >= done_at, na.rm = TRUE), .groups = "drop") %>%
    arrange(exit_term)

  list(
    bands = exit$bands, series = series, colleges = colleges, majors = majors,
    meta = c(exit$meta, list(line = line, done_at = done_at, n_far = nrow(far),
                             n_done = sum(far$credits >= done_at),
                             n_far_flagged = sum(far$flagged %in% TRUE),
                             n_far_pell = sum(far$ever_pell %in% TRUE),
                             n_not_recorded = sum(is.na(students$credits)),
                             min_list = min_list, n_majors_pooled = n_pooled))
  )
}

.graduation_n <- function(x) format(as.integer(round(x)), big.mark = ",", trim = TRUE)

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
    x = labels, y = b$n, type = "bar", text = .graduation_n(b$n), textposition = "outside",
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

#' Far-along students who left, by last term
plot_exit_series <- function(payload) {
  s <- payload$series
  labels <- vapply(s$exit_term, fmt_term, character(1))
  m <- payload$meta
  plotly::plot_ly(
    x = labels, y = s$n_far, type = "bar", text = .graduation_n(s$n_far), textposition = "outside",
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
    "", "## By major", group_head, group_lines(payload$majors)
  )
}
