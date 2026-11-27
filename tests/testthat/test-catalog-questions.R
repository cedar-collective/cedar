test_that("a reading's open items carry their catalog passage and who can settle each", {
  f <- normalization_fixture(withr::local_tempdir())
  # Change: the designed reading also asks whether permission is required for
  # admission, and its triage names the catalog for Combined Biology only.
  proposal <- compiler_biology_proposal
  proposal$questions <- list(list(block_id = "b-c83ed948337af5e15eada1e2", question = "Is department permission required, or only advised?"))
  reading <- list(program_id = f$program$packet$program_id, unit_key = f$unit$key, proposal = proposal,
                  triage = list(list(item = "rule:combined-scope", settled_by = "catalog")))
  rows <- degree_reading_question_rows(reading, f$program$packet)
  expect_equal(rows$item, c("rule:combined-scope", "question:1"))
  expect_equal(rows$kind, c("rule", "question"))
  expect_equal(rows$settled_by, c("catalog", ""))
  expect_equal(rows$question[2], "Is department permission required, or only advised?")
  # The passage is the packet's whole block, of which the rule cites a part.
  blocks <- f$unit$request$source_blocks
  cited <- blocks[[match("b-12cf2b1d2a007e540e5f8c49", catalog_normalization_ids(blocks))]]
  expect_equal(rows$passage[1], cited$text)
  expect_equal(rows$section[1], cited$section)
  expect_true(grepl("Combined Biology (4)", rows$passage[1], fixed = TRUE))
})

test_that("a triage that names no open item, names one twice or an unknown settler stops", {
  f <- normalization_fixture(withr::local_tempdir())
  reading <- list(program_id = f$program$packet$program_id, unit_key = f$unit$key, proposal = compiler_biology_proposal)
  triage <- function(...) { sorted <- reading; sorted$triage <- list(...); sorted }
  expect_error(degree_reading_question_rows(triage(list(item = "question:1", settled_by = "catalog")), f$program$packet),
               "names no open item, or names one twice: question:1")
  expect_error(degree_reading_question_rows(triage(list(item = "rule:combined-scope", settled_by = "catalog"),
                                                   list(item = "rule:combined-scope", settled_by = "reading")), f$program$packet),
               "names one twice: rule:combined-scope")
  expect_error(degree_reading_question_rows(triage(list(item = "rule:combined-scope", settled_by = "registrar")), f$program$packet),
               "settled_by must be one of catalog, capture, reading")
  # No triage at all: every item is listed, and none is said to be settled by anyone.
  expect_equal(degree_reading_question_rows(reading, f$program$packet)$settled_by, "")
})

test_that("the list filters by who can settle an item and by program, in program order", {
  q <- catalog_questions_designed
  expect_equal(unname(catalog_question_settler_choices(q)), c("", "catalog", "capture", "reading", "none"))
  expect_equal(names(catalog_question_settler_choices(q)),
               c("Any (3)", "The catalog (1)", "CEDAR's copy of the catalog (0)", "CEDAR's reading (1)", "Not sorted yet (1)"))
  expect_equal(unname(catalog_question_program_choices(q)), c("", "Bachelor of Arts in History", "Bachelor of Science in Biology"))
  all <- catalog_question_rows(q)
  expect_equal(all$program, c("Bachelor of Arts in History", rep("Bachelor of Science in Biology", 2)))
  expect_equal(all$settled_by, c("CEDAR's reading", "The catalog", "Not sorted yet"))
  # A rule or a passage leads with its label; a question is its own words.
  expect_equal(all$question[3], "Is department permission required for admission, or only advised?")
  expect_true(startsWith(all$question[2], "Does Combined Biology replace both Biology I and its lab? The list"))
  expect_true(startsWith(all$question[1], "Unresolved source treatment: The credit wording"))
  expect_equal(all$location[2], "catalog_interpretations/2026-2027/biology.v1.json · rule combined-scope")
  expect_equal(catalog_question_rows(q, "none")$location, "catalog_interpretations/2026-2027/biology.v1.json · question 1")
  expect_equal(nrow(catalog_question_rows(q, "capture")), 0L)
  expect_equal(catalog_question_rows(q, "", "Bachelor of Arts in History")$settled_by, "CEDAR's reading")
  expect_error(catalog_question_rows(q, "registrar"), "Unknown settled_by")
})

test_that("the questions read as a document for the catalog office", {
  testthat::local_edition(3)
  q <- catalog_questions_designed
  expect_snapshot(cat(format_catalog_questions(catalog_question_rows(q), catalog_question_scope())))
  expect_snapshot(cat(format_catalog_questions(catalog_question_rows(q, "catalog"), catalog_question_scope("catalog"))))
  expect_snapshot(cat(format_catalog_questions(catalog_question_rows(q, "capture", "Bachelor of Arts in History"),
                                               catalog_question_scope("capture", "Bachelor of Arts in History"))))
})

test_that("each compiled board is listed with its reading's status and what it leaves out", {
  boards <- list(status = degree_board_status_demo, catalog = test_degree_catalog)
  rows <- degree_draft_board_rows(boards)
  expect_equal(nrow(rows), 1L)
  biology <- test_degree_catalog$catalogs[test_degree_catalog$catalogs$catalog_id == "demo-biology-bs-2026", ]
  expect_equal(rows$degree, biology$degree_label)
  expect_equal(rows$review, "Its catalog reading is not signed off in Catalog Review.")
  expect_equal(rows$note, biology$notes)
})
