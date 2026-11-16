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
  compiled$rules <- dplyr::bind_rows(compiled$rules, tibble::tibble(rule_id = "calc", parent_id = "major", role = "course",
    subject_course = "MATH 1512", label = "Calculus I", tiles = 1L, credits = 4, block_id = "", quote = "Calculus I"))
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

# ── Step 2: the draft board ──────────────────────────────────────────────────

test_that("each course's requisites carry the catalog template's timing, or none", {
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  nodes <- utils::read.csv(file.path(f$capture, "analysis", "rule-nodes.csv"), colClasses = "character")
  req <- degree_course_requisites(nodes, courses)
  expect_equal(paste(req$subject_course, req$requisite), c("BIOL 2110 BIOL 200", "BIOL 2110L BIOL 2110", "BIOL 200 BIOL 2110"))
  # "Earned a minimum grade of C in each" is before; "Complete before enrolling:"
  # and a bare "Complete the following:" say nothing about timing.
  expect_equal(req$timing, c(NA, "prior", NA))
  expect_error(degree_course_requisites(nodes[setdiff(names(nodes), "timing")], courses), "predates extractor 1.4.0")
})

test_that("a draft board validates, places its tiles and draws only timed arrows", {
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  nodes <- utils::read.csv(file.path(f$capture, "analysis", "rule-nodes.csv"), colClasses = "character")
  compiled <- compile_degree_interpretation(compiler_biology_proposal, courses)
  program <- degree_packet_program_facts(f$program$packet)
  draft <- assemble_compiled_degree_board(compiled, courses, program, degree_course_requisites(nodes, courses),
    compiler_biology_catalog_row, test_degree_roadmaps, test_degree_catalog$evidence, "math1350")

  # The choice of the lab pair or Combined Biology is two tiles: first and second course.
  own <- draft$roadmaps$nodes[draft$roadmaps$nodes$catalog_id == "demo-biology-draft", ]
  expect_equal(own$node_id, c("start_1", "start_2"))
  expect_equal(own$kind, c("choice", "choice"))
  opts <- draft$roadmaps$options
  expect_equal(opts$subject_course[opts$node_id == "start_1"], c("BIOL 2110", "BIOL 200"))
  expect_equal(opts$subject_course[opts$node_id == "start_2"], "BIOL 2110L")
  expect_equal(draft$roadmaps$plans$degree_credit_target, "120")
  expect_equal(draft$roadmaps$math_routes$node_ids[draft$roadmaps$math_routes$start_id == "intermediate"], "math1215|math1350")
  # No arrow can start from a choice, and the choices' courses need only each other.
  expect_equal(nrow(draft$roadmaps$links[draft$roadmaps$links$catalog_id == "demo-biology-draft", ]), 0L)

  plan <- build_degree_roadmap(draft$catalog, draft$roadmaps, "demo-biology-draft", "calculus", "composition")
  expect_true(all(plan$nodes$semester[plan$nodes$node_id %in% c("start_1", "start_2")] >= 1L))
  expect_equal(plan$degree_credits, 120)
})

test_that("required courses get arrows timed by their templates; untimed wording is held", {
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  nodes <- utils::read.csv(file.path(f$capture, "analysis", "rule-nodes.csv"), colClasses = "character")
  compiled <- compile_degree_interpretation(compiler_biology_proposal, courses)
  # Change: the reading requires all three courses instead of offering a choice.
  compiled$rules <- tibble::tibble(rule_id = c("r1", "r2", "r3"), parent_id = "major", role = "course",
    subject_course = c("BIOL 2110", "BIOL 2110L", "BIOL 200"), label = "Required", tiles = 1L, credits = c(3, 1, 4),
    block_id = "b-7dcbcb97cd7ee63e0e5368a9", quote = "Complete all of the following")
  compiled$options <- compiled$options[0, ]
  draft <- assemble_compiled_degree_board(compiled, courses, degree_packet_program_facts(f$program$packet),
    degree_course_requisites(nodes, courses), compiler_biology_catalog_row, test_degree_roadmaps,
    test_degree_catalog$evidence, "math1350")

  links <- draft$roadmaps$links[draft$roadmaps$links$catalog_id == "demo-biology-draft", ]
  expect_equal(paste(links$from, links$to, links$timing), "biol_2110 biol_2110l before")
  expect_equal(draft$catalog$evidence$source_url[draft$catalog$evidence$evidence_id == links$evidence_id],
               courses$catalog_url[courses$subject_course == "BIOL 2110L"])
  expect_equal(paste(draft$held$requisite, draft$held$subject_course), c("BIOL 200 BIOL 2110", "BIOL 2110 BIOL 200"))
  expect_true(all(draft$held$why == "wording is not a recognised requisite template"))

  plan <- build_degree_roadmap(draft$catalog, draft$roadmaps, "demo-biology-draft", "calculus", "composition")
  at <- function(code) plan$nodes$semester[plan$nodes$code == code]
  expect_gt(at("BIOL 2110L"), at("BIOL 2110"))

  # Change: every requisite is timed. BIOL 2110 and BIOL 200 then list each
  # other; that pair is held (a cycle), and only the lab's arrow is drawn.
  timed <- degree_course_requisites(nodes, courses); timed$timing <- "prior"
  cycle <- assemble_compiled_degree_board(compiled, courses, degree_packet_program_facts(f$program$packet), timed,
    compiler_biology_catalog_row, test_degree_roadmaps, test_degree_catalog$evidence, "math1350")
  expect_equal(nrow(cycle$roadmaps$links[cycle$roadmaps$links$catalog_id == "demo-biology-draft", ]), 1L)
  expect_true(all(cycle$held$why == "listed each way; the board cannot draw a cycle"))
  expect_equal(nrow(cycle$held), 2L)

  # Change: the lab's requisite allows the same term; the arrow says so.
  same <- degree_course_requisites(nodes, courses); same$timing[same$subject_course == "BIOL 2110L"] <- "prior_or_concurrent"
  same <- assemble_compiled_degree_board(compiled, courses, degree_packet_program_facts(f$program$packet), same,
    compiler_biology_catalog_row, test_degree_roadmaps, test_degree_catalog$evidence, "math1350")
  expect_equal(same$roadmaps$links$timing[same$roadmaps$links$catalog_id == "demo-biology-draft"], "before_or_same")
})

test_that("the board comparison reads as a semester-by-semester checklist", {
  testthat::local_edition(3)
  f <- normalization_fixture(withr::local_tempdir())
  courses <- degree_packet_course_facts(f$program$packet)
  nodes <- utils::read.csv(file.path(f$capture, "analysis", "rule-nodes.csv"), colClasses = "character")
  draft <- assemble_compiled_degree_board(compile_degree_interpretation(compiler_biology_proposal, courses), courses,
    degree_packet_program_facts(f$program$packet), degree_course_requisites(nodes, courses),
    compiler_biology_catalog_row, test_degree_roadmaps, test_degree_catalog$evidence, "math1350")
  placed <- build_degree_roadmap(draft$catalog, draft$roadmaps, "demo-biology-draft", "calculus", "composition")
  hand <- build_degree_roadmap(test_degree_catalog, test_degree_roadmaps, BIOLOGY, "calculus", "composition")
  expect_snapshot(cat(format_degree_board_comparison("Biology B.S.", "calculus", placed, hand, draft$held)))
})
