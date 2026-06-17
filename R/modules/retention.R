# Shiny Module: Retention Tab
#
# Institution-level student retention, viewed through the lens of which courses
# students were taking when retention is measured. Two analyses:
#
#   Course Comparison — for a single anchor term, shows T+1 to T+N retention
#       rates side-by-side across courses in a college, department, or subject.
#       Reveals which courses are associated with students who stay vs. leave.
#
#   Course Trend — for a single course across all terms it has been offered,
#       shows how T+1 to T+N retention has changed over time. Optionally
#       breaks out results by instructor.
#
# Retention definition: any enrollment record with registration_status_code in
# STATUS_REGISTERED in the target term (institution-level, any major).
#
# Depends on (sourced via load-funcs.R):
#   R/cones/course-retention.R  — get_retention_comparison(), get_retention_trend()
#   cedar_data_summary          — display_terms, current term
#   .term_label(), .dept_choices — from global.R / ui.R
#
# Exported functions:
#   retentionUI(id)
#   retentionServer(id, students)


# =============================================================================
# UI
# =============================================================================

retentionUI <- function(id) {
  ns <- NS(id)

  tagList(
    h1("Retention"),
    p(class = "cedar-lead",
      "Institution-level retention (still enrolled at UNM, any major) measured from a
      course enrollment anchor. Use \u201cCourse Comparison\u201d to compare retention rates
      across courses for a single term. Use \u201cCourse Trend\u201d to track how one course\u2019s
      retention has changed over time."),

    layout_sidebar(
      id = ns("retention-sidebar-layout"),

      # ---- Sidebar: shared display controls --------------------------------
      sidebar = sidebar(
        width = 260,
        open  = TRUE,

        h6("Display Options", class = "fw-semibold mt-1 mb-2"),

        sliderInput(
          ns("n_terms"),
          label   = "Semesters to track",
          min = 1, max = 8, value = 5, step = 1,
          width = "100%"
        ),

        numericInput(
          ns("min_n"),
          label = "Min students per row",
          value = 10, min = 1, step = 1,
          width = "100%"
        ),

        hr(class = "my-3"),

        p(class = "text-note m-0",
          icon("circle-info"), " Rows with fewer than the minimum student count are hidden to protect privacy and suppress unstable rates.")
      ),

      # ---- Main content: two analysis tabs ---------------------------------
      navset_tab(
        id = ns("retention_tabs"),
        selected = "Course Comparison",

        # ── Tab 1: Course Comparison ──────────────────────────────────────
        nav_panel(
          "Course Comparison",

          div(class = "filters-compact mt-filters",

            fluidRow(
              column(3,
                selectInput(
                  ns("comp_term"),
                  label   = "Term",
                  choices = sort(unique(c(cedar_sections$term_type, cedar_sections$term)),
                                 decreasing = TRUE),
                  width   = "100%"
                )
              ),
              column(6,
                selectizeInput(
                  ns("comp_courses"),
                  label    = "Course(s) — leave blank for all",
                  multiple = TRUE,
                  choices  = NULL,   # populated server-side
                  options  = list(placeholder = "Type to search...", maxOptions = 500),
                  width    = "100%"
                )
              ),
              column(3,
                div(style = "margin-top: 22px;",
                  actionButton(ns("run_comp"), "Run Comparison",
                               class = "btn-primary w-100",
                               icon  = icon("table"))
                )
              )
            )

          ), # end filters-compact

          br(),
          uiOutput(ns("comp_results"))
        ),

        # ── Tab 2: Course Trend ───────────────────────────────────────────
        nav_panel(
          "Course Trend",

          div(class = "filters-compact mt-filters",

            fluidRow(
              column(5,
                selectizeInput(
                  ns("trend_course"),
                  label   = "Course",
                  choices = NULL,   # populated server-side
                  options = list(placeholder = "Type to search...", maxOptions = 500),
                  width   = "100%"
                )
              ),
              column(4,
                div(style = "margin-top: 28px;",
                  checkboxInput(
                    ns("trend_by_instructor"),
                    label = "Break out by instructor",
                    value = FALSE
                  )
                )
              ),
              column(3,
                div(style = "margin-top: 22px;",
                  actionButton(ns("run_trend"), "Run Trend",
                               class = "btn-primary",
                               icon  = icon("chart-line"))
                )
              )
            )

          ), # end filters-compact

          br(),
          uiOutput(ns("trend_results"))
        )

      ) # end navset_tab
    ) # end layout_sidebar
  ) # end tagList
}


# =============================================================================
# Server
# =============================================================================

retentionServer <- function(id, students) {
  moduleServer(id, function(input, output, session) {

    # ---- Populate course selectize choices (both tabs) ----------------------

    observe({
      course_vals <- sort(unique(cedar_sections$subject_course))
      updateSelectizeInput(session, "comp_courses", choices = course_vals, server = TRUE)
      updateSelectizeInput(session, "trend_course",  choices = course_vals, server = TRUE)
    })


    # ---- Course Comparison --------------------------------------------------

    comp_data <- eventReactive(input$run_comp, {
      term_val <- input$comp_term
      req(nzchar(term_val %||% ""))

      opt <- list(
        term    = as.integer(term_val),
        n_terms = input$n_terms,
        min_n   = input$min_n
      )
      if (length(input$comp_courses) > 0) opt$course <- input$comp_courses

      message("[retention module] Running comparison: term=", opt$term)

      notify_id <- "ret_comp_loading"
      showNotification("Computing retention comparison\u2026", type = "warning",
                       duration = NULL, id = notify_id)
      on.exit(removeNotification(notify_id))

      tryCatch(
        get_retention_comparison(students, opt),
        error = function(e) {
          showNotification(paste("Retention comparison failed:", e$message), type = "error")
          NULL
        }
      )
    })

    output$comp_results <- renderUI({
      result <- comp_data()
      if (is.null(result)) return(NULL)
      if (nrow(result) == 0) {
        return(div(class = "alert alert-warning",
                   "No courses met the minimum student threshold for the selected filters."))
      }
      DTOutput(session$ns("comp_table"))
    })

    output$comp_table <- renderDT({
      result <- comp_data()
      req(!is.null(result) && nrow(result) > 0)

      # Use the actual columns in the result, not the current slider value.
      # (Slider may have changed since the last Run.)
      n_terms  <- sum(startsWith(names(result), "ret_"))
      ret_cols <- paste0("ret_", seq_len(n_terms))
      disp_cols <- c("subject_course", "n", intersect(ret_cols, names(result)))
      display_df <- result %>% select(all_of(disp_cols))

      dt_obj <- datatable(
        display_df,
        rownames  = FALSE,
        selection = "none",
        options   = list(
          pageLength = 25,
          order      = list(list(1, "desc")),  # sort by n desc initially
          columnDefs = list(list(className = "dt-right", targets = seq_len(n_terms + 1)))
        ),
        colnames = c("Course", "Students", paste0("+", seq_len(n_terms), " sem"))
      ) %>%
        formatPercentage(intersect(ret_cols, names(display_df)), digits = 1)

      # Heatmap: color ret_n columns by numeric value (0–1)
      breaks  <- seq(0.40, 0.95, by = 0.05)
      palette <- colorRampPalette(c("#f44336", "#ff9800", "#8bc34a", "#4caf50"))(length(breaks) + 1)

      for (col in intersect(ret_cols, names(display_df))) {
        dt_obj <- dt_obj %>%
          formatStyle(col, backgroundColor = styleInterval(breaks, palette))
      }

      dt_obj
    }, server = FALSE)


    # ---- Course Trend -------------------------------------------------------

    trend_data <- eventReactive(input$run_trend, {
      course_val <- input$trend_course
      req(nzchar(course_val %||% ""))

      opt <- list(
        course        = course_val,
        n_terms       = input$n_terms,
        min_n         = input$min_n,
        by_instructor = isTRUE(input$trend_by_instructor)
      )

      message("[retention module] Running trend: course='", course_val, "'")

      notify_id <- "ret_trend_loading"
      showNotification("Computing retention trend\u2026", type = "warning",
                       duration = NULL, id = notify_id)
      on.exit(removeNotification(notify_id))

      tryCatch(
        get_retention_trend(students, opt),
        error = function(e) {
          showNotification(paste("Retention trend failed:", e$message), type = "error")
          NULL
        }
      )
    })

    output$trend_results <- renderUI({
      result <- trend_data()
      if (is.null(result)) return(NULL)
      if (nrow(result) == 0) {
        return(div(class = "alert alert-warning",
                   "No terms met the minimum student threshold for this course."))
      }
      DTOutput(session$ns("trend_table"))
    })

    output$trend_table <- renderDT({
      result <- trend_data()
      req(!is.null(result) && nrow(result) > 0)

      n_terms       <- sum(startsWith(names(result), "ret_"))
      by_instructor <- isTRUE(input$trend_by_instructor)
      ret_cols      <- paste0("ret_", seq_len(n_terms))

      id_cols   <- c("term_label", if (by_instructor) "instructor_id", "n")
      disp_cols <- c(id_cols, intersect(ret_cols, names(result)))
      display_df <- result %>% select(all_of(disp_cols))

      col_names <- c("Term", if (by_instructor) "Instructor", "Students",
                     paste0("+", seq_len(n_terms), " sem"))

      dt_obj <- datatable(
        display_df,
        rownames  = FALSE,
        selection = "none",
        options   = list(
          pageLength = 20,
          columnDefs = list(list(className = "dt-right",
                                 targets   = seq(length(id_cols), length(disp_cols) - 1)))
        ),
        colnames = col_names
      ) %>%
        formatPercentage(intersect(ret_cols, names(display_df)), digits = 1)

      # Heatmap coloring
      breaks  <- seq(0.40, 0.95, by = 0.05)
      palette <- colorRampPalette(c("#f44336", "#ff9800", "#8bc34a", "#4caf50"))(length(breaks) + 1)

      for (col in intersect(ret_cols, names(display_df))) {
        dt_obj <- dt_obj %>%
          formatStyle(col, backgroundColor = styleInterval(breaks, palette))
      }

      dt_obj
    }, server = FALSE)

  }) # end moduleServer
}
