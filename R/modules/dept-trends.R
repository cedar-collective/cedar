# Shiny Module: Dept Trends
#
# Active department profile surface. The module owns Shiny UI/wiring only;
# tab computations are delegated to R/features/dept-trends.R helpers and lower
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
    # Powers the credit-band x-axis on the graduate Gen Ed section; that section
    # hides itself when this is absent rather than substituting a credit source
    # that cannot answer the question. See R/features/gen-ed.R.
    term_credits <- data_objects[["cedar_student_term_credits"]]

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
      term_credits = term_credits,
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
          dept_code = dept,
          current_term = current_term,
          campus = if (length(campus) > 0) campus else NULL
        )

        hc_plots <- c(
          "hc_progs_under_long_majors_plot",
          "hc_progs_under_long_minors_plot",
          "hc_progs_grad_long_majors_plot",
          "hc_progs_grad_long_minors_plot"
        )
        sp <- function(plots, keys) plots[intersect(names(plots), keys)]

        finish_base_load <- function(base, cache_context, cached) {
          cedar_debug("[dept-trends.R] Computing eager credit hours for: ", dept)
          credit_hours <- compute_dept_credit_hours_tab(base)
          ch_data(credit_hours)
          log_inventory(credit_hours, "credit_hours_eager")

          duration_sec <- end_report_timer(timer, cached = cached)
          dept_data(base)
          log_inventory(base, cache_context)
          signal_load_complete(session, ns("dept_report"), duration_sec, cached = cached)
        }

        cached <- load_dept_headcount_cache(dept, data_objects)
        if (!is.null(cached)) {
          message("[dept-trends.R] Headcount cache hit for: ", dept)
          plots <- rebuild_dept_hc_plots(cached)
          do_filt <- filter_data_objects(
            data_objects,
            if (length(campus) > 0) campus else NULL
          )

          # `palette` is intentionally NOT restored from the cache — it is
          # config, not data, and an older cached value (e.g. "Spectral") would
          # otherwise override the CEDAR palette on every chart built from this
          # base. Always read the live config value.
          base <- c(
            cached[c(
              "dept_code", "dept_raw", "dept_name", "subj_codes",
              "prog_codes", "prog_focus", "term_start", "term_end"
            )],
            list(
              palette = if (exists("cedar_report_palette")) cedar_report_palette else NULL,
              current_term = current_term,
              plots = sp(plots, hc_plots),
              tables = cached$tables["hc_progs_under_long_majors"],
              data_objects_filt = do_filt
            )
          )
          finish_base_load(base, "headcount_cache_hit", cached = TRUE)
        } else {
          cedar_debug("[dept-trends.R] Computing headcount for: ", dept)
          base <- create_dept_report_base(data_objects, opt)
          cedar_debug("[dept-trends.R] Headcount ready for: ", dept)

          cache_dept_headcount(dept, base, data_objects)
          finish_base_load(base, "headcount_fresh", cached = FALSE)
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
                     icon = icon("rotate"), class = "btn-sm btn-primary")
      )
    })

    output$profile <- renderUI({
      data <- dept_data()
      if (is.null(data)) {
        return(empty_state("Select a department to load its trends."))
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

      selected_tab <- isolate(input$tabs) %||% "Headcount"

      tabsetPanel(
        id = ns("tabs"),
        selected = selected_tab,
        tabPanel("Headcount",
          subtab_header(
            "Headcount",
            "Distinct registered students with a program record in this department, term by term."
          ),
          fluidRow(
            column(12,
              dashboard_section(
                "Registered Student Headcount",
                tagList(
                  tags$p(
                    class = "cedar-dashboard-section-description",
                    "Official headcount counts distinct registered students with a department ",
                    "program record in the same term. Major panels use Major and Second Major ",
                    "records, including declared majors and mapped pre-majors when they appear ",
                    "in the program feed; minor panels use First and Second Minor records. ",
                    "Because the definition requires registration, it undercounts students who ",
                    "are away from UNM in a given term."
                  )
                ),
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Undergraduate Majors",
                      "Declared undergraduate majors and mapped pre-majors over time.",
                      plotlyOutput(ns("hc_progs_under_long_majors_plot"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Undergraduate Minors",
                      "Undergraduate minor declarations connected to this department.",
                      plotlyOutput(ns("hc_progs_under_long_minors_plot"))
                    )
                  )
                ),
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Graduate Majors",
                      "Graduate major program headcount over time.",
                      plotlyOutput(ns("hc_progs_grad_long_majors_plot"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Graduate Minors",
                      "Graduate minor program headcount where available.",
                      plotlyOutput(ns("hc_progs_grad_long_minors_plot"))
                    )
                  )
                )
              )
            )
          )
        ),
        tabPanel("Enrollment",
          subtab_header(
            "Enrollment",
            "Long-run course demand for this department: how much teaching it carries, ",
            "how that compares with its college, and which courses drive the change."
          ),
          fluidRow(
            column(12,
              dashboard_section(
                "Enrollment Over Time",
                "Longitudinal view of how much teaching the department carries, how many sections it runs, and how section size has changed across the report window.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Course Enrollment by Level",
                      "Total active enrollment in home-department sections each term.",
                      plotlyOutput(ns("enrl_term_enrollment_plot"), height = "320px")
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Active Sections by Level",
                      "Number of active home-department sections each term.",
                      plotlyOutput(ns("enrl_term_sections_plot"), height = "320px")
                    )
                  )
                ),
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Average Section Size",
                      "Average enrollment per active section, useful for separating growth from scheduling changes.",
                      plotlyOutput(ns("enrl_term_avg_size_plot"), height = "320px")
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Section Size Distribution",
                      "Distribution of typical course size across the report window.",
                      plotlyOutput(ns("highest_mean_histo_plot"), height = "320px")
                    )
                  )
                )
              ),
              dashboard_section(
                "College Context",
                "Indexed comparisons show whether the department is growing faster or slower than its college peers. Each line starts at 100 in the first term, so the shape matters more than raw size.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "All Student Credit Hours",
                      "Department SCH trajectory compared with the college overall.",
                      plotlyOutput(ns("enrl_college_dept_dual_plot"), height = "320px")
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Upper-Division Student Credit Hours",
                      "Upper-division SCH trajectory compared with the college.",
                      plotlyOutput(ns("enrl_college_dept_upper_dual_plot"), height = "320px")
                    )
                  )
                ),
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Graduate Student Credit Hours",
                      "Graduate SCH trajectory compared with the college.",
                      plotlyOutput(ns("enrl_college_dept_grad_dual_plot"), height = "320px")
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Gen Ed Course Enrollment",
                      "Department Gen Ed enrollment trajectory compared with college Gen Ed enrollment.",
                      plotlyOutput(ns("enrl_gen_ed_college_context_plot"), height = "320px")
                    )
                  )
                )
              ),
              dashboard_section(
                "Course Portfolio",
                "Which courses account for the department's long-run enrollment load.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Highest Total Enrollment",
                      "Courses carrying the largest cumulative enrollment over the report window.",
                      plotlyOutput(ns("highest_total_enrl_plot"), height = "340px")
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Highest Mean Section Size",
                      "Courses with the largest typical section size when offered.",
                      plotlyOutput(ns("highest_mean_enrl_plot"), height = "340px")
                    )
                  )
                )
              ),
              dashboard_section(
                "Course Trajectories",
                "Longer-run course-level movement across the report window. Topics courses use exact titles so unrelated rotating topics are not merged.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Largest Enrollment Increases",
                      "Courses with the largest gain from the early report-window average to the recent average.",
                      reactable::reactableOutput(ns("enrl_largest_increase_table"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Largest Enrollment Decreases",
                      "Courses with the largest decline from the early report-window average to the recent average.",
                      reactable::reactableOutput(ns("enrl_largest_decrease_table"))
                    )
                  )
                ),
                fluidRow(
                  column(12,
                    dashboard_subsection(
                      "Repeated Topics With History",
                      "Recurring T: topics with enough offerings to show a trend as a course-title-specific pattern.",
                      reactable::reactableOutput(ns("enrl_repeated_topics_table"))
                    )
                  )
                )
              ),
              dashboard_section(
                "Students Served",
                "Current-term audience context for the long-run enrollment patterns: who takes the department's courses and how department programs overlap with others.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Lower-Division Audience by Major",
                      "Selected-term lower-division home-department sections.",
                      plotlyOutput(ns("enrl_lower_major_current"), height = "280px"),
                      uiOutput(ns("enrl_lower_major_table"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Upper-Division Audience by Major",
                      "Selected-term upper-division home-department sections.",
                      plotlyOutput(ns("enrl_upper_major_current"), height = "280px"),
                      uiOutput(ns("enrl_upper_major_table"))
                    )
                  )
                ),
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Lower-Division Audience by Class Standing",
                      "Selected-term lower-division home-department sections.",
                      plotlyOutput(ns("enrl_lower_class_current"), height = "280px"),
                      uiOutput(ns("enrl_lower_class_table"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Upper-Division Audience by Class Standing",
                      "Selected-term upper-division home-department sections.",
                      plotlyOutput(ns("enrl_upper_class_current"), height = "280px"),
                      uiOutput(ns("enrl_upper_class_table"))
                    )
                  )
                ),
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Where Dept Majors Also Study",
                      "Other minors held by students majoring in this department in the selected term.",
                      plotlyOutput(ns("enrl_cross_dept_minors"), height = "320px")
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Who Minors Here",
                      "Majors held by students minoring in this department in the selected term.",
                      plotlyOutput(ns("enrl_majors_with_minor"), height = "320px")
                    )
                  )
                )
              ),
              dashboard_section(
                "Historical Signals for Review",
                "Long-run patterns that help distinguish structural enrollment issues from one unusual semester.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "Repeated Low Enrollment",
                      "Courses that repeatedly run at or below the low-enrollment threshold.",
                      reactable::reactableOutput(ns("enrl_perennial_low_table"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "Repeated Waitlist Pressure",
                      "Courses with waitlists in a high share of offerings.",
                      reactable::reactableOutput(ns("enrl_often_waitlisted_table"))
                    )
                  )
                )
              )
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
        ),
        tabPanel("Degrees",
          subtab_header(
            "Degrees",
            "Completions awarded in this department's programs, by term and degree type."
          ),
          fluidRow(
            column(12,
              dashboard_section(
                "Degree Completion",
                "Degrees awarded through department programs across the report window.",
                fluidRow(
                  column(6,
                    dashboard_subsection(
                      "By Major",
                      "Degree counts separated by major program.",
                      plotlyOutput(ns("degree_summary_faceted_by_major_plot"))
                    )
                  ),
                  column(6,
                    dashboard_subsection(
                      "By Program",
                      "Degree counts stacked by program for a compact comparison.",
                      plotlyOutput(ns("degree_summary_filtered_program_stacked_plot"))
                    )
                  )
                )
              )
            )
          )
        ),
        tabPanel("Demographics",
          subtab_header(
            "Demographics",
            "Who enters this department's programs, and how that mix has shifted."
          ),
          fluidRow(
            column(12,
              dashboard_section(
                "New-Entrant Mix",
                "How the mix of new entrants has shifted over time for declared majors and pre-majors in this department. Each student is counted once at their first term in the program.",
                dashboard_subsection(
                  "Population Type Over Time",
                  "First-time freshman, transfer, continuing, and other entrant categories by first department term.",
                  plotOutput(ns("pt_plot"), height = "520px")
                )
              )
            )
          )
        )
      )
    })

    plot_map <- list(
      hc_progs_under_long_majors_plot = "hc",
      hc_progs_under_long_minors_plot = "hc",
      hc_progs_grad_long_majors_plot = "hc",
      hc_progs_grad_long_minors_plot = "hc",
      enrl_term_enrollment_plot = "enrl",
      enrl_term_sections_plot = "enrl",
      enrl_term_avg_size_plot = "enrl",
      enrl_gen_ed_college_context_plot = "enrl",
      enrl_college_dept_dual_plot = "ch",
      enrl_college_dept_upper_dual_plot = "ch",
      enrl_college_dept_grad_dual_plot = "ch",
      enrl_credit_hours_by_level_plot = "enrl",
      enrl_cross_dept_minors = "enrl",
      enrl_majors_with_minor = "enrl",
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
      college_dept_dual_plot = "ch",
      college_dept_lower_dual_plot = "ch",
      college_dept_upper_dual_plot = "ch",
      college_dept_grad_dual_plot = "ch"
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

    make_enrl_signal_table <- function(table_name, columns) {
      reactable::renderReactable({
        data <- enrl_data()
        if (is.null(data)) return(NULL)
        tbl <- data$tables[[table_name]]
        if (is.null(tbl) || !is.data.frame(tbl) || nrow(tbl) == 0) {
          return(reactable::reactable(
            tibble::tibble(Message = "No courses found for this signal."),
            theme = cedar_tbl_theme,
            pagination = FALSE,
            columns = list(Message = reactable::colDef(minWidth = 220))
          ))
        }

        display <- tbl %>%
          select(any_of(names(columns)))
        names(display) <- unname(columns[names(display)])

        column_defs <- list(
          Course = reactable::colDef(minWidth = 95),
          Title = reactable::colDef(minWidth = 160),
          Campus = reactable::colDef(minWidth = 78, maxWidth = 90),
          Level = reactable::colDef(minWidth = 80, maxWidth = 95),
          Terms = reactable::colDef(align = "right", maxWidth = 76),
          `% Low` = reactable::colDef(align = "right", maxWidth = 82),
          `% Waitlisted` = reactable::colDef(align = "right", maxWidth = 112),
          Sections = reactable::colDef(align = "right", maxWidth = 86),
          `Avg Enrl` = reactable::colDef(align = "right", maxWidth = 90),
          `Avg Wait` = reactable::colDef(align = "right", maxWidth = 90),
          `Max Wait` = reactable::colDef(align = "right", maxWidth = 90),
          Waiting = reactable::colDef(align = "right", maxWidth = 90),
          `Recent History` = reactable::colDef(minWidth = 150),
          Enrolled = reactable::colDef(align = "right", maxWidth = 90),
          `Hist Avg` = reactable::colDef(align = "right", maxWidth = 95),
          Diff = reactable::colDef(align = "right", maxWidth = 82),
          `Early Avg` = reactable::colDef(align = "right", maxWidth = 90),
          `Recent Avg` = reactable::colDef(align = "right", maxWidth = 100),
          Change = reactable::colDef(align = "right", maxWidth = 90),
          `% Change` = reactable::colDef(
            align = "right",
            maxWidth = 100,
            format = reactable::colFormat(suffix = "%")
          ),
          From = reactable::colDef(maxWidth = 90),
          To = reactable::colDef(maxWidth = 90),
          Topic = reactable::colDef(maxWidth = 70)
        )

        reactable::reactable(
          display,
          theme = cedar_tbl_theme,
          striped = TRUE,
          highlight = TRUE,
          defaultPageSize = 8,
          columns = column_defs[names(column_defs) %in% names(display)]
        )
      })
    }

    output$enrl_largest_increase_table <- make_enrl_signal_table(
      "largest_enrl_increase",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        topics_flag = "Topic",
        n_terms = "Terms",
        baseline_avg_enrl = "Early Avg",
        recent_avg_enrl = "Recent Avg",
        change_abs = "Change",
        change_pct = "% Change",
        enrl_history = "Recent History"
      )
    )

    output$enrl_largest_decrease_table <- make_enrl_signal_table(
      "largest_enrl_decrease",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        topics_flag = "Topic",
        n_terms = "Terms",
        baseline_avg_enrl = "Early Avg",
        recent_avg_enrl = "Recent Avg",
        change_abs = "Change",
        change_pct = "% Change",
        enrl_history = "Recent History"
      )
    )

    output$enrl_repeated_topics_table <- make_enrl_signal_table(
      "repeated_topics_history",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        n_terms = "Terms",
        avg_enrl = "Avg Enrl",
        baseline_avg_enrl = "Early Avg",
        recent_avg_enrl = "Recent Avg",
        change_abs = "Change",
        change_pct = "% Change",
        first_term_label = "From",
        last_term_label = "To",
        enrl_history = "Recent History"
      )
    )

    output$enrl_perennial_low_table <- make_enrl_signal_table(
      "perennial_low",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        level = "Level",
        n_terms = "Terms",
        pct_low = "% Low",
        avg_enrl = "Avg Enrl",
        enrl_history = "Recent History"
      )
    )

    output$enrl_often_waitlisted_table <- make_enrl_signal_table(
      "often_waitlisted",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        n_terms = "Terms",
        pct_waitlisted = "% Waitlisted",
        avg_waiting = "Avg Wait",
        max_waiting = "Max Wait",
        enrl_history = "Recent History"
      )
    )

    for (.donut_key in c(
      "lower_major_current", "upper_major_current",
      "lower_class_current", "upper_class_current"
    )) {
      local({
        key <- .donut_key
        output[[paste0("enrl_", key)]] <- renderPlotly({
          data <- enrl_data()
          if (is.null(data)) return(NULL)
          p <- data$plots$student_donuts[[key]]
          if (!is.null(p)) p else NULL
        })
      })
    }

    render_enrl_composition_table <- function(df) {
      if (is.null(df) || nrow(df) == 0) {
        return(p("No data available.", class = "text-hint"))
      }

      header <- tags$tr(
        tags$th(style = "padding: 2px 6px 4px 0; font-weight: 600; color: #555; font-size: 0.8em;", ""),
        tags$th(style = "padding: 2px 4px 4px; font-weight: 600; color: #555; font-size: 0.8em; text-align: right;", "Count"),
        tags$th(style = "padding: 2px 0 4px 6px; font-weight: 600; color: #555; font-size: 0.8em; text-align: right;", "Share")
      )

      rows <- lapply(seq_len(nrow(df)), function(i) {
        r <- df[i, ]
        color <- if (!is.na(r$color) && nzchar(r$color)) r$color else "#aaaaaa"
        cur_str <- if (!is.na(r$n) && r$n > 0) as.character(round(r$n)) else "-"
        share_str <- if (!is.na(r$pct)) paste0(r$pct, "%") else "-"

        tags$tr(
          tags$td(
            style = "padding: 2px 6px 2px 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 180px;",
            tags$span(style = paste0("display:inline-block; width:9px; height:9px; border-radius:2px; background:", color, "; margin-right:5px; vertical-align:middle;")),
            tags$span(r$label, style = "font-size: 0.85em; vertical-align: middle;")
          ),
          tags$td(style = "padding: 2px 4px; text-align: right; font-size: 0.85em; white-space: nowrap;", cur_str),
          tags$td(style = "padding: 2px 0 2px 6px; text-align: right; font-size: 0.85em; white-space: nowrap; color: #555;", share_str)
        )
      })

      tags$table(
        class = "table table-sm",
        style = "font-size: 0.82em; margin-bottom: 0; table-layout: fixed; width: 100%;",
        tags$thead(header),
        tags$tbody(rows)
      )
    }

    for (.lvl in c("lower", "upper")) {
      local({
        lvl <- .lvl
        lvl_label <- if (lvl == "lower") "Lower Div" else "Upper Div"

        output[[paste0("enrl_", lvl, "_major_table")]] <- renderUI({
          data <- enrl_data()
          if (is.null(data)) return(NULL)
          df <- data$plots$student_donuts[[paste0(lvl, "_major_table_df")]]
          tagList(
            p(paste0(lvl_label, " Majors - selected term"),
              style = "font-size: 0.8em; color: #666; margin-bottom: 4px;"),
            render_enrl_composition_table(df)
          )
        })

        output[[paste0("enrl_", lvl, "_class_table")]] <- renderUI({
          data <- enrl_data()
          if (is.null(data)) return(NULL)
          df <- data$plots$student_donuts[[paste0(lvl, "_class_table_df")]]
          tagList(
            p(paste0(lvl_label, " Class Standing - selected term"),
              style = "font-size: 0.8em; color: #666; margin-bottom: 4px;"),
            render_enrl_composition_table(df)
          )
        })
      })
    }

    outside_major_full_breakdown <- reactive({
      data <- ch_data()
      if (is.null(data) || is.null(data$tables)) return(NULL)

      add_level <- function(tbl, level_label) {
        if (is.null(tbl) || !is.data.frame(tbl) || nrow(tbl) == 0) return(NULL)
        tbl %>%
          dplyr::mutate(level = level_label, .before = 1)
      }

      out <- dplyr::bind_rows(
        add_level(data$tables$sch_outside_full_lower, "Lower Division"),
        add_level(data$tables$sch_outside_full_upper, "Upper Division")
      )

      if (nrow(out) == 0) NULL else out
    })

    output$sch_outside_full_table <- reactable::renderReactable({
      tbl <- outside_major_full_breakdown()
      if (is.null(tbl)) {
        return(reactable::reactable(
          tibble::tibble(Message = "No outside-major credit-hour rows found."),
          theme = cedar_tbl_theme,
          pagination = FALSE,
          columns = list(Message = reactable::colDef(minWidth = 260))
        ))
      }
      display <- tbl %>%
        dplyr::rename(
          Level = level,
          `Outside Major` = major_name,
          `Total SCH` = total_hours
        ) %>%
        dplyr::mutate(`Total SCH` = round(`Total SCH`, 0))

      reactable::reactable(
        display,
        theme = cedar_tbl_theme,
        striped = TRUE,
        highlight = TRUE,
        compact = TRUE,
        searchable = TRUE,
        defaultPageSize = 20,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(10, 20, 50, 100),
        columns = list(
          Level = reactable::colDef(maxWidth = 125),
          `Outside Major` = reactable::colDef(minWidth = 220),
          `Total SCH` = reactable::colDef(
            align = "right",
            format = reactable::colFormat(separators = TRUE, digits = 0)
          )
        )
      )
    })

    make_ch_download <- function(table_name, suffix) {
      downloadHandler(
        filename = function() {
          base <- dept_data()
          dept_code <- if (!is.null(base$dept_code)) base$dept_code else "dept"
          dept_code <- gsub("[^A-Za-z0-9_-]+", "-", dept_code)
          paste0("cedar-", tolower(dept_code), "-credit-hours-", suffix, ".csv")
        },
        content = function(file) {
          data <- ch_data()
          tbl <- data$tables[[table_name]]
          if (is.null(tbl) || !is.data.frame(tbl)) {
            tbl <- data.frame(message = "No credit-hours data available")
          }
          utils::write.csv(tbl, file, row.names = FALSE)
        }
      )
    }

    output$download_ch_period <- make_ch_download(
      "chd_by_period_table", "by-term-subject"
    )
    output$download_ch_outside <- downloadHandler(
      filename = function() {
        base <- dept_data()
        dept_code <- if (!is.null(base$dept_code)) base$dept_code else "dept"
        dept_code <- gsub("[^A-Za-z0-9_-]+", "-", dept_code)
        paste0("cedar-", tolower(dept_code), "-credit-hours-outside-majors.csv")
      },
      content = function(file) {
        tbl <- outside_major_full_breakdown()
        if (is.null(tbl) || !is.data.frame(tbl)) {
          tbl <- data.frame(message = "No outside-major credit-hours data available")
        }
        utils::write.csv(tbl, file, row.names = FALSE)
      }
    )

    output$pt_plot <- renderPlot({
      req(!is.null(demo_data()))
      demo_data()
    })
  })
}

deptTrendsCreditHoursUI <- function(ns, data, home_major_code_label, ch_data) {
  tagList(
    # The counting rules used to sit in a collapsed blue box. They are the three
    # things a reader has to know before reading any number on the tab, so they
    # belong in the description where they cannot be missed — and every other
    # subtab now opens the same way.
    subtab_header(
      "Credit Hours",
      "Everything here counts Student Credit Hours: course credits summed ",
      "across enrollments, not a headcount of students. Only enrollments that ",
      "finished with a passing grade (A+ through C, or CR) are included, and ",
      "each course counts toward the department that owns it rather than the ",
      "student's major."
    ),
    fluidRow(
      column(12,
        dashboard_section(
        "Credit Hour Production",
        "How much SCH this department generates over time, how that production is distributed across subject codes and course levels, and how its trajectory compares with the college.",
        dashboard_subsection(
          "By Level and Subject Code",
          "Total SCH earned in this department's courses each term, broken down by course level and subject code prefix.",
          div(class = "download-row",
            downloadButton(
              ns("download_ch_period"),
              "Download SCH by term/subject",
              class = "btn btn-outline-secondary btn-sm"
            )
          ),
          plotlyOutput(ns("chd_by_year_facet_subj_plot"))
        ),
        dashboard_subsection(
          "By Subject Code",
          "Same SCH data collapsed across course levels.",
          plotlyOutput(ns("chd_by_year_subj_plot"))
        ),
        dashboard_subsection(
          "College Comparison",
          "Indexed SCH growth for this department compared with its college.",
          plotlyOutput(ns("college_dept_dual_plot"))
        )
      ),
      dashboard_section(
        "Students Served",
        tagList(
          tags$p(
            class = "cedar-dashboard-section-description",
            "How SCH is split between home majors and students from other programs. Home majors match this department's program codes (",
            tags$code(home_major_code_label),
            "). Outside majors include students from other programs, pre-majors, undeclared students, and other colleges."
          )
        ),
        fluidRow(
          column(6,
            dashboard_subsection(
              "Outside Majors: Lower Division",
              "Outside-major share of lower-division SCH across the report window.",
              plotlyOutput(ns("sch_outside_pct_lower_plot"))
            )
          ),
          column(6,
            dashboard_subsection(
              "Outside Majors: Upper Division",
              "Outside-major share of upper-division SCH across the report window.",
              plotlyOutput(ns("sch_outside_pct_upper_plot"))
            )
          )
        ),
        fluidRow(
          column(6,
            dashboard_subsection(
              "Home vs Non-Major SCH: Lower Division",
              "Lower-division SCH generated by department majors compared with everyone else.",
              plotlyOutput(ns("sch_dept_pct_lower_plot"))
            )
          ),
          column(6,
            dashboard_subsection(
              "Home vs Non-Major SCH: Upper Division",
              "Upper-division SCH generated by department majors compared with everyone else.",
              plotlyOutput(ns("sch_dept_pct_upper_plot"))
            )
          )
        )
      ),
      dashboard_section(
        "Outside-Major Detail",
        "Which outside-major groups account for SCH in this department, how their contribution has changed, and the full ranked breakdown behind the summaries.",
        fluidRow(
          column(6,
            dashboard_subsection(
              "Lower-Division SCH Over Time",
              "Term-by-term SCH for the top outside-major groups plus an Other stack.",
              plotlyOutput(ns("sch_top_majors_lower_plot"))
            )
          ),
          column(6,
            dashboard_subsection(
              "Upper-Division SCH Over Time",
              "Term-by-term SCH for the top outside-major groups plus an Other stack.",
              plotlyOutput(ns("sch_top_majors_upper_plot"))
            )
          )
        ),
        fluidRow(
          column(6,
            dashboard_subsection(
              "Lower-Division Trend Cards",
              "Top outside-major groups ranked by absolute SCH change.",
              render_sch_trend_cards(
                ch_data()$tables$sch_major_trends_lower,
                "Lower Division"
              )
            )
          ),
          column(6,
            dashboard_subsection(
              "Upper-Division Trend Cards",
              "Top outside-major groups ranked by absolute SCH change.",
              render_sch_trend_cards(
                ch_data()$tables$sch_major_trends_upper,
                "Upper Division"
              )
            )
          )
        ),
        dashboard_subsection(
          "Full Breakdown",
          "Complete ranked list of all outside-major groups by total SCH across the date range.",
          div(class = "download-row",
            downloadButton(
              ns("download_ch_outside"),
              "Download outside-major CSV",
              class = "btn btn-outline-secondary btn-sm"
            )
          ),
          reactable::reactableOutput(ns("sch_outside_full_table"))
        )
      )
    )
  )
  )
}
