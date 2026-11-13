# What the tests in test-course-impact.R share: builders, option lists, constants.

# The two cones read outcomes off cedar_attempts (ADR-001 step 7): MC02's
# attempt table, built to these edges; a test that adds rows rebuilds it.
.impact_attempts <- function() keyed_attempts(test_students_mc, .impact_edges)

.sequence_audit_fixture <- function() {
  late_y <- .mc_row(
    "SEQ_T2", 202080, "SEQ 201", "ABQ", "SEQ",
    grade = NA_character_, instructor = "SEQ_I1"
  ) %>%
    dplyr::mutate(registration_status_code = "DW")

  students <- dplyr::bind_rows(
    .mc_row("SEQ_T1", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_T2", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_T1", 202080, "SEQ 201", "ABQ", "SEQ", "F", "SEQ_I1"),
    late_y,
    .mc_row("SEQ_T1", 202110, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_C1", 202080, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_C2", 202080, "SEQ 201", "ABQ", "SEQ", "B", "SEQ_I1"),
    # This X pass is outside the requested campus. The student's ABQ Y attempt
    # must therefore remain in the control group.
    .mc_row("SEQ_XC", 202010, "SEQ 101", "GA", "SEQ", "A", "SEQ_I2"),
    .mc_row("SEQ_XC", 202080, "SEQ 201", "ABQ", "SEQ", "A", "SEQ_I1")
  )

  ids <- c("SEQ_T1", "SEQ_T2", "SEQ_C1", "SEQ_C2", "SEQ_XC")
  program_template <- test_programs_mc %>%
    dplyr::filter(student_id == "MC_A2", term == 202010L) %>%
    dplyr::slice(1L)
  programs <- dplyr::bind_rows(lapply(seq_along(ids), function(i) {
    program_template %>%
      dplyr::mutate(
        student_id = ids[[i]],
        program_id = paste0("SEQ-PROG-", i),
        student_campus = "ABQ"
      )
  }))

  list(students = students, programs = programs, ids = ids)
}

# The audit fixture plus SEQ_F1, who failed SEQ 101 on ABQ in 202010 and then
# failed SEQ 201 in 202080 (control: attempted X earlier, did not pass), and
# SEQ_M1, who passed SEQ 101 and then passed the modular SEQ 201X (in no group
# until SEQ 201X is read as part of the later course).
#   Treatment: SEQ_T1 (Y dfw, HS 3.0, ACT 20), SEQ_T2 (Y dfw, no HS, no ACT)
#   Control:   SEQ_C1 (pass, 3.2, 22), SEQ_C2 (pass, 2.8, 16),
#              SEQ_XC (pass, none, none), SEQ_F1 (dfw, 3.0, 19)
.sequence_band_fixture <- function() {
  fixture <- .sequence_audit_fixture()
  fixture$students <- dplyr::bind_rows(
    fixture$students,
    .mc_row("SEQ_F1", 202010, "SEQ 101", "ABQ", "SEQ", "F", "SEQ_I1"),
    .mc_row("SEQ_F1", 202080, "SEQ 201", "ABQ", "SEQ", "F", "SEQ_I1"),
    .mc_row("SEQ_M1", 202010, "SEQ 101", "ABQ", "SEQ", "A", "SEQ_I1"),
    .mc_row("SEQ_M1", 202080, "SEQ 201X", "ABQ", "SEQ", "A", "SEQ_I1")
  )
  extra <- c("SEQ_F1", "SEQ_M1")
  fixture$programs <- dplyr::bind_rows(fixture$programs, lapply(seq_along(extra), function(i) {
    fixture$programs %>% dplyr::slice(1L) %>%
      dplyr::mutate(student_id = extra[[i]], program_id = paste0("SEQ-PROG-X", i))
  }))
  fixture$applicants <- tibble::tibble(
    student_id = c(fixture$ids, extra),
    high_school_cum_gpa    = c(3.0, NA, 3.2, 2.8, NA, 3.0, NA),
    unm_act_combined_score = c(20, NA, 22, 16, NA, 19, NA)
  )
  fixture
}

.run_sequence_bands <- function(fixture, ...) {
  suppressMessages(get_course_sequence_effect(
    fixture$students, keyed_attempts(fixture$students, .impact_edges), fixture$programs,
    applicants = fixture$applicants,
    opt = c(list(course_x = "SEQ 101", campus = "ABQ", min_n = 1L), list(...)),
    data_edges = .impact_edges
  ))
}
