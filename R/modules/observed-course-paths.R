# Descriptive course mix belongs to Pathways and uses its selected population.
observedCoursePathsUI <- function(id, campuses) {
  ns <- NS(id)
  tagList(
    subtab_header("Course paths", "See the kinds of courses students actually take, term by term, for the population defined above."),
    filter_bar("Course paths", "Use delivery campuses and the number of observed enrolled terms to set the view.",
      fluidRow(
        column(6, selectizeInput(ns("campus"), "Delivery campus", choices = campuses,
          selected = intersect(CEDAR_CAMPUS_DEFAULT, campuses), multiple = TRUE)),
        column(3, numericInput(ns("max_terms"), "Enrolled terms", value = 8, min = 1, max = 16)),
        column(3, actionButton(ns("button"), "Show course paths", class = "btn-primary")))),
    cedar_loading_overlay(id, "button", report_type = "degree-paths", fresh_default = 5,
      uiOutput(ns("path_scope")),
      plotly::plotlyOutput(ns("path_plot"), height = "620px"),
      dashboard_section("Courses inside the groups", "Select a group to inspect its courses. Counts retain delivery campus and observed term.",
        selectInput(ns("detail_group"), "Course group", choices = c("All groups" = "all")),
        reactable::reactableOutput(ns("path_courses")))),
    info_panel("How these paths are counted",
      tags$p("Term one is first observed undergraduate enrollment; summer counts and gaps do not advance the clock. Registered students and late drops count; waitlists and early drops do not. Earlier study may be missing at the data boundary."),
      tags$p("Cells show participation, not completion or prerequisites. Students can take several groups together, so shares can exceed 100% in total. Subject groups do not establish degree eligibility. Small cells are suppressed.")))
}

observedCoursePathsServer <- function(id, students, population, description, edges, groups) {
  moduleServer(id, function(input, output, session) {
    paths <- reactiveVal(NULL)
    # A changed population clears the old result; the chart always describes the current population.
    observeEvent(population(), { paths(NULL) }, ignoreInit = TRUE, ignoreNULL = FALSE)
    output$path_scope <- renderUI({
      p <- paths()
      if (is.null(p)) return(empty_state("Define a population above, then show course paths."))
      div(class = "scope-bar scope-bar--stacked", p$note)
    })
    output$path_plot <- plotly::renderPlotly({ req(paths()); plot_grouped_student_paths(paths()) })
    output$path_courses <- reactable::renderReactable({
      req(paths())
      display <- degree_path_course_table(paths(), input$detail_group %||% "all") %>%
        dplyr::select(campus, relative_term, group_label, subject_course, n_students, n_eligible, pct_students)
      reactable::reactable(display, theme = cedar_tbl_theme, compact = TRUE, searchable = TRUE,
        defaultPageSize = 20, columns = list(
          campus = reactable::colDef(name = "Campus"),
          relative_term = reactable::colDef(name = "Enrolled term", format = reactable::colFormat(digits = 0)),
          group_label = reactable::colDef(name = "Course group"),
          subject_course = reactable::colDef(name = "Course"),
          n_students = reactable::colDef(name = "Students"),
          n_eligible = reactable::colDef(name = "Students at term"),
          pct_students = reactable::colDef(name = "% at term", format = reactable::colFormat(digits = 1))))
    })

    observeEvent(input$button, {
      if (is.null(population()) || !nrow(population())) {
        showNotification("Define a nonempty population above first.", type = "warning")
        signal_load_complete(session, id, error = TRUE)
        return()
      }
      if (!length(input$campus)) {
        showNotification("Select at least one delivery campus.", type = "warning")
        signal_load_complete(session, id, error = TRUE)
        return()
      }
      timer <- start_report_timer("degree-paths")
      tryCatch({
        result <- withProgress(message = "Building course paths", value = 0.5, {
          build_population_course_paths(students, population(), groups,
            list(campus = input$campus, max_terms = input$max_terms, data_edges = edges), description())
        })
        paths(result)
        updateSelectInput(session, "detail_group", choices = c("All groups" = "all",
          stats::setNames(result$groups$group_id, result$groups$group_label)), selected = "all")
        duration <- end_report_timer(timer, result = result)
        signal_load_complete(session, id, duration_sec = duration)
      }, error = function(e) {
        paths(NULL)
        showNotification(conditionMessage(e), type = "error", duration = NULL)
        end_report_timer(timer, success = FALSE, error = e)
        signal_load_complete(session, id, error = TRUE)
      })
    }, ignoreInit = TRUE)
  })
}
