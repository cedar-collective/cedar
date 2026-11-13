# What the tests in test-gpa-timeline.R share: builders, option lists, constants.

# GP_S1 — three terms, all graded, whole record inside the window.
# GP_S2 — starts in the first term of the data, so left-truncated.
# GP_S9 — one term with an A beside W, CR and I: points for the A only.
# GP_S8 — a W only: no graded hours, no timeline row.
# Rows through the ST01 constructor (3 credits each, registered, ABQ).
make_gpa_students <- function() {
  dplyr::bind_rows(
    .st_row("GP_S1", 202080L, "AAA 101", "RE", "A"),
    .st_row("GP_S1", 202080L, "BBB 101", "RE", "B"),
    .st_row("GP_S1", 202110L, "CCC 101", "RE", "C"),
    .st_row("GP_S1", 202180L, "DDD 101", "RE", "A"),
    .st_row("GP_S2", 202010L, "EEE 101", "RE", "B"),
    .st_row("GP_S2", 202110L, "FFF 101", "RE", "A"),
    .st_row("GP_S9", 202080L, "GGG 101", "RE", "A"),
    .st_row("GP_S9", 202080L, "HHH 101", "RE", "W"),
    .st_row("GP_S9", 202080L, "III 101", "RE", "CR"),
    .st_row("GP_S9", 202080L, "JJJ 101", "RE", "I"),
    .st_row("GP_S8", 202080L, "KKK 101", "RE", "W")
  )
}

gpa_student_terms <- function(students = make_gpa_students()) {
  suppressMessages(build_student_terms(
    students, programs = NULL, degrees = NULL,
    edges = list(last_enrolled_complete = 202180L)
  ))
}

gpa_timeline <- function() build_gpa_timeline(gpa_student_terms())
