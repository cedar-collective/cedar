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
    h1("Student Headcount", style = "margin-bottom: 8px;"),
    p("Unduplicated count of students with an active declared program per term, drawn from
      Banner academic studies records. Each student is counted once per term regardless of
      how many courses they take or which department those courses are in.",
      style = "color: #666; font-size: 0.9em; margin-bottom: 6px;"),

    tags$details(
      style = "font-size: 0.85em; color: #555; margin-bottom: 20px;",
      tags$summary(
        style = "cursor: pointer; color: #337ab7; margin-bottom: 8px;",
        "How filters and counting work"
      ),
      tags$div(
        style = "padding: 10px 0 4px 12px; border-left: 3px solid #ddd;",

        tags$p(tags$strong("Source data"),
          "— Headcount is based on Banner academic studies records, not course enrollment.
          A student with a declared major appears in every term they are actively enrolled
          at UNM, even if they take no courses in their home department that term."),

        tags$p(tags$strong("What “in a department” means"),
          "— Each program (major, minor, concentration) is linked to a department through
          an institutional code lookup. Selecting a department includes any student who has
          at least one program—major, minor, or concentration—that maps to that
          department’s code. A student whose major is in History but who also holds an
          Anthropology minor will appear under both departments."),

        tags$p(tags$strong("Names vs. codes"),
          "— Majors, minors, and concentrations are matched by their Banner program name
          (e.g., “History”, “Anthropology”). Departments are matched by
          code (e.g., HIST, ANTH) derived from each program’s major code via an
          institutional mapping table. The department dropdown shows human-readable names
          but filters by code under the hood, so selecting “History” finds all
          programs whose code maps to HIST."),

        tags$p(tags$strong("Cascading dropdowns"),
          "— Selecting a department narrows the major list to programs offered in that
          department. Selecting a major then narrows the minor list to minors actually
          held by students with that major. Selecting a minor further narrows the
          concentration list. Each dropdown only shows options that exist in the data
          given the upstream selections."),

        tags$p(tags$strong("Combining filters"),
          "— Selecting both a major and a minor counts only students who have both.
          The plot reflects the primary filter (major if selected, otherwise minor,
          otherwise concentration), so the headcount shows how that narrowed group
          has changed over time.")
      )
    ),

    fluidRow(
      column(4,
        selectizeInput(ns("hc_campus"), "Select Campus", multiple = TRUE, choices = NULL)
      ),
      column(4,
        selectizeInput(ns("hc_college"), "Select College", multiple = TRUE, choices = NULL)
      ),
      column(4,
        selectizeInput(ns("hc_dept"), "Select Department", multiple = TRUE, choices = NULL)
      )
    ),
    fluidRow(
      column(2,
        selectizeInput(ns("hc_major"), "Select Major", multiple = TRUE, choices = NULL)
      ),
      column(2,
        selectizeInput(ns("hc_minor"), "Select Minor", multiple = TRUE, choices = NULL)
      ),
      column(2,
        selectizeInput(ns("hc_conc"), "Select Concentration", multiple = TRUE, choices = NULL)
      ),
      column(3,
        actionButton(ns("hc_button"), label = "Update Table", icon = icon("sync-alt"))
      )
    ),

    card(
      card_header("Undergraduate Headcount"),
      style = "height:100vh; min-height:100vh; overflow-y:auto;",
      plotlyOutput(ns("hc_undergrad_plot"))
    ),
    card(
      card_header("Graduate Headcount"),
      style = "height:100vh; min-height:100vh; overflow-y:auto;",
      plotlyOutput(ns("hc_grad_plot"))
    )
  )
}

headcountServer <- function(id, programs, lookups) {
  moduleServer(id, function(input, output, session) {

    # Updates major/minor/conc dropdowns after a college or dept selection changes.
    # filtered_data is cedar_programs pre-filtered by college/dept; minors and
    # concentrations are resolved against all programs for those students so that
    # cross-department combinations remain visible.
    update_downstream_filters <- function(filtered_data) {
      # When a dept is selected, use program_name_lookup to find programs that
      # belong to that dept rather than deriving them from student enrollment records.
      # cedar_programs$dept_code only reflects a student's major, so going through
      # student IDs would show minors/concentrations from unrelated departments.
      dept_program_names <- if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
        lookups$program_name_lookup %>%
          filter(dept_code %in% input$hc_dept) %>%
          pull(program_name)
      } else {
        NULL
      }

      available_majors <- filtered_data %>%
        filter(!is.na(program_name), program_name != "",
               program_type %in% c("Major", "Second Major")) %>%
        distinct(program_name) %>%
        arrange(program_name) %>%
        pull(program_name)

      updateSelectizeInput(session, "hc_major",
                           choices = available_majors, selected = NULL, server = TRUE)

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

      updateSelectizeInput(session, "hc_minor",
                           choices = available_minors, selected = NULL, server = TRUE)
      updateSelectizeInput(session, "hc_conc",
                           choices = available_concentrations, selected = NULL, server = TRUE)
    }

    # College changes reset department and all downstream filters (hierarchical).
    observeEvent(input$hc_college, {
      if (cedar_logging_enabled) {
        write_log("INFO", "data_filter", "headcount_college", session$token, list(
          college = input$hc_college
        ))
      }

      filtered_data <- programs
      if (!is.null(input$hc_college) && length(input$hc_college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$hc_college)
      }

      available_codes <- filtered_data %>%
        filter(!is.na(dept_code), dept_code != "") %>%
        distinct(dept_code) %>%
        pull(dept_code)
      filtered_choices <- .dept_choices[.dept_choices %in% available_codes]

      updateSelectizeInput(session, "hc_dept",
                           choices = filtered_choices, selected = NULL, server = TRUE)
      update_downstream_filters(filtered_data)

    }, ignoreInit = FALSE, ignoreNULL = FALSE)

    # Department changes update the major list and reset minor/conc.
    observeEvent(input$hc_dept, {
      if (cedar_logging_enabled) {
        write_log("INFO", "data_filter", "headcount_dept", session$token, list(
          dept = input$hc_dept
        ))
      }

      filtered_data <- programs
      if (!is.null(input$hc_college) && length(input$hc_college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$hc_college)
      }
      if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
        filtered_data <- filtered_data %>% filter(dept_code %in% input$hc_dept)
      }

      update_downstream_filters(filtered_data)

    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # Major selection limits minor choices to those held by students with that major.
    observeEvent(input$hc_major, {
      filtered_data <- programs
      if (!is.null(input$hc_college) && length(input$hc_college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$hc_college)
      }
      if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
        filtered_data <- filtered_data %>% filter(dept_code %in% input$hc_dept)
      }

      base_ids <- filtered_data %>% filter(!is.na(student_id)) %>% distinct(student_id) %>% pull(student_id)

      if (!is.null(input$hc_major) && length(input$hc_major) > 0) {
        scoped_ids <- programs %>%
          filter(student_id %in% base_ids,
                 program_type %in% c("Major", "Second Major"),
                 program_name %in% input$hc_major,
                 !is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)
      } else {
        scoped_ids <- base_ids
      }

      dept_program_names <- if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
        lookups$program_name_lookup %>%
          filter(dept_code %in% input$hc_dept) %>%
          pull(program_name)
      } else {
        NULL
      }

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

      updateSelectizeInput(session, "hc_minor",
                           choices = available_minors, selected = NULL, server = TRUE)
      updateSelectizeInput(session, "hc_conc",
                           choices = available_concentrations, selected = NULL, server = TRUE)

    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # Minor selection limits concentration choices to those held by matching students.
    observeEvent(input$hc_minor, {
      filtered_data <- programs
      if (!is.null(input$hc_college) && length(input$hc_college) > 0) {
        filtered_data <- filtered_data %>% filter(student_college %in% input$hc_college)
      }
      if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
        filtered_data <- filtered_data %>% filter(dept_code %in% input$hc_dept)
      }

      base_ids <- filtered_data %>% filter(!is.na(student_id)) %>% distinct(student_id) %>% pull(student_id)

      if (!is.null(input$hc_major) && length(input$hc_major) > 0) {
        base_ids <- programs %>%
          filter(student_id %in% base_ids,
                 program_type %in% c("Major", "Second Major"),
                 program_name %in% input$hc_major,
                 !is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)
      }

      if (!is.null(input$hc_minor) && length(input$hc_minor) > 0) {
        scoped_ids <- programs %>%
          filter(student_id %in% base_ids,
                 program_type %in% c("First Minor", "Second Minor"),
                 program_name %in% input$hc_minor,
                 !is.na(student_id)) %>%
          distinct(student_id) %>%
          pull(student_id)
      } else {
        scoped_ids <- base_ids
      }

      dept_program_names <- if (!is.null(input$hc_dept) && length(input$hc_dept) > 0) {
        lookups$program_name_lookup %>%
          filter(dept_code %in% input$hc_dept) %>%
          pull(program_name)
      } else {
        NULL
      }

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

      updateSelectizeInput(session, "hc_conc",
                           choices = available_concentrations, selected = NULL, server = TRUE)

    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # Initialize all filter choices with the full data
    updateSelectizeInput(session, "hc_college",
                         choices = sort(unique(programs$student_college[!is.na(programs$student_college) & programs$student_college != ""])),
                         server = TRUE)
    updateSelectizeInput(session, "hc_dept",
                         choices = .dept_choices,
                         server = TRUE)
    updateSelectizeInput(session, "hc_campus",
                         choices = sort(unique(programs$student_campus[!is.na(programs$student_campus) & programs$student_campus != ""])),
                         server = TRUE)
    updateSelectizeInput(session, "hc_major",
                         choices = sort(unique(programs$program_name[!is.na(programs$program_name) & programs$program_type %in% c("Major", "Second Major")])),
                         server = TRUE)
    updateSelectizeInput(session, "hc_minor",
                         choices = sort(unique(programs$program_name[!is.na(programs$program_name) & programs$program_type %in% c("First Minor", "Second Minor")])),
                         server = TRUE)
    updateSelectizeInput(session, "hc_conc",
                         choices = sort(unique(programs$program_name[!is.na(programs$program_name) & programs$program_type %in% c("First Concentration", "Second Concentration", "Third Concentration")])),
                         server = TRUE)

    hc_data <- eventReactive(input$hc_button, {
      log_report_generation(session, "headcount", list(
        college       = input$hc_college,
        dept          = input$hc_dept,
        campus        = input$hc_campus,
        major         = input$hc_major,
        minor         = input$hc_minor,
        concentration = input$hc_conc
      ))

      showNotification("Updating headcount...", type = "warning", duration = NULL, id = "hc_loading")

      if (is.null(programs)) {
        showNotification("cedar_programs data is NULL!", type = "error", duration = 5)
        return(NULL)
      }

      cedar_debug("[headcount] Counting heads with major:", toString(input$hc_major),
                  " minor:", toString(input$hc_minor),
                  " concentration:", toString(input$hc_conc))

      opt <- list(
        shiny         = TRUE,
        college       = input$hc_college,
        dept          = input$hc_dept,
        campus        = input$hc_campus,
        major         = input$hc_major,
        minor         = input$hc_minor,
        concentration = input$hc_conc
      )

      result <- tryCatch({
        get_headcount(programs, opt, lookups = lookups)
      }, error = function(e) {
        handle_error(e, "[headcount] headcount_calculation")
        removeNotification("hc_loading")
        showNotification(paste("Error:", conditionMessage(e)), type = "error", duration = 8)
        return(NULL)
      })

      removeNotification("hc_loading")
      if (!is.null(result) && nrow(result$data) > 0) {
        showNotification("Headcount data ready.", type = "message", duration = 4)
      } else if (!is.null(result) && nrow(result$data) == 0) {
        showNotification("No data found for the selected filters.", type = "warning", duration = 5)
      }
      result
    }, ignoreNULL = TRUE, ignoreInit = TRUE)

    hc_plots <- reactive({
      data <- hc_data()
      req(data)
      make_headcount_plots_by_level(data)
    })

    output$hc_undergrad_plot <- renderPlotly({ hc_plots()$undergrad })
    output$hc_grad_plot      <- renderPlotly({ hc_plots()$graduate })
  })
}
