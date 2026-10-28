context("Degree Explorer")

# Public-source ingestion uses an authored catalog fixture, just like the demo
# CSVs below. It models nested alternatives/bundles, a prose condition, an
# unlabeled minor, an excluded graduate credential, and cyclic course links.
scan_fixture <- function() read_source_json(file.path(cedar_institution_dir(cedar_base_dir, "demo"), "catalog-source-fixture.json"))
scan_config <- function() {
  dir <- cedar_institution_dir(cedar_base_dir, "demo")
  list(source = as.list(read_institution_file("catalog_scan_sources", dir)[1, ]),
    credentials = read_institution_file("catalog_scan_credentials", dir),
    fields = read_institution_file("catalog_scan_fields", dir))
}
scan_fetcher <- function(fixture = scan_fixture(), observer = function(url) NULL) {
  force(fixture)
  function(url) {
    observer(url)
    base <- scan_config()$source$api_base
    edition <- fixture$edition$`_id`
    if (identical(url, scan_config()$source$landing_url)) {
      bytes <- charToRaw(paste0("<script>window.catalogId='", edition, "'</script>"))
    } else {
      path <- substring(url, nchar(base) + 1L)
      value <- if (path == "/public/catalogs") list(fixture$edition)
        else if (path == paste0("/public/catalogs/", edition)) fixture$edition
        else if (path == paste0("/programs/", edition)) fixture$index
        else if (startsWith(path, paste0("/schema/", edition, "/"))) fixture$schemas[[sub(".*/", "", path)]]
        else if (startsWith(path, paste0("/program/", edition, "/"))) fixture$programs[[sub(".*/", "", path)]]
        else if (startsWith(path, paste0("/course/byId/", edition, "/"))) fixture$courses[[sub(".*/", "", path)]]
        else stop("Unexpected fixture URL: ", url)
      if (is.null(value)) stop("Unexpected fixture record: ", url)
      bytes <- source_json_bytes(value)
    }
    list(body = bytes, final_url = url, status_code = 200L, content_type = "application/json",
      etag = "fixture-etag", last_modified = "")
  }
}

# Pipeline-shaped AI response scaffolding, deliberately unresolved throughout.
# Source facts remain in the authored demo catalog; no model is called in tests.
normalization_proposal <- function(request) {
  nodes <- lapply(seq_along(request$source_blocks), function(i) {
    block <- request$source_blocks[[i]]
    list(id = paste0("rule-", i), parent_id = "", entity_id = block$entity_id,
      phase = if (block$phase == "info") "information" else block$phase,
      kind = "unresolved", label = block$text, minimum = NULL, maximum = NULL,
      unit = "none", comparison = "none", value = "Designed unresolved passage", minimum_grade = "",
      course_refs = list(), program_ref = "", timing = "not_applicable",
      citations = list(list(block_id = block$id, quote = block$text)))
  })
  list(schema_version = "1.0.0", nodes = nodes,
    coverage = lapply(seq_along(nodes), function(i) list(block_id = request$source_blocks[[i]]$id,
      disposition = "unresolved", node_ids = list(nodes[[i]]$id), explanation = "Designed unresolved interpretation")),
    questions = list())
}

normalization_fixture <- function(root) {
  config <- scan_config(); capture <- file.path(root, "captures", "designed")
  capture_degree_catalog(config$source, config$credentials, config$fields, capture, fetch = scan_fetcher(), pause = 0)
  analyze_degree_catalog(capture)
  payload <- load_catalog_review(dirname(capture), "designed/analysis")
  store <- file.path(root, "reviews")
  path <- prepare_catalog_normalization(payload, "biology", store,
    paste(readLines(file.path(cedar_base_dir, "config/catalog-normalization-prompt.txt")), collapse = "\n"),
    read_source_json(file.path(cedar_base_dir, "config/catalog-normalization.schema.json")))
  program <- load_catalog_normalization_program(store, basename(path))
  list(program = program, root = store, payload = payload, capture = capture,
    unit = program$packet$units[[1]])
}

test_that("AI packets preserve complete source context and keep course units separate", {
  root <- tempfile("catalog-normalization-"); withr::defer(unlink(root, recursive = TRUE))
  f <- normalization_fixture(root); unit <- f$unit
  expect_length(f$program$packet$units, 4)
  expect_setequal(unlist(unit$request$target_entities), c("programs:biology", "specializations:cellular"))
  blocks <- unit$request$source_blocks
  round_trip <- jsonlite::fromJSON(rawToChar(source_json_bytes(unit$request)), simplifyVector = FALSE)
  expect_null(names(round_trip$source_blocks))
  expect_null(names(round_trip$context_blocks))
  expect_null(names(round_trip$documents))
  expect_true(any(vapply(blocks, function(x) grepl("two upper-level courses", x$text, fixed = TRUE), logical(1))))
  expect_true(any(vapply(blocks, function(x) x$source_pointer == "/specializations/0/concentrationRequirements", logical(1))))
  expect_true(any(vapply(blocks, function(x) x$source_pointer == "/degreeHours", logical(1))))
  expect_true(any(vapply(blocks, function(x) grepl("BIOL2110L", x$text, fixed = TRUE), logical(1))))
  expect_false("tree" %in% names(unit$request))
  expect_true(all(vapply(blocks, function(x) nzchar(x$dom_path) && nzchar(x$source_sha256), logical(1))))
  expect_silent(verify_catalog_normalization_sources(f$program, unit, dirname(f$capture)))
  expect_equal(nrow(list_catalog_normalization_programs(f$root)), 1)
  # Same sources/instructions reproduce the same identity, without replacing files.
  expect_identical(basename(prepare_catalog_normalization(f$payload, "biology", f$root,
    unit$request$instructions, unit$request$response_schema)), f$program$meta$key)
  changed <- prepare_catalog_normalization(f$payload, "biology", f$root,
    paste(unit$request$instructions, "Changed instruction"), unit$request$response_schema)
  expect_false(identical(basename(changed), f$program$meta$key))
  # The same specialization can be embedded under multiple programs. A parent
  # join must select this program's occurrence, not the first matching pid.
  other <- Filter(function(x) x$kind == "specializations", f$payload$records)[[1]]
  other$parent_program_id <- "another-program"
  alternate <- f$payload; alternate$records <- c(list(other), alternate$records)
  scoped <- prepare_catalog_normalization(alternate, "biology", file.path(root, "scoped"), unit$request$instructions, unit$request$response_schema)
  scoped <- load_catalog_normalization_program(file.path(root, "scoped"), basename(scoped))
  concentration <- Filter(function(x) x$id == "specializations:cellular", scoped$packet$units[[1]]$request$documents)[[1]]
  expect_match(concentration$catalog_url, "#/programs/biology", fixed = TRUE)
  response <- normalization_proposal(unit$request)
  expect_silent(validate_catalog_normalization(response, unit$request))
  bad <- response; bad$coverage <- bad$coverage[-1]
  expect_error(validate_catalog_normalization(bad, unit$request), "every requested block")
  bad <- response; bad$nodes[[1]]$citations[[1]]$quote <- "A quotation the catalog never published"
  expect_error(validate_catalog_normalization(bad, unit$request), "Citation does not match")
  bad <- response; bad$nodes[[1]]$entity_id <- "courses:course-one"
  expect_error(validate_catalog_normalization(bad, unit$request), "context-only entity")
  bad <- response; bad$nodes[[1]]$course_refs <- list("courses:not-captured")
  expect_error(validate_catalog_normalization(bad, unit$request), "Unknown or duplicate course")
  bad <- response; bad$nodes[[1]]$extra <- "not in schema"
  expect_error(validate_catalog_normalization(bad, unit$request), "missing/extra fields")
  bad <- response; bad$coverage[[1]]$disposition <- "information"
  expect_error(validate_catalog_normalization(bad, unit$request), "classified as information")
  bad <- response; bad$nodes[[1]]$citations[[1]]$block_id <- blocks[[2]]$id
  expect_error(validate_catalog_normalization(bad, unit$request), "Citation does not match")
  # A missing original blob must also fail when a derived packet remains valid.
  doc <- unit$request$documents[[1]]
  writeBin(charToRaw("modified"), file.path(f$capture, doc$receipt$file))
  expect_error(verify_catalog_normalization_sources(f$program, unit, dirname(f$capture)), "hash mismatch")
})

test_that("normalization preserves nested science bundles, grade scope and standing predicates", {
  root <- tempfile("catalog-ai-rules-"); withr::defer(unlink(root, recursive = TRUE))
  f <- normalization_fixture(root); request <- f$unit$request
  proposal <- normalization_proposal(request)
  texts <- vapply(request$source_blocks, function(x) x$text, character(1))
  find <- function(pattern) { i <- which(grepl(pattern, texts, fixed = TRUE)); expect_length(i, 1); i }
  choice <- find("Complete at least 1 of the following:")
  lecture <- find("BIOL2110 - Biology I (3)")
  lab <- find("BIOL2110L - Biology I Lab (1)")
  combined <- which(texts == "BIOL200 - Combined Biology (4)" & vapply(request$source_blocks, function(x) x$entity_id == "programs:biology", logical(1)))
  bundle <- which(texts == "Complete the following:" & vapply(request$source_blocks, function(x) x$entity_id == "programs:biology", logical(1)))
  expect_length(bundle, 1); expect_length(combined, 1)
  proposal$nodes[[choice]]$kind <- "choose_n"; proposal$nodes[[choice]]$minimum <- 1
  proposal$nodes[[choice]]$unit <- "courses"; proposal$nodes[[choice]]$minimum_grade <- "C-"
  proposal$nodes[[bundle]]$kind <- "all"; proposal$nodes[[bundle]]$parent_id <- proposal$nodes[[choice]]$id
  for (i in c(lecture, lab, combined)) {
    proposal$nodes[[i]]$kind <- "course"
    proposal$nodes[[i]]$parent_id <- proposal$nodes[[if (i == combined) choice else bundle]]$id
  }
  proposal$nodes[[lecture]]$course_refs <- list("courses:course-one")
  proposal$nodes[[lab]]$course_refs <- list("courses:course-lab")
  proposal$nodes[[combined]]$course_refs <- list("courses:course-two")
  expect_silent(validate_catalog_normalization(proposal, request))
  expect_equal(sum(vapply(proposal$nodes, function(x) x$parent_id == proposal$nodes[[choice]]$id, logical(1))), 2)
  expect_equal(proposal$nodes[[choice]]$minimum_grade, "C-")
  bad <- proposal; bad$nodes[[choice]]$minimum <- 3
  expect_error(validate_catalog_normalization(bad, request), "Invalid choice count")
  bad <- proposal; bad$nodes[[choice]]$parent_id <- proposal$nodes[[bundle]]$id
  expect_error(validate_catalog_normalization(bad, request), "cycle")
  bad <- proposal; bad$nodes[[lab]]$phase <- "admission"
  expect_error(validate_catalog_normalization(bad, request), "phase boundary")
  course <- f$program$packet$units[[2]]
  if (!"courses:course-one" %in% unlist(course$request$target_entities)) course <- Filter(function(x) "courses:course-one" %in% unlist(x$request$target_entities), f$program$packet$units)[[1]]
  standing <- normalization_proposal(course$request)
  i <- which(vapply(course$request$source_blocks, function(x) x$text == "Must have a class standing of Junior", logical(1)))
  expect_length(i, 1)
  standing$nodes[[i]]$kind <- "class_standing"; standing$nodes[[i]]$comparison <- "equals"; standing$nodes[[i]]$value <- "Junior"
  expect_silent(validate_catalog_normalization(standing, course$request))
  expect_match(catalog_normalization_node_summary(standing$nodes[[i]], course$request$reference_registry), "equals Junior", fixed = TRUE)
})

test_that("human reviews retain original AI output, reset edited approvals and reject stale writers", {
  root <- tempfile("catalog-ai-review-"); withr::defer(unlink(root, recursive = TRUE))
  f <- normalization_fixture(root); unit <- f$unit
  proposal <- normalization_proposal(unit$request)
  path <- file.path(root, "response.json"); write_source_json(proposal, path)
  key <- import_catalog_normalization(f$root, unit, path, "Designed AI response fixture")
  imported <- load_catalog_normalization_proposal(f$root, unit, key)
  expect_identical(imported$original, proposal)
  expect_length(list_catalog_normalization_proposals(f$root, unit), 1)
  state <- read_catalog_normalization_review(f$root, unit, imported)
  expect_false(catalog_normalization_approved(state))
  id <- proposal$nodes[[1]]$id; block <- proposal$coverage[[1]]$block_id
  expect_error(catalog_normalization_decision(state, "nodes", id, "approved", ""), "unresolved")
  expect_error(catalog_normalization_decision(state, "blocks", block, "needs_clarification", ""), "Explain")
  next_state <- catalog_normalization_decision(state, "blocks", block, "needs_clarification", "Check the course count")
  expect_error(save_catalog_normalization_review(f$root, unit, imported, next_state, "", state$head), "your name")
  saved <- save_catalog_normalization_review(f$root, unit, imported, next_state, "Designed reviewer", state$head)
  expect_equal(saved$revision, 1)
  expect_equal(saved$blocks[[block]], "needs_clarification")
  expect_identical(saved$last_review$reviewer, "Designed reviewer")
  expect_error(save_catalog_normalization_review(f$root, unit, imported, next_state, "Other reviewer", state$head), "another session")
  expect_error(export_catalog_normalization(f$program, unit, imported, saved), "sign off the complete unit")
  expect_error(approve_catalog_normalization(saved), "open review cases")
  expect_equal(nrow(catalog_normalization_issues(saved)), length(proposal$nodes) + 1L)
  resolved <- edit_catalog_normalization_node(state, id, list(kind = "restriction", value = "Corrected predicate"), unit$request)
  expect_equal(resolved$proposal$coverage[[1]]$disposition, "requirements")
  expect_equal(nrow(catalog_normalization_issues(resolved)), length(proposal$nodes) - 1L)
  expect_error(clear_catalog_normalization_flag(state, "nodes", id, "Checked"), "edit an unresolved")
  # This fixture tests the review/export contract, not an academic judgment:
  # a reviewer explicitly changes every unresolved item to informational.
  edited <- proposal
  edited$nodes <- lapply(edited$nodes, function(x) { x$kind <- "information"; x })
  edited$coverage <- lapply(edited$coverage, function(x) { x$disposition <- "information"; x })
  changed <- edit_catalog_normalization(saved, edited, unit$request)
  expect_true(all(unlist(changed$blocks) == "pending"))
  expect_equal(nrow(catalog_normalization_issues(changed)), 0)
  expect_false(catalog_normalization_approved(changed))
  changed <- approve_catalog_normalization(changed)
  approved <- save_catalog_normalization_review(f$root, unit, imported, changed, "Designed reviewer", saved$head)
  expect_true(catalog_normalization_approved(approved))
  expect_true(all(unlist(approved$nodes) == "approved"))
  expect_true(all(unlist(approved$blocks) == "confirmed"))
  flagged <- catalog_normalization_decision(approved, "nodes", names(approved$nodes)[1], "needs_clarification", "Check scope")
  expect_false(catalog_normalization_approved(flagged))
  expect_equal(nrow(catalog_normalization_issues(flagged)), 1)
  expect_error(approve_catalog_normalization(flagged), "open review cases")
  expect_error(clear_catalog_normalization_flag(flagged, "nodes", names(flagged$nodes)[1], ""), "explain")
  cleared <- clear_catalog_normalization_flag(flagged, "nodes", names(flagged$nodes)[1], "Scope checked against full section")
  expect_false(catalog_normalization_approved(cleared))
  expect_true(catalog_normalization_approved(approve_catalog_normalization(cleared)))
  questioned <- changed; questioned$proposal$questions <- list(list(block_id = block, question = "What is the scope?"))
  expect_error(approve_catalog_normalization(questioned), "open review cases")
  exported <- export_catalog_normalization(f$program, unit, imported, approved)
  expect_equal(exported$status, "human_reviewed")
  expect_identical(exported$requirements, edited)
  expect_identical(load_catalog_normalization_proposal(f$root, unit, key)$original, proposal)
  reset <- edit_catalog_normalization_node(approved, edited$nodes[[1]]$id, list(label = "Corrected explanation"), unit$request)
  expect_false(catalog_normalization_approved(reset))
  expect_true(all(unlist(reset$nodes) == "pending"))
  history <- list.files(file.path(f$root, "reviews", key), full.names = TRUE)
  writeBin(charToRaw("changed"), history[1])
  expect_error(read_catalog_normalization_review(f$root, unit, imported))
})

test_that("versioned local drafts stage automatically without creating human approvals", {
  root <- tempfile("catalog-local-draft-"); withr::defer(unlink(root, recursive = TRUE))
  f <- normalization_fixture(root); directory <- file.path(root, "drafts"); dir.create(directory)
  proposal <- normalization_proposal(f$unit$request)
  artifact <- list(schema_version = "1.0.0", version = 1L, producer = "Designed maintainer draft",
    program_id = f$program$packet$program_id, catalog_id = f$program$packet$catalog_id,
    unit_key = f$unit$key, proposal = proposal)
  path <- file.path(directory, "biology.v1.json"); write_source_json(artifact, path)
  first <- stage_catalog_normalization_drafts(f$root, directory, dirname(f$capture))
  expect_length(first, 1)
  expect_identical(stage_catalog_normalization_drafts(f$root, directory, dirname(f$capture)), first)
  expect_length(list_catalog_normalization_proposals(f$root, f$unit), 1)
  original <- load_catalog_normalization_proposal(f$root, f$unit, first[[1]])
  expect_match(original$meta$model, "draft v1", fixed = TRUE)
  state <- read_catalog_normalization_review(f$root, f$unit, original)
  expect_equal(state$revision, 0)
  expect_false(catalog_normalization_approved(state))
  # One unresolved interpretation is one case even when multiple passages cite it.
  expect_equal(nrow(catalog_normalization_issues(state)), length(proposal$nodes))
  artifact$version <- 2L
  artifact$proposal$nodes[[1]]$label <- "Corrected interpretation"
  write_source_json(artifact, file.path(directory, "biology.v2.json"))
  next_keys <- stage_catalog_normalization_drafts(f$root, directory, dirname(f$capture))
  expect_length(unique(next_keys), 2)
  expect_identical(load_catalog_normalization_proposal(f$root, f$unit, first[[1]])$original, proposal)
  artifact$proposal$nodes[[1]]$citations[[1]]$quote <- "Invented evidence"
  write_source_json(artifact, file.path(directory, "biology.v2.json"))
  expect_error(stage_catalog_normalization_drafts(f$root, directory, dirname(f$capture)), "Citation does not match")
  artifact$unit_key <- strrep("a", 64)
  write_source_json(artifact, file.path(directory, "biology.v2.json"))
  expect_error(stage_catalog_normalization_drafts(f$root, directory, dirname(f$capture)), "matching source packet")
})

test_that("catalog extraction preserves OR options containing AND course bundles", {
  fixture <- scan_fixture()
  tree <- extract_catalog_rule_tree(fixture$programs$biology$degreeRequirements)
  choice <- tree$children[[1]]$children[[1]]
  expect_identical(tree$children[[1]]$operator, "all")
  expect_identical(choice$operator, "choose_n")
  expect_equal(choice$minimum, 1)
  expect_length(choice$children, 2)
  expect_identical(choice$children[[1]]$operator, "all")
  expect_length(choice$children[[1]]$children, 2)
  expect_identical(choice$children[[1]]$children[[2]]$course_references[[1]]$code, "BIOL2110L")
  expect_false(tree$requires_review)
  condition <- extract_catalog_rule_tree(fixture$programs$biology$graduateAdmissionsRequirements)
  expect_true(condition$requires_review)
  expect_identical(condition$children[[1]]$operator, "condition")
  expect_length(condition$children[[1]]$course_references, 0)
  qualified <- extract_catalog_rule_tree('<ul><li><a href="#/courses/view/bio1">BIOL2110</a> - Biology I (3); minimum grade C</li></ul>')
  expect_identical(qualified$children[[1]]$operator, "condition")
  expect_true(qualified$requires_review)
  expect_error(validate_catalog_index(list()), "nonempty")
  bad <- fixture$index; bad[[1]]$degreeType$name <- "Unclassified new credential"
  expect_error(catalog_program_scope(bad, scan_config()$credentials), "Unclassified degree types")
  expect_error(catalog_program_scope(fixture$index, scan_config()$credentials["degree_type"]), "credential classification")
})

test_that("standard grade rules retain threshold, selection and nested course scope", {
  fixture <- scan_fixture()
  all <- extract_catalog_rule_tree(fixture$courses$biolab$corequisites)
  expect_false(all$requires_review)
  rule <- all$children[[1]]
  expect_equal(rule$operator, "all")
  expect_equal(rule$minimum_grade, "C")
  expect_equal(rule$children[[1]]$course_references[[1]]$code, "BIOL2110")
  expect_match(paste(catalog_review_tree_text(all), collapse = "\n"), "[minimum grade C]", fixed = TRUE)
  choice <- extract_catalog_rule_tree(fixture$parser_cases$grade_choice)
  rule <- choice$children[[1]]
  expect_false(choice$requires_review)
  expect_equal(rule$operator, "choose_n")
  expect_equal(rule$minimum, 1)
  expect_equal(rule$minimum_grade, "C-")
  expect_length(rule$children, 2)
  expect_equal(rule$children[[1]]$operator, "all")
  expect_length(rule$children[[1]]$children, 2)
  # The threshold applies to the option group; a lecture/lab AND bundle stays
  # one option, with its two courses retained. No grade is guessed for a leaf.
  expect_null(rule$children[[1]]$children[[1]]$minimum_grade)
  higher <- all; higher$children[[1]]$minimum_grade <- "C-"
  expect_false(identical(catalog_rule_structure(all), catalog_rule_structure(higher)))
  for (name in c("grade_qualified", "grade_empty", "grade_impossible", "grade_concurrent")) {
    unresolved <- extract_catalog_rule_tree(fixture$parser_cases[[name]])
    expect_true(unresolved$requires_review, info = name)
    expect_equal(unresolved$children[[1]]$operator, "condition", info = name)
  }
  missing <- extract_catalog_rule_tree(fixture$parser_cases$missing_course)
  expect_true(missing$requires_review)
  expect_equal(missing$children[[1]]$minimum_grade, "C")
  expect_equal(missing$children[[1]]$children[[1]]$operator, "condition")
})

test_that("catalog option wrappers preserve every group and distinguish headings from conditions", {
  fixture <- scan_fixture()
  tree <- extract_catalog_rule_tree(fixture$parser_cases$wrapped_choice)
  choice <- tree$children[[1]]
  expect_false(tree$requires_review)
  expect_equal(choice$operator, "choose_n")
  expect_equal(choice$minimum, 1)
  expect_length(choice$children, 2)
  expect_equal(vapply(choice$children, function(x) x$text, character(1)), c("Major study", "Second major"))
  expect_equal(choice$children[[1]]$operator, "group")
  expect_equal(choice$children[[1]]$children[[1]]$operator, "all")
  expect_length(choice$children[[1]]$children[[1]]$children, 2)
  expect_equal(choice$children[[2]]$children[[1]]$children[[1]]$course_references[[1]]$code, "BIOL200")
  qualified <- extract_catalog_rule_tree(fixture$parser_cases$qualified_wrapper)
  expect_true(qualified$requires_review)
  expect_equal(qualified$children[[1]]$operator, "condition")
  expect_match(qualified$children[[1]]$text, "department permission", fixed = TRUE)
  expect_length(qualified$children[[1]]$children, 1)
  qualified <- extract_catalog_rule_tree(fixture$parser_cases$qualified_heading)
  expect_true(qualified$requires_review)
  expect_equal(qualified$children[[1]]$operator, "condition")
  expect_match(qualified$children[[1]]$text, "permission required", fixed = TRUE)
  direct <- extract_catalog_rule_tree(fixture$parser_cases$direct_list_text)
  expect_true(direct$requires_review)
  expect_equal(direct$children[[1]]$text, "Department permission required")
  expect_equal(direct$children[[2]]$operator, "course")
  orphan <- extract_catalog_rule_tree(fixture$parser_cases$orphan_list)
  expect_true(orphan$requires_review)
  expect_equal(orphan$children[[1]]$operator, "condition")
  expect_equal(orphan$children[[1]]$course_references[[1]]$code, "BIOL200")
})

test_that("standing milestones preserve literal statuses, exclusions and OR context", {
  fixture <- scan_fixture()
  tree <- extract_catalog_rule_tree(fixture$courses$biolab$prerequisites)
  choice <- tree$children[[1]]
  expect_false(tree$requires_review)
  expect_equal(choice$operator, "choose_n")
  expect_equal(choice$minimum, 1)
  expect_equal(vapply(choice$children, function(x) x$milestone$value, character(1)), c("Junior", "Senior"))
  expect_true(all(vapply(choice$children, function(x) x$operator == "milestone", logical(1))))
  expect_equal(choice$children[[1]]$milestone$relation, "is")
  expect_equal(choice$children[[1]]$milestone$id, "class_standing:is:Junior")
  expect_null(choice$children[[1]]$minimum)
  expect_length(choice$children[[1]]$course_references, 0)
  exclusion <- extract_catalog_rule_tree(fixture$parser_cases$standing_exclusion)$children[[1]]
  expect_equal(exclusion$milestone$relation, "is_not")
  expect_equal(exclusion$milestone$value, "Freshman")
  for (name in c("standing_qualified", "standing_inline_choice", "standing_credits",
    "admission_unlinked", "admission_qualified", "admission_negative", "admission_multiple")) {
    unresolved <- extract_catalog_rule_tree(fixture$parser_cases[[name]])
    expect_equal(unresolved$children[[1]]$operator, "condition", info = name)
    expect_true(unresolved$requires_review, info = name)
  }
})

test_that("program milestones resolve source links, retain policy evidence and share definitions", {
  fixture <- scan_fixture(); config <- scan_config(); root <- tempfile("catalog-milestones-")
  out <- file.path(root, "capture")
  withr::defer(unlink(root, recursive = TRUE))
  capture_degree_catalog(config$source, config$credentials, config$fields, out, fetch = scan_fetcher(), pause = 0)
  analyze_degree_catalog(out)
  payload <- load_catalog_review(root, "capture/analysis")
  expect_true(payload$milestone_support)
  expect_equal(payload$meta$counts$milestones, 3)
  expect_equal(payload$meta$counts$milestone_uses, 4)
  definitions <- payload$milestones
  junior <- definitions[definitions$milestone_id == "class_standing:is:Junior", ]
  expect_equal(junior$rule_uses, "2")
  expect_equal(junior$course_records, "2")
  admission <- definitions[definitions$type == "program_admission", ]
  expect_equal(admission$milestone_id, "program_admission:biology")
  expect_equal(admission$target_program_id, "biology")
  expect_identical(admission$admission_text, catalog_html_text(fixture$programs$biology$graduateAdmissionsRequirements))
  views <- filter_catalog_review(payload)
  expect_equal(nrow(views$milestones), 4)
  expect_true(all(views$milestones$review_status == "Unreviewed"))
  use <- views$milestones[views$milestones$milestone_id == admission$milestone_id, ]
  detail <- catalog_review_detail(payload, use$item_id)
  expect_match(detail$tree, "program_admission:biology", fixed = TRUE)
  expect_length(detail$admission_evidence, 1)
  expect_identical(detail$admission_evidence[[1]]$value, fixture$programs$biology$graduateAdmissionsRequirements)
  expect_equal(detail$admission_evidence[[1]]$pointer, "/graduateAdmissionsRequirements")
  # The reference and its policy are independently verified on every Inspect.
  program <- Filter(function(x) x$kind == "programs", payload$records)[[1]]
  writeBin(charToRaw("changed"), file.path(out, program$source$file))
  expect_error(catalog_review_detail(payload, use$item_id), "hash mismatch")
  # A program outside the frozen undergraduate capture is not guessed from its
  # label, nor does the scanner expand scope to capture another credential.
  missing <- fixture
  missing$courses$bio1$program <- fixture$parser_cases$admission_missing
  other <- file.path(root, "missing-target")
  capture_degree_catalog(config$source, config$credentials, config$fields, other, fetch = scan_fetcher(missing), pause = 0)
  analyze_degree_catalog(other)
  unresolved <- load_catalog_review(root, "missing-target/analysis")
  expect_equal(unresolved$meta$counts$milestones, 2)
  expect_true(any(grepl("Admitted to BS Biology", filter_catalog_review(unresolved)$interpretation$excerpt, fixed = TRUE)))
})

test_that("catalog capture inventories every entry and follows course links without looping", {
  config <- scan_config(); out <- tempfile("catalog-capture-")
  withr::defer(unlink(out, recursive = TRUE))
  capture_degree_catalog(config$source, config$credentials, config$fields, out, fetch = scan_fetcher(), pause = 0)
  manifest <- catalog_capture_manifest(out)
  inventory <- read.csv(file.path(out, "program-inventory.csv"))
  expect_equal(nrow(inventory), 3)
  expect_equal(inventory$scope, c("undergraduate_degree", "excluded", "excluded"))
  expect_equal(unlist(manifest$program_ids), "biology")
  expect_equal(sum(vapply(manifest$requests, function(x) x$kind == "course", logical(1))), 3)
  expect_false("program:graduate" %in% names(manifest$requests))
  unavailable <- function(url) { value <- scan_fetcher()(url); value$status_code <- 404L; value }
  expect_error(capture_public_source(config$source$landing_url, tempfile(), "landing", "page",
    fetch = unavailable, document_format = "html"), "Invalid source response")
  expect_error(capture_degree_catalog(config$source, config$credentials, config$fields, out,
    fetch = scan_fetcher(), pause = 0), "already exists")
  analysis <- analyze_degree_catalog(out)
  summary <- read_source_json(file.path(analysis, "analysis-manifest.json"))
  expect_equal(summary$counts$degrees, 1)
  expect_equal(summary$counts$specializations, 1)
  expect_equal(summary$counts$course_requests, 3)
  expect_equal(summary$counts$source_issues, 1)
  issues <- read.csv(file.path(analysis, "source-issues.csv"))
  expect_equal(issues$issue, "source_query_flag_false")
  expect_equal(issues$entity, "courses:course-one")
  sections <- read.csv(file.path(analysis, "sections.csv"))
  expect_equal(sections$label[sections$field == "graduateAdmissionsRequirements"], "Admissions Requirements")
  rules <- read.csv(file.path(analysis, "rule-nodes.csv"))
  expect_true(all(rules$review_status == "unreviewed"))
  prose <- rules[rules$field == "graduateAdmissionsRequirements" & rules$operator != "document", ]
  expect_equal(prose$operator, "condition")
  expect_equal(prose$course_codes, "")
  expect_equal(rules$operator[rules$entity == "courses:course-two" & rules$field == "program" & rules$operator != "document"], "condition")
  grade <- rules[rules$entity == "courses:course-lab" & rules$operator == "all", ]
  expect_equal(grade$minimum_grade, "C")
  expect_false(grade$requires_review)
  queue <- lapply(readLines(file.path(analysis, "review-queue.jsonl")), jsonlite::fromJSON)
  expect_false(any(vapply(queue, function(x) identical(x$node_id, grade$node_id), logical(1))))
  expect_true(all(nzchar(rules$source_pointer)))
  expect_match(readLines(file.path(analysis, "REPORT.md"))[1], "Designed Catalog")
  expect_error(analyze_degree_catalog(out), "already exists")
})

test_that("conflicting total-credit mentions are flagged without claiming which number is right", {
  config <- scan_config()
  baseline <- tempfile("catalog-credits-baseline-")
  withr::defer(unlink(baseline, recursive = TRUE))
  capture_degree_catalog(config$source, config$credentials, config$fields, baseline, fetch = scan_fetcher(), pause = 0)
  analyze_degree_catalog(baseline)
  clean_issues <- read.csv(file.path(baseline, "analysis", "source-issues.csv"))
  expect_false("total_credit_conflict" %in% clean_issues$issue)

  conflicting <- scan_fixture()
  conflicting$programs$biology$description <- "<p>Grand Total Credits: 130</p>"
  out <- tempfile("catalog-credits-conflict-")
  withr::defer(unlink(out, recursive = TRUE))
  capture_degree_catalog(config$source, config$credentials, config$fields, out, fetch = scan_fetcher(conflicting), pause = 0)
  analyze_degree_catalog(out)
  issues <- read.csv(file.path(out, "analysis", "source-issues.csv"))
  flagged <- issues[issues$issue == "total_credit_conflict", ]
  expect_equal(nrow(flagged), 1L)
  expect_equal(flagged$entity, "programs:biology")
  expect_match(flagged$detail, "Degree Hours \\(structured field\\): 120", perl = TRUE)
  expect_match(flagged$detail, "Grand Total Credits: 130", perl = TRUE)
  expect_match(flagged$detail, "does not say which number is correct", fixed = TRUE)

  consistent <- scan_fixture()
  consistent$programs$biology$description <- "<p>Grand Total Credits: 120</p>"
  matched <- tempfile("catalog-credits-consistent-")
  withr::defer(unlink(matched, recursive = TRUE))
  capture_degree_catalog(config$source, config$credentials, config$fields, matched, fetch = scan_fetcher(consistent), pause = 0)
  analyze_degree_catalog(matched)
  agreeing <- read.csv(file.path(matched, "analysis", "source-issues.csv"))
  expect_false("total_credit_conflict" %in% agreeing$issue)
})

test_that("failed captures resume from verified bytes and tampering blocks extraction", {
  config <- scan_config(); out <- tempfile("catalog-resume-")
  withr::defer(unlink(out, recursive = TRUE))
  failed <- FALSE; calls <- character()
  observe <- function(url) {
    calls <<- c(calls, url)
    if (endsWith(url, "/minor") && !failed) { failed <<- TRUE; stop("Network unavailable") }
  }
  fetch <- scan_fetcher(observer = observe)
  expect_error(capture_degree_catalog(config$source, config$credentials, config$fields, out,
    fetch = fetch, pause = 0), "Network unavailable")
  expect_error(catalog_capture_manifest(out), "incomplete")
  expect_error(analyze_degree_catalog(out), "incomplete")
  capture_degree_catalog(config$source, config$credentials, config$fields, out,
    resume = TRUE, fetch = fetch, pause = 0)
  expect_equal(sum(endsWith(calls, "/program/demo-edition/biology")), 1)
  manifest <- catalog_capture_manifest(out)
  receipt <- manifest$requests[["program:biology"]]
  writeBin(charToRaw("changed"), file.path(out, receipt$file))
  expect_error(analyze_degree_catalog(out), "hash mismatch")
})

test_that("catalog review connects flagged language to full immutable source context", {
  config <- scan_config(); root <- tempfile("catalog-review-"); out <- file.path(root, "capture")
  withr::defer(unlink(root, recursive = TRUE))
  expect_equal(nrow(list_catalog_review_scans(root)), 0)
  capture_degree_catalog(config$source, config$credentials, config$fields, out, fetch = scan_fetcher(), pause = 0)
  analyze_degree_catalog(out)
  index <- list_catalog_review_scans(root)
  expect_equal(index$scan_id, "capture/analysis")
  payload <- load_catalog_review(root, index$scan_id)
  key <- catalog_review_cache_key(root, index$scan_id)
  expect_identical(catalog_review_cache_key(root, index$scan_id), key)
  report_path <- file.path(out, "analysis", "REPORT.md")
  report_bytes <- readBin(report_path, "raw", n = file.info(report_path)$size)
  # A changed artifact cannot enter a warm cache, even at the same byte length.
  changed_report <- report_bytes; changed_report[1] <- charToRaw("!")
  writeBin(changed_report, report_path)
  expect_error(catalog_review_cache_key(root, index$scan_id), "modified analysis artifact")
  writeBin(report_bytes, report_path)
  expect_identical(catalog_review_cache_key(root, index$scan_id), key)
  views <- filter_catalog_review(payload, program = "biology")
  # One program, its concentration, and three cyclically linked courses: once each.
  expect_setequal(catalog_review_program_entities(payload$records, "biology"),
    c("programs:biology", "specializations:cellular", "courses:course-one", "courses:course-two", "courses:course-lab"))
  expect_length(catalog_review_program_entities(payload$records, "biology"), 5)
  expect_equal(nrow(views$source), 1)
  expect_match(views$source$next_step, "does not establish cancellation", fixed = TRUE)
  expect_true(all(views$items$review_status == "Unreviewed"))
  admission <- filter_catalog_review(payload, kind = "Degree", phase = "Admission")$interpretation
  expect_equal(nrow(admission), 1)
  detail <- catalog_review_detail(payload, admission$item_id)
  expect_identical(detail$source, scan_fixture()$programs$biology$graduateAdmissionsRequirements)
  expect_equal(detail$item$source_pointer, "/graduateAdmissionsRequirements")
  expect_equal(detail$catalog_url, paste0(config$source$landing_url, "#/programs/biology"))
  concentration <- views$sections[views$sections$kind == "Concentration", ]
  detail <- catalog_review_detail(payload, concentration$item_id)
  expect_identical(detail$source, scan_fixture()$programs$biology$specializations[[1]]$concentrationRequirements)
  expect_equal(detail$item$source_pointer, "/specializations/0/concentrationRequirements")
  expect_match(detail$catalog_url, "#/programs/biology", fixed = TRUE)
  program <- views$sections[views$sections$kind == "Degree" & views$sections$phase == "Degree", ]
  detail <- catalog_review_detail(payload, program$item_id)
  expect_match(detail$tree, "Choose at least 1", fixed = TRUE)
  expect_match(detail$tree, "BIOL2110L", fixed = TRUE)
  expect_identical(detail$source, scan_fixture()$programs$biology$degreeRequirements)
  lab <- views$sections[views$sections$entity == "courses:course-lab" & views$sections$phase == "Corequisite", ]
  expect_match(catalog_review_detail(payload, lab$item_id)$tree, "[minimum grade C]", fixed = TRUE)
  expect_false(any(views$interpretation$entity == "courses:course-lab"))
  expect_identical(catalog_review_detail(payload, views$source$item_id)$source, FALSE)
  expect_error(load_catalog_review(root, "../elsewhere"), "Select an available")
  expect_error(catalog_review_detail(payload, "missing-id"), "Select one available")
  expect_error(source_json_pointer(scan_fixture(), "/programs/biology/not-a-field"), "does not resolve")
  # Early schema-1.0.0 analyses lack the later source-issues report. The same
  # source checks still run against frozen records; missing facts are not zeros.
  meta_path <- file.path(out, "analysis", "analysis-manifest.json")
  meta <- read_source_json(meta_path)
  meta$files$`source-issues.csv` <- NULL; meta$counts$source_issues <- NULL
  write_source_json(meta, meta_path)
  unlink(file.path(out, "analysis", "source-issues.csv"))
  expect_equal(load_catalog_review(root, index$scan_id)$source_check_count, 1)
  expect_false(identical(catalog_review_cache_key(root, index$scan_id), key))
  # Evidence is checked again on Inspect, even after a page payload was loaded.
  receipt <- payload$records[[1]]$source
  writeBin(charToRaw("changed"), file.path(out, receipt$file))
  # The queue uses verified derived artifacts; original blobs are checked only
  # when read as evidence. Full offline verification still checks every blob.
  expect_equal(nrow(load_catalog_review(root, index$scan_id)$items), nrow(payload$items))
  expect_error(catalog_capture_manifest(out), "hash mismatch")
  expect_error(catalog_review_detail(payload, program$item_id), "hash mismatch")
})

test_that("catalog evidence renderer preserves nesting and cannot execute source markup", {
  withr::local_package("shiny")
  withr::local_package("bslib")
  load_funcs(cedar_base_dir, modules = TRUE)
  html <- as.character(catalog_review_source_view('<ul onclick="bad()"><li><a href="javascript:bad()">One</a><ul><li>Two &amp; three</li></ul></li></ul><script>bad()</script><img src="x" onerror="bad()">'))
  expect_match(html, "<ul>", fixed = TRUE)
  expect_match(html, "Two &amp; three", fixed = TRUE)
  expect_false(grepl("script|onclick|onerror|javascript:|src=|bad\\(", html))
  ui <- as.character(catalogReviewUI("catalog_review", test_degree_catalog, test_degree_roadmaps))
  expect_match(ui, "Visualization rules", fixed = TRUE)
  expect_match(ui, "not a checklist for approving the visualization", fixed = TRUE)
  expect_match(ui, "catalog_review-interpretation", fixed = TRUE)
  expect_match(ui, "Program coverage", fixed = TRUE)
})

test_that("catalog comparisons separate choice changes, formatting and missing scope", {
  config <- scan_config(); old <- tempfile("catalog-before-"); new <- tempfile("catalog-after-"); diff <- tempfile("catalog-diff-")
  withr::defer(unlink(c(old, new, diff), recursive = TRUE))
  capture_degree_catalog(config$source, config$credentials, config$fields, old, fetch = scan_fetcher(), pause = 0)
  changed <- scan_fixture()
  changed$edition$`_id` <- "demo-next-edition"
  changed$edition$title <- "2027-2028 Designed Catalog"
  changed$programs$biology$degreeRequirements <- sub("<span>1</span>", "<span>2</span>", changed$programs$biology$degreeRequirements, fixed = TRUE)
  changed$courses$bio2$credits$value <- 5
  changed$courses$biolab$corequisites <- sub("<span>C</span>", "<span>C-</span>", changed$courses$biolab$corequisites, fixed = TRUE)
  changed$courses$bio1$prerequisites <- sub("Junior", "Sophomore", changed$courses$bio1$prerequisites, fixed = TRUE)
  capture_degree_catalog(config$source, config$credentials, config$fields, new, fetch = scan_fetcher(changed), pause = 0)
  before <- analyze_degree_catalog(old); after <- analyze_degree_catalog(new)
  compare_degree_catalog_scans(before, after, diff)
  changes <- read.csv(file.path(diff, "changes.csv"))
  expect_equal(nrow(changes), 4)
  expect_equal(changes$change[changes$field == "degreeRequirements"], "structure_and_wording_changed")
  expect_equal(changes$change[changes$entity == "courses:course-two"], "metadata_changed")
  expect_equal(changes$change[changes$entity == "courses:course-lab"], "structure_and_wording_changed")
  expect_equal(changes$change[changes$entity == "courses:course-one"], "structure_and_wording_changed")
  comparison <- read_source_json(file.path(diff, "comparison-manifest.json"))
  expect_false(comparison$extractor_changed)
  expect_false(comparison$configuration_changed)
  expect_equal(comparison$after$catalog_title, "2027-2028 Designed Catalog")
  same <- read.csv(file.path(before, "sections.csv"), colClasses = "character")
  format_only <- same; format_only$html_sha256[1] <- "format-change"
  expect_equal(compare_catalog_sections(same, format_only)$change, "formatting_only")
  ambiguous <- rbind(same, same[1, ])
  expect_error(compare_catalog_sections(same, ambiguous), "ambiguous")
  meta <- read_source_json(file.path(after, "analysis-manifest.json")); meta$include_courses <- FALSE
  write_source_json(meta, file.path(after, "analysis-manifest.json"))
  expect_error(compare_degree_catalog_scans(before, after, tempfile()), "same program and course capture scope")
})

# The demo institution's designed catalog (institution/demo/degree_*.csv,
# exposed by setup.R as test_degree_catalog / test_degree_roadmaps) holds two
# synthetic programs built to exercise each planning rule. Every schedule below
# is worked by hand from those files.
#
# Biology B.S., calculus-ready, Composition I, fall start (120 credits, 15 usual,
# 16 maximum, upper-level from semester 5):
#   s1 calc1 4, engl1 3, bio1 4, chem1 4 (lecture/lab bundle)    = 15
#   s2 engl2 3, bio2 4, chem2 4 (bundle), phys1 4 (after calc1)  = 15
#   s3 genetics 3 (after bio2 and chem1), biosci 4 (choice)      =  7
#   s5 molecular 4, evolution 4, physiology 3 (evolution before or with it) = 11
#   s7 bioelective 3 (choice); s8 biocap 3 (after molecular)
#   Shown 54; other degree work 66 fills every semester to 15.
#   Allowance cards: s3 3 + 3 + 2; s4 five 3s; s5 one 4; s6 five 3s; s7 and s8
#   four 3s each. With no Gen Ed band, math (row 1) and writing (row 2) come
#   first, electives fill rows 3–7, and the program's families begin at row 8.
#   molecular's ancestors: genetics, chem2 (2), bio2, chem1 (2), bio1 = 7 courses,
#   chem1 counted once although both genetics and chem2 lead from it.
#   physiology: prereq_depth 2, not 3 — a concurrent link adds no semester.
# History B.A., algebra-ready (statistics), Composition I:
#   math1350 s1 (a suggested Gen Ed course), hist1 s1, hist2 s2,
#   histmethods/histupper1/histupper2 s5, histupper3/histupper4/histchoice s6,
#   historiography s7 (2 of the histupper pool, plus permission), histsenior s8.
catalog <- function() test_degree_catalog
roadmaps <- function() test_degree_roadmaps
BIOLOGY <- "demo-biology-bs-2026"
HISTORY <- "demo-history-ba-2026"
plan <- function(id = BIOLOGY, math = "calculus", english = "composition", r = roadmaps()) {
  build_degree_roadmap(catalog(), r, id, math, english)
}
view_of <- function(id = BIOLOGY, math = "calculus", english = "composition", season = "fall", r = roadmaps()) {
  build_degree_roadmap_view(catalog(), r, id, math, english, season)
}
at <- function(view, id, field = "semester") view$nodes[[field]][match(id, view$nodes$node_id)]

# EC-11 and EC-11b supply the raw section and class-list rows for popup history.
history_edges <- list(last_enrolled_complete = 202080L, last_enrolled = 202180L)
planning_gen_ed <- function() data.frame(subject_course = c("SOCI 100", "SOCI 101", "SOCI 104"),
  area_label = c("4: Social sciences", "4: Social sciences", "5: Humanities"))

# ── Catalog rule trees ───────────────────────────────────────────────────────

test_that("catalog trees preserve alternatives, bundles, timing and unresolved source rules", {
  expect_equal(validate_degree_catalog(catalog()), catalog())
  rules <- degree_rule_outline(catalog(), catalog()$catalogs$catalog_id)
  intermediate <- rules[rules$rule_id == "bio-intermediate", ]
  bundle <- rules[rules$rule_id == "bio-microbiology", ]
  expect_equal(intermediate$operator, "choose_n")
  expect_equal(intermediate$minimum, "2")
  expect_match(intermediate$text, "Choose at least 2 options", fixed = TRUE)
  expect_equal(bundle$parent_id, intermediate$rule_id)
  expect_equal(bundle$depth, 1L)
  expect_equal(rules$depth[rules$rule_id == "bio-micro-lab"], 2L)
  # Children follow their parent, whatever the file order.
  expect_equal(match("bio-micro-lab", rules$rule_id), match("bio-microbiology", rules$rule_id) + 2L)
  expect_true(any(rules$operator == "concurrent"))
  expect_match(rules$text[rules$rule_id == "bio-physiology-req"],
    "BIOL 304C — Evolution (4 credits) [for BIOL 3200]: Complete before or take concurrently", fixed = TRUE)
  expect_match(rules$text[rules$rule_id == "bio-total"], "[SOURCE CONFLICT]", fixed = TRUE)
  bad <- catalog(); bad$rules$parent_id[1] <- bad$rules$rule_id[1]
  expect_error(validate_degree_catalog(bad), "Cycle")
  bad <- catalog(); bad$rules$minimum[bad$rules$rule_id == "bio-intermediate"] <- "4"
  expect_error(validate_degree_catalog(bad), "Invalid choice group")
  bad <- catalog(); bad$courses$rule_id[1] <- "missing"
  expect_error(validate_degree_catalog(bad), "unknown rule")
  bad <- catalog(); bad$evidence$catalog_year[1] <- "2025-2026"
  expect_error(validate_degree_catalog(bad), "evidence year")
})

# Banner gives a field's B.A. and B.S. separate program codes (BA-PSY-AS,
# BS-PSY-AS) under one program name, so a degree map claims its own codes.
# The demo has no pre-major for History; FHIS below is built here, named after
# its own code as UNM's FFDA is, to show that leads_to is what connects it.
test_that("each degree claims its own Banner program codes, keeping a B.A. apart from a B.S.", {
  programs <- read_institution_file("programs", cedar_institution_dir(cedar_base_dir, "demo"))
  codes <- catalog()$program_codes
  expect_equal(codes$catalog_id, c(BIOLOGY, HISTORY))
  expect_equal(codes$program_code, c("BS-BIOL-AS", "BA-HIST-AS"))
  expect_equal(codes$major_code, c("BIOL", "HIST"))
  is_id <- function(cats, id) cats$catalog_id == id
  bad <- catalog(); bad$catalogs$program_codes[is_id(bad$catalogs, BIOLOGY)] <- "BA-BIOL-AS"
  expect_error(validate_degree_catalog(bad), "belong to the catalog's degree: demo-biology-bs-2026")
  bad <- catalog(); bad$catalogs$program_codes[is_id(bad$catalogs, BIOLOGY)] <- "BS-BIOL"
  expect_error(validate_degree_catalog(bad), "belong to the catalog's degree")
  bad <- catalog(); bad$catalogs$program_codes[is_id(bad$catalogs, BIOLOGY)] <- ""
  expect_error(validate_degree_catalog(bad), "belong to the catalog's degree")
  bad <- catalog(); bad$catalogs$degree_code[is_id(bad$catalogs, HISTORY)] <- "BS"
  bad$catalogs$program_codes[is_id(bad$catalogs, HISTORY)] <- "BS-BIOL-AS"
  expect_error(validate_degree_catalog(bad), "belongs to one catalog")

  cats <- catalog()$catalogs
  cats$program_codes[is_id(cats, HISTORY)] <- "BA-BIOL-AS"
  expect_error(degree_catalog_program_codes(cats, programs), "not the catalog's program: BA-BIOL-AS")
  cats$program_codes[is_id(cats, HISTORY)] <- "BA-HIST-AS|BA-FHIS-AS"
  expect_error(degree_catalog_program_codes(cats, programs), "not the catalog's program: BA-FHIS-AS")
  pre <- rbind(programs, transform(programs[programs$program_code == "HIST", ],
    program_code = "FHIS", program_name = "FHIS", is_pre_major = "TRUE", leads_to = "HIST"))
  out <- degree_catalog_program_codes(cats, pre)
  expect_equal(out$is_pre_major[out$catalog_id == HISTORY], c(FALSE, TRUE))
  expect_match(degree_program_codes_note(list(program_codes = out), HISTORY),
    "Banner program codes for this degree: BA-HIST-AS; pre-major BA-FHIS-AS.", fixed = TRUE)
  expect_match(view_of(HISTORY)$program_codes_note, "for this degree: BA-HIST-AS. Another degree", fixed = TRUE)
  rules <- build_degree_plan_rules(catalog(), roadmaps(), view_of(HISTORY))$rows
  expect_equal(rules$rule[rules$kind == "Banner program codes"], view_of(HISTORY)$program_codes_note)
  pre$leads_to[pre$program_code == "FHIS"] <- "BIOL"
  expect_error(degree_catalog_program_codes(cats, pre), "not the catalog's program: BA-FHIS-AS")
})

# ── Scheduling ───────────────────────────────────────────────────────────────

test_that("readable plan rules expose the active graph and distinguish policy from scheduling", {
  v <- view_of(HISTORY)
  rules <- build_degree_plan_rules(catalog(), roadmaps(), v)
  expect_match(rules$scenario, "Math: Calculus-ready: take statistics", fixed = TRUE)
  rows <- rules$rows
  expect_equal(sum(rows$kind == "Prerequisite arrow"), nrow(v$links))
  expect_equal(sum(rows$kind == "Other enrollment condition"), nrow(v$conditions))
  expect_true(any(grepl("2+ upper-level", rows$rule, fixed = TRUE)))
  # Aggregate conditions must not turn the entire qualifying pool into arrows.
  arrows <- rows[rows$kind == "Prerequisite arrow", ]
  expect_false(any(startsWith(arrows$node_ids, "histupper")))
  expect_true(all(nzchar(arrows$source_url) & nzchar(arrows$quote)))
  preference <- rows[rows$kind == "Planning preference", ]
  expect_true(any(grepl("15 credits; never more than 16", preference$rule, fixed = TRUE)))
  expect_true(all(preference$source_url == "" & preference$quote == ""))
  expect_true(any(rows$kind == "Suggested general coursework" & grepl("MATH 1350", rows$rule, fixed = TRUE)))
  expect_true(all(grepl("not evaluated", rows$effect[rows$kind == "Recorded catalog requirement"], fixed = TRUE)))
  prepared <- build_degree_plan_rules(catalog(), roadmaps(), view_of(HISTORY, "intermediate"))$rows
  expect_true(any(prepared$kind == "Preparation" & grepl("MATH 1215", prepared$rule, fixed = TRUE)))
  expect_false(any(rows$kind == "Preparation" & grepl("MATH 1215", rows$rule, fixed = TRUE)))
  expect_setequal(setdiff(unique(unlist(strsplit(paste(rows$node_ids, collapse = "|"), "|", fixed = TRUE))), ""), c(v$nodes$node_id, v$allowances$node_id))
})

test_that("required blocks count actual component courses rather than assuming a two-course pair", {
  nodes <- data.frame(node_id = c("clinical", "advanced"), kind = c("cohort", "major"),
    bundle = c(TRUE, FALSE), component_count = c(5L, 1L))
  links <- data.frame(from = "clinical", to = "advanced", timing = "before")
  metrics <- get_degree_chain_metrics(nodes, links)
  expect_equal(metrics$n_prerequisites[metrics$node_id == "advanced"], 5L)
  expect_equal(metrics$n_direct[metrics$node_id == "advanced"], 5L)
  expect_equal(metrics$prereq_depth[metrics$node_id == "advanced"], 1L)
  expect_equal(metrics$n_downstream[metrics$node_id == "clinical"], 1L)
})

test_that("the calculus-ready biology plan matches its hand-worked schedule", {
  v <- plan()
  expect_equal(at(v, c("calc1", "engl1", "bio1", "chem1")), rep(1L, 4))
  expect_equal(at(v, c("engl2", "bio2", "chem2", "phys1")), rep(2L, 4))
  expect_equal(at(v, c("genetics", "biosci")), c(3L, 3L))
  expect_equal(at(v, c("molecular", "evolution", "physiology")), rep(5L, 3))
  expect_equal(at(v, c("bioelective", "biocap")), c(7L, 8L))
  expect_equal(v$terms$known_credits, c(15, 15, 7, 0, 11, 0, 3, 3))
  expect_equal(v$terms$other_credits, c(0, 0, 8, 15, 4, 15, 12, 12))
  expect_equal(v$terms$planned_credits, rep(15, 8))
  expect_equal(v$terms$other_phase, rep(c("foundation", "advanced"), each = 4))
  expect_equal(v$preparation_credits, 0)
  expect_equal(v$n_moved, 0L)
  expect_equal(v$math_target$code, "MATH 1512")
  expect_error(build_degree_roadmap(catalog(), roadmaps(), catalog()$catalogs$catalog_id, "calculus", "composition"),
    "one known degree")
  expect_error(plan(math = "unknown"), "known math")
})

test_that("math preparation adds its sequence and moves only the courses that depend on it", {
  ready <- plan()
  prepared <- plan(math = "intermediate")
  expect_equal(at(prepared, c("math1215", "math1220", "math1250", "calc1")), 1:4)
  # Physics follows Calculus I out of semester 2; nothing else moves.
  expect_equal(at(prepared, "phys1"), 5L)
  expect_true(at(prepared, "phys1", "moved"))
  expect_equal(prepared$n_moved, 1L)
  unrelated <- c("bio1", "chem1", "genetics", "molecular", "biocap")
  expect_equal(at(prepared, unrelated), at(ready, unrelated))
  expect_equal(prepared$n_preparation, 3L)
  expect_equal(prepared$preparation_credits, 9)
  # 129 planned credits cannot fit eight semesters at 16; the plan grows a ninth.
  expect_equal(nrow(prepared$terms), 9L)
  expect_equal(prepared$terms$planned_credits, c(rep(15, 8), 9))
  expect_false("math1215" %in% ready$nodes$node_id)
})

test_that("English starting points replace the sequence and completed credit leaves the target", {
  stretch <- plan(english = "stretch")
  expect_equal(stretch$nodes$code[stretch$nodes$track == "english"], c("ENGL 1110X", "ENGL 1110Y", "ENGL 1120"))
  expect_equal(at(stretch, c("englX", "englY", "engl2")), 1:3)
  # Stretch I is preparation: 123 credits over eight semesters uses the 16-credit maximum.
  expect_equal(stretch$preparation_credits, 3)
  expect_equal(stretch$terms$planned_credits, c(16, 16, 16, 15, 15, 15, 15, 15))
  advanced <- plan(english = "composition2")
  expect_equal(advanced$nodes$code[advanced$nodes$track == "english"], "ENGL 1120")
  expect_equal(at(advanced, "engl2"), 1L)
  complete <- plan(english = "complete")
  expect_false(any(complete$nodes$track == "english"))
  expect_equal(complete$completed_credits, 6)
  expect_equal(sum(complete$terms$planned_credits), 114)
})

test_that("lecture/lab bundles stay together and count as two courses", {
  v <- plan()
  expect_equal(sum(v$nodes$bundle), 2L)
  expect_equal(at(v, c("chem1", "chem2"), "credits"), c(4, 4))
  expect_equal(at(v, "chem2", "n_prerequisites"), 2L)
  # Genetics' direct prerequisites: Biology II plus the chemistry bundle.
  expect_equal(at(v, "genetics", "n_direct"), 3L)
})

test_that("planning burden counts unique ancestors and keeps chain length separate", {
  v <- plan()
  expect_equal(at(v, "molecular", "n_prerequisites"), 7L)
  expect_equal(at(v, "molecular", "prereq_depth"), 3L)
  expect_setequal(strsplit(at(v, "molecular", "upstream_ids"), "|", fixed = TRUE)[[1]],
    c("genetics", "chem2", "bio2", "chem1", "bio1"))
  expect_equal(at(v, "biocap", "n_prerequisites"), 8L)
  expect_equal(at(v, "physiology", "prereq_depth"), 2L)
  expect_equal(at(v, "physiology", "n_prerequisites"), 3L)
  expect_equal(at(v, "bio1", "n_downstream"), 6L)
  expect_equal(at(v, "bio1", "chain_terms"), 5L)
  expect_setequal(strsplit(at(v, "chem1", "downstream_ids"), "|", fixed = TRUE)[[1]],
    c("chem2", "genetics", "molecular", "biocap"))
  expect_equal(at(v, "chem1", "n_downstream"), 5L)
  expect_equal(at(v, c("bio1", "bio2", "genetics", "evolution", "molecular", "biosci"), "planning_level"),
    c("green", "yellow", "red", "yellow", "red", "unresolved"))
  # Concurrent timing may share a semester; a "before" link may not.
  links <- v$links
  expect_true(all(at(v, links$to) >= at(v, links$from) + as.integer(links$timing == "before")))
  expect_equal(at(v, "physiology"), at(v, "evolution"))
})

# Authored timing perturbation: a delayed course pushes its dependants past semester 8.
test_that("the semester board extends rather than dropping delayed courses", {
  r <- roadmaps()
  r$nodes$semester[r$nodes$catalog_id == BIOLOGY & r$nodes$node_id == "molecular"] <- "8"
  v <- plan(r = r)
  expect_equal(at(v, c("molecular", "biocap")), c(8L, 9L))
  expect_equal(tail(v$terms$semester, 1), 9L)
  expect_equal(nrow(v$nodes), 15L)
  expect_match(format_degree_explorer_preview(view_of(r = r)), "Semester 9", fixed = TRUE)
})

test_that("upper-level courses wait for the institution's later planning stage", {
  v <- plan()
  expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= 5L))
  r <- roadmaps()
  r$plans$upper_level_from_semester[r$plans$catalog_id == BIOLOGY] <- "7"
  late <- view_of(r = r)
  expect_equal(at(late, c("molecular", "evolution", "physiology", "bioelective", "biocap")), c(7L, 7L, 7L, 7L, 8L))
  expect_true(all(late$terms$other_label[late$terms$semester < 7L] == "Gen Ed where identified; other elective / minor credits"))
  expect_true(all(late$terms$other_label[late$terms$semester >= 7L] == "Elective / minor · upper level may count"))
  expect_match(late$timing_note, "semester 7", fixed = TRUE)
  expect_true(all(late$terms$planned_credits <= 16))
})

# ── Layout ───────────────────────────────────────────────────────────────────

test_that("course families align after scheduling and parallel courses take separate rows", {
  v <- plan()
  expect_equal(at(v, c("calc1", "engl1", "engl2"), "row"), c(1L, 2L, 2L))
  expect_equal(at(v, c("bio1", "bio2", "genetics", "molecular"), "row"), rep(8L, 4))
  # Evolution and Physiology share Molecular Biology's semester and family.
  expect_equal(at(v, c("evolution", "physiology"), "row"), c(9L, 10L))
  # Other families reuse a row outside each other's span.
  expect_equal(at(v, c("biocap", "bioelective"), "row"), c(8L, 8L))
  expect_equal(at(v, c("chem1", "chem2", "biosci", "phys1"), "row"), c(9L, 9L, 9L, 10L))
  expect_false(anyDuplicated(paste(v$nodes$semester, v$nodes$row)) > 0L)
  # Layout metadata cannot change credit budgets, course timing or graph metrics.
  r <- roadmaps()
  r$nodes$row_group <- "one_family"
  alternate <- plan(r = r)
  fields <- c("node_id", "semester", "credits", "n_prerequisites", "n_downstream")
  expect_equal(v$nodes[fields], alternate$nodes[fields])
  expect_equal(v$terms, alternate$terms)
  r$nodes$row_group[1] <- ""
  expect_error(validate_degree_roadmaps(r, catalog()), "row group")
})

test_that("allowance cards fill every semester between math/writing and the program's courses", {
  v <- view_of()
  expect_identical(v$nodes$row, plan()$nodes$row)
  expect_equal(v$allowances$semester, rep(3:8, c(3, 5, 1, 5, 4, 4)))
  expect_equal(v$allowances$credits, c(3, 3, 2, rep(3, 5), 4, rep(3, 13)))
  expect_equal(v$allowances$row, c(3:5, 3:7, 3L, 3:7, 3:6, 3:6))
  foundation <- v$nodes$row_group %in% c("math", "writing")
  expect_lt(max(v$nodes$row[foundation]), min(v$allowances$row))
  expect_lt(max(v$allowances$row), min(v$nodes$row[!foundation]))
  expect_equal(v$allowances$title[3], "Credits left to allocate")
  expect_equal(unique(v$allowances$title[v$allowances$semester >= 5L]), "Any level · upper level may count")
  expect_equal(v$n_rows, 10L)
  # Later semesters have cards too: no credit is left to a footer.
  for (s in v$terms$semester) {
    expect_equal(sum(v$allowances$credits[v$allowances$semester == s]), v$terms$other_credits[v$terms$semester == s])
  }
  expect_false(anyDuplicated(c(paste(v$nodes$semester, v$nodes$row),
    paste(v$allowances$semester, v$allowances$row))) > 0L)
  spring <- view_of(season = "spring")
  expect_equal(v$terms$season[1:4], c("fall", "spring", "fall", "spring"))
  expect_equal(spring$terms$season[1:4], c("spring", "fall", "spring", "fall"))
  expect_identical(v$allowances[c("node_id", "semester", "credits", "row")],
    spring$allowances[c("node_id", "semester", "credits", "row")])
  expect_error(degree_semester_seasons(1:8, "summer"), "fall or spring")
  r <- roadmaps()
  r$plans$degree_credit_target[r$plans$catalog_id == BIOLOGY] <- "54"
  no_allowances <- view_of(r = r)
  expect_equal(nrow(no_allowances$allowances), 0L)
  expect_equal(min(no_allowances$nodes$row), 1L)
})

# ── Programs: routes, conditions, choices and citations ──────────────────────

test_that("a statistics major takes its own math route and never inherits calculus", {
  h <- plan(HISTORY, "intermediate")
  expect_equal(h$nodes$code[h$nodes$track == "math"], c("MATH 1215", "MATH 1350"))
  expect_equal(at(h, c("math1215", "math1350")), 1:2)
  expect_equal(h$preparation_credits, 3)
  expect_false(any(c("calc1", "math1220", "math1250") %in% h$nodes$node_id))
  ready <- plan(HISTORY, "algebra")
  expect_equal(ready$math_target$code, "MATH 1350")
  expect_equal(ready$math_target$semester, 1L)
  expect_equal(ready$n_preparation, 0L)
  expect_setequal(unname(degree_math_start_choices(roadmaps(), HISTORY)),
    roadmaps()$starts$start_id[roadmaps()$starts$track == "math"])
  bad <- roadmaps(); bad$math_routes <- bad$math_routes[-1, ]
  expect_error(validate_degree_roadmaps(bad, catalog()), "math starting routes missing")
  bad <- roadmaps(); bad$math_routes$node_ids[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "math route course")
  bad <- roadmaps(); bad$math_routes$node_ids[bad$math_routes$catalog_id == HISTORY] <- "calc1"
  expect_error(validate_degree_roadmaps(bad, catalog()), "requirement evidence")
})

test_that("a course-count condition stays separate from named prerequisites", {
  h <- view_of(HISTORY, "algebra")
  expect_equal(at(h, c("histmethods", "histupper1", "histupper2")), rep(5L, 3))
  expect_equal(at(h, c("histupper3", "histupper4", "histchoice")), rep(6L, 3))
  expect_equal(at(h, c("historiography", "histsenior")), c(7L, 8L))
  expect_false(any(h$links$to == "historiography"))
  target <- h$nodes[h$nodes$node_id == "historiography", ]
  expect_equal(target$n_prerequisites, 0L)
  expect_equal(target$n_conditions, 2L)
  expect_equal(target$planning_level, "conditional")
  expect_equal(target$condition_label, "2+ upper-level History courses · Department permission")
  expect_equal(target$prerequisite_label, "Prior coursework / permission")
  expect_equal(target$chain_badge, "◇ Enrollment conditions")
  expect_match(target$planning_note, "0 named prerequisite courses", fixed = TRUE)
  expect_setequal(strsplit(target$qualifying_ids, "|", fixed = TRUE)[[1]], paste0("histupper", 1:4))
  expect_true(all(grepl("/courses/", h$conditions$source_url, fixed = TRUE)))
  expect_equal(at(h, "histsenior", "planning_level"), "yellow")
})

# Authored timing perturbation: the condition waits for the second qualifying
# pool completion, not for every member and not for two particular electives.
test_that("course-count conditions schedule against the earliest qualifying pool completions", {
  r <- roadmaps()
  history <- r$nodes$catalog_id == HISTORY
  r$nodes$semester[history & r$nodes$node_id %in% paste0("histupper", 1:3)] <- "8"
  r$nodes$semester[history & r$nodes$node_id == "histupper4"] <- "5"
  r$nodes$semester[history & r$nodes$node_id == "historiography"] <- "1"
  v <- plan(HISTORY, "algebra", r = r)
  expect_equal(at(v, "historiography"), 9L)
  bad <- roadmaps(); bad$conditions$minimum[1] <- "5"
  expect_error(validate_degree_roadmaps(bad, catalog()), "course-count condition")
  bad <- roadmaps(); bad$conditions$evidence_id[1] <- "total-hist"
  expect_error(validate_degree_roadmaps(bad, catalog()), "Condition needs matching course evidence")
})

test_that("Gen Ed suggestions are labelled while named requirements keep program styling", {
  h <- view_of(HISTORY, "algebra")
  b <- view_of()
  suggestion <- h$nodes[h$nodes$node_id == "math1350", ]
  expect_true(suggestion$is_suggested)
  expect_equal(suggestion$basis, "general")
  expect_equal(suggestion$kind_label, "Suggested Gen Ed")
  calculus <- b$nodes[b$nodes$node_id == "calc1", ]
  expect_false(calculus$is_suggested)
  expect_equal(calculus$basis, "degree")
})

test_that("named course sets expose every alternative without one option's prerequisites", {
  h <- view_of(HISTORY, "algebra")
  world <- h$nodes[h$nodes$node_id == "histchoice", ]
  expect_equal(world$option_label, "Choose 1 of 4 courses")
  expect_equal(world$option_codes, "HIST 1160, HIST 327, HIST 395, HIST 401")
  expect_equal(world$planning_level, "unresolved")
  expect_equal(world$kind_label, "Course choice · Level varies")
  expect_equal(nrow(h$options), 4L)
  expect_equal(h$options$credit_label[h$options$subject_course == "HIST 401"], "3–4")
  expect_equal(h$options$prerequisite_note[h$options$subject_course == "HIST 401"], "HIST 300 - Historical Methods (3)")
  expect_equal(h$options$prerequisite_note[h$options$subject_course == "HIST 327"], "")
  bad <- roadmaps(); bad$options <- rbind(bad$options, bad$options[1, ])
  expect_error(validate_degree_roadmaps(bad, catalog()), "option course")
  bad <- roadmaps(); bad$options$minimum[bad$options$node_id == "histchoice"] <- "5"
  expect_error(validate_degree_roadmaps(bad, catalog()), "option set")
  bad <- roadmaps(); bad$options$evidence_id[bad$options$node_id == "histchoice"][1] <- "total-hist"
  expect_error(validate_degree_roadmaps(bad, catalog()), "program requirement evidence")
  bad <- roadmaps(); bad$options$source_url[bad$options$subject_course == "HIST 401"] <- catalog()$catalogs$source_url[2]
  expect_error(validate_degree_roadmaps(bad, catalog()), "matching course evidence")
  # A named edge into a set would misstate every alternative.
  bad <- roadmaps(); edge <- bad$links[bad$links$catalog_id == HISTORY, ][1, ]
  edge$from <- "histmethods"; edge$to <- "histchoice"
  bad$links <- rbind(bad$links, edge)
  expect_error(validate_degree_roadmaps(bad, catalog()), "inherit a particular course")
})

test_that("lecture/lab alternatives count complete options and keep the slot's credits", {
  v <- view_of()
  science <- v$nodes[v$nodes$node_id == "biosci", ]
  expect_equal(science$option_label, "Choose 1 of 3 options")
  expect_equal(science$option_codes, "PHYS 1230 + PHYS 1230L, GEOL 1110 + GEOL 1110L, ENVS 1110C")
  groups <- v$option_groups[v$option_groups$node_id == "biosci", ]
  expect_equal(groups$component_count, c(2L, 2L, 1L))
  expect_true(all(groups$credits_min == 4 & groups$credits_max == 4))
  expect_false(any(v$links$from == "biosci" | v$links$to == "biosci"))
  # Counting rows as alternatives would let a one-credit lab fill the slot.
  bad <- roadmaps(); bad$nodes$credits[bad$nodes$catalog_id == BIOLOGY & bad$nodes$node_id == "biosci"] <- "3"
  expect_error(validate_degree_roadmaps(bad, catalog()), "option set or planning credits")
})

test_that("each tile cites its own requirement, and preparation cites the course it unlocks", {
  v <- plan(math = "intermediate")
  molecular <- v$nodes[v$nodes$node_id == "molecular", ]
  expect_equal(molecular$evidence_section, "Requirements → Biology core")
  expect_match(molecular$evidence_quote, "BIOL300C", fixed = TRUE)
  expect_equal(molecular$evidence_source_url, v$catalog$source_url)
  preparation <- v$nodes[v$nodes$node_id == "math1215", ]
  expect_equal(preparation$basis, "prerequisite")
  expect_match(preparation$evidence_source_url, "MATH-1220", fixed = TRUE)
  expect_false(preparation$source_url == preparation$evidence_source_url)
  expect_true(all(v$nodes$evidence_catalog_year == "2026-2027"))
  bad <- roadmaps(); bad$basis$evidence_id[bad$basis$catalog_id == BIOLOGY & bad$basis$node_id == "molecular"] <- "req-bio1-bio2"
  expect_error(validate_degree_roadmaps(bad, catalog()), "program page")
  bad <- roadmaps(); bad$basis$node_id[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "requirement evidence")
  bad <- roadmaps(); bad$links$evidence_id[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "Unknown roadmap evidence")
  bad <- roadmaps(); bad$links$from[1] <- "missing"
  expect_error(validate_degree_roadmaps(bad, catalog()), "endpoint")
  bad <- roadmaps(); bad$links$to[1] <- bad$links$from[1]
  expect_error(validate_degree_roadmaps(bad, catalog()), "Cycle")
})

test_that("authored course levels agree with institution numbering bands", {
  r <- roadmaps()
  r$nodes$course_level[r$nodes$node_id == "molecular"] <- "lower"
  expect_error(validate_degree_roadmaps(r, catalog()), "level disagrees")
  r <- roadmaps(); r$nodes$course_level[r$nodes$kind == "choice"] <- ""
  expect_error(validate_degree_roadmaps(r, catalog()), "Invalid roadmap course level")
  r <- roadmaps(); r$plans$upper_level_from_semester <- "1"
  expect_error(validate_degree_roadmaps(r, catalog()), "early-coursework stage")
  r <- roadmaps(); r$courses$subject_course[r$courses$node_id == "phys1"] <- "PHYS 1320"
  expect_error(validate_degree_roadmaps(r, catalog()), "components disagree")
})

# ── The loaded institution's own catalog ─────────────────────────────────────

# Integrity of whichever institution is loaded (UNM by default): its authored
# files, not the planner, are under test. A demo or empty catalog passes trivially.
test_that("the loaded institution's roadmaps keep every planning rule in every starting scenario", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  for (id in c$catalogs$catalog_id) {
    max_load <- as.numeric(r$plans$max_load[r$plans$catalog_id == id])
    upper_start <- as.integer(r$plans$upper_level_from_semester[r$plans$catalog_id == id])
    for (math in r$starts$start_id[r$starts$track == "math"]) {
      for (english in r$starts$start_id[r$starts$track == "english"]) {
        v <- build_degree_roadmap(c, r, id, math, english)
        expect_true(all(v$terms$planned_credits <= max_load))
        expect_equal(v$terms$planned_credits, v$terms$known_credits + v$terms$other_credits)
        expect_equal(sum(v$terms$planned_credits), v$degree_credits - v$completed_credits + v$preparation_credits)
        expect_true(all(v$nodes$semester[v$nodes$course_level == "upper"] >= upper_start))
        expect_true(all(v$nodes$semester[match(v$links$to, v$nodes$node_id)] >=
          v$nodes$semester[match(v$links$from, v$nodes$node_id)] + as.integer(v$links$timing == "before")))
        expect_false(anyDuplicated(paste(v$nodes$semester, v$nodes$row)) > 0L)
        expect_lte(length(unique(v$nodes$row[v$nodes$row_group == "writing"])), 1L)
        foundation <- v$nodes$row_group %in% c("math", "writing")
        expect_lt(max(c(0L, v$nodes$row[foundation])), min(c(Inf, v$allowances$row)))
        expect_lt(max(c(0L, v$allowances$row)), min(c(Inf, v$nodes$row[!foundation])))
        expect_equal(sum(v$allowances$credits), sum(v$terms$other_credits))
        expect_false(anyDuplicated(c(paste(v$nodes$semester, v$nodes$row),
          paste(v$allowances$semester, v$allowances$row))) > 0L)
      }
    }
  }
  expect_setequal(unique(c$program_codes$catalog_id), c$catalogs$catalog_id)
})

# ── Popup history ────────────────────────────────────────────────────────────

test_that("history components are explicit, and unenumerated groups and new codes stay unresolved", {
  r <- roadmaps()
  expect_setequal(r$courses$subject_course[r$courses$node_id == "chem1"], c("CHEM 1215", "CHEM 1215L"))
  group <- build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "bioelective")
  expect_equal(group$state, "choice")
  # None of the physical-science options has a section in the window.
  science <- build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "biosci")
  expect_equal(science$state, "empty")
  expect_setequal(science$missing_courses, r$options$subject_course[r$options$node_id == "biosci"])
  world <- build_degree_course_history(test_sections, test_students, history_edges, r, HISTORY, "histchoice")
  expect_equal(world$state, "ready")
  expect_match(world$note, "alternatives", fixed = TRUE)
  expect_setequal(unique(world$table$subject_course), c("HIST 327", "HIST 395"))
  expect_setequal(world$missing_courses, c("HIST 1160", "HIST 401"))
  course <- build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "phys1")
  expect_equal(course$state, "empty")
  expect_equal(course$missing_courses, "PHYS 1310")
  expect_error(build_degree_course_history(test_sections, test_students, history_edges, r, BIOLOGY, "nope"),
    "Unknown degree course selection")
})

# Authored components redirect a tile to EC-11's raw rows; no institutional
# records are invented here.
test_that("a course popup keeps every campus, bundle component and alternative at its own grain", {
  r <- roadmaps()
  r$courses$subject_course[r$courses$node_id == "calc1"] <- "SOCI 100"
  h <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, BIOLOGY, "calc1")
  expect_setequal(h$table$campus, c("ABQ", "EA"))
  expect_true(is.numeric(h$table$capacity) && is.numeric(h$table$first_day_enrl))
  # Lecture and lab may have different campus histories; never cross their sets.
  r$courses$subject_course[r$courses$node_id == "chem1"] <- c("SOCI 100", "SOCI 101")
  bundle <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, BIOLOGY, "chem1")
  expect_equal(nrow(distinct(bundle$table, subject_course, campus)), 3L)
  r$options$subject_course[r$options$node_id == "histchoice"][1:3] <- c("SOCI 100", "SOCI 101", "SOCI 104")
  set <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, HISTORY, "histchoice")
  expect_setequal(unique(set$table$subject_course), c("SOCI 100", "SOCI 101", "SOCI 104"))
  full <- set$table[set$table$subject_course == "SOCI 100" & set$table$campus == "ABQ" &
    set$table$part_term == "1" & set$table$term == 202080L, ]
  expect_equal(full$capacity, 100)
  expect_equal(full$first_day_enrl, 107)
  expect_false(anyDuplicated(set$table[c("term", "subject_course", "campus", "college", "part_term")]) > 0L)
})

test_that("allowance popups disclose credit fit and exclude courses the plan already shows", {
  v <- view_of()
  remainder <- v$allowances$node_id[v$allowances$credits == 2]
  selection <- list(type = "allowance", catalog_id = BIOLOGY, math_start = "calculus",
    english_start = "composition", start_season = "fall", node_id = remainder)
  membership <- rbind(planning_gen_ed(), data.frame(subject_course = c("MATH 1512", "ENGL 1120"),
    area_label = c("2: Math", "1: Communication")))
  h <- build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    catalog(), roadmaps(), membership, selection)
  expect_equal(h$kind, "allowance")
  expect_equal(h$season, "fall")
  expect_equal(h$credits, 2)
  expect_true(all(h$table$credit_fit == "Needs more credits"))
  expect_false(any(c("MATH 1512", "ENGL 1120") %in% h$missing_courses))
  expect_match(h$credit_note, "rather than a complete course", fixed = TRUE)
  expect_match(format_degree_allowance_preview(h), "SOCI 100 · ABQ", fixed = TRUE)
  expect_false(any(c("student_id", "crn") %in% names(h$table)))
  selection$node_id <- "allowance-99-1"
  expect_error(build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    catalog(), roadmaps(), membership, selection), "Unknown degree allowance")
})

# ── Rendering ────────────────────────────────────────────────────────────────

test_that("the board and popups render the payload; catalog evidence lives in the server modal", {
  withr::local_package("shiny")
  withr::local_package("bslib")
  load_funcs(cedar_base_dir, modules = TRUE)
  ui <- as.character(degreeExplorerUI("degree_explorer", catalog(), roadmaps()))
  expect_match(ui, "degree_explorer-dx_math_start", fixed = TRUE)
  expect_match(ui, "degree_explorer-dx_copy_url", fixed = TRUE)
  v <- view_of(math = "intermediate", english = "stretch")
  board <- as.character(degree_semester_board(v, "board"))
  expect_match(board, "data-roadmap", fixed = TRUE)
  expect_match(board, "Semester 9", fixed = TRUE)
  expect_match(board, "CHEM 1215 + 1215L", fixed = TRUE)
  expect_match(board, "↔ Paired", fixed = TRUE)
  expect_match(board, "3+ prerequisite courses", fixed = TRUE)
  expect_match(board, 'data-card-type="allowance"', fixed = TRUE)
  expect_match(board, "Browse Fall courses", fixed = TRUE)
  expect_match(board, "window.CedarRoadmap.initialize", fixed = TRUE)
  # The browser receives each chain from R and never sees catalog evidence.
  expect_match(board, '"upstream_ids"', fixed = TRUE)
  expect_false(grepl("evidence_quote", board, fixed = TRUE))
  popup <- as.character(degree_tile_modal(degree_roadmap_tile_detail(v, "molecular"), "history"))
  expect_match(popup, "cedar-roadmap-evidence-quote", fixed = TRUE)
  expect_match(popup, "Degree requirements ↗", fixed = TRUE)
  expect_match(popup, "modal-dialog-scrollable", fixed = TRUE)
  allowance <- as.character(degree_tile_modal(degree_roadmap_tile_detail(v, v$allowances$node_id[1]), "history"))
  expect_false(grepl("cedar-roadmap-detail\"", allowance, fixed = TRUE))
  expect_match(allowance, "Degree credit requirements ↗", fixed = TRUE)
  science <- as.character(degree_tile_modal(degree_roadmap_tile_detail(v, "biosci"), "history"))
  expect_equal(lengths(regmatches(science, gregexpr("<li data-option=", science, fixed = TRUE))), 3L)
  expect_match(science, "PHYS 1230 + PHYS 1230L · 4 credits together", fixed = TRUE)
  h <- view_of(HISTORY, "algebra")
  condition <- as.character(degree_tile_modal(degree_roadmap_tile_detail(h, "historiography"), "history"))
  expect_match(condition, "◇ Department permission", fixed = TRUE)
  expect_error(degree_roadmap_tile_detail(h, "nope"), "Unknown degree roadmap tile")
  expect_match(as.character(observedCoursePathsUI("paths", cedar_campus_choices(test_students))),
    "paths-button", fixed = TRUE)
})

test_that("popup history renders one standard table with first-day seats", {
  withr::local_package("shiny")
  r <- roadmaps()
  r$courses$subject_course[r$courses$node_id == "calc1"] <- "SOCI 100"
  h <- build_degree_course_history(test_sections_regstats, test_students_regstats, history_edges, r, BIOLOGY, "calc1")
  html <- as.character(degree_course_history_ui(h, "history_table"))
  expect_match(html, "filled at first class day", fixed = TRUE)
  expect_match(html, "history_table", fixed = TRUE)
  expect_match(html, "Near full", fixed = TRUE)
  expect_match(html, 'data-history-node="calc1"', fixed = TRUE)
  expect_match(html, "cedar-section-heading", fixed = TRUE)
  expect_s3_class(degree_history_table(h), "reactable")
  v <- view_of()
  selection <- list(type = "allowance", catalog_id = BIOLOGY, math_start = "calculus",
    english_start = "composition", start_season = "fall", node_id = v$allowances$node_id[1])
  suggestions <- build_degree_popup_history(test_sections_regstats, test_students_regstats, history_edges,
    catalog(), roadmaps(), planning_gen_ed(), selection)
  expect_s3_class(degree_allowance_table(suggestions), "reactable")
  html <- as.character(degree_allowance_history_ui(suggestions, "suggestion_table"))
  expect_match(html, "Fall course options", fixed = TRUE)
  expect_match(html, "first class day", fixed = TRUE)
  failed <- list(state = "error", kind = "allowance", node_id = "allowance-3-1", note = "Planner stopped")
  expect_match(as.character(degree_allowance_history_ui(failed, "suggestion_table")), "Planner stopped", fixed = TRUE)
})
