# Shiny Module: Waitlists Tab
#
# Course waitlist inspection — by count, major, and student classification.
# Also handles cross-tab navigation from regstats via the wl_navigate input.
#
# Exported functions:
#   waitlistUI(id, sections, next_term, dept_choices)
#   waitlistServer(id, students, parent_session)
#
# Cross-tab note: the regstats tab triggers navigation here via
# Shiny.setInputValue('waitlist-wl_navigate', ...) — the namespace prefix is
# required because wl_navigate lives inside this module.

waitlistUI <- function(id, sections, next_term, dept_choices) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Waitlists",
      "Students waiting for enrollment in full courses, by count, major, and classification.",
      fluidRow(class = "explore-filter-row explore-filter-row--dense",
        column(2, class = "wl-filter-campus",
          selectizeInput(ns("wl_campus"), "Campus", multiple = TRUE,
                         choices = sort(unique(sections$campus)),
                         selected = c("ABQ", "EA"))
        ),
        column(1, class = "wl-filter-college",
          selectizeInput(ns("wl_college"), "College", multiple = TRUE,
                         choices = sort(unique(sections$college)))
        ),
        column(2, class = "wl-filter-dept",
          selectizeInput(ns("wl_dept"), "Department", multiple = TRUE,
                         choices = dept_choices)
        ),
        column(1, class = "wl-filter-level",
          selectizeInput(ns("wl_level"), "Level", multiple = TRUE,
                         choices = sort(unique(sections$level)))
        ),
        column(2, class = "wl-filter-term",
          selectizeInput(ns("wl_term"), "Term", multiple = TRUE,
                         choices = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
                         selected = next_term)
        ),
        column(1, class = "wl-filter-pot",
          selectInput(ns("wl_pt"), "PoT", multiple = TRUE,
                      choices = sort(unique(sections$part_term)))
        ),
        column(2, class = "wl-filter-course",
          selectizeInput(ns("wl_course"), "Course", multiple = TRUE, choices = NULL)
        ),
        column(2, class = "wl-filter-action",
          filter_actions(
            actionButton(ns("wl_button"), label = "Inspect Waitlists",
                         icon = icon("list-ol"), class = "btn-primary")
          )
        )
      )
    ),

    uiOutput(ns("wl_output"))
  )
}

waitlistServer <- function(id, students, parent_session) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    wl_has_run <- reactiveVal(FALSE)

    output$wl_output <- renderUI({
      if (!wl_has_run()) {
        return(empty_state("Select a course or term and click Inspect Waitlists."))
      }
      tagList(
        info_panel("Column guide",
          tags$ul(
            tags$li(tags$strong("Waitlisted"), " — unique students on the waitlist who are not already registered for the same course."),
            tags$li(tags$strong("Program"), " — student's declared major or program code."),
            tags$li(tags$strong("Classification"), " — academic level (Freshman, Sophomore, Junior, Senior, Graduate, etc.).")
          )
        ),
        tags$h5("Course Overview",
                style = "margin: 16px 0 4px 0; font-weight: 600; color: #333;"),
        tags$p("Unique waitlisted students per course (students already registered elsewhere are excluded).",
               style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
        reactable::reactableOutput(ns("wl_count")),
        tags$hr(style = "margin: 20px 0 12px 0;"),
        fluidRow(
          column(6,
            tags$h5("By Program", style = "margin-bottom: 4px; font-weight: 600; color: #333;"),
            tags$p("Which programs have students waiting.",
                   style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
            reactable::reactableOutput(ns("wl_majors"))
          ),
          column(6,
            tags$h5("By Classification", style = "margin-bottom: 4px; font-weight: 600; color: #333;"),
            tags$p("Academic level of students on the waitlist.",
                   style = "color: #666; font-size: 0.85em; margin-bottom: 8px;"),
            reactable::reactableOutput(ns("wl_classifications"))
          )
        )
      )
    })

    run_wl_inspection <- function(course, term) {
      course <- if (length(course) == 0 || identical(course, "")) NULL else course
      term   <- if (length(term)   == 0) NULL else term

      if (is.null(course) && is.null(term)) {
        showNotification("Please select a course or term before inspecting waitlists.",
                         type = "warning", duration = 5)
        return()
      }

      wl_has_run(TRUE)

      opt <- list(
        course         = course,
        term           = term,
        course_campus  = if (length(input$wl_campus)  > 0) input$wl_campus  else NULL,
        course_college = if (length(input$wl_college) > 0) input$wl_college else NULL,
        dept           = if (length(input$wl_dept)    > 0) input$wl_dept    else NULL,
        level          = if (length(input$wl_level)   > 0) input$wl_level   else NULL,
        pt             = if (length(input$wl_pt)      > 0) input$wl_pt      else NULL
      )
      waitlist_data <- inspect_waitlist(students, opt)

      term_str <- paste(term, collapse = ",")

      wl_reactable <- function(data, columns) {
        reactable::reactable(
          data,
          theme               = cedar_tbl_theme,
          striped             = TRUE,
          highlight           = TRUE,
          compact             = TRUE,
          searchable          = TRUE,
          defaultPageSize     = 15,
          showPageSizeOptions = TRUE,
          pageSizeOptions     = c(15, 30, 50),
          defaultSorted       = list(count = "desc"),
          columns             = columns
        )
      }

      output$wl_count <- reactable::renderReactable({
        data <- waitlist_data[["count"]] %>% arrange(desc(count))
        wl_reactable(data, list(
          campus         = reactable::colDef(name = "Campus",     maxWidth = 65),
          subject_course = reactable::colDef(name = "Course",     minWidth = 90,
            cell = function(v, i) {
              htmltools::tags$a(
                href = "javascript:void(0)",
                onclick = sprintf("Shiny.setInputValue('waitlist-wl_navigate',{course:'%s',term:'%s'},{priority:'event'})",
                                  htmltools::htmlEscape(v), htmltools::htmlEscape(term_str)),
                htmltools::span(style = "font-weight:600", v)
              )
            }),
          course_title   = reactable::colDef(name = "Title",      minWidth = 160),
          count          = reactable::colDef(name = "Waitlisted", maxWidth = 100, align = "right")
        ))
      })

      output$wl_majors <- reactable::renderReactable({
        data <- waitlist_data[["majors"]] %>% arrange(desc(count))
        wl_reactable(data, list(
          campus         = reactable::colDef(name = "Campus",     maxWidth = 65),
          term           = reactable::colDef(name = "Term",       maxWidth = 80),
          subject_course = reactable::colDef(name = "Course",     minWidth = 90,
            cell = function(v, i) {
              t <- data$term[i]
              htmltools::tags$a(
                href = "javascript:void(0)",
                onclick = sprintf("Shiny.setInputValue('waitlist-wl_navigate',{course:'%s',term:'%s'},{priority:'event'})",
                                  htmltools::htmlEscape(v), htmltools::htmlEscape(as.character(t))),
                htmltools::span(style = "font-weight:600", v)
              )
            }),
          course_title   = reactable::colDef(name = "Title",      minWidth = 140),
          major_code     = reactable::colDef(name = "Program",    minWidth = 120),
          count          = reactable::colDef(name = "Waitlisted", maxWidth = 100, align = "right")
        ))
      })

      output$wl_classifications <- reactable::renderReactable({
        data <- waitlist_data[["classifications"]] %>% arrange(desc(count))
        wl_reactable(data, list(
          campus                = reactable::colDef(name = "Campus",         maxWidth = 65),
          term                  = reactable::colDef(name = "Term",           maxWidth = 80),
          subject_course        = reactable::colDef(name = "Course",         minWidth = 90,
            cell = function(v, i) {
              t <- data$term[i]
              htmltools::tags$a(
                href = "javascript:void(0)",
                onclick = sprintf("Shiny.setInputValue('waitlist-wl_navigate',{course:'%s',term:'%s'},{priority:'event'})",
                                  htmltools::htmlEscape(v), htmltools::htmlEscape(as.character(t))),
                htmltools::span(style = "font-weight:600", v)
              )
            }),
          course_title          = reactable::colDef(name = "Title",          minWidth = 140),
          student_classification = reactable::colDef(name = "Classification", minWidth = 130),
          count                 = reactable::colDef(name = "Waitlisted",     maxWidth = 100, align = "right")
        ))
      })
    }

    # Initialize course choices server-side
    updateSelectizeInput(session, "wl_course",
                         choices = sort(unique(students$subject_course)),
                         server = TRUE)

    observeEvent(input$wl_button, {
      log_report_generation(session, "waitlist", list(
        campus  = input$wl_campus,
        college = input$wl_college,
        dept    = input$wl_dept,
        level   = input$wl_level,
        pt      = input$wl_pt,
        course  = input$wl_course,
        term    = input$wl_term
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
