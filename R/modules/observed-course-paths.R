# Pathways > Course paths: what the Pathways population takes, term by term,
# by what each course is to it. Every section reads one payload,
# build_population_course_paths(), one arrival (first-time or transfer) at a
# time; the grid's words come from course_path_grid_view().

# The grid: a row per kind of course, a column per enrolled term, each cell
# shaded by its share. `view` is course_path_grid_view() output.
course_path_grid_ui <- function(view, max_terms) {
  cell <- function(r) {
    if (!nrow(r)) return(tags$td(class = "cedar-course-grid-empty"))
    tags$td(class = if (is.na(r$shade)) "cedar-course-grid-withheld" else paste0("cedar-course-grid-shade-", r$shade),
      if (!is.na(r$share)) tags$span(class = "cedar-course-grid-share", r$share),
      if (!is.na(r$of)) tags$span(class = "cedar-course-grid-of", r$of),
      if (length(r$items[[1]])) tags$ul(class = "cedar-course-grid-items", lapply(r$items[[1]], tags$li)),
      if (!is.na(r$more)) tags$span(class = "cedar-course-grid-more", r$more),
      if (!is.na(r$note)) tags$span(class = "cedar-course-grid-note", r$note))
  }
  campuses <- unique(view$campus)
  tagList(lapply(campuses, function(campus) {
    rows <- view[view$campus == campus, ]
    tagList(
      if (length(campuses) > 1L) section_heading(campus, level = "h6"),
      div(class = "cedar-course-grid-wrap",
        tags$table(class = "cedar-course-grid",
          tags$thead(tags$tr(tags$th(scope = "col", class = "cedar-course-grid-kind", "Kind of course"),
            lapply(seq_len(max_terms), function(k) tags$th(scope = "col", paste("Term", k))))),
          tags$tbody(lapply(unique(rows$group_id), function(g) {
            kind <- rows[rows$group_id == g, ]
            tags$tr(tags$th(scope = "row", class = "cedar-course-grid-kind", kind$group_label[1]),
              lapply(seq_len(max_terms), function(k) cell(kind[kind$relative_term == k, ])))
          })))))
  }),
  div(class = "cedar-course-grid-key",
    span(class = "cedar-course-grid-key-label", "Share of the term's students"),
    lapply(seq_along(COURSE_PATH_SHADE_LABELS), function(i) span(class = "cedar-course-grid-key-step",
      span(class = paste0("cedar-course-grid-swatch cedar-course-grid-shade-", i - 1L)), COURSE_PATH_SHADE_LABELS[[i]]))))
}

observedCoursePathsUI <- function(id, campuses) {
  ns <- NS(id)
  tagList(
    subtab_header("Course paths",
      "What these students take in each term they enroll: their department's courses, the courses their degree plan names, Gen Ed, and everything else."),
    filter_bar("Course paths", "Choose the delivery campuses and how many enrolled terms to follow.",
      fluidRow(
        column(6, selectizeInput(ns("campus"), "Delivery campus", choices = campuses,
          selected = intersect(CEDAR_CAMPUS_DEFAULT, unname(campuses)), multiple = TRUE)),
        column(3, numericInput(ns("max_terms"), "Enrolled terms", value = 8, min = 1, max = 16)),
        column(3, cedar_requires(actionButton(ns("button"), "Show course paths", class = "btn-primary"),
                                 ns("campus"), "Choose a delivery campus first")))),
    cedar_loading_overlay(id, "button", report_type = "degree-paths", fresh_default = 5,
      uiOutput(ns("path_scope")),
      radioButtons(ns("entry"), "Students", inline = TRUE, selected = "first_time",
                   choices = c("Started here first-time" = "first_time", "Transferred in" = "transfer")),
      dashboard_section("Courses by term",
        "In each term, what share of these students took a course of each kind, and which courses they took most.",
        concept = "pathways.course-grid",
        method = tagList(tags$ul(
          tags$li("A row is a kind of course, by what it is to these students: one of their department's subjects; a course their degree plan names, as a requirement or as one option of a choice; a Gen Ed course; or anything else. A course counts in the first row it fits."),
          tags$li("A cell is the share of the campus's students that term who took at least one course of that kind, then its three most-taken courses with each one's share, or for everything else its three most-taken subjects. \"+N more\" counts the rest, those too few to show included."),
          tags$li("Term 1 is the term a student started here at the population's level, first-time or as a transfer, as the registrar recorded it, and each later term is the next they enrolled in, summers included. Courses taken before they started are left out, and so is an earlier start at another level."),
          tags$li("Registered students and late drops count; waitlists and early drops do not. A student takes several kinds of course in a term, so a column's shares add past 100%."),
          tags$li("It shows what students took, not what they passed or needed: a course a plan leaves to a choice it does not list counts as everything else.")),
          uiOutput(ns("grid_method"))),
        uiOutput(ns("path_grid"))),
      dashboard_section("Every course they take",
        "Each course behind the grid, with the share of these students taking it in each term.",
        concept = "pathways.course-table",
        method = tags$ul(
          tags$li("A row is a course on one delivery campus; a term column is the share of that campus's students in that term who took it, with the number of students in brackets."),
          tags$li("Kind of course is the course's row in the grid. Degree plan names the plans that name the course, and says when it is one option of a choice."),
          tags$li("A course needs 10 students in a term, and its campus 20 students that term, to be shown; a dash is a term below that."),
          tags$li("Rows run by kind of course, then campus, then the course's largest share in any term.")),
        fluidRow(
          column(4, selectInput(ns("detail_group"), "Kind of course", choices = c("All kinds" = "all"))),
          column(4, checkboxGroupInput(ns("detail_level"), "Course level",
                                       choices = c("Lower" = "lower", "Upper" = "upper", "Graduate" = "grad"),
                                       selected = c("lower", "upper", "grad"), inline = TRUE)),
          column(4, radioButtons(ns("detail_gen_ed"), "Gen Ed",
                                 choices = c("All courses" = "all", "Gen Ed only" = "gen_ed", "Not Gen Ed" = "not_gen_ed"),
                                 selected = "all", inline = TRUE))),
        reactable::reactableOutput(ns("path_courses")))))
}

# population_opt: the options the population was built from (its departments).
# programs: cedar_programs, for the arrivals, the plans and the departments.
# courses, course_codes: the course dimension. boards: the degree plans, or
# NULL to read none.
observedCoursePathsServer <- function(id, students, population, population_opt, description, edges,
                                      programs, dims, courses, course_codes, boards = NULL) {
  moduleServer(id, function(input, output, session) {
    # Custom-message channels do not inherit a parent module's namespace.
    # Match the fully namespaced ID passed to the nested UI's loading overlay.
    overlay_id <- session$ns(NULL)
    payload <- reactiveVal(NULL)
    # A changed population clears the old result; the page always describes the current population.
    observeEvent(population(), payload(NULL), ignoreInit = TRUE, ignoreNULL = FALSE)
    slice <- reactive({
      p <- payload(); req(p, input$entry)
      path_entry_slice(p$paths, input$entry)
    })
    grid <- reactive(degree_path_course_grid(slice()))
    output$path_scope <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("Define a population above, then show course paths."))
      headcount_scope_bar(course_paths_scope_facts(p))
    })
    output$path_grid <- renderUI({
      g <- grid()
      if (!nrow(g$cells)) return(empty_state(course_paths_empty_note(payload()$paths$meta, input$entry)))
      course_path_grid_ui(course_path_grid_view(g), g$meta$max_terms)
    })
    output$grid_method <- renderUI({
      req(payload())
      tags$ul(lapply(course_paths_method_notes(payload(), grid()), tags$li))
    })
    output$path_courses <- reactable::renderReactable({
      s <- slice(); req(input$detail_gen_ed)
      table <- degree_path_course_table(s, input$detail_group %||% "all", descriptions = payload()$descriptions) %>%
        filter_major_course_rows(level = input$detail_level %||% character(0), gen_ed = input$detail_gen_ed)
      terms <- seq_len(s$meta$max_terms)
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
          group_label = reactable::colDef(name = "Kind of course", minWidth = 150),
          campus = reactable::colDef(name = "Campus", maxWidth = 80),
          subject_course = reactable::colDef(name = "Course", minWidth = 100),
          title = reactable::colDef(name = "Title", minWidth = 180, na = "—"),
          course_level = reactable::colDef(name = "Level", maxWidth = 90, na = "—"),
          gen_ed_area = reactable::colDef(name = "Gen Ed", minWidth = 140, na = "—"),
          in_plan = reactable::colDef(name = "Degree plan", minWidth = 160, na = "—")), term_cols))
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
        result <- build_population_course_paths(students, population(), population_opt(), programs, dims,
          courses, course_codes, boards, list(campus = input$campus, max_terms = input$max_terms, data_edges = edges),
          description())
        payload(result)
        kinds <- path_group_levels(result$paths$cells, names(COURSE_PATH_ROLES))
        labels <- result$paths$groups$group_label[match(kinds, result$paths$groups$group_id)]
        updateSelectInput(session, "detail_group", choices = c("All kinds" = "all", stats::setNames(kinds, labels)),
                          selected = "all")
        duration <- end_report_timer(timer, result = result)
        signal_load_complete(session, overlay_id, duration_sec = duration)
      }, error = function(e) {
        payload(NULL)
        showNotification(conditionMessage(e), type = "error", duration = NULL)
        end_report_timer(timer, success = FALSE, error = e)
        signal_load_complete(session, overlay_id, error = TRUE)
      })
    }, ignoreInit = TRUE)
  })
}
