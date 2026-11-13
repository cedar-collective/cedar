# What the tests in test-course-overview.R share: builders, option lists, constants.

# The base class list carries no CRNs, so it cannot reach a section family
# through the full payload; these tests count its rows directly instead.
base_overview <- function(course) {
  opt <- create_test_opt(list(course = course))
  students <- filter_class_list(test_students, opt)
  assemble_course_overview(
    test_sections,
    add_first_day_enrl(calc_cl_enrls(students), students, test_sections),
    opt
  )
}

# A hand-built overview with only the columns the snapshot reads, so expected
# values are visible here: four falls at ABQ, two at EA.
.snapshot_overview <- function() {
  lifecycle <- tibble::tibble(
    campus = c(rep("ABQ", 4), "EA", "EA"),
    term = c(202080L, 202180L, 202280L, 202380L, 202180L, 202280L),
    term_type = "fall",
    subject_course = "HIST 1110",
    first_day_enrl = c(NA, 64L, 80L, 1104L, 10L, 15L),
    census_enrl = c(55, 66, 80, 1110, 10, 15),
    current_enrl = c(50L, 60L, 75L, 1000L, 10L, 15L),
    early_drops = c(5L, 6L, 8L, 10L, 0L, 1L),
    late_drops = c(5L, 6L, 5L, 110L, 0L, 0L),
    waitlisted = c(1L, 2L, 4L, 8L, 0L, 0L)
  )
  list(
    lifecycle = lifecycle,
    sections = tibble::tibble(
      campus = lifecycle$campus, term = lifecycle$term, term_type = "fall",
      subject_course = "HIST 1110", sections = c(2L, 3L, 4L, 40L, 1L, 1L),
      avg_section_size = c(25, 20, 18.75, 25.04, 10, 15)
    ),
    listings = lifecycle[, c("campus", "term", "term_type", "subject_course",
                             "first_day_enrl", "census_enrl", "current_enrl",
                             "early_drops", "late_drops", "waitlisted")],
    overlap = tibble::tibble(
      campus = character(), term = integer(), term_type = character(),
      kind = character(), from_code = character(), to_code = character(),
      students = integer()
    )
  )
}
