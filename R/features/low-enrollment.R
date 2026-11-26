# low-enrollment.R — Courses > Low Enrollment: which sections are under their threshold?
#
# What the page draws. The counting is R/branches/enrl.R's
# (classify_low_enrollment_terms(), build_low_enrollment_alerts(),
# get_enrollment_concerns(), collect_low_enrollment_threshold_rows()); this
# file chooses which view the chosen terms get, and shapes the rows, the band
# counts and the page's words. No Shiny, and no table but the ones passed in.
#
# The views (`page$mode`):
#   "alerts"    a term with registrations: each active section's class against
#               the threshold for its level.
#   "concerns"  a term nobody has registered for yet, shown as a schedule
#               check: each scheduled course's average over its last
#               same-season terms against the same threshold.
#   "mixed"     terms of both kinds were chosen. The two views do not share
#               columns, so there are no rows and the page says why.
#
# The thresholds are part of a run, like its terms: the rows are fetched,
# kept, banded and coloured under the thresholds the run was given, and a
# changed threshold takes effect at the next run. (The page this replaced
# re-filtered a finished run under its live inputs, so a raised threshold
# showed a list missing rows it had never fetched.)
#
# One band a row. A section's band is the one build_low_enrollment_alerts()
# stored (`severity`): its class, which for a crosslisted section is the
# combined class, against its own level's threshold. The cards count that band
# and the table colours it, as the Dept Dashboard's review does.
#
#   build_low_enrollment_page()       the payload for one run
#   low_enrollment_has_rows()         whether the run lists anything
#   low_enrollment_level_rows()       one level tab's rows
#   low_enrollment_first_level()      the level tab a run opens on
#   summarize_low_enrollment_bands()  how many listed rows sit in each band
#   low_enrollment_summary_cards()    those counts as the page's cards
#   low_enrollment_display_table()    a tab's rows as its table shows them
#   low_enrollment_download_table()   the listed rows as the CSV holds them
#   describe_low_enrollment_scope()   the facts the scope bar states
#   low_enrollment_view_notes()       the caveats above the list, when there are any
#   low_enrollment_mixed_terms_note() why terms of two kinds give no list
#   low_enrollment_empty_note()       what an empty list means
#   low_enrollment_section_words()    the section's title and sentence
#   low_enrollment_method_notes()     how the list is counted, in paragraphs

# The level tabs the page splits its rows into, each with its tab's name.
# "split" is a crosslist that spans the undergraduate / graduate boundary.
LOW_ENROLLMENT_LEVELS <- c(lower = "Lower", upper = "Upper", split = "Split", grad = "Graduate")

# A schedule check and a section's history line both look at this many of the
# course's earlier same-season terms.
LOW_ENROLLMENT_HISTORY_TERMS <- 4L

# History lines are added only to a list this long or shorter: a longer one is
# a scan of a college or a campus, and the page says the history was left out.
LOW_ENROLLMENT_HISTORY_LIMIT <- 500L

# The column each view judges against the threshold, and so the one coloured.
LOW_ENROLLMENT_JUDGED_COLUMN <- c(alerts = "XL Total", concerns = "Hist Avg")

LOW_ENROLLMENT_SPLIT_NOTE <- paste0(
  "Crosslisted courses that span the undergraduate and graduate levels: at least one ",
  "section numbered 499 or lower and one numbered 500 or higher. Split Partners names ",
  "every course in the group, and XL Total is the group's combined class.")

#' The Low Enrollment page's payload for one run
#'
#' @param sections cedar_sections.
#' @param opt The scope, in `filter_DESRs()` names: `term` (required, at least
#'   one), `course_campus`, `course_college`, `dept_code`, `pt`, `im`, `level`.
#'   Active sections only and the excluded-course list always apply.
#' @param thresholds Named thresholds (`lower`, `upper`, `split`, `grad`), each
#'   a number; NULL for the standard ones.
#' @param min_enrl Smallest section a registrations view lists (1 leaves out
#'   active sections nobody is in). A schedule check does not read it.
#' @param current_term `cedar_current_term`: a later term with no
#'   registrations is a schedule.
#' @param min_days_after_start The edges' `min_days_after_start`: counts pulled
#'   sooner than this after a term's start are still moving.
#' @param history_limit The longest list of sections that gets history lines.
#' @return A list: `mode` ("alerts", "concerns" or "mixed"); `term_views` (one
#'   row per chosen term, from `classify_low_enrollment_terms()`); `review`
#'   (the rows the page lists, each with `.threshold`, `.level_group` and
#'   `.band`; NULL when there are none, or the terms are mixed);
#'   `history_skipped` (TRUE when the list was too long for history lines);
#'   and `history_limit`, `thresholds`, `min_enrl` and `opt` as run.
build_low_enrollment_page <- function(sections, opt, thresholds = NULL, min_enrl = 1L,
                                      current_term, min_days_after_start,
                                      history_limit = LOW_ENROLLMENT_HISTORY_LIMIT) {
  if (length(opt[["term"]]) == 0) {
    stop("[low-enrollment.R] build_low_enrollment_page() needs at least one term in opt$term.")
  }
  thresholds <- normalize_low_enrollment_thresholds(thresholds)
  if (anyNA(thresholds) || any(thresholds < 1)) {
    stop("[low-enrollment.R] Every threshold is a number of students, 1 or more. Got: ",
         paste(names(thresholds), thresholds, sep = " = ", collapse = ", "), ".")
  }
  if (length(min_enrl) != 1 || is.na(min_enrl) || min_enrl < 0) {
    stop("[low-enrollment.R] min_enrl is one number, 0 or more.")
  }
  opt$status <- "A"
  opt$uel <- TRUE

  term_views <- classify_low_enrollment_terms(sections, opt[["term"]], current_term,
                                              min_days_after_start)
  views <- unique(term_views$view)
  mode <- if (length(views) > 1) "mixed" else views

  rows <- switch(mode,
    mixed = NULL,
    concerns = get_enrollment_concerns(sections, opt, n_history_terms = LOW_ENROLLMENT_HISTORY_TERMS),
    alerts = build_low_enrollment_alerts(
      sections, opt,
      thresholds     = thresholds,
      include_buffer = TRUE,
      min_enrl       = min_enrl,
      add_history    = TRUE,
      history_limit  = history_limit,
      max_term       = current_term
    ))

  list(
    mode = mode, term_views = term_views,
    review = .low_enrollment_review(rows, thresholds, mode),
    history_skipped = identical(mode, "alerts") && !is.null(rows) && nrow(rows) > history_limit,
    history_limit = history_limit,
    thresholds = thresholds, min_enrl = min_enrl, opt = opt
  )
}

# The rows the page lists: every level group's rows under the run's
# thresholds, each with the threshold it was judged against, its level tab and
# its band. NULL when there are none.
.low_enrollment_review <- function(rows, thresholds, mode) {
  if (is.null(rows) || nrow(rows) == 0) return(NULL)
  review <- dplyr::ungroup(
    collect_low_enrollment_threshold_rows(rows, thresholds = thresholds, mode = mode))
  if (nrow(review) == 0) return(NULL)
  # collect_low_enrollment_threshold_rows() keeps a split crosslist in the
  # split group alone, whatever its sections' levels.
  review$.level_group <- dplyr::if_else(dplyr::coalesce(review$is_split, FALSE), "split",
                                        as.character(review$level))
  review$.band <- .low_enrollment_row_bands(review, mode)
  review
}

# The band each listed row is counted and coloured in.
#
# A registrations view reads the band the builder stored. A schedule check
# judges the course's same-season average, as shares of its threshold: under
# half, half to three quarters, up to the threshold, and at or over it (rows
# listed because they are within five students of it). A course with no
# same-season history has no average and is its own band, never a zero.
.low_enrollment_row_bands <- function(review, mode) {
  needed <- if (identical(mode, "concerns")) c("avg_enrl", "n_prior_terms", ".threshold") else "severity"
  missing_cols <- setdiff(needed, names(review))
  if (length(missing_cols) > 0) {
    stop("[low-enrollment.R] the ", mode, " rows have no column(s): ",
         paste(missing_cols, collapse = ", "))
  }
  if (!identical(mode, "concerns")) return(as.character(review$severity))
  dplyr::case_when(
    review$n_prior_terms == 0                  ~ "no_history",
    review$avg_enrl < review$.threshold * 0.5  ~ "critical",
    review$avg_enrl < review$.threshold * 0.75 ~ "warning",
    review$avg_enrl < review$.threshold        ~ "watch",
    TRUE                                       ~ "buffer"
  )
}

# Whether a run lists anything.
low_enrollment_has_rows <- function(page) {
  !is.null(page$review) && nrow(page$review) > 0
}

#' One level tab's rows
#'
#' @param page A `build_low_enrollment_page()` payload.
#' @param level One of `names(LOW_ENROLLMENT_LEVELS)`.
#' @return That level's listed rows (possibly none); NULL when the run lists nothing.
low_enrollment_level_rows <- function(page, level) {
  if (length(level) != 1 || !level %in% names(LOW_ENROLLMENT_LEVELS)) {
    stop("[low-enrollment.R] low_enrollment_level_rows() needs one level of: ",
         paste(names(LOW_ENROLLMENT_LEVELS), collapse = ", "), ".")
  }
  if (!low_enrollment_has_rows(page)) return(NULL)
  page$review[page$review$.level_group == level, , drop = FALSE]
}

#' How many listed rows sit in each band
#'
#' @param page A `build_low_enrollment_page()` payload that lists rows.
#' @return A named list of counts: `critical`, `warning`, `watch`, `buffer`,
#'   `total`; plus `no_history` for a schedule check, and `students` (the
#'   listed sections' own students) and `mean_enrolled` for a registrations view.
summarize_low_enrollment_bands <- function(page) {
  if (!low_enrollment_has_rows(page)) {
    stop("[low-enrollment.R] summarize_low_enrollment_bands() needs a run that lists rows.")
  }
  review <- page$review
  counts <- list(
    critical = sum(review$.band == "critical"),
    warning  = sum(review$.band == "warning"),
    watch    = sum(review$.band == "watch"),
    buffer   = sum(review$.band == "buffer"),
    total    = nrow(review)
  )
  if (identical(page$mode, "concerns")) {
    counts$no_history <- sum(review$.band == "no_history")
  } else {
    counts$students <- sum(review$enrolled, na.rm = TRUE)
    counts$mean_enrolled <- mean(review$enrolled, na.rm = TRUE)
  }
  counts
}

#' The level tab a run opens on: the first that has rows
#'
#' @param page A `build_low_enrollment_page()` payload with rows.
#' @return One of the names of `LOW_ENROLLMENT_LEVELS`.
low_enrollment_first_level <- function(page) {
  if (!low_enrollment_has_rows(page)) {
    stop("[low-enrollment.R] low_enrollment_first_level() needs a run that listed rows.")
  }
  levels <- names(LOW_ENROLLMENT_LEVELS)
  listed <- levels[levels %in% page$review$.level_group]
  if (length(listed) == 0) {
    stop("[low-enrollment.R] No listed row belongs to a level tab: ",
         paste(unique(page$review$.level_group), collapse = ", "))
  }
  listed[[1]]
}

#' The band counts as the page's row of cards
#'
#' @param counts `summarize_low_enrollment_bands()` output.
#' @param mode "alerts" or "concerns".
#' @return Tibble, one row per card in display order: `key`, `value` (as
#'   shown), `label`, `note` (the line under the label: a band's range, or
#'   what a total counts) and `tone` (the band's colour; NA for a plain card).
low_enrollment_summary_cards <- function(counts, mode) {
  whole <- function(n) format(n, big.mark = ",", trim = TRUE)
  if (identical(mode, "concerns")) {
    keys <- c("critical", "warning", "watch", "buffer", "no_history", "total")
    tibble::tibble(
      key   = keys,
      value = vapply(counts[keys], whole, character(1)),
      label = c("Historically Low", "Borderline", "Watch", "Near Threshold",
                "No Same-Season History", "Total Courses"),
      note  = c("under 50% of threshold", "50–75% of threshold", "75–100% of threshold",
                "at or over threshold", "nothing to compare with", "in this list"),
      tone  = c("critical", "warning", "info", "success", "neutral", NA_character_)
    )
  } else if (identical(mode, "alerts")) {
    keys <- c("critical", "warning", "watch", "buffer", "total", "students")
    tibble::tibble(
      key   = c(keys, "mean_enrolled"),
      value = c(vapply(counts[keys], whole, character(1)),
                formatC(counts$mean_enrolled, format = "f", digits = 2)),
      label = c("Critical", "Warning", "Watch", "Monitor",
                "Total Sections", "Total Students", "Avg Enrollment"),
      # The totals count each listed section's own students, where the bands
      # judge its class (the combined class for a crosslist).
      note  = c("under 50% of threshold", "50–75% of threshold", "75–100% of threshold",
                "over threshold", "in this list", "each section's own",
                "own students a section"),
      tone  = c("critical", "warning", "info", "success", NA_character_, NA_character_,
                NA_character_)
    )
  } else {
    stop("[low-enrollment.R] low_enrollment_summary_cards() has no cards for mode '", mode, "'.")
  }
}

#' A level tab's rows as its table shows them
#'
#' Picks the columns, names them for a reader and puts the smallest first.
#' Nothing is recounted. A section with no history line shows an em dash; a
#' scheduled course with no same-season history lists where else it has run.
#'
#' @param rows `low_enrollment_level_rows()` output.
#' @param mode "alerts" or "concerns".
#' @param split_partners TRUE on the Split tab: adds the partner sections of
#'   each crosslist when the rows carry them (`split_sections`).
#' @return Tibble in display order with display names, then `.band` (each
#'   row's band, for the table's colour; not a column to show). NULL when
#'   there are no rows.
low_enrollment_display_table <- function(rows, mode, split_partners = FALSE) {
  if (is.null(rows) || nrow(rows) == 0) return(NULL)
  needed <- if (identical(mode, "concerns")) {
    c("campus", "department", "subject_course", "course_title", "n_sections", "avg_enrl",
      "trend", "n_prior_terms", "history_text", "other_history_text", ".band")
  } else if (identical(mode, "alerts")) {
    c("campus", "department", "subject_course", "section", "course_title", "term",
      "n_sections", "enrolled", "total_enrl", "course_enrl", "history_text", ".band")
  } else {
    stop("[low-enrollment.R] low_enrollment_display_table() has no table for mode '", mode, "'.")
  }
  missing_cols <- setdiff(needed, names(rows))
  if (length(missing_cols) > 0) {
    stop("[low-enrollment.R] low_enrollment_display_table() needs column(s): ",
         paste(missing_cols, collapse = ", "))
  }
  with_partners <- isTRUE(split_partners) && "split_sections" %in% names(rows)
  partners <- if (with_partners) c(`Split Partners` = "split_sections")

  if (mode == "concerns") {
    rows %>%
      dplyr::ungroup() %>%
      dplyr::mutate(history_text = dplyr::if_else(
        is.na(other_history_text), history_text,
        paste0(history_text, "; other offerings: ", other_history_text))) %>%
      dplyr::select(
        Campus = campus, Department = department, Course = subject_course,
        dplyr::all_of(partners), Title = course_title, Sects = n_sections,
        `Hist Avg` = avg_enrl, Trend = trend, `# Terms` = n_prior_terms,
        `Prior History` = history_text, .band
      ) %>%
      dplyr::arrange(`Hist Avg`)
  } else {
    rows %>%
      dplyr::ungroup() %>%
      dplyr::mutate(history_text = dplyr::if_else(is.na(history_text), "—", history_text)) %>%
      dplyr::select(
        Campus = campus, Dept = department, Course = subject_course, `Sect#` = section,
        dplyr::all_of(partners), Title = course_title, Term = term, Sects = n_sections,
        Enrolled = enrolled, `XL Total` = total_enrl, `Course Total` = course_enrl,
        `Prior History` = history_text, .band
      ) %>%
      dplyr::arrange(Enrolled)
  }
}

#' The listed rows as the download holds them
#'
#' Every column the run carries, with the per-term history table (a list
#' column a CSV cannot hold) left out; its text stays in `history_text`.
low_enrollment_download_table <- function(page) {
  if (!low_enrollment_has_rows(page)) {
    stop("[low-enrollment.R] low_enrollment_download_table() needs a run that lists rows.")
  }
  dplyr::select(page$review, -dplyr::any_of("history"))
}

# "low_enrollment_HIST_202680_2026-11-26.csv": the run's departments and terms, then the date.
low_enrollment_download_name <- function(page, date = Sys.Date()) {
  scope <- c(if (length(page$opt[["dept_code"]]) > 0) paste(page$opt[["dept_code"]], collapse = "-"),
             paste(page$opt[["term"]], collapse = "-"))
  paste0(paste(c("low_enrollment", scope, as.character(date)), collapse = "_"), ".csv")
}

# A chosen term as a reader names it: "Spring 2027" for a term code, and
# "fall terms" for a term type, which stands for every term of that season.
.low_enrollment_term_labels <- function(terms) {
  vapply(as.character(terms), function(term) {
    if (grepl("^\\d{6}$", term)) term_code_to_str(term) else paste(term, "terms")
  }, character(1), USE.NAMES = FALSE)
}

# "Oct 23, 2026"
.low_enrollment_date <- function(date) {
  paste0(format(date, "%b "), as.integer(format(date, "%d")), format(date, ", %Y"))
}

# "Spring 2027 (pulled Oct 23, 2026)" for each of the given terms.
.low_enrollment_pull_labels <- function(term_views) {
  paste0(.low_enrollment_term_labels(term_views$term), " (pulled ",
         vapply(seq_len(nrow(term_views)),
                function(i) .low_enrollment_date(term_views$pulled_on[[i]]), character(1)),
         ")")
}

#' The facts the scope bar states for a run
#'
#' @param page A `build_low_enrollment_page()` payload.
#' @return A named list, one short value per chip, in display order: the
#'   view, the filters the run was made with (`Scope`), the terms and their
#'   pulls, the thresholds (with the smallest section a list of sections
#'   keeps) and how many are listed. A chip that does not apply to the view is
#'   absent.
describe_low_enrollment_scope <- function(page) {
  described <- list(
    View = switch(page$mode,
      alerts = "Sections, by registrations",
      concerns = "Schedule check, by each course's history",
      mixed = "None: terms of two kinds"),
    Scope = .low_enrollment_scope_words(page$opt),
    Terms = paste(.low_enrollment_pull_labels(page$term_views), collapse = "; ")
  )
  if (identical(page$mode, "mixed")) return(described)
  described$Thresholds <- paste(LOW_ENROLLMENT_LEVELS[names(page$thresholds)], page$thresholds,
                                collapse = ", ")
  if (identical(page$mode, "alerts")) {
    described$Thresholds <- paste0(described$Thresholds, " · smallest section listed ",
                                   format(page$min_enrl, trim = TRUE))
  }
  listed <- if (low_enrollment_has_rows(page)) nrow(page$review) else 0L
  thing <- if (identical(page$mode, "concerns")) "course" else "section"
  described$Listed <- paste(format(listed, big.mark = ",", trim = TRUE),
                            if (listed == 1L) thing else paste0(thing, "s"))
  described
}

# The filters a run was made with, as one line: the campuses and departments
# always (an empty choice is every one of them), the rest only when chosen.
.low_enrollment_scope_words <- function(opt) {
  chosen <- function(key) {
    value <- opt[[key]]
    value <- value[!is.na(value) & nzchar(as.character(value))]
    if (length(value) == 0) NULL else paste(value, collapse = ", ")
  }
  level <- opt[["level"]]
  level <- level[!is.na(level) & nzchar(as.character(level))]
  unknown <- setdiff(level, names(LOW_ENROLLMENT_LEVELS))
  if (length(unknown) > 0) {
    stop("[low-enrollment.R] Unknown level in the run's filters: ", paste(unknown, collapse = ", "))
  }
  parts <- c(
    if (is.null(chosen("course_campus"))) "All campuses" else paste("Campus", chosen("course_campus")),
    if (!is.null(chosen("course_college"))) paste("College", chosen("course_college")),
    if (is.null(chosen("dept_code"))) {
      if (is.null(chosen("course_college"))) "All departments"
    } else {
      paste("Department", chosen("dept_code"))
    },
    if (length(level) > 0) paste("Level", paste(LOW_ENROLLMENT_LEVELS[level], collapse = ", ")),
    if (!is.null(chosen("pt"))) paste("Part of term", chosen("pt")),
    if (!is.null(chosen("im"))) paste("Method", chosen("im"))
  )
  paste(parts, collapse = " · ")
}

#' The caveats that change how a run's list is read
#'
#' A schedule check is not a count of students; counts pulled before a term's
#' registration settled can still move; and a list too long for history lines
#' has none. Each is said above the list.
#'
#' @param page A `build_low_enrollment_page()` payload.
#' @return A list of notes, each a list with `lead` (said in bold) and `text`;
#'   empty when the run needs none.
low_enrollment_view_notes <- function(page) {
  if (identical(page$mode, "concerns")) {
    terms <- paste(.low_enrollment_term_labels(page$term_views$term), collapse = " and ")
    season <- paste(unique(vapply(page$term_views$term, get_term_type, character(1))),
                    collapse = " or ")
    return(list(list(
      lead = paste0("Schedule check: ", terms, " has no registrations yet. "),
      text = paste0(
        "Each scheduled course is compared with its own enrollment in its last ",
        LOW_ENROLLMENT_HISTORY_TERMS, " ", season, " terms on the same campus. ",
        "Courses in the green band have met the threshold but sit near it. A course with no ",
        season, " history there lists where else it has run.")
    )))
  }
  if (!identical(page$mode, "alerts")) return(list())
  notes <- list()
  moving <- page$term_views[page$term_views$view == "alerts" &
                              page$term_views$registration_open %in% TRUE, ]
  if (nrow(moving) > 0) {
    notes <- c(notes, list(list(
      lead = "Registration had not settled when these counts were pulled. ",
      text = paste0(
        "Counts for ", paste(.low_enrollment_pull_labels(moving), collapse = " and "),
        " come from a pull made before registration settled, so sections can still ",
        "gain or lose students. Compare each section with its history before acting.")
    )))
  }
  if (isTRUE(page$history_skipped)) {
    notes <- c(notes, list(list(
      lead = "This list is too long for each section's history. ",
      text = paste0(
        "A run that lists more than ", page$history_limit, " sections leaves the ",
        "Prior History column empty. Choose a college or a department to see it.")
    )))
  }
  notes
}

#' Why terms of two kinds give no list
#'
#' @param page A `build_low_enrollment_page()` payload whose mode is "mixed".
#' @return One paragraph naming which chosen terms get which view.
low_enrollment_mixed_terms_note <- function(page) {
  named <- function(view) {
    paste(.low_enrollment_term_labels(page$term_views$term[page$term_views$view == view]),
          collapse = " and ")
  }
  paste0(
    "These terms need two different lists. Nobody has registered for ", named("concerns"),
    " yet: that gets a schedule check, each scheduled course against its own history. ",
    "Registrations are in for ", named("alerts"), ": that gets a list of sections. ",
    "Choose one kind and run again."
  )
}

#' What an empty list means, for the view that ran
low_enrollment_empty_note <- function(page) {
  if (identical(page$mode, "concerns")) {
    return(paste0(
      "Nothing to review. No course scheduled in this scope has averaged under its threshold, ",
      "or within five students of it, and none is without same-season history."))
  }
  paste0("Nothing to review. No active section in this scope is at its threshold, under it, ",
         "or within a quarter above it.")
}

#' The section's title and its one sentence, for a view
#'
#' Its plain account of what it shows is its paragraph in
#' docs/_data/concepts.yml, which the module names.
low_enrollment_section_words <- function(mode) {
  if (identical(mode, "concerns")) {
    list(title = "Scheduled courses that have run small",
         sentence = paste0("Each scheduled course whose earlier terms averaged at or near the ",
                           "threshold for its level, smallest first."))
  } else if (identical(mode, "alerts")) {
    list(title = "Sections at or near their threshold",
         sentence = paste0("Each active section whose class is at, under or just over the ",
                           "threshold for its level, smallest first."))
  } else {
    stop("[low-enrollment.R] low_enrollment_section_words() has no section for mode '", mode, "'.")
  }
}

#' How the list on screen is counted, one paragraph an item
#'
#' @param page A `build_low_enrollment_page()` payload (not mixed).
#' @return A character vector of paragraphs for the section's method slot.
low_enrollment_method_notes <- function(page) {
  thresholds <- paste(tolower(LOW_ENROLLMENT_LEVELS[names(page$thresholds)]), page$thresholds,
                      collapse = ", ")
  bands <- paste0(
    "The bands are shares of the row's own threshold: red under 50%, yellow 50% to 75%, ",
    if (identical(page$mode, "concerns")) "blue 75% up to it, green at or over it."
    else "blue 75% up to and at it, green over it.")
  if (identical(page$mode, "concerns")) {
    return(c(
      paste0("One row per scheduled course and campus, from active sections on the schedule ",
             "after the excluded-course list. Thresholds for this run: ", thresholds, "."),
      paste0("Hist Avg is the course's average combined enrollment over its last ",
             LOW_ENROLLMENT_HISTORY_TERMS, " terms of the same season on the same campus, and ",
             "is the number judged. A course is listed when that average is under its ",
             "threshold or within five students of it, or when it has no such history."),
      paste0(bands, " A course with no same-season history has no average: it is gray, ",
             "counted on its own card, and its Prior History lists its latest offerings in ",
             "other seasons, on other campuses or as other topics, which never set the average."),
      paste0("Sects is the number of scheduled home sections. Trend is the direction of a ",
             "straight line through the earlier terms. # Terms is how many of them there were.")
    ))
  }
  c(
    paste0("One row per active section, after the excluded-course list. Thresholds for this ",
           "run: ", thresholds, ". ",
           if (page$min_enrl <= 0) "Sections with no students are listed too."
           else if (page$min_enrl == 1) "Sections with no students are left out."
           else paste0("Sections with fewer than ", format(page$min_enrl, trim = TRUE),
                       " students are left out.")),
    paste0("XL Total is the number judged: the section's own students, or for a crosslisted ",
           "section the combined class across its partners. A section is listed when that is ",
           "at or under its threshold, or within a quarter above it."),
    bands,
    paste0("Enrolled is the section's own students, and the cards' Total Students and Avg ",
           "Enrollment add those up. Sects is the number of active home sections of the course ",
           "that term, and Course Total their combined classes."),
    paste0("Prior History is the course's enrollment in its last ", LOW_ENROLLMENT_HISTORY_TERMS,
           " earlier terms. A run that lists more than ", page$history_limit,
           " sections leaves it out.")
  )
}
