# Semester roadmap payloads and descriptive observed course mix.

plot_grouped_student_paths <- function(paths) {
  cells <- paths$cells %>% dplyr::mutate(
    display_group = paste(group_label, campus, sep = " · "),
    hover = dplyr::if_else(suppressed, "Suppressed: insufficient students",
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
  m <- paths$meta
  paths$note <- paste0(description, ": ", format(m$n_observed, big.mark = ","),
    " observed students from ", format(m$n_population, big.mark = ","), " population members. Through ",
    fmt_term(m$analysis_through), ". First observed enrolled term = 1. ",
    m$n_left_boundary, " students begin at the data boundary. ", m$n_unmapped_rows,
    " of ", m$n_course_rows, " course records are unmapped. ", m$n_suppressed,
    " cells suppressed (minimum ", m$min_band_n, " students per campus/term and ", m$min_n, " per positive cell).")
  paths
}

#' Presentation payload: one degree with a consistent, adaptive semester board
build_degree_roadmap_view <- function(catalog, roadmaps, catalog_id, math_start, english_start, start_season = "fall") {
  view <- build_degree_roadmap(catalog, roadmaps, catalog_id, math_start, english_start)
  view$start_season <- start_season
  view$terms$season <- degree_semester_seasons(view$terms$semester, start_season)
  slots <- build_degree_allowance_slots(view$nodes, view$terms, as.numeric(view$policy$allowance_slot_credits))
  slots$season <- view$terms$season[match(slots$semester, view$terms$semester)]
  slots$season_label <- tools::toTitleCase(slots$season)
  slots$kind <- rep("allowance", nrow(slots))
  slots$code <- rep("Gen Ed / lower-level elective", nrow(slots))
  slots$title <- ifelse(slots$credits < as.numeric(view$policy$allowance_slot_credits),
    "Credits left to allocate", "Suggested course slot")
  slots$detail <- vapply(seq_len(nrow(slots)), function(i) paste0(slots$credits[i],
    " credits reserved. Browse recent ", slots$season[i],
    " Gen Ed offerings. Suggestions need individual prerequisites and a degree audit; no course has been selected."), character(1))
  slots$source_url <- rep(view$policy$gen_ed_source_url, nrow(slots))
  view$allowances <- slots
  view$n_rows <- max(view$nodes$row, slots$row)
  view$title <- paste(view$catalog$degree_label, "·", view$catalog$catalog_year)
  view$math_note <- paste0(view$math_target$code, " starts in semester ", view$math_target$semester, ".")
  view$change_note <- paste0(nrow(view$terms), " semesters · ", view$policy$normal_load,
    " credits usual · ", view$policy$max_load, " maximum")
  upper_start <- as.integer(view$policy$upper_level_from_semester)
  view$timing_note <- paste0("Planning preference: prioritize Gen Ed in semesters 1–", upper_start - 1L,
    "; upper-level courses start in semester ", upper_start, " or later. Allowances still need a degree audit.")
  view$terms$other_label <- ifelse(view$terms$other_phase == "foundation",
    "Gen Ed / lower-level electives", "Upper-level / minor / electives")
  view$workload_note <- paste0("Planning workload: ", view$degree_credits, " degree credits − ",
    view$completed_credits, " already completed + ",
    view$preparation_credits, " preparation credits. ", view$policy$assumption)
  view$note <- "Illustrative plan: specific choices, admission, offerings, transfer credit and a complete degree audit still need review. Colors describe prerequisites in this selected route, not eligibility or course difficulty."
  n <- view$nodes
  options <- roadmaps$options[roadmaps$options$catalog_id == catalog_id, ]
  options$credit_label <- ifelse(options$credits_min == options$credits_max, options$credits_min,
    paste0(options$credits_min, "–", options$credits_max))
  options$course_level <- course_level_from_number(options$subject_course)
  proof <- catalog$evidence[match(options$requisite_evidence_id, catalog$evidence$evidence_id), ]
  options$prerequisite_note <- ifelse(nzchar(options$requisite_evidence_id), proof$quote, "")
  view$options <- options
  groups <- options %>% group_by(catalog_id, node_id, option_id) %>%
    summarize(option_code = paste(subject_course, collapse = " + "),
      component_count = n(), credits_min = sum(as.numeric(credits_min)),
      credits_max = sum(as.numeric(credits_max)), .groups = "drop")
  groups <- groups[order(match(paste(groups$node_id, groups$option_id),
    paste(options$node_id, options$option_id))), ]
  groups$credit_label <- ifelse(groups$credits_min == groups$credits_max, groups$credits_min,
    paste0(groups$credits_min, "–", groups$credits_max))
  view$option_groups <- groups
  n$option_count <- integer(nrow(n)); n$option_label <- n$option_codes <- rep("", nrow(n))
  for (i in seq_len(nrow(n))) {
    choices <- options[options$node_id == n$node_id[i], ]
    if (!nrow(choices)) next
    alternatives <- groups[groups$node_id == n$node_id[i], ]
    n$option_count[i] <- nrow(alternatives)
    n$option_label[i] <- paste("Choose", choices$minimum[1], "of", nrow(alternatives),
      if (any(alternatives$component_count > 1L)) "options" else "courses")
    n$option_codes[i] <- paste(alternatives$option_code, collapse = ", ")
  }
  labels <- c(major = "Major", support = "Math / support", writing = "English",
              choice = "Course choice", preparation = "Preparation")
  n$kind_label <- unname(labels[n$kind])
  n$is_suggested <- n$basis == "general"
  n$kind_label[n$is_suggested] <- "Suggested Gen Ed"
  n$kind_label <- paste0(n$kind_label, ifelse(n$course_level == "upper", " · Upper-level", ""))
  for (i in which(n$option_count > 0L)) {
    choices <- options[options$node_id == n$node_id[i], ]
    if (length(unique(choices$course_level)) > 1L) n$kind_label[i] <- "Course choice · Level varies"
  }
  n$condition_label <- vapply(n$node_id, function(id)
    paste(view$conditions$label[view$conditions$node_id == id], collapse = " · "), character(1))
  n$prerequisite_label <- ifelse(n$kind == "choice", "Prerequisites vary",
    ifelse(n$n_conditions > 0L & n$n_prerequisites == 0L, "Prior coursework / permission",
      paste(n$n_prerequisites, ifelse(n$n_prerequisites == 1L, "prereq", "prereqs"))))
  n$planning_note <- ifelse(n$kind == "choice", "Prerequisites depend on the course chosen.",
    paste0(n$n_prerequisites, " prerequisite courses in this route (", n$n_direct,
      " direct); longest prerequisite sequence needs ", n$prereq_depth, " earlier semesters."))
  n$planning_note[n$n_conditions > 0L] <- paste0(n$n_prerequisites[n$n_conditions > 0L],
    " named prerequisite courses in the displayed chain. Additional conditions: ",
    n$condition_label[n$n_conditions > 0L], ". A course-count condition can be met by different courses.")
  n$planning_note <- paste0(n$planning_note, ifelse(n$course_level == "upper",
    paste0(" Upper-level planning starts in semester ", upper_start, "."), ""))
  has_options <- n$option_count > 0L
  n$planning_note[has_options] <- paste0(n$option_label[has_options], ". ", n$credits[has_options],
    " credits reserved in this illustrative plan; prerequisites and credit hours depend on the selection.")
  n$chain_note <- paste0("Named-course chain: ", n$chain_terms,
    ifelse(n$chain_terms == 1L, " stage", " stages"), " · leads to ", n$n_downstream, " later courses")
  n$chain_note[n$n_conditions > 0L & n$n_prerequisites == 0L & n$n_downstream == 0L] <- ""
  n$chain_badge <- ifelse(n$kind == "choice", "Choose course first",
    ifelse(n$n_downstream > 0 & n$n_prerequisites == 0,
      paste0("Chain start → ", n$n_downstream, " later"),
      paste0("→ ", n$n_downstream, " later · ", n$chain_terms, ifelse(n$chain_terms == 1L, " stage", " stages"))))
  n$chain_badge[n$n_conditions > 0L & n$n_prerequisites == 0L & n$n_downstream == 0L] <- "◇ Enrollment conditions"
  n$requisite_note <- vapply(n$node_id, function(id) {
    if (any(options$node_id == id)) return("Choose from the complete list above; review the individual course prerequisites and any variable credits before planning that selection.")
    incoming <- view$links[view$links$to == id, ]
    if (!nrow(incoming)) return(if (any(view$conditions$node_id == id))
      "Meet the conditions shown above before enrolling. Highlighted options can contribute; they are not all required."
      else "No earlier course is shown in this selected route; placement and other restrictions still apply.")
    paste(vapply(seq_len(nrow(incoming)), function(k) {
      code <- n$code[match(incoming$from[k], n$node_id)]
      paste(code, if (incoming$timing[k] == "before") "before" else "before or together")
    }, character(1)), collapse = "; ")
  }, character(1))
  view$nodes <- n
  view
}

#' Canonical readable preview of the same semester payload used by Shiny
format_degree_explorer_preview <- function(view) {
  paste(c(view$title, view$math_note, view$change_note, view$timing_note, vapply(view$terms$semester, function(term) {
    courses <- view$nodes[view$nodes$semester == term, ]
    paste(c(paste("Semester", term, "·", view$terms$planned_credits[view$terms$semester == term], "credits planned"),
            ifelse(courses$option_count > 0L,
              paste(courses$option_label, courses$option_codes, courses$title, sep = " · "),
              paste(courses$code, courses$title, sep = " · ")),
            paste(view$terms$other_label[view$terms$semester == term], ":",
              view$terms$other_credits[view$terms$semester == term], "credits")), collapse = "\n")
  }, character(1)), view$workload_note, view$note), collapse = "\n\n")
}
#' Assemble history for a selected tile; authored components distinguish bundles
#' from unresolved choices and never infer historical course equivalences.
build_degree_course_history <- function(sections, students, edges, roadmaps, catalog_id, node_id) {
  node <- roadmaps$nodes[roadmaps$nodes$catalog_id %in% c("*", catalog_id) &
    roadmaps$nodes$node_id == node_id, ]
  if (nrow(node) != 1L) stop("Unknown degree course selection")
  components <- roadmaps$courses$subject_course[roadmaps$courses$catalog_id %in% c("*", catalog_id) &
    roadmaps$courses$node_id == node_id]
  options <- roadmaps$options$subject_course[roadmaps$options$catalog_id == catalog_id & roadmaps$options$node_id == node_id]
  if (length(options)) components <- unique(options)
  if (!length(components)) return(list(state = "choice", node_id = node_id,
    note = "Choose a specific course in this group before checking offering history or seat pressure."))
  history <- get_course_planning_history(sections, students, components, edges)
  if (length(options)) history$note <- paste("History for the alternatives, with each course shown separately.", history$note)
  history$node_id <- node_id
  if (history$state != "ready") return(history)
  # One typed table, retaining the exact component/campus/college/session grain.
  history$table <- history$offerings %>%
    add_term_type_col("term") %>%
    left_join(history$frequency %>% select(campus, subject_course, term_type, offered_terms, eligible_terms),
      by = c("campus", "subject_course", "term_type"), relationship = "many-to-one") %>%
    mutate(term_label = vapply(term, fmt_term, character(1)),
      season_frequency = if_else(eligible_terms > 0L, paste(offered_terms, "of", eligible_terms), "Unknown")) %>%
    arrange(desc(term), subject_course, campus, college, part_term) %>%
    select(term, term_label, subject_course, campus, college, part_term, capacity,
      first_day_enrl, first_day_fill, pressure_status, season_frequency)
  history
}

#' Resolve a clicked card against the current plan, never client-supplied credits.
build_degree_popup_history <- function(sections, students, edges, catalog, roadmaps, gen_ed, selection) {
  if (!selection$type %in% c("course", "allowance")) stop("Unknown degree card type")
  if (selection$type == "course") {
    history <- build_degree_course_history(sections, students, edges, roadmaps,
      selection$catalog_id, selection$node_id)
    history$kind <- "course"
    return(history)
  }
  view <- build_degree_roadmap_view(catalog, roadmaps, selection$catalog_id,
    selection$math_start, selection$english_start, selection$start_season)
  slot <- view$allowances[view$allowances$node_id == selection$node_id, ]
  if (nrow(slot) != 1L) stop("Unknown degree allowance slot")
  # Entry routes, fixed courses and enumerated choice pools already have their
  # own places. Do not suggest them a second time as additional degree credit.
  ids <- degree_roadmap_node_ids(roadmaps, selection$catalog_id)
  excluded <- c(roadmaps$courses$subject_course[roadmaps$courses$catalog_id %in% c("*", selection$catalog_id) &
    roadmaps$courses$node_id %in% ids],
    roadmaps$options$subject_course[roadmaps$options$catalog_id == selection$catalog_id])
  pool <- setdiff(gen_ed$subject_course, excluded)
  h <- get_course_planning_history(sections, students, pool, edges)
  h$kind <- "allowance"; h$node_id <- slot$node_id
  h$season <- slot$season; h$credits <- slot$credits
  h$source_url <- slot$source_url
  h$note <- paste(slot$season_label, "examples from CEDAR's Gen Ed list.", h$note, "Matching-season rows only.")
  h$credit_note <- if (slot$credits < as.numeric(view$policy$allowance_slot_credits))
    paste(slot$credits, "credits left to allocate, rather than a complete course. Larger choices require a revised plan.")
    else paste(slot$credits, "credits reserved. Courses marked Needs more credits require moving credits from another slot.")
  if (h$state != "ready") return(h)
  h$table <- get_gen_ed_planning_options(sections, h, gen_ed, slot$season,
    as.numeric(view$policy$allowance_slot_credits))
  h$table$credit_label <- ifelse(h$table$credits_min == h$table$credits_max, h$table$credits_min,
    paste0(h$table$credits_min, "–", h$table$credits_max))
  h$table$credit_fit <- ifelse(h$table$credits_max <= slot$credits, "Within allowance", "Needs more credits")
  h$table <- h$table %>% select(subject_course, course_title, area_label, credit_label,
    campus, college, part_term, capacity, first_day_enrl, first_day_fill, term,
    season_frequency, credit_fit, pressure_status, credits_min, credits_max)
  if (!nrow(h$table)) h$state <- "empty"
  # A suggestion needs only this aggregate table, not the full multi-term history.
  h[c("pressure", "terms", "frequency", "offerings", "coverage")] <- NULL
  h
}

#' Readable preview of the same aggregate suggestions displayed in the popup.
format_degree_allowance_preview <- function(history) {
  lines <- c(paste(tools::toTitleCase(history$season), "Gen Ed suggestions"), history$credit_note, history$note)
  if (history$state != "ready") return(paste(c(lines, "No suggestions with usable history."), collapse = "\n"))
  x <- head(history$table, 12L)
  rows <- paste(x$subject_course, x$campus, x$college, x$part_term,
    vapply(x$term, fmt_term, character(1)), paste(x$credit_label, "credits"), x$credit_fit,
    paste("seats", x$capacity, "→ first day", x$first_day_enrl), x$season_frequency, sep = " · ")
  paste(c(lines, rows), collapse = "\n")
}
