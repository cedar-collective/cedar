context("Registration snapshots")

# IS01 (BIOL 1140, Fall 2020, ABQ and EA with a December intersession at EA)
# and WL01 (PSYC 1110, Fall 2020, waitlists on three campuses) together, with
# IS01's schedule. One row per campus, course and part of term:
#
#   course     campus part  registered  waitlisted  early drops  sections  seats
#   BIOL 1140  ABQ    1     2 (A, D)    0           1 (E)        1         30
#   BIOL 1140  EA     1     1 (B)       0           0            1         20
#   BIOL 1140  EA     INT   2 (C, D)    1 (F)       0            1         15
#   PSYC 1110  ABQ    1     2 (C, R1)   4 (A,B,D,E) 0            0         0
#   PSYC 1110  EA     1     2 (D, R2)   1 (A)       0            0         0
#   PSYC 1110  GA     1     0           1 (F)       0            0         0
#   PSYC 2110  ABQ    1     0           1 (G)       0            0         0
#
# WL_E is waiting, not an early drop: a waitlist row outranks a drop in the
# class-list count (STATUS_PRECEDENCE), and the canonical waitlist rule keeps a
# student whose only other row is a drop. PSYC has no section in the IS01
# schedule, so its sections and seats are measured zeros.

test_that("a snapshot counts each campus and part of term on its own row", {
  snapshot <- build_registration_snapshot(
    snapshot_students, test_sections_intersession, snapshot_course_terms(), list(terms = 202080L)
  )
  expect_named(snapshot, REGISTRATION_SNAPSHOT_COLUMNS)
  got <- snapshot %>%
    dplyr::transmute(key = paste(subject_course, campus, part_term),
                     registered, waitlisted, dr_early, dr_late, sections, seats)
  expected <- tibble::tribble(
    ~key,                 ~registered, ~waitlisted, ~dr_early, ~dr_late, ~sections, ~seats,
    "BIOL 1140 ABQ 1",    2L,          0L,          1L,        0L,       1L,        30,
    "BIOL 1140 EA 1",     1L,          0L,          0L,        0L,       1L,        20,
    "BIOL 1140 EA INT",   2L,          1L,          0L,        0L,       1L,        15,
    "PSYC 1110 ABQ 1",    2L,          4L,          0L,        0L,       0L,        0,
    "PSYC 1110 EA 1",     2L,          1L,          0L,        0L,       0L,        0,
    "PSYC 1110 GA 1",     0L,          1L,          0L,        0L,       0L,        0,
    "PSYC 2110 ABQ 1",    0L,          1L,          0L,        0L,       0L,        0
  )
  expect_equal(dplyr::arrange(got, key), expected)
  # Each term's newest pull, from the class lists and the schedule separately.
  expect_equal(unique(snapshot$classlist_as_of), as.Date("2020-10-23"))
  expect_equal(unique(snapshot$sections_as_of), as.Date("2020-10-23"))
  expect_false(any(c("student_id", "enrollment_id") %in% names(snapshot)))
})

test_that("a crosslisted section's seats are counted once, under its home listing", {
  # Spring 2020: HIST 490 has a section of its own (S10003, 20 seats) and is
  # also the partner listing of XL04, whose home is ANTH 490 (XL0401). XL04's
  # section is ANTH 490's; counted under every listing, HIST 490 would show two
  # sections and XL04's seats twice. A real crosslist's students register under
  # both codes, so a partner's row can hold students and no section.
  snapshot <- build_registration_snapshot(test_students, test_sections, test_course_terms,
                                          list(terms = 202010L))
  hist <- dplyr::filter(snapshot, subject_course == "HIST 490", campus == "ABQ")
  anth <- dplyr::filter(snapshot, subject_course == "ANTH 490", campus == "ABQ")
  expect_equal(sum(hist$registered), 2L)
  expect_equal(sum(hist$sections), 1L)
  expect_equal(sum(hist$seats), 20)
  expect_equal(sum(anth$sections), 1L)
  expect_equal(sum(anth$registered), 0L)
})

test_that("a source with no pull for the term leaves its counts unknown, not zero", {
  # IS01's schedule relabelled as Spring 2021's draft, pulled in November before
  # registration opened: sections and seats are counted, registrations unknown.
  draft <- test_sections_intersession %>%
    dplyr::mutate(term = 202110L, term_type = "spring",
                  as_of_date = as.Date("2020-11-15"))
  ahead <- build_registration_snapshot(snapshot_students, draft,
                                       snapshot_course_terms(sections = draft), list(terms = 202110L))
  expect_equal(nrow(ahead), 3L)
  expect_true(all(is.na(ahead$classlist_as_of)))
  expect_true(all(is.na(ahead$registered) & is.na(ahead$waitlisted) &
                    is.na(ahead$dr_early) & is.na(ahead$dr_late)))
  expect_equal(sum(ahead$sections), 3L)
  expect_equal(sum(ahead$seats), 65)
  # And the reverse: a class list with no schedule rows for its term.
  unscheduled <- build_registration_snapshot(
    snapshot_students, test_sections_intersession[0, ],
    snapshot_course_terms(sections = test_sections_intersession[0, ]), list(terms = 202080L)
  )
  expect_true(all(is.na(unscheduled$sections_as_of) & is.na(unscheduled$sections) &
                    is.na(unscheduled$seats)))
  expect_equal(sum(unscheduled$registered), 9L)
})

test_that("a snapshot refuses a term with no rows and a call with no terms", {
  tbl <- snapshot_course_terms()
  expect_error(build_registration_snapshot(snapshot_students, test_sections_intersession, tbl),
               "opt\\$terms is required")
  expect_error(build_registration_snapshot(snapshot_students, test_sections_intersession, tbl,
                                           list(terms = c(202080L, 202110L))),
               "no class-list or section rows for term\\(s\\) 202110")
  expect_error(build_registration_snapshot(
    dplyr::select(snapshot_students, -as_of_date), test_sections_intersession, tbl,
    list(terms = 202080L)), "as_of_date")
  # The counts are the course-term table's: a recount is not that table.
  expect_error(build_registration_snapshot(snapshot_students, test_sections_intersession,
                                           calc_cl_enrls(snapshot_students, by_part_term = TRUE),
                                           list(terms = 202080L)),
               "build_course_terms")
})

test_that("the terms snapshotted are the ones in registration or scheduled ahead", {
  # IS01 again, relabelled as Spring 2021 and pulled in November, before that
  # term began: Fall 2020 has settled; Spring 2021 is in registration once its
  # class list exists, and scheduled ahead when only its draft does.
  spring <- test_students_intersession %>%
    dplyr::mutate(term = 202110L, term_type = "spring",
                  as_of_date = as.Date("2020-11-15"))
  draft <- test_sections_intersession %>%
    dplyr::mutate(term = 202110L, term_type = "spring",
                  as_of_date = as.Date("2020-11-15"))
  expect_identical(registration_snapshot_terms(snapshot_students, test_sections_intersession),
                   integer(0))
  expect_identical(registration_snapshot_terms(dplyr::bind_rows(snapshot_students, spring),
                                               test_sections_intersession),
                   202110L)
  expect_identical(registration_snapshot_terms(snapshot_students,
                                               dplyr::bind_rows(test_sections_intersession, draft)),
                   202110L)
})

test_that("a pull is written once, read back whole, and a bad file is refused", {
  dir <- tempfile("registration-snapshots-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  first <- record_registration_snapshot(snapshot_students, test_sections_intersession,
                                        snapshot_course_terms(), dir, terms = 202080L)
  expect_equal(first$status, "written")
  expect_equal(basename(first$path),
               "registration-202080-classlist-2020-10-23-schedule-2020-10-23.qs2")
  expect_equal(first$rows, 7L)
  again <- record_registration_snapshot(snapshot_students, test_sections_intersession,
                                        snapshot_course_terms(), dir, terms = 202080L)
  expect_equal(again$status, "already recorded")
  expect_length(list.files(dir), 1L)

  kept <- read_registration_snapshots(dir)
  expect_equal(kept, build_registration_snapshot(
    snapshot_students, test_sections_intersession, snapshot_course_terms(), list(terms = 202080L)
  ), ignore_attr = TRUE)
  expect_equal(nrow(read_registration_snapshots(dir, terms = 202110L)), 0L)

  qs2::qs_save(dplyr::select(kept, -seats),
               file.path(dir, "registration-202110-classlist-none-schedule-2020-11-15.qs2"))
  expect_error(read_registration_snapshots(dir), "missing column\\(s\\): seats")
  expect_error(read_registration_snapshots(file.path(dir, "absent")), "does not exist")
})


# RW01: Fall 2020's students and their Spring 2021 registration, both pulled
# 2020-11-20. See the RW01 block in designed_test_data.R for each student. The
# snapshot reads the student-term table built from those rows (setup.R).
test_that("a return snapshot counts last term's students by what they have done since", {
  snapshot <- build_return_snapshot(test_student_terms_rw, list(terms = 202110L))
  expect_named(snapshot, RETURN_SNAPSHOT_COLUMNS)
  expect_false(any(c("student_id", "enrollment_id") %in% names(snapshot)))
  expect_equal(unique(snapshot$anchor_term), 202080L)
  expect_equal(unique(snapshot$classlist_as_of), as.Date("2020-11-20"))
  expect_equal(unique(snapshot$anchor_classlist_as_of), as.Date("2020-11-20"))
  expect_equal(unique(snapshot$programs_as_of), as.Date("2020-11-20"))

  got <- snapshot %>%
    dplyr::select(dept_code, academic_standing, student_classification,
                  late_withdrawal, dfw_grades, students, registered,
                  waitlisted_only, dropped_only) %>%
    dplyr::arrange(dept_code, academic_standing, late_withdrawal, dfw_grades)
  expected <- tibble::tribble(
    ~dept_code, ~academic_standing,   ~student_classification, ~late_withdrawal, ~dfw_grades,   ~students, ~registered, ~waitlisted_only, ~dropped_only,
    "HIST",     "Academic Probation", "Sophomore",             "none",           "2+",          1L,        0L,          0L,               1L,
    "HIST",     "Good Standing",      "Sophomore",             "all",            "none posted", 1L,        0L,          0L,               0L,
    "HIST",     "Good Standing",      "Sophomore",             "none",           "0",           2L,        1L,          0L,               0L,
    "HIST",     "Good Standing",      "Sophomore",             "none",           "none posted", 1L,        0L,          1L,               0L,
    "MATH",     "Good Standing",      "Junior",                "some",           "1",           1L,        1L,          0L,               0L,
    "SPAN",     NA,                   "Sophomore",             "none",           "0",           1L,        0L,          0L,               0L
  )
  expect_equal(got, expected)
  # RW_F (early drop only) and RW_G (new in Spring) are not last term's
  # students; RW_E's second Major row does not count them twice; RW_E's
  # registration on another campus counts. RW_H has no academic studies row:
  # the major Banner stamped on the roster (SPAN) places them, standing stays
  # unknown.
  expect_equal(sum(snapshot$students), 7L)
  expect_equal(sum(snapshot$registered), 2L)
})

test_that("a return snapshot refuses Summer, an unopened term, and a table without its columns", {
  expect_error(build_return_snapshot(test_student_terms_rw, list()),
               "opt\\$terms is required")
  expect_error(build_return_snapshot(test_student_terms_rw, list(terms = 202160L)),
               "not Fall or Spring")
  expect_error(build_return_snapshot(dplyr::filter(test_student_terms_rw, term != 202110L),
                                     list(terms = 202110L)),
               "registration has not opened")
  # A declaration alone is not registration: RW_C's Spring program row does
  # not open the term.
  declared_only <- dplyr::filter(test_student_terms_rw,
                                 term != 202110L | class_list_rows == 0L)
  expect_error(build_return_snapshot(declared_only, list(terms = 202110L)),
               "registration has not opened")
  no_programs <- test_student_terms_rw %>%
    dplyr::mutate(programs_as_of = dplyr::if_else(term == 202080L, as.Date(NA), programs_as_of))
  expect_error(build_return_snapshot(no_programs, list(terms = 202110L)),
               "no programs pull date for term 202080")
  expect_error(build_return_snapshot(dplyr::select(test_student_terms_rw, -late_withdrawals),
                                     list(terms = 202110L)),
               "missing column\\(s\\): late_withdrawals")
})

test_that("a return snapshot describes students as the student-term table does", {
  # The class list calls RW_A a Junior in Fall 2020; academic studies says
  # Sophomore. The table's precedence (programs wins, the conflict flagged) is
  # the snapshot's: it never re-reads the class list.
  disagreeing <- test_students_rw %>%
    dplyr::mutate(student_classification = dplyr::if_else(
      student_id == "RW_A" & term == 202080L, "Junior", student_classification))
  st <- attach_test_student_terms(suppressMessages(build_student_terms(
    disagreeing, test_programs_rw, edges = list(last_enrolled_complete = 202080L))))
  expect_true(st$description_conflict[st$student_id == "RW_A" & st$term == 202080L])
  snapshot <- build_return_snapshot(st, list(terms = 202110L))
  expect_equal(snapshot, build_return_snapshot(test_student_terms_rw, list(terms = 202110L)))
  # And the population is the table's `enrolled`: dropping RW_D's late
  # withdrawals to early drops removes them from it.
  never_attended <- test_students_rw %>%
    dplyr::mutate(registration_status_code = dplyr::if_else(
      student_id == "RW_D", "DR", registration_status_code))
  st2 <- attach_test_student_terms(suppressMessages(build_student_terms(
    never_attended, test_programs_rw, edges = list(last_enrolled_complete = 202080L))))
  expect_equal(sum(build_return_snapshot(st2, list(terms = 202110L))$students), 6L)
})

test_that("return snapshot terms are the Fall and Spring terms whose registration has opened", {
  # Fall 2020, pulled in November, has settled; Spring 2021 is in registration.
  # A Summer 2021 class list is in registration too, but is never a target.
  expect_identical(return_snapshot_terms(test_students_rw), 202110L)
  summer <- test_students_rw %>%
    dplyr::filter(student_id == "RW_G") %>%
    dplyr::mutate(term = 202160L, term_type = "summer")
  expect_identical(return_snapshot_terms(dplyr::bind_rows(test_students_rw, summer)),
                   202110L)
  fall_only <- dplyr::filter(test_students_rw, term == 202080L)
  expect_identical(return_snapshot_terms(fall_only), integer(0))
})

test_that("a return snapshot is written once, read back whole, and a bad file is refused", {
  dir <- tempfile("return-snapshots-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  first <- record_return_snapshot(test_students_rw, test_student_terms_rw, dir)
  expect_equal(first$status, "written")
  expect_equal(basename(first$path),
               "return-202110-classlist-2020-11-20-anchor-2020-11-20-programs-2020-11-20.qs2")
  expect_equal(c(first$rows, first$students, first$registered), c(6L, 7L, 2L))
  again <- record_return_snapshot(test_students_rw, test_student_terms_rw, dir)
  expect_equal(again$status, "already recorded")
  expect_length(list.files(dir), 1L)

  kept <- read_return_snapshots(dir)
  expect_equal(kept, build_return_snapshot(test_student_terms_rw, list(terms = 202110L)),
               ignore_attr = TRUE)
  expect_equal(nrow(read_return_snapshots(dir, terms = 202180L)), 0L)
  # The two kinds of snapshot share the directory and never read each other.
  expect_equal(nrow(read_registration_snapshots(dir)), 0L)

  qs2::qs_save(dplyr::mutate(kept, registered = students + 1L),
               file.path(dir, "return-202180-classlist-2021-04-01-anchor-2021-04-01-programs-2021-04-01.qs2"))
  expect_error(read_return_snapshots(dir), "counts exceed its students")
})
