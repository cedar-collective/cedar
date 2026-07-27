# Shiny Module: Headcount Tab
#
# Unduplicated student headcount by program, with cascading college → dept →
# major → minor → concentration filters.
#
# Exported functions:
#   headcountUI(id)
#   headcountServer(id, programs, lookups)

headcountUI <- function(id) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Headcount",
      "Unduplicated students with an active declared program per term, drawn from Banner academic studies records.",
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
        column(2,
          selectizeInput(ns("major"), "Select Major", multiple = TRUE, choices = NULL)
        ),
        column(2,
          selectizeInput(ns("minor"), "Select Minor", multiple = TRUE, choices = NULL)
        ),
        column(2,
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
      )
    ),

    cedar_loading_overlay(id, "button", emoji = "\U0001f465",
      report_type = "headcount", fresh_default = 8,
      uiOutput(ns("output"))
    )
  )
}

headcountServer <- function(id, programs, lookups, error_handler = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    hc_has_run <- reactiveVal(FALSE)

    get_selected_dept_program_names <- function() {
      if (is.null(input$dept) || length(input$dept) == 0) {
        return(NULL)
      }

      require_headcount_lookup(
        lookups, "program_name_lookup", c("program_name", "dept_code")
      ) %>%
        filter(dept_code %in% input$dept) %>%
        pull(program_name)
    }

    output$output <- renderUI({
      if (!hc_has_run()) {
        return(empty_state("Select a department, major, or program and click Update Headcount."))
      }
      tagList(
        info_panel("How to read these charts",
          tags$ul(
            tags$li("Each point is a term. The chart counts ", tags$strong("unique students"),
                    " with an active declared program — not course enrollments."),
            tags$li("A student holding both a History major and an Anthropology minor appears under both departments when each is selected separately."),
            tags$li("Combining major + minor filters counts only students who hold ", tags$em("both"), " simultaneously.")
          ),
          tags$a("Full methodology →", href = "https://cedarplatform.org/users/headcount",
                 target = "_blank")
        ),
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

    # Updates major/minor/conc dropdowns after a college or dept selection changes.
    # filtered_data is cedar_programs pre-filtered by college/dept; minors and
    # concentrations are resolved against all programs for those students so that
    # cross-department combinations remain visible.
    update_downstream_filters <- function(filtered_data) {
      # When a dept is selected, use program_name_lookup to find programs that
      # belong to that dept rather than deriving them from student enrollment records.
      # cedar_programs$dept_code only reflects a student's major, so going through
      # student IDs would show minors/concentrations from unrelated departments.
      dept_program_names <- get_selected_dept_program_names()

      available_majors <- filtered_data %>%
        filter(!is.na(program_name), program_name != "",
               program_type %in% c("Major", "Second Major")) %>%
        distinct(program_name) %>%
        arrange(program_name) %>%
        pull(program_name)

      updateSelectizeInput(session, "major",
                           choices = available_majors,
                           selected = intersect(input$major %||% character(0), available_majors),
                           server = TRUE)

      if (!is.null(dept_program_names)) {
        available_minors <- programs %>%
          filter(!is.na(program_name), program_name != "",
                 program_type %in% c("First Minor", "Second Minor"),
                 program_name %in% dept_program_names) %>%
          distinct(program_name) %>%
          arrange(program_name) %>%
          pull(program_name)

        available_concentrations <- programs %>%
          filter(!is.na(program_name), program_name != "",
                 program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"),
                 program_name %in% dept_program_names) %>%
          distinct(program_name) %>%
          arrange(program_name) %>%
          pull(program_name)
      } else {
        student_ids <- filtered_data %>%
          filter(!is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)

        student_data <- programs %>% filter(student_id %in% student_ids)

        available_minors <- student_data %>%
          filter(!is.na(program_name), program_name != "",
                 program_type %in% c("First Minor", "Second Minor")) %>%
          distinct(program_name) %>%
          arrange(program_name) %>%
          pull(program_name)

        available_concentrations <- student_data %>%
          filter(!is.na(program_name), program_name != "",
                 program_type %in% c("First Concentration", "Second Concentration", "Third Concentration")) %>%
          distinct(program_name) %>%
          arrange(program_name) %>%
          pull(program_name)
      }

      updateSelectizeInput(session, "minor",
                           choices = available_minors,
                           selected = intersect(input$minor %||% character(0), available_minors),
                           server = TRUE)
      updateSelectizeInput(session, "concentration",
                           choices = available_concentrations,
                           selected = intersect(input$concentration %||% character(0), available_concentrations),
                           server = TRUE)
    }

    # College changes reset department and all downstream filters (hierarchical).
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
      update_downstream_filters(filtered_data)

    }, ignoreInit = FALSE, ignoreNULL = FALSE)

    # Department changes update the major list and reset minor/conc.
    observeEvent(input$dept, {
      if (cedar_logging_enabled) {
        write_log("INFO", "data_filter", "headcount_dept", session$token, list(
          dept = input$dept
        ))
      }

      filtered_data <- programs
      if (!is.null(input$college) && length(input$college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$college)
      }
      if (!is.null(input$dept) && length(input$dept) > 0) {
        filtered_data <- filtered_data %>% filter(dept_code %in% input$dept)
      }

      update_downstream_filters(filtered_data)

    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # Major selection limits minor choices to those held by students with that major.
    observeEvent(input$major, {
      filtered_data <- programs
      if (!is.null(input$college) && length(input$college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$college)
      }
      if (!is.null(input$dept) && length(input$dept) > 0) {
        filtered_data <- filtered_data %>% filter(dept_code %in% input$dept)
      }

      base_ids <- filtered_data %>% filter(!is.na(student_id)) %>% distinct(student_id) %>% pull(student_id)

      if (!is.null(input$major) && length(input$major) > 0) {
        scoped_ids <- programs %>%
          filter(student_id %in% base_ids,
                 program_type %in% c("Major", "Second Major"),
                 program_name %in% input$major,
                 !is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)
      } else {
        scoped_ids <- base_ids
      }

      dept_program_names <- get_selected_dept_program_names()

      student_data <- programs %>% filter(student_id %in% scoped_ids)

      minor_data <- student_data %>%
        filter(!is.na(program_name), program_name != "",
               program_type %in% c("First Minor", "Second Minor"))
      if (!is.null(dept_program_names)) {
        minor_data <- minor_data %>% filter(program_name %in% dept_program_names)
      }
      available_minors <- minor_data %>%
        distinct(program_name) %>%
        arrange(program_name) %>%
        pull(program_name)

      conc_data <- student_data %>%
        filter(!is.na(program_name), program_name != "",
               program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"))
      if (!is.null(dept_program_names)) {
        conc_data <- conc_data %>% filter(program_name %in% dept_program_names)
      }
      available_concentrations <- conc_data %>%
        distinct(program_name) %>%
        arrange(program_name) %>%
        pull(program_name)

      updateSelectizeInput(session, "minor",
                           choices = available_minors,
                           selected = intersect(input$minor %||% character(0), available_minors),
                           server = TRUE)
      updateSelectizeInput(session, "concentration",
                           choices = available_concentrations,
                           selected = intersect(input$concentration %||% character(0), available_concentrations),
                           server = TRUE)

    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # Minor selection limits concentration choices to those held by matching students.
    observeEvent(input$minor, {
      filtered_data <- programs
      if (!is.null(input$college) && length(input$college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$college)
      }
      if (!is.null(input$dept) && length(input$dept) > 0) {
        filtered_data <- filtered_data %>% filter(dept_code %in% input$dept)
      }

      base_ids <- filtered_data %>% filter(!is.na(student_id)) %>% distinct(student_id) %>% pull(student_id)

      if (!is.null(input$major) && length(input$major) > 0) {
        base_ids <- programs %>%
          filter(student_id %in% base_ids,
                 program_type %in% c("Major", "Second Major"),
                 program_name %in% input$major,
                 !is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)
      }

      if (!is.null(input$minor) && length(input$minor) > 0) {
        scoped_ids <- programs %>%
          filter(student_id %in% base_ids,
                 program_type %in% c("First Minor", "Second Minor"),
                 program_name %in% input$minor,
                 !is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)
      } else {
        scoped_ids <- base_ids
      }

      dept_program_names <- get_selected_dept_program_names()

      student_data <- programs %>% filter(student_id %in% scoped_ids)

      conc_data <- student_data %>%
        filter(!is.na(program_name), program_name != "",
               program_type %in% c("First Concentration", "Second Concentration", "Third Concentration"))
      if (!is.null(dept_program_names)) {
        conc_data <- conc_data %>% filter(program_name %in% dept_program_names)
      }
      available_concentrations <- conc_data %>%
        distinct(program_name) %>%
        arrange(program_name) %>%
        pull(program_name)

      updateSelectizeInput(session, "concentration",
                           choices = available_concentrations,
                           selected = intersect(input$concentration %||% character(0), available_concentrations),
                           server = TRUE)

    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # Initialize all filter choices with the full data
    updateSelectizeInput(session, "college",
                         choices = sort(unique(programs$student_college[!is.na(programs$student_college) & programs$student_college != ""])),
                         server = TRUE)
    updateSelectizeInput(session, "dept",
                         choices = .dept_choices,
                         server = TRUE)
    updateSelectizeInput(session, "campus",
                         choices = sort(unique(programs$student_campus[!is.na(programs$student_campus) & programs$student_campus != ""])),
                         server = TRUE)
    updateSelectizeInput(session, "major",
                         choices = sort(unique(programs$program_name[!is.na(programs$program_name) & programs$program_type %in% c("Major", "Second Major")])),
                         server = TRUE)
    updateSelectizeInput(session, "minor",
                         choices = sort(unique(programs$program_name[!is.na(programs$program_name) & programs$program_type %in% c("First Minor", "Second Minor")])),
                         server = TRUE)
    updateSelectizeInput(session, "concentration",
                         choices = sort(unique(programs$program_name[!is.na(programs$program_name) & programs$program_type %in% c("First Concentration", "Second Concentration", "Third Concentration")])),
                         server = TRUE)

    hc_data_rv <- reactiveVal(NULL)

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
        end_report_timer(timer)
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
        dept          = input$dept,
        campus        = input$campus,
        major         = input$major,
        minor         = input$minor,
        concentration = input$concentration
      )

      result <- tryCatch({
        hc_result <- get_headcount(programs, opt, lookups = lookups)
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
        tryCatch(end_report_timer(timer), error = function(te) {
          message("[headcount] Error ending timer: ", te$message)
        })
        signal_load_complete(session, id, error = TRUE)
        return(NULL)
      })

      if (!is.null(result)) {
        duration_sec <- end_report_timer(timer)
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
