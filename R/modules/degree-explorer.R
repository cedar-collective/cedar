# One degree at a time, shown as an adaptive semester roadmap.

degreeExplorerUI <- function(id, catalog, roadmaps) {
  ns <- NS(id)
  if (!nrow(catalog$catalogs)) return(empty_state("No degree roadmaps are configured for this institution."))
  starts <- roadmaps$starts
  choices <- function(track) stats::setNames(starts$start_id[starts$track == track], starts$label[starts$track == track])
  tagList(
    htmltools::htmlDependency("cedar-roadmap", "1.7.0", src = c(href = ""),
      stylesheet = "cedar-roadmap.css", script = "cedar-roadmap.js"),
    filter_bar("Build your degree roadmap", "Choose a degree and your starting courses. Watch the sequence change.",
      fluidRow(
        column(4, selectInput(ns("dx_catalog_id"), "Degree · latest catalog", choices = degree_catalog_choices(catalog))),
        column(3, selectInput(ns("dx_math_start"), "Where will you start in math?",
          choices = degree_math_start_choices(roadmaps, catalog$catalogs$catalog_id[1]))),
        column(3, selectInput(ns("dx_english_start"), "Where will you start in English?", choices = choices("english"))),
        column(2, selectInput(ns("dx_start_season"), "First semester", choices = c(Fall = "fall", Spring = "spring"))))),
    uiOutput(ns("roadmap")),
    tags$p(class = "text-hint", "Want to see what students actually take? Open Pathways → Course paths."))
}

degreeExplorerServer <- function(id, catalog, roadmaps, sections, students, edges) {
  if (!nrow(catalog$catalogs)) return(invisible(NULL))
  moduleServer(id, function(input, output, session) {
    observeEvent(input$dx_catalog_id, {
      updateSelectInput(session, "dx_math_start",
        choices = degree_math_start_choices(roadmaps, input$dx_catalog_id),
        selected = isolate(input$dx_math_start))
    }, ignoreInit = TRUE)
    output$roadmap <- renderUI({
      req(input$dx_catalog_id, input$dx_math_start, input$dx_english_start, input$dx_start_season)
      view <- build_degree_roadmap_view(catalog, roadmaps, input$dx_catalog_id,
        input$dx_math_start, input$dx_english_start, input$dx_start_season)
      cedar_semester_roadmap(view, session$ns("semester_board"),
        history_id = session$ns("course_history"), select_id = session$ns("course_node"))
    })
    # Source tables and edges are immutable for the session. Cache clicked cards
    # by the full selection, including season and entry context for suggestions.
    history <- bindCache(reactive({
      req(input$course_node$catalog_id %in% catalog$catalogs$catalog_id,
        input$course_node$node_id)
      build_degree_popup_history(sections, students, edges, catalog, roadmaps,
        CEDAR_GEN_ED_COURSES, input$course_node)
    }), input$course_node, cache = "session")
    output$course_history <- renderUI({
      h <- history()
      if (h$kind == "allowance") cedar_degree_allowance_history(h, session$ns("course_history_table"))
      else cedar_degree_course_history(h, session$ns("course_history_table"))
    })
    output$course_history_table <- reactable::renderReactable({
      h <- history()
      req(h$state == "ready")
      if (h$kind == "allowance") cedar_degree_allowance_table(h) else cedar_degree_history_table(h)
    })
    # Native dialog visibility does not emit Bootstrap's modal visibility events.
    # req() keeps this lazy; a click must render even if Shiny last saw it hidden.
    outputOptions(output, "course_history", suspendWhenHidden = FALSE)
    outputOptions(output, "course_history_table", suspendWhenHidden = FALSE)
  })
}
