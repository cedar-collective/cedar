# Shiny module for the read-only Registration > Projections workspace.
#
# The module consumes one validated saved bundle. All forecasting, aftcasting,
# model selection, and explanation logic lives below the module layer.

enrollment_projection_method_guide_ui <- function(guide) {
  method_rows <- function(methods) {
    do.call(tagList, lapply(seq_len(nrow(methods)), function(i) {
      tagList(
        tags$dt(methods$method_label[[i]]),
        tags$dd(
          tags$span(methods$basis[[i]]),
          tags$span(
            class = "enrollment-projection-method-distinction",
            methods$distinction[[i]]
          )
        )
      )
    }))
  }

  family_sections <- do.call(tagList, lapply(guide$families, function(family) {
    tags$section(
      class = "enrollment-projection-method-family",
      tags$h4(family$label),
      tags$p(family$description),
      tags$p(
        class = "enrollment-projection-method-selection",
        tags$strong("Selection use: "), family$selection_note
      ),
      tags$dl(
        class = "enrollment-projection-method-list",
        method_rows(family$methods)
      )
    )
  }))

  info_panel(
    "Projection methods",
    tags$p(guide$overview),
    family_sections,
    tags$p(
      tags$strong("How CEDAR manages the set. "),
      guide$selection_process
    ),
    cedar_docs_link(
      "users/enrollment-projections",
      label = "Full projection guide \u2192"
    ),
    description = guide$summary,
    class = "enrollment-projection-method-guide"
  )
}


enrollmentProjectionsUI <- function(id) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Enrollment Projections",
      paste(
        "Saved course-demand projections with confidence, planning guidance,",
        "and row-level evidence."
      ),
      fluidRow(
        column(
          3,
          selectInput(
            ns("group"), "Course group",
            choices = enrollment_projection_group_choices(),
            selected = "always_monitored"
          )
        ),
        column(
          3,
          selectizeInput(
            ns("department"), "Department", multiple = TRUE, choices = NULL
          )
        ),
        column(
          3,
          selectizeInput(
            ns("course"), "Course", multiple = TRUE, choices = NULL
          )
        ),
        column(
          2,
          selectInput(
            ns("confidence"), "Confidence", multiple = TRUE,
            choices = c("High", "Medium", "Low", "None")
          )
        ),
        column(
          1,
          tags$div(
            class = "enrollment-projection-export",
            downloadButton(
              ns("download"), label = NULL, icon = icon("download"),
              title = "Export filtered projections",
              class = "btn-outline-secondary btn-sm"
            )
          )
        )
      ),
      filter_scope_stripe(uiOutput(ns("scope"))),
      class = "enrollment-projection-filters"
    ),
    uiOutput(ns("bundle_status")),
    info_panel(
      "How projections work and how to read the table",
      tags$p(
        tags$strong("Methodology. "),
        paste(
          "These saved Spring demand projections cover the pooled Albuquerque",
          "and online course market. Projection targets the class-list first-day",
          "/ ever-registered proxy; expected census applies each course's",
          "historical retention."
        )
      ),
      tags$p(
        paste(
          "Upstream-anchored methods balance the prior same-season level with",
          "changed source populations. They split the estimate between prior",
          "same-term-type enrollment and a population, cohort, or feeder estimate,",
          "and are preferred when leakage-safe aftcasts are close to or better",
          "than a purely historical method."
        )
      ),
      tags$p(
        paste(
          "Confidence reflects aftcast accuracy, evidence volume, and stability",
          "across terms. Capacity limits and other structural conditions are",
          "reported separately because they qualify what that historical fit can",
          "establish. Upstream measures are observational indicators, not proof",
          "of a causal effect."
        )
      ),
      tags$p(tags$strong("Table columns"), class = "mb-1"),
      tags$ul(
        tags$li(tags$strong("Course / Dept"),
                " identifies the projected course and its academic department."),
        tags$li(tags$strong("Projection"),
                " is projected first-day / ever-registered class-list demand."),
        tags$li(tags$strong("Expected census"),
                " applies the course's historical census retention to the projection."),
        tags$li(tags$strong("Method"),
                " is the approach selected from leakage-safe historical aftcasts."),
        tags$li(tags$strong("Aftcast accuracy"),
                " summarizes comparable historical predictions and their error."),
        tags$li(tags$strong("Confidence"),
                " rates the evidence High, Medium, Low, or None."),
        tags$li(tags$strong("Why confidence"),
                " summarizes evidence volume, stability, and the most important qualification."),
        tags$li(tags$strong("Recent term columns"),
                " show first-day / ever-registered enrollment followed by scheduled sections for each of the four latest same-season terms; for example, 479 / 4 means 479 students across 4 sections."),
        tags$li(tags$strong("Planning sects"),
                paste(
                  "is projected demand divided by the target schedule's average",
                  "section size when available, otherwise the recent historical",
                  "median, rounded up. It is a planning conversion—not a forecast",
                  "of how many sections will actually be scheduled."
                ))
      ),
      tags$p(
        "Select a course for bias-correction, population-fit, capacity, and full method evidence."
      ),
      cedar_docs_link("users/enrollment-projections"),
      description = "Methodology, confidence, and a guide to every displayed column.",
      class = "enrollment-projection-guide"
    ),
    tags$div(
      id = ns("projection_table_anchor"),
      class = "enrollment-projection-table-anchor",
      tabindex = "-1"
    ),
    tags$div(
      class = "enrollment-projection-table-flow",
      reactable::reactableOutput(ns("projection_table"), height = NULL)
    ),
    uiOutput(ns("method_guide")),
    uiOutput(ns("detail"))
  )
}


enrollmentProjectionsServer <- function(id, bundle) {
  moduleServer(id, function(input, output, session) {
    bundle_value <- reactive({
      value <- if (shiny::is.reactive(bundle)) {
        bundle()
      } else if (is.function(bundle)) {
        bundle()
      } else {
        bundle
      }
      if (!is.null(value)) validate_enrollment_projection_bundle(value)
      value
    })

    observeEvent(bundle_value(), {
      value <- bundle_value()
      if (is.null(value)) return()
      choices <- enrollment_projection_filter_choices(
        value,
        list(group_id = input$group %||% "always_monitored")
      )
      updateSelectizeInput(
        session, "department", choices = choices$departments,
        selected = intersect(input$department %||% character(0), choices$departments),
        server = TRUE
      )
      updateSelectizeInput(
        session, "course", choices = choices$courses,
        selected = intersect(input$course %||% character(0), choices$courses),
        server = TRUE
      )
    }, ignoreNULL = FALSE)

    observeEvent(input$group, {
      value <- bundle_value()
      if (is.null(value)) return()
      choices <- enrollment_projection_filter_choices(
        value, list(group_id = input$group)
      )
      updateSelectizeInput(
        session, "department", choices = choices$departments,
        selected = intersect(input$department %||% character(0), choices$departments),
        server = TRUE
      )
    }, ignoreInit = TRUE)

    observeEvent(list(input$group, input$department), {
      value <- bundle_value()
      if (is.null(value)) return()
      choices <- enrollment_projection_filter_choices(
        value,
        list(group_id = input$group, departments = input$department)
      )
      updateSelectizeInput(
        session, "course", choices = choices$courses,
        selected = intersect(input$course %||% character(0), choices$courses),
        server = TRUE
      )
    }, ignoreInit = TRUE)

    view <- reactive({
      value <- bundle_value()
      req(!is.null(value))
      build_enrollment_projection_view(
        value,
        list(
          group_id = input$group %||% "always_monitored",
          departments = input$department,
          courses = input$course,
          confidence = input$confidence
        )
      )
    })

    confidence_cell <- function(value) {
      colors <- switch(
        value,
        High = c("#e4eee7", "#2d4336"),
        Medium = c("#edf0e2", "#4f5c2f"),
        Low = c("#f4e9d2", "#7a5010"),
        None = c("#f2e3de", "#7a2a1c"),
        c("#eeeeee", "#555555")
      )
      htmltools::span(
        value,
        style = paste0(
          "display:inline-block;padding:2px 6px;border-radius:3px;",
          "font-size:0.78rem;font-weight:600;background:", colors[[1]],
          ";color:", colors[[2]], ";"
        )
      )
    }

    output$bundle_status <- renderUI({
      if (!is.null(bundle_value())) return(NULL)
      empty_state("No validated enrollment projection bundle is available.")
    })

    output$scope <- renderUI({
      data <- view()
      provenance <- data$meta$model_provenance
      commit <- provenance$git_commit
      commit_label <- if (length(commit) == 1L && !is.na(commit)) {
        substr(commit, 1L, 8L)
      } else {
        "unavailable"
      }
      worktree_label <- if (isTRUE(provenance$relevant_worktree_dirty)) {
        "model files had uncommitted changes at build time"
      } else if (identical(provenance$relevant_worktree_dirty, FALSE)) {
        "model files matched the recorded Git commit"
      } else {
        "Git worktree status was unavailable"
      }
      model_note <- paste0(
        "Model ", data$meta$model_version, "; Git ", commit_label, "; ",
        worktree_label, ". Exact normalized model source is embedded in the saved bundle."
      )
      tagList(
        tags$div(
          class = "scope-bar",
          tags$strong(data$meta$target_term_label),
          " demand | Data window: ", data$meta$history_start_term_label,
          " through ", data$meta$as_of_term_label,
          " | ABQ + EA | ", data$meta$n_rows,
          paste0(" course", if (data$meta$n_rows == 1L) "" else "s"),
          " | model ", data$meta$model_version,
          tags$span(
            class = "enrollment-projection-model-info",
            title = model_note,
            `aria-label` = model_note,
            icon("circle-info")
          )
        )
      )
    })

    output$projection_table <- reactable::renderReactable({
      projection_view <- view()
      data <- projection_view$table
      if (nrow(data) == 0L) return(NULL)
      history_meta <- projection_view$meta$summary_history_columns
      history_column_names <- paste0("history_", 1:4)
      history_columns <- stats::setNames(
        lapply(history_column_names, function(column_name) {
          row <- history_meta[history_meta$name == column_name, , drop = FALSE]
          reactable::colDef(
            name = if (nrow(row) == 1L) row$header[[1]] else column_name,
            align = "right", minWidth = 105,
            show = nrow(row) == 1L,
            na = "—"
          )
        }),
        history_column_names
      )
      select_course <- htmlwidgets::JS(sprintf(
        paste0(
          "function(rowInfo) {",
          "rowInfo.toggleRowSelected(true);",
          "Shiny.setInputValue('%s', rowInfo.values.course, {priority: 'event'});",
          "}"
        ),
        session$ns("selected_course")
      ))
      reactable::reactable(
        data,
        theme = cedar_tbl_theme,
        compact = TRUE,
        striped = TRUE,
        highlight = TRUE,
        searchable = TRUE,
        selection = "single",
        onClick = select_course,
        pagination = FALSE,
        columns = c(list(
          course = reactable::colDef(
            name = "Course", minWidth = 95,
            cell = function(value) htmltools::strong(value)
          ),
          department = reactable::colDef(name = "Dept", maxWidth = 85),
          projected_demand = reactable::colDef(
            name = "Projection", align = "right", maxWidth = 95,
            format = reactable::colFormat(separators = TRUE, digits = 0)
          ),
          expected_census = reactable::colDef(
            name = "Expected census", align = "right", maxWidth = 115,
            format = reactable::colFormat(separators = TRUE, digits = 0)
          ),
          planning_sections = reactable::colDef(
            name = "Planning sects", align = "right", maxWidth = 105,
            header = htmltools::span(
              "Planning sects",
              title = paste(
                "Projected demand divided by target average section size,",
                "or recent median section size when the target schedule is unavailable"
              )
            ),
            format = reactable::colFormat(separators = TRUE, digits = 0),
            na = "—"
          ),
          method = reactable::colDef(name = "Method", minWidth = 130),
          aftcast_accuracy = reactable::colDef(
            name = "Aftcast accuracy", minWidth = 115
          ),
          confidence = reactable::colDef(
            name = "Confidence", maxWidth = 95, cell = confidence_cell
          ),
          confidence_reason = reactable::colDef(show = FALSE),
          confidence_brief = reactable::colDef(
            name = "Why confidence", minWidth = 240
          ),
          confidence_explanation = reactable::colDef(show = FALSE),
          demand_signal = reactable::colDef(show = FALSE),
          why_uncertain = reactable::colDef(show = FALSE)
        ), history_columns)
      )
    })

    output$method_guide <- renderUI({
      enrollment_projection_method_guide_ui(view()$method_guide)
    })

    selected_course_value <- reactiveVal(NULL)

    observeEvent(input$selected_course, {
      selected_course_value(input$selected_course)
    })

    observeEvent(input$back_to_table, {
      reactable::updateReactable(
        "projection_table", selected = NA, session = session
      )
      selected_course_value(NULL)
    })

    selected_course <- reactive({
      data <- view()$table
      index <- reactable::getReactableState("projection_table", "selected")
      if (!is.null(index) && length(index) == 1L && index <= nrow(data)) {
        return(data$course[[index]])
      }
      course <- selected_course_value()
      if (is.null(course) || !course %in% data$course) return(NULL)
      course
    })

    detail <- reactive({
      enrollment_projection_course_detail(view(), selected_course())
    })

    output$detail <- renderUI({
      data <- detail()
      if (is.null(data)) {
        return(empty_state("Select a projection row to inspect its evidence."))
      }
      current <- data$current
      table_anchor <- session$ns("projection_table_anchor")
      table_target <- session$ns("projection_table")
      back_input <- session$ns("back_to_table")
      tagList(
        hr(class = "mt-4 mb-3"),
        tags$a(
          href = paste0("#", table_anchor),
          class = "enrollment-projection-back",
          title = "Return to the projection table",
          onclick = sprintf(paste0(
            "event.preventDefault();",
            "Shiny.setInputValue('%s',Date.now(),{priority:'event'});",
            "history.replaceState(null,'','#%s');",
            "setTimeout(function(){",
            "var target=document.getElementById('%s');",
            "var anchor=document.getElementById('%s');",
            "if(target){target.scrollIntoView({behavior:'smooth',block:'start'});}",
            "if(anchor){anchor.focus({preventScroll:true});}",
            "},350);"
          ), back_input, table_anchor, table_target, table_anchor),
          icon("arrow-up"),
          tags$span("Back to projection table")
        ),
        section_heading(paste(current$subject_course, "projection evidence")),
        tags$dl(
          class = "enrollment-projection-summary",
          tags$dt("Selected method"), tags$dd(current$method_label),
          tags$dt("Why selected"), tags$dd(current$selection_reason),
          tags$dt("Upstream change"),
          tags$dd(
            if (current$method_role[[1]] == "anchored_upstream") {
              dplyr::coalesce(
                current$component_summary,
                "Upstream component detail is unavailable"
              )
            } else {
              "No upstream adjustment in the selected method"
            }
          ),
          tags$dt("Confidence"), tags$dd(current$confidence),
          tags$dt("Why confidence"), tags$dd(current$confidence_explanation),
          tags$dt("Estimated sections"),
          tags$dd(
            if (is.na(current$recommended_sections)) "Unavailable" else
              format(current$recommended_sections, big.mark = ",")
          ),
          tags$dt("Planning recommendation"), tags$dd(current$recommendation),
          tags$dt("Bias correction"), tags$dd(current$bias_correction),
          tags$dt("Population fit"),
          tags$dd(paste(current$coupling_status, current$coupling_reason, sep = ": ")),
          tags$dt("Demand signal"), tags$dd(current$demand_note),
          tags$dt("Capacity check"), tags$dd(current$capacity_limit_note)
        ),
        section_heading("Historical methods and enrollment lifecycle", level = "h3"),
        tags$div(
          class = "alert-box alert-box--info",
          tags$strong("What is being compared"),
          "The lines recreate each forecasting method for prior ",
          switch(
            current$term_type[[1]],
            spring = "Spring", summer = "Summer", fall = "Fall",
            "same-term-type"
          ),
          " terms only. Each upstream-anchored line is a fixed blend with prior ",
          "same-term-type enrollment. Method choice and confidence use ",
          dplyr::if_else(
            current$selection_uses_uncensored[[1]],
            "unconstrained-term WAPE", "all-term WAPE"
          ), " against the ",
          tags$strong("first day / ever registered proxy"),
          paste(
            ": unique non-waitlisted students found in the class-list extract.",
            "It is not a frozen first-day roster. Census (registered plus late",
            "drops) and final/last day (still registered) are shown for lifecycle context."
          )
        ),
        plotly::plotlyOutput(
          session$ns("method_history_plot"), height = "450px", fill = FALSE
        ),
        section_heading("Recent same-season evidence", level = "h3"),
        reactable::reactableOutput(session$ns("history_table")),
        info_panel(
          "Enrollment movement diagnostic",
          tags$p(tags$strong("Schedule relationship. "),
                 data$movement$schedule_summary),
          tags$p(tags$strong("Upstream enrollment. "),
                 data$movement$upstream_summary),
          tags$p(tags$strong("DFW and repeat pressure. "),
                 data$movement$dfw_summary),
          tags$p(class = "text-muted", data$movement$caveat),
          reactable::reactableOutput(session$ns("movement_table")),
          description = paste(
            "Compares course enrollment with capacity, preceding-term",
            "university enrollment, incoming freshmen, and course DFW pressure."
          ),
          class = "enrollment-projection-movement"
        ),
        section_heading("Candidate methods", level = "h3"),
        reactable::reactableOutput(session$ns("candidate_table"))
      )
    })

    output$method_history_plot <- plotly::renderPlotly({
      data <- detail()
      req(!is.null(data), nrow(data$method_history) > 0L)
      build_enrollment_projection_method_history_plot(
        data$method_history,
        selected_method_id = data$current$method_id[[1]]
      )
    })

    output$movement_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$movement$data) > 0L)
      reactable::reactable(
        data$movement$data,
        theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          term = reactable::colDef(name = "Term", minWidth = 95),
          enrollment = reactable::colDef(name = "Enrollment", align = "right"),
          enrollment_change = reactable::colDef(
            name = "Δ enrl", align = "right",
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          sections = reactable::colDef(name = "Sects", align = "right"),
          capacity = reactable::colDef(name = "Capacity", align = "right"),
          capacity_change = reactable::colDef(
            name = "Δ cap", align = "right",
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          source_term = reactable::colDef(name = "Upstream term", minWidth = 105),
          university_students = reactable::colDef(
            name = "University students", align = "right", minWidth = 125
          ),
          university_change = reactable::colDef(
            name = "Δ university", align = "right", minWidth = 105,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          incoming_first_sem = reactable::colDef(
            name = "Incoming freshmen", align = "right", minWidth = 125
          ),
          incoming_change = reactable::colDef(
            name = "Δ incoming", align = "right", minWidth = 100,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          market_students = reactable::colDef(
            name = "Market students", align = "right", minWidth = 110
          ),
          market_change = reactable::colDef(
            name = "Δ market", align = "right", minWidth = 90,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          prior_term_dfw = reactable::colDef(
            name = "Prior-term DFW (n / rate)", minWidth = 155,
            align = "right"
          ),
          dfw_repeaters = reactable::colDef(
            name = "Next-term repeaters (n / share)", minWidth = 185,
            align = "right"
          ),
          context = reactable::colDef(name = "Reading", minWidth = 235)
        )
      )
    })

    output$history_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$history) > 0L)
      table <- data$history %>%
        dplyr::transmute(
          term = history_term_label,
          aftcast = round(aftcast_classlist_total),
          raw_error = aftcast_pct_error,
          assessment = dplyr::case_when(
            !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "No aftcast",
            dplyr::coalesce(aftcast_capacity_censored, FALSE) ~ "Capacity-bounded",
            TRUE ~ "Observed"
          ),
          first_day_proxy = round(actual_classlist_total),
          census = round(actual_census),
          final = round(actual_final_enrollment),
          sections = scheduled_sections,
          capacity = round(scheduled_capacity),
          registration_fill,
          potential_explanation = potential_miss_explanation
        )
      reactable::reactable(
        table, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          term = reactable::colDef(name = "Term", minWidth = 95),
          aftcast = reactable::colDef(name = "Aftcast", align = "right"),
          raw_error = reactable::colDef(
            name = "Raw error", align = "right",
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          assessment = reactable::colDef(name = "Assessment", minWidth = 115),
          first_day_proxy = reactable::colDef(
            name = "First day / ever registered", align = "right",
            minWidth = 155
          ),
          census = reactable::colDef(name = "Census", align = "right"),
          final = reactable::colDef(name = "Final / last day", align = "right"),
          sections = reactable::colDef(name = "Sections", align = "right"),
          capacity = reactable::colDef(name = "Capacity", align = "right"),
          registration_fill = reactable::colDef(
            name = "Fill", align = "right",
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          potential_explanation = reactable::colDef(
            name = "Potential explanation", minWidth = 270
          )
        )
      )
    })

    output$candidate_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$candidates) > 0L)
      table <- data$candidates %>%
        dplyr::transmute(
          method = method_label,
          role = dplyr::recode(
            method_role,
            observed_enrollment = "Observed enrollment",
            structural_demand = "Upstream indicator",
            anchored_upstream = "Upstream-anchored"
          ),
          projection = round(projected_classlist_total),
          aftcasts = n_backtests,
          all_term_wape = wape,
          uncapped_wape = uncensored_wape,
          selected,
          applicable,
          upstream_change = dplyr::coalesce(component_summary, "—"),
          evidence = applicability_reason
        )
      reactable::reactable(
        table, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          method = reactable::colDef(name = "Method", minWidth = 150),
          role = reactable::colDef(name = "Role", minWidth = 125),
          projection = reactable::colDef(name = "Projection", align = "right"),
          aftcasts = reactable::colDef(name = "Aftcasts", align = "right"),
          all_term_wape = reactable::colDef(
            name = "All-term WAPE", align = "right", minWidth = 115,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          uncapped_wape = reactable::colDef(
            name = "Uncapped WAPE", align = "right", minWidth = 115,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          selected = reactable::colDef(name = "Selected", maxWidth = 80),
          applicable = reactable::colDef(name = "Usable", maxWidth = 70),
          upstream_change = reactable::colDef(
            name = "Upstream change / components", minWidth = 280
          ),
          evidence = reactable::colDef(name = "Evidence", minWidth = 260)
        )
      )
    })

    output$download <- downloadHandler(
      filename = function() {
        paste0(
          "cedar-enrollment-projections-", view()$meta$target_term, ".csv"
        )
      },
      content = function(file) {
        utils::write.csv(view()$table, file, row.names = FALSE, na = "")
      }
    )

    invisible(list(view = view, selected_course = selected_course, detail = detail))
  })
}
