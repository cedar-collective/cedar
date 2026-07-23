# Shiny Module: Cancellations Tab
#
# Shows cancelled course sections and cancellation timing patterns.
#
# Exported functions:
#   cancellationsUI(id, sections, default_term, dept_choices)
#   cancellationsServer(id, sections, error_handler = NULL)

cancellationsUI <- function(id, sections, default_term, dept_choices) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Cancellations",
      "Cancelled sections matching your filters, with timing shown relative to course start.",
      fluidRow(class = "explore-filter-row",
        column(2,
          selectizeInput(ns("cn_campus"), "Campus", multiple = TRUE,
                         choices = sort(unique(sections$campus)),
                         selected = c("ABQ", "EA"))
        ),
        column(1,
          selectizeInput(ns("cn_college"), "College", multiple = TRUE,
                         choices = sort(unique(sections$college)))
        ),
        column(2,
          selectizeInput(ns("cn_dept"), "Department", multiple = TRUE,
                         choices = as.list(dept_choices))
        ),
        column(2,
          selectizeInput(ns("cn_term"), "Term", multiple = TRUE,
                         choices = sort(unique(c(sections$term_type, sections$term)), decreasing = TRUE),
                         selected = default_term)
        ),
        column(1,
          selectInput(ns("cn_pt"), "PoT", multiple = TRUE,
                      choices = sort(unique(sections$part_term)))
        ),
        column(1,
          selectInput(ns("cn_im"), "Method", multiple = TRUE,
                      choices = sort(unique(sections$delivery_method)))
        ),
        column(1,
          selectInput(ns("cn_level"), "Level", multiple = TRUE,
                      choices = sort(unique(sections$level)),
                      selected = "lower")
        ),
        column(2,
          filter_actions(
            actionButton(ns("cn_button"), label = "Find Cancellations",
                         icon = icon("ban"), class = "btn-primary"),
            actionButton(ns("cn_copy_url"), label = NULL, icon = icon("link"),
                         title = "Copy shareable link for current view",
                         class = "btn-outline-secondary btn-sm")
          )
        )
      ),
      filter_scope_stripe(uiOutput(ns("cn_filter_summary")))
    ),

    cedar_loading_overlay(id, "cn_button", emoji = "\U0001fa91",
      report_type = "cancellations", fresh_default = 5,
      uiOutput(ns("cn_output"))
    )
  )
}

cancellationsServer <- function(id, sections, error_handler = NULL) {
  moduleServer(id, function(input, output, session) {
    cn_has_run <- reactiveVal(FALSE)
    cn_data <- reactiveVal(NULL)

    section_col_defs <- function() {
      list(
        term_label = reactable::colDef(name = "Term", maxWidth = 95),
        department = reactable::colDef(name = "Dept", maxWidth = 80),
        section_id = reactable::colDef(name = "Section ID", minWidth = 130),
        subject_course = reactable::colDef(name = "Course", minWidth = 105,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        course_title = reactable::colDef(name = "Title", minWidth = 220),
        section = reactable::colDef(name = "Sec", maxWidth = 65),
        crn = reactable::colDef(name = "CRN", maxWidth = 75),
        campus = reactable::colDef(name = "Campus", maxWidth = 80),
        college = reactable::colDef(name = "College", maxWidth = 65),
        part_term = cedar_pot_coldef(),
        delivery_method = reactable::colDef(name = "Method", maxWidth = 90),
        level = reactable::colDef(name = "Level", maxWidth = 85),
        enrolled = reactable::colDef(name = "Enrl", align = "right", maxWidth = 75),
        capacity = reactable::colDef(name = "Cap", align = "right", maxWidth = 70),
        available = reactable::colDef(name = "Avail", align = "right", maxWidth = 60),
        status = reactable::colDef(name = "Status", maxWidth = 55),
        canceled_on = reactable::colDef(name = "Canceled", maxWidth = 110),
        start_date = reactable::colDef(name = "Start", maxWidth = 110),
        census1 = reactable::colDef(name = "Census", show = FALSE),
        timing_reference = reactable::colDef(show = FALSE),
        timing_reference_date = reactable::colDef(show = FALSE),
        days_before_start = reactable::colDef(name = "Days to Start", align = "right", maxWidth = 120),
        days_before_census = reactable::colDef(show = FALSE),
        comments = reactable::colDef(name = "Comments", minWidth = 220)
      )
    }

    common_course_col_defs <- function() {
      list(
        campus = reactable::colDef(name = "Campus", maxWidth = 75),
        college = reactable::colDef(name = "College", maxWidth = 65),
        subject_course = reactable::colDef(name = "Course", minWidth = 105,
          cell = function(v) htmltools::span(class = "fw-semibold", v)),
        course_title = reactable::colDef(name = "Title", minWidth = 220),
        n_cancelled_sections = reactable::colDef(name = "Cancelled", align = "right", maxWidth = 95),
        n_terms_cancelled = reactable::colDef(name = "Terms", align = "right", maxWidth = 80),
        first_cancelled_term = reactable::colDef(name = "First", maxWidth = 105),
        last_cancelled_term = reactable::colDef(name = "Last", maxWidth = 105),
        median_days_before_start = reactable::colDef(name = "Median Days to Start", align = "right", maxWidth = 150),
        cancelled_before_start = reactable::colDef(name = "Before Start", align = "right", maxWidth = 115),
        cancelled_after_start = reactable::colDef(name = "After Start", align = "right", maxWidth = 110)
      )
    }

    trend_col_defs <- function() {
      list(
        term = reactable::colDef(name = "Term Code", align = "right", maxWidth = 105),
        term_label = reactable::colDef(name = "Term", maxWidth = 105),
        chart_unit = reactable::colDef(name = "Unit", maxWidth = 100),
        n_cancelled = reactable::colDef(name = "Cancelled", align = "right", maxWidth = 100)
      )
    }

    build_trend_chart_data <- function(trends) {
      if (is.null(trends) || nrow(trends) == 0) return(trends)

      top_units <- trends %>%
        dplyr::group_by(department) %>%
        dplyr::summarize(total_cancelled = sum(n_cancelled), .groups = "drop") %>%
        dplyr::arrange(dplyr::desc(total_cancelled), department) %>%
        dplyr::slice_head(n = 10) %>%
        dplyr::pull(department)

      trends %>%
        dplyr::mutate(chart_unit = dplyr::if_else(department %in% top_units, department, "Other")) %>%
        dplyr::group_by(term, term_label, chart_unit) %>%
        dplyr::summarize(n_cancelled = sum(n_cancelled), .groups = "drop") %>%
        dplyr::arrange(term, dplyr::desc(n_cancelled), chart_unit)
    }

    make_reactable <- function(df, page_size = 50, columns = list(), full_width = TRUE) {
      if (is.null(df) || nrow(df) == 0) return(NULL)
      columns <- columns[names(columns) %in% names(df)]
      reactable::reactable(
        df,
        theme = cedar_tbl_theme,
        striped = TRUE,
        highlight = TRUE,
        compact = TRUE,
        fullWidth = full_width,
        defaultPageSize = page_size,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(25, 50, 100),
        columns = columns
      )
    }

    output$cn_cancelled_sections <- reactable::renderReactable({
      data <- cn_data()
      if (is.null(data)) return(NULL)
      display <- data$cancelled_sections %>%
        dplyr::select(dplyr::any_of(c(
          "campus", "college", "term_label", "department", "subject_course",
          "course_title", "section", "crn", "part_term", "delivery_method",
          "status", "enrolled", "capacity", "available", "canceled_on",
          "start_date", "days_before_start", "comments"
        )))
      make_reactable(display, columns = section_col_defs())
    })

    output$cn_common_courses <- reactable::renderReactable({
      data <- cn_data()
      if (is.null(data)) return(NULL)
      make_reactable(data$common_courses, page_size = 25, columns = common_course_col_defs())
    })

    output$cn_trends_table <- reactable::renderReactable({
      data <- cn_data()
      if (is.null(data)) return(NULL)
      make_reactable(
        build_trend_chart_data(data$trends),
        page_size = 25,
        columns = trend_col_defs(),
        full_width = FALSE
      )
    })

    output$cn_filter_summary <- renderUI({
      data <- cn_data()
      if (is.null(data)) {
        return(div(class = "scope-bar scope-bar--stacked scope-bar-placeholder",
                   "Run cancellations to see the current timing scope."))
      }

      summary <- data$timing_summary
      if (is.null(summary) || nrow(summary) == 0) {
        summary <- tibble::tibble(
          total_cancelled = nrow(data$cancelled_sections),
          parsed_cancel_date = 0L,
          missing_cancel_date = 0L,
          missing_start_date = 0L,
          missing_census_date = 0L,
          missing_timing_reference = 0L,
          timing_window_0_100 = 0L,
          earlier_than_100_days = data$timing_omitted %||% 0L,
          after_start = 0L,
          parse_rate = NA_real_
        )
      }
      distinct_courses <- nrow(data$common_courses %||% tibble::tibble())
      rs <- data$status_note
      removed <- rs$n_sections[rs$status == "R"]
      suspended <- rs$n_sections[rs$status == "S"]
      parse_rate <- if (is.na(summary$parse_rate)) "n/a" else paste0(round(summary$parse_rate * 100, 1), "%")
      div(class = "scope-bar scope-bar--stacked",
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Count scope:"),
          tags$span(class = "rs-stripe-val", summary$total_cancelled),
          tags$span("status C section rows"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(class = "rs-stripe-val", distinct_courses),
          tags$span("course groups"),
          div(class = "rs-stripe-right",
            tags$span(class = "rs-stripe-label", "Not included:"),
            tags$span(class = "rs-stripe-val", removed),
            tags$span("R"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-stripe-val", suspended),
            tags$span("S")
          )
        ),
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Timing plot:"),
          tags$span(class = "rs-stripe-val", summary$timing_window_0_100),
          tags$span("rows 0-100 days before start"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(class = "rs-stripe-val", summary$parsed_cancel_date),
          tags$span("parsed dates"),
          tags$span("·", class = "rs-stripe-sep"),
          tags$span(class = "rs-stripe-val", summary$missing_cancel_date),
          tags$span("missing cancel date"),
          div(class = "rs-stripe-right",
            tags$span(class = "rs-stripe-label", "Excluded from timing:"),
            tags$span(class = "rs-stripe-val", summary$earlier_than_100_days),
            tags$span(">100 days"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-stripe-val", summary$after_start),
            tags$span("after start"),
            tags$span("·", class = "rs-stripe-sep"),
            tags$span(class = "rs-stripe-val", summary$missing_timing_reference),
            tags$span("missing timing date")
          )
        ),
        div(class = "rs-stripe-row",
          tags$span(class = "rs-stripe-label", "Method:"),
          tags$span(
            paste0(
              "status C section/CRN rows only; R/S are excluded · ",
              "timing uses parsed comments vs start_date, falling back to census1 · ",
              "parsed coverage ", parse_rate, " · trends ignore exact term codes"
            ),
            class = "rs-stripe-thresholds"
          )
        )
      )
    })

    output$cn_dept_term_plot <- renderPlot({
      data <- cn_data()
      if (is.null(data) || nrow(data$by_department_term) == 0) return(NULL)
      term_levels <- data$by_department_term %>%
        dplyr::arrange(term) %>%
        dplyr::distinct(term_label) %>%
        dplyr::pull(term_label)
      ggplot2::ggplot(data$by_department_term,
                      ggplot2::aes(x = factor(term_label, levels = term_levels),
                                   y = n_cancelled)) +
        ggplot2::geom_col(fill = "#5F7C8A") +
        ggplot2::facet_wrap(~ department, scales = "free_y", ncol = 4) +
        ggplot2::scale_y_continuous(breaks = scales::breaks_width(1)) +
        ggplot2::labs(x = NULL, y = "Cancelled sections") +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
                       panel.grid.minor = ggplot2::element_blank())
    }, height = 520)

    output$cn_trends_plot <- plotly::renderPlotly({
      data <- cn_data()
      if (is.null(data) || nrow(data$trends) == 0) return(NULL)

      term_levels <- data$trends %>%
        dplyr::arrange(term) %>%
        dplyr::distinct(term_label) %>%
        dplyr::pull(term_label) %>%
        unname()

      top_units <- data$trends %>%
        dplyr::group_by(department) %>%
        dplyr::summarize(total_cancelled = sum(n_cancelled), .groups = "drop") %>%
        dplyr::arrange(dplyr::desc(total_cancelled), department) %>%
        dplyr::slice_head(n = 10) %>%
        dplyr::pull(department) %>%
        unname()

      other_details <- data$trends %>%
        dplyr::filter(!department %in% top_units) %>%
        dplyr::arrange(term, dplyr::desc(n_cancelled), department) %>%
        dplyr::group_by(term, term_label) %>%
        dplyr::summarize(
          other_units = dplyr::n_distinct(department),
          other_detail = paste(
            paste0(department, ": ", n_cancelled),
            collapse = "<br>"
          ),
          .groups = "drop"
        )

      plot_data <- build_trend_chart_data(data$trends) %>%
        dplyr::left_join(other_details, by = c("term", "term_label")) %>%
        dplyr::mutate(
          term_label = factor(term_label, levels = term_levels),
          hover_text = dplyr::if_else(
            chart_unit == "Other",
            paste0(
              "Term: ", term_label,
              "<br>Unit: Other",
              "<br>Cancelled sections: ", n_cancelled,
              "<br>Grouped units: ", dplyr::coalesce(other_units, 0L),
              dplyr::if_else(
                is.na(other_detail) | other_detail == "",
                "",
                paste0("<br><br>", other_detail)
              )
            ),
            paste0(
              "Term: ", term_label,
              "<br>Unit: ", chart_unit,
              "<br>Cancelled sections: ", n_cancelled
            )
          )
        )

      unit_levels <- plot_data %>%
        dplyr::group_by(chart_unit) %>%
        dplyr::summarize(total_cancelled = sum(n_cancelled), .groups = "drop") %>%
        dplyr::arrange(chart_unit == "Other", dplyr::desc(total_cancelled), chart_unit) %>%
        dplyr::pull(chart_unit) %>%
        unname()

      palette <- c(
        "#3F5E4B", "#4D6FA8", "#8A6F5F", "#6F8B78", "#A15D4E",
        "#6B4A2A", "#7A8A80", "#344D77", "#C7A96B", "#5F7C8A",
        "#B9B3A8"
      )
      colors <- as.list(unname(palette[seq_along(unit_levels)]))
      names(colors) <- unit_levels

      p <- plotly::plot_ly()
      for (unit in unit_levels) {
        unit_data <- plot_data %>% dplyr::filter(chart_unit == unit)
        p <- plotly::add_bars(
          p,
          data = unit_data,
          x = ~term_label,
          y = ~n_cancelled,
          name = unit,
          hovertext = ~hover_text,
          hoverinfo = "text",
          textposition = "none",
          marker = list(color = unname(colors[[unit]]))
        )
      }

      plotly::layout(
        p,
        barmode = "stack",
        xaxis = list(title = "Terms", categoryorder = "array", categoryarray = term_levels),
        yaxis = list(title = "Cancelled sections"),
        legend = list(title = list(text = "Unit")),
        margin = list(l = 55, r = 20, t = 10, b = 80),
        hoverlabel = list(align = "left"),
        annotations = list(list(
          text = "Trend view ignores specific term-code filters; Fall, Spring, and Summer filters are retained. Units outside the top ten are grouped as Other.",
          x = 0,
          y = -0.22,
          xref = "paper",
          yref = "paper",
          showarrow = FALSE,
          xanchor = "left",
          align = "left",
          font = list(size = 11, color = "#555")
        ))
      )
    })

    output$cn_timing_plot <- renderPlot({
      data <- cn_data()
      if (is.null(data) || nrow(data$timing) == 0) return(NULL)
      ggplot2::ggplot(data$timing,
                      ggplot2::aes(x = days_before_start, y = n_cancelled)) +
        ggplot2::geom_col(fill = "#8A6F5F") +
        ggplot2::geom_vline(xintercept = 0, color = "#9D2B2B", linewidth = 0.8) +
        ggplot2::facet_wrap(~ department, scales = "free_y", ncol = 4) +
        ggplot2::scale_x_continuous(limits = c(0, 100), expand = ggplot2::expansion(mult = c(0, 0.04))) +
        ggplot2::labs(
          x = "Days before course start",
          y = "Cancelled sections",
          caption = "Timing view includes only cancellations from 0 to 100 days before course start."
        ) +
        ggplot2::theme_minimal(base_size = 12) +
        ggplot2::theme(
          panel.grid.minor = ggplot2::element_blank(),
          plot.caption = ggplot2::element_text(color = "#555", hjust = 0)
        )
    }, height = 520)

    output$cn_output <- renderUI({
      if (!cn_has_run()) {
        return(empty_state("Set filters and click Find Cancellations to view cancelled sections."))
      }
      data <- cn_data()
      if (is.null(data)) return(NULL)
      no_cancelled_sections <- nrow(data$cancelled_sections) == 0
      no_trends <- is.null(data$trends) || nrow(data$trends) == 0
      no_data_callout <- div(
        class = "alert-box alert-box--info",
        tags$strong("No data"),
        tags$p(class = "mt-1 mb-0",
               "There are no cancelled sections for the selected filter criteria.")
      )
      if (no_cancelled_sections && no_trends) {
        return(tagList(
          no_data_callout
        ))
      }
      tagList(
        if (no_cancelled_sections) no_data_callout,
        tabsetPanel(
          tabPanel("Cancelled Sections", reactable::reactableOutput(session$ns("cn_cancelled_sections"))),
          tabPanel("By Department", plotOutput(session$ns("cn_dept_term_plot"))),
          tabPanel("Timing", plotOutput(session$ns("cn_timing_plot"))),
          tabPanel("Common Courses", reactable::reactableOutput(session$ns("cn_common_courses"))),
          tabPanel("Trends",
            plotly::plotlyOutput(session$ns("cn_trends_plot"), height = "480px"),
            reactable::reactableOutput(session$ns("cn_trends_table"))
          )
        )
      )
    })

    cedar_copy_url_observer(input, session, "cn_copy_url", spec_title = "Cancellations",
      values_fn = function() list(
        campus  = input$cn_campus,
        college = input$cn_college,
        dept    = input$cn_dept,
        term    = input$cn_term,
        pt      = input$cn_pt,
        im      = input$cn_im,
        level   = input$cn_level
      ))

    observeEvent(input$cn_button, {
      if (is.null(input$cn_term) || length(input$cn_term) == 0) {
        showNotification("Please select at least one term before finding cancellations.",
                         type = "warning", duration = 5)
        return()
      }

      cn_has_run(TRUE)
      log_report_generation(session, "cancellations", list(
        campus  = input$cn_campus,
        college = input$cn_college,
        dept    = input$cn_dept,
        term    = input$cn_term,
        pt      = input$cn_pt,
        im      = input$cn_im,
        level   = input$cn_level
      ))

      timer <- start_report_timer("cancellations", list(
        dept = input$cn_dept,
        term = input$cn_term
      ))

      tryCatch({
        opt <- list(
          course_campus  = input$cn_campus,
          course_college = input$cn_college,
          dept           = input$cn_dept,
          term           = input$cn_term,
          pt             = input$cn_pt,
          im             = input$cn_im,
          level          = input$cn_level
        )
        result <- get_cancellations(sections, opt)
        cn_data(result)
        duration_sec <- end_report_timer(timer)
        signal_load_complete(session, id, duration_sec = duration_sec)
      }, error = function(e) {
        if (is.function(error_handler)) {
          error_handler(e, "cancellations", NULL)
        } else {
          message("[cancellations] Error: ", conditionMessage(e))
          showModal(modalDialog(
            title = "Cancellations error",
            conditionMessage(e),
            easyClose = TRUE,
            footer = modalButton("Close")
          ))
        }
        tryCatch(end_report_timer(timer), error = function(te) {
          message("[cancellations] Error ending timer: ", te$message)
        })
        signal_load_complete(session, id, error = TRUE)
      })
    }, ignoreInit = TRUE)
  })
}
