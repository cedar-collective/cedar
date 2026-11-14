# registration-watch.R — Which registrations are worth a look, ranked?
#
# Regstats runs several screens, each against a course's own history: an
# enrollment bump or dip, students still waiting, fill (near full now, near
# full in most earlier terms, fuller than usual) and early or late drops. Read
# one at a time they mislead: a dip reads as falling demand until the same
# course is also near full, when it says the seats fell. This feature reads them together.
#
#   build_registration_watch()   one row per course the screens flagged, its
#                                flags, the pattern they make, the students
#                                behind it; a roll-up by college
#   format_registration_watch()  the payload as text (text-first preview)
#
# A row is a term, campus, college, course and part of term, the grain every
# Regstats table is reported at, so a course is never read across campuses
# (campus-policy.md). Each row gets the first pattern in
# REGISTRATION_WATCH_PATTERNS its flags satisfy. "Usually near full" (near
# full now and in most earlier terms, or in most earlier terms only, with
# nothing else unusual) is a state, not news: it is counted in `meta` and left out of the
# list unless opt$include_known is TRUE.
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
# Nothing is recounted: every number is the Regstats payload's. The screens'
# thresholds are the run's (`flagged$thresholds`), recorded in `meta`. A
# renumbered course is one course here because Regstats keys on course_id
# (a confirmed code_history.csv rename); an unconfirmed one has no baseline
# under its new code and no current rows under its old, so neither is flagged.
#
# Depends on: get_reg_stats() output (features/regstats.R)
#             fmt_term() (trunk/utils.R)

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
#'   rows), and `thresholds`.
#' @param opt `include_known` (default FALSE: "usually near full" rows are counted,
#'   not listed).
#' @return A list: `courses` (one row per flagged term, campus, college,
#'   course and part of term: the flags as logical columns, `n_screens`,
#'   `pattern`, `label`, `sentence`, `students`, and the evidence:
#'   `census_enrl`, `census_enrl_mean`, `waiting`, `capacity`, `fill_rate`,
#'   `drops_beyond`), ordered by pattern, then students, then screens;
#'   `rollup` (college x pattern: `courses`, `students`, `examples`); `meta`
#'   (`terms`, `campuses`, `n_flagged`, `n_listed`, `n_usually_full`,
#'   `include_known`, `thresholds`).
build_registration_watch <- function(flagged, opt = list()) {
  if (!is.list(flagged)) stop("[registration-watch.R] flagged must be the get_reg_stats() list", call. = FALSE)
  include_known <- isTRUE(opt$include_known)
  key <- .REGISTRATION_WATCH_KEY
  bumps <- .registration_watch_frame(flagged, "bumps", c("census_enrl", "census_enrl_mean", "impacted"))
  dips  <- .registration_watch_frame(flagged, "dips",  c("census_enrl", "census_enrl_mean", "impacted"))
  waits <- .registration_watch_frame(flagged, "waits", "waiting")
  sat   <- .registration_watch_frame(flagged, "sat", c("census_enrl", "capacity", "fill_rate",
                                                       "is_full_now", "is_chronic_hist", "is_running_hot"))
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
    dplyr::left_join(pick(bumps, c("census_enrl", "census_enrl_mean", "impacted"),
                          c("bump_enrl", "bump_mean", "bump_beyond")), by = key) %>%
    dplyr::left_join(pick(dips, c("census_enrl", "census_enrl_mean", "impacted"),
                          c("dip_enrl", "dip_mean", "dip_beyond")), by = key) %>%
    dplyr::left_join(pick(waits, "waiting"), by = key) %>%
    dplyr::left_join(pick(sat, c("census_enrl", "capacity", "fill_rate", "is_full_now",
                                 "is_chronic_hist", "is_running_hot"),
                          c("sat_enrl", "capacity", "fill_rate", "full_now", "usually_full", "running_hot")),
                     by = key) %>%
    dplyr::left_join(pick(early, "impacted", "early_beyond"), by = key) %>%
    dplyr::left_join(pick(late, "impacted", "late_beyond"), by = key) %>%
    dplyr::mutate(
      full_now = full_now %in% TRUE, usually_full = usually_full %in% TRUE,
      running_hot = running_hot %in% TRUE,
      n_screens = bump + dip + waitlist + full_now + usually_full + running_hot + early_drops + late_drops,
      census_enrl = dplyr::coalesce(bump_enrl, dip_enrl, sat_enrl),
      census_enrl_mean = dplyr::coalesce(bump_mean, dip_mean),
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
                  students, census_enrl, census_enrl_mean, waiting, capacity, fill_rate, drops_beyond)
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
  near_full <- m$thresholds[["chronic_fill_rate"]]
  if (!is.numeric(near_full) || length(near_full) != 1 || is.na(near_full)) {
    stop("[registration-watch.R] payload$meta$thresholds lacks chronic_fill_rate", call. = FALSE)
  }
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
