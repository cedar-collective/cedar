# Admin > Data & Usage > Catalog Review. Sources and decisions remain files.

catalogReviewUI <- function(id, catalog, roadmaps) {
  ns <- NS(id)
  navset_tab(id = ns("mode"), selected = "rules",
    nav_panel("Visualization rules", value = "rules", degreePlanRulesUI(ns("rules"), catalog, roadmaps)),
    nav_panel("Draft interpretations", value = "program", catalogNormalizationUI(ns("normalization"))),
    nav_panel("Extraction diagnostics", value = "diagnostics", catalogExtractionDiagnosticsUI(id)))
}

catalogExtractionDiagnosticsUI <- function(id) {
  ns <- NS(id)
  div(
    subtab_header("Parser diagnostics",
      "These flags describe limitations of the older catalog parser. They do not describe the rules driving Degree Explorer and are not a checklist for approving the visualization."),
    div(class = "alert alert-info", "For the readable rules actually used by the chart, open Visualization rules. This diagnostic scan includes linked course records and additional alternatives beyond the selected prototype."),
    fluidRow(
      column(10, selectInput(ns("scan"), "Catalog scan", choices = character(), width = "100%")),
      column(2, filter_actions(actionButton(ns("refresh"), "Refresh scans", icon = icon("rotate"))))
    ),
    uiOutput(ns("status")),
    fluidRow(
      column(6, selectizeInput(ns("program"), "Degree and its referenced courses", choices = c("All degrees and courses" = ""), width = "100%")),
      column(3, selectInput(ns("kind"), "Record type", choices = c("All types" = "", "Degree", "Concentration", "Course"), width = "100%")),
      column(3, selectInput(ns("phase"), "Requirement type", choices = c("All types" = "", "Admission", "Degree", "Prerequisite", "Corequisite", "Unclassified", "Source"), width = "100%"))
    ),
    p(class = "text-hint", "A degree filter includes its concentrations and courses reachable through catalog links. A link alone does not mean a course is required. Inspect opens the saved evidence; the catalog link opens the currently published page."),
    filter_actions(downloadButton(ns("download"), "Download filtered review queue")),
    navset_tab(
      nav_panel("Requirements to interpret",
        subtab_header("Requirements to interpret", "These flags identify rules the extractor cannot yet fully represent, not necessarily catalog errors. Supported lists, grades and status milestones are retained without separate interpretation flags; all sections still await validation."),
        reactable::reactableOutput(ns("interpretation"))),
      nav_panel("Milestones",
        subtab_header("Status milestones", "Each row cites a use of a shared class-standing or program-admission milestone. The enclosing rule preserves alternatives such as Junior or Senior. These statuses do not award credits, assign a semester or establish a student's eligibility."),
        reactable::reactableOutput(ns("milestones"))),
      nav_panel("Source checks",
        subtab_header("Source checks", "Catalog inclusion flags, missing requirement sections and uncertain credentials need source verification before interpretation."),
        reactable::reactableOutput(ns("source"))),
      nav_panel("All requirement sections",
        subtab_header("All requirement sections", "Parsed course lists also remain unreviewed. Inspect a complete section to compare its source language with the draft structure."),
        reactable::reactableOutput(ns("sections"))),
      nav_panel("Program coverage",
        subtab_header("Program coverage", "Degree-level coverage and narrative counts, following the degree filter. Other filters apply to the review tables. Counts here exclude concentrations and course records, which have their own review items."),
        reactable::reactableOutput(ns("coverage")))
    )
  )
}

# Render only text and a small tag vocabulary. No catalog attributes, scripts,
# active embeds or event handlers ever reach the browser; list nesting survives.
catalog_review_source_view <- function(value) {
  if (!is.character(value) || length(value) != 1L) {
    return(tags$pre(as.character(jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA))))
  }
  document <- catalog_html_document(value)
  root <- xml2::xml_find_first(document, "//div[@id='cedar-source']")
  allowed <- c("div", "p", "ul", "ol", "li", "span", "strong", "em", "b", "i", "br", "table", "thead", "tbody", "tr", "th", "td", "code", "pre")
  render <- function(node) {
    if (xml2::xml_type(node) == "text") return(xml2::xml_text(node))
    name <- xml2::xml_name(node)
    if (name %in% c("script", "style")) return(NULL)
    if (!name %in% allowed) name <- "span"
    htmltools::tag(name, lapply(xml2::xml_contents(node), render))
  }
  div(class = "cedar-body", lapply(xml2::xml_contents(root), render))
}

catalog_review_table <- function(items, ns, reason_name = "Why review") {
  if (!nrow(items)) return(reactable::reactable(data.frame(Message = "No items match these filters."),
    pagination = FALSE, theme = cedar_tbl_theme))
  reactable::reactable(items[, c("title", "kind", "section", "phase", "reason", "excerpt", "item_id")],
    theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE, compact = TRUE,
    searchable = TRUE, defaultPageSize = 10L, showPageSizeOptions = TRUE,
    pageSizeOptions = c(10L, 25L, 50L),
    onClick = htmlwidgets::JS(paste0("function(rowInfo, column) { if (column.id === 'item_id') { Shiny.setInputValue(",
      jsonlite::toJSON(ns("inspect"), auto_unbox = TRUE), ", rowInfo.values.item_id, {priority: 'event'}); } }")),
    columns = list(title = reactable::colDef(name = "Program / course", minWidth = 210),
      kind = reactable::colDef(name = "Type", width = 115),
      section = reactable::colDef(name = "Catalog section", minWidth = 150),
      phase = reactable::colDef(name = "Requirement type", width = 125),
      reason = reactable::colDef(name = reason_name, minWidth = 160),
      excerpt = reactable::colDef(name = "Language / source concern", minWidth = 260,
        cell = htmlwidgets::JS("function(cellInfo) { var text = cellInfo.value; return text.length > 170 ? text.slice(0, 170) + '…' : text; }")),
      item_id = reactable::colDef(name = "Evidence", width = 95, sortable = FALSE, searchable = FALSE,
        html = TRUE, cell = htmlwidgets::JS("function() { return '<button type=\"button\" class=\"btn btn-sm btn-outline-secondary\">Inspect</button>'; }"))))
}

catalog_review_modal <- function(detail) {
  item <- detail$item
  cedar_info_modal(item$title,
    div(class = "alert alert-info", tags$strong(item$reason), p(item$next_step),
      "This extraction is unreviewed. Reviewing this page does not change a degree plan."),
    if (item$category != "Section") dashboard_subsection("Flagged language or source concern",
      "The selected queue item and its location in the captured record.", tags$blockquote(item$excerpt)),
    dashboard_subsection("Captured catalog section", paste(detail$catalog_title, "·", item$section),
      catalog_review_source_view(detail$source)),
    if (nzchar(item$milestone_id)) p("Shared milestone: ", tags$code(item$milestone_id)),
    if (length(detail$admission_evidence)) tagList(lapply(detail$admission_evidence, function(evidence)
      dashboard_subsection("Linked program admission policy", "Captured policy context; admission status is a separate requirement.",
        p(tags$a("Open program requirements", href = evidence$catalog_url, target = "_blank", rel = "noopener noreferrer")),
        catalog_review_source_view(evidence$value),
        p("Source field: ", tags$code(evidence$pointer), " · SHA-256: ", tags$code(evidence$sha256))))),
    if (isTRUE(detail$admission_policy_missing)) p(class = "text-hint",
      "No admission policy section was supplied in this captured program. Admission is still required."),
    if (nzchar(detail$tree)) tags$details(tags$summary("Draft structure — not validated"), tags$pre(detail$tree)),
    dashboard_subsection("Source evidence", paste("Captured", detail$captured_at),
      p(tags$a("Open catalog page", href = detail$catalog_url, target = "_blank", rel = "noopener noreferrer"),
        " · ", tags$a("Public source record", href = item$source_url, target = "_blank", rel = "noopener noreferrer")),
      tags$dl(tags$dt("Field in saved record"), tags$dd(tags$code(item$source_pointer)),
        if (nzchar(item$node_id)) tagList(tags$dt("Node in draft structure"), tags$dd(tags$code(item$node_id))),
        tags$dt("Source SHA-256"), tags$dd(tags$code(item$source_sha256)))), size = "l", scrollable = TRUE)
}

catalogReviewServer <- function(id, root, active, catalog, roadmaps,
    review_root = file.path(dirname(dirname(root)), "catalog-normalizations", basename(root)), shared = NULL) {
  moduleServer(id, function(input, output, session) {
    overall_active <- active
    degreePlanRulesServer("rules", catalog, roadmaps, shared)
    catalogNormalizationServer("normalization", root = review_root, capture_root = root,
      active = reactive(isTRUE(overall_active()) && identical(input$mode, "program")))
    active <- reactive(isTRUE(overall_active()) && identical(input$mode, "diagnostics"))
    scans <- reactiveVal(NULL)
    payload <- reactiveVal(NULL)
    failure <- reactiveVal(NULL)
    refresh_revision <- reactiveVal(0L)
    refresh_seen <- NULL
    report_error <- function(e) {
      payload(NULL)
      failure(conditionMessage(e))
      showNotification(conditionMessage(e), type = "error", duration = NULL)
    }
    observeEvent(list(active(), input$refresh), {
      req(isTRUE(active()))
      # Returning to the tab keeps its loaded snapshot, filters and table state.
      if (!is.null(scans()) && identical(input$refresh, refresh_seen)) return()
      tryCatch({
        index <- list_catalog_review_scans(root)
        scans(index); failure(NULL); payload(NULL)
        refresh_seen <<- input$refresh
        selected <- if (length(input$scan) == 1L && input$scan %in% index$scan_id) input$scan else if (nrow(index)) index$scan_id[1] else character()
        updateSelectInput(session, "scan", choices = stats::setNames(index$scan_id, index$label), selected = selected)
        refresh_revision(refresh_revision() + 1L)
      }, error = report_error)
    }, ignoreNULL = FALSE)
    prepared <- bindCache(reactive({
      load_catalog_review(root, input$scan)
    }), {
      refresh_revision()
      req(input$scan, scans(), input$scan %in% scans()$scan_id)
      catalog_review_cache_key(root, input$scan)
    }, cache = "app")
    observeEvent(list(input$scan, refresh_revision()), {
      req(isTRUE(active()), input$scan, scans(), input$scan %in% scans()$scan_id)
      tryCatch({
        data <- prepared()
        payload(data); failure(NULL)
        selected <- if (length(input$program) == 1L && input$program %in% data$programs) input$program else ""
        updateSelectizeInput(session, "program", choices = c(list("All degrees and courses" = ""), as.list(data$programs)), selected = selected)
      }, error = report_error)
    }, ignoreNULL = FALSE)
    output$status <- renderUI({
      if (!is.null(failure())) return(div(class = "alert alert-danger", tags$strong("Catalog review unavailable. "), failure()))
      if (is.null(scans())) return(p(class = "text-hint", "Open this tab to load local catalog scans."))
      if (!nrow(scans())) return(div(class = "alert alert-info", tags$strong("No catalog scans are available. "),
        "Run scripts/scan-degree-catalog.R and keep the full archive under data/catalog-scans/<institution>/. Refresh scans when it is ready."))
      if (is.null(payload())) return(p(class = "text-hint", "Verifying the saved catalog evidence…"))
      data <- payload(); n <- data$meta$counts
      div(class = "alert alert-info", tags$strong("All extracted requirements are unreviewed. "),
        sprintf("%s degrees · %s concentrations · %s linked course records. %s narrative items and %s source checks are flagged across the full scan. ",
          n$degrees, n$specializations, n$course_requests, n$review_items, data$source_check_count),
        if (isTRUE(data$milestone_support)) sprintf("%s shared status milestones are recognized. ", n$milestones),
        "The flagged queue is a starting point; parsed sections also need validation. Decisions belong in reviewed, versioned requirement files.",
        p(class = "mb-0", paste("Capture started:", data$manifest$started_at,
          "· Extractor:", data$meta$extractor_version,
          "· Analysis and capture-manifest hashes verified. Original source bytes are verified on Inspect. Opening this page does not scan the website.")))
    })
    views <- reactive({
      req(payload())
      filter_catalog_review(payload(), input$program %||% "", input$kind %||% "", input$phase %||% "")
    })
    output$interpretation <- reactable::renderReactable(catalog_review_table(views()$interpretation, session$ns))
    output$milestones <- reactable::renderReactable({
      req(payload())
      if (!payload()$milestone_support) return(reactable::reactable(
        data.frame(Message = "This analysis predates status milestones. Re-analyze its frozen capture into a new directory to extract them."),
        pagination = FALSE, theme = cedar_tbl_theme))
      catalog_review_table(views()$milestones, session$ns, reason_name = "Milestone type")
    })
    output$source <- reactable::renderReactable(catalog_review_table(views()$source, session$ns))
    output$sections <- reactable::renderReactable(catalog_review_table(views()$sections, session$ns))
    output$coverage <- reactable::renderReactable({
      data <- views()$coverage
      reactable::reactable(data[, c("title", "degree_type", "sections", "degree_sections", "review_items")],
        theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, searchable = TRUE, defaultPageSize = 15L,
        columns = list(title = reactable::colDef(name = "Program"), degree_type = reactable::colDef(name = "Credential"),
          sections = reactable::colDef(name = "Requirement sections"), degree_sections = reactable::colDef(name = "Degree sections"),
          review_items = reactable::colDef(name = "Degree-level narrative flags")))
    })
    observeEvent(input$inspect, {
      req(payload())
      tryCatch(showModal(catalog_review_modal(catalog_review_detail(payload(), input$inspect))), error = report_error)
    })
    output$download <- downloadHandler(filename = function() "catalog-review.csv",
      content = function(file) utils::write.csv(views()$items, file, row.names = FALSE, na = ""))
  })
}
