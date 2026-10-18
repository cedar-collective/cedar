# CEDAR-PLATFORM: versioned degree rule trees and descriptive pathway categories

CEDAR_DEGREE_PHASES <- c("admission", "degree", "prerequisite", "corequisite")
CEDAR_DEGREE_AREAS <- c("entry", "core", "supporting", "electives", "general_education",
                        "minor", "completion", "requisites")
CEDAR_DEGREE_AREA_LABELS <- c(entry = "Entering the program", core = "Required courses",
  supporting = "Supporting coursework", electives = "Choices and electives",
  general_education = "University and college requirements", minor = "Concentration or minor",
  completion = "Overall completion rules", requisites = "Course prerequisites and corequisites")
CEDAR_DEGREE_OPERATORS <- c("all", "choose_n", "course", "credits", "condition", "none",
                           "prior", "concurrent", "prior_or_concurrent")

#' Validate the catalog boundary before any consumer reads it
validate_degree_catalog <- function(catalog) {
  for (nm in c("catalogs", "rules", "courses", "evidence")) {
    if (is.null(catalog[[nm]])) stop("Degree catalog needs ", nm)
  }
  c <- catalog$catalogs; r <- catalog$rules; x <- catalog$courses
  specs <- list(catalogs = "degree_catalogs", rules = "degree_rules", courses = "degree_rule_courses", evidence = "degree_catalog_evidence")
  for (nm in names(specs)) {
    missing <- setdiff(CEDAR_CONFIG_FILE_SPECS[[specs[[nm]]]], names(catalog[[nm]]))
    if (length(missing)) stop("Degree ", nm, " missing columns: ", paste(missing, collapse = ", "))
    if (anyNA(catalog[[nm]])) stop("Degree ", nm, " has NA fields; use blanks for optional values")
  }
  if (length(unique(c$catalog_year)) > 1L) stop("Active degree catalog must contain one year")
  if (anyDuplicated(c$catalog_id) || any(!nzchar(c$catalog_id))) stop("Duplicate or blank catalog_id")
  if (any(!c$coverage %in% c("excerpt", "complete"))) stop("Invalid degree coverage")
  if (any(!grepl("^[0-9]{4}-[0-9]{4}$", c$catalog_year))) stop("Invalid catalog_year")
  if (any(!nzchar(c$source_url)) || any(!nzchar(c$program_name))) stop("Catalog needs source and program name")
  if (anyDuplicated(r$rule_id) || any(!nzchar(r$rule_id))) stop("Duplicate or blank rule_id")
  if (any(!r$catalog_id %in% c$catalog_id)) stop("Rule references unknown catalog")
  if (any(!r$phase %in% CEDAR_DEGREE_PHASES) || any(!r$area %in% CEDAR_DEGREE_AREAS)) stop("Invalid rule phase or area")
  if (any(!r$operator %in% CEDAR_DEGREE_OPERATORS)) stop("Invalid degree operator")
  if (any(!r$review_status %in% c("draft", "verified", "conflict"))) stop("Invalid rule review_status")
  parent <- match(r$parent_id, r$rule_id)
  has_parent <- nzchar(r$parent_id)
  if (any(has_parent & is.na(parent))) stop("Rule references unknown parent")
  if (any(r$catalog_id[has_parent] != r$catalog_id[parent[has_parent]]) ||
      any(r$phase[has_parent] != r$phase[parent[has_parent]]) ||
      any(r$area[has_parent] != r$area[parent[has_parent]]) ||
      any(r$target_course[has_parent] != r$target_course[parent[has_parent]])) stop("Rule parent crosses catalog or scope")
  for (id in r$rule_id) {
    seen <- character(); at <- id
    while (nzchar(at)) {
      if (at %in% seen) stop("Cycle in degree rules: ", id)
      seen <- c(seen, at); at <- r$parent_id[match(at, r$rule_id)]
    }
  }
  amount <- suppressWarnings(as.numeric(r$minimum))
  needs_amount <- r$operator %in% c("choose_n", "credits")
  if (any(needs_amount & (!is.finite(amount) | amount <= 0))) stop("Rule needs positive minimum")
  for (i in which(r$operator %in% c("all", "choose_n"))) {
    children <- sum(r$parent_id == r$rule_id[i])
    if (children == 0 || (r$operator[i] == "choose_n" &&
        (amount[i] != floor(amount[i]) || amount[i] > children))) stop("Invalid choice group: ", r$rule_id[i])
  }
  if (any(!x$rule_id %in% r$rule_id)) stop("Course references unknown rule")
  if (anyDuplicated(x$rule_id)) stop("Each course leaf must have one course")
  leaf <- r$operator %in% c("course", "prior", "concurrent", "prior_or_concurrent")
  if (!setequal(x$rule_id, r$rule_id[leaf])) stop("Course leaves and course rows disagree")
  if (any(r$parent_id %in% r$rule_id[!r$operator %in% c("all", "choose_n")])) stop("Only groups may have children")
  if (any(!nzchar(x$subject_course))) stop("Blank catalog course")
  credits <- suppressWarnings(as.numeric(x$credits))
  if (any(!is.finite(credits) | credits <= 0)) stop("Invalid catalog course credits")
  req <- r$phase %in% c("prerequisite", "corequisite")
  if (any(req & !nzchar(r$target_course))) stop("Requisite needs target_course")
  e <- catalog$evidence
  if (anyDuplicated(e$evidence_id) || any(!nzchar(e$evidence_id))) stop("Duplicate or blank catalog evidence")
  if (any(!e$catalog_year %in% c$catalog_year) || any(!e$source_type %in% c("program", "course"))) stop("Invalid evidence year or source type")
  if (any(!e$review_status %in% c("transcribed", "reviewed", "conflict")) ||
      any(!grepl("^https://", e$source_url)) || any(!nzchar(e$section)) || any(!nzchar(e$quote)) ||
      any(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", e$retrieved_on))) stop("Invalid catalog evidence citation")
  catalog
}

validate_pathway_subject_groups <- function(groups) {
  if (!all(CEDAR_CONFIG_FILE_SPECS$pathway_subject_groups %in% names(groups))) stop("Invalid pathway grouping columns")
  if (anyNA(groups) || any(!nzchar(as.matrix(groups)))) stop("Blank pathway grouping field")
  if (anyDuplicated(groups$subject_code)) stop("Subject has multiple pathway groups")
  labels <- split(groups$group_label, groups$group_id)
  if (any(vapply(labels, function(x) length(unique(x)) != 1L, logical(1)))) stop("Inconsistent pathway group label")
  groups
}

CEDAR_DEGREE_CATALOG <- validate_degree_catalog(list(
  catalogs = read_institution_file("degree_catalogs"),
  rules = read_institution_file("degree_rules"),
  courses = read_institution_file("degree_rule_courses"),
  evidence = read_institution_file("degree_catalog_evidence")
))
CEDAR_PATHWAY_SUBJECT_GROUPS <- validate_pathway_subject_groups(read_institution_file("pathway_subject_groups"))

# Shared nodes belong to a program only when one of its entry routes uses them.
# A statistics route must not acquire the calculus sequence (or its citations).
degree_roadmap_node_ids <- function(roadmaps, catalog_id) {
  routes <- c(roadmaps$math_routes$node_ids[roadmaps$math_routes$catalog_id == catalog_id],
    roadmaps$starts$node_ids[roadmaps$starts$track == "english"])
  unique(c(roadmaps$nodes$node_id[roadmaps$nodes$catalog_id == catalog_id],
    unlist(strsplit(routes[nzchar(routes)], "|", fixed = TRUE), use.names = FALSE)))
}

#' Validate authored planning templates separately from requirement truth
validate_degree_roadmaps <- function(roadmaps, catalog) {
  for (nm in c("nodes", "links", "starts", "math_routes", "conditions", "basis", "plans", "courses", "options")) {
    x <- roadmaps[[nm]]
    if (is.null(x) || !all(CEDAR_CONFIG_FILE_SPECS[[paste0("degree_roadmap_", nm)]] %in% names(x)))
      stop("Invalid roadmap ", nm, " columns")
    if (anyNA(x)) stop("Roadmap ", nm, " contains NA")
  }
  n <- roadmaps$nodes; l <- roadmaps$links; s <- roadmaps$starts
  if (any(!n$course_level %in% c("lower", "upper"))) stop("Invalid roadmap course level")
  b <- roadmaps$basis; p <- roadmaps$plans; e <- catalog$evidence
  cc <- roadmaps$courses
  options <- roadmaps$options
  option_key <- paste(options$catalog_id, options$node_id)
  node_key <- paste(n$catalog_id, n$node_id)
  if (anyDuplicated(paste(option_key, options$option_id, options$subject_course)) ||
      any(!grepl("^[a-z][a-z0-9_]*$", options$option_id)) || any(!option_key %in% node_key) ||
      any(!grepl("^[A-Z]+ [0-9]+[A-Z]*$", options$subject_course)) ||
      any(!nzchar(options$course_title)) || any(!grepl("^https://", options$source_url)))
    stop("Invalid roadmap option course")
  for (key in unique(option_key)) {
    choices <- options[option_key == key, ]; node <- n[match(key, node_key), ]
    minimum <- suppressWarnings(as.numeric(unique(choices$minimum)))
    low <- suppressWarnings(as.numeric(choices$credits_min)); high <- suppressWarnings(as.numeric(choices$credits_max))
    planned <- suppressWarnings(as.numeric(node$credits))
    # A lecture/lab option costs the sum of its components. Counting each row
    # as an alternative would let a one-credit lab satisfy a four-credit slot.
    option_low <- tapply(low, choices$option_id, sum)
    option_high <- tapply(high, choices$option_id, sum)
    levels <- unname(COURSE_LEVEL_BY_LEADING_DIGIT[substr(sub("^.* ", "", choices$subject_course), 1, 1)])
    if (node$kind != "choice" || node$bundle != "0" || length(minimum) != 1L ||
        !is.finite(minimum) || minimum < 1 || minimum != floor(minimum) || minimum > length(option_low) ||
        any(!is.finite(low) | !is.finite(high) | low <= 0 | high < low) ||
        !is.finite(planned) || planned < sum(sort(option_low)[seq_len(minimum)]) ||
        planned > sum(sort(option_high, decreasing = TRUE)[seq_len(minimum)]) ||
        anyNA(levels) || any(!levels %in% c("lower", "upper")) ||
        (all(levels == "upper") && node$course_level != "upper"))
      stop("Invalid roadmap option set or planning credits")
    proof <- e[match(choices$evidence_id, e$evidence_id), ]
    cat <- catalog$catalogs[catalog$catalogs$catalog_id == node$catalog_id, ]
    basis <- b[b$catalog_id == node$catalog_id & b$node_id == node$node_id, ]
    if (nrow(basis) != 1L || anyNA(proof$evidence_id) || any(proof$source_type != "program") ||
        any(proof$catalog_year != cat$catalog_year) || any(proof$source_url != cat$source_url) ||
        any(choices$evidence_id != basis$evidence_id)) stop("Options need matching program requirement evidence")
    req <- which(nzchar(choices$requisite_evidence_id))
    rp <- e[match(choices$requisite_evidence_id[req], e$evidence_id), ]
    if (anyNA(rp$evidence_id) || any(rp$source_type != "course") ||
        any(rp$catalog_year != cat$catalog_year) || any(rp$source_url != choices$source_url[req]))
      stop("Option prerequisite needs matching course evidence")
    # A selected example's prerequisites cannot be applied to every alternative.
    if (any(l$catalog_id == node$catalog_id & (l$from == node$node_id | l$to == node$node_id)) ||
        any(roadmaps$conditions$catalog_id == node$catalog_id & roadmaps$conditions$node_id == node$node_id))
      stop("Unresolved option set cannot inherit a particular course's prerequisites")
  }
  if (anyDuplicated(cc) || any(!grepl("^[A-Z]+ [0-9]+[A-Z]*$", cc$subject_course)) ||
      any(!paste(cc$catalog_id, cc$node_id) %in% paste(n$catalog_id, n$node_id)))
    stop("Invalid roadmap course components")
  for (i in seq_len(nrow(n))) {
    components <- cc$subject_course[cc$catalog_id == n$catalog_id[i] & cc$node_id == n$node_id[i]]
    expected <- if (n$kind[i] == "choice") 0L else if (n$bundle[i] == "1") 2L else 1L
    if (length(components) != expected || (expected == 1L && components != n$code[i]))
      stop("Roadmap course components disagree with node: ", n$node_id[i])
    # Lists load before trunk helpers: use the same institution digit lookup as
    # course_level_from_number(), without calling a higher architecture layer.
    levels <- unname(COURSE_LEVEL_BY_LEADING_DIGIT[substr(sub("^.* ", "", components), 1, 1)])
    if (anyNA(levels) || any(levels != n$course_level[i]))
      stop("Roadmap course level disagrees with components: ", n$node_id[i])
  }
  if (anyDuplicated(paste(n$catalog_id, n$node_id)) || any(!nzchar(n$node_id))) stop("Duplicate or blank roadmap node")
  if (any(!n$catalog_id %in% c("*", catalog$catalogs$catalog_id)) ||
      any(!l$catalog_id %in% c("*", catalog$catalogs$catalog_id))) stop("Unknown roadmap catalog")
  if (any(!n$track %in% c("main", "math", "english")) ||
      any(!n$kind %in% c("major", "support", "writing", "choice", "preparation"))) stop("Invalid roadmap track or kind")
  if (any(!n$bundle %in% c("0", "1"))) stop("Invalid roadmap bundle")
  if (any(!grepl("^[a-z][a-z0-9_]*$", n$row_group))) stop("Invalid roadmap row group")
  credits <- suppressWarnings(as.numeric(n$credits)); semester <- suppressWarnings(as.numeric(n$semester))
  if (any(!is.finite(credits) | credits <= 0) ||
      any(!is.finite(semester) | semester < 1 | semester != floor(semester))) stop("Invalid roadmap credits or semester")
  if (any(!nzchar(n$source_url)) || any(!nzchar(l$source_url))) stop("Roadmap needs sources")
  if (any(!l$timing %in% c("before", "before_or_same"))) stop("Invalid roadmap timing")
  if (anyDuplicated(paste(l$catalog_id, l$from, l$to))) stop("Duplicate roadmap link")
  for (id in unique(c(n$catalog_id, l$catalog_id))) {
    ids <- n$node_id[n$catalog_id %in% c("*", id)]
    edges <- l[l$catalog_id %in% c("*", id), ]
    if (anyDuplicated(ids) || any(!edges$from %in% ids) || any(!edges$to %in% ids)) stop("Unknown or ambiguous roadmap endpoint")
    # Even a before-or-same cycle is rejected; same-term lecture/lab pairs are one bundle.
    remaining <- ids
    while (length(remaining)) {
      ready <- setdiff(remaining, edges$to[edges$from %in% remaining])
      if (!length(ready)) stop("Cycle in roadmap links")
      remaining <- setdiff(remaining, ready)
    }
  }
  if (any(!s$track %in% c("math", "english")) || anyDuplicated(paste(s$track, s$start_id))) stop("Invalid roadmap starting point")
  completed <- suppressWarnings(as.numeric(s$completed_degree_credits))
  if (any(!is.finite(completed) | completed < 0)) stop("Invalid completed starting credits")
  for (i in seq_len(nrow(s))) {
    ids <- if (nzchar(s$node_ids[i])) strsplit(s$node_ids[i], "|", fixed = TRUE)[[1]] else character()
    allowed <- n$node_id[n$catalog_id == "*" & n$track == s$track[i]]
    if (anyDuplicated(ids) || any(!ids %in% allowed)) stop("Unknown roadmap starting course")
  }
  mr <- roadmaps$math_routes
  math_starts <- s$start_id[s$track == "math"]
  if (any(!mr$catalog_id %in% catalog$catalogs$catalog_id) ||
      any(!mr$start_id %in% math_starts) || any(!nzchar(mr$label)) ||
      anyDuplicated(paste(mr$catalog_id, mr$start_id))) stop("Invalid program math route")
  for (i in seq_len(nrow(mr))) {
    ids <- strsplit(mr$node_ids[i], "|", fixed = TRUE)[[1]]
    allowed <- n$node_id[n$catalog_id == "*" & n$track == "math"]
    if (!length(ids) || anyDuplicated(ids) || any(!ids %in% allowed)) stop("Unknown program math route course")
  }
  for (id in catalog$catalogs$catalog_id) {
    if (!any(n$catalog_id == id)) stop("Catalog has no roadmap: ", id)
    if (!all(c("math", "english") %in% s$track)) stop("Roadmap starting points missing")
    if (!setequal(mr$start_id[mr$catalog_id == id], math_starts)) stop("Program math starting routes missing: ", id)
    ids <- degree_roadmap_node_ids(roadmaps, id)
    edges <- l[l$catalog_id == id, ]
    if (any(!edges$from %in% ids) || any(!edges$to %in% ids)) stop("Program route has unavailable endpoint")
  }
  conditions <- roadmaps$conditions
  if (anyDuplicated(conditions$condition_id) || any(!nzchar(conditions$condition_id)) ||
      any(!conditions$catalog_id %in% catalog$catalogs$catalog_id) ||
      any(!conditions$kind %in% c("course_count", "permission")) || any(!nzchar(conditions$label)))
    stop("Invalid roadmap condition")
  for (i in seq_len(nrow(conditions))) {
    condition <- conditions[i, ]
    ids <- degree_roadmap_node_ids(roadmaps, condition$catalog_id)
    if (!condition$node_id %in% ids) stop("Unknown condition target")
    pool <- if (nzchar(condition$eligible_node_ids)) strsplit(condition$eligible_node_ids, "|", fixed = TRUE)[[1]] else character()
    if (condition$kind == "course_count") {
      minimum <- suppressWarnings(as.numeric(condition$minimum))
      if (!is.finite(minimum) || minimum < 1 || minimum != floor(minimum) ||
          anyDuplicated(pool) || any(!pool %in% ids) || condition$node_id %in% pool ||
          length(pool) < minimum) stop("Invalid course-count condition pool or minimum")
      members <- n[n$catalog_id %in% c("*", condition$catalog_id) & n$node_id %in% pool, ]
      if (any(members$bundle == "1")) stop("Course-count condition pools need single-course slots")
    } else if (length(pool) || nzchar(condition$minimum)) stop("Permission condition cannot count courses")
    proof <- e[match(condition$evidence_id, e$evidence_id), ]
    cat_year <- catalog$catalogs$catalog_year[match(condition$catalog_id, catalog$catalogs$catalog_id)]
    if (is.na(proof$evidence_id) || proof$source_type != "course" || proof$catalog_year != cat_year)
      stop("Condition needs matching course evidence")
    target <- n[n$catalog_id %in% c("*", condition$catalog_id) & n$node_id == condition$node_id, ]
    if (proof$source_url != target$source_url) stop("Condition evidence must cite its target course")
  }
  if (!setequal(p$catalog_id, catalog$catalogs$catalog_id) || anyDuplicated(p$catalog_id)) stop("Roadmap needs one plan per catalog")
  for (col in c("degree_credit_target", "normal_load", "max_load", "baseline_semesters", "upper_level_from_semester", "allowance_slot_credits")) {
    value <- suppressWarnings(as.numeric(p[[col]]))
    if (any(!is.finite(value) | value <= 0 | value != floor(value))) stop("Invalid roadmap plan ", col)
  }
  if (any(as.numeric(p$normal_load) > as.numeric(p$max_load))) stop("Normal load exceeds maximum")
  if (any(as.numeric(p$allowance_slot_credits) > as.numeric(p$max_load)) ||
      any(!grepl("^https://", p$gen_ed_source_url))) stop("Invalid allowance planning policy")
  if (any(as.numeric(p$upper_level_from_semester) < 2)) stop("Upper-level timing needs an early-coursework stage")
  if (anyDuplicated(paste(b$catalog_id, b$node_id)) || any(!b$catalog_id %in% p$catalog_id) ||
      any(!b$basis %in% c("degree", "prerequisite", "general"))) stop("Invalid roadmap basis")
  if (any(!c(l$evidence_id, b$evidence_id, p$evidence_id) %in% e$evidence_id)) stop("Unknown roadmap evidence")
  if (any(e$source_type[match(l$evidence_id, e$evidence_id)] != "course") ||
      any(l$source_url != e$source_url[match(l$evidence_id, e$evidence_id)])) stop("Link needs matching course evidence")
  for (id in p$catalog_id) {
    cn <- n[n$catalog_id %in% c("*", id) & n$node_id %in% degree_roadmap_node_ids(roadmaps, id), ]
    cb <- b[b$catalog_id == id, ]
    if (!setequal(cn$node_id, cb$node_id)) stop("Roadmap node needs requirement evidence: ", id)
    plan <- p[p$catalog_id == id, ]; ec <- e[match(c(cb$evidence_id, plan$evidence_id), e$evidence_id), ]
    cat <- catalog$catalogs[catalog$catalogs$catalog_id == id, ]
    le <- e[match(l$evidence_id[l$catalog_id %in% c("*", id)], e$evidence_id), ]
    if (any(c(ec$catalog_year, le$catalog_year) != cat$catalog_year)) stop("Roadmap evidence crosses catalog years")
    if (any(as.numeric(cn$credits) > as.numeric(plan$max_load))) stop("Course bundle exceeds maximum load")
    degree <- cb$basis %in% c("degree", "general")
    de <- e[match(cb$evidence_id[degree], e$evidence_id), ]
    if (any(de$source_type != "program") || any(de$source_url != cat$source_url)) stop("Degree basis needs the program page")
    if (any(e$source_type[match(cb$evidence_id[!degree], e$evidence_id)] != "course")) stop("Preparation needs course evidence")
  }
  roadmaps
}

CEDAR_DEGREE_ROADMAPS <- validate_degree_roadmaps(list(
  nodes = read_institution_file("degree_roadmap_nodes"),
  links = read_institution_file("degree_roadmap_links"),
  starts = read_institution_file("degree_roadmap_starts"),
  math_routes = read_institution_file("degree_roadmap_math_routes"),
  conditions = read_institution_file("degree_roadmap_conditions"),
  basis = read_institution_file("degree_roadmap_basis"),
  plans = read_institution_file("degree_roadmap_plans"),
  courses = read_institution_file("degree_roadmap_courses"),
  options = read_institution_file("degree_roadmap_options")
), CEDAR_DEGREE_CATALOG)
