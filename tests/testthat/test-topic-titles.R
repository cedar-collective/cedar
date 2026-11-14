# The wording-blind key a section's topic is read by, and topic_titles.csv,
# the reviewed merges for what the key cannot match (R/lists/topic_titles.R).

test_that("the topic key ignores the section label, case, punctuation and & against and", {
  expect_identical(topic_title_key(c("Sem: Create, Sell, Bank", "Sem: Create. Sell. Bank")),
                   rep("create sell bank", 2))
  expect_identical(topic_title_key(c("Sem: Success Starts Here", "Success Starts Here")),
                   rep("success starts here", 2))
  expect_identical(topic_title_key(c("Sem: Intro to UNM & Higher Ed", "Sem: Intro to UNM and Higher Ed")),
                   rep("intro to unm and higher ed", 2))
  expect_identical(topic_title_key(c("T: Pilates:", "Perf Conc: Violin")), c("pilates", "violin"))
})

test_that("a colon past the label's twelve characters is part of the title, not a label", {
  expect_identical(topic_title_key("Introduction to Physics: Mechanics"),
                   "introduction to physics mechanics")
  expect_identical(topic_title_text("Introduction to Physics: Mechanics"),
                   "Introduction to Physics: Mechanics")
})

test_that("a missing title has no key and a bare label an empty one", {
  expect_identical(topic_title_key(c(NA, "T:")), c(NA_character_, ""))
})

test_that("topic_titles.csv rows are read with both keys", {
  expect_identical(tp_topic_titles$title_key, c("intro to unm and hed", "math learning stategies"))
  expect_identical(tp_topic_titles$topic_key, c("intro to unm and higher ed", "math learning strategies"))
})

test_that("a row that merges nothing, a title merged twice, or a chain of merges is refused", {
  # A topic that differs from its title only in punctuation.
  same <- cedar_topic_titles_tp
  same$topic[1] <- "Sem: Intro to UNM & HED."
  expect_error(validate_topic_titles(same), "merges nothing")

  # The first row twice.
  twice <- rbind(cedar_topic_titles_tp, cedar_topic_titles_tp[1, ])
  expect_error(validate_topic_titles(twice), "merged twice")

  # A row whose topic is the first row's title, itself merged.
  chained <- rbind(cedar_topic_titles_tp, data.frame(
    subject_course = "FYEX 1110", title = "Sem: Intro UNM HED", topic = "Sem: Intro to UNM & HED",
    notes = "", stringsAsFactors = FALSE))
  expect_error(validate_topic_titles(chained), "itself a merged title")

  # A blank topic.
  blank <- cedar_topic_titles_tp
  blank$topic[2] <- ""
  expect_error(validate_topic_titles(blank), "blank topic")
})
