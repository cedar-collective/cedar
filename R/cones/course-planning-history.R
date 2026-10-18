#' Historical availability and first-class-day pressure for exact course codes
#'
#' The last nine possible terms end at settled enrollment. Keep course, delivery
#' campus, college and session together. First day is reconstructed only from
#' dated class-list statuses, never substituted with census or ever-registered.
get_course_planning_history <- function(sections, students, subject_courses, edges,
                                        min_n = 10L) {
  edge <- cedar_longitudinal_edge(edges, grade_dependent = FALSE)
  if (is.null(edge)) return(list(state = "unavailable", note = "Settled enrollment coverage is unavailable."))
  required <- list(sections = c("campus", "college", "part_term", "subject_course", "term", "crn",
    "status", "enrolled", "available", "total_enrl", "crosslist_code", "start_date"),
    students = c("campus", "college", "part_term", "subject_course", "term", "term_type",
      "crn", "student_id", "registration_status_code", "registration_date", "as_of_date"))
  for (name in names(required)) {
    missing <- setdiff(required[[name]], names(if (name == "sections") sections else students))
    if (length(missing)) stop("[course-planning-history.R] Course history ", name, " missing: ", paste(missing, collapse = ", "))
  }
  if (!is.finite(min_n) || min_n < 10) stop("[course-planning-history.R] Course history minimum cell size must be at least 10")
  year <- as.integer(substr(as.character(edge), 1, 4))
  possible <- as.integer(names(make_term_sequence(year - 3L, year)))
  window <- tail(possible[possible <= edge], 9L)
  source <- sections %>% ungroup() %>% filter(term %in% window)
  coverage <- source %>% distinct(campus, term) %>% add_term_type_col("term")
  selected <- source %>% filter(subject_course %in% subject_courses, status == "A",
    !is.finite(enrolled + available) | enrolled + available > 0 | total_enrl > 0)
  note <- paste0(fmt_term(window[1]), "–", fmt_term(edge), ". First day = each section's first class day.")
  if (!nrow(selected)) return(list(state = "empty", note = note,
    missing_courses = subject_courses, coverage = coverage))
  keys <- c("campus", "college", "subject_course", "term", "part_term")
  quality <- selected %>% group_by(across(all_of(keys))) %>%
    summarize(capacity_known = all(is.finite(enrolled) & is.finite(available) &
      enrolled + available > 0), .groups = "drop")
  seats <- get_enrl(selected, list(uel = FALSE, group_cols = keys)) %>% ungroup() %>%
    mutate(capacity = enrolled + avail) %>%
    left_join(quality, by = keys, relationship = "one-to-one") %>%
    mutate(capacity = if_else(capacity_known, capacity, NA_real_))
  scoped_students <- students %>% ungroup() %>%
    filter(term %in% window, subject_course %in% subject_courses) %>%
    filter_classlist_to_sections(selected)
  section_keys <- c(keys, "crn")
  matches <- selected %>% distinct(across(all_of(section_keys))) %>%
    left_join(scoped_students %>% distinct(across(all_of(section_keys))) %>% mutate(.matched = TRUE),
      by = section_keys, relationship = "one-to-one") %>%
    group_by(across(all_of(keys))) %>%
    summarize(classlist_complete = all(!is.na(.matched)), .groups = "drop")
  first_day <- calc_first_day_enrl(scoped_students, selected, by_part_term = TRUE)
  pressure <- seats %>% left_join(first_day, by = keys, relationship = "one-to-one") %>%
    left_join(matches, by = keys, relationship = "one-to-one") %>%
    mutate(source_matched = classlist_complete,
      first_day_enrl = if_else(source_matched, as.numeric(first_day_enrl), NA_real_),
      first_day_known = is.finite(first_day_enrl), small_cell = first_day_known & first_day_enrl < min_n)
  metrics <- enrollment_capacity_metrics(pressure$first_day_enrl, pressure$capacity) %>%
    rename(first_day_fill = fill_rate, first_day_available_seats = available_seats)
  pressure <- bind_cols(pressure, metrics) %>%
    mutate(pressure_known = capacity_usable & source_matched & first_day_known & !small_cell,
      near_full = if_else(pressure_known, capacity_constrained, NA),
      capacity_constrained = near_full,
      # Suppress small counts and reconstructable percentages in every payload.
      first_day_enrl = if_else(small_cell, NA_real_, first_day_enrl),
      first_day_fill = if_else(pressure_known, first_day_fill, NA_real_),
      first_day_available_seats = if_else(pressure_known, first_day_available_seats, NA_real_),
      pressure_status = case_when(!source_matched ~ "No class-list match", small_cell ~ "Suppressed (<10)",
        !first_day_known ~ "First-day dates unavailable", !capacity_usable ~ "Unreliable capacity",
        near_full ~ "Near full", TRUE ~ "Below 90%"))
  terms <- pressure %>% group_by(campus, subject_course, term) %>%
    summarize(capacity = if (all(is.finite(capacity))) sum(capacity) else NA_real_,
      sessions = n(), pressure_known = all(pressure_known),
      near_full = if (all(pressure_known)) any(near_full) else NA,
      .groups = "drop") %>% add_term_type_col("term")
  denominator <- coverage %>% count(campus, term_type, name = "eligible_terms") %>%
    tidyr::complete(campus, term_type = c("spring", "summer", "fall"), fill = list(eligible_terms = 0L))
  frequency <- selected %>% distinct(subject_course, campus) %>%
    inner_join(denominator, by = "campus", relationship = "many-to-many") %>%
    left_join(terms %>% group_by(campus, subject_course, term_type) %>%
      summarize(offered_terms = n(),
        typical_seats = if (any(is.finite(capacity))) stats::median(capacity, na.rm = TRUE) else NA_real_,
        scored_terms = sum(pressure_known), near_full_terms = sum(near_full, na.rm = TRUE),
        .groups = "drop"), by = c("campus", "subject_course", "term_type"), relationship = "one-to-one") %>%
    mutate(across(c(offered_terms, scored_terms, near_full_terms), ~tidyr::replace_na(.x, 0L)))
  # Show every possible term in the one history table. Source-covered absence is
  # a non-offering; missing campus coverage stays unknown, never a fabricated zero.
  grid <- tidyr::crossing(selected %>% distinct(campus, subject_course), term = window) %>%
    left_join(coverage %>% select(campus, term) %>% mutate(source_covered = TRUE),
      by = c("campus", "term"), relationship = "many-to-one")
  offerings <- grid %>% left_join(pressure %>% select(all_of(keys), capacity, first_day_enrl,
      first_day_fill, pressure_status), by = c("campus", "subject_course", "term"), relationship = "one-to-many") %>%
    mutate(offered = !is.na(pressure_status), source_covered = coalesce(source_covered, FALSE),
      capacity = if_else(!offered & source_covered, 0, capacity),
      pressure_status = case_when(offered ~ pressure_status, source_covered ~ "Not offered", TRUE ~ "Source unavailable"))
  list(state = "ready", note = note, pressure = pressure, terms = terms, frequency = frequency,
    offerings = offerings, missing_courses = setdiff(subject_courses, selected$subject_course), coverage = coverage)
}

#' Recent lower-level Gen Ed options for a season, retaining the first-day grain.
#' History is supplied by the feature; this cone never calls another cone.
get_gen_ed_planning_options <- function(sections, history, gen_ed, season, slot_credits) {
  if (length(season) != 1L || !season %in% c("fall", "spring")) stop("[course-planning-history.R] Select a fall or spring suggestion season")
  if (length(slot_credits) != 1L || !is.finite(slot_credits) || slot_credits <= 0) stop("[course-planning-history.R] Supply the usual allowance course credits")
  required <- c("campus", "college", "subject_course", "term", "part_term", "crn",
    "course_title", "credits_min", "credits_max", "level", "is_topics", "status")
  missing <- setdiff(required, names(sections))
  if (length(missing)) stop("[course-planning-history.R] Gen Ed options missing: ", paste(missing, collapse = ", "))
  if (history$state != "ready") stop("[course-planning-history.R] Gen Ed options need ready course history")
  if (!all(c("subject_course", "area_label") %in% names(gen_ed))) stop("[course-planning-history.R] Gen Ed options need area membership")
  keys <- c("campus", "college", "subject_course", "term", "part_term")
  rows <- history$pressure %>% add_term_type_col("term") %>% filter(term_type == season)
  # CAMPUS_ROLLUP: this is catalog membership, not an enrollment aggregate.
  membership <- gen_ed[!duplicated(gen_ed$subject_course), c("subject_course", "area_label")]
  metadata <- sections %>% ungroup() %>%
    semi_join(rows, by = keys) %>% filter(status == "A") %>% arrange(term, crn) %>%
    group_by(across(all_of(keys))) %>%
    summarize(eligible = all(level == "lower" & !is.na(is_topics) & !is_topics & !is_topics_course(course_title)),
      course_title = last(course_title),
      credits_min = if (all(is.finite(credits_min))) min(credits_min) else NA_real_,
      credits_max = if (all(is.finite(credits_max))) max(credits_max) else NA_real_,
      .groups = "drop") %>%
    # Standalone labs and unknown/large credit ranges are not presented as full
    # Gen Ed choices. Eligibility for a student's remaining areas is not inferred.
    filter(eligible %in% TRUE, is.finite(credits_min), is.finite(credits_max),
      credits_min >= slot_credits, credits_max <= slot_credits + 1) %>%
    inner_join(membership, by = "subject_course", relationship = "many-to-one")
  rows <- rows %>% inner_join(metadata, by = keys, relationship = "one-to-one")
  group <- setdiff(keys, "term")
  frequency <- rows %>% group_by(across(all_of(group))) %>%
    summarize(season_offerings = n_distinct(term), .groups = "drop")
  coverage <- history$coverage %>% filter(term_type == season) %>%
    count(campus, name = "source_terms")
  rows %>% arrange(term) %>% group_by(across(all_of(group))) %>% slice_tail(n = 1L) %>% ungroup() %>%
    left_join(frequency, by = group, relationship = "one-to-one") %>%
    left_join(coverage, by = "campus", relationship = "many-to-one") %>%
    mutate(season_frequency = paste(season_offerings, "of", source_terms)) %>%
    arrange(desc(season_offerings), desc(first_day_enrl), area_label, subject_course, campus, college, part_term) %>%
    select(area_label, subject_course, course_title, credits_min, credits_max,
      campus, college, part_term, term, capacity, first_day_enrl, first_day_fill,
      pressure_status, season_frequency)
}
