# Admin program review: versioned drafts and attributed whole-unit sign-off.

catalogNormalizationUI <- function(id) {
  ns <- NS(id)
  tagList(
    subtab_header("Program review", "Compare the versioned interpretation with the captured catalog. Review exceptions, then sign off the complete program once. Linked course prerequisites are separate review units."),
    fluidRow(column(10, selectInput(ns("program"), "Program and catalog edition", choices = character(), width = "100%")),
      column(2, filter_actions(actionButton(ns("refresh"), "Refresh reviews", icon = icon("rotate"))))),
    uiOutput(ns("status")),
    fluidRow(column(6, selectInput(ns("unit"), "Requirements to review", choices = character(), width = "100%")),
      column(6, selectInput(ns("proposal"), "Interpretation version", choices = character(), width = "100%"))),
    # File exchange is deferred while the maintainer creates drafts in Git.
    # Restore these controls and the import observer together for shared use.
    # tags$details(tags$summary("Exchange files with AI"),
    #   downloadButton(ns("packet"), "Download interpretation packet"),
    #   fileInput(ns("response"), "AI response (JSON)", accept = ".json"),
    #   textInput(ns("model"), "AI model or tool used"),
    #   actionButton(ns("import"), "Validate and import proposal")),
    fluidRow(column(4, textInput(ns("reviewer"), "Your name for the review record", width = "100%")),
      column(8, textAreaInput(ns("note"), "Review note", rows = 2, placeholder = "Explain corrections or what needs clarification.", width = "100%"))),
    uiOutput(ns("review_status")),
    uiOutput(ns("sign_off")),
    tags$details(open = TRUE, tags$summary("Cases needing attention"), reactable::reactableOutput(ns("issues"))),
    fluidRow(
      column(6, dashboard_subsection("Catalog evidence", "Every passage is accounted for automatically. Inspect any passage or open its complete section to check the interpretation.",
        selectInput(ns("block"), "Source passage", choices = character(), width = "100%"),
        uiOutput(ns("evidence")),
        filter_actions(actionButton(ns("question_source"), "Flag passage"), actionButton(ns("clear_source"), "Resolve passage flag")))),
      column(6, dashboard_subsection("Proposed requirements", "Select a rule to compare its meaning with the quoted catalog. Routine rules are covered by the program sign-off.",
        reactable::reactableOutput(ns("rules")), uiOutput(ns("selected_rule")),
        filter_actions(actionButton(ns("edit"), "Edit rule"), actionButton(ns("question_rule"), "Flag rule"),
          actionButton(ns("clear_rule"), "Resolve rule flag"))))),
    tags$details(tags$summary("Edit complete proposal"),
      p("Use this editor to add missing rules, change coverage classifications, or resolve questions. Saving an edit resets approvals; earlier revisions and the original AI response are retained."),
      actionButton(ns("edit_proposal"), "Open complete proposal editor"),
      downloadButton(ns("draft"), "Download current draft")),
    uiOutput(ns("export_control")))
}

catalog_normalization_evidence_view <- function(program, unit, state, block_id, context) {
  block <- unit$request$source_blocks[[match(block_id, catalog_normalization_ids(unit$request$source_blocks))]]
  document <- unit$request$documents[[match(block$entity_id, catalog_normalization_ids(unit$request$documents))]]
  section <- Filter(function(x) x$source_pointer == block$source_pointer, document$sections)
  tagList(p(tags$strong(block$title), " · ", block$section),
    tags$blockquote(class = "cedar-review-source", block$text),
    if (!is.null(state)) {
      coverage <- state$proposal$coverage[[match(block_id, catalog_normalization_ids(state$proposal$coverage, "block_id"))]]
      tagList(p(tags$strong("AI treatment: "), coverage$disposition, " · ", coverage$explanation),
        if (!is.null(state$notes[[paste0("blocks:", block_id)]])) p("Review note: ", state$notes[[paste0("blocks:", block_id)]]),
        lapply(Filter(function(x) x$block_id == block_id, state$proposal$questions), function(x) p(class = "text-warning", x$question)))
    },
    p(tags$a("Open catalog page", href = document$catalog_url, target = "_blank", rel = "noopener noreferrer"),
      " · ", tags$a("Public source record", href = block$source_url, target = "_blank", rel = "noopener noreferrer")),
    if (length(section)) tags$details(tags$summary("Complete enclosing catalog section"), catalog_review_source_view(section[[1]]$html)),
    if (length(context)) tags$details(tags$summary("Linked program admission policies (captured context)"),
      lapply(context, function(x) tagList(p(tags$strong(x$title), " · ", x$section), catalog_review_source_view(x$value),
        p(tags$code(x$source_pointer), " · ", tags$code(x$source_sha256))))),
    tags$details(tags$summary("Source locator and fingerprint"), p(tags$code(block$source_pointer)),
      p(tags$code(block$dom_path)), p(tags$code(block$source_sha256))))
}

catalog_normalization_edit_modal <- function(ns, node, request) {
  schema <- request$response_schema$properties$nodes$items$properties
  options <- function(name) unlist(schema[[name]]$enum)
  registry <- request$reference_registry
  choices <- stats::setNames(catalog_normalization_ids(registry), vapply(registry, function(x) paste(x$code, x$title), character(1)))
  cedar_info_modal("Edit requirement", p("Saving changes resets approvals. Source citations stay attached; use the complete proposal editor to change citations, add rules, or resolve source questions."),
    textInput(ns("edit_label"), "Readable requirement", node$label),
    fluidRow(column(6, selectInput(ns("edit_kind"), "Requirement kind", options("kind"), selected = node$kind)),
      column(6, selectInput(ns("edit_phase"), "Applies to", options("phase"), selected = node$phase))),
    textInput(ns("edit_parent"), "Parent group ID (blank for a top-level rule)", node$parent_id),
    fluidRow(column(4, textInput(ns("edit_minimum"), "Minimum (blank if unused)", if (is.null(node$minimum)) "" else node$minimum)),
      column(4, textInput(ns("edit_maximum"), "Maximum (blank if unused)", if (is.null(node$maximum)) "" else node$maximum)),
      column(4, selectInput(ns("edit_unit"), "Measure", options("unit"), selected = node$unit))),
    fluidRow(column(6, selectInput(ns("edit_comparison"), "Comparison", options("comparison"), selected = node$comparison)),
      column(6, textInput(ns("edit_grade"), "Minimum grade (blank if unused)", node$minimum_grade))),
    textAreaInput(ns("edit_value"), "Qualification, standing, GPA scope, permission or restriction", node$value, rows = 3),
    selectizeInput(ns("edit_courses"), "Explicit course references", choices[startsWith(choices, "courses:")], selected = unlist(node$course_refs), multiple = TRUE),
    selectInput(ns("edit_program"), "Admission program", c("None" = "", choices[startsWith(choices, "programs:")]), selected = node$program_ref),
    selectInput(ns("edit_timing"), "Timing", options("timing"), selected = node$timing),
    footer = tagList(modalButton("Cancel"), actionButton(ns("save_edit"), "Save edited requirement")), size = "l", scrollable = TRUE)
}

catalogNormalizationServer <- function(id, root, capture_root, active,
    draft_dir = file.path(cedar_institution_dir(), "catalog_interpretations")) {
  moduleServer(id, function(input, output, session) {
    index <- reactiveVal(NULL); program <- reactiveVal(NULL); unit <- reactiveVal(NULL)
    imported <- reactiveVal(NULL); state <- reactiveVal(NULL); error <- reactiveVal(NULL)
    selected <- reactiveVal(NULL); editing <- reactiveVal(NULL)
    notification <- NULL
    clear_error <- function() {
      error(NULL)
      if (!is.null(notification)) removeNotification(notification)
      notification <<- NULL
    }
    report_error <- function(e) {
      error(conditionMessage(e))
      if (!is.null(notification)) removeNotification(notification)
      notification <<- showNotification(conditionMessage(e), type = "error", duration = NULL)
    }
    refresh_proposals <- function(select = NULL) {
      proposals <- list_catalog_normalization_proposals(root, unit())
      choices <- stats::setNames(vapply(proposals, function(x) x$key, character(1)),
        vapply(proposals, function(x) paste(x$model, x$imported_at, substr(x$key, 1L, 8L), sep = " · "), character(1)))
      updateSelectInput(session, "proposal", choices = choices, selected = if (length(select) == 1L && select %in% choices) select else if (length(choices)) choices[1] else character())
    }
    observeEvent(list(active(), input$refresh), {
      req(isTRUE(active()))
      tryCatch({
        stage_catalog_normalization_drafts(root, draft_dir, capture_root)
        rows <- list_catalog_normalization_programs(root); index(rows); clear_error()
        updateSelectInput(session, "program", choices = stats::setNames(rows$key, rows$label),
          selected = if (length(input$program) == 1L && input$program %in% rows$key) input$program else if (nrow(rows)) rows$key[1] else character())
        if (!is.null(unit())) refresh_proposals(input$proposal)
      }, error = report_error)
    }, ignoreNULL = FALSE)
    observeEvent(input$program, {
      req(input$program)
      tryCatch({
        data <- load_catalog_normalization_program(root, input$program)
        program(data); unit(NULL); imported(NULL); state(NULL); clear_error()
        choices <- stats::setNames(vapply(data$packet$units, function(x) x$key, character(1)), vapply(data$packet$units, function(x) x$title, character(1)))
        updateSelectInput(session, "unit", choices = choices, selected = choices[1])
      }, error = report_error)
    })
    observeEvent(input$unit, {
      req(program(), input$unit)
      tryCatch({
        data <- catalog_normalization_unit(program(), input$unit)
        verify_catalog_normalization_sources(program(), data, capture_root)
        unit(data); imported(NULL); state(NULL); selected(NULL); clear_error()
        blocks <- data$request$source_blocks
        choices <- stats::setNames(catalog_normalization_ids(blocks), vapply(seq_along(blocks), function(i)
          paste(i, blocks[[i]]$title, blocks[[i]]$section, substr(blocks[[i]]$text, 1L, 75L), sep = " · "), character(1)))
        updateSelectInput(session, "block", choices = choices, selected = choices[1]); refresh_proposals()
      }, error = report_error)
    })
    observeEvent(list(input$proposal, input$refresh), {
      req(unit(), input$proposal)
      req(input$proposal %in% vapply(list_catalog_normalization_proposals(root, unit()), function(x) x$key, character(1)))
      tryCatch({
        data <- load_catalog_normalization_proposal(root, unit(), input$proposal)
        imported(data); state(read_catalog_normalization_review(root, unit(), data)); clear_error()
      }, error = report_error)
    })
    # Deferred with the exchange controls above; backend/CLI validation remains.
    # observeEvent(input$import, {
    #   req(unit(), input$response)
    #   tryCatch({
    #     key <- import_catalog_normalization(root, unit(), input$response$datapath, input$model)
    #     refresh_proposals(key); clear_error()
    #   }, error = report_error)
    # })
    save <- function(next_state) {
      verify_catalog_normalization_sources(program(), unit(), capture_root)
      updated <- save_catalog_normalization_review(root, unit(), imported(), next_state, input$reviewer, state()$head)
      state(updated); clear_error()
    }
    decision <- function(type, id, value) {
      req(state(), id)
      tryCatch(save(catalog_normalization_decision(state(), type, id, value, input$note)), error = report_error)
    }
    observeEvent(input$approve_unit, {
      req(state()); tryCatch(save(approve_catalog_normalization(state())), error = report_error)
    })
    observeEvent(input$question_rule, decision("nodes", selected(), "needs_clarification"))
    observeEvent(input$question_source, decision("blocks", input$block, "needs_clarification"))
    observeEvent(input$clear_rule, {
      req(state(), selected()); tryCatch(save(clear_catalog_normalization_flag(state(), "nodes", selected(), input$note)), error = report_error)
    })
    observeEvent(input$clear_source, {
      req(state(), input$block); tryCatch(save(clear_catalog_normalization_flag(state(), "blocks", input$block, input$note)), error = report_error)
    })
    observeEvent(input$issue, {
      req(state()); issue <- catalog_normalization_issues(state())[input$issue, , drop = FALSE]
      req(nrow(issue) == 1L)
      if (issue$type == "nodes") {
        selected(issue$id)
        node <- state()$proposal$nodes[[match(issue$id, catalog_normalization_ids(state()$proposal$nodes))]]
        updateSelectInput(session, "block", selected = node$citations[[1]]$block_id)
      } else updateSelectInput(session, "block", selected = issue$id)
    })
    observeEvent(input$rule, {
      req(state()); selected(input$rule)
      node <- state()$proposal$nodes[[match(input$rule, catalog_normalization_ids(state()$proposal$nodes))]]
      updateSelectInput(session, "block", selected = node$citations[[1]]$block_id)
    })
    output$status <- renderUI({
      if (!is.null(error())) return(div(class = "alert alert-danger", error()))
      if (is.null(index()) || !nrow(index())) return(div(class = "alert alert-info", "No program review packets are available. Prepare them with scripts/normalize-degree-catalog.R. Catalog extraction diagnostics remain available in the other tab."))
      req(program(), unit())
      p(class = "text-hint", paste(program()$packet$catalog_title, "·", length(program()$packet$units) - 1L,
        "linked course review units. Captured source bytes are checked when opening requirements or a passage. No proposal changes a semester plan or projection."))
    })
    output$review_status <- renderUI({
      if (is.null(state())) return(p(class = "text-hint", "An interpretation has not been drafted for this unit yet. The captured source is available below; no review is implied."))
      data <- state()
      div(class = if (catalog_normalization_approved(data)) "alert alert-success" else "alert alert-info",
        sprintf("%s rules · %s source passages accounted for · %s review cases · review revision %s.",
          length(data$nodes), length(data$blocks), nrow(catalog_normalization_issues(data)), data$revision),
        if (catalog_normalization_approved(data)) " Complete unit signed off." else " Draft — awaiting whole-unit sign-off.",
        " Reviewer names are entered by the reviewer; they are not verified account identities.")
    })
    output$sign_off <- renderUI({
      req(state())
      if (catalog_normalization_approved(state())) return(NULL)
      if (nrow(catalog_normalization_issues(state()))) return(p(class = "text-hint", "Resolve the cases below before signing off. Routine rules do not need individual approval."))
      tagList(p("After comparing this complete unit with the catalog, approve it once. This includes the treatment of informational passages."),
        actionButton(session$ns("approve_unit"), "Approve complete unit", class = "btn-primary"))
    })
    output$issues <- reactable::renderReactable({
      req(state())
      rows <- catalog_normalization_issues(state())
      if (!nrow(rows)) return(reactable::reactable(data.frame(Status = "No open cases. Compare the complete interpretation before signing off."), pagination = FALSE, theme = cedar_tbl_theme))
      reactable::reactable(rows, theme = cedar_tbl_theme, compact = TRUE, highlight = TRUE, defaultPageSize = 5L,
        onClick = htmlwidgets::JS(paste0("function(row) { Shiny.setInputValue(", jsonlite::toJSON(session$ns("issue"), auto_unbox = TRUE), ", row.index + 1, {priority:'event'}); }")),
        columns = list(type = reactable::colDef(show = FALSE), id = reactable::colDef(show = FALSE),
          label = reactable::colDef(name = "Case"), reason = reactable::colDef(name = "What to check")))
    })
    output$evidence <- renderUI({
      req(program(), unit(), input$block)
      req(input$block %in% catalog_normalization_ids(unit()$request$source_blocks))
      tryCatch({ verify_catalog_normalization_sources(program(), unit(), capture_root)
        catalog_normalization_evidence_view(program(), unit(), state(), input$block,
          catalog_normalization_context_sources(program(), unit(), capture_root))
      }, error = function(e) { report_error(e); div(class = "alert alert-danger", conditionMessage(e)) })
    })
    output$rules <- reactable::renderReactable({
      req(unit())
      if (is.null(state())) return(reactable::reactable(data.frame(Message = "No interpretation drafted for this unit."), pagination = FALSE, theme = cedar_tbl_theme))
      rows <- catalog_normalization_rule_rows(state(), unit()$request)
      preview <- htmlwidgets::JS("function(cell) { var text = cell.value; return text.length > 160 ? text.slice(0, 160) + '…' : text; }")
      reactable::reactable(rows, theme = cedar_tbl_theme, compact = TRUE, highlight = TRUE, searchable = TRUE, defaultPageSize = 8L,
        onClick = htmlwidgets::JS(paste0("function(row) { Shiny.setInputValue(", jsonlite::toJSON(session$ns("rule"), auto_unbox = TRUE), ", row.values.id, {priority:'event'}); }")),
        columns = list(id = reactable::colDef(show = FALSE), requirement = reactable::colDef(name = "Requirement", minWidth = 170, cell = preview),
          meaning = reactable::colDef(name = "Structured meaning", minWidth = 190, cell = preview), status = reactable::colDef(name = "Review", minWidth = 95)))
    })
    output$selected_rule <- renderUI({
      req(state(), selected())
      node <- state()$proposal$nodes[[match(selected(), catalog_normalization_ids(state()$proposal$nodes))]]
      tagList(p(tags$strong(node$label)), p(catalog_normalization_node_summary(node, unit()$request$reference_registry)),
        lapply(node$citations, function(x) tags$blockquote(class = "cedar-review-source", x$quote)),
        p("Rule ID: ", tags$code(node$id), " · ", state()$nodes[[node$id]]),
        if (!is.null(state()$notes[[paste0("nodes:", node$id)]])) p("Review note: ", state()$notes[[paste0("nodes:", node$id)]]))
    })
    observeEvent(input$edit, {
      req(state(), selected()); editing(selected())
      node <- state()$proposal$nodes[[match(selected(), catalog_normalization_ids(state()$proposal$nodes))]]
      showModal(catalog_normalization_edit_modal(session$ns, node, unit()$request))
    })
    observeEvent(input$save_edit, {
      req(state(), editing())
      tryCatch({
        number <- function(x) { if (!nzchar(trimws(x))) NULL else { value <- suppressWarnings(as.numeric(x)); if (!is.finite(value)) stop("Enter a number or leave the bound blank"); value } }
        fields <- list(label = input$edit_label, parent_id = input$edit_parent, kind = input$edit_kind, phase = input$edit_phase,
          minimum = number(input$edit_minimum), maximum = number(input$edit_maximum), unit = input$edit_unit,
          comparison = input$edit_comparison, value = input$edit_value, minimum_grade = input$edit_grade,
          course_refs = as.list(input$edit_courses), program_ref = input$edit_program, timing = input$edit_timing)
        save(edit_catalog_normalization_node(state(), editing(), fields, unit()$request)); removeModal()
      }, error = report_error)
    })
    observeEvent(input$edit_proposal, {
      req(state()); showModal(cedar_info_modal("Edit complete proposal",
        p("Keep source IDs and exact quotations. Missing coverage, invalid references and broken group logic are rejected. Saving resets approvals."),
        textAreaInput(session$ns("proposal_json"), "Normalized requirements, coverage and questions (JSON)", rawToChar(source_json_bytes(state()$proposal)), rows = 20, width = "100%"),
        footer = tagList(modalButton("Cancel"), actionButton(session$ns("save_proposal"), "Validate and save edit")), size = "l", scrollable = TRUE))
    })
    observeEvent(input$save_proposal, {
      req(state()); tryCatch({
        proposal <- jsonlite::fromJSON(input$proposal_json, simplifyVector = FALSE)
        save(edit_catalog_normalization(state(), proposal, unit()$request)); selected(NULL); removeModal()
      }, error = report_error)
    })
    output$packet <- downloadHandler(filename = function() paste0("catalog-interpretation-", substr(unit()$key, 1L, 12L), ".json"),
      content = function(file) { req(unit()); verify_catalog_normalization_sources(program(), unit(), capture_root); write_source_json(c(list(unit_key = unit()$key), unit()$request), file) })
    output$draft <- downloadHandler(filename = function() "catalog-requirements-draft.json", content = function(file) { req(state()); write_source_json(state()$proposal, file) })
    output$export_control <- renderUI({
      if (is.null(state()) || !catalog_normalization_approved(state())) return(p(class = "text-hint", "Reviewed export becomes available after the complete unit is signed off. Each linked course requires its own review."))
      downloadButton(session$ns("reviewed"), "Download reviewed requirements")
    })
    output$reviewed <- downloadHandler(filename = function() "catalog-requirements-reviewed.json", content = function(file) {
      req(state()); verify_catalog_normalization_sources(program(), unit(), capture_root)
      current <- read_catalog_normalization_review(root, unit(), imported())
      write_source_json(export_catalog_normalization(program(), unit(), imported(), current), file)
    })
  })
}
