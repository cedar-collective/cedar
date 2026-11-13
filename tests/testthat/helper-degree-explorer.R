# What the tests in test-degree-explorer.R share: builders, option lists, constants.

# Public-source ingestion uses an authored catalog fixture, just like the demo
# CSVs setup.R reads. It models nested alternatives/bundles, a prose condition, an
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

# The demo institution's two designed programs (institution/demo/degree_*.csv,
# exposed by setup.R as test_degree_catalog and test_degree_roadmaps), and the
# plan and view of one of them. Their schedules are worked by hand at the head
# of the roadmap tests in test-degree-explorer.R.
BIOLOGY <- "demo-biology-bs-2026"
HISTORY <- "demo-history-ba-2026"

roadmap_plan <- function(id = BIOLOGY, math = "calculus", english = "composition", r = test_degree_roadmaps) {
  build_degree_roadmap(test_degree_catalog, r, id, math, english)
}

roadmap_view <- function(id = BIOLOGY, math = "calculus", english = "composition", season = "fall", r = test_degree_roadmaps) {
  build_degree_roadmap_view(test_degree_catalog, r, id, math, english, season)
}

node_at <- function(view, id, field = "semester") view$nodes[[field]][match(id, view$nodes$node_id)]
