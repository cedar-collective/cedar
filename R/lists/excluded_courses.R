# CEDAR-PLATFORM: excluded-course list from institution/<id>/excluded_courses.csv
# Courses left out of course lists and reviews when a computation applies the
# excluded list (opt$uel = TRUE): thesis, dissertation, honors-credit,
# independent-study and similar special enrollments, whose counts are real but
# whose rows would otherwise dominate any list of courses. Which courses those
# are is the institution's, in excluded_courses.csv (read and validated here at
# load); filter_class_list() and filter_DESRs() in R/trunk/filter.R apply it.
.cedar_excluded <- validate_excluded_courses(read_institution_file("excluded_courses"))

excluded_courses <- .cedar_excluded$subject_course
