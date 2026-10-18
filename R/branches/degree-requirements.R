# Degree Explorer planning: rule outlines, semester scheduling, row layout and
# prerequisite-chain metrics for one selected route.
#
# Planning reads catalog and roadmap metadata only. Nothing here reads a student
# record, infers eligibility or audits a degree. Rules:
# docs/developers/degree-explorer-rules.md; contract:
# docs/developers/degree-requirements.md.

degree_catalog_choices <- function(catalog) {
  stats::setNames(catalog$catalogs$catalog_id,
    paste(catalog$catalogs$degree_label, catalog$catalogs$catalog_year, sep = " · "))
}

degree_math_start_choices <- function(roadmaps, catalog_id) {
  routes <- roadmaps$math_routes[roadmaps$math_routes$catalog_id == catalog_id, ]
  stats::setNames(routes$start_id, routes$label)
}

#' One row per rule; nested alternatives retain their depth and timing language
degree_rule_outline <- function(catalog, catalog_ids) {
  if (!length(catalog_ids) || any(!catalog_ids %in% catalog$catalogs$catalog_id)) {
    stop("[degree-requirements.R] Select known catalog IDs")
  }
  rules <- catalog$rules[catalog$rules$catalog_id %in% catalog_ids, ]
  rules$depth <- vapply(rules$parent_id, function(parent) {
    depth <- 0L
    while (nzchar(parent)) {
      depth <- depth + 1L
      parent <- rules$parent_id[match(parent, rules$rule_id)]
    }
    depth
  }, integer(1), USE.NAMES = FALSE)

  phrases <- c(all = "Take all", choose_n = "Choose at least", course = "Take",
    credits = "Earn at least", condition = "Condition", none = "Not required",
    prior = "Complete before", concurrent = "Take concurrently",
    prior_or_concurrent = "Complete before or take concurrently")
  course <- catalog$courses[match(rules$rule_id, catalog$courses$rule_id), ]
  title <- ifelse(is.na(course$rule_id), rules$label,
    paste0(course$subject_course, " — ", course$course_title, " (", course$credits, " credits)"))
  amount <- ifelse(rules$operator == "choose_n",
    paste0(" ", rules$minimum, ifelse(rules$minimum == "1", " option", " options")),
    ifelse(rules$operator == "credits", paste0(" ", rules$minimum, " credits"), ""))
  target <- ifelse(nzchar(rules$target_course), paste0(" [for ", rules$target_course, "]"), "")
  grade <- ifelse(nzchar(rules$min_grade), paste0("; minimum grade ", rules$min_grade), "")
  detail <- ifelse(nzchar(rules$detail), paste0(". ", rules$detail), "")
  conflict <- ifelse(rules$review_status == "conflict", " [SOURCE CONFLICT]", "")
  rules$text <- paste0(title, target, ": ", unname(phrases[rules$operator]), amount, grade, detail,
                       conflict, recycle0 = TRUE)

  # File order is not assumed to be a pre-order traversal.
  preorder <- function(id) {
    children <- rules$rule_id[rules$parent_id == id]
    c(id, unlist(lapply(children, preorder), use.names = FALSE))
  }
  ordered <- unlist(lapply(rules$rule_id[!nzchar(rules$parent_id)], preorder), use.names = FALSE)
  rules[match(ordered, rules$rule_id), ]
}

#' Classify a course once for descriptive pathways, never as degree fulfillment
attach_pathway_groups <- function(rows, groups) {
  groups <- validate_pathway_subject_groups(groups)
  rows %>%
    mutate(subject_code = sub(" .*", "", subject_course)) %>%
    left_join(groups, by = "subject_code", relationship = "many-to-one") %>%
    mutate(group_id = coalesce(group_id, "unmapped"),
           group_label = coalesce(group_label, "Unmapped coursework"))
}

degree_path_course_table <- function(paths, group_id = "all") {
  if (identical(group_id, "all")) return(paths$courses)
  paths$courses[paths$courses$group_id == group_id, ]
}

#' Schedule one selected route using prerequisite timing and authored semester floors
#'
#' Metadata only: no transcript, admission, availability or degree-audit
#' inference. Courses are placed by prerequisite timing, course-count
#' conditions, the upper-level planning stage and the credit maximum; other
#' degree work then fills each semester toward the usual load.
build_degree_roadmap <- function(catalog, roadmaps, catalog_id, math_start, english_start) {
  if (length(catalog_id) != 1L || !catalog_id %in% catalog$catalogs$catalog_id) {
    stop("[degree-requirements.R] Select one known degree")
  }
  if (length(math_start) != 1L || length(english_start) != 1L) {
    stop("[degree-requirements.R] Select one starting point per subject")
  }
  policy <- roadmaps$plans[roadmaps$plans$catalog_id == catalog_id, ]
  if (nrow(policy) != 1L) stop("[degree-requirements.R] Select a degree with planning rules")

  starts <- c(math = math_start, english = english_start)
  entry <- resolve_degree_entry_routes(roadmaps, catalog_id, starts)
  nodes <- prepare_degree_roadmap_nodes(roadmaps$nodes, catalog_id, unlist(entry$routes),
                                        as.integer(policy$upper_level_from_semester))
  # Shared entry courses omitted by placement are already satisfied for this scenario.
  links <- roadmaps$links[roadmaps$links$catalog_id %in% c("*", catalog_id), ]
  links <- links[links$from %in% nodes$node_id & links$to %in% nodes$node_id, ]
  conditions <- attach_degree_condition_evidence(
    roadmaps$conditions[roadmaps$conditions$catalog_id == catalog_id, ], catalog)

  schedule <- schedule_degree_roadmap(nodes, links, conditions, as.numeric(policy$max_load))
  nodes <- schedule$nodes
  nodes$moved <- nodes$semester > nodes$base_semester & nodes$catalog_id == catalog_id
  nodes <- assign_degree_roadmap_rows(nodes)
  nodes <- nodes[order(nodes$semester, match(nodes$track, c("math", "english", "main")), nodes$base_semester), ]
  terms <- allocate_degree_semester_credits(nodes, schedule$loads, policy, entry$completed_credits)

  metrics <- get_degree_chain_metrics(nodes, links, conditions)
  nodes <- cbind(nodes, metrics[match(nodes$node_id, metrics$node_id), setdiff(names(metrics), "node_id")])
  nodes <- attach_degree_roadmap_evidence(nodes, roadmaps, catalog, catalog_id)
  cedar_debug("[degree-requirements.R] ", catalog_id, ": ", nrow(nodes), " courses over ",
              nrow(terms), " semesters (math ", math_start, ", English ", english_start, ").")

  list(catalog = catalog$catalogs[match(catalog_id, catalog$catalogs$catalog_id), ],
    nodes = nodes, links = links, conditions = conditions, terms = terms, starts = starts, policy = policy,
    degree_credits = as.numeric(policy$degree_credit_target),
    preparation_credits = sum(nodes$credits[nodes$kind == "preparation"]),
    completed_credits = entry$completed_credits,
    n_preparation = sum(nodes$kind == "preparation"), n_moved = sum(nodes$moved),
    math_target = nodes[nodes$node_id == tail(entry$routes$math, 1), ])
}

#' The entry courses each starting point adds, and the degree credit it already earned
#'
#' Math placement resolves per program: a statistics major never inherits the
#' calculus sequence. English routes are shared by every program.
resolve_degree_entry_routes <- function(roadmaps, catalog_id, starts) {
  routes <- list()
  completed_credits <- 0
  for (track in names(starts)) {
    start <- roadmaps$starts[roadmaps$starts$track == track & roadmaps$starts$start_id == starts[[track]], ]
    if (nrow(start) != 1L) stop("[degree-requirements.R] Select a known ", track, " starting point")
    route <- start$node_ids
    if (track == "math") {
      math_routes <- roadmaps$math_routes
      route <- math_routes$node_ids[math_routes$catalog_id == catalog_id & math_routes$start_id == starts[[track]]]
      if (length(route) != 1L) stop("[degree-requirements.R] Select a known program math starting route")
    }
    routes[[track]] <- degree_split_ids(route)
    completed_credits <- completed_credits + as.numeric(start$completed_degree_credits)
  }
  list(routes = routes, completed_credits = completed_credits)
}

#' The program's tiles plus the shared entry courses its routes use, typed for scheduling
prepare_degree_roadmap_nodes <- function(nodes, catalog_id, entry_ids, upper_start) {
  nodes <- nodes[nodes$catalog_id == catalog_id | (nodes$catalog_id == "*" & nodes$node_id %in% entry_ids), ]
  nodes$credits <- as.numeric(nodes$credits)
  nodes$base_semester <- as.integer(nodes$semester)
  # An authored planning preference, distinct from catalog prerequisites. Choice
  # groups carry explicit levels; a display label is never parsed for one.
  nodes$earliest_semester <- pmax(nodes$base_semester, ifelse(nodes$course_level == "upper", upper_start, 1L))
  nodes$semester <- nodes$base_semester
  nodes$bundle <- nodes$bundle == "1"
  nodes
}

attach_degree_condition_evidence <- function(conditions, catalog) {
  evidence <- catalog$evidence[match(conditions$evidence_id, catalog$evidence$evidence_id), ]
  for (field in c("section", "quote", "source_url")) conditions[[field]] <- evidence[[field]]
  conditions
}

#' Place each course in the earliest semester its constraints allow
#'
#' A course is ready once every prerequisite is placed and each of its
#' course-count conditions has enough pool members placed. Foundation courses
#' go first and file order breaks ties. A course then waits for its
#' prerequisites (a "before" link adds a semester), for the earliest qualifying
#' pool completions, and for a semester with room under `max_load`.
#' @return list(nodes with `semester` set, loads = credits per semester).
schedule_degree_roadmap <- function(nodes, links, conditions, max_load) {
  # A threshold over a pool is not an AND edge from every possible member.
  count_conditions <- conditions[conditions$kind == "course_count", ]
  pools <- lapply(count_conditions$eligible_node_ids, degree_split_ids)
  pool_minimums <- as.integer(count_conditions$minimum)
  pool_met <- function(id, scheduled) {
    own <- which(count_conditions$node_id == id)
    all(vapply(own, function(k) sum(pools[[k]] %in% scheduled) >= pool_minimums[k], logical(1)))
  }

  unscheduled <- nodes$node_id
  loads <- numeric(0)
  while (length(unscheduled)) {
    scheduled <- setdiff(nodes$node_id, unscheduled)
    ready <- setdiff(unscheduled, links$to[links$from %in% unscheduled])
    ready <- ready[vapply(ready, pool_met, logical(1), scheduled = scheduled)]
    if (!length(ready)) {
      stop("[degree-requirements.R] Cycle or unsatisfied course-count condition in selected roadmap")
    }
    ready <- ready[order(nodes$earliest_semester[match(ready, nodes$node_id)])]
    id <- ready[1]
    i <- match(id, nodes$node_id)

    semester <- nodes$earliest_semester[i]
    incoming <- links[links$to == id, ]
    if (nrow(incoming)) {
      prerequisite_terms <- nodes$semester[match(incoming$from, nodes$node_id)]
      semester <- max(semester, prerequisite_terms + as.integer(incoming$timing == "before"))
    }
    # Use the earliest qualifying completions in the actual scheduled scenario.
    for (k in which(count_conditions$node_id == id)) {
      qualifying_terms <- sort(nodes$semester[match(intersect(pools[[k]], scheduled), nodes$node_id)])
      semester <- max(semester, qualifying_terms[pool_minimums[k]] + 1L)
    }
    while (semester <= length(loads) && loads[semester] + nodes$credits[i] > max_load) {
      semester <- semester + 1L
    }
    if (semester > length(loads)) loads <- c(loads, rep(0, semester - length(loads)))
    loads[semester] <- loads[semester] + nodes$credits[i]
    nodes$semester[i] <- semester
    unscheduled <- setdiff(unscheduled, id)
  }
  list(nodes = nodes, loads = loads)
}

#' Per-semester credits: shown courses plus other degree work
#'
#' Other degree work fills each semester toward the usual load first; the
#' permitted maximum absorbs the remainder. The horizon grows with the workload
#' rather than forcing the baseline number of semesters.
allocate_degree_semester_credits <- function(nodes, loads, policy, completed_credits) {
  normal_load <- as.numeric(policy$normal_load)
  max_load <- as.numeric(policy$max_load)
  degree_credits <- as.numeric(policy$degree_credit_target)
  upper_start <- as.integer(policy$upper_level_from_semester)
  preparation_credits <- sum(nodes$credits[nodes$kind == "preparation"])
  workload <- degree_credits - completed_credits + preparation_credits
  horizon <- max(as.integer(policy$baseline_semesters), nodes$semester, ceiling(workload / max_load))
  loads <- c(loads, rep(0, horizon - length(loads)))

  unallocated <- degree_credits - completed_credits - sum(nodes$credits[nodes$kind != "preparation"])
  if (unallocated < 0) stop("[degree-requirements.R] Shown degree courses exceed the planning credit target")
  other <- numeric(horizon)
  for (limit in c(normal_load, max_load)) {
    for (semester in seq_len(horizon)) {
      amount <- min(unallocated, max(0, limit - loads[semester]))
      other[semester] <- other[semester] + amount
      loads[semester] <- loads[semester] + amount
      unallocated <- unallocated - amount
    }
  }
  if (unallocated > 0) stop("[degree-requirements.R] Planning workload exceeds the available semester budget")

  semesters <- seq_len(horizon)
  data.frame(semester = semesters, known_credits = loads - other, other_credits = other,
    planned_credits = loads, year = ceiling(semesters / 2),
    other_phase = ifelse(semesters < upper_start, "foundation", "advanced"))
}

#' Align authored course families after scheduling; never change their semesters
#'
#' Math and writing rows are reserved. Other families may share a row only
#' outside each other's full semester span, so gaps inside a sequence remain
#' visible.
assign_degree_roadmap_rows <- function(nodes) {
  families <- unique(nodes$row_group)
  foundation <- intersect(c("math", "writing"), families)
  families <- c(foundation, setdiff(families, foundation))
  row_spans <- list()
  n_reserved <- 0L
  nodes$row <- integer(nrow(nodes))
  for (family in families) {
    members <- which(nodes$row_group == family)
    # A family can contain parallel courses. The first, second, ... course of the
    # family in each semester go to separate rows rather than overlapping.
    slot <- ave(nodes$semester[members], nodes$semester[members], FUN = seq_along)
    for (subrow in seq_len(max(slot))) {
      ids <- members[slot == subrow]
      span <- seq.int(min(nodes$semester[ids]), max(nodes$semester[ids]))
      if (family %in% foundation) {
        row <- length(row_spans) + 1L
      } else {
        row <- n_reserved + 1L
        while (row <= length(row_spans) && any(span %in% row_spans[[row]])) row <- row + 1L
      }
      if (row > length(row_spans)) row_spans[[row]] <- integer()
      row_spans[[row]] <- c(row_spans[[row]], span)
      nodes$row[ids] <- row
    }
    if (family %in% foundation) n_reserved <- length(row_spans)
  }
  nodes
}

#' Break early planning allowances into course-sized slots without adding credit
#'
#' Keep family gaps and the reserved math/writing rows intact. Suggestions have
#' no prerequisite edges and never become catalog requirement nodes.
build_degree_allowance_slots <- function(nodes, terms, slot_credits) {
  slots <- data.frame(node_id = character(), semester = integer(), credits = numeric(), row = integer())
  row_spans <- vector("list", max(nodes$row))
  family_key <- paste(nodes$row, nodes$row_group)
  for (key in unique(family_key)) {
    family <- nodes[family_key == key, ]
    row <- family$row[1]
    span <- if (family$row_group[1] %in% c("math", "writing")) terms$semester
            else seq.int(min(family$semester), max(family$semester))
    row_spans[[row]] <- unique(c(row_spans[[row]], span))
  }
  for (i in which(terms$other_phase == "foundation" & terms$other_credits > 0)) {
    semester <- terms$semester[i]
    unallocated <- terms$other_credits[i]
    index <- 0L
    while (unallocated > 0) {
      # Permit a one-credit extension of a usual slot (e.g. 3 + 4), while
      # leaving small remainders explicit rather than rounding the budget up.
      amount <- if (unallocated <= slot_credits + 1) unallocated else slot_credits
      row <- 1L
      while (row <= length(row_spans) && semester %in% row_spans[[row]]) row <- row + 1L
      if (row > length(row_spans)) row_spans[[row]] <- integer()
      row_spans[[row]] <- c(row_spans[[row]], semester)
      index <- index + 1L
      slots[nrow(slots) + 1L, ] <- list(paste0("allowance-", semester, "-", index), semester, amount, row)
      unallocated <- unallocated - amount
    }
  }
  slots
}

degree_semester_seasons <- function(semesters, start_season) {
  if (length(start_season) != 1L || !start_season %in% c("fall", "spring")) {
    stop("[degree-requirements.R] Select a fall or spring starting semester")
  }
  second <- if (start_season == "fall") "spring" else "fall"
  ifelse(semesters %% 2L == 1L, start_season, second)
}

#' Prerequisite burden and downstream reach on the selected route, not readiness
#'
#' Counts unique direct and indirect prerequisite courses (a lecture/lab pair
#' counts twice), the longest chain of earlier semesters, and the courses that
#' depend on each one. `upstream_ids` / `downstream_ids` carry the same chains
#' to the browser, which draws them without walking the graph itself.
get_degree_chain_metrics <- function(nodes, links, conditions = NULL) {
  ids <- nodes$node_id
  ancestors <- descendants <- stats::setNames(vector("list", length(ids)), ids)
  depth_before <- depth_after <- stats::setNames(integer(length(ids)), ids)
  unvisited <- ids
  topological <- character()
  while (length(unvisited)) {
    ready <- setdiff(unvisited, links$to[links$from %in% unvisited])
    if (!length(ready)) stop("[degree-requirements.R] Cycle in selected prerequisite route")
    for (id in ready) {
      incoming <- links[links$to == id, ]
      ancestors[[id]] <- unique(c(incoming$from, unlist(ancestors[incoming$from], use.names = FALSE)))
      if (nrow(incoming)) {
        depth_before[[id]] <- max(depth_before[incoming$from] + as.integer(incoming$timing == "before"))
      }
    }
    topological <- c(topological, ready)
    unvisited <- setdiff(unvisited, ready)
  }
  for (id in rev(topological)) {
    outgoing <- links[links$from == id, ]
    descendants[[id]] <- unique(c(outgoing$to, unlist(descendants[outgoing$to], use.names = FALSE)))
    if (nrow(outgoing)) {
      depth_after[[id]] <- max(depth_after[outgoing$to] + as.integer(outgoing$timing == "before"))
    }
  }

  # A lecture/lab pair occupies one graph node but represents two actual courses.
  weights <- stats::setNames(ifelse(nodes$bundle, 2L, 1L), ids)
  n_prerequisites <- unname(vapply(ancestors, function(chain) sum(weights[chain]), integer(1)))
  n_direct <- vapply(ids, function(id) sum(weights[links$from[links$to == id]]), integer(1), USE.NAMES = FALSE)
  n_downstream <- unname(vapply(descendants, function(chain) sum(weights[chain]), integer(1)))
  n_conditions <- vapply(ids, function(id) sum(conditions$node_id == id), integer(1), USE.NAMES = FALSE)
  data.frame(node_id = ids, n_prerequisites = n_prerequisites, n_direct = n_direct,
    prereq_depth = unname(depth_before), n_downstream = n_downstream,
    chain_terms = unname(depth_before + depth_after + 1L), n_conditions = n_conditions,
    upstream_ids = unname(vapply(ancestors, paste, character(1), collapse = "|")),
    downstream_ids = unname(vapply(descendants, paste, character(1), collapse = "|")),
    planning_level = case_when(
      nodes$kind == "choice" ~ "unresolved",
      n_prerequisites == 0L & n_conditions > 0L ~ "conditional",
      n_prerequisites == 0L ~ "green",
      n_prerequisites <= 2L ~ "yellow",
      TRUE ~ "red"))
}

#' Resolve why a tile is present against a year-specific program or requisite citation
attach_degree_roadmap_evidence <- function(nodes, roadmaps, catalog, catalog_id) {
  basis <- roadmaps$basis[roadmaps$basis$catalog_id == catalog_id, ]
  basis <- basis[match(nodes$node_id, basis$node_id), ]
  evidence <- catalog$evidence[match(basis$evidence_id, catalog$evidence$evidence_id), ]
  if (anyNA(basis$node_id) || anyNA(evidence$evidence_id)) {
    stop("[degree-requirements.R] Missing roadmap provenance")
  }
  nodes$basis <- basis$basis
  nodes$basis_explanation <- basis$explanation
  for (field in c("section", "quote", "source_url", "catalog_year", "retrieved_on", "review_status", "note")) {
    nodes[[paste0("evidence_", field)]] <- evidence[[field]]
  }
  nodes
}
