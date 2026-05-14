# Shiny Module: Open Seats (Seatfinder) Tab
#
# Shows courses with available capacity for selected filters, with DFW history.
#
# Exported functions:
#   seatfinderUI(id, sections, next_term, dept_choices)
#   seatfinderServer(id, students, sections, faculty)

seatfinderUI <- function(id, sections, next_term, dept_choices) {
  ns <- NS(id)
  tagList(
    h1("Open Seats"),

    div(class = "alert alert-info", style = "font-size: 0.88em;",
      icon("circle-info"), " ",
      tags$strong("Open Seats"), " shows courses with available capacity (registered < max enrollment)
      matching your filters. ", tags$strong("DFW %"), " is the historical D/F/Withdrawal rate for
      that course under the same filter parameters — no DFW % means the course hasn't been offered
      with those filters before. DFW rates reflect grades from Fall 2019 onward; early drops
      (pre-census DR) are excluded from the denominator.",
      tags$br(),
      "Additional tabs: ", tags$strong("Offered Last Year"), " — courses on the schedule a year ago;
      ", tags$strong("Not Offered Last Year"), " — gaps vs. the prior year (may warrant investigation);
      ", tags$strong("Common"), " — sections running in both years;
      ", tags$strong("Gen Ed Likely"), " — active sections capped at 0, typically holding spots for
      gen ed courses not yet opened to general registration."
    ),

    fluidRow(
      column(1,
        selectizeInput(ns("sf_campus"), "Campus", multiple = TRUE,
                       choices = sort(unique(sections$campus)),
                       selected = c("ABQ", "EA"))
      ),
      column(1,
        selectizeInput(ns("sf_college"), "College", multiple = TRUE,
                       choices = sort(unique(sections$college)))
      ),
      column(2,
        selectizeInput(ns("sf_dept"), "Department", multiple = TRUE,
                       choices = dept_choices)
      ),
      column(2,
        selectizeInput(ns("sf_term"), "Term", multiple = TRUE,
                       choices = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
                       selected = next_term)
      ),
      column(1,
        selectInput(ns("sf_pt"), "PoT", multiple = TRUE,
                    choices = sort(unique(sections$part_term)))
      ),
      column(1,
        selectInput(ns("sf_im"), "Method", multiple = TRUE,
                    choices = sort(unique(sections$delivery_method)))
      ),
      column(2,
        selectInput(ns("sf_level"), "Level", multiple = TRUE,
                    choices = sort(unique(sections$level)),
                    selected = "lower")
      ),
      column(2,
        actionButton(ns("sf_button"), label = "Refresh table", icon = icon("sync-alt"))
      )
    ),

    tabsetPanel(
      tabPanel("Courses",       DT::DTOutput(ns("type_summary"))),
      tabPanel("Common",        DT::DTOutput(ns("courses_common"))),
      tabPanel("Prev",          DT::DTOutput(ns("courses_prev"))),
      tabPanel("New",           DT::DTOutput(ns("courses_new"))),
      tabPanel("Gen Ed",        DT::DTOutput(ns("gen_ed_summary"))),
      tabPanel("Gen Ed Likely", DT::DTOutput(ns("gen_ed_likely")))
    )
  )
}

seatfinderServer <- function(id, students, sections, faculty) {
  moduleServer(id, function(input, output, session) {

    observeEvent(input$sf_button, {
      if (is.null(input$sf_term) || length(input$sf_term) == 0) {
        showNotification("Please select at least one term before finding open seats.",
                         type = "warning", duration = 5)
        return()
      }

      log_report_generation(session, "open-seats", list(
        campus  = input$sf_campus,
        college = input$sf_college,
        dept    = input$sf_dept,
        term    = input$sf_term,
        pt      = input$sf_pt,
        im      = input$sf_im,
        level   = input$sf_level
      ))

      status_message <- create_timing_status_message("open-seats", "Finding open seats")
      showNotification(status_message, type = "warning", duration = NULL, id = "open_seats_loading")

      timer <- start_report_timer("open-seats", list(
        dept = input$sf_dept,
        term = input$sf_term
      ))

      tryCatch({
        opt <- list(
          course_campus  = input$sf_campus,
          course_college = input$sf_college,
          dept           = input$sf_dept,
          term           = input$sf_term,
          pt             = input$sf_pt,
          im             = input$sf_im,
          level          = input$sf_level,
          group_cols     = input$sf_agg_by
        )

        courses_list <- seatfinder(students, sections, faculty, opt)

        output$type_summary <- DT::renderDataTable({
          create_seatfinder_datatable(courses_list[["type_summary"]],
                                      color_avail = TRUE, color_dfw = TRUE)
        }, options = list(pageLength = 50))

        output$courses_common <- DT::renderDataTable({
          create_styled_datatable(
            courses_list[["courses_common"]],
            column_schemes = list("avail" = "availability", "DFW %" = "dfw")
          )
        }, options = list(pageLength = 50))

        output$courses_prev <- DT::renderDataTable({
          create_styled_datatable(courses_list[["courses_prev"]])
        }, options = list(pageLength = 50))

        output$courses_new <- DT::renderDataTable({
          create_styled_datatable(courses_list[["courses_new"]])
        }, options = list(pageLength = 50))

        output$gen_ed_summary <- DT::renderDataTable({
          create_styled_datatable(courses_list[["gen_ed_summary"]])
        }, options = list(pageLength = 50))

        output$gen_ed_likely <- DT::renderDataTable({
          courses_list[["gen_ed_likely"]]
        }, options = list(pageLength = 50))

        duration_sec <- end_report_timer(timer)
        removeNotification("open_seats_loading")
        showNotification(
          paste("Open seats loaded successfully! (", round(duration_sec, 1), "s)"),
          type = "message", duration = 3
        )
      }, error = function(e) {
        handle_error(e, "open-seats", "open_seats_loading")
        tryCatch(end_report_timer(timer), error = function(te) {
          message("[seatfinder] Error ending timer: ", te$message)
        })
      })

    }, ignoreInit = TRUE)
  })
}
