# Degree Explorer: one degree at a time, shown as an adaptive semester roadmap.
#
# Scheduling, layout and chain metrics come from R/branches/degree-requirements.R
# and the display payload from R/features/degree-explorer.R. This file renders
# them. www/cedar-roadmap.js handles hover previews and connectors only; a
# click opens the standard CEDAR modal, rendered here from the same payload.

degreeExplorerUI <- function(id, catalog, roadmaps) {
  ns <- NS(id)
  if (!nrow(catalog$catalogs)) return(empty_state("No degree roadmaps are configured for this institution."))
  english <- roadmaps$starts[roadmaps$starts$track == "english", ]
  tagList(
    htmltools::htmlDependency("cedar-roadmap", "2.0.0", src = c(href = ""),
      stylesheet = "cedar-roadmap.css", script = "cedar-roadmap.js"),
    filter_bar("Build your degree roadmap", "Choose a degree and your starting courses. Watch the sequence change.",
      fluidRow(
        column(4, selectInput(ns("dx_catalog_id"), "Degree · latest catalog", choices = degree_catalog_choices(catalog))),
        column(3, selectInput(ns("dx_math_start"), "Where will you start in math?",
          choices = degree_math_start_choices(roadmaps, catalog$catalogs$catalog_id[1]))),
        column(3, selectInput(ns("dx_english_start"), "Where will you start in English?",
          choices = stats::setNames(english$start_id, english$label))),
        column(2, selectInput(ns("dx_start_season"), "First semester", choices = c(Fall = "fall", Spring = "spring")),
          filter_actions(actionButton(ns("dx_copy_url"), label = NULL, icon = icon("link"),
            title = "Copy shareable link for current view", class = "btn-outline-secondary btn-sm"))))),
    filter_actions(actionButton(ns("show_rules"), "Rules behind this plan", icon = icon("list"))),
    uiOutput(ns("roadmap")),
    tags$p(class = "text-hint", "Want to see what students actually take? Open Pathways → Course paths."))
}

degreeExplorerServer <- function(id, catalog, roadmaps, sections, students, edges, shared = NULL) {
  if (!nrow(catalog$catalogs)) return(invisible(NULL))
  moduleServer(id, function(input, output, session) {
    observeEvent(input$dx_catalog_id, {
      updateSelectInput(session, "dx_math_start",
        choices = degree_math_start_choices(roadmaps, input$dx_catalog_id),
        selected = isolate(input$dx_math_start))
    }, ignoreInit = TRUE)

    cedar_copy_url_observer(input, session, "dx_copy_url", spec_title = "Degree Explorer",
      values_fn = function() list(
        catalog_id = input$dx_catalog_id,
        math_start = input$dx_math_start,
        english_start = input$dx_english_start,
        start_season = input$dx_start_season))

    view <- reactive({
      req(input$dx_catalog_id, input$dx_math_start, input$dx_english_start, input$dx_start_season)
      tryCatch(
        build_degree_roadmap_view(catalog, roadmaps, input$dx_catalog_id,
          input$dx_math_start, input$dx_english_start, input$dx_start_season, shared),
        error = function(e) {
          showNotification(conditionMessage(e), type = "error", duration = NULL)
          NULL
        })
    })

    output$roadmap <- renderUI({
      current <- view()
      if (is.null(current)) return(empty_state("This roadmap could not be built; the notification explains why."))
      degree_semester_board(current, session$ns("semester_board"), select_id = session$ns("course_node"))
    })

    observeEvent(input$show_rules, {
      req(view())
      showModal(cedar_info_modal("Rules behind this plan",
        p("Generated from the same saved rules, courses, choices and prerequisite graph as the visualization. CEDAR planning preferences are labeled separately."),
        reactable::reactableOutput(session$ns("plan_rules")), size = "xl", scrollable = TRUE))
    })
    output$plan_rules <- reactable::renderReactable({
      req(view()); degree_plan_rules_table(build_degree_plan_rules(catalog, roadmaps, view())$rows)
    })

    # A click on a tile opens the popup. The board's own scenario travels with
    # the click, so a click on a board the inputs have since replaced is ignored.
    observeEvent(input$course_node, {
      selection <- input$course_node
      current <- view()
      req(current, identical(selection$catalog_id, current$catalog$catalog_id),
        identical(selection$math_start, current$starts[["math"]]),
        identical(selection$english_start, current$starts[["english"]]),
        identical(selection$start_season, current$start_season))
      detail <- degree_roadmap_tile_detail(current, selection$node_id)
      showModal(degree_tile_modal(detail, session$ns("course_history")))
    })

    # Source tables and edges are immutable for the session. Cache clicked cards
    # by the full selection, including season and entry context for suggestions.
    history <- bindCache(reactive({
      selection <- input$course_node
      req(selection$catalog_id %in% catalog$catalogs$catalog_id, selection$node_id)
      tryCatch(
        build_degree_popup_history(sections, students, edges, catalog, roadmaps, CEDAR_GEN_ED_COURSES, selection, shared),
        error = function(e) {
          showNotification(conditionMessage(e), type = "error", duration = NULL)
          list(state = "error", kind = selection$type, node_id = selection$node_id, note = conditionMessage(e))
        })
    }), input$course_node, cache = "session")

    output$course_history <- renderUI({
      current <- history()
      if (current$kind == "allowance") degree_allowance_history_ui(current, session$ns("course_history_table"))
      else degree_course_history_ui(current, session$ns("course_history_table"))
    })
    output$course_history_table <- reactable::renderReactable({
      current <- history()
      req(current$state == "ready")
      if (current$kind == "allowance") degree_allowance_table(current) else degree_history_table(current)
    })
  })
}

# Same readable table in Admin and the graph's rules dialog.
degree_plan_rules_table <- function(rows) {
  reactable::reactable(rows, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
    searchable = TRUE, defaultPageSize = 15L, showPageSizeOptions = TRUE, pageSizeOptions = c(15L, 30L, 100L),
    columns = list(kind = reactable::colDef(name = "Rule type", minWidth = 120),
      rule = reactable::colDef(name = "Readable rule", minWidth = 270),
      effect = reactable::colDef(name = "How the visualization uses it", minWidth = 240),
      source_url = reactable::colDef(name = "Source", width = 100,
        cell = function(value) if (nzchar(value)) tags$a("Catalog", href = value, target = "_blank", rel = "noopener noreferrer") else "CEDAR setting"),
      quote = reactable::colDef(name = "Catalog wording", minWidth = 230), node_ids = reactable::colDef(show = FALSE)))
}

degreePlanRulesUI <- function(id, catalog, roadmaps) {
  ns <- NS(id)
  if (!nrow(catalog$catalogs)) return(empty_state("No degree visualization prototypes are configured."))
  english <- roadmaps$starts[roadmaps$starts$track == "english", ]
  tagList(subtab_header("Visualization rules", "The readable rules behind Degree Explorer, generated from its saved course lists, choices and graph. Compare catalog requirements with their source; CEDAR planning preferences are labeled separately."),
    fluidRow(column(5, selectInput(ns("catalog"), "Program", degree_catalog_choices(catalog), width = "100%")),
      column(3, selectInput(ns("math"), "Math starting point", degree_math_start_choices(roadmaps, catalog$catalogs$catalog_id[1]), width = "100%")),
      column(4, selectInput(ns("english"), "English starting point", stats::setNames(english$start_id, english$label), width = "100%"))),
    uiOutput(ns("summary")), downloadButton(ns("download"), "Download readable rules"),
    reactable::reactableOutput(ns("table")))
}

degreePlanRulesServer <- function(id, catalog, roadmaps, shared = NULL) {
  if (!nrow(catalog$catalogs)) return(invisible(NULL))
  moduleServer(id, function(input, output, session) {
    observeEvent(input$catalog, updateSelectInput(session, "math",
      choices = degree_math_start_choices(roadmaps, input$catalog), selected = isolate(input$math)), ignoreInit = TRUE)
    rules <- reactive({
      req(input$catalog, input$math, input$english)
      build_degree_plan_rules(catalog, roadmaps,
        build_degree_roadmap_view(catalog, roadmaps, input$catalog, input$math, input$english, shared = shared))
    })
    output$summary <- renderUI({
      data <- rules()
      tagList(p(tags$strong(data$title), " · ", tags$a("Open program requirements", href = data$source_url, target = "_blank", rel = "noopener noreferrer")),
        p(class = "text-hint", data$scenario), p(class = "text-hint", data$note),
        p(class = "text-hint", "This explains the current prototype. It does not require per-rule approval. Recorded admission/GPA policies are shown, but student eligibility and degree completion are not evaluated."))
    })
    output$table <- reactable::renderReactable(degree_plan_rules_table(rules()$rows))
    output$download <- downloadHandler(filename = function() paste0(input$catalog, "-visualization-rules.csv"),
      content = function(file) utils::write.csv(rules()$rows, file, row.names = FALSE, na = ""))
  })
}

# ── Semester board ───────────────────────────────────────────────────────────

#' The semester board: course tiles in aligned rows, with the hover preview
#' skeleton and the JSON payload cedar-roadmap.js reads.
degree_semester_board <- function(view, id, select_id = paste0(id, "-select")) {
  legend <- c(green = "0 prerequisite courses", yellow = "1–2 prerequisite courses",
              red = "3+ prerequisite courses", unresolved = "Choice: prerequisites vary",
              conditional = "◇ Coursework / permission condition", suggested = "Suggested Gen Ed course")
  tile_fields <- c("node_id", "code", "kind", "condition_label", "option_count", "option_label",
                   "option_codes", "requirement_summary", "upstream_ids", "downstream_ids", "qualifying_ids")
  tagList(
    subtab_header(view$title, "A semester-by-semester picture · hover for prerequisites · click for enrollment history"),
    div(class = "scope-bar cedar-roadmap-summary", role = "status",
      tags$strong(view$math_note), tags$span(view$change_note),
      tags$span(class = "cedar-roadmap-prototype", "Planning prototype")),
    div(id = id, class = "cedar-roadmap", `data-roadmap` = "true",
      `data-select-input` = select_id,
      `data-catalog` = view$catalog$catalog_id,
      `data-math-start` = view$starts[["math"]], `data-english-start` = view$starts[["english"]],
      `data-start-season` = view$start_season,
      div(class = "cedar-roadmap-legend", lapply(names(legend), function(level)
        tags$span(class = paste("cedar-roadmap-key", paste0("cedar-roadmap-key--", level)), legend[[level]])),
        tags$span("Counts name courses in the chain; ◇ conditions are separate. ↔ = courses planned together.")),
      tags$p(class = "text-hint", paste("Hover or focus a course to preview its prerequisite chain and the",
        "courses that depend on it. Blue lines lead in; purple lines lead out. Click for first-day seats and",
        "enrollment history. Related courses line up across semesters.")),
      tags$p(class = "text-hint cedar-roadmap-timing", view$timing_note),
      tags$p(class = "text-hint cedar-roadmap-coverage", view$coverage_note),
      degree_hover_preview(id),
      div(class = "cedar-roadmap-scroll", tabindex = "0", role = "region",
        `aria-label` = "Semester roadmap; scroll horizontally to see later semesters",
        div(class = "cedar-roadmap-board",
          style = paste0("--roadmap-terms:", nrow(view$terms), ";--roadmap-rows:", view$n_rows),
          lapply(seq_len(nrow(view$terms)), function(i) degree_semester_column(view, view$terms[i, ])))),
      degree_json_script(view$links[c("from", "to", "timing")], "cedar-roadmap-links"),
      degree_json_script(view$nodes[tile_fields], "cedar-roadmap-node-data"),
      degree_json_script(view$allowances[c("node_id", "code", "kind", "detail")], "cedar-roadmap-allowance-data"),
      tags$script(HTML(sprintf("window.CedarRoadmap.initialize(document.getElementById(%s));",
                               jsonlite::toJSON(id, auto_unbox = TRUE))))),
    tags$p(class = "text-hint mt-2", view$workload_note),
    tags$p(class = "text-hint", view$program_codes_note),
    tags$p(class = "text-hint", view$note, " ",
      tags$a(href = view$catalog$source_url, target = "_blank", rel = "noopener noreferrer", "Degree catalog source"),
      " · saved ", view$catalog$catalog_year, " excerpt, retrieved ", view$catalog$retrieved_on, "."))
}

# JSON for the browser, with "<" escaped so a catalog quote cannot close the script.
degree_json_script <- function(data, class) {
  json <- jsonlite::toJSON(data, dataframe = "rows", auto_unbox = TRUE)
  tags$script(type = "application/json", class = class, HTML(gsub("<", "\\u003c", json, fixed = TRUE)))
}

degree_hover_preview <- function(id) {
  div(id = paste0(id, "-hover"), class = "cedar-roadmap-hover", role = "tooltip", hidden = TRUE,
    tags$strong(class = "cedar-roadmap-hover-title"),
    div(class = "cedar-roadmap-hover-upstream",
      tags$strong("Prerequisite / corequisite chain"), tags$p(class = "cedar-roadmap-hover-before")),
    tags$p(class = "cedar-roadmap-hover-conditions", hidden = TRUE),
    div(class = "cedar-roadmap-hover-downstream",
      tags$strong("Courses that depend on it"), tags$p(class = "cedar-roadmap-hover-after")),
    tags$p(class = "cedar-roadmap-hover-options", hidden = TRUE),
    tags$small("This selected route only. Click for enrollment history and catalog evidence."))
}

degree_semester_column <- function(view, term) {
  courses <- view$nodes[view$nodes$semester == term$semester, ]
  allowances <- view$allowances[view$allowances$semester == term$semester, ]
  tags$section(class = "cedar-roadmap-semester", `aria-label` = paste("Semester", term$semester),
    `data-planned-credits` = term$planned_credits,
    div(class = "cedar-roadmap-semester-header",
      tags$span(class = "cedar-roadmap-year", paste("Year", term$year, "·", tools::toTitleCase(term$season))),
      tags$strong(paste("Semester", term$semester)),
      tags$span(class = "cedar-roadmap-load", paste(term$planned_credits, "credits planned"))),
    div(class = "cedar-roadmap-courses",
      lapply(seq_len(nrow(allowances)), function(j) degree_allowance_tile(allowances[j, ])),
      lapply(seq_len(nrow(courses)), function(j) degree_course_tile(view, courses[j, ]))),
    if (term$footer_credits >= 1 && term$other_phase == "advanced") {
      div(class = "cedar-roadmap-flex", `data-allowance-phase` = term$other_phase,
        `data-credits` = term$footer_credits,
        tags$span(term$other_label), tags$strong(paste(term$footer_credits, "cr planned")))
    })
}

degree_course_tile <- function(view, course) {
  has_options <- course$option_count > 0L
  tags$button(type = "button",
    class = paste("cedar-roadmap-course", paste0("cedar-roadmap-course--", course$kind),
                  paste0("cedar-roadmap-course--", course$planning_level)),
    style = paste0("grid-row:", course$row),
    `data-node` = course$node_id, `data-card-type` = "course", `data-kind` = course$kind,
    `data-semester` = course$semester, `data-row` = course$row, `data-row-group` = course$row_group,
    `data-course-level` = course$course_level, `data-credits` = course$credits,
    `data-option-count` = course$option_count, `data-basis` = course$basis,
    `data-conditions` = course$n_conditions, `data-title` = paste(course$code, "·", course$title),
    `data-planning-level` = course$planning_level, `data-prerequisites` = course$n_prerequisites,
    `data-downstream` = course$n_downstream, `aria-pressed` = "false", `aria-haspopup` = "dialog",
    tags$span(class = "cedar-roadmap-course-code", if (has_options) course$option_label else course$code),
    if (nzchar(course$requirement_summary)) {
      tags$span(class = "cedar-roadmap-requirement-summary", course$requirement_summary)
    },
    if (has_options) degree_option_preview(view, course),
    tags$span(class = "cedar-roadmap-course-title", course$title),
    tags$span(class = "cedar-roadmap-category", course$kind_label, if (course$bundle) if (course$kind == "cohort") " · ↔ Together" else " · ↔ Paired"),
    if (nzchar(course$coverage_label)) tags$span(class = "cedar-roadmap-coverage-badge", course$coverage_label,
      title = course$coverage_detail),
    tags$span(class = "cedar-roadmap-prereq-count", course$prerequisite_label),
    if (nzchar(course$condition_label)) {
      tags$span(class = "cedar-roadmap-condition-badge", paste("◇", course$condition_label))
    },
    tags$span(class = "cedar-roadmap-chain-badge", course$chain_badge),
    tags$span(class = "cedar-roadmap-course-meta", paste(course$credits, if (has_options) "cr planned" else "cr"),
      if (course$moved) tags$span(class = "cedar-roadmap-moved", "Shifted")))
}

# Every alternative's codes, each kept whole, clamped to three lines by CSS.
degree_option_preview <- function(view, course) {
  alternatives <- view$option_groups[view$option_groups$node_id == course$node_id, ]
  tags$span(class = "cedar-roadmap-option-preview", title = course$option_codes,
    lapply(seq_len(nrow(alternatives)), function(k) {
      codes <- view$options$subject_course[view$options$node_id == course$node_id &
                                             view$options$option_id == alternatives$option_id[k]]
      tagList(lapply(seq_along(codes), function(j) tagList(
        tags$span(class = "cedar-roadmap-option-code", codes[j]),
        if (j < length(codes)) " + " else if (k < nrow(alternatives)) ", " else "")))
    }))
}

degree_allowance_tile <- function(allowance) {
  tags$button(type = "button", class = "cedar-roadmap-course cedar-roadmap-course--allowance",
    style = paste0("grid-row:", allowance$row),
    `data-node` = allowance$node_id, `data-card-type` = "allowance", `data-kind` = "allowance",
    `data-semester` = allowance$semester, `data-season` = allowance$season,
    `data-credits` = allowance$credits, `data-row` = allowance$row,
    `data-row-group` = paste0("allowance_", allowance$semester), `data-purpose` = allowance$purpose,
    `data-gen-ed-area` = allowance$area, `data-allowance-phase` = allowance$phase,
    `data-title` = paste(allowance$code, "·", allowance$credits, "credits"),
    `aria-pressed` = "false", `aria-haspopup` = "dialog",
    tags$span(class = "cedar-roadmap-course-code", allowance$code),
    tags$span(class = "cedar-roadmap-course-title", allowance$title),
    tags$span(class = "cedar-roadmap-category", if (allowance$purpose == "gen_ed") "Gen Ed area · confirm overlap" else "Flexible degree credit"),
    tags$span(class = "cedar-roadmap-chain-badge", paste("Browse", allowance$season_label, "courses")),
    tags$span(class = "cedar-roadmap-course-meta", paste(allowance$credits, "cr planned")))
}

# ── Tile popup ───────────────────────────────────────────────────────────────

#' The popup for one tile: catalog links, then offering history, then evidence
degree_tile_modal <- function(detail, history_id) {
  cedar_info_modal(detail$title,
    div(class = "cedar-roadmap-dialog", `data-dialog-node` = detail$node_id,
      div(class = "cedar-roadmap-detail-actions",
        tags$a(class = "cedar-roadmap-program-source", href = detail$program_url,
          target = "_blank", rel = "noopener noreferrer", "Degree requirements ↗"),
        tags$a(class = "cedar-roadmap-detail-course", href = detail$course_url,
          target = "_blank", rel = "noopener noreferrer", paste(detail$course_link_label, "↗")),
        if (!is.null(detail$coverage_url)) tags$a(href = detail$coverage_url,
          target = "_blank", rel = "noopener noreferrer", "Gen Ed requirements ↗")),
      if (nzchar(detail$summary)) tags$p(class = "text-hint cedar-roadmap-dialog-summary", detail$summary),
      uiOutput(history_id, class = "cedar-roadmap-history", `aria-live` = "polite"),
      if (detail$type == "course") degree_tile_evidence(detail)),
    size = "xl", scrollable = TRUE, close_label = "Back to roadmap")
}

degree_tile_evidence <- function(detail) {
  node <- detail$node
  div(class = "cedar-roadmap-detail",
    section_heading("Catalog requirements & course details"),
    div(class = "cedar-roadmap-evidence", `data-review` = node$evidence_review_status,
      tags$strong(class = "cedar-roadmap-evidence-basis", node$basis_explanation),
      tags$a(class = "cedar-roadmap-evidence-location", href = node$evidence_source_url,
        target = "_blank", rel = "noopener noreferrer", paste(node$evidence_section, "↗")),
      tags$q(class = "cedar-roadmap-evidence-quote", node$evidence_quote),
      tags$span(class = "cedar-roadmap-evidence-stamp", paste0(node$evidence_catalog_year, " · retrieved ",
        node$evidence_retrieved_on, " · ", node$evidence_review_status)),
      tags$span(class = "cedar-roadmap-evidence-note", node$evidence_note)),
    div(class = "cedar-roadmap-chain-detail", detail$chain_text),
    if (nrow(detail$conditions)) {
      div(class = "cedar-roadmap-condition-detail", lapply(seq_len(nrow(detail$conditions)), function(i) {
        condition <- detail$conditions[i, ]
        div(tags$strong(paste("◇", condition$label)),
          tags$a(href = condition$source_url, target = "_blank", rel = "noopener noreferrer",
            paste(condition$section, "↗")),
          tags$q(condition$quote))
      }))
    },
    if (nrow(detail$alternatives)) degree_tile_alternatives(detail),
    tags$p(class = "cedar-roadmap-detail-text", detail$detail_text))
}

# Every alternative in a choice set, lecture/lab components grouped under one option.
degree_tile_alternatives <- function(detail) {
  node <- detail$node
  description <- c(node$requirement_summary, node$detail)
  div(class = "cedar-roadmap-option-detail",
    section_heading(node$option_label, level = "h6"),
    tags$p(paste(description[nzchar(description)], collapse = ". ")),
    tags$ul(lapply(seq_len(nrow(detail$alternatives)), function(k) {
      alternative <- detail$alternatives[k, ]
      components <- detail$components[detail$components$option_id == alternative$option_id, ]
      tags$li(`data-option` = alternative$option_id,
        if (alternative$component_count > 1L) {
          tags$strong(paste0(alternative$option_code, " · ", alternative$credit_label, " credits together"))
        },
        lapply(seq_len(nrow(components)), function(j) {
          component <- components[j, ]
          div(tags$a(href = component$source_url, target = "_blank", rel = "noopener noreferrer",
              paste0(component$subject_course, " — ", component$course_title, " (", component$credit_label,
                     " credits · ", component$course_level, "-level) ↗")),
            if (nzchar(component$prerequisite_note)) {
              tags$p(paste("Course prerequisite:", component$prerequisite_note))
            })
        }))
    })))
}

#' Course history rendering only; all counts and summaries arrive from a feature.
degree_course_history_ui <- function(history, table_id) {
  div(`data-history-node` = history$node_id, `data-history-state` = history$state,
    section_heading("Offering history & first-day seats"),
    tags$p(class = "text-hint", history$note),
    if (history$state == "empty") {
      tags$p("No active offering history under this exact course code in this window. Renamed courses are not automatically combined.")
    },
    if (history$state == "ready") tagList(
      tags$p(class = "text-hint", paste("Seats offered → filled at first class day → fill %. Filter Course or",
        "Campus to compare the same offering over time. Season frequency counts source-covered terms only.")),
      reactable::reactableOutput(table_id),
      if (length(history$missing_courses)) {
        tags$p("No history for: ", paste(history$missing_courses, collapse = ", "), ". Components are checked separately.")
      },
      tags$p(class = "text-hint", paste("Near full = at least", scales::percent(CEDAR_NEAR_FULL_FILL),
        "filled at first day. Missing dates are unavailable; counts below 10 are suppressed. History does",
        "not guarantee future seats.")),
      info_panel("How first-day enrollment is measured",
        tags$p(paste("Source: scheduled seats from DESR and first-day enrollment reconstructed from class-list",
          "status dates against each section’s start date. This uses CEDAR’s shared first-day helper; it does",
          "not substitute census or ever-registered counts.")),
        tags$p(paste("Banner retains only the current status date. A student who added after day one and later",
          "dropped can be counted as present, so this is a reconstruction, not a frozen first-day roster.",
          "Scheduled capacity is the retained snapshot.")),
        tags$p(paste("Lecture/lab, teaching campuses, colleges and parts of term stay separate. Incomplete",
          "source matches, missing dates, cells below 10 and implausible fill above 125% are unscored. Not",
          "offered means source-covered absence; Source unavailable means the campus has no retained source term.")))))
}

degree_allowance_history_ui <- function(history, table_id) {
  div(`data-history-node` = history$node_id, `data-history-state` = history$state,
    `data-history-season` = history$season,
    section_heading(paste(tools::toTitleCase(history$season %||% ""), "course options")),
    tags$p(class = "text-hint", history$note),
    tags$p(class = "text-hint", history$credit_note),
    tags$p(class = "text-hint", paste("Historical examples, not major-specific recommendations or audited",
      "requirements. Check prerequisites and current Gen Ed approval.")),
    if (history$state %in% c("empty", "unavailable")) {
      tags$p("No matching-season options with usable course metadata were found. Open language/studio choices and separate lecture/lab pairings need individual catalog review.")
    },
    if (history$state == "ready") tagList(
      tags$p(class = "text-hint", paste("Latest matching-season offering per course/campus/college/session.",
        "Seats offered → filled at first class day → fill %. Filter Gen Ed area, Course or Campus.")),
      reactable::reactableOutput(table_id),
      tags$p(class = "text-hint", paste("First-day counts are reconstructed; missing dates remain unavailable",
        "and counts below 10 are suppressed. Near full means at least", scales::percent(CEDAR_NEAR_FULL_FILL),
        "filled. Historical offerings do not guarantee future seats.")),
      info_panel("How suggestions are chosen",
        tags$p(paste("An identified Gen Ed slot uses its annual catalog area list. Elective/minor slots use lower- and upper-level undergraduate offerings; Gen Ed approval is optional.",
          "Course-sized credit ranges and usable historical metadata are required. Courses already represented by entry routes, requirements and enumerated choice pools are excluded.",
          "No prerequisite-free status, student eligibility or unlisted language/studio approval is inferred.")),
        tags$p(paste("The history window ends at settled enrollment. Rows show the latest matching-season",
          "offering at each course/campus/college/session; frequent offerings sort first, followed by",
          "first-day enrollment. Season frequency counts source-covered terms, not missing terms.")),
        tags$p(paste("Scheduled seats come from DESR; first-day enrollment uses the shared class-list",
          "reconstruction. Missing matches and dates stay unknown. Banner retains only the current status",
          "date, so late additions later dropped may be counted at first day. Census counts are not substituted.")))))
}

# Seats, first-day enrollment and coverage, shared by both popup tables.
degree_seat_coldefs <- function() {
  list(
    capacity = cedar_count_coldef("Seats offered", minWidth = 85),
    first_day_enrl = cedar_count_coldef("Filled · first day", minWidth = 95),
    first_day_fill = cedar_percent_coldef("First-day fill", minWidth = 85),
    pressure_status = reactable::colDef(name = "Pressure / coverage", minWidth = 140,
      style = function(value) {
        if (value == "Near full") list(background = CEDAR_SURFACE_TINTS[["warning"]], fontWeight = "600") else list()
      }),
    season_frequency = reactable::colDef(name = "Season frequency", minWidth = 100))
}

#' Standard CEDAR table; counts stay numeric for sorting and formatting.
degree_history_table <- function(history) {
  reactable::reactable(history$table, theme = cedar_tbl_theme, striped = TRUE,
    highlight = TRUE, compact = TRUE, filterable = TRUE,
    defaultColDef = reactable::colDef(filterable = FALSE), defaultPageSize = 9,
    showPageSizeOptions = TRUE, pageSizeOptions = c(9, 18, 36),
    columns = c(list(
      term = reactable::colDef(name = "Term", minWidth = 95, cell = fmt_term),
      subject_course = reactable::colDef(name = "Course", minWidth = 100, filterable = TRUE),
      campus = reactable::colDef(name = "Campus", minWidth = 65, filterable = TRUE),
      college = reactable::colDef(name = "College", minWidth = 65),
      part_term = cedar_pot_coldef()), degree_seat_coldefs()))
}

degree_allowance_table <- function(history) {
  reactable::reactable(history$table, theme = cedar_tbl_theme, striped = TRUE,
    highlight = TRUE, compact = TRUE, filterable = TRUE,
    defaultColDef = reactable::colDef(filterable = FALSE), defaultPageSize = 12,
    showPageSizeOptions = TRUE, pageSizeOptions = c(12, 24, 48),
    columns = c(list(
      area_label = reactable::colDef(name = "Gen Ed area", minWidth = 125, filterable = TRUE),
      course_level = reactable::colDef(name = "Level", minWidth = 70, filterable = TRUE),
      subject_course = reactable::colDef(name = "Course", minWidth = 100, filterable = TRUE),
      course_title = reactable::colDef(name = "Title", minWidth = 190, filterable = TRUE),
      credits_min = reactable::colDef(show = FALSE), credits_max = reactable::colDef(show = FALSE),
      credit_label = reactable::colDef(name = "Credits", minWidth = 60),
      credit_fit = reactable::colDef(name = "Credit fit", minWidth = 125, filterable = TRUE),
      campus = reactable::colDef(name = "Campus", minWidth = 65, filterable = TRUE),
      college = reactable::colDef(name = "College", minWidth = 65),
      part_term = cedar_pot_coldef(),
      term = reactable::colDef(name = "Last offered", minWidth = 95, cell = fmt_term)),
      degree_seat_coldefs()))
}
