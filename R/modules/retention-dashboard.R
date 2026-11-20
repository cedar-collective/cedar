# Bird's Eye > Retention
#
# Are students coming back? One term type at a time: how often enrolled
# students came back the next regular term and whether that is rising or
# falling; who is not coming back, by the warning signs known by the end of
# the term; each classification and college; and the courses where a DFW
# grade goes with not coming back the most.
#
# The module holds no analysis: it collects the term type, level and home
# campuses, calls build_retention_dashboard() (features/retention-dashboard.R)
# and lays out its payload. It builds only while the tab is open, once per
# scope a session asks for.
#
# Exported functions:
#   retentionDashboardUI(id, campuses)
#   retentionDashboardServer(id, student_terms, attempts, degrees, dims, edges, active)

RETENTION_TERM_TYPES <- c(Fall = "fall", Spring = "spring")

# campuses  the home campuses to offer; it opens on the main campus
#           (CEDAR_CAMPUS_MAIN), and none selected reads every campus.
retentionDashboardUI <- function(id, campuses) {
  ns <- NS(id)
  # The page opens on student_levels.csv's first level.
  levels <- stats::setNames(names(CEDAR_STUDENT_LEVEL_LABELS), unname(CEDAR_STUDENT_LEVEL_LABELS))
  tagList(
    filter_bar(
      "Retention",
      "Are students coming back the next semester, and who is not?",
      fluidRow(
        column(3, radioButtons(ns("term_type"), "Term type", choices = RETENTION_TERM_TYPES,
                               selected = "fall", inline = TRUE)),
        column(3, selectInput(ns("level"), "Student level", choices = levels, selected = levels[[1]])),
        column(4, selectizeInput(ns("campus"), "Home campus", choices = campuses, multiple = TRUE,
                                 selected = intersect(CEDAR_CAMPUS_MAIN, campuses),
                                 options = list(placeholder = "Every home campus")))
      )
    ),
    # Opened by the server while it reads (cedar_with_loading()).
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f332", loading_label = "Reading who came back…",
    dashboard_section(
      "How Often Students Come Back",
      "Is the share of students who come back the next regular term rising or falling?",
      method = uiOutput(ns("method_overall")),
      uiOutput(ns("overall_finding")),
      plotly::plotlyOutput(ns("overall_plot"), height = "340px")
    ),
    dashboard_section(
      "Who Isn't Coming Back",
      "How often students with each warning sign came back, and how many of those who did not had it.",
      method = uiOutput(ns("method_signs")),
      reactable::reactableOutput(ns("signs_table"))
    ),
    dashboard_section(
      "By Classification and College",
      "Whether each classification and college is moving the same way.",
      method = uiOutput(ns("method_groups")),
      fluidRow(
        column(6, dashboard_subsection("Classification", "The student's classification that term.",
                                       reactable::reactableOutput(ns("classification_table")))),
        column(6, dashboard_subsection("College", "The college of the student's primary major that term.",
                                       reactable::reactableOutput(ns("college_table"))))
      )
    ),
    dashboard_section(
      "Courses Where a DFW Costs the Most",
      "In which courses do students who got a D, F or withdrawal come back much less often than those who passed?",
      method = uiOutput(ns("method_courses")),
      reactable::reactableOutput(ns("courses_table"))
    ))
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

.retention_n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
.retention_pct <- function(x) if (length(x) == 0L || is.na(x)) "—" else sprintf("%.1f%%", x)
.retention_type <- function(p) tolower(names(RETENTION_TERM_TYPES)[RETENTION_TERM_TYPES == p$meta$term_type])
.retention_rate_coldef <- function(name, ...) {
  reactable::colDef(name = name, align = "right", na = "—",
                    format = reactable::colFormat(digits = 1, suffix = "%"), ...)
}

.retention_group_table <- function(g, labels = NULL) {
  shown <- data.frame(
    group = if (is.null(labels)) g$group else dplyr::coalesce(unname(labels[g$group]), g$group),
    last_term = vapply(g$last_term, fmt_term, character(1)),
    last_pct = g$last_pct, pooled_pct = g$pooled_pct, direction = g$direction,
    stringsAsFactors = FALSE)
  series <- g$rates
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, defaultPageSize = 15,
    defaultSorted = list(last_pct = "asc"), columns = list(
      group = reactable::colDef(name = "", minWidth = 160),
      last_term = reactable::colDef(name = "Latest term"),
      last_pct = .retention_rate_coldef("Came back"),
      pooled_pct = .retention_rate_coldef("Over the terms"),
      # The line is the message; its verdict is the cell's tooltip.
      direction = reactable::colDef(name = "Trend", minWidth = 110, html = TRUE, cell = function(value, index) {
        as.character(tags$span(title = unname(DFW_DIRECTION_LABELS[value]), make_sparkline(series[[index]])))
      })))
}

# ── Server ───────────────────────────────────────────────────────────────────

# student_terms, attempts, degrees, dims, edges   the loaded tables and edges.
# active   reactive: TRUE while the tab is open.
retentionDashboardServer <- function(id, student_terms, attempts, degrees, dims, edges, active) {
  moduleServer(id, function(input, output, session) {
    college_names <- college_code_names(dims)
    payload <- reactive({
      req(isTRUE(active()), input$term_type, input$level)
      cedar_with_loading(session, session$ns("load"), {
        tryCatch(
          build_retention_dashboard(student_terms, attempts, degrees, list(
            term_type = input$term_type, student_level = input$level,
            campus = if (length(input$campus) > 0) input$campus else NULL, data_edges = edges)),
          error = function(e) {
            showNotification(paste("Retention:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          })
      })
    }) |> bindCache(input$term_type, input$level, input$campus, cache = "session")

    output$overall_finding <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("The retention figures could not be built; the notification says why."))
      if (nrow(p$series) == 0L) return(empty_state("No student in this scope has a settled next term to read."))
      # The chart carries the finding: each term's rate, and the trend's line
      # labelled with its slope and verdict.
      NULL
    })
    output$overall_plot <- plotly::renderPlotly({ p <- payload(); req(p, nrow(p$series) > 0L); plot_return_series(p) })
    output$method_overall <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("Every enrolled student-term of the ", .retention_type(p), " terms (registered, or withdrawn after ",
                       "census), by the student's home campus. Came back means enrolled the next regular term, ",
                       "at UNM on any campus: summer is not a step, and moving campus is not leaving.")),
        tags$li(paste0("Left out: ", .retention_n(m$n_graduated), " awarded a degree that term, who finished ",
                       "rather than left, and ", .retention_n(m$n_unobservable), " whose next term had not settled.")),
        tags$li(paste0("The dashed line is the trend, fitted through the terms; it is rising or falling when its ",
                       "slope is beyond both chance and the ordinary term-to-term swings. ",
                       retention_trend_sentence(p$trend[1, , drop = FALSE]))),
        tags$li(paste0("Enrollment settled through ", fmt_term(m$edge), "; a term's rate needs ", m$min_n,
                       " students whose return can be read. Hover a term for its counts.")))
    })

    output$signs_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$signs) > 0L)
      last <- p$signs_latest
      shown <- data.frame(
        sign = unname(RETENTION_SIGNS[last$sign]), term = vapply(last$term, fmt_term, character(1)),
        n_with = last$n_with, return_with = last$return_with_pct, return_without = last$return_without_pct,
        share = last$share_of_nonreturners_pct, stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, columns = list(
        sign = reactable::colDef(name = "Warning sign", minWidth = 140),
        term = reactable::colDef(name = "Term"),
        n_with = cedar_count_coldef("Students with it"),
        return_with = .retention_rate_coldef("Came back, with it"),
        return_without = .retention_rate_coldef("Came back, without it"),
        share = .retention_rate_coldef("Of those who didn't come back, had it")))
    })
    output$method_signs <- renderUI({
      p <- payload(); req(p)
      tags$ul(
        tags$li("A late withdrawal: at least one course dropped after census that term."),
        tags$li(paste0("A DFW grade: at least one D, F or other non-passing grade posted that term (a late ",
                       "withdrawal is counted apart). Read only for terms with posted grades, through ",
                       fmt_term(p$meta$graded_edge), "; a student with no grade posted is in neither group.")),
        tags$li("Each sign is read apart: a student may carry both, so the shares can add to more than 100%."),
        tags$li(paste0("The latest term with the sign known is shown; a rate needs ", p$meta$min_n,
                       " students. Probation is not yet a sign: academic standings are not yet mapped.")))
    })

    output$classification_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$groups) > 0L)
      .retention_group_table(p$groups[p$groups$dimension == "classification", , drop = FALSE])
    })
    output$college_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$groups) > 0L)
      .retention_group_table(p$groups[p$groups$dimension == "college", , drop = FALSE], college_names)
    })
    output$method_groups <- renderUI({
      p <- payload(); req(p)
      tags$ul(
        tags$li("Classification is the student's that term; college is the college of the primary major that term."),
        tags$li(paste0("A group's rate is read in each term it had ", p$meta$min_n, " or more students whose return ",
                       "could be read; a group not read in the latest term is left out (",
                       .retention_n(p$meta$n_groups_past), " here). Sorted with the lowest latest rate first.")))
    })

    output$courses_table <- reactable::renderReactable({
      p <- payload(); req(p, NROW(p$courses$listed) > 0L)
      top <- p$courses$listed
      shown <- data.frame(course = top$subject_course, campus = top$campus, n_dfw = top$pop_n_dfw,
                          dfw_rate = top$pop_dfw_rate, after_dfw = 1 - top$pop_dfw_stopout_rate,
                          after_pass = 1 - top$pop_pass_stopout_rate, gap = 100 * top$pop_stopout_gap,
                          excess = round(top$excess_not_back), stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, columns = list(
        course = reactable::colDef(name = "Course"), campus = reactable::colDef(name = "Campus"),
        n_dfw = cedar_count_coldef("Students with a DFW"),
        dfw_rate = cedar_percent_coldef("DFW rate"),
        after_dfw = cedar_percent_coldef("Came back after a DFW"),
        after_pass = cedar_percent_coldef("Came back after passing"),
        gap = cedar_points_coldef("Gap (points)"),
        excess = cedar_count_coldef("Not back, beyond the passers' rate")))
    })
    output$method_courses <- renderUI({
      p <- payload(); req(p)
      terms <- p$courses$terms
      tags$ul(
        tags$li(paste0("The students of the latest ", length(terms), " ", .retention_type(p), " terms with posted grades (",
                       paste(vapply(terms, fmt_term, character(1)), collapse = ", "), "), by the campus that taught ",
                       "the course. A degree that term counts as finishing, not leaving.")),
        tags$li(paste0("A course is listed when 100 or more of these students took it, 20 or more got a DFW, and the ",
                       "students who did not pass came back less often than those who passed by more than chance ",
                       "(chi-squared, p below 0.05, not adjusted across courses).")),
        tags$li(paste0("Ranked by the students a gap stands for: the students with a DFW times the gap, how many ",
                       "more did not come back than would have at the passers' rate. A large course with a ",
                       "moderate gap comes before a small one with a wide gap. The top 25 are listed.")),
        tags$li("The gap describes who fails the course as much as the course itself; Course Dynamics > Downstream > Coming Back reads one course in depth."))
    })
  })
}
