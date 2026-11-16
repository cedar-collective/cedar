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
    test_degree_catalog$evidence, "math1350", degree_course_conditions(nodes, courses), settled)
  manifest <- data.frame(catalog_id = BIOLOGY, program_id = reading$program_id, reading = "catalog_interpretations/biology.v1.json",
    packet_key = basename(f$program$directory), unit_key = reading$unit_key,
    proposal_key = degree_reading_proposal_key(f$root, f$program, reading),
    reading_sha256 = source_sha256(source_json_bytes(settled)), analysis = "analysis", compiled_on = "2026-11-16")
  out <- file.path(root, "degree_drafts")
  write_degree_drafts(stats::setNames(list(board), BIOLOGY), manifest, out, test_degree_catalog$evidence)
  drafts <- read_degree_drafts(out)
  expect_equal(drafts$manifest$catalog_id, BIOLOGY)
  expect_false(any(drafts$evidence$evidence_id %in% test_degree_catalog$evidence$evidence_id))
  expect_null(read_degree_drafts(file.path(root, "none")))

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

  # A draft replaces an authored board; it never adds one, or reuses an evidence id.
  stray <- drafts; stray$manifest$catalog_id <- "demo-unknown"; stray$catalogs$catalog_id <- "demo-unknown"
  expect_error(publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, stray, transform(status, catalog_id = "demo-unknown")), "replaces an authored board")
  reused <- drafts; reused$evidence$evidence_id[1] <- test_degree_catalog$evidence$evidence_id[1]
  expect_error(publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, reused, status), "already in the institution's evidence")
  # No drafts folder: the authored boards, unchanged.
  plain <- publish_degree_drafts(test_degree_catalog, test_degree_roadmaps, NULL, degree_board_review_status(NULL, f$root))
  expect_true(all(plain$status$source == "authored"))
  expect_identical(plain$roadmaps, test_degree_roadmaps)
})
