# Shiny Module: Headcount Tab
#
# Unduplicated student headcount by program, with cascading college → dept →
# major → minor → concentration filters.
#
# Exported functions:
#   headcountUI(id)
#   headcountServer(id, programs, dims, in_progress_terms)

headcountUI <- function(id) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Headcount",
      cedar_definition_summary("program-headcount"),
      fluidRow(
        column(4,
          selectizeInput(ns("campus"), "Select Campus", multiple = TRUE, choices = NULL)
        ),
        column(4,
          selectizeInput(ns("college"), "Select College", multiple = TRUE, choices = NULL)
        ),
        column(4,
          selectizeInput(ns("dept"), "Select Department", multiple = TRUE, choices = NULL)
        )
      ),
      fluidRow(
        column(3,
          selectizeInput(ns("major"), "Select Major", multiple = TRUE, choices = NULL)
        ),
        column(3,
          selectizeInput(ns("minor"), "Select Minor", multiple = TRUE, choices = NULL)
        ),
        column(3,
          selectizeInput(ns("concentration"), "Select Concentration", multiple = TRUE, choices = NULL)
        ),
        column(3,
          filter_actions(
            # No copy-shareable-link button here: Headcount's filters cascade
            # (college→dept→major→…) and its deep-link RESTORE is broken, so we do
            # not hand out share URLs that won't reload correctly. See AGENTS.md
            # "URL deep links & shareable state".
            actionButton(ns("button"), label = "Update Headcount",
                         icon = icon("users"), class = "btn-primary")
          )
        )
      ),

      filter_scope_stripe(uiOutput(ns("scope_summary")))
    ),

    cedar_loading_overlay(id, "button", emoji = "\U0001f465",
      report_type = "headcount", fresh_default = 8,
      uiOutput(ns("output"))
    )
  )
}

headcountServer <- function(id, programs, dims, in_progress_terms, error_handler = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    hc_has_run <- reactiveVal(FALSE)

    output$output <- renderUI({
      if (!hc_has_run()) {
        return(empty_state("Select a department, major, or program, then click Update Headcount."))
      }
      tagList(
        cedar_definition_panel("program-headcount", "How to read these charts"),
        uiOutput(ns("download_ui")),
        card(
          card_header("Undergraduate Headcount"),
          style = "height:100vh; min-height:100vh; overflow-y:auto;",
          plotlyOutput(ns("undergrad_plot"))
        ),
        card(
          card_header("Graduate Headcount"),
          style = "height:100vh; min-height:100vh; overflow-y:auto;",
          plotlyOutput(ns("grad_plot"))
        )
      )
    })

    # The Major / Minor / Concentration choices for the scope picked so far,
    # one branch call (headcount_filter_choices()): majors and minors by program
    # code, renames joined, a department's own programs only.
    program_labels <- reactiveVal(character(0))
    update_program_choices <- function(which = c("major", "minor", "concentration")) {
      scope <- list(college = input$college, dept_code = input$dept,
                    major_codes = input$major, minor_codes = input$minor)
      # The choices for a scope are the same for every session, and every
      # session asks for the unscoped ones as it starts, on whatever page it
      # opened: counted once and shared (cedar_shared_result(), ISSUES I80).
      choices <- cedar_shared_result(c(list("headcount_filter_choices"), scope),
                                     function() headcount_filter_choices(programs, dims, scope))
      # Code to label, so the scope bar names a picked program as the picker did.
      known <- c(choices$major, choices$minor)
      program_labels(c(stats::setNames(names(known), known),
                       program_labels()[setdiff(names(program_labels()), known)]))
      for (key in which) {
        updateSelectizeInput(session, key, choices = choices[[key]],
                             selected = intersect(input[[key]] %||% character(0),
                                                  unname(choices[[key]])),
                             server = TRUE)
      }
    }

    # College changes narrow the departments and every program list.
    observeEvent(input$college, {
      if (cedar_logging_enabled) {
        write_log("INFO", "data_filter", "headcount_college", session$token, list(
          college = input$college
        ))
      }

      filtered_data <- programs
      if (!is.null(input$college) && length(input$college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$college)
      }

      available_codes <- filtered_data %>%
        filter(!is.na(dept_code), dept_code != "") %>%
        distinct(dept_code) %>%
        pull(dept_code)
      filtered_choices <- .dept_choices[.dept_choices %in% available_codes]

      updateSelectizeInput(session, "dept",
                           choices = filtered_choices,
                           selected = intersect(input$dept %||% character(0), unname(filtered_choices)),
                           server = TRUE)
      update_program_choices()
    }, ignoreInit = FALSE, ignoreNULL = FALSE)

    observeEvent(input$dept, {
      if (cedar_logging_enabled) {
        write_log("INFO", "data_filter", "headcount_dept", session$token, list(
          dept = input$dept
        ))
      }
      update_program_choices()
    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # A picked major narrows the minors to those its students hold; a picked
    # minor narrows the concentrations.
    observeEvent(input$major, update_program_choices(c("minor", "concentration")),
                 ignoreInit = TRUE, ignoreNULL = FALSE)
    observeEvent(input$minor, update_program_choices("concentration"),
                 ignoreInit = TRUE, ignoreNULL = FALSE)

    updateSelectizeInput(session, "college",
                         choices = sort(unique(programs$student_college[!is.na(programs$student_college) & programs$student_college != ""])),
                         server = TRUE)
    updateSelectizeInput(session, "dept",
                         choices = .dept_choices,
                         server = TRUE)
    # Home campus as the declarations name it (Banner's names, not codes); it
    # opens on the main campus, through the campus file's names for it.
    .campus_choices <- sort(unique(programs$student_campus[!is.na(programs$student_campus) & programs$student_campus != ""]))
    updateSelectizeInput(session, "campus",
                         choices = .campus_choices,
                         selected = .campus_choices[cedar_campus_code_from_source(.campus_choices) %in% CEDAR_CAMPUS_MAIN],
                         server = TRUE)

    hc_data_rv <- reactiveVal(NULL)

    # Scope stripe — matches Regstats/Waitlists/Cancellations/Open Seats so the
    # counting scope for the headcount tables is visible on screen.
    output$scope_summary <- renderUI({
      result <- hc_data_rv()
      if (is.null(result) || is.null(result$data) || !is.data.frame(result$data)) {
        return(div(class = "scope-bar scope-bar-placeholder",
                   "Set filters and click Update Headcount to see the current scope."))
      }

      # What the run counted, in words -- read off the result, not the inputs.
      described <- describe_headcount_scope(result$scope, in_progress_terms)
      labels <- isolate(program_labels())
      picked <- c(input$major, input$minor)
      selected <- c(input$college, input$dept,
                    ifelse(picked %in% names(labels), labels[picked], picked),
                    input$concentration)

      # The codes behind each department the run counted, by name, from the
      # mapping files: the same block Dept Trends and the Dept Dashboard show.
      codes <- if (length(result$scope$dept_codes)) {
        unit_codes_scope(unit_mapping_rows(result$scope$dept_codes, cedar_institution_files))
      }
      tagList(
        headcount_scope_bar(described,
                            scope_chip("Selected", if (length(selected)) selected else "everything")),
        codes)
    })

    output$download_ui <- renderUI({
      result <- hc_data_rv()
      if (is.null(result) || is.null(result$data) || !is.data.frame(result$data) ||
          nrow(result$data) == 0) {
        return(NULL)
      }

      div(class = "download-row",
        downloadButton(
          ns("download_headcount"),
          "Download headcount CSV",
          class = "btn btn-outline-secondary btn-sm"
        )
      )
    })

    output$download_headcount <- downloadHandler(
      filename = function() {
        scope <- c(input$dept, input$major, input$minor, input$concentration,
                   input$college, input$campus)
        scope <- scope[!is.na(scope) & nzchar(scope)]
        scope <- if (length(scope) > 0) paste(scope, collapse = "-") else "all"
        scope <- gsub("[^A-Za-z0-9_-]+", "-", scope)
        paste0("cedar-headcount-", tolower(scope), ".csv")
      },
      content = function(file) {
        utils::write.csv(format_headcount_export(hc_data_rv()), file, row.names = FALSE)
      }
    )

    # Copy-shareable-link observer intentionally removed: Headcount's cascading
    # server-side selectizes don't restore reliably from a URL yet. See AGENTS.md
    # "URL deep links & shareable state" for the general mechanism and why
    # Headcount deviates.

    observeEvent(input$button, {
      hc_has_run(TRUE)
      log_report_generation(session, "headcount", list(
        college       = input$college,
        dept          = input$dept,
        campus        = input$campus,
        major         = input$major,
        minor         = input$minor,
        concentration = input$concentration
      ))

      timer <- start_report_timer("headcount", list(
        college = input$college,
        dept    = input$dept
      ))

      if (is.null(programs)) {
        end_report_timer(timer, success = FALSE)
        signal_load_complete(session, id, error = TRUE)
        showNotification("cedar_programs data is NULL!", type = "error", duration = 5)
        return(NULL)
      }

      cedar_debug("[headcount] Counting heads with major:", toString(input$major),
                  " minor:", toString(input$minor),
                  " concentration:", toString(input$concentration))

      opt <- list(
        shiny         = TRUE,
        college       = input$college,
        dept_code     = input$dept,
        campus        = input$campus,
        major_codes   = input$major,
        minor_codes   = input$minor,
        concentration = input$concentration
      )

      result <- tryCatch({
        hc_result <- get_headcount(programs, opt, dims = dims)
        # Build plots here too, so the timer/overlay covers the actual slow part
        # (per-program subplot generation), not just the data filter/summarize step.
        hc_result$plots <- make_headcount_plots_by_level(hc_result)
        hc_result
      }, error = function(e) {
        if (is.function(error_handler)) {
          error_handler(e, "[headcount] headcount_calculation")
        } else {
          message("[headcount] Error: ", conditionMessage(e))
          showNotification(paste("Error:", conditionMessage(e)), type = "error", duration = 8)
        }
        tryCatch(end_report_timer(timer, success = FALSE, error = e), error = function(te) {
          message("[headcount] Error ending timer: ", te$message)
        })
        signal_load_complete(session, id, error = TRUE)
        return(NULL)
      })

      if (!is.null(result)) {
        duration_sec <- end_report_timer(timer, result = result)
        signal_load_complete(session, id, duration_sec = duration_sec)
      }

      if (!is.null(result) && nrow(result$data) == 0) {
        showNotification("No data found for the selected filters.", type = "warning", duration = 5)
      }
      hc_data_rv(result)
    }, ignoreNULL = TRUE, ignoreInit = TRUE)

    output$undergrad_plot <- renderPlotly({
      data <- hc_data_rv()
      req(data)
      data$plots$undergrad
    })
    output$grad_plot <- renderPlotly({
      data <- hc_data_rv()
      req(data)
      data$plots$graduate
    })
  })
}
