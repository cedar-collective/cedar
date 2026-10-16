# CEDAR-PLATFORM: Gen Ed area course table from institution/<id>/gen_ed_courses.csv
# The institution's Gen Ed areas and the courses in each come from its
# gen_ed_courses.csv (read and validated here at load). This file names no
# area and no course.
#
# CEDAR_GEN_ED_COURSES: one row per (area, course), in file order, with
#   area (integer), area_name, area_label ("1: Communication") and subject_course.
# gen_ed_all: every Gen Ed course once, as a list, for callers that only need
#   membership (Pathways, the projection monitoring group).
# A course listed under two areas counts under the first listed:
# gen_ed_course_lookup() (R/features/gen-ed.R) and the transform both take the
# first row per course.

.cedar_gen_ed <- validate_gen_ed_courses(read_institution_file("gen_ed_courses"))

CEDAR_GEN_ED_COURSES <- tibble::tibble(
  area           = .cedar_gen_ed$area,
  area_name      = .cedar_gen_ed$area_name,
  area_label     = paste0(.cedar_gen_ed$area, ": ", .cedar_gen_ed$area_name),
  subject_course = .cedar_gen_ed$subject_course
)

gen_ed_all <- as.list(unique(CEDAR_GEN_ED_COURSES$subject_course))
