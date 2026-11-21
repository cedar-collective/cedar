# Descriptive course mix belongs to Pathways and uses its selected population.
observedCoursePathsUI <- function(id, campuses) {
  ns <- NS(id)
  tagList(
    subtab_header("Course paths", "See the kinds of courses students actually take, term by term, for the population defined above."),
    filter_bar("Course paths", "Use delivery campuses and the number of observed enrolled terms to set the view.",
      fluidRow(
        column(6, selectizeInput(ns("campus"), "Delivery campus", choices = campuses,
          selected = intersect(CEDAR_CAMPUS_DEFAULT, unname(campuses)), multiple = TRUE)),
        column(3, numericInput(ns("max_terms"), "Enrolled terms", value = 8, min = 1, max = 16)),
        column(3, cedar_requires(actionButton(ns("button"), "Show course paths", class = "btn-primary"),
                                 ns("campus"), "Choose a delivery campus first")))),
    cedar_loading_overlay(id, "button", report_type = "degree-paths", fresh_default = 5,
      uiOutput(ns("path_scope")),
      plotly::plotlyOutput(ns("path_plot"), height = "620px"),
      dashboard_section("Courses inside the groups", "Which courses make up each group, and when students take them.",
        method = tags$ul(
          tags$li("A row is a course on one delivery campus; a term column is the share of that campus's students in that observed enrolled term who took it, with the number of students in brackets."),
          tags$li("A course needs 10 students in a term, and its campus 20 students that term, to be shown; a dash is a term below that."),
          tags$li("Rows run by course group, then campus, then the course's largest share in any term.")),
        fluidRow(
          column(4, selectInput(ns("detail_group"), "Course group", choices = c("All groups" = "all"))),
          column(4, checkboxGroupInput(ns("detail_level"), "Course level",
                                       choices = c("Lower" = "lower", "Upper" = "upper", "Graduate" = "grad"),
                                       selected = c("lower", "upper", "grad"), inline = TRUE)),
          column(4, radioButtons(ns("detail_gen_ed"), "Gen Ed",
                                 choices = c("All courses" = "all", "Gen Ed only" = "gen_ed", "Not Gen Ed" = "not_gen_ed"),
                                 selected = "all", inline = TRUE))),
        uiOutput(ns("detail_plans")),
        reactable::reactableOutput(ns("path_courses")))),
    info_panel("How these paths are counted",
      tags$p("Term one is first observed undergraduate enrollment; summer counts and gaps do not advance the clock. Registered students and late drops count; waitlists and early drops do not. Earlier study may be missing at the data boundary."),
      tags$p("Cells show participation, not completion or prerequisites. Students can take several groups together, so shares can exceed 100% in total. Subject groups do not establish degree eligibility. Small cells are suppressed.")))
}

# courses, course_codes: the course dimension, to describe each listed course.
# boards, declarations: the degree plans and cedar_programs, to mark the
#   courses a plan of the population's majors names; NULL boards marks none.
observedCoursePathsServer <- function(id, students, population, description, edges, groups,
                                      courses, course_codes, boards = NULL, declarations = NULL) {
  moduleServer(id, function(input, output, session) {
    # Custom-message channels do not inherit a parent module's namespace.
    # Match the fully namespaced ID passed to the nested UI's loading overlay.
    overlay_id <- session$ns(NULL)
    paths <- reactiveVal(NULL)
    # Each listed course's title, level, Gen Ed area and degree-plan mark.
    described <- reactiveVal(NULL)
    # A changed population clears the old result; the chart always describes the current population.
    observeEvent(population(), { paths(NULL); described(NULL) }, ignoreInit = TRUE, ignoreNULL = FALSE)
    output$path_scope <- renderUI({
      p <- paths()
      if (is.null(p)) return(empty_state("Define a population above, then show course paths."))
      div(class = "scope-bar scope-bar--stacked", p$note)
    })
    output$path_plot <- plotly::renderPlotly({ req(paths()); plot_grouped_student_paths(paths()) })
    output$path_courses <- reactable::renderReactable({
      req(paths())
      req(described(), input$detail_gen_ed)
      table <- degree_path_course_table(paths(), input$detail_group %||% "all", descriptions = described()$courses) %>%
        filter_major_course_rows(level = input$detail_level %||% character(0), gen_ed = input$detail_gen_ed)
      terms <- seq_len(paths()$meta$max_terms)
      display <- table %>%
        mutate(course_level = unname(c(lower = "Lower", upper = "Upper", grad = "Graduate")[course_level])) %>%
        select(group_label, campus, subject_course, title, course_level, gen_ed_area, in_plan,
               all_of(paste0("term_", terms)))
      term_cols <- stats::setNames(lapply(terms, function(k)
        cedar_pct_count_coldef(paste("Term", k), table[[paste0("n_", k)]])), paste0("term_", terms))
      reactable::reactable(display, theme = cedar_tbl_theme, compact = TRUE, searchable = TRUE,
        defaultPageSize = 25, sortable = TRUE,
        columnGroups = list(reactable::colGroup(name = "Share of the campus's students in each enrolled term",
                                                columns = paste0("term_", terms))),
        columns = c(list(
          group_label = reactable::colDef(name = "Course group", minWidth = 150),
          campus = reactable::colDef(name = "Campus", maxWidth = 80),
          subject_course = reactable::colDef(name = "Course", minWidth = 100),
          title = reactable::colDef(name = "Title", minWidth = 180, na = "\u2014"),
          course_level = reactable::colDef(name = "Level", maxWidth = 90, na = "\u2014"),
          gen_ed_area = reactable::colDef(name = "Gen Ed", minWidth = 140, na = "\u2014"),
          in_plan = reactable::colDef(name = "Degree plan", minWidth = 140, na = "\u2014")), term_cols))
    })
    output$detail_plans <- renderUI({
      d <- described(); req(d)
      tags$p(class = "text-muted", if (length(d$plans) > 0L) {
        paste0("Degree plan marks a course that a plan of this population's majors names as required (",
               paste(d$plans, collapse = ", "), "). A choice among courses, an elective or a Gen Ed slot names no course. ",
               "A plan compiled from the catalog is a draft until a reviewer signs it off.")
      } else "No degree plan has been compiled for this population's majors, so no course is marked as required.")
    })

    observeEvent(input$button, {
      if (is.null(population()) || !nrow(population())) {
        showNotification("Define a nonempty population above first.", type = "warning")
        signal_load_complete(session, overlay_id, error = TRUE)
        return()
      }
      if (!length(input$campus)) {
        showNotification("Select at least one delivery campus.", type = "warning")
        signal_load_complete(session, overlay_id, error = TRUE)
        return()
      }
      timer <- start_report_timer("degree-paths")
      tryCatch({
        # The page's overlay is already open (its run button); no second indicator.
        result <- build_population_course_paths(students, population(), groups,
          list(campus = input$campus, max_terms = input$max_terms, data_edges = edges), description())
        # The plans of the majors the population was defined by, if it was.
        majors <- attr(population(), "focal_programs")$codes$program_code
        marks <- if (is.null(boards) || length(majors) == 0L) {
          list(courses = tibble::tibble(subject_course = character(), in_plan = character()), plans = character(0))
        } else degree_plan_course_marks(boards, majors, declarations, course_codes)
        described(list(
          courses = describe_courses(result$courses$subject_course, courses, course_codes) %>%
            dplyr::left_join(marks$courses, by = "subject_course"),
          plans = marks$plans))
        paths(result)
        updateSelectInput(session, "detail_group", choices = c("All groups" = "all",
          stats::setNames(result$groups$group_id, result$groups$group_label)), selected = "all")
        duration <- end_report_timer(timer, result = result)
        signal_load_complete(session, overlay_id, duration_sec = duration)
      }, error = function(e) {
        paths(NULL); described(NULL)
        showNotification(conditionMessage(e), type = "error", duration = NULL)
        end_report_timer(timer, success = FALSE, error = e)
        signal_load_complete(session, overlay_id, error = TRUE)
      })
    }, ignoreInit = TRUE)
  })
}
