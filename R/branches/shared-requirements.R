# Versioned University/Gen Ed/college rules and illustrative plan coverage.
# This does not evaluate a student's transcript or add overlapping credits.

shared_requirement_nodes <- function(rules, inherited_refs = NULL, depth = 0L) {
  unlist(lapply(rules, function(rule) {
    if (is.null(rule$source_refs)) rule$source_refs <- inherited_refs
    rule$depth <- depth
    c(list(rule), shared_requirement_nodes(rule$children, rule$source_refs, depth + 1L))
  }), recursive = FALSE)
}

#' Read and validate the shared reference bundle; optionally verify saved bytes
#' Source verification is explicit so a repository-only reader can inspect the
#' rules without pretending that a missing local capture has been checked.
read_shared_requirement_bundle <- function(directory, source_directory = NULL) {
  fail <- function(...) stop("[shared-requirements.R] ", ..., call. = FALSE)
  bundle <- read_source_json(file.path(directory, "bundle.json"))
  provenance <- read_source_json(file.path(directory, "sources.json"))
  if (!identical(bundle$schema_version, "1.0.0") ||
      !identical(provenance$schema_version, "1.0.0") ||
      !identical(bundle$catalog_id, provenance$catalog_id) ||
      !identical(bundle$catalog_year, provenance$catalog_year) ||
      !grepl("^[0-9]{4}-[0-9]{4}$", bundle$catalog_year)) fail("Invalid bundle edition")
  files <- unlist(bundle$rule_files, use.names = FALSE)
  if (!length(files) || anyDuplicated(files) ||
      any(!grepl("^([a-z0-9-]+/)*[a-z0-9-]+[.]json$", files))) fail("Invalid rule file paths")
  sets <- lapply(files, function(file) read_source_json(file.path(directory, file)))
  ids <- vapply(sets, function(x) x$rule_set_id, character(1))
  if (anyDuplicated(ids)) fail("Duplicate rule-set IDs")
  names(sets) <- ids
  sources <- provenance$sources
  if (!length(sources) || anyDuplicated(names(sources))) fail("Invalid sources")
  for (source in sources) {
    if (!grepl("^[a-f0-9]{64}$", source$sha256) ||
        !grepl("^https://", source$url) || !grepl("^https://", source$catalog_url)) fail("Invalid source receipt")
  }
  documents <- if (!is.null(source_directory)) lapply(sources, function(source)
    read_captured_source(source, source_directory, json = !identical(source$kind, "landing"))) else NULL
  seen <- character()
  areas <- character()
  for (set in sets) {
    if (!identical(set$schema_version, bundle$schema_version) ||
        !identical(set$catalog_year, bundle$catalog_year) ||
        !identical(set$catalog_id, bundle$catalog_id)) fail("Rule-set edition mismatch")
    if (!set$scope$level %in% c("university", "college") ||
        (set$scope$level == "college" && !nzchar(set$scope$college_code))) fail("Invalid scope")
    if (!set$coverage %in% c("selected_sections", "requirements_and_enumerated_course_memberships",
                             "not_located_on_checked_overview")) fail("Coverage must be explicit")
    if (!length(set$rules) && (!identical(set$coverage, "not_located_on_checked_overview") ||
        !length(set$checked_source_ids) || any(!unlist(set$checked_source_ids) %in% names(sources)))) {
      fail("An empty rule set must document its source coverage")
    }
    nodes <- shared_requirement_nodes(set$rules)
    for (rule in nodes) {
      if (!grepl("^[a-z][a-z0-9._-]+$", rule$rule_id) || rule$rule_id %in% seen) fail("Duplicate/invalid rule ID")
      seen <- c(seen, rule$rule_id)
      if (!nzchar(rule$statement) || !nzchar(rule$label) ||
          !rule$operator %in% c("all", "choose_n", "credits", "course", "condition", "none")) fail("Invalid readable rule")
      for (field in c("minimum", "maximum", "maximum_exclusive", "minimum_gpa", "minimum_fraction", "exception_fraction")) {
        value <- rule[[field]]
        if (!is.null(value) && (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 0)) fail("Invalid numeric threshold")
      }
      # Exact lookup: a conditional minimum_unique_per_major is not minimum.
      minimum <- rule[["minimum"]]
      maximum <- rule[["maximum"]]
      if (rule$operator == "credits" && is.null(minimum) && is.null(maximum)) fail("Credit rule needs a threshold")
      if (!is.null(minimum) && !is.null(maximum) && minimum > maximum) fail("Minimum exceeds maximum")
      if (rule$operator == "all" && !length(rule$children)) fail("All group needs children")
      if (rule$operator == "choose_n" && (is.null(minimum) || minimum < 1 ||
          minimum != floor(minimum) || minimum > length(rule$children))) fail("Invalid alternative set")
      if (!is.null(rule$rule_set_ref) && !rule$rule_set_ref %in% ids) fail("Unknown referenced rule set")
      if (!is.null(rule$area)) areas <- c(areas, rule$area)
      if (!is.null(rule$planning_method) && !rule$planning_method %in%
          c("listed_course", "related_science", "distinct_areas")) fail("Unknown planning method")
      if (identical(rule$planning_method, "distinct_areas")) {
        count <- rule$planning_course_count
        if (!is.numeric(count) || length(count) != 1L || !is.finite(count) || count < 1 ||
            count != floor(count) || is.null(minimum) || minimum <= 0) fail("Invalid flexible planning count")
      }
      if (length(rule$planning_parts)) {
        for (part in rule$planning_parts) {
          if (!nzchar(part$label) || !is.numeric(part$minimum) || part$minimum <= 0 ||
              !length(part$subject_courses)) fail("Invalid planning part")
        }
        if (sum(vapply(rule$planning_parts, function(x) x$minimum, numeric(1))) != minimum)
          fail("Planning parts must preserve the area total")
      }
      if (!length(rule$source_refs)) fail("Rule needs source evidence")
      for (ref in rule$source_refs) {
        if (!ref$source_id %in% names(sources) || !startsWith(ref$pointer, "/") || !nzchar(ref$anchor)) fail("Invalid source reference")
        if (!is.null(documents)) {
          passage <- source_json_pointer(documents[[ref$source_id]], ref$pointer)
          if (!is.character(passage) || length(passage) != 1L || !grepl(ref$anchor, passage, fixed = TRUE)) fail("Source anchor does not match saved evidence")
        }
      }
    }
    local_ids <- vapply(nodes, function(x) x$rule_id, character(1))
    if (!is.null(set$planning)) {
      prep <- set$planning$preparation_rule_id
      if (is.null(prep) || !prep %in% local_ids ||
          sum(vapply(nodes, function(x) identical(x$planning_method, "distinct_areas"), logical(1))) != 1L ||
          sum(vapply(nodes, function(x) length(x$planning_parts) > 0L, logical(1))) != 1L)
        fail("Invalid shared planning references")
    }
    for (attention in set$attention) {
      if (!nzchar(attention$statement) || any(!unlist(attention$rule_ids) %in% local_ids)) fail("Invalid attention case")
    }
  }
  profiles <- bundle$profiles
  profile_ids <- vapply(profiles, function(x) x$catalog_id, character(1))
  if (anyDuplicated(profile_ids)) fail("Duplicate program profile")
  for (profile in profiles) {
    refs <- unlist(profile$rule_set_ids)
    if (anyDuplicated(refs) || any(!refs %in% ids)) fail("Invalid profile references")
    colleges <- Filter(function(set) set$scope$level == "college", sets[refs])
    if (length(colleges) != 1L || !identical(colleges[[1]]$scope$college_code, profile$college_code)) fail("Profile awarding college mismatch")
  }
  membership_file <- file.path(directory, "gen-ed-course-memberships.csv")
  memberships <- read.csv(membership_file, colClasses = "character", check.names = FALSE)
  required <- c("area", "subject_course", "credits", "course_url", "source_id", "pointer")
  if (!identical(names(memberships), required) || anyNA(memberships) ||
      anyDuplicated(memberships[c("area", "subject_course")]) ||
      any(!memberships$area %in% areas) || any(!memberships$source_id %in% names(sources)) ||
      any(!grepl("^[A-Z]+ [0-9]+[A-Z]*$", memberships$subject_course)) ||
      any(!is.finite(suppressWarnings(as.numeric(memberships$credits)))) ||
      any(as.numeric(memberships$credits) <= 0)) fail("Invalid Gen Ed memberships")
  if (!is.null(documents)) for (i in seq_len(nrow(memberships))) {
    passage <- source_json_pointer(documents[[memberships$source_id[i]]], memberships$pointer[i])
    course_key <- sub(" ", "", memberships$subject_course[i], fixed = TRUE)
    if (!grepl(course_key, passage, fixed = TRUE) ||
        !grepl(sub("^.*#", "#", memberships$course_url[i]), passage, fixed = TRUE)) fail("Course membership not found in saved source")
  }
  list(bundle = bundle, sets = sets, provenance = provenance, memberships = memberships,
       source_bytes_verified = !is.null(source_directory))
}

#' Source-linked, illustrative coverage from the courses already on a roadmap
#' Membership is curricular, not enrollment data (CAMPUS_ROLLUP). A course is
#' consumed once across base/flexible areas; its major credits are never added
#' again. Open choices can advertise potential coverage but cannot satisfy it.
degree_shared_coverage <- function(view, roadmaps, reference) {
  if (is.null(reference)) return(NULL)
  profiles <- Filter(function(x) identical(x$catalog_id, view$catalog$catalog_id), reference$bundle$profiles)
  if (!length(profiles)) return(NULL)
  if (!identical(reference$bundle$catalog_year, view$catalog$catalog_year))
    stop("[shared-requirements.R] Plan and shared rules have different editions")
  sets <- reference$sets[unlist(profiles[[1]]$rule_set_ids)]
  gen <- Filter(function(x) !is.null(x$planning), sets)
  if (length(gen) != 1L) return(NULL)
  gen <- gen[[1]]
  rules <- shared_requirement_nodes(gen$rules)
  names(rules) <- vapply(rules, function(x) x$rule_id, character(1))
  area_rules <- Filter(function(x) identical(x$role, "gen_ed_area"), rules)
  memberships <- reference$memberships
  source_url <- function(rule) reference$provenance$sources[[rule$source_refs[[1]]$source_id]]$catalog_url
  areas <- do.call(rbind, lapply(area_rules, function(rule) data.frame(
    area = rule$area, label = sub("^Area [^:]+: ", "", rule$label),
    minimum = rule[["minimum"]], rule_id = rule$rule_id, source_url = source_url(rule))))
  preparation <- unlist(rules[[gen$planning$preparation_rule_id]]$subject_courses)
  flex <- Filter(function(x) identical(x$planning_method, "distinct_areas"), area_rules)
  if (length(flex) != 1L) stop("[shared-requirements.R] Need one flexible-area rule")
  flex <- flex[[1]]
  flex_unit <- flex[["minimum"]] / flex$planning_course_count
  units <- list()
  add_unit <- function(id, courses, area, credits) {
    units[[length(units) + 1L]] <<- list(node_id = id, courses = courses, area = area, credits = credits)
  }
  components <- roadmaps$courses[roadmaps$courses$catalog_id %in% c("*", view$catalog$catalog_id), ]
  completed <- unlist(gen$planning$completed_courses_by_english_start[[view$starts[["english"]]]])
  selected <- rbind(data.frame(node_id = view$nodes$node_id[view$nodes$kind != "choice"]),
                    data.frame(node_id = if (length(completed)) "already-completed" else character()))
  for (id in selected$node_id) {
    courses <- if (id == "already-completed") completed else components$subject_course[components$node_id == id]
    member <- memberships[memberships$subject_course %in% courses, ]
    for (area in unique(member$area)) {
      rows <- member[member$area == area, ]
      rule <- area_rules[[match(area, vapply(area_rules, function(x) x$area, character(1)))]]
      if (identical(rule$planning_method, "related_science")) {
        # Only the authored lecture/lab bundle or a combined course establishes
        # pairing. Never assemble a science choice from unrelated lab rows.
        if (setequal(courses, rows$subject_course) && sum(as.numeric(rows$credits)) >= rule[["minimum"]])
          add_unit(id, courses, area, sum(as.numeric(rows$credits)))
      } else for (j in seq_len(nrow(rows))) add_unit(id, rows$subject_course[j], area, as.numeric(rows$credits[j]))
    }
    prep <- intersect(courses, preparation)
    # This exception applies to preparation actually on the selected route;
    # a completed-English starting point does not prove prior preparation need.
    if (id != "already-completed" && length(prep)) {
      communication_area <- area_rules[[which(vapply(area_rules, function(x) length(x$planning_parts) > 0L, logical(1)))]]$area
      for (course in prep) add_unit(id, course, communication_area, flex_unit)
    }
  }
  assigned <- data.frame(node_id = character(), area = character(), credits = numeric(), courses = character())
  needs <- data.frame(area = character(), label = character(), credits = numeric(), source_url = character())
  used <- character()
  assign_unit <- function(unit, area, credits) {
    used <<- union(used, unit$courses)
    assigned[nrow(assigned) + 1L, ] <<- list(unit$node_id, area, credits, paste(unit$courses, collapse = " + "))
  }
  for (rule in area_rules) {
    if (identical(rule$planning_method, "distinct_areas")) next
    parts <- rule$planning_parts
    if (!length(parts)) parts <- list(list(label = areas$label[areas$area == rule$area], minimum = rule[["minimum"]]))
    for (part in parts) {
      eligible <- Filter(function(u) u$area == rule$area && !any(u$courses %in% used) &&
        !any(u$courses %in% preparation) && u$credits >= part$minimum &&
        (is.null(part$subject_courses) || all(u$courses %in% unlist(part$subject_courses))), units)
      if (length(eligible)) assign_unit(eligible[[1]], rule$area, part$minimum)
      else needs[nrow(needs) + 1L, ] <- list(rule$area, part$label, part$minimum, source_url(rule))
    }
  }
  flex_areas <- character()
  for (i in seq_len(flex$planning_course_count)) {
    eligible <- Filter(function(u) !any(u$courses %in% used) && !u$area %in% flex_areas && u$credits >= flex_unit, units)
    if (length(eligible)) {
      unit <- eligible[[1]]; assign_unit(unit, flex$area, flex_unit); flex_areas <- c(flex_areas, unit$area)
    } else needs[nrow(needs) + 1L, ] <- list(flex$area, "Flexible Gen Ed choice", flex_unit, source_url(flex))
  }
  areas$planned <- vapply(areas$area, function(area) sum(assigned$credits[assigned$area == area]), numeric(1))
  areas$remaining <- areas$minimum - areas$planned
  # The standard upper-division threshold is context, not an automatic choice
  # of a conditional alternative (language approval, etc.). Mixed blocks cannot
  # be counted wholesale merely because their display level is upper.
  upper_rules <- Filter(function(x) identical(x$planning_metric, "upper_credits"),
    unlist(lapply(sets, function(x) shared_requirement_nodes(x$rules)), recursive = FALSE))
  upper <- NULL
  if (length(upper_rules)) {
    rule <- upper_rules[[1]]
    ids <- vapply(seq_len(nrow(view$nodes)), function(i) {
      node <- view$nodes[i, ]; codes <- components$subject_course[components$node_id == node$node_id]
      node$course_level == "upper" && (node$kind == "choice" ||
        (length(codes) > 0L && all(course_level_from_number(codes) == "upper")))
    }, logical(1))
    planned <- sum(view$nodes$credits[ids])
    upper <- list(minimum = rule[["minimum"]], planned = planned, remaining = max(0, rule[["minimum"]] - planned),
      statement = rule$statement, source_url = source_url(rule))
  }
  option_courses <- roadmaps$options$subject_course[roadmaps$options$catalog_id == view$catalog$catalog_id]
  choice_areas <- unique(memberships$area[memberships$subject_course %in% option_courses])
  list(areas = areas, assigned = assigned, needs = needs, upper = upper, choice_areas = choice_areas,
    memberships = memberships, note = gen$planning$note, flexible_area = flex$area, flexible_areas_used = flex_areas)
}

#' Earmark actual area gaps inside the existing allowance budget, never on top
allocate_shared_degree_slots <- function(view, coverage) {
  budget <- view$terms$other_credits
  slots <- data.frame(node_id = character(), semester = integer(), credits = numeric(), row = integer(),
    area = character(), code = character(), purpose = character(), source_url = character())
  add <- function(i, amount, area = "", code = "Elective / minor", purpose = "elective", url = "") {
    slots[nrow(slots) + 1L, ] <<- list("", view$terms$semester[i], amount, 0L, area, code, purpose, url)
    budget[i] <<- budget[i] - amount
  }
  pending <- if (is.null(coverage)) NULL else coverage$needs
  unplaced <- pending
  if (!is.null(pending)) for (j in seq_len(nrow(pending))) {
    fit <- which(budget >= pending$credits[j])
    if (length(fit)) {
      add(fit[1], pending$credits[j], pending$area[j], paste("Gen Ed ·", pending$label[j]), "gen_ed", pending$source_url[j])
      unplaced <- unplaced[rownames(unplaced) != rownames(pending)[j], ]
    }
  }
  for (i in which(view$terms$other_phase == "foundation" & budget > 0)) while (budget[i] > 0) {
    usual <- as.numeric(view$policy$allowance_slot_credits)
    amount <- if (budget[i] <= usual + 1) budget[i] else usual
    add(i, amount)
  }
  for (semester in unique(slots$semester)) {
    ix <- which(slots$semester == semester)
    slots$node_id[ix] <- paste0("allowance-", semester, "-", seq_along(ix))
    slots$row[ix] <- seq_along(ix)
  }
  old_band <- max(c(0L, view$allowances$row)); new_band <- max(c(0L, slots$row))
  view$nodes$row <- view$nodes$row - old_band + new_band
  view$allowances <- slots
  view$terms$footer_credits <- budget
  view$shared <- coverage
  view$unplaced_gen_ed <- unplaced
  view
}
