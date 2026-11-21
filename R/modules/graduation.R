# Bird's Eye > Graduation
#
# Where do students leave without a degree, and how far along were they? The
# students whose last enrolled term is behind them and who hold no degree: how
# many credits they had when they stopped, when they stopped, where they stood
# against the general standards for aid, and which colleges and majors the
# far-along ones were in.
#
# The module holds no analysis: it collects the level, the home campuses and
# the credit line, calls build_graduation_dashboard()
# (features/graduation-dashboard.R) and lays out its payload. It builds only
# while the tab is open, once per scope, shared by every session.
#
# Exported functions:
#   graduationUI(id, campuses)
#   graduationServer(id, student_terms, programs, degrees, terms, dims, edges, active)

graduationUI <- function(id, campuses) {
  ns <- NS(id)
  levels <- stats::setNames(names(CEDAR_STUDENT_LEVEL_LABELS), unname(CEDAR_STUDENT_LEVEL_LABELS))
  lines <- stats::setNames(GRADUATION_LINES, paste(GRADUATION_LINES, "credits or more"))
  tagList(
    filter_bar(
      "Graduation",
      "Where do students leave without a degree, and how far along were they?",
      fluidRow(
        column(3, selectInput(ns("level"), "Student level", choices = levels, selected = levels[[1]])),
        column(4, selectizeInput(ns("campus"), "Home campus", choices = campuses, multiple = TRUE,
                                 selected = intersect(CEDAR_CAMPUS_MAIN, campuses),
                                 options = list(placeholder = "Every home campus"))),
        column(5, radioButtons(ns("line"), "Far along means", choices = lines,
                               selected = GRADUATION_LINES[[1]], inline = TRUE))
      )
    ),
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f332",
                          loading_label = "Reading who left…",
    dashboard_section(
      "How Far Along They Were",
      "Of the students who left without a degree, how many credits had each earned when they stopped?",
      method = uiOutput(ns("method_bands")),
      uiOutput(ns("headline")),
      plotly::plotlyOutput(ns("bands_plot"), height = "360px")
    ),
    dashboard_section(
      "Term by Term",
      "How many far-along students stopped after each term?",
      method = uiOutput(ns("method_series")),
      plotly::plotlyOutput(ns("series_plot"), height = "340px")
    ),
    dashboard_section(
      "Where They Stood",
      "In each credit band, how many had ever been Pell-eligible, and how many no longer met the general standards for aid?",
      method = uiOutput(ns("method_standing")),
      reactable::reactableOutput(ns("standing_table"))
    ),
    dashboard_section(
      "By College and Major",
      "Which colleges and majors were the far-along students in when they stopped?",
      method = uiOutput(ns("method_groups")),
      dashboard_subsection("College", "The college of the student's primary major in their last term.",
                           reactable::reactableOutput(ns("college_table"))),
      dashboard_subsection("Major", "The student's primary major in their last term, with its code: two majors may share a name.",
                           reactable::reactableOutput(ns("major_table")))
    ))
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

# show_code adds the group's code beside its name (majors: names repeat).
.graduation_group_table <- function(g, done_at, first_col, show_code = FALSE) {
  if (NROW(g) == 0L) return(reactable::reactable(
    data.frame(Message = "No student in this scope."), theme = cedar_tbl_theme, compact = TRUE))
  shown <- data.frame(group = g$label, code = g$group, n = g$n, n_done = g$n_done, n_flagged = g$n_flagged,
                      n_pell = g$n_pell, stringsAsFactors = FALSE)
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, defaultPageSize = 15,
    columns = list(
      group = reactable::colDef(name = first_col, minWidth = 200),
      code = reactable::colDef(name = "Code", show = show_code, na = "\u2014", minWidth = 80),
      n = cedar_count_coldef("Left"),
      n_done = cedar_count_coldef(paste(done_at, "credits or more")),
      n_flagged = cedar_count_coldef("Under a standard"),
      n_pell = cedar_count_coldef("Ever Pell-eligible")))
}

# ── Server ───────────────────────────────────────────────────────────────────

# student_terms, programs, degrees, terms, dims, edges   the loaded tables and edges.
# active   reactive: TRUE while the tab is open.
graduationServer <- function(id, student_terms, programs, degrees, terms, dims, edges, active) {
  moduleServer(id, function(input, output, session) {
    payload <- reactive({
      req(isTRUE(active()), input$level, input$line)
      cedar_with_loading(session, session$ns("load"), report_type = "graduation_dashboard", {
        tryCatch(
          build_graduation_dashboard(student_terms, programs, degrees, terms, dims, list(
            student_level = input$level, campus = if (length(input$campus) > 0) input$campus else NULL,
            line = as.numeric(input$line), data_edges = edges)),
          error = function(e) {
            showNotification(paste("Graduation:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          })
      })
    # Shared by every session: the tables are fixed for the life of the process.
    }) |> bindCache(input$level, input$campus, input$line, cache = "app")

    n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
    has_rows <- function(p) !is.null(p) && p$meta$n_left > 0L

    output$headline <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("The figures could not be built; the notification says why."))
      if (!has_rows(p)) return(empty_state(graduation_headline(p)))
      lead_text(graduation_headline(p))
    })
    output$bands_plot <- plotly::renderPlotly({ p <- payload(); req(has_rows(p)); plot_exit_bands(p) })
    output$series_plot <- plotly::renderPlotly({ p <- payload(); req(has_rows(p)); plot_exit_series(p) })

    output$method_bands <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("A student's last term is the last one they were enrolled in at this university, at any level, ",
                       "scoped by their level and home campus that term. They left when the two regular terms after it ",
                       "passed with no enrollment (summer is not a step) and they hold no degree of any kind.")),
        tags$li(paste0("Enrollment is settled through ", fmt_term(m$edge), " and degrees are posted through ",
                       fmt_term(m$degree_edge), ". ", n(m$n_not_judged), " students' last terms are too recent to judge: ",
                       "everyone still enrolled is among them. ", n(m$n_with_degree),
                       " students whose last term can be judged hold a degree and are not shown.")),
        tags$li(paste0("Credits are the total on the registrar's record when the student stopped, transfer and test ",
                       "credit included. For ", n(m$n_last_term_added), " students that record was pulled before the ",
                       "next term began, so the credits completed in the last term are added. ", n(m$n_not_recorded),
                       " have no total on record.")),
        tags$li("A student who finished at another institution is not known to have, and counts here as having left."))
    })
    output$method_series <- renderUI({
      p <- payload(); req(p)
      tags$ul(
        tags$li(paste0("Each bar is the students whose last term it was and who had ", p$meta$line,
                       " credits or more. Hover a term for those at ", p$meta$done_at, " or more and for everyone who left.")),
        tags$li("Terms are not alike: more students stop after a spring than a fall, and few after a summer. Compare a term with the same term a year earlier."))
    })

    output$standing_table <- reactable::renderReactable({
      p <- payload(); req(has_rows(p))
      b <- graduation_band_table(p)
      m <- p$meta
      shown <- data.frame(band = b$band, n = b$n, share = b$share_pct / 100, pell = b$pell_pct / 100,
                          gpa = b$gpa_below_pct / 100, ceiling = b$over_ceiling_pct / 100,
                          either = b$flagged_pct / 100, stringsAsFactors = FALSE)
      reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, sortable = FALSE, columns = list(
        band = reactable::colDef(name = "Credits when they stopped", minWidth = 170),
        n = cedar_count_coldef("Left"),
        share = cedar_percent_coldef("Share of all who left"),
        pell = cedar_percent_coldef("Ever Pell-eligible"),
        gpa = cedar_percent_coldef(paste0("GPA under ", format(m$gpa_floor, nsmall = 1))),
        ceiling = cedar_percent_coldef(paste0(m$credit_ceiling, " attempted credits or more")),
        either = cedar_percent_coldef("Either")),
        columnGroups = list(reactable::colGroup(name = "No longer met a general standard for aid",
                                                columns = c("gpa", "ceiling", "either"))))
    })
    output$method_standing <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("The two standards are general ones, computed here: a cumulative GPA under ",
                       format(m$gpa_floor, nsmall = 1), ", and ", m$credit_ceiling,
                       " attempted credits or more. The data holds no record of anyone's aid, so this is who would no ",
                       "longer have met the standard, not who lost aid.")),
        tags$li("GPA and attempted credits are the registrar's figures when the student stopped. Ever Pell-eligible means in any term on record."),
        tags$li(paste0("Each share is of the students the figure is known for; a band needs ", m$min_n,
                       " of them to show a share.")))
    })

    output$college_table <- reactable::renderReactable({
      p <- payload(); req(has_rows(p)); .graduation_group_table(p$colleges, p$meta$done_at, "College")
    })
    output$major_table <- reactable::renderReactable({
      p <- payload(); req(has_rows(p)); .graduation_group_table(p$majors, p$meta$done_at, "Major", show_code = TRUE)
    })
    output$method_groups <- renderUI({
      p <- payload(); req(p)
      m <- p$meta
      tags$ul(
        tags$li(paste0("The ", n(m$n_far), " students who left with ", m$line, " credits or more, by the primary major ",
                       "on record in their last term and that major's college. Under a standard counts the students ",
                       "below the GPA line or at the credit line above.")),
        tags$li(paste0("A major with fewer than ", m$min_list, " such students is not named: ", n(m$n_majors_pooled),
                       " are counted together as all other majors.")),
        tags$li("What each student's major still required is not shown yet: it needs a reviewed requirement file for the program."))
    })
  })
}
