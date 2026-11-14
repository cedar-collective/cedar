# Course Dynamics > Topics: a course number's topics, read from its sections'
# titles, counted by campus and term, pooled, and withheld where one
# instructor taught them. TP01 (fixtures/designed_test_data.R) holds every
# expectation's rows.

test_that("each section's topic is its title, read wording-blind, with the reviewed merges", {
  s <- attach_section_topics(test_sections_tp %>% filter(subject_course == "FYEX 1110"), tp_topic_titles)
  topic_of <- stats::setNames(s$topic, s$section_id)
  expect_identical(unname(topic_of[c("S1", "S2", "S4", "S7", "S12")]), rep("Success Starts Here", 5))
  expect_identical(unname(topic_of[c("S3", "S8", "S9")]), rep("Intro to UNM & Higher Ed", 3))
  expect_identical(unname(topic_of[c("S5", "S6")]), rep("Math Learning Strategies", 2))
  expect_identical(s$topic_basis[s$section_id %in% c("S6", "S8")], rep("topic_titles", 2))
  expect_true(all(s$topic_basis[!s$section_id %in% c("S6", "S8")] == "title"))
})

test_that("without the reviewed merges a misspelt or abbreviated title is a topic of its own", {
  s <- attach_section_topics(test_sections_tp %>% filter(subject_course == "FYEX 1110"),
                             tp_topic_titles[0, ])
  topic_of <- stats::setNames(s$topic, s$section_id)
  expect_identical(unname(topic_of[c("S6", "S8")]), c("Math Learning Stategies", "Intro to UNM & HED"))
  # The key still joins S9's "and" to S3's "&".
  expect_identical(topic_of[["S9"]], topic_of[["S3"]])
})

test_that("a course offers topics when one campus-term offered two or more", {
  expect_true(course_has_topics(test_sections_tp, tp_topic_titles, list(course = "FYEX 1110")))
  # EA offered one topic, in one term.
  expect_false(course_has_topics(test_sections_tp, tp_topic_titles, list(course = "FYEX 1110", campus = "EA")))
  # Two sections with one title, then a retitle: one course, no topics.
  expect_false(course_has_topics(test_sections_tp, tp_topic_titles, list(course = "TPCO 101")))
  counts <- course_topic_counts(test_sections_tp, tp_topic_titles, list(course = "FYEX 1110", campus = "ABQ"))
  expect_identical(counts$term, c(202080L, 202110L, 202180L, 202210L))
  # Fall 2021: the cancelled section is not an offering.
  expect_identical(counts$n_topics, c(2L, 1L, 3L, 2L))
  expect_identical(counts$n_sections, c(3L, 2L, 4L, 2L))
})

test_that("a topic-term counts sections, seats, census, DFW and return on its own campus", {
  d <- course_topics_term_table(tp_topics(), unlocked = TRUE)
  ssh <- tp_row(d, "ABQ", "Success Starts Here", 202080L)
  expect_identical(c(ssh$sections, ssh$census_enrl, ssh$n_instructors, ssh$attempts, ssh$dfw,
                     ssh$n_return_observable, ssh$n_returned), c(2L, 7L, 2L, 7L, 3L, 7L, 4L))
  expect_equal(ssh$seats, 40)
  expect_equal(ssh$fill_pct, 17.5)
  expect_equal(ssh$dfw_pct, 300 / 7)
  # The same topic on EA, the same term: its own row, never pooled with ABQ's.
  ea <- tp_row(d, "EA", "Success Starts Here", 202080L)
  expect_identical(c(ea$sections, ea$census_enrl, ea$attempts, ea$dfw, ea$n_returned), c(1L, 2L, 2L, 1L, 1L))
  # S5 and S6 are one topic through the reviewed merge.
  mls <- tp_row(d, "ABQ", "Math Learning Strategies", 202110L)
  expect_identical(c(mls$sections, mls$census_enrl, mls$attempts, mls$dfw, mls$n_returned),
                   c(2L, 4L, 4L, 1L, 2L))
  total <- tp_row(d, "ABQ", COURSE_TOPICS_ALL, 202080L)
  expect_identical(c(total$sections, total$census_enrl, total$n_instructors, total$attempts, total$dfw,
                     total$n_returned), c(3L, 11L, 3L, 11L, 4L, 7L))
})

test_that("a crosslisted section's topic-term has no fill, and neither does its term's total", {
  d <- course_topics_term_table(tp_topics(), unlocked = TRUE)
  expect_true(is.na(tp_row(d, "ABQ", "Black Minds Matter", 202180L)$fill_pct))
  expect_true(is.na(tp_row(d, "ABQ", COURSE_TOPICS_ALL, 202180L)$fill_pct))
  expect_equal(tp_row(d, "ABQ", "Intro to UNM & Higher Ed", 202180L)$fill_pct, 10)
})

test_that("a cancelled section is no topic, and a term in progress has students and no outcome", {
  d <- course_topics_term_table(tp_topics(), unlocked = TRUE)
  expect_false("Cancelled Topic" %in% d$topic)
  spring22 <- d[d$term == 202210L, ]
  expect_true(all(spring22$in_progress))
  expect_identical(tp_row(d, "ABQ", "Financial Capabilities", 202210L)$census_enrl, 1L)
  expect_true(all(is.na(spring22$attempts)))
  # Fall 2021's next regular term has not settled: no return to read.
  expect_true(all(d$n_return_observable[d$term == 202180L] == 0L))
})

test_that("rates of a one-instructor topic are withheld, with the complement that would give them back", {
  locked <- course_topics_term_table(tp_topics())
  intro <- tp_row(locked, "ABQ", "Intro to UNM & Higher Ed", 202080L)
  expect_identical(intro$withheld_reason, "one_instructor")
  # Two instructors, but the term's total less its rates would be Intro's.
  ssh <- tp_row(locked, "ABQ", "Success Starts Here", 202080L)
  expect_identical(ssh$withheld_reason, "complement")
  expect_true(ssh$withheld)
  expect_true(all(is.na(c(ssh$dfw, ssh$dfw_pct, ssh$n_returned, ssh$return_pct))))
  # Students are never withheld; the course's own total never is.
  expect_identical(ssh$census_enrl, 7L)
  total <- tp_row(locked, "ABQ", COURSE_TOPICS_ALL, 202080L)
  expect_false(total$withheld)
  expect_identical(total$dfw, 4L)
  # Fall 2021: two topics have one instructor, so neither is a lone one and
  # Intro, with two, is shown.
  intro21 <- tp_row(locked, "ABQ", "Intro to UNM & Higher Ed", 202180L)
  expect_false(intro21$withheld)
  expect_equal(intro21$dfw_pct, 25)
  expect_true(tp_row(locked, "ABQ", "Black Minds Matter", 202180L)$withheld)
  expect_true(tp_row(locked, "EA", "Success Starts Here", 202080L)$withheld)
  # With the password, nothing is withheld.
  open <- course_topics_term_table(tp_topics(), unlocked = TRUE)
  expect_false(any(open$withheld))
  expect_true(course_topics_withheld_any(tp_topics()))
})

test_that("pooled over settled terms, a locked topic's rates cover only its terms shown", {
  open <- course_topics_summary(tp_topics(), unlocked = TRUE)
  total <- tp_row(open, "ABQ", COURSE_TOPICS_ALL)
  expect_identical(c(total$terms, total$census_enrl, total$n_instructors, total$attempts, total$dfw,
                     total$n_return_observable, total$n_returned), c(3L, 24L, 6L, 24L, 7L, 15L, 9L))
  ssh <- tp_row(open, "ABQ", "Success Starts Here")
  expect_identical(c(ssh$terms, ssh$census_enrl, ssh$n_instructors, ssh$attempts, ssh$dfw,
                     ssh$n_return_observable, ssh$n_returned), c(2L, 10L, 2L, 10L, 4L, 7L, 4L))
  expect_equal(ssh$fill_pct, 100 * 10 / 60)
  # The topics follow the total, most students first; Spring 2022 is in
  # progress and pools nothing.
  expect_identical(open$topic[open$campus == "ABQ"],
                   c(COURSE_TOPICS_ALL, "Success Starts Here", "Intro to UNM & Higher Ed",
                     "Math Learning Strategies", "Black Minds Matter"))

  locked <- course_topics_summary(tp_topics())
  intro <- tp_row(locked, "ABQ", "Intro to UNM & Higher Ed")
  expect_true(intro$partial)
  expect_identical(c(intro$census_enrl, intro$graded_terms, intro$rate_terms, intro$attempts, intro$dfw),
                   c(8L, 2L, 1L, 4L, 1L))
  ssh_locked <- tp_row(locked, "ABQ", "Success Starts Here")
  expect_true(ssh_locked$withheld)
  expect_true(is.na(ssh_locked$dfw_pct))
  expect_identical(tp_row(locked, "ABQ", COURSE_TOPICS_ALL)$dfw, 7L)
})

test_that("the term types chosen decide every row, and a rate needs the minimum", {
  spring <- course_topics_term_table(tp_topics(), "spring", unlocked = TRUE)
  expect_identical(sort(unique(spring$term)), c(202110L, 202210L))
  expect_identical(unique(course_topics_summary(tp_topics(), "spring", unlocked = TRUE)$topic),
                   c(COURSE_TOPICS_ALL, "Math Learning Strategies"))
  # At ten, only Fall 2020's ABQ total (11 graded) has a DFW rate; the counts
  # stay.
  ten <- course_topics_term_table(tp_topics(min_n = 10L), unlocked = TRUE)
  expect_identical(which(!is.na(ten$dfw_pct)),
                   which(ten$campus == "ABQ" & ten$term == 202080L & ten$is_total))
  expect_identical(tp_row(ten, "ABQ", "Success Starts Here", 202080L)$dfw, 3L)
})

test_that("topics are offered most students first, and the chart draws only rates shown", {
  expect_identical(names(course_topics_choices(tp_topics())),
                   c("Success Starts Here", "Intro to UNM & Higher Ed", "Math Learning Strategies",
                     "Black Minds Matter", "Financial Capabilities"))
  p <- tp_topics()
  intro <- unname(course_topics_choices(p)[["Intro to UNM & Higher Ed"]])
  traces <- plotly::plotly_build(plot_course_topics(p, "dfw_pct", intro))$x$data
  drawn <- stats::setNames(lapply(traces, function(t) as.character(t$x)),
                           vapply(traces, function(t) t$name, ""))
  # Locked: Intro's Fall 2020 rate is withheld, so its line holds Fall 2021
  # alone; every topic together is drawn in both.
  expect_identical(unname(lengths(drawn[grepl("^Intro", names(drawn))])), 1L)
  expect_true(any(grepl(COURSE_TOPICS_ALL, names(drawn))))
})

test_that("every offered title is listed under its topic, saying how it was matched", {
  t <- course_topics_titles(tp_topics())
  read_as <- stats::setNames(t$read_as, t$course_title)
  expect_identical(read_as[["Sem: Intro to UNM & HED"]], "topic_titles.csv")
  expect_identical(read_as[["Sem: Intro to UNM and Higher Ed"]], "the same words")
  expect_identical(read_as[["Success Starts Here"]], "its own title")
  expect_false("Sem: Cancelled Topic" %in% t$course_title)
})

test_that("the class list must hold a student once per term and campus of the course", {
  # TP_A1's Fall 2020 row, twice.
  doubled <- bind_rows(test_students_tp, test_students_tp[1, ])
  expect_error(tp_topics(students = doubled), "more than once")
})

test_that("the Topics payload reads as text", {
  testthat::local_edition(3)
  expect_snapshot(cat(format_course_topics(tp_topics()), sep = "\n"))
  expect_snapshot(cat(format_course_topics(tp_topics(), unlocked = TRUE), sep = "\n"))
})
