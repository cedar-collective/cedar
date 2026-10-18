# Shared catalog presentation and descriptive grouping; no student eligibility inference.

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
  if (!length(catalog_ids) || any(!catalog_ids %in% catalog$catalogs$catalog_id)) stop("Select known catalog IDs")
  r <- catalog$rules[catalog$rules$catalog_id %in% catalog_ids, ]
  x <- catalog$courses
  r$depth <- integer(nrow(r)); r$text <- character(nrow(r))
  phrases <- c(all = "Take all", choose_n = "Choose at least", course = "Take",
    credits = "Earn at least", condition = "Condition", none = "Not required",
    prior = "Complete before", concurrent = "Take concurrently", prior_or_concurrent = "Complete before or take concurrently")
  for (i in seq_len(nrow(r))) {
    parent <- r$parent_id[i]
    while (nzchar(parent)) {
      r$depth[i] <- r$depth[i] + 1L
      parent <- r$parent_id[match(parent, r$rule_id)]
    }
    value <- if (r$operator[i] == "choose_n") paste0(" ", r$minimum[i], if (r$minimum[i] == "1") " option" else " options")
             else if (r$operator[i] == "credits") paste0(" ", r$minimum[i], " credits") else ""
    title <- r$label[i]
    course <- x[x$rule_id == r$rule_id[i], ]
    if (nrow(course)) title <- paste0(course$subject_course, " — ", course$course_title,
                                     " (", course$credits, " credits)")
    grade <- if (nzchar(r$min_grade[i])) paste0("; minimum grade ", r$min_grade[i]) else ""
    target <- if (nzchar(r$target_course[i])) paste0(" [for ", r$target_course[i], "]") else ""
    r$text[i] <- paste0(title, target, ": ", phrases[[r$operator[i]]], value, grade,
                       if (nzchar(r$detail[i])) paste0(". ", r$detail[i]) else "",
                       if (r$review_status[i] == "conflict") " [SOURCE CONFLICT]" else "")
  }
  # File order is not assumed to be a pre-order traversal.
  ordered <- character()
  walk <- function(id) {
    ordered <<- c(ordered, id)
    for (child in r$rule_id[r$parent_id == id]) walk(child)
  }
  for (id in r$rule_id[!nzchar(r$parent_id)]) walk(id)
  r[match(ordered, r$rule_id), ]
}

#' Classify a course once for descriptive pathways, never as degree fulfillment
attach_pathway_groups <- function(rows, groups) {
  groups <- validate_pathway_subject_groups(groups)
  out <- rows %>% dplyr::mutate(subject_code = sub(" .*", "", subject_course)) %>%
    dplyr::left_join(groups, by = "subject_code")
  out %>% dplyr::mutate(group_id = dplyr::coalesce(group_id, "unmapped"),
                        group_label = dplyr::coalesce(group_label, "Unmapped coursework"))
}

degree_path_course_table <- function(paths, group_id = "all") {
  if (identical(group_id, "all")) return(paths$courses)
  paths$courses[paths$courses$group_id == group_id, ]
}

#' Schedule one selected route using prerequisite timing and authored semester floors
#' Metadata only: no transcript, admission, availability or degree-audit inference.
build_degree_roadmap <- function(catalog, roadmaps, catalog_id, math_start, english_start) {
  if (length(catalog_id) != 1L || !catalog_id %in% catalog$catalogs$catalog_id) stop("Select one known degree")
  if (length(math_start) != 1L || length(english_start) != 1L) stop("Select one starting point per subject")
  policy <- roadmaps$plans[roadmaps$plans$catalog_id == catalog_id, ]
  if (nrow(policy) != 1L) stop("Select a degree with planning rules")
  normal_load <- as.numeric(policy$normal_load); max_load <- as.numeric(policy$max_load)
  n <- roadmaps$nodes
  selected <- character(); routes <- list(); completed_credits <- 0
  starts <- c(math = math_start, english = english_start)
  for (track in names(starts)) {
    s <- roadmaps$starts[roadmaps$starts$track == track & roadmaps$starts$start_id == starts[[track]], ]
    if (nrow(s) != 1L) stop("Select a known ", track, " starting point")
    route <- s$node_ids
    if (track == "math") {
      route <- roadmaps$math_routes$node_ids[roadmaps$math_routes$catalog_id == catalog_id &
        roadmaps$math_routes$start_id == math_start]
      if (length(route) != 1L) stop("Select a known program math starting route")
    }
    routes[[track]] <- if (nzchar(route)) strsplit(route, "|", fixed = TRUE)[[1]] else character()
    selected <- c(selected, routes[[track]])
    completed_credits <- completed_credits + as.numeric(s$completed_degree_credits)
  }
  n <- n[n$catalog_id == catalog_id | (n$catalog_id == "*" & n$node_id %in% selected), ]
  n$credits <- as.numeric(n$credits); n$base_semester <- as.integer(n$semester)
  # This is an authored planning preference, distinct from catalog prerequisites.
  # Choice groups carry explicit levels; never parse a display label to infer one.
  upper_start <- as.integer(policy$upper_level_from_semester)
  n$earliest_semester <- pmax(n$base_semester,
    ifelse(n$course_level == "upper", upper_start, 1L))
  n$semester <- n$base_semester
  n$bundle <- n$bundle == "1"
  l <- roadmaps$links[roadmaps$links$catalog_id %in% c("*", catalog_id), ]
  # Shared entry courses omitted by placement are already satisfied for this scenario.
  l <- l[l$from %in% n$node_id & l$to %in% n$node_id, ]
  conditions <- roadmaps$conditions[roadmaps$conditions$catalog_id == catalog_id, ]
  proof <- catalog$evidence[match(conditions$evidence_id, catalog$evidence$evidence_id), ]
  for (field in c("section", "quote", "source_url")) conditions[[field]] <- proof[[field]]
  pools <- lapply(conditions$eligible_node_ids, function(x)
    if (nzchar(x)) strsplit(x, "|", fixed = TRUE)[[1]] else character())
  counts <- which(conditions$kind == "course_count")
  remaining <- n$node_id; loads <- numeric(0)
  while (length(remaining)) {
    ready <- setdiff(remaining, l$to[l$from %in% remaining])
    scheduled <- setdiff(n$node_id, remaining)
    ready <- ready[vapply(ready, function(id) all(vapply(counts[conditions$node_id[counts] == id],
      function(k) sum(pools[[k]] %in% scheduled) >= as.integer(conditions$minimum[k]), logical(1))), logical(1))]
    if (!length(ready)) stop("Cycle or unsatisfied course-count condition in selected roadmap")
    # Schedule foundation slots first, then upper-level work. File order breaks ties.
    ready <- ready[order(n$earliest_semester[match(ready, n$node_id)])]
    id <- ready[1]; i <- match(id, n$node_id)
    incoming <- l[l$to == id, ]
    earliest <- n$earliest_semester[i]
    if (nrow(incoming)) earliest <- max(earliest,
      n$semester[match(incoming$from, n$node_id)] + as.integer(incoming$timing == "before"))
    # A threshold over a pool is not an AND edge from every possible member.
    # Use the earliest qualifying completions in the actual scheduled scenario.
    for (k in counts[conditions$node_id[counts] == id]) {
      terms <- sort(n$semester[match(intersect(pools[[k]], scheduled), n$node_id)])
      earliest <- max(earliest, terms[as.integer(conditions$minimum[k])] + 1L)
    }
    while (length(loads) >= earliest && !is.na(loads[earliest]) && loads[earliest] + n$credits[i] > max_load)
      earliest <- earliest + 1L
    if (length(loads) < earliest) loads <- c(loads, rep(0, earliest - length(loads)))
    loads[earliest] <- loads[earliest] + n$credits[i]
    n$semester[i] <- earliest
    remaining <- setdiff(remaining, id)
  }
  n$moved <- n$semester > n$base_semester & n$catalog_id == catalog_id
  n <- assign_degree_roadmap_rows(n)
  n <- n[order(n$semester, match(n$track, c("math", "english", "main")), n$base_semester), ]
  degree_credits <- as.numeric(policy$degree_credit_target)
  preparation_credits <- sum(n$credits[n$kind == "preparation"])
  horizon <- max(as.integer(policy$baseline_semesters), n$semester,
    ceiling((degree_credits - completed_credits + preparation_credits) / max_load))
  loads <- c(loads, rep(0, horizon - length(loads)))
  # Fill toward the usual load first; the permitted maximum can absorb the remainder.
  # The workload-derived horizon grows before allocation rather than forcing eight terms.
  remaining <- degree_credits - completed_credits - sum(n$credits[n$kind != "preparation"])
  if (remaining < 0) stop("Shown degree courses exceed the planning credit target")
  other <- numeric(horizon)
  for (limit in c(normal_load, max_load)) {
    for (at in seq_along(loads)) {
      amount <- min(remaining, max(0, limit - loads[at]))
      other[at] <- other[at] + amount; loads[at] <- loads[at] + amount
      remaining <- remaining - amount
    }
  }
  if (remaining > 0) stop("Planning workload exceeds the available semester budget")
  terms <- data.frame(semester = seq_along(loads), known_credits = loads - other,
    other_credits = other, planned_credits = loads)
  terms$year <- ceiling(terms$semester / 2)
  terms$other_phase <- ifelse(terms$semester < upper_start, "foundation", "advanced")
  metrics <- get_degree_chain_metrics(n, l, conditions)
  n <- cbind(n, metrics[match(n$node_id, metrics$node_id), setdiff(names(metrics), "node_id")])
  n <- attach_degree_roadmap_evidence(n, roadmaps, catalog, catalog_id)

  list(catalog = catalog$catalogs[match(catalog_id, catalog$catalogs$catalog_id), ],
    nodes = n, links = l, conditions = conditions, terms = terms, starts = starts, policy = policy,
    degree_credits = degree_credits, preparation_credits = preparation_credits, completed_credits = completed_credits,
    n_preparation = sum(n$kind == "preparation"), n_moved = sum(n$moved),
    math_target = n[n$node_id == tail(routes$math, 1), ])
}

#' Align authored course families after scheduling; never change their semesters.
#' Reserve math/writing rows. Other families may share a row only outside each
#' other's full semester span, so gaps inside a sequence remain visible.
assign_degree_roadmap_rows <- function(nodes) {
  groups <- unique(nodes$row_group)
  foundation <- intersect(c("math", "writing"), groups)
  groups <- c(foundation, setdiff(groups, foundation))
  occupied <- list(); reserved <- 0L
  nodes$row <- integer(nrow(nodes))
  for (group in groups) {
    members <- which(nodes$row_group == group)
    # A family can contain parallel courses. Match the first, second, ... slot
    # in each semester to separate rows rather than stacking or overlapping.
    slot <- ave(nodes$semester[members], nodes$semester[members], FUN = seq_along)
    for (subrow in seq_len(max(slot))) {
      ids <- members[slot == subrow]
      span <- seq.int(min(nodes$semester[ids]), max(nodes$semester[ids]))
      row <- reserved + 1L
      if (group %in% foundation) row <- length(occupied) + 1L
      else while (row <= length(occupied) && any(span %in% occupied[[row]])) row <- row + 1L
      if (row > length(occupied)) occupied[[row]] <- integer()
      occupied[[row]] <- c(occupied[[row]], span)
      nodes$row[ids] <- row
    }
    if (group %in% foundation) reserved <- length(occupied)
  }
  nodes
}

#' Break early planning allowances into course-sized slots without adding credit.
#' Keep family gaps and the reserved math/writing rows intact. Suggestions have
#' no prerequisite edges and never become catalog requirement nodes.
build_degree_allowance_slots <- function(nodes, terms, slot_credits) {
  slots <- data.frame(node_id = character(), semester = integer(), credits = numeric(), row = integer())
  occupied <- vector("list", max(nodes$row))
  for (key in unique(paste(nodes$row, nodes$row_group))) {
    members <- nodes[paste(nodes$row, nodes$row_group) == key, ]
    row <- members$row[1]
    span <- if (members$row_group[1] %in% c("math", "writing")) terms$semester
      else seq.int(min(members$semester), max(members$semester))
    occupied[[row]] <- unique(c(occupied[[row]], span))
  }
  for (i in which(terms$other_phase == "foundation" & terms$other_credits > 0)) {
    remaining <- terms$other_credits[i]; index <- 0L
    while (remaining > 0) {
      # Permit a one-credit extension of a usual slot (e.g. 3 + 4), while
      # leaving small remainders explicit rather than rounding the budget up.
      amount <- if (remaining <= slot_credits + 1) remaining else slot_credits
      row <- 1L
      while (row <= length(occupied) && terms$semester[i] %in% occupied[[row]]) row <- row + 1L
      if (row > length(occupied)) occupied[[row]] <- integer()
      occupied[[row]] <- c(occupied[[row]], terms$semester[i]); index <- index + 1L
      slots[nrow(slots) + 1L, ] <- list(paste0("allowance-", terms$semester[i], "-", index),
        terms$semester[i], amount, row)
      remaining <- remaining - amount
    }
  }
  slots
}

degree_semester_seasons <- function(semesters, start_season) {
  if (length(start_season) != 1L || !start_season %in% c("fall", "spring")) stop("Select a fall or spring starting semester")
  second <- if (start_season == "fall") "spring" else "fall"
  ifelse(semesters %% 2L == 1L, start_season, second)
}

#' Prerequisite burden and downstream reach on the selected route, not readiness
get_degree_chain_metrics <- function(nodes, links, conditions = NULL) {
  ids <- nodes$node_id
  ancestors <- descendants <- stats::setNames(vector("list", length(ids)), ids)
  before <- after <- stats::setNames(integer(length(ids)), ids)
  remaining <- ids; order <- character()
  while (length(remaining)) {
    ready <- setdiff(remaining, links$to[links$from %in% remaining])
    if (!length(ready)) stop("Cycle in selected prerequisite route")
    for (id in ready) {
      incoming <- links[links$to == id, ]
      ancestors[[id]] <- unique(c(incoming$from, unlist(ancestors[incoming$from], use.names = FALSE)))
      if (nrow(incoming)) before[[id]] <- max(before[incoming$from] + as.integer(incoming$timing == "before"))
    }
    order <- c(order, ready); remaining <- setdiff(remaining, ready)
  }
  for (id in rev(order)) {
    outgoing <- links[links$from == id, ]
    descendants[[id]] <- unique(c(outgoing$to, unlist(descendants[outgoing$to], use.names = FALSE)))
    if (nrow(outgoing)) after[[id]] <- max(after[outgoing$to] + as.integer(outgoing$timing == "before"))
  }
  weights <- stats::setNames(ifelse(nodes$bundle, 2L, 1L), ids)
  # A lecture/lab pair occupies one graph node but represents two actual courses.
  count <- vapply(ancestors, function(x) sum(weights[x]), integer(1))
  n_conditions <- vapply(ids, function(id) sum(conditions$node_id == id), integer(1))
  data.frame(node_id = ids, n_prerequisites = unname(count),
    n_direct = vapply(ids, function(id) sum(weights[links$from[links$to == id]]), integer(1), USE.NAMES = FALSE),
    prereq_depth = unname(before), n_downstream = unname(vapply(descendants, function(x) sum(weights[x]), integer(1))),
    chain_terms = unname(before + after + 1L), n_conditions = n_conditions,
    planning_level = ifelse(nodes$kind == "choice", "unresolved",
      ifelse(count == 0L & n_conditions > 0L, "conditional",
        ifelse(count == 0L, "green", ifelse(count <= 2L, "yellow", "red")))))
}

#' Resolve why a tile is present against a year-specific program or requisite citation
attach_degree_roadmap_evidence <- function(nodes, roadmaps, catalog, catalog_id) {
  b <- roadmaps$basis[roadmaps$basis$catalog_id == catalog_id, ]
  b <- b[match(nodes$node_id, b$node_id), ]
  e <- catalog$evidence[match(b$evidence_id, catalog$evidence$evidence_id), ]
  if (anyNA(b$node_id) || anyNA(e$evidence_id)) stop("Missing roadmap provenance")
  nodes$basis <- b$basis; nodes$basis_explanation <- b$explanation
  for (field in c("section", "quote", "source_url", "catalog_year", "retrieved_on", "review_status", "note"))
    nodes[[paste0("evidence_", field)]] <- e[[field]]
  nodes
}
