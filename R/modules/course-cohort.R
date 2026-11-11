# Shiny Module: Course Dynamics > Takers vs Non-Takers
#
# A course's takers against its non-takers, read against the college's other
# courses. The module owns the controls and the rendering; every number comes
# from build_course_cohort_context() (R/features/course-cohort-context.R),
# whose defaults open the page on the course's own classification, college,
# level and recent terms.
#
# Exported functions:
#   courseCohortUI(id)
#   courseCohortServer(id, student_terms, attempts, programs, dims, edges,
#                      course, campus)

courseCohortUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("body"))
}

#' @param course Reactive: the analysed course's id (NULL before Analyze Course).
#' @param campus Reactive: the page's campus selection, offered as the home
#'   campuses where it names one.
courseCohortServer <- function(id, student_terms, attempts, programs, dims, edges,
                               course, campus) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    result <- reactiveVal(NULL)
    college_names <- college_code_names(dims)

    defaults <- reactive({
      crs <- course()
      req(crs, nzchar(crs))
      course_cohort_context_defaults(crs, student_terms, attempts, edges, list(campus = campus()))
    })

    # A new course is a new question: the old answer leaves with it.
    observeEvent(course(), result(NULL), ignoreNULL = FALSE)

    output$body <- renderUI({
      crs <- course()
      if (is.null(crs) || !nzchar(crs)) {
        return(empty_state("Select a course and click Analyze Course first, then open this tab."))
      }
      d <- tryCatch(defaults(), error = function(e) {
        showNotification(paste("Takers vs Non-Takers:", conditionMessage(e)), type = "error", duration = 10)
        NULL
      })
      if (is.null(d)) return(empty_state(paste0("No graded attempt of ", crs, " to read.")))

      term_choices <- stats::setNames(d$choices$terms, fmt_term(d$choices$terms))
      college_choices <- stats::setNames(names(college_names), paste0(college_names, " (", names(college_names), ")"))
      if (!is.na(d$college) && !d$college %in% names(college_names)) {
        college_choices <- c(college_choices, stats::setNames(d$college, d$college))
      }
      level_choices <- sort(unique(attempts$level[!is.na(attempts$level)]))

      tagList(
        subtab_header(
          "Takers vs Non-Takers",
          cedar_definition_summary("course-cohort-effect"),
          " The page opens on the classification most of this course's recent takers held, its own college and level, and the last three years of regular terms; change any of them and compare again."
        ),
        cedar_definition_panel("course-cohort-effect"),
        fluidRow(
          column(3, selectizeInput(ns("classification"), "Classification",
                                   choices = d$choices$classifications$student_classification,
                                   selected = d$classification, multiple = TRUE)),
          column(2, selectizeInput(ns("campus"), "Home campus", choices = d$choices$campuses,
                                   selected = d$campus, multiple = TRUE,
                                   options = list(placeholder = "Every home campus"))),
          column(3, selectizeInput(ns("terms"), "Terms", choices = term_choices,
                                   selected = d$terms, multiple = TRUE)),
          column(2, selectizeInput(ns("college"), "Benchmark college", choices = college_choices,
                                   selected = d$college)),
          column(2, checkboxGroupInput(ns("level"), "Benchmark course levels", choices = level_choices,
                                       selected = d$level))
        ),
        fluidRow(
          column(2, numericInput(ns("min_n"), "Min students per group:", value = 10, min = 1, max = 1000)),
          column(8, helpText(
            "Students are counted by home campus, and a student who took the course on any campus is a taker. ",
            "A benchmark course needs the minimum in both its passed and its never-took groups; this course is never its own benchmark."
          )),
          column(2, br(), actionButton(ns("run"), "Compare Groups", icon = icon("play"), class = "btn-primary"))
        ),
        uiOutput(ns("results"))
      )
    })

    observeEvent(input$run, {
      crs <- course()
      req(crs, nzchar(crs), input$classification, input$college)
      result(NULL)
      opt <- list(
        course = crs,
        classification = input$classification,
        campus = if (length(input$campus) > 0) input$campus else NULL,
        term = if (length(input$terms) > 0) as.integer(input$terms) else NULL,
        college = input$college,
        level = if (length(input$level) > 0) input$level else NULL,
        min_n = as.integer(input$min_n %||% 10L),
        data_edges = edges,
        college_label = if (input$college %in% names(college_names)) unname(college_names[[input$college]]) else input$college
      )
      withProgress(message = "Comparing takers with non-takers...", value = 0.3, {
        payload <- tryCatch(
          build_course_cohort_context(student_terms, attempts, opt),
          error = function(e) {
            showNotification(paste("Takers vs Non-Takers:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          }
        )
        if (!is.null(payload) && !is.null(programs)) {
          setProgress(0.8, detail = "balance table")
          # The programs table may lack the demographic columns the balance
          # needs; the groups stand without it, and the page says the table is
          # missing rather than failing the comparison.
          payload <- tryCatch(
            course_cohort_context_balance(payload, student_terms, attempts, programs),
            error = function(e) {
              showNotification(paste("Balance table unavailable:", conditionMessage(e)),
                               type = "warning", duration = 8)
              payload
            }
          )
        }
        result(payload)
        setProgress(1)
      })
    })

    output$results <- renderUI({
      p <- result()
      if (is.null(p)) return(NULL)
      meta <- p$meta
      lo <- p$left_out
      n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
      tagList(
        lapply(course_cohort_context_headline(p), function(s) tags$p(class = "cedar-lead", s)),
        info_panel(
          "Who is being counted",
          description = "The population, the groups, who is in no group, and the guard.",
          div(class = "alert alert-info", tags$strong("Data window: "),
              cedar_longitudinal_edge_note(edges, grade_dependent = FALSE)),
          tags$ul(class = "mb-0",
            tags$li("The population is every enrolled student-term of the selected classification(s) in the selected terms, by home campus: ",
                    n(meta$n_population_student_terms), " student-terms."),
            tags$li("Passed, DFW'd and never took it are read off every graded attempt (", meta$course,
                    " taken on any campus counts); return is enrollment the next regular term, and summer is not a step."),
            tags$li("The next-term DFW share is DFW over the group's classified attempts in that next term; it is blank where the next term is not yet graded."),
            tags$li("In the population and in no group: ", n(sum(lo$n_early_drops)), " early drops and ",
                    n(sum(lo$n_unclassified)), " registrations with no posted grade."),
            tags$li("A group under ", meta$min_n, " students keeps its count and shows no rate. A benchmark course needs ",
                    meta$min_n, " in both its passed and its never-took groups; ", n(meta$n_benchmark_candidates),
                    " ", meta$college_label, " courses were candidates."),
            tags$li("Both gaps are passed minus never took, in points, and describe who takes the course before they describe the course.")
          )
        ),
        dashboard_subsection(
          "The Population",
          "Every enrolled student of the classification in each term and home campus, with its own return and next-term DFW share: the floor every group is read against.",
          reactable::reactableOutput(ns("population_table"))
        ),
        dashboard_subsection(
          "Passed, DFW'd, Never Took It",
          paste0("The three groups side by side for ", meta$course, ". The gap columns are the passed group's rate minus the never-took group's, in points."),
          reactable::reactableOutput(ns("groups_table"))
        ),
        dashboard_subsection(
          "Against the College's Courses",
          paste0("The same gap for every other ", meta$college_label, " course the population took, summarised: the median and quartiles across courses, and the share of courses whose gap is below ", meta$course, "'s."),
          reactable::reactableOutput(ns("benchmark_table"))
        ),
        dashboard_subsection(
          "Every Course in the Benchmark",
          "One row per benchmark course, term and home campus. Sort by a gap column to see which courses' passers return most, or fail least, relative to the students who never took them.",
          reactable::reactableOutput(ns("courses_table"))
        ),
        if (!is.null(p$balance)) dashboard_subsection(
          "How Alike Are Takers and Never-Takers",
          paste0("Standardized mean differences between students who took ", meta$course,
                 " and students who never did, at each student's first selected term. A substantial difference says the gap above describes who is placed into the course."),
          uiOutput(ns("balance_ui"))
        )
      )
    })

    term_coldef <- reactable::colDef(name = "Term", cell = function(v) fmt_term(v), minWidth = 100)
    campus_coldef <- reactable::colDef(name = "Home campus", maxWidth = 110)
    pct <- function(x) x / 100

    output$population_table <- reactable::renderReactable({
      p <- result(); req(p)
      display <- p$population %>%
        transmute(term, student_campus, population, return_pct = pct(return_pct),
                  next_attempts, next_dfw_pct = pct(next_dfw_pct))
      reactable::reactable(
        display, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE,
        defaultSorted = list(term = "desc"),
        columns = list(
          term = term_coldef, student_campus = campus_coldef,
          population = cedar_count_coldef("Students"),
          return_pct = cedar_percent_coldef("Returned"),
          next_attempts = cedar_count_coldef("Next-term attempts"),
          next_dfw_pct = cedar_percent_coldef("Next-term DFW")
        )
      )
    })

    output$groups_table <- reactable::renderReactable({
      p <- result(); req(p)
      display <- p$focal %>%
        transmute(term, student_campus,
                  passed_n_students, passed_return_pct = pct(passed_return_pct), passed_next_dfw_pct = pct(passed_next_dfw_pct),
                  dfw_n_students, dfw_return_pct = pct(dfw_return_pct), dfw_next_dfw_pct = pct(dfw_next_dfw_pct),
                  none_n_students, none_return_pct = pct(none_return_pct), none_next_dfw_pct = pct(none_next_dfw_pct),
                  lift_return, lift_next_dfw)
      reactable::reactable(
        display, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE,
        defaultSorted = list(term = "desc"),
        columns = list(
          term = term_coldef, student_campus = campus_coldef,
          passed_n_students = cedar_count_coldef("Students"),
          passed_return_pct = cedar_percent_coldef("Returned"),
          passed_next_dfw_pct = cedar_percent_coldef("Next-term DFW"),
          dfw_n_students = cedar_count_coldef("Students"),
          dfw_return_pct = cedar_percent_coldef("Returned"),
          dfw_next_dfw_pct = cedar_percent_coldef("Next-term DFW"),
          none_n_students = cedar_count_coldef("Students"),
          none_return_pct = cedar_percent_coldef("Returned"),
          none_next_dfw_pct = cedar_percent_coldef("Next-term DFW"),
          lift_return = cedar_points_coldef("Return"),
          lift_next_dfw = cedar_points_coldef("Next-term DFW")
        ),
        columnGroups = list(
          reactable::colGroup(name = "Passed it", columns = c("passed_n_students", "passed_return_pct", "passed_next_dfw_pct")),
          reactable::colGroup(name = "DFW'd it", columns = c("dfw_n_students", "dfw_return_pct", "dfw_next_dfw_pct")),
          reactable::colGroup(name = "Never took it", columns = c("none_n_students", "none_return_pct", "none_next_dfw_pct")),
          reactable::colGroup(name = "Gap, points", columns = c("lift_return", "lift_next_dfw"))
        )
      )
    })

    output$benchmark_table <- reactable::renderReactable({
      p <- result(); req(p)
      if (nrow(p$benchmark) == 0L) {
        return(reactable::reactable(
          tibble::tibble(Message = paste0("No ", p$meta$college_label, " course has both groups at ", p$meta$min_n, " students.")),
          theme = cedar_tbl_theme, pagination = FALSE, columns = list(Message = reactable::colDef(minWidth = 260))
        ))
      }
      display <- p$benchmark %>%
        left_join(p$focal %>% select(term, student_campus, focal_lift_return = lift_return, focal_lift_next_dfw = lift_next_dfw),
                  by = c("term", "student_campus")) %>%
        transmute(term, student_campus, n_courses,
                  passed_return_median = pct(passed_return_median), passed_return_q1 = pct(passed_return_q1), passed_return_q3 = pct(passed_return_q3),
                  lift_return_median, lift_return_q1, lift_return_q3, focal_lift_return, share_below_return,
                  lift_next_dfw_median, focal_lift_next_dfw, share_below_next_dfw)
      reactable::reactable(
        display, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE,
        defaultSorted = list(term = "desc"),
        columns = list(
          term = term_coldef, student_campus = campus_coldef,
          n_courses = cedar_count_coldef("Courses"),
          passed_return_median = cedar_percent_coldef("Median"),
          passed_return_q1 = cedar_percent_coldef("Q1"),
          passed_return_q3 = cedar_percent_coldef("Q3"),
          lift_return_median = cedar_points_coldef("Median"),
          lift_return_q1 = cedar_points_coldef("Q1"),
          lift_return_q3 = cedar_points_coldef("Q3"),
          focal_lift_return = cedar_points_coldef(p$meta$course),
          share_below_return = cedar_percent_coldef("Courses below it"),
          lift_next_dfw_median = cedar_points_coldef("Median"),
          focal_lift_next_dfw = cedar_points_coldef(p$meta$course),
          share_below_next_dfw = cedar_percent_coldef("Courses below it")
        ),
        columnGroups = list(
          reactable::colGroup(name = "Passers' return", columns = c("passed_return_median", "passed_return_q1", "passed_return_q3")),
          reactable::colGroup(name = "Return gap, points", columns = c("lift_return_median", "lift_return_q1", "lift_return_q3", "focal_lift_return", "share_below_return")),
          reactable::colGroup(name = "Next-term DFW gap, points (larger is worse)", columns = c("lift_next_dfw_median", "focal_lift_next_dfw", "share_below_next_dfw"))
        )
      )
    })

    output$courses_table <- reactable::renderReactable({
      p <- result(); req(p)
      display <- p$courses %>%
        filter(in_benchmark) %>%
        transmute(term, student_campus, course,
                  passed_n_students, passed_return_pct = pct(passed_return_pct),
                  none_n_students, none_return_pct = pct(none_return_pct),
                  lift_return, lift_next_dfw)
      reactable::reactable(
        display, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, highlight = TRUE,
        searchable = TRUE, defaultPageSize = 15, showPageSizeOptions = TRUE, pageSizeOptions = c(15, 30, 100),
        defaultSorted = list(term = "desc", lift_return = "desc"),
        columns = list(
          term = term_coldef, student_campus = campus_coldef,
          course = reactable::colDef(name = "Course", minWidth = 110),
          passed_n_students = cedar_count_coldef("Passed"),
          passed_return_pct = cedar_percent_coldef("Passers returned"),
          none_n_students = cedar_count_coldef("Never took it"),
          none_return_pct = cedar_percent_coldef("Never-takers returned"),
          lift_return = cedar_points_coldef("Return gap"),
          lift_next_dfw = cedar_points_coldef("Next-term DFW gap")
        )
      )
    })

    output$balance_ui <- renderUI({
      p <- result(); req(p, !is.null(p$balance))
      smd <- p$balance$smd_table
      if (is.null(smd) || nrow(smd) == 0L) return(tags$p(class = "text-note", "No balance data."))
      tagList(
        cedar_balance_summary(p$balance),
        reactable::reactable(
          cedar_balance_smd_rows(smd, c("Took it", "Never took it")),
          theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE
        )
      )
    })
  })
}
