# Courses > Low Enrollment: the page's payload and view shapes
# (R/features/low-enrollment.R). The counting underneath is tested in
# test-low-enrollment.R; these hold what the page adds: which view the chosen
# terms get, the rows a run lists, the band each is counted in, and what each
# table and note says.
#
# The fixtures' current term is Fall 2020 (202080). Spring 2020 (202010) has
# four small active HIST sections at the standard thresholds (lower 12, upper
# 12, split 10, graduate 5):
#   HIST 480-001  upper, a class of 12                       threshold 12  watch
#   HIST 490-001  upper, a class of 15                       threshold 12  just over it
#   HIST 484-001  split, 8 of its own in a combined 11       threshold 10  just over it
#   HIST 475-001  split, a class of 10                       threshold 10  watch
context("Low Enrollment page")

test_that("a term with registrations is listed by section, and a schedule nobody has registered for is checked against history", {
  registered <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                          current_term = 202080L, min_days_after_start = 14L)
  expect_equal(registered$mode, "alerts")
  expect_setequal(paste(registered$review$subject_course, registered$review$section),
                  c("HIST 480 001", "HIST 490 001", "HIST 484 001", "HIST 475 001"))

  # SC01: Spring 2021 scheduled, nobody registered.
  schedule <- build_low_enrollment_page(test_sections_schedule, list(term = "202110"),
                                        current_term = 202080L, min_days_after_start = 14L)
  expect_equal(schedule$mode, "concerns")
  # Five of the six scheduled courses have no spring history; HIST 411 averaged
  # 20, well over its threshold of 12, and is not listed.
  expect_setequal(schedule$review$subject_course,
                  c("HIST 412", "HIST 413", "HIST 414", "HIST 415", "HIST 416"))
})

test_that("terms of both kinds give no rows, and a term type is named as one", {
  testthat::local_edition(3)
  mixed <- build_low_enrollment_page(test_sections_schedule,
                                     list(term = c("202080", "202110", "fall")),
                                     current_term = 202080L, min_days_after_start = 14L)
  expect_equal(mixed$mode, "mixed")
  expect_null(mixed$review)
  expect_false(low_enrollment_has_rows(mixed))
  expect_length(low_enrollment_view_notes(mixed), 0L)
  expect_snapshot(cat(low_enrollment_mixed_terms_note(mixed)))
})

test_that("a run reads active sections under the excluded-course list, whatever it is handed", {
  page <- build_low_enrollment_page(test_sections,
                                    list(term = "202010", status = "C", uel = FALSE),
                                    current_term = 202080L, min_days_after_start = 14L)
  expect_equal(page$opt$status, "A")
  expect_true(page$opt$uel)
  expect_true(all(page$review$status == "A"))
})

test_that("a run stops without a term, on a blank threshold or a blank smallest section", {
  run <- function(opt = list(term = "202010"), ...) {
    build_low_enrollment_page(test_sections, opt, ..., current_term = 202080L,
                              min_days_after_start = 14L)
  }
  expect_error(run(list(dept_code = "HIST")), "at least one term")
  expect_error(run(thresholds = c(lower = NA, upper = 12, split = 10, grad = 5)), "lower = NA")
  expect_error(run(thresholds = c(lower = 0, upper = 12, split = 10, grad = 5)), "1 or more")
  expect_error(run(min_enrl = NA), "min_enrl is one number")
})

test_that("a scope with nothing small lists nothing, and says so as a result", {
  testthat::local_edition(3)
  # No lower-division section in Spring 2020 is at or near its threshold.
  none <- build_low_enrollment_page(test_sections, list(term = "202010", level = "lower"),
                                    current_term = 202080L, min_days_after_start = 14L)
  expect_equal(none$mode, "alerts")
  expect_false(low_enrollment_has_rows(none))
  expect_null(low_enrollment_level_rows(none, "lower"))
  expect_error(summarize_low_enrollment_bands(none), "a run that lists rows")
  expect_error(low_enrollment_download_table(none), "a run that lists rows")
  expect_error(low_enrollment_first_level(none), "a run that listed rows")
  expect_snapshot(cat(low_enrollment_empty_note(none)))
  expect_snapshot(cat(low_enrollment_empty_note(list(mode = "concerns"))))
})

test_that("the smallest section a run lists is its own setting", {
  from_one <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                        current_term = 202080L, min_days_after_start = 14L)
  from_zero <- build_low_enrollment_page(test_sections, list(term = "202010"), min_enrl = 0L,
                                         current_term = 202080L, min_days_after_start = 14L)
  expect_equal(nrow(from_one$review), 4L)
  expect_equal(nrow(from_zero$review), 5L)   # EC-01's active section nobody is in
  expect_equal(from_zero$min_enrl, 0L)
})

test_that("each level tab holds its own rows, and a split crosslist is in the split tab alone", {
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    current_term = 202080L, min_days_after_start = 14L)
  tab <- function(level) {
    rows <- low_enrollment_level_rows(page, level)
    paste(rows$subject_course, rows$section)
  }
  expect_setequal(tab("upper"), c("HIST 480 001", "HIST 490 001"))
  expect_setequal(tab("split"), c("HIST 484 001", "HIST 475 001"))   # both are upper-level sections
  expect_length(tab("lower"), 0L)
  expect_length(tab("grad"), 0L)
  # The page opens on the first level that lists anything, not on an empty one.
  expect_identical(low_enrollment_first_level(page), "upper")
  # Every listed row is in exactly one tab.
  expect_equal(sum(vapply(names(LOW_ENROLLMENT_LEVELS),
                          function(level) nrow(low_enrollment_level_rows(page, level)), integer(1))),
               nrow(page$review))
  expect_error(low_enrollment_level_rows(page, "undergrad"), "one level of")
})

test_that("the thresholds are the run's: rows are fetched, kept and judged under them", {
  standard <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                        current_term = 202080L, min_days_after_start = 14L)
  raised <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                      thresholds = c(lower = 20, upper = 20, split = 20, grad = 20),
                                      current_term = 202080L, min_days_after_start = 14L)
  expect_equal(nrow(standard$review), 4L)
  # A run at 20 lists the lower-division sections a run at 12 never fetched.
  expect_equal(nrow(raised$review), 15L)
  expect_equal(as.list(table(raised$review$.level_group)),
               list(grad = 1L, lower = 9L, split = 2L, upper = 3L))
  expect_equal(unique(raised$review$.threshold), 20)
  expect_equal(raised$thresholds, c(lower = 20, upper = 20, split = 20, grad = 20))
  # One level's threshold moves that level alone.
  upper_six <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                         thresholds = c(upper = 6),
                                         current_term = 202080L, min_days_after_start = 14L)
  expect_setequal(upper_six$review$subject_course, c("HIST 484", "HIST 475"))
})

test_that("a section's band is its class against its own threshold, and a crosslisted section's class is the combined one", {
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    current_term = 202080L, min_days_after_start = 14L)
  band <- setNames(page$review$.band, page$review$subject_course)
  expect_equal(band[["HIST 480"]], "watch")    # 12 of 12
  expect_equal(band[["HIST 490"]], "buffer")   # 15 over 12
  expect_equal(band[["HIST 475"]], "watch")    # 10 of 10
  # HIST 484 has 8 students of its own in a combined class of 11, over its
  # threshold of 10. Judged on its own 8 it would be a watch.
  expect_equal(band[["HIST 484"]], "buffer")
  expect_equal(page$review$.band, page$review$severity)

  counts <- summarize_low_enrollment_bands(page)
  expect_equal(counts[c("critical", "warning", "watch", "buffer", "total")],
               list(critical = 0L, warning = 0L, watch = 2L, buffer = 2L, total = 4L))
  # The students are the listed sections' own.
  expect_equal(counts$students, 45L)
  expect_equal(counts$mean_enrolled, 11.25)
  expect_false("no_history" %in% names(counts))
})

test_that("a schedule check counts each course in the band of its average, and one with no history apart", {
  # Spring 2021 before registration opened: the same schedule, nobody enrolled yet.
  schedule_only <- test_sections %>% mutate(enrolled = replace(enrolled, term == 202110L, 0))
  page <- build_low_enrollment_page(schedule_only, list(term = "202110"),
                                    thresholds = c(lower = 30, upper = 30, split = 30, grad = 30),
                                    current_term = 202080L, min_days_after_start = 14L)
  counts <- summarize_low_enrollment_bands(page)
  # Against a threshold of 30: one average under 15, seven from 15 to under
  # 22.5, four from 22.5 to under 30, and ANTH 1140's 30 exactly, which has met it.
  expect_equal(counts[c("critical", "warning", "watch", "buffer", "no_history", "total")],
               list(critical = 1L, warning = 7L, watch = 4L, buffer = 1L, no_history = 2L, total = 15L))
  expect_equal(sum(unlist(counts[c("critical", "warning", "watch", "buffer", "no_history")])),
               counts$total)
  band <- setNames(page$review$.band, paste(page$review$subject_course, page$review$campus))
  expect_equal(band[["ANTH 1140 ABQ"]], "buffer")
  expect_equal(band[["HIST 601 ABQ"]], "critical")   # averaged 12
  # No same-season history is not an average of zero.
  expect_equal(band[["ENGL 2210 ABQ"]], "no_history")
  expect_true(all(is.na(page$review$avg_enrl[page$review$.band == "no_history"])))
  expect_false("students" %in% names(counts))
})

test_that("the cards say what each band is, in each view's own words", {
  testthat::local_edition(3)
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(as.data.frame(low_enrollment_summary_cards(summarize_low_enrollment_bands(page), "alerts")))

  schedule <- build_low_enrollment_page(test_sections_schedule, list(term = "202110"),
                                        current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(as.data.frame(low_enrollment_summary_cards(summarize_low_enrollment_bands(schedule), "concerns")))
  expect_error(low_enrollment_summary_cards(list(), "mixed"), "no cards for mode")
})

test_that("a registrations table shows the section, its three counts and its history, smallest first", {
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    current_term = 202080L, min_days_after_start = 14L)
  upper <- low_enrollment_display_table(low_enrollment_level_rows(page, "upper"), "alerts")
  expect_named(upper, c("Campus", "Dept", "Course", "Sect#", "Title", "Term", "Sects",
                        "Enrolled", "XL Total", "Course Total", "Prior History", ".band"))
  expect_equal(upper$Course, c("HIST 480", "HIST 490"))
  expect_equal(upper$Enrolled, c(12L, 15L))
  expect_equal(upper$`Prior History`, c("No history", "12 (Fa20)"))
  expect_equal(upper$.band, c("watch", "buffer"))

  # The Split tab names each crosslist's partners; its own students and the
  # combined class are separate columns, and the band follows the combined one.
  split <- low_enrollment_display_table(low_enrollment_level_rows(page, "split"), "alerts",
                                        split_partners = TRUE)
  expect_named(split, c("Campus", "Dept", "Course", "Sect#", "Split Partners", "Title", "Term",
                        "Sects", "Enrolled", "XL Total", "Course Total", "Prior History", ".band"))
  expect_equal(split$Course, c("HIST 484", "HIST 475"))
  expect_equal(split$`Split Partners`, c("HIST 484 / HIST 584", "AMST 475 / HIST 475 / HIST 575"))
  expect_equal(split$Enrolled, c(8L, 10L))
  expect_equal(split$`XL Total`, c(11L, 10L))
  expect_equal(split$.band, c("buffer", "watch"))
  # Partners are the Split tab's column: the same rows elsewhere go without it.
  expect_false("Split Partners" %in%
                 names(low_enrollment_display_table(low_enrollment_level_rows(page, "split"), "alerts")))
  # The column coloured is the one judged, and each view has one.
  expect_true(LOW_ENROLLMENT_JUDGED_COLUMN[["alerts"]] %in% names(upper))
})

test_that("each table lists the smallest first, whatever order the rows arrive in", {
  # At thresholds of 20 the lower-division tab has nine sections, which arrive
  # by campus, department and title.
  sections <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                        thresholds = c(lower = 20, upper = 20, split = 20, grad = 20),
                                        current_term = 202080L, min_days_after_start = 14L)
  arriving <- low_enrollment_level_rows(sections, "lower")
  expect_true(is.unsorted(arriving$enrolled))
  expect_equal(low_enrollment_display_table(arriving, "alerts")$Enrolled,
               c(18L, 20L, 20L, 21L, 22L, 22L, 22L, 24L, 25L))

  schedule_only <- test_sections %>% mutate(enrolled = replace(enrolled, term == 202110L, 0))
  schedule <- build_low_enrollment_page(schedule_only, list(term = "202110"),
                                        thresholds = c(lower = 30, upper = 30, split = 30, grad = 30),
                                        current_term = 202080L, min_days_after_start = 14L)
  arriving <- low_enrollment_level_rows(schedule, "lower")
  expect_equal(arriving$avg_enrl[1], 30)
  # A course with no average sorts last, never first as a zero would.
  expect_equal(low_enrollment_display_table(arriving, "concerns")$`Hist Avg`,
               c(20, 21, 22, 22, 22, 24, 25, 28, 30, NA, NA))
})

test_that("a list too long for history lines says so, and its sections show a dash", {
  testthat::local_edition(3)
  # Four sections against a limit of two: the run is too long for history.
  long <- build_low_enrollment_page(test_sections, list(term = "202010"), history_limit = 2L,
                                    current_term = 202080L, min_days_after_start = 14L)
  expect_true(long$history_skipped)
  upper <- low_enrollment_display_table(low_enrollment_level_rows(long, "upper"), "alerts")
  expect_equal(upper$`Prior History`, c("—", "—"))
  notes <- low_enrollment_view_notes(long)
  expect_snapshot(notes[[length(notes)]])

  short <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                     current_term = 202080L, min_days_after_start = 14L)
  expect_false(short$history_skipped)
})

test_that("a schedule-check table shows each course's average and history, and where else a course with none has run", {
  schedule <- build_low_enrollment_page(test_sections_schedule, list(term = "202110"),
                                        thresholds = c(lower = 30, upper = 30, split = 30, grad = 30),
                                        current_term = 202080L, min_days_after_start = 14L)
  upper <- low_enrollment_display_table(low_enrollment_level_rows(schedule, "upper"), "concerns")
  expect_named(upper, c("Campus", "Department", "Course", "Title", "Sects", "Hist Avg", "Trend",
                        "# Terms", "Prior History", ".band"))
  # The one course with an average comes first; the rest have none and follow.
  expect_equal(upper$Course[1], "HIST 411")
  expect_equal(upper$`Hist Avg`, c(20, NA, NA, NA, NA, NA))
  expect_equal(upper$.band, c("warning", rep("no_history", 5)))   # 20 is two thirds of 30
  history <- setNames(upper$`Prior History`, upper$Course)
  expect_equal(history[["HIST 411"]], "20 (Sp20)")
  expect_equal(history[["HIST 412"]], "None in spring on ABQ; other offerings: 16 (ABQ Fa20)")
  expect_equal(history[["HIST 415"]], "No earlier offering")
  expect_true(LOW_ENROLLMENT_JUDGED_COLUMN[["concerns"]] %in% names(upper))
})

test_that("a table stops on a view it does not draw or a missing column, and is nothing for no rows", {
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    current_term = 202080L, min_days_after_start = 14L)
  upper <- low_enrollment_level_rows(page, "upper")
  expect_null(low_enrollment_display_table(upper[0, ], "alerts"))
  expect_null(low_enrollment_display_table(NULL, "alerts"))
  expect_error(low_enrollment_display_table(upper, "mixed"), "no table for mode")
  expect_error(low_enrollment_display_table(select(upper, -course_enrl), "alerts"), "course_enrl")
  expect_error(low_enrollment_display_table(upper, "concerns"), "avg_enrl")
})

test_that("counts still moving, and a schedule check, are said above the list; settled counts need no note", {
  testthat::local_edition(3)
  # The fixtures' pulls are dated days after each term's start: registration unsettled.
  moving <- build_low_enrollment_page(test_sections, list(term = "202080"),
                                      current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(low_enrollment_view_notes(moving))

  schedule <- build_low_enrollment_page(test_sections_schedule, list(term = "202110"),
                                        current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(low_enrollment_view_notes(schedule))

  # The same Fall 2020 rows pulled a month into the term, after add/drop.
  later <- test_sections %>% mutate(as_of_date = as_of_date + 30L)
  settled <- build_low_enrollment_page(later, list(term = "202080"),
                                       current_term = 202080L, min_days_after_start = 14L)
  expect_length(low_enrollment_view_notes(settled), 0L)
})

test_that("the scope bar states the view, the run's filters, the pulls, the thresholds and how many are listed", {
  testthat::local_edition(3)
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    thresholds = c(upper = 15), min_enrl = 0L,
                                    current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(str(describe_low_enrollment_scope(page)))

  schedule <- build_low_enrollment_page(test_sections_schedule, list(term = "202110"),
                                        current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(str(describe_low_enrollment_scope(schedule)))

  mixed <- build_low_enrollment_page(test_sections_schedule, list(term = c("202080", "202110")),
                                     current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(str(describe_low_enrollment_scope(mixed)))

  # The filters a run was made with are named; an empty campus or department
  # choice is every one of them, and the rest appear only when chosen.
  scope_of <- function(opt) {
    describe_low_enrollment_scope(build_low_enrollment_page(
      test_sections, c(list(term = "202010"), opt),
      current_term = 202080L, min_days_after_start = 14L))
  }
  expect_snapshot(str(scope_of(list(course_campus = c("ABQ", "EA"), dept_code = "HIST",
                                    level = c("upper", "grad")))))
  # One section listed is "1 section".
  expect_snapshot(str(scope_of(list(course_college = "ARTS", pt = "1", im = "ONL"))))
  expect_error(describe_low_enrollment_scope(modifyList(page, list(opt = list(level = "undergrad")))),
               "Unknown level")
})

test_that("each view's section says what it lists and how it is counted", {
  testthat::local_edition(3)
  page <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                    current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(str(low_enrollment_section_words("alerts")))
  expect_snapshot(cat(low_enrollment_method_notes(page), sep = "\n\n"))

  schedule <- build_low_enrollment_page(test_sections_schedule, list(term = "202110"),
                                        current_term = 202080L, min_days_after_start = 14L)
  expect_snapshot(str(low_enrollment_section_words("concerns")))
  expect_snapshot(cat(low_enrollment_method_notes(schedule), sep = "\n\n"))
  expect_snapshot(cat(LOW_ENROLLMENT_SPLIT_NOTE))
  expect_error(low_enrollment_section_words("mixed"), "no section for mode")
})

test_that("the download holds every listed row, named for its departments, terms and date", {
  page <- build_low_enrollment_page(test_sections, list(term = c("202010", "202080"),
                                                        dept_code = c("HIST", "ENGL")),
                                    current_term = 202080L, min_days_after_start = 14L)
  download <- low_enrollment_download_table(page)
  expect_equal(nrow(download), nrow(page$review))
  # The per-term history table is a list column a CSV cannot hold; its text stays.
  expect_true("history" %in% names(page$review))
  expect_false("history" %in% names(download))
  expect_true(all(c("history_text", ".threshold", ".level_group", ".band") %in% names(download)))
  expect_false(any(vapply(download, is.list, logical(1))))
  expect_equal(low_enrollment_download_name(page, as.Date("2026-11-26")),
               "low_enrollment_HIST-ENGL_202010-202080_2026-11-26.csv")
  all_depts <- build_low_enrollment_page(test_sections, list(term = "202010"),
                                         current_term = 202080L, min_days_after_start = 14L)
  expect_equal(low_enrollment_download_name(all_depts, as.Date("2026-11-26")),
               "low_enrollment_202010_2026-11-26.csv")
})
