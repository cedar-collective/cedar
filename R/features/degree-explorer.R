# Semester roadmap payloads and descriptive observed course mix.

plot_grouped_student_paths <- function(paths) {
  cells <- paths$cells %>% mutate(
    display_group = paste(group_label, campus, sep = " · "),
    hover = if_else(suppressed, "Suppressed: insufficient students",
      paste0(n_students, " of ", n_eligible, " students (", sprintf("%.1f", pct_students), "%)")),
    hover = paste0(display_group, "<br>Observed enrolled term ", relative_term, "<br>", hover))
  plotly::plot_ly(cells, x = ~relative_term, y = ~display_group, z = ~pct_students,
    type = "heatmap", text = ~hover, hoverinfo = "text", zmin = 0, zmax = 100,
    colors = c(CEDAR_SURFACE_TINTS[["success"]], CEDAR_PALETTE[[1]]),
    colorbar = list(title = "% students")) %>%
    plotly::layout(xaxis = list(title = "Observed enrolled term (summer included)", dtick = 1),
      yaxis = list(title = "", automargin = TRUE), margin = list(l = 230, r = 50, b = 65, t = 10)) %>%
    plotly::config(displayModeBar = FALSE)
}

#' Use the Pathways population rather than creating a second, hidden major filter
build_population_course_paths <- function(students, population, groups, opt, description) {
  paths <- get_grouped_student_paths(students, population, groups, opt)
  meta <- paths$meta
  paths$note <- paste0(description, ": ", format(meta$n_observed, big.mark = ","),
    " observed students from ", format(meta$n_population, big.mark = ","), " population members. Through ",
    fmt_term(meta$analysis_through), ". First observed enrolled term = 1. ",
    meta$n_left_boundary, " students begin at the data boundary. ", meta$n_unmapped_rows,
    " of ", meta$n_course_rows, " course records are unmapped. ", meta$n_suppressed,
    " cells suppressed (minimum ", meta$min_band_n, " students per campus/term and ", meta$min_n,
    " per positive cell).")
  paths
}

# "3" or "3–4": a credit range as the catalog states it.
degree_credit_label <- function(credits_min, credits_max) {
  ifelse(credits_min == credits_max, as.character(credits_min), paste0(credits_min, "–", credits_max))
}

#' Presentation payload: one degree with a consistent, adaptive semester board
build_degree_roadmap_view <- function(catalog, roadmaps, catalog_id, math_start, english_start,
                                      start_season = "fall") {
  view <- build_degree_roadmap(catalog, roadmaps, catalog_id, math_start, english_start)
  upper_start <- as.integer(view$policy$upper_level_from_semester)
  view$start_season <- start_season
  view$terms$season <- degree_semester_seasons(view$terms$semester, start_season)
  view$terms$other_label <- ifelse(view$terms$other_phase == "foundation",
    "Gen Ed / lower-level electives", "Upper-level / minor / electives")
  view$allowances <- build_degree_allowance_tiles(view)
  view$n_rows <- max(view$nodes$row, view$allowances$row)
  view$options <- degree_option_courses(roadmaps, catalog, catalog_id)
  view$option_groups <- degree_option_groups(view$options)
  view$nodes <- label_degree_roadmap_nodes(view$nodes, view$options, view$option_groups,
                                           view$conditions, view$links, upper_start)

  view$title <- paste(view$catalog$degree_label, "·", view$catalog$catalog_year)
  view$math_note <- paste0(view$math_target$code, " starts in semester ", view$math_target$semester, ".")
  view$change_note <- paste0(nrow(view$terms), " semesters · ", view$policy$normal_load,
    " credits usual · ", view$policy$max_load, " maximum")
  view$timing_note <- paste0("Planning preference: prioritize Gen Ed in semesters 1–", upper_start - 1L,
    "; upper-level courses start in semester ", upper_start, " or later. Allowances still need a degree audit.")
  view$workload_note <- paste0("Planning workload: ", view$degree_credits, " degree credits − ",
    view$completed_credits, " already completed + ",
    view$preparation_credits, " preparation credits. ", view$policy$assumption)
  view$note <- paste("Illustrative plan: specific choices, admission, offerings, transfer credit and a",
    "complete degree audit still need review. Colors describe prerequisites in this selected route,",
    "not eligibility or course difficulty.")
  view
}

#' Early Gen Ed / lower-level allowances as clickable, course-sized tiles
build_degree_allowance_tiles <- function(view) {
  slot_credits <- as.numeric(view$policy$allowance_slot_credits)
  slots <- build_degree_allowance_slots(view$nodes, view$terms, slot_credits)
  season <- view$terms$season[match(slots$semester, view$terms$semester)]
  slots$season <- season
  slots$season_label <- tools::toTitleCase(season)
  slots$kind <- rep("allowance", nrow(slots))
  slots$code <- rep("Gen Ed / lower-level elective", nrow(slots))
  slots$title <- ifelse(slots$credits < slot_credits, "Credits left to allocate", "Suggested course slot")
  slots$detail <- sprintf(paste("%s credits reserved. Browse recent %s Gen Ed offerings. Suggestions need",
    "individual prerequisites and a degree audit; no course has been selected."), slots$credits, season)
  slots$source_url <- rep(view$policy$gen_ed_source_url, nrow(slots))
  slots
}

#' Every course in the program's enumerated choice sets, with its own citation
degree_option_courses <- function(roadmaps, catalog, catalog_id) {
  options <- roadmaps$options[roadmaps$options$catalog_id == catalog_id, ]
  options$credit_label <- degree_credit_label(options$credits_min, options$credits_max)
  options$course_level <- course_level_from_number(options$subject_course)
  requisite <- catalog$evidence[match(options$requisite_evidence_id, catalog$evidence$evidence_id), ]
  options$prerequisite_note <- ifelse(nzchar(options$requisite_evidence_id), requisite$quote, "")
  options
}

#' One row per alternative: a lecture/lab option is one choice of two courses
degree_option_groups <- function(options) {
  options %>%
    mutate(appearance = match(paste(node_id, option_id), paste(node_id, option_id))) %>%
    group_by(catalog_id, node_id, option_id) %>%
    summarize(appearance = first(appearance), option_code = paste(subject_course, collapse = " + "),
      component_count = n(), credits_min = sum(as.numeric(credits_min)),
      credits_max = sum(as.numeric(credits_max)), .groups = "drop") %>%
    arrange(appearance) %>%
    select(-appearance) %>%
    mutate(credit_label = degree_credit_label(credits_min, credits_max))
}

#' Reader-facing labels for each tile: kind, prerequisite count, chain and notes
label_degree_roadmap_nodes <- function(nodes, options, option_groups, conditions, links, upper_start) {
  nodes$option_count <- vapply(nodes$node_id, function(id) sum(option_groups$node_id == id),
                               integer(1), USE.NAMES = FALSE)
  nodes$option_label <- ""
  nodes$option_codes <- ""
  for (i in which(nodes$option_count > 0L)) {
    alternatives <- option_groups[option_groups$node_id == nodes$node_id[i], ]
    minimum <- options$minimum[options$node_id == nodes$node_id[i]][1]
    noun <- if (any(alternatives$component_count > 1L)) "options" else "courses"
    nodes$option_label[i] <- paste("Choose", minimum, "of", nrow(alternatives), noun)
    nodes$option_codes[i] <- paste(alternatives$option_code, collapse = ", ")
  }

  kind_labels <- c(major = "Major", support = "Math / support", writing = "English",
                   choice = "Course choice", preparation = "Preparation")
  nodes$is_suggested <- nodes$basis == "general"
  nodes$kind_label <- ifelse(nodes$is_suggested, "Suggested Gen Ed", unname(kind_labels[nodes$kind]))
  nodes$kind_label <- paste0(nodes$kind_label, ifelse(nodes$course_level == "upper", " · Upper-level", ""))
  mixed_levels <- vapply(nodes$node_id, function(id) length(unique(options$course_level[options$node_id == id])) > 1L,
                         logical(1), USE.NAMES = FALSE)
  nodes$kind_label[mixed_levels] <- "Course choice · Level varies"
  nodes$condition_label <- vapply(nodes$node_id, function(id)
    paste(conditions$label[conditions$node_id == id], collapse = " · "), character(1), USE.NAMES = FALSE)
  # The pool a course-count condition draws on, outlined when its course is selected.
  nodes$qualifying_ids <- vapply(nodes$node_id, function(id) {
    pools <- lapply(conditions$eligible_node_ids[conditions$node_id == id], degree_split_ids)
    paste(unique(unlist(pools, use.names = FALSE)), collapse = "|")
  }, character(1), USE.NAMES = FALSE)

  is_choice <- nodes$kind == "choice"
  has_options <- nodes$option_count > 0L
  has_conditions <- nodes$n_conditions > 0L
  conditions_only <- has_conditions & nodes$n_prerequisites == 0L
  isolated_condition <- conditions_only & nodes$n_downstream == 0L
  stages <- paste0(nodes$chain_terms, ifelse(nodes$chain_terms == 1L, " stage", " stages"))

  nodes$prerequisite_label <- case_when(
    is_choice ~ "Prerequisites vary",
    conditions_only ~ "Prior coursework / permission",
    TRUE ~ paste(nodes$n_prerequisites, ifelse(nodes$n_prerequisites == 1L, "prereq", "prereqs")))
  route_note <- case_when(
    has_conditions ~ paste0(nodes$n_prerequisites, " named prerequisite courses in the displayed chain. ",
      "Additional conditions: ", nodes$condition_label, ". A course-count condition can be met by different courses."),
    is_choice ~ "Prerequisites depend on the course chosen.",
    TRUE ~ paste0(nodes$n_prerequisites, " prerequisite courses in this route (", nodes$n_direct,
      " direct); longest prerequisite sequence needs ", nodes$prereq_depth, " earlier semesters."))
  upper_note <- ifelse(nodes$course_level == "upper",
    paste0(" Upper-level planning starts in semester ", upper_start, "."), "")
  nodes$planning_note <- ifelse(has_options,
    paste0(nodes$option_label, ". ", nodes$credits,
      " credits reserved in this illustrative plan; prerequisites and credit hours depend on the selection."),
    paste0(route_note, upper_note))
  nodes$chain_note <- ifelse(isolated_condition, "",
    paste0("Named-course chain: ", stages, " · leads to ", nodes$n_downstream, " later courses"))
  nodes$chain_badge <- case_when(
    isolated_condition ~ "◇ Enrollment conditions",
    is_choice ~ "Choose course first",
    nodes$n_downstream > 0 & nodes$n_prerequisites == 0 ~ paste0("Chain start → ", nodes$n_downstream, " later"),
    TRUE ~ paste0("→ ", nodes$n_downstream, " later · ", stages))
  nodes$requisite_note <- vapply(nodes$node_id, function(id) {
    if (any(options$node_id == id)) {
      return(paste("Choose from the complete list above; review the individual course prerequisites",
                   "and any variable credits before planning that selection."))
    }
    incoming <- links[links$to == id, ]
    if (!nrow(incoming)) {
      if (any(conditions$node_id == id)) {
        return(paste("Meet the conditions shown above before enrolling. Highlighted options can contribute;",
                     "they are not all required."))
      }
      return("No earlier course is shown in this selected route; placement and other restrictions still apply.")
    }
    codes <- nodes$code[match(incoming$from, nodes$node_id)]
    paste(codes, ifelse(incoming$timing == "before", "before", "before or together"), collapse = "; ")
  }, character(1), USE.NAMES = FALSE)
  nodes
}

#' Everything the popup shows about one tile, resolved from the current plan
#'
#' A course carries its requirement citation, chain notes, conditions and (for
#' a choice set) every alternative with its components. An allowance carries
#' only its reserved credits and season: no course is selected, so it has no
#' catalog excerpt or prerequisites.
degree_roadmap_tile_detail <- function(view, node_id) {
  allowance <- view$allowances[view$allowances$node_id == node_id, ]
  if (nrow(allowance) == 1L) {
    return(list(type = "allowance", node_id = node_id, title = paste(allowance$code, "·", allowance$credits, "credits"),
      summary = paste0(allowance$credits, " credits reserved · ", allowance$season_label,
                       " examples · no course selected."),
      course_url = allowance$source_url, course_link_label = "Current Gen Ed course list",
      program_url = view$catalog$source_url))
  }
  node <- view$nodes[view$nodes$node_id == node_id, ]
  if (nrow(node) != 1L) stop("[degree-explorer.R] Unknown degree roadmap tile: ", node_id)
  alternatives <- view$option_groups[view$option_groups$node_id == node_id, ]
  components <- view$options[view$options$node_id == node_id, ]
  list(type = "course", node_id = node_id, title = paste(node$code, "·", node$title), node = node,
    summary = if (nzchar(node$requirement_summary)) paste0(node$requirement_summary, ". ", node$option_label,
      ". Full choices and paired labs appear below the offering history.") else "",
    course_url = node$source_url,
    course_link_label = if (node$kind == "choice") "Course group details" else "Course description",
    program_url = view$catalog$source_url,
    conditions = view$conditions[view$conditions$node_id == node_id, ],
    alternatives = alternatives,
    components = components,
    chain_text = paste(c(node$planning_note, node$chain_note)[nzchar(c(node$planning_note, node$chain_note))],
                       collapse = " "),
    detail_text = paste(node$detail, node$requisite_note))
}

#' Canonical readable preview of the same semester payload used by Shiny
format_degree_explorer_preview <- function(view) {
  semesters <- vapply(view$terms$semester, function(semester) {
    term <- view$terms[view$terms$semester == semester, ]
    courses <- view$nodes[view$nodes$semester == semester, ]
    tiles <- ifelse(courses$option_count > 0L,
      paste(courses$option_label, courses$option_codes, courses$title, sep = " · "),
      paste(courses$code, courses$title, sep = " · "))
    paste(c(paste("Semester", semester, "·", term$planned_credits, "credits planned"), tiles,
            paste(term$other_label, ":", term$other_credits, "credits")), collapse = "\n")
  }, character(1))
  paste(c(view$title, view$math_note, view$change_note, view$timing_note, semesters,
          view$workload_note, view$note), collapse = "\n\n")
}

#' Assemble history for a selected tile; authored components distinguish bundles
#' from unresolved choices and never infer historical course equivalences.
build_degree_course_history <- function(sections, students, edges, roadmaps, catalog_id, node_id) {
  node <- roadmaps$nodes[roadmaps$nodes$catalog_id %in% c("*", catalog_id) & roadmaps$nodes$node_id == node_id, ]
  if (nrow(node) != 1L) stop("[degree-explorer.R] Unknown degree course selection")
  components <- roadmaps$courses$subject_course[roadmaps$courses$catalog_id %in% c("*", catalog_id) &
                                                  roadmaps$courses$node_id == node_id]
  alternatives <- roadmaps$options$subject_course[roadmaps$options$catalog_id == catalog_id &
                                                    roadmaps$options$node_id == node_id]
  if (length(alternatives)) components <- unique(alternatives)
  if (!length(components)) {
    return(list(state = "choice", node_id = node_id,
      note = "Choose a specific course in this group before checking offering history or seat pressure."))
  }
  history <- get_course_planning_history(sections, students, components, edges)
  if (length(alternatives)) {
    history$note <- paste("History for the alternatives, with each course shown separately.", history$note)
  }
  history$node_id <- node_id
  if (history$state != "ready") return(history)
  # One typed table, retaining the exact component/campus/college/session grain.
  history$table <- history$offerings %>%
    add_term_type_col("term") %>%
    left_join(history$frequency %>% select(campus, subject_course, term_type, offered_terms, eligible_terms),
      by = c("campus", "subject_course", "term_type"), relationship = "many-to-one") %>%
    mutate(season_frequency = if_else(eligible_terms > 0L, paste(offered_terms, "of", eligible_terms), "Unknown")) %>%
    arrange(desc(term), subject_course, campus, college, part_term) %>%
    select(term, subject_course, campus, college, part_term, capacity,
      first_day_enrl, first_day_fill, pressure_status, season_frequency)
  history
}

#' Resolve a clicked card against the current plan, never client-supplied credits.
build_degree_popup_history <- function(sections, students, edges, catalog, roadmaps, gen_ed, selection) {
  if (!selection$type %in% c("course", "allowance")) stop("[degree-explorer.R] Unknown degree card type")
  if (selection$type == "course") {
    history <- build_degree_course_history(sections, students, edges, roadmaps,
      selection$catalog_id, selection$node_id)
    history$kind <- "course"
    return(history)
  }
  view <- build_degree_roadmap_view(catalog, roadmaps, selection$catalog_id,
    selection$math_start, selection$english_start, selection$start_season)
  slot <- view$allowances[view$allowances$node_id == selection$node_id, ]
  if (nrow(slot) != 1L) stop("[degree-explorer.R] Unknown degree allowance slot")
  slot_credits <- as.numeric(view$policy$allowance_slot_credits)
  # Entry routes, fixed courses and enumerated choice pools already have their
  # own places. Do not suggest them a second time as additional degree credit.
  shown <- degree_roadmap_node_ids(roadmaps, selection$catalog_id)
  represented <- c(
    roadmaps$courses$subject_course[roadmaps$courses$catalog_id %in% c("*", selection$catalog_id) &
                                      roadmaps$courses$node_id %in% shown],
    roadmaps$options$subject_course[roadmaps$options$catalog_id == selection$catalog_id])
  history <- get_course_planning_history(sections, students, setdiff(gen_ed$subject_course, represented), edges)
  history$kind <- "allowance"
  history$node_id <- slot$node_id
  history$season <- slot$season
  history$credits <- slot$credits
  history$source_url <- slot$source_url
  history$note <- paste(slot$season_label, "examples from CEDAR's Gen Ed list.", history$note,
                        "Matching-season rows only.")
  history$credit_note <- if (slot$credits < slot_credits) {
    paste(slot$credits, "credits left to allocate, rather than a complete course. Larger choices require a revised plan.")
  } else {
    paste(slot$credits, "credits reserved. Courses marked Needs more credits require moving credits from another slot.")
  }
  if (history$state != "ready") return(history)
  history$table <- get_gen_ed_planning_options(sections, history, gen_ed, slot$season, slot_credits) %>%
    mutate(credit_label = degree_credit_label(credits_min, credits_max),
           credit_fit = if_else(credits_max <= slot$credits, "Within allowance", "Needs more credits")) %>%
    select(subject_course, course_title, area_label, credit_label, campus, college, part_term,
      capacity, first_day_enrl, first_day_fill, term, season_frequency, credit_fit, pressure_status,
      credits_min, credits_max)
  if (!nrow(history$table)) history$state <- "empty"
  # A suggestion needs only this aggregate table, not the full multi-term history.
  history[c("pressure", "terms", "frequency", "offerings", "coverage")] <- NULL
  history
}

#' Readable preview of the same aggregate suggestions displayed in the popup.
format_degree_allowance_preview <- function(history) {
  lines <- c(paste(tools::toTitleCase(history$season), "Gen Ed suggestions"), history$credit_note, history$note)
  if (history$state != "ready") return(paste(c(lines, "No suggestions with usable history."), collapse = "\n"))
  top <- head(history$table, 12L)
  rows <- paste(top$subject_course, top$campus, top$college, top$part_term,
    vapply(top$term, fmt_term, character(1)), paste(top$credit_label, "credits"), top$credit_fit,
    paste("seats", top$capacity, "→ first day", top$first_day_enrl), top$season_frequency, sep = " · ")
  paste(c(lines, rows), collapse = "\n")
}
