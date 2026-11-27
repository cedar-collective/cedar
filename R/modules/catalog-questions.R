# Admin > Data & Usage > Catalog Review > Catalog questions: every open
# question in the catalog readings, and the boards compiled from them.
# The list and its words are built in R/features/catalog-questions.R.

catalog_questions_method <- function() {
  tagList(
    p("Each reading of a program's catalog page lists what it could not settle from the page: questions, and rules it left unresolved. Each cites the passage it is about. Every program's latest reading is listed here, with or without a board."),
    tags$ul(
      tags$li(tags$strong(CATALOG_QUESTION_SETTLERS[["catalog"]]), ": the catalog contradicts itself, is unclear or names nothing. The department or the catalog office answers, and the catalog changes."),
      tags$li(tags$strong(CATALOG_QUESTION_SETTLERS[["capture"]]), ": the catalog says it on a linked page or in a footnote that CEDAR's copy did not keep. The catalog scan is fixed."),
      tags$li(tags$strong(CATALOG_QUESTION_SETTLERS[["reading"]]), ": the catalog leaves a choice and the reading planned it one way. A reviewer confirms or changes the reading.")),
    p("Who can settle each item is the reading's own judgment, in its file's triage. To change an answer, edit the file the item names, then recompile the boards (scripts/compile-degree-interpretations.R --write)."),
    p("The list also holds every program whose catalog page gives the degree two totals: the Degree Hours field and a total printed on the page, such as Grand Total Credits. CEDAR's catalog scan finds these whether or not CEDAR has read the program, and only the catalog can settle them."))
}

catalogQuestionsUI <- function(id, drafts) {
  ns <- NS(id)
  if (is.null(drafts)) return(empty_state("No catalog readings are compiled for this institution."))
  tagList(
    subtab_header("Catalog questions", "Every open question in CEDAR's readings of the catalog, the passage it is about, and who can settle it.",
      method = catalog_questions_method()),
    uiOutput(ns("stale")),
    fluidRow(
      column(4, selectInput(ns("settled_by"), "Who can settle it", catalog_question_settler_choices(drafts$questions), width = "100%")),
      column(5, selectInput(ns("program"), "Program", catalog_question_program_choices(drafts$questions), width = "100%")),
      column(3, filter_actions(downloadButton(ns("download"), "Download these questions")))),
    reactable::reactableOutput(ns("questions")),
    dashboard_section("Boards compiled from a reading",
      "Each draft board in Degree Explorer, whether its reading is signed off, and what the board leaves out.",
      reactable::reactableOutput(ns("boards")),
      method = tagList(
        p("A board compiled from a reading takes the place of the hand-built board for the same degree, or joins the degree list when there is none. It is labelled a draft until the review store holds a complete sign-off of the exact reading it was compiled from."),
        p("What the board leaves out is its catalog row's note, also shown under \"Rules behind this plan\" in Degree Explorer. The status is read when the app starts, so a sign-off shows after the next restart."))))
}

catalogQuestionsServer <- function(id, drafts, boards) {
  if (is.null(drafts)) return(invisible(NULL))
  moduleServer(id, function(input, output, session) {
    settled_by <- reactive(input$settled_by %||% "")
    program <- reactive(input$program %||% "")
    rows <- reactive(catalog_question_rows(drafts$questions, settled_by(), program()))
    output$stale <- renderUI({
      if (!length(drafts$questions_stale)) return(NULL)
      div(class = "alert alert-warning", tags$strong("These readings changed after the list was compiled: "),
        paste(drafts$questions_stale, collapse = ", "),
        ". Their rows may be out of date until the boards are recompiled (scripts/compile-degree-interpretations.R --write).")
    })
    output$questions <- reactable::renderReactable({
      shown <- rows()
      if (!nrow(shown)) return(reactable::reactable(data.frame(Status = "No open questions for this choice."), pagination = FALSE, theme = cedar_tbl_theme))
      preview <- htmlwidgets::JS("function(cell) { var text = cell.value; return text.length > 280 ? text.slice(0, 280) + '…' : text; }")
      reactable::reactable(shown[c("program", "settled_by", "question", "section", "passage", "location")],
        theme = cedar_tbl_theme, compact = TRUE, searchable = TRUE, defaultPageSize = 10L, wrap = TRUE,
        columns = list(
          program = reactable::colDef(name = "Program", minWidth = 150,
            cell = function(value, index) tags$a(href = shown$catalog_url[index], target = "_blank", rel = "noopener noreferrer", value)),
          settled_by = reactable::colDef(name = "Who can settle it", minWidth = 110),
          question = reactable::colDef(name = "Question", minWidth = 260),
          section = reactable::colDef(name = "Catalog section", minWidth = 110),
          passage = reactable::colDef(name = "What the catalog says", minWidth = 240, cell = preview),
          location = reactable::colDef(name = "Change it in", minWidth = 170)))
    })
    output$download <- downloadHandler(
      filename = function() "catalog-questions.md",
      content = function(file) writeLines(format_catalog_questions(rows(), catalog_question_scope(settled_by(), program())), file))
    output$boards <- reactable::renderReactable({
      reactable::reactable(degree_draft_board_rows(boards), theme = cedar_tbl_theme, compact = TRUE, pagination = FALSE, wrap = TRUE,
        columns = list(degree = reactable::colDef(name = "Degree", minWidth = 160),
          review = reactable::colDef(name = "Its reading", minWidth = 200),
          note = reactable::colDef(name = "What the board leaves out", minWidth = 360,
            cell = function(value) if (nzchar(value)) value else "\u2014")))
    })
  })
}
