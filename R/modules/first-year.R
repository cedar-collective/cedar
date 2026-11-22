# Bird's Eye > First Year
#
# The first of the three pages (First Year, Retention, Graduation): how much
# of each entering class is still enrolled in its first semesters, by how the
# students entered. Retention reads continuing students term by term;
# Graduation reads students at the end.
#
# The module holds no analysis: it collects the term type, level, home
# campuses and who a class holds, calls retention_dashboard_milestones()
# (features/retention-dashboard.R) and lays out its rows. It builds only while
# the tab is open, once per scope a session asks for.
#
# Exported functions:
#   firstYearUI(id, campuses)
#   firstYearServer(id, student_terms, degrees, programs, attempts, courses, course_codes, edges, active)

# campuses  the home campuses to offer; it opens on the main campus
#           (CEDAR_CAMPUS_MAIN), and none selected reads every campus.
firstYearUI <- function(id, campuses) {
  ns <- NS(id)
  # The page opens on student_levels.csv's first level.
  levels <- stats::setNames(names(CEDAR_STUDENT_LEVEL_LABELS), unname(CEDAR_STUDENT_LEVEL_LABELS))
  tagList(
    filter_bar(
      "First Year",
      "How much of each entering class is still here after its first semesters?",
      fluidRow(
        column(3, radioButtons(ns("term_type"), "Entering term", choices = RETENTION_TERM_TYPES,
                               selected = "fall", inline = TRUE)),
        column(3, selectInput(ns("level"), "Student level", choices = levels, selected = levels[[1]])),
        column(4, selectizeInput(ns("campus"), "Home campus", choices = campuses, multiple = TRUE,
                                 selected = intersect(CEDAR_CAMPUS_MAIN, campuses),
                                 options = list(placeholder = "Every home campus")))
      )
    ),
    # Opened by the server while it reads (cedar_with_loading()).
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f331", loading_label = "Reading the entering classes…",
    dashboard_section(
      "Each Entering Class, Semester by Semester",
      "How much of each entering class is still enrolled in its 2nd, 3rd, 4th and 5th semesters?",
      method = uiOutput(ns("method_milestones")), concept = "first-year.entering-classes",
      radioButtons(ns("entry"), "Entering students", choices = RETENTION_ENTRY_CHOICES,
                   selected = "first_time", inline = TRUE),
      uiOutput(ns("milestones_finding")),
      plotly::plotlyOutput(ns("milestones_plot"), height = "380px")
    ),
    dashboard_section(
      "The Summer After the First Spring",
      "Do students who take a course the summer after their first spring come back in the fall more often?",
      method = uiOutput(ns("method_summer")), concept = "first-year.first-spring-summer",
      uiOutput(ns("summer_finding")),
      plotly::plotlyOutput(ns("summer_plot"), height = "340px"),
      dashboard_subsection(
        "Their Summer Courses",
        "The courses these students took most that summer.",
        reactable::reactableOutput(ns("summer_courses")))
    )
    )
  )
}

# Who an entering class holds: the page's choices, and what each asks the cone
# for. Full-time is the time status of the entering term.
RETENTION_ENTRY_CHOICES <- c("First-time" = "first_time", "First-time, full-time" = "first_time_ft",
                             "New transfer" = "transfer", "Everyone new at this level" = "all")
RETENTION_ENTRY_OPTIONS <- list(
  first_time = list(entry = "first_time", time_status = NULL),
  first_time_ft = list(entry = "first_time", time_status = "FT"),
  transfer = list(entry = "transfer", time_status = NULL),
  all = list(entry = "all", time_status = NULL)
)

.retention_entry_note <- function(entry, type, n_summer_starts) {
  switch(entry,
    first_time = paste0(
      "An entering class is the students the registrar's record calls first-time in that ", type,
      " term and who were enrolled in it, by home campus that term. A student who took college courses in high school ",
      "enters when the record calls them first-time, not at their first course. A first-time student who started in the ",
      "summer and was enrolled that fall is in the fall class, as federal reporting counts them (",
      fmt_count(n_summer_starts), " over these classes). The full-time choice keeps those full-time in their entering term."),
    transfer = paste0("An entering class is the students the registrar's record calls a new transfer in that ", type,
                      " term and who were enrolled in it, by home campus that term."),
    all = paste0("An entering class is every student whose first enrolled term at this level was that ", type,
                 " term, by home campus that term. It includes transfer students and, among undergraduates, students ",
                 "taking college courses while in high school."))
}

# ── Server ───────────────────────────────────────────────────────────────────

# student_terms, degrees, programs, attempts, edges   the loaded tables and edges.
# courses, course_codes   the course dimension, for titles.
# active   reactive: TRUE while the tab is open.
firstYearServer <- function(id, student_terms, degrees, programs, attempts, courses, course_codes, edges, active) {
  moduleServer(id, function(input, output, session) {
    # Each class in the summer after its first spring: read after the chart above.
    summer <- reactive({
      req(isTRUE(active()), input$term_type, input$level, input$entry)
      entry <- RETENTION_ENTRY_OPTIONS[[input$entry]]
      cedar_shared_result(list("first_year_summer", input$term_type, input$level, input$campus, input$entry), function() tryCatch(
        build_first_year_summer(student_terms, attempts, degrees, programs, list(
          term_type = input$term_type, student_level = input$level,
          campus = if (length(input$campus) > 0) input$campus else NULL, data_edges = edges,
          entry = entry$entry, entry_time_status = entry$time_status)),
        error = function(e) {
          showNotification(paste("Summer:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        }))
    })
    summer_rows <- reactive({ s <- summer(); req(s); summer_return_by_taking(s) })
    output$summer_finding <- renderUI({
      s <- summer()
      if (is.null(s)) return(empty_state("The summer figures could not be built; the notification says why."))
      sentence <- summer_return_sentence(summer_rows())
      if (length(sentence) == 0L) return(empty_state("No entering class in this scope has a settled fall after its first spring."))
      lead_text(sentence)
    })
    output$summer_plot <- plotly::renderPlotly({
      rows <- summer_rows(); req(any(!is.na(rows$back_took_pct)))
      plot_summer_return(rows, label = function(r) paste(vapply(as.integer(r$group), fmt_term, character(1)), "class"))
    })
    output$summer_courses <- reactable::renderReactable({
      s <- summer(); req(s)
      cedar_course_share_table(s$courses, describe_courses(s$courses$subject_course, courses, course_codes),
                               "Of those who took a summer course")
    })
    output$method_summer <- renderUI({
      s <- summer(); req(s)
      m <- s$meta
      tags$ul(
        tags$li(paste0("The students of each entering class who were enrolled in its first spring: the 2nd semester ",
                       "of a fall class, the entering term of a spring one. ", fmt_count(m$n_students), " students over ",
                       "these classes; ", fmt_count(m$n_took), " took a course here in the summer after.")),
        tags$li(paste0("Back in the fall means enrolled then at this university, on any campus, or awarded a degree by ",
                       "then. A class is read once that fall has settled (enrollment is settled through ",
                       fmt_term(m$edge), "), and a line needs 30 students for a point.")),
        tags$li(paste0("This does not show that a summer course keeps a student here. A student who signs up for ",
                       "summer has usually already decided to come back, and differs from one who does not in ways ",
                       "the data holds (credits, grades) and ways it does not (money, work, plans).")),
        tags$li(if (length(m$course_terms) == 0L) "No summer in this scope has posted grades, so no course is listed."
                else paste0("Courses are graded attempts in ", paste(vapply(m$course_terms, fmt_term, character(1)), collapse = ", "),
                            ", by the campus that taught them, as a share of the ", fmt_count(m$n_course_students),
                            " students who took a course in those summers. A course taken by fewer than ", m$min_n,
                            " of them is not listed.")))
    })

    # The entering classes are read on their own, so choosing who a class
    # holds rebuilds this chart and nothing else.
    milestones <- reactive({
      req(isTRUE(active()), input$term_type, input$level, input$entry)
      entry <- RETENTION_ENTRY_OPTIONS[[input$entry]]
      cedar_shared_result(list("retention_milestones", input$term_type, input$level, input$campus, input$entry), function() cedar_with_loading(session, session$ns("load"), report_type = "first_year", tryCatch(
        retention_dashboard_milestones(student_terms, degrees, list(
          term_type = input$term_type, student_level = input$level,
          campus = if (length(input$campus) > 0) input$campus else NULL, data_edges = edges,
          entry = entry$entry, entry_time_status = entry$time_status), programs),
        error = function(e) {
          showNotification(paste("Entering classes:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        })))
    })

    output$milestones_finding <- renderUI({
      ms <- milestones(); req(ms)
      sentence <- retention_milestone_sentence(list(milestones = ms))
      if (length(sentence) == 0L) return(empty_state("No entering class in this scope has a settled later term to read."))
      lead_text(sentence)
    })
    output$milestones_plot <- plotly::renderPlotly({
      ms <- milestones(); req(ms, any(!is.na(ms$here_pct)))
      plot_entering_class_milestones(list(milestones = ms))
    })
    output$method_milestones <- renderUI({
      ms <- milestones(); req(ms)
      tags$ul(
        tags$li(.retention_entry_note(attr(ms, "entry"), tolower(names(RETENTION_TERM_TYPES)[RETENTION_TERM_TYPES == input$term_type]), attr(ms, "n_summer_starts"))),
        tags$li("Still enrolled means enrolled in that later term on any campus, or awarded a degree by then. A student away one term and back the next is missing from the first and counted in the second."),
        tags$li(paste0("Each line is one semester of the class's time here: the entering term is the 1st, so a year on is ",
                       "the 3rd, the one retention is usually quoted at. A semester is a fall or a spring; summer is not ",
                       "counted. The gap between two lines is the share lost between them.")),
        tags$li(paste0("A line stops at the last class whose later term has settled (enrollment settled through ",
                       fmt_term(attr(ms, "edge")), "). ",
                       if (identical(attr(ms, "entry"), "all")) paste0(
                         fmt_term(attr(ms, "first_term")), " is the first term on record, so no one can be called new in it: ",
                         fmt_count(attr(ms, "n_first_term")), " students first seen then are in no class. "),
                       "A class needs ",
                       attr(ms, "min_n"), " students for a rate.")))
    })
  })
}
