# Shiny Module: Pathways Tab
#
# Population-aware curriculum analytics. The user defines a student population
# (via the top filter stripe), then runs analysis subtabs:
#
#   Stop-Outs     — courses where a DFW grade predicts leaving the institution
#   Course Timing — when in their academic career population students take each course
#   Course Pairs  — which courses population students commonly take in sequence
#   Course to Major — courses associated with later department declarations
#   Major Changes — how students move between programs
#
# Population Trend (new-entrant mix over time) lives in the Dept Dashboard → Demographics tab.
#
# Depends on (sourced before this file via load-funcs.R):
#   R/branches/population.R   — build_population()
#   R/branches/pathways.R     — Pathways-specific pure helpers
#   R/cones/stopout.R         — get_stopout()
#   R/cones/pathway.R         — get_course_timing(), plot_curriculum_map(), get_course_pairs()
#   R/cones/major-changes.R   — detect_major_changes(), major_change_pathways()
#   R/cones/gen-ed-conversion.R — get_course_major_associations()
#
# Exported functions:
#   pathwaysUI(id, campus_choices)
#   pathwaysServer(id, students, programs, degrees, lookups)
#
# Internal sub-module:
#   populationSelectorUI(id, campus_choices)
#   populationSelectorServer(id, programs)  → returns reactive list(population, description)


# Standardized subtab intro: a slightly-larger, plain-language description of what
# the subtab does, led by the bold subtab name. Keep it to a sentence or two plus
# any necessary caveat. Pass the trailing text (and inline tags) as ...:
#   subtab_intro("Course Timing", "shows when students take each course …")
subtab_intro <- function(name, ...) {
  tags$p(class = "pathways-intro", tags$strong(name), " ", ...)
}

pathways_section_heading <- function(title, ..., level = "h3", class = NULL) {
  section_heading(
    title,
    ...,
    level = level,
    class = paste(c("pathways-section-heading", class), collapse = " ")
  )
}


# =============================================================================
# Population Selector sub-module
# =============================================================================
#
# UI: top filter stripe with program selectors and an "Apply" button.
# Server: calls build_population() on click, returns list(population = tibble, description = string).

populationSelectorUI <- function(id, campus_choices, status_output = NULL) {
  ns <- NS(id)
  filter_bar(
    "Pathways",
    tags$span(
      "Define a student population, then explore course timing, roadblocks, sequences, and major changes. ",
      tags$a("Institution-level Gen Ed patterns are in Explore > Gen Ed.", href = "?tab=gen-ed")
    ),
    class = "pathways-population-filter",
    fluidRow(
      column(2,
        selectInput(
          ns("population_type"), "Select population by",
          choices = c(
            "Major"                = "major",
            "Department"           = "dept",
            "Major Group (preset)" = "preset",
            "Demographics"         = "demographic"
          ),
          selected = "major",
          width    = "100%"
        )
      ),
      column(3,
        conditionalPanel(
          condition = sprintf("input['%s'] == 'preset'", ns("population_type")),
          selectInput(
            ns("preset"), "Major Group",
            choices  = names(COHORT_PRESETS),
            selected = "All Health Programs",
            width    = "100%"
          )
        ),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'dept'", ns("population_type")),
          selectizeInput(
            ns("dept_code"), "Department",
            choices = c(),
            options = list(placeholder = "Type to search...", maxOptions = 300),
            width   = "100%"
          )
        ),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'major'", ns("population_type")),
          selectizeInput(
            ns("program_names"), "Majors",
            choices  = c(),
            multiple = TRUE,
            options  = list(placeholder = "Type to search majors...", maxOptions = 500),
            width    = "100%"
          )
        ),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'demographic'", ns("population_type")),
          div(class = "pathways-demo-options",
            checkboxInput(ns("demo_pell"), "Ever Pell-Eligible", value = FALSE),
            checkboxInput(ns("demo_first_gen"), "Ever First-Generation", value = FALSE),
            selectizeInput(
              ns("demo_time_status"), "Enrollment Intensity",
              choices  = c("Full-time" = "FT", "Part-time" = "PT"),
              multiple = TRUE,
              selected = NULL,
              width    = "100%",
              options  = list(placeholder = "Any")
            )
          )
        )
      ),
      column(2,
        conditionalPanel(
          condition = sprintf("input['%s'] != 'demographic'", ns("population_type")),
          selectInput(
            ns("population_scope"), "Population scope",
            choices  = c(
              "Declared majors only" = "declared",
              "Declared + pre-major" = "all",
              "Pre-major only"       = "pre_only"
            ),
            selected = "all",
            width    = "100%"
          )
        ),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'demographic'", ns("population_type")),
          div(
            style = "opacity: 0.55; pointer-events: none;",
            selectInput(
              ns("population_scope_na"), "Population scope",
              choices = c("Not available" = ""),
              selected = "",
              width = "100%"
            )
          )
        )
      ),
      column(1,
        selectInput(
          ns("student_level"), "Level",
          choices  = c("All" = "", "Undergrad" = "Undergraduate", "Grad" = "Graduate"),
          selected = "Undergraduate",
          width    = "100%"
        )
      ),
      column(2,
        selectizeInput(
          ns("campus"), "Campus",
          choices  = campus_choices,
          multiple = TRUE,
          selected = "ABQ",
          width    = "100%",
          options  = list(placeholder = "All campuses…")
        )
      ),
      column(2,
        filter_actions(
          actionButton(ns("build_btn"), "Apply Population",
                       class = "btn-primary",
                       icon  = icon("users"))
        )
      )
    ),
    if (!is.null(status_output)) filter_scope_stripe(status_output)
  )
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
                           server  = FALSE)

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
                           server  = FALSE)

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

      if (length(input$campus) > 0)             opt$campus        <- input$campus
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
        description <- paste0(description, " — ", tolower(input$student_level))
      if (length(input$campus) > 0)
        description <- paste0(description, " — ", paste(input$campus, collapse = "+"))

      if (type %in% c("preset", "dept", "major")) {
        # Always append a scope note — including for "declared" — so the absence of
        # a note can never be misread as "this UI just doesn't mention pre-majors."
        scope_note <- switch(scope,
          declared = "(declared majors only)",
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

      list(population = result, description = description, opt = opt, scope = scope,
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
    populationSelectorUI(
      ns("population"),
      campus_choices,
      status_output = uiOutput(ns("population_status"))
    ),

      # ---- Analysis sub-panels — main content area ----
      div(class = "pathways-analysis-content",
      navset_tab(
        id       = ns("analysis_tabs"),
        selected = "Population",

        # ---- Population Audit ----
        nav_panel("Population",
          subtab_intro("Population",
            "audits the student group you defined — how many students it includes, how they entered (first-time, transfer, pre-major), and how the focal / pre-major split breaks down."),
          uiOutput(ns("pop_audit_ui"))
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
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("so_meta"))))
          ),
          subtab_intro("Roadblocks",
            "flags courses where a D/F/W is often followed by students in your population leaving UNM — at a higher rate than comparable students in the same course. Read each row as a risk flag worth a look, not proof the course caused the departure."),

          div(class = "pathways-section",
            pathways_section_heading("Departure Risk"),
            p(
              "Courses where a DFW is followed by a bigger departure gap for this population than for other students in the same course. The most useful rows have both a large gap and enough affected students to matter.",
              class = "text-hint"
            ),
            info_panel("Column guide",
              tags$ul(
                tags$li(HTML("<strong>Course</strong>: course code.")),
                tags$li(HTML("<strong>Impact</strong>: positive excess gap multiplied by the number of population students with a DFW. Higher values balance severity and scale.")),
                tags$li(HTML("<strong>excess_gap</strong>: population stop-out gap minus baseline stop-out gap.")),
                tags$li(HTML("<strong>pop_stopout_gap</strong>: population DFW stop-out rate minus population pass stop-out rate.")),
                tags$li(HTML("<strong>baseline_stopout_gap</strong>: the same DFW-vs-pass gap among all non-population students in the course.")),
                tags$li(HTML("<strong>pop_n_dfw</strong> and <strong>pop_n_pass</strong>: population students in the DFW and passing groups.")),
                tags$li(HTML("<strong>pop_dfw_stopout_rate</strong> and <strong>pop_pass_stopout_rate</strong>: share of each group that did not return the next fall or spring.")),
                tags$li(HTML("<strong>baseline_*</strong> columns: comparison values for students outside the selected population.")),
                tags$li(HTML("<strong>p_value</strong>: a statistical test of whether DFW and passing students had different stop-out rates. Treat small counts cautiously."))
              )
            ),
            uiOutput(ns("so_recent_term_warn")),
            reactable::reactableOutput(ns("so_table"))
          ),

          div(class = "pathways-section",
            pathways_section_heading("Grade Setback"),
            p(
              "Academic friction even when students stay enrolled — a high DFW rate can slow progress, force retakes, and add scheduling pressure. The baseline columns show whether the population experiences the course differently from other students.",
              class = "text-hint"
            ),
            info_panel("Column guide",
              tags$ul(
                tags$li(HTML("<strong>Course</strong>: course code.")),
                tags$li(HTML("<strong>est_affected</strong>: estimated number of population students with a DFW in the course; used to sort the table.")),
                tags$li(HTML("<strong>pop_n_graded</strong>: population students with graded records in the course.")),
                tags$li(HTML("<strong>pop_n_dfw</strong>: population students with a DFW outcome.")),
                tags$li(HTML("<strong>pop_dfw_rate</strong>: population DFW outcomes divided by population graded records.")),
                tags$li(HTML("<strong>baseline_n_graded</strong>, <strong>baseline_n_dfw</strong>, and <strong>baseline_dfw_rate</strong>: the same measures for all non-population students in the course."))
              )
            ),
            reactable::reactableOutput(ns("dfw_table"))
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
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("ct_meta"))))
          ),
          subtab_intro("Course Timing",
            "shows when students in your population typically take each course — by credits earned, enrolled term, or classification — so you can see the usual sequence and spot courses taken unusually early or late."),
          uiOutput(ns("ct_explanation")),
          uiOutput(ns("ct_plot_ui")),
          div(class = "mt-3",
            reactable::reactableOutput(ns("ct_table"))
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
                numericInput(ns("cp_min_pair"), "Min students (A→B)",
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
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("cp_meta"))))
          ),
          subtab_intro("Course Pairs",
            "surfaces common A→B course sequences: of students who took course A, what share later took course B? Useful for spotting de-facto prerequisites and popular follow-ons. Pairs more than the max term gap apart are excluded, and non-ongoing students count only through their last focal term."),
          reactable::reactableOutput(ns("cp_table"))
        ),

        # ---- Course to Major ----
        nav_panel("Course to Major",
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(2,
                selectInput(ns("ge_level"), "Course level",
                            choices = c("All" = "all", "Undergrad" = "undergrad",
                                        "Lower div" = "lower", "Upper div" = "upper", "Grad" = "grad"),
                            selected = "undergrad")
              ),
              column(2,
                selectizeInput(ns("ge_campus"), "Campus",
                               choices  = c(),
                               multiple = TRUE,
                               options  = list(placeholder = "All…"))
              ),
              column(1,
                div(class = "filter-checkbox-tile",
                  div(class = "control-label", "GEN ED"),
                  checkboxInput(ns("ge_gen_ed_only"), "GE only", value = FALSE)
                )
              ),
              column(1,
                numericInput(ns("ge_min_n"), "Min N", value = 5, min = 1, max = 100)
              ),
              column(1,
                selectizeInput(ns("ge_from_term"), "From term",
                               choices = c(),
                               multiple = FALSE)
              ),
              column(1,
                selectizeInput(ns("ge_to_term"), "To term",
                               choices = c(),
                               multiple = FALSE)
              ),
              column(1,
                numericInput(ns("ge_conv_max_lag"), "Heatmap lag",
                             value = 3, min = 1, max = 6, step = 1)
              ),
              column(2,
                div(class = "mt-btn",
                  actionButton(ns("ge_conv_run"), "Run", class = "btn-sm btn-secondary",
                               icon = icon("play"))
                )
              )
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("ge_instructor_meta"))))
          ),
          subtab_intro("Course to Major",
            "looks for courses near the doorway into the major — which course-and-instructor groups are most often followed by a later declaration, and (in the heatmaps) what students took before they first entered the unit. Descriptive signals, not causal claims."),

          # ── Course + Instructor Associations (primary) ───────────────────────
          pathways_section_heading("Course + Instructor Signals"),
          p(
            class = "text-hint",
            "The population defines the focal department and subject prefixes; this table then scans ",
            tags$strong("all enrolled students"),
            " in those focal-subject courses — it is ", tags$em("not"),
            " limited by the Population scope dropdown. A student counts as having “declared” as soon as ",
            "their first ", tags$strong("major or pre-major"),
            " record appears in this department, so a pre-major counts as entry here. (By contrast, the ",
            tags$em("Courses Before Major Entry"),
            " heatmaps below are limited to your selected population.)"
          ),
          info_panel("Column guide",
            tags$ul(style = "margin: 0; padding-left: 18px;",
              tags$li(HTML("<strong>Course</strong> — the course code.")),
              tags$li(HTML("<strong>Instructor</strong> — primary instructor of record for that section.")),
              tags$li(HTML("<strong>Eligible</strong> — registered students in that course + instructor group who did <em>not</em> already have a department major or pre-major before the course term.")),
              tags$li(HTML("<strong>Later declared</strong> — eligible students whose first department major or pre-major record appears in the course term or a later term.")),
              tags$li(HTML("<strong>Declaration %</strong> — Later declared ÷ Eligible.")),
              tags$li(HTML("<strong>% of Pool</strong> — this group’s Eligible count as a share of all distinct eligible students across all groups. It can sum to more than 100% because one student can take multiple courses.")),
              tags$li(HTML("<strong>Terms</strong> — how many distinct terms this instructor taught this course (indicates sample breadth)."))
            )
          ),
          reactable::reactableOutput(ns("ge_instructor_table")),

          # ── Entry Heatmaps (collapsed) ───────────────────────────────────────
          hr(class = "mt-btn"),
          tags$details(
            tags$summary(
              "Courses Before Major Entry",
              class = "text-hint", style = "cursor: pointer;"
            ),
            p(
              "For students who entered the selected population, this shows courses taken before their first focal program record.",
              " T−1 is the prior regular term; summer is skipped by default. Empty cells did not meet the minimum-student threshold.",
              " Campus, level, Gen Ed, and date-range association filters do not apply to these heatmaps.",
              class = "text-hint"
            ),
            uiOutput(ns("ge_heatmap_meta")),
            pathways_section_heading("Courses from this unit", level = "h4"),
            plotlyOutput(ns("ge_heatmap_in"), height = "500px"),
            hr(class = "mt-btn"),
            pathways_section_heading("Courses from other departments", level = "h4"),
            plotlyOutput(ns("ge_heatmap_out"), height = "500px")
          )
        ),

        # ---- Major Changes ----
        # No Run button: this tab has no local inputs, so the analysis is fully
        # determined by the population. mc_data computes automatically the first
        # time the tab is viewed (see server).
        nav_panel("Major Changes",
          subtab_intro("Major Changes",
            "follows students in your population who switched majors — where they came from, where they went, and how far into their studies the move happened. Use it to see which programs feed students into yours and which ones draw them away."),
          info_panel(
            "How a “major change” is counted",
            tags$ul(
              tags$li("A change is any pair of back-to-back terms where the student’s primary declared program is different."),
              tags$li("Only moves that touch the focal major are shown — students arriving into it, or leaving it for somewhere else."),
              tags$li("Moving from a pre-major to the full major in the same program does ", tags$em("not"), " count as a change."),
              tags$li("Undergraduate-to-graduate transitions are excluded.")
            ),
            description = "The exact rules behind every count on this tab."
          ),

          # ── Summary cards ───────────────────────────────────────────────────
          uiOutput(ns("mc_summary_cards")),

          # ── Trend sparkline + donuts ─────────────────────────────────────────
          fluidRow(
            column(5,
              section_heading("Changes by Term", level = "h6"),
              plotlyOutput(ns("mc_trend_plot"), height = "180px")
            ),
            column(7,
              fluidRow(
                column(6,
                  section_heading("Arriving from", level = "h6"),
                  plotlyOutput(ns("mc_donut_arriving"), height = "240px")
                ),
                column(6,
                  section_heading("Leaving for", level = "h6"),
                  plotlyOutput(ns("mc_donut_leaving"), height = "240px")
                )
              )
            )
          ),

          hr(),

          # ── Per-major flow table ─────────────────────────────────────────────
          pathways_section_heading("Inflow / Outflow by Major"),
          p(class = "text-hint",
            "One row per major. ", tags$strong("Arriving to"), " counts students who switched ",
            "into that major from somewhere else; ", tags$strong("leaving for elsewhere"),
            " counts students who switched out of it. The same major can show up in both."),
          div(class = "mt-2", reactable::reactableOutput(ns("mc_flow_table"))),

          hr(class = "mc-divider"),

          # ── A → B pathways ───────────────────────────────────────────────────
          pathways_section_heading("Common Pathways (from → to)"),
          p(class = "text-hint",
            "Each row is a specific from→to switch. Switches involving only a few students are ",
            "hidden so individuals can't be identified. ",
            tags$strong("Avg UNM / total credits"), " is how many attempted hours the student had ",
            "already accumulated when they switched (institutional only vs. including transfer) — ",
            "a rough sense of how far along they typically were. Figures are lag-adjusted to the ",
            "term before the change posted to Banner."),
          div(class = "mt-2", reactable::reactableOutput(ns("mc_pathways_table"))),

          hr(class = "mc-divider"),

          # ── Student-level detail (collapsed) ─────────────────────────────────
          info_panel(
            "Change events (student-level)",
            div(class = "mt-2", reactable::reactableOutput(ns("mc_changes_table"))),
            description = "Every individual change event behind the summaries above.",
            class = "cedar-detail-panel"
          )
        ),

        # ---- Methodology ----
        nav_panel("Methodology",
          methodology_panel_content()
        )

      ) # end navset_tab
      ) # end pathways-analysis-content div
  ) # end tagList
}

pathways_start_panel <- function() {
  tab_item <- function(title, text, icon_name) {
    div(
      class = "pathways-start-tab",
      div(class = "pathways-start-tab-icon", icon(icon_name)),
      div(
        class = "pathways-start-tab-copy",
        tags$strong(title),
        tags$span(text)
      )
    )
  }

  div(
    class = "alert alert-info pathways-start-panel",
    div(
      class = "pathways-start-header",
      div(class = "pathways-start-icon", icon("route")),
      div(
        tags$h4("Define a population to begin"),
        tags$p(
          "Pathways works from a student population that you define first. Use the green filter ",
          "bar above to pick a major, department, preset group, or demographic group, then click ",
          tags$strong("Apply Population"),
          ". Every subtab below then describes that same group of students."
        )
      )
    ),
    div(
      class = "pathways-start-tabs",
      tab_item("Population", "See who falls into the group you defined and how their major and pre-major paths played out.", "users"),
      tab_item("Roadblocks", "Spot courses whose grades or DFW rates tend to coincide with later departure — a flag for a closer look, not proof of cause.", "triangle-exclamation"),
      tab_item("Course Timing", "See when students in the group typically take key courses across their time here.", "calendar-days"),
      tab_item("Course Pairs", "Surface course sequences that often occur together and the usual gap between them.", "shuffle"),
      tab_item("Course to Major", "Highlight courses that often precede a student declaring into this unit — an association worth exploring, not a recruiting guarantee.", "arrow-right-to-bracket"),
      tab_item("Major Changes", "Trace how students move into, out of, and across programs over time.", "right-left")
    ),
    div(
      class = "pathways-start-caveat",
      icon("circle-info"),
      tags$span(
        tags$strong("How to read these results. "),
        "Every Pathways analysis is descriptive. It summarizes patterns in past enrollment and ",
        "surfaces associations — it can't tell you ", tags$em("why"), " a pattern exists or whether ",
        "one thing caused another. A course linked to later departure isn't necessarily the reason ",
        "students left; students who took a course before declaring weren't necessarily drawn in by it. ",
        "Small groups can swing on a handful of students. Treat what you find here as a starting point ",
        "for questions, not a conclusion."
      )
    )
  )
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
           class = "cedar-lead"),

    tags$h3("1. Building a Student Group", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/branches/population.R</code><br>
            <strong>Functions:</strong> <code>build_population()</code> →
            <code>get_focal_programs()</code>,
            <code>get_ongoing_ids()</code>, <code>get_graduated_ids()</code>,
            <code>get_switched_out_ids()</code>, <code>get_never_declared_ids()</code>,
            <code>get_entry_pathways()</code>, <code>classify_origin()</code>,
            <code>classify_entry_method()</code>, <code>classify_entry_status()</code>,
            <code>build_demographic_population()</code>")
    ),

    tags$p(HTML("A student population is built in three stages: (1) identify <em>candidates</em>
                 — any student who ever appeared in the focal major; (2) <em>classify outcomes</em>
                 — determine what happened to each candidate relative to the major; (3) <em>filter
                 and label</em> — include the desired outcome groups and assign labels.
                 The result (a tibble with <code>student_id</code>, <code>population_label</code>,
                 <code>outcome</code>, <code>entry_pathway</code>, <code>origin</code>,
                 <code>entry_method</code>, <code>entry_status</code>, <code>relevant_until</code>)
                 is passed to every downstream analysis.")),

    tags$h4("Outcomes", class = "help-h4"),
    tags$ul(
      tags$li(HTML("<strong>ongoing</strong> — still declared in the focal major in the most recent data term.")),
      tags$li(HTML("<strong>graduated</strong> — received a degree in the focal major in their last focal term.")),
      tags$li(HTML("<strong>switched_out</strong> — left the focal major but remained at UNM. Detected two ways: (1) a formal declaration of another major after their last focal term in <code>cedar_programs</code>; (2) any enrollment record in <code>cedar_students</code> after their last focal term, even without a re-declaration.")),
      tags$li(HTML("<strong>stopped_out</strong> — all declared candidates not accounted for by ongoing, graduated, or switched_out. No UNM enrollment or major record after their last focal term.")),
      tags$li(HTML("<strong>chose_elsewhere</strong> — appeared only as a pre-major; never declared the focal major, but did declare a different major afterward.")),
      tags$li(HTML("<strong>left_undeclared</strong> — appeared only as a pre-major; never declared any major and has no later major record in the available data. Displayed as <em>Stopped before declaring</em>."))
    ),

    tags$h4("Entry pathway (<code>entry_pathway</code>)", class = "help-h4"),
    tags$p("How the student arrived at the focal major — computed by", tags$code("get_entry_pathways()"), ":"),
    tags$ul(
      tags$li(HTML("<strong>direct</strong> — first major at UNM was the focal major (no prior declared major or pre-major).")),
      tags$li(HTML("<strong>switched_in</strong> — had a non-focal declared major before declaring the focal major.")),
      tags$li(HTML("<strong>pre_major</strong> — appeared as a focal pre-major before (or instead of) declaring."))
    ),

    tags$h4("Entry classification columns", class = "help-h4"),
    tags$ul(
      tags$li(HTML("<strong>entry_method</strong> (<code>classify_entry_method()</code>) — <em>first_program</em>: no prior major record of any kind before this unit; <em>switched_in</em>: had at least one prior major record; <em>unclear</em>: first unit record is at the earliest available term, so prior history is unobservable.")),
      tags$li(HTML("<strong>entry_status</strong> (<code>classify_entry_status()</code>) — whether the student’s first record in this unit was as a <em>pre_major</em> or a declared <em>major</em>."))
    ),

    tags$h4("Enrollment window (<code>relevant_until</code>)", class = "help-h4"),
    tags$p(HTML("Each non-ongoing population student carries a <code>relevant_until</code> term: their
                 <code>last_declared_term</code> (last term with a declared, non-pre-major focal record).
                 Course enrollments <em>after</em> that term are excluded from all analyses. A student
                 who was History for 2 terms, then switched to Business for 8 terms, contributes only
                 the 2 History terms to the analysis. Ongoing students have
                 <code>relevant_until = NA</code> (no restriction).")),

    tags$h4("Worked example — dept = HIST, default scope (declared + pre-major)", class = "help-h4"),
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
        tags$tr(tags$td("S001"),tags$td("History"),tags$td("Major"),tags$td("FALSE"),tags$td("ongoing"),tags$td("✓ included",class="hl")),
        tags$tr(tags$td("S002"),tags$td("History"),tags$td("Second Major"),tags$td("FALSE"),tags$td("ongoing"),tags$td("✓ included (Second Major counts)",class="hl")),
        tags$tr(tags$td("S003"),tags$td("History"),tags$td("Major"),tags$td("TRUE"),tags$td("chose_elsewhere / left_undeclared"),tags$td("— excluded unless pre-major scope is included")),
        tags$tr(tags$td("S004"),tags$td("English"),tags$td("Major"),tags$td("FALSE"),tags$td("—"),tags$td("— excluded (different dept)")),
        tags$tr(tags$td("S005"),tags$td("History"),tags$td("Minor"),tags$td("FALSE"),tags$td("—"),tags$td("— excluded (Minor)"))
      )
    ),

    tags$p(HTML("<strong>What programs belong to a department?</strong> The selector uses
                 <code>cedar_programs$dept_code</code>, which is assigned during transformation from
                 program/catalog and subject lookup tables with a final identity fallback when no
                 explicit mapping exists. Mapping issues are surfaced under Admin → Data & Usage
                 → Mappings; questionable fallbacks also appear in the Pathways scope bar."),
           class = "text-muted-sm"),

    # =========================================================================
    tags$h3("2. Roadblocks — DFW as a Predictor of Leaving", class = "help-h3"),
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
        tags$tr(tags$td("DR (early drop)"),tags$td("any"),tags$td("dfw — non-completion regardless of grade",class="hl")),
        tags$tr(tags$td("RE / RS / RR"),tags$td("D, D+, D–, F, W, RD, RF"),tags$td("dfw",class="hl")),
        tags$tr(tags$td("RE / RS / RR"),tags$td("A–C, CR, P, S, RA–RC, RCR"),tags$td("pass",class="hl")),
        tags$tr(tags$td("RE / RS / RR"),tags$td("I, AUD, NR, or other"),tags$td("excluded — ungraded, no signal")),
        tags$tr(tags$td("WL / other"),tags$td("any"),tags$td("excluded"))
      )
    ),

    tags$h4("Step 2: Determine whether each student returned the following term", class = "help-h4"),
    tags$p(HTML("For each student in each term, we check whether they appear in
                 <code>cedar_students</code> in the <em>next fall or spring</em>.
                 Summer is not counted — skipping summer is normal and not a stop-out.")),

    tags$h4("Graduate correction", class = "help-h4"),
    tags$p(HTML("Students who earned a degree in term T are <strong>not counted as stopped out</strong>
                 for that term, even though they don’t appear in term T+1. Without this correction,
                 every graduate who finished their program would be misclassified as a stop-out.
                 The correction uses <code>cedar_degrees$term</code> to identify graduation terms.")),
    div(class = "alert-box alert-box--watch",
      tags$strong("⚠ Partial coverage:"),
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
      "<strong>pass_stopout_rate</strong> = 1/2 = 0.500 (S002 didn’t return)<br>
       <strong>dfw_stopout_rate</strong> = 2/3 = 0.667 (S004, S005 didn’t return)<br>
       <strong>stopout_gap</strong> = 0.667 − 0.500 = 0.167<br>
       <strong>p_value</strong>: chi-squared test on the 2×2 contingency table (outcome × returned).
       Skipped if either group has fewer than 5 students — result is NA."
    )),

    div(class = "alert-box alert-box--watch",
      tags$strong("⚠ Known anomalies to watch for:"),
      tags$ul(class = "mt-1",
        tags$li("The module caps Pathways analyses at the term before the current term. If source
                  data or precomputed next-term lookups do not include a visible following fall/spring
                  for the latest analyzed term, recently active courses can still show inflated
                  stop-out rates."),
        tags$li(HTML("Rows where <code>pop_n_dfw</code> is very small (1–4) produce
                       unreliable rates. The Min group DFW students filter (default 5) removes these.")),
        tags$li("The baseline is ALL non-group students in the same courses."),
        tags$li("Stop-out is measured as ‘returned to UNM,’ not ‘continued in the program.’")
      )
    ),

    # =========================================================================
    tags$h3("3. Course Timing — When Students Take Each Course", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/cones/pathway.R</code><br>
            <strong>Functions:</strong> <code>get_course_timing()</code>,
            <code>plot_curriculum_map()</code>")
    ),

    tags$p("Computes where population students took each course along the selected x-axis.
            The default x-axis is total-credit bands, so transfer and continuing students are
            compared by credits earned rather than by calendar year or first observed term."),

    tags$h4("X-axis choices", class = "help-h4"),
    tags$ul(
      tags$li(HTML("<strong>Total credits:</strong> 0–30, 31–60, 61–90, 91–120, 121+ credits earned, including transfer credit.")),
      tags$li(HTML("<strong>UNM credits:</strong> the same bands, using institutional credits attempted only.")),
      tags$li(HTML("<strong>Relative term:</strong> 1st, 2nd, 3rd… observed enrolled term for each student.")),
      tags$li(HTML("<strong>Classification:</strong> Freshman, Sophomore, Junior, or Senior at the time of enrollment."))
    ),

    tags$h4("How relative term is defined", class = "help-h4"),
    tags$p(HTML("Relative term 1 is the <strong>first term in which the student has a registered
                 course record in <code>cedar_students</code></strong>. It is not necessarily their
                 first semester at UNM or their first semester in the program. It is
                 <code>row_number()</code> over distinct enrolled terms, sorted by UNM term code.")),

    tags$h4("Skipped semesters", class = "help-h4"),
    tags$p("The counter only increments for terms with actual registered enrollment.
            Gaps are invisible. A student enrolled in Fall, absent in Spring, enrolled in Fall
            has relative terms 1 and 2 — not 1 and 3. There is no concept of
            “missed term 2” in this model."),

    tags$h4("Summer terms", class = "help-h4"),
    tags$p(HTML("By default, summer does <em>not</em> advance the counter.
                 Summer courses are pinned to the relative term of the immediately preceding
                 fall or spring. A student taking a summer course between their 2nd and 3rd
                 fall/spring semesters has those summer courses recorded as relative term 2.
                 The current Pathways UI does not expose an Include summer toggle, so the app
                 always uses the default non-summer-advancing behavior.")),

    tags$h4("Denominator", class = "help-h4"),
    tags$p(HTML("Each cell is a percentage: students who took the course at that x-axis position
                 divided by students observed at that position. For relative term, that means
                 students whose enrollment record reached that term. For credit bands and
                 classification, it means students with any enrollment in that band or class.")),

    div(class = "alert-box alert-box--watch",
      tags$strong("⚠ Left-truncation artifact — Freshman-start filter is applied automatically:"),
      tags$p(HTML("Students who were already enrolled when CEDAR data begins (Fall 2018) have
                   relative term 1 set to Fall 2018, regardless of how long they had actually
                   been at UNM. A senior in Fall 2018 looks like a first-semester student, which
                   makes the chart meaningless. This is called <em>left truncation</em>."), class = "mt-1"),
      tags$p(HTML("To reduce this artifact, the app <strong>automatically restricts the relative-term axis
                   to students whose first observed registered term in CEDAR is classified as Freshman</strong>.
                   This is a practical proxy for first-semester students, not independent proof of
                   first-time-freshman status. You can override this by selecting a different
                   Starting Classification in the filters."), class = "mt-1"),
      tags$p(HTML("This filter does <em>not</em> apply to the Classification, Inst. Credits, or
                   Overall Credits x-axis modes — those use actual Banner values recorded at the
                   time of enrollment and are unaffected by when the data window starts."), class = "mt-1")
    ),

    # =========================================================================
    tags$h3("4. Course Pairs — Common Sequences", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>File:</strong> <code>R/cones/pathway.R</code><br>
            <strong>Function:</strong> <code>get_course_pairs()</code>")
    ),

    tags$p(HTML("Finds ordered pairs (A → B) where group students took Course A in one
                 relative term and Course B in a later term, within a configurable term gap.")),

    tags$h4("Exact computation", class = "help-h4"),
    tags$ol(
      tags$li(HTML("Assign relative terms, then self-join enrolled records on <code>student_id</code> where
                    <code>relative_term_B &gt; relative_term_A</code> and
                    <code>relative_term_B − relative_term_A ≤ max_term_gap</code> and
                    <code>course_A ≠ course_B</code>.")),
      tags$li("Count distinct students per (course_A, course_B) pair."),
      tags$li(HTML("<strong>pct_a_to_b</strong> = students who took both ÷ students who took A."))
    ),

    div(class = "alert-box alert-box--watch",
      tags$strong("⚠ This is correlation, not causation."),
      " A high pct_a_to_b means students who took A commonly went on to take B.
        It does not mean A is a prerequisite for B or that taking A causes students to take B."
    ),

    # =========================================================================
    tags$h3("5. Course to Major — Course Associations Before/Into the Unit", class = "help-h3"),
    div(class = "alert-box alert-box--code",
      HTML("<strong>Files:</strong>
            <code>R/cones/gen-ed-conversion.R</code> (course + instructor associations),
            <code>R/cones/major-changes.R</code> (entry heatmap),
            <code>R/modules/pathways.R</code> (focal subject/dept resolution and display)<br>
            <strong>Key functions:</strong> <code>get_course_major_associations()</code>,
            <code>get_entry_heatmap()</code>")
    ),

    tags$p(HTML("This subtab has two related but different scopes. The
                 <strong>Course + Instructor Associations</strong> table is department/course scoped:
                 the selected Pathways population is used to resolve the focal department and subject
                 prefixes, but the table itself is computed from all enrolled students in those focal
                 courses. The <strong>Courses Before Major Entry</strong> heatmaps are population scoped:
                 they use only students in the selected population and look backward from each student's
                 first focal program record.")),

    tags$h4("Course + Instructor Associations", class = "help-h4"),
    tags$ol(
      tags$li(HTML("Resolve focal subject prefixes from the selected population's department codes.
                    Department codes are not assumed to be course prefixes; they are translated through
                    <code>cedar_lookups$subject_lookup</code>.")),
      tags$li(HTML("Filter <code>cedar_students</code> to registered enrollments in those focal subjects.
                    The level, campus, Gen Ed only, and date-range controls apply here.")),
      tags$li(HTML("For each enrollment, find the student's first <code>cedar_programs</code> record in
                    the focal department (<code>program_type %in% c('Major', 'Second Major')</code>).
                    A student is eligible for that course term only if they had no department major or
                    pre-major before the enrollment term.")),
      tags$li(HTML("<strong>Later declared</strong> means the first focal-department program record exists
                    at the course term or in a later term. This includes students whose first focal record
                    is a pre-major or a declared major.")),
      tags$li(HTML("Rows are grouped by <code>subject_course + instructor_name</code>. Distinct students are
                    counted within each group; totals across visible groups are group memberships, not
                    unique headcount, because one student can take multiple focal courses."))
    ),

    tags$h4("Courses Before Major Entry heatmaps", class = "help-h4"),
    tags$ol(
      tags$li(HTML("Use <code>population$first_unit_term</code> as each student's entry anchor. This is
                    scoped to the focal program and avoids accidentally anchoring switchers to their prior
                    non-focal major.")),
      tags$li(HTML("Build lag terms by walking backward through the sorted non-summer term sequence.
                    <code>T-1</code> is the prior regular term, <code>T-2</code> two regular terms back, and so on.")),
      tags$li(HTML("Count population students who took each course at each lag. Split courses into focal
                    subjects versus other departments.")),
      tags$li(HTML("Compute <code>pct_of_majors</code> as students in that course-lag cell divided by the
                    selected population size, and <code>pct_converted</code> as those students divided by all
                    students enrolled in the same course/term slots. The heatmap currently visualizes
                    <code>pct_of_majors</code>.")),
      tags$li(HTML("The heatmaps use Min N and Heatmap lag only. Campus, level, Gen Ed only, and date-range
                    controls are association-table filters and do not affect the heatmaps."))
    ),

    div(class = "alert-box alert-box--watch",
      tags$strong("⚠ Interpretive boundary:"),
      " Course to Major is descriptive. It can show which courses students commonly took before or near
        department entry, and which course/instructor groups are associated with later department records.
        It does not establish that a course or instructor caused a student to declare."
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

    tags$p("Detects when a student’s primary declared major changed from one observed primary-major record to the next,
            then summarizes those transitions for the selected student group."),

    tags$h4("Step 1: Detect change events", class = "help-h4"),
    tags$p(HTML("Source: <code>detect_major_changes()</code> in <code>R/cones/major-changes.R</code>.")),
    tags$ol(
      tags$li(HTML("Filter <code>cedar_programs</code> to <code>program_type == “Major”</code>
                    rows for the population students only.")),
      tags$li(HTML("Sort by <code>student_id</code>, <code>term</code>. Use <code>lag()</code> to get
                    each student’s program in the prior term (<code>prev_major</code>) and their prior
                    academic level (<code>prev_level</code>).")),
      tags$li(HTML("Flag a change when <code>program_name != prev_major</code> AND
                    <code>(is.na(prev_level) | student_level == prev_level)</code>. The level
                    check excludes transitions between undergraduate and graduate programs —
                    a History BA student enrolling in Law School is not a “major change”
                    in the undergraduate sense. First records are not change events because
                    <code>prev_major</code> is missing.")),
      tags$li(HTML("Each flagged row becomes one change event with: <code>student_id</code>,
                    <code>change_term</code>, <code>from_major</code>, <code>to_major</code>, and four
                    credit columns. All are <em>attempted</em> hours (not earned, so they aren’t
                    deflated by W/F grades from the abandoned major):
                    <code>unm_credits_at_change</code> / <code>total_credits_at_change</code> are the
                    cumulative hours as Banner recorded them at <code>change_term</code>
                    (UNM-only vs. UNM + transfer);
                    <code>unm_credits_before_change</code> / <code>total_credits_before_change</code> are
                    the <strong>lag-adjusted</strong> hours via <code>lag()</code> — the cumulative
                    totals as of <code>prev_term</code>.")),
      tags$li(HTML("<strong>Why lag-adjust?</strong> A major change typically posts to Banner the
                    term <em>after</em> the student actually switches, so the credits recorded at
                    <code>change_term</code> overstate credits-at-decision by roughly one term’s
                    load (~15). Because the credit columns are running totals, <code>lag()</code>
                    subtracts exactly that student’s lagged-term hours — not a flat estimate.
                    Summaries and the cards above use the <code>*_before_change</code> figures."))
    ),

    tags$h4("Worked example — History student program history", class = "help-h4"),
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
        tags$tr(tags$td("S001"),tags$td("202310"),tags$td("Psychology"),tags$td("Undergraduate"),tags$td("(none)"),tags$td("— first term, no change")),
        tags$tr(tags$td("S001"),tags$td("202380"),tags$td("Psychology"),tags$td("Undergraduate"),tags$td("Psychology"),tags$td("— same major")),
        tags$tr(tags$td("S001"),tags$td("202410"),tags$td("History"),tags$td("Undergraduate"),tags$td("Psychology"),tags$td("✓ change event: Psych → History",class="hl")),
        tags$tr(tags$td("S001"),tags$td("202480"),tags$td("History"),tags$td("Undergraduate"),tags$td("History"),tags$td("— same major")),
        tags$tr(tags$td("S001"),tags$td("202710"),tags$td("Juris Doctor"),tags$td("Graduate/GASM"),tags$td("History"),tags$td("— level changed (UG→GR), excluded"))
      )
    ),

    tags$h4("Step 2: Derive focal majors", class = "help-h4"),
    tags$p(HTML("Source: <code>mc_data</code> reactive in <code>R/modules/pathways.R</code>.")),
    tags$p(HTML("Focal majors are the majors that <em>define</em> the selected student group —
                 not all majors ever held by group members. A History cohort student who also
                 declared Political Science should not make PolSci a focal major.")),
    tags$ul(
      tags$li(HTML("<strong>Dept mode</strong> (e.g., HIST): all majors where
                    <code>dept_code == “HIST”</code> and <code>program_type %in%
                    c(“Major”, “Second Major”)</code> in <code>cedar_programs</code>.")),
      tags$li(HTML("<strong>Specific majors mode</strong>: exactly the majors the user selected
                    in the population filters.")),
      tags$li(HTML("<strong>Preset mode</strong>: the <code>program_names</code> list from
                    the population opt."))
    ),

    tags$h4("Step 3: Filter to focal changes", class = "help-h4"),
    tags$p(HTML("From the full set of change events, keep only rows where
                 <code>from_major %in% focal_programs OR to_major %in% focal_programs</code>.
                 This means a History cohort sees:")),
    tags$ul(
      tags$li("Psychology → History (arriving to History) ✓"),
      tags$li("History → Political Science (leaving History) ✓"),
      tags$li("Political Science → Law (made by a History student, but neither side is History) ✗ excluded")
    ),

    tags$h4("Step 4: Build summary outputs", class = "help-h4"),
    tags$p(HTML("Source: <code>major_change_pathways()</code> in <code>R/cones/major-changes.R</code>.")),
    tags$ul(
      tags$li(HTML("<strong>Inflow / Outflow table</strong>: count change events by <code>to_major</code>
                    (arrivals) and <code>from_major</code> (departures) in focal changes, then filter
                    to rows where the major is in focal_programs. Net = arrivals − departures.")),
      tags$li(HTML("<strong>Common Pathways table</strong>: group focal changes by
                    (from_major, to_major), count events, and compute <code>avg_unm_credits</code>
                    and <code>avg_total_credits</code> = average lag-adjusted attempted hours
                    (<code>*_before_change</code>) at the moment of the switch, UNM-only and
                    UNM + transfer. Minimum threshold (default 3) removes rare pairs.")),
      tags$li(HTML("<strong>Avg credits</strong> is a proxy for timing: 30 credits ≈ freshman year,
                    60 ≈ sophomore, 90 ≈ junior. A History → Political Science pair at 75 UNM credits
                    means students are switching in their junior year on average. The <em>total</em>
                    column is usually higher for transfer-heavy programs, since it counts hours
                    brought in from elsewhere.")),
      tags$li(HTML("<strong>Trend sparkline</strong>: per-term count of arrivals
                    (<code>to_major %in% focal</code>, green) and departures
                    (<code>from_major %in% focal</code>, red).")),
      tags$li(HTML("<strong>Donuts</strong>: “Leaving for” = top <code>to_major</code>
                    values among departures. “Arriving from” = top <code>from_major</code>
                    values among arrivals. If the selected unit contains multiple focal majors,
                    focal-to-focal changes can appear."))
    ),

    tags$h4("Worked example — Inflow / Outflow for a History dept cohort", class = "help-h4"),
    tags$table(class = "help-tbl",
      tags$thead(tags$tr(
        tags$th("major"),
        tags$th("students arriving to"),
        tags$th("students leaving for elsewhere"),
        tags$th("net")
      )),
      tags$tbody(
        tags$tr(tags$td("History",class="hl"),tags$td("47"),tags$td("31"),tags$td("+16",class="hl")),
        tags$tr(tags$td("History / Pre-Law",class="hl"),tags$td("5"),tags$td("12"),tags$td("−7"))
      )
    ),
    tags$p("Only History-dept programs appear. The 47 arriving students came from other majors;
            the 31 departures went to other majors (shown in the “Leaving for” donut).",
           class = "text-muted-sm"),

    div(class = "alert-box alert-box--watch",
      tags$strong("⚠ Known edge cases:"),
      tags$ul(class = "mt-1",
        tags$li("A student who switched History → PolSci → History generates two change events.
                  Both appear in the tables. The net can mask churn."),
        tags$li("Pre-major → declared transitions within the same program are not flagged
                  as changes (same program_name, different is_pre_major flag)."),
        tags$li("The minimum event threshold filter removes pairs with fewer than N events.
                  Rare pathways that may still be meaningful are hidden. Lower the threshold to see them.")
      )
    ),

    # =========================================================================
    div(class = "alert-box alert-box--code",
      style = "margin-top: 32px;",
      tags$strong("Reading this with Claude or GitHub Copilot:"),
      tags$p(HTML("Each section above names the exact file and function that implements it.
              To go deeper, open the file in your editor, select the function body, and ask
              “explain this function” or “what does this do step by step?”
              All functions have parameter descriptions in the header comment.<br><br>
              For a fuller picture, paste the function into Claude along with a specific question —
              for example: “Why does <code>get_switched_out_ids()</code> use <code>last_focal_term + 100</code>
              as an upper bound?” or “What edge cases does the enrollment-based switch detection handle
              that the program-record check misses?” The code is designed to be readable; the AI fills
              in the reasoning."),
             class = "mt-1")
    ),

    tags$p(class = "text-note", style = "margin-top: 16px; border-top: 1px solid #eee; padding-top: 12px;",
      HTML("Methodology reflects: <code>R/branches/population.R</code> (group builder),
            <code>R/cones/stopout.R</code>,
            <code>R/cones/pathway.R</code>, <code>R/cones/major-changes.R</code>,
            and <code>R/modules/pathways.R</code> (display logic).
            Update this panel when cone logic changes."))

  ) # end div
}


# =============================================================================
# Pathways tab module — server
# =============================================================================

pathwaysServer <- function(id, students, programs, degrees = NULL,
                           cedar_grades = NULL, cedar_next_term = NULL,
                           lookups = list()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    make_pathways_table <- function(df, page_size = 25, columns = list(),
                                    selection = NULL, on_click = NULL,
                                    full_width = TRUE) {
      if (is.null(df) || nrow(df) == 0) return(NULL)
      columns <- columns[names(columns) %in% names(df)]
      reactable::reactable(
        df,
        theme = cedar_tbl_theme,
        striped = TRUE,
        highlight = TRUE,
        compact = TRUE,
        searchable = TRUE,
        fullWidth = full_width,
        defaultPageSize = page_size,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(25, 50, 100),
        selection = selection,
        onClick = on_click,
        columns = columns
      )
    }

    message_table <- function(message) {
      make_pathways_table(data.frame(Message = message), page_size = 25, full_width = FALSE)
    }

    numeric_col_defs <- function(df, digits = 3, extra = list()) {
      nums <- names(df)[vapply(df, is.numeric, logical(1))]
      defs <- lapply(nums, function(col) {
        reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = digits)
        )
      })
      names(defs) <- nums
      utils::modifyList(defs, extra)
    }

    course_timing_display <- function(df, x_axis = "overall_credit_band") {
      if (is.null(df) || nrow(df) == 0) return(df)

      bucket_label <- switch(
        x_axis,
        relative_term = paste0("Term ", df$relative_term),
        classification = dplyr::case_when(
          df$relative_term == 1L ~ "Freshman",
          df$relative_term == 2L ~ "Sophomore",
          df$relative_term == 3L ~ "Junior",
          df$relative_term == 4L ~ "Senior",
          TRUE ~ as.character(df$relative_term)
        ),
        inst_credit_band = dplyr::case_when(
          df$relative_term == 1L ~ "0-30",
          df$relative_term == 2L ~ "31-60",
          df$relative_term == 3L ~ "61-90",
          df$relative_term == 4L ~ "91-120",
          df$relative_term == 5L ~ "121+",
          TRUE ~ as.character(df$relative_term)
        ),
        overall_credit_band = dplyr::case_when(
          df$relative_term == 1L ~ "0-30",
          df$relative_term == 2L ~ "31-60",
          df$relative_term == 3L ~ "61-90",
          df$relative_term == 4L ~ "91-120",
          df$relative_term == 5L ~ "121+",
          TRUE ~ as.character(df$relative_term)
        ),
        as.character(df$relative_term)
      )

      df %>%
        dplyr::group_by(subject_course) %>%
        dplyr::mutate(total_students = sum(n_students, na.rm = TRUE)) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(
          timing_bucket = bucket_label,
          n_students = as.integer(n_students),
          n_eligible = as.integer(n_eligible),
          total_students = as.integer(total_students)
        ) %>%
        dplyr::select(
          subject_course,
          course_title,
          subject_code,
          timing_bucket,
          n_students,
          n_eligible,
          pct_pop,
          total_students
        )
    }

    color_from_cuts <- function(value, thresholds, colors) {
      if (is.na(value)) return(NULL)
      colors[findInterval(value, thresholds) + 1L]
    }

    # ---- Population selector sub-module ----
    population_rv <- populationSelectorServer("population", programs,
                                               degrees = degrees, students = students)

    # Convenience accessors
    get_population  <- function() population_rv()$population
    get_description <- function() population_rv()$description

    # All analysis tabs use the population created by the top Population scope
    # control. Major/pre-major distinctions are shown in the Population audit
    # rather than acting as a hidden global analysis filter.
    get_analysis_population <- reactive({
      get_population()
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
          class = "scope-bar scope-bar--stacked scope-bar-placeholder",
          "Define your student population first. Choose programs in the filters above and click Apply Population before running any analysis."
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
          paste0("cedar_programs.dept_code = “", opt$dept_code, "”")
        } else if (opt$type %in% c("major", "preset") &&
                   length(opt$program_names %||% character(0)) > 0) {
          nms <- opt$program_names
          if (length(nms) == 1) {
            paste0("cedar_programs.program_name = “", nms, "”")
          } else {
            paste0("cedar_programs.program_name ∈ {",
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
          # Each "CODE (Name)" pair is wrapped in a nowrap span so the code and its
          # parenthetical name never break across lines, while the list as a whole
          # still wraps at the " · " separators. (Replaces an embedded NBSP.)
          pair_spans <- Map(function(code, name)
            tags$span(class = "text-nowrap", paste0(code, " (", name, ")")),
            coded$major_code, coded$program_name)
          join_pairs <- function(spans) {
            out <- list()
            for (i in seq_along(spans)) {
              if (i > 1L) out[[length(out) + 1L]] <- " · "
              out[[length(out) + 1L]] <- spans[[i]]
            }
            do.call(tagList, out)
          }
          coded_text <- if (nrow(coded) == 0) {
            NULL
          } else if (length(pair_spans) > MAX_SHOW) {
            tagList(join_pairs(pair_spans[seq_len(MAX_SHOW)]),
                    paste0(" · … +", nrow(coded) - MAX_SHOW, " more"))
          } else {
            join_pairs(pair_spans)
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
        label_display <- c(
          major = "entered as declared major",
          pre_major = "entered as pre-major",
          first_program = "first program",
          switched_in = "switched in",
          unclear = "unclear",
          transfer = "transfer",
          unm = "UNM",
          unknown = "unknown"
        )
        counts <- population %>%
          group_by(population_label) %>%
          summarize(n = n(), .groups = "drop") %>%
          arrange(desc(n)) %>%
          mutate(label = dplyr::coalesce(unname(label_display[population_label]), population_label))
        paste(counts$label, format(counts$n, big.mark = ","), sep = ": ", collapse = " / ")
      } else NULL

      analysis_window <- if (!is.null(analysis_through)) {
        max_data_term <- max(programs$term, na.rm = TRUE)
        tagList(
          tags$br(),
          tags$strong("Analysis through: "),
          fmt_term(analysis_through),
          if (max_data_term > analysis_through)
            tags$span(
              class = "text-muted-sm",
              paste0(" (", fmt_term(max_data_term), " confirms ongoing status only)")
            )
        )
      }

      # NOTE: the per-outcome breakdown that used to render here (Major status /
      # Pre-major status counts) was removed from this persistent callout. It lives
      # on the Population audit subtab as detailed cards; echoing it here meant it
      # trailed onto every analysis subtab where it was just noise.
      tagList(
        div(class = "pathways-population-callout",
          div(class = "pathways-population-callout-main",
            tags$span(class = "pathways-population-count", n_total, " students"),
            tags$span(class = "pathways-population-description", description)
          ),
          if (!is.null(label_breakdown)) {
            div(class = "pathways-population-detail",
              tags$strong("Groups: "),
              label_breakdown
            )
          },
          if (!is.null(focal_codes_result) || nrow(prog_span) > 0) {
            div(class = "pathways-population-detail pathways-population-detail-bordered",
              tags$strong("Program records: "),
              fmt_term(prog_span$from),
              "–",
              fmt_term(prog_span$to),
              analysis_window,
              if (!is.null(focal_codes_result)) tagList(
                tags$br(),
                tags$strong("Matched on: "),
                focal_codes_result$match_basis,
                tags$span(" (Major + Second Major records only)", class = "text-muted-sm")
              ),
              if (!is.null(focal_codes_result) && !is.null(focal_codes_result$coded_text)) tagList(
                tags$br(),
                tags$strong("Resolved to: "),
                focal_codes_result$coded_text
              ),
              if (!is.null(focal_codes_result) && !is.null(focal_codes_result$uncoded)) tags$span(
                class = "pathways-population-warning",
                paste0(paste(focal_codes_result$uncoded, collapse = ", "),
                       ": matched by program name only — no major code found in any record")
              )
            )
          },
          # Dept-code mapping diagnostic: show ALL major_codes that resolve to the
          # focal dept_code(s), grouped by whether they matched via lookup tiers or
          # fell through to the identity fallback (tier 4). Surfaces grad program
          # codes that don't resolve correctly.
          local({
            subj_lu <- lookups$subject_lookup %||% tibble(subject_code = character(), dept_code = character())
            focal_dc <- if (opt$type == "dept") {
              opt$dept_code
            } else if (opt$type %in% c("major", "preset")) {
              programs %>%
                filter(program_name %in% (opt$program_names %||% character(0)), !is_pre_major) %>%
                pull(dept_code) %>% unique() %>% na.omit()
            } else character(0)

            if (length(focal_dc) > 0) {
              # All major_codes that resolved to these dept_codes in cedar_programs
              resolved <- programs %>%
                filter(program_type %in% c("Major", "Second Major"),
                       dept_code %in% focal_dc) %>%
                distinct(major_code, program_name, dept_code, student_level) %>%
                filter(!is.na(major_code))

              # Codes in lookup tiers 1-3 (would resolve without the identity fallback)
              in_subj   <- names(subj_to_dept)[subj_to_dept %in% focal_dc]
              in_major  <- names(major_to_dept)[major_to_dept %in% focal_dc]
              in_mcd    <- {
                matches <- major_college_to_dept[major_college_to_dept %in% focal_dc]
                sub(":.*$", "", names(matches))
              }
              known_codes <- unique(c(in_subj, in_major, in_mcd))

              # Codes that only resolved via tier-4 identity fallback
              all_codes <- unique(resolved$major_code)
              fallback_codes <- setdiff(all_codes, known_codes)
              # Remove F-prefix pre-major codes and numeric codes — those are expected
              fallback_codes <- fallback_codes[
                !grepl("^F[A-Z]", fallback_codes) &
                !grepl("^[0-9]+$", fallback_codes) &
                !fallback_codes %in% focal_dc  # codes that ARE the dept_code are fine
              ]

              if (length(fallback_codes) > 0) {
                # Show what these codes resolved to and how many students they affect
                fb_detail <- resolved %>%
                  filter(major_code %in% fallback_codes) %>%
                  group_by(major_code, program_name) %>%
                  summarize(
                    levels = paste(sort(unique(student_level)), collapse = "/"),
                    .groups = "drop"
                  ) %>%
                  mutate(label = paste0(major_code, " (", program_name, ", ", levels, ")"))

                div(class = "pathways-population-detail pathways-population-detail-bordered",
                  style = "color: #8a5a00;",
                  tags$strong("⚠ Unmapped major codes: "),
                  paste(fb_detail$label, collapse = " · "),
                  tags$br(),
                  tags$span(
                    style = "font-size: 0.82em;",
                    "These codes resolved to dept_code via identity fallback (tier 4). ",
                    "If they belong to this department, add them to extra_p2d in R/lists/program_code_maps.R. ",
                    "Students with these codes may not be recognized as prior affiliates in Course to Major."
                  )
                )
              }
            }
          }),
          if (split_by == "entry" && n_unclear > 0) {
            div(class = "pathways-population-detail pathways-population-detail-bordered",
              tags$strong(format(n_unclear, big.mark = ","),
                          if (n_unclear == 1) " student excluded" else " students excluded"),
              " from pathway groups — their records begin at the earliest available term,",
              " so whether they arrived directly or switched in cannot be confirmed from the data."
            )
          }
        )
      )
    })

    # Modal guard — show a blocking dialog if any Run button is clicked before a population is built
    walk(c("so_run", "ct_run", "cp_run", "ge_conv_run"), function(btn_id) {
      observeEvent(input[[btn_id]], {
        if (!population_built()) {
          showModal(modalDialog(
            title = "No population defined",
            p("You need to define a student population before running analysis."),
            p("Use the population filters at the top of the page:"),
            tags$ol(
              tags$li("Choose a selection type (Major Group, Department, etc.)"),
              tags$li("Select your majors or filters"),
              tags$li("Click ", tags$strong("Apply Population"))
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

    so_auto  <- reactiveVal(0L)
    ct_auto  <- reactiveVal(0L)
    cp_auto  <- reactiveVal(0L)
    ge_auto  <- reactiveVal(0L)
    # Major Changes has no auto trigger: mc_data is a plain reactive on the
    # population, so it re-runs on rebuild on its own (no Run button to re-fire).

    observeEvent(population_rv(), {
      prior <- has_prior_population()
      has_prior_population(TRUE)
      if (!prior) return()

      switch(input$analysis_tabs,
        "Roadblocks"       = so_auto(so_auto()   + 1L),
        "Course Timing"    = ct_auto(ct_auto()   + 1L),
        "Course Pairs"     = cp_auto(cp_auto()   + 1L),
        "Course to Major"  = ge_auto(ge_auto()   + 1L)
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
      pop <- tryCatch(population_rv()$population, error = function(e) NULL)
      apply_pathways_population_window(students, pop, analysis_through)
    })

    # Pre-windowed cedar_grades: apply the same analysis_through + relevant_until
    # windowing as filtered_students, but to the pre-classified grade table.
    # This is passed to get_stopout/get_dfw_rates so they skip the expensive
    # classify_outcomes(1.7M rows) call entirely.
    # Returns NULL if cedar_grades was not loaded (file doesn't exist yet).
    filtered_cedar_grades <- reactive({
      g <- cedar_grades
      if (is.null(g) || nrow(g) == 0) return(NULL)

      pop <- tryCatch(population_rv()$population, error = function(e) NULL)
      apply_pathways_population_window(g, pop, analysis_through)
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
      # population_rv is an eventReactive that has not fired until "Apply Population"
      # is clicked; accessing it before then raises a silent pending error. Catch it
      # so the start panel renders on first landing instead of leaving the area blank.
      pop <- tryCatch(get_population(), error = function(e) NULL)
      if (is.null(pop) || nrow(pop) == 0) {
        return(pathways_start_panel())
      }
      rv <- tryCatch(population_rv(), error = function(e) NULL)
      conversion_stats <- rv$conversion_stats %||% attr(pop, "conversion_stats") %||% list()
      n_converted <- as.integer(conversion_stats$n_converted %||% 0L)

      outcome_order <- c("ongoing", "graduated", "switched_out", "stopped_out",
                         "chose_elsewhere", "left_undeclared")
      outcome_labels <- c(
        ongoing        = "Ongoing",
        graduated      = "Graduated",
        switched_out    = "Switched out",
        stopped_out     = "Stopped out after major status",
        chose_elsewhere = "Chose elsewhere",
        left_undeclared = "Stopped before declaring"
      )
      outcome_desc <- c(
        ongoing        = "Still declared in the focal major in the most recent data term.",
        graduated      = "Received a degree in the focal major near their last focal term.",
        switched_out    = "Declared majors only. Left the focal major but remained at UNM — either declared another major or had enrollment records after their last focal term.",
        stopped_out     = "Declared majors only. No UNM enrollment or major record of any kind after their last focal term.",
        chose_elsewhere = "Pre-major only. Never declared this program, but did declare a different program afterward.",
        left_undeclared = "Pre-major only. Never declared any program and has no later major record in the available data."
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

      outcome_counts <- stats::setNames(counts$n, counts$outcome)
      declared_counts <- pop %>%
        filter(!is.na(last_declared_term)) %>%
        count(outcome)
      declared_outcome_counts <- stats::setNames(declared_counts$n, declared_counts$outcome)
      format_pct_count <- function(n, denominator = NULL) {
        n <- as.integer(n %||% 0L)
        if (is.null(denominator) || is.na(denominator) || denominator <= 0) {
          return(format(n, big.mark = ","))
        }
        paste0(round(100 * n / denominator), "% (", format(n, big.mark = ","), ")")
      }
      make_outcome_card <- function(oc, counts = outcome_counts,
                                    label = NULL, description = NULL,
                                    denominator = sum(counts, na.rm = TRUE)) {
        n <- if (oc %in% names(counts)) counts[[oc]] else 0L
        col <- outcome_colors[[oc]] %||% "#555"
        recent_note <- if (oc == "stopped_out" && n_recent_stopped > 0) {
          tags$p(class = "text-note",
            style = "color: #b07000;",
            paste0(n_recent_stopped, " last appeared in ", fmt_term(prev_term),
                   " — may not have fully left yet."))
        }
        div(
          class = "outcome-card",
          style = paste0("border-left: 4px solid ", col, ";"),
          div(
            class = "outcome-card-body",
            tags$span(
              style = paste0("font-size: 1.4em; font-weight: bold; color: ", col, ";"),
              format_pct_count(n, denominator)
            ),
            tags$strong(label %||% outcome_labels[[oc]] %||% oc)
          ),
          tags$p(class = "text-note", description %||% outcome_desc[[oc]] %||% ""),
          recent_note
        )
      }
      make_count_card <- function(n, label, description, color = "#1565c0",
                                  denominator = NULL) {
        div(
          class = "outcome-card",
          style = paste0("border-left: 4px solid ", color, ";"),
          div(
            class = "outcome-card-body",
            tags$span(
              style = paste0("font-size: 1.4em; font-weight: bold; color: ", color, ";"),
              format_pct_count(n, denominator)
            ),
            tags$strong(label)
          ),
          tags$p(class = "text-note", description)
        )
      }
      declared_denominator <- sum(declared_outcome_counts, na.rm = TRUE)
      declared_outcome_cards <- lapply(
        c("ongoing", "graduated", "switched_out", "stopped_out"),
        make_outcome_card,
        counts = declared_outcome_counts,
        denominator = declared_denominator
      )
      n_current_premajor <- if (
        all(c("outcome", "entry_status", "last_declared_term") %in% names(pop))
      ) {
        sum(
          pop$outcome == "ongoing" &
            pop$entry_status == "pre_major" &
            is.na(pop$last_declared_term),
          na.rm = TRUE
        )
      } else 0L
      pre_major_outcomes <- c("chose_elsewhere", "left_undeclared")
      pre_major_counts <- sum(outcome_counts[intersect(pre_major_outcomes, names(outcome_counts))], na.rm = TRUE)
      n_chose_elsewhere <- if ("chose_elsewhere" %in% names(outcome_counts)) {
        outcome_counts[["chose_elsewhere"]]
      } else 0L
      pre_major_left_undeclared <- if ("left_undeclared" %in% names(outcome_counts)) {
        outcome_counts[["left_undeclared"]]
      } else 0L
      pre_major_denominator <- n_current_premajor + n_converted +
        n_chose_elsewhere + pre_major_left_undeclared
      pre_major_stopped <- if (all(c("outcome", "last_unit_term", "last_record_term") %in% names(pop))) {
        sum(
          pop$outcome == "left_undeclared" &
            (is.na(pop$last_record_term) | pop$last_record_term <= pop$last_unit_term),
          na.rm = TRUE
        )
      } else {
        pre_major_left_undeclared
      }
      pre_major_continued_no_major <- pre_major_left_undeclared - pre_major_stopped
      pre_major_stopped_desc <- tagList(
        "Pre-major-status students with no UNM enrollment after their last focal pre-major term."
      )
      current_premajor_card <- make_count_card(
        n_current_premajor,
        "Still pre-major",
        "Pre-major-only students whose focal pre-major record is in the most recent data term.",
        "#2e7d32",
        denominator = pre_major_denominator
      )
      pre_major_outcome_cards <- list(
        make_count_card(
          n_converted,
          "Became majors",
          "Students whose first focal-unit status was pre-major and who later held declared major status in this unit.",
          "#1565c0",
          denominator = pre_major_denominator
        ),
        make_outcome_card(
          "chose_elsewhere",
          denominator = pre_major_denominator
        ),
        make_count_card(
          pre_major_stopped,
          "Stopped out before declaring",
          pre_major_stopped_desc,
          "#4a148c",
          denominator = pre_major_denominator
        ),
        make_count_card(
          pre_major_continued_no_major,
          "Enrolled later, no major found",
          "Pre-major-status students with later UNM enrollment after their last focal pre-major term, but no later major or pre-major record in the available program data.",
          "#6f8b78",
          denominator = pre_major_denominator
        )
      )
      has_pre_major_display <- n_current_premajor > 0 || pre_major_counts > 0 || n_converted > 0

      has_stopped_out  <- "stopped_out" %in% pop$outcome
      has_degrees_data <- !is.null(degrees)

      tagList(
        h4("Major-Status Outcomes", class = "mt-3 mb-1"),
        p(class = "text-hint",
          "These cards describe students who held declared major status in the focal unit. A
           stopped-out student here left after a declared major term."
        ),
        div(class = "pathways-outcome-grid", tagList(declared_outcome_cards)),

        h4("Pre-Major Pipeline", class = "mt-4 mb-1"),
        p(class = "text-hint",
          "These cards track students who appeared as focal pre-majors: still pre-major,
           became majors, chose another major, or stopped out before declaring. The
           stop-out card counts only students with no UNM enrollment after their last
           focal pre-major term."
        ),
        if (has_pre_major_display) {
          div(
            class = "pathways-outcome-grid",
            tagList(c(list(current_premajor_card), pre_major_outcome_cards))
          )
        } else {
          div(class = "alert alert-light", style = "font-size: 0.85em;",
            "No pre-major-only outcomes are included in the current population scope.")
        },

        info_panel(
          "Student Detail",
          p(
            HTML("<code>origin</code>: unm / transfer / unknown. &nbsp;
                  <code>entry_method</code>: first_program (no prior program anywhere) /
                  switched_in (had prior program before this unit) / unclear (data boundary). &nbsp;
                  <code>entry_status</code>: pre_major / major (how they first appeared in this unit). &nbsp;
                  <code>first_unm_term</code> = first UNM enrollment (any program). &nbsp;
                  <code>first_unit_term</code> = first record in this unit. &nbsp;
                  <code>last_unit_term</code> = last record in this unit. &nbsp;
                  <code>last_record_term</code> = last UNM enrollment of any kind.")
          ),
          reactable::reactableOutput(ns("pop_detail_table")),
          description = "Expandable spot-check table with the student-level population classifications behind the cards.",
          class = "cedar-detail-panel"
        ),

        if (has_stopped_out && has_degrees_data) {
          info_panel(
            "Degree Check: Stopped-Out Students",
            p(
              HTML("<strong>within_window</strong> = a degree record was found within one academic year
                    of <code>last_declared_term</code>. These students may be graduates whose degree was
                    processed after their last program record — a known data lag of 1–2 terms.")
            ),
            reactable::reactableOutput(ns("pop_degree_check_table")),
            description = "Expandable audit table for checking whether stopped-out students also have nearby degree records.",
            class = "cedar-detail-panel"
          )
        }
      )
    })

    output$pop_detail_table <- reactable::renderReactable({
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
      make_pathways_table(pop[, display_cols, drop = FALSE])
    })

    output$pop_degree_check_table <- reactable::renderReactable({
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

      make_pathways_table(
        degree_check,
        columns = list(
          within_window = reactable::colDef(
            name = "Within Window",
            cell = function(value) if (isTRUE(value)) "Yes" else "No",
            style = function(value) {
              if (isTRUE(value)) list(backgroundColor = "#fff8e1", fontWeight = "600")
            }
          )
        )
      )
    })


    # ---- Stop-Outs ----

    # Shared level filter for stop-out and DFW: both panels use the same selector.
    so_level_opt <- reactive({
      pathways_level_filter(input$so_level)
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
          tags$strong("⚠ Most-recent-term bias: "),
          "The data extends through ", fmt_term(latest_global), ". ",
          "Students enrolled in that term have no visible next term, so they all appear as stopped out. ",
          "Stop-out rates for recently active courses are inflated. ",
          "To exclude this effect, set a Term filter that ends one term earlier."
        )
      }
    })

    output$so_meta <- renderUI({
      if (is.null(get_population()))
        return(tags$span(class = "scope-bar-placeholder", "Apply a population, then Run to see scope."))
      req(so_data())
      tr       <- so_data()$term_range
      n_courses <- nrow(so_data()$by_course)
      if (any(is.na(tr))) return(NULL)
      div(
        class = "text-hint",
        tags$strong("Terms analyzed: "),
        fmt_term(tr[1]), " – ", fmt_term(tr[2]),
        tags$span(class = "ms-3", tags$strong("Graduates excluded: "),
          if (!is.null(degrees)) "yes (degree term)" else
            tags$span(class = "text-critical", "no — cedar_degrees not provided")
        ),
        tags$span(
          class = "ms-3",
          tags$strong("Courses shown: "),
          n_courses,
          sprintf("(≥%d enrolled, ≥%d DFW)",
                  as.integer(input$so_min_n),
                  as.integer(input$so_min_dfw_n))
        )
      )
    })

    output$so_table <- reactable::renderReactable({
      req(so_data())
      result <- so_data()$by_course
      if (is.null(result) || nrow(result) == 0) {
        return(message_table("No qualifying courses found."))
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
      rate_defs <- lapply(rate_cols, function(col) {
        reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 3)
        )
      })
      names(rate_defs) <- rate_cols
      rate_defs$subject_course <- reactable::colDef(name = "Course", minWidth = 105,
        cell = function(value) htmltools::span(class = "fw-semibold", value))
      rate_defs$impact_score <- reactable::colDef(name = "Impact", align = "right",
        format = reactable::colFormat(digits = 1))
      rate_defs$pop_dfw_stopout_rate <- reactable::colDef(
        align = "right",
        format = reactable::colFormat(digits = 3),
        style = function(value) {
          bg <- color_from_cuts(value, c(0.10, 0.25), c("#d4edda", "#fff3cd", "#f8d7da"))
          if (!is.null(bg)) list(backgroundColor = bg)
        }
      )
      rate_defs$pop_stopout_gap <- reactable::colDef(
        align = "right",
        format = reactable::colFormat(digits = 3),
        style = function(value) {
          bg <- color_from_cuts(value, c(-0.05, 0.05), c("#d4edda", "#fff9e6", "#f8d7da"))
          if (!is.null(bg)) list(backgroundColor = bg)
        }
      )

      make_pathways_table(result, columns = rate_defs)
    })

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

    output$dfw_table <- reactable::renderReactable({
      req(dfw_data())
      result <- dfw_data()
      if (is.null(result) || nrow(result) == 0)
        return(message_table("No qualifying courses found."))

      result <- result %>%
        mutate(est_affected = pop_n_dfw) %>%
        arrange(desc(est_affected))

      rate_cols <- grep("rate", names(result), value = TRUE)
      rate_defs <- lapply(rate_cols, function(col) {
        reactable::colDef(
          align = "right",
          format = reactable::colFormat(digits = 3)
        )
      })
      names(rate_defs) <- rate_cols
      rate_defs$subject_course <- reactable::colDef(name = "Course", minWidth = 105,
        cell = function(value) htmltools::span(class = "fw-semibold", value))
      rate_defs$pop_dfw_rate <- reactable::colDef(
        align = "right",
        format = reactable::colFormat(digits = 3),
        style = function(value) {
          bg <- color_from_cuts(value, c(0.15, 0.30), c("#d4edda", "#fff3cd", "#f8d7da"))
          if (!is.null(bg)) list(backgroundColor = bg)
        }
      )

      make_pathways_table(result, columns = rate_defs)
    })


    # ---- Course Timing ----

    output$ct_explanation <- renderUI({
      axis <- input$ct_x_axis %||% "overall_credit_band"
      axis_note <- switch(axis,
        overall_credit_band = tagList(
          tags$strong("X-axis: total-credit bands. "),
          "Students are grouped by overall credits earned at the time they took the course, including transfer credit."
        ),
        inst_credit_band = tagList(
          tags$strong("X-axis: UNM-credit bands. "),
          "Students are grouped by institutional credits attempted at the time they took the course."
        ),
        relative_term = tagList(
          tags$strong("X-axis: relative enrolled term. "),
          "Term 1 is each student's first observed registered term in CEDAR; gaps are not counted as empty terms."
        ),
        classification = tagList(
          tags$strong("X-axis: student classification. "),
          "Students are grouped by Freshman/Sophomore/Junior/Senior classification at the time they took the course."
        ),
        tagList(
          tags$strong("X-axis: selected stage. "),
          "Students are grouped by the selected stage at the time they took the course."
        )
      )
      denominator_note <- switch(axis,
        relative_term =
          "Each cell is the share of students who reached that observed term and took the course there.",
        overall_credit_band =
          "Each cell is the share of students observed in that total-credit band who took the course there.",
        inst_credit_band =
          "Each cell is the share of students observed in that UNM-credit band who took the course there.",
        classification =
          "Each cell is the share of students observed at that classification who took the course there.",
        "Each cell is the share of students observed at that stage who took the course there."
      )
      p(
        axis_note,
        " Y-axis = course, sorted by median x-axis position. ",
        denominator_note,
        class = "text-hint"
      )
    })

    ct_data <- reactive({
      req(get_population())
      opt <- list(
        x_axis            = input$ct_x_axis %||% "overall_credit_band",
        max_relative_term = as.integer(input$ct_max_term),
        min_n             = as.integer(input$ct_min_n)
      )
      opt$level <- pathways_level_filter(input$ct_level)
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
          title = "Filtered to Freshman-start students",
          p("The ", tags$strong("Relative term"), " axis assigns term 1 based on each student's
             first appearance in CEDAR — not their actual first semester at UNM. Students who were
             already enrolled when the data begins (Fall 2018) look like first-semester students
             even if they were seniors. This is called ", tags$em("left truncation"), "."),
          p("To prevent misleading results, this analysis has been automatically restricted to
             students classified as ", tags$strong("Freshman"), " at their first enrollment record.
             This is the best available proxy for a genuine first semester in this data window."),
          p("You can change this in the ", tags$strong("Starting classification"), " dropdown.
             Switching to a credit-band or classification x-axis removes the restriction entirely —
             those axes use actual values from Banner and are unaffected by when the data starts.",
            class = "cedar-body"),
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
      pop_rv <- tryCatch(population_rv()$population, error = function(e) NULL)
      students_pre <- apply_pathways_population_window(students_pre, pop_rv, analysis_through)
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
      if (is.null(get_population()))
        return(tags$span(class = "scope-bar-placeholder", "Apply a population, then Run to see scope."))
      d    <- ct_data()
      meta <- attr(d, "timing_meta")
      if (is.null(meta)) return(NULL)

      filtered <- !is.null(meta$start_classification) &&
                  meta$n_analyzed < meta$n_population

      tags$p(
        if (filtered) {
          sprintf(
            "%s of %s population students analyzed (“%s” start classification filter). %s course%s shown (taken by ≥%d students).",
            format(meta$n_analyzed,    big.mark = ","),
            format(meta$n_population,  big.mark = ","),
            meta$start_classification,
            format(meta$n_courses,     big.mark = ","),
            if (meta$n_courses == 1) "" else "s",
            meta$min_n
          )
        } else {
          sprintf(
            "%s students analyzed. %s course%s shown (taken by ≥%d students).",
            format(meta$n_analyzed,   big.mark = ","),
            format(meta$n_courses,    big.mark = ","),
            if (meta$n_courses == 1) "" else "s",
            meta$min_n
          )
        },
        class = "text-muted-sm"
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
               " courses by population enrollment. Raise “Min students” to reduce.")
      else
        NULL

      # Use n_analyzed (post-filter) rather than nrow(get_population()) so the
      # title reflects who actually contributed data to the heatmap.
      n_title <- if (!is.null(meta)) meta$n_analyzed else nrow(get_population())

      plot_curriculum_map(plot_data, opt = list(
        title = paste0("Course Timing — ",
                       format(n_title, big.mark = ","),
                       " students — ", get_description()),
        note  = note
      ))
    })

    output$ct_table <- reactable::renderReactable({
      req(ct_data())
      disp <- course_timing_display(ct_data(), input$ct_x_axis %||% "overall_credit_band")
      make_pathways_table(
        disp,
        columns = list(
          subject_course = reactable::colDef(name = "Course", minWidth = 105,
            cell = function(value) htmltools::span(class = "fw-semibold", value)),
          course_title = reactable::colDef(name = "Title", minWidth = 220),
          subject_code = reactable::colDef(name = "Subject", maxWidth = 90),
          timing_bucket = reactable::colDef(name = "Timing", minWidth = 110),
          n_students = reactable::colDef(name = "Students", align = "right",
            maxWidth = 95, format = reactable::colFormat(digits = 0)),
          n_eligible = reactable::colDef(name = "Eligible", align = "right",
            maxWidth = 95, format = reactable::colFormat(digits = 0)),
          pct_pop = reactable::colDef(name = "Population %", align = "right",
            maxWidth = 115, format = reactable::colFormat(percent = TRUE, digits = 1)),
          total_students = reactable::colDef(name = "Course Total", align = "right",
            maxWidth = 115, format = reactable::colFormat(digits = 0))
        )
      )
    })


    # ---- Course Pairs ----

    cp_data <- reactive({
      req(get_population())
      opt <- list(
        min_n        = as.integer(input$cp_min_n),
        min_pair_n   = as.integer(input$cp_min_pair),
        max_term_gap = as.integer(input$cp_max_gap)
      )
      opt$level <- pathways_level_filter(input$cp_level)
      if (length(input$cp_subject) > 0) opt$subject_code <- input$cp_subject

      status_message <- create_timing_status_message("pathways-pairs", "Computing course pairs")
      showNotification(status_message, type = "warning", duration = NULL, id = "cp_loading")
      timer <- start_report_timer("pathways-pairs")

      cp_pop_ids   <- unique(get_analysis_population()$student_id)
      cp_students  <- filter(students, student_id %in% cp_pop_ids)
      pop_rv <- tryCatch(population_rv()$population, error = function(e) NULL)
      cp_students <- apply_pathways_population_window(cp_students, pop_rv, analysis_through)

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

    # Sorted display data — stored as a reactive so the table's initial order is stable.
    cp_display <- reactive({
      req(cp_data(), nrow(cp_data()) > 0)
      cp_data() %>%
        select(course_a, course_b, pct_a_to_b, n_students, n_took_a, median_term_gap) %>%
        arrange(desc(pct_a_to_b))
    })

    output$cp_table <- reactable::renderReactable({
      req(cp_data())
      if (is.null(cp_data()) || nrow(cp_data()) == 0) {
        return(message_table("No qualifying pairs found."))
      }
      disp <- cp_display()
      format_gap <- function(value) {
        if (is.na(value)) return("")
        if (abs(value - round(value)) < 1e-9) {
          format(round(value), big.mark = ",")
        } else {
          format(round(value, 1), nsmall = 1, trim = TRUE)
        }
      }
      make_pathways_table(
        disp,
        columns = list(
          course_a = reactable::colDef(name = "Course A", minWidth = 105,
            cell = function(value) htmltools::span(class = "fw-semibold", value)),
          course_b = reactable::colDef(name = "Course B", minWidth = 105),
          pct_a_to_b = reactable::colDef(
            name = "% A to B",
            align = "right",
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          n_students = reactable::colDef(
            name = "Students A to B",
            align = "right",
            format = reactable::colFormat(digits = 0)
          ),
          n_took_a = reactable::colDef(
            name = "Students Taking A",
            align = "right",
            format = reactable::colFormat(digits = 0)
          ),
          median_term_gap = reactable::colDef(
            name = "Median Term Gap",
            align = "right",
            cell = format_gap
          )
        )
      )
    })

    output$cp_meta <- renderUI({
      if (is.null(get_population()))
        return(tags$span(class = "scope-bar-placeholder", "Apply a population, then Run to see scope."))
      d    <- cp_data()
      meta <- attr(d, "pair_meta")
      if (is.null(meta)) return(NULL)
      tags$p(
        sprintf(
          "%d qualifying course%s (taken by ≥%d students). Searched %s A-side × %s B-side enrollment records. %d pair%s found (taken by ≥%d students each).",
          meta$n_qualifying, if (meta$n_qualifying == 1) "" else "s",
          meta$min_n,
          format(meta$n_a_rows, big.mark = ","),
          format(meta$n_b_rows, big.mark = ","),
          meta$n_pairs, if (meta$n_pairs == 1) "" else "s",
          meta$min_pair_n
        ),
        class = "text-muted-sm"
      )
    })

    # ---- Major Changes ----

    mc_data <- reactive({
      req(get_population())
      pop_ids      <- get_analysis_population()$student_id
      pop_programs <- programs %>% filter(student_id %in% pop_ids)

      # Small-cell suppression floor — set once in config/shiny_config.R so every
      # descriptive breakdown shares the same minimum group size.
      opt <- list(min_n = cedar_min_group_size)

      status_message <- create_timing_status_message("pathways-major-changes", "Detecting major changes")
      showNotification(status_message, type = "warning", duration = NULL, id = "mc_loading")
      timer <- start_report_timer("pathways-major-changes")

      # Focal programs = the programs this population is defined around.
      # Derived from the cohort opt (returned by populationSelectorServer) so only
      # the user-selected dept/programs are focal — not all programs ever declared by
      # population members, which would include double-majors in other departments.
      population_opt  <- population_rv()$opt %||% list()
      focal_programs <- resolve_pathways_focal_programs(
        population_opt, programs, pop_programs = pop_programs
      )

      # Focal subject codes — used to split prior-course history into in-unit vs outside.
      # Dept codes are not necessarily course prefixes, so resolve through subject_lookup.
      focal_subjects <- resolve_pathways_focal_subjects(
        population_opt, programs, lookups, pop_programs = pop_programs
      )

      result <- tryCatch({
        changes <- detect_major_changes(pop_programs)

        # focal_changes: only transitions that directly involve the population's programs.
        # A History cohort shows History→PolSci and PolSci→History, but NOT PolSci→Law
        # (even though a History student made that change). Used for all summary views.
        # Full `changes` is preserved for the student-level detail table.
        focal_changes <- changes %>%
          filter(from_major %in% focal_programs | to_major %in% focal_programs)

        pathways <- major_change_pathways(focal_changes, opt = opt)

        decl_context <- get_declaration_context(
          pop_programs, students, get_analysis_population(),
          focal_subjects = focal_subjects,
          opt = opt
        )

        # Timing summary over the focal-touching changes. Credits are lag-adjusted
        # (decision-point) attempted hours from detect_major_changes(); see the
        # Banner-lag note rendered in mc_summary_cards. late_threshold flags moves
        # made deep into a student's studies, where excess-credit cost is highest.
        late_threshold <- 60L
        first_terms <- pop_programs %>%
          filter(program_type == "Major") %>%
          group_by(student_id) %>%
          summarize(first_term = min(term), .groups = "drop")
        first_focal <- focal_changes %>%
          group_by(student_id) %>%
          summarize(first_change_term = min(change_term), .groups = "drop") %>%
          left_join(first_terms, by = "student_id") %>%
          mutate(terms_until = term_diff(first_term, first_change_term))
        timing <- list(
          median_terms   = stats::median(first_focal$terms_until, na.rm = TRUE),
          median_unm     = stats::median(focal_changes$unm_credits_before_change,   na.rm = TRUE),
          median_total   = stats::median(focal_changes$total_credits_before_change, na.rm = TRUE),
          late_threshold = late_threshold,
          n_late         = sum(focal_changes$unm_credits_before_change > late_threshold, na.rm = TRUE),
          n_events       = nrow(focal_changes)
        )

        list(changes = changes, focal_changes = focal_changes,
             pathways = pathways, focal_programs = focal_programs,
             decl_context = decl_context, timing = timing)
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
    })
    # Plain reactive (no Run button): outputs are suspended while the tab is hidden,
    # so this computes the first time the tab is viewed, caches afterward, and
    # re-runs automatically when the population is rebuilt.

    output$mc_changes_table <- reactable::renderReactable({
      req(!is.null(mc_data()))
      result <- mc_data()$changes
      if (is.null(result) || nrow(result) == 0)
        return(message_table("No major changes found for this population."))
      make_pathways_table(result, columns = numeric_col_defs(result, digits = 0, extra = list(
        unm_credits_before_change   = reactable::colDef(name = "UNM credits at change (lag-adj.)", align = "right"),
        total_credits_before_change = reactable::colDef(name = "Total credits at change (lag-adj.)", align = "right"),
        unm_credits_at_change       = reactable::colDef(name = "UNM credits (as recorded)", align = "right"),
        total_credits_at_change     = reactable::colDef(name = "Total credits (as recorded)", align = "right")
      )))
    })

    output$mc_pathways_table <- reactable::renderReactable({
      req(!is.null(mc_data()))
      result <- mc_data()$pathways
      if (is.null(result) || nrow(result) == 0)
        return(message_table("No pathways met the minimum threshold."))
      make_pathways_table(result, columns = numeric_col_defs(result, digits = 1, extra = list(
        from_major        = reactable::colDef(name = "From major"),
        to_major          = reactable::colDef(name = "To major"),
        n_changes         = reactable::colDef(name = "Changes", align = "right",
                                              format = reactable::colFormat(digits = 0)),
        avg_unm_credits   = reactable::colDef(name = "Avg UNM credits at change", align = "right"),
        avg_total_credits = reactable::colDef(name = "Avg total credits at change", align = "right")
      )))
    })

    output$mc_summary_cards <- renderUI({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      focal   <- mc_data()$focal_programs %||% character(0)
      if (is.null(changes) || nrow(changes) == 0) return(NULL)

      n_changers <- n_distinct(changes$student_id)

      change_row <- if (length(focal) == 1) {
        arriving_data <- changes %>%
          filter(to_major == focal) %>%
          count(major = from_major, sort = TRUE)
        leaving_data <- changes %>%
          filter(from_major == focal) %>%
          count(major = to_major, sort = TRUE)

        make_top3 <- function(df) {
          top3  <- slice_head(df, n = 3)
          total <- sum(df$n)
          if (nrow(top3) == 0) return(tags$em("—", class = "text-muted"))
          tagList(lapply(seq_len(nrow(top3)), function(i) {
            pct <- if (total > 0) round(100 * top3$n[i] / total) else 0
            div(class = "mb-1",
              tags$span(class = "fw-semibold", top3$major[i]),
              tags$span(class = "text-note ms-1",
                        paste0(top3$n[i], " (", pct, "%)"))
            )
          }))
        }

        fluidRow(
          column(4, div(class = "stat-card",
            p(n_changers, class = "stat-num"),
            p("students changed majors", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card stat-card--left",
            tags$strong("Top arriving from", class = "stat-lbl d-block mb-1"),
            make_top3(arriving_data)
          )),
          column(4, div(class = "stat-card stat-card--left",
            tags$strong("Top leaving for", class = "stat-lbl d-block mb-1"),
            make_top3(leaving_data)
          ))
        )

      } else {
        top_from <- changes %>% count(from_major, sort = TRUE) %>% slice(1)
        top_to   <- changes %>% count(to_major,   sort = TRUE) %>% slice(1)

        fluidRow(
          column(4, div(class = "stat-card",
            p(n_changers, class = "stat-num"),
            p("students changed majors", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card",
            p(if (nrow(top_from) > 0) top_from$from_major else "—", class = "stat-num"),
            p("most common departure", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card",
            p(if (nrow(top_to) > 0) top_to$to_major else "—", class = "stat-num"),
            p("most common destination", class = "stat-lbl")
          ))
        )
      }

      # Declaration stats feed the pipeline table. This count can be smaller than
      # the population count because it requires an observed first focal-major
      # declaration term with usable credit context.
      ctx <- mc_data()$decl_context
      declaration_context_note <- if (!is.null(ctx) && !is.null(ctx$credits)) {
        cr <- ctx$credits
        p(class = "text-hint",
          "Credit-at-declaration rows use ",
          tags$strong(format(cr$n, big.mark = ",")),
          " students with an observed first focal-major declaration and usable credit context. ",
          "This can be smaller than the population count above because the population can include ",
          "students who are still pre-majors, never declared the focal major, or entered before the available record window.")
      }

      # Pipeline breakdown table showing UNM + total credits by entry type
      pipeline_row <- if (!is.null(ctx) && !is.null(ctx$pipeline_summary) &&
                          nrow(ctx$pipeline_summary) > 0) {
        ps <- ctx$pipeline_summary
        has_terms   <- !all(is.na(ps$mean_terms))
        has_overall <- "mean_overall" %in% names(ps)
        rows <- lapply(seq_len(nrow(ps)), function(i) {
          r <- ps[i, ]
          overall_cell <- if (has_overall && !is.na(r$mean_overall))
            tags$td(paste0(r$mean_overall, " avg / ", r$median_overall, " med"))
          else
            tags$td("—")
          terms_cell <- if (has_terms && !is.na(r$mean_terms))
            tags$td(paste0(r$mean_terms, " terms"))
          else
            tags$td("—")
          tags$tr(
            tags$td(r$pipeline),
            tags$td(format(r$n, big.mark = ",")),
            tags$td(paste0(r$mean_inst, " avg / ", r$median_inst, " med")),
            overall_cell,
            terms_cell
          )
        })
        header <- tags$tr(
          tags$th("Pipeline"),
          tags$th("Students"),
          tags$th("UNM credits at declaration"),
          if (has_overall) tags$th("Total credits at declaration") else NULL,
          if (has_terms) tags$th("Terms before declaring") else NULL
        )
        div(class = "mt-3",
          pathways_section_heading("Credits at Declaration by Entry Pipeline"),
          declaration_context_note,
          p(class = "text-hint",
            "Students are grouped by how they first arrived at UNM, alongside how many credits ",
            "they had already attempted by the time they declared this major. ",
            tags$strong("UNM"), " counts institutional hours only; ", tags$strong("total"),
            " adds transfer hours. Both are attempted (not earned)."),
          tags$table(class = "table table-sm table-borderless mc-pipeline-table",
            tags$thead(header),
            tags$tbody(rows)
          ),
          info_panel(
            "What the entry pipelines mean",
            tags$ul(
              tags$li(tags$strong("Transfer:"),
                " first UNM enrollment was as a transfer student. Includes transfers who declared ",
                "this major right away and those who switched into it after arriving."),
              tags$li(tags$strong("Switched in (UNM):"),
                " a continuing UNM student who held a different declared program before first ",
                "appearing in this major."),
              tags$li(tags$strong("Direct entry (UNM):"),
                " no prior declared program at UNM — this major was their first, including students ",
                "who came in through its pre-major pathway."),
              tags$li(tags$strong("Unclear:"),
                " their first record in this program is the earliest term in the data, so we ",
                "cannot see what came before.")
            ),
            description = "How each student is sorted into a pipeline."
          )
        )
      }

      tm <- mc_data()$timing

      # ── Timing of the move ───────────────────────────────────────────────────
      timing_row <- if (!is.null(tm)) {
        late_pct <- if (tm$n_events > 0) round(100 * tm$n_late / tm$n_events) else 0
        fluidRow(class = "mt-2",
          column(4, div(class = "stat-card",
            p(if (is.na(tm$median_terms)) "—" else tm$median_terms, class = "stat-num"),
            p("median terms to first change", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card",
            p(HTML(paste0(
              if (is.na(tm$median_unm)) "—" else round(tm$median_unm),
              " <span class='text-note'>UNM</span> / ",
              if (is.na(tm$median_total)) "—" else round(tm$median_total),
              " <span class='text-note'>total</span>")), class = "stat-num"),
            p("median credits at change", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card",
            p(paste0(late_pct, "%"), class = "stat-num"),
            p(paste0("changed after ", tm$late_threshold, "+ UNM credits"), class = "stat-lbl")
          ))
        )
      }

      # ── Credit-basis / Banner-lag caveat ─────────────────────────────────────
      lag_note <- div(class = "alert-box alert-box--watch mt-2",
        tags$strong("⚠ About the credit figures"),
        tags$ul(class = "mt-1",
          tags$li(HTML("Credits are <strong>attempted</strong> hours (not earned), so they
                        aren't deflated by the W/F grades that come from dropping the old
                        major's courses. <strong>UNM</strong> counts institutional hours only;
                        <strong>total</strong> adds transfer hours.")),
          tags$li(HTML("Major changes typically post to Banner the term <em>after</em> the
                        student actually switches. The figures above are
                        <strong>lag-adjusted</strong> — they use the cumulative credits as of
                        the term <em>before</em> the change posted, which removes that extra
                        (~one-term, often ~15-credit) semester. The raw, as-recorded credits
                        run roughly a semester higher."))
        )
      )

      tagList(change_row, timing_row, lag_note, pipeline_row)
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
          xaxis  = list(title = "", tickangle = -45, tickfont = list(size = 12)),
          yaxis  = list(title = "# students", tickfont = list(size = 12)),
          legend = list(orientation = "h", x = 0, y = 1.2, font = list(size = 13)),
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
        insidetextfont = list(size = 12, color = "#ffffff"),
        hovertemplate = "%{label}: %{value} (%{percent})<extra></extra>",
        marker = list(colors = unname(color_map[top_to$major])),
        showlegend = TRUE
      ) %>%
        layout(
          legend = list(orientation = "v", x = 1.02, y = 0.5, font = list(size = 12)),
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
        insidetextfont = list(size = 12, color = "#ffffff"),
        hovertemplate = "%{label}: %{value} (%{percent})<extra></extra>",
        marker = list(colors = unname(color_map[top_from$major])),
        showlegend = TRUE
      ) %>%
        layout(
          legend = list(orientation = "v", x = 1.02, y = 0.5, font = list(size = 12)),
          margin = list(t = 5, b = 5, l = 5, r = 5)
        )
    })

    output$mc_flow_table <- reactable::renderReactable({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      if (is.null(changes) || nrow(changes) == 0)
        return(message_table("No major changes found."))

      focal <- mc_data()$focal_programs %||% character(0)

      inflows  <- changes %>% count(major = to_major,   name = "n_in")
      outflows <- changes %>% count(major = from_major, name = "n_out")
      flow <- full_join(inflows, outflows, by = "major") %>%
        replace_na(list(n_in = 0L, n_out = 0L)) %>%
        mutate(net = n_in - n_out) %>%
        filter(length(focal) == 0 | major %in% focal) %>%
        arrange(desc(n_in + n_out))

      make_pathways_table(
        flow,
        page_size = 25,
        columns = list(
          major = reactable::colDef(name = "Major", minWidth = 180),
          n_in = reactable::colDef(name = "Students arriving to", align = "right", maxWidth = 160),
          n_out = reactable::colDef(name = "Students leaving for elsewhere", align = "right", minWidth = 190),
          net = reactable::colDef(
            name = "Net",
            align = "right",
            maxWidth = 80,
            style = function(value) {
              color <- if (is.na(value) || value == 0) "#888" else if (value < 0) "#c62828" else "#2e7d32"
              list(color = color, fontWeight = "600")
            }
          )
        )
      )
    })


    output$mc_decl_courses_other_meta <- renderUI({
      req(!is.null(mc_data()))
      ctx <- mc_data()$decl_context
      if (is.null(ctx)) return(NULL)
      p(paste0("Based on ", format(ctx$n_declarers, big.mark = ","), " students who declared."),
        class = "text-hint")
    })

    output$mc_decl_courses_other <- reactable::renderReactable({
      req(!is.null(mc_data()))
      d <- mc_data()$decl_context$courses_other
      if (is.null(d) || nrow(d) == 0)
        return(message_table("No out-of-unit courses met the threshold."))
      make_pathways_table(
        d,
        page_size = 25,
        columns = list(
          subject_course = reactable::colDef(name = "Course", minWidth = 105,
            cell = function(value) htmltools::span(class = "fw-semibold", value)),
          course_title = reactable::colDef(name = "Title", minWidth = 220),
          n_became_major = reactable::colDef(name = "Students", align = "right", maxWidth = 95),
          pct = reactable::colDef(name = "% of Declarers", align = "right",
            format = reactable::colFormat(percent = TRUE, digits = 1))
        )
      )
    })


    # ---- Course to Major (entry heatmap) ----

    ge_conv_data <- reactive({
      req(get_population())
      pop <- get_population()

      if (!"first_unit_term" %in% names(pop)) {
        showNotification("Course to Major requires a program-based population.",
                         type = "warning", duration = 5)
        return(NULL)
      }

      population_opt  <- population_rv()$opt %||% list()
      population_type <- population_opt$type %||% "preset"
      focal_dept_codes <- resolve_pathways_focal_dept_codes(population_opt, programs)
      focal_subjects <- resolve_pathways_focal_subjects(population_opt, programs, lookups)

      message("[course-to-major] population_type: ", population_type,
              " | focal_subjects: ", paste(focal_subjects, collapse = ", "),
              " | dept_codes: ", paste(focal_dept_codes, collapse = ", "))

      if (length(focal_subjects) == 0) {
        showNotification(
          "Could not determine focal subject codes. Use a dept or major population.",
          type = "warning", duration = 6)
        return(NULL)
      }

      # ── Term range for course + instructor associations ───────────────────
      from_term <- as.integer(input$ge_from_term)
      to_term   <- as.integer(input$ge_to_term)
      all_terms <- sort(unique(students$term))
      sel_terms <- all_terms[all_terms >= from_term & all_terms <= to_term]

      # ── Course + instructor associations ─────────────────────────────────
      ge_instructor_data(NULL)
      if (length(focal_dept_codes) > 0) {
        ic_opt <- list(
          subject_code   = focal_subjects,
          dept_codes     = focal_dept_codes,
          gen_ed_only    = isTRUE(input$ge_gen_ed_only),
          gen_ed_courses = unlist(gen_ed_all),
          terms          = if (length(sel_terms) > 0) sel_terms else NULL,
          min_n          = as.integer(input$ge_min_n),
          campus         = if (length(input$ge_campus) > 0) input$ge_campus else NULL,
          level          = pathways_level_filter(input$ge_level),
          group_cols     = c("subject_course", "instructor_name")
        )
        instructor_result <- tryCatch(
          get_course_major_associations(students, programs, ic_opt),
          error = function(e) {
            showNotification(paste("Course + instructor associations failed:", e$message),
                             type = "error")
            stop(e)
          }
        )
        ge_instructor_data(instructor_result)
      }

      # ── Entry heatmaps ────────────────────────────────────────────────────
      opt <- list(
        max_lag = as.integer(input$ge_conv_max_lag %||% 3L),
        min_n   = as.integer(input$ge_min_n %||% 5L)
      )

      showNotification("Computing course-to-major analysis...", type = "warning",
                       duration = NULL, id = "ge_conv_loading")
      timer <- start_report_timer("entry-heatmap")

      result <- tryCatch(
        get_entry_heatmap(students, programs, pop, focal_subjects, opt = opt),
        error = function(e) {
          showNotification(paste("Course to Major failed:", e$message), type = "error")
          NULL
        }
      )

      removeNotification("ge_conv_loading")
      if (!is.null(result))
        showNotification(
          paste0("Course to Major complete (", round(end_report_timer(timer), 1), "s)"),
          type = "message", duration = 3)
      result
    }) |> bindEvent(input$ge_conv_run, ge_auto(), ignoreInit = TRUE)

    output$ge_heatmap_meta <- renderUI({
      d <- ge_conv_data()
      if (is.null(d)) return(NULL)
      n_in  <- if (!is.null(d$in_unit))  nrow(d$in_unit)  else 0L
      n_out <- if (!is.null(d$out_unit)) nrow(d$out_unit) else 0L
      p(sprintf(
        "Cohort: %s students. Showing %d in-unit and %d out-of-unit course×lag cells.",
        format(d$n_majors, big.mark = ","), n_in, n_out
      ), class = "text-hint")
    })

    .make_entry_heatmap <- function(d, title, n_majors) {
      empty_plot <- function(msg)
        plot_ly(type = "scatter", mode = "text") %>%
          layout(
            title       = list(text = title, font = list(size = 13)),
            annotations = list(list(
              text = msg, xref = "paper", yref = "paper",
              x = 0.5, y = 0.5, showarrow = FALSE,
              font = list(size = 13, color = "#888")
            )),
            xaxis = list(visible = FALSE),
            yaxis = list(visible = FALSE)
          )

      if (is.null(d) || nrow(d) == 0L)
        return(empty_plot("No courses met the minimum threshold."))

      lag_labels <- paste0("T-", sort(unique(d$lag)))

      wide_pct <- d %>%
        select(subject_course, lag_label, pct_of_majors) %>%
        tidyr::pivot_wider(names_from  = lag_label,
                           values_from = pct_of_majors,
                           values_fill = 0)

      present_lags <- intersect(lag_labels, names(wide_pct))
      if (length(present_lags) == 0L) return(empty_plot("No lag data available."))

      pct_mat  <- wide_pct[, present_lags, drop = FALSE]
      row_max  <- apply(pct_mat, 1, max, na.rm = TRUE)
      ord      <- order(-row_max)
      wide_pct <- wide_pct[ord, ][seq_len(min(nrow(wide_pct), 50L)), ]

      wide_text <- d %>%
        mutate(txt = sprintf(
          "<b>%s</b><br>%d of %d cohort students (%s%% of cohort) took this %s before entry",
          subject_course, n_became_major, n_majors,
          formatC(100 * pct_of_majors, format = "f", digits = 1),
          lag_label
        )) %>%
        select(subject_course, lag_label, txt) %>%
        tidyr::pivot_wider(names_from  = lag_label,
                           values_from = txt,
                           values_fill = "")

      wide_text <- wide_text[match(wide_pct$subject_course, wide_text$subject_course), ]

      z        <- as.matrix(wide_pct[, present_lags, drop = FALSE])
      text_mat <- as.matrix(wide_text[, present_lags, drop = FALSE])

      plot_ly(
        x    = present_lags,
        y    = wide_pct$subject_course,
        z    = z,
        text = text_mat,
        type        = "heatmap",
        colorscale  = "Blues",
        reversescale = TRUE,
        hovertemplate = "%{text}<extra></extra>",
        showscale   = TRUE
      ) %>%
        layout(
          title  = list(text = title, font = list(size = 13)),
          xaxis  = list(title = "Semesters before entry", side = "top"),
          yaxis  = list(title = "", autorange = "reversed"),
          margin = list(l = 130, r = 20, t = 60, b = 20)
        )
    }

    output$ge_heatmap_in <- renderPlotly({
      req(!is.null(ge_conv_data()))
      d <- ge_conv_data()
      .make_entry_heatmap(d$in_unit, "Courses from this unit (before major entry)", d$n_majors)
    })

    output$ge_heatmap_out <- renderPlotly({
      req(!is.null(ge_conv_data()))
      d <- ge_conv_data()
      .make_entry_heatmap(d$out_unit, "Courses from other departments (before major entry)", d$n_majors)
    })



    # ---- Course + Instructor Associations (Course to Major tab) ----
    ge_instructor_data <- reactiveVal(NULL)

    observe({
      ge_campus_choices <- sort(unique(students$campus[
        !is.na(students$campus) & nzchar(students$campus)
      ]))
      updateSelectizeInput(session, "ge_campus",
                           choices  = ge_campus_choices,
                           selected = intersect(c("ABQ", "EA"), ge_campus_choices),
                           server   = TRUE)

      all_terms  <- sort(unique(students$term))
      from_terms <- all_terms[all_terms < cedar_current_term]
      from_labels <- setNames(
        from_terms,
        vapply(from_terms, .term_label, FUN.VALUE = character(1))
      )
      # To term: include up to cedar_current_term so recent later declarations are
      # captured, but never beyond it (no future scheduling terms).
      to_terms <- all_terms[all_terms <= cedar_current_term]
      to_labels <- setNames(
        to_terms,
        vapply(to_terms, .term_label, FUN.VALUE = character(1))
      )
      updateSelectizeInput(session, "ge_from_term",
                           choices  = from_labels,
                           selected = if (length(from_terms)) min(from_terms) else NULL,
                           server   = TRUE)
      updateSelectizeInput(session, "ge_to_term",
                           choices  = to_labels,
                           selected = if (length(to_terms)) max(to_terms) else NULL,
                           server   = TRUE)
    })

    output$ge_instructor_meta <- renderUI({
      d <- ge_instructor_data()
      if (is.null(d) || nrow(d) == 0) {
        if (isTruthy(input$ge_conv_run) && input$ge_conv_run > 0)
          return(p("No course + instructor groups met the minimum threshold.",
                   class = "text-hint"))
        return(tags$span(class = "scope-bar-placeholder", "Apply a population, then Run to see scope."))
      }
      meta <- attr(d, "association_meta") %||% list()
      distinct_eligible <- meta$distinct_eligible %||% NA_integer_
      distinct_later    <- meta$distinct_later_declared %||% NA_integer_
      group_eligible    <- meta$group_eligible_sum %||% sum(d$n_eligible, na.rm = TRUE)
      group_later       <- meta$group_later_sum %||% sum(d$n_later_declared, na.rm = TRUE)
      decl_pct <- if (!is.na(distinct_eligible) && distinct_eligible > 0) {
        100 * distinct_later / distinct_eligible
      } else {
        NA_real_
      }
      p(sprintf(
        "%d course + instructor groups met the threshold. Distinct eligible pool: %s students; %s later declared (%s%%). Visible group memberships sum to %s eligible / %s later declared because students can appear in more than one course + instructor group.",
        nrow(d),
        format(distinct_eligible, big.mark = ","),
        format(distinct_later, big.mark = ","),
        if (is.na(decl_pct)) "NA" else formatC(decl_pct, format = "f", digits = 1),
        format(group_eligible, big.mark = ","),
        format(group_later, big.mark = ",")
      ), class = "text-hint")
    })

    output$ge_instructor_table <- reactable::renderReactable({
      d <- ge_instructor_data()
      req(!is.null(d), nrow(d) > 0)
      make_pathways_table(
        d,
        columns = list(
          subject_course = reactable::colDef(
            name = "Course", minWidth = 105,
            cell = function(value) htmltools::span(class = "fw-semibold", value)
          ),
          course_title = reactable::colDef(name = "Title", minWidth = 220),
          instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
          n_eligible = reactable::colDef(name = "Eligible", align = "right",
            maxWidth = 100),
          n_later_declared = reactable::colDef(name = "Later Declared", align = "right",
            maxWidth = 130),
          declaration_pct = reactable::colDef(
            name = "Declaration %", align = "right", maxWidth = 130,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          pct_of_eligible = reactable::colDef(
            name = "% of Pool", align = "right", maxWidth = 100,
            format = reactable::colFormat(percent = TRUE, digits = 1)
          ),
          n_terms = reactable::colDef(name = "Terms", align = "right", maxWidth = 80)
        )
      )
    })

  }) # end moduleServer
}


# Null-coalescing operator — define only if not already loaded
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
