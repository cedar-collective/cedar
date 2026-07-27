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
              current_term = current_term,
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
              section_block(
                "Registration Signals",
                "Long-running course demand signals for the selected department and campus scope. Uses CEDAR's default signal settings; use Registration Statistics for more filters and thresholds.",
                fluidRow(
                  column(6,
                    h4("Perennially Low Enrollment"),
                    reactable::reactableOutput(ns("enrl_perennial_low_table"))
                  ),
                  column(6,
                    h4("Often Waitlisted"),
                    reactable::reactableOutput(ns("enrl_often_waitlisted_table"))
                  )
                ),
                fluidRow(
                  column(6,
                    h4("Recently Above Average"),
                    reactable::reactableOutput(ns("enrl_current_above_avg_table"))
                  ),
                  column(6,
                    h4("Recently Below Average"),
                    reactable::reactableOutput(ns("enrl_current_below_avg_table"))
                  )
                )
              ),
              section_block(
                "Withdrawal Patterns",
                "Selected-term courses with early or late withdrawal rates unusually different from their own same-season history. These are diagnostic patterns, not dashboard action items.",
                fluidRow(
                  column(6,
                    h4("Early Withdrawals"),
                    uiOutput(ns("enrl_early_drop_patterns"))
                  ),
                  column(6,
                    h4("Late Withdrawals"),
                    uiOutput(ns("enrl_late_drop_patterns"))
                  )
                )
              ),
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
          `Avg Enrl` = reactable::colDef(align = "right", maxWidth = 90),
          `Avg Wait` = reactable::colDef(align = "right", maxWidth = 90),
          `Max Wait` = reactable::colDef(align = "right", maxWidth = 90),
          `Recent History` = reactable::colDef(minWidth = 150),
          Enrolled = reactable::colDef(align = "right", maxWidth = 90),
          `Hist Avg` = reactable::colDef(align = "right", maxWidth = 95),
          Diff = reactable::colDef(align = "right", maxWidth = 82)
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

    output$enrl_current_above_avg_table <- make_enrl_signal_table(
      "current_above_avg",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        total_enrl = "Enrolled",
        hist_avg_enrl = "Hist Avg",
        diff = "Diff"
      )
    )

    output$enrl_current_below_avg_table <- make_enrl_signal_table(
      "current_below_avg",
      c(
        subject_course = "Course",
        course_title = "Title",
        campus = "Campus",
        total_enrl = "Enrolled",
        hist_avg_enrl = "Hist Avg",
        diff = "Diff"
      )
    )

    render_dept_drop_level_table <- function(courses, rate_col, diff_col, level_avg_col) {
      if (is.null(courses) || nrow(courses) == 0) {
        return(p("None.", class = "text-hint"))
      }

      level_name <- function(x) switch(as.character(x),
        lower = "Lower Division", upper = "Upper Division",
        grad = "Graduate", as.character(x)
      )
      fmt_diff <- function(d) if (!is.na(d)) paste0(if (d > 0) "+" else "", d, " pts") else "n/a"
      diff_color <- function(d) if (!is.na(d) && d > 0) "#c62828" else "#2e7d32"

      level_order <- c("lower", "upper", "grad")
      present_levels <- unique(courses$course_level)
      known <- intersect(level_order, present_levels[!is.na(present_levels)])
      other <- setdiff(present_levels[!is.na(present_levels)], level_order)
      ordered_levels <- c(known, other)
      if (any(is.na(present_levels))) ordered_levels <- c(ordered_levels, NA_character_)

      tagList(lapply(ordered_levels, function(level_value) {
        group <- if (is.na(level_value)) {
          courses[is.na(courses$course_level), ]
        } else {
          courses[!is.na(courses$course_level) & courses$course_level == level_value, ]
        }
        if (nrow(group) == 0) return(NULL)
        group <- group[order(-group[[rate_col]]), ]

        level_avg <- group[[level_avg_col]][1]
        avg_text <- if (!is.na(level_avg)) paste0(" - level avg: ", level_avg, "%") else ""
        header <- paste0(if (!is.na(level_value)) level_name(level_value) else "Other", avg_text)

        tagList(
          tags$p(
            style = paste0(
              "font-size: 0.78em; font-weight: 700; color: #888;",
              " text-transform: uppercase; letter-spacing: 0.06em;",
              " margin: 10px 0 3px;"
            ),
            header
          ),
          tags$table(
            class = "table table-sm",
            style = "font-size: 0.82em; margin-bottom: 0;",
            lapply(seq_len(nrow(group)), function(i) {
              row <- group[i, ]
              title <- if (!is.na(row$course_title)) row$course_title else ""
              diff <- row[[diff_col]]
              tags$tr(
                tags$td(
                  style = "padding: 2px 6px 2px 0; font-weight: 600; white-space: nowrap;",
                  row$subject_course
                ),
                tags$td(style = "padding: 2px 4px; color: #555;", title),
                tags$td(
                  style = "padding: 2px 4px; text-align: right; white-space: nowrap; color: #333;",
                  paste0(row[[rate_col]], "%")
                ),
                tags$td(
                  style = paste0(
                    "padding: 2px 0 2px 6px; text-align: right;",
                    " white-space: nowrap; color: ", diff_color(diff), ";"
                  ),
                  fmt_diff(diff)
                )
              )
            })
          )
        )
      }))
    }

    make_withdrawal_pattern_output <- function(kind, rate_col, diff_col, level_avg_col, empty_label) {
      renderUI({
        data <- enrl_data()
        if (is.null(data)) return(NULL)
        stats <- data$drop_stats[[kind]]
        if (is.null(stats)) {
          return(p(paste0("No ", empty_label, " withdrawal pattern data available."), class = "text-hint"))
        }

        fluidRow(
          column(6,
            tags$span(style = "color: #2e7d32; font-weight: 600;", "Below historical average"),
            render_dept_drop_level_table(stats$below, rate_col, diff_col, level_avg_col)
          ),
          column(6,
            tags$span(style = "color: #c62828; font-weight: 600;", "Above historical average"),
            render_dept_drop_level_table(stats$above, rate_col, diff_col, level_avg_col)
          )
        )
      })
    }

    output$enrl_early_drop_patterns <- make_withdrawal_pattern_output(
      "early_drops", "early_rate", "diff_early", "level_avg_early_rate", "early"
    )

    output$enrl_late_drop_patterns <- make_withdrawal_pattern_output(
      "late_drops", "late_rate", "diff_late", "level_avg_late_rate", "late"
    )

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
    output$download_ch_outside_lower <- make_ch_download(
      "sch_outside_full_lower", "outside-majors-lower"
    )
    output$download_ch_outside_upper <- make_ch_download(
      "sch_outside_full_upper", "outside-majors-upper"
    )

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
        div(class = "download-row",
          downloadButton(
            ns("download_ch_period"),
            "Download SCH by term/subject",
            class = "btn btn-outline-secondary btn-sm"
          )
        ),
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
        div(class = "download-row",
          downloadButton(
            ns("download_ch_outside_lower"),
            "Download lower-division CSV",
            class = "btn btn-outline-secondary btn-sm"
          ),
          downloadButton(
            ns("download_ch_outside_upper"),
            "Download upper-division CSV",
            class = "btn btn-outline-secondary btn-sm"
          )
        ),
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
