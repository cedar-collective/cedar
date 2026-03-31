# Shiny Module: Pathways Tab
#
# Population-aware curriculum analytics. The user defines a student population
# (via the Student Population card), then runs any of five analyses:
#
#   Bottlenecks   — courses where population students face unmet enrollment demand
#   Stop-Outs     — courses where a DFW grade predicts leaving the institution
#   Course Timing — when in their academic career population students take each course
#   Course Pairs  — which courses population students commonly take in sequence
#   Major Changes — how students move between programs
#
# Population Trend (new-entrant mix over time) lives in the Dept Dashboard → Demographics tab.
#
# Depends on (sourced before this file via load-funcs.R):
#   R/cones/cohort.R          — build_population(), DEFAULT_HEALTH_PROGRAMS
#   R/cones/bottleneck.R      — get_bottlenecks()
#   R/cones/stopout.R         — get_stopout()
#   R/cones/pathway.R         — get_course_timing(), plot_curriculum_map(), get_course_pairs()
#   R/cones/major-changes.R   — detect_major_changes(), major_change_pathways()
#
# Exported functions:
#   pathwaysUI(id, campus_choices)
#   pathwaysServer(id, students, programs)
#
# Internal sub-module:
#   populationSelectorUI(id, campus_choices)
#   populationSelectorServer(id, programs)  → returns reactive list(population, description)


# =============================================================================
# Population Selector sub-module
# =============================================================================
#
# UI: compact card with program selectors and an "Apply" button.
# Server: calls build_population() on click, returns list(population = tibble, description = string).

populationSelectorUI <- function(id, campus_choices) {
  ns <- NS(id)
  card(
    class = "population-card",
    card_header("Student Population"),

    # ── Population type selector ──────────────────────────────────────────────
    selectInput(
      ns("population_type"), "Select population by",
      choices = c(
        "Major"                  = "major",
        "Department"             = "dept",
        "Major Group (preset)"   = "preset",
        "Demographics"           = "demographic"
      ),
      selected = "major",
      width    = "100%"
    ),

    # ── Major Group mode ──────────────────────────────────────────────────
    conditionalPanel(
      condition = sprintf("input['%s'] == 'preset'", ns("population_type")),
      selectInput(
        ns("preset"), "Major Group",
        choices  = names(COHORT_PRESETS),
        selected = "All Health Programs",
        width    = "100%"
      )
    ),

    # ── Department mode ───────────────────────────────────────────────────
    conditionalPanel(
      condition = sprintf("input['%s'] == 'dept'", ns("population_type")),
      selectizeInput(
        ns("dept_code"), "Department",
        choices = c(),   # populated server-side
        options = list(placeholder = "Type to search...", maxOptions = 300),
        width   = "100%"
      )
    ),

    # ── Specific Majors mode ──────────────────────────────────────────────
    conditionalPanel(
      condition = sprintf("input['%s'] == 'major'", ns("population_type")),
      selectizeInput(
        ns("program_names"), "Majors",
        choices  = c(),  # populated server-side
        multiple = TRUE,
        options  = list(placeholder = "Type to search majors...", maxOptions = 500),
        width    = "100%"
      )
    ),

    # ── Demographics mode ─────────────────────────────────────────────────
    conditionalPanel(
      condition = sprintf("input['%s'] == 'demographic'", ns("population_type")),
      checkboxInput(ns("demo_pell"),      "Ever Pell-Eligible",      value = FALSE),
      checkboxInput(ns("demo_first_gen"), "Ever First-Generation",   value = FALSE),
      selectizeInput(
        ns("demo_time_status"), "Enrollment Intensity",
        choices  = c("Full-time" = "FT", "Part-time" = "PT"),
        multiple = TRUE,
        selected = NULL,
        width    = "100%",
        options  = list(placeholder = "Any (leave blank)")
      ),
      p("All checked filters are combined (AND). Students must match every criterion in at least one term.",
        style = "font-size: 0.8em; color: #666; margin-top: 4px;")
    ),

    # ── Population scope ─────────────────────────────────────────────────
    # Controls which outcome groups and how labels are split.
    # Grayed out for demographic (no focal program → no outcome classification).
    conditionalPanel(
      condition = sprintf("input['%s'] != 'demographic'", ns("population_type")),
      selectInput(
        ns("population_scope"), "Population scope",
        choices  = c(
          "Declared majors only" = "declared",
          "Declared + pre-major" = "all",
          "Pre-major only"       = "pre_only"
        ),
        selected = "declared",
        width    = "100%"
      )
    ),
    conditionalPanel(
      condition = sprintf("input['%s'] == 'demographic'", ns("population_type")),
      div(
        style = "opacity: 0.45; pointer-events: none;",
        selectInput(
          ns("population_scope_na"), "Population scope",
          choices = c("Not available" = ""),
          selected = "",
          width = "100%"
        )
      ),
      p("Outcome filtering requires a major or department selection.",
        style = "font-size: 0.8em; color: #888; margin-top: -6px;")
    ),

    # ── Student level (all modes) ─────────────────────────────────────────
    selectInput(
      ns("student_level"), "Student level",
      choices  = c("All levels" = "", "Undergraduate" = "Undergraduate", "Graduate" = "Graduate"),
      selected = "Undergraduate",
      width    = "100%"
    ),

    # ── Campus (all modes) ────────────────────────────────────────────────
    selectizeInput(
      ns("campus"), "Campus (optional)",
      choices  = c("All campuses" = "", campus_choices),
      multiple = FALSE,
      selected = "ABQ",
      width    = "100%"
    ),

    actionButton(ns("build_btn"), "Apply",
                 class = "btn-primary w-100",
                 icon  = icon("users")),


  ) # end card
}

populationSelectorServer <- function(id, programs, degrees = NULL, students = NULL) {
  moduleServer(id, function(input, output, session) {

    # Populate dept_code, program_names, and term choices server-side
    observe({
      # Departments: sorted by display name, value = dept_code
      dept_codes <- programs %>%
        filter(program_type %in% c("Major", "Second Major"),
                      !is.na(dept_code), nzchar(dept_code)) %>%
        distinct(dept_code) %>%
        pull(dept_code) %>%
        sort()
      dept_names <- dept_code_to_name[dept_codes]
      dept_names[is.na(dept_names)] <- dept_codes[is.na(dept_names)]
      updateSelectizeInput(session, "dept_code",
                           choices = setNames(dept_codes, dept_names),
                           server  = TRUE)

      # All program names — exclude pre-major rows so "Pre-History" doesn't appear
      # alongside "History". After transform normalization both share the same name;
      # pre-major inclusion is controlled by the Population scope dropdown.
      prog_names <- programs %>%
        filter(program_type %in% c("Major", "Second Major"),
                      !is_pre_major,
                      !is.na(program_name), nzchar(program_name)) %>%
        distinct(program_name) %>%
        arrange(program_name) %>%
        pull(program_name)
      updateSelectizeInput(session, "program_names",
                           choices = prog_names,
                           server  = TRUE)

    })

    population_rv <- eventReactive(input$build_btn, {
      type  <- input$population_type %||% "preset"
      scope <- input$population_scope %||% "all"

      # Map UI scope to opt$outcomes
      scope_outcomes <- switch(scope,
        declared = c("graduated", "switched_out", "stopped_out", "ongoing"),
        pre_only = c("chose_elsewhere", "left_undeclared"),
        all      = c("graduated", "switched_out", "stopped_out", "ongoing",
                     "chose_elsewhere", "left_undeclared"),
        c("graduated", "switched_out", "stopped_out", "ongoing",
          "chose_elsewhere", "left_undeclared")  # fallback
      )

      opt <- if (type == "preset") {
        preset <- COHORT_PRESETS[[input$preset]]
        programs_selected <- preset$programs %||% DEFAULT_HEALTH_PROGRAMS
        req(length(programs_selected) > 0)
        list(type = "preset", program_names = programs_selected,
             outcomes = scope_outcomes)

      } else if (type == "dept") {
        req(nzchar(input$dept_code %||% ""))
        list(type = "dept", dept_code = input$dept_code,
             outcomes = scope_outcomes)

      } else if (type == "major") {
        req(length(input$program_names) > 0)
        list(type = "major", program_names = input$program_names,
             outcomes = scope_outcomes)

      } else {  # demographic
        demo_opt <- list(type = "demographic")
        if (isTRUE(input$demo_pell))      demo_opt$pell_eligible <- TRUE
        if (isTRUE(input$demo_first_gen)) demo_opt$first_gen     <- TRUE
        if (length(input$demo_time_status) > 0) demo_opt$time_status <- input$demo_time_status
        if (length(demo_opt) <= 1) {
          showNotification("Select at least one demographic filter.", type = "warning")
          return(NULL)
        }
        demo_opt
      }

      if (nzchar(input$campus        %||% "")) opt$campus        <- input$campus
      if (nzchar(input$student_level %||% "")) opt$student_level <- input$student_level

      # Build plain-English description
      description <- if (type == "preset") {
        paste0("students in ", input$preset)
      } else if (type == "dept") {
        dept_display <- dept_code_to_name[input$dept_code] %||% input$dept_code
        paste0(dept_display, " department students")
      } else if (type == "major") {
        prog_str <- if (length(input$program_names) <= 3) {
          paste(input$program_names, collapse = ", ")
        } else {
          paste0(paste(input$program_names[1:2], collapse = ", "),
                 " + ", length(input$program_names) - 2, " more")
        }
        paste0(prog_str, " students")
      } else {
        filters <- c()
        if (isTRUE(input$demo_pell))      filters <- c(filters, "ever Pell-eligible")
        if (isTRUE(input$demo_first_gen)) filters <- c(filters, "ever first-generation")
        if (length(input$demo_time_status) > 0) {
          ts_labels <- c("FT" = "full-time", "PT" = "part-time")
          filters <- c(filters, paste(ts_labels[input$demo_time_status], collapse = " or "))
        }
        paste0("students who were ", paste(filters, collapse = ", "))
      }

      if (nzchar(input$student_level %||% ""))
        description <- paste0(description, " \u2014 ", tolower(input$student_level))
      if (nzchar(input$campus %||% ""))
        description <- paste0(description, " \u2014 ", input$campus)

      if (type %in% c("preset", "dept", "major")) {
        scope_note <- switch(scope,
          pre_only = "(pre-major only)",
          all      = "(declared + pre-major)",
          NULL
        )
        if (!is.null(scope_note)) description <- paste(description, scope_note)
      }

      message("[pathways module] Building population: type='", type, "', scope='", scope, "'")

      status_message <- create_timing_status_message("pathways-population", "Building student population")
      showNotification(status_message, type = "warning", duration = NULL, id = "pop_loading")
      timer <- start_report_timer("pathways-population")

      result <- tryCatch(
        build_population(programs, degrees = degrees, students = students, opt = opt),
        error = function(e) {
          showNotification(paste("Population build failed:", e$message), type = "error")
          NULL
        }
      )

      duration_sec <- end_report_timer(timer)
      removeNotification("pop_loading")

      if (!is.null(result) && nrow(result) > 0) {
        showNotification(
          paste0(format(nrow(result), big.mark = ","), " students identified (",
                 round(duration_sec, 1), "s)"),
          type = "message", duration = 3
        )
      }

      list(population = result, description = description, opt = opt,
           conversion_stats = attr(result, "conversion_stats"))
    })

    return(population_rv)
  })
}


# =============================================================================
# Pathways tab module — UI
# =============================================================================

pathwaysUI <- function(id, campus_choices) {
  ns <- NS(id)

  tagList(

    div(
      class = "pathways-header",
      tags$h1("Pathways Analysis"),
      tags$p(
        "Define a student population, then explore where they face enrollment barriers, ",
        "which courses pose the biggest risk of departure or grade setback, and how they move through the curriculum over time."
      )
    ),

    layout_sidebar(
      id = "pathways-sidebar-layout",
      # ---- Population selector — always visible in sidebar ----
      sidebar = sidebar(
        width   = 320,
        open    = TRUE,
        populationSelectorUI(ns("population"), campus_choices)
      ),

      # ---- Population status bar (warning OR summary + global term selectors) ----
      uiOutput(ns("population_status")),

      # ---- Analysis sub-panels — main content area ----
      div(class = "pathways-analysis-content",
      navset_tab(
        id       = ns("analysis_tabs"),
        selected = "Population",

        # ---- Population Audit ----
        nav_panel("Population",
          uiOutput(ns("pop_audit_ui"))
        ),

        # ---- Bottlenecks ----
        nav_panel("Bottlenecks",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(3,
                selectizeInput(ns("btn_term"), "Term (optional)",
                               choices  = c("All terms" = ""),
                               multiple = FALSE,
                               selected = "")
              ),
              column(2,
                div(class = "mt-btn",
                  actionButton(ns("btn_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            )
          ),
          p(
            "Courses where population students are waitlisted but hold no registered seat — unmet enrollment demand.",
            "Hedged waitlisters (already registered in another section) are excluded.",
            class = "text-hint"
          ),
          DTOutput(ns("btn_table"))
        ),

        # ---- Roadblocks ----
        nav_panel("Roadblocks",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(3,
                selectInput(ns("so_level"), "Course level",
                            choices  = c("All" = "all", "Undergrad" = "undergrad",
                                         "Lower div" = "lower", "Upper div" = "upper",
                                         "Grad" = "grad"),
                            selected = "undergrad")
              ),
              column(4,
                numericInput(ns("so_min_n"), "Min population students per course",
                             value = 10, min = 5, max = 100, step = 5)
              ),
              column(3,
                numericInput(ns("so_min_dfw_n"), "Min population DFW students",
                             value = 5, min = 1, max = 50, step = 1)
              ),
              column(2,
                div(class = "mt-btn",
                  actionButton(ns("so_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            )
          ),
          uiOutput(ns("so_meta")),

          div(style = "position: relative;",
            tags$h5("Departure Risk",
                    style = "margin-top: 14px; margin-bottom: 2px; font-weight: 600;"),
            p(
              HTML(
                "Courses where students who got a DFW were less likely to return the <strong>following fall or spring</strong> than students who passed — ",
                "compared to the same pattern among all other students in those courses. ",
                "This is a correlation, not a cause: the course may reflect a harder structural barrier rather than being the source of attrition. ",
                "<strong>stopout_gap</strong> = DFW stop-out rate \u2212 pass stop-out rate. ",
                "Sorted by <strong>impact_score</strong> = excess gap \u00d7 DFW count \u2014 balances the size of the disproportionate penalty against how many students are affected. ",
                "Baseline = all non-population students in the same courses. ",
                "Graduates in their degree term are <strong>not counted as stopped out</strong>."
              ),
              style = "font-size: 0.85em; color: #666; margin-top: 4px;"
            ),
            uiOutput(ns("so_recent_term_warn")),
            DTOutput(ns("so_table"))
          ),

          div(style = "position: relative; margin-top: 28px;",
            tags$h5("Grade Setback",
                    style = "margin-bottom: 2px; font-weight: 600;"),
            p(
              HTML(
                "Courses with the highest DFW rates among population students, regardless of whether they predict departure. ",
                "A high DFW rate is a setback even for students who stay — it delays progress and often triggers a retake. ",
                "Baseline columns show DFW rates for all non-population students in the same courses."
              ),
              style = "font-size: 0.85em; color: #666; margin-top: 4px;"
            ),
            DTOutput(ns("dfw_table"))
          )
        ),

        # ---- Course Timing ----
        nav_panel("Course Timing",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(2,
                selectizeInput(ns("ct_subject"), "Subject code (optional)",
                               choices = c(),
                               multiple = TRUE,
                               options  = list(placeholder = "All subjects..."))
              ),
              column(2,
                selectInput(ns("ct_level"), "Course level",
                            choices = c("All" = "all", "Undergrad" = "undergrad",
                                        "Lower div" = "lower", "Upper div" = "upper", "Grad" = "grad"),
                            selected = "undergrad")
              ),
              column(2,
                selectInput(ns("ct_x_axis"), "X-axis",
                            choices  = c(
                              "Total credits (bands)" = "overall_credit_band",
                              "UNM credits (bands)"   = "inst_credit_band",
                              "Relative term"         = "relative_term",
                              "Classification"        = "classification"
                            ),
                            selected = "overall_credit_band")
              ),
              column(2,
                selectizeInput(ns("ct_start_class"), "Starting classification",
                              choices  = c(
                                "All students" = "",
                                "Freshman"     = "Freshman",
                                "Transfer"     = "Transfer",
                                "Sophomore"    = "Sophomore"
                              ),
                              selected = "",
                              options  = list(allowEmptyOption = TRUE))
              ),
              column(1,
                numericInput(ns("ct_max_term"), "Max term",
                             value = 8, min = 4, max = 12, step = 1)
              ),
              column(2,
                numericInput(ns("ct_min_n"), "Min students per course",
                             value = 15, min = 5, max = 500, step = 5)
              ),
              column(1,
                div(class = "mt-btn",
                  actionButton(ns("ct_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            )
          ),
          p(
            "When in their academic career do population students take each course? ",
            "Y-axis = course, sorted by median x-axis position. ",
            "Cell = % of eligible students who took that course at that stage. ",
            tags$em("Relative term: "), "1st, 2nd, 3rd enrolled term from each student's first semester. ",
            tags$em("Classification: "), "Freshman/Sophomore/Junior/Senior at time of enrollment.",
            class = "text-hint"
          ),
          uiOutput(ns("ct_meta")),
          uiOutput(ns("ct_plot_ui")),
          div(style = "margin-top: 20px;",
            DTOutput(ns("ct_table"))
          )
        ),

        # ---- Course Pairs ----
        nav_panel("Course Pairs",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(3,
                selectizeInput(ns("cp_subject"), "Subject code (optional)",
                               choices = c(),
                               multiple = TRUE,
                               options  = list(placeholder = "All subjects..."))
              ),
              column(2,
                selectInput(ns("cp_level"), "Course level",
                            choices = c("All" = "all", "Undergrad" = "undergrad",
                                        "Lower div" = "lower", "Upper div" = "upper", "Grad" = "grad"),
                            selected = "undergrad")
              ),
              column(2,
                numericInput(ns("cp_min_n"), "Min students (course A)",
                             value = 15, min = 5, max = 100, step = 5)
              ),
              column(2,
                numericInput(ns("cp_min_pair"), "Min students (A\u2192B)",
                             value = 10, min = 5, max = 50, step = 5)
              ),
              column(2,
                numericInput(ns("cp_max_gap"), "Max term gap (relative)",
                             value = 2, min = 1, max = 8, step = 1)
              ),
              column(1,
                div(class = "mt-btn",
                  actionButton(ns("cp_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            )
          ),
          p(
            "Ordered course pairs: of population students who took Course A, what fraction later took Course B? ",
            "Sorted by that fraction. Pairs more than max_gap relative terms apart are excluded. ",
            "Non-ongoing students contribute only their enrollment through their last focal term.",
            class = "text-hint"
          ),
          uiOutput(ns("cp_meta")),
          DTOutput(ns("cp_table")),
          uiOutput(ns("cp_sankey_ui"))
        ),

        # ---- Entry Patterns ----
        nav_panel("Entry Patterns",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(4,
                radioButtons(ns("ep_sort"), "Sort by",
                             choices = c("Most common among converters" = "common",
                                         "Most differentiating (lift)"  = "lift"),
                             selected = "lift",
                             inline   = TRUE)
              ),
              column(2,
                numericInput(ns("ep_min_n"), "Min students per course",
                             value = 5, min = 2, max = 50, step = 1)
              ),
              column(2,
                div(class = "mt-btn",
                  actionButton(ns("ep_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            )
          ),
          p(
            "Courses taken in the semester immediately before a student first appeared in the unit. ",
            "Entered = students who eventually declared (any entry path); did not enter = students in the unit\u2019s pool who never declared. ",
            "Lift > 1: course is disproportionately associated with entry. ",
            "This is a correlation \u2014 many factors shape program entry.",
            class = "text-hint"
          ),
          uiOutput(ns("ep_meta")),
          DTOutput(ns("ep_table"))
        ),

        # ---- Major Changes ----
        nav_panel("Major Changes",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(2,
                numericInput(ns("mc_min_n"), "Min students per pathway",
                             value = 3, min = 1, max = 50, step = 1)
              ),
              column(2,
                div(class = "mt-btn",
                  actionButton(ns("mc_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            )
          ),
          p(
            "Major changes made by population students — consecutive terms where program_name differs. ",
            "Only changes involving the focal major on at least one side are shown (arriving to or leaving from). ",
            "Pre-major \u2192 declared transitions within the same major are not counted. ",
            "Undergraduate \u2192 graduate transitions are excluded.",
            class = "text-hint"
          ),

          # ── Summary cards ───────────────────────────────────────────────────
          uiOutput(ns("mc_summary_cards")),

          # ── Trend sparkline + donuts ─────────────────────────────────────────
          fluidRow(
            column(5,
              h6("Changes by Term", class = "text-secondary mb-1"),
              plotlyOutput(ns("mc_trend_plot"), height = "180px")
            ),
            column(7,
              fluidRow(
                column(6,
                  h6("Arriving from", class = "text-secondary mb-1"),
                  plotlyOutput(ns("mc_donut_arriving"), height = "240px")
                ),
                column(6,
                  h6("Leaving for", class = "text-secondary mb-1"),
                  plotlyOutput(ns("mc_donut_leaving"), height = "240px")
                )
              )
            )
          ),

          hr(),

          # ── Per-major flow table ─────────────────────────────────────────────
          h5("Inflow / Outflow by Major"),
          p("\u201cStudents arriving to\u201d = changed INTO that major from somewhere else. \u201cStudents leaving\u201d = changed OUT OF that major. A major can appear in both columns.",
            style = "font-size: 0.8em; color: #888; margin: 2px 0 8px 0;"),
          div(class = "mt-2", DTOutput(ns("mc_flow_table"))),

          hr(class = "mt-btn"),

          # ── A → B pathways ───────────────────────────────────────────────────
          h5("Common Pathways (A \u2192 B)"),
          p("Each row is a from\u2192to pair that occurred at least the minimum number of times. \u201cAvg credits\u201d is the average institutional credits the student had already attempted at the moment of the switch \u2014 a proxy for how far into their degree the change typically happened.",
            style = "font-size: 0.8em; color: #888; margin: 2px 0 8px 0;"),
          div(class = "mt-2", DTOutput(ns("mc_pathways_table"))),

          hr(class = "mt-btn"),

          # ── Student-level detail (collapsed) ─────────────────────────────────
          tags$details(
            tags$summary(
              "Change Event Detail (student-level)",
              style = "cursor: pointer; font-size: 0.88em; color: #888; margin-bottom: 8px;"
            ),
            div(class = "mt-2", DTOutput(ns("mc_changes_table")))
          )
        ),

        # ---- Methodology ----
        nav_panel("Methodology",
          methodology_panel_content()
        )

      ) # end navset_tab
      ) # end pathways-analysis-content div
    ) # end layout_sidebar
  ) # end tagList
}


# =============================================================================
# Methodology panel content
# Static HTML generated from the actual cone code. Update when logic changes.
# =============================================================================

methodology_panel_content <- function() {

  div(style = "max-width: 820px; padding: 16px 4px;",

    # =========================================================================
    tags$h2("How These Analyses Work"),
    tags$p("This page documents exactly how each analysis is computed, derived directly from the source code.
            Use it to interpret results correctly and spot anomalies.",
           style = "color: #555; margin-bottom: 12px;"),

    tags$h3("1. Building a Student Group", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/branches/population.R</code><br>
            <strong>Functions:</strong> <code>build_population()</code> \u2192
            <code>get_focal_programs()</code>,
            <code>get_ongoing_ids()</code>, <code>get_graduated_ids()</code>,
            <code>get_switched_out_ids()</code>, <code>get_never_declared_ids()</code>,
            <code>get_entry_pathways()</code>, <code>classify_origin()</code>,
            <code>classify_entry_method()</code>, <code>classify_entry_status()</code>,
            <code>build_demographic_population()</code>")
    ),

    tags$p(HTML("A student population is built in three stages: (1) identify <em>candidates</em>
                 \u2014 any student who ever appeared in the focal major; (2) <em>classify outcomes</em>
                 \u2014 determine what happened to each candidate relative to the major; (3) <em>filter
                 and label</em> \u2014 include the desired outcome groups and assign labels.
                 The result (a tibble with <code>student_id</code>, <code>population_label</code>,
                 <code>outcome</code>, <code>entry_pathway</code>, <code>origin</code>,
                 <code>entry_method</code>, <code>entry_status</code>, <code>relevant_until</code>)
                 is passed to every downstream analysis.")),

    tags$h4("Outcomes", class = "help-h4"),
    tags$ul(
      tags$li(HTML("<strong>ongoing</strong> \u2014 still declared in the focal major in the most recent data term.")),
      tags$li(HTML("<strong>graduated</strong> \u2014 received a degree in the focal major in their last focal term.")),
      tags$li(HTML("<strong>switched_out</strong> \u2014 left the focal major but remained at UNM. Detected two ways: (1) a formal declaration of another major after their last focal term in <code>cedar_programs</code>; (2) any enrollment record in <code>cedar_students</code> after their last focal term, even without a re-declaration.")),
      tags$li(HTML("<strong>stopped_out</strong> \u2014 all declared candidates not accounted for by ongoing, graduated, or switched_out. No UNM enrollment or major record after their last focal term.")),
      tags$li(HTML("<strong>chose_elsewhere</strong> \u2014 appeared only as a pre-major; never declared the focal major, but did declare a different major afterward.")),
      tags$li(HTML("<strong>left_undeclared</strong> \u2014 appeared only as a pre-major; never declared any major. Left without committing."))
    ),

    tags$h4("Entry pathway (<code>entry_pathway</code>)", class = "help-h4"),
    tags$p("How the student arrived at the focal major — computed by", tags$code("get_entry_pathways()"), ":"),
    tags$ul(
      tags$li(HTML("<strong>direct</strong> \u2014 first major at UNM was the focal major (no prior declared major or pre-major).")),
      tags$li(HTML("<strong>switched_in</strong> \u2014 had a non-focal declared major before declaring the focal major.")),
      tags$li(HTML("<strong>pre_major</strong> \u2014 appeared as a focal pre-major before (or instead of) declaring."))
    ),

    tags$h4("Entry classification columns", class = "help-h4"),
    tags$ul(
      tags$li(HTML("<strong>entry_method</strong> (<code>classify_entry_method()</code>) \u2014 <em>first_program</em>: no prior major record of any kind before this unit; <em>switched_in</em>: had at least one prior major record; <em>unclear</em>: first unit record is at the earliest available term, so prior history is unobservable.")),
      tags$li(HTML("<strong>entry_status</strong> (<code>classify_entry_status()</code>) \u2014 whether the student\u2019s first record in this unit was as a <em>pre_major</em> or a declared <em>major</em>."))
    ),

    tags$h4("Enrollment window (<code>relevant_until</code>)", class = "help-h4"),
    tags$p(HTML("Each non-ongoing population student carries a <code>relevant_until</code> term: their
                 <code>last_declared_term</code> (last term with a declared, non-pre-major focal record).
                 Course enrollments <em>after</em> that term are excluded from all analyses. A student
                 who was History for 2 terms, then switched to Business for 8 terms, contributes only
                 the 2 History terms to the analysis. Ongoing students have
                 <code>relevant_until = NA</code> (no restriction).")),

    tags$h4("Worked example \u2014 dept = HIST, default scope (declared majors)", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("student_id"),
        tags$th("program_name"),
        tags$th("program_type"),
        tags$th("is_pre_major"),
        tags$th("outcome"),
        tags$th("result")
      )),
      tags$tbody(
        tags$tr(tags$td("S001"),tags$td("History"),tags$td("Major"),tags$td("FALSE"),tags$td("ongoing"),tags$td("\u2713 included",class="hl")),
        tags$tr(tags$td("S002"),tags$td("History"),tags$td("Second Major"),tags$td("FALSE"),tags$td("ongoing"),tags$td("\u2713 included (Second Major counts)",class="hl")),
        tags$tr(tags$td("S003"),tags$td("History"),tags$td("Major"),tags$td("TRUE"),tags$td("chose_elsewhere / left_undeclared"),tags$td("\u2014 excluded by default (pre-major only)")),
        tags$tr(tags$td("S004"),tags$td("English"),tags$td("Major"),tags$td("FALSE"),tags$td("\u2014"),tags$td("\u2014 excluded (different dept)")),
        tags$tr(tags$td("S005"),tags$td("History"),tags$td("Minor"),tags$td("FALSE"),tags$td("\u2014"),tags$td("\u2014 excluded (Minor)"))
      )
    ),

    tags$p(HTML("<strong>What programs belong to a department?</strong> The lookup uses
                 <code>cedar_programs$dept_code</code>, which is populated during transformation
                 via a three-tier lookup: major_dept_map \u2192 subj_dept_map \u2192 major_code identity.
                 If a program\u2019s dept_code is missing or wrong, it won\u2019t appear in the dropdown."),
           class = "text-muted-sm"),

    # =========================================================================
    tags$h3("2. Bottlenecks \u2014 Unmet Enrollment Demand", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/cones/bottleneck.R</code><br>
            <strong>Functions:</strong> <code>get_bottlenecks()</code>,
            <code>compute_waitlist_pressure()</code>")
    ),

    tags$p("Counts group students who are waitlisted for a course but hold no registered seat in it.
            These are the students who wanted in and didn\u2019t get in."),

    tags$h4("Exact computation", class = "help-h4"),
    tags$ol(
      tags$li(HTML("Waitlisted = <code>registration_status_code == \u201cWL\u201d</code>")),
      tags$li(HTML("Registered = <code>registration_status_code %in% c(\u201cRE\u201d, \u201cRS\u201d, \u201cRR\u201d)</code>")),
      tags$li(HTML("Pure waitlisters = waitlisted rows that do <em>not</em> also appear as registered
                    in the same course. A student waitlisted for section 002 while registered in
                    section 001 is a <strong>hedged waitlister</strong> and is excluded \u2014 they already
                    have a seat.")),
      tags$li("Count unique student IDs per course among pure waitlisters.")
    ),

    tags$h4("Worked example", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("student_id"),
        tags$th("subject_course"),
        tags$th("status"),
        tags$th("counted?")
      )),
      tags$tbody(
        tags$tr(tags$td("S001"),tags$td("BIOL 2310"),tags$td("WL"),tags$td("\u2713 pure waitlister",class="hl")),
        tags$tr(tags$td("S002"),tags$td("BIOL 2310"),tags$td("WL + RE (other section)"),tags$td("\u2717 hedged \u2014 already registered")),
        tags$tr(tags$td("S003"),tags$td("BIOL 2310"),tags$td("RE"),tags$td("\u2717 not waitlisted"))
      )
    ),
    tags$p("Result: BIOL 2310 \u2192 n_waitlisted = 1 (S001 only)"),

    div(class = "alert-box alert-box--watch",
      tags$strong("\u26a0 Interpretation caution:"),
      " Waitlist data in CEDAR reflects end-of-term snapshots. Students who wanted a course,
       couldn\u2019t get in, and stopped trying do not appear \u2014 they simply have no waitlist record.
       High counts are a real signal; low counts do not confirm demand is met."
    ),

    # =========================================================================
    tags$h3("3. Roadblocks \u2014 DFW as a Predictor of Leaving", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/cones/stopout.R</code><br>
            <strong>Functions:</strong> <code>get_stopout()</code>,
            <code>classify_outcomes()</code>, <code>compute_stopout_for_group()</code>")
    ),

    tags$p(HTML("For each course, compares the fraction of group students who <em>did not return
                 the following term</em> among those who got a DFW grade versus those who passed.
                 The gap between those rates is the key signal.")),

    tags$h4("Step 1: Classify outcomes (per student per course per term)", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("registration_status_code"),
        tags$th("final_grade"),
        tags$th("classified as")
      )),
      tags$tbody(
        tags$tr(tags$td("DR (early drop)"),tags$td("any"),tags$td("dfw \u2014 non-completion regardless of grade",class="hl")),
        tags$tr(tags$td("RE / RS / RR"),tags$td("D, D+, D\u2013, F, W, RD, RF"),tags$td("dfw",class="hl")),
        tags$tr(tags$td("RE / RS / RR"),tags$td("A\u2013C, CR, P, S, RA\u2013RC, RCR"),tags$td("pass",class="hl")),
        tags$tr(tags$td("RE / RS / RR"),tags$td("I, AUD, NR, or other"),tags$td("excluded \u2014 ungraded, no signal")),
        tags$tr(tags$td("WL / other"),tags$td("any"),tags$td("excluded"))
      )
    ),

    tags$h4("Step 2: Determine whether each student returned the following term", class = "help-h4"),
    tags$p(HTML("For each student in each term, we check whether they appear in
                 <code>cedar_students</code> in the <em>next fall or spring</em>.
                 Summer is not counted \u2014 skipping summer is normal and not a stop-out.")),

    tags$h4("Graduate correction", class = "help-h4"),
    tags$p(HTML("Students who earned a degree in term T are <strong>not counted as stopped out</strong>
                 for that term, even though they don\u2019t appear in term T+1. Without this correction,
                 every graduate who finished their program would be misclassified as a stop-out.
                 The correction uses <code>cedar_degrees$term</code> to identify graduation terms.")),
    div(class = "alert-box alert-box--watch",
      tags$strong("\u26a0 Partial coverage:"),
      " Graduate correction only applies to degrees recorded in CEDAR. Students who
        transferred out or completed credentials not in cedar_degrees will still appear as stop-outs."
    ),

    tags$h4("Step 3: Compute rates and gap", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("student_id"),
        tags$th("BIOL 2310 outcome"),
        tags$th("returned next term?")
      )),
      tags$tbody(
        tags$tr(tags$td("S001"),tags$td("pass (A)"),tags$td("yes")),
        tags$tr(tags$td("S002"),tags$td("pass (B)"),tags$td("no")),
        tags$tr(tags$td("S003"),tags$td("dfw (F)"),tags$td("yes")),
        tags$tr(tags$td("S004"),tags$td("dfw (W)"),tags$td("no")),
        tags$tr(tags$td("S005"),tags$td("dfw (W)"),tags$td("no"))
      )
    ),
    tags$p(HTML(
      "<strong>pass_stopout_rate</strong> = 1/2 = 0.500 (S002 didn\u2019t return)<br>
       <strong>dfw_stopout_rate</strong> = 2/3 = 0.667 (S004, S005 didn\u2019t return)<br>
       <strong>stopout_gap</strong> = 0.667 \u2212 0.500 = 0.167<br>
       <strong>p_value</strong>: chi-squared test on the 2\u00d72 contingency table (outcome \u00d7 returned).
       Skipped if either group has fewer than 5 students \u2014 result is NA."
    )),

    div(class = "alert-box alert-box--watch",
      tags$strong("\u26a0 Known anomalies to watch for:"),
      tags$ul(class = "mt-1",
        tags$li("The most recent term in the data has no visible \u2018next term,\u2019 so all students
                  in that term appear as stopped out. This inflates stop-out rates for recently
                  active courses."),
        tags$li(HTML("Rows where <code>pop_n_dfw</code> is very small (1\u20134) produce
                       unreliable rates. The Min group DFW students filter (default 5) removes these.")),
        tags$li("The baseline is ALL non-group students in the same courses."),
        tags$li("Stop-out is measured as \u2018returned to UNM,\u2019 not \u2018continued in the program.\u2019")
      )
    ),

    # =========================================================================
    tags$h3("4. Course Timing \u2014 When Students Take Each Course", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/cones/pathway.R</code><br>
            <strong>Functions:</strong> <code>get_course_timing()</code>,
            <code>plot_curriculum_map()</code>")
    ),

    tags$p(HTML("Computes the fraction of group students who took each course in their
                 1st, 2nd, 3rd\u2026 <em>enrolled</em> term. Uses relative terms so students who
                 started in different calendar years are aligned on the same axis.")),

    tags$h4("How \u201cterm 1\u201d is defined", class = "help-h4"),
    tags$p(HTML("Relative term 1 is the <strong>first term in which the student has a registered
                 course record in <code>cedar_students</code></strong> \u2014 not their first semester
                 at UNM, not their first semester in the program, and not any self-reported
                 start date. It is <code>row_number()</code> over their distinct enrolled terms,
                 sorted chronologically by UNM term code.")),

    tags$h4("Skipped semesters", class = "help-h4"),
    tags$p("The counter only increments for terms with actual registered enrollment.
            Gaps are invisible. A student enrolled in Fall, absent in Spring, enrolled in Fall
            has relative terms 1 and 2 \u2014 not 1 and 3. There is no concept of
            \u201cmissed term 2\u201d in this model."),

    tags$h4("Summer terms", class = "help-h4"),
    tags$p(HTML("By default, summer does <em>not</em> advance the counter.
                 Summer courses are pinned to the relative term of the immediately preceding
                 fall or spring. A student taking a summer course between their 2nd and 3rd
                 fall/spring semesters has those summer courses recorded as relative term 2.
                 If \u201cInclude summer\u201d is enabled, summer gets its own slot in the sequence.")),

    tags$h4("Denominator", class = "help-h4"),
    tags$p(HTML("For each relative term, the denominator is the number of group students who
                 <em>reached</em> that term \u2014 i.e., students whose enrollment record extends
                 to at least that relative term. Students with only 3 terms of data are excluded
                 from relative terms 4\u20138. This prevents the percentage from being artificially
                 deflated for later terms.")),

    div(class = "alert-box alert-box--watch",
      tags$strong("\u26a0 Left-truncation artifact \u2014 Freshman filter is applied automatically:"),
      tags$p(HTML("Students who were already enrolled when CEDAR data begins (Fall 2018) have
                   relative term 1 set to Fall 2018, regardless of how long they had actually
                   been at UNM. A senior in Fall 2018 looks like a first-semester student, which
                   makes the chart meaningless. This is called <em>left truncation</em>."), class = "mt-1"),
      tags$p(HTML("To prevent this, the app <strong>automatically restricts the relative-term axis
                   to first-time freshmen</strong> \u2014 students whose first enrollment record in CEDAR
                   is classified as Freshman. These are the only students whose term 1 is genuinely
                   their first semester. You can override this by selecting a different
                   Starting Classification in the filters."), class = "mt-1"),
      tags$p(HTML("This filter does <em>not</em> apply to the Classification, Inst. Credits, or
                   Overall Credits x-axis modes \u2014 those use actual Banner values recorded at the
                   time of enrollment and are unaffected by when the data window starts."), class = "mt-1")
    ),

    # =========================================================================
    tags$h3("5. Course Pairs \u2014 Common Sequences", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/cones/pathway.R</code><br>
            <strong>Function:</strong> <code>get_course_pairs()</code>")
    ),

    tags$p(HTML("Finds ordered pairs (A \u2192 B) where group students took Course A in one
                 relative term and Course B in a later term, within a configurable term gap.")),

    tags$h4("Exact computation", class = "help-h4"),
    tags$ol(
      tags$li(HTML("Self-join enrolled records on <code>student_id</code> where
                    <code>term_B &gt; term_A</code> and
                    <code>term_B \u2212 term_A \u2264 max_term_gap</code> and
                    <code>course_A \u2260 course_B</code>.")),
      tags$li("Count distinct students per (course_A, course_B) pair."),
      tags$li(HTML("<strong>pct_a_to_b</strong> = students who took both \u00f7 students who took A."))
    ),

    div(class = "alert-box alert-box--watch",
      tags$strong("\u26a0 This is correlation, not causation."),
      " A high pct_a_to_b means students who took A commonly went on to take B.
        It does not mean A is a prerequisite for B or that taking A causes students to take B."
    ),

    # =========================================================================
    tags$h3("6. Major Changes", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>Files:</strong>
            <code>R/cones/major-changes.R</code> (detection and summarization),
            <code>R/branches/population.R</code> (group building),
            <code>R/modules/pathways.R</code> (focal program derivation and display)<br>
            <strong>Key functions:</strong> <code>detect_major_changes()</code>,
            <code>major_change_pathways()</code>")
    ),

    tags$p("Detects when a student\u2019s primary declared major changed from one term to the next,
            then summarizes those transitions for the selected student group."),

    tags$h4("Step 1: Detect change events", class = "help-h4"),
    tags$p(HTML("Source: <code>detect_major_changes()</code> in <code>R/cones/major-changes.R</code>.")),
    tags$ol(
      tags$li(HTML("Filter <code>cedar_programs</code> to <code>program_type == \u201cMajor\u201d</code>
                    rows for the population students only.")),
      tags$li(HTML("Sort by <code>student_id</code>, <code>term</code>. Use <code>lag()</code> to get
                    each student\u2019s program in the prior term (<code>prev_major</code>) and their prior
                    academic level (<code>prev_level</code>).")),
      tags$li(HTML("Flag a change when <code>program_name != prev_major</code> AND
                    <code>(is.na(prev_level) | student_level == prev_level)</code>. The level
                    check excludes transitions between undergraduate and graduate programs \u2014
                    a History BA student enrolling in Law School is not a \u201cmajor change\u201d
                    in the undergraduate sense. <code>is.na(prev_level)</code> passes the first
                    record per student through since there is no prior level to compare.")),
      tags$li(HTML("Each flagged row becomes one change event with: <code>student_id</code>,
                    <code>change_term</code>, <code>from_major</code>, <code>to_major</code>,
                    <code>credits_at_change</code> (institutional credits attempted at the time)."))
    ),

    tags$h4("Worked example \u2014 History student program history", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("student_id"),
        tags$th("term"),
        tags$th("program_name"),
        tags$th("student_level"),
        tags$th("prev_major"),
        tags$th("result")
      )),
      tags$tbody(
        tags$tr(tags$td("S001"),tags$td("202310"),tags$td("Psychology"),tags$td("Undergraduate"),tags$td("(none)"),tags$td("\u2014 first term, no change")),
        tags$tr(tags$td("S001"),tags$td("202380"),tags$td("Psychology"),tags$td("Undergraduate"),tags$td("Psychology"),tags$td("\u2014 same major")),
        tags$tr(tags$td("S001"),tags$td("202410"),tags$td("History"),tags$td("Undergraduate"),tags$td("Psychology"),tags$td("\u2713 change event: Psych \u2192 History",class="hl")),
        tags$tr(tags$td("S001"),tags$td("202480"),tags$td("History"),tags$td("Undergraduate"),tags$td("History"),tags$td("\u2014 same major")),
        tags$tr(tags$td("S001"),tags$td("202710"),tags$td("Juris Doctor"),tags$td("Graduate/GASM"),tags$td("History"),tags$td("\u2014 level changed (UG\u2192GR), excluded"))
      )
    ),

    tags$h4("Step 2: Derive focal majors", class = "help-h4"),
    tags$p(HTML("Source: <code>mc_data</code> reactive in <code>R/modules/pathways.R</code>.")),
    tags$p(HTML("Focal majors are the majors that <em>define</em> the selected student group \u2014
                 not all majors ever held by group members. A History cohort student who also
                 declared Political Science should not make PolSci a focal major.")),
    tags$ul(
      tags$li(HTML("<strong>Dept mode</strong> (e.g., HIST): all majors where
                    <code>dept_code == \u201cHIST\u201d</code> and <code>program_type %in%
                    c(\u201cMajor\u201d, \u201cSecond Major\u201d)</code> in <code>cedar_programs</code>.")),
      tags$li(HTML("<strong>Specific majors mode</strong>: exactly the majors the user selected
                    in the sidebar.")),
      tags$li(HTML("<strong>Preset mode</strong>: the <code>program_names</code> list from
                    the population opt."))
    ),

    tags$h4("Step 3: Filter to focal changes", class = "help-h4"),
    tags$p(HTML("From the full set of change events, keep only rows where
                 <code>from_major %in% focal_programs OR to_major %in% focal_programs</code>.
                 This means a History cohort sees:")),
    tags$ul(
      tags$li("Psychology \u2192 History (arriving to History) \u2713"),
      tags$li("History \u2192 Political Science (leaving History) \u2713"),
      tags$li("Political Science \u2192 Law (made by a History student, but neither side is History) \u2717 excluded")
    ),

    tags$h4("Step 4: Build summary outputs", class = "help-h4"),
    tags$p(HTML("Source: <code>major_change_pathways()</code> in <code>R/cones/major-changes.R</code>.")),
    tags$ul(
      tags$li(HTML("<strong>Inflow / Outflow table</strong>: count distinct <code>to_major</code>
                    (arrivals) and <code>from_major</code> (departures) in focal changes, then filter
                    to rows where the major is in focal_programs. Net = arrivals \u2212 departures.")),
      tags$li(HTML("<strong>Common Pathways table</strong>: group focal changes by
                    (from_major, to_major), count events, compute <code>avg_credits</code> =
                    average <code>inst_credits_attempted</code> at the moment of the switch.
                    Minimum threshold (default 3) removes rare pairs.")),
      tags$li(HTML("<strong>Avg credits</strong> is a proxy for timing: 30 credits \u2248 freshman year,
                    60 \u2248 sophomore, 90 \u2248 junior. A History \u2192 Political Science pair at 75 credits
                    means students are switching in their junior year on average.")),
      tags$li(HTML("<strong>Trend sparkline</strong>: per-term count of arrivals
                    (<code>to_major %in% focal</code>, green) and departures
                    (<code>from_major %in% focal</code>, red).")),
      tags$li(HTML("<strong>Donuts</strong>: \u201cLeaving for\u201d = top non-focal <code>to_major</code>
                    values among departures. \u201cArriving from\u201d = top non-focal <code>from_major</code>
                    values among arrivals. Students cycling between focal majors are excluded
                    from the donuts to avoid self-referential loops."))
    ),

    tags$h4("Worked example \u2014 Inflow / Outflow for a History dept cohort", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("major"),
        tags$th("students arriving to"),
        tags$th("students leaving for elsewhere"),
        tags$th("net")
      )),
      tags$tbody(
        tags$tr(tags$td("History",class="hl"),tags$td("47"),tags$td("31"),tags$td("+16",class="hl")),
        tags$tr(tags$td("History / Pre-Law",class="hl"),tags$td("5"),tags$td("12"),tags$td("\u22127"))
      )
    ),
    tags$p("Only History-dept programs appear. The 47 arriving students came from other majors;
            the 31 departures went to other majors (shown in the \u201cLeaving for\u201d donut).",
           class = "text-muted-sm"),

    div(class = "alert-box alert-box--watch",
      tags$strong("\u26a0 Known edge cases:"),
      tags$ul(class = "mt-1",
        tags$li("A student who switched History \u2192 PolSci \u2192 History generates two change events.
                  Both appear in the tables. The net can mask churn."),
        tags$li("Pre-major \u2192 declared transitions within the same program are not flagged
                  as changes (same program_name, different is_pre_major flag)."),
        tags$li("The minimum event threshold (sidebar) removes pairs with fewer than N events.
                  Rare pathways that may still be meaningful are hidden. Lower the threshold to see them.")
      )
    ),

    # =========================================================================
    div(class = "alert-box alert-box--code",
      style = "margin-top: 32px;",
      tags$strong("Reading this with Claude or GitHub Copilot:"),
      tags$p(HTML("Each section above names the exact file and function that implements it.
              To go deeper, open the file in your editor, select the function body, and ask
              \u201cexplain this function\u201d or \u201cwhat does this do step by step?\u201d
              All functions have parameter descriptions in the header comment.<br><br>
              For a fuller picture, paste the function into Claude along with a specific question \u2014
              for example: \u201cWhy does <code>get_switched_out_ids()</code> use <code>last_focal_term + 100</code>
              as an upper bound?\u201d or \u201cWhat edge cases does the enrollment-based switch detection handle
              that the program-record check misses?\u201d The code is designed to be readable; the AI fills
              in the reasoning."),
             class = "mt-1")
    ),

    tags$p(style = "margin-top: 16px; font-size: 0.8em; color: #888; border-top: 1px solid #eee; padding-top: 12px;",
      HTML("Methodology reflects: <code>R/branches/population.R</code> (group builder),
            <code>R/cones/bottleneck.R</code>, <code>R/cones/stopout.R</code>,
            <code>R/cones/pathway.R</code>, <code>R/cones/major-changes.R</code>,
            and <code>R/modules/pathways.R</code> (display logic).
            Update this panel when cone logic changes."))

  ) # end div
}


# =============================================================================
# Pathways tab module — server
# =============================================================================

pathwaysServer <- function(id, students, programs, degrees = NULL,
                           cedar_grades = NULL, cedar_next_term = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Population selector sub-module ----
    population_rv <- populationSelectorServer("population", programs,
                                               degrees = degrees, students = students)

    # Convenience accessors
    get_population  <- function() population_rv()$population
    get_description <- function() population_rv()$description

    # When a split population has multiple labels, the user can narrow to one
    # group via the status-bar group filter. All cone calls use this instead of
    # get_population() so the analysis reflects the selected subgroup.
    #
    # Entry-method split: unclear students are silently excluded.
    # These are students whose first program record falls at the earliest term
    # in the dataset — their prior history is unobservable, so we cannot
    # confirm they were first_program vs switched_in. Including them would
    # misrepresent the entry_method groups. The count is surfaced in the sidebar
    # and status bar so users know how many were set aside.
    get_analysis_population <- reactive({
      pop <- get_population()
      if (is.null(pop)) return(NULL)

      split_by <- population_rv()$opt$split_by %||% "none"
      if (split_by == "entry" && "entry_method" %in% names(pop))
        pop <- filter(pop, entry_method != "unclear")

      sel <- input$global_group_filter %||% "all"
      if (sel == "all" || sel == "" || !sel %in% pop$population_label) return(pop)
      pop[pop$population_label == sel, ]
    })

    # TRUE once population has been successfully built
    population_built <- reactive({
      tryCatch({
        rv <- population_rv()
        !is.null(rv) && !is.null(rv$population)
      }, error = function(e) FALSE)
    })

    output$population_status <- renderUI({
      if (!population_built()) {
        return(div(
          class = "alert alert-info",
          style = "margin: 0 0 4px 0;",
          tags$strong("Define your student population first."),
          " Choose programs in the sidebar and click ",
          tags$strong("Apply"),
          " before running any analysis."
        ))
      }

      population <- population_rv()$population
      description <- get_description()
      n_total <- format(nrow(population), big.mark = ",")
      opt      <- population_rv()$opt

      # Focal program codes — show how students were matched and which major codes
      # the selection resolved to in cedar_programs.
      focal_codes_result <- {
        # Build human-readable description of the matching criterion
        match_basis <- if (opt$type == "dept") {
          paste0("cedar_programs.dept_code = \u201c", opt$dept_code, "\u201d")
        } else if (opt$type %in% c("major", "preset") &&
                   length(opt$program_names %||% character(0)) > 0) {
          nms <- opt$program_names
          if (length(nms) == 1) {
            paste0("cedar_programs.program_name = \u201c", nms, "\u201d")
          } else {
            paste0("cedar_programs.program_name \u2208 {",
                   paste(nms, collapse = ", "), "}")
          }
        } else NULL

        prog_detail <- if (opt$type == "dept") {
          programs %>%
            filter(program_type %in% c("Major", "Second Major"),
                          dept_code == opt$dept_code) %>%
            distinct(major_code, program_name) %>%
            arrange(major_code)
        } else if (opt$type %in% c("major", "preset") &&
                   length(opt$program_names %||% character(0)) > 0) {
          programs %>%
            filter(program_type %in% c("Major", "Second Major"),
                          program_name %in% opt$program_names) %>%
            distinct(major_code, program_name) %>%
            arrange(major_code)
        } else {
          NULL
        }

        if (!is.null(prog_detail) && nrow(prog_detail) > 0) {
          # Exclude numeric major_codes (Banner internal org IDs that leaked into
          # source data — same logic the transform uses to nullify numeric dept_codes).
          coded   <- filter(prog_detail,
                                   !is.na(major_code),
                                   !grepl("^[0-9]+$", major_code))
          uncoded <- filter(prog_detail,
                                   is.na(major_code) | grepl("^[0-9]+$", major_code))
          # Suppress the warning for programs that already resolved to a code in
          # other records — Banner sometimes omits the code column in older exports,
          # producing mixed coded/uncoded rows for the same program name.
          uncoded <- filter(uncoded, !program_name %in% coded$program_name)
          MAX_SHOW <- 8L
          pairs <- paste0(coded$major_code, "\u00a0(", coded$program_name, ")")
          coded_text <- if (nrow(coded) == 0) NULL else if (length(pairs) > MAX_SHOW) {
            paste0(paste(pairs[seq_len(MAX_SHOW)], collapse = " \u00b7 "),
                   " \u00b7 \u2026 +", nrow(coded) - MAX_SHOW, " more")
          } else {
            paste(pairs, collapse = " \u00b7 ")
          }
          list(match_basis  = match_basis,
               coded_text   = coded_text,
               uncoded      = if (nrow(uncoded) > 0) uncoded$program_name else NULL)
        } else NULL
      }

      # Program record span — shows what time window population students appear in cedar_programs
      prog_span <- programs %>%
        filter(student_id %in% population$student_id) %>%
        summarize(from = min(term, na.rm = TRUE), to = max(term, na.rm = TRUE))

      split_by  <- population_rv()$opt$split_by %||% "none"
      n_unclear <- if ("entry_method" %in% names(population))
        sum(population$entry_method == "unclear", na.rm = TRUE) else 0L

      # Build label breakdown for split populations
      label_breakdown <- if (split_by != "none" && length(unique(population$population_label)) > 1) {
        counts <- population %>%
          group_by(population_label) %>%
          summarize(n = n(), .groups = "drop") %>%
          arrange(desc(n))
        paste(counts$population_label, format(counts$n, big.mark = ","), sep = ": ", collapse = " / ")
      } else NULL

      # Outcome breakdown — "180 ongoing · 42 grad · 129 switched out · 385 stopped out"
      has_outcomes <- "outcome" %in% names(population) && any(!is.na(population$outcome))
      outcome_breakdown <- if (has_outcomes) {
        outcome_order  <- c("ongoing", "graduated", "switched_out", "stopped_out",
                            "chose_elsewhere", "left_undeclared")
        outcome_abbrev <- c(
          ongoing        = "ongoing",
          graduated      = "graduated",
          switched_out    = "switched out",
          stopped_out     = "stopped out",
          chose_elsewhere = "chose elsewhere",
          left_undeclared = "left undeclared"
        )
        oc <- population %>%
          count(outcome) %>%
          arrange(match(outcome, outcome_order))
        paste(
          sapply(seq_len(nrow(oc)), function(i)
            paste0(format(oc$n[i], big.mark = ","), "\u00a0",
                   outcome_abbrev[[oc$outcome[i]]] %||% oc$outcome[i])
          ),
          collapse = " \u00b7 "
        )
      } else NULL

      has_windowed <- has_outcomes &&
        any(c("stopped_out", "switched_out") %in% population$outcome)

      div(
        class = "alert alert-success",
        style = "margin: 0 0 4px 0; padding: 10px 16px;",
        # --- Top row: Program Records and Analysis Through — single continuous line ---
        div(
          style = "color: #2d6a2d; font-size: 1em; margin-bottom: 2px;",
          tags$strong("Program records: "),
          fmt_term(prog_span$from), " \u2013 ", fmt_term(prog_span$to),
          if (!is.null(analysis_through)) {
            max_data_term <- max(programs$term, na.rm = TRUE)
            tagList(
              tags$span(style = "margin: 0 8px; color: #5a9a5a;", "\u00b7"),
              tags$strong("Analysis through: "),
              fmt_term(analysis_through),
              if (max_data_term > analysis_through)
                tags$span(
                  style = "color: #5a7a5a; font-size: 0.875em; margin-left: 6px;",
                  paste0("(", fmt_term(max_data_term), " confirms ongoing status only)")
                )
            )
          }
        ),
        # --- Second row: Number of students (large font) and description ---
        div(
          style = "display: flex; align-items: baseline; flex-wrap: wrap; gap: 16px; margin-bottom: 2px;",
          tags$span(style = "font-size: 1.5em; font-weight: 600; color: #145214;", n_total, " students"),
          tags$span(style = "margin-left: 8px; color: #2d6a2d; font-size: 1em;", description)
        ),
        # --- Split breakdown (only when split is active) ---
        if (!is.null(label_breakdown)) {
          div(
            style = "color: #2d6a2d;",
            tags$strong("Groups: "),
            label_breakdown
          )
        },
        # --- Group filter selector (only when split is active) ---
        if (split_by != "none" && length(unique(population$population_label)) > 1) {
          div(
            style = "display: flex; align-items: center; gap: 6px;",
            tags$strong("Analyze group:"),
            selectInput(ns("global_group_filter"), NULL,
                        choices  = c("All groups" = "all",
                                     sort(unique(population$population_label))),
                        selected = input$global_group_filter %||% "all",
                        width    = "160px")
          )
        },
        # --- Matching basis + resolved program codes ---
        if (!is.null(focal_codes_result)) {
          div(
            style = "margin-top: 6px; font-size: 0.8em; color: #2d6a2d; border-top: 1px solid #b2d8b2; padding-top: 6px;",
            tags$strong("Matched on: "),
            focal_codes_result$match_basis,
            tags$span(style = "color: #5a7a5a;", " (Major + Second Major records only)"),
            if (!is.null(focal_codes_result$coded_text)) tagList(
              tags$br(),
              tags$strong("Resolved to: "),
              focal_codes_result$coded_text
            ),
            if (!is.null(focal_codes_result$uncoded)) tags$span(
              style = "margin-left: 8px; color: #b07000; font-style: italic;",
              paste0(paste(focal_codes_result$uncoded, collapse = ", "),
                     ": matched by program name only \u2014 no major code found in any record")
            )
          )
        },
        # --- Outcome counts (always shown for program-based populations) ---
        if (!is.null(outcome_breakdown)) {
          div(
            style = "margin-top: 6px; font-size: 0.875em; color: #2d6a2d; border-top: 1px solid #b2d8b2; padding-top: 6px;",
            outcome_breakdown,
            if (has_windowed) tags$span(
              style = "margin-left: 12px; color: #5a7a5a; font-style: italic;",
              "Stopped-out and switched-out students are included only through their last focal term."
            )
          )
        },
        # --- Left-truncation note (only when entry split is active) ---
        if (split_by == "entry" && n_unclear > 0) {
          div(
            style = "margin-top: 6px; font-size: 0.85em; color: #5a7a5a; border-top: 1px solid #b2d8b2; padding-top: 6px;",
            tags$strong(format(n_unclear, big.mark = ","),
                        if (n_unclear == 1) " student excluded" else " students excluded"),
            " from pathway groups \u2014 their records begin at the earliest available term,",
            " so whether they arrived directly or switched in cannot be confirmed from the data."
          )
        }
      )
    })

    # Modal guard — show a blocking dialog if any Run button is clicked before a population is built
    walk(c("btn_run", "so_run", "ct_run", "cp_run", "mc_run"), function(btn_id) {
      observeEvent(input[[btn_id]], {
        if (!population_built()) {
          showModal(modalDialog(
            title = "No population defined",
            p("You need to define a student population before running analysis."),
            p("Use the ", tags$strong("Student Population"), " panel on the left:"),
            tags$ol(
              tags$li("Choose a selection type (Major Group, Department, etc.)"),
              tags$li("Select your majors or filters"),
              tags$li("Click ", tags$strong("Apply"))
            ),
            footer = modalButton("Got it"),
            easyClose = TRUE
          ))
        }
      }, ignoreInit = TRUE)
    })

    # ---- Auto-run on population rebuild ----
    #
    # When the user rebuilds a population (clicks Apply a second time), the
    # current analysis tab is stale. Re-run it automatically so the user doesn't
    # have to manually click Run again.
    #
    # has_prior_population: TRUE once any population has been built. On the first
    # Apply there is nothing to re-run; we only auto-trigger on subsequent ones.
    has_prior_population <- reactiveVal(FALSE)

    btn_auto <- reactiveVal(0L)
    so_auto  <- reactiveVal(0L)
    ct_auto  <- reactiveVal(0L)
    cp_auto  <- reactiveVal(0L)
    mc_auto  <- reactiveVal(0L)

    observeEvent(population_rv(), {
      prior <- has_prior_population()
      has_prior_population(TRUE)
      if (!prior) return()

      switch(input$analysis_tabs,
        "Bottlenecks"   = btn_auto(btn_auto() + 1L),
        "Roadblocks"    = so_auto(so_auto()   + 1L),
        "Course Timing" = ct_auto(ct_auto()   + 1L),
        "Course Pairs"  = cp_auto(cp_auto()   + 1L),
        "Major Changes" = mc_auto(mc_auto()   + 1L)
      )
    }, ignoreInit = TRUE)

    # Global term filter — applied to all analysis reactives.
    #
    # Enrollment filter — applied to all analysis reactives.
    #
    # The current in-progress term is always excluded: stop-out and graduation
    # outcomes require a future term to measure against, so including the current
    # term produces false stop-outs for every student still enrolled. This cap is
    # a correctness constraint, not a user preference.
    #
    # Per-student enrollment window: students who left their focal program have
    # a `relevant_until` term ceiling in the population data frame. Enrollments
    # after that term are excluded so a student who was History for 2 terms then
    # switched to Business doesn't contribute their Business career to the
    # History analysis. Ongoing students (relevant_until = NA) are unrestricted.
    analysis_through <- tryCatch(subtract_term(cedar_current_term), error = function(e) NULL)

    filtered_students <- reactive({
      s <- students
      if (!is.null(analysis_through)) s <- filter(s, term <= analysis_through)

      pop <- tryCatch(population_rv()$population, error = function(e) NULL)
      if (!is.null(pop) && nrow(pop) > 0 && "relevant_until" %in% names(pop)) {
        bounded <- pop %>%
          filter(!is.na(relevant_until)) %>%
          select(student_id, relevant_until)
        if (nrow(bounded) > 0) {
          # Single left join: all rows pass through; bounded students get a
          # relevant_until value which is used to drop rows after their ceiling.
          # Faster than split-and-bind when s is already pre-filtered to pop IDs;
          # at full-table scale the join still beats two full-table scans + bind_rows.
          s <- s %>%
            left_join(bounded, by = "student_id") %>%
            filter(is.na(relevant_until) | term <= relevant_until) %>%
            select(-relevant_until)
        }
      }

      s
    })

    # Pre-windowed cedar_grades: apply the same analysis_through + relevant_until
    # windowing as filtered_students, but to the pre-classified grade table.
    # This is passed to get_stopout/get_dfw_rates so they skip the expensive
    # classify_outcomes(1.7M rows) call entirely.
    # Returns NULL if cedar_grades was not loaded (file doesn't exist yet).
    filtered_cedar_grades <- reactive({
      g <- cedar_grades
      if (is.null(g) || nrow(g) == 0) return(NULL)

      if (!is.null(analysis_through)) g <- filter(g, term <= analysis_through)

      pop <- tryCatch(population_rv()$population, error = function(e) NULL)
      if (!is.null(pop) && nrow(pop) > 0 && "relevant_until" %in% names(pop)) {
        bounded <- pop %>%
          filter(!is.na(relevant_until)) %>%
          select(student_id, relevant_until)
        if (nrow(bounded) > 0) {
          g <- g %>%
            left_join(bounded, by = "student_id") %>%
            filter(is.na(relevant_until) | term <= relevant_until) %>%
            select(-relevant_until)
        }
      }
      g
    })

    # Populate term choices once the app loads
    observe({
      term_vals <- sort(unique(students$term), decreasing = TRUE)
      choices   <- c("All terms" = "", setNames(term_vals, term_vals))
      updateSelectizeInput(session, "btn_term", choices = choices, server = TRUE)
    })

    # Populate subject code choices for course timing and pairs
    observe({
      subjects <- sort(unique(sub(" .*", "", students$subject_course[
        !is.na(students$subject_course) & nzchar(students$subject_course)
      ])))
      updateSelectizeInput(session, "ct_subject", choices = subjects, server = TRUE)
      updateSelectizeInput(session, "cp_subject", choices = subjects, server = TRUE)
    })

    # ---- Population Audit ----
    #
    # Reactive on get_population() — updates immediately after build, no Run button.
    # Three sections:
    #   1. Outcome summary cards (with plain-language descriptions)
    #   2. Student detail table (all population columns)
    #   3. Degree check table (stopped_out only — surfaces graduation-lag cases)

    output$pop_audit_ui <- renderUI({
      pop <- get_population()
      if (is.null(pop) || nrow(pop) == 0) {
        return(div(
          class = "alert alert-info mt-3",
          "Build a student population first, then click ",
          tags$strong("Apply"), " in the sidebar."
        ))
      }

      outcome_order <- c("ongoing", "graduated", "switched_out", "stopped_out",
                         "chose_elsewhere", "left_undeclared")
      outcome_labels <- c(
        ongoing        = "Ongoing",
        graduated      = "Graduated",
        switched_out    = "Switched out",
        stopped_out     = "Stopped out",
        chose_elsewhere = "Chose elsewhere",
        left_undeclared = "Left undeclared"
      )
      outcome_desc <- c(
        ongoing        = "Still declared in the focal major in the most recent data term.",
        graduated      = "Received a degree in the focal major near their last focal term.",
        switched_out    = "Declared majors only. Left the focal major but remained at UNM \u2014 either declared another major or had enrollment records after their last focal term.",
        stopped_out     = "Declared majors only. No UNM enrollment or major record of any kind after their last focal term.",
        chose_elsewhere = "Pre-major only. Never declared this program, but did declare a different program afterward.",
        left_undeclared = "Pre-major only. Never declared any program \u2014 left without committing to a major."
      )

      # Count stopped-out students who last appeared in the term immediately
      # before the most recent data term — only one term has elapsed, so they
      # may not have truly left yet (could re-enroll next semester).
      max_prog_term    <- max(programs$term, na.rm = TRUE)
      prev_term        <- tryCatch(subtract_term(max_prog_term), error = function(e) NA_integer_)
      n_recent_stopped <- if (!is.na(prev_term) && "last_declared_term" %in% names(pop)) {
        sum(pop$outcome == "stopped_out" &
            !is.na(pop$last_declared_term) &
            pop$last_declared_term >= prev_term,
            na.rm = TRUE)
      } else 0L

      outcome_colors <- c(
        ongoing        = "#2e7d32",
        graduated      = "#1565c0",
        switched_out    = "#e65100",
        stopped_out     = "#c62828",
        chose_elsewhere = "#6a1b9a",
        left_undeclared = "#4a148c"
      )

      counts <- pop %>%
        count(outcome) %>%
        arrange(match(outcome, outcome_order))

      outcome_cards <- lapply(seq_len(nrow(counts)), function(i) {
        oc  <- counts$outcome[i]
        n   <- counts$n[i]
        col <- outcome_colors[[oc]] %||% "#555"
        recent_note <- if (oc == "stopped_out" && n_recent_stopped > 0) {
          tags$p(class = "text-note",
            style = "color: #b07000;",
            paste0(n_recent_stopped, " last appeared in ", fmt_term(prev_term),
                   " \u2014 may not have fully left yet."))
        }
        div(
          class = "outcome-card",
          style = paste0("border-left: 4px solid ", col, ";"),
          div(
            class = "outcome-card-body",
            tags$span(style = paste0("font-size: 1.4em; font-weight: bold; color: ", col, ";"), n),
            tags$strong(outcome_labels[[oc]] %||% oc)
          ),
          tags$p(class = "text-note", outcome_desc[[oc]] %||% ""),
          recent_note
        )
      })

      has_stopped_out  <- "stopped_out" %in% pop$outcome
      has_degrees_data <- !is.null(degrees)

      tagList(
        h4("Outcome Counts", class = "mt-3 mb-1"),
        p(class = "text-hint",
          "Every student is assigned exactly one outcome. These counts reflect the full population;
           use the \u201cAnalyze group\u201d filter in the status bar to narrow to a subgroup before running analyses."
        ),
        div(style = "max-width: 560px;", tagList(outcome_cards)),

        # Pre-major conversion card — always shown.
        # Uses pre-filter stats from build_population() so counts are correct
        # even when scope = "pre_only" hides the declared outcomes from pop.
        local({
          conv <- population_rv()$conversion_stats
          if (!is.null(conv)) {
            n_converted <- conv$n_converted
            n_elsewhere <- conv$n_chose_elsewhere
            n_undeclared <- conv$n_left_undeclared
          } else {
            # Fallback: derive from pop (correct for "all" scope; zero for "pre_only")
            n_converted  <- sum(!is.na(pop$entry_status) &
                                  pop$entry_status == "pre_major" &
                                  pop$outcome %in% c("ongoing", "graduated",
                                                     "switched_out", "stopped_out"),
                                na.rm = TRUE)
            n_elsewhere  <- sum(pop$outcome == "chose_elsewhere")
            n_undeclared <- sum(pop$outcome == "left_undeclared")
          }
          n_not_converted <- n_elsewhere + n_undeclared
          n_total         <- n_converted + n_not_converted

          # Recent non-converters: chose_elsewhere/left_undeclared whose last
          # focal pre-major record is prev_term — they may not have had time to
          # declare yet. Current-term pre-majors are already excluded (classified
          # as ongoing), but prev-term pre-majors are counted as non-converters.
          n_recent_nonconv <- if (!is.na(prev_term) && "last_unit_term" %in% names(pop)) {
            sum(
              pop$outcome %in% c("chose_elsewhere", "left_undeclared") &
              !is.na(pop$last_unit_term) &
              pop$last_unit_term >= prev_term,
              na.rm = TRUE
            )
          } else 0L

          body <- if (n_total == 0) {
            tags$p(class = "text-note",
              "No pre-major records in this population. ",
              "This program may not use the pre-major designation, or pre-major outcomes ",
              "(chose elsewhere, left undeclared) may be excluded from the current scope."
            )
          } else {
            pct <- round(100 * n_converted / n_total)
            detail <- if (n_not_converted > 0) {
              parts <- c(
                if (n_elsewhere  > 0) paste0(n_elsewhere,  " chose elsewhere"),
                if (n_undeclared > 0) paste0(n_undeclared, " left undeclared")
              )
              paste0(" (", paste(parts, collapse = ", "), ")")
            } else ""
            recent_note <- if (n_recent_nonconv > 0)
              tags$p(class = "text-note", style = "color: #b07000;",
                paste0(n_recent_nonconv, " non-converter(s) last appeared in ",
                       fmt_term(prev_term),
                       " \u2014 may not have had time to declare yet."))
            tagList(
              div(
                class = "outcome-card-body",
                tags$span(
                  style = "font-size: 1.4em; font-weight: bold; color: #555;",
                  paste0(n_converted, " / ", n_total)
                ),
                tags$strong("Pre-major \u2192 declared")
              ),
              tags$p(class = "text-note",
                paste0(pct, "% of students who appeared as a focal pre-major went on to declare the major. ",
                       n_not_converted, " did not", detail, ".")
              ),
              recent_note
            )
          }

          div(
            style = "max-width: 560px; margin-top: 8px;",
            div(class = "outcome-card", style = "border-left: 4px solid #555;", body)
          )
        }),

        hr(),

        h4("Student Detail", style = "margin-bottom: 4px;"),
        p(
          HTML("<code>origin</code>: unm / transfer / unknown. &nbsp;
                <code>entry_method</code>: first_program (no prior program anywhere) /
                switched_in (had prior program before this unit) / unclear (data boundary). &nbsp;
                <code>entry_status</code>: pre_major / major (how they first appeared in this unit). &nbsp;
                <code>first_unm_term</code> = first UNM enrollment (any program). &nbsp;
                <code>first_unit_term</code> = first record in this unit. &nbsp;
                <code>last_unit_term</code> = last record in this unit. &nbsp;
                <code>last_record_term</code> = last UNM enrollment of any kind."),
          style = "font-size: 0.85em; color: #555; margin-bottom: 8px;"
        ),
        DTOutput(ns("pop_detail_table")),

        if (has_stopped_out && has_degrees_data) {
          tagList(
            hr(),
            h4("Degree Check \u2014 Stopped-Out Students", style = "margin-bottom: 4px;"),
            p(
              HTML("<strong>within_window</strong> = a degree record was found within one academic year
                    of <code>last_declared_term</code>. These students may be graduates whose degree was
                    processed after their last program record \u2014 a known data lag of 1\u20132 terms."),
              style = "font-size: 0.85em; color: #555; margin-bottom: 8px;"
            ),
            DTOutput(ns("pop_degree_check_table"))
          )
        }
      )
    })

    output$pop_detail_table <- renderDT({
      pop <- get_population()
      if (is.null(pop) || nrow(pop) == 0) return(NULL)

      # Only show population_label when there are multiple distinct values
      # (single-value columns just repeat the same string every row)
      show_label <- n_distinct(pop$population_label) > 1

      display_cols <- intersect(
        c("outcome", "origin", "entry_method", "entry_status",
          "first_unm_term", "first_unit_term", "last_unit_term", "last_record_term",
          if (show_label) "population_label"),
        names(pop)
      )
      datatable(
        pop[, display_cols, drop = FALSE],
        rownames   = TRUE,
        caption    = tags$caption(
          style = "color:#555; font-size:0.85em;",
          "Each row is one unique student. Row numbers are assigned after filtering and carry no external meaning."
        ),
        extensions = "Buttons",
        options    = list(
          pageLength = 25,
          scrollX    = TRUE,
          dom        = "Bfrtip",
          buttons    = list("csv")
        )
      )
    })

    output$pop_degree_check_table <- renderDT({
      pop <- get_population()
      if (is.null(pop) || nrow(pop) == 0 || is.null(degrees)) return(NULL)
      stopped <- pop %>%
        filter(outcome == "stopped_out") %>%
        select(student_id, last_declared_term, relevant_until)
      if (nrow(stopped) == 0) return(NULL)

      degree_check <- stopped %>%
        left_join(
          degrees %>% select(student_id, degree_term = term, degree, major_code),
          by = "student_id"
        ) %>%
        mutate(
          within_window = !is.na(degree_term) &
            degree_term >= last_declared_term &
            degree_term <= last_declared_term + 100L
        ) %>%
        arrange(desc(within_window), student_id)

      datatable(
        degree_check,
        rownames   = FALSE,
        extensions = "Buttons",
        options    = list(
          pageLength = 25,
          scrollX    = TRUE,
          dom        = "Bfrtip",
          buttons    = list("csv")
        )
      ) %>%
        formatStyle(
          "within_window",
          backgroundColor = styleEqual(TRUE, "#fff8e1"),
          fontWeight      = styleEqual(TRUE, "bold")
        )
    })


    # ---- Bottlenecks ----

    btn_data <- reactive({
      req(get_population())
      opt <- list()
      if (nzchar(input$btn_term %||% "")) opt$term <- as.integer(input$btn_term)

      status_message <- create_timing_status_message("pathways-bottlenecks", "Computing bottlenecks")
      showNotification(status_message, type = "warning", duration = NULL, id = "btn_loading")
      timer <- start_report_timer("pathways-bottlenecks")

      btn_pop_ids  <- unique(get_analysis_population()$student_id)
      btn_students <- filter(students, student_id %in% btn_pop_ids)
      if (!is.null(analysis_through))
        btn_students <- filter(btn_students, term <= analysis_through)

      result <- tryCatch(
        get_bottlenecks(get_analysis_population(), btn_students, opt),
        error = function(e) {
          showNotification(paste("Bottleneck analysis failed:", e$message), type = "error")
          NULL
        }
      )

      duration_sec <- end_report_timer(timer)
      removeNotification("btn_loading")
      if (!is.null(result))
        showNotification(paste0("Bottleneck analysis complete (", round(duration_sec, 1), "s)"),
                         type = "message", duration = 3)
      result
    }) |> bindEvent(input$btn_run, btn_auto(), ignoreInit = TRUE)

    output$btn_table <- renderDT({
      req(!is.null(btn_data()))
      result <- btn_data()$waitlist
      if (is.null(result) || nrow(result) == 0) {
        return(datatable(data.frame(Message = "No waitlist records found for this population.")))
      }
      datatable(
        result,
        rownames = FALSE,
        caption  = tags$caption(
          style = "color:#555; font-size:0.85em;",
          paste0(format(nrow(get_population()), big.mark = ","), " students — ", get_description())
        ),
        options = list(pageLength = 25, scrollX = TRUE)
      )
    })


    # ---- Stop-Outs ----

    # Shared level filter for stop-out and DFW: both panels use the same selector.
    so_level_opt <- reactive({
      if (input$so_level == "undergrad") c("lower", "upper")
      else if (input$so_level == "all")  NULL
      else                               input$so_level
    })

    so_data <- reactive({
      req(get_population())

      status_message <- create_timing_status_message("pathways-stopouts", "Computing stop-out rates")
      showNotification(status_message, type = "warning", duration = NULL, id = "so_loading")
      timer <- start_report_timer("pathways-stopouts")

      # Evaluate cedar_grades once; use it to decide whether the expensive
      # filtered_students() fallback is needed. get_stopout() only touches
      # `students` when cedar_grades is absent — avoid the full-table scan otherwise.
      so_grades   <- filtered_cedar_grades()
      so_students <- if (!is.null(so_grades) && nrow(so_grades) > 0) NULL else filtered_students()

      result <- tryCatch({
        get_stopout(
          so_students, get_analysis_population(),
          degrees        = degrees,
          opt            = list(
            min_n     = as.integer(input$so_min_n),
            min_dfw_n = as.integer(input$so_min_dfw_n),
            level     = so_level_opt()
          ),
          cedar_grades    = so_grades,
          cedar_next_term = cedar_next_term
        )
      }, error = function(e) {
        showNotification(paste("Stop-out analysis failed:", e$message), type = "error")
        NULL
      })

      duration_sec <- end_report_timer(timer)
      removeNotification("so_loading")
      if (!is.null(result))
        showNotification(paste0("Stop-out analysis complete (", round(duration_sec, 1), "s)"),
                         type = "message", duration = 3)
      result
    }) |> bindEvent(input$so_run, so_auto(), ignoreInit = TRUE)

    output$so_recent_term_warn <- renderUI({
      req(so_data())
      tr <- so_data()$term_range
      if (any(is.na(tr))) return(NULL)
      max_data_term <- tr[2]
      # Warn when the most recent analyzed term equals the latest term in the data.
      # All students enrolled in that term have no visible next term, so they
      # all appear as stopped out — this inflates stop-out rates for recent courses.
      latest_global <- max(programs$term, na.rm = TRUE)
      if (max_data_term >= latest_global) {
        div(
          class = "alert alert-warning alert-compact",
          tags$strong("\u26a0 Most-recent-term bias: "),
          "The data extends through ", fmt_term(latest_global), ". ",
          "Students enrolled in that term have no visible next term, so they all appear as stopped out. ",
          "Stop-out rates for recently active courses are inflated. ",
          "To exclude this effect, set a Term filter that ends one term earlier."
        )
      }
    })

    output$so_meta <- renderUI({
      req(so_data())
      tr       <- so_data()$term_range
      n_courses <- nrow(so_data()$by_course)
      if (any(is.na(tr))) return(NULL)
      div(
        style = "font-size: 0.82em; color: #555; margin: 6px 0 2px 0;",
        tags$strong("Terms analyzed: "),
        fmt_term(tr[1]), " \u2013 ", fmt_term(tr[2]),
        tags$span(style = "margin-left: 16px;", tags$strong("Graduates excluded: "),
          if (!is.null(degrees)) "yes (degree term)" else
            tags$span(style = "color: #c00;", "no \u2014 cedar_degrees not provided")
        ),
        tags$span(
          style = "margin-left: 16px;",
          tags$strong("Courses shown: "),
          n_courses,
          sprintf("(\u2265%d enrolled, \u2265%d DFW)",
                  as.integer(input$so_min_n),
                  as.integer(input$so_min_dfw_n))
        )
      )
    })

    output$so_table <- renderDT({
      # server = TRUE: only send the current page to the browser, not the full
      # table — eliminates the 15-20s JSON serialization lag on large results.
      req(so_data())
      result <- so_data()$by_course
      if (is.null(result) || nrow(result) == 0) {
        return(datatable(data.frame(Message = "No qualifying courses found.")))
      }
      result <- result %>%
        mutate(
          excess_gap   = round(pop_stopout_gap - coalesce(baseline_stopout_gap, 0), 3),
          # excess_gap × pop DFW count: surfaces courses where the disproportionate
          # burden is both large and affects many students.
          impact_score = round(pmax(excess_gap, 0) * pop_n_dfw, 1)
        ) %>%
        arrange(desc(impact_score)) %>%
        select(subject_course, impact_score, excess_gap,
                      pop_stopout_gap, baseline_stopout_gap, everything())
      rate_cols <- grep("rate|gap|p_value", names(result), value = TRUE)

      stopout_rate_scheme <- list(thresholds = c(0.10, 0.25),
                                  colors     = c('#d4edda', '#fff3cd', '#f8d7da'),
                                  reverse_scale = FALSE)
      stopout_gap_scheme  <- list(thresholds = c(-0.05, 0.05),
                                  colors     = c('#d4edda', '#fff9e6', '#f8d7da'),
                                  reverse_scale = FALSE)

      dt <- datatable(
        result,
        rownames = FALSE,
        options  = list(pageLength = 25, scrollX = TRUE)
      ) %>%
        formatRound(columns = rate_cols, digits = 3)

      if ("pop_dfw_stopout_rate" %in% names(result))
        dt <- apply_column_colors(dt, "pop_dfw_stopout_rate", stopout_rate_scheme)
      if ("pop_stopout_gap" %in% names(result))
        dt <- apply_column_colors(dt, "pop_stopout_gap", stopout_gap_scheme)

      dt
    }, server = TRUE)

    dfw_data <- eventReactive(input$so_run, {
      req(get_population())
      dfw_grades   <- filtered_cedar_grades()
      dfw_students <- if (!is.null(dfw_grades) && nrow(dfw_grades) > 0) NULL else filtered_students()
      tryCatch(
        get_dfw_rates(
          dfw_students, get_analysis_population(),
          opt = list(
            min_n     = as.integer(input$so_min_n),
            min_dfw_n = as.integer(input$so_min_dfw_n),
            level     = so_level_opt()
          ),
          cedar_grades = dfw_grades
        ),
        error = function(e) {
          showNotification(paste("DFW rate analysis failed:", e$message), type = "error")
          NULL
        }
      )
    })

    output$dfw_table <- renderDT({
      req(dfw_data())
      result <- dfw_data()
      if (is.null(result) || nrow(result) == 0)
        return(datatable(data.frame(Message = "No qualifying courses found.")))

      result <- result %>%
        mutate(est_affected = pop_n_dfw) %>%
        arrange(desc(est_affected))

      dfw_rate_scheme <- list(thresholds    = c(0.15, 0.30),
                              colors        = c('#d4edda', '#fff3cd', '#f8d7da'),
                              reverse_scale = FALSE)

      dt <- datatable(
        result,
        rownames = FALSE,
        options  = list(pageLength = 25, scrollX = TRUE)
      ) %>%
        formatRound(columns = grep("rate", names(result), value = TRUE), digits = 3)

      if ("pop_dfw_rate" %in% names(result))
        dt <- apply_column_colors(dt, "pop_dfw_rate", dfw_rate_scheme)

      dt
    }, server = TRUE)


    # ---- Course Timing ----

    ct_data <- reactive({
      req(get_population())
      opt <- list(
        x_axis            = input$ct_x_axis %||% "overall_credit_band",
        max_relative_term = as.integer(input$ct_max_term),
        min_n             = as.integer(input$ct_min_n)
      )
      if (input$ct_level == "undergrad")      opt$level <- c("lower", "upper")
      else if (input$ct_level %in% c("lower", "upper", "grad")) opt$level <- input$ct_level
      if (length(input$ct_subject) > 0)          opt$subject_code         <- input$ct_subject
      if (nzchar(input$ct_start_class %||% ""))  opt$start_classification <- input$ct_start_class

      # Relative-term axis is left-truncated for students who were already enrolled
      # when the data starts. Force Freshman filter unless the user has explicitly
      # chosen a different start classification. Other x-axis modes use actual
      # Banner values and are unaffected.
      if (identical(opt$x_axis, "relative_term") && is.null(opt$start_classification)) {
        opt$start_classification <- "Freshman"
        updateSelectInput(session, "ct_start_class", selected = "Freshman")
        showModal(modalDialog(
          title = "Filtered to first-time freshmen",
          p("The ", tags$strong("Relative term"), " axis assigns term 1 based on each student's
             first appearance in CEDAR — not their actual first semester at UNM. Students who were
             already enrolled when the data begins (Fall 2018) look like first-semester students
             even if they were seniors. This is called ", tags$em("left truncation"), "."),
          p("To prevent misleading results, this analysis has been automatically restricted to
             students classified as ", tags$strong("Freshman"), " at their first enrollment record.
             These are the only students whose relative term 1 is genuinely their first semester."),
          p("You can change this in the ", tags$strong("Starting classification"), " dropdown.
             Switching to a credit-band or classification x-axis removes the restriction entirely —
             those axes use actual values from Banner and are unaffected by when the data starts.",
            style = "color: #666; font-size: 0.9em;"),
          footer = modalButton("Got it"),
          easyClose = TRUE
        ))
      }

      status_message <- create_timing_status_message("pathways-timing", "Computing course timing")
      showNotification(status_message, type = "warning", duration = NULL, id = "ct_loading")
      timer <- start_report_timer("pathways-timing")

      # Pre-filter both student tables to population IDs before entering the
      # course timing pipeline. get_course_timing() only needs population
      # students — passing the full table (potentially millions of rows) forces
      # an expensive scan inside the function on every run.
      # students_full uses the raw (un-windowed) table for start_classification
      # lookups, but we still restrict to pop IDs and the 4 needed columns.
      pop_ids_ct    <- unique(get_analysis_population()$student_id)
      # Pre-filter to pop IDs first, then apply windowing on the small subset.
      # Avoids running the full relevant_until window on 2M+ rows just to get ~30K.
      students_pre  <- filter(students, student_id %in% pop_ids_ct)
      if (!is.null(analysis_through))
        students_pre <- filter(students_pre, term <= analysis_through)
      pop_rv <- tryCatch(population_rv()$population, error = function(e) NULL)
      if (!is.null(pop_rv) && nrow(pop_rv) > 0 && "relevant_until" %in% names(pop_rv)) {
        bounded <- pop_rv %>%
          filter(!is.na(relevant_until)) %>%
          select(student_id, relevant_until)
        if (nrow(bounded) > 0) {
          students_pre <- students_pre %>%
            left_join(bounded, by = "student_id") %>%
            filter(is.na(relevant_until) | term <= relevant_until) %>%
            select(-relevant_until)
        }
      }
      students_pop  <- students_pre
      students_meta <- filter(students, student_id %in% pop_ids_ct) %>%
        select(student_id, term, student_classification, registration_status_code)

      result <- tryCatch(
        get_course_timing(students_pop, get_analysis_population(), programs = programs, opt = opt,
                          students_full = students_meta),
        error = function(e) {
          showNotification(paste("Course timing failed:", e$message), type = "error")
          NULL
        }
      )

      duration_sec <- end_report_timer(timer)
      removeNotification("ct_loading")
      if (!is.null(result))
        showNotification(paste0("Course timing complete (", round(duration_sec, 1), "s)"),
                         type = "message", duration = 3)
      result
    }) |> bindEvent(input$ct_run, ct_auto(), ignoreInit = TRUE)

    # Dynamic height: 20px per course row + ~100px overhead.
    # Hard cap at 8000px CSS (= 16000px at 2x DPR) to stay under ragg's 50000px limit.
    #
    # IMPORTANT: n_plot must mirror plot_curriculum_map()'s internal filters so the
    # canvas height matches the rows actually drawn. Mismatch → variable tile heights.
    #   min_pct = 0.05  (courses that never reach 5% are dropped)
    #   top_n   = 40L   (only top 40 by peak pct_pop are drawn)
    # Keep these values in sync with plot_curriculum_map() defaults.
    output$ct_plot_ui <- renderUI({
      req(ct_data())
      MIN_PCT <- 0.05
      TOP_N   <- 40L
      n_above_min <- ct_data() %>%
        group_by(subject_course) %>%
        summarize(peak = max(pct_pop, na.rm = TRUE), .groups = "drop") %>%
        filter(peak >= MIN_PCT) %>%
        nrow()
      n_plot <- min(n_above_min, TOP_N)
      height <- min(max(n_plot * 20 + 100, 200), 8000)
      plotOutput(ns("ct_plot"), height = paste0(height, "px"))
    })

    output$ct_meta <- renderUI({
      d    <- ct_data()
      meta <- attr(d, "timing_meta")
      if (is.null(meta)) return(NULL)

      filtered <- !is.null(meta$start_classification) &&
                  meta$n_analyzed < meta$n_population

      tags$p(
        if (filtered) {
          sprintf(
            "%s of %s population students analyzed (\u201c%s\u201d start classification filter). %s course%s shown (taken by \u2265%d students).",
            format(meta$n_analyzed,    big.mark = ","),
            format(meta$n_population,  big.mark = ","),
            meta$start_classification,
            format(meta$n_courses,     big.mark = ","),
            if (meta$n_courses == 1) "" else "s",
            meta$min_n
          )
        } else {
          sprintf(
            "%s students analyzed. %s course%s shown (taken by \u2265%d students).",
            format(meta$n_analyzed,   big.mark = ","),
            format(meta$n_courses,    big.mark = ","),
            if (meta$n_courses == 1) "" else "s",
            meta$min_n
          )
        },
        style = "font-size: 0.85em; color: #555; margin-top: 4px; font-style: italic;"
      )
    })

    output$ct_plot <- renderPlot({
      req(ct_data())

      MAX_COURSES <- 200L
      plot_data   <- ct_data()
      meta        <- attr(plot_data, "timing_meta")
      n_total     <- n_distinct(plot_data$subject_course)

      if (n_total > MAX_COURSES) {
        top_courses <- plot_data %>%
          group_by(subject_course) %>%
          summarize(total = sum(n_students), .groups = "drop") %>%
          slice_max(total, n = MAX_COURSES) %>%
          pull(subject_course)
        plot_data <- plot_data %>% filter(subject_course %in% top_courses)
      }

      note <- if (n_total > MAX_COURSES)
        paste0("Showing top ", MAX_COURSES, " of ", n_total,
               " courses by population enrollment. Raise \u201cMin students\u201d to reduce.")
      else
        NULL

      # Use n_analyzed (post-filter) rather than nrow(get_population()) so the
      # title reflects who actually contributed data to the heatmap.
      n_title <- if (!is.null(meta)) meta$n_analyzed else nrow(get_population())

      plot_curriculum_map(plot_data, opt = list(
        title = paste0("Course Timing \u2014 ",
                       format(n_title, big.mark = ","),
                       " students \u2014 ", get_description()),
        note  = note
      ))
    })

    output$ct_table <- renderDT({
      req(ct_data())
      datatable(
        ct_data(),
        rownames = FALSE,
        options  = list(pageLength = 25, scrollX = TRUE)
      ) %>%
        formatRound(columns = "pct_pop", digits = 3)
    })


    # ---- Course Pairs ----

    cp_data <- reactive({
      req(get_population())
      opt <- list(
        min_n        = as.integer(input$cp_min_n),
        min_pair_n   = as.integer(input$cp_min_pair),
        max_term_gap = as.integer(input$cp_max_gap)
      )
      if (input$cp_level == "undergrad")      opt$level <- c("lower", "upper")
      else if (input$cp_level %in% c("lower", "upper", "grad")) opt$level <- input$cp_level
      # "all" → no level filter
      if (length(input$cp_subject) > 0) opt$subject_code <- input$cp_subject

      status_message <- create_timing_status_message("pathways-pairs", "Computing course pairs")
      showNotification(status_message, type = "warning", duration = NULL, id = "cp_loading")
      timer <- start_report_timer("pathways-pairs")

      cp_pop_ids   <- unique(get_analysis_population()$student_id)
      cp_students  <- filter(students, student_id %in% cp_pop_ids)
      if (!is.null(analysis_through))
        cp_students <- filter(cp_students, term <= analysis_through)

      result <- tryCatch(
        get_course_pairs(cp_students, get_analysis_population(), opt),
        error = function(e) {
          showNotification(paste("Course pairs failed:", e$message), type = "error")
          NULL
        }
      )

      duration_sec <- end_report_timer(timer)
      removeNotification("cp_loading")
      if (!is.null(result))
        showNotification(paste0("Course pairs complete (", round(duration_sec, 1), "s)"),
                         type = "message", duration = 3)
      result
    }) |> bindEvent(input$cp_run, cp_auto(), ignoreInit = TRUE)

    # Sorted display data — stored as a reactive so row indices stay consistent
    # with DT's initial order even if the Sankey reads from it after render.
    cp_display <- reactive({
      req(cp_data(), nrow(cp_data()) > 0)
      cp_data() %>%
        select(course_a, course_b, pct_a_to_b, n_students, n_took_a, median_term_gap) %>%
        arrange(desc(pct_a_to_b))
    })

    output$cp_table <- renderDT({
      req(cp_data())
      if (is.null(cp_data()) || nrow(cp_data()) == 0) {
        return(datatable(data.frame(Message = "No qualifying pairs found.")))
      }
      disp    <- cp_display()
      pct_col <- which(names(disp) == "pct_a_to_b") - 1L  # 0-indexed for DT
      datatable(
        disp,
        rownames  = FALSE,
        selection = 'single',
        options   = list(
          pageLength = 25,
          scrollX   = TRUE,
          order     = list(list(pct_col, "desc"))
        )
      ) %>%
        formatRound(columns = c("pct_a_to_b", "median_term_gap"), digits = 3)
    })

    output$cp_meta <- renderUI({
      d    <- cp_data()
      meta <- attr(d, "pair_meta")
      if (is.null(meta)) return(NULL)
      tags$p(
        sprintf(
          "%d qualifying course%s (taken by \u2265%d students). Searched %s A-side \u00d7 %s B-side enrollment records. %d pair%s found (taken by \u2265%d students each).",
          meta$n_qualifying, if (meta$n_qualifying == 1) "" else "s",
          meta$min_n,
          format(meta$n_a_rows, big.mark = ","),
          format(meta$n_b_rows, big.mark = ","),
          meta$n_pairs, if (meta$n_pairs == 1) "" else "s",
          meta$min_pair_n
        ),
        style = "font-size: 0.85em; color: #555; margin-top: 4px; font-style: italic;"
      )
    })

    # Course selected by clicking a row — drives the Sankey below the table
    cp_selected_course <- reactive({
      sel <- input$cp_table_rows_selected
      req(length(sel) > 0, !is.null(cp_display()))
      cp_display()$course_a[sel]
    })

    # Compute where_to / where_from for the selected course using population students only
    cp_sankey_data <- reactive({
      req(cp_selected_course(), get_analysis_population())
      sankey_pop_ids <- get_analysis_population()$student_id
      pop_students   <- filter(students, student_id %in% sankey_pop_ids)
      if (!is.null(analysis_through))
        pop_students <- filter(pop_students, term <= analysis_through)
      opt <- list(course = cp_selected_course())
      tryCatch({
        to_courses   <- where_to(pop_students, opt)
        from_courses <- where_from(pop_students, opt)
        plot_course_sankey_by_term_with_flow_counts(to_courses, from_courses, opt)
      }, error = function(e) {
        showNotification(paste("Sankey failed:", e$message), type = "error")
        NULL
      })
    })

    output$cp_sankey_ui <- renderUI({
      req(cp_selected_course())
      plots <- cp_sankey_data()
      req(!is.null(plots), length(plots) > 0)
      term_choices <- names(plots)
      tagList(
        hr(),
        div(
          style = "display: flex; align-items: center; gap: 12px; margin: 8px 0 4px 0;",
          tags$strong(paste0("Course flow: ", cp_selected_course())),
          selectInput(ns("cp_sankey_term"), NULL,
                      choices  = term_choices,
                      selected = term_choices[1],
                      width    = "120px")
        ),
        p("Sankey shows where population students went after (right) and came from before (left) taking this course.",
          style = "font-size: 0.82em; color: #666; margin: 0 0 6px 0;"),
        plotlyOutput(ns("cp_sankey"), height = "420px")
      )
    })

    output$cp_sankey <- renderPlotly({
      req(cp_sankey_data(), input$cp_sankey_term)
      cp_sankey_data()[[input$cp_sankey_term]]
    })

    # ---- Major Changes ----

    mc_data <- reactive({
      req(get_population())
      pop_ids      <- get_analysis_population()$student_id
      pop_programs <- programs %>% filter(student_id %in% pop_ids)

      opt <- list(min_n = input$mc_min_n)

      status_message <- create_timing_status_message("pathways-major-changes", "Detecting major changes")
      showNotification(status_message, type = "warning", duration = NULL, id = "mc_loading")
      timer <- start_report_timer("pathways-major-changes")

      # Focal programs = the programs this population is defined around.
      # Derived from the cohort opt (returned by populationSelectorServer) so only
      # the user-selected dept/programs are focal — not all programs ever declared by
      # population members, which would include double-majors in other departments.
      population_opt  <- population_rv()$opt %||% list()
      population_type <- population_opt$type %||% "preset"
      focal_programs <- if (population_type == "dept") {
        programs %>%
          filter(dept_code == population_opt$dept_code,
                        program_type %in% c("Major", "Second Major")) %>%
          distinct(program_name) %>%
          pull(program_name)
      } else if (population_type == "major") {
        population_opt$program_names %||% character(0)
      } else if (population_type == "preset") {
        population_opt$program_names %||% character(0)
      } else {
        # demographic: no single focal program — use all majors held by pop members
        pop_programs %>%
          filter(program_type == "Major") %>%
          distinct(program_name) %>%
          pull(program_name)
      }

      result <- tryCatch({
        changes <- detect_major_changes(pop_programs)

        # focal_changes: only transitions that directly involve the population's programs.
        # A History cohort shows History→PolSci and PolSci→History, but NOT PolSci→Law
        # (even though a History student made that change). Used for all summary views.
        # Full `changes` is preserved for the student-level detail table.
        focal_changes <- changes %>%
          filter(from_major %in% focal_programs | to_major %in% focal_programs)

        pathways <- major_change_pathways(focal_changes, opt = opt)
        list(changes = changes, focal_changes = focal_changes,
             pathways = pathways, focal_programs = focal_programs)
      }, error = function(e) {
        showNotification(paste("Major changes failed:", e$message), type = "error")
        NULL
      })

      duration_sec <- end_report_timer(timer)
      removeNotification("mc_loading")
      if (!is.null(result))
        showNotification(paste0("Major changes complete (", round(duration_sec, 1), "s)"),
                         type = "message", duration = 3)
      result
    }) |> bindEvent(input$mc_run, mc_auto(), ignoreInit = TRUE)

    output$mc_changes_table <- renderDT({
      req(!is.null(mc_data()))
      result <- mc_data()$changes
      if (is.null(result) || nrow(result) == 0)
        return(datatable(data.frame(Message = "No major changes found for this population.")))
      datatable(result, rownames = FALSE, options = list(pageLength = 25, scrollX = TRUE))
    })

    output$mc_pathways_table <- renderDT({
      req(!is.null(mc_data()))
      result <- mc_data()$pathways
      if (is.null(result) || nrow(result) == 0)
        return(datatable(data.frame(Message = "No pathways met the minimum threshold.")))
      datatable(result, rownames = FALSE, options = list(pageLength = 25, scrollX = TRUE))
    })

    output$mc_summary_cards <- renderUI({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      focal   <- mc_data()$focal_programs %||% character(0)
      if (is.null(changes) || nrow(changes) == 0) return(NULL)

      n_changers <- n_distinct(changes$student_id)
      n_events   <- nrow(changes)

      if (length(focal) == 1) {
        # Single focal program: show top-3 arriving-from and leaving-for with counts + pct
        arriving_data <- changes %>%
          filter(to_major == focal) %>%
          count(major = from_major, sort = TRUE)
        leaving_data <- changes %>%
          filter(from_major == focal) %>%
          count(major = to_major, sort = TRUE)

        make_top3 <- function(df) {
          top3  <- slice_head(df, n = 3)
          total <- sum(df$n)
          if (nrow(top3) == 0) return(tags$em("\u2014", style = "color:#aaa;"))
          tagList(lapply(seq_len(nrow(top3)), function(i) {
            pct <- if (total > 0) round(100 * top3$n[i] / total) else 0
            div(class = "mb-1",
              tags$span(class = "fw-semibold", top3$major[i]),
              tags$span(class = "text-note ms-1",
                        paste0(top3$n[i], "\u00a0(", pct, "%)"))
            )
          }))
        }

        fluidRow(
          column(3, div(class = "stat-card",
            p(n_changers, class = "stat-num"),
            p("students changed majors", class = "stat-lbl")
          )),
          column(3, div(class = "stat-card",
            p(n_events, class = "stat-num"),
            p("total change events", class = "stat-lbl")
          )),
          column(3, div(class = "stat-card stat-card--left",
            tags$strong("Top arriving from", class = "stat-lbl d-block mb-1"),
            make_top3(arriving_data)
          )),
          column(3, div(class = "stat-card stat-card--left",
            tags$strong("Top leaving for", class = "stat-lbl d-block mb-1"),
            make_top3(leaving_data)
          ))
        )

      } else {
        # Multiple focal programs: single-value summary cards
        top_from <- changes %>% count(from_major, sort = TRUE) %>% slice(1)
        top_to   <- changes %>% count(to_major,   sort = TRUE) %>% slice(1)

        fluidRow(
          column(3, div(class = "stat-card",
            p(n_changers, class = "stat-num"),
            p("students changed majors", class = "stat-lbl")
          )),
          column(3, div(class = "stat-card",
            p(n_events, class = "stat-num"),
            p("total change events", class = "stat-lbl")
          )),
          column(3, div(class = "stat-card",
            p(if (nrow(top_from) > 0) top_from$from_major else "\u2014", class = "stat-num"),
            p("most common departure", class = "stat-lbl")
          )),
          column(3, div(class = "stat-card",
            p(if (nrow(top_to) > 0) top_to$to_major else "\u2014", class = "stat-num"),
            p("most common destination", class = "stat-lbl")
          ))
        )
      }
    })

    output$mc_trend_plot <- renderPlotly({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      focal   <- mc_data()$focal_programs %||% character(0)
      if (is.null(changes) || nrow(changes) == 0) return(NULL)

      all_terms <- data.frame(change_term = sort(unique(changes$change_term)))

      arriving <- changes %>%
        filter(to_major %in% focal) %>%
        count(change_term, name = "n") %>%
        right_join(all_terms, by = "change_term") %>%
        replace_na(list(n = 0)) %>%
        arrange(change_term) %>%
        mutate(term_label = as.character(change_term))

      leaving <- changes %>%
        filter(from_major %in% focal) %>%
        count(change_term, name = "n") %>%
        right_join(all_terms, by = "change_term") %>%
        replace_na(list(n = 0)) %>%
        arrange(change_term) %>%
        mutate(term_label = as.character(change_term))

      plot_ly() %>%
        add_trace(
          data = arriving, x = ~term_label, y = ~n,
          type = "scatter", mode = "lines+markers", name = "Arriving",
          line   = list(color = "#2e7d32", width = 2),
          marker = list(color = "#2e7d32", size = 5),
          hovertemplate = "%{x}: %{y} arriving<extra></extra>"
        ) %>%
        add_trace(
          data = leaving, x = ~term_label, y = ~n,
          type = "scatter", mode = "lines+markers", name = "Leaving",
          line   = list(color = "#c62828", width = 2),
          marker = list(color = "#c62828", size = 5),
          hovertemplate = "%{x}: %{y} leaving<extra></extra>"
        ) %>%
        layout(
          xaxis  = list(title = "", tickangle = -45, tickfont = list(size = 10)),
          yaxis  = list(title = "# students"),
          legend = list(orientation = "h", x = 0, y = 1.2, font = list(size = 11)),
          margin = list(t = 30, b = 60, l = 40, r = 10)
        )
    })

    # Shared color map so the same program gets the same color in both donuts.
    # Union of both top-8 lists so any program appearing in either chart gets
    # a stable color regardless of which side it appears on.
    mc_donut_color_map <- reactive({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      focal   <- mc_data()$focal_programs %||% character(0)
      if (is.null(changes) || nrow(changes) == 0) return(character(0))

      arriving_programs <- changes %>%
        filter(to_major %in% focal) %>%
        count(major = from_major, sort = TRUE) %>%
        slice_head(n = 8) %>%
        pull(major)
      leaving_programs <- changes %>%
        filter(from_major %in% focal) %>%
        count(major = to_major, sort = TRUE) %>%
        slice_head(n = 8) %>%
        pull(major)

      build_color_map(union(arriving_programs, leaving_programs))
    })

    output$mc_donut_arriving <- renderPlotly({
      req(!is.null(mc_data()))
      changes   <- mc_data()$focal_changes
      focal     <- mc_data()$focal_programs %||% character(0)
      color_map <- mc_donut_color_map()
      if (is.null(changes) || nrow(changes) == 0) return(NULL)

      top_to <- changes %>%
        filter(to_major %in% focal) %>%
        count(major = from_major, name = "n", sort = TRUE) %>%
        slice_head(n = 8)

      if (nrow(top_to) == 0) return(NULL)

      plot_ly(
        top_to, labels = ~major, values = ~n, type = "pie",
        hole = 0.45,
        textinfo = "percent", textposition = "inside",
        hovertemplate = "%{label}: %{value} (%{percent})<extra></extra>",
        marker = list(colors = unname(color_map[top_to$major])),
        showlegend = TRUE
      ) %>%
        layout(
          legend = list(orientation = "v", x = 1.02, y = 0.5, font = list(size = 9)),
          margin = list(t = 5, b = 5, l = 5, r = 5)
        )
    })

    output$mc_donut_leaving <- renderPlotly({
      req(!is.null(mc_data()))
      changes   <- mc_data()$focal_changes
      focal     <- mc_data()$focal_programs %||% character(0)
      color_map <- mc_donut_color_map()
      if (is.null(changes) || nrow(changes) == 0) return(NULL)

      top_from <- changes %>%
        filter(from_major %in% focal) %>%
        count(major = to_major, name = "n", sort = TRUE) %>%
        slice_head(n = 8)

      if (nrow(top_from) == 0) return(NULL)

      plot_ly(
        top_from, labels = ~major, values = ~n, type = "pie",
        hole = 0.45,
        textinfo = "percent", textposition = "inside",
        hovertemplate = "%{label}: %{value} (%{percent})<extra></extra>",
        marker = list(colors = unname(color_map[top_from$major])),
        showlegend = TRUE
      ) %>%
        layout(
          legend = list(orientation = "v", x = 1.02, y = 0.5, font = list(size = 9)),
          margin = list(t = 5, b = 5, l = 5, r = 5)
        )
    })

    output$mc_flow_table <- renderDT({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      if (is.null(changes) || nrow(changes) == 0)
        return(datatable(data.frame(Message = "No major changes found.")))

      focal <- mc_data()$focal_programs %||% character(0)

      inflows  <- changes %>% count(major = to_major,   name = "n_in")
      outflows <- changes %>% count(major = from_major, name = "n_out")
      flow <- full_join(inflows, outflows, by = "major") %>%
        replace_na(list(n_in = 0L, n_out = 0L)) %>%
        mutate(net = n_in - n_out) %>%
        filter(length(focal) == 0 | major %in% focal) %>%
        arrange(desc(n_in + n_out))

      # "Students arriving to" = changed INTO this major from somewhere else
      # "Students leaving for" = changed OUT OF this major to somewhere else
      # A major can appear in both columns — e.g. History students both arrive and depart
      datatable(
        flow, rownames = FALSE,
        colnames = c("Major", "Students arriving to", "Students leaving for elsewhere", "Net"),
        options  = list(pageLength = 15, scrollX = TRUE)
      ) %>%
        formatStyle(
          "net",
          color = styleInterval(c(-0.5, 0.5), c("#c62828", "#888", "#2e7d32")),
          fontWeight = "bold"
        )
    })


    # ---- Entry Patterns ----
    #
    # Uses get_population() (not get_analysis_population()) so that both
    # converters and non-converters are always present for the comparison,
    # regardless of any group_filter or split the user has applied.

    ep_data <- reactive({
      req(get_population())
      pop   <- get_population()
      min_n <- as.integer(input$ep_min_n)

      if (!"first_unit_term" %in% names(pop)) {
        showNotification(
          "Entry patterns requires a program-based population (not demographic mode).",
          type = "warning", duration = 5
        )
        return(NULL)
      }

      status_message <- create_timing_status_message("pathways-entry-patterns",
                                                      "Computing entry patterns")
      showNotification(status_message, type = "warning", duration = NULL,
                       id = "ep_loading")
      timer <- start_report_timer("pathways-entry-patterns")

      pop_ids     <- unique(pop$student_id)
      ep_students <- filter(students, student_id %in% pop_ids)
      if (!is.null(analysis_through))
        ep_students <- filter(ep_students, term <= analysis_through)

      result <- tryCatch(
        get_event_adjacent_courses(ep_students, pop,
                                   event = "entry", window = 1L,
                                   include_event_term = FALSE,
                                   min_n = min_n),
        error = function(e) {
          showNotification(paste("Entry patterns failed:", e$message), type = "error")
          NULL
        }
      )

      duration_sec <- end_report_timer(timer)
      removeNotification("ep_loading")
      if (!is.null(result) && nrow(result) > 0)
        showNotification(
          paste0("Entry patterns complete (", round(duration_sec, 1), "s)"),
          type = "message", duration = 3
        )
      result
    }) |> bindEvent(input$ep_run, ignoreInit = TRUE)

    output$ep_meta <- renderUI({
      pop <- get_population()
      if (is.null(pop) || !"outcome" %in% names(pop)) return(NULL)

      n_entered   <- sum(pop$outcome %in% c("ongoing", "graduated",
                                            "switched_out", "stopped_out"),
                         na.rm = TRUE)
      n_not_entered <- sum(pop$outcome %in% c("chose_elsewhere", "left_undeclared"),
                           na.rm = TRUE)

      d <- ep_data()

      if (n_entered == 0 || n_not_entered == 0) {
        missing_grp <- if (n_entered == 0) "any who entered" else "any who did not enter"
        return(p(
          sprintf("Population has %d entered and %d did-not-enter students. ",
                  n_entered, n_not_entered),
          sprintf("The comparison requires both groups — no %s found.", missing_grp),
          class = "text-hint"
        ))
      }

      meta       <- if (!is.null(d)) attr(d, "ep_meta") else NULL
      n_no_prior <- meta$n_no_prior %||% 0L
      n_courses  <- if (!is.null(d)) nrow(d) else 0L

      p(
        sprintf("%d entered \u2014 %d did not enter.",  n_entered, n_not_entered),
        if (n_no_prior > 0)
          sprintf(" %d excluded: no prior enrollment term on record.", n_no_prior),
        if (n_courses > 0)
          sprintf(" Showing %d courses above the threshold.", n_courses)
        else if (!is.null(d))
          " No courses met the min threshold \u2014 try lowering Min students per course.",
        class = "text-hint"
      )
    })

    output$ep_table <- renderDT({
      d <- ep_data()
      req(!is.null(d), nrow(d) > 0)

      # Sort: lift (most differentiating) or converter % (most common gateway)
      sort_by <- input$ep_sort %||% "lift"
      if (sort_by == "lift" && "lift" %in% names(d)) {
        d <- arrange(d, desc(lift))
      } else if ("pct_entered" %in% names(d)) {
        d <- arrange(d, desc(pct_entered))
      }

      show_cols <- intersect(
        c("subject_course", "course_title",
          "n_students_entered",      "pct_entered",
          "n_students_did_not_enter", "pct_did_not_enter",
          "lift"),
        names(d)
      )
      col_labels <- c(
        subject_course            = "Course",
        course_title              = "Title",
        n_students_entered        = "Entered (n)",
        pct_entered               = "Entered (%)",
        n_students_did_not_enter  = "Did not enter (n)",
        pct_did_not_enter         = "Did not enter (%)",
        lift                      = "Lift"
      )

      dt <- datatable(
        d[, show_cols, drop = FALSE],
        rownames = FALSE,
        colnames = unname(col_labels[show_cols]),
        options  = list(pageLength = 20, scrollX = TRUE)
      )

      pct_cols <- intersect(c("pct_entered", "pct_did_not_enter"), show_cols)
      if (length(pct_cols) > 0)
        dt <- formatPercentage(dt, columns = pct_cols, digits = 1)
      if ("lift" %in% show_cols)
        dt <- formatRound(dt, columns = "lift", digits = 2)

      dt
    })


  }) # end moduleServer
}


# Null-coalescing operator — define only if not already loaded
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
