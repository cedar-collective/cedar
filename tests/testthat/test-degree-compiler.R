# The degree compiler (R/branches/degree-compiler.R) on the designed Biology
# reading (compiler_biology_proposal) of the demo catalog fixture, against the
# demo Biology board. Step 1 drafts rows; nothing here writes a board file.

test_that("the designed reading is a legal interpretation of the fixture catalog", {
  f <- normalization_fixture(withr::local_tempdir())
  expect_silent(validate_catalog_normalization(compiler_biology_proposal, f$unit$request))
})

test_that("course credits come from each course's own catalog record", {
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  expect_equal(courses$subject_course, c("BIOL 2110", "BIOL 2110L", "BIOL 200"))
  expect_equal(courses$credits_min, c(3, 1, 4))

  # A course record without credits stops rather than guessing three.
  packet <- f$program$packet
  lab <- which(vapply(packet$units, function(u) identical(u$request$documents[[1]]$id, "courses:course-lab"), TRUE))
  packet$units[[lab]]$request$source_blocks <- Filter(function(b) b$field != "credits", packet$units[[lab]]$request$source_blocks)
  expect_error(degree_packet_course_facts(packet), "BIOL2110L has no 'credits' field")
})

test_that("a choice becomes one tile group with its options; conditions, totals and questions stay off the board", {
  f <- normalization_fixture(withr::local_tempdir())
  compiled <- compile_degree_interpretation(compiler_biology_proposal, degree_packet_course_facts(f$program$packet))

  # One of {Biology I + lab, Combined Biology}: the larger option is two courses.
  expect_equal(compiled$rules$rule_id, "start")
  expect_equal(compiled$rules$role, "choice")
  expect_equal(compiled$rules$tiles, 2L)
  expect_equal(compiled$rules$credits, 4)
  expect_equal(compiled$options$option_id, c("pair", "pair", "combined"))
  expect_equal(compiled$options$subject_course, c("BIOL 2110", "BIOL 2110L", "BIOL 200"))

  # The unresolved node under the choice is a question, never an option.
  expect_equal(compiled$flags$id, "combined-scope")
  expect_equal(compiled$conditions$id, c("admit-upper", "admit-permission"))
  expect_equal(compiled$credit_rules$id, "degree-total")
  expect_equal(compiled$concentrations$entity_id, "specializations:cellular")
  expect_equal(compiled$concentrations$n_rules, 2L)
})

test_that("an unlisted credit pool is elective space inside the major and a credit rule outside it", {
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  # Change: the major also asks for 7 upper-level elective credits (not in the fixture's text).
  pool <- compiler_biology_proposal$nodes[[match("degree-total", vapply(compiler_biology_proposal$nodes, `[[`, "", "id"))]]
  pool$id <- "electives"; pool$label <- "At least 7 upper-level BIOL elective credits"; pool$minimum <- 7

  inside <- compiler_biology_proposal
  inside$nodes <- c(inside$nodes, list(modifyList(pool, list(parent_id = "major"))))
  slot <- compile_degree_interpretation(inside, courses)$rules
  expect_equal(slot$role[slot$rule_id == "electives"], "slot")
  expect_equal(slot$tiles[slot$rule_id == "electives"], 2L)  # 7 credits: two 3-credit courses, rounded
  expect_equal(slot$credits[slot$rule_id == "electives"], 7)

  outside <- compiler_biology_proposal
  outside$nodes <- c(outside$nodes, list(pool))
  compiled <- compile_degree_interpretation(outside, courses)
  expect_false("electives" %in% compiled$rules$rule_id)
  expect_equal(compiled$credit_rules$id, c("degree-total", "electives"))
})

test_that("a credit group whose listed courses add up to its minimum requires each of them", {
  f <- normalization_fixture(withr::local_tempdir())
  # Change: the pair is "4 credits" rather than "all of", outside any choice.
  reading <- compiler_biology_proposal
  ids <- vapply(reading$nodes, `[[`, "", "id")
  reading$nodes[[match("pair", ids)]] <- modifyList(reading$nodes[[match("pair", ids)]],
    list(parent_id = "major", kind = "credits", minimum = 4, unit = "credits"))
  rules <- compile_degree_interpretation(reading, degree_packet_course_facts(f$program$packet))$rules
  expect_equal(rules$subject_course[rules$role == "course"], c("BIOL 2110", "BIOL 2110L"))
})

test_that("a course the packet does not carry stops the compiler", {
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  expect_error(compile_degree_interpretation(compiler_biology_proposal, courses[courses$course_ref != "courses:course-two", ]),
               "Courses missing from the packet: courses:course-two")
})

test_that("the comparison reads the board's own course lists and the shared routes", {
  f <- normalization_fixture(withr::local_tempdir())
  compiled <- compile_degree_interpretation(compiler_biology_proposal, degree_packet_course_facts(f$program$packet))
  # Change: the board's first biology tile is Combined Biology, and the reading
  # also requires Calculus I, which reaches the board on the shared math route.
  roadmaps <- test_degree_roadmaps
  roadmaps$courses$subject_course[roadmaps$courses$catalog_id == BIOLOGY & roadmaps$courses$node_id == "bio1"] <- "BIOL 200"
  compiled$rules <- dplyr::bind_rows(compiled$rules, tibble::tibble(rule_id = "calc", role = "course",
    subject_course = "MATH 1512", label = "Calculus I", tiles = 1L, credits = 4, quote = "Calculus I"))
  cmp <- compare_compiled_degree(compiled, roadmaps, BIOLOGY)

  expect_equal(cmp$choices$on_board, "BIOL 200")
  expect_equal(cmp$required_on_shared_routes, "MATH 1512")
  expect_length(cmp$required_not_on_board, 0L)
  # A lecture + lab tile is two courses on the board.
  expect_true(all(c("CHEM 1215", "CHEM 1215L") %in% cmp$board_not_compiled))
  expect_false("BIOL 200" %in% cmp$board_not_compiled)
  expect_equal(cmp$tiles, c(compiled = 3L, board = 12L))
  expect_equal(cmp$slot_credits, c(compiled = 0, board = 3))
  expect_error(compare_compiled_degree(compiled, roadmaps, "no-such-board"), "No hand-built board")
})

test_that("the text preview reads as a reviewer's checklist", {
  testthat::local_edition(3)
  f <- normalization_fixture(withr::local_tempdir())
  compiled <- compile_degree_interpretation(compiler_biology_proposal, degree_packet_course_facts(f$program$packet))
  expect_snapshot(cat(format_compiled_degree_preview("Biology B.S.", compiled,
                                                     compare_compiled_degree(compiled, test_degree_roadmaps, BIOLOGY))))
})
