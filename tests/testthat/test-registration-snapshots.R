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
snapshot_students <- function() {
  dplyr::bind_rows(test_students_intersession, test_students_wlmkt)
}

test_that("a snapshot counts each campus and part of term on its own row", {
  snapshot <- build_registration_snapshot(
    snapshot_students(), test_sections_intersession, list(terms = 202080L)
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
  snapshot <- build_registration_snapshot(test_students, test_sections,
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
  ahead <- build_registration_snapshot(snapshot_students(), draft,
                                       list(terms = 202110L))
  expect_equal(nrow(ahead), 3L)
  expect_true(all(is.na(ahead$classlist_as_of)))
  expect_true(all(is.na(ahead$registered) & is.na(ahead$waitlisted) &
                    is.na(ahead$dr_early) & is.na(ahead$dr_late)))
  expect_equal(sum(ahead$sections), 3L)
  expect_equal(sum(ahead$seats), 65)
  # And the reverse: a class list with no schedule rows for its term.
  unscheduled <- build_registration_snapshot(
    snapshot_students(), test_sections_intersession[0, ], list(terms = 202080L)
  )
  expect_true(all(is.na(unscheduled$sections_as_of) & is.na(unscheduled$sections) &
                    is.na(unscheduled$seats)))
  expect_equal(sum(unscheduled$registered), 9L)
})

test_that("a snapshot refuses a term with no rows and a call with no terms", {
  expect_error(build_registration_snapshot(snapshot_students(), test_sections_intersession),
               "opt\\$terms is required")
  expect_error(build_registration_snapshot(snapshot_students(), test_sections_intersession,
                                           list(terms = c(202080L, 202110L))),
               "no class-list or section rows for term\\(s\\) 202110")
  expect_error(build_registration_snapshot(
    dplyr::select(snapshot_students(), -as_of_date), test_sections_intersession,
    list(terms = 202080L)), "as_of_date")
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
  expect_identical(registration_snapshot_terms(snapshot_students(), test_sections_intersession),
                   integer(0))
  expect_identical(registration_snapshot_terms(dplyr::bind_rows(snapshot_students(), spring),
                                               test_sections_intersession),
                   202110L)
  expect_identical(registration_snapshot_terms(snapshot_students(),
                                               dplyr::bind_rows(test_sections_intersession, draft)),
                   202110L)
})

test_that("a pull is written once, read back whole, and a bad file is refused", {
  dir <- tempfile("registration-snapshots-")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  first <- record_registration_snapshot(snapshot_students(), test_sections_intersession,
                                        dir, terms = 202080L)
  expect_equal(first$status, "written")
  expect_equal(basename(first$path),
               "registration-202080-classlist-2020-10-23-schedule-2020-10-23.qs2")
  expect_equal(first$rows, 7L)
  again <- record_registration_snapshot(snapshot_students(), test_sections_intersession,
                                        dir, terms = 202080L)
  expect_equal(again$status, "already recorded")
  expect_length(list.files(dir), 1L)

  kept <- read_registration_snapshots(dir)
  expect_equal(kept, build_registration_snapshot(
    snapshot_students(), test_sections_intersession, list(terms = 202080L)
  ), ignore_attr = TRUE)
  expect_equal(nrow(read_registration_snapshots(dir, terms = 202110L)), 0L)

  qs2::qs_save(dplyr::select(kept, -seats),
               file.path(dir, "registration-202110-classlist-none-schedule-2020-11-15.qs2"))
  expect_error(read_registration_snapshots(dir), "missing column\\(s\\): seats")
  expect_error(read_registration_snapshots(file.path(dir, "absent")), "does not exist")
})
