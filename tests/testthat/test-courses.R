# The course dimension (ADR-001 step 4): one course_id per code, through the
# confirmed successions in institution/<id>/code_history.csv. Fixtures: RN01
# (designed_test_data.R) read with the demo institution's file (demo_dims()).

test_that("every code gets one course_id, following confirmed successions step by step", {
  cc <- suppressMessages(build_cedar_courses(test_sections_rn, test_students_rn, demo_dims()))
  expect_s3_class(cc, "cedar_courses")
  codes <- cc$codes
  expect_equal(names(codes), CEDAR_COURSE_CODES_COLUMNS)
  expect_equal(nrow(codes), 11L)
  id_of <- function(code) codes$course_id[codes$subject_course == code]
  steps_of <- function(code) codes$steps[codes$subject_course == code]
  # The subject rename: one step.
  expect_equal(id_of("SOC 371"), "SOCI 371")
  expect_equal(steps_of("SOC 371"), 1L)
  expect_equal(id_of("SOCI 371"), "SOCI 371")
  # A chain across kinds: the subject's rename, then the course's renumbering.
  expect_equal(id_of("SOC 250"), "SOCI 2315")
  expect_equal(steps_of("SOC 250"), 2L)
  expect_equal(id_of("SOCI 250"), "SOCI 2315")
  expect_equal(id_of("HIST 320"), "HIST 3201")
  # A proposed row assigns nothing.
  expect_equal(id_of("PHIL 150"), "PHIL 150")
  expect_equal(id_of("PHIL 1115"), "PHIL 1115")
  # A class-list-only code is a row, never dropped.
  expect_equal(id_of("SOCI 2120"), "SOCI 2120")
  expect_false(codes$in_sections[codes$subject_course == "SOCI 2120"])
  expect_true(codes$in_class_lists[codes$subject_course == "SOCI 2120"])
  # SOC 371's class list already read SOCI 371, so that code is on both tables
  # from Spring 2020 while the schedule's SOC 371 is sections-only (I45).
  expect_false(codes$in_class_lists[codes$subject_course == "SOC 371"])
  expect_equal(codes$first_term[codes$subject_course == "SOCI 371"], 202010L)
})

test_that("a course's row spans every code it has carried", {
  cc <- suppressMessages(build_cedar_courses(test_sections_rn, test_students_rn, demo_dims()))
  courses <- cc$courses
  expect_equal(names(courses), CEDAR_COURSES_COLUMNS)
  expect_equal(nrow(courses), 7L)
  expect_setequal(courses$course_id,
                  c("SOCI 371", "SOCI 2315", "HIST 3201", "PHIL 150", "PHIL 1115", "SOCI 2120", "LING 2110"))
  sp <- courses[courses$course_id == "SOCI 2315", ]
  expect_equal(sp$n_codes, 3L)
  expect_equal(sp$former_codes, "SOC 250, SOCI 250")
  expect_equal(c(sp$first_term, sp$last_term), c(202010L, 202110L))
  expect_equal(sp$course_title, "Social Problems")
  expect_equal(c(sp$subject, sp$course_number, sp$level), c("SOCI", "2315", "lower"))
  # SOCI 371's history begins where SOC 371's did (I45).
  expect_equal(courses$first_term[courses$course_id == "SOCI 371"], 202010L)
  expect_equal(courses$former_codes[courses$course_id == "SOCI 371"], "SOC 371")
  # One code, one course: nothing to list.
  expect_true(is.na(courses$former_codes[courses$course_id == "LING 2110"]))
  expect_equal(courses$n_codes[courses$course_id == "LING 2110"], 1L)
})

test_that("the main fixtures build one course per code: the demo file touches none of them", {
  cc <- suppressMessages(build_cedar_courses(test_sections, test_students, demo_dims()))
  expect_equal(nrow(cc$courses), nrow(cc$codes))
  expect_true(all(cc$codes$steps == 0L))
  expect_setequal(cc$codes$subject_course, union(test_sections$subject_course, test_students$subject_course))
})

test_that("attach_course_ids keys each table on the course, the registrar's code in listed_code", {
  cc <- suppressMessages(build_cedar_courses(test_sections_rn, test_students_rn, demo_dims()))
  stale <- dplyr::mutate(test_sections_rn, course_id = "STALE")
  attr(stale, "cedar_provenance") <- "kept"
  out <- suppressMessages(attach_course_ids(
    list(cedar_sections = stale, cedar_registrations = test_students_rn, cedar_programs = test_programs), cc))
  secs <- out$cedar_sections
  # subject_course is the course; the code the schedule used that term is kept.
  expect_equal(secs$subject_course[secs$listed_code == "SOC 371"], "SOCI 371")
  expect_equal(secs$subject_course[secs$listed_code == "PHIL 150"], "PHIL 150")
  expect_equal(secs$listed_code, test_sections_rn$subject_course)
  expect_equal(secs$course_id, secs$subject_course)
  expect_false(any(secs$course_id == "STALE"))
  expect_equal(attr(secs, "cedar_provenance"), "kept")
  expect_equal(out$cedar_registrations$subject_course[out$cedar_registrations$listed_code == "SOCI 250"], "SOCI 2315")
  expect_false("course_id" %in% names(out$cedar_programs))
  # Keying a keyed table again reads its listed_code: the same table.
  again <- suppressMessages(attach_course_ids(out["cedar_sections"], cc))$cedar_sections
  expect_identical(again, secs)
  # The code-level functions read the registrar's code off a keyed table.
  expect_equal(suppressMessages(build_cedar_courses(secs, out$cedar_registrations, demo_dims()))$codes, cc$codes)
  # A table with a code the dimension never saw is a stop, not an NA.
  expect_error(suppressMessages(attach_course_ids(list(cedar_sections = test_sections), cc)),
               "does not know")
})

test_that("resolve_course_codes refuses a malformed code and a cycle the validator missed", {
  history <- demo_files()$code_history
  expect_error(resolve_course_codes(c("SOCI 371", "SOCI371"), history), "SUBJECT NUMBER")
  looped <- rbind(history,
                  data.frame(kind = "course", from_code = c("MATH 1", "MATH 2"), to_code = c("MATH 2", "MATH 1"),
                             effective_term = "202080", scope = "", basis = "catalog", status = "confirmed",
                             evidence = "", notes = ""))
  expect_error(resolve_course_codes("MATH 1", looped), "cycle")
})

test_that("detect_course_renamings finds the shared section and the one-to-one title match", {
  files <- demo_files()
  cand <- detect_course_renamings(test_sections_rn, test_students_rn, files)
  subj <- cand[cand$kind == "subject", ]
  expect_equal(nrow(subj), 1L)
  expect_equal(c(subj$from_code, subj$to_code, subj$basis), c("SOC", "SOCI", "section_crn"))
  expect_equal(subj$n_evidence, 2L)              # RN01A and RN01C
  expect_equal(subj$effective_term, 202080L)      # SOCI first on the schedule
  expect_equal(subj$in_file, "confirmed")
  expect_match(subj$evidence, "2 sections \\(Spring 2020\\) carry SOC on the schedule and SOCI on the class list")
  crs <- cand[cand$kind == "course", ]
  # Pairs the file already joins (HIST 320, SOCI 250) are not candidates.
  expect_equal(nrow(crs), 1L)
  expect_equal(c(crs$from_code, crs$to_code, crs$basis), c("PHIL 150", "PHIL 1115", "title_match"))
  expect_equal(crs$effective_term, 202080L)
  expect_equal(crs$in_file, "proposed")
  expect_match(crs$evidence, "^Introduction to Logic retired as PHIL 150 after Spring 2020 and began as PHIL 1115 in Fall 2020")

  # With nothing in the file: HIST 320's renumbering is found; "Social
  # Problems" has two retired codes (SOC 250, SOCI 250) and is left to a person.
  files$code_history <- files$code_history[0, ]
  bare <- detect_course_renamings(test_sections_rn, test_students_rn, files)
  expect_true(all(is.na(bare$in_file)))
  expect_setequal(paste(bare$from_code, bare$to_code),
                  c("SOC SOCI", "HIST 320 HIST 3201", "PHIL 150 PHIL 1115"))
  # With only the subject rename confirmed, the two retired codes are one
  # course, and the renumbering is found under the resolved code.
  files$code_history <- demo_files()$code_history
  files$code_history <- files$code_history[files$code_history$kind == "subject", ]
  one <- detect_course_renamings(test_sections_rn, test_students_rn, files)
  expect_true("SOCI 250 SOCI 2315" %in% paste(one$from_code, one$to_code))
  expect_false("SOC 250 SOCI 2315" %in% paste(one$from_code, one$to_code))

  # A file that joins the two sections' codes course by course (as UNM's joins
  # each CCST nnn to its CCS nnn, CCS staying the upper-division prefix) gets
  # no subject candidate for them.
  history <- demo_files()$code_history
  history <- history[history$kind != "subject", ]
  files$code_history <- rbind(history, data.frame(
    kind = "course", from_code = c("SOC 371", "SOC 250"), to_code = c("SOCI 371", "SOCI 250"),
    effective_term = "202010", scope = "", basis = "section_crn", status = "confirmed",
    evidence = "", notes = ""))
  by_course <- detect_course_renamings(test_sections_rn, test_students_rn, files)
  expect_false(any(by_course$kind == "subject"))
})

test_that("course_id_of resolves any code a loaded table carries to its course", {
  rn <- rn01_course_tables()
  keyed <- rn$cedar_sections
  # Any code the course has carried names it; a code the table does not carry
  # is its own course.
  expect_equal(course_id_of(rn$cedar_sections, "SOC 371"), "SOCI 371")
  expect_equal(course_id_of(rn$cedar_sections, "SOCI 371"), "SOCI 371")
  expect_equal(course_id_of(keyed, "SOC 250"), "SOCI 2315")
  expect_equal(course_id_of(keyed, "SOCI 2315"), "SOCI 2315")
  expect_equal(course_id_of(rn$cedar_sections, "MATH 9999"), "MATH 9999")
  expect_error(course_id_of(rn$cedar_sections, c("SOC 371", "SOCI 371")), "one course code")
  expect_error(course_id_of(test_sections_rn, "SOC 371"), "needs columns course_id and listed_code")

  # The codes a course has been listed under, and the renames a frame shows.
  expect_equal(course_codes_of(rn$cedar_sections, "SOCI 2315"), c("SOC 250", "SOCI 2315"))
  expect_equal(course_codes_of(keyed, "HIST 3201"), c("HIST 320", "HIST 3201"))
  expect_equal(course_codes_of(rn$cedar_sections, "LING 2110"), "LING 2110")
  expect_equal(
    course_code_renames(rn$cedar_sections),
    c("HIST 320 > HIST 3201", "SOC 250 > SOCI 2315", "SOC 371 > SOCI 371")
  )
  # The class list already carries SOCI on the old SOC sections.
  expect_equal(course_code_renames(rn$cedar_registrations), c("HIST 320 > HIST 3201", "SOCI 250 > SOCI 2315"))
  expect_equal(course_code_renames(test_sections), character(0))
})

test_that("course_former_code_spans names each course's former codes with their terms", {
  rn <- rn01_course_tables()
  spans <- course_former_code_spans(rn$cedar_registrations, rn$cedar_sections)
  expect_equal(spans$subject_course, c("HIST 3201", "SOCI 2315", "SOCI 371"))
  expect_equal(spans$former_codes, c(
    "HIST 320 (Spring 2020 to Fall 2020)",
    "SOC 250 (Spring 2020), SOCI 250 (Spring 2020)",
    "SOC 371 (Spring 2020)"
  ))
  # One table names only the codes it carries.
  secs <- course_former_code_spans(rn$cedar_sections)
  expect_equal(secs$subject_course, c("HIST 3201", "SOCI 2315", "SOCI 371"))
  expect_equal(secs$former_codes[secs$subject_course == "SOCI 2315"], "SOC 250 (Spring 2020)")
  # No renames: no rows, the two columns.
  none <- course_former_code_spans(test_sections, test_students)
  expect_equal(nrow(none), 0L)
  expect_equal(names(none), c("subject_course", "former_codes"))
  expect_error(course_former_code_spans(dplyr::select(test_sections, -course_id)), "course_id")
})

test_that("course_ids_of resolves picked codes, current or former, over a reader's tables", {
  rn <- rn01_course_tables()
  expect_equal(course_ids_of("SOC 250, HIST 3201", rn$cedar_sections, rn$cedar_registrations),
               c("SOCI 2315", "HIST 3201"))
  # Two codes of one course are one id.
  expect_equal(course_ids_of(c("SOC 371", "SOCI 371"), rn$cedar_sections), "SOCI 371")
  # A code no table carries is its own course; no pick is NULL.
  expect_equal(course_ids_of("ZZZ 101", rn$cedar_sections), "ZZZ 101")
  expect_null(course_ids_of(NULL, rn$cedar_sections))
  expect_null(course_ids_of("", rn$cedar_sections))
  expect_error(course_ids_of("SOC 371", dplyr::select(rn$cedar_sections, -course_id)), "course_id")
})
