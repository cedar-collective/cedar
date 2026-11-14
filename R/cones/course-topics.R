# course-topics.R — A course's topics, term by term
#
# One question: under one course number, how did each topic do in each term
# on each campus that taught it? A topic is a section title, read by
# attach_section_topics() (branches/course-topics.R). The measure tables are
# counted by course and part of term, not by section, so they hold no topic:
# each count here is taken over the course's own rows of the table that holds
# the fact, joined to its section's topic by term and CRN.
#
#   offerings  the schedule's offered sections (keep_offered_sections()): how
#              many, their seats (enrolled + available, as cedar_course_terms
#              counts them), and their instructors. A crosslisted section's
#              seats are its family's, so a topic-term with one has no fill.
#   students   the class list: still registered, late drops, census
#              (add_census_enrl()). calc_cl_enrls() groups by course and
#              cannot take a topic; the class list holds one row per student,
#              course, campus and term (dedup_class_list_rows()), checked
#              here, so each status bucket is a count of rows.
#   outcomes   cedar_attempts' classified outcome (pass / dfw), to its graded
#              edge.
#   return     cedar_student_terms' returned_next_regular_term for each
#              student with a classified attempt, where return_observable.
#
# Only the course's own listing is counted: students registered under a
# crosslisted partner code are that code's. Terms run to the last enrolled
# term; a term after the settled edge is in progress, its enrollment current
# registration. A class-list row or attempt whose CRN no section of the
# course carries has no topic and is counted apart (`unmatched`).
#
# Depends on: attach_section_topics() (branches/course-topics.R),
#             keep_offered_sections() (trunk/filter.R),
#             add_census_enrl() (branches/enrl.R)

.course_topics_need <- function(df, cols, what) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0) {
    stop("[course-topics.R] ", what, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(df)
}

.course_topics_edge <- function(edges, name) {
  edge <- edges[[name]]
  if (is.null(edge) || length(edge) != 1L || is.na(edge)) {
    stop("[course-topics.R] opt$data_edges has no ", name, " edge.", call. = FALSE)
  }
  as.integer(edge)
}

#' A course's topics by campus and term
#'
#' @param sections `cedar_sections`.
#' @param students `cedar_registrations`.
#' @param attempts `cedar_attempts`.
#' @param student_terms `cedar_student_terms`.
#' @param topic_titles CEDAR_TOPIC_TITLES, or another validate_topic_titles()
#'   result.
#' @param opt `course` (one course id; required), `campus` (campuses that
#'   taught it; NULL for every campus), `data_edges` (`cedar_data_edges()`
#'   output with `last_enrolled`, `last_enrolled_complete` and `last_graded`;
#'   required).
#' @return Named list:
#'   `terms`: one row per campus, term and topic with an offered section or a
#'   student: `campus`, `term`, `term_type`, `topic_key`, `topic`, `sections`,
#'   `crosslisted_sections`, `seats`, `seats_known`, `n_instructors` (distinct
#'   recorded instructors of its sections), `registered`, `dr_late`,
#'   `census_enrl`, `attempts` (classified: the DFW denominator), `passed`,
#'   `dfw`, `n_return_observable`, `n_returned`, `in_progress` (after the
#'   settled edge) and `graded` (at or before the graded edge). Outcome and
#'   return counts are NA in a term past the graded edge; return is counted
#'   over the students whose return is observable, none in a term whose next
#'   regular term has not settled.
#'   `instructors`: `campus`, `term`, `topic_key`, `instructor_id`, one row per
#'   recorded instructor of a topic-term's offered sections, for counting
#'   instructors across terms.
#'   `titles`: one row per campus and title an offered section carried:
#'   `campus`, `course_title`, `topic_key`, `topic`, `topic_basis`,
#'   `sections`, `first_term`, `last_term`.
#'   `unmatched`: class-list rows (`students`) and classified attempts
#'   (`attempts`) whose CRN no section of the course carries.
#'   `course`, `campus`, `last_enrolled`, `settled_edge`, `graded_edge`.
get_course_topic_terms <- function(sections, students, attempts, student_terms, topic_titles,
                                   opt = list()) {
  course <- opt[["course"]]
  if (is.null(course) || length(course) != 1L || is.na(course) || !nzchar(course)) {
    stop("[course-topics.R] opt$course (one course id) is required.", call. = FALSE)
  }
  edges <- opt[["data_edges"]]
  last_enrolled <- .course_topics_edge(edges, "last_enrolled")
  settled_edge  <- .course_topics_edge(edges, "last_enrolled_complete")
  graded_edge   <- .course_topics_edge(edges, "last_graded")
  campus <- opt[["campus"]]
  .course_topics_need(sections, c("term", "crn", "campus", "subject_course", "listed_code",
                                  "course_title", "status", "enrolled", "available", "total_enrl",
                                  "instructor_id", "crosslist_group", "is_combined"), "sections")
  .course_topics_need(students, c("student_id", "term", "campus", "subject_course", "crn",
                                  "registration_status_code"), "students")
  .course_topics_need(attempts, c("student_id", "term", "campus", "subject_course", "crn",
                                  "outcome"), "attempts")
  .course_topics_need(student_terms, c("student_id", "term", "return_observable",
                                       "returned_next_regular_term"), "student_terms")
  scope <- function(rows) {
    rows <- rows %>% ungroup() %>% filter(subject_course == .env$course, term <= .env$last_enrolled)
    if (!is.null(campus)) rows <- rows %>% filter(campus %in% .env$campus)
    rows
  }
  key <- c("campus", "term", "topic_key")

  # ── The schedule: every section's topic; the offered ones' supply ─────────
  course_sections <- scope(sections) %>% attach_section_topics(topic_titles)
  topic_of_crn <- course_sections %>% distinct(term, crn, topic_key, topic)
  offered <- keep_offered_sections(course_sections)
  supply <- offered %>%
    group_by(across(all_of(key))) %>%
    summarize(
      # A combined lecture-and-lab course (C suffix) lists a CRN per lab: one
      # offering, never one per CRN.
      sections = n_distinct(crn[!is_combined %in% TRUE]) + as.integer(any(is_combined %in% TRUE)),
      crosslisted_sections = sum(!is.na(crosslist_group)),
      seats = sum(as.numeric(enrolled) + as.numeric(available)),
      seats_known = all(is.finite(enrolled) & is.finite(available) & enrolled + available > 0),
      n_instructors = n_distinct(instructor_id[!is.na(instructor_id)]),
      .groups = "drop"
    )
  instructors <- offered %>%
    filter(!is.na(instructor_id)) %>%
    distinct(campus, term, topic_key, instructor_id)

  # ── The class list ────────────────────────────────────────────────────────
  roster <- scope(students) %>% select(student_id, term, campus, crn, registration_status_code)
  dup <- roster %>% count(student_id, term, campus) %>% filter(n > 1L)
  if (nrow(dup) > 0) {
    stop("[course-topics.R] the class list holds ", nrow(dup), " students more than once in one ",
         "term and campus of ", course, "; it must be one row per student, course, campus and term ",
         "(dedup_class_list_rows()).", call. = FALSE)
  }
  roster <- roster %>% left_join(topic_of_crn, by = c("term", "crn"), relationship = "many-to-one")
  enrollment <- roster %>%
    filter(!is.na(topic_key)) %>%
    group_by(across(all_of(key))) %>%
    summarize(registered = sum(registration_status_code %in% STATUS_REGISTERED),
              dr_late = sum(registration_status_code %in% STATUS_DROP_LATE),
              .groups = "drop") %>%
    add_census_enrl()

  # ── Outcomes and return ───────────────────────────────────────────────────
  classified <- scope(attempts) %>%
    filter(!is.na(outcome)) %>%
    select(student_id, term, campus, crn, outcome) %>%
    left_join(topic_of_crn, by = c("term", "crn"), relationship = "many-to-one")
  outcomes <- classified %>%
    filter(!is.na(topic_key)) %>%
    left_join(student_terms %>% select(student_id, term, return_observable, returned_next_regular_term),
              by = c("student_id", "term"), relationship = "many-to-one")
  orphans <- sum(is.na(outcomes$return_observable))
  if (orphans > 0) {
    stop("[course-topics.R] ", orphans, " classified attempts of ", course, " have no student-term ",
         "row; attempts and student_terms must come from one class list.", call. = FALSE)
  }
  outcomes <- outcomes %>%
    group_by(across(all_of(key))) %>%
    summarize(attempts = n(),
              passed = sum(outcome == "pass"),
              dfw = sum(outcome == "dfw"),
              n_return_observable = sum(return_observable),
              n_returned = sum(returned_next_regular_term[return_observable]),
              .groups = "drop")

  labels <- topic_of_crn %>% distinct(topic_key, topic)
  terms <- supply %>%
    full_join(enrollment, by = key) %>%
    full_join(outcomes, by = key) %>%
    left_join(labels, by = "topic_key", relationship = "many-to-one") %>%
    mutate(
      term = as.integer(term),
      term_type = get_term_type(term),
      in_progress = term > .env$settled_edge,
      graded = term <= .env$graded_edge,
      # A topic-term with students and no offered section (its section was
      # cancelled) offered nothing.
      sections = coalesce(sections, 0L),
      crosslisted_sections = coalesce(crosslisted_sections, 0L),
      n_instructors = coalesce(n_instructors, 0L),
      seats_known = coalesce(seats_known, FALSE),
      across(c(registered, dr_late, census_enrl), ~ coalesce(as.integer(.x), 0L)),
      # A graded term with no classified attempt has none; one past the graded
      # edge has no outcomes yet.
      across(c(attempts, passed, dfw), ~ if_else(graded, coalesce(.x, 0L), NA_integer_)),
      # Return is observable for a term or not, for every student in it.
      n_return_observable = if_else(graded, coalesce(n_return_observable, 0L), NA_integer_),
      n_returned = if_else(graded, coalesce(n_returned, 0L), NA_integer_)
    ) %>%
    # A cancelled section whose students all dropped early offered nothing to
    # anyone: no topic-term.
    filter(sections > 0L | census_enrl > 0L | coalesce(attempts, 0L) > 0L) %>%
    arrange(campus, term, topic) %>%
    select(campus, term, term_type, topic_key, topic, sections, crosslisted_sections, seats,
           seats_known, n_instructors, registered, dr_late, census_enrl, attempts, passed, dfw,
           n_return_observable, n_returned, in_progress, graded)

  titles <- offered %>%
    group_by(campus, course_title, topic_key, topic, topic_basis) %>%
    summarize(sections = n(), first_term = as.integer(min(term)), last_term = as.integer(max(term)),
              .groups = "drop") %>%
    arrange(campus, topic, course_title)

  cedar_debug("[course-topics.R] ", course, ": ", n_distinct(terms$topic_key), " topics over ",
              nrow(terms), " topic-terms")
  list(
    terms = terms,
    instructors = instructors,
    titles = titles,
    unmatched = list(students = sum(is.na(roster$topic_key)),
                     attempts = sum(is.na(classified$topic_key))),
    course = course,
    campus = campus,
    last_enrolled = last_enrolled,
    settled_edge = settled_edge,
    graded_edge = graded_edge
  )
}
