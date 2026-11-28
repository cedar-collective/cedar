# Semester roadmap payloads and descriptive observed course mix.

#' What each course is to a Pathways population: the course grid's groups
#'
#' @param population build_population() output; its focal programs name the
#'   majors whose degree plans are read.
#' @param population_opt The options it was built from, which name its departments.
#' @param programs cedar_programs.
#' @param dims build_cedar_dims() output.
#' @param courses,course_codes `cedar_courses`, `cedar_course_codes`.
#' @param boards publish_degree_drafts() output, or NULL to read no plan.
#' @return list(`groups`: course_path_roles() over every course; `marks`:
#'   degree_plan_course_marks()'s courses, a choice's options included;
#'   `plans`: the degree plans read; `department_subjects`).
population_course_roles <- function(population, population_opt, programs, dims, courses, course_codes,
                                    boards = NULL) {
  subjects <- resolve_pathways_focal_subjects(population_opt, programs, dims)
  majors <- attr(population, "focal_programs")$codes$program_code
  marks <- if (is.null(boards) || length(majors) == 0L) {
    list(courses = tibble::tibble(subject_course = character(), in_plan = character()), plans = character(0))
  } else degree_plan_course_marks(boards, majors, programs, course_codes, include_options = TRUE)
  described <- describe_courses(courses$course_id, courses, course_codes)
  list(groups = course_path_roles(courses$course_id, subjects, marks$courses$subject_course,
                                  described$subject_course[!is.na(described$gen_ed_area)]),
       marks = marks$courses, plans = marks$plans, department_subjects = sort(subjects))
}

#' The arrivals a population's course paths start from
#'
#' student_term_entry_type() over the population's own declarations: each
#' term the registrar recorded a student as new, first-time or transfer.
#'
#' @param programs cedar_programs.
#' @param population build_population() output.
#' @return student_term_entry_type()'s rows for the population's students.
course_path_arrivals <- function(programs, population) {
  student_term_entry_type(programs[programs$student_id %in% population$student_id, ])
}

#' Course paths for a Pathways population, by what each course is to it
#'
#' The Pathways population, never a second, hidden major filter. Each
#' student's path starts at their arrival and the paths are split first-time
#' and transfer (get_grouped_student_paths()'s `arrivals`).
#'
#' @param students cedar_registrations.
#' @param population,population_opt The Pathways population and its options.
#' @param programs,dims,courses,course_codes,boards As population_course_roles().
#' @param opt get_grouped_student_paths()'s options.
#' @param description The population, as the page describes it.
#' @return list(`paths`, split by arrival; `descriptions`: describe_courses()
#'   for every listed course with its `in_plan` mark; `plans`;
#'   `department_subjects`; `description`).
build_population_course_paths <- function(students, population, population_opt, programs, dims, courses,
                                          course_codes, boards, opt, description) {
  roles <- population_course_roles(population, population_opt, programs, dims, courses, course_codes, boards)
  paths <- get_grouped_student_paths(students, population, roles$groups, opt,
                                     arrivals = course_path_arrivals(programs, population))
  descriptions <- describe_courses(unique(paths$courses$subject_course), courses, course_codes) %>%
    left_join(roles$marks, by = "subject_course")
  list(paths = paths, descriptions = descriptions, plans = roles$plans,
       department_subjects = roles$department_subjects, description = description)
}

COURSE_PATH_ARRIVALS <- c(first_time = "first-time students", transfer = "transfer students")

#' What a Pathways population's course paths cover, as scope-bar facts
#'
#' @param payload build_population_course_paths() output.
#' @return A named list of strings, one scope chip each.
course_paths_scope_facts <- function(payload) {
  meta <- payload$paths$meta
  list(Population = payload$description,
       `Started first-time` = fmt_count(meta$n_observed_by_entry[["first_time"]]),
       `Transferred in` = fmt_count(meta$n_observed_by_entry[["transfer"]]),
       `No start on record` = fmt_count(meta$n_no_arrival),
       Through = fmt_term(meta$analysis_through),
       `Degree plans` = if (length(payload$plans)) paste(payload$plans, collapse = "; ") else "None compiled")
}

#' Why one arrival's course grid is empty, in the page's words
#'
#' @param meta The paths' meta (get_grouped_student_paths(), split by arrival).
#' @param entry_type "first_time" or "transfer".
#' @return One sentence.
course_paths_empty_note <- function(meta, entry_type) {
  if (sum(meta$n_observed_by_entry) == 0L) {
    n <- meta$n_no_arrival
    paste0("No student here has a start on record as a first-time or transfer student, so no path can begin. ",
           if (identical(as.integer(n), 1L)) "The one student with courses was" else paste0("All ", fmt_count(n), " with courses were"),
           " already here when the records begin, readmitted, or started at another level.")
  } else paste0("This population has no ", COURSE_PATH_ARRIVALS[[entry_type]], ".")
}

#' The course grid's run-specific method notes
#'
#' @param payload build_population_course_paths() output.
#' @param grid degree_path_course_grid() over one arrival's slice.
#' @return Character: one sentence each.
course_paths_method_notes <- function(payload, grid) {
  meta <- grid$meta
  subjects <- payload$department_subjects
  c(if (length(subjects)) paste0("Their department's courses are those in ", paste(subjects, collapse = ", "), ".")
    else "This population names no department, so no course is counted as theirs.",
    if (length(payload$plans)) paste0(sub("([^.])$", "\\1.", paste0("The degree plans read are ", paste(payload$plans, collapse = "; "))),
      " A plan compiled from the catalog is a draft until a reviewer signs it off.")
    else "No degree plan has been compiled for these majors, so no course is counted as named by one.",
    paste0(fmt_count(meta$n_no_arrival), " of the population's students with courses have no start on record: ",
           "they were here before the records begin, were readmitted, or started at another level. They are left out."),
    paste0("A term needs ", meta$min_band_n, " students on a campus to be shown, and a cell, a course or a subject ",
           meta$min_n, " students; ", fmt_count(sum(grid$cells$suppressed)), " cells are withheld."),
    paste0("Through ", fmt_term(meta$analysis_through), ", the last term whose enrollment is settled."))
}

# The course grid's shading steps, by a cell's share of the term's students,
# and the key's words for them.
COURSE_PATH_SHADE_BREAKS <- c(10, 25, 50, 75)
COURSE_PATH_SHADE_LABELS <- c(
  paste0("Under ", COURSE_PATH_SHADE_BREAKS[1], "%"),
  paste0(utils::head(COURSE_PATH_SHADE_BREAKS, -1), "\u2013", COURSE_PATH_SHADE_BREAKS[-1], "%"),
  paste0(utils::tail(COURSE_PATH_SHADE_BREAKS, 1), "% or more"))

#' The course grid's cells as the page and the text preview show them
#'
#' The one place the grid's numbers are rounded and its cells worded.
#'
#' @param grid degree_path_course_grid() output.
#' @return The grid's cells with `shade` (0 to 4, the step of
#'   COURSE_PATH_SHADE_BREAKS its share is in; NA where withheld), `share`, `of`, `items` (a list of
#'   "CODE x.x%" strings), `more` and `note` (a withheld, empty or
#'   unlistable cell's words, in place of the others).
course_path_grid_view <- function(grid) {
  meta <- grid$meta
  pct <- function(x) sprintf("%.1f%%", x)
  noun <- function(detail, n) paste0(if_else(detail == "subject", "subject", "course"), if_else(n == 1L, "", "s"))
  listed <- grid$items %>%
    group_by(campus, group_id, relative_term) %>%
    summarize(items = list(paste(item, pct(pct_students))), .groups = "drop")
  grid$cells %>%
    left_join(listed, by = c("campus", "group_id", "relative_term")) %>%
    mutate(
      empty = !suppressed & n_students == 0L,
      unlisted = !suppressed & !empty & n_shown == 0L,
      shade = if_else(suppressed, NA_integer_, findInterval(pct_students, COURSE_PATH_SHADE_BREAKS)),
      share = if_else(suppressed | empty, NA_character_, pct(pct_students)),
      of = if_else(band_suppressed, NA_character_, paste("of", fmt_count(n_eligible))),
      note = case_when(
        band_suppressed ~ paste("Fewer than", meta$min_band_n, "students this term"),
        suppressed ~ paste("Fewer than", meta$min_n, "students took one"),
        empty ~ "None took one",
        unlisted ~ paste0(fmt_count(n_more), " ", noun(detail, n_more), ", ",
                          if_else(n_more == 1L, "taken", "each taken"), " by fewer than ", meta$min_n, " students"),
        TRUE ~ NA_character_),
      more = if_else(is.na(note) & n_more > 0L, paste0("+", fmt_count(n_more), " more ", noun(detail, n_more)), NA_character_),
      items = lapply(items, function(x) if (is.null(x)) character(0) else x)) %>%
    select(-empty, -unlisted)
}

#' The course grid as text, before its page
#'
#' @param grid degree_path_course_grid() output, one arrival's.
#' @param description The population, as the page describes it.
#' @param plans The degree plans read.
#' @return One string.
format_degree_path_course_grid <- function(grid, description, plans = character(0)) {
  meta <- grid$meta
  who <- if (is.null(meta$entry_type)) "observed students" else COURSE_PATH_ARRIVALS[[meta$entry_type]]
  if (identical(as.integer(meta$n_observed), 1L)) who <- sub("students$", "student", who)
  view <- course_path_grid_view(grid)
  lines <- c(
    paste0(description, ": ", fmt_count(meta$n_observed), " ", who, " of ", fmt_count(meta$n_population),
           " in the population, through ", fmt_term(meta$analysis_through), ". ",
           if (isTRUE(meta$split_entry)) "Term 1 is the term they started." else "Term 1 is each student's first observed enrolled term."),
    paste0("A cell is the share of the campus's students that term who took a course of that kind, then its ", meta$n_top,
           " most-taken ", paste0("courses (subjects for ", paste(COURSE_PATH_ROLES[meta$by_subject], collapse = ", "), ")"),
           ", each with its own share; \"+N more\" counts the rest."),
    if (length(plans)) sub("([^.])$", "\\1.", paste0("Degree plans read: ", paste(plans, collapse = "; ")))
    else "No degree plan has been compiled for these majors.")
  for (campus in unique(view$campus)) {
    lines <- c(lines, "", campus)
    on_campus <- view[view$campus == campus, ]
    for (group in unique(on_campus$group_id)) {
      rows <- on_campus[on_campus$group_id == group, ]
      lines <- c(lines, paste0("  ", rows$group_label[1]))
      for (i in seq_len(nrow(rows))) {
        r <- rows[i, ]
        cell <- if (!is.na(r$note) && is.na(r$share)) r$note else
          paste0(r$share, " ", r$of, ": ", if (!is.na(r$note)) r$note else
            paste(c(r$items[[1]], stats::na.omit(r$more)), collapse = ", "))
        lines <- c(lines, sprintf("    Term %-2d %s", r$relative_term, cell))
      }
    }
  }
  paste(lines, collapse = "\n")
}

# "3" or "3–4": a credit range as the catalog states it.
degree_credit_label <- function(credits_min, credits_max) {
  ifelse(credits_min == credits_max, as.character(credits_min), paste0(credits_min, "–", credits_max))
}

#' Readable rules from the exact catalog/template/graph used by this scenario
#' These describe the running prototype; no independent catalog parser or AI
#' proposal is consulted, and recorded policies are not called eligibility checks.
build_degree_plan_rules <- function(catalog, roadmaps, view) {
  rows <- list()
  add <- function(kind, rule, effect, url = "", quote = "", ids = "") {
    rows[[length(rows) + 1L]] <<- data.frame(kind = kind, rule = rule, effect = effect,
      source_url = url, quote = quote, node_ids = ids, stringsAsFactors = FALSE)
  }
  program <- view$catalog; policy <- view$policy
  outline <- degree_rule_outline(catalog, program$catalog_id)
  for (i in seq_len(nrow(outline))) add("Recorded catalog requirement", outline$text[i],
    "Recorded in the prototype; admission, GPA and degree completion are not evaluated.", program$source_url)
  add("Banner program codes", view$program_codes_note,
    "Names the students this degree describes, so it is not confused with another degree in the same field. The roadmap reads no student records.")

  # Identical pool slots share a readable rule but retain every underlying ID.
  nodes <- view$nodes
  keys <- paste(nodes$code, nodes$kind, nodes$basis, nodes$evidence_quote, sep = "\r")
  groups <- split(seq_len(nrow(nodes)), factor(keys, levels = unique(keys)))
  for (indices in groups) {
    node <- nodes[indices[1], ]; n <- length(indices)
    options <- view$option_groups[view$option_groups$node_id == node$node_id, ]
    label <- if (nrow(options)) paste0(node$option_label, ": ", paste(options$option_code, collapse = "; "), ".")
      else if (n > 1L) paste0(n, " slots from ", node$code, " (", sum(nodes$credits[indices]), " planned credits).")
      else paste0(node$code, " — ", node$title, " (", node$credits, " planned credits).")
    label <- paste(label, node$basis_explanation,
      if (nzchar(node$requirement_summary)) node$requirement_summary else "")
    effect <- if (node$kind == "choice") "Course choice remains open; no particular option's prerequisites are assumed."
      else if (node$basis == "general") "Illustrative general requirement choice; this degree does not require this particular course."
      else if (node$basis == "prerequisite") "Preparation included for the selected starting point."
      else "Course or selected example included in this scenario."
    add(if (node$basis == "general") "Suggested general coursework" else if (node$basis == "prerequisite") "Preparation"
      else if (node$kind == "choice") "Course group" else "Course shown", label, effect,
      node$evidence_source_url, node$evidence_quote, paste(nodes$node_id[indices], collapse = "|"))
  }
  for (i in seq_len(nrow(view$links))) {
    link <- view$links[i, ]; evidence <- catalog$evidence[match(link$evidence_id, catalog$evidence$evidence_id), ]
    from <- nodes$code[match(link$from, nodes$node_id)]; to <- nodes$code[match(link$to, nodes$node_id)]
    add("Prerequisite arrow", paste0(from, if (link$timing == "before") " must precede " else " must precede or be taken with ", to, ". ", link$detail),
      "This timing constraint is used by the scheduler for the selected route.", evidence$source_url, evidence$quote, paste(link$from, link$to, sep = "|"))
  }
  for (i in seq_len(nrow(view$conditions))) {
    condition <- view$conditions[i, ]; code <- nodes$code[match(condition$node_id, nodes$node_id)]
    add("Other enrollment condition", paste(code, "requires", condition$label),
      if (condition$kind == "course_count") "The scheduler places enough qualifying slots earlier; these are not named-course prerequisite arrows."
      else "Shown as a condition; the prototype cannot establish permission or admission.",
      condition$source_url, condition$quote, condition$node_id)
  }
  evidence <- catalog$evidence[match(policy$evidence_id, catalog$evidence$evidence_id), ]
  add("Degree workload", paste0("Plan toward ", policy$degree_credit_target, " degree credits."), view$workload_note,
    evidence$source_url, evidence$quote)
  if (!is.null(view$shared)) {
    for (i in seq_len(nrow(view$shared$areas))) {
      area <- view$shared$areas[i, ]
      assigned <- view$shared$assigned[view$shared$assigned$area == area$area, ]
      add("Shared Gen Ed allocation", paste0("Area ", area$area, ": ", area$label, " — ", area$minimum, " credits minimum",
          if (area$minimum > area$university_minimum) paste0(" (this program's own; the University asks for ", area$university_minimum, ")"), "."),
        paste0(area$planned, " planned credits represented by ",
          if (nrow(assigned)) paste(assigned$courses, collapse = "; ") else "no selected course", "; ",
          area$remaining, " credits still earmarked in open space. Credits are counted once; open choices/transfer can change coverage."),
        if (area$minimum > area$university_minimum) view$catalog$source_url else area$source_url,
        ids = paste(assigned$node_id[nzchar(assigned$node_id)], collapse = "|"))
    }
    add("Shared allocation limits", view$shared$note, "Planned coverage only. Grades, approvals and transfer are not evaluated.")
    if (!is.null(view$shared$upper)) add("Shared college requirement", view$shared$upper$statement,
      paste(view$shared$upper$planned, "upper-level credits shown;", view$shared$upper$remaining,
        "more to fit within existing elective/minor space. Conditional alternatives are not automatically selected."), view$shared$upper$source_url)
  }
  for (label in unique(view$allowances$code)) {
    slots <- view$allowances[view$allowances$code == label, ]
    add("Allowance purpose", paste(label, "—", sum(slots$credits), "credits reserved."), slots$detail[1],
      slots$source_url[1], ids = paste(slots$node_id, collapse = "|"))
  }
  add("Planning preference", paste0("Usually ", policy$normal_load, " credits; never more than ", policy$max_load, " in a semester."),
    "CEDAR planning setting. Extend the plan when prerequisites or workload require it.")
  add("Planning preference", paste0("Prioritize Gen Ed in semesters 1–", as.integer(policy$upper_level_from_semester) - 1L,
    "; schedule upper-level work from semester ", policy$upper_level_from_semester, " and ",
    COURSE_SENIOR_LEADING_DIGIT, "00-level work from semester ", policy$senior_level_from_semester, "."),
    "CEDAR planning setting, rather than a catalog prerequisite.")
  for (i in which(nodes$catalog_id == program$catalog_id)) add("Planning preference",
    paste0(nodes$code[i], ": preferred starting semester ", nodes$base_semester[i], "."),
    paste0("Authored template position; prerequisites, upper-level timing and the credit limit may move it later. Related courses align in the ", nodes$row_group[i], " row."),
    ids = nodes$node_id[i])
  add("Planning preference", "Fill existing workload space with identified Gen Ed areas, then elective/minor credits. Gen Ed sits at the top, then math and writing, then elective/minor space, then the program's own courses.",
    "Elective space does not have to be Gen Ed or lower level. Upper-level entry conditions still apply. Overlapping requirements never add credits to the budget.")
  math_choices <- degree_math_start_choices(roadmaps, program$catalog_id)
  list(title = view$title, source_url = program$source_url, note = program$notes,
    scenario = paste("Math:", names(math_choices)[match(view$starts[["math"]], unname(math_choices))],
      "· English:", roadmaps$starts$label[match(view$starts[["english"]], roadmaps$starts$start_id)]),
    rows = do.call(rbind, rows))
}

#' Presentation payload: one degree with a consistent, adaptive semester board
build_degree_roadmap_view <- function(catalog, roadmaps, catalog_id, math_start, english_start,
                                      start_season = "fall", shared = NULL) {
  view <- build_degree_roadmap(catalog, roadmaps, catalog_id, math_start, english_start)
  view <- allocate_shared_degree_slots(view, degree_shared_coverage(view, roadmaps, shared))
  upper_start <- as.integer(view$policy$upper_level_from_semester)
  senior_start <- as.integer(view$policy$senior_level_from_semester)
  view$start_season <- start_season
  view$terms$season <- degree_semester_seasons(view$terms$semester, start_season)
  view$terms$other_label <- ifelse(view$terms$other_phase == "foundation",
    "Gen Ed where identified; other elective / minor credits", "Elective / minor · upper level may count")
  view$allowances <- build_degree_allowance_tiles(view)
  view$n_rows <- max(view$nodes$row, view$allowances$row)
  view$options <- degree_option_courses(roadmaps, catalog, catalog_id)
  view$option_groups <- degree_option_groups(view$options)
  view$nodes <- label_degree_roadmap_nodes(view$nodes, view$options, view$option_groups,
                                           view$conditions, view$links, upper_start, senior_start)
  view$nodes$coverage_label <- ""
  view$nodes$coverage_detail <- ""
  if (!is.null(view$shared)) for (i in seq_len(nrow(view$nodes))) {
    node <- view$nodes[i, ]
    # A lecture and lab counted as one pair carry both ids ("chem_1215|chem_1215l").
    assigned <- view$shared$assigned[vapply(strsplit(view$shared$assigned$node_id, "|", fixed = TRUE),
                                            function(ids) node$node_id %in% ids, TRUE), ]
    possible <- unique(view$shared$memberships$area[view$shared$memberships$subject_course %in%
      view$options$subject_course[view$options$node_id == node$node_id]])
    if (nrow(assigned)) {
      labels <- view$shared$areas$label[match(assigned$area, view$shared$areas$area)]
      labels[assigned$area == view$shared$flexible_area] <- paste(labels[assigned$area == view$shared$flexible_area], "(provisional)")
      view$nodes$coverage_label[i] <- paste("Also Gen Ed ·", paste(labels, collapse = ", "))
      view$nodes$coverage_detail[i] <- paste("Illustrative Gen Ed coverage:",
        paste(paste(labels, assigned$credits, "credits"), collapse = "; "),
        ". These are the same course credits, counted once in the degree total. Grades and approvals still apply.")
    } else if (length(possible)) {
      view$nodes$coverage_label[i] <- paste("May also meet Gen Ed", paste(possible, collapse = "/"))
      view$nodes$coverage_detail[i] <- "Some options have Gen Ed approval. Choose a specific eligible option to replace matching Gen Ed allowance space; this open choice is not counted as completed coverage."
    }
  }

  view$title <- paste(view$catalog$degree_label, "·", view$catalog$catalog_year)
  # The math start's own course: none, or only preparation, when the program
  # names no course on the shared math route. A program's own math courses
  # (a teacher-education program's math for teachers) are its tiles, not the route's.
  target <- view$math_target
  view$math_note <- if (nrow(target) && !identical(target$kind, "preparation")) {
    paste0(target$code, " starts in semester ", target$semester, ".")
  } else if (nrow(target)) {
    paste0("This math starting point adds ", target$code, " in semester ", target$semester, ", as preparation.")
  } else {
    "This math starting point adds no math course to the plan."
  }
  view$change_note <- paste0(nrow(view$terms), " semesters · ", view$policy$normal_load,
    " credits usual · ", view$policy$max_load, " maximum")
  view$timing_note <- paste0("Planning preference: prioritize Gen Ed in semesters 1–", upper_start - 1L,
    "; required upper-level courses start in semester ", upper_start, " or later, and ",
    COURSE_SENIOR_LEADING_DIGIT, "00-level courses in semester ", senior_start, " or later. Other electives can be upper level when their entry requirements allow it.")
  # Flexible choices met by the program's own extra area credits sit inside
  # those areas' cards: counted once, in neither total.
  inside <- if (is.null(view$shared)) 0 else sum(view$shared$assigned$credits[!nzchar(view$shared$assigned$node_id)])
  view$coverage_note <- if (is.null(view$shared)) {
    "Shared Gen Ed coverage is not configured for this program. Elective boxes are unallocated credits, not additional Gen Ed requirements."
  } else paste0("Gen Ed: ", sum(view$shared$areas$planned) - inside, " of ", sum(view$shared$areas$minimum) - inside,
    " minimum credits represented by courses already shown or explicitly completed; ",
    sum(view$allowances$credits[view$allowances$purpose == "gen_ed"]), " credits earmarked in open space.",
    if (inside > 0) " The program's extra credits in its Gen Ed areas also count as the flexible Gen Ed choices.",
    " Other boxes do not have to be Gen Ed. Flexible-area coverage is provisional because catalog wording needs clarification. This is illustrative coverage, not a degree audit.")
  if (!is.null(view$shared$upper)) view$coverage_note <- paste(view$coverage_note,
    paste0("Standard college upper-level minimum: ", view$shared$upper$minimum, " credits; ",
      view$shared$upper$planned, " shown in named/upper-level choice slots; ", view$shared$upper$remaining,
      " more needed within the existing elective/minor space or approved overlapping choices. Conditional alternatives need advising."))
  if (!is.null(view$unplaced_gen_ed) && nrow(view$unplaced_gen_ed) > 0L) view$coverage_note <- paste(view$coverage_note,
    paste(sum(view$unplaced_gen_ed$credits), "Gen Ed credits could not fit a whole slot; redistribute existing allowances with an advisor."))
  view$workload_note <- paste0("Planning workload: ", view$degree_credits, " degree credits − ",
    view$completed_credits, " already completed + ",
    view$preparation_credits, " preparation credits. ", view$policy$assumption)
  view$program_codes_note <- degree_program_codes_note(catalog, catalog_id)
  view$note <- paste("Illustrative plan: specific choices, admission, offerings, transfer credit and a",
    "complete degree audit still need review. Colors describe prerequisites in this selected route,",
    "not eligibility or course difficulty.")
  view
}

# Banner gives a field's B.A. and B.S. separate program codes under one name;
# the degree names its own, as validated by degree_catalog_program_codes().
degree_program_codes_note <- function(catalog, catalog_id) {
  codes <- catalog$program_codes[catalog$program_codes$catalog_id == catalog_id, ]
  if (!nrow(codes)) stop("[degree-explorer.R] No Banner program codes for ", catalog_id)
  pre <- codes$program_code[codes$is_pre_major]
  paste0("Banner program codes for this degree: ", paste(codes$program_code[!codes$is_pre_major], collapse = ", "),
    if (length(pre)) paste0("; pre-major ", paste(pre, collapse = ", ")),
    ". Another degree in the same field, such as a B.A. beside a B.S., has codes of its own.")
}

#' Source-identified Gen Ed needs and flexible elective/minor allowance tiles
build_degree_allowance_tiles <- function(view) {
  slot_credits <- as.numeric(view$policy$allowance_slot_credits)
  slots <- view$allowances
  season <- view$terms$season[match(slots$semester, view$terms$semester)]
  slots$season <- season
  slots$season_label <- tools::toTitleCase(season)
  slots$phase <- view$terms$other_phase[match(slots$semester, view$terms$semester)]
  slots$kind <- rep("allowance", nrow(slots))
  slots$title <- ifelse(slots$credits < slot_credits, "Credits left to allocate",
    ifelse(slots$purpose == "gen_ed", "Remaining area in this example",
      ifelse(slots$phase == "advanced", "Any level · upper level may count", "Any level · Gen Ed not required")))
  if (!is.null(view$shared)) {
    possible <- view$shared$choice_areas
    slots$title[slots$purpose == "gen_ed" & slots$area %in% possible] <- "May be covered by a program choice"
  }
  slots$detail <- ifelse(slots$purpose == "gen_ed",
    paste(slots$credits, "credits earmarked for", slots$code,
      ". An eligible program choice or approved prior credit may cover this area; then use this space for another elective. Flexible coverage is provisional; language/studio approvals are not inferred."),
    paste(slots$credits, "unallocated degree credits. This does not have to be Gen Ed or lower division.",
      "It can contribute to a minor or the upper-level minimum. An upper-level course with no prerequisites could fit; verify its catalog entry conditions."))
  slots$source_url[slots$purpose != "gen_ed"] <- view$catalog$source_url
  slots
}

#' One pinned annual bundle, read at startup, rather than on every card click
load_degree_shared_requirements <- function(catalog, institution_dir) {
  years <- unique(catalog$catalogs$catalog_year)
  if (length(years) != 1L) return(NULL)
  directory <- file.path(institution_dir, "shared_requirements", years)
  if (!dir.exists(directory)) return(NULL)
  read_shared_requirement_bundle(directory)
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
label_degree_roadmap_nodes <- function(nodes, options, option_groups, conditions, links, upper_start, senior_start) {
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

  kind_labels <- c(major = "Major", cohort = "Required course block", support = "Math / support", writing = "English",
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
  upper_note <- ifelse(nodes$senior_level,
    paste0(" ", COURSE_SENIOR_LEADING_DIGIT, "00-level planning starts in semester ", senior_start, "."),
    ifelse(nodes$course_level == "upper", paste0(" Upper-level planning starts in semester ", upper_start, "."), ""))
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
      summary = paste(allowance$detail, allowance$season_label, "examples · no course selected."),
      course_url = allowance$source_url,
      course_link_label = if (allowance$purpose == "gen_ed") "Gen Ed area requirements" else "Degree credit requirements",
      program_url = view$catalog$source_url))
  }
  node <- view$nodes[view$nodes$node_id == node_id, ]
  if (nrow(node) != 1L) stop("[degree-explorer.R] Unknown degree roadmap tile: ", node_id)
  alternatives <- view$option_groups[view$option_groups$node_id == node_id, ]
  components <- view$options[view$options$node_id == node_id, ]
  list(type = "course", node_id = node_id, title = paste(node$code, "·", node$title), node = node,
    summary = paste(node$coverage_detail, if (nzchar(node$requirement_summary)) paste0(node$requirement_summary, ". ", node$option_label,
      ". Full choices and paired labs appear below the offering history.") else ""),
    course_url = node$source_url,
    course_link_label = if (node$kind == "choice") "Course group details" else "Course description",
    coverage_url = if (!is.null(view$shared) && nzchar(node$coverage_label)) view$shared$areas$source_url[1] else NULL,
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
          view$workload_note, view$note, view$program_codes_note), collapse = "\n\n")
}

#' Assemble history for a selected tile; authored components distinguish bundles
#' from unresolved choices and never infer historical course equivalences.
build_degree_course_history <- function(sections, course_terms, edges, roadmaps, catalog_id, node_id) {
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
  history <- get_course_planning_history(sections, course_terms, components, edges)
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
build_degree_popup_history <- function(sections, course_terms, edges, catalog, roadmaps, gen_ed, selection, shared = NULL) {
  if (!selection$type %in% c("course", "allowance")) stop("[degree-explorer.R] Unknown degree card type")
  if (selection$type == "course") {
    history <- build_degree_course_history(sections, course_terms, edges, roadmaps,
      selection$catalog_id, selection$node_id)
    history$kind <- "course"
    return(history)
  }
  view <- build_degree_roadmap_view(catalog, roadmaps, selection$catalog_id,
    selection$math_start, selection$english_start, selection$start_season, shared)
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
  if (slot$purpose == "gen_ed") {
    members <- view$shared$memberships
    members <- members[members$area == slot$area |
      (slot$area == view$shared$flexible_area & !members$area %in% view$shared$flexible_areas_used), ]
    # Open language/studio alternatives and paired labs require individual
    # review; no invented memberships or standalone-lab recommendations.
    pool <- data.frame(subject_course = members$subject_course, area_label = slot$code)
    if (slot$credits >= 4) pool <- pool[as.numeric(members$credits) >= slot$credits, ]
    levels <- c("lower", "upper")
  } else {
    # The pool is all undergraduate offerings, not just the Gen Ed subset.
    pool <- unique(sections[sections$level %in% c("lower", "upper"), "subject_course", drop = FALSE])
    membership <- if (is.null(view$shared)) gen_ed else transform(view$shared$memberships, area_label = paste("Area", area))
    pool$area_label <- vapply(pool$subject_course, function(course) {
      labels <- unique(membership$area_label[membership$subject_course == course])
      if (length(labels)) paste(labels, collapse = "; ") else "No listed area · optional"
    }, character(1))
    levels <- c("lower", "upper")
  }
  pool <- pool[!pool$subject_course %in% represented, ]
  history <- get_course_planning_history(sections, course_terms, pool$subject_course, edges)
  history$kind <- "allowance"
  history$node_id <- slot$node_id
  history$season <- slot$season
  history$credits <- slot$credits
  history$source_url <- slot$source_url
  history$note <- paste(slot$detail, history$note, "Matching-season rows only. Prerequisites have not been evaluated.")
  history$credit_note <- if (slot$credits < slot_credits) {
    paste(slot$credits, "credits left to allocate, rather than a complete course. Larger choices require a revised plan.")
  } else {
    paste(slot$credits, "credits reserved. Courses marked Needs more credits require moving credits from another slot.")
  }
  if (history$state != "ready") return(history)
  history$table <- get_gen_ed_planning_options(sections, history, pool, slot$season, slot_credits, levels) %>%
    mutate(credit_label = degree_credit_label(credits_min, credits_max),
           credit_fit = if_else(credits_max <= slot$credits, "Within allowance", "Needs more credits")) %>%
    select(subject_course, course_title, area_label, course_level, credit_label, campus, college, part_term,
      capacity, first_day_enrl, first_day_fill, term, season_frequency, credit_fit, pressure_status,
      credits_min, credits_max)
  if (!nrow(history$table)) history$state <- "empty"
  # A suggestion needs only this aggregate table, not the full multi-term history.
  history[c("pressure", "terms", "frequency", "offerings", "coverage")] <- NULL
  history
}

#' Readable preview of the same aggregate suggestions displayed in the popup.
format_degree_allowance_preview <- function(history) {
  lines <- c(paste(tools::toTitleCase(history$season), "course options"), history$credit_note, history$note)
  if (history$state != "ready") return(paste(c(lines, "No suggestions with usable history."), collapse = "\n"))
  top <- head(history$table, 12L)
  rows <- paste(top$subject_course, top$campus, top$college, top$part_term,
    vapply(top$term, fmt_term, character(1)), paste(top$credit_label, "credits"), top$credit_fit,
    paste("seats", top$capacity, "→ first day", top$first_day_enrl), top$season_frequency, sep = " · ")
  paste(c(lines, rows), collapse = "\n")
}
