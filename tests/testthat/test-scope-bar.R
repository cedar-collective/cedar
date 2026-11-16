test_that("the scope bar's visible line holds facts; what they mean opens with the codes", {
  facts <- list(`In progress` = c("Fall 2026 (as of Oct 8, 2026)", "Spring 2027 (registration filling)"),
                `Grades through` = "Summer 2026")
  meaning <- "What a term in progress means."
  bar <- htmltools::renderTags(unit_codes_scope(scope_unit_rows, time_facts = facts, time_meaning = meaning))$html
  summary <- regmatches(bar, regexpr("<summary>.*?</summary>", bar))

  expect_equal(lengths(regmatches(summary, gregexpr('class="scope-chip"', summary))), 2L)
  expect_true(grepl("Fall 2026 (as of Oct 8, 2026); Spring 2027 (registration filling)", summary, fixed = TRUE))
  expect_true(grepl("Summer 2026", summary, fixed = TRUE))
  expect_false(grepl(meaning, summary, fixed = TRUE))
  expect_true(grepl(meaning, sub(summary, "", bar, fixed = TRUE), fixed = TRUE))
})

test_that("without time facts the scope bar is the unit and its codes alone", {
  bar <- htmltools::renderTags(unit_codes_scope(scope_unit_rows))$html
  expect_false(grepl('class="scope-chip"', bar, fixed = TRUE))
  expect_true(grepl("Data scope for History (HIST), Arts and Sciences", bar, fixed = TRUE))
})
