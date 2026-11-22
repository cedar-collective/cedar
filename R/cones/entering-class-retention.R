# entering-class-retention.R — How much of each entering class is still here?
#
# One question: of the students who first enrolled in a term, what share was
# enrolled one, two, three and more regular terms later?
#
# get_return_rates() (return-rates.R) reads every enrolled student-term and
# one step, the next regular term. This cone follows one group, an entering
# class, across several steps, so a class that holds its students through the
# first spring and loses them over the summer shows where it loses them. The
# two are siblings because their populations differ (every student-term
# against each student once, at entry); extending either would change the
# other's answer.
#
#   Entering class  the students whose first enrolled term at the level in
#                   scope is that term (cedar_student_terms' `enrolled`),
#                   scoped by their home campus that term. The first term the
#                   table holds is nobody's entering class: every continuing
#                   student's first row is there. It is left out and counted.
#   Still here      enrolled in the target term on any campus and at any
#                   level, or awarded a degree in or before it. Moving campus
#                   is not leaving; finishing is not leaving. A student away
#                   one term and back the next is not here in the first and
#                   here in the second.
#   Steps           regular terms: summer is not a step (advance_term()). For
#                   a fall class step 1 is the next spring and step 2 the
#                   next fall; `target_term` says which.
#   Edge            enrollment is read to the settled edge; a target term past
#                   it is unknown (NA), never zero.
#
# Who is in it: `opt$entry`.
#   "all"         everyone new at the level, which includes transfer students
#                 and, among undergraduates, students taking college courses
#                 while in high school. The default.
#   "first_time"  the standard retention cohort: students the record calls
#                 first-time in that term (student_term_entry_type() over
#                 `programs`), enrolled in it. A student who took college
#                 courses in high school enters in the term the record calls
#                 them first-time, not at their first course. A first-time
#                 student who starts in the summer and is enrolled that fall
#                 belongs to the fall class, as federal reporting counts
#                 them; one who is not stays a summer entrant.
#   "transfer"    students the record calls a new transfer in that term.
# For the two recorded kinds the table's first term is a real class: the
# record says who is new, so nothing is left out.
# `opt$time_status` keeps students with one of the given time statuses in
# their entering term (full-time, for the federal cohort).
# `opt$classification` narrows the class to students holding one of the
# given classifications in their entering term.
# `opt$arrival_credits` (`c(low, high)`) keeps the entering students who
# brought at least `low` and fewer than `high` credits from elsewhere
# (build_credit_timeline()'s `transfer_credits`, the sanctioned read), so
# transfer classes can be followed by how far along they arrived. A student
# with no record of it yet is in no band: attribute `n_arrival_unknown`
# (`term`, `n`, `n_class`) counts them by class. A new student's first pull
# has none, and a student who left before the next pull never gets one, so
# reading them as "brought none" filled the lowest band with leavers, and
# leaving them out leaves each band its stayers (ISSUES I74). A class with
# more than `opt$max_unknown_share` (2%) of its students unrecorded is
# therefore not read by band at all: its rows keep `n_entering` and every
# rate and count is NA (attribute `arrival_withheld`, the terms).
#
# Pace: `opt$pace` (credits a regular term, fastest first, named; e.g.
# DEGREE_PACE_TERM_CREDITS) splits "still here" at each step. An extension,
# not a sibling: same classes, same steps, and no existing column changes.
#   Degree        awarded in or before the target term.
#   On a pace     enrolled in the target term having completed, before it
#                 began, at least that pace's credits for each regular term
#                 since entry (summer credits count; the entering term is
#                 term one). Each student is counted under the fastest pace
#                 they meet, else `n_slower`.
#   Credits       completed credits earned here, the running total on
#                 cedar_student_terms. Credit brought from elsewhere (test,
#                 dual or transfer credit) is not in it, so a student who
#                 arrived with credit is further along than shown. A running
#                 total that is not whole (`timeline_valid` not TRUE) is
#                 `n_credits_unknown`, never placed on a pace.
#   Gone          not enrolled in the target term and no degree. A student
#                 away for the term is gone at that step and may be back at
#                 the next.
#   Pace edge     credits before a term need every earlier term graded: a
#                 step is split only where its target term is at or before
#                 the calendar term after `last_graded` (attribute
#                 `pace_edge`). Past it the pace columns are NA.
# `credits_q1` / `credits_median` / `credits_q3` describe the enrolled
# students with a known total: survivors only, which the reader is told.
#
# Depends on: .build_enrolled_lookup(), degrees_to_date(),
#               .compute_retention() (branches/retention-context.R)
#             cedar_longitudinal_edge() (branches/data-edges.R)
#             advance_term() (branches/cedar-terms.R), get_term_type()
#             student_term_entry_type() (branches/population.R)

#' Each entering class's share still enrolled one to `n_terms` regular terms later
#'
#' @param student_terms `cedar_student_terms`.
#' @param degrees `cedar_degrees`, so a degree counts as still here; NULL
#'   reads enrollment alone. A degree is degrees_to_date(): awarded to the
#'   degree edge (`opt$data_edges$last_degree`, required with `degrees`), and
#'   past it an application to graduate.
#' @param opt `term_type` (the entering classes' term type; NULL keeps every
#'   regular term type), `student_level` (level codes; NULL keeps every
#'   level, each student entering once), `campus` (home campuses in the
#'   entering term; NULL keeps every campus), `classification` (entering-term
#'   classifications to keep; NULL keeps all), `n_terms` (steps followed;
#'   default 4), `min_n` (smallest entering class given a rate; default 30),
#'   `data_edges` (`cedar_data_edges()` output, required), `entry` (`"all"`,
#'   the default, `"first_time"` or `"transfer"`: see the header; the last
#'   two need `programs`), `time_status` (entering-term time statuses to
#'   keep; NULL keeps all), `arrival_credits` (`c(low, high)` credits brought
#'   from elsewhere; needs `programs`; NULL keeps all), `pace` (named credits a regular term, fastest
#'   first; adds the pace columns, see the header).
#' @param programs `cedar_programs`, for `entry` other than `"all"`.
#' @return A tibble, one row per entering `term` and `step`: `target_term`,
#'   `n_entering`, `n_here` (NA past the edge), `here_pct` (NA past the edge
#'   or under `min_n`). With `opt$pace`, also `n_degree`, one `n_<name>` per
#'   pace, `n_slower`, `n_credits_unknown`, `n_gone` and the three credit
#'   quartiles of the enrolled, all NA past the edge. Attributes: `edge`, `first_term` (the table's first
#'   term, left out under `entry = "all"`), `n_first_term` (the students
#'   whose first row is there; 0 for a recorded entry kind), `entry`,
#'   `n_summer_starts` (first-time summer starters counted in the fall
#'   class), `n_arrival_unknown` and `arrival_withheld` (with
#'   `arrival_credits`), `n_label_trusted` (with `pace`: first-time students
#'   entering in the table's first term, whose credits are read from that
#'   term on), `n_terms`, `min_n`.
get_entering_class_retention <- function(student_terms, degrees = NULL, opt = list(), programs = NULL) {
  entry <- opt$entry %||% "all"
  if (length(entry) != 1L || !entry %in% c("all", "first_time", "transfer")) {
    stop("[entering-class-retention.R] opt$entry must be \"all\", \"first_time\" or \"transfer\".", call. = FALSE)
  }
  if (entry != "all" && is.null(programs)) {
    stop("[entering-class-retention.R] programs (cedar_programs) is required for opt$entry = \"", entry,
         "\": the record of who is new is there.", call. = FALSE)
  }
  pace <- opt$pace
  if (!is.null(pace) && (is.null(names(pace)) || any(!nzchar(names(pace))) || is.unsorted(rev(pace), strictly = TRUE))) {
    stop("[entering-class-retention.R] opt$pace must be named credits a term, fastest first.", call. = FALSE)
  }
  needed <- c("student_id", "term", "enrolled", "student_level", "student_campus",
              if (!is.null(pace)) c("cumulative_completed_unm_credits", "completed_unm_credits", "timeline_valid"),
              if (!is.null(opt$classification)) "student_classification",
              if (!is.null(opt$time_status)) "time_status")
  missing <- setdiff(needed, names(student_terms))
  if (length(missing) > 0L) {
    stop("[entering-class-retention.R] student_terms lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  edge <- cedar_longitudinal_edge(opt$data_edges)
  if (is.null(edge)) {
    stop("[entering-class-retention.R] opt$data_edges has no settled enrollment edge.", call. = FALSE)
  }
  n_terms <- as.integer(opt$n_terms %||% 4L)
  if (is.na(n_terms) || n_terms < 1L) {
    stop("[entering-class-retention.R] opt$n_terms must be at least 1.", call. = FALSE)
  }
  min_n <- as.integer(opt$min_n %||% 30L)

  enrolled <- student_terms %>% filter(enrolled, term <= edge) %>% mutate(term = as.integer(term))
  if (nrow(enrolled) == 0L) {
    stop("[entering-class-retention.R] no enrolled student-term at or before the settled edge.", call. = FALSE)
  }
  first_term <- min(enrolled$term)

  # Each student's entering term at the level in scope: the first enrolled
  # term among that level's rows.
  at_level <- if (is.null(opt$student_level)) enrolled else enrolled %>% filter(student_level %in% opt$student_level)
  n_summer_starts <- 0L
  n_arrival_unknown <- NULL
  arrival_withheld <- integer(0)
  if (entry == "all") {
    entering <- at_level %>%
      arrange(student_id, term) %>%
      distinct(student_id, .keep_all = TRUE)
    n_first_term <- sum(entering$term == first_term)
    entering <- entering %>% filter(term > first_term)
  } else {
    # The first enrolled term the record calls the student new in.
    arrivals <- student_term_entry_type(programs) %>% filter(entry_type == entry)
    entering <- at_level %>%
      semi_join(arrivals, by = c("student_id", "term")) %>%
      arrange(student_id, term) %>%
      distinct(student_id, .keep_all = TRUE)
    n_first_term <- 0L
    if (entry == "first_time") {
      # A summer starter enrolled that fall is in the fall class, described
      # by their fall row.
      summer <- entering %>%
        filter(get_term_type(term) == "summer") %>%
        transmute(student_id, term = advance_term(term, 1L))
      moved <- at_level %>% semi_join(summer, by = c("student_id", "term"))
      n_summer_starts <- nrow(moved)
      entering <- bind_rows(entering %>% filter(!student_id %in% moved$student_id), moved)
    }
  }
  if (!is.null(opt$term_type)) entering <- entering %>% filter(get_term_type(term) %in% opt$term_type)
  entering <- entering %>% filter(get_term_type(term) %in% c("fall", "spring", "summer"))
  if (!is.null(opt$campus)) entering <- entering %>% filter(student_campus %in% opt$campus)
  if (!is.null(opt$classification)) entering <- entering %>% filter(student_classification %in% opt$classification)
  if (!is.null(opt$time_status)) entering <- entering %>% filter(time_status %in% opt$time_status)
  if (!is.null(opt$arrival_credits)) {
    range <- as.numeric(opt$arrival_credits)
    if (length(range) != 2L || anyNA(range) || range[1] >= range[2] || is.null(programs)) {
      stop("[entering-class-retention.R] opt$arrival_credits must be c(low, high) and needs programs.", call. = FALSE)
    }
    brought <- build_credit_timeline(entering, programs)
    # No record of the credit brought is not "none brought": such a student
    # is in no band, and counted (ISSUES I74).
    unknown_ids <- brought$student_id[!brought$transfer_credits_known]
    n_arrival_unknown <- entering %>%
      group_by(term) %>%
      summarize(n = sum(student_id %in% unknown_ids), n_class = n(), .groups = "drop") %>%
      filter(n > 0L)
    # The students without a record are mostly the ones who left (a student
    # who stays gets one at the next pull), so the class's banded students are
    # the ones who stayed. Past a small share the class is not read by band.
    max_unknown <- as.numeric(opt$max_unknown_share %||% 0.02)
    arrival_withheld <- n_arrival_unknown$term[n_arrival_unknown$n / n_arrival_unknown$n_class > max_unknown]
    keep <- brought$student_id[brought$transfer_credits_known & brought$transfer_credits >= range[1] &
                                 brought$transfer_credits < range[2]]
    entering <- entering %>% filter(student_id %in% keep)
  }
  cedar_debug("[entering-class-retention.R] ", nrow(entering), " entering students to ", fmt_term(edge))
  # Degrees to the settled edge: awarded where posted, applied for past the
  # degree edge, so the newest steps do not read a new graduate as gone.
  to_date <- NULL
  if (!is.null(degrees)) {
    if (is.null(opt$data_edges[["last_degree"]])) {
      stop("[entering-class-retention.R] degrees need opt$data_edges$last_degree.", call. = FALSE)
    }
    # An application is for a term the student may still be enrolled in: it
    # counts from the term after.
    to_date <- degrees_to_date(degrees, opt$data_edges[["last_degree"]]) %>%
      mutate(degree_term = if_else(basis == "applied", advance_term(degree_term, 1L, summer = TRUE), degree_term)) %>%
      filter(degree_term <= edge)
  }

  empty <- tibble::tibble(term = integer(), step = integer(), target_term = integer(), n_entering = integer(),
                          n_here = integer(), here_pct = numeric())
  result <- if (nrow(entering) == 0L) empty else {
    cohort <- entering %>% transmute(student_id, anchor_term = term)
    graduated <- if (is.null(to_date)) NULL else to_date %>% distinct(student_id, grad_term = degree_term)
    # The lookup is every level's enrollment: a student who moves level is here.
    followed <- .compute_retention(cohort, .build_enrolled_lookup(enrolled), n_terms, graduated)
    bind_rows(lapply(seq_len(n_terms), function(k) {
      followed %>%
        group_by(term = anchor_term) %>%
        summarize(n_entering = n(), n_here = sum(.data[[paste0("retained_", k)]]), .groups = "drop") %>%
        mutate(step = k, target_term = advance_term(term, k))
    })) %>%
      mutate(n_here = as.integer(n_here),
             here_pct = if_else(n_entering >= min_n, 100 * n_here / n_entering, NA_real_)) %>%
      select(term, step, target_term, n_entering, n_here, here_pct) %>%
      arrange(term, step)
  }
  pace_edge <- NULL
  if (!is.null(pace)) {
    graded <- opt$data_edges[["last_graded"]]
    if (is.null(graded)) {
      stop("[entering-class-retention.R] opt$pace needs opt$data_edges$last_graded.", call. = FALSE)
    }
    pace_edge <- min(edge, advance_term(as.integer(graded), 1L, summer = TRUE))
    # A first-time student's record starts with them: where the table's
    # first term is their entering term the running total is whole apart from
    # credit earned here before entering (dual credit), and is read.
    trusted <- if (entry == "first_time") entering$student_id[entering$term == first_term] else character(0)
    result <- .entering_class_pace(result, entering, enrolled, to_date, pace, n_terms, pace_edge, trusted)
    attr(result, "n_label_trusted") <- length(trusted)
  }
  if (length(arrival_withheld) > 0L) {
    held <- result$term %in% arrival_withheld
    for (col in setdiff(names(result), c("term", "step", "target_term", "n_entering"))) result[[col]][held] <- NA
  }
  attr(result, "arrival_withheld") <- arrival_withheld
  attr(result, "pace") <- pace
  attr(result, "pace_edge") <- pace_edge
  attr(result, "edge") <- edge
  attr(result, "first_term") <- first_term
  attr(result, "n_first_term") <- n_first_term
  attr(result, "entry") <- entry
  attr(result, "n_summer_starts") <- n_summer_starts
  attr(result, "n_arrival_unknown") <- n_arrival_unknown
  attr(result, "n_terms") <- n_terms
  attr(result, "min_n") <- min_n
  result
}

# The pace columns for get_entering_class_retention(): each entering student's
# state at each step whose target term is settled, counted by class and step.
.entering_class_pace <- function(result, entering, enrolled, to_date, pace, n_terms, edge, trusted = character(0)) {
  at_term <- enrolled %>%
    transmute(student_id, target_term = term,
              credits = if_else(timeline_valid %in% TRUE | student_id %in% trusted,
                                as.numeric(cumulative_completed_unm_credits) - as.numeric(completed_unm_credits),
                                NA_real_))
  awarded <- if (is.null(to_date)) {
    tibble::tibble(student_id = character(), degree_term = integer(), basis = character())
  } else to_date %>% filter(degree_term <= edge)
  steps <- bind_rows(lapply(seq_len(n_terms), function(k) {
    entering %>% transmute(student_id, term, step = k, target_term = advance_term(term, k))
  })) %>%
    filter(target_term <= edge)
  # A degree counts from the entering term on, as "still here" counts it.
  has_degree <- steps %>%
    inner_join(awarded, by = "student_id", relationship = "many-to-many") %>%
    filter(degree_term >= term, degree_term <= target_term) %>%
    distinct(student_id, term, step)
  states <- steps %>%
    left_join(at_term, by = c("student_id", "target_term"), relationship = "many-to-one") %>%
    left_join(has_degree %>% mutate(degree = TRUE), by = c("student_id", "term", "step"),
              relationship = "one-to-one") %>%
    left_join(at_term %>% distinct(student_id, target_term) %>% mutate(here = TRUE),
              by = c("student_id", "target_term"), relationship = "many-to-one") %>%
    mutate(degree = degree %in% TRUE, here = here %in% TRUE & !degree)
  # The fastest pace met, as its position in `pace`; 0 is slower than all.
  # Paces run fastest first, so the number met places the student.
  n_met <- rowSums(vapply(unname(pace), function(rate) states$credits >= rate * states$step,
                          logical(nrow(states))) %>% matrix(nrow = nrow(states)))
  states$pace_met <- if_else(n_met > 0, length(pace) - n_met + 1, 0)
  quartile <- function(x, p) if (length(x) == 0L) NA_real_ else stats::quantile(x, p, names = FALSE)
  counts <- states %>%
    group_by(term, step) %>%
    summarize(
      n_degree = sum(degree),
      n_slower = sum(here & pace_met %in% 0), n_credits_unknown = sum(here & is.na(pace_met)),
      n_gone = sum(!here & !degree),
      credits_q1 = quartile(credits[here & !is.na(credits)], 0.25),
      credits_median = quartile(credits[here & !is.na(credits)], 0.5),
      credits_q3 = quartile(credits[here & !is.na(credits)], 0.75), .groups = "drop")
  for (i in seq_along(pace)) {
    on_pace <- states %>%
      group_by(term, step) %>%
      summarize(n = sum(here & pace_met %in% i), .groups = "drop")
    counts[[paste0("n_", names(pace)[[i]])]] <- on_pace$n[match(paste(counts$term, counts$step),
                                                                paste(on_pace$term, on_pace$step))]
  }
  counts <- counts %>%
    select(term, step, n_degree, all_of(paste0("n_", names(pace))), n_slower, n_credits_unknown, n_gone,
           credits_q1, credits_median, credits_q3)
  result %>% left_join(counts, by = c("term", "step"), relationship = "one-to-one")
}
