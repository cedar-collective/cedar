# CEDAR-PLATFORM: a course's topics, from its sections' titles
#
# One course number can carry many courses: FYEX 1110's seminars, a
# special-topics slot. Each section's title is its topic, read wording-blind
# (topic_title_key(), R/lists/topic_titles.R) and merged where the
# institution's topic_titles.csv says two wordings are one topic. A course
# offers topics when one of its campus-terms has offered sections of two or
# more; a course retitled between terms never has, so its history stays one
# course. Banner's "T:" prefix (cedar_sections$is_topics) marks only some of
# them: FYEX 1110's seminars are titled "Sem:".
#
#   attach_section_topics()  topic_key, topic and topic_basis on each section
#   course_topic_counts()    how many topics each campus-term of a course offered
#   course_has_topics()      whether any campus-term offered two or more
#
# Depends on: topic_title_key(), topic_title_text(), CEDAR_TOPIC_TITLES
#             (lists/topic_titles.R); keep_offered_sections() (trunk/filter.R)

#' What a section's topic was read from: its own title, a topic_titles.csv
#' row, or nothing (no title on the schedule).
TOPIC_BASES <- c("title", "topic_titles", "no_title")

#' The label of the topic a section with no title is counted under.
TOPIC_NO_TITLE <- "(no title on the schedule)"

.topic_titles_check <- function(topic_titles) {
  missing <- setdiff(c("subject_course", "title_key", "topic_key", "topic"), names(topic_titles))
  if (length(missing) > 0) {
    stop("[course-topics.R] topic_titles lacks ", paste(missing, collapse = ", "),
         "; pass CEDAR_TOPIC_TITLES or a validate_topic_titles() result.", call. = FALSE)
  }
  invisible(topic_titles)
}

#' Attach each section's topic
#'
#' A section's topic is its title's key (topic_title_key()), or, where
#' topic_titles.csv lists the title under the code the section is listed
#' under, the key of the topic that row names. A topic is labelled with the
#' wording most of its own-titled sections used (the label dropped), the most
#' recent on a tie; a topic only merged rows reach takes the row's wording.
#'
#' @param sections `cedar_sections` rows with `subject_course` (the course
#'   id), `listed_code`, `term` and `course_title`.
#' @param topic_titles CEDAR_TOPIC_TITLES, or another validate_topic_titles()
#'   result.
#' @return `sections` with `topic_key` ("" for a section with no title),
#'   `topic` (the label) and `topic_basis` (one of TOPIC_BASES).
attach_section_topics <- function(sections, topic_titles) {
  missing <- setdiff(c("subject_course", "listed_code", "term", "course_title"), names(sections))
  if (length(missing) > 0) {
    stop("[course-topics.R] attach_section_topics(): sections lack ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  .topic_titles_check(topic_titles)
  sections <- ungroup(sections)
  own_key <- topic_title_key(sections$course_title)
  untitled <- is.na(own_key) | !nzchar(own_key)
  merged <- match(paste(sections$listed_code, own_key),
                  paste(topic_titles$subject_course, topic_titles$title_key))
  merged[untitled] <- NA_integer_
  sections$topic_key <- dplyr::case_when(
    untitled ~ "",
    !is.na(merged) ~ topic_titles$topic_key[merged],
    TRUE ~ own_key
  )
  sections$topic_basis <- dplyr::case_when(
    untitled ~ "no_title",
    !is.na(merged) ~ "topic_titles",
    TRUE ~ "title"
  )
  sections$.topic_own <- !untitled & is.na(merged)
  sections$.topic_text <- dplyr::if_else(
    is.na(merged), topic_title_text(sections$course_title),
    topic_title_text(topic_titles$topic[merged])
  )

  # The label: the wording most of the topic's own-titled sections used; a
  # topic reached only through topic_titles.csv takes the row's wording.
  # CAMPUS_ROLLUP: a label, not a count. A topic is one key on every campus,
  # so it carries one name on every campus; every count stays by campus.
  labels <- sections %>%
    filter(topic_basis != "no_title") %>%
    group_by(subject_course, topic_key, .topic_text) %>%
    summarize(.own = sum(.topic_own), .n = n(), .last = max(term), .groups = "drop") %>%
    arrange(subject_course, topic_key, desc(.own), desc(.n), desc(.last), .topic_text) %>%
    distinct(subject_course, topic_key, .keep_all = TRUE) %>%
    select(subject_course, topic_key, topic = .topic_text)
  sections %>%
    select(-any_of("topic")) %>%
    left_join(labels, by = c("subject_course", "topic_key"), relationship = "many-to-one") %>%
    mutate(topic = if_else(topic_basis == "no_title", TOPIC_NO_TITLE, topic)) %>%
    select(-.topic_own, -.topic_text)
}

#' How many topics each campus-term of a course offered
#'
#' @param sections `cedar_sections` rows, with `status`, `enrolled`,
#'   `available` and `total_enrl` beside the columns attach_section_topics()
#'   needs.
#' @param topic_titles As for attach_section_topics().
#' @param opt `course` (one course id; required), `campus` (campuses that
#'   taught it; NULL for every campus).
#' @return One row per campus and term with an offered section: `campus`,
#'   `term`, `n_topics`, `n_sections`.
course_topic_counts <- function(sections, topic_titles, opt = list()) {
  course <- opt[["course"]]
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-topics.R] course_topic_counts(): opt$course (one course id) is required.", call. = FALSE)
  }
  rows <- sections %>% ungroup() %>% filter(subject_course == .env$course)
  if (!is.null(opt[["campus"]])) rows <- rows %>% filter(campus %in% opt[["campus"]])
  rows %>%
    keep_offered_sections() %>%
    attach_section_topics(topic_titles) %>%
    group_by(campus, term) %>%
    summarize(n_topics = n_distinct(topic_key), n_sections = n_distinct(crn), .groups = "drop") %>%
    arrange(campus, term)
}

#' Does a course offer topics?
#'
#' TRUE when some campus-term offered sections of two or more topics.
#'
#' @inheritParams course_topic_counts
#' @return TRUE or FALSE.
course_has_topics <- function(sections, topic_titles, opt = list()) {
  any(course_topic_counts(sections, topic_titles, opt)$n_topics > 1L)
}
