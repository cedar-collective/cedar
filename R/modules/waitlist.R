# Shiny Module: Waitlists Tab
#
# Course waitlist inspection — by count, major, and student classification.
# Also handles cross-tab navigation from regstats via the wl_navigate input.
#
# Exported functions:
#   waitlistUI(id, sections, default_term, dept_choices)
#   waitlistServer(id, students, parent_session)
#
# Cross-tab note: the regstats tab triggers navigation here via
# Shiny.setInputValue('waitlist-wl_navigate', ...) — the namespace prefix is
# required because wl_navigate lives inside this module.

waitlistUI <- function(id, sections, default_term, dept_choices) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Waitlists",
      "Students waiting for enrollment in full courses, by count, major, and classification.",
      # Standard responsive filter row (matches Cancellations / Regstats): plain
      # Bootstrap columns summing to 12 so the bar wraps/stacks on small screens
      # instead of clipping. Do NOT reintroduce per-column fixed widths here.
      fluidRow(class = "explore-filter-row",
        column(1,
          selectizeInput(ns("wl_campus"), "Campus", multiple = TRUE,
                         choices = sort(unique(sections$campus)),
                         selected = c("ABQ", "EA"))
        ),
        column(1,
          selectizeInput(ns("wl_college"), "College", multiple = TRUE,
                         choices = sort(unique(sections$college)))
        ),
        column(2,
          selectizeInput(ns("wl_dept"), "Department", multiple = TRUE,
                         choices = dept_choices)
        ),
        column(2,
          selectizeInput(ns("wl_term"), "Term", multiple = TRUE,
                         choices = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
                         selected = default_term)
        ),
        column(1,
          selectizeInput(ns("wl_level"), "Level", multiple = TRUE,
                         choices = sort(unique(sections$level)))
        ),
        column(1,
          selectInput(ns("wl_pt"), "PoT", multiple = TRUE,
                      choices = sort(unique(sections$part_term)))
        ),
        column(2,
          selectizeInput(ns("wl_course"), "Course", multiple = TRUE, choices = NULL)
        ),
        column(2,
          filter_actions(
            actionButton(ns("wl_button"), label = "Inspect Waitlists",
                         icon = icon("list-ol"), class = "btn-primary"),
            actionButton(ns("wl_copy_url"), label = NULL, icon = icon("link"),
                         title = "Copy shareable link for current view",
                         class = "btn-outline-secondary btn-sm")
          )
        )
      ),
      # Light-green scope band hosting the minimum-waitlist control. This is a
      # display throttle, not a query input: broad, unfiltered runs ship tens of
      # thousands of rows to the browser and lag for several seconds, so this
      # slider trims rows below the threshold in ALL THREE result tables before
      # reactable draws them. Default 5 keeps the first paint of a broad view
      # fast; drag to 1 to see every row. Filtering runs client-side against the
      # already-computed data (see wl_apply_min), so it never re-runs the inspection.
      filter_scope_stripe(
        div(class = "wl-scope-slider",
          tags$span(class = "wl-scope-label", "Minimum waitlisted"),
          sliderInput(ns("wl_min"), label = NULL, min = 1, max = 50,
                      value = 5, step = 1, ticks = FALSE, width = "240px"),
          tags$span(class = "wl-scope-suffix", "hides smaller rows in all three tables")
        )
      )
    ),

    cedar_loading_overlay(id, "wl_button", emoji = "\U000023f3",
      report_type = "waitlist", fresh_default = 6,
      uiOutput(ns("wl_output"))
    )
  )
}

waitlistServer <- function(id, students, parent_session, sections = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    wl_has_run <- reactiveVal(FALSE)

    # Minimum-waitlist display filter, driven by the sliderInput in the filter
    # scope strip (see waitlistUI). NULL-guarded to the slider's own default (5)
    # as a belt-and-suspenders fallback. Shiny's slider input debounces (250ms)
    # client-side, so dragging won't thrash the three reactable re-renders.
    WL_MIN_DEFAULT <- 5L
    wl_min <- reactive({
      m <- input$wl_min
      if (is.null(m) || is.na(m)) WL_MIN_DEFAULT else as.integer(m)
    })

    # Drop rows whose Waitlisted count is below the threshold before handing data
    # to reactable. This re-filters the already-computed result reactively, so
    # moving the slider never re-runs inspect_waitlist — only the number of rows
    # shipped to the browser shrinks, which is the source of the multi-second lag
    # on broad, unfiltered views.
    wl_apply_min <- function(df, m) {
      if (m <= 1 || is.null(df) || !"count" %in% names(df)) df
      else filter(df, count >= m)
    }

    output$wl_output <- renderUI({
      if (!wl_has_run()) {
        return(empty_state("Select a course or term and click Inspect Waitlists."))
      }
      tagList(
        section_heading("Course Overview"),
        reactable::reactableOutput(ns("wl_count")),
        tags$hr(class = "mt-4 mb-2"),
        fluidRow(
          column(6,
            section_heading("By Program"),
            tags$p(class = "cedar-body", "Which programs have students waiting."),
            reactable::reactableOutput(ns("wl_majors"))
          ),
          column(6,
            section_heading("By Classification"),
            tags$p(class = "cedar-body", "Academic level of students on the waitlist."),
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
        # Dismiss the overlay the button click optimistically showed.
        signal_load_complete(session, id, error = TRUE)
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

      # Time the run and drive the loading overlay (start_report_timer /
      # end_report_timer also feed the shared report-timing log).
      timer <- start_report_timer("waitlist", list(course = course, term = term))
      waitlist_data <- tryCatch(
        inspect_waitlist(students, opt, sections),
        error = function(e) {
          message("[waitlist] Error: ", conditionMessage(e))
          showNotification(paste("Waitlist error:", conditionMessage(e)),
                           type = "error", duration = 10)
          tryCatch(end_report_timer(timer), error = function(te) NULL)
          signal_load_complete(session, id, error = TRUE)
          NULL
        }
      )
      if (is.null(waitlist_data)) return()

      duration_sec <- end_report_timer(timer)
      signal_load_complete(session, id, duration_sec = duration_sec)

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
        data <- wl_apply_min(waitlist_data[["count"]], wl_min()) %>% arrange(desc(count))
        wl_reactable(data, list(
          campus         = reactable::colDef(name = "Campus",     maxWidth = 65),
          college        = reactable::colDef(name = "College",    minWidth = 95),
          term           = reactable::colDef(name = "Term",       maxWidth = 80),
          part_term      = reactable::colDef(name = "PoT",        maxWidth = 70),
          subject_course = reactable::colDef(name = "Course",     minWidth = 90,
            cell = function(v, i) {
              htmltools::tags$a(
                href = "javascript:void(0)",
                onclick = sprintf("Shiny.setInputValue('waitlist-wl_navigate',{course:'%s',term:'%s'},{priority:'event'})",
                                  htmltools::htmlEscape(v), htmltools::htmlEscape(term_str)),
                htmltools::span(class = "fw-semibold", v)
              )
            }),
          course_title   = reactable::colDef(name = "Title",      minWidth = 110),
          count          = reactable::colDef(name = "Waitlisted", maxWidth = 100, align = "right"),
          n_sections     = reactable::colDef(name = "Sections",   maxWidth = 90,  align = "right"),
          avg_size       = reactable::colDef(name = "Avg Size",   maxWidth = 90,  align = "right"),
          sections_needed = reactable::colDef(name = "Sections Needed", maxWidth = 120, align = "right")
        ))
      })

      output$wl_majors <- reactable::renderReactable({
        data <- wl_apply_min(waitlist_data[["majors"]], wl_min()) %>% arrange(desc(count))
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
                htmltools::span(class = "fw-semibold", v)
              )
            }),
          course_title   = reactable::colDef(name = "Title",      minWidth = 140),
          major_code     = reactable::colDef(name = "Program",    minWidth = 120),
          count          = reactable::colDef(name = "Waitlisted", maxWidth = 100, align = "right")
        ))
      })

      output$wl_classifications <- reactable::renderReactable({
        data <- wl_apply_min(waitlist_data[["classifications"]], wl_min()) %>% arrange(desc(count))
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
                htmltools::span(class = "fw-semibold", v)
              )
            }),
          course_title          = reactable::colDef(name = "Title",          minWidth = 140),
          student_classification = reactable::colDef(name = "Classification", minWidth = 130),
          count                 = reactable::colDef(name = "Waitlisted",     maxWidth = 100, align = "right")
        ))
      })
    }

    # Initialize course choices server-side. When a course arrives via a deep link
    # (?tab=waitlists&course=…), preselect it as part of THIS init: a value injected
    # separately by cedar_restore_from_query() gets wiped when the server-side
    # selectize (re)initializes, which is what made the course flash in and then
    # vanish (and be ignored by the run). Baking it into the init makes it stick.
    observeEvent(parent_session$clientData$url_search, {
      updateSelectizeInput(session, "wl_course",
                           choices  = sort(unique(students$subject_course)),
                           selected = cedar_url_restore_value(parent_session, "Waitlists", "course"),
                           server   = TRUE)
    }, once = TRUE)

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

    # Copy a shareable URL for the current waitlist view. Standard copy/restore
    # round-trip — slug + button + restore types come from CEDAR_SHARE_SPECS.
    cedar_copy_url_observer(input, session, "wl_copy_url", spec_title = "Waitlists",
      values_fn = function() list(
        campus  = input$wl_campus,
        college = input$wl_college,
        dept    = input$wl_dept,
        level   = input$wl_level,
        term    = input$wl_term,
        pt      = input$wl_pt,
        course  = input$wl_course
      ))

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
