# Bird's Eye > DFW Rates
#
# How are UNM's lower-division courses doing on DFW grades, and where is
# action needed? One term type at a time: the rate term by term and its
# verdict, the courses that hold the DFW grades, which are rising, falling or
# swinging, how far apart each course's sections are and whether that is
# changing, and each campus and college.
#
# The module holds no analysis: it collects the term type, campuses and term
# range, calls
# build_dfw_dashboard() (features/dfw-dashboard.R), and lays out what
# features/dfw-dashboard-view.R computes from it. A scope's result is the
# same for every session, so it is built once and shared, and the scope the
# page opens on is built in the background when the app starts
# (dfw_rates_preload_jobs(), called from global.R).
#
# Exported functions:
#   dfwRatesUI(id, campuses, terms)
#   dfwRatesServer(id, attempts, dims, edges, active)
#   dfw_rates_payload_job()                          a shared result's key and build
#   dfw_rates_preload_jobs(tables, campuses, terms)  the opening scope's, for the preload

DFW_RATES_TERM_TYPES <- c(Fall = "fall", Spring = "spring", Summer = "summer")

# The tone each part of a figure carries; the same tone marks its rows below.
DFW_RATES_TONES <- c(quarter = "critical", half = "warning", rest = "muted",
                     rising = "warning", falling = "success", steady = "muted")

# campuses  the teaching campuses to offer; ABQ and EA are selected, and none
#           selected reads every campus.
# terms     the graded terms to offer as the first and last term read.
dfwRatesUI <- function(id, campuses, terms) {
  ns <- NS(id)
  terms <- sort(unique(as.integer(terms)))
  # The opening values are the scope the preload builds: one source for both.
  opens_on <- dfw_rates_default_scope(campuses, terms)
  tagList(
    filter_bar(
      "DFW Rates",
      "How lower-division courses are doing on D, F and withdrawal grades, and where to act.",
      fluidRow(
        cedar_rate_scope_inputs(ns, "dr", c("campus", "from_term", "to_term", "term_type"),
          choices = list(campus = campuses, from_term = terms, to_term = terms,
                         term_type = DFW_RATES_TERM_TYPES),
          selected = opens_on[c("campus", "from_term", "to_term", "term_type")]),
        column(2, filter_actions(cedar_link_menu(ns("dr_copy_url"))))
      ),
      # What the page read, as facts (describe_dfw_rates_scope()).
      filter_scope_stripe(uiOutput(ns("scope")))
    ),
    # Opened by the server while it reads (cedar_with_loading()).
    cedar_loading_overlay(ns("load"), run_button = NULL, emoji = "\U0001f332",
                          loading_label = "Reading every lower-division course's DFW grades…",
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
      "How far apart a course's sections are on DFW rate, averaged over its terms, and whether they are drawing together or moving apart.",
      method = uiOutput(ns("method_sections")),
      uiOutput(ns("section_finding")),
      dashboard_subsection(
        "Every Course, Term by Term",
        "How far apart sections were each term, over every course with enough sections to compare.",
        plotly::plotlyOutput(ns("spread_terms_plot"), height = "300px")
      ),
      dashboard_subsection(
        "Courses, Furthest Apart First",
        "Each course's average over its terms. The chart draws the fifteen courses whose sections are furthest apart.",
        plotly::plotlyOutput(ns("spread_course_bars"), height = "460px"),
        reactable::reactableOutput(ns("section_table"))
      )
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
    ))
  )
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

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
        tags$p(class = "stat-compare", paste0(fmt_count(f$n_dfw), " DFW grades in ",
                                              fmt_count(f$n_attempts), " attempts"))),
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
    headline = fmt_count(tot$n_dfw),
    caption = paste0("DFW grades in ", fmt_count(tot$n_attempts), " attempts (",
                     .dfw_rates_pct(tot$dfw_pct), ") over ", fmt_count(tot$n_courses), " courses"),
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
    cedar_finding_card(title, scope = paste("of", fmt_count(k$n_listed[1]), "listed courses"),
                       headline = fmt_count(k$n[k$what == what]), caption = caption, warn = warn)
  }
  div(class = "finding-card-row",
      card("rising", "Rising", "getting worse", warn = TRUE),
      card("falling", "Falling", "getting better"),
      card("swings", "Swinging", "more than courses usually do"))
}

.dfw_rates_section_finding <- function(p) {
  f <- dfw_spread_finding(p)
  if (f$n_courses == 0L) {
    return(empty_state(paste0("No course in this scope has ", p$sections$meta$min_sections, " or more sections of ",
                              p$sections$meta$min_section_n, "+ attempts in a term, so there are no sections to compare.")))
  }
  parts <- dfw_spread_direction_parts(p)
  n_short <- attr(parts, "n_short")
  n_spreading <- parts$n[parts$part == "rising"]
  div(class = "finding-card-row",
      cedar_finding_card(
        "How far apart", scope = paste(fmt_term(f$first_term), "to", fmt_term(f$last_term)),
        headline = sprintf("%.1f", f$spread_pts),
        caption = "points between a section's DFW rate and its course's, beyond chance",
        tags$p(class = "stat-compare", paste0(
          "Lowest section ", .dfw_rates_pct(f$lo_pct), ", highest ", .dfw_rates_pct(f$hi_pct),
          " on average, over ", fmt_count(f$n_course_terms), " course-terms in ", fmt_count(f$n_courses), " courses.")),
        tags$p(class = "stat-compare", paste0("Term by term: ", f$direction_phrase, "."))),
      cedar_finding_card(
        "Direction", scope = paste0("of ", fmt_count(sum(parts$n)), " courses read in ",
                                    attr(parts, "min_trend_terms"), " or more terms"),
        headline = fmt_count(n_spreading), caption = "courses whose sections are spreading",
        warn = n_spreading > 0L,
        if (sum(parts$n) > 0L) cedar_segment_figure(
          data.frame(n = parts$n, tone = unname(DFW_RATES_TONES[parts$part]), label = parts$label,
                     detail = NA_character_, stringsAsFactors = FALSE),
          description = paste0(parts$n[1], " courses' sections are spreading, ", parts$n[2],
                               " consolidating, and ", parts$n[3], " show no clear change.")),
        if (n_short > 0L) tags$p(class = "stat-compare", paste0(
          fmt_count(n_short), if (n_short == 1L) " course" else " courses", " read in fewer than ",
          attr(parts, "min_trend_terms"), " terms ", if (n_short == 1L) "has" else "have",
          " no direction and ", if (n_short == 1L) "is" else "are", " not listed."))))
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
  series <- t$series
  .dfw_rates_table(dplyr::select(t, -series), list(
    subject_course = reactable::colDef(name = "Course", minWidth = 100),
    campus = reactable::colDef(name = "Campus", maxWidth = 80),
    spread_pts = reactable::colDef(name = "Points apart, beyond chance", align = "right",
                                   format = reactable::colFormat(digits = 1)),
    lo_pct = .dfw_rates_rate_coldef("Lowest section, average"),
    hi_pct = .dfw_rates_rate_coldef("Highest section, average"),
    # The direction's word with the spread each term behind it.
    direction = reactable::colDef(name = "Direction", minWidth = 210, html = TRUE,
                                  cell = function(value, index) paste0(as.character(make_sparkline(series[[index]])),
                                                                       " ", value)),
    dfw_pct = .dfw_rates_rate_coldef("DFW rate"),
    terms_read = reactable::colDef(name = "Terms", maxWidth = 70, align = "right"),
    sections_per_term = reactable::colDef(name = "Sections a term", align = "right",
                                          format = reactable::colFormat(digits = 1)),
    n_attempts = cedar_count_coldef("Attempts")
  ), searchable = TRUE,
  language = reactable::reactableLang(noData = "No course in this scope is read in enough terms to list."))
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
                   fmt_count(m$n_swing_tests), " courses are tested at once, so the bar is shared across them: about a 1-in-20 chance that even one is called a swinger by luck.")),
    tags$li("A swing is a question to ask, not a verdict: a course that changed format or text in one term will swing.")
  )
}

.dfw_rates_method_sections <- function(p) {
  m <- p$sections$meta
  tags$ul(
    tags$li(paste0("Scope: ", .dfw_rates_scope(p), ". Each course-term with ", m$min_sections, " or more sections of ",
                   m$min_section_n, "+ attempts is read, in every term of the scope; smaller sections are left out.")),
    tags$li("Points apart is about how far a section's DFW rate sits from its course's rate that term, after taking out the difference chance alone gives sections of their sizes. Sections that differ only as chance would make them read 0."),
    tags$li("The lowest and highest section are each term's, averaged over the course's terms. They are shown beside the points and do not rank the courses: the gap between them grows with the number of sections, and with how small they are, by chance alone."),
    tags$li(paste0("A course's figure pools its terms, a larger term counting for more. A course is listed, and given a direction, when it is read in ",
                   m$min_trend_terms, " or more terms; the first card's figure pools every course-term read.")),
    tags$li("Direction is judged as the page's other trends are: the line through a course's terms has to clear both chance and the terms' own scatter to be called spreading or consolidating. The bar is strict, so most courses read no clear change."),
    tags$li("The term-by-term line pools every course read that term, so it also moves with which courses had enough sections. In the table, the small line is the course's own spread each term."),
    if (m$n_without_spread > 0L) {
      tags$li(paste0("Left out: ", fmt_count(m$n_without_spread), if (m$n_without_spread == 1L) " course-term" else " course-terms",
                     " in which no student, or every student, got a DFW grade."))
    },
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

# ── Shared results ───────────────────────────────────────────────────────────
#
# A scope's payload is the same for every session, so it is built once and
# shared (cedar_shared_result()). A job is the result's key and its build. The
# server's reactive and the startup preload make their jobs here, so the
# result built ahead is the one the page asks for.
#
# tables   named list: attempts, dims, edges (as dfwRatesServer() takes them).

DFW_RATES_TABLES <- c("attempts", "dims", "edges")

# The payload for one term type, teaching campuses and term range.
dfw_rates_payload_job <- function(tables, term_type, campus, from_term, to_term) {
  missing <- setdiff(DFW_RATES_TABLES, names(tables)[!vapply(tables, is.null, logical(1))])
  if (length(missing) > 0L) {
    stop("[dfw-rates.R] The DFW Rates page needs: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  scope <- dfw_rates_page_scope(term_type, campus, from_term, to_term)
  list(key = list("dfw_dashboard", scope$term_type, scope$campus, scope$from_term, scope$to_term),
       build = function() build_dfw_dashboard(tables$attempts, tables$dims,
                                              dfw_rates_page_opt(scope, tables$edges)))
}

# What the preload builds: the scope the page opens on.
dfw_rates_preload_jobs <- function(tables, campuses, terms) {
  opens_on <- dfw_rates_default_scope(campuses, terms)
  list(dfw_rates_payload_job(tables, opens_on$term_type, opens_on$campus, opens_on$from_term, opens_on$to_term))
}

# ── Server ───────────────────────────────────────────────────────────────────

# attempts, dims, edges  cedar_attempts, cedar_dims and the data edges.
# active                 reactive: TRUE while DFW Rates is the open tab.
dfwRatesServer <- function(id, attempts, dims, edges, active) {
  moduleServer(id, function(input, output, session) {
    tables <- list(attempts = attempts, dims = dims, edges = edges)

    cedar_copy_url_observer(input, session, "dr_copy_url", spec_title = "DFW Rates",
                            values_fn = function() list(term_type = input$dr_term_type, campus = input$dr_campus,
                                                        from_term = input$dr_from_term, to_term = input$dr_to_term))

    # Shared by every session: the tables are fixed for the life of the process.
    # The opening scope is already there (the startup preload); another is
    # built here, behind the overlay, the first time anyone asks for it. No
    # campus picked reads every campus.
    payload <- reactive({
      req(isTRUE(active()), input$dr_term_type, input$dr_from_term, input$dr_to_term)
      if (as.integer(input$dr_from_term) > as.integer(input$dr_to_term)) {
        showNotification("DFW Rates: the From term is after the To term.", type = "warning",
                         duration = 6, id = "dfw_rates_term_order")
        req(FALSE)
      }
      job <- dfw_rates_payload_job(tables, input$dr_term_type, input$dr_campus,
                                   input$dr_from_term, input$dr_to_term)
      cedar_shared_result(job$key, function() cedar_with_loading(session, session$ns("load"), report_type = "dfw_dashboard", {
        tryCatch(job$build(), error = function(e) {
          showNotification(paste("DFW Rates:", conditionMessage(e)), type = "error", duration = 10)
          NULL
        })
      }))
    })

    output$scope <- renderUI({
      p <- payload(); req(p)
      headcount_scope_bar(describe_dfw_rates_scope(p))
    })

    output$caveat <- renderUI({
      p <- payload()
      req(p)
      nr <- dfw_overall_finding(p)$nr_terms
      if (nrow(nr) == 0L) return(NULL)
      div(class = "alert-box alert-box--warning", paste0(
        paste0(vapply(nr$term, fmt_term, character(1)), " holds ", fmt_count(nr$n_nr), " NR (not reported) grades, ",
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
    output$spread_terms_plot <- plotly::renderPlotly({
      p <- payload()
      req(p)
      terms <- prepare_dfw_spread_term_plot_data(p)
      req(nrow(terms) > 0L)
      plot_dfw_spread_terms(terms)
    })
    output$spread_course_bars <- plotly::renderPlotly({
      p <- payload()
      req(p)
      bars <- prepare_dfw_spread_course_bars(p)
      req(nrow(bars) > 0L)
      plot_dfw_spread_course_bars(bars)
    })
    output$section_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      .dfw_rates_section_reactable(dfw_spread_course_table(p))
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
