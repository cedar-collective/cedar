# Shiny Module: Course Dynamics > Topics
#
# A course number that carries many courses, one topic at a time and its
# topics side by side: sections, students at census, fill, DFW and return the
# next regular term, by term and pooled, within the one course. The tab is
# shown only for a course whose campus-terms offered two or more topics
# (courseTopicsServer() returns whether the analysed course does).
#
# The module holds no analysis: it collects inputs, calls
# build_course_topics() (features/course-topics.R), and lays out that file's
# chart and tables. A topic-term taught by one instructor has that
# instructor's rates; the payload marks which rates a viewer without the
# instructor password may not see, and the tables render them only while the
# shared gate (modules/instructor-gate.R) is open.
#
# Exported functions:
#   courseTopicsUI(id)
#   courseTopicsServer(id, ...)

courseTopicsUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("body"))
}

# ── Layout helpers (no analysis) ─────────────────────────────────────────────

.course_topics_table <- function(d, columns, page_size = 25L, ...) {
  reactable::reactable(
    d, theme = cedar_tbl_theme, striped = TRUE, highlight = TRUE, compact = TRUE,
    searchable = nrow(d) > page_size, defaultPageSize = page_size,
    showPageSizeOptions = nrow(d) > page_size, pageSizeOptions = c(10, 25, 50),
    columns = columns, ...
  )
}

.course_topics_count_coldef <- function(name) {
  reactable::colDef(name = name, align = "right", na = "—",
                    format = reactable::colFormat(separators = TRUE, digits = 0))
}

.course_topics_term_coldef <- function(name) {
  reactable::colDef(name = name, cell = function(value) if (is.na(value)) "—" else fmt_term(value))
}

# A rate, or why there is none: withheld behind the gate, or too few students.
.course_topics_rate_coldef <- function(name, d, den_col, min_n, partial = FALSE) {
  reactable::colDef(
    name = name, align = "right",
    cell = function(value, index) {
      if (isTRUE(d$withheld[[index]])) return("withheld")
      den <- d[[den_col]][[index]]
      if (is.na(den)) return("not graded")
      if (is.na(value)) return(if (den > 0) paste0("under ", min_n) else "—")
      paste0(formatC(value, format = "f", digits = 1), "%",
             if (partial && isTRUE(d$partial[[index]])) "*" else "")
    }
  )
}

.course_topics_count_or_withheld <- function(name, d) {
  reactable::colDef(name = name, align = "right",
                    cell = function(value, index) {
                      if (isTRUE(d$withheld[[index]])) return("withheld")
                      if (is.na(value)) "—" else format(value, big.mark = ",")
                    })
}

.course_topics_total_style <- function(d) {
  function(index) if (isTRUE(d$is_total[[index]])) list(fontWeight = 600) else NULL
}

.course_topics_summary_reactable <- function(d, min_n) {
  .course_topics_table(
    d,
    columns = list(
      campus = reactable::colDef(name = "Campus", maxWidth = 80),
      topic = reactable::colDef(name = "Topic", minWidth = 200),
      terms = .course_topics_count_coldef("Terms"),
      first_term = .course_topics_term_coldef("First"),
      last_term = .course_topics_term_coldef("Last"),
      sections = .course_topics_count_coldef("Sections"),
      census_enrl = .course_topics_count_coldef("Students"),
      avg_section = reactable::colDef(name = "Per section", align = "right", na = "—",
                                      format = reactable::colFormat(digits = 1)),
      fill_pct = reactable::colDef(name = "Fill", align = "right", na = "—",
                                   format = reactable::colFormat(digits = 1, suffix = "%")),
      n_instructors = .course_topics_count_coldef("Instructors"),
      attempts = .course_topics_count_coldef("Graded"),
      dfw = .course_topics_count_or_withheld("DFW", d),
      dfw_pct = .course_topics_rate_coldef("DFW %", d, "attempts", min_n, partial = TRUE),
      n_return_observable = .course_topics_count_coldef("Return known"),
      n_returned = .course_topics_count_or_withheld("Returned", d),
      return_pct = .course_topics_rate_coldef("Returned %", d, "n_return_observable", min_n, partial = TRUE),
      withheld = reactable::colDef(show = FALSE),
      partial = reactable::colDef(show = FALSE),
      is_total = reactable::colDef(show = FALSE)
    ),
    rowStyle = .course_topics_total_style(d)
  )
}

.course_topics_term_reactable <- function(d, min_n) {
  d <- d %>% mutate(term_label = paste0(fmt_term(term), if_else(in_progress, " (in progress)", "")))
  .course_topics_table(
    d %>% select(campus, term_label, topic, sections, seats, census_enrl, fill_pct, n_instructors,
                 attempts, dfw, dfw_pct, n_return_observable, n_returned, return_pct),
    columns = list(
      campus = reactable::colDef(name = "Campus", maxWidth = 80),
      term_label = reactable::colDef(name = "Term", minWidth = 110),
      topic = reactable::colDef(name = "Topic", minWidth = 200),
      sections = .course_topics_count_coldef("Sections"),
      seats = .course_topics_count_coldef("Seats"),
      census_enrl = .course_topics_count_coldef("Students"),
      fill_pct = reactable::colDef(name = "Fill", align = "right", na = "—",
                                   format = reactable::colFormat(digits = 1, suffix = "%")),
      n_instructors = .course_topics_count_coldef("Instructors"),
      attempts = .course_topics_count_coldef("Graded"),
      dfw = .course_topics_count_or_withheld("DFW", d),
      dfw_pct = .course_topics_rate_coldef("DFW %", d, "attempts", min_n),
      n_return_observable = .course_topics_count_coldef("Return known"),
      n_returned = .course_topics_count_or_withheld("Returned", d),
      return_pct = .course_topics_rate_coldef("Returned %", d, "n_return_observable", min_n)
    ),
    rowStyle = .course_topics_total_style(d)
  )
}

.course_topics_titles_reactable <- function(d) {
  .course_topics_table(
    d,
    columns = list(
      campus = reactable::colDef(name = "Campus", maxWidth = 80),
      topic = reactable::colDef(name = "Topic", minWidth = 180),
      course_title = reactable::colDef(name = "Title on the schedule", minWidth = 220),
      read_as = reactable::colDef(name = "Counted by", minWidth = 120),
      sections = .course_topics_count_coldef("Sections"),
      first_term = .course_topics_term_coldef("First"),
      last_term = .course_topics_term_coldef("Last")
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

# course, campus      reactives: the analysed course's id (NULL before Analyze
#                     Course) and the page's campuses (NULL for every campus).
# sections, students, attempts, student_terms, edges
#                     CEDAR tables and the data edges.
# topic_titles        the reviewed title merges (CEDAR_TOPIC_TITLES).
# instructor_access   the session's shared instructor-gate flag.
# instructor_password the configured password ("" when none is).
#
# Returns a reactive: TRUE when the analysed course offers topics on the
# page's campuses, FALSE otherwise (and before any course is analysed).
courseTopicsServer <- function(id, course, campus, sections, students, attempts, student_terms,
                               edges, topic_titles, instructor_access, instructor_password) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    instructorGateServer("instructor_gate", instructor_access, instructor_password,
                         what = "DFW and return rates of a topic one instructor taught")

    has_topics <- reactive({
      crs <- course()
      if (is.null(crs) || !nzchar(crs)) return(FALSE)
      tryCatch(
        course_has_topics(sections, topic_titles, list(course = crs, campus = campus())),
        error = function(e) {
          showNotification(paste("Topics:", conditionMessage(e)), type = "error", duration = 10)
          FALSE
        }
      )
    })

    payload <- reactive({
      crs <- course()
      req(crs, nzchar(crs), isTRUE(has_topics()))
      withProgress(message = "Reading the course's topics...", value = 0.4, {
        tryCatch(
          build_course_topics(sections, students, attempts, student_terms,
                              list(course = crs, campus = campus(), data_edges = edges),
                              topic_titles = topic_titles),
          error = function(e) {
            showNotification(paste("Topics:", conditionMessage(e)), type = "error", duration = 10)
            NULL
          }
        )
      })
    })

    term_types <- reactive({
      shiny::validate(shiny::need(length(input$term_type) > 0, "Tick at least one term type."))
      input$term_type
    })
    min_n <- reactive(max(1L, as.integer(input$min_n %||% 10L)))
    unlocked <- reactive(isTRUE(instructor_access()))

    output$body <- renderUI({
      p <- payload()
      if (is.null(p)) return(empty_state("The topics could not be read; the notification says why."))
      types <- course_topics_term_types(p)
      regular <- intersect(c("fall", "spring"), types)
      chosen <- intersect(isolate(input$term_type) %||% regular, types)
      if (length(chosen) == 0L) chosen <- types
      choices <- course_topics_choices(p, chosen)
      picked <- intersect(isolate(input$topics) %||% character(0), choices)
      if (length(picked) == 0L) picked <- utils::head(unname(choices), 5L)
      measures <- stats::setNames(names(COURSE_TOPICS_MEASURES),
                                  vapply(COURSE_TOPICS_MEASURES, `[[`, "", "label"))
      tagList(
        subtab_header(
          "Topics",
          "This course number's sections carry more than one title, and each title is its own course. ",
          "Every section is counted under its topic, its title read without the section label (\"Sem:\", \"T:\"), ",
          "case or punctuation, and with the reviewed merges in topic_titles.csv; the last table lists every title. ",
          "Topics are compared only with each other, within this course and campus. ",
          "Only this course number's own registrations count: a crosslisted partner code's students are that code's."
        ),
        tags$p(class = "text-note", course_topics_scope_note(p)),
        dashboard_subsection(
          "Topics by Term",
          paste0("One measure at a time for the topics chosen, by term, a line per topic and term type; for a rate, ",
                 "the grey line is every topic together. Read one term type at a time: a Fall cohort and a Spring one ",
                 "are different students. The term types chosen here govern every table on this tab."),
          fluidRow(
            column(3, checkboxGroupInput(ns("term_type"), "Term types",
                                         choices = stats::setNames(types, tools::toTitleCase(types)),
                                         selected = chosen, inline = TRUE)),
            column(5, selectizeInput(ns("topics"), "Topics", choices = choices, selected = picked,
                                     multiple = TRUE, width = "100%",
                                     options = list(placeholder = "Choose topics to draw"))),
            column(2, selectInput(ns("measure"), "Measure", choices = measures,
                                  selected = isolate(input$measure) %||% "census_enrl")),
            column(2, numericInput(ns("min_n"), "Min students for a rate", value = isolate(input$min_n) %||% 10,
                                   min = 1, max = 100))
          ),
          plotly::plotlyOutput(ns("plot"), height = "380px")
        ),
        uiOutput(ns("gate")),
        dashboard_subsection(
          "Topics Side by Side",
          paste0("Each topic pooled over the settled terms of the chosen types, every topic together first. ",
                 "Students are counted at census (still registered plus late drops); fill is census over seats, and is ",
                 "left blank where a section's seats are shared with a crosslisted code. DFW is over graded students, ",
                 "return over those whose next regular term has settled."),
          reactable::reactableOutput(ns("summary")),
          uiOutput(ns("summary_note"))
        ),
        dashboard_subsection(
          "Topic by Term",
          "The rows behind the chart and the table above, for the topics chosen, with every topic's total for each term.",
          reactable::reactableOutput(ns("term_table"))
        ),
        dashboard_subsection(
          "Titles Behind Each Topic",
          paste0("Every title an offered section carried and the topic it is counted under: its own title, the same ",
                 "words worded differently, or a reviewed merge in topic_titles.csv. A title merged with nothing stays its ",
                 "own topic; add a row to topic_titles.csv to merge it."),
          reactable::reactableOutput(ns("titles"))
        )
      )
    })

    # A term type change reorders the topics without losing the ones chosen.
    observeEvent(input$term_type, {
      p <- payload()
      req(p, length(input$term_type) > 0)
      choices <- course_topics_choices(p, input$term_type)
      updateSelectizeInput(session, "topics", choices = choices,
                           selected = intersect(input$topics, choices))
    }, ignoreInit = TRUE)

    output$gate <- renderUI({
      p <- payload()
      req(p)
      if (unlocked() || !course_topics_withheld_any(p, term_types())) return(NULL)
      tagList(
        tags$p(class = "text-note",
               "A topic taught by one instructor in a term has that instructor's DFW and return rates, so they are behind the instructor-data password. ",
               "Where they would be the only ones withheld in a term, the smallest other topic's are withheld too, since the term's total for every topic is shown and would give them back. ",
               "Pooled over terms, a topic's rates cover only its terms not withheld (marked *). Students, sections and seats are never withheld."),
        instructorGateUI(ns("instructor_gate"))
      )
    })

    output$plot <- plotly::renderPlotly({
      p <- payload()
      req(p, input$measure, length(input$topics) > 0)
      plot <- plot_course_topics(p, input$measure, input$topics, term_types(), unlocked(), min_n())
      shiny::validate(shiny::need(!is.null(plot), "Nothing to draw for these topics and term types."))
      plot
    })

    output$summary <- reactable::renderReactable({
      p <- payload()
      req(p)
      d <- course_topics_summary(p, term_types(), unlocked(), min_n())
      shiny::validate(shiny::need(nrow(d) > 0, "No settled term of the ticked types."))
      .course_topics_summary_reactable(
        d %>% select(campus, topic, terms, first_term, last_term, sections, census_enrl, avg_section,
                     fill_pct, n_instructors, attempts, dfw, dfw_pct, n_return_observable, n_returned,
                     return_pct, withheld, partial, is_total),
        min_n()
      )
    })

    output$summary_note <- renderUI({
      p <- payload()
      req(p)
      d <- course_topics_summary(p, term_types(), unlocked(), min_n())
      notes <- c(
        if (any(d$partial)) "* Pooled over only the topic's terms whose rates are not withheld.",
        if (p$unmatched$students > 0L || p$unmatched$attempts > 0L) paste0(
          format(p$unmatched$students, big.mark = ","), " class-list rows and ",
          format(p$unmatched$attempts, big.mark = ","),
          " graded attempts carry a CRN no section of this course has, and are in no topic.")
      )
      if (length(notes) == 0L) return(NULL)
      tags$p(class = "text-note", paste(notes, collapse = " "))
    })

    output$term_table <- reactable::renderReactable({
      p <- payload()
      req(p)
      d <- course_topics_term_table(p, term_types(), unlocked(), min_n()) %>%
        filter(is_total | topic_key %in% input$topics)
      shiny::validate(shiny::need(nrow(d) > 0, "No term of the ticked types."))
      .course_topics_term_reactable(d, min_n())
    })

    output$titles <- reactable::renderReactable({
      p <- payload()
      req(p)
      .course_topics_titles_reactable(course_topics_titles(p))
    })

    has_topics
  })
}
