# CEDAR-PLATFORM: versioned degree rule trees and descriptive pathway categories
#
# The catalog files (degree_catalogs, degree_rules, degree_rule_courses,
# degree_catalog_evidence) record what a program page and its course pages
# say. The roadmap files (degree_roadmap_*) are authored planning templates
# built on that evidence. Both are validated here, at load, so a file that
# disagrees with its citations stops the app rather than reaching a page.
# Rules: docs/developers/degree-explorer-rules.md; contract:
# docs/developers/degree-requirements.md.

CEDAR_DEGREE_PHASES <- c("admission", "degree", "prerequisite", "corequisite")
CEDAR_DEGREE_AREAS <- c("entry", "core", "supporting", "electives", "general_education",
                        "minor", "completion", "requisites")
CEDAR_DEGREE_AREA_LABELS <- c(entry = "Entering the program", core = "Required courses",
  supporting = "Supporting coursework", electives = "Choices and electives",
  general_education = "University and college requirements", minor = "Concentration or minor",
  completion = "Overall completion rules", requisites = "Course prerequisites and corequisites")
CEDAR_DEGREE_OPERATORS <- c("all", "choose_n", "course", "credits", "condition", "none",
                           "prior", "concurrent", "prior_or_concurrent")

.DEGREE_COURSE_CODE_PATTERN <- "^[A-Z]+ [0-9]+[A-Z]*$"
.DEGREE_ID_PATTERN <- "^[a-z][a-z0-9_]*$"

#' Split a pipe-delimited id list from a roadmap file; a blank field means none
degree_split_ids <- function(ids) {
  if (!nzchar(ids)) return(character())
  strsplit(ids, "|", fixed = TRUE)[[1]]
}

#' Validate the catalog boundary before any consumer reads it
validate_degree_catalog <- function(catalog) {
  tables <- c(catalogs = "degree_catalogs", rules = "degree_rules",
              courses = "degree_rule_courses", evidence = "degree_catalog_evidence")
  for (table in names(tables)) {
    if (is.null(catalog[[table]])) stop("[degree_catalog.R] Degree catalog needs ", table)
  }
  for (table in names(tables)) {
    missing <- setdiff(CEDAR_CONFIG_FILE_SPECS[[tables[[table]]]], names(catalog[[table]]))
    if (length(missing)) {
      stop("[degree_catalog.R] Degree ", table, " missing columns: ", paste(missing, collapse = ", "))
    }
    if (anyNA(catalog[[table]])) {
      stop("[degree_catalog.R] Degree ", table, " has NA fields; use blanks for optional values")
    }
  }
  .validate_degree_catalogs(catalog$catalogs)
  .validate_degree_rules(catalog$rules, catalog$catalogs)
  .validate_degree_rule_courses(catalog$courses, catalog$rules)
  .validate_degree_evidence(catalog$evidence, catalog$catalogs)
  catalog
}

.validate_degree_catalogs <- function(catalogs) {
  if (length(unique(catalogs$catalog_year)) > 1L) {
    stop("[degree_catalog.R] Active degree catalog must contain one year")
  }
  if (anyDuplicated(catalogs$catalog_id) || any(!nzchar(catalogs$catalog_id))) {
    stop("[degree_catalog.R] Duplicate or blank catalog_id")
  }
  if (any(!catalogs$coverage %in% c("excerpt", "complete"))) stop("[degree_catalog.R] Invalid degree coverage")
  if (any(!grepl("^[0-9]{4}-[0-9]{4}$", catalogs$catalog_year))) stop("[degree_catalog.R] Invalid catalog_year")
  if (any(!nzchar(catalogs$source_url)) || any(!nzchar(catalogs$program_name))) {
    stop("[degree_catalog.R] Catalog needs source and program name")
  }
}

.validate_degree_rules <- function(rules, catalogs) {
  if (anyDuplicated(rules$rule_id) || any(!nzchar(rules$rule_id))) {
    stop("[degree_catalog.R] Duplicate or blank rule_id")
  }
  if (any(!rules$catalog_id %in% catalogs$catalog_id)) stop("[degree_catalog.R] Rule references unknown catalog")
  if (any(!rules$phase %in% CEDAR_DEGREE_PHASES) || any(!rules$area %in% CEDAR_DEGREE_AREAS)) {
    stop("[degree_catalog.R] Invalid rule phase or area")
  }
  if (any(!rules$operator %in% CEDAR_DEGREE_OPERATORS)) stop("[degree_catalog.R] Invalid degree operator")
  if (any(!rules$review_status %in% c("draft", "verified", "conflict"))) {
    stop("[degree_catalog.R] Invalid rule review_status")
  }

  parent <- match(rules$parent_id, rules$rule_id)
  has_parent <- nzchar(rules$parent_id)
  if (any(has_parent & is.na(parent))) stop("[degree_catalog.R] Rule references unknown parent")
  child <- which(has_parent)
  for (field in c("catalog_id", "phase", "area", "target_course")) {
    if (any(rules[[field]][child] != rules[[field]][parent[child]])) {
      stop("[degree_catalog.R] Rule parent crosses catalog or scope")
    }
  }
  for (rule_id in rules$rule_id) {
    seen <- character()
    at <- rule_id
    while (nzchar(at)) {
      if (at %in% seen) stop("[degree_catalog.R] Cycle in degree rules: ", rule_id)
      seen <- c(seen, at)
      at <- rules$parent_id[match(at, rules$rule_id)]
    }
  }

  minimum <- suppressWarnings(as.numeric(rules$minimum))
  needs_minimum <- rules$operator %in% c("choose_n", "credits")
  if (any(needs_minimum & (!is.finite(minimum) | minimum <= 0))) {
    stop("[degree_catalog.R] Rule needs positive minimum")
  }
  for (i in which(rules$operator %in% c("all", "choose_n"))) {
    n_children <- sum(rules$parent_id == rules$rule_id[i])
    choose_n <- rules$operator[i] == "choose_n"
    if (n_children == 0 || (choose_n && (minimum[i] != floor(minimum[i]) || minimum[i] > n_children))) {
      stop("[degree_catalog.R] Invalid choice group: ", rules$rule_id[i])
    }
  }
  groups <- rules$rule_id[rules$operator %in% c("all", "choose_n")]
  if (any(nzchar(rules$parent_id) & !rules$parent_id %in% groups)) {
    stop("[degree_catalog.R] Only groups may have children")
  }
  requisite <- rules$phase %in% c("prerequisite", "corequisite")
  if (any(requisite & !nzchar(rules$target_course))) stop("[degree_catalog.R] Requisite needs target_course")
}

.validate_degree_rule_courses <- function(courses, rules) {
  if (any(!courses$rule_id %in% rules$rule_id)) stop("[degree_catalog.R] Course references unknown rule")
  if (anyDuplicated(courses$rule_id)) stop("[degree_catalog.R] Each course leaf must have one course")
  leaves <- rules$rule_id[rules$operator %in% c("course", "prior", "concurrent", "prior_or_concurrent")]
  if (!setequal(courses$rule_id, leaves)) stop("[degree_catalog.R] Course leaves and course rows disagree")
  if (any(!nzchar(courses$subject_course))) stop("[degree_catalog.R] Blank catalog course")
  credits <- suppressWarnings(as.numeric(courses$credits))
  if (any(!is.finite(credits) | credits <= 0)) stop("[degree_catalog.R] Invalid catalog course credits")
}

.validate_degree_evidence <- function(evidence, catalogs) {
  if (anyDuplicated(evidence$evidence_id) || any(!nzchar(evidence$evidence_id))) {
    stop("[degree_catalog.R] Duplicate or blank catalog evidence")
  }
  if (any(!evidence$catalog_year %in% catalogs$catalog_year) ||
      any(!evidence$source_type %in% c("program", "course"))) {
    stop("[degree_catalog.R] Invalid evidence year or source type")
  }
  if (any(!evidence$review_status %in% c("transcribed", "reviewed", "conflict")) ||
      any(!grepl("^https://", evidence$source_url)) || any(!nzchar(evidence$section)) ||
      any(!nzchar(evidence$quote)) || any(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", evidence$retrieved_on))) {
    stop("[degree_catalog.R] Invalid catalog evidence citation")
  }
}

validate_pathway_subject_groups <- function(groups) {
  if (!all(CEDAR_CONFIG_FILE_SPECS$pathway_subject_groups %in% names(groups))) {
    stop("[degree_catalog.R] Invalid pathway grouping columns")
  }
  if (anyNA(groups) || any(!nzchar(as.matrix(groups)))) stop("[degree_catalog.R] Blank pathway grouping field")
  if (anyDuplicated(groups$subject_code)) stop("[degree_catalog.R] Subject has multiple pathway groups")
  labels_per_group <- vapply(split(groups$group_label, groups$group_id),
                             function(labels) length(unique(labels)), integer(1))
  if (any(labels_per_group != 1L)) stop("[degree_catalog.R] Inconsistent pathway group label")
  groups
}

#' Read and validate an institution's degree catalog files
read_degree_catalog <- function(dir = cedar_institution_dir()) {
  validate_degree_catalog(list(
    catalogs = read_institution_file("degree_catalogs", dir),
    rules = read_institution_file("degree_rules", dir),
    courses = read_institution_file("degree_rule_courses", dir),
    evidence = read_institution_file("degree_catalog_evidence", dir)
  ))
}

CEDAR_DEGREE_CATALOG <- read_degree_catalog()
CEDAR_PATHWAY_SUBJECT_GROUPS <- validate_pathway_subject_groups(read_institution_file("pathway_subject_groups"))

#' Node ids a program's roadmap can show
#'
#' Shared nodes belong to a program only when one of its entry routes uses them.
#' A statistics route must not acquire the calculus sequence (or its citations).
degree_roadmap_node_ids <- function(roadmaps, catalog_id) {
  routes <- c(roadmaps$math_routes$node_ids[roadmaps$math_routes$catalog_id == catalog_id],
              roadmaps$starts$node_ids[roadmaps$starts$track == "english"])
  route_ids <- unlist(lapply(routes, degree_split_ids), use.names = FALSE)
  unique(c(roadmaps$nodes$node_id[roadmaps$nodes$catalog_id == catalog_id], route_ids))
}

#' Validate authored planning templates separately from requirement truth
#'
#' Checks run in a fixed order, and each failure names its rule, so a
#' perturbed file always reports the same problem.
validate_degree_roadmaps <- function(roadmaps, catalog) {
  for (table in c("nodes", "links", "starts", "math_routes", "conditions", "basis", "plans", "courses", "options")) {
    rows <- roadmaps[[table]]
    if (is.null(rows) || !all(CEDAR_CONFIG_FILE_SPECS[[paste0("degree_roadmap_", table)]] %in% names(rows))) {
      stop("[degree_catalog.R] Invalid roadmap ", table, " columns")
    }
    if (anyNA(rows)) stop("[degree_catalog.R] Roadmap ", table, " contains NA")
  }
  if (any(!roadmaps$nodes$course_level %in% c("lower", "upper"))) {
    stop("[degree_catalog.R] Invalid roadmap course level")
  }
  .validate_roadmap_options(roadmaps, catalog)
  .validate_roadmap_components(roadmaps)
  .validate_roadmap_nodes(roadmaps$nodes, catalog)
  .validate_roadmap_links(roadmaps$links, roadmaps$nodes, catalog)
  .validate_roadmap_starts(roadmaps, catalog)
  .validate_roadmap_programs(roadmaps, catalog)
  .validate_roadmap_conditions(roadmaps, catalog)
  .validate_roadmap_plans(roadmaps$plans, catalog)
  .validate_roadmap_basis(roadmaps, catalog)
  roadmaps
}

# Enumerated course sets ("choose N of these"): each option's credits, level
# and citations must support the slot the plan reserves for it.
.validate_roadmap_options <- function(roadmaps, catalog) {
  nodes <- roadmaps$nodes
  options <- roadmaps$options
  option_key <- paste(options$catalog_id, options$node_id)
  node_key <- paste(nodes$catalog_id, nodes$node_id)
  if (anyDuplicated(paste(option_key, options$option_id, options$subject_course)) ||
      any(!grepl(.DEGREE_ID_PATTERN, options$option_id)) || any(!option_key %in% node_key) ||
      any(!grepl(.DEGREE_COURSE_CODE_PATTERN, options$subject_course)) ||
      any(!nzchar(options$course_title)) || any(!grepl("^https://", options$source_url))) {
    stop("[degree_catalog.R] Invalid roadmap option course")
  }
  for (key in unique(option_key)) {
    choices <- options[option_key == key, ]
    node <- nodes[match(key, node_key), ]
    .validate_roadmap_option_set(choices, node)
    .validate_roadmap_option_evidence(choices, node, roadmaps, catalog)
  }
}

.validate_roadmap_option_set <- function(choices, node) {
  invalid <- "[degree_catalog.R] Invalid roadmap option set or planning credits"
  minimum <- suppressWarnings(as.numeric(unique(choices$minimum)))
  low <- suppressWarnings(as.numeric(choices$credits_min))
  high <- suppressWarnings(as.numeric(choices$credits_max))
  planned <- suppressWarnings(as.numeric(node$credits))
  # A lecture/lab option costs the sum of its components. Counting each row
  # as an alternative would let a one-credit lab satisfy a four-credit slot.
  option_low <- tapply(low, choices$option_id, sum)
  option_high <- tapply(high, choices$option_id, sum)
  if (node$kind != "choice" || node$bundle != "0" || length(minimum) != 1L || !is.finite(minimum) ||
      minimum < 1 || minimum != floor(minimum) || minimum > length(option_low)) stop(invalid)
  if (any(!is.finite(low) | !is.finite(high) | low <= 0 | high < low) || !is.finite(planned) ||
      planned < sum(sort(option_low)[seq_len(minimum)]) ||
      planned > sum(sort(option_high, decreasing = TRUE)[seq_len(minimum)])) stop(invalid)
  levels <- course_level_from_number(choices$subject_course)
  if (anyNA(levels) || any(!levels %in% c("lower", "upper")) ||
      (all(levels == "upper") && node$course_level != "upper")) stop(invalid)
}

.validate_roadmap_option_evidence <- function(choices, node, roadmaps, catalog) {
  evidence <- catalog$evidence
  program <- catalog$catalogs[catalog$catalogs$catalog_id == node$catalog_id, ]
  basis <- roadmaps$basis[roadmaps$basis$catalog_id == node$catalog_id &
                            roadmaps$basis$node_id == node$node_id, ]
  requirement <- evidence[match(choices$evidence_id, evidence$evidence_id), ]
  if (nrow(basis) != 1L || anyNA(requirement$evidence_id) || any(requirement$source_type != "program") ||
      any(requirement$catalog_year != program$catalog_year) ||
      any(requirement$source_url != program$source_url) || any(choices$evidence_id != basis$evidence_id)) {
    stop("[degree_catalog.R] Options need matching program requirement evidence")
  }
  cited <- which(nzchar(choices$requisite_evidence_id))
  requisite <- evidence[match(choices$requisite_evidence_id[cited], evidence$evidence_id), ]
  if (anyNA(requisite$evidence_id) || any(requisite$source_type != "course") ||
      any(requisite$catalog_year != program$catalog_year) ||
      any(requisite$source_url != choices$source_url[cited])) {
    stop("[degree_catalog.R] Option prerequisite needs matching course evidence")
  }
  # A selected example's prerequisites cannot be applied to every alternative.
  links <- roadmaps$links
  conditions <- roadmaps$conditions
  if (any(links$catalog_id == node$catalog_id & (links$from == node$node_id | links$to == node$node_id)) ||
      any(conditions$catalog_id == node$catalog_id & conditions$node_id == node$node_id)) {
    stop("[degree_catalog.R] Unresolved option set cannot inherit a particular course's prerequisites")
  }
}

# The exact course codes behind each tile: none for an unresolved choice, two
# for a lecture/lab bundle, otherwise the tile's own code.
.validate_roadmap_components <- function(roadmaps) {
  nodes <- roadmaps$nodes
  components <- roadmaps$courses
  if (anyDuplicated(components) || any(!grepl(.DEGREE_COURSE_CODE_PATTERN, components$subject_course)) ||
      any(!paste(components$catalog_id, components$node_id) %in% paste(nodes$catalog_id, nodes$node_id))) {
    stop("[degree_catalog.R] Invalid roadmap course components")
  }
  for (i in seq_len(nrow(nodes))) {
    codes <- components$subject_course[components$catalog_id == nodes$catalog_id[i] &
                                         components$node_id == nodes$node_id[i]]
    cohort <- nodes$kind[i] == "cohort"
    expected <- if (cohort) length(codes) else if (nodes$kind[i] == "choice") 0L else if (nodes$bundle[i] == "1") 2L else 1L
    if (cohort && (expected < 2L || nodes$bundle[i] != "1")) stop("[degree_catalog.R] Required course blocks need at least two components")
    if (length(codes) != expected || (expected == 1L && codes != nodes$code[i])) {
      stop("[degree_catalog.R] Roadmap course components disagree with node: ", nodes$node_id[i])
    }
    levels <- course_level_from_number(codes)
    level_ok <- if (cohort) nodes$course_level[i] == if ("upper" %in% levels) "upper" else "lower" else all(levels == nodes$course_level[i])
    if (anyNA(levels) || !level_ok) {
      stop("[degree_catalog.R] Roadmap course level disagrees with components: ", nodes$node_id[i])
    }
  }
}

.validate_roadmap_nodes <- function(nodes, catalog) {
  if (anyDuplicated(paste(nodes$catalog_id, nodes$node_id)) || any(!nzchar(nodes$node_id))) {
    stop("[degree_catalog.R] Duplicate or blank roadmap node")
  }
  if (any(!nodes$catalog_id %in% c("*", catalog$catalogs$catalog_id))) {
    stop("[degree_catalog.R] Unknown roadmap catalog")
  }
  if (any(!nodes$track %in% c("main", "math", "english")) ||
      any(!nodes$kind %in% c("major", "support", "writing", "choice", "preparation", "cohort"))) {
    stop("[degree_catalog.R] Invalid roadmap track or kind")
  }
  if (any(!nodes$bundle %in% c("0", "1"))) stop("[degree_catalog.R] Invalid roadmap bundle")
  if (any(!grepl(.DEGREE_ID_PATTERN, nodes$row_group))) stop("[degree_catalog.R] Invalid roadmap row group")
  credits <- suppressWarnings(as.numeric(nodes$credits))
  semester <- suppressWarnings(as.numeric(nodes$semester))
  if (any(!is.finite(credits) | credits <= 0) ||
      any(!is.finite(semester) | semester < 1 | semester != floor(semester))) {
    stop("[degree_catalog.R] Invalid roadmap credits or semester")
  }
  if (any(!nzchar(nodes$source_url))) stop("[degree_catalog.R] Roadmap needs sources")
}

.validate_roadmap_links <- function(links, nodes, catalog) {
  if (any(!links$catalog_id %in% c("*", catalog$catalogs$catalog_id))) {
    stop("[degree_catalog.R] Unknown roadmap catalog")
  }
  if (any(!nzchar(links$source_url))) stop("[degree_catalog.R] Roadmap needs sources")
  if (any(!links$timing %in% c("before", "before_or_same"))) stop("[degree_catalog.R] Invalid roadmap timing")
  if (anyDuplicated(paste(links$catalog_id, links$from, links$to))) stop("[degree_catalog.R] Duplicate roadmap link")
  for (catalog_id in unique(c(nodes$catalog_id, links$catalog_id))) {
    ids <- nodes$node_id[nodes$catalog_id %in% c("*", catalog_id)]
    edges <- links[links$catalog_id %in% c("*", catalog_id), ]
    if (anyDuplicated(ids) || any(!edges$from %in% ids) || any(!edges$to %in% ids)) {
      stop("[degree_catalog.R] Unknown or ambiguous roadmap endpoint")
    }
    # Even a before-or-same cycle is rejected; same-term lecture/lab pairs are one bundle.
    unvisited <- ids
    while (length(unvisited)) {
      ready <- setdiff(unvisited, edges$to[edges$from %in% unvisited])
      if (!length(ready)) stop("[degree_catalog.R] Cycle in roadmap links")
      unvisited <- setdiff(unvisited, ready)
    }
  }
}

.validate_roadmap_starts <- function(roadmaps, catalog) {
  nodes <- roadmaps$nodes
  starts <- roadmaps$starts
  if (any(!starts$track %in% c("math", "english")) || anyDuplicated(paste(starts$track, starts$start_id))) {
    stop("[degree_catalog.R] Invalid roadmap starting point")
  }
  completed <- suppressWarnings(as.numeric(starts$completed_degree_credits))
  if (any(!is.finite(completed) | completed < 0)) stop("[degree_catalog.R] Invalid completed starting credits")
  for (i in seq_len(nrow(starts))) {
    ids <- degree_split_ids(starts$node_ids[i])
    shared <- nodes$node_id[nodes$catalog_id == "*" & nodes$track == starts$track[i]]
    if (anyDuplicated(ids) || any(!ids %in% shared)) stop("[degree_catalog.R] Unknown roadmap starting course")
  }
  math_routes <- roadmaps$math_routes
  math_starts <- starts$start_id[starts$track == "math"]
  if (any(!math_routes$catalog_id %in% catalog$catalogs$catalog_id) ||
      any(!math_routes$start_id %in% math_starts) || any(!nzchar(math_routes$label)) ||
      anyDuplicated(paste(math_routes$catalog_id, math_routes$start_id))) {
    stop("[degree_catalog.R] Invalid program math route")
  }
  shared_math <- nodes$node_id[nodes$catalog_id == "*" & nodes$track == "math"]
  for (i in seq_len(nrow(math_routes))) {
    ids <- degree_split_ids(math_routes$node_ids[i])
    if (!length(ids) || anyDuplicated(ids) || any(!ids %in% shared_math)) {
      stop("[degree_catalog.R] Unknown program math route course")
    }
  }
}

# Every catalog has a roadmap, both entry tracks, a math route for every
# placement, and links whose endpoints its own routes can show.
.validate_roadmap_programs <- function(roadmaps, catalog) {
  math_routes <- roadmaps$math_routes
  math_starts <- roadmaps$starts$start_id[roadmaps$starts$track == "math"]
  for (catalog_id in catalog$catalogs$catalog_id) {
    if (!any(roadmaps$nodes$catalog_id == catalog_id)) stop("[degree_catalog.R] Catalog has no roadmap: ", catalog_id)
    if (!all(c("math", "english") %in% roadmaps$starts$track)) {
      stop("[degree_catalog.R] Roadmap starting points missing")
    }
    if (!setequal(math_routes$start_id[math_routes$catalog_id == catalog_id], math_starts)) {
      stop("[degree_catalog.R] Program math starting routes missing: ", catalog_id)
    }
    ids <- degree_roadmap_node_ids(roadmaps, catalog_id)
    edges <- roadmaps$links[roadmaps$links$catalog_id == catalog_id, ]
    if (any(!edges$from %in% ids) || any(!edges$to %in% ids)) {
      stop("[degree_catalog.R] Program route has unavailable endpoint")
    }
  }
}

# Course-count and permission conditions: a pool and minimum, never named edges.
.validate_roadmap_conditions <- function(roadmaps, catalog) {
  conditions <- roadmaps$conditions
  nodes <- roadmaps$nodes
  evidence <- catalog$evidence
  if (anyDuplicated(conditions$condition_id) || any(!nzchar(conditions$condition_id)) ||
      any(!conditions$catalog_id %in% catalog$catalogs$catalog_id) ||
      any(!conditions$kind %in% c("course_count", "permission")) || any(!nzchar(conditions$label))) {
    stop("[degree_catalog.R] Invalid roadmap condition")
  }
  for (i in seq_len(nrow(conditions))) {
    condition <- conditions[i, ]
    ids <- degree_roadmap_node_ids(roadmaps, condition$catalog_id)
    if (!condition$node_id %in% ids) stop("[degree_catalog.R] Unknown condition target")
    pool <- degree_split_ids(condition$eligible_node_ids)
    if (condition$kind == "course_count") {
      minimum <- suppressWarnings(as.numeric(condition$minimum))
      if (!is.finite(minimum) || minimum < 1 || minimum != floor(minimum) ||
          anyDuplicated(pool) || any(!pool %in% ids) || condition$node_id %in% pool ||
          length(pool) < minimum) {
        stop("[degree_catalog.R] Invalid course-count condition pool or minimum")
      }
      members <- nodes[nodes$catalog_id %in% c("*", condition$catalog_id) & nodes$node_id %in% pool, ]
      if (any(members$bundle == "1")) stop("[degree_catalog.R] Course-count condition pools need single-course slots")
    } else if (length(pool) || nzchar(condition$minimum)) {
      stop("[degree_catalog.R] Permission condition cannot count courses")
    }
    proof <- evidence[match(condition$evidence_id, evidence$evidence_id), ]
    catalog_year <- catalog$catalogs$catalog_year[match(condition$catalog_id, catalog$catalogs$catalog_id)]
    if (is.na(proof$evidence_id) || proof$source_type != "course" || proof$catalog_year != catalog_year) {
      stop("[degree_catalog.R] Condition needs matching course evidence")
    }
    target <- nodes[nodes$catalog_id %in% c("*", condition$catalog_id) & nodes$node_id == condition$node_id, ]
    if (proof$source_url != target$source_url) {
      stop("[degree_catalog.R] Condition evidence must cite its target course")
    }
  }
}

.validate_roadmap_plans <- function(plans, catalog) {
  if (!setequal(plans$catalog_id, catalog$catalogs$catalog_id) || anyDuplicated(plans$catalog_id)) {
    stop("[degree_catalog.R] Roadmap needs one plan per catalog")
  }
  for (column in c("degree_credit_target", "normal_load", "max_load", "baseline_semesters",
                   "upper_level_from_semester", "allowance_slot_credits")) {
    value <- suppressWarnings(as.numeric(plans[[column]]))
    if (any(!is.finite(value) | value <= 0 | value != floor(value))) {
      stop("[degree_catalog.R] Invalid roadmap plan ", column)
    }
  }
  if (any(as.numeric(plans$normal_load) > as.numeric(plans$max_load))) {
    stop("[degree_catalog.R] Normal load exceeds maximum")
  }
  if (any(as.numeric(plans$allowance_slot_credits) > as.numeric(plans$max_load)) ||
      any(!grepl("^https://", plans$gen_ed_source_url))) {
    stop("[degree_catalog.R] Invalid allowance planning policy")
  }
  if (any(as.numeric(plans$upper_level_from_semester) < 2)) {
    stop("[degree_catalog.R] Upper-level timing needs an early-coursework stage")
  }
}

# Why each tile is present: a degree requirement cites the program page, a
# preparation course cites the prerequisite on the course page it unlocks.
.validate_roadmap_basis <- function(roadmaps, catalog) {
  basis <- roadmaps$basis
  plans <- roadmaps$plans
  links <- roadmaps$links
  evidence <- catalog$evidence
  if (anyDuplicated(paste(basis$catalog_id, basis$node_id)) || any(!basis$catalog_id %in% plans$catalog_id) ||
      any(!basis$basis %in% c("degree", "prerequisite", "general"))) {
    stop("[degree_catalog.R] Invalid roadmap basis")
  }
  if (any(!c(links$evidence_id, basis$evidence_id, plans$evidence_id) %in% evidence$evidence_id)) {
    stop("[degree_catalog.R] Unknown roadmap evidence")
  }
  link_evidence <- evidence[match(links$evidence_id, evidence$evidence_id), ]
  if (any(link_evidence$source_type != "course") || any(links$source_url != link_evidence$source_url)) {
    stop("[degree_catalog.R] Link needs matching course evidence")
  }
  for (catalog_id in plans$catalog_id) {
    shown <- roadmaps$nodes[roadmaps$nodes$catalog_id %in% c("*", catalog_id) &
                              roadmaps$nodes$node_id %in% degree_roadmap_node_ids(roadmaps, catalog_id), ]
    program_basis <- basis[basis$catalog_id == catalog_id, ]
    if (!setequal(shown$node_id, program_basis$node_id)) {
      stop("[degree_catalog.R] Roadmap node needs requirement evidence: ", catalog_id)
    }
    plan <- plans[plans$catalog_id == catalog_id, ]
    program <- catalog$catalogs[catalog$catalogs$catalog_id == catalog_id, ]
    cited <- evidence[match(c(program_basis$evidence_id, plan$evidence_id), evidence$evidence_id), ]
    linked <- evidence[match(links$evidence_id[links$catalog_id %in% c("*", catalog_id)], evidence$evidence_id), ]
    if (any(c(cited$catalog_year, linked$catalog_year) != program$catalog_year)) {
      stop("[degree_catalog.R] Roadmap evidence crosses catalog years")
    }
    if (any(as.numeric(shown$credits) > as.numeric(plan$max_load))) {
      stop("[degree_catalog.R] Course bundle exceeds maximum load")
    }
    degree <- program_basis$basis %in% c("degree", "general")
    degree_evidence <- evidence[match(program_basis$evidence_id[degree], evidence$evidence_id), ]
    if (any(degree_evidence$source_type != "program") || any(degree_evidence$source_url != program$source_url)) {
      stop("[degree_catalog.R] Degree basis needs the program page")
    }
    preparation <- evidence$source_type[match(program_basis$evidence_id[!degree], evidence$evidence_id)]
    if (any(preparation != "course")) stop("[degree_catalog.R] Preparation needs course evidence")
  }
}

#' Read an institution's roadmap files and validate them against its catalog
read_degree_roadmaps <- function(catalog, dir = cedar_institution_dir()) {
  tables <- c("nodes", "links", "starts", "math_routes", "conditions", "basis", "plans", "courses", "options")
  roadmaps <- lapply(stats::setNames(tables, tables), function(table) {
    read_institution_file(paste0("degree_roadmap_", table), dir)
  })
  validate_degree_roadmaps(roadmaps, catalog)
}

CEDAR_DEGREE_ROADMAPS <- read_degree_roadmaps(CEDAR_DEGREE_CATALOG)
