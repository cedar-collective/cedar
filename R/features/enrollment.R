# App-facing enrollment payloads ---------------------------------------------

#' Check whether an Enrollment request has a narrowing filter
#'
#' Bird's Eye > Enrollment can otherwise scan the full section and class-list
#' histories in one Shiny worker. Any selected filter may establish the scope,
#' except Level: undergraduate is the page default and is too broad to protect
#' the shared worker by itself.
#'
#' @param college Selected college code(s).
#' @param dept_codes Selected department code(s).
#' @param campus Selected delivery campus code(s).
#' @param term Selected term code(s) or term type(s).
#' @param part_term Selected part-of-term value(s).
#' @param subject Selected subject prefix(es).
#' @param course Selected course code(s).
#' @param instructor Selected instructor name(s).
#' @param delivery_method Selected instructional method(s).
#' @param gen_ed Selected general-education area(s).
#' @param level Selected level value(s), intentionally ignored by the guard.
#' @return A single logical value.
enrollment_scope_is_ready <- function(college = NULL, dept_codes = NULL,
                                      campus = NULL, term = NULL,
                                      part_term = NULL, subject = NULL,
                                      course = NULL, instructor = NULL,
                                      delivery_method = NULL, gen_ed = NULL,
                                      level = NULL) {
  has_value <- function(x) {
    x <- trimws(as.character(unlist(x, use.names = FALSE)))
    any(!is.na(x) & nzchar(x))
  }
  filters <- list(
    college, dept_codes, campus, term, part_term, subject, course,
    instructor, delivery_method, gen_ed
  )
  any(vapply(filters, has_value, logical(1)))
}

#' Expand the Enrollment page's convenient level groups
#'
#' The stored section levels remain `lower`, `upper`, and `grad`. The UI's
#' `undergrad` choice is a compact alias for the two undergraduate values so it
#' can be the safe default without changing the canonical data vocabulary.
#'
#' @param levels Selected UI level value(s).
#' @return Canonical section level values, or NULL when no level was selected.
resolve_enrollment_levels <- function(levels = NULL) {
  if (is.null(levels) || length(levels) == 0) return(NULL)
  levels <- trimws(as.character(unlist(levels, use.names = FALSE)))
  levels <- levels[!is.na(levels) & nzchar(levels)]
  if (length(levels) == 0) return(NULL)
  if ("undergrad" %in% levels) {
    levels <- c(setdiff(levels, "undergrad"), "lower", "upper")
  }
  unique(levels)
}

#' Attach class-list counts to the Enrollment page's section rows
#'
#' The Enrollment table's rows are the schedule's sections, chosen by the page's
#' filters (instructor, method, part of term and the rest, which a course-term
#' table cannot answer), so its student counts come from the class list, by
#' section. This is one of the deliberate class-list counts beside
#' `cedar_course_terms` (AGENTS.md, CEDAR Data Tables). A class-list row sits in
#' exactly one section, so the section rows of a course add up to its course
#' row and any grouping above the section is a sum.
#'
#' Only offered sections are kept (`keep_offered_sections()`: active, with
#' seats or students); a placeholder with neither is not an offering. A section
#' the class list has no row for keeps NA counts: no one has registered (or, for
#' a term not yet pulled, the class list has nothing to say), never zero.
#'
#' A crosslisted section's own count is one listing's students. The primary
#' listing's row (the home listing, or the one a same-subject group counts first) also carries the whole offering's count (`xl_registered`,
#' `xl_dr_early`, `xl_dr_late`, `xl_census_enrl`, `xl_first_day_enrl`): its own
#' students plus those of every offered partner listing in its crosslist group
#' (term, campus, `crosslist_group`), read from the whole schedule, so partners
#' outside the page's filters are counted. `xl_listings` says how many listings
#' that is. A view that shows the home row in place of its partners reads
#' these (`summarize_enrollment_view()`), so its class-list counts and the
#' schedule's combined total (`total_enrl`) describe the same students. A
#' student with a row under two listings (moved between them, or dropped both)
#' is counted once, by the status `STATUS_PRECEDENCE` ranks first.
#'
#' @param sections Section rows from `get_enrl()` with no `group_cols`, carrying
#'   `term`, `crn`, `enrolled`, `available` and `crosslist_code`.
#' @param students Class-list rows (`cedar_registrations`); only those in
#'   `sections` are read.
#' @param schedule `cedar_sections`, for each section's status and first class
#'   day, which `get_enrl()` does not return.
#' @return list(rows = the offered section rows with `registered`, `dr_early`,
#'   `dr_late`, `census_enrl`, `first_day_enrl`, `first_day_basis`, `seats`,
#'   `seats_known`, `crosslisted` and, on a crosslist group's primary row, the
#'   `xl_*` counts and `xl_listings` (NA elsewhere); n_placeholders = section
#'   rows dropped as not offered).
attach_enrollment_section_counts <- function(sections, students, schedule) {
  need <- c("term", "crn", "enrolled", "available", "crosslist_code")
  missing <- setdiff(need, names(sections))
  if (length(missing) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): sections lack ",
         paste(missing, collapse = ", "))
  }
  need <- c(need, "campus", "crosslist_role", "crosslist_primary")
  missing <- setdiff(need, names(sections))
  if (length(missing) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): sections lack ",
         paste(missing, collapse = ", "))
  }
  missing <- setdiff(c("term", "crn", "campus", "status", "enrolled", "available",
                       "total_enrl", "start_date", "crosslist_group", "college", "subject_course"), names(schedule))
  if (length(missing) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): schedule lacks ",
         paste(missing, collapse = ", "))
  }

  sections <- dplyr::ungroup(sections)
  # Only the terms on the page: the schedule and the class list are filtered
  # by term (an integer test) before any join reads them.
  terms <- unique(sections$term)
  schedule <- schedule %>% dplyr::ungroup() %>% dplyr::filter(term %in% terms)
  students <- students %>% dplyr::ungroup() %>% dplyr::filter(term %in% terms)
  offered_schedule <- keep_offered_sections(schedule)
  offered_keys <- offered_schedule %>% dplyr::distinct(term, crn)
  offered <- sections %>% dplyr::semi_join(offered_keys, by = c("term", "crn"))
  if (anyDuplicated(offered[c("term", "crn")]) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): a section (term, crn) ",
         "appears more than once; counts would be attached twice")
  }

  # Every offered listing of a crosslist group whose home row is on the page.
  group_key <- c("term", "campus", "crosslist_group")
  homes <- offered %>%
    dplyr::filter(crosslist_primary %in% TRUE) %>%
    dplyr::select(term, crn) %>%
    dplyr::inner_join(offered_schedule %>%
                        dplyr::filter(!is.na(crosslist_group)) %>%
                        dplyr::distinct(term, crn, campus, crosslist_group),
                      by = c("term", "crn"), relationship = "one-to-one") %>%
    dplyr::rename(home_crn = crn)
  listings <- offered_schedule %>%
    dplyr::distinct(term, crn, campus, crosslist_group) %>%
    dplyr::inner_join(homes, by = group_key, relationship = "many-to-one")

  scoped <- filter_classlist_to_sections(
    students, dplyr::bind_rows(offered %>% dplyr::select(term, crn),
                               listings %>% dplyr::select(term, crn))
  )
  if (nrow(scoped) > 0) {
    counts <- calc_cl_enrls(scoped, by_section = TRUE) %>%
      dplyr::ungroup() %>%
      dplyr::select(term, crn, registered, dr_early, dr_late, census_enrl)
    first_day <- calc_first_day_enrl(
      scoped,
      schedule %>%
        dplyr::ungroup() %>%
        dplyr::select(term, crn, start_date),
      by_section = TRUE
    ) %>%
      dplyr::select(term, crn, first_day_enrl, first_day_basis)
  } else {
    counts <- tibble::tibble(term = offered$term[0], crn = offered$crn[0],
                             registered = integer(), dr_early = integer(),
                             dr_late = integer(), census_enrl = integer())
    first_day <- tibble::tibble(term = offered$term[0], crn = offered$crn[0],
                                first_day_enrl = integer(),
                                first_day_basis = character())
  }

  # The offering behind each home row, counted as the Course Report counts a
  # crosslist family (get_course_crosslist_classlist_enrl()): every listing's
  # rows relabelled to the home listing, so calc_cl_enrls() keeps one row a
  # student, the one STATUS_PRECEDENCE ranks first. A student who dropped one
  # listing and registered under another is registered, once.
  empty_offering <- tibble::tibble(
    term = offered$term[0], crn = offered$crn[0], xl_listings = integer(),
    xl_registered = integer(), xl_dr_early = integer(), xl_dr_late = integer(),
    xl_census_enrl = integer(), xl_first_day_enrl = integer()
  )
  offering <- if (nrow(listings) == 0) empty_offering else {
    home_label <- offered_schedule %>%
      dplyr::semi_join(homes, by = c("term", "crn" = "home_crn")) %>%
      dplyr::distinct(term, home_crn = crn, .campus = campus, .college = college,
                      .course = subject_course)
    n_listings <- listings %>% dplyr::count(term, crn = home_crn, name = "xl_listings")
    pooled <- scoped %>%
      dplyr::inner_join(listings %>% dplyr::select(term, crn, home_crn),
                        by = c("term", "crn"), relationship = "many-to-one") %>%
      dplyr::inner_join(home_label, by = c("term", "home_crn"), relationship = "many-to-one") %>%
      dplyr::mutate(crn = home_crn, campus = .campus, college = .college, subject_course = .course)
    if (nrow(pooled) == 0) {
      dplyr::bind_rows(empty_offering, n_listings)
    } else {
      n_listings %>%
        dplyr::left_join(
          calc_cl_enrls(pooled, by_section = TRUE) %>%
            dplyr::ungroup() %>%
            dplyr::select(term, crn, xl_registered = registered, xl_dr_early = dr_early,
                          xl_dr_late = dr_late, xl_census_enrl = census_enrl),
          by = c("term", "crn"), relationship = "one-to-one") %>%
        dplyr::left_join(
          calc_first_day_enrl(pooled, schedule %>% dplyr::select(term, crn, start_date),
                              by_section = TRUE) %>%
            dplyr::select(term, crn, xl_first_day_enrl = first_day_enrl),
          by = c("term", "crn"), relationship = "one-to-one")
    }
  }

  rows <- offered %>%
    dplyr::left_join(counts, by = c("term", "crn"), relationship = "one-to-one") %>%
    dplyr::left_join(first_day, by = c("term", "crn"), relationship = "one-to-one") %>%
    dplyr::left_join(offering, by = c("term", "crn"), relationship = "one-to-one") %>%
    dplyr::mutate(
      seats = as.numeric(enrolled) + as.numeric(available),
      seats_known = is.finite(enrolled) & is.finite(available) & seats > 0,
      crosslisted = !is.na(crosslist_code) & !crosslist_code %in% c("0", "")
    )
  list(rows = rows, n_placeholders = nrow(sections) - nrow(offered))
}

# The crosslist views that show an offering once, on its home row.
ENROLLMENT_OFFERING_VIEWS <- c("home", "xl-home", "split")

#' Build one crosslist view of the Enrollment table
#'
#' Filters the counted section rows to a crosslist view, groups them at the
#' page's Group by grain, measures first-day fill, and applies Min/Max to
#' census. Census is the filter's count because it is one fixed point in every
#' term; the DESR count is a pull-time snapshot and stays a labelled column.
#' A row with no registrations has no census, so Min/Max cannot judge it: it is
#' kept, and counted in `n_no_registrations`.
#'
#' A grouped row's count is the sum over its sections; it is NA only when no
#' section has a class-list row. Its first day is a sum only when every
#' section's first day is known (the course-term rule, `cedar_course_terms`).
#' Fill is first-day enrollment over seats, judged by `enrollment_capacity_metrics()`,
#' and is withheld where seats are unknown or the row holds a crosslisted
#' section, whose seats are shared with the partner listing.
#'
#' @param section_rows `attach_enrollment_section_counts()$rows`.
#' @param opt `view` (a `filter_enrollment_crosslist_view()` view, default
#'   "home"), `group_cols` (NULL for one row per section), `enrl_min`,
#'   `enrl_max` (census bounds; NULL or NA for none).
#' In the views that leave a crosslisted offering's partner listings out (home,
#' xl-home and split), the row shown counts the whole offering (the `xl_*` counts);
#' every other view counts each listing's own students.
#' A row grouped by `subject_course` (and not by `course_title`) carries
#' `course_title`, its sections' most common title, and `n_titles`.
#'
#' @return list(rows, grouped, group_cols, n_before_filter, n_no_registrations).
summarize_enrollment_view <- function(section_rows, opt = list()) {
  view <- opt[["view"]] %||% "home"
  group_cols <- opt[["group_cols"]]
  grouped <- length(group_cols) > 0
  rows <- filter_enrollment_crosslist_view(section_rows, view)
  # A view that shows a crosslisted offering once, on its home row, counts the
  # whole offering there: the home listing's students and its partners'.
  if (view %in% ENROLLMENT_OFFERING_VIEWS && nrow(rows) > 0) {
    # Same-subject listings ("internal") each keep a row in the home views, so
    # there each counts its own students; Split Level shows the primary alone.
    whole <- !is.na(rows$xl_listings) & (view == "split" | rows$crosslist_role %in% "home")
    for (col in c("registered", "dr_early", "dr_late", "census_enrl", "first_day_enrl")) {
      rows[[col]][whole] <- rows[[paste0("xl_", col)]][whole]
    }
  }

  if (grouped) {
    missing <- setdiff(group_cols, names(rows))
    if (length(missing) > 0) {
      stop("[enrollment.R] summarize_enrollment_view(): cannot group by ",
           paste(missing, collapse = ", "))
    }
    sum_known <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
    schedule_side <- summarize_courses(rows, list(group_cols = group_cols)) %>%
      dplyr::ungroup() %>%
      dplyr::select(dplyr::all_of(group_cols), sections, xl_sections, enrolled, total_enrl)
    class_list_side <- rows %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) %>%
      dplyr::summarize(
        sections_matched = sum(!is.na(registered)),
        seats = sum(seats),
        seats_known = all(seats_known),
        crosslisted = any(crosslisted),
        first_day_enrl = if (any(is.na(first_day_enrl))) NA_real_ else sum(first_day_enrl),
        census_enrl = sum_known(census_enrl),
        registered = sum_known(registered),
        dr_early = sum_known(dr_early),
        dr_late = sum_known(dr_late),
        .groups = "drop"
      )
    out <- schedule_side %>%
      dplyr::inner_join(class_list_side, by = group_cols, relationship = "one-to-one") %>%
      dplyr::mutate(avg_census = dplyr::if_else(
        sections_matched > 0, census_enrl / sections_matched, NA_real_
      ))
    # A row grouped by course names it: its most common title over its
    # sections, and how many titles they had (a topics course, or a course
    # renamed across the terms a row spans).
    if ("subject_course" %in% group_cols && !"course_title" %in% group_cols) {
      if (!"course_title" %in% names(rows)) {
        stop("[enrollment.R] summarize_enrollment_view(): section rows lack course_title")
      }
      titles <- rows %>%
        dplyr::filter(!is.na(course_title), nzchar(course_title)) %>%
        dplyr::count(dplyr::across(dplyr::all_of(c(group_cols, "course_title"))), name = "n_sections") %>%
        dplyr::arrange(dplyr::desc(n_sections), course_title) %>%
        dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) %>%
        dplyr::summarize(course_title = dplyr::first(course_title), n_titles = dplyr::n(), .groups = "drop")
      out <- out %>% dplyr::left_join(titles, by = group_cols, relationship = "one-to-one")
    }
  } else {
    out <- rows %>%
      dplyr::mutate(sections_matched = as.integer(!is.na(registered)))
  }

  capacity <- enrollment_capacity_metrics(out$first_day_enrl, out$seats)
  out <- out %>%
    dplyr::mutate(
      first_day_fill = dplyr::if_else(
        capacity$capacity_usable & seats_known & !crosslisted,
        capacity$fill_rate, NA_real_
      ),
      fill_status = dplyr::case_when(
        first_day_fill >= CEDAR_FULL_FILL ~ "full",
        first_day_fill >= CEDAR_NEAR_FULL_FILL ~ "near full",
        TRUE ~ NA_character_
      )
    )

  n_before <- nrow(out)
  bound <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    if (length(x) == 0 || is.na(x[[1]])) NULL else x[[1]]
  }
  lo <- bound(opt[["enrl_min"]]) %||% -Inf
  hi <- bound(opt[["enrl_max"]]) %||% Inf
  keep <- is.na(out$census_enrl) | (out$census_enrl >= lo & out$census_enrl <= hi)
  out <- out[keep, , drop = FALSE]

  list(
    rows = out,
    grouped = grouped,
    group_cols = group_cols,
    n_before_filter = n_before,
    n_no_registrations = sum(is.na(out$census_enrl))
  )
}

# The Enrollment table's columns in reading order: what the row is, the
# schedule's facts, the seats and the class-list counts through the term, then
# the DESR snapshot. Columns a grain lacks are skipped.
ENROLLMENT_TABLE_SECTION_COLS <- c(
  "campus", "college", "term", "term_type", "listed_code", "section", "part_term",
  "course_title", "instructor_name", "delivery_method", "gen_ed_area", "partners"
)
ENROLLMENT_TABLE_COUNT_COLS <- c(
  "sections", "sections_matched", "xl_sections", "seats", "first_day_enrl",
  "first_day_fill", "fill_status", "census_enrl", "avg_census", "registered",
  "dr_early", "dr_late", "enrolled", "total_enrl"
)

#' Shape one Enrollment view for display and download
#'
#' Rounds once, here: counts whole, fill a percentage to one decimal, the
#' per-section census mean to two. A section row names the code the schedule
#' used that term (`listed_code`) and its crosslist or split partners; a row
#' grouped by course names its title after the course, "(+N more)" when its
#' sections had several.
#'
#' @param view A `summarize_enrollment_view()` result.
#' @return A tibble in display order.
enrollment_table_display <- function(view) {
  rows <- view$rows
  if (is.null(rows) || nrow(rows) == 0) return(tibble::tibble())
  if (isTRUE(view$grouped)) {
    keep <- view$group_cols
    if ("n_titles" %in% names(rows)) {
      # The title follows the course; a row with several says how many more.
      rows <- rows %>% dplyr::mutate(course_title = dplyr::if_else(
        n_titles > 1L, paste0(course_title, " (+", n_titles - 1L, " more)"), course_title))
      at <- match("subject_course", keep)
      keep <- append(keep, "course_title", after = at)
    }
    keep <- c(keep, intersect(ENROLLMENT_TABLE_COUNT_COLS, names(rows)))
  } else {
    partners <- dplyr::coalesce(
      if ("split_sections" %in% names(rows)) as.character(rows$split_sections) else NA_character_,
      if ("crosslist_partners" %in% names(rows)) as.character(rows$crosslist_partners) else NA_character_
    )
    rows <- rows %>% dplyr::mutate(partners = partners)
    keep <- c(intersect(ENROLLMENT_TABLE_SECTION_COLS, names(rows)),
              intersect(setdiff(ENROLLMENT_TABLE_COUNT_COLS,
                                c("sections", "xl_sections", "avg_census")), names(rows)))
  }
  whole <- intersect(c("sections", "sections_matched", "xl_sections", "seats",
                       "first_day_enrl", "census_enrl", "registered", "dr_early",
                       "dr_late", "enrolled", "total_enrl"), keep)
  rows %>%
    dplyr::ungroup() %>%
    dplyr::select(dplyr::all_of(keep)) %>%
    dplyr::mutate(
      dplyr::across(dplyr::all_of(whole), ~ as.integer(round(.x))),
      first_day_fill = round(100 * first_day_fill, 1),
      dplyr::across(dplyr::any_of("avg_census"), ~ round(.x, 2))
    )
}
