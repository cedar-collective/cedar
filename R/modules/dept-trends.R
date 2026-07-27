# Shiny Module: Dept Trends
#
# Active department profile surface. The module owns Shiny UI/wiring only;
# tab computations are delegated to R/reports/dept-trends.R helpers and lower
# branch/cone functions.

deptTrendsUI <- function(id, sections, dept_choices, current_term = NULL) {
  ns <- NS(id)

  campuses <- sort(unique(sections$campus[
    !is.na(sections$campus) & sections$campus != ""
  ]))
  default_campuses <- intersect(c("ABQ", "EA"), campuses)

  tagList(
    dept_selector_bar(
      title = "Dept Trends",
      subtitle = "Longitudinal department patterns in students, enrollment, degrees, credit hours, Gen Ed, and course outcomes.",
      campus_input = selectizeInput(
        inputId = ns("campus"),
        label = "Campus",
        multiple = TRUE,
        choices = campuses,
        selected = default_campuses,
        options = list(placeholder = "All campuses")
      ),
      dept_input = selectizeInput(
        inputId = ns("dept"),
        label = "Department",
        multiple = FALSE,
        choices = c("Select a department..." = "", dept_choices),
        selected = ""
      ),
      actions = uiOutput(ns("actions"), inline = TRUE),
      scope_output = uiOutput(ns("program_info"))
    ),
    fluidRow(
      column(12,
        cedar_loading_overlay(ns("dept_report"), run_button = NULL,
          trigger_input = ns("dept"),
          hide_on_empty = TRUE,
          emoji = "\U0001f332",
          report_type = "dept_report",
          fresh_default = 20,
          uiOutput(ns("profile"))
        )
      )
    )
  )
}

deptTrendsServer <- function(id, data_objects, dept_choices, current_term,
                             error_handler = NULL, scope_info_ui = NULL,
                             dfw_password = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    sections <- data_objects[["cedar_sections"]]
    students <- data_objects[["cedar_students"]]
    programs <- data_objects[["cedar_programs"]]
    degrees  <- data_objects[["cedar_degrees"]]

    dept_data <- reactiveVal(NULL)
    enrl_data <- reactiveVal(NULL)
    deg_data  <- reactiveVal(NULL)
    ch_data   <- reactiveVal(NULL)
    demo_data <- reactiveVal(NULL)

    log_inventory <- function(data, context) {
      if (is.null(data)) return(invisible(NULL))

      table_names <- names(data$tables %||% list())
      plot_names <- names(data$plots %||% list())
      table_rows <- vapply(data$tables %||% list(), function(tbl) {
        if (is.data.frame(tbl)) nrow(tbl) else NA_integer_
      }, integer(1))

      write_log("DEBUG", "dept_profile_inventory", list(
        context = context,
        dept_code = data$dept_code %||% NULL,
        dept_name = data$dept_name %||% NULL,
        tables = table_names,
        plots = plot_names,
        table_rows = as.list(table_rows)
      ), session$token)
    }

    deptProfileGenEdServer("gen_ed",
      students = students,
      sections = sections,
      programs = programs,
      degrees = degrees,
      dept = reactive(input$dept),
      campus = reactive(input$campus),
      current_term = current_term,
      dfw_password = dfw_password
    )

    observeEvent(input$campus, {
      campus <- input$campus
      if (is.null(campus) || length(campus) == 0) {
        choices <- c("Select a department..." = "", dept_choices)
      } else {
        depts_at_campus <- sort(unique(sections$department[
          !is.na(sections$department) &
            sections$department != "" &
            sections$campus %in% campus
        ]))
        filtered <- dept_choices[dept_choices %in% depts_at_campus]
        choices <- c("Select a department..." = "", filtered)
      }

      current_dept <- isolate(input$dept)
      if (!is.null(current_dept) && nchar(current_dept) > 0 &&
          current_dept %in% unname(choices)) {
        updateSelectizeInput(session, "dept", choices = choices,
                             selected = current_dept)
      } else {
        updateSelectizeInput(session, "dept", choices = choices)
      }
    }, ignoreInit = TRUE)

    output$program_info <- renderUI({
      dept <- input$dept
      req(dept, dept != "")
      if (is.null(scope_info_ui)) return(NULL)
      scope_info_ui(dept)
    })

    run_dept_trends <- function() {
      dept <- input$dept
      campus <- input$campus
      req(dept, dept != "")

      log_data_filter(session, "dept_report_dept", dept)
      log_report_generation(session, "dept_report", list(department = dept, campus = campus))
      dept_data(NULL)
      enrl_data(NULL)
      deg_data(NULL)
      ch_data(NULL)
      demo_data(NULL)

      signal_load_start(session, ns("dept_report"))
      timer <- start_report_timer("dept_report", list(department = dept))

      tryCatch({
        cedar_debug("[dept-trends.R] Checking dept trends cache for: ", dept)
        opt <- list(
          shiny = TRUE,
          dept = dept,
          campus = if (length(campus) > 0) campus else NULL
        )

        hc_plots <- c(
          "hc_progs_under_long_majors_plot",
          "hc_progs_under_long_minors_plot",
          "hc_progs_grad_long_majors_plot",
          "hc_progs_grad_long_minors_plot"
        )
        sp <- function(plots, keys) plots[intersect(names(plots), keys)]

        cached <- load_dept_headcount_cache(dept, data_objects)
        if (!is.null(cached)) {
          message("[dept-trends.R] Headcount cache hit for: ", dept)
          plots <- rebuild_dept_hc_plots(cached)
          duration_sec <- end_report_timer(timer, cached = TRUE)
          do_filt <- filter_data_objects(
            data_objects,
            if (length(campus) > 0) campus else NULL
          )

          base <- c(
            cached[c(
              "dept_code", "dept_raw", "dept_name", "subj_codes",
              "prog_codes", "prog_focus", "palette", "term_start", "term_end"
            )],
            list(
              plots = sp(plots, hc_plots),
              tables = cached$tables["hc_progs_under_long_majors"],
              data_objects_filt = do_filt
            )
          )
          dept_data(base)
          log_inventory(base, "headcount_cache_hit")
          signal_load_complete(session, ns("dept_report"), duration_sec, cached = TRUE)
        } else {
          cedar_debug("[dept-trends.R] Computing headcount for: ", dept)
          base <- create_dept_report_base(data_objects, opt)
          cedar_debug("[dept-trends.R] Headcount ready for: ", dept)

          duration_sec <- end_report_timer(timer)
          dept_data(base)
          log_inventory(base, "headcount_fresh")
          cache_dept_headcount(dept, base, data_objects)
          signal_load_complete(session, ns("dept_report"), duration_sec, cached = FALSE)
        }
      }, error = function(e) {
        signal_load_complete(session, ns("dept_report"), error = TRUE)
        if (!is.null(error_handler)) {
          error_handler(e, "dept_report")
        } else {
          showNotification(paste("Dept Trends error:", conditionMessage(e)),
                           type = "error", duration = 8)
        }
      })
    }

    observeEvent(input$dept, {
      run_dept_trends()
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    observeEvent(input$reload, {
      run_dept_trends()
    }, ignoreInit = TRUE)

    observeEvent(input$tabs, {
      tab <- input$tabs
      base <- dept_data()
      req(!is.null(base))

      if (tab == "Enrollment" && is.null(enrl_data())) {
        enrl_data(compute_dept_enrl_tab(base))
        log_inventory(enrl_data(), "enrollment_tab")
      } else if (tab == "Demographics" && is.null(demo_data())) {
        demo_data(make_population_trend(programs, dept_code = base$dept_code))
      } else if (tab == "Degrees" && is.null(deg_data())) {
        deg_data(compute_dept_degrees_tab(base))
        log_inventory(deg_data(), "degrees_tab")
      } else if (tab == "Credit Hours" && is.null(ch_data())) {
        ch_data(compute_dept_credit_hours_tab(base))
        log_inventory(ch_data(), "credit_hours_tab")
      }
    }, ignoreInit = TRUE)

    output$actions <- renderUI({
      if (is.null(dept_data())) return(NULL)
      filter_actions(
        actionButton(ns("reload"), label = "Reload",
                     icon = icon("rotate"), class = "btn-primary btn-sm")
      )
    })

    output$profile <- renderUI({
      data <- dept_data()
      if (is.null(data)) {
        return(div(
          class = "empty-state",
          h4("Select a department to view its profile.")
        ))
      }

      clean_display_codes <- function(x) {
        x <- as.character(x)
        unique(x[!is.na(x) & nzchar(x)])
      }
      home_major_codes <- clean_display_codes(data$prog_codes)
      if (length(home_major_codes) == 0) {
        home_major_codes <- clean_display_codes(data$dept_code)
      }
      home_major_code_label <- paste(home_major_codes, collapse = ", ")

      tabsetPanel(
        id = ns("tabs"),
        tabPanel("Headcount",
          fluidRow(
            column(12,
              h3(paste("Department:", data$dept_name)),
              h4("Undergrad Majors"),
              plotlyOutput(ns("hc_progs_under_long_majors_plot")),
              h4("Undergrad Minors"),
              plotlyOutput(ns("hc_progs_under_long_minors_plot")),
              h4("Grad Majors"),
              plotlyOutput(ns("hc_progs_grad_long_majors_plot")),
              h4("Grad Minors"),
              plotlyOutput(ns("hc_progs_grad_long_minors_plot"))
            )
          )
        ),
        tabPanel("Enrollment",
          fluidRow(
            column(12,
              h3(paste("Department:", data$dept_name)),
              h4("Credit Hours by Course Level"),
              p("Student credit hours generated by this department's sections over the past five years, broken out by course level."),
              plotlyOutput(ns("enrl_credit_hours_by_level_plot")),
              h4("Highest Total Enrollment"),
              plotlyOutput(ns("highest_total_enrl_plot")),
              h4("Highest Mean Enrollment"),
              plotlyOutput(ns("highest_mean_enrl_plot")),
              h4("Mean Enrollment Distribution"),
              plotlyOutput(ns("highest_mean_histo_plot"))
            )
          )
        ),
        tabPanel("Demographics",
          fluidRow(
            column(12,
              h3(paste("Department:", data$dept_name)),
              p(
                "How the mix of new entrants has shifted over time for declared majors and pre-majors in this department. Each student is counted once at their first term in the program.",
                style = "font-size: 0.85em; color: #666; margin-top: 8px;"
              ),
              plotOutput(ns("pt_plot"), height = "520px")
            )
          )
        ),
        tabPanel("Degrees",
          fluidRow(
            column(12,
              h3(paste("Department:", data$dept_name)),
              h4("Degree Summary by Major"),
              plotlyOutput(ns("degree_summary_faceted_by_major_plot")),
              h4("Degree Summary by Program (Stacked)"),
              plotlyOutput(ns("degree_summary_filtered_program_stacked_plot"))
            )
          )
        ),
        tabPanel("Credit Hours",
          deptTrendsCreditHoursUI(ns, data, home_major_code_label, ch_data)
        ),
        tabPanel("Gen Ed",
          deptProfileGenEdUI(ns("gen_ed"),
            sections = sections,
            current_term = current_term,
            dept = input$dept
          )
        )
      )
    })

    plot_map <- list(
      hc_progs_under_long_majors_plot = "hc",
      hc_progs_under_long_minors_plot = "hc",
      hc_progs_grad_long_majors_plot = "hc",
      hc_progs_grad_long_minors_plot = "hc",
      enrl_credit_hours_by_level_plot = "enrl",
      highest_total_enrl_plot = "enrl",
      highest_mean_enrl_plot = "enrl",
      highest_mean_histo_plot = "enrl",
      degree_summary_faceted_by_major_plot = "deg",
      degree_summary_filtered_program_stacked_plot = "deg",
      chd_by_year_facet_subj_plot = "ch",
      chd_by_year_subj_plot = "ch",
      chd_by_year_plot = "ch",
      sch_outside_pct_lower_plot = "ch",
      sch_outside_pct_upper_plot = "ch",
      sch_dept_pct_lower_plot = "ch",
      sch_dept_pct_upper_plot = "ch",
      sch_top_majors_lower_plot = "ch",
      sch_top_majors_upper_plot = "ch",
      chd_by_fac_facet_plot = "ch",
      chd_by_fac_plot = "ch",
      college_dept_dual_plot = "ch"
    )

    lapply(names(plot_map), function(plot_name) {
      output[[plot_name]] <- renderPlotly({
        tab_data <- switch(plot_map[[plot_name]],
          hc = dept_data(),
          enrl = enrl_data(),
          deg = deg_data(),
          ch = ch_data()
        )
        if (!is.null(tab_data) && plot_name %in% names(tab_data$plots)) {
          tab_data$plots[[plot_name]]
        } else {
          NULL
        }
      })
    })

    output$sch_outside_full_lower_table <- DT::renderDataTable({
      tbl <- ch_data()$tables$sch_outside_full_lower
      if (is.null(tbl)) return(NULL)
      tbl %>%
        dplyr::rename(`Outside Major` = major_name, `Total SCH` = total_hours) %>%
        dplyr::mutate(`Total SCH` = round(`Total SCH`, 0))
    }, options = list(pageLength = 15, scrollX = TRUE, dom = "tip"), rownames = FALSE)

    output$sch_outside_full_upper_table <- DT::renderDataTable({
      tbl <- ch_data()$tables$sch_outside_full_upper
      if (is.null(tbl)) return(NULL)
      tbl %>%
        dplyr::rename(`Outside Major` = major_name, `Total SCH` = total_hours) %>%
        dplyr::mutate(`Total SCH` = round(`Total SCH`, 0))
    }, options = list(pageLength = 15, scrollX = TRUE, dom = "tip"), rownames = FALSE)

    output$pt_plot <- renderPlot({
      req(!is.null(demo_data()))
      demo_data()
    })
  })
}

deptTrendsCreditHoursUI <- function(ns, data, home_major_code_label, ch_data) {
  fluidRow(
    column(12,
      h3(paste("Department:", data$dept_name)),
      info_panel(
        "How credit hours are counted on this tab",
        tags$p(
          "Every number on this tab is a count of ",
          tags$strong("Student Credit Hours (SCH)"),
          ": the sum of course credit values across qualifying enrollments."
        ),
        tags$p(
          tags$strong("Source: "),
          "Banner class lists, stored in cedar_students. Each row is one student registered in one course section in one term."
        ),
        tags$p(
          tags$strong("Passing grades only. "),
          "Only enrollments with a final grade of A+, A, A-, B+, B, B-, C+, C, or CR are counted."
        ),
        tags$p(
          tags$strong("Course department, not student department. "),
          "The department column identifies the course's home department, not the student's major."
        )
      ),
      section_block(
        "Credit Hours by Level and Subject Code",
        "Total SCH earned in this department's courses each term, broken down by course level and subject code prefix.",
        plotlyOutput(ns("chd_by_year_facet_subj_plot"))
      ),
      section_block(
        "Credit Hours by Subject Code (Combined)",
        "Same data as above, collapsed across levels.",
        plotlyOutput(ns("chd_by_year_subj_plot"))
      ),
      section_block(
        "Student Credit Hours by Major",
        tagList(
          tags$p(
            "Home majors match this department's program codes (",
            tags$code(home_major_code_label),
            "). Outside majors include students from other programs, pre-majors, undeclared students, and other colleges.",
            class = "cedar-body"
          )
        ),
        fluidRow(
          column(6, h5("Outside Majors (Lower Division)"),
                 plotlyOutput(ns("sch_outside_pct_lower_plot"))),
          column(6, h5("Outside Majors (Upper Division)"),
                 plotlyOutput(ns("sch_outside_pct_upper_plot")))
        ),
        fluidRow(
          column(6, h5("Majors vs Non-Majors (Lower Division)"),
                 plotlyOutput(ns("sch_dept_pct_lower_plot"))),
          column(6, h5("Majors vs Non-Majors (Upper Division)"),
                 plotlyOutput(ns("sch_dept_pct_upper_plot")))
        )
      ),
      section_block(
        "Outside Majors - Credit Hours Over Time",
        "Term-by-term SCH for the top outside-major groups plus an Other stack.",
        fluidRow(
          column(6, h5("Lower Division"),
                 plotlyOutput(ns("sch_top_majors_lower_plot"))),
          column(6, h5("Upper Division"),
                 plotlyOutput(ns("sch_top_majors_upper_plot")))
        )
      ),
      section_block(
        "All Outside Majors - Full Breakdown",
        "Complete ranked list of all outside-major groups by total SCH across the date range.",
        fluidRow(
          column(6, h5("Lower Division - All Outside Majors"),
                 DT::DTOutput(ns("sch_outside_full_lower_table"))),
          column(6, h5("Upper Division - All Outside Majors"),
                 DT::DTOutput(ns("sch_outside_full_upper_table")))
        )
      ),
      section_block(
        "Outside Major Trends",
        "Top outside-major groups ranked by absolute SCH change, separately for lower and upper division.",
        fluidRow(
          column(6, render_sch_trend_cards(
            ch_data()$tables$sch_major_trends_lower,
            "Lower Division"
          )),
          column(6, render_sch_trend_cards(
            ch_data()$tables$sch_major_trends_upper,
            "Upper Division"
          ))
        )
      ),
      h4("College vs Department Comparison"),
      plotlyOutput(ns("college_dept_dual_plot"))
    )
  )
}
