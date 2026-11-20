# Bird's Eye > DFW Rates
#
# How are UNM's lower-division courses doing on DFW grades, and where is
# action needed? One term type at a time: the rate term by term and its
# verdict, the courses that hold the DFW grades, which are rising, falling or
# swinging, which courses' sections disagree term after term, and each campus
# and college.
#
# The module holds no analysis: it collects the term type, campuses and term
# range, calls
# build_dfw_dashboard() (features/dfw-dashboard.R), and lays out what
# features/dfw-dashboard-view.R computes from it. It builds only while the tab
# is open, once per scope a session asks for.
#
# Exported functions:
#   dfwRatesUI(id, campuses, terms)
#   dfwRatesServer(id, attempts, dims, edges, active)

DFW_RATES_TERM_TYPES <- c(Fall = "fall", Spring = "spring", Summer = "summer")

# The tone each part of a figure carries; the same tone marks its rows below.
DFW_RATES_TONES <- c(quarter = "critical", half = "warning", rest = "muted",
                     uneven = "warning", even = "muted")

# campuses  the teaching campuses to offer; ABQ and EA are selected, and none
#           selected reads every campus.
# terms     the graded terms to offer as the first and last term read.
dfwRatesUI <- function(id, campuses, terms) {
  ns <- NS(id)
  terms <- sort(unique(as.integer(terms)))
  term_choices <- stats::setNames(terms, vapply(terms, fmt_term, character(1)))
  tagList(
    filter_bar(
      "DFW Rates",
      "How lower-division courses are doing on D, F and withdrawal grades, and where to act.",
      fluidRow(
        column(3, radioButtons(ns("dr_term_type"), "Term type", choices = DFW_RATES_TERM_TYPES,
                               selected = "fall", inline = TRUE)),
        column(3, selectInput(ns("dr_campus"), "Campus", multiple = TRUE, choices = campuses,
                              selected = intersect(CEDAR_CAMPUS_DEFAULT, campuses))),
        column(2, selectizeInput(ns("dr_from_term"), "From term", choices = term_choices,
                                 selected = unname(utils::head(term_choices, 1L)))),
        column(2, selectizeInput(ns("dr_to_term"), "To term", choices = term_choices,
                                 selected = unname(utils::tail(term_choices, 1L)))),
        column(2, filter_actions(cedar_link_menu(ns("dr_copy_url"))))
      )
    ),
    uiOutput(ns("caveat")),
    dashboard_section(
      "How UNM Is Doing",
      "Is the DFW rate going up or down, term after term?",
      method = uiOutput(ns("method_overall")),
      uiOutput(ns("overall_finding")),
      plotly::plotlyOutput(ns("overall_plot"), height = "360px")
    ),
    dashboard_section(
      "Where the DFW Grades Are",
      "Which courses hold the most DFW grades: where a change reaches the most students.",
      method = uiOutput(ns("method_courses")),
      uiOutput(ns("concentration")),
      plotly::plotlyOutput(ns("course_bars"), height = "460px"),
      reactable::reactableOutput(ns("course_table"))
    ),
    dashboard_section(
      "What Is Changing",
      "Which courses are getting worse or better, and which swing from term to term more than courses usually do.",
      method = uiOutput(ns("method_changing")),
      uiOutput(ns("change_cards")),
      dashboard_subsection(
        "Rising and Falling",
        paste("The ten courses getting worse and the ten getting better with the most DFW grades.",
              "A bar is how much the course's DFW rate changes in a year along its trend:",
              "+2 means a 20% rate is 22% a year later."),
        plotly::plotlyOutput(ns("slope_plot"), height = "520px")
      ),
      dashboard_subsection(
        "Swinging More Than Courses Usually Do",
        "Courses whose rate jumps around its line by more than chance and the usual term-to-term change.",
        reactable::reactableOutput(ns("swing_table"))
      )
    ),
    dashboard_section(
      "Sections That Disagree",
      "Courses whose sections' DFW rates differ by more than chance, term after term.",
      method = uiOutput(ns("method_sections")),
      uiOutput(ns("section_finding")),
      plotly::plotlyOutput(ns("section_strip"), height = "640px"),
      reactable::reactableOutput(ns("section_table"))
    ),
    dashboard_section(
      "By Campus and College",
      "Whether each campus and college is moving the same way.",
      method = uiOutput(ns("method_groups")),
      fluidRow(
        column(6, dashboard_subsection("Campus", "Every campus, whichever the Campus filter picks: the campus that taught the course.",
                                       reactable::reactableOutput(ns("campus_table")))),
        column(6, dashboard_subsection("College", "The college that offers the course.",
                                       reactable::reactableOutput(ns("college_table"))))
      )
    )
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

.dfw_rates_n <- function(x) format(as.integer(x), big.mark = ",", trim = TRUE)
.dfw_rates_pct <- function(x) if (length(x) == 0L || is.na(x)) "—" else sprintf("%.1f%%", x)
.dfw_rates_terms <- function(terms) paste(vapply(terms, fmt_term, character(1)), collapse = ", ")
.dfw_rates_type <- function(p) tolower(names(DFW_RATES_TERM_TYPES)[DFW_RATES_TERM_TYPES == p$meta$term_type])
.dfw_rates_scope <- function(p) {
  m <- p$meta
  range <- if (!is.null(m$from_term) || !is.null(m$to_term)) {
    paste0(" from ", fmt_term(m$from_term %||% min(p$overall$terms$term)),
           " to ", fmt_term(m$to_term %||% m$graded_edge))
  } else ""
  paste0(m$level, "-division courses, ", .dfw_rates_type(p), " terms", range, ", ",
         if (is.null(m$campus)) "every campus" else paste(m$campus, collapse = " and "))
}

.dfw_rates_table <- function(d, columns, page_size = 15L, ...) {
  reactable::reactable(
    d, theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE, compact = TRUE,
    defaultPageSize = page_size, showPageSizeOptions = nrow(d) > page_size,
    pageSizeOptions = c(15, 50, 100), columns = columns[names(columns) %in% names(d)], ...
  )
}
.dfw_rates_rate_coldef <- function(name, ...) {
  reactable::colDef(name = name, align = "right", na = "—",
                    format = reactable::colFormat(digits = 1, suffix = "%"), ...)
}
# A trend cell: the rates its line reads; the line is the message, and its
# verdict is the cell's tooltip. `series` is the table's list of rate vectors,
# in its row order.
.dfw_rates_trend_coldef <- function(series, name = "Trend") {
  force(series)
  reactable::colDef(name = name, minWidth = 110, html = TRUE, cell = function(value, index) {
    label <- unname(DFW_DIRECTION_LABELS[dplyr::coalesce(value, "none")])
    as.character(tags$span(title = label, make_sparkline(series[[index]])))
  })
}
.dfw_rates_campus_label <- function(codes) {
  unname(ifelse(codes %in% names(CEDAR_CAMPUS_LABELS), CEDAR_CAMPUS_LABELS[codes], codes))
}

.dfw_rates_overall_cards <- function(f) {
  div(class = "finding-card-row",
      cedar_finding_card(
        "Latest term", scope = fmt_term(f$term), headline = .dfw_rates_pct(f$dfw_pct), caption = "DFW",
        tags$p(class = "stat-compare", paste0(.dfw_rates_n(f$n_dfw), " DFW grades in ",
                                              .dfw_rates_n(f$n_attempts), " attempts"))),
      cedar_finding_card(
        "Trend", scope = unname(DFW_DIRECTION_LABELS[f$direction]),
        headline = if (is.na(f$slope)) "—" else sprintf("%+.1f", f$slope), caption = "points a year",
        warn = identical(f$direction, "rising"),
        tags$p(class = "stat-compare", f$sentence)))
}

.dfw_rates_concentration <- function(p) {
  parts <- dfw_concentration_parts(p)
  tot <- p$courses$totals
  cedar_finding_card(
    "DFW grades", scope = .dfw_rates_terms(p$courses$meta$window_terms),
    headline = .dfw_rates_n(tot$n_dfw),
    caption = paste0("DFW grades in ", .dfw_rates_n(tot$n_attempts), " attempts (",
                     .dfw_rates_pct(tot$dfw_pct), ") over ", .dfw_rates_n(tot$n_courses), " courses"),
    if (nrow(parts)) cedar_segment_figure(
      data.frame(n = parts$n, tone = unname(DFW_RATES_TONES[parts$part]), label = parts$label,
                 detail = parts$detail, stringsAsFactors = FALSE),
      description = paste0("The ", tot$courses_for_quarter, " courses with the most DFW grades hold a quarter of them; the top ",
                           tot$courses_for_half, " hold half."))
  )
}

.dfw_rates_change_cards <- function(p) {
  k <- dfw_change_counts(p)
  card <- function(what, title, caption, warn = FALSE) {
    cedar_finding_card(title, scope = paste("of", .dfw_rates_n(k$n_listed[1]), "listed courses"),
                       headline = .dfw_rates_n(k$n[k$what == what]), caption = caption, warn = warn)
  }
  div(class = "finding-card-row",
      card("rising", "Rising", "getting worse", warn = TRUE),
      card("falling", "Falling", "getting better"),
      card("swings", "Swinging", "more than courses usually do"))
}

.dfw_rates_section_finding <- function(p) {
  parts <- dfw_section_parts(p)
  cedar_finding_card(
    "Uneven term after term", scope = .dfw_rates_terms(p$sections$meta$window_terms),
    headline = .dfw_rates_n(attr(parts, "n_repeat")), caption = "courses uneven in two or more terms",
    warn = attr(parts, "n_repeat") > 0L,
    if (sum(parts$n) > 0L) cedar_segment_figure(
      data.frame(n = parts$n, tone = unname(DFW_RATES_TONES[parts$part]), label = parts$label,
                 detail = NA_character_, stringsAsFactors = FALSE),
      description = paste0("In ", parts$n[1], " of ", sum(parts$n), " course-terms the sections differed more than chance allows."))
  )
}

.dfw_rates_course_reactable <- function(t) {
  series <- t$series
  d <- dplyr::select(t, -series, -slope, -dplyr::any_of("swings"))
  .dfw_rates_table(d, list(
    rank = reactable::colDef(name = "#", maxWidth = 50, align = "right"),
    subject_course = reactable::colDef(name = "Course", minWidth = 100),
    campus = reactable::colDef(name = "Campus", maxWidth = 80),
    college_name = reactable::colDef(name = "College", minWidth = 160),
    n_attempts = cedar_count_coldef("Attempts"),
    n_dfw = cedar_count_coldef("DFW grades"),
    dfw_pct = .dfw_rates_rate_coldef("DFW rate"),
    share_pct = .dfw_rates_rate_coldef("Share of all DFW"),
    cum_pct = .dfw_rates_rate_coldef("Cumulative share"),
    direction = .dfw_rates_trend_coldef(series)
  ), searchable = TRUE)
}

.dfw_rates_swing_reactable <- function(t) {
  series <- t$series
  .dfw_rates_table(dplyr::select(t, -series), list(
    subject_course = reactable::colDef(name = "Course", minWidth = 100),
    campus = reactable::colDef(name = "Campus", maxWidth = 80),
    college_name = reactable::colDef(name = "College", minWidth = 160),
    n_dfw = cedar_count_coldef("DFW grades, last terms"),
    pooled_pct = .dfw_rates_rate_coldef("DFW rate, every term"),
    resid_sd = reactable::colDef(name = "Points a term around its line", align = "right", html = TRUE,
                                 cell = function(v, index) paste0(as.character(make_sparkline(series[[index]])),
                                                                  " ", sprintf("%.1f", v))),
    n_terms = reactable::colDef(name = "Terms", maxWidth = 70, align = "right")
  ))
}

.dfw_rates_section_reactable <- function(t) {
  .dfw_rates_table(t, list(
    subject_course = reactable::colDef(name = "Course", minWidth = 100),
    campus = reactable::colDef(name = "Campus", maxWidth = 80),
    terms_tested = reactable::colDef(name = "Terms tested", align = "right"),
    terms_uneven = reactable::colDef(name = "Terms uneven", align = "right"),
    n_attempts = cedar_count_coldef("Attempts"),
    n_dfw = cedar_count_coldef("DFW grades"),
    dfw_pct = .dfw_rates_rate_coldef("DFW rate"),
    sections_above = reactable::colDef(name = "Sections above", align = "right"),
    sections_below = reactable::colDef(name = "Sections below", align = "right")
  ), searchable = TRUE)
}

.dfw_rates_group_reactable <- function(t, title) {
  series <- t$series
  d <- dplyr::select(t, label, last_n, first_pct, last_pct, direction)
  .dfw_rates_table(d, list(
    label = reactable::colDef(name = title, minWidth = 170),
    last_n = cedar_count_coldef("Attempts, latest term"),
    first_pct = .dfw_rates_rate_coldef("First term"),
    last_pct = .dfw_rates_rate_coldef("Last term"),
    direction = .dfw_rates_trend_coldef(series)
  ), page_size = 20L)
}

.dfw_rates_method_overall <- function(p, edges) {
  m <- p$overall$meta
  tags$ul(
    tags$li(paste0("Scope: ", .dfw_rates_scope(p), ". One term type at a time: a fall's students are not a spring's.")),
    tags$li("DFW is every grade but A+ to C and CR, plus every late withdrawal; an early drop counts nowhere. Each bar splits the rate into what the DFW grades were: withdrawals, F, D or C-, and other nonpassing grades (NC, I, NR and the rest)."),
    tags$li(paste0("The trend reads every term with ", m$min_term_n, " or more attempts, and needs ", m$min_trend_terms,
                   " such terms. Its slope, in points a year, is set against the slope chance and the terms' own scatter would give with no trend; beyond twice that it is rising or falling.")),
    tags$li(cedar_edge_note(edges, "graded")),
    tags$li(cedar_definition_links("dfw"))
  )
}

.dfw_rates_method_courses <- function(p) {
  m <- p$courses$meta
  tags$ul(
    tags$li(paste0("The last ", length(m$window_terms), " ", .dfw_rates_type(p), " terms: ", .dfw_rates_terms(m$window_terms), ".")),
    tags$li("A course taught on two campuses is two rows: each campus's attempts are its own."),
    tags$li(paste0("A course is listed with ", m$min_window_n, " or more attempts over those terms; every course counts in the totals and shares.")),
    tags$li("Courses are ranked by DFW grades, not rate: the count is where the students are. Share is of every DFW grade in scope; cumulative share adds the courses above."),
    tags$li("The small line is the course's rate in every term of the type, as in How UNM Is Doing; hover over it for the trend's verdict.")
  )
}

.dfw_rates_method_changing <- function(p) {
  m <- p$courses$meta
  tags$ul(
    tags$li("Rising and falling: each listed course's trend over every term of the type, judged as UNM's is. The chart shows the ten of each with the most DFW grades."),
    tags$li(paste0("Every course's rate moves from term to term by more than chance: a new instructor, another cohort. The typical course here moves ",
                   sprintf("%.1f", m$typical_extra_sd), " points a term beyond chance (the median, over the courses with a trend).")),
    tags$li(paste0("A course swings when its terms scatter around its line by more than chance plus that typical amount. ",
                   .dfw_rates_n(m$n_swing_tests), " courses are tested at once, so the bar is shared across them: about a 1-in-20 chance that even one is called a swinger by luck.")),
    tags$li("A swing is a question to ask, not a verdict: a course that changed format or text in one term will swing.")
  )
}

.dfw_rates_method_sections <- function(p) {
  m <- p$sections$meta
  tags$ul(
    tags$li(paste0("Over ", .dfw_rates_terms(m$window_terms), ", each course-term with ", m$min_sections,
                   " or more sections of ", m$min_section_n, "+ attempts is tested; smaller sections are left out of the test.")),
    tags$li(paste0("Its sections are uneven when their rates spread more than chance allows (a chi-square test of one rate across them, at ",
                   m$alpha, "). Each section is above, within or below the band chance gives a section its size around the course's rate that term (95%).")),
    tags$li("A course uneven term after term is a matter of how it is run, not of one term's draw. The chart shows the courses uneven in two or more terms, their uneven terms only; a dot is a section, sized by its attempts."),
    tags$li("Sections differ for reasons the grades do not record (time of day, delivery, which students chose it). A section is its CRN; no instructor is shown.")
  )
}

.dfw_rates_method_groups <- function(p) {
  m <- p$by_campus$meta
  tags$ul(
    tags$li("Each row reads its own rate term by term and judges its line as How UNM Is Doing does; the small line is its rates, and hovering gives the verdict."),
    tags$li("The campus table sets every campus beside the others, whichever campuses the filter picks; the college table reads the campuses picked."),
    tags$li(paste0("A row with fewer than ", m$min_trend_terms, " terms of ", m$min_term_n,
                   "+ attempts has no trend. A course's college is the one that offers it; College not decided marks courses the mapping files do not yet place."))
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

# attempts, dims, edges  cedar_attempts, cedar_dims and the data edges.
# active                 reactive: TRUE while DFW Rates is the open tab.
dfwRatesServer <- function(id, attempts, dims, edges, active) {
  moduleServer(id, function(input, output, session) {
    built <- new.env(parent = emptyenv())

    cedar_copy_url_observer(input, session, "dr_copy_url", spec_title = "DFW Rates",
                            values_fn = function() list(term_type = input$dr_term_type, campus = input$dr_campus,
                                                        from_term = input$dr_from_term, to_term = input$dr_to_term))

    payload <- reactive({
      req(isTRUE(active()), input$dr_term_type, input$dr_from_term, input$dr_to_term)
      # No campus picked reads every campus.
      campus <- if (length(input$dr_campus) == 0L) NULL else sort(input$dr_campus)
      from_term <- as.integer(input$dr_from_term)
      to_term <- as.integer(input$dr_to_term)
      if (from_term > to_term) {
        showNotification("DFW Rates: the From term is after the To term.", type = "warning",
                         duration = 6, id = "dfw_rates_term_order")
        req(FALSE)
      }
      key <- paste(input$dr_term_type, paste(campus, collapse = "+"), from_term, to_term)
      if (!is.null(built[[key]])) return(built[[key]])
      p <- withProgress(message = "Reading every lower-division course's DFW grades…", value = 0.3, {
        tryCatch(
          build_dfw_dashboard(attempts, dims, list(term_type = input$dr_term_type, campus = campus,
                                                   from_term = from_term, to_term = to_term,
                                                   data_edges = edges)),
          error = function(e) {
            showNotification(paste("DFW Rates:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          }
        )
      })
      if (!is.null(p)) assign(key, p, envir = built)
      p
    })

    output$caveat <- renderUI({
      p <- payload()
      req(p)
      nr <- dfw_overall_finding(p)$nr_terms
      if (nrow(nr) == 0L) return(NULL)
      div(class = "alert-box alert-box--warning", paste0(
        paste0(vapply(nr$term, fmt_term, character(1)), " holds ", .dfw_rates_n(nr$n_nr), " NR (not reported) grades, ",
               sprintf("%.1f%%", 100 * nr$n_nr / nr$n_attempts), " of its attempts", collapse = "; "),
        ". Each counts as DFW, so that term reads high; the grades may not have been posted when the data was pulled."))
    })

    output$overall_finding <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("The DFW figures could not be built; the notification says why."))
      .dfw_rates_overall_cards(dfw_overall_finding(p))
    })
    output$overall_plot <- plotly::renderPlotly({
      p <- payload()
      req(p)
      plot_dfw_overall(prepare_dfw_overall_plot_data(p))
    })
    output$method_overall <- renderUI({ p <- payload(); req(p); .dfw_rates_method_overall(p, edges) })

    output$concentration <- renderUI({ p <- payload(); req(p); .dfw_rates_concentration(p) })
    output$course_bars <- plotly::renderPlotly({
      p <- payload()
      req(p)
      bars <- prepare_dfw_course_bars(p)
      req(nrow(bars) > 0L)
      plot_dfw_course_bars(bars)
    })
    output$course_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      .dfw_rates_course_reactable(dfw_course_table(p))
    })
    output$method_courses <- renderUI({ p <- payload(); req(p); .dfw_rates_method_courses(p) })

    output$change_cards <- renderUI({ p <- payload(); req(p); .dfw_rates_change_cards(p) })
    output$slope_plot <- plotly::renderPlotly({
      p <- payload()
      req(p)
      slopes <- prepare_dfw_slope_plot_data(p)
      req(nrow(slopes) > 0L)
      plot_dfw_slopes(slopes)
    })
    output$swing_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      .dfw_rates_swing_reactable(dfw_swing_table(p))
    })
    output$method_changing <- renderUI({ p <- payload(); req(p); .dfw_rates_method_changing(p) })

    output$section_finding <- renderUI({ p <- payload(); req(p); .dfw_rates_section_finding(p) })
    output$section_strip <- plotly::renderPlotly({
      p <- payload()
      req(p)
      strip <- prepare_dfw_section_strip_data(p)
      req(nrow(strip$sections) > 0L)
      plot_dfw_section_strip(strip)
    })
    output$section_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      .dfw_rates_section_reactable(dfw_section_course_table(p))
    })
    output$method_sections <- renderUI({ p <- payload(); req(p); .dfw_rates_method_sections(p) })

    output$campus_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      t <- dfw_group_table(p$by_campus, "campus")
      t$label <- .dfw_rates_campus_label(t$campus)
      .dfw_rates_group_reactable(t, "Campus")
    })
    output$college_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      .dfw_rates_group_reactable(dfw_group_table(p$by_college, "college_name"), "College")
    })
    output$method_groups <- renderUI({ p <- payload(); req(p); .dfw_rates_method_groups(p) })
  })
}
