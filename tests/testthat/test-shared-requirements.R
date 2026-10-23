# These are artifact-format fixtures, not student/section domain tables. The
# tiny published-document stub makes evidence validation inspectable offline.
make_shared_rule_artifact <- function() {
  directory <- tempfile("shared-rules-"); dir.create(directory)
  capture <- tempfile("shared-source-")
  body <- source_json_bytes(list(body = '<p>Choices <a href="#/courses/c1">ALFA101</a> (3)</p>'))
  receipt <- capture_public_source("https://example.invalid/policy", capture, "policy", "page",
    fetch = function(url) list(body = body, status_code = 200L, final_url = url,
      content_type = "application/json", etag = "", last_modified = ""))
  receipt$catalog_url <- "https://example.invalid/#/policies/example"
  receipt$title <- "Designed source"
  source <- list(source_id = "page", pointer = "/body", anchor = "Choices")
  leaf <- function(id, op, ...) c(list(rule_id = id, label = id, statement = "Designed rule.", operator = op), list(...))
  set <- list(schema_version = "1.0.0", rule_set_id = "fixture", catalog_id = "edition",
    catalog_year = "2020-2021", title = "Designed reference", scope = list(level = "university"),
    coverage = "selected_sections", notes = list(), attention = list(), rules = list(
      leaf("fixture.required", "all", source_refs = list(source), children = list(
        leaf("fixture.choice", "choose_n", minimum = 1, children = list(
          leaf("fixture.course", "course", subject_course = "ALFA 101"),
          leaf("fixture.exception", "condition", maximum = 12, minimum_unique_per_major = 24))))),
      leaf("fixture.area", "credits", minimum = 3, unit = "credit_hours", area = "A",
        source_refs = list(source))))
  college <- list(schema_version = "1.0.0", rule_set_id = "fixture-college", catalog_id = "edition",
    catalog_year = "2020-2021", title = "Designed college", scope = list(level = "college", college_code = "EX"),
    coverage = "not_located_on_checked_overview", checked_source_ids = list("page"), rules = list(), notes = list(), attention = list())
  bundle <- list(schema_version = "1.0.0", catalog_id = "edition", catalog_year = "2020-2021",
    rule_files = list("university.json", "college.json"), composition_policy = list("Credits count once."),
    profiles = list(list(catalog_id = "designed-program", college_code = "EX", rule_set_ids = list("fixture", "fixture-college"))))
  provenance <- list(schema_version = "1.0.0", catalog_id = "edition", catalog_year = "2020-2021",
    capture_directory = capture, sources = list(page = receipt))
  write_source_json(set, file.path(directory, "university.json"))
  write_source_json(college, file.path(directory, "college.json"))
  write_source_json(bundle, file.path(directory, "bundle.json"))
  write_source_json(provenance, file.path(directory, "sources.json"))
  write.csv(data.frame(area = "A", subject_course = "ALFA 101", credits = 3,
    course_url = "https://example.invalid/#/courses/c1", source_id = "page", pointer = "/body"),
    file.path(directory, "gen-ed-course-memberships.csv"), row.names = FALSE)
  list(directory = directory, capture = capture, set = set, bundle = bundle, body = body)
}

test_that("shared rules preserve alternatives, source proof and explicit empty coverage", {
  fixture <- make_shared_rule_artifact()
  metadata <- read_shared_requirement_bundle(fixture$directory)
  verified <- read_shared_requirement_bundle(fixture$directory, fixture$capture)
  expect_false(metadata$source_bytes_verified)
  expect_true(verified$source_bytes_verified)
  expect_length(shared_requirement_nodes(verified$sets$fixture$rules), 5L)
  expect_length(verified$sets$`fixture-college`$rules, 0L)
  expect_match(format_shared_requirement_preview(verified), "coverage limit, not an exemption", fixed = TRUE)
  expect_match(format_shared_requirement_preview(verified), "https://example.invalid/#/policies/example", fixed = TRUE)
  expect_match(format_shared_requirement_preview(verified), "not yet used to schedule", fixed = TRUE)
  expect_match(format_shared_requirement_preview(verified), "\n    - **fixture.course**", fixed = TRUE)
  broken <- fixture$set
  broken$rules[[2]]$source_refs[[1]]$anchor <- "Missing passage"
  write_source_json(broken, file.path(fixture$directory, "university.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory, fixture$capture), "anchor does not match")
  write_source_json(fixture$set, file.path(fixture$directory, "university.json"))
  receipt <- verified$provenance$sources$page
  writeBin(charToRaw("tampered"), file.path(fixture$capture, receipt$file))
  expect_error(read_shared_requirement_bundle(fixture$directory, fixture$capture), "hash mismatch")
})

test_that("shared references reject impossible choices, ambiguous identity and wrong scope", {
  fixture <- make_shared_rule_artifact()
  broken <- fixture$set
  broken$rules[[1]]$children[[1]]$minimum <- 3
  write_source_json(broken, file.path(fixture$directory, "university.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory), "Invalid alternative")
  broken <- fixture$set; broken$rules[[2]]$minimum <- -1
  write_source_json(broken, file.path(fixture$directory, "university.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory), "numeric threshold")
  broken <- fixture$set; broken$rules[[2]]$rule_id <- "fixture.course"
  write_source_json(broken, file.path(fixture$directory, "university.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory), "Duplicate/invalid rule")
  broken <- fixture$set; broken$catalog_year <- "2021-2022"
  write_source_json(broken, file.path(fixture$directory, "university.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory), "edition mismatch")
  write_source_json(fixture$set, file.path(fixture$directory, "university.json"))
  broken <- fixture$bundle; broken$profiles[[1]]$college_code <- "OTHER"
  write_source_json(broken, file.path(fixture$directory, "bundle.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory), "awarding college mismatch")
  broken <- fixture$bundle; broken$rule_files[[1]] <- "../university.json"
  write_source_json(broken, file.path(fixture$directory, "bundle.json"))
  expect_error(read_shared_requirement_bundle(fixture$directory), "file paths")
})

test_that("recapture makes source candidates without rewriting the authored rules", {
  fixture <- make_shared_rule_artifact()
  reference <- read_shared_requirement_bundle(fixture$directory)
  before <- readBin(file.path(fixture$directory, "university.json"), "raw", n = 1e6)
  target <- tempfile("shared-candidate-")
  candidate <- capture_shared_requirement_sources(reference, target,
    fetch = function(url) list(body = source_json_bytes(list(body = "Changed public source")),
      status_code = 200L, final_url = url, content_type = "application/json", etag = "", last_modified = ""))
  expect_identical(candidate$status, "source_candidate_only")
  expect_false(identical(candidate$sources$page$sha256, reference$provenance$sources$page$sha256))
  expect_identical(readBin(file.path(fixture$directory, "university.json"), "raw", n = 1e6), before)
  expect_error(capture_shared_requirement_sources(reference, target), "new capture directory")
})

test_that("shipped annual shared-rule files are coherent without a private source archive", {
  paths <- list.files(file.path(cedar_base_dir, "institution"), "^bundle[.]json$", recursive = TRUE, full.names = TRUE)
  paths <- paths[grepl("/shared_requirements/", paths, fixed = TRUE)]
  expect_gt(length(paths), 0L)
  for (path in paths) {
    reference <- read_shared_requirement_bundle(dirname(path))
    expect_false(reference$source_bytes_verified)
    institution <- dirname(dirname(dirname(path)))
    catalogs <- read.csv(file.path(institution, "degree_catalogs.csv"), colClasses = "character")
    active_ids <- catalogs$catalog_id[catalogs$catalog_year == reference$bundle$catalog_year]
    if (length(active_ids)) {
      expect_setequal(vapply(reference$bundle$profiles, function(profile) profile$catalog_id, character(1)), active_ids)
    }
    colleges <- read.csv(file.path(institution, "colleges.csv"), colClasses = "character")
    expect_true(all(vapply(reference$bundle$profiles, function(profile) profile$college_code %in% colleges$college_code, logical(1))))
    for (set in reference$sets) {
      areas <- Filter(function(rule) identical(rule$role, "gen_ed_area"), set$rules)
      total <- Filter(function(rule) identical(rule$role, "subset_total"), set$rules)
      if (length(areas) && length(total) == 1L) {
        expect_equal(sum(vapply(areas, function(rule) rule$minimum, numeric(1))), total[[1]]$minimum)
      }
    }
    expect_gt(nrow(reference$memberships), 0L)
  }
})

# Derived planning/reference scaffolding: these invented memberships exercise
# allocation against the existing demo roadmap. They are not UNM claims or new
# student/section domain rows.
planning_reference <- function() {
  ref <- list(source_id = "page", pointer = "/body", anchor = "Designed policy")
  area <- function(id, label, minimum, method = "listed_course", ...) c(list(
    rule_id = paste0("example.", id), area = id, label = label, statement = label,
    role = "gen_ed_area", minimum = minimum, planning_method = method, source_refs = list(ref)), list(...))
  gen <- list(planning = list(preparation_rule_id = "example.prep",
    completed_courses_by_english_start = list(complete = list("ENGL 1120")), note = "Designed illustrative policy."),
    rules = list(
      area("A", "Writing and communication", 6, planning_parts = list(
        list(label = "Writing", minimum = 3, subject_courses = list("ENGL 1120")),
        list(label = "Communication", minimum = 3, subject_courses = list("COMM 1130")))),
      area("B", "Math", 3), area("C", "Science", 4, "related_science"),
      area("F", "Flexible", 6, "distinct_areas", planning_course_count = 2),
      list(rule_id = "example.prep", subject_courses = list("ENGL 1110", "ENGL 1110Y"))))
  list(bundle = list(catalog_year = test_degree_catalog$catalogs$catalog_year[1], profiles = list(
      list(catalog_id = "demo-biology-bs-2026", rule_set_ids = list("example")))),
    sets = list(example = gen), provenance = list(sources = list(page = list(catalog_url = "https://example.invalid/policy"))),
    memberships = data.frame(area = c("A", "B", "C", "C", "C", "C"),
      subject_course = c("ENGL 1120", "MATH 1512", "CHEM 1215", "CHEM 1215L", "PHYS 1230", "PHYS 1230L"),
      credits = c(3, 4, 3, 1, 3, 1)))
}

test_that("planned coverage consumes each course once and never resolves an open choice", {
  reference <- planning_reference()
  view <- build_degree_roadmap_view(test_degree_catalog, test_degree_roadmaps,
    "demo-biology-bs-2026", "calculus", "composition", shared = reference)
  # 1120 = 3 writing, calculus = 3 math, paired chemistry = 4 science,
  # 1110 = 3 flexible. The four-credit calculus course cannot supply its spare
  # credit to flexible, and the unresolved physics pool contributes nothing.
  expect_equal(view$shared$areas$planned, c(3, 3, 4, 3))
  expect_equal(view$shared$areas$remaining, c(3, 0, 0, 3))
  expect_equal(sum(view$allowances$credits[view$allowances$purpose == "gen_ed"]), 6)
  expect_false("biosci" %in% view$shared$assigned$node_id)
  expect_match(view$nodes$coverage_label[view$nodes$node_id == "biosci"], "May also meet", fixed = TRUE)
  expect_match(view$nodes$coverage_label[view$nodes$node_id == "engl1"], "provisional", fixed = TRUE)
  courses <- unlist(strsplit(view$shared$assigned$courses, " + ", fixed = TRUE))
  expect_false(anyDuplicated(courses) > 0L)
  base <- build_degree_roadmap(test_degree_catalog, test_degree_roadmaps,
    "demo-biology-bs-2026", "calculus", "composition")
  expect_equal(view$terms$planned_credits, base$terms$planned_credits)
  for (i in seq_len(nrow(view$terms))) expect_equal(
    sum(view$nodes$credits[view$nodes$semester == i]) +
      sum(view$allowances$credits[view$allowances$semester == i]) + view$terms$footer_credits[i],
    view$terms$planned_credits[i])
  # A bare approved lab is not a full science requirement.
  reference$memberships <- reference$memberships[reference$memberships$subject_course != "CHEM 1215", ]
  missing <- degree_shared_coverage(base, test_degree_roadmaps, reference)
  expect_equal(missing$areas$remaining[missing$areas$area == "C"], 4)
  reference$bundle$catalog_year <- "1900-1901"
  expect_error(degree_shared_coverage(base, test_degree_roadmaps, reference), "different editions")
})

test_that("placement does not award preparation coverage and absent profiles stay generic", {
  reference <- planning_reference()
  ready <- build_degree_roadmap_view(test_degree_catalog, test_degree_roadmaps,
    "demo-biology-bs-2026", "calculus", "composition2", shared = reference)
  completed <- build_degree_roadmap_view(test_degree_catalog, test_degree_roadmaps,
    "demo-biology-bs-2026", "calculus", "complete", shared = reference)
  expect_equal(ready$shared$areas$planned, c(3, 3, 4, 0))
  expect_equal(completed$shared$areas$planned, c(3, 3, 4, 0))
  expect_equal(completed$shared$assigned$node_id[completed$shared$assigned$area == "A"], "already-completed")
  generic <- build_degree_roadmap_view(test_degree_catalog, test_degree_roadmaps,
    "demo-history-ba-2026", "calculus", "composition", shared = reference)
  expect_null(generic$shared)
  expect_true(all(generic$allowances$purpose == "elective"))
  expect_true(all(grepl("Gen Ed not required", generic$allowances$title[generic$allowances$credits >= 3], fixed = TRUE)))
})

test_that("active annual profiles preserve semester budgets and show source-linked area gaps", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  reference <- load_degree_shared_requirements(c, cedar_institution_dir(cedar_base_dir))
  if (is.null(reference)) return(invisible(NULL))
  for (id in c$catalogs$catalog_id) for (english in r$starts$start_id[r$starts$track == "english"]) {
    view <- build_degree_roadmap_view(c, r, id, "intermediate", english, shared = reference)
    expect_true(all(view$terms$planned_credits <= 16))
    expect_equal(sum(view$terms$planned_credits), view$degree_credits - view$completed_credits + view$preparation_credits)
    expect_true(all(view$shared$areas$remaining >= 0))
    expect_true(all(grepl("^https://", view$allowances$source_url)))
    expect_equal(sum(view$allowances$credits) + sum(view$terms$footer_credits), sum(view$terms$other_credits))
    expect_false(anyDuplicated(c(paste(view$nodes$semester, view$nodes$row),
      paste(view$allowances$semester, view$allowances$row))) > 0L)
  }
})
