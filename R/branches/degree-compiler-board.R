# Degree compiler, step 2: a compiled reading as a complete draft board.
#
# compile_degree_interpretation() (degree-compiler.R) drafts the rows; this
# file turns them into the same tables an authored board has
# (degree_catalogs ... degree_roadmap_plans), validates them with the same
# validators (validate_degree_catalog(), validate_degree_roadmaps()), and lets
# build_degree_roadmap() place them. Nothing here writes a file. A separate
# file because the board needs inputs the compiler does not: the course pages'
# requisite trees, the institution's shared math and English routes, and its
# planning defaults.
#
# Placement: a lower-division tile starts in semester 1 and an upper-division
# one at the plan's upper-level semester; the scheduler moves each later for
# prerequisites and load, as it does for an authored board. An elective slot's
# level is its group's: upper when every course its group requires is upper.
#
# Arrows: the course pages' structured requisites (extractor 1.4.0 or later),
# timed by the catalog's own template ("Earned" before; "or concurrently
# enrolled" before or same term). A requisite under wording the extractor does
# not recognise is held for a reviewer, never drawn. A pair listed each way
# (a lecture and its lab) is held too: the board cannot draw a cycle.

DEGREE_BOARD_TIMING <- c(prior = "before", prior_or_concurrent = "before_or_same", concurrent = "before_or_same")
DEGREE_BOARD_DRAFT_NOTE <- "Draft compiled from a catalog reading that no one has reviewed yet."

degree_board_id <- function(x) {
  id <- gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(x)))
  ifelse(grepl("^[a-z]", id), id, paste0("n_", id))
}

# Whole credits that add to `total` over `n` tiles (14 over 5 is 3, 3, 3, 3, 2).
degree_board_split_credits <- function(total, n) {
  each <- rep(total %/% n, n)
  extra <- round(total - sum(each))
  if (extra > 0) each[seq_len(extra)] <- each[seq_len(extra)] + 1
  each
}

#' The program page's own facts a board cites
#'
#' @param packet A prepared packet.
#' @return List: `entity_id`, `title`, `catalog_url`, `degree_hours`, `blocks`
#'   (every program and concentration source block, for citation sections).
degree_packet_program_facts <- function(packet) {
  unit <- Filter(function(u) any(startsWith(vapply(u$request$documents, function(d) d$id, ""), "programs:")), packet$units)
  if (length(unit) != 1L) stop("[degree-compiler-board.R] The packet has no single program unit")
  request <- unit[[1]]$request
  doc <- Filter(function(d) startsWith(d$id, "programs:"), request$documents)[[1]]
  hours <- Filter(function(b) identical(b$field, "degreeHours") && identical(b$entity_id, doc$id), request$source_blocks)
  if (length(hours) != 1L) stop("[degree-compiler-board.R] The program record has no Degree Hours field")
  list(entity_id = doc$id, title = doc$title, catalog_url = doc$catalog_url,
       degree_hours = as.numeric(jsonlite::fromJSON(hours[[1]]$text)), hours_quote = hours[[1]]$text,
       blocks = request$source_blocks)
}

#' Each course's structured requisites, from the catalog analysis
#'
#' @param rule_nodes An analysis `rule-nodes.csv` (extractor 1.4.0 or later).
#' @param courses `degree_packet_course_facts()`: the courses whose requisites are read.
#' @return Tibble: `subject_course` (the course), `requisite` (the course it
#'   needs), `timing` (`prior`, `prior_or_concurrent`, `concurrent`, or `NA` when
#'   the wording is not a recognised template), `alternative` (one of several),
#'   `quote`, `source_url` (the course's page).
degree_course_requisites <- function(rule_nodes, courses) {
  needed <- c("entity", "phase", "node_id", "parent_id", "operator", "course_codes", "text", "timing")
  missing <- setdiff(needed, names(rule_nodes))
  if ("timing" %in% missing) stop("[degree-compiler-board.R] The analysis predates extractor 1.4.0 (no requisite timing); re-run analyze_degree_catalog()")
  if (length(missing)) stop("[degree-compiler-board.R] rule nodes need ", paste(missing, collapse = ", "))
  rows <- rule_nodes[rule_nodes$entity %in% courses$course_ref & rule_nodes$phase %in% c("prerequisite", "corequisite"), ]
  parent_of <- stats::setNames(rows$parent_id, rows$node_id)
  leaves <- rows[rows$operator == "course" & nzchar(rows$course_codes), ]
  out <- lapply(seq_len(nrow(leaves)), function(i) {
    leaf <- leaves[i, ]; at <- leaf$parent_id; timing <- NA_character_; alternative <- FALSE; opaque <- FALSE
    while (nzchar(at) && at %in% rows$node_id) {
      node <- rows[rows$node_id == at, ]
      if (is.na(timing) && nzchar(node$timing)) timing <- node$timing
      if (node$operator %in% c("choose_n", "credits")) alternative <- TRUE
      if (node$operator == "condition") opaque <- TRUE
      at <- parent_of[[at]]
    }
    if (opaque) timing <- NA_character_
    codes <- trimws(strsplit(leaf$course_codes, "|", fixed = TRUE)[[1]])
    tibble::tibble(subject_course = courses$subject_course[match(leaf$entity, courses$course_ref)],
                   requisite = degree_compiler_course_code(codes), timing = timing, alternative = alternative,
                   quote = leaf$text, source_url = courses$catalog_url[match(leaf$entity, courses$course_ref)])
  })
  none <- tibble::tibble(subject_course = character(), requisite = character(), timing = character(),
                         alternative = logical(), quote = character(), source_url = character())
  dplyr::distinct(dplyr::bind_rows(none, out), subject_course, requisite, .keep_all = TRUE)
}

#' A compiled reading as a validated draft board
#'
#' @param compiled `compile_degree_interpretation()` output.
#' @param courses `degree_packet_course_facts()`.
#' @param program `degree_packet_program_facts()`.
#' @param requisites `degree_course_requisites()`.
#' @param catalog_row One row of `degree_catalogs` columns for the draft (its
#'   `catalog_id`, names, Banner codes, year); `source_url` must be the program page.
#' @param shared The institution's boards (`read_degree_roadmaps()`), read for
#'   its shared rows (`catalog_id` "*"), program math routes and planning defaults.
#' @param evidence The institution's `degree_catalog_evidence`, for the shared routes' citations.
#' @param general_math The shared math node a program with no math requirement plans toward.
#' @return List: `catalog`, `roadmaps` (validated), `held` (requisites among the
#'   board's courses not drawn, with why).
assemble_compiled_degree_board <- function(compiled, courses, program, requisites, catalog_row, shared, evidence, general_math) {
  id <- catalog_row$catalog_id
  if (catalog_row$source_url != program$catalog_url) stop("[degree-compiler-board.R] The draft's source must be its program page")
  year <- catalog_row$catalog_year
  blocks <- program$blocks
  section_of <- function(block) { hit <- Filter(function(b) identical(b$id, block), blocks); if (length(hit)) hit[[1]]$section else "Program requirements" }
  ev <- list()
  cite <- function(eid, type, url, section, quote) {
    ev[[eid]] <<- data.frame(evidence_id = eid, catalog_year = year, source_type = type, source_url = url, section = section,
      quote = quote, retrieved_on = catalog_row$retrieved_on, review_status = "transcribed", note = DEGREE_BOARD_DRAFT_NOTE)
    eid
  }
  plan_evidence <- cite(paste0("total-", id), "program", program$catalog_url, "Degree Hours", program$hours_quote)

  rules <- compiled$rules
  shared_nodes <- shared$nodes[shared$nodes$catalog_id == "*", ]
  shared_codes <- stats::setNames(shared_nodes$node_id, shared_nodes$code)
  required_shared <- intersect(rules$subject_course[rules$role == "course"], names(shared_codes))
  course_rules <- rules[rules$role == "course" & !rules$subject_course %in% required_shared, ]
  main_subject <- names(sort(table(sub(" .*", "", course_rules$subject_course)), decreasing = TRUE))[1]
  upper_from <- as.character(degree_board_plan_default(shared$plans, "upper_level_from_semester"))
  level_semester <- function(level) ifelse(level == "upper", upper_from, "1")
  node <- function(node_id, code, title, credits, kind, level, url, row_group, detail)
    data.frame(catalog_id = id, node_id = node_id, track = "main", code = code, title = title, credits = as.character(credits),
      semester = level_semester(level), kind = kind, bundle = "0", detail = detail, source_url = url,
      course_level = level, row_group = row_group, requirement_summary = "")
  nodes <- list(); options <- list(); components <- list(); basis <- list()
  add_basis <- function(node_id, kind, eid, why) basis[[node_id]] <<- data.frame(catalog_id = id, node_id = node_id, basis = kind, evidence_id = eid, explanation = why)
  rule_evidence <- function(r) cite(paste0("degree-", id, "-", degree_board_id(r$rule_id)), "program", program$catalog_url,
                                    section_of(r$block_id), r$quote)

  for (i in seq_len(nrow(rules))) {
    r <- rules[i, ]
    group <- degree_board_id(if (nzchar(r$parent_id)) r$parent_id else r$rule_id)
    detail <- paste(DEGREE_BOARD_DRAFT_NOTE, r$label)
    if (r$role == "course") {
      if (r$subject_course %in% required_shared) next
      course <- courses[courses$subject_course == r$subject_course, ][1, ]
      nid <- degree_board_id(r$subject_course)
      level <- course_level_from_number(r$subject_course)
      kind <- if (sub(" .*", "", r$subject_course) == main_subject) "major" else "support"
      nodes[[nid]] <- node(nid, r$subject_course, course$title, course$credits_min, kind, level, course$catalog_url, group, detail)
      components[[nid]] <- data.frame(catalog_id = id, node_id = nid, subject_course = r$subject_course)
      add_basis(nid, "degree", rule_evidence(r), "Degree requirement in the draft reading.")
      next
    }
    eid <- rule_evidence(r)
    if (r$role == "slot") {
      siblings <- rules$subject_course[rules$role == "course" & rules$parent_id == r$parent_id & nzchar(r$parent_id)]
      level <- if (length(siblings) && all(course_level_from_number(siblings) == "upper")) "upper" else "lower"
      credits <- degree_board_split_credits(if (is.na(r$credits)) 3 * r$tiles else r$credits, r$tiles)
      for (k in seq_len(r$tiles)) {
        nid <- paste0(degree_board_id(r$rule_id), "_", k)
        nodes[[nid]] <- node(nid, "Elective", r$label, credits[k], "choice", level, program$catalog_url, group, detail)
        add_basis(nid, "degree", eid, "Elective credits in the draft reading.")
      }
      next
    }
    # A choice: one tile per course position of its options, repeated for each one chosen.
    opts <- compiled$options[compiled$options$rule_id == r$rule_id, ]
    seqs <- split(opts$subject_course, factor(opts$option_id, unique(opts$option_id)))
    size <- max(lengths(seqs)); copies <- max(1L, r$tiles %/% size)
    # A pool of credits from single courses splits its total over its tiles,
    # within its options' range; a sequence plans each position's smallest course.
    credits <- if (is.na(r$credits) || size > 1L) NULL else degree_board_split_credits(r$credits, copies)
    k <- 0L
    for (copy in seq_len(copies)) for (pos in seq_len(size)) {
      k <- k + 1L
      at <- Filter(function(x) length(x) >= pos, seqs)
      codes <- vapply(at, function(x) x[pos], "")
      facts <- courses[match(codes, courses$subject_course), ]
      nid <- paste0(degree_board_id(r$rule_id), "_", k)
      planned <- if (is.null(credits)) min(facts$credits_min) else min(max(credits[k], min(facts$credits_min)), max(facts$credits_max))
      level <- if (all(course_level_from_number(codes) == "upper")) "upper" else "lower"
      title <- if (size > 1L) paste0(r$label, " (course ", pos, " of ", size, ")") else r$label
      nodes[[nid]] <- node(nid, "Choice", title, planned, "choice", level, program$catalog_url, group, detail)
      options[[nid]] <- data.frame(catalog_id = id, node_id = nid, option_id = degree_board_id(names(at)), minimum = "1",
        subject_course = codes, course_title = facts$title, credits_min = as.character(facts$credits_min),
        credits_max = as.character(facts$credits_max), source_url = facts$catalog_url, evidence_id = eid, requisite_evidence_id = "")
      add_basis(nid, "degree", eid, "Course choice in the draft reading.")
    }
  }

  # Math: the program's required shared math course, or the general target.
  routes <- shared$math_routes
  ends <- vapply(routes$node_ids, function(x) utils::tail(degree_split_ids(x), 1), "")
  required_math <- unname(shared_codes[required_shared][shared_nodes$track[match(shared_codes[required_shared], shared_nodes$node_id)] == "math"])
  target <- if (length(required_math)) required_math else general_math
  if (length(target) != 1L) stop("[degree-compiler-board.R] The reading requires several shared math courses: ", paste(target, collapse = ", "))
  template <- sort(unique(routes$catalog_id[ends == target]))
  template <- template[vapply(template, function(t) all(ends[routes$catalog_id == t] == target), TRUE)]
  if (!length(template)) stop("[degree-compiler-board.R] No program's math routes end at ", target)
  math_routes <- routes[routes$catalog_id == template[1], ]
  math_routes$catalog_id <- id

  # Shared tiles this board shows: required ones cite the reading; preparation
  # cites the route's own course evidence; the rest are illustrative.
  roadmaps <- list(nodes = rbind(shared$nodes[shared$nodes$catalog_id == "*", ], do.call(rbind, nodes)),
    math_routes = math_routes, starts = shared$starts)
  shown <- setdiff(degree_roadmap_node_ids(roadmaps, id), names(nodes))
  for (nid in shown) {
    code <- shared_nodes$code[shared_nodes$node_id == nid]
    if (code %in% required_shared) {
      r <- rules[rules$role == "course" & rules$subject_course == code, ][1, ]
      add_basis(nid, "degree", rule_evidence(r), "Degree requirement in the draft reading.")
    } else if (shared_nodes$kind[shared_nodes$node_id == nid] == "preparation") {
      route <- shared$links[shared$links$catalog_id == "*" & shared$links$from == nid, ]
      if (!nrow(route)) stop("[degree-compiler-board.R] Shared preparation course has no route evidence: ", nid)
      add_basis(nid, "prerequisite", route$evidence_id[1], "Preparation added by the selected starting route; not a listed requirement.")
    } else {
      add_basis(nid, "general", plan_evidence, "Illustrative general education course on the shared starting route; the draft reading does not require it.")
    }
  }
  shared_evidence <- evidence[evidence$evidence_id %in% c(shared$links$evidence_id[shared$links$catalog_id == "*"],
                                                          vapply(basis, function(b) b$evidence_id, "")), ]

  # Arrows between course tiles this board shows.
  # (A board of choices alone has no course tiles of its own.)
  code_to_node <- c(stats::setNames(as.character(names(components)), vapply(components, function(x) x$subject_course, "")),
                    stats::setNames(shown, shared_nodes$code[match(shown, shared_nodes$node_id)]))
  candidates <- requisites[requisites$subject_course %in% names(code_to_node) & requisites$requisite %in% names(code_to_node), ]
  candidates$from <- unname(code_to_node[candidates$requisite]); candidates$to <- unname(code_to_node[candidates$subject_course])
  candidates <- candidates[!(candidates$from %in% shown & candidates$to %in% shown), ]
  mutual <- paste(candidates$from, candidates$to) %in% paste(candidates$to, candidates$from)
  # A course that needs one of a choice's options: the board draws no arrow
  # from a choice (the option a student takes is not known), so say so.
  option_codes <- unique(unlist(lapply(options, function(o) o$subject_course)))
  from_choice <- requisites[requisites$subject_course %in% names(code_to_node) & requisites$requisite %in% option_codes &
                              !requisites$requisite %in% names(code_to_node), ]
  held <- dplyr::bind_rows(
    dplyr::mutate(from_choice, why = "needs a course offered in a choice; a choice draws no arrow"),
    dplyr::mutate(candidates[is.na(candidates$timing), ], why = "wording is not a recognised requisite template"),
    dplyr::mutate(candidates[!is.na(candidates$timing) & mutual, ], why = "listed each way; the board cannot draw a cycle"))
  drawn <- candidates[!is.na(candidates$timing) & !mutual, ]
  links <- do.call(rbind, c(list(shared$links[shared$links$catalog_id == "*", ]), lapply(seq_len(nrow(drawn)), function(i) {
    d <- drawn[i, ]
    eid <- cite(paste0("route-", id, "-", d$from, "-", d$to), "course", d$source_url, "Prerequisites", d$quote)
    data.frame(catalog_id = id, from = d$from, to = d$to, timing = DEGREE_BOARD_TIMING[[d$timing]],
      detail = paste0(DEGREE_BOARD_DRAFT_NOTE, if (d$alternative) " One of several listed prerequisites." else ""),
      source_url = d$source_url, evidence_id = eid)
  })))

  plan <- data.frame(catalog_id = id, degree_credit_target = as.character(program$degree_hours),
    normal_load = as.character(degree_board_plan_default(shared$plans, "normal_load")),
    max_load = as.character(degree_board_plan_default(shared$plans, "max_load")),
    baseline_semesters = as.character(degree_board_plan_default(shared$plans, "baseline_semesters")),
    evidence_id = plan_evidence, assumption = DEGREE_BOARD_DRAFT_NOTE, upper_level_from_semester = upper_from,
    allowance_slot_credits = as.character(degree_board_plan_default(shared$plans, "allowance_slot_credits")),
    gen_ed_source_url = as.character(degree_board_plan_default(shared$plans, "gen_ed_source_url")))
  empty <- function(spec) as.data.frame(stats::setNames(replicate(length(spec), character(), simplify = FALSE), spec))
  catalog <- validate_degree_catalog(list(
    catalogs = as.data.frame(catalog_row),
    rules = data.frame(rule_id = paste0(id, "-total"), catalog_id = id, parent_id = "", phase = "degree", area = "completion",
      target_course = "", label = "Minimum degree credits", operator = "credits", minimum = as.character(program$degree_hours),
      min_grade = "", review_status = "draft", detail = DEGREE_BOARD_DRAFT_NOTE),
    courses = empty(CEDAR_CONFIG_FILE_SPECS$degree_rule_courses),
    evidence = rbind(shared_evidence[CEDAR_CONFIG_FILE_SPECS$degree_catalog_evidence], do.call(rbind, ev))))
  roadmaps <- validate_degree_roadmaps(list(
    nodes = roadmaps$nodes, links = links, starts = shared$starts, math_routes = math_routes,
    conditions = empty(CEDAR_CONFIG_FILE_SPECS$degree_roadmap_conditions),
    basis = do.call(rbind, basis), plans = plan,
    courses = rbind(shared$courses[shared$courses$catalog_id == "*", ], do.call(rbind, components)),
    options = if (length(options)) do.call(rbind, options) else empty(CEDAR_CONFIG_FILE_SPECS$degree_roadmap_options)), catalog)
  list(catalog = catalog, roadmaps = roadmaps, held = held)
}

# A planning default: the value most authored boards use (every board plans 15
# credits a term; most start upper-division work in semester 5). A tie stops.
degree_board_plan_default <- function(plans, column) {
  counts <- sort(table(plans[[column]]), decreasing = TRUE)
  if (!length(counts) || (length(counts) > 1L && counts[[1]] == counts[[2]])) {
    stop("[degree-compiler-board.R] No planning default for ", column, ": authored plans split evenly")
  }
  value <- names(counts)[1]
  if (column == "gen_ed_source_url") value else as.numeric(value)
}

#' Where a draft board and the hand-built board place each course
#'
#' @param draft,board `build_degree_roadmap()` output for the same starting points.
#' @return Tibble: `code`, `draft_semester`, `board_semester` for each course
#'   tile either shows (NA where one does not), ordered by the board.
compare_degree_board_semesters <- function(draft, board) {
  pick <- function(plan) { n <- plan$nodes[plan$nodes$kind != "choice", ]; tibble::tibble(code = n$code, semester = n$semester) }
  out <- dplyr::full_join(dplyr::rename(pick(draft), draft_semester = semester),
                          dplyr::rename(pick(board), board_semester = semester), by = "code")
  out[order(out$board_semester, out$draft_semester, out$code, na.last = TRUE), ]
}

#' A draft board beside the hand-built one, as text
#'
#' @param title Program name. @param math The math starting point both used.
#' @param draft,board `build_degree_roadmap()` output. @param held The requisites the draft did not draw.
format_degree_board_comparison <- function(title, math, draft, board, held) {
  rows <- compare_degree_board_semesters(draft, board)
  same <- sum(rows$draft_semester == rows$board_semester, na.rm = TRUE)
  both <- sum(!is.na(rows$draft_semester) & !is.na(rows$board_semester))
  show <- function(x) ifelse(is.na(x), "\u2014", as.character(x))
  c(paste0(title, " \u00b7 math start: ", math),
    paste0("  Semesters: ", nrow(draft$terms), " draft, ", nrow(board$terms), " on the board"),
    paste0("  Arrows: ", nrow(draft$links), " draft, ", nrow(board$links), " on the board; ", nrow(held), " held for a reviewer"),
    paste0("  Courses on both: ", both, ", same semester for ", same),
    paste0("    ", formatC(rows$code, width = -12), " draft ", show(rows$draft_semester), " \u00b7 board ", show(rows$board_semester)),
    if (nrow(held)) {
      # CAMPUS_ROLLUP: catalog course codes and their listed requisites; no
      # enrollment row and no campus is read here.
      grouped <- dplyr::summarize(dplyr::group_by(held, subject_course, why),
                                  needs = paste(sort(unique(requisite)), collapse = " or "), .groups = "drop")
      paste0("  Held: ", grouped$subject_course, " needs ", grouped$needs, " (", grouped$why, ")")
    }) |>
    paste(collapse = "\n")
}
