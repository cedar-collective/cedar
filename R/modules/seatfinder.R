# Shiny Module: Open Seats (Seatfinder) Tab
#
# Shows courses with available capacity for selected filters, with DFW history.
#
# Exported functions:
#   seatfinderUI(id, sections, default_term, dept_choices)
#   seatfinderServer(id, students, sections, faculty)

seatfinderUI <- function(id, sections, default_term, dept_choices) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Open Seats",
      "Courses with available capacity matching your filters, with DFW history and year-over-year schedule comparisons.",
      fluidRow(class = "explore-filter-row",
        column(2,
          selectizeInput(ns("sf_campus"), "Campus", multiple = TRUE,
                         choices = sort(unique(sections$campus)),
                         selected = c("ABQ", "EA"))
        ),
        column(1,
          selectizeInput(ns("sf_college"), "College", multiple = TRUE,
                         choices = sort(unique(sections$college)))
        ),
        column(2,
          selectizeInput(ns("sf_term"), "Term", multiple = TRUE,
                         choices = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
                         selected = default_term)
        ),
        column(1,
          selectInput(ns("sf_pt"), "PoT", multiple = TRUE,
                      choices = sort(unique(sections$part_term)))
        ),
        column(2,
          selectizeInput(ns("sf_dept"), "Department", multiple = TRUE,
                         choices = dept_choices)
        ),
        column(1,
          selectInput(ns("sf_im"), "Method", multiple = TRUE,
                      choices = sort(unique(sections$delivery_method)))
        ),
        column(1,
          selectInput(ns("sf_level"), "Level", multiple = TRUE,
                      choices = sort(unique(sections$level)),
                      selected = "lower")
        ),
        column(2,
          filter_actions(
            actionButton(ns("sf_button"), label = "Find Seats",
                         icon = icon("door-open"), class = "btn-primary"),
            actionButton(ns("sf_copy_url"), label = NULL, icon = icon("link"),
                         title = "Copy shareable link for current view",
                         class = "btn-outline-secondary btn-sm")
          )
        )
      )
    ),

    cedar_loading_overlay(id, "sf_button", emoji = "\U0001fa91",
      report_type = "open-seats", fresh_default = 30, cached_default = 2,
      uiOutput(ns("sf_output"))
    )
  )
}

seatfinderServer <- function(id, students, sections, faculty) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    avail_style <- function(v) {
      if (is.na(v)) return(list())
      if (v <  5)  list(background = "#F2E3DE", fontWeight = "600")
      else if (v < 15) list(background = "#F4E9D2", fontWeight = "600")
      else             list(background = "#E4EEE7", fontWeight = "600")
    }
    diff_style <- function(v) {
      if (is.na(v)) return(list())
      if (v < -5)  list(background = "#F2E3DE")
      else if (v <= 5) list(background = "#F4E9D2")
      else             list(background = "#E4EEE7")
    }
    dfw_style <- function(v) {
      if (is.na(v) || v == "") return(list())
      n <- suppressWarnings(as.numeric(gsub("%", "", v)))
      if (is.na(n)) return(list())
      if (n > 30) list(background = "#F2E3DE", fontWeight = "600")
      else if (n >= 15) list(background = "#F4E9D2")
      else              list(background = "#E4EEE7")
    }
    enrl_style <- function(v) {
      if (is.na(v)) return(list())
      if (v < 8)  list(background = "#F2E3DE")
      else if (v < 12) list(background = "#F4E9D2")
      else             list(background = "#E6EDF6")
    }
    diff_enrl_style <- function(v) {
      if (is.na(v)) return(list())
      if (v < -5)  list(background = "#F2E3DE")
      else if (v <= 5) list(background = "#F4E9D2")
      else             list(background = "#E4EEE7")
    }

    sf_col_defs <- function(df) {
      cols <- names(df)
      defs <- list(
        campus         = reactable::colDef(show = FALSE),
        term           = reactable::colDef(show = FALSE),
        term_type      = reactable::colDef(show = FALSE),
        level          = reactable::colDef(show = FALSE),
        waiting        = reactable::colDef(show = FALSE),
        gen_ed_area    = reactable::colDef(name = "Gen Ed",    maxWidth = 90),
        subject_course = reactable::colDef(name = "Course",    minWidth = 105,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        course_title   = reactable::colDef(name = "Title",     minWidth = 190),
        college        = reactable::colDef(name = "College",   maxWidth = 80),
        part_term      = cedar_pot_coldef(),
        avail          = reactable::colDef(name = "Avail",     maxWidth = 80,
          align = "right", style = avail_style),
        sections       = reactable::colDef(name = "Sections",  maxWidth = 80, align = "right"),
        avg_size       = reactable::colDef(name = "Avg Size",  maxWidth = 85, align = "right"),
        enrolled       = reactable::colDef(name = "Enrolled",  maxWidth = 90,
          align = "right", style = enrl_style),
        avail_diff     = reactable::colDef(name = "Avail Diff", maxWidth = 100,
          align = "right", style = diff_style),
        `DFW %`        = reactable::colDef(name = "DFW %",     maxWidth = 85,
          align = "right", style = dfw_style),
        dfw_pct        = reactable::colDef(name = "DFW %",     maxWidth = 85,
          align = "right", style = dfw_style),
        enrl_diff_from_last_year = reactable::colDef(name = "Enrl Diff YoY", maxWidth = 110,
          align = "right", style = diff_enrl_style)
      )
      defs[intersect(names(defs), cols)]
    }

    # Standard display column order shared by every Open Seats subtab. Comparative
    # tabs append their own extra (e.g. Common's enrl_diff_from_last_year); Gen Ed
    # keeps its Likely flag and Gen Ed area. total_enrl and avail_diff are
    # intentionally omitted — total_enrl multiply-counts crosslisted sections, and
    # avail_diff belongs only where a year-over-year comparison is defined.
    sf_standard_cols <- c("college", "subject_course", "course_title", "part_term",
                          "avail", "sections", "avg_size", "enrolled", "dfw_pct")
    sf_display <- function(df, extra = character(0)) {
      if (is.null(df) || nrow(df) == 0) return(df)
      # ungroup first: dplyr::select silently re-adds grouping columns (some cone
      # outputs are still grouped), which would prepend campus/term to the table.
      df %>% dplyr::ungroup() %>% dplyr::select(dplyr::any_of(c(sf_standard_cols, extra)))
    }

    make_sf_reactable <- function(df) {
      if (is.null(df) || nrow(df) == 0) return(NULL)
      reactable::reactable(
        df,
        theme               = cedar_tbl_theme,
        striped             = TRUE,
        highlight           = TRUE,
        compact             = TRUE,
        defaultPageSize     = 50,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(25, 50, 100),
        columns             = sf_col_defs(df)
      )
    }

    sf_has_run   <- reactiveVal(FALSE)
    sf_data      <- reactiveVal(NULL)

    output$type_summary <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      make_sf_reactable(sf_display(data[["type_summary"]]))
    })

    output$courses_common <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      # Common is the one deliberately comparative tab: append the year-over-year
      # enrollment change.
      make_sf_reactable(sf_display(data[["courses_common"]],
                                   extra = "enrl_diff_from_last_year"))
    })

    output$courses_prev <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      make_sf_reactable(sf_display(data[["courses_prev"]]))
    })

    output$courses_new <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      make_sf_reactable(sf_display(data[["courses_new"]]))
    })

    output$gen_ed_combined <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      df <- data[["gen_ed_combined"]]
      if (is.null(df) || nrow(df) == 0) return(NULL)
      # Same standard order as the other subtabs, with the Likely flag up front
      # and the Gen Ed area kept after the title.
      df <- sf_display(df, extra = c("likely", "gen_ed_area")) %>%
        dplyr::select(dplyr::any_of(c(
          "likely", "college", "subject_course", "course_title", "gen_ed_area",
          "part_term", "avail", "sections", "avg_size", "enrolled", "dfw_pct"
        )))
      likely_def <- list(likely = reactable::colDef(
        name = "",
        width = 65,
        cell = function(value) {
          if (isTRUE(value))
            htmltools::div(
              style = paste0(
                "display:inline-block;padding:1px 7px;border-radius:9px;",
                "font-size:0.73rem;font-weight:600;",
                "background:#F4E9D2;color:#7A5010"
              ),
              "Likely"
            )
          else ""
        }
      ))
      reactable::reactable(
        df,
        theme           = cedar_tbl_theme,
        striped         = FALSE,
        highlight       = TRUE,
        compact         = TRUE,
        defaultPageSize = 50,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(25, 50, 100),
        rowStyle = function(index) {
          if (isTRUE(df$likely[index]))
            list(background = "#FFF8EE", borderLeft = "3px solid #C7A96B")
          else
            list()
        },
        columns = c(likely_def, sf_col_defs(df))
      )
    })

    output$sf_output <- renderUI({
      if (!sf_has_run()) {
        return(empty_state("Set filters and click Find Open Seats to view available sections."))
      }
      tagList(
        info_panel("Column guide",
          tags$ul(
            tags$li(tags$strong("Avail"), " — seats currently available (max enrollment minus registered). Courses tab: only rows with avail > 0 are shown."),
            tags$li(tags$strong("Sections / Avg Size"), " — number of sections of the course and the average enrollment per section."),
            tags$li(tags$strong("Enrolled"), " — current enrollment count across sections."),
            tags$li(tags$strong("DFW %"), " — historical D/F/Withdrawal rate averaged across all prior terms for this course. Blank if no grade history exists."),
            tags$li(tags$strong("Common tab"), " — courses in both terms; ", tags$strong("Enrl Diff YoY"), " shows enrollment change year-over-year."),
            tags$li(tags$strong("Prev tab"), " — courses offered last year but not this term."),
            tags$li(tags$strong("New tab"), " — courses this term not offered last year."),
            tags$li(tags$strong("Gen Ed"), " — gen ed courses with open seats. Rows flagged ", tags$strong("Likely"), " (amber) have 0 available and 0 enrolled — capped sections that may open later.")
          ),
          tags$a("Full methodology →", href = "https://cedarplatform.org/users/open-seats",
                 target = "_blank")
        ),
        tabsetPanel(
          tabPanel("Courses",       reactable::reactableOutput(ns("type_summary"))),
          tabPanel("Common",        reactable::reactableOutput(ns("courses_common"))),
          tabPanel("Prev",          reactable::reactableOutput(ns("courses_prev"))),
          tabPanel("New",           reactable::reactableOutput(ns("courses_new"))),
          tabPanel("Gen Ed",        reactable::reactableOutput(ns("gen_ed_combined")))
        )
      )
    })

    cedar_copy_url_observer(input, session, "sf_copy_url", spec_title = "Open Seats",
      values_fn = function() list(
        campus  = input$sf_campus,
        college = input$sf_college,
        dept    = input$sf_dept,
        term    = input$sf_term,
        pt      = input$sf_pt,
        im      = input$sf_im,
        level   = input$sf_level
      ))

    observeEvent(input$sf_button, {
      if (is.null(input$sf_term) || length(input$sf_term) == 0) {
        showNotification("Please select at least one term before finding open seats.",
                         type = "warning", duration = 5)
        return()
      }

      sf_has_run(TRUE)

      log_report_generation(session, "open-seats", list(
        campus  = input$sf_campus,
        college = input$sf_college,
        dept    = input$sf_dept,
        term    = input$sf_term,
        pt      = input$sf_pt,
        im      = input$sf_im,
        level   = input$sf_level
      ))



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
          level          = input$sf_level
        )

        message("[seatfinder] Cache check — campus:", paste(opt$course_campus, collapse=","),
                " college:", paste(opt$course_college, collapse=","),
                " dept:", paste(opt$dept, collapse=","),
                " term:", paste(opt$term, collapse=","),
                " level:", paste(opt$level, collapse=","))

        cached <- load_seatfinder_cache(opt)
        if (!is.null(cached)) {
          sf_data(cached)
          duration_sec <- end_report_timer(timer, cached = TRUE)
          signal_load_complete(session, id, duration_sec = duration_sec, cached = TRUE)
        } else {
          courses_list <- seatfinder(students, sections, faculty, opt)
          sf_data(courses_list)
          save_seatfinder_cache(opt, courses_list)
          duration_sec <- end_report_timer(timer, cached = FALSE)
          signal_load_complete(session, id, duration_sec = duration_sec, cached = FALSE)
        }
      }, error = function(e) {
        handle_error(e, "open-seats", NULL)
        tryCatch(end_report_timer(timer), error = function(te) {
          message("[seatfinder] Error ending timer: ", te$message)
        })
        signal_load_complete(session, id, error = TRUE)
      })

    }, ignoreInit = TRUE)
  })
}
