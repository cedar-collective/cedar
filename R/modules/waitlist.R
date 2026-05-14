# Shiny Module: Waitlists Tab
#
# Course waitlist inspection — by count, major, and student classification.
# Also handles cross-tab navigation from regstats via the wl_navigate input.
#
# Exported functions:
#   waitlistUI(id, sections, next_term)
#   waitlistServer(id, students, parent_session)
#
# Cross-tab note: the regstats tab triggers navigation here via
# Shiny.setInputValue('waitlist-wl_navigate', ...) — the namespace prefix is
# required because wl_navigate lives inside this module.

waitlistUI <- function(id, sections, next_term) {
  ns <- NS(id)
  tagList(
    h1("Course Waitlist Reporting", style = "margin-bottom: 20px;"),

    fluidRow(
      column(4,
        selectizeInput(ns("wl_course"), "Select Course", multiple = TRUE, choices = NULL)
      ),
      column(3,
        selectizeInput(ns("wl_term"), "Term", multiple = TRUE,
                       choices = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
                       selected = next_term)
      ),
      column(3,
        actionButton(ns("wl_button"), label = "Inspect Wait Lists",
                     icon = icon("list-ol"), style = "margin-top: 25px;")
      )
    ),

    uiOutput(ns("wl_placeholder")),

    fluidRow(column(12, tags$h4("Waitlist by Count"),           DTOutput(ns("wl_count")))),
    fluidRow(column(12, tags$h4("Waitlist by Major"),           DTOutput(ns("wl_majors")))),
    fluidRow(column(12, tags$h4("Waitlist by Classification"),  DTOutput(ns("wl_classifications"))))
  )
}

waitlistServer <- function(id, students, parent_session) {
  moduleServer(id, function(input, output, session) {

    output$wl_placeholder <- renderUI({
      tags$p("Select a course to inspect its waitlist.",
             style = "color: #888; font-style: italic; margin-top: 10px;")
    })

    # Builds a JS link that fires wl_navigate with the namespaced input ID.
    # Regstats and any other caller must use 'waitlist-wl_navigate' as the target.
    course_link <- function(sc, t) {
      t_str <- paste(t, collapse = ",")
      sprintf(
        '<a href="javascript:void(0)" onclick="Shiny.setInputValue(\'waitlist-wl_navigate\', {course:\'%s\', term:\'%s\'}, {priority:\'event\'})">%s</a>',
        htmltools::htmlEscape(sc), htmltools::htmlEscape(t_str), htmltools::htmlEscape(sc)
      )
    }

    run_wl_inspection <- function(course, term) {
      course <- if (length(course) == 0 || identical(course, "")) NULL else course
      term   <- if (length(term)   == 0) NULL else term

      if (is.null(course) && is.null(term)) {
        showNotification("Please select a course or term before inspecting waitlists.",
                         type = "warning", duration = 5)
        return()
      }

      output$wl_placeholder <- renderUI({ NULL })

      opt <- list(course = course, term = term)
      waitlist_data <- inspect_waitlist(students, opt)

      term_str <- paste(term, collapse = ",")

      output$wl_count <- DT::renderDataTable({
        data <- waitlist_data[["count"]] %>%
          arrange(desc(count)) %>%
          mutate(subject_course = course_link(subject_course, term_str))
        count_col <- which(colnames(data) == "count") - 1L
        DT::datatable(data, escape = FALSE, rownames = FALSE,
                      options = list(pageLength = 25, scrollX = TRUE,
                                     order = list(list(count_col, "desc"))))
      })

      output$wl_majors <- DT::renderDataTable({
        data <- waitlist_data[["majors"]] %>%
          arrange(desc(count)) %>%
          mutate(subject_course = mapply(course_link, subject_course, term))
        count_col <- which(colnames(data) == "count") - 1L
        DT::datatable(data, escape = FALSE, rownames = FALSE,
                      options = list(pageLength = 25, scrollX = TRUE,
                                     order = list(list(count_col, "desc"))))
      })

      output$wl_classifications <- DT::renderDataTable({
        data <- waitlist_data[["classifications"]] %>%
          arrange(desc(count)) %>%
          mutate(subject_course = mapply(course_link, subject_course, term))
        count_col <- which(colnames(data) == "count") - 1L
        DT::datatable(data, escape = FALSE, rownames = FALSE,
                      options = list(pageLength = 25, scrollX = TRUE,
                                     order = list(list(count_col, "desc"))))
      })
    }

    # Initialize course choices server-side
    updateSelectizeInput(session, "wl_course",
                         choices = sort(unique(students$subject_course)),
                         server = TRUE)

    observeEvent(input$wl_button, {
      log_report_generation(session, "waitlist", list(
        course = input$wl_course,
        term   = input$wl_term
      ))
      run_wl_inspection(input$wl_course, input$wl_term)
    }, ignoreInit = TRUE)

    # Navigate from regstats (or any other tab) to the Waitlists tab and run inspection.
    # Triggered via Shiny.setInputValue('waitlist-wl_navigate', {course, term}).
    observeEvent(input$wl_navigate, {
      nav    <- input$wl_navigate
      course <- nav$course %||% ""
      term   <- nav$term   %||% ""
      message("[wl_navigate] course='", course, "' term='", term, "'")

      updateNavbarPage(parent_session, "main_navbar", selected = "Waitlists")

      if (nzchar(course))
        parent_session$sendCustomMessage("selectize_set_value",
                                         list(id = session$ns("wl_course"), value = course))
      if (nzchar(term))
        updateSelectizeInput(session, "wl_term", selected = term)

      tryCatch(
        run_wl_inspection(
          if (nzchar(course)) course else NULL,
          if (nzchar(term))   term   else NULL
        ),
        error = function(e) showNotification(
          paste("Waitlist error:", conditionMessage(e)), type = "error", duration = 10
        )
      )
    })
  })
}
