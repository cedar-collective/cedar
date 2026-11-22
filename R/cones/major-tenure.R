# Major tenure: semester by semester after students enter a major, where are they?
#
# The question a page asks about Undecided ("how long do students stay
# Undecided, and how many never declare?") and about any other major: of the
# students who entered it, at the start of each regular term after, how many
# are still in it, are enrolled in another major, hold a degree, or are not
# enrolled.
#
# One row per step after entry. Entry is the population's `first_unit_term`
# (build_population(): the student's first record in the focal majors, a
# pre-major's included). Each step has its own students: those whose term at
# that step is settled and inside the degree edge (the opportunity edge), so a
# recent entrant is in the early steps and not the later ones.
#
# A student already in the major when the data begin has no entry to count
# from, and is counted in `meta$n_unclear`, not placed.
#
# How a student arrived (`opt$arrival`, with `programs`) is what the record
# says of them in the term they entered the major (student_term_entry_type()):
#   "first_time"    new to UNM that term as a first-time student
#   "transfer"      new to UNM that term as a transfer student
#   "already_here"  anything else: continuing, readmitted, a change of level.
#                   They were at UNM before they entered this major.
# The groups differ in how often they stay enrolled, so the whole population's
# bars are a blend of them.
#
# Sections: calculation, plot prep, plot, text.
# Depends on: follow_students(), awarded_degrees() (branches/retention-context.R), validate_population(),
#   fmt_term() (trunk/utils.R), student_term_entry_type() (branches/population.R).

# The states a student can be in at a step, in drawing order: column, label.
MAJOR_TENURE_STATES <- c(
  n_in_major = "Still in it",
  n_other_major = "Enrolled in another major",
  n_no_major = "Enrolled, major not on record",
  n_degree = "Awarded a degree",
  n_not_enrolled = "Not enrolled that semester")

# How students arrived: value, the page's choice label.
MAJOR_TENURE_ARRIVALS <- c(
  all = "All students",
  first_time = "New first-time students",
  transfer = "New transfer students",
  already_here = "Already at UNM")

# ── Calculation ─────────────────────────────────────────────────────────────

#' Where a major's entrants are, each regular term after they entered
#'
#' @param population `build_population()` output with `first_unit_term`.
#' @param student_terms `cedar_student_terms`: `student_id`, `term`,
#'   `enrolled`, `primary_major_code`.
#' @param degrees `cedar_degrees`: `student_id`, `term`; a degree is one
#'   awarded_degrees() keeps.
#' @param opt `program_codes` (the focal major codes; required), `data_edges`
#'   (required: `last_enrolled_complete`, `last_degree`), `n_terms` (steps
#'   after entry, default 8), `arrival` (one name of `MAJOR_TENURE_ARRIVALS`,
#'   default `"all"`; any other needs `programs`).
#' @param programs `cedar_programs` (`student_id`, `term`,
#'   `student_population`), or NULL. With it, entrants are labelled by how
#'   they arrived and `meta$by_arrival` counts each group.
#' @return list(`steps`: `step` 0..n_terms, `n_observed` and one count per
#'   state of `MAJOR_TENURE_STATES`, which add to it; `meta`: `n_entered`
#'   (entered after the data begin and by both edges; the first step's count),
#'   `n_unclear` (in the major when the data begin), `n_no_entry` (no
#'   `first_unit_term`), `first_entry`, `last_entry`, `settled_edge`,
#'   `degree_edge`, `n_terms`, `program_codes`, `arrival`, `by_arrival`
#'   (`arrival`, `n` over every entrant; NULL without `programs`)).
get_major_tenure <- function(population, student_terms, degrees, opt = list(), programs = NULL) {
  validate_population(population, "major-tenure.R")
  need <- list(population = "first_unit_term", student_terms = c("student_id", "term", "enrolled", "primary_major_code"),
               degrees = c("student_id", "term"))
  have <- list(population = population, student_terms = student_terms, degrees = degrees)
  for (name in names(need)) {
    missing <- setdiff(need[[name]], names(have[[name]]))
    if (length(missing) > 0) stop("[major-tenure.R] ", name, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  codes <- opt$program_codes
  if (is.null(codes) || length(codes) == 0L) stop("[major-tenure.R] opt$program_codes (the focal major codes) is required.", call. = FALSE)
  edges <- opt$data_edges
  settled <- edges[["last_enrolled_complete"]]
  degree_edge <- edges[["last_degree"]]
  if (is.null(settled) || is.null(degree_edge)) {
    stop("[major-tenure.R] opt$data_edges must name the settled and degree edges.", call. = FALSE)
  }
  n_terms <- as.integer(opt$n_terms %||% 8L)
  arrival <- opt$arrival %||% "all"
  if (length(arrival) != 1L || !arrival %in% names(MAJOR_TENURE_ARRIVALS)) {
    stop("[major-tenure.R] opt$arrival must be one of ", paste(names(MAJOR_TENURE_ARRIVALS), collapse = ", "), ".", call. = FALSE)
  }
  if (arrival != "all" && is.null(programs)) {
    stop("[major-tenure.R] opt$arrival needs programs (the record of how each student arrived).", call. = FALSE)
  }
  data_start <- min(as.integer(student_terms$term))

  entrants <- population %>% distinct(student_id, .keep_all = TRUE) %>%
    transmute(student_id, entry = as.integer(first_unit_term))
  n_no_entry <- sum(is.na(entrants$entry))
  entrants <- entrants %>% filter(!is.na(entry))
  n_unclear <- sum(entrants$entry <= data_start)
  # An entrant's own entering term must be readable on both edges, so the
  # count of entrants is the first step's count.
  entrants <- entrants %>% filter(entry > data_start, entry <= settled, entry <= degree_edge)

  by_arrival <- NULL
  if (!is.null(programs)) {
    # One arrival per student-term; a term recorded both ways reads first-time.
    arrivals <- student_term_entry_type(programs) %>%
      arrange(entry_type) %>%
      distinct(student_id, term, .keep_all = TRUE)
    entrants <- entrants %>%
      left_join(arrivals, by = c("student_id", "entry" = "term"), relationship = "many-to-one") %>%
      mutate(arrival = dplyr::coalesce(entry_type, "already_here")) %>%
      select(-entry_type)
    by_arrival <- tibble::tibble(arrival = setdiff(names(MAJOR_TENURE_ARRIVALS), "all")) %>%
      left_join(entrants %>% count(arrival, name = "n"), by = "arrival", relationship = "one-to-one") %>%
      mutate(n = dplyr::coalesce(n, 0L))
    if (arrival != "all") entrants <- entrants[entrants$arrival == arrival, ]
  }

  here <- student_terms %>%
    filter(enrolled %in% TRUE, student_id %in% entrants$student_id) %>%
    distinct(student_id, target_term = as.integer(term), major = primary_major_code)
  if (anyDuplicated(here[c("student_id", "target_term")]) > 0L) {
    stop("[major-tenure.R] student_terms holds two rows for one student and term.", call. = FALSE)
  }
  placed <- follow_students(entrants %>% transmute(student_id, start = entry),
                            here %>% transmute(student_id, term = target_term), awarded_degrees(degrees),
                            n_terms, settled, degree_edge) %>%
    left_join(here, by = c("student_id", "target_term"), relationship = "many-to-one") %>%
    mutate(
      state = case_when(
        degree ~ "n_degree",
        enrolled & !is.na(major) & major %in% codes ~ "n_in_major",
        enrolled & !is.na(major) ~ "n_other_major",
        enrolled ~ "n_no_major",
        TRUE ~ "n_not_enrolled"))

  counts <- placed %>%
    count(step, state) %>%
    tidyr::pivot_wider(names_from = state, values_from = n, values_fill = 0L)
  for (state in names(MAJOR_TENURE_STATES)) if (!state %in% names(counts)) counts[[state]] <- integer(nrow(counts))
  steps <- tibble::tibble(step = 0:n_terms) %>%
    left_join(counts, by = "step", relationship = "one-to-one") %>%
    mutate(across(all_of(names(MAJOR_TENURE_STATES)), ~ dplyr::coalesce(.x, 0L))) %>%
    mutate(n_observed = n_in_major + n_other_major + n_no_major + n_degree + n_not_enrolled) %>%
    select(step, n_observed, all_of(names(MAJOR_TENURE_STATES)))

  list(steps = steps,
       meta = list(n_entered = nrow(entrants), n_unclear = n_unclear, n_no_entry = n_no_entry,
                   first_entry = if (nrow(entrants)) min(entrants$entry) else NA_integer_,
                   last_entry = if (nrow(entrants)) max(entrants$entry) else NA_integer_,
                   settled_edge = settled, degree_edge = degree_edge, n_terms = n_terms, program_codes = codes,
                   arrival = arrival, by_arrival = by_arrival))
}

# A count as page text: whole, with separators.

# ── Plot prep ───────────────────────────────────────────────────────────────

#' Each step's states as shares of the students who can be followed that far
#'
#' @param tenure `get_major_tenure()` output.
#' @param min_n Fewest students followed to a step for it to be kept.
#' @return One row per step kept: `step`, `when`, `n_observed`, the counts and
#'   a `<state>_pct` for each.
major_tenure_shares <- function(tenure, min_n = 10L) {
  states <- names(MAJOR_TENURE_STATES)
  rows <- tenure$steps %>% filter(n_observed >= min_n)
  for (state in states) rows[[sub("^n_", "", paste0(state, "_pct"))]] <- 100 * rows[[state]] / rows$n_observed
  rows %>% mutate(when = if_else(step == 0L, "Entering semester", paste0("Semester ", step + 1L)), .after = step)
}

#' The lead sentence: how many are still in the major a year and two years on
#'
#' @param tenure `get_major_tenure()` output.
#' @param major_name The major in the reader's words ("Undecided").
#' @param min_n As `major_tenure_shares()`.
major_tenure_lead <- function(tenure, major_name, min_n = 10L) {
  m <- tenure$meta
  s <- major_tenure_shares(tenure, min_n)
  if (nrow(s) == 0L || m$n_entered == 0L) {
    return(paste0("Too few students entered ", major_name, " where it can be seen to follow them."))
  }
  one <- function(step) {
    row <- s[s$step == step, ]
    if (nrow(row) == 0L) return(NULL)
    paste0("By their ", c("third", "fifth")[match(step, c(2L, 4L))], " semester, ", sprintf("%.1f%%", row$in_major_pct),
           " were still in it, ", sprintf("%.1f%%", row$other_major_pct), " were enrolled in another major and ",
           sprintf("%.1f%%", row$not_enrolled_pct), " were not enrolled (of ", fmt_count(row$n_observed), " who can be followed that far).")
  }
  how <- c(all = "", first_time = " in their first term at UNM, as first-time students,",
           transfer = " in their first term at UNM, as transfer students,",
           already_here = " when they were already at UNM")[[m$arrival %||% "all"]]
  paste(c(paste0(fmt_count(m$n_entered), " students entered ", major_name, how, " between ", fmt_term(m$first_entry), " and ",
                 fmt_term(m$last_entry), "."), one(2L), one(4L)), collapse = " ")
}

# ── Plot ────────────────────────────────────────────────────────────────────

#' One stacked bar a semester: where the entrants are
#' @param tenure `get_major_tenure()` output.
#' @param min_n As `major_tenure_shares()`.
plot_major_tenure <- function(tenure, min_n = 10L) {
  s <- major_tenure_shares(tenure, min_n)
  if (nrow(s) == 0L) stop("[major-tenure.R] too few students followed to draw.", call. = FALSE)
  colours <- c(n_in_major = CEDAR_SEMANTIC_COLORS[["neutral"]], n_other_major = CEDAR_SEMANTIC_COLORS[["positive"]],
               n_no_major = CEDAR_SEMANTIC_COLORS[["caution"]], n_degree = CEDAR_SEMANTIC_COLORS[["warning"]],
               n_not_enrolled = CEDAR_SEMANTIC_COLORS[["reference"]])
  fig <- plotly::plot_ly()
  for (state in names(MAJOR_TENURE_STATES)) {
    if (sum(s[[state]]) == 0L) next
    share <- s[[sub("^n_", "", paste0(state, "_pct"))]]
    fig <- plotly::add_trace(fig, x = s$when, y = share, type = "bar", name = MAJOR_TENURE_STATES[[state]],
                             marker = list(color = unname(colours[[state]])),
                             text = if_else(share >= 7, sprintf("%.0f%%", share), ""), textposition = "inside", textangle = 0,
                             hovertext = paste0(s$when, "<br>", MAJOR_TENURE_STATES[[state]], ": ", fmt_count(s[[state]]), " of ",
                                                fmt_count(s$n_observed), " (", sprintf("%.1f%%", share), ")"), hoverinfo = "text")
  }
  fig %>% plotly::layout(barmode = "stack",
                         xaxis = list(title = "", type = "category", categoryorder = "array", categoryarray = as.list(s$when)),
                         yaxis = list(title = "Share of students followed that far", ticksuffix = "%", range = c(0, 100)),
                         legend = list(orientation = "h", y = -0.15, traceorder = "normal"), margin = list(t = 20))
}

# ── Text ────────────────────────────────────────────────────────────────────

#' The tenure table as text
#' @param tenure `get_major_tenure()` output.
#' @param major_name The major in the reader's words.
#' @return Character vector, one element per line.
format_major_tenure <- function(tenure, major_name) {
  m <- tenure$meta
  s <- major_tenure_shares(tenure, min_n = 1L)
  pct <- function(x) sprintf("%.1f%%", x)
  c(paste0("## Semester by semester after entering ", major_name),
    major_tenure_lead(tenure, major_name, min_n = 1L),
    paste0("Not followed: ", fmt_count(m$n_unclear), " already in it when the data begin."),
    sprintf("  %-18s %9s %8s %8s %9s %8s %8s", "When", "Followed", "In it", "Other", "No major", "Degree", "Away"),
    sprintf("  %-18s %9s %8s %8s %9s %8s %8s", s$when, fmt_count(s$n_observed), pct(s$in_major_pct), pct(s$other_major_pct),
            pct(s$no_major_pct), pct(s$degree_pct), pct(s$not_enrolled_pct)))
}
