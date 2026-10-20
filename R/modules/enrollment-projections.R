# Shiny module for the read-only Registration > Projections workspace.
#
# The module consumes one validated saved bundle at a time, chosen by target
# term: CEDAR publishes one bundle per season, and neither supersedes the other.
# Discovery and loading are injected -- the module owns no paths and no file I/O.
# All forecasting, aftcasting, model selection, and explanation logic lives below
# the module layer.

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
  defaults <- enrollment_projection_defaults()
  bump_share <- scales::percent(defaults$pressure_bump_share, accuracy = 1)
  bump_decline <- scales::percent(defaults$pressure_bump_feeder_decline, accuracy = 1)
  tagList(
    filter_bar(
      "Enrollment Projections",
      paste(
        "Saved course-demand projections with stability, evidence depth,",
        "aftcast accuracy, planning guidance, and row-level detail."
      ),
      fluidRow(
        column(
          2,
          selectInput(ns("target_term"), "Target term", choices = NULL)
        ),
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
          2,
          selectizeInput(
            ns("course"), "Course", multiple = TRUE, choices = NULL
          )
        ),
        column(
          2,
          selectInput(
            ns("stability"), "Stability", multiple = TRUE,
            choices = c("Stable", "Moderate", "Volatile", "Unrated")
          )
        ),
        column(
          2,
          selectInput(
            ns("accuracy"), "Aftcast accuracy", multiple = TRUE,
            choices = c("Close", "Fair", "Poor", "Unrated")
          )
        )
      ),
      checkboxInput(
        ns("attention_only"),
        "Only courses that need a look: near full last term, a big Fall change, or past forecasts more than 20% off",
        value = FALSE
      ),
      filter_scope_stripe(uiOutput(ns("scope"))),
      class = "enrollment-projection-filters"
    ),
    uiOutput(ns("bundle_status")),
    tags$p(
      class = "enrollment-projection-lead",
      paste(
        "Each row plans one course for the target term. Sections are planned",
        "for registrations, which start from last year's same-term",
        "registrations; a course that is always full gets a pressure bump on",
        "top, and a course whose enrollment moved sharply in the term just",
        "finished is flagged for a look. The range is where past forecasts",
        "for that course usually landed."
      )
    ),
    info_panel(
      "How projections work and how to read the table",
      cedar_definition_note("enrollment-projection"),
      tags$p(tags$strong("Table columns"), class = "mb-1"),
      tags$ul(
        tags$li(tags$strong("Course"),
                " with its academic department beneath."),
        tags$li(tags$strong("Sections"),
                paste(
                  " to plan: registrations plus any pressure bump, divided by",
                  "the section size (the target schedule's average, otherwise",
                  "the recent median), rounded up. It is a planning conversion,",
                  "not a forecast of what will be scheduled. A course that",
                  "filled its seats last term reads as a floor."
                )),
        tags$li(tags$strong("Pressure bump"),
                paste(
                  " is what the plan adds for a course near full on the first",
                  "day in every recent same-season term with a first-day count:",
                  "its registrations were capped by its seats, so it is planned",
                  "for", bump_share, "more than last time, or for the students",
                  "left waiting if that is more, unless its feeder courses just",
                  "fell", bump_decline, "or more. When near-full courses were",
                  "given 10% or more seats, the new seats filled. Beneath it,",
                  "the sections the bump adds. The registration forecast and",
                  "its accuracy do not include it."
                )),
        tags$li(tags$strong("Registrations"),
                paste(
                  " is everyone expected to sign up, including students who",
                  "drop before or after classes begin: the class-list demand",
                  "the model forecasts, and the number sections are planned",
                  "for. It runs above first-day seats, and that margin is",
                  "deliberate: running short of seats costs more than an",
                  "empty one. Beneath it, the range past forecasts for this",
                  "course usually landed in and the change on the last",
                  "same-season term's registrations."
                )),
        tags$li(tags$strong("Seats (day 1)"),
                paste(
                  " is how many students are expected to hold a seat when",
                  "classes begin: registrations times the share of this",
                  "course's registrants still enrolled on the first day in",
                  "recent terms. It is context, not the planning number."
                )),
        tags$li(tags$strong("First day / sections"),
                paste(
                  " shows the last four same-season terms: students enrolled on",
                  "the first day over the sections scheduled. A dash means the",
                  "course was not offered, or that term's class lists carry no",
                  "status dates to reconstruct the first day from; hover for",
                  "which."
                )),
        tags$li(tags$strong("Flags"),
                " are plain-language reasons to look at a row: full on the first day last term, students left waiting, a big change in the term just finished, a volatile history, or past forecasts that were well off."),
        tags$li(tags$strong("Stability"),
                paste(
                  " asks whether the course is predictable from its own history",
                  "at all, using no model: Stable, Moderate, Volatile, or",
                  "Unrated when too few comparable terms exist. A Volatile",
                  "course is not a forecasting failure — it is a course where",
                  "something is moving and worth investigating."
                )),
        tags$li(tags$strong("Depth"),
                paste(
                  " is how much comparable aftcast evidence stands behind the",
                  "selected method: Deep, Moderate, Thin, or None. It says how",
                  "much we know, not how good we are."
                )),
        tags$li(tags$strong("Accuracy"),
                paste(
                  " is how close those aftcasts landed: Close, Fair, Poor, or",
                  "Unrated when there are too few to measure. The selection",
                  "rule is replayed at each past term with only the evidence",
                  "available then, so this is an out-of-sample record, not",
                  "the fit of the winner on the terms that chose it."
                ))
      ),
      tags$p(
        paste(
          "Click a course for its method: prior same-season enrollment (the",
          "spine) unless the adjusted candidate beat it by a margin on earlier",
          "aftcasts. The adjusted candidate raises the spine to a floor when",
          "the prior term was full on the first day and adds the change in the",
          "course's own and its feeder courses' enrollment in the term just",
          "finished."
        )
      ),
      tags$p(
        paste(
          "Whether seats were full is judged on the first day of classes,",
          "reconstructed from each student's registration and drop dates;",
          "a course counts as full at 98% of its seats. Census, on the 15th",
          "day of classes, follows three weeks of drops, so a course full on",
          "day one can read below capacity at census. Terms whose class lists carry no status",
          "dates are shown as unknown, never filled in from census."
        )
      ),
      cedar_docs_link("users/enrollment-projections"),
      description = "Methodology, the three evidence axes, and a guide to every displayed column.",
      class = "enrollment-projection-guide"
    ),
    navset_tab(
      id = ns("projection_tabs"),
      selected = "Projections",

      nav_panel(
        "Projections",
        subtab_header(
          "Projections",
          paste(
            "One published projection per course for the selected target term,",
            "with the evidence behind it. Click a course for its floor, Fall",
            "deltas, capacity, and full method evidence."
          )
        ),
        uiOutput(ns("pressure_summary")),
        tags$div(
          class = "enrollment-projection-table-flow cedar-clickable-rows",
          reactable::reactableOutput(ns("projection_table"), height = NULL)
        ),
        uiOutput(ns("method_guide"))
      ),

      nav_panel(
        "Scenario",
        subtab_header(
          "Population growth scenario",
          paste(
            "Grows one student population and reads the effect on the courses",
            "it takes. The first year is the published projection above;",
            "later years are arithmetic on it, not forecasts."
          )
        ),
        fluidRow(
          column(
            3,
            selectInput(
              ns("scenario_population"), "Population",
              choices = population_group_choices(),
              selected = population_group_default("scenario")
            )
          ),
          column(
            2,
            numericInput(
              ns("scenario_growth"), "Annual growth (%)",
              value = 10, min = -50, max = 100, step = 1
            )
          ),
          column(
            2,
            sliderInput(
              ns("scenario_horizon"), "Years", min = 2, max = 10,
              value = 5, step = 1, ticks = FALSE
            )
          ),
          column(
            3,
            selectInput(
              ns("scenario_measure"), "Show",
              choices = c(
                "Students" = "students",
                "Sections needed" = "sections",
                "Additional sections" = "additional"
              )
            )
          ),
          column(
            2,
            tags$div(
              class = "enrollment-projection-export",
              downloadButton(
                ns("scenario_download"), label = NULL, icon = icon("download"),
                title = "Export the scenario table",
                class = "btn-outline-secondary btn-sm"
              )
            )
          )
        ),
        uiOutput(ns("scenario_assumption")),
        tags$div(
          class = "enrollment-projection-table-flow",
          reactable::reactableOutput(ns("scenario_table"), height = NULL)
        ),
        uiOutput(ns("scenario_excluded"))
      )
    )
  )
}


enrollmentProjectionsServer <- function(id, bundles, load_bundle, programs) {
  moduleServer(id, function(input, output, session) {
    saved_bundles <- reactive({
      if (shiny::is.reactive(bundles) || is.function(bundles)) bundles() else bundles
    })

    # The reader picks a season. The nearest target is selected by default: it
    # is the term a schedule is being built for now.
    observeEvent(saved_bundles(), {
      saved <- saved_bundles()
      if (is.null(saved) || nrow(saved) == 0L) {
        updateSelectInput(session, "target_term", choices = character(0))
        return()
      }
      saved <- saved[order(saved$target_term), , drop = FALSE]
      choices <- stats::setNames(
        as.character(saved$target_term), fmt_term(saved$target_term)
      )
      selected <- if (isTRUE(input$target_term %in% choices)) {
        input$target_term
      } else {
        choices[[1]]
      }
      updateSelectInput(session, "target_term", choices = choices, selected = selected)
    }, ignoreNULL = FALSE)

    bundle_value <- reactive({
      saved <- saved_bundles()
      if (is.null(saved) || nrow(saved) == 0L) return(NULL)
      req(input$target_term)
      # A saved file that this build cannot read is an empty state, not a stack
      # trace. It happens for real: a deploy restarts the app on new code before
      # the bundles are rebuilt, so after a schema bump the page spends the whole
      # rebuild -- 38 minutes on the last one -- holding artifacts it will not
      # accept. The reader gets the ordinary "no bundle available" panel and one
      # notification saying why, rather than an error where the table belongs.
      tryCatch(
        {
          value <- load_bundle(as.integer(input$target_term))
          if (!is.null(value)) validate_enrollment_projection_bundle(value)
          value
        },
        error = function(e) {
          showNotification(
            paste0(
              "The saved projection for ", fmt_term(as.integer(input$target_term)),
              " cannot be read by this version of CEDAR: ", conditionMessage(e)
            ),
            type = "warning", duration = 12
          )
          NULL
        }
      )
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
          stability = input$stability,
          accuracy = input$accuracy,
          attention_only = isTRUE(input$attention_only)
        )
      )
    })

    # None/Unrated mean "not enough evidence", which is grey, never red: an
    # unmeasured course has not failed anything.
    axis_cell <- function(value) {
      tone <- switch(
        value,
        Stable = , Deep = , Close = "good",
        Moderate = , Fair = "mid",
        Thin = "thin",
        Volatile = , Poor = "poor",
        "none"
      )
      htmltools::span(
        value, class = paste0("projection-axis projection-axis--", tone)
      )
    }

    flag_cell <- function(value) {
      if (is.na(value) || !nzchar(value)) return("\u2014")
      flags <- strsplit(value, " | ", fixed = TRUE)[[1]]
      htmltools::tagList(lapply(flags, function(flag) {
        warn <- grepl("^Fall enrollment|^Past forecasts|Hard to predict", flag)
        htmltools::span(
          flag,
          class = paste(c("projection-flag", if (warn) "projection-flag--warn"),
                        collapse = " ")
        )
      }))
    }

    output$bundle_status <- renderUI({
      saved <- saved_bundles()
      # Short-circuits before bundle_value(), so an empty projections directory
      # reports itself rather than being blocked by the target-term req().
      if (!is.null(saved) && nrow(saved) > 0L && !is.null(bundle_value())) {
        return(NULL)
      }
      empty_state("No validated enrollment projection bundle is available.")
    })

    output$pressure_summary <- renderUI({
      tags$p(
        class = "enrollment-projection-lead",
        view()$meta$pressure_bump$sentence
      )
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
      season <- projection_view$meta$season_label
      history_terms <- projection_view$meta$summary_history_columns
      count_text <- function(value) {
        if (is.finite(value)) format(round(value), big.mark = ",") else "—"
      }
      # A row click opens the course's evidence in a modal over the table. The
      # table is unpaginated, and evidence rendered beneath it read as a click
      # that did nothing (reported twice); a modal also returns the reader to
      # the row they left.
      select_course <- htmlwidgets::JS(sprintf(
        paste0(
          "function(rowInfo) {",
          "Shiny.setInputValue('%s', rowInfo.values.course, {priority: 'event'});",
          "}"
        ),
        session$ns("selected_course")
      ))
      # Sized to fit a laptop-width window without horizontal scrolling: the
      # department sits under the course, the range and the change under the
      # registrations, and the method and its evidence in the modal.
      reactable::reactable(
        data,
        theme = cedar_tbl_theme,
        compact = TRUE,
        striped = TRUE,
        highlight = TRUE,
        searchable = TRUE,
        onClick = select_course,
        pagination = FALSE,
        columns = list(
          course = reactable::colDef(
            name = "Course", minWidth = 105,
            cell = function(value, index) {
              htmltools::tagList(
                htmltools::strong(value),
                htmltools::div(class = "text-note", data$department[[index]])
              )
            }
          ),
          department = reactable::colDef(show = FALSE, searchable = TRUE),
          planning_sections = reactable::colDef(
            name = "Sections", align = "right", minWidth = 75,
            header = htmltools::span(
              "Sections",
              title = paste(
                "Sections to plan: registrations plus any pressure bump,",
                "divided by the section size and rounded up; a floor when last",
                "term filled its seats"
              )
            ),
            format = reactable::colFormat(separators = TRUE, digits = 0),
            na = "—"
          ),
          pressure_bump = reactable::colDef(
            name = "Pressure bump", align = "right", minWidth = 90,
            header = htmltools::span(
              "Pressure bump",
              title = paste(
                "Registrations added to the plan because the course was near",
                "full on the first day in every recent same-season term, and",
                "the sections that adds. Click the course for why"
              )
            ),
            cell = function(value, index) {
              if (!isTRUE(value > 0)) return("—")
              added <- data$pressure_bump_sections[[index]]
              htmltools::tagList(
                paste0("+", count_text(value)),
                if (isTRUE(added > 0)) {
                  htmltools::div(
                    class = "text-note",
                    paste0("+", added, " section", if (added == 1L) "" else "s")
                  )
                }
              )
            }
          ),
          pressure_bump_sections = reactable::colDef(show = FALSE),
          pressure_bump_note = reactable::colDef(show = FALSE),
          projected_demand = reactable::colDef(
            name = "Registrations", align = "right", minWidth = 105,
            header = htmltools::span(
              "Registrations",
              title = paste(
                "Everyone expected to register, including students who later",
                "drop: the number sections are planned for. Beneath it, the",
                "range past forecasts for this course usually landed in and",
                "the change on last", season, "term"
              )
            ),
            cell = function(value, index) {
              change <- data$change_vs_last[[index]]
              htmltools::tagList(
                count_text(value),
                if (!is.na(data$demand_range[[index]])) {
                  htmltools::div(class = "text-note", data$demand_range[[index]])
                },
                if (is.finite(change)) {
                  htmltools::div(
                    class = "text-note",
                    sprintf("%+.0f%% vs last %s", 100 * change, season)
                  )
                }
              )
            }
          ),
          demand_range = reactable::colDef(show = FALSE),
          change_vs_last = reactable::colDef(show = FALSE),
          expected_first_day = reactable::colDef(
            name = "Seats (day 1)", align = "right", minWidth = 100,
            header = htmltools::span(
              "Seats (day 1)",
              title = paste(
                "Students expected to hold a seat when classes begin. Fewer",
                "than registrations, because a student who drops early frees",
                "a seat someone else takes"
              )
            ),
            cell = function(value, index) count_text(value)
          ),
          recent_first_day = reactable::colDef(
            name = paste("Last", season, "terms"), minWidth = 190,
            sortable = FALSE, searchable = FALSE,
            header = htmltools::tagList(
              htmltools::div(paste0(
                "First day / sections, last ", nrow(history_terms), " ", season, "s"
              )),
              htmltools::div(
                class = "projection-history-grid text-note",
                lapply(history_terms$abbr, htmltools::span)
              )
            ),
            cell = function(value, index) {
              sections <- data$recent_sections[[index]]
              htmltools::div(
                class = "projection-history-grid",
                title = data$recent_terms[[index]],
                lapply(seq_along(value), function(i) {
                  htmltools::span(
                    count_text(value[[i]]),
                    htmltools::span(
                      class = "text-note",
                      if (is.finite(sections[[i]])) paste(sections[[i]], "sec") else "—"
                    )
                  )
                })
              )
            }
          ),
          recent_sections = reactable::colDef(show = FALSE),
          recent_terms = reactable::colDef(show = FALSE),
          flags = reactable::colDef(name = "Flags", minWidth = 170, cell = flag_cell),
          attention = reactable::colDef(show = FALSE),
          stability = reactable::colDef(
            name = "Stability", minWidth = 85, cell = axis_cell
          ),
          stability_reason = reactable::colDef(show = FALSE),
          depth = reactable::colDef(
            name = "Depth", minWidth = 80, cell = axis_cell
          ),
          depth_reason = reactable::colDef(show = FALSE),
          accuracy = reactable::colDef(
            name = "Accuracy", minWidth = 85, cell = axis_cell
          ),
          accuracy_reason = reactable::colDef(show = FALSE),
          # The basis and its evidence are in the course modal.
          method = reactable::colDef(show = FALSE),
          selection_evidence = reactable::colDef(show = FALSE),
          summary_sentence = reactable::colDef(show = FALSE),
          axis_brief = reactable::colDef(show = FALSE),
          axis_explanation = reactable::colDef(show = FALSE),
          regime_alarm = reactable::colDef(show = FALSE),
          why_uncertain = reactable::colDef(show = FALSE)
        )
      )
    })

    output$method_guide <- renderUI({
      enrollment_projection_method_guide_ui(view()$method_guide)
    })

    selected_course_value <- reactiveVal(NULL)

    selected_course <- reactive({
      course <- selected_course_value()
      if (is.null(course) || !course %in% view()$table$course) return(NULL)
      course
    })

    detail <- reactive({
      enrollment_projection_course_detail(view(), selected_course())
    })

    # The evidence opens in a modal over the table. Its tables and plot are
    # ordinary outputs below, rendered from detail() once the modal binds them.
    observeEvent(input$selected_course, {
      selected_course_value(input$selected_course)
      data <- enrollment_projection_course_detail(view(), input$selected_course)
      if (is.null(data)) return()
      showModal(cedar_info_modal(
        paste(data$current$subject_course, "projection evidence"),
        projection_detail_ui(data),
        size = "xl"
      ))
    })

    projection_detail_ui <- function(data) {
      current <- data$current
      tags$div(
        id = session$ns("detail"),
        class = "enrollment-projection-detail",
        tags$p(class = "enrollment-projection-lead", current$summary_sentence),
        tags$dl(
          class = "enrollment-projection-summary",
          tags$dt("Selected method"), tags$dd(current$method_label),
          tags$dt("Why selected"), tags$dd(current$selection_reason),
          tags$dt("Adjusted candidate"),
          tags$dd(
            if (isTRUE(current$adjusted_applicable[[1]])) {
              paste0(
                format(round(current$adjusted_projection[[1]]), big.mark = ","),
                " (", current$adjusted_reason[[1]], ")"
              )
            } else {
              dplyr::coalesce(current$adjusted_reason[[1]], "Not applicable")
            }
          ),
          tags$dt("Stability"), tags$dd(current$stability),
          tags$dt("Depth"), tags$dd(current$depth),
          tags$dt("Aftcast accuracy"), tags$dd(current$accuracy),
          tags$dt("What this means"), tags$dd(current$axis_explanation),
          tags$dt("Estimated sections"),
          tags$dd(
            if (is.na(current$recommended_sections)) "Unavailable" else
              format(current$recommended_sections, big.mark = ",")
          ),
          tags$dt("Pressure bump"), tags$dd(current$pressure_bump_note),
          tags$dt("Planning recommendation"), tags$dd(current$recommendation),
          tags$dt("Saturation floor"), tags$dd(current$floor_note),
          tags$dt("Fall deltas"),
          tags$dd(dplyr::coalesce(current$adjusted_delta_basis, "Not available")),
          tags$dt("Regime check"), tags$dd(current$regime_note),
          tags$dt("Capacity check"), tags$dd(current$capacity_limit_note)
        ),
        section_heading("Recent same-season evidence", level = "h3"),
        reactable::reactableOutput(session$ns("history_table")),
        info_panel(
          "Analyst detail: methods, movement diagnostic, and candidates",
          tags$div(
          class = "alert-box alert-box--info",
          tags$strong("What is being compared"),
          "The lines recreate each forecasting method for prior ",
          switch(
            current$term_type[[1]],
            spring = "Spring", summer = "Summer", fall = "Fall",
            "same-term-type"
          ),
          " terms only. Method choice is rolling: at every past ",
          "term the rule saw only earlier aftcasts, and the accuracy shown is ",
          "the error of the method it would have published then, measured ",
          "against ",
          tags$strong("ever-registered demand"),
          paste(
            ": unique non-waitlisted students found in the class-list extract,",
            "including those who dropped. Whether the seats were full is judged",
            "on the first day of classes, reconstructed from registration and",
            "drop dates; it has gaps where the class lists carry no dates.",
            "Census (registered plus late drops) and final/last day (still",
            "registered) are shown for lifecycle context."
          )
        ),
        plotly::plotlyOutput(
          session$ns("method_history_plot"), height = "450px", fill = FALSE
        ),
        section_heading("Enrollment movement diagnostic", level = "h4"),
        tags$p(tags$strong("Schedule relationship. "),
               data$movement$schedule_summary),
        tags$p(tags$strong("Upstream enrollment. "),
               data$movement$upstream_summary),
        tags$p(tags$strong("DFW and repeat pressure. "),
               data$movement$dfw_summary),
        tags$p(class = "text-muted", data$movement$caveat),
        reactable::reactableOutput(session$ns("movement_table")),
        section_heading("Candidate methods", level = "h4"),
        reactable::reactableOutput(session$ns("candidate_table")),
          description = paste(
            "The method aftcast plot, the capacity and upstream movement",
            "diagnostic, and both candidates with their evidence."
          ),
          class = "enrollment-projection-movement"
        )
      )
    }

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
          enrollment_change = cedar_percent_coldef("Δ enrl"),
          sections = reactable::colDef(name = "Sects", align = "right"),
          capacity = reactable::colDef(name = "Capacity", align = "right"),
          capacity_change = cedar_percent_coldef("Δ cap"),
          source_term = reactable::colDef(name = "Upstream term", minWidth = 105),
          university_students = reactable::colDef(
            name = "University students", align = "right", minWidth = 125
          ),
          university_change = cedar_percent_coldef("Δ university", minWidth = 105),
          incoming_first_sem = reactable::colDef(
            name = "Incoming freshmen", align = "right", minWidth = 125
          ),
          incoming_change = cedar_percent_coldef("Δ incoming", minWidth = 100),
          market_students = reactable::colDef(
            name = "Market students", align = "right", minWidth = 110
          ),
          market_change = cedar_percent_coldef("Δ market", minWidth = 90),
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
          aftcast_method = dplyr::coalesce(aftcast_method_label, "—"),
          aftcast = round(aftcast_classlist_total),
          raw_error = aftcast_pct_error,
          assessment = dplyr::case_when(
            !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "No aftcast",
            dplyr::coalesce(aftcast_capacity_censored, FALSE) ~ "Capacity-bounded",
            TRUE ~ "Observed"
          ),
          ever_registered = round(actual_classlist_total),
          first_day = round(actual_first_day),
          census = round(actual_census),
          final = round(actual_final_enrollment),
          sections = scheduled_sections,
          capacity = round(scheduled_capacity),
          first_day_fill,
          potential_explanation = potential_miss_explanation
        )
      reactable::reactable(
        table, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          term = reactable::colDef(name = "Term", minWidth = 95),
          aftcast_method = reactable::colDef(
            name = "Method that term", minWidth = 130
          ),
          aftcast = reactable::colDef(name = "Aftcast", align = "right"),
          raw_error = cedar_percent_coldef("Raw error"),
          assessment = reactable::colDef(name = "Assessment", minWidth = 115),
          ever_registered = reactable::colDef(
            name = "Ever registered", align = "right", minWidth = 120
          ),
          # Unknown where the class lists carry no status dates.
          first_day = reactable::colDef(
            name = "First day", align = "right", na = "\u2014"
          ),
          census = reactable::colDef(name = "Census", align = "right"),
          final = reactable::colDef(name = "Final / last day", align = "right"),
          sections = reactable::colDef(name = "Sections", align = "right"),
          capacity = reactable::colDef(name = "Capacity", align = "right"),
          first_day_fill = cedar_percent_coldef("First-day fill"),
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
          components = dplyr::coalesce(component_summary, "—"),
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
          all_term_wape = cedar_percent_coldef("All-term WAPE", minWidth = 115),
          uncapped_wape = cedar_percent_coldef("Uncapped WAPE", minWidth = 115),
          selected = reactable::colDef(name = "Selected", maxWidth = 80),
          applicable = reactable::colDef(name = "Usable", maxWidth = 70),
          components = reactable::colDef(
            name = "Floor and delta components", minWidth = 280
          ),
          evidence = reactable::colDef(name = "Evidence", minWidth = 260)
        )
      )
    })

    # ---- Scenario sub-tab ---------------------------------------------------
    # Inputs in, feature call, render out. The arithmetic, the guards, and the
    # honesty rules all live in build_enrollment_projection_scenario().
    scenario <- reactive({
      value <- bundle_value()
      req(!is.null(value))
      req(input$scenario_population)
      growth <- input$scenario_growth
      req(is.finite(growth))
      tryCatch(
        build_enrollment_projection_scenario(
          value, programs = programs,
          opt = list(
            group_id = input$group %||% "always_monitored",
            departments = input$department,
            courses = input$course,
            population_group = input$scenario_population,
            growth_rate = growth / 100,
            horizon_years = input$scenario_horizon %||% 5L
          )
        ),
        error = function(e) {
          showNotification(
            paste("Scenario unavailable:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
    })

    output$scenario_assumption <- renderUI({
      data <- scenario()
      if (is.null(data)) return(NULL)
      meta <- data$meta
      tags$div(
        class = "scope-bar",
        tags$strong(meta$population_label),
        tags$span(meta$assumption),
        tags$span(paste0(
          "Anchored on the published ", meta$target_term_label,
          " projection; ", meta$n_courses, " course(s) scaled, ",
          meta$n_excluded, " shown without scenario numbers."
        ))
      )
    })

    scenario_table_data <- reactive({
      data <- scenario()
      if (is.null(data) || nrow(data$rows) == 0L) return(NULL)
      measure <- input$scenario_measure %||% "students"
      value_column <- switch(
        measure,
        students = "projected_classlist_total",
        sections = "recommended_sections",
        additional = "additional_sections"
      )
      data$rows %>%
        dplyr::mutate(value = round(as.numeric(.data[[value_column]]))) %>%
        dplyr::select(subject_course, department, target_term_label, value) %>%
        tidyr::pivot_wider(
          names_from = target_term_label, values_from = value
        ) %>%
        dplyr::left_join(
          data$courses %>%
            dplyr::select(subject_course, population_cohort, population_share),
          by = "subject_course"
        ) %>%
        dplyr::relocate(population_cohort, population_share,
                        .after = department)
    })

    output$scenario_table <- reactable::renderReactable({
      table <- scenario_table_data()
      if (is.null(table)) {
        return(reactable::reactable(
          tibble::tibble(Message = "No course in scope carries enough of this population to scale.")
        ))
      }
      year_columns <- setdiff(
        names(table),
        c("subject_course", "department", "population_cohort", "population_share")
      )
      columns <- c(
        list(
          subject_course = reactable::colDef(name = "Course", minWidth = 110),
          department = reactable::colDef(name = "Dept", minWidth = 80),
          population_cohort = reactable::colDef(
            name = "In course", minWidth = 90,
            format = reactable::colFormat(separators = TRUE)
          ),
          population_share = cedar_percent_coldef("Share", minWidth = 80)
        ),
        stats::setNames(
          lapply(year_columns, function(column) {
            reactable::colDef(
              minWidth = 95,
              format = reactable::colFormat(separators = TRUE)
            )
          }),
          year_columns
        )
      )
      reactable::reactable(
        table, columns = columns, defaultPageSize = nrow(table),
        pagination = FALSE, highlight = TRUE, compact = TRUE,
        defaultSorted = list(subject_course = "asc")
      )
    })

    output$scenario_excluded <- renderUI({
      data <- scenario()
      if (is.null(data) || nrow(data$excluded) == 0L) return(NULL)
      info_panel(
        paste0("Courses shown without scenario numbers (", nrow(data$excluded), ")"),
        tags$ul(
          lapply(seq_len(nrow(data$excluded)), function(i) {
            tags$li(
              tags$strong(data$excluded$subject_course[[i]]), " — ",
              data$excluded$ineligible_reason[[i]]
            )
          })
        ),
        description = paste(
          "A course is listed here rather than dropped, so a thin population",
          "reads as thin evidence instead of as an absence of demand."
        )
      )
    })

    output$scenario_download <- downloadHandler(
      filename = function() {
        paste0("cedar-projection-scenario-", view()$meta$target_term, ".csv")
      },
      content = function(file) {
        data <- scenario()
        req(!is.null(data))
        utils::write.csv(data$rows, file, row.names = FALSE, na = "")
      }
    )

    invisible(list(view = view, selected_course = selected_course,
                   detail = detail, scenario = scenario))
  })
}
