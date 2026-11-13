# What the tests in test-shared-requirements.R share: builders, option lists, constants.

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
