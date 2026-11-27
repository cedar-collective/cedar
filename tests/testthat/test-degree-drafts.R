test_that("a compiled board takes its authored board's place on the page, labelled from the review store", {
  testthat::local_edition(3)
  root <- withr::local_tempdir()
  f <- normalization_fixture(root)
  courses <- degree_packet_course_facts(f$program$packet)
  nodes <- utils::read.csv(file.path(f$capture, "analysis", "rule-nodes.csv"), colClasses = "character")
  # Change: a reading with no open question (the designed one asks whether
  # Combined Biology replaces the pair), so it can be signed off.
  settled <- compiler_biology_proposal
  settled$nodes <- Filter(function(n) n$id != "combined-scope", settled$nodes)
  settled$coverage <- lapply(settled$coverage, function(x) {
    if (x$block_id == "b-12cf2b1d2a007e540e5f8c49") { x$disposition <- "requirements"; x$node_ids <- list("combined") }
    x
  })
  reading <- list(schema_version = "1.0.0", version = 1L, producer = "Designed maintainer draft",
    program_id = f$program$packet$program_id, catalog_id = f$program$packet$catalog_id, unit_key = f$unit$key, proposal = settled)
  staged <- file.path(root, "readings"); dir.create(staged)
  write_source_json(reading, file.path(staged, "biology.v1.json"))
  stage_catalog_normalization_drafts(f$root, staged, dirname(f$capture))

  # Change: the draft takes the authored Biology board's id, as --write builds it.
  row <- compiler_biology_catalog_row; row$catalog_id <- BIOLOGY
  board <- assemble_compiled_degree_board(compile_degree_interpretation(settled, courses), courses,
    degree_packet_program_facts(f$program$packet), degree_course_requisites(nodes, courses), row, test_degree_roadmaps,
    test_degree_catalog$evidence, compiler_general_math_routes, degree_course_conditions(nodes, courses), settled, compiler_no_gen_ed_pools)
  manifest <- data.frame(catalog_id = BIOLOGY, program_id = reading$program_id, reading = "catalog_interpretations/biology.v1.json",
    packet_key = basename(f$program$directory), unit_key = reading$unit_key,
    proposal_key = degree_reading_proposal_key(f$root, f$program, reading),
    reading_sha256 = source_sha256(source_json_bytes(settled)), analysis = "analysis", compiled_on = "2026-11-16")
  out <- file.path(root, "degree_drafts")
  # The designed reading's open question (Combined Biology against the pair),
  # listed as --write lists every latest reading's, its triage naming the catalog.
  designed <- reading
  designed$proposal <- compiler_biology_proposal
  designed$triage <- list(list(item = "rule:combined-scope", settled_by = "catalog"))
  designed_path <- file.path(root, "catalog_interpretations", "designed.v1.json")
  dir.create(dirname(designed_path)); write_source_json(designed, designed_path)
  questions <- data.frame(reading = "catalog_interpretations/designed.v1.json", reading_file_sha256 = degree_reading_file_sha256(designed_path),
    program_id = designed$program_id, program_title = f$program$packet$title,
    catalog_url = degree_packet_program_facts(f$program$packet)$catalog_url, catalog_id = BIOLOGY,
    degree_reading_question_rows(designed, f$program$packet))
  write_degree_drafts(stats::setNames(list(board), BIOLOGY), manifest, out, test_degree_catalog$evidence, questions)
  drafts <- read_degree_drafts(out, test_degree_programs)
  expect_equal(drafts$manifest$catalog_id, BIOLOGY)
  expect_equal(drafts$questions$item, "rule:combined-scope")
  expect_equal(drafts$questions$settled_by, "catalog")
  expect_equal(drafts$questions$passage, questions$passage)
  expect_length(drafts$questions_stale, 0L)
  # Change: the reading's triage now names CEDAR's reading, and nothing is recompiled.
  resorted <- designed
  resorted$triage[[1]]$settled_by <- "reading"
  write_source_json(resorted, designed_path)
  expect_equal(read_degree_drafts(out, test_degree_programs)$questions_stale, "catalog_interpretations/designed.v1.json")
  write_source_json(designed, designed_path)
  # Change: the list also holds a degree total from the catalog scan, which
  # names no reading; no reading file can make it stale.
  utils::write.csv(rbind(drafts$questions, catalog_total_question_designed), file.path(out, "degree_reading_questions.csv"), row.names = FALSE)
  expect_length(read_degree_drafts(out, test_degree_programs)$questions_stale, 0L)
  # Change: the written list names a settler CEDAR does not know.
  unknown <- drafts$questions; unknown$settled_by <- "registrar"
  utils::write.csv(unknown, file.path(out, "degree_reading_questions.csv"), row.names = FALSE)
  expect_error(read_degree_drafts(out, test_degree_programs), "unknown settled_by")
  utils::write.csv(drafts$questions, file.path(out, "degree_reading_questions.csv"), row.names = FALSE)
  expect_false(any(drafts$evidence$evidence_id %in% test_degree_catalog$evidence$evidence_id))
  expect_null(read_degree_drafts(file.path(root, "none"), test_degree_programs))

  # Staged, not signed off: a draft.
  status <- degree_board_review_status(drafts, f$root)
  expect_equal(paste(status$review, status$note), "draft Its catalog reading is not signed off in Catalog Review.")
  expect_equal(degree_board_review_status(drafts, file.path(root, "elsewhere"))$note, "Its catalog reading is not staged in Catalog Review.")
  page <- publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, drafts, status)
  expect_equal(page$catalog$catalogs$catalog_id, test_degree_catalog$catalogs$catalog_id)
  expect_equal(page$status$source, ifelse(page$status$catalog_id == BIOLOGY, "compiled", "authored"))
  expect_equal(page$status$review[page$status$catalog_id == BIOLOGY], "draft")
  # The authored Biology board is gone from the page; History is untouched.
  ours <- page$roadmaps$nodes[page$roadmaps$nodes$catalog_id == BIOLOGY, ]
  expect_setequal(ours$node_id, board$roadmaps$nodes$node_id[board$roadmaps$nodes$catalog_id == BIOLOGY])
  expect_equal(page$roadmaps$nodes[page$roadmaps$nodes$catalog_id == HISTORY, ],
               test_degree_roadmaps$nodes[test_degree_roadmaps$nodes$catalog_id == HISTORY, ], ignore_attr = TRUE)
  expect_true(all(page$catalog$rules$rule_id[page$catalog$rules$catalog_id == BIOLOGY] %in% drafts$rules$rule_id))
  view <- build_degree_roadmap_view(page$catalog, page$roadmaps, BIOLOGY, "calculus", "composition", "fall")
  expect_true(all(c("start_1", "start_2") %in% view$nodes$node_id))

  # Signed off as compiled: reviewed.
  imported <- load_catalog_normalization_proposal(f$root, f$unit, manifest$proposal_key)
  state <- read_catalog_normalization_review(f$root, f$unit, imported)
  signed <- save_catalog_normalization_review(f$root, f$unit, imported, approve_catalog_normalization(state), "Designed reviewer", state$head)
  reviewed <- degree_board_review_status(drafts, f$root)
  expect_equal(reviewed$review, "reviewed")
  expect_equal(reviewed$note, paste0("Its catalog reading was signed off in Catalog Review on ", substr(signed$last_review$reviewed_at, 1, 10), "."))

  # Change: the reviewer edits a label and signs off again. The board was not
  # recompiled from the edited reading, so it is a draft again.
  edited <- settled; edited$nodes[[1]]$label <- "Complete the Biology major (edited)"
  again <- approve_catalog_normalization(edit_catalog_normalization(signed, edited, f$unit$request))
  save_catalog_normalization_review(f$root, f$unit, imported, again, "Designed reviewer", signed$head)
  expect_equal(degree_board_review_status(drafts, f$root)$note,
               "Its reading was signed off after edits; the board has not been recompiled from the edited reading.")

  # A draft never reuses an evidence id.
  reused <- drafts; reused$evidence$evidence_id[1] <- test_degree_catalog$evidence$evidence_id[1]
  expect_error(publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, reused, status), "already in the institution's evidence")
  # No drafts folder: the authored boards, unchanged.
  plain <- publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, NULL, degree_board_review_status(NULL, f$root))
  expect_true(all(plain$status$source == "authored"))
  expect_identical(plain$roadmaps, test_degree_roadmaps)
})

test_that("a compiled board for a program with no authored board joins the degree list, its codes checked like any board's", {
  root <- withr::local_tempdir()
  f <- normalization_fixture(root)
  courses <- degree_packet_course_facts(f$program$packet)
  nodes <- utils::read.csv(file.path(f$capture, "analysis", "rule-nodes.csv"), colClasses = "character")
  reading <- list(schema_version = "1.0.0", version = 1L, producer = "Designed maintainer draft",
    program_id = f$program$packet$program_id, catalog_id = f$program$packet$catalog_id, unit_key = f$unit$key,
    proposal = compiler_biology_proposal)
  staged <- file.path(root, "readings"); dir.create(staged)
  write_source_json(reading, file.path(staged, "biology.v1.json"))
  stage_catalog_normalization_drafts(f$root, staged, dirname(f$capture))
  compile <- function(row) assemble_compiled_degree_board(compile_degree_interpretation(compiler_biology_proposal, courses), courses,
    degree_packet_program_facts(f$program$packet), degree_course_requisites(nodes, courses), row, test_degree_roadmaps,
    test_degree_catalog$evidence, compiler_general_math_routes, degree_course_conditions(nodes, courses), compiler_biology_proposal, compiler_no_gen_ed_pools)
  manifest_row <- function(id) data.frame(catalog_id = id, program_id = reading$program_id, reading = "catalog_interpretations/biology.v1.json",
    packet_key = basename(f$program$directory), unit_key = reading$unit_key,
    proposal_key = degree_reading_proposal_key(f$root, f$program, reading),
    reading_sha256 = source_sha256(source_json_bytes(compiler_biology_proposal)), analysis = "analysis", compiled_on = "2026-11-26")
  publish <- function(row) {
    out <- file.path(root, row$catalog_id)
    write_degree_drafts(stats::setNames(list(compile(row)), row$catalog_id), manifest_row(row$catalog_id), out, test_degree_catalog$evidence,
                        catalog_questions_designed[0, ])  # no open questions: this test is about the boards
    drafts <- read_degree_drafts(out, test_degree_programs)
    publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, drafts, degree_board_review_status(drafts, f$root))
  }

  # Change: the designed catalog's Biology board is the B.S.; this draft is a
  # Biology B.A., a program with no authored board, as degree_reading_catalogs.csv gives it.
  ba <- compiler_biology_catalog_row
  ba$catalog_id <- "demo-biology-ba-draft"; ba$degree_code <- "BA"; ba$program_codes <- "BA-BIOL-AS"
  page <- publish(ba)
  # It follows the authored boards, which keep their order and their boards.
  expect_equal(page$catalog$catalogs$catalog_id, c(test_degree_catalog$catalogs$catalog_id, "demo-biology-ba-draft"))
  expect_equal(page$status$source, c(rep("authored", nrow(test_degree_catalog$catalogs)), "compiled"))
  expect_equal(page$status$review[page$status$catalog_id == "demo-biology-ba-draft"], "draft")
  expect_equal(page$roadmaps$nodes[page$roadmaps$nodes$catalog_id == BIOLOGY, ],
               test_degree_roadmaps$nodes[test_degree_roadmaps$nodes$catalog_id == BIOLOGY, ], ignore_attr = TRUE)
  # Its Banner code is its own, beside the authored boards'.
  codes <- page$catalog$program_codes
  expect_equal(codes$catalog_id[codes$program_code == "BA-BIOL-AS"], "demo-biology-ba-draft")
  expect_equal(codes$catalog_id[codes$program_code == "BS-BIOL-AS"], BIOLOGY)
  view <- build_degree_roadmap_view(page$catalog, page$roadmaps, "demo-biology-ba-draft", "calculus", "composition", "fall")
  expect_true(nrow(view$nodes) > 0L)

  # Change: a draft named History claiming the authored History board's code.
  # A code belongs to one board.
  history <- ba; history$program_name <- "History"; history$program_codes <- "BA-HIST-AS"
  expect_error(publish(history), "code belongs to one catalog")
  # Change: a code whose major is not the draft's program.
  other <- ba; other$program_codes <- "BA-HIST-AS"
  expect_error(publish(other), "not the catalog's program")
  # Change: a draft of the authored B.S. board whose codes were decided after it
  # was compiled. It stops for a recompile rather than show either set.
  stale <- compiler_biology_catalog_row; stale$catalog_id <- BIOLOGY; stale$program_codes <- "BS-BIOL-AS|BS-BIOL-UC"
  expect_error(publish(stale), "recompile the drafts")
})
