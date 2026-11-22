# Bird's Eye > First Year
#
# The first of the three pages (First Year, Retention, Graduation): how much
# of each entering class is still enrolled in its first semesters, by how the
# students entered. Retention reads continuing students term by term;
# Graduation reads students at the end.
#
# The module holds no analysis: it collects the term type, level, home
# campuses and who a class holds, calls retention_dashboard_milestones()
# (features/retention-dashboard.R) and lays out its rows. It builds only while
# the tab is open, once per scope a session asks for.
#
# Exported functions:
#   firstYearUI(id, campuses)
#   firstYearServer(id, student_terms, degrees, programs, edges, active)

# campuses  the home campuses to offer; it opens on the main campus
#           (CEDAR_CAMPUS_MAIN), and none selected reads every campus.
firstYearUI <- function(id, campuses) {
  ns <- NS(id)
  # The page opens on student_levels.csv's first level.
  levels <- stats::setNames(names(CEDAR_STUDENT_LEVEL_LABELS), unname(CEDAR_STUDENT_LEVEL_LABELS))
  tagList(
    filter_bar(
      "First Year",
      "How much of each entering class is still here after its first semesters?",
      fluidRow(
        column(3, radioButtons(ns("term_type"), "Entering term", choices = RETENTION_TERM_TYPES,
                               selected = "fall", inline = TRUE)),
        column(3, selectInput(ns("level"), "Student level", choices = levels, selected = levels[[1]])),
        column(4, selectizeInput(ns("campus"), "Home campus", choices = campuses, multiple = TRUE,
                                 selected = intersect(CEDAR_CAMPUS_MAIN, campuses),
                                 options = list(placeholder = "Every home campus")))
      )
    ),
    # Opened by the server while it reads (cedar_with_loading()).
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f331", loading_label = "Reading the entering classes…",
    dashboard_section(
      "Each Entering Class, Semester by Semester",
      "How much of each entering class is still enrolled in its 2nd, 3rd, 4th and 5th semesters?",
      method = uiOutput(ns("method_milestones")),
      radioButtons(ns("entry"), "Entering students", choices = RETENTION_ENTRY_CHOICES,
                   selected = "first_time", inline = TRUE),
      uiOutput(ns("milestones_finding")),
      plotly::plotlyOutput(ns("milestones_plot"), height = "380px")
    )
    )
  )
}

# Who an entering class holds: the page's choices, and what each asks the cone
# for. Full-time is the time status of the entering term.
RETENTION_ENTRY_CHOICES <- c("First-time" = "first_time", "First-time, full-time" = "first_time_ft",
                             "New transfer" = "transfer", "Everyone new at this level" = "all")
RETENTION_ENTRY_OPTIONS <- list(
  first_time = list(entry = "first_time", time_status = NULL),
  first_time_ft = list(entry = "first_time", time_status = "FT"),
  transfer = list(entry = "transfer", time_status = NULL),
  all = list(entry = "all", time_status = NULL)
)

.retention_entry_note <- function(entry, type, n_summer_starts) {
  switch(entry,
    first_time = paste0(
      "An entering class is the students the registrar's record calls first-time in that ", type,
      " term and who were enrolled in it, by home campus that term. A student who took college courses in high school ",
      "enters when the record calls them first-time, not at their first course. A first-time student who started in the ",
      "summer and was enrolled that fall is in the fall class, as federal reporting counts them (",
      fmt_count(n_summer_starts), " over these classes). The full-time choice keeps those full-time in their entering term."),
    transfer = paste0("An entering class is the students the registrar's record calls a new transfer in that ", type,
                      " term and who were enrolled in it, by home campus that term."),
    all = paste0("An entering class is every student whose first enrolled term at this level was that ", type,
                 " term, by home campus that term. It includes transfer students and, among undergraduates, students ",
                 "taking college courses while in high school."))
}

# ── Server ───────────────────────────────────────────────────────────────────

# student_terms, degrees, programs, edges   the loaded tables and edges.
# active   reactive: TRUE while the tab is open.
firstYearServer <- function(id, student_terms, degrees, programs, edges, active) {
  moduleServer(id, function(input, output, session) {
    # The entering classes are read on their own, so choosing who a class
    # holds rebuilds this chart and nothing else.
    milestones <- reactive({
      req(isTRUE(active()), input$term_type, input$level, input$entry)
      entry <- RETENTION_ENTRY_OPTIONS[[input$entry]]
      cedar_shared_result(list("retention_milestones", input$term_type, input$level, input$campus, input$entry), function() cedar_with_loading(session, session$ns("load"), report_type = "first_year", tryCatch(
        retention_dashboard_milestones(student_terms, degrees, list(
          term_type = input$term_type, student_level = input$level,
          campus = if (length(input$campus) > 0) input$campus else NULL, data_edges = edges,
          entry = entry$entry, entry_time_status = entry$time_status), programs),
        error = function(e) {
          showNotification(paste("Entering classes:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        })))
    })

    output$milestones_finding <- renderUI({
      ms <- milestones(); req(ms)
      sentence <- retention_milestone_sentence(list(milestones = ms))
      if (length(sentence) == 0L) return(empty_state("No entering class in this scope has a settled later term to read."))
      lead_text(sentence)
    })
    output$milestones_plot <- plotly::renderPlotly({
      ms <- milestones(); req(ms, any(!is.na(ms$here_pct)))
      plot_entering_class_milestones(list(milestones = ms))
    })
    output$method_milestones <- renderUI({
      ms <- milestones(); req(ms)
      tags$ul(
        tags$li(.retention_entry_note(attr(ms, "entry"), tolower(names(RETENTION_TERM_TYPES)[RETENTION_TERM_TYPES == input$term_type]), attr(ms, "n_summer_starts"))),
        tags$li("Still enrolled means enrolled in that later term on any campus, or awarded a degree by then. A student away one term and back the next is missing from the first and counted in the second."),
        tags$li(paste0("Each line is one semester of the class's time here: the entering term is the 1st, so a year on is ",
                       "the 3rd, the one retention is usually quoted at. A semester is a fall or a spring; summer is not ",
                       "counted. The gap between two lines is the share lost between them.")),
        tags$li(paste0("A line stops at the last class whose later term has settled (enrollment settled through ",
                       fmt_term(attr(ms, "edge")), "). ",
                       if (identical(attr(ms, "entry"), "all")) paste0(
                         fmt_term(attr(ms, "first_term")), " is the first term on record, so no one can be called new in it: ",
                         fmt_count(attr(ms, "n_first_term")), " students first seen then are in no class. "),
                       "A class needs ",
                       attr(ms, "min_n"), " students for a rate.")))
    })
  })
}
