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
#' @param sections Section rows from `get_enrl()` with no `group_cols`, carrying
#'   `term`, `crn`, `enrolled`, `available` and `crosslist_code`.
#' @param students Class-list rows (`cedar_registrations`); only those in
#'   `sections` are read.
#' @param schedule `cedar_sections`, for each section's status and first class
#'   day, which `get_enrl()` does not return.
#' @return list(rows = the offered section rows with `registered`, `dr_early`,
#'   `dr_late`, `census_enrl`, `first_day_enrl`, `first_day_basis`, `seats`,
#'   `seats_known` and `crosslisted`; n_placeholders = section rows dropped as
#'   not offered).
attach_enrollment_section_counts <- function(sections, students, schedule) {
  need <- c("term", "crn", "enrolled", "available", "crosslist_code")
  missing <- setdiff(need, names(sections))
  if (length(missing) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): sections lack ",
         paste(missing, collapse = ", "))
  }
  missing <- setdiff(c("term", "crn", "status", "enrolled", "available",
                       "total_enrl", "start_date"), names(schedule))
  if (length(missing) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): schedule lacks ",
         paste(missing, collapse = ", "))
  }

  sections <- dplyr::ungroup(sections)
  offered_keys <- schedule %>%
    dplyr::ungroup() %>%
    keep_offered_sections() %>%
    dplyr::distinct(term, crn)
  offered <- sections %>% dplyr::semi_join(offered_keys, by = c("term", "crn"))
  if (anyDuplicated(offered[c("term", "crn")]) > 0) {
    stop("[enrollment.R] attach_enrollment_section_counts(): a section (term, crn) ",
         "appears more than once; counts would be attached twice")
  }

  scoped <- filter_classlist_to_sections(students, offered)
  if (nrow(scoped) > 0) {
    counts <- calc_cl_enrls(scoped, by_section = TRUE) %>%
      dplyr::ungroup() %>%
      dplyr::select(term, crn, registered, dr_early, dr_late, census_enrl)
    first_day <- calc_first_day_enrl(
      scoped,
      schedule %>%
        dplyr::ungroup() %>%
        dplyr::semi_join(offered_keys, by = c("term", "crn")) %>%
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

  rows <- offered %>%
    dplyr::left_join(counts, by = c("term", "crn"), relationship = "one-to-one") %>%
    dplyr::left_join(first_day, by = c("term", "crn"), relationship = "one-to-one") %>%
    dplyr::mutate(
      seats = as.numeric(enrolled) + as.numeric(available),
      seats_known = is.finite(enrolled) & is.finite(available) & seats > 0,
      crosslisted = !is.na(crosslist_code) & !crosslist_code %in% c("0", "")
    )
  list(rows = rows, n_placeholders = nrow(sections) - nrow(offered))
}

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
#' @return list(rows, grouped, group_cols, n_before_filter, n_no_registrations).
summarize_enrollment_view <- function(section_rows, opt = list()) {
  view <- opt[["view"]] %||% "home"
  group_cols <- opt[["group_cols"]]
  grouped <- length(group_cols) > 0
  rows <- filter_enrollment_crosslist_view(section_rows, view)

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
#' used that term (`listed_code`) and its crosslist or split partners.
#'
#' @param view A `summarize_enrollment_view()` result.
#' @return A tibble in display order.
enrollment_table_display <- function(view) {
  rows <- view$rows
  if (is.null(rows) || nrow(rows) == 0) return(tibble::tibble())
  if (isTRUE(view$grouped)) {
    keep <- c(view$group_cols, intersect(ENROLLMENT_TABLE_COUNT_COLS, names(rows)))
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
