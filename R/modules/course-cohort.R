# Shiny Module: Course Dynamics > Downstream > Overall > Against Students Who
# Didn't Take It ("Takers vs Non-Takers" before 2026-11-17)
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
#                      course, campus, applicants)
#
# With the applicants table, the same run also reads the course against
# similar non-takers (build_course_similar_students()): the like-with-like
# gap, its change over time, every course the population takes, and the
# course's instructors.

courseCohortUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("body"))
}

#' @param course Reactive: the analysed course's id (NULL before Analyze Course).
#' @param campus Reactive: the page's campus selection, offered as the home
#'   campuses where it names one.
#' @param applicants `cedar_applicants`, or NULL: without it the page has no
#'   similar-students sections and says so.
#' @param instructor_access The session's shared instructor-gate flag
#'   (`reactiveVal`); the by-instructor table renders only when it is TRUE.
#' @param instructor_password The gate's password ("" when none is configured).
courseCohortServer <- function(id, student_terms, attempts, programs, dims, edges,
                               course, campus, applicants = NULL,
                               instructor_access = reactiveVal(FALSE), instructor_password = "") {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    result <- reactiveVal(NULL)
    similar <- reactiveVal(NULL)
    college_names <- college_code_names(dims)
    instructorGateServer("instructor_gate", instructor_access, instructor_password,
                         what = "Results by instructor")

    defaults <- reactive({
      crs <- course()
      req(crs, nzchar(crs))
      course_cohort_context_defaults(crs, student_terms, attempts, edges, list(campus = campus()))
    })

    # A new course is a new question: the old answer leaves with it.
    observeEvent(course(), { result(NULL); similar(NULL) }, ignoreNULL = FALSE)

    output$body <- renderUI({
      crs <- course()
      if (is.null(crs) || !nzchar(crs)) {
        return(empty_state("Select a course and click Analyze Course first, then open this tab."))
      }
      d <- tryCatch(defaults(), error = function(e) {
        showNotification(paste("Comparison with non-takers:", conditionMessage(e)), type = "error", duration = 10)
        NULL
      })
      if (is.null(d)) return(empty_state(paste0("No graded attempt of ", crs, " to read.")))

      term_choices <- stats::setNames(d$choices$terms, fmt_term(d$choices$terms))
      college_choices <- stats::setNames(names(college_names), paste0(college_names, " (", names(college_names), ")"))
      if (!is.na(d$college) && !d$college %in% names(college_names)) {
        college_choices <- c(college_choices, stats::setNames(d$college, d$college))
      }
      level_choices <- sort(unique(attempts$level[!is.na(attempts$level)]))
      term_type_choices <- stats::setNames(d$choices$term_types, tools::toTitleCase(d$choices$term_types))

      tagList(
        subtab_header(
          "Against Students Who Didn't Take It",
          paste0("Do students who take ", crs, " come back and do well the next semester more often than students who don't?"),
          method = tagList(
            cedar_definition_note("course-cohort-effect"),
            tags$p("The page opens on this course's takers whose home campus is among the page's campuses (every home campus when none is): every term of the term type most of them took it in, the classification most of them held, and the course's own college and level. Change any of them and compare again."),
            tags$p("A Fall cohort and a Spring one are different students, so read one term type at a time. Students are counted by home campus, and a student who took the course on any campus is a taker.")
          )
        ),
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
          column(2, checkboxGroupInput(ns("term_type"), "Term types", choices = term_type_choices,
                                       selected = d$term_type, inline = TRUE)),
          column(2, numericInput(ns("min_n"), "Min students per group:", value = 10, min = 1, max = 1000)),
          column(2, selectInput(ns("comparison"), "Similar students compared",
                                choices = stats::setNames(names(course_similar_comparisons()),
                                                          c("Everyone else", "In a Gen Ed course")),
                                selected = "all")),
          column(4, helpText(
            "Choosing term types selects every term of those types; narrow them in Terms."
          )),
          column(2, br(), actionButton(ns("run"), "Compare Groups", icon = icon("play"), class = "btn-primary"))
        ),
        uiOutput(ns("results"))
      )
    })

    # A term type selects every term of that type; Terms then narrows them.
    observeEvent(input$term_type, {
      terms <- defaults()$choices$terms
      updateSelectizeInput(session, "terms", selected = terms[get_term_type(terms) %in% input$term_type])
    }, ignoreInit = TRUE)

    observeEvent(input$run, {
      crs <- course()
      req(crs, nzchar(crs), input$classification, input$college)
      result(NULL)
      similar(NULL)
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
            showNotification(paste("Comparison with non-takers:", conditionMessage(e)), type = "error", duration = 10)
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
        if (!is.null(payload) && !is.null(applicants)) {
          setProgress(0.9, detail = "similar students")
          similar(tryCatch(
            build_course_similar_students(
              student_terms, attempts, applicants,
              list(course = crs, classification = opt$classification, campus = opt$campus, term = opt$term,
                   comparison = input$comparison %||% "all", data_edges = edges)),
            error = function(e) {
              showNotification(paste("Similar-students comparison:", conditionMessage(e)), type = "error", duration = 10)
              NULL
            }
          ))
        }
        result(payload)
        setProgress(1)
      })
    })

    # The results in Downstream's order: the answer (against similar
    # students), its change over time, by instructor, against other courses,
    # then How Far to Trust It. Without the applicants table the answer is
    # the unmatched comparison with the college's courses.
    output$results <- renderUI({
      p <- result()
      if (is.null(p)) return(NULL)
      meta <- p$meta
      lo <- p$left_out
      n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
      tagList(
        uiOutput(ns("similar_ui")),
        dashboard_subsection(
          "Before Matching: Against the College's Courses",
          paste0("Whether passing ", meta$course, " goes with a bigger lead over every student who never took it than passing ", meta$college_label, "'s other courses does, with no matching."),
          method = tags$p("A course's gap is its passers' rate minus the rate of the students who never took it, in percentage points; it describes who takes and passes the course before it describes the course. The same gap for every other ", meta$college_label,
                          " course the population took, summarised as the median and quartiles across courses, with the share of courses whose gap is below ",
                          meta$course, "'s. A median over courses counts a small course as much as a large one."),
          reactable::reactableOutput(ns("benchmark_table")),
          info_panel(
            "Every course in the benchmark",
            description = "The same comparison for each of the college's other courses.",
            tags$p(class = "text-note", "One row per benchmark course, term and home campus. Sort by a gap column to see which courses' passers return most, or fail least, relative to the students who never took them."),
            reactable::reactableOutput(ns("courses_table"))
          ),
          info_panel(
            "The population",
            description = "How often every student in the population came back, and passed their courses, the next semester.",
            tags$p(class = "text-note", "Every enrolled student of the selected classification in each selected term and home campus, with that group's own return rate and share of next-semester attempts not passed (DFW): the baseline for both comparisons."),
            reactable::reactableOutput(ns("population_table"))
          )
        ),
        downstream_trust_section(
          paste0("Who was compared with whom, and whether the students who took ", meta$course, " already differed from those who never did."),
          who_counted = tagList(
            tags$p(class = "text-note", tags$strong("Data window: "), cedar_longitudinal_edge_note(edges, grade_dependent = FALSE)),
            tags$ul(class = "mb-0",
              tags$li("The population is every enrolled student-term of the selected classification(s) in the selected terms, by home campus: ",
                      n(meta$n_population_student_terms), " student-terms."),
              tags$li("Passed and never took it are read off every graded attempt (", meta$course,
                      " taken on any campus counts); return is enrollment the next regular term, and summer is not a step."),
              tags$li("The next-term DFW share is DFW over the group's classified attempts in that next term; it is blank where the next term is not yet graded."),
              tags$li("In the population and in no group: ", n(sum(lo$n_early_drops)), " early drops and ",
                      n(sum(lo$n_unclassified)), " registrations with no posted grade."),
              tags$li("A group under ", meta$min_n, " students keeps its count and shows no rate. A benchmark course needs ",
                      meta$min_n, " in both its passed and its never-took groups, and this course is never its own benchmark; ",
                      n(meta$n_benchmark_candidates), " ", meta$college_label, " courses were candidates.")
            )
          ),
          if (!is.null(p$balance)) cedar_alike_block(
            p$balance, c("Took it", "Never took it"),
            paste0("The students who took ", meta$course, " against those who never did, measured at each student's first selected term."),
            method = tags$p("A substantial difference says the gaps above describe who is placed into the course."),
            title = "How Alike Takers and Never-Takers Were"),
          method = tags$p("Matching on term, home campus, high-school GPA band and full- or part-time status removes those four differences and nothing else: placement, advising, major and motivation are not in it. The unmatched comparison removes none.")
        )
      )
    })

    # ── Against similar non-takers ──────────────────────────────────────────
    output$similar_ui <- renderUI({
      s <- similar()
      if (is.null(s)) return(NULL)
      m <- s$meta
      txt <- course_similar_students_text(s)
      fnd <- course_similar_students_findings(s)
      tagList(
        dashboard_subsection(
          "Against Similar Students",
          paste0("Did students who took ", m$course, " do better than students like them who did not",
                 if (identical(m$comparison, "gen_ed")) " and took a Gen Ed course instead" else "", "?"),
          method = tagList(
            tags$p("Each student who took ", m$course, " is set beside students of the same term, home campus, high-school GPA band and full- or part-time status who did not take it, pooled over the selected terms. ",
                   "The similar students' figure is what the takers would have shown at their peers' rates. A group of peers smaller than ", m$min_cell_n,
                   " supplies no figure, and its takers are left out."),
            if (length(txt$comparison)) tags$p(txt$comparison),
            tags$p("Chance alone is two standard errors at the similar students' rates: a gap inside it could arise with no real difference. Came back means enrolled in the next fall or spring semester (summer does not count); other courses not passed counts a D, an F or a withdrawal among the semester's other attempts; GPA is the next semester's, for those who came back."),
            tags$p("The matching removes those four things and nothing else: placement, advising, major and motivation are not in it.")
          ),
          if (nrow(fnd) == 0L) lapply(txt$findings, lead_text) else tagList(
            div(class = "finding-card-row", lapply(seq_len(nrow(fnd)), function(i) similar_finding_card(fnd[i, ], m$course))),
            tags$p(class = "text-note", "This shows who takes the course and how they fare, not what the course causes: students are matched on four things only.")
          ),
          if (!is.null(s$focal)) reactable::reactableOutput(ns("similar_focal_table"))
        ),
        if (nrow(s$by_term) > 0L) dashboard_subsection(
          "Over Time",
          paste0("Has each gap grown or shrunk from one ", m$trend_term_type, " to the next?"),
          method = tags$p("Each dot is one term's gap and its bar the range chance alone gives (two standard errors). The dashed line is fitted ",
                          m$trend_term_type, " to ", m$trend_term_type, ", the term type with the most takers; a term needs ", m$min_term_n,
                          " students who can be compared. A line is a trend only when its slope a year is beyond two standard errors, the larger of chance and the terms' own ups and downs; fewer than three terms draws no line."),
          lapply(txt$trend, lead_text),
          plotly::plotlyOutput(ns("similar_trend_plot"), height = "680px"),
          info_panel("Each term", description = "The gaps behind the chart, term by term.",
                     reactable::reactableOutput(ns("similar_term_table")))
        ),
        if (nrow(s$instructors) > 0L) dashboard_subsection(
          paste0(m$course, " by Instructor"),
          if (length(txt$instructors)) txt$instructors else paste0("The comparison for each instructor's students."),
          method = tags$p("The course's takers by the instructor of their attempt, each against the course's similar students; instructors with ",
                          m$min_n, " or more students who can be compared."),
          tags$p(class = "text-note", "Not a measure of teaching and not a basis for evaluating anyone: a section tied to a program, a learning community or a time of day shows who enrolled in it."),
          if (isTRUE(instructor_access())) reactable::reactableOutput(ns("similar_instructors_table"))
          else instructorGateUI(ns("instructor_gate"))
        ),
        dashboard_subsection(
          "Against Other Courses",
          if (length(txt$benchmark)) txt$benchmark else "The same comparison for every course these students take.",
          method = tags$p("Each dot is a course these students take with ", m$min_n, " or more students who can be compared, at its return gap. The shaded band holds the middle half of the courses, the solid line marks the typical (median) course, and the dotted line marks zero. Taking almost any course goes with coming back, so read a course against the others here, never against zero; a course students are placed into shows its placement. ",
                          "Return trend is each course's return gap ", m$trend_term_type, " to ", m$trend_term_type, ", read as in Over Time."),
          if (length(txt$benchmark)) plotly::plotlyOutput(ns("similar_benchmark_plot"), height = "220px"),
          info_panel("Every course these students take", description = "Largest return gap first, with each course's return-gap trend.",
                     reactable::reactableOutput(ns("similar_courses_table")))
        )
      )
    })

    # One outcome's card: the gap, the two values as bars, the verdict.
    similar_finding_card <- function(row, course) {
      verdict <- switch(row$verdict,
                        better = list(class = "stat-compare stat-compare--better", text = "Better than similar students"),
                        worse = list(class = "stat-compare stat-compare--worse", text = "Worse than similar students"),
                        same = list(class = "stat-compare", text = "About the same as similar students"),
                        unclear = list(class = "stat-compare", text = "Too few similar students to judge"))
      fmt <- if (row$unit == "pct") function(v) sprintf("%.1f%%", v) else function(v) sprintf("%.2f", v)
      scale <- if (row$unit == "pct") 100 else 4
      cedar_finding_card(
        row$title,
        headline = row$gap_label, caption = "against similar students",
        tags$p(class = verdict$class, verdict$text,
               span(class = "text-note", paste0(" (chance alone: \u00b1", if (row$unit == "pct") sprintf("%.1f", row$chance) else sprintf("%.2f", row$chance), ")"))),
        cedar_compare_bars(tibble::tibble(
          label = c(paste0("Took ", course), "Similar students"),
          share = c(row$taker, row$similar) / scale,
          text = c(fmt(row$taker), fmt(row$similar)),
          reference = c(FALSE, TRUE))),
        tags$p(class = "text-note", row$sentence)
      )
    }

    similar_columns <- function(first) {
      c(first, list(
        n_covered = cedar_count_coldef("Takers"),
        return_pct = cedar_percent_coldef("Actual"),
        return_expected_pct = cedar_percent_coldef("Expected"),
        return_gap = cedar_points_coldef("Gap"),
        return_chance = reactable::colDef(name = "Chance, ±", align = "right", na = "—",
                                          format = reactable::colFormat(digits = 1)),
        other_dfw_pct = cedar_percent_coldef("Actual"),
        other_dfw_expected_pct = cedar_percent_coldef("Expected"),
        other_dfw_gap = cedar_points_coldef("Gap"),
        next_gpa = reactable::colDef(name = "Actual", align = "right", na = "—",
                                     format = reactable::colFormat(digits = 2)),
        next_gpa_expected = reactable::colDef(name = "Expected", align = "right", na = "—",
                                              format = reactable::colFormat(digits = 2)),
        next_gpa_gap = reactable::colDef(name = "Gap", align = "right", na = "—",
                                         format = reactable::colFormat(digits = 2))
      ))
    }
    similar_groups <- list(
      reactable::colGroup(name = "Returned next term", columns = c("return_pct", "return_expected_pct", "return_gap", "return_chance")),
      reactable::colGroup(name = "DFW in other courses that term (lower is better)",
                          columns = c("other_dfw_pct", "other_dfw_expected_pct", "other_dfw_gap")),
      reactable::colGroup(name = "Next-term GPA, returners", columns = c("next_gpa", "next_gpa_expected", "next_gpa_gap"))
    )
    similar_display <- function(rows, first_cols, extra_cols = character()) {
      rows %>% transmute(
        across(all_of(first_cols)), n_covered, across(all_of(extra_cols)),
        return_pct = return_pct / 100, return_expected_pct = return_expected_pct / 100, return_gap,
        return_chance = 2 * return_gap_se,
        other_dfw_pct = other_dfw_pct / 100, other_dfw_expected_pct = other_dfw_expected_pct / 100, other_dfw_gap,
        next_gpa, next_gpa_expected, next_gpa_gap)
    }
    similar_table <- function(rows, first_cols, first_defs, extra_defs = list(), ...) {
      reactable::reactable(
        similar_display(rows, first_cols, names(extra_defs)), theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        columns = c(similar_columns(first_defs), extra_defs), columnGroups = similar_groups, ...)
    }
    # A course's return gap across terms: the line, its slope a year, the verdict.
    trend_def <- function(rows) {
      verdict <- c(rising = "rising", falling = "falling", steady = "steady", too_few_terms = "too few terms")
      list(return_trend_slope = reactable::colDef(
        name = "Return trend", minWidth = 150, align = "left", na = "—",
        cell = function(value, index) {
          dir <- rows$return_trend[index]
          if (is.na(dir)) return("—")
          label <- if (dir == "too_few_terms") verdict[[dir]]
                   else paste0(sprintf("%+.1f", value), " a year, ", verdict[[dir]])
          htmltools::tagList(make_sparkline(rows$return_gap_series[[index]]), " ", label)
        }))
    }
    course_def <- list(course = reactable::colDef(name = "Course", minWidth = 110))

    output$similar_focal_table <- reactable::renderReactable({
      s <- similar(); req(s, !is.null(s$focal))
      similar_table(s$focal, "course", course_def, pagination = FALSE)
    })
    output$similar_term_table <- reactable::renderReactable({
      s <- similar(); req(s, nrow(s$by_term) > 0L)
      similar_table(s$by_term, "term",
                    list(term = reactable::colDef(name = "Term", cell = function(v) fmt_term(v), minWidth = 100)),
                    pagination = FALSE, defaultSorted = list(term = "desc"))
    })
    output$similar_benchmark_plot <- plotly::renderPlotly({
      s <- similar(); req(s)
      plot_course_similar_students_benchmark(s)
    })
    output$similar_trend_plot <- plotly::renderPlotly({
      s <- similar(); req(s)
      plot_course_similar_students_trend(s)
    })
    output$similar_courses_table <- reactable::renderReactable({
      s <- similar(); req(s)
      similar_table(s$courses, "course", course_def, extra_defs = trend_def(s$courses), highlight = TRUE, searchable = TRUE,
                    defaultPageSize = 15, showPageSizeOptions = TRUE, pageSizeOptions = c(15, 30, 100),
                    rowClass = reactable::JS(sprintf(
                      "function(rowInfo) { return rowInfo && rowInfo.values.course === %s ? 'fw-semibold' : null }",
                      jsonlite::toJSON(s$meta$course, auto_unbox = TRUE))))
    })
    output$similar_instructors_table <- reactable::renderReactable({
      s <- similar(); req(s, nrow(s$instructors) > 0L, isTRUE(instructor_access()))
      similar_table(s$instructors, "instructor_name",
                    list(instructor_name = reactable::colDef(name = "Instructor", minWidth = 160)),
                    pagination = FALSE)
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
  })
}
