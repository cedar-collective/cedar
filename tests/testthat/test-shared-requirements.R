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
    drafts <- file.path(institution, "degree_drafts", "degree_catalogs.csv")
    if (file.exists(drafts)) catalogs <- rbind(catalogs, read.csv(drafts, colClasses = "character")[names(catalogs)])
    catalogs <- catalogs[catalogs$catalog_year == reference$bundle$catalog_year, ]
    profile_ids <- vapply(reference$bundle$profiles, function(profile) profile$catalog_id, character(1))
    # Every hand-built board has a profile, and every profile names a board. A
    # compiled board has none only when its college has no rule set; the
    # compile then refuses its Gen Ed pools (degree_reading_gen_ed_pools()).
    authored <- read.csv(file.path(institution, "degree_catalogs.csv"), colClasses = "character")
    expect_equal(setdiff(authored$catalog_id[authored$catalog_year == reference$bundle$catalog_year], profile_ids), character())
    expect_equal(setdiff(profile_ids, catalogs$catalog_id), character())
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

test_that("planned coverage consumes each course once and never resolves an open choice", {
  reference <- planning_reference
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
      sum(view$allowances$credits[view$allowances$semester == i]),
    view$terms$planned_credits[i])
  # Both earmarked areas land in semester 3, the first with room. Gen Ed heads
  # the board; elective space sits between math/writing and the program's courses.
  gen_ed <- view$allowances$purpose == "gen_ed"
  foundation <- view$nodes$row_group %in% c("math", "writing")
  expect_equal(view$allowances$row[gen_ed], 1:2)
  expect_lt(max(view$allowances$row[gen_ed]), min(view$nodes$row))
  expect_true(all(view$allowances$row[!gen_ed] > max(view$nodes$row[foundation]) &
    view$allowances$row[!gen_ed] < min(view$nodes$row[!foundation])))
  # A bare approved lab is not a full science requirement.
  reference$memberships <- reference$memberships[reference$memberships$subject_course != "CHEM 1215", ]
  missing <- degree_shared_coverage(base, test_degree_roadmaps, reference)
  expect_equal(missing$areas$remaining[missing$areas$area == "C"], 4)
  reference$bundle$catalog_year <- "1900-1901"
  expect_error(degree_shared_coverage(base, test_degree_roadmaps, reference), "different editions")
})

test_that("a lecture and its own lab drawn as two tiles meet a science area together, as a bundle does (I97)", {
  reference <- planning_reference
  # Change: Biology draws General Chemistry I as two tiles, the lecture and its
  # lab, as a compiled board does.
  r <- test_degree_roadmaps
  lab <- r$nodes[r$nodes$catalog_id == "demo-biology-bs-2026" & r$nodes$node_id == "chem1", ]
  lab$node_id <- "chem1l"; lab$code <- "CHEM 1215L"; lab$credits <- "1"; lab$bundle <- "0"
  r$nodes$credits[r$nodes$catalog_id == "demo-biology-bs-2026" & r$nodes$node_id == "chem1"] <- "3"
  r$nodes <- rbind(r$nodes, lab)
  basis <- r$basis[r$basis$catalog_id == "demo-biology-bs-2026" & r$basis$node_id == "chem1", ]
  basis$node_id <- "chem1l"
  r$basis <- rbind(r$basis, basis)
  r$courses$node_id[r$courses$catalog_id == "demo-biology-bs-2026" & r$courses$subject_course == "CHEM 1215L"] <- "chem1l"
  view <- build_degree_roadmap_view(test_degree_catalog, r, "demo-biology-bs-2026", "calculus", "composition", shared = reference)
  science <- view$shared$assigned[view$shared$assigned$area == "C", ]
  expect_equal(science$node_id, "chem1|chem1l")
  expect_equal(science$courses, "CHEM 1215 + CHEM 1215L")
  expect_equal(view$shared$areas$remaining[view$shared$areas$area == "C"], 0)
  expect_match(view$nodes$coverage_label[view$nodes$node_id == "chem1"], "Science", fixed = TRUE)
  expect_match(view$nodes$coverage_label[view$nodes$node_id == "chem1l"], "Science", fixed = TRUE)
  # Change: the lab tile is another lecture's lab. It is never paired.
  r$courses$subject_course[r$courses$catalog_id == "demo-biology-bs-2026" & r$courses$node_id == "chem1l"] <- "PHYS 1230L"
  r$nodes$code[r$nodes$node_id == "chem1l"] <- "PHYS 1230L"
  view <- build_degree_roadmap_view(test_degree_catalog, r, "demo-biology-bs-2026", "calculus", "composition", shared = reference)
  expect_false(any(grepl("|", view$shared$assigned$node_id, fixed = TRUE)))
  expect_equal(view$shared$areas$remaining[view$shared$areas$area == "C"], 4)
})

test_that("a program that asks for more of an area gets those Gen Ed cards, which also fill the flexible choices (I97)", {
  reference <- planning_reference
  # Change: Biology's page asks for 6 math credits and 8 of science, where the
  # University asks for 3 and 4.
  r <- test_degree_roadmaps
  r$plans$gen_ed_area_minimums[r$plans$catalog_id == "demo-biology-bs-2026"] <- "B:6|C:8"
  view <- build_degree_roadmap_view(test_degree_catalog, r, "demo-biology-bs-2026", "calculus", "composition", shared = reference)
  areas <- view$shared$areas
  expect_equal(areas$minimum, c(6, 6, 8, 6))
  expect_equal(areas$university_minimum, c(6, 3, 4, 6))
  # Calculus and the paired chemistry cover the University's part; one more math
  # and one more science course are cards. ENGL 1110 fills one flexible choice
  # and the added math the other, so no flexible card is left.
  expect_equal(areas$planned, c(3, 3, 4, 6))
  expect_equal(areas$remaining, c(3, 3, 4, 0))
  needs <- view$shared$needs
  expect_equal(needs$credits[needs$area %in% c("B", "C")], c(3, 4))
  expect_true(all(needs$source_url[needs$area %in% c("B", "C")] == test_degree_catalog$catalogs$source_url[
    test_degree_catalog$catalogs$catalog_id == "demo-biology-bs-2026"]))
  expect_equal(view$shared$flexible_areas_used, c("A", "B"))
  # The flexible choice the added math meets is inside the math cards: counted
  # in neither total (26 minimum and 16 planned, less those 3).
  testthat::local_edition(3)
  expect_snapshot(view$coverage_note)
  # A minimum for an area the rules lack, or for the flexible area, stops.
  r$plans$gen_ed_area_minimums[r$plans$catalog_id == "demo-biology-bs-2026"] <- "Z:3"
  expect_error(build_degree_roadmap_view(test_degree_catalog, r, "demo-biology-bs-2026", "calculus", "composition", shared = reference),
               "area the shared rules do not: Z")
  r$plans$gen_ed_area_minimums[r$plans$catalog_id == "demo-biology-bs-2026"] <- "F:9"
  expect_error(build_degree_roadmap_view(test_degree_catalog, r, "demo-biology-bs-2026", "calculus", "composition", shared = reference),
               "flexible area is not planned: F")
  # The plan's value is read strictly.
  expect_equal(degree_gen_ed_area_minimums(""), stats::setNames(numeric(), character()))
  expect_equal(degree_gen_ed_area_minimums("I:9|III:8"), c(I = 9, III = 8))
  for (bad in c("I:9|I:3", "I:x", "I", ":3", "I:0")) expect_error(degree_gen_ed_area_minimums(bad), "Invalid gen_ed_area_minimums", info = bad)
  expect_equal(degree_shared_gen_ed_areas(reference), c("A", "B", "C"))
})

test_that("placement does not award preparation coverage and absent profiles stay generic", {
  reference <- planning_reference
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
  whole <- generic$allowances[generic$allowances$credits >= 3, ]
  expect_true(all(grepl("Gen Ed not required", whole$title[whole$phase == "foundation"], fixed = TRUE)))
  expect_true(any(whole$phase == "advanced") &&
    all(grepl("upper level may count", whole$title[whole$phase == "advanced"], fixed = TRUE)))
})

test_that("active annual profiles preserve semester budgets and show source-linked area gaps", {
  c <- CEDAR_DEGREE_CATALOG; r <- CEDAR_DEGREE_ROADMAPS
  reference <- load_degree_shared_requirements(c, cedar_institution_dir(cedar_base_dir))
  if (is.null(reference)) return(invisible(NULL))
  # Each rule broken is listed by program and English start.
  problems <- character(0)
  for (id in c$catalogs$catalog_id) for (english in r$starts$start_id[r$starts$track == "english"]) {
    view <- build_degree_roadmap_view(c, r, id, "intermediate", english, shared = reference)
    rules <- vapply(list(
      "a semester over 16 credits" = all(view$terms$planned_credits <= 16),
      "planned credits that do not cover the degree" =
        all.equal(sum(view$terms$planned_credits),
                  view$degree_credits - view$completed_credits + view$preparation_credits),
      "a Gen Ed area with negative credits remaining" = all(view$shared$areas$remaining >= 0),
      "an allowance without a source link" = all(grepl("^https://", view$allowances$source_url)),
      "allowance credits that do not sum to the semesters' other credits" =
        all.equal(sum(view$allowances$credits), sum(view$terms$other_credits)),
      "two cards in one semester and row" =
        anyDuplicated(c(paste(view$nodes$semester, view$nodes$row),
          paste(view$allowances$semester, view$allowances$row))) == 0L
    ), isTRUE, logical(1))
    problems <- c(problems, sprintf("%s, intermediate math, %s English: %s",
      id, english, names(rules)[!rules]))
  }
  expect(length(problems) == 0L, paste(problems, collapse = "\n"))
})
