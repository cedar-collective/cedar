gen_ed_term_choices <- function(sections, current_term = NULL) {
  terms <- sort(unique(sections$term[!is.na(sections$term)]))
  if (!is.null(current_term)) terms <- terms[terms <= current_term]
  stats::setNames(terms, vapply(terms, fmt_term, character(1)))
}


gen_ed_dept_sections <- function(sections, dept = NULL) {
  dept_val <- if (is.function(dept)) dept() else dept
  if (is.null(dept_val) || length(dept_val) == 0 || !nzchar(dept_val[1])) return(sections)

  gen_ed_lu <- gen_ed_course_lookup()
  sections %>%
    dplyr::filter(
      department %in% dept_val,
      subject_course %in% gen_ed_lu$subject_course
    )
}


gen_ed_area_choices <- function(sections) {
  areas <- sort(unique(sections$gen_ed_area[!is.na(sections$gen_ed_area)]))
  stats::setNames(areas, paste("Area", areas))
}


genEdExploreUI <- function(id, sections, dept_choices, current_term = NULL) {
  ns <- NS(id)
  term_choices <- gen_ed_term_choices(sections, current_term)
  area_choices <- gen_ed_area_choices(sections)

  tagList(
    filter_bar(
      "Gen Ed",
      "Aggregate view of Gen Ed enrollment, grade outcomes, and later major declarations.",
      fluidRow(
        column(2,
          selectInput(ns("ge_campus"), "Campus", multiple = TRUE,
            choices = sort(unique(sections$campus[!is.na(sections$campus)])),
            selected = intersect(c("ABQ", "EA"), unique(sections$campus)))
        ),
        column(2,
          selectInput(ns("ge_college"), "College", multiple = TRUE,
            choices = sort(unique(sections$college[!is.na(sections$college)])))
        ),
        column(2,
          selectizeInput(ns("ge_dept"), "Department", multiple = TRUE,
            choices = dept_choices)
        ),
        column(2,
          selectInput(ns("ge_gen_ed_area"), "Gen Ed Area", multiple = TRUE,
            choices = area_choices)
        ),
        column(2,
          selectInput(ns("ge_level"), "Level", multiple = TRUE,
            choices = sort(unique(sections$level[!is.na(sections$level)])),
            selected = c("lower", "upper"))
        ),
        column(2,
          numericInput(ns("ge_min_n"), "Min N", value = 5, min = 1, max = 100)
        )
      ),
      fluidRow(
        column(2,
          selectizeInput(ns("ge_from_term"), "From term",
            choices = term_choices, selected = if (length(term_choices)) unname(term_choices)[1])
        ),
        column(2,
          selectizeInput(ns("ge_to_term"), "To term",
            choices = term_choices, selected = if (length(term_choices)) unname(term_choices)[length(term_choices)])
        ),
        column(2,
          filter_actions(
            actionButton(ns("ge_button"), "Run", class = "btn-primary btn-sm", icon = icon("play"))
          )
        )
      ),
      filter_scope_stripe(uiOutput(ns("scope_summary")))
    ),

    uiOutput(ns("summary_cards")),
    fluidRow(
      column(6,
        h5("Enrollment by Modality", class = "text-secondary mb-1"),
        plotlyOutput(ns("enrl_modality"), height = "300px")
      ),
      column(6,
        h5("Top Gen Ed Courses by Enrollment", class = "text-secondary mb-1"),
        plotlyOutput(ns("enrl_course"), height = "300px")
      )
    ),
    hr(),
    h5("Department Summary", class = "text-secondary mb-1"),
    uiOutput(ns("dept_table_ui")),
    hr(),
    h5("DFW Rates by Course", class = "text-secondary mb-1"),
    uiOutput(ns("dfw_table_ui")),
    hr(),
    h5("Grade Distribution", class = "text-secondary mb-1"),
    uiOutput(ns("grade_table_ui")),
    hr(),
    h5("Course Associations", class = "text-secondary mb-1"),
    tags$p(
      "For each course, eligible students had no prior major or pre-major in the course department before taking it. Later declared counts students whose first department record appears in that term or later.",
      class = "text-hint"
    ),
    uiOutput(ns("assoc_meta")),
    uiOutput(ns("assoc_table_ui"))
  )
}


deptProfileGenEdUI <- function(id, sections = NULL, current_term = NULL, dept = NULL) {
  ns <- NS(id)
  term_sections <- if (is.null(sections)) NULL else gen_ed_dept_sections(sections, dept)
  term_choices <- if (is.null(term_sections)) c() else gen_ed_term_choices(term_sections, current_term)
  first_term <- if (length(term_choices)) unname(term_choices)[1] else NULL
  last_term <- if (length(term_choices)) unname(term_choices)[length(term_choices)] else NULL

  tagList(
    div(class = "filters-compact mt-filters",
      fluidRow(
        column(2, numericInput(ns("min_n"), "Min N", value = 5, min = 1, max = 100)),
        column(2, selectizeInput(ns("from_term"), "From term",
          choices = term_choices, selected = first_term)),
        column(2, selectizeInput(ns("to_term"), "To term",
          choices = term_choices, selected = last_term)),
        column(2,
          filter_actions(
            actionButton(ns("run"), "Run", class = "btn-primary btn-sm", icon = icon("play"))
          )
        )
      )
    ),
    p(
      "Department-scoped Gen Ed snapshot. Instructor rows are descriptive associations, not causal evidence.",
      class = "text-hint"
    ),
    uiOutput(ns("scope_summary")),
    uiOutput(ns("summary_cards")),
    fluidRow(
      column(6, plotlyOutput(ns("enrl_modality"), height = "260px")),
      column(6, plotlyOutput(ns("enrl_course"), height = "260px"))
    ),
    h5("Course + Instructor Associations", class = "text-secondary mb-1"),
    tags$p(
      "Because this department view can include instructor names, association rows use the same restricted access as instructor DFW.",
      class = "text-hint"
    ),
    uiOutput(ns("assoc_meta")),
    uiOutput(ns("assoc_table_ui")),
    hr(),
    h5("DFW Rates by Course", class = "text-secondary mb-1"),
    uiOutput(ns("dfw_table_ui")),
    hr(),
    h5("Restricted Instructor DFW", class = "text-secondary mb-1"),
    tags$p(
      "Instructor rows are descriptive section outcomes for department Gen Ed courses. Use them to find patterns worth discussing, not as causal evidence of instructor effects.",
      class = "text-hint"
    ),
    uiOutput(ns("instructor_dfw_access"))
  )
}


gen_ed_render_table <- function(data, columns = NULL, defaultPageSize = 10) {
  if (!is.null(columns)) columns <- columns[names(columns) %in% names(data)]
  reactable::reactable(
    data,
    columns = columns,
    defaultPageSize = defaultPageSize,
    striped = TRUE,
    highlight = TRUE,
    searchable = TRUE,
    defaultSorted = NULL,
    theme = cedar_tbl_theme
  )
}


gen_ed_empty_table <- function(message) {
  div(class = "alert-box alert-box--info", message)
}


gen_ed_table_output_or_note <- function(data, output_id, message, label = "table") {
  if (is.null(data) || nrow(data) == 0) return(gen_ed_empty_table(message))
  row_word <- if (nrow(data) == 1L) "row" else "rows"
  tagList(
    p(
      sprintf("%s %s %s available.", format(nrow(data), big.mark = ","), label, row_word),
      class = "text-hint"
    ),
    reactable::reactableOutput(output_id)
  )
}


gen_ed_module_server <- function(input, output, session, students, sections, programs,
                                 degrees, current_term, opt_builder, report_timer_name,
                                 run_id = "run", instructor_dfw_enabled = FALSE,
                                 dfw_password = NULL) {
  data_rv <- reactiveVal(NULL)
  instructor_dfw_authenticated <- reactiveVal(FALSE)
  instructor_dfw_password <- dfw_password %||% Sys.getenv("CEDAR_DFW_PASSWORD", unset = "cedar-dfw-2025")
  associations_require_auth <- function(d) {
    !is.null(d) &&
      !is.null(d$associations) &&
      "instructor_name" %in% names(d$associations)
  }

  output$scope_summary <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(empty_state("Set filters and click Run."))
    m <- d$summary[1, ]
    tagList(
      p(sprintf(
        "%s courses across %s departments. %s registered enrollments from %s distinct students.",
        format(m$n_courses, big.mark = ","),
        format(m$n_departments, big.mark = ","),
        format(m$registered_enrollments, big.mark = ","),
        format(m$n_students, big.mark = ",")
      ), class = "text-hint"),
      p(
        "Enrollment figures use section rows. DFW and grade tables use registered student rows with final grades; associations also need program declaration history and must meet Min N.",
        class = "text-hint"
      )
    )
  })

  observeEvent(input[[run_id]], {
    data_rv(NULL)
    instructor_dfw_authenticated(FALSE)
    timer <- start_report_timer(report_timer_name)
    showNotification("Computing Gen Ed profile...", type = "message",
                     duration = NULL, id = session$ns("loading"))
    result <- tryCatch(
      get_gen_ed_profile(students, sections, programs, degrees, opt_builder()),
      error = function(e) {
        showNotification(paste("Gen Ed profile failed:", e$message), type = "error")
        NULL
      }
    )
    removeNotification(session$ns("loading"))
    data_rv(result)
    if (!is.null(result)) {
      showNotification(
        paste0("Gen Ed profile complete (", round(end_report_timer(timer), 1), "s)"),
        type = "message", duration = 3
      )
    }
  })

  output$summary_cards <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    s <- d$summary[1, ]
    fluidRow(
      column(2, div(class = "stat-card",
        p(format(s$n_courses, big.mark = ","), class = "stat-num"),
        p("gen ed courses", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(format(s$n_departments, big.mark = ","), class = "stat-num"),
        p("departments", class = "stat-lbl")
      )),
      column(2, div(class = "stat-card",
        p(format(s$total_enrl, big.mark = ","), class = "stat-num"),
        p("section enrollment", class = "stat-lbl")
      )),
      column(3, div(class = "stat-card",
        p(format(s$n_students, big.mark = ","), class = "stat-num"),
        p("distinct students", class = "stat-lbl")
      )),
      column(3, div(class = "stat-card",
        p(if (!is.na(s$overall_dfw)) paste0(s$overall_dfw, "%") else "-", class = "stat-num"),
        p("overall DFW rate", class = "stat-lbl")
      ))
    )
  })

  output$enrl_modality <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_modality) > 0)
    ebm <- d$enrl_by_modality
    chrono <- unique(ebm$term_label[order(ebm$term)])
    plot_ly(ebm, x = ~term_label, y = ~enrl, color = ~modality,
            colors = c("F2F" = "#1565c0", "Online" = "#e65100"),
            type = "bar",
            hovertemplate = "%{x}: %{y} %{data.name}<extra></extra>") %>%
      layout(
        barmode = "stack",
        xaxis = list(title = "", tickangle = -45, categoryorder = "array", categoryarray = chrono),
        yaxis = list(title = "Enrollment"),
        legend = list(orientation = "h", x = 0, y = 1.1),
        margin = list(t = 30, b = 70, l = 50, r = 10)
      )
  })

  output$enrl_course <- renderPlotly({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_course) > 0)
    totals <- d$enrl_by_course %>%
      dplyr::group_by(subject_course) %>%
      dplyr::summarize(total = sum(enrl, na.rm = TRUE), .groups = "drop") %>%
      dplyr::slice_max(total, n = 12, with_ties = FALSE)
    ebc <- d$enrl_by_course %>%
      dplyr::filter(subject_course %in% totals$subject_course)
    chrono <- unique(ebc$term_label[order(ebc$term)])
    plot_ly(ebc, x = ~term_label, y = ~enrl, color = ~subject_course,
            type = "scatter", mode = "lines+markers",
            hovertemplate = "%{data.name} %{x}: %{y}<extra></extra>") %>%
      layout(
        xaxis = list(title = "", tickangle = -45, categoryorder = "array", categoryarray = chrono),
        yaxis = list(title = "Enrollment"),
        legend = list(orientation = "v", x = 1.02, y = 1),
        margin = list(t = 20, b = 70, l = 50, r = 130)
      )
  })

  output$dept_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    gen_ed_table_output_or_note(
      d$enrl_by_dept,
      session$ns("dept_table"),
      "No department summary rows are available for this filter scope. If enrollment charts are visible above, check whether the matching section rows are missing department values.",
      "department summary"
    )
  })

  output$dept_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), nrow(d$enrl_by_dept) > 0)
    gen_ed_render_table(d$enrl_by_dept, columns = list(
      department = reactable::colDef(name = "Department"),
      n_courses = reactable::colDef(name = "Courses", align = "right"),
      total_enrl = reactable::colDef(name = "Enrollment", align = "right")
    ))
  })

  output$dfw_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    gen_ed_table_output_or_note(
      d$dfw_by_course,
      session$ns("dfw_table"),
      "No DFW table rows met the current filters and Min N. This table uses registered student enrollment records with final grades, so section enrollment can still appear above when grade rows are unavailable or below the threshold.",
      "DFW"
    )
  })

  output$dfw_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), nrow(d$dfw_by_course) > 0)
    gen_ed_render_table(d$dfw_by_course, columns = list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course"),
      n_enrolled = reactable::colDef(name = "Attempts", align = "right"),
      n_dfw = reactable::colDef(name = "DFW", align = "right"),
      dfw_rate = reactable::colDef(
        name = "DFW Rate", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      n_c_minus = reactable::colDef(name = "C-", align = "right"),
      n_d = reactable::colDef(name = "D", align = "right"),
      n_f = reactable::colDef(name = "F", align = "right"),
      n_w = reactable::colDef(name = "W", align = "right"),
      n_early_drop = reactable::colDef(name = "Early Drops", align = "right"),
      w_pct = reactable::colDef(
        name = "W %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      df_pct = reactable::colDef(
        name = "D/F %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      below_c_pct = reactable::colDef(
        name = "Below C %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      )
    ))
  })

  observeEvent(input$instructor_dfw_submit, {
    if (identical(input$instructor_dfw_password, instructor_dfw_password)) {
      instructor_dfw_authenticated(TRUE)
      showNotification("Access granted", type = "message", duration = 3)
    } else {
      showNotification("Incorrect password. Please try again.", type = "error", duration = 3)
    }
  }, ignoreInit = TRUE)

  output$instructor_dfw_access <- renderUI({
    if (!isTRUE(instructor_dfw_enabled)) return(NULL)

    d <- data_rv()
    if (is.null(d)) {
      return(empty_state("Run the Gen Ed profile before opening restricted instructor outcomes."))
    }

    if (!isTRUE(instructor_dfw_authenticated())) {
      ns <- session$ns
      return(div(
        class = "alert alert-warning",
        style = "margin: 12px 0;",
        h5(icon("lock"), " Access Restricted"),
        p("This section contains instructor-level academic performance data and requires authentication."),
        div(
          style = "display: flex; gap: 10px; align-items: flex-start;",
          div(
            style = "flex: 1; max-width: 300px;",
            passwordInput(ns("instructor_dfw_password"), "", placeholder = "Enter password")
          ),
          actionButton(ns("instructor_dfw_submit"), "Access",
            class = "btn-primary", style = "margin-top: 0; white-space: nowrap;")
        )
      ))
    }

    tagList(
      p(
        "Bars show course averages; dots show instructor averages for the same filtered Gen Ed scope.",
        class = "text-hint"
      ),
      plotlyOutput(session$ns("instructor_dfw_plot"), height = "320px"),
      uiOutput(session$ns("instructor_dfw_table_ui"))
    )
  })

  output$instructor_dfw_plot <- renderPlotly({
    d <- data_rv()
    req(
      isTRUE(instructor_dfw_enabled),
      isTRUE(instructor_dfw_authenticated()),
      !is.null(d),
      !is.null(d$instructor_dfw),
      nrow(d$dfw_by_course) > 0,
      nrow(d$instructor_dfw) > 0
    )

    course_avg <- d$dfw_by_course %>%
      dplyr::mutate(subject_course = factor(subject_course, levels = unique(subject_course)))

    instructor_avg <- d$instructor_dfw %>%
      dplyr::mutate(
        subject_course = factor(subject_course, levels = levels(course_avg$subject_course)),
        hovertext = paste0(
          "Instructor: ", instructor_name,
          "<br>Course: ", subject_course,
          "<br>Instructor DFW: ", round(100 * dfw_rate, 1), "%",
          "<br>Attempts: ", n_attempts,
          "<br>Terms: ", n_terms
        )
      )

    p <- plot_ly() %>%
      add_bars(
        data = course_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~subject_course,
        orientation = "h",
        name = "Course average",
        marker = list(color = "#5b8def"),
        hovertemplate = "Course: %{y}<br>Course DFW: %{x:.1f}%<extra></extra>"
      ) %>%
      add_markers(
        data = instructor_avg,
        x = ~round(100 * dfw_rate, 1),
        y = ~subject_course,
        name = "Instructor average",
        marker = list(size = 8, color = "#c45a1c", opacity = 0.85),
        text = ~hovertext,
        hoverinfo = "text"
      )

    p %>%
      layout(
        barmode = "overlay",
        xaxis = list(title = "DFW %"),
        yaxis = list(title = ""),
        legend = list(orientation = "h", x = 0, y = 1.12),
        margin = list(t = 35, b = 45, l = 80, r = 20)
      )
  })

  output$instructor_dfw_table_ui <- renderUI({
    d <- data_rv()
    if (
      !isTRUE(instructor_dfw_enabled) ||
      !isTRUE(instructor_dfw_authenticated()) ||
      is.null(d)
    ) {
      return(NULL)
    }

    gen_ed_table_output_or_note(
      d$instructor_dfw,
      session$ns("instructor_dfw_table"),
      "No instructor DFW rows met the current filters and Min N. This can happen when course-level rows exist but each instructor group is below the threshold.",
      "instructor DFW"
    )
  })

  output$instructor_dfw_table <- reactable::renderReactable({
    d <- data_rv()
    req(
      isTRUE(instructor_dfw_enabled),
      isTRUE(instructor_dfw_authenticated()),
      !is.null(d),
      !is.null(d$instructor_dfw),
      nrow(d$instructor_dfw) > 0
    )

    gen_ed_render_table(d$instructor_dfw, columns = list(
      subject_course = reactable::colDef(name = "Course"),
      instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
      n_attempts = reactable::colDef(name = "Attempts", align = "right"),
      n_dfw = reactable::colDef(name = "DFW", align = "right"),
      dfw_rate = reactable::colDef(
        name = "Instructor DFW", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      course_dfw_rate = reactable::colDef(
        name = "Course DFW", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      dfw_diff_pp = reactable::colDef(
        name = "Diff", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, " pp") else "-"
      ),
      c_minus_pct = reactable::colDef(
        name = "C- %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      d_pct = reactable::colDef(
        name = "D %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      f_pct = reactable::colDef(
        name = "F %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      w_pct = reactable::colDef(
        name = "W %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      early_drop_pct = reactable::colDef(
        name = "Early Drop %", align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      ),
      n_terms = reactable::colDef(name = "Terms", align = "right")
    ))
  })

  output$grade_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    gen_ed_table_output_or_note(
      d$grade_dist,
      session$ns("grade_table"),
      "No grade distribution rows are available for this scope. This table requires registered student rows with final grades; current/future terms or sparse departments may have section enrollment without grade detail.",
      "grade distribution"
    )
  })

  output$grade_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), nrow(d$grade_dist) > 0)
    gd <- d$grade_dist
    pct_cols <- intersect(paste0(c("A", "B", "C", "D", "F", "W", "Other"), "_pct"), names(gd))
    display <- gd[, intersect(c("department", "subject_course", "total", pct_cols), names(gd)), drop = FALSE]
    cols <- list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course"),
      total = reactable::colDef(name = "Total", align = "right")
    )
    for (pc in pct_cols) {
      cols[[pc]] <- reactable::colDef(
        name = sub("_pct$", "", pc), align = "right",
        cell = function(value) if (!is.na(value)) paste0(value, "%") else "-"
      )
    }
    gen_ed_render_table(display, columns = cols)
  })

  output$assoc_table_ui <- renderUI({
    d <- data_rv()
    if (is.null(d)) return(NULL)
    if (associations_require_auth(d) && !isTRUE(instructor_dfw_authenticated())) {
      return(gen_ed_empty_table(
        "Instructor-level course association rows require authentication. Use the restricted instructor access section on this tab to unlock them."
      ))
    }
    gen_ed_table_output_or_note(
      d$associations,
      session$ns("assoc_table"),
      "No course association rows met the current filters and Min N. This means no qualifying course groups had enough eligible students after excluding students with prior majors or pre-majors in the course department.",
      "course association"
    )
  })

  output$assoc_meta <- renderUI({
    d <- data_rv()
    if (associations_require_auth(d) && !isTRUE(instructor_dfw_authenticated())) {
      return(NULL)
    }
    if (is.null(d) || is.null(d$associations) || nrow(d$associations) == 0) {
      return(NULL)
    }
    total_eligible <- sum(d$associations$n_eligible)
    total_later <- sum(d$associations$n_later_declared)
    p(sprintf(
      "%d groups. %s eligible students, %s later declared (%s%%).",
      nrow(d$associations),
      format(total_eligible, big.mark = ","),
      format(total_later, big.mark = ","),
      formatC(100 * total_later / max(total_eligible, 1), format = "f", digits = 1)
    ), class = "text-hint")
  })

  output$assoc_table <- reactable::renderReactable({
    d <- data_rv()
    req(!is.null(d), !is.null(d$associations), nrow(d$associations) > 0)
    req(!associations_require_auth(d) || isTRUE(instructor_dfw_authenticated()))
    cols <- list(
      department = reactable::colDef(name = "Department"),
      subject_course = reactable::colDef(name = "Course"),
      instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
      n_eligible = reactable::colDef(name = "Eligible", align = "right"),
      n_later_declared = reactable::colDef(name = "Later Declared", align = "right"),
      declaration_pct = reactable::colDef(
        name = "Declaration %", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      pct_of_eligible = reactable::colDef(
        name = "% of Pool", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      ),
      n_terms = reactable::colDef(name = "Terms", align = "right")
    )
    cols <- cols[names(cols) %in% names(d$associations)]
    gen_ed_render_table(d$associations, columns = cols)
  })

  for (output_id in c("dept_table", "dfw_table", "grade_table", "assoc_table",
                      "instructor_dfw_plot", "instructor_dfw_table")) {
    outputOptions(output, output_id, suspendWhenHidden = FALSE)
  }

  data_rv
}


genEdExploreServer <- function(id, students, sections, programs, degrees = NULL,
                               current_term = NULL) {
  moduleServer(id, function(input, output, session) {
    build_terms <- reactive({
      all_terms <- sort(unique(sections$term[!is.na(sections$term)]))
      from_term <- as.integer(input$ge_from_term)
      to_term <- as.integer(input$ge_to_term)
      all_terms[all_terms >= from_term & all_terms <= to_term]
    })

    opt_builder <- reactive({
      list(
        campus = if (length(input$ge_campus) > 0) input$ge_campus else NULL,
        college = if (length(input$ge_college) > 0) input$ge_college else NULL,
        dept = if (length(input$ge_dept) > 0) input$ge_dept else NULL,
        gen_ed_area = if (length(input$ge_gen_ed_area) > 0) input$ge_gen_ed_area else NULL,
        level = if (length(input$ge_level) > 0) input$ge_level else NULL,
        terms = build_terms(),
        min_n = as.integer(input$ge_min_n),
        include_associations = TRUE,
        association_group_cols = c("department", "subject_course")
      )
    })

    gen_ed_module_server(
      input, output, session, students, sections, programs, degrees,
      current_term, opt_builder, "gen-ed-explore", run_id = "ge_button"
    )
  })
}


deptProfileGenEdServer <- function(id, students, sections, programs, degrees = NULL,
                                   dept, campus = NULL, current_term = NULL,
                                   dfw_password = NULL) {
  moduleServer(id, function(input, output, session) {
    observe({
      term_sections <- gen_ed_dept_sections(sections, dept)
      term_choices <- gen_ed_term_choices(term_sections, current_term)
      updateSelectizeInput(session, "from_term",
        choices = term_choices,
        selected = if (length(term_choices)) unname(term_choices)[1],
        server = TRUE
      )
      updateSelectizeInput(session, "to_term",
        choices = term_choices,
        selected = if (length(term_choices)) unname(term_choices)[length(term_choices)],
        server = TRUE
      )
    })

    build_terms <- reactive({
      term_sections <- gen_ed_dept_sections(sections, dept)
      all_terms <- sort(unique(term_sections$term[!is.na(term_sections$term)]))
      if (!is.null(current_term)) all_terms <- all_terms[all_terms <= current_term]
      from_term <- as.integer(input$from_term)
      to_term <- as.integer(input$to_term)
      req(!is.na(from_term), !is.na(to_term))
      all_terms[all_terms >= from_term & all_terms <= to_term]
    })

    opt_builder <- reactive({
      dept_val <- if (is.function(dept)) dept() else dept
      campus_val <- if (is.null(campus)) NULL else if (is.function(campus)) campus() else campus
      req(dept_val, nzchar(dept_val))
      list(
        dept = dept_val,
        campus = if (length(campus_val) > 0) campus_val else NULL,
        level = c("lower", "upper"),
        terms = build_terms(),
        min_n = as.integer(input$min_n),
        include_associations = TRUE,
        include_instructor_dfw = TRUE,
        association_group_cols = c("subject_course", "instructor_name")
      )
    })

    gen_ed_module_server(
      input, output, session, students, sections, programs, degrees,
      current_term, opt_builder, "dept-profile-gen-ed",
      instructor_dfw_enabled = TRUE,
      dfw_password = dfw_password
    )
  })
}
