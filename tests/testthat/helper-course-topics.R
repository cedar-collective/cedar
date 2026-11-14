# Course Dynamics > Topics over TP01 (fixtures/designed_test_data.R): FYEX
# 1110 to tp01_edges, with TP01's reviewed merges unless a test passes others.
tp_topics <- function(campus = NULL, min_n = 1L, topic_titles = tp_topic_titles,
                      students = test_students_tp) {
  build_course_topics(
    test_sections_tp, students, tp_attempts, test_student_terms_tp,
    list(course = "FYEX 1110", campus = campus, data_edges = tp01_edges, min_n = min_n),
    topic_titles = topic_titles
  )
}

# One row of a Topics table, by campus, topic and (for the term table) term.
tp_row <- function(d, campus, topic, term = NULL) {
  rows <- d[d$campus == campus & d$topic == topic, , drop = FALSE]
  if (!is.null(term)) rows <- rows[rows$term == term, , drop = FALSE]
  stopifnot(nrow(rows) == 1L)
  rows
}
