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

    div(style = "position: relative; min-height: 300px;",

      div(
        id = "seatfinder-loading-overlay",
        style = "display: none;",
        div(class = "dash-loader-backdrop"),
        div(class = "dash-loader-box",
          div(class = "dash-loader-icon",
            div(class = "dash-spinner"),
            tags$span("\U0001fa91", class = "dash-tree-icon")
          ),
          div(id = "seatfinder-loading-label", class = "dash-loader-msg", "Loading…"),
          div(id = "seatfinder-timing-msg",    class = "dash-timing-msg")
        )
      ),

      tags$script(HTML(paste0('
      (function() {
        var expectedSec = ', {
          avg <- get_average_report_time("open-seats")
          if (!is.null(avg)) round(avg) else 10L
        }, ';
        var hideTimer = null;

        // Use capture-phase click listener so it fires for both user clicks and
        // programmatic btn.click() triggered by URL autorun. shiny:inputchanged
        // fires asynchronously and misses the URL-load path.
        document.addEventListener("click", function(e) {
          if (e.target && e.target.closest && e.target.closest("#seatfinder-sf_button")) {
            showOverlay();
          }
        }, true);

        Shiny.addCustomMessageHandler("seatfinder_load_complete", function(msg) {
          completeOverlay(msg.duration_sec, msg.avg_sec);
        });

        function showOverlay() {
          clearTimeout(hideTimer);
          var el    = document.getElementById("seatfinder-loading-overlay");
          var label = document.getElementById("seatfinder-loading-label");
          var timing = document.getElementById("seatfinder-timing-msg");
          if (!el) return;
          label.textContent  = "Loading… (est. " + Math.round(expectedSec) + "s)";
          timing.textContent = "";
          el.style.opacity    = "0";
          el.style.display    = "flex";
          el.style.transition = "opacity 0.2s ease";
          el.offsetWidth;
          el.style.opacity = "1";
        }

        function completeOverlay(durationSec, avgSec) {
          var el     = document.getElementById("seatfinder-loading-overlay");
          var timing = document.getElementById("seatfinder-timing-msg");
          if (!el || el.style.display === "none") return;
          var txt = "Loaded in " + durationSec + "s";
          if (avgSec !== null && avgSec !== undefined) txt += " · avg " + avgSec + "s";
          timing.textContent = txt;
          hideTimer = setTimeout(function() {
            el.style.transition = "opacity 0.4s ease";
            el.style.opacity    = "0";
            setTimeout(function() {
              el.style.display    = "none";
              el.style.transition = "";
              el.style.opacity    = "1";
            }, 400);
          }, 800);
        }
      })();
      '))),

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
          cell = function(v) htmltools::span(style = "font-weight:600", v)),
        course_title   = reactable::colDef(name = "Title",     minWidth = 190),
        college        = reactable::colDef(name = "College",   maxWidth = 80),
        part_term      = reactable::colDef(name = "Part",      maxWidth = 55),
        avail          = reactable::colDef(name = "Avail",     maxWidth = 80,
          align = "right", style = avail_style),
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
      make_sf_reactable(data[["type_summary"]])
    })

    output$courses_common <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      make_sf_reactable(data[["courses_common"]])
    })

    output$courses_prev <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      make_sf_reactable(data[["courses_prev"]])
    })

    output$courses_new <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      make_sf_reactable(data[["courses_new"]])
    })

    output$gen_ed_combined <- reactable::renderReactable({
      data <- sf_data()
      if (is.null(data)) return(NULL)
      df <- data[["gen_ed_combined"]]
      if (is.null(df) || nrow(df) == 0) return(NULL)
      df <- dplyr::select(df, dplyr::any_of(c(
        "likely", "college", "gen_ed_area", "part_term", "subject_course", "course_title",
        "avail", "enrolled", "dfw_pct", "avail_diff"
      )))
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
        columns = list(
          likely      = reactable::colDef(
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
          ),
          campus         = reactable::colDef(show = FALSE),
          term           = reactable::colDef(show = FALSE),
          subject_course = reactable::colDef(name = "Course",   minWidth = 105,
            cell = function(v) htmltools::span(style = "font-weight:600", v)),
          course_title   = reactable::colDef(name = "Title",    minWidth = 220),
          gen_ed_area    = reactable::colDef(name = "Gen Ed",   minWidth = 100),
          college        = reactable::colDef(name = "College",  maxWidth = 80),
          part_term      = reactable::colDef(name = "PoT",      maxWidth = 60),
          avail          = reactable::colDef(name = "Avail",    maxWidth = 80,  align = "right"),
          enrolled       = reactable::colDef(name = "Enrolled", maxWidth = 90,  align = "right"),
          dfw_pct        = reactable::colDef(name = "DFW %",    maxWidth = 85,  align = "right"),
          avail_diff     = reactable::colDef(name = "Avail Diff", maxWidth = 75, align = "right")
        )
      )
    })

    output$sf_output <- renderUI({
      if (!sf_has_run()) {
        return(empty_state("Set filters and click Find Open Seats to view available sections."))
      }
      tagList(
        info_panel("Column guide",
          tags$ul(
            tags$li(tags$strong("avail"), " — seats currently available (max enrollment minus registered). Courses tab: only rows with avail > 0 are shown."),
            tags$li(tags$strong("enrolled"), " — current enrollment count."),
            tags$li(tags$strong("avail_diff"), " — change in available seats versus the same course in the prior-year term. Negative = fewer open seats than last year."),
            tags$li(tags$strong("DFW %"), " — historical D/F/Withdrawal rate averaged across all prior terms for this course. Blank if no grade history exists."),
            tags$li(tags$strong("Common tab"), " — courses in both terms; ", tags$strong("enrl_diff_from_last_year"), " shows enrollment change year-over-year."),
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

    observeEvent(input$sf_copy_url, {
      params <- c("tab=open-seats", "autorun=true")
      add_param <- function(key, val) {
        if (!is.null(val) && length(val) > 0)
          params <<- c(params, paste0(key, "=", paste(val, collapse = ",")))
      }
      add_param("campus",  input$sf_campus)
      add_param("college", input$sf_college)
      add_param("dept",    input$sf_dept)
      add_param("term",    input$sf_term)
      add_param("pt",      input$sf_pt)
      add_param("im",      input$sf_im)
      add_param("level",   input$sf_level)
      session$sendCustomMessage("copy_cedar_url", list(
        queryStr = paste(params, collapse = "&"),
        buttonId = session$ns("sf_copy_url")
      ))
    }, ignoreInit = TRUE)

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
          duration_sec <- end_report_timer(timer)
          session$sendCustomMessage("seatfinder_load_complete", list(
            duration_sec = round(duration_sec, 1),
            avg_sec      = NULL
          ))
        } else {
          courses_list <- seatfinder(students, sections, faculty, opt)
          sf_data(courses_list)
          save_seatfinder_cache(opt, courses_list)
          duration_sec <- end_report_timer(timer)
          session$sendCustomMessage("seatfinder_load_complete", list(
            duration_sec = round(duration_sec, 1),
            avg_sec      = NULL
          ))
        }
      }, error = function(e) {
        handle_error(e, "open-seats", NULL)
        tryCatch(end_report_timer(timer), error = function(te) {
          message("[seatfinder] Error ending timer: ", te$message)
        })
      })

    }, ignoreInit = TRUE)
  })
}
