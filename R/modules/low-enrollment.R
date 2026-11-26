# Shiny Module: Courses > Low Enrollment
#
# Which sections are running under the enrollment expected for their level:
# for a term with registrations, each active section; for a term nobody has
# registered for yet, each scheduled course against its own history.
#
# The module collects the scope and the thresholds, runs
# build_low_enrollment_page() (R/features/low-enrollment.R) and draws its
# payload. Every count, band and sentence is the feature's.
#
# Exported functions:
#   lowEnrollmentUI(id, sections, default_term, dept_choices)
#   lowEnrollmentServer(id, sections, current_term, min_days_after_start, error_handler = NULL)

# The thresholds a reader can change, in the order the bar shows them, each
# with its label. `min_enrl` is the smallest section a list of sections shows.
LOW_ENROLLMENT_THRESHOLD_LABELS <- c(
  lower = "Lower division", upper = "Upper division", split = "Split-level",
  grad = "Graduate", min_enrl = "Smallest section listed")

lowEnrollmentUI <- function(id, sections, default_term, dept_choices) {
  ns <- NS(id)
  standard <- default_low_enrollment_thresholds()
  threshold_input <- function(key) {
    column(2, numericInput(ns(paste0("le_threshold_", key)), LOW_ENROLLMENT_THRESHOLD_LABELS[[key]],
                           value = standard[[key]], min = 1, max = 100, step = 1))
  }
  tagList(
    filter_bar(
      "Low Enrollment",
      "Sections running under the enrollment expected for their level, in the terms and departments you choose.",
      fluidRow(class = "explore-filter-row",
        cedar_section_scope_inputs(ns, "le", sections, dept_choices, default_term,
                                   level_selected = NULL),
        column(2,
          filter_actions(
            cedar_requires(actionButton(ns("le_button"), label = "Find Low Enrollment",
                                        icon = icon("exclamation-triangle"), class = "btn-primary"),
                           ns("le_term"), "Choose at least one term first"),
            cedar_link_menu(ns("le_copy_url"))
          )
        )
      ),
      fluidRow(
        column(10,
          cedar_threshold_fold(ns("le_threshold_state"),
            lapply(names(standard), threshold_input),
            column(2, numericInput(ns("le_min_enrl"), LOW_ENROLLMENT_THRESHOLD_LABELS[["min_enrl"]],
                                   value = 1, min = 0, max = 1000, step = 1))
          )
        )
      ),
      filter_scope_stripe(uiOutput(ns("le_filter_summary")))
    ),

    cedar_loading_overlay(id, "le_button", emoji = "\U0001f4c9",
      report_type = "low_enrollment", fresh_default = 5,
      uiOutput(ns("le_output"))
    )
  )
}

# A level tab's table. `display` is low_enrollment_display_table() output: the
# judged column takes each row's band colour, and `.band` itself is not shown.
low_enrollment_reactable <- function(display, mode) {
  nowrap <- list(whiteSpace = "nowrap")
  band_fill <- c(critical = "var(--alert-critical-bg)", warning = "var(--alert-warning-bg)",
                 watch = "var(--alert-info-bg)", buffer = "var(--alert-success-bg)",
                 no_history = "var(--alert-neutral-bg)")
  judged <- LOW_ENROLLMENT_JUDGED_COLUMN[[mode]]
  band_style <- function(name) {
    if (!identical(name, judged)) return(NULL)
    function(value, index) list(background = band_fill[[display$.band[[index]]]], fontWeight = "bold")
  }
  trend_class <- c("↑ up" = "text-success", "↓ down" = "text-critical")
  # `.column`, not `name`: a `na =` passed on to colDef() would partially
  # match `name` and be taken for it.
  column <- function(.column, ...) {
    reactable::colDef(..., style = band_style(.column), headerStyle = nowrap)
  }
  columns <- list(
    Campus = column("Campus", minWidth = 76, maxWidth = 90),
    Dept = column("Dept", minWidth = 62, maxWidth = 78),
    Department = column("Department", minWidth = 104, maxWidth = 118),
    Course = column("Course", minWidth = 90,
                    cell = function(value) htmltools::span(class = "fw-semibold", value)),
    `Sect#` = column("Sect#", minWidth = 68, maxWidth = 78, align = "right"),
    `Split Partners` = column("Split Partners", minWidth = 120),
    Title = column("Title", minWidth = 150),
    Term = column("Term", minWidth = 76, maxWidth = 90, align = "right"),
    Sects = column("Sects", minWidth = 66, maxWidth = 76, align = "right"),
    Enrolled = column("Enrolled", minWidth = 88, maxWidth = 104, align = "right"),
    `XL Total` = column("XL Total", minWidth = 86, maxWidth = 100, align = "right"),
    `Course Total` = column("Course Total", minWidth = 104, maxWidth = 116, align = "right"),
    `Hist Avg` = column("Hist Avg", minWidth = 86, maxWidth = 100, align = "right", na = "—"),
    Trend = column("Trend", maxWidth = 80, align = "center", cell = function(value) {
      tone <- if (value %in% names(trend_class)) trend_class[[value]] else "text-muted"
      htmltools::span(class = paste(tone, "fw-medium"), value)
    }),
    `# Terms` = column("# Terms", minWidth = 78, maxWidth = 90, align = "right"),
    `Prior History` = column("Prior History", minWidth = 150),
    .band = reactable::colDef(show = FALSE)
  )
  reactable::reactable(
    display,
    theme = cedar_tbl_theme,
    striped = TRUE,
    highlight = TRUE,
    defaultPageSize = 25,
    columns = columns[names(columns) %in% names(display)]
  )
}

lowEnrollmentServer <- function(id, sections, current_term, min_days_after_start,
                                error_handler = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    le_page <- reactiveVal(NULL)
    level_keys <- names(default_low_enrollment_thresholds())

    # The bar's thresholds as the inputs hold them now. A run reads them once.
    threshold_inputs <- function() {
      c(lapply(setNames(nm = level_keys), function(key) input[[paste0("le_threshold_", key)]]),
        list(min_enrl = input$le_min_enrl))
    }

    output$le_threshold_state <- renderText({
      cedar_threshold_state(threshold_inputs(),
                            c(default_low_enrollment_thresholds(), min_enrl = 1),
                            LOW_ENROLLMENT_THRESHOLD_LABELS)
    })

    output$le_filter_summary <- renderUI({
      page <- le_page()
      if (is.null(page)) {
        return(div(class = "scope-bar scope-bar--stacked scope-bar-placeholder",
                   "Run to see which list the terms get and the thresholds it used."))
      }
      headcount_scope_bar(describe_low_enrollment_scope(page))
    })

    output$le_method <- renderUI({
      page <- le_page()
      req(page, page$mode != "mixed")
      lapply(low_enrollment_method_notes(page), tags$p)
    })

    for (level in names(LOW_ENROLLMENT_LEVELS)) {
      local({
        level_key <- level
        output[[paste0("le_table_", level_key)]] <- reactable::renderReactable({
          page <- le_page()
          req(page)
          display <- low_enrollment_display_table(
            low_enrollment_level_rows(page, level_key), page$mode,
            split_partners = level_key == "split")
          req(display)
          low_enrollment_reactable(display, page$mode)
        })
      })
    }

    # One tab a level, its count in the title, so an empty level is seen
    # without opening it.
    level_tab <- function(page, level_key) {
      n <- nrow(low_enrollment_level_rows(page, level_key))
      tabPanel(
        paste0(LOW_ENROLLMENT_LEVELS[[level_key]], " (", format(n, big.mark = ","), ")"),
        value = level_key,
        if (level_key == "split") tags$p(class = "cedar-body", LOW_ENROLLMENT_SPLIT_NOTE),
        if (n == 0) {
          empty_state(paste0("Nothing to review at this level."))
        } else {
          reactable::reactableOutput(ns(paste0("le_table_", level_key)))
        }
      )
    }

    output$le_output <- renderUI({
      page <- le_page()
      if (is.null(page)) {
        return(empty_state("Choose a term, narrow to a college or department if you like, then click Find Low Enrollment."))
      }
      if (page$mode == "mixed") {
        return(div(class = "alert-box alert-box--warning", low_enrollment_mixed_terms_note(page)))
      }
      notes <- lapply(low_enrollment_view_notes(page), function(note) {
        div(class = "alert-box alert-box--warning", tags$strong(note$lead), note$text)
      })
      if (!low_enrollment_has_rows(page)) {
        return(tagList(notes, empty_state(low_enrollment_empty_note(page))))
      }
      words <- low_enrollment_section_words(page$mode)
      cards <- low_enrollment_summary_cards(summarize_low_enrollment_bands(page), page$mode)
      # The concept keys are written out here: test-definitions.R reads each
      # module for the paragraphs of docs/_data/concepts.yml it uses.
      section <- function(concept) {
        dashboard_section(
          words$title, words$sentence,
          method = uiOutput(ns("le_method")), concept = concept,
          div(class = "row", lapply(seq_len(nrow(cards)), function(i) {
            tone <- cards$tone[[i]]
            div(class = "col", cedar_stat_card(cards$value[[i]], cards$label[[i]],
                                               note = cards$note[[i]],
                                               class = if (!is.na(tone)) paste0("stat-card--", tone)))
          })),
          div(class = "download-row",
              downloadButton(ns("le_download"), "Download CSV",
                             class = "btn btn-outline-secondary btn-sm")),
          do.call(tabsetPanel, c(
            list(id = ns("le_level_tabs"), selected = low_enrollment_first_level(page)),
            lapply(names(LOW_ENROLLMENT_LEVELS), function(level_key) level_tab(page, level_key))
          ))
        )
      }
      tagList(
        notes,
        if (page$mode == "concerns") {
          section(concept = "low-enrollment.schedule-check")
        } else {
          section(concept = "low-enrollment.sections")
        }
      )
    })

    output$le_download <- downloadHandler(
      filename = function() low_enrollment_download_name(le_page()),
      content = function(file) {
        write.csv(low_enrollment_download_table(le_page()), file, row.names = FALSE)
      }
    )

    cedar_copy_url_observer(input, session, "le_copy_url", spec_title = "Low Enrollment",
      values_fn = function() c(
        list(
          campus  = input$le_campus,
          college = input$le_college,
          dept    = input$le_dept,
          term    = input$le_term,
          pt      = input$le_pt,
          im      = input$le_im,
          level   = input$le_level
        ),
        setNames(threshold_inputs(), c(paste0("threshold_", level_keys), "min_enrl"))
      ))

    le_run <- cedar_run_trigger(input, session, "le_button", "Low Enrollment")
    observeEvent(le_run(), {
      if (is.null(input$le_term) || length(input$le_term) == 0) {
        showNotification("Please select at least one term before finding low enrollment.",
                         type = "warning", duration = 5)
        return()
      }
      asked <- threshold_inputs()
      blank <- names(asked)[vapply(asked, function(value) length(value) != 1 || is.na(value), logical(1))]
      if (length(blank) > 0) {
        showNotification(
          paste0("Give a number for: ",
                 paste(LOW_ENROLLMENT_THRESHOLD_LABELS[blank], collapse = ", "), "."),
          type = "warning", duration = 8)
        return()
      }

      opt <- list(
        course_campus  = input$le_campus,
        course_college = input$le_college,
        dept_code      = input$le_dept,
        term           = input$le_term,
        pt             = input$le_pt,
        im             = input$le_im,
        level          = input$le_level
      )
      log_report_generation(session, "low_enrollment", c(opt, asked))
      timer <- start_report_timer("low_enrollment", list(
        dept = input$le_dept,
        term = input$le_term
      ))

      tryCatch({
        result <- build_low_enrollment_page(
          sections, opt,
          thresholds = unlist(asked[level_keys]),
          min_enrl = asked$min_enrl,
          current_term = current_term,
          min_days_after_start = min_days_after_start
        )
        le_page(result)
        duration_sec <- end_report_timer(timer, result = result$review)
        signal_load_complete(session, id, duration_sec = duration_sec)
      }, error = function(e) {
        if (is.function(error_handler)) {
          error_handler(e, "low_enrollment", NULL)
        } else {
          message("[low-enrollment] Error: ", conditionMessage(e))
          showModal(cedar_info_modal(
            title = "Low Enrollment error",
            conditionMessage(e)
          ))
        }
        tryCatch(end_report_timer(timer, success = FALSE, error = e), error = function(te) {
          message("[low-enrollment] Error ending timer: ", te$message)
        })
        signal_load_complete(session, id, error = TRUE)
      })
    }, ignoreInit = TRUE)
  })
}
