# registration-watch.R — Which registrations are worth a look, ranked?
#
# Regstats runs several screens, each against a course's own history: an
# enrollment bump or dip, students still waiting, fill (near full now, near
# full in most earlier terms, fuller than usual) and early or late drops. Read
# one at a time they mislead: a dip reads as falling demand until the same
# course is also near full, when it says the seats fell. This feature reads
# them together.
#
#   build_registration_watch()   one row per course the screens flagged, its
#                                flags, the pattern they make, the students
#                                behind it; a roll-up by college
#   format_registration_watch()  the payload as text (text-first preview)
#   prepare_registration_watch_plot_data()  the listed courses on two axes:
#                                census against its usual, and census fill
#   plot_registration_watch()    the chart (native plotly)
#   registration_watch_plot_note()  what the chart leaves out, in a sentence
#
# A row is a term, campus, college, course and part of term, the grain every
# Regstats table is reported at, so a course is never read across campuses
# (campus-policy.md). Each row gets the first pattern in
# REGISTRATION_WATCH_PATTERNS its flags satisfy. "Usually near full" (near
# full now and in most earlier terms, or in most earlier terms only, with
# nothing else unusual) is a state, not news: it is counted in `meta` and
# left out of the list unless opt$include_known is TRUE.
#
# The students behind a row are the pattern's lead measure, read from the
# screen that raised it: for a bump or a dip, the students beyond the
# course's usual range (Regstats' `impacted`); for a waitlist, the students
# waiting; for drops, the drops beyond the usual range. Fill-only patterns
# have no student count (NA) and rank after the rest of their pattern by fill.
#
# "Near full" is Regstats' saturation screen: census fill at or above the
# run's Chronic Fill Rate (CEDAR_NEAR_FULL_FILL, 90%, unless the user changed
# it). It is never called full, which is 98% of seats on the first day
# (R/lists/seat_fill.R); the preview prints the rate it used.
#
# Nothing is recounted: every number is the Regstats payload's. A course's
# census, usual census, seats and fill are its `course_context` row, there
# whichever screen raised it, so every listed course is read on the same
# measures. The screens'
# thresholds are the run's (`flagged$thresholds`), recorded in `meta`. A
# renumbered course is one course here because Regstats keys on course_id
# (a confirmed code_history.csv rename); an unconfirmed one has no baseline
# under its new code and no current rows under its old, so neither is flagged.
#
# Depends on: get_reg_stats() output (features/regstats.R)
#             fmt_term() (trunk/utils.R), CEDAR_SEMANTIC_COLORS (trunk/utils.R)

REGISTRATION_WATCH_PATTERNS <- tibble::tribble(
  ~pattern,             ~label,                 ~sentence,
  "seats_cut",          "Seats cut",            "fewer students than usual, and its sections are near full",
  "unmet_demand",       "Students waiting",     "students are still waiting for a seat",
  "growth_at_capacity", "Growth near capacity", "more students than usual, and its sections are now near full",
  "churn",              "Growth with churn",    "more students than usual, and more of them dropping",
  "falling_demand",     "Falling demand",       "fewer students than usual, with seats to spare",
  "rising_demand",      "Rising demand",        "more students than usual, with seats to spare",
  "drop_spike",         "Drop spike",           "more drops than usual",
  "fuller_than_usual",  "Fuller than usual",    "fuller than its usual pattern",
  "usually_full",       "Usually near full",    "near full in most earlier terms, and nothing else unusual"
)

.REGISTRATION_WATCH_KEY <- c("term", "campus", "college", "subject_course", "part_term")

.registration_watch_frame <- function(flagged, name, measures) {
  df <- flagged[[name]]
  if (is.null(df)) stop("[registration-watch.R] flagged has no `", name, "` table", call. = FALSE)
  if (nrow(df) == 0) return(NULL)
  missing <- setdiff(c(.REGISTRATION_WATCH_KEY, measures), names(df))
  if (length(missing)) {
    stop("[registration-watch.R] flagged$", name, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  out <- df %>% dplyr::ungroup() %>%
    dplyr::mutate(term = as.character(term), part_term = as.character(part_term)) %>%
    dplyr::select(dplyr::all_of(c(.REGISTRATION_WATCH_KEY, measures)),
                  dplyr::any_of("course_title"))
  dup <- out %>% dplyr::count(dplyr::across(dplyr::all_of(.REGISTRATION_WATCH_KEY))) %>% dplyr::filter(n > 1)
  if (nrow(dup)) {
    stop("[registration-watch.R] flagged$", name, " repeats a term, campus, college, course and ",
         "part of term (", dup$subject_course[1], " ", dup$campus[1], ")", call. = FALSE)
  }
  out
}

#' Which registrations are worth a look, ranked
#'
#' @param flagged The list get_reg_stats() returns: `bumps`, `dips`,
#'   `waits`, `sat`, `early_drops` and `late_drops` (a table may have no
#'   rows), `course_context` (every raised course's census, usual census,
#'   seats and fill) and `thresholds`.
#' @param opt `include_known` (default FALSE: "usually near full" rows are counted,
#'   not listed).
#' @return A list: `courses` (one row per flagged term, campus, college,
#'   course and part of term: the flags as logical columns, `n_screens`,
#'   `pattern`, `label`, `sentence`, `students`, and the evidence:
#'   `census_enrl`, `census_enrl_mean`, `enrl_ratio` (census over its usual),
#'   `waiting`, `capacity`, `fill_rate`, `drops_beyond`), ordered by pattern, then students, then screens;
#'   `rollup` (college x pattern: `courses`, `students`, `examples`); `meta`
#'   (`terms`, `campuses`, `n_flagged`, `n_listed`, `n_usually_full`,
#'   `include_known`, `thresholds`).
build_registration_watch <- function(flagged, opt = list()) {
  if (!is.list(flagged)) stop("[registration-watch.R] flagged must be the get_reg_stats() list", call. = FALSE)
  include_known <- isTRUE(opt$include_known)
  key <- .REGISTRATION_WATCH_KEY
  bumps <- .registration_watch_frame(flagged, "bumps", "impacted")
  dips  <- .registration_watch_frame(flagged, "dips",  "impacted")
  waits <- .registration_watch_frame(flagged, "waits", "waiting")
  sat   <- .registration_watch_frame(flagged, "sat", c("is_full_now", "is_chronic_hist", "is_running_hot"))
  context <- .registration_watch_frame(flagged, "course_context",
                                       c("census_enrl", "census_enrl_mean", "capacity", "fill_rate"))
  early <- .registration_watch_frame(flagged, "early_drops", "impacted")
  late  <- .registration_watch_frame(flagged, "late_drops",  "impacted")

  # Every flagged key, once, with its title from whichever screen carries one.
  frames <- list(bumps, dips, waits, sat, early, late)
  keys <- dplyr::bind_rows(lapply(Filter(Negate(is.null), frames), function(f)
    dplyr::select(f, dplyr::all_of(key), dplyr::any_of("course_title"))))
  empty_courses <- tibble::tibble(term = character(), campus = character(), college = character(),
                                  subject_course = character(), part_term = character())
  if (nrow(keys) == 0) keys <- empty_courses
  if (!"course_title" %in% names(keys)) keys$course_title <- NA_character_
  rows <- keys %>% dplyr::group_by(dplyr::across(dplyr::all_of(key))) %>%
    dplyr::summarise(course_title = dplyr::first(stats::na.omit(c(course_title, NA_character_))),
                     .groups = "drop")
  # Every raised course has its context row, whichever screen raised it; a
  # row without one is a payload from another version, never filled in.
  no_context <- if (is.null(context)) rows else dplyr::anti_join(rows, context, by = key)
  if (nrow(no_context)) {
    stop("[registration-watch.R] flagged$course_context has no row for ", no_context$subject_course[1],
         " (", no_context$campus[1], "); rerun Regstats", call. = FALSE)
  }
  if (is.null(context)) {   # nothing raised: rows is empty too
    context <- dplyr::mutate(rows[key], census_enrl = numeric(), census_enrl_mean = numeric(),
                             capacity = numeric(), fill_rate = numeric())
  }

  pick <- function(f, cols, renames = cols) {
    if (is.null(f)) return(rows[key] %>% dplyr::mutate(!!!stats::setNames(rep(list(NA), length(renames)), renames)))
    dplyr::select(f, dplyr::all_of(key), stats::setNames(cols, renames))
  }
  flag <- function(f) if (is.null(f)) rows[key][0, ] else dplyr::select(f, dplyr::all_of(key))
  in_frame <- function(f) {
    hit <- flag(f) %>% dplyr::mutate(.hit = TRUE)
    dplyr::left_join(rows[key], hit, by = key)$.hit %in% TRUE
  }
  courses <- rows %>%
    dplyr::mutate(bump = in_frame(bumps), dip = in_frame(dips), waitlist = in_frame(waits),
                  early_drops = in_frame(early), late_drops = in_frame(late)) %>%
    dplyr::left_join(pick(bumps, "impacted", "bump_beyond"), by = key) %>%
    dplyr::left_join(pick(dips, "impacted", "dip_beyond"), by = key) %>%
    dplyr::left_join(pick(waits, "waiting"), by = key) %>%
    dplyr::left_join(pick(sat, c("is_full_now", "is_chronic_hist", "is_running_hot"),
                          c("full_now", "usually_full", "running_hot")), by = key) %>%
    dplyr::left_join(dplyr::select(context, dplyr::all_of(key), census_enrl, census_enrl_mean,
                                   capacity, fill_rate),
                     by = key, relationship = "one-to-one") %>%
    dplyr::left_join(pick(early, "impacted", "early_beyond"), by = key) %>%
    dplyr::left_join(pick(late, "impacted", "late_beyond"), by = key) %>%
    dplyr::mutate(
      full_now = full_now %in% TRUE, usually_full = usually_full %in% TRUE,
      running_hot = running_hot %in% TRUE,
      n_screens = bump + dip + waitlist + full_now + usually_full + running_hot + early_drops + late_drops,
      # Census as a multiple of its usual; NA with no earlier offering to compare.
      enrl_ratio = dplyr::if_else(!is.na(census_enrl_mean) & census_enrl_mean > 0,
                                  census_enrl / census_enrl_mean, NA_real_),
      drops_beyond = dplyr::if_else(early_drops | late_drops,
                                    dplyr::coalesce(early_beyond, 0) + dplyr::coalesce(late_beyond, 0),
                                    NA_real_),
      pattern = dplyr::case_when(
        dip & full_now                         ~ "seats_cut",
        waitlist                               ~ "unmet_demand",
        bump & full_now                        ~ "growth_at_capacity",
        bump & (early_drops | late_drops)      ~ "churn",
        dip                                    ~ "falling_demand",
        bump                                   ~ "rising_demand",
        early_drops | late_drops               ~ "drop_spike",
        running_hot | (full_now & !usually_full) ~ "fuller_than_usual",
        usually_full                           ~ "usually_full"
      ),
      students = dplyr::case_when(
        pattern %in% c("seats_cut", "falling_demand")              ~ as.numeric(dip_beyond),
        pattern == "unmet_demand"                                  ~ as.numeric(waiting),
        pattern %in% c("growth_at_capacity", "rising_demand")      ~ as.numeric(bump_beyond),
        pattern %in% c("churn", "drop_spike")                      ~ drops_beyond,
        TRUE                                                       ~ NA_real_)
    )
  if (any(is.na(courses$pattern))) {
    stop("[registration-watch.R] a flagged row matched no pattern: ",
         courses$subject_course[is.na(courses$pattern)][1], call. = FALSE)
  }
  courses <- courses %>%
    dplyr::left_join(dplyr::mutate(REGISTRATION_WATCH_PATTERNS, .rank = dplyr::row_number()), by = "pattern") %>%
    dplyr::arrange(.rank, dplyr::desc(dplyr::coalesce(students, -1)), dplyr::desc(n_screens),
                   dplyr::desc(fill_rate), subject_course, campus) %>%
    dplyr::select(dplyr::all_of(key), course_title, bump, dip, waitlist, full_now, usually_full,
                  running_hot, early_drops, late_drops, n_screens, pattern, label, sentence,
                  students, census_enrl, census_enrl_mean, enrl_ratio, waiting, capacity, fill_rate,
                  drops_beyond)
  n_usually_full <- sum(courses$pattern == "usually_full")
  listed <- if (include_known) courses else dplyr::filter(courses, pattern != "usually_full")

  rollup <- listed %>%
    dplyr::group_by(college, pattern, label) %>%
    dplyr::summarise(courses = dplyr::n(),
                     # A fill-only pattern has no student count: NA, never 0.
                     students = if (all(is.na(students))) NA_real_ else sum(students, na.rm = TRUE),
                     examples = paste(utils::head(unique(subject_course), 3), collapse = ", "),
                     .groups = "drop") %>%
    dplyr::left_join(dplyr::transmute(REGISTRATION_WATCH_PATTERNS, pattern, .rank = dplyr::row_number()),
                     by = "pattern") %>%
    dplyr::arrange(college, .rank) %>% dplyr::select(-.rank)

  list(
    courses = listed,
    rollup = rollup,
    meta = list(terms = sort(unique(courses$term)), campuses = sort(unique(courses$campus)),
                n_flagged = nrow(courses), n_listed = nrow(listed),
                n_usually_full = n_usually_full, include_known = include_known,
                thresholds = flagged$thresholds)
  )
}

.registration_watch_n <- function(x) format(as.integer(round(x)), big.mark = ",", trim = TRUE)

# The near-full rate the run used (Regstats' Chronic Fill Rate), never assumed.
.registration_watch_near_full <- function(meta) {
  near_full <- meta$thresholds[["chronic_fill_rate"]]
  if (!is.numeric(near_full) || length(near_full) != 1 || is.na(near_full)) {
    stop("[registration-watch.R] payload$meta$thresholds lacks chronic_fill_rate", call. = FALSE)
  }
  near_full
}

.registration_watch_line <- function(r) {
  parts <- c(
    if (!is.na(r$census_enrl) && !is.na(r$census_enrl_mean))
      sprintf("%s enrolled against a usual %s", .registration_watch_n(r$census_enrl),
              .registration_watch_n(r$census_enrl_mean)),
    if (r$waitlist && !is.na(r$waiting)) sprintf("%s waiting", .registration_watch_n(r$waiting)),
    if (!is.na(r$fill_rate))
      sprintf("%s seats, %.1f%% filled at census", .registration_watch_n(r$capacity), 100 * r$fill_rate),
    if ((r$early_drops || r$late_drops) && !is.na(r$drops_beyond))
      sprintf("%s drops beyond the usual range", .registration_watch_n(r$drops_beyond))
  )
  where <- paste(c(r$campus, r$college, if (!identical(r$part_term, "1")) paste("part", r$part_term)),
                 collapse = " · ")
  sprintf("  %s (%s): %s; %d %s.", r$subject_course, where,
          paste(parts, collapse = "; "), as.integer(r$n_screens),
          if (r$n_screens == 1) "screen" else "screens")
}

#' The registration watch as text
#'
#' @param payload build_registration_watch() output.
#' @param n_per_pattern The most courses listed under each pattern.
#' @return A character vector of lines.
format_registration_watch <- function(payload, n_per_pattern = 5L) {
  if (!all(c("courses", "rollup", "meta") %in% names(payload))) {
    stop("[registration-watch.R] payload must come from build_registration_watch()", call. = FALSE)
  }
  m <- payload$meta
  near_full <- .registration_watch_near_full(m)
  terms <- if (length(m$terms)) paste(vapply(m$terms, function(t) fmt_term(as.integer(t)), character(1)), collapse = ", ") else "no term"
  out <- c(
    sprintf("Registration watch: %s · %s", terms, paste(m$campuses, collapse = ", ")),
    sprintf("%s courses flagged by at least one Regstats screen; %s usually near full and %s.",
            .registration_watch_n(m$n_flagged), .registration_watch_n(m$n_usually_full),
            if (isTRUE(m$include_known)) "listed" else "not listed"),
    sprintf("Near full means at least %s%% of seats filled at census.", format(100 * near_full))
  )
  courses <- payload$courses
  for (p in unique(courses$pattern)) {
    rows <- courses[courses$pattern == p, ]
    out <- c(out, "", sprintf("%s (%d): %s.", rows$label[1], nrow(rows), rows$sentence[1]))
    shown <- utils::head(rows, n_per_pattern)
    out <- c(out, vapply(seq_len(nrow(shown)), function(i) .registration_watch_line(shown[i, ]), character(1)))
    if (nrow(rows) > n_per_pattern) out <- c(out, sprintf("  and %d more.", nrow(rows) - n_per_pattern))
  }
  if (nrow(payload$rollup)) {
    out <- c(out, "", "By college:")
    for (cl in unique(payload$rollup$college)) {
      r <- payload$rollup[payload$rollup$college == cl, ]
      out <- c(out, sprintf("  %s: %s", cl, paste(sprintf("%s %d", tolower(r$label), r$courses), collapse = ", ")))
    }
  }
  out
}


# ── Plot prep ──────────────────────────────────────────────────────────────────
#
# Each listed course is a point: across, its census as a multiple of its usual
# (a log scale, so half and twice its usual sit the same distance from usual);
# up, its seats filled at census, with the near-full line drawn. Seats cut,
# growth near capacity, falling and rising demand fall in their own corners.
#
# Colour says only what matters most on these axes: short of seats, demand
# moving with seats to spare, or another flag. A scatter lets any two colours
# touch, and no four CEDAR hues stay apart for every reader under that test
# (the dataviz validator, all pairs); rust and blue pass it, and the neutral
# reads as gray on purpose. The shape names the pattern, pointing down for
# fewer students than usual and up for more; the legend and the hover name it
# in words, and the ranked list beside the chart is its table.

.REGISTRATION_WATCH_MARKS <- tibble::tribble(
  ~pattern,             ~family,  ~symbol,
  "seats_cut",          "short",  "triangle-down",
  "unmet_demand",       "short",  "diamond",
  "growth_at_capacity", "short",  "triangle-up",
  "churn",              "other",  "square",
  "falling_demand",     "moving", "triangle-down",
  "rising_demand",      "moving", "triangle-up",
  "drop_spike",         "other",  "diamond",
  "fuller_than_usual",  "other",  "circle",
  "usually_full",       "other",  "circle-open"
)

.REGISTRATION_WATCH_FAMILIES <- c(short  = "Short of seats",
                                  moving = "Demand moving, seats to spare",
                                  other  = "Other flags")

.registration_watch_family_colors <- function() {
  c(short  = unname(CEDAR_SEMANTIC_COLORS["negative"]),
    moving = unname(CEDAR_SEMANTIC_COLORS["neutral"]),
    other  = unname(CEDAR_SEMANTIC_COLORS["reference"]))
}

.registration_watch_multiple <- function(x) {
  ifelse(x >= 1, sprintf("%.1f times its usual", x), sprintf("%.0f%% of its usual", 100 * x))
}

#' The listed courses placed on the watch's two axes
#'
#' @param payload build_registration_watch() output.
#' @param opt `max_ratio` (default 4): the axis runs from 1/max_ratio to
#'   max_ratio times the usual, and a course past either end is drawn at it
#'   (`off_scale`, its own value in the hover). `n_labels` (default 6): the
#'   courses with the most students behind them are named on the chart, among
#'   those at least `label_off_usual` (default 0.15) off their usual, skipping
#'   any that would sit on a name already placed; the crowded middle is left
#'   to the hover.
#' @return A list: `points` (one row per course drawn: the payload's key and
#'   pattern, `family`, `symbol`, `x` (the multiple, held to the axis), `y`
#'   (percent of seats filled at census), `size`, `off_scale`, `label`,
#'   `hover`); `not_drawn` (`reason`, `courses`: listed courses with no usual
#'   to compare or no usable seats); `near_full_pct`; `max_ratio`; `n_listed`.
prepare_registration_watch_plot_data <- function(payload, opt = list()) {
  if (!all(c("courses", "meta") %in% names(payload))) {
    stop("[registration-watch.R] payload must come from build_registration_watch()", call. = FALSE)
  }
  max_ratio <- opt$max_ratio %||% 4
  n_labels <- opt$n_labels %||% 6L
  label_off_usual <- opt$label_off_usual %||% 0.15
  if (!is.numeric(max_ratio) || length(max_ratio) != 1 || max_ratio <= 1) {
    stop("[registration-watch.R] opt$max_ratio must be one number above 1", call. = FALSE)
  }
  near_full <- .registration_watch_near_full(payload$meta)
  courses <- payload$courses
  missing <- setdiff(c("pattern", "enrl_ratio", "fill_rate", "students"), names(courses))
  if (length(missing)) {
    stop("[registration-watch.R] payload$courses lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  unmarked <- setdiff(courses$pattern, .REGISTRATION_WATCH_MARKS$pattern)
  if (length(unmarked)) stop("[registration-watch.R] no mark for pattern ", unmarked[1], call. = FALSE)

  courses <- courses %>%
    dplyr::mutate(reason = dplyr::case_when(
      is.na(census_enrl_mean) | census_enrl_mean <= 0 ~ "no earlier offering to compare",
      is.na(enrl_ratio) | enrl_ratio <= 0             ~ "no students at census",
      is.na(fill_rate)                                ~ "no usable seats",
      TRUE                                            ~ NA_character_))
  not_drawn <- courses %>% dplyr::filter(!is.na(reason)) %>%
    dplyr::count(reason, name = "courses")

  drawn <- courses %>% dplyr::filter(is.na(reason))
  biggest <- suppressWarnings(max(drawn$students, na.rm = TRUE))
  points <- drawn %>%
    dplyr::left_join(.REGISTRATION_WATCH_MARKS, by = "pattern") %>%
    dplyr::mutate(
      off_scale = enrl_ratio > max_ratio | enrl_ratio < 1 / max_ratio,
      x = pmin(pmax(enrl_ratio, 1 / max_ratio), max_ratio),
      y = 100 * fill_rate,
      # Area grows with the students behind the flag; a pattern with no count
      # (fill alone) is drawn at the smallest size, never as zero.
      size = dplyr::if_else(is.na(students) | !is.finite(biggest) | biggest <= 0, 9,
                            9 + 21 * sqrt(pmax(students, 0) / biggest)),
      .nameable = !is.na(students) &
        (enrl_ratio >= 1 + label_off_usual | enrl_ratio <= 1 / (1 + label_off_usual)),
      label = .registration_watch_names(x, 100 * fill_rate, students, .nameable, max_ratio, n_labels),
      hover = paste0(
        "<b>", subject_course, "</b> \u00b7 ", campus, " \u00b7 ", college,
        dplyr::if_else(part_term == "1", "", paste0(" \u00b7 part ", part_term)),
        "<br>", .registration_watch_label(pattern),
        "<br>", .registration_watch_n(census_enrl), " at census against a usual ",
        .registration_watch_n(census_enrl_mean), " (", .registration_watch_multiple(enrl_ratio), ")",
        "<br>", sprintf("%.1f%%", y), " of ", .registration_watch_n(capacity), " seats filled at census",
        dplyr::if_else(waitlist & !is.na(waiting),
                       paste0("<br>", .registration_watch_n(waiting), " waiting"), ""),
        dplyr::if_else(!is.na(drops_beyond),
                       paste0("<br>", .registration_watch_n(drops_beyond), " drops beyond the usual range"), ""),
        "<br>", n_screens, dplyr::if_else(n_screens == 1, " screen", " screens"))
    ) %>%
    dplyr::select(dplyr::all_of(.REGISTRATION_WATCH_KEY), pattern, label_text = subject_course,
                  family, symbol, x, y, size, off_scale, label, hover, students)

  list(points = points, not_drawn = not_drawn, near_full_pct = 100 * near_full,
       max_ratio = max_ratio, n_listed = nrow(courses))
}

# Which points to name: biggest first, skipping one within about a label's
# width and height (as fractions of the axes) of a point already named.
.registration_watch_names <- function(x, y, students, nameable, max_ratio, n_labels) {
  across <- log10(x) / (2 * log10(max_ratio))
  up <- y / 120
  named <- logical(length(x))
  for (i in order(-ifelse(nameable, students, -Inf))) {
    if (!nameable[i] || sum(named) >= n_labels) break
    near <- named & abs(across - across[i]) < 0.07 & abs(up - up[i]) < 0.05
    if (!any(near)) named[i] <- TRUE
  }
  named
}

.registration_watch_label <- function(pattern) {
  REGISTRATION_WATCH_PATTERNS$label[match(pattern, REGISTRATION_WATCH_PATTERNS$pattern)]
}

#' What the chart leaves out, in a sentence
#'
#' @param plot_data prepare_registration_watch_plot_data() output.
#' @return One sentence, or NULL when every listed course is drawn on scale.
registration_watch_plot_note <- function(plot_data) {
  n_off <- sum(plot_data$points$off_scale)
  n_out <- sum(plot_data$not_drawn$courses)
  r <- format(plot_data$max_ratio)
  parts <- c(
    if (n_off > 0)
      sprintf("%d %s more than %s times or less than 1/%s of its usual, drawn at the chart's edge.",
              n_off, if (n_off == 1) "course is" else "courses are", r, r),
    if (n_out > 0)
      sprintf("%d listed %s not drawn: %s.", n_out, if (n_out == 1) "course is" else "courses are",
              paste(sprintf("%d with %s", plot_data$not_drawn$courses, plot_data$not_drawn$reason),
                    collapse = " and "))
  )
  if (!length(parts)) return(NULL)
  paste(c(parts, "The list has every course."), collapse = " ")
}

# ── Plotting ───────────────────────────────────────────────────────────────────

#' The registration watch as a chart
#'
#' @param plot_data prepare_registration_watch_plot_data() output, with at
#'   least one point.
#' @return A plotly object.
plot_registration_watch <- function(plot_data) {
  pts <- plot_data$points
  if (is.null(pts) || nrow(pts) == 0) {
    stop("[registration-watch.R] no course to draw; show the list alone", call. = FALSE)
  }
  colors <- .registration_watch_family_colors()
  ink <- unname(CEDAR_COLORS["text"])
  guide <- unname(CEDAR_SEMANTIC_COLORS["reference"])
  span <- log10(plot_data$max_ratio)
  x_range <- c(-span, span) * 1.08
  steps <- 2^seq(-floor(log2(plot_data$max_ratio)), floor(log2(plot_data$max_ratio)))
  tick_text <- ifelse(steps == 1, "usual", ifelse(steps > 1, paste0(steps, "\u00d7"),
                                                  paste0("1/", 1 / steps, "\u00d7")))
  y_max <- max(110, ceiling(max(pts$y) / 10) * 10 + 5)

  # Other flags are drawn first, under the courses short of seats or with
  # demand moving; the legend still lists the families in that order.
  families <- names(.REGISTRATION_WATCH_FAMILIES)
  marks <- .REGISTRATION_WATCH_MARKS %>%
    dplyr::filter(pattern %in% pts$pattern) %>%
    dplyr::mutate(.fam = match(family, families),
                  .pat = match(pattern, REGISTRATION_WATCH_PATTERNS$pattern),
                  legendrank = 100 * .fam + .pat) %>%
    dplyr::arrange(dplyr::desc(.fam), .pat)
  p <- plotly::plot_ly()
  for (i in seq_len(nrow(marks))) {
    pat <- marks$pattern[i]
    d <- pts[pts$pattern == pat, ]
    fam <- d$family[1]
    p <- plotly::add_trace(
      p, data = d, x = ~x, y = ~y, type = "scatter", mode = "markers",
      name = .registration_watch_label(pat), legendgroup = fam, legendrank = marks$legendrank[i],
      legendgrouptitle = list(text = unname(.REGISTRATION_WATCH_FAMILIES[fam])),
      text = ~hover, hovertemplate = "%{text}<extra></extra>",
      marker = list(color = unname(colors[fam]), symbol = d$symbol[1], size = ~size,
                    opacity = 0.85, line = list(color = "#ffffff", width = 1.5))
    )
  }
  lab <- pts[pts$label, ]
  labels <- lapply(seq_len(nrow(lab)), function(i) list(
    x = log10(lab$x[i]), y = lab$y[i], text = lab$label_text[i], showarrow = FALSE,
    xanchor = "left", xshift = lab$size[i] / 2 + 3, font = list(size = 11, color = ink)))
  corner <- function(text, x, y, xanchor, yanchor) list(
    text = text, x = x, y = y, xref = "paper", yref = "paper", xanchor = xanchor,
    yanchor = yanchor, showarrow = FALSE, font = list(size = 11, color = guide))
  guides <- list(
    corner("Fewer than usual, near full", 0, 1, "left", "top"),
    corner("More than usual, near full", 1, 1, "right", "top"),
    corner("Fewer than usual, seats to spare", 0, 0, "left", "bottom"),
    corner("More than usual, seats to spare", 1, 0, "right", "bottom"),
    list(text = sprintf("near full (%s%%)", format(plot_data$near_full_pct)), x = 1, xref = "paper",
         y = plot_data$near_full_pct, yref = "y", xanchor = "right", yanchor = "bottom",
         showarrow = FALSE, font = list(size = 11, color = guide)))

  p %>%
    plotly::layout(
      xaxis = list(title = "Census enrollment against its usual (log scale)", type = "log",
                   range = x_range, tickvals = steps, ticktext = tick_text, zeroline = FALSE,
                   showgrid = FALSE),
      yaxis = list(title = "Seats filled at census", ticksuffix = "%", range = c(0, y_max),
                   zeroline = FALSE, gridcolor = "#ECEFEC"),
      shapes = list(
        list(type = "line", xref = "paper", x0 = 0, x1 = 1, y0 = plot_data$near_full_pct,
             y1 = plot_data$near_full_pct, line = list(color = guide, width = 1, dash = "dash")),
        list(type = "line", x0 = 0, x1 = 0, yref = "paper", y0 = 0, y1 = 1,
             line = list(color = guide, width = 1, dash = "dot"))),
      annotations = c(guides, labels),
      legend = list(orientation = "h", x = 0, y = -0.2, itemsizing = "constant",
                    groupclick = "toggleitem"),
      margin = list(t = 20, r = 20, b = 110, l = 65),
      hoverlabel = list(align = "left")
    ) %>%
    plotly::config(displaylogo = FALSE)
}
