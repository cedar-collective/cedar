# Shiny Module: Pathways Tab
#
# Population-aware curriculum analytics. The user defines a student population
# (via the top filter stripe), then runs analysis subtabs:
#
#   Roadblocks    — descriptive DFW/pass stop-out comparisons for a population
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
#   R/cones/major-changes.R   — detect_major_changes()
#   R/cones/gen-ed-conversion.R — get_course_major_associations()
#
# Exported functions:
#   pathwaysUI(id, campus_choices, program_choices, dept_choices)
#   pathwaysServer(id, students, programs, degrees, cedar_student_term_credits, lookups, program_choices, dept_choices)
#
# Internal sub-module:
#   populationSelectorUI(id, campus_choices, program_choices, dept_choices)
#   populationSelectorServer(id, programs)  → returns reactive list(population, description)


# Standardized subtab intro: a slightly-larger, plain-language description of what
# the subtab does, led by the bold subtab name. Keep it to a sentence or two plus
# any necessary caveat. Pass the trailing text (and inline tags) as ...:
pathways_section_heading <- function(title, ..., level = "h3", class = NULL) {
  section_heading(
    title,
    ...,
    level = level,
    class = class
  )
}


# =============================================================================
# Population Selector sub-module
# =============================================================================

pathways_population_choice_lists <- function(programs) {
  empty <- list(program_choices = character(), dept_choices = character())
  if (is.null(programs) || nrow(programs) == 0) return(empty)

  major_rows <- programs %>%
    filter(
      program_type %in% c("Major", "Second Major"),
      !is.na(program_name), nzchar(program_name)
    )

  dept_codes <- major_rows %>%
    filter(!is.na(dept_code), nzchar(dept_code)) %>%
    distinct(dept_code) %>%
    pull(dept_code) %>%
    sort()

  dept_lookup <- if (exists("dept_code_to_name", envir = .GlobalEnv)) {
    get("dept_code_to_name", envir = .GlobalEnv)
  } else {
    setNames(character(), character())
  }
  dept_names <- dept_lookup[dept_codes]
  dept_names[is.na(dept_names) | !nzchar(dept_names)] <- dept_codes[is.na(dept_names) | !nzchar(dept_names)]

  prog_names <- major_rows %>%
    filter(!is_pre_major) %>%
    distinct(program_name) %>%
    arrange(program_name) %>%
    pull(program_name)

  list(
    program_choices = prog_names,
    dept_choices = setNames(dept_codes, dept_names)
  )
}

pathways_guide_link <- function(anchor, label = "Pathways guide \u2192") {
  cedar_docs_link(paste0("users/pathways#", anchor), label = label)
}
#
# UI: top filter stripe with program selectors and an "Apply" button.
# Server: calls build_population() on click, returns list(population = tibble, description = string).

populationSelectorUI <- function(id, campus_choices, program_choices = character(),
                                 dept_choices = character(), status_output = NULL) {
  ns <- NS(id)

  # Default to main campus, resolved against the choices actually supplied
  # rather than hardcoded. Pathways filters on cedar_programs$student_campus,
  # which spells main campus "Albuquerque/Main" — not the "ABQ" code used by
  # cedar_sections$campus. The literal "ABQ" that used to sit in `selected`
  # matched nothing, so the filter opened with no campus selected at all.
  # Falls back to no selection (= all campuses) if no label looks like main.
  default_campus <- campus_choices[
    grepl("^ABQ$|^Main$|Albuquer", campus_choices, ignore.case = TRUE)
  ]
  filter_bar(
    "Pathways",
    tags$span(
      "Define a student population, then explore course timing, roadblocks, sequences, and major changes. ",
      tags$a("Institution-level Gen Ed patterns are in Explore > Gen Ed.", href = "?tab=gen-ed")
    ),
    class = "pathways-population-filter",
    fluidRow(
      column(2,
        selectizeInput(
          ns("campus"), "Campus",
          choices  = campus_choices,
          multiple = TRUE,
          selected = default_campus,
          width    = "100%",
          options  = list(placeholder = "All campuses…")
        )
      ),
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
            choices  = names(PATHWAYS_MAJOR_GROUP_PRESETS),
            selected = "All Health Programs",
            width    = "100%"
          )
        ),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'dept'", ns("population_type")),
          selectizeInput(
            ns("dept_code"), "Department",
            choices = dept_choices,
            options = list(placeholder = "Type to search...", maxOptions = 300),
            width   = "100%"
          )
        ),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'major'", ns("population_type")),
          selectizeInput(
            ns("program_names"), "Majors",
            choices  = program_choices,
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
        filter_actions(
          actionButton(ns("build_btn"), "Define Population",
                       class = "btn-primary",
                       icon  = icon("users"))
        )
      )
    ),
    if (!is.null(status_output)) filter_scope_stripe(status_output)
  )
}

populationSelectorServer <- function(id, programs, degrees = NULL, students = NULL,
                                     program_choices = character(), dept_choices = character()) {
  moduleServer(id, function(input, output, session) {

    # The normal path receives precomputed choices from global.R so the selector
    # is searchable as soon as the page loads. Keep this fallback for tests or
    # standalone module use where the caller did not provide choices.
    if (length(program_choices) == 0 || length(dept_choices) == 0) {
      observe({
        choices <- pathways_population_choice_lists(programs)
        updateSelectizeInput(session, "dept_code",
                             choices = choices$dept_choices,
                             server  = FALSE)
        updateSelectizeInput(session, "program_names",
                             choices = choices$program_choices,
                             server  = FALSE)
      })
    }

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
        preset <- PATHWAYS_MAJOR_GROUP_PRESETS[[input$preset]]
        programs_selected <- preset$programs %||% DEFAULT_MAJOR_GROUP_PROGRAMS
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

pathwaysUI <- function(id, campus_choices, program_choices = character(),
                       dept_choices = character()) {
  ns <- NS(id)

  tagList(
    populationSelectorUI(
      ns("population"),
      campus_choices,
      program_choices = program_choices,
      dept_choices = dept_choices,
      status_output = uiOutput(ns("population_status"))
    ),

      # ---- Analysis sub-panels — main content area ----
      div(class = "pathways-analysis-content",
      navset_tab(
        id       = ns("analysis_tabs"),
        selected = "Population",

        # ---- Population Audit ----
        nav_panel("Population",
          subtab_header(
            "Population",
            "Audits the student group you defined \u2014 how many students it includes, how they ",
            "entered (first-time, transfer, pre-major), and how the focal / pre-major split ",
            "breaks down. Read the coverage panel first: it says how much of each student's ",
            "record this data can see, which bounds every timing view on the other subtabs. ",
            pathways_guide_link("build-a-population")
          ),
          cedar_definition_panel("pathways-population"),
          uiOutput(ns("pop_audit_ui"))
        ),

        # ---- Roadblocks ----
        nav_panel("Roadblocks",
          subtab_header(
            "Roadblocks",
            cedar_definition_summary("roadblocks"), " ",
            pathways_guide_link("roadblocks")
          ),
          cedar_definition_panel("roadblocks"),
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(3,
                selectizeInput(ns("so_subject"), "Subject codes",
                               choices  = c(),
                               multiple = TRUE,
                               options  = list(placeholder = "All subjects\u2026"))
              ),
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
                  actionButton(ns("so_run"), "Run", class = "btn-sm btn-primary",
                               icon = icon("play"))
                )
              )
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("so_meta"))))
          ),

          div(class = "pathways-section",
            # Shared definition above; keep only reading guidance here.
            div(class = "pathways-explainer",
              tags$p(class = "cedar-body",
                "Read the counts and stop-out rates together. Pop gap is DFW stop-out minus pass stop-out; ",
                "Excess gap subtracts the same comparison for other students. Gaps are percentage points (pp). ",
                "Impact ranks the positive excess gap times the population DFW count; it is not an estimate of students lost because of a course."),
              pathways_guide_link("roadblocks")
            ),
            uiOutput(ns("so_recent_term_warn")),
            reactable::reactableOutput(ns("so_table"))
          )
        ),

        # ---- Course Timing ----
        nav_panel("Course Timing",
          subtab_header(
            "Course Timing",
            cedar_definition_summary("course-timing"), " ",
            pathways_guide_link("course-timing")
          ),
          cedar_definition_panel(c("course-timing", "credit-position")),
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(2,
                selectizeInput(ns("ct_campus"), "Course campus",
                               choices  = cedar_campus_choices(),
                               multiple = TRUE,
                               selected = CEDAR_CAMPUS_DEFAULT,
                               options  = list(placeholder = "All campuses..."))
              ),
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
                # Classification leads and is the default: it is the only axis
                # that reads a genuine per-term Banner value, so it works for the
                # whole population. The credit and relative-term axes are built
                # from running totals and can only describe students whose full
                # record is inside the data window.
                selectInput(ns("ct_x_axis"), "X-axis",
                            choices  = c(
                              "Classification"        = "classification",
                              "Total credits (bands)" = "overall_credit_band",
                              "UNM credits (bands)"   = "inst_credit_band",
                              "Relative term"         = "relative_term"
                            ),
                            selected = "classification")
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
                  actionButton(ns("ct_run"), "Run", class = "btn-sm btn-primary",
                               icon = icon("play"))
                )
              )
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("ct_meta")))),
            uiOutput(ns("ct_axis_note"))
          ),
          uiOutput(ns("ct_explanation")),
          uiOutput(ns("ct_plot_ui")),
          div(class = "mt-3",
            reactable::reactableOutput(ns("ct_table"))
          )
        ),

        # ---- Course Pairs ----
        nav_panel("Course Pairs",
          subtab_header(
            "Course Pairs",
            "Surfaces common A\u2192B course sequences: of students who took course A, what share ",
            "later took course B? Useful for spotting de-facto prerequisites and popular ",
            "follow-ons. Pairs more than the max term gap apart are excluded, and non-ongoing ",
            "students count only through their last focal term. Course A enrollments are counted ",
            "only where the data holds the full follow-up window, so recent terms don't deflate ",
            "the rates. ",
            pathways_guide_link("course-pairs")
          ),
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(2,
                selectizeInput(ns("cp_campus"), "Course campus",
                               choices  = cedar_campus_choices(),
                               multiple = TRUE,
                               selected = CEDAR_CAMPUS_DEFAULT,
                               options  = list(placeholder = "All campuses..."))
              ),
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
                  actionButton(ns("cp_run"), "Run", class = "btn-sm btn-primary",
                               icon = icon("play"))
                )
              )
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("cp_meta"))))
          ),
          reactable::reactableOutput(ns("cp_table"))
        ),

        # ---- Course to Major ----
        nav_panel("Course to Major",
          subtab_header(
            "Course to Major",
            "Looks for courses near the doorway into the major \u2014 which course-and-instructor ",
            "groups are most often followed by later entry into the department, and, in the ",
            "heatmaps, what students took before they first entered the unit. Descriptive ",
            "signals, not causal claims. ",
            pathways_guide_link("course-to-major")
          ),
          div(class = "filters-compact mt-filters",
            fluidRow(
              column(2,
                selectizeInput(ns("ge_campus"), "Campus",
                               choices  = c(),
                               multiple = TRUE,
                               options  = list(placeholder = "All…"))
              ),
              column(2,
                selectizeInput(ns("ge_from_term"), "From term",
                               choices = c(),
                               multiple = FALSE)
              ),
              column(1,
                selectizeInput(ns("ge_to_term"), "To term",
                               choices = c(),
                               multiple = FALSE)
              ),
              column(2,
                selectInput(ns("ge_level"), "Course level",
                            choices = c("All" = "all", "Undergrad" = "undergrad",
                                        "Lower div" = "lower", "Upper div" = "upper", "Grad" = "grad"),
                            selected = "undergrad")
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
                numericInput(ns("ge_conv_max_lag"), "Heatmap lag",
                             value = 3, min = 1, max = 6, step = 1)
              ),
              column(2,
                div(class = "mt-btn",
                  actionButton(ns("ge_conv_run"), "Run", class = "btn-sm btn-primary",
                               icon = icon("play"))
                )
              )
            ),
            filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("ge_instructor_meta"))))
          ),

          # ── Course + Instructor Associations (primary) ───────────────────────
          pathways_section_heading("Course + Instructor Signals"),
          p(
            class = "text-hint",
            "The population defines the focal department and subject prefixes; this table then scans ",
            tags$strong("all enrolled students"),
            " in those focal-subject courses — it is ", tags$em("not"),
            " limited by the Population scope dropdown. A student counts as entering only when their first ",
            tags$strong("major or pre-major"),
            " record in this department appears after the course term. Same-term department records are excluded because the course did not clearly precede entry. By default the ",
            tags$strong("To term"),
            " ends one regular term before the newest complete term — students enrolled more recently have had no time to enter the department, so including them deflates Entry %. The ",
            tags$em("Courses Before Major Entry"),
            " heatmaps use a different scope: selected-population students only."
          ),
          info_panel("Column guide",
            tags$ul(style = "margin: 0; padding-left: 18px;",
              tags$li(HTML("<strong>Campus</strong> — the campus that delivered the course.")),
              tags$li(HTML("<strong>Course</strong> — the course code.")),
              tags$li(HTML("<strong>Instructor</strong> — primary instructor of record for that section.")),
              tags$li(HTML("<strong>Eligible</strong> — registered students in that course + instructor group who did <em>not</em> already have a department major or pre-major before or during the course term.")),
              tags$li(HTML("<strong>Later entered</strong> — eligible students whose first department major or pre-major record appears after the course term.")),
              tags$li(HTML("<strong>Later major / pre-major</strong> — whether that first later department record was a full major or a pre-major.")),
              tags$li(HTML("<strong>Median terms</strong> — typical number of regular terms between the course and first later department record.")),
              tags$li(HTML("<strong>Entry %</strong> — Later entered ÷ Eligible.")),
              tags$li(HTML("<strong>% of Pool</strong> — this group’s Eligible count as a share of all distinct eligible students across all groups. It can sum to more than 100% because one student can take multiple courses.")),
              tags$li(HTML("<strong>Terms</strong> — how many distinct terms this instructor taught this course (indicates sample breadth)."))
            )
          ),
          div(class = "pathways-table-caption",
            tags$strong("Table: Course + Instructor Signals"),
            " — all enrolled students in focal-subject courses, grouped by campus, course title, and instructor."
          ),
          reactable::reactableOutput(ns("ge_instructor_table")),

          # ── Entry Heatmaps (collapsed) ───────────────────────────────────────
          tags$details(
            class = "pathways-inline-details",
            ontoggle = "if (this.open && window.Plotly) setTimeout(() => this.querySelectorAll('.js-plotly-plot').forEach(p => Plotly.Plots.resize(p)), 50);",
            tags$summary(
              class = "pathways-inline-summary",
              tags$span(class = "pathways-inline-summary-title", "Courses Before Major Entry"),
              tags$span(class = "pathways-inline-summary-action", "Show heatmaps")
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
          subtab_header(
            "Major Changes",
            "Shows when students enter the selected unit as pre-majors or full majors, when ",
            "pre-majors become full majors, and when students leave for another major. ",
            "Transfer origin comes from the Academic Studies Student Population label, not ",
            "from a credit threshold. The separate 30-credit entry rule uses attempted UNM ",
            "credits reconstructed term by term from Class Lists. ",
            pathways_guide_link("major-changes")
          ),
          filter_scope_stripe(div(class = "subtab-scope", uiOutput(ns("mc_meta")))),

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
          section_block(
            "Inflow / Outflow by Major",
            description = tags$p(class = "text-hint",
              "One row per major. ", tags$strong("Arriving to"), " counts students who switched ",
              "into that major from somewhere else; ", tags$strong("leaving for elsewhere"),
              " counts students who switched out of it. The same major can show up in both."
            ),
            level = "h3",
            div(class = "mt-2", reactable::reactableOutput(ns("mc_flow_table")))
          ),

          hr(class = "mc-divider"),

          # ── A → B pathways ───────────────────────────────────────────────────
          section_block(
            "Common Pathways (from → to)",
            description = tags$p(class = "text-hint",
            "Each row is a specific from→to switch. Switches involving only a few students are ",
            "hidden so individuals can't be identified. ",
            tags$strong("Median completed / attempted UNM credits"), " come from class-list-derived ",
            "observed credits through the term before the switch posted."
            ),
            level = "h3",
            div(class = "mt-2", reactable::reactableOutput(ns("mc_pathways_table")))
          ),

          hr(class = "mc-divider"),

          # ── Courses in the term before a departure ───────────────────────────
          # Paired with its baseline column deliberately: a bare "most common
          # courses" list ranks whatever is largest, and reads as a finding.
          section_block(
            "Courses in the Term Before Students Left",
            description = tagList(
              tags$p(class = "text-hint",
                "What students who left the selected unit were taking in their last term here. ",
                "A switch reaches Banner the term after a student actually moves, so this is the ",
                "term they were sitting in while deciding — not the term the change showed up."
              ),
              tags$p(class = "text-hint",
                "Every course is shown twice: how often it turned up in those final terms, and how ",
                "often it turns up in a normal term for this group. ",
                tags$strong("If the two numbers are close, the course is just part of what everyone ",
                "here takes."), " A course only stands out when the first is well above the second."
              ),
              # Deliberately no real course code here. Naming one in a section about
              # courses that precede departures reads as an accusation, and it would
              # not match whatever population the user actually has loaded.
              div(class = "alert-box alert-box--neutral mt-2",
                tags$strong("Example. "),
                "A course taken by 15% of departing students in their final term, against 10% in a ",
                "typical term, is 1.5× — common, but not concentrated. One at 4% against 0.5% is ",
                "8×: rarer overall, yet eight times more likely right before a switch. ",
                "The biggest numbers are usually just the required courses; the interesting rows are ",
                "often further down. Sort by ", tags$strong("Times as likely"), " to bring them up."
              ),
              div(class = "alert-box alert-box--info mt-2",
                tags$strong("This is not causal. "),
                "Nothing here says a course caused anyone to switch, or that the course is a problem. ",
                "Students who were already leaning toward another field pick different courses, so ",
                "the arrow can just as easily run the other way — the decision showing up in the ",
                "schedule rather than the schedule producing the decision. Switches also cluster ",
                "early in a career, and the comparison does not adjust for that, so lower-division ",
                "courses will tend to sit above 1.0 for reasons that have nothing to do with ",
                "switching. Treat a high ratio as a question worth asking, not an answer."
              )
            ),
            level = "h3",
            uiOutput(ns("mc_pre_change_meta")),
            div(class = "mt-2", reactable::reactableOutput(ns("mc_pre_change_table")))
          ),

          hr(class = "mc-divider"),

          # ── Reference detail tables (collapsed) ──────────────────────────────
          section_block(
            "Reference Tables",
            description = tags$p(class = "text-hint",
              "Use these when you need to audit the summaries above. The movement table is aggregated; ",
              "the change-events table is student-level."
            ),
            level = "h3",
            info_panel(
              "Movement detail (aggregated)",
              uiOutput(ns("mc_movement_detail_table")),
              description = "Rows behind the Enter / Convert / Leave movement cards, including rows excluded from headline cards.",
              class = "cedar-detail-panel"
            ),
            info_panel(
              "Change events (student-level switches)",
              div(class = "mt-2", reactable::reactableOutput(ns("mc_changes_table"))),
              description = "Every individual primary-major switch behind the switch charts and tables.",
              class = "cedar-detail-panel"
            )
          )
        )

      ) # end navset_tab
      ) # end pathways-analysis-content div
  ) # end tagList
}

# What this data window can and cannot say about a population.
#
# Stated as counts for the population on screen, not as a generic disclaimer.
# The two limits are structural — they come from the data starting and ending
# somewhere, not from a defect — and they are invisible in the outcome counts,
# which is why they are worth saying out loud rather than leaving in
# the docs. No promises about future coverage, no defence of the gap.
pathways_coverage_panel <- function(coverage) {
  if (is.null(coverage) || is.na(coverage$pct_truncated %||% NA)) return(NULL)

  fmt <- function(n) format(n, big.mark = ",")
  n_tr <- coverage$n_truncated; n_ce <- coverage$n_censored

  info_panel(
    "What this data window can see about these students",
    tagList(
      tags$p(class = "cedar-body", sprintf(
        "CEDAR's enrollment records run %s to %s. Of the %s students in this population, %s (%s%%) have a complete record inside that window — both their arrival at UNM and their outcome are visible.",
        fmt_term(coverage$min_data_term), fmt_term(coverage$max_data_term),
        fmt(coverage$n), fmt(coverage$n_complete %||% NA), coverage$pct_complete %||% NA)),
      tags$ul(class = "cedar-body",
        tags$li(HTML(sprintf(
          "<strong>%s students (%s%%) were already enrolled when the records begin.</strong> Their earlier coursework is not in the data. On any timing view they look like first-semester students, and credit or term counts for them start mid-career at zero.",
          fmt(n_tr), coverage$pct_truncated))),
        tags$li(HTML(sprintf(
          "<strong>%s students (%s%%) are still enrolled in the most recent term.</strong> Their outcome has not happened yet, so they cannot be counted as graduating, switching, or stopping out — only as ongoing.",
          fmt(n_ce), coverage$pct_censored)))
      ),
      tags$p(class = "cedar-body",
        "Outcome counts on this page use every student. Timing views are the ones these
         limits bind, and each says which restriction it applies."),
      tags$p(class = "cedar-body",
        tags$em("Not knowable from this data at all:"),
        " anything before the window opens — a student's full transfer history, coursework
         at a prior institution, or how far along they were when they arrived; and the
         reason behind any transition CEDAR records.")
    ),
    description = sprintf(
      "%s of %s students have a complete record here. The rest are bounded at one end or the other.",
      fmt(coverage$n_complete %||% NA), fmt(coverage$n)),
    class = "cedar-detail-panel"
  )
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
          tags$strong("Define Population"),
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
# Pathways tab module — server
# =============================================================================

pathwaysServer <- function(id, students, programs, degrees = NULL,
                           cedar_grades = NULL, cedar_student_term_credits = NULL,
                           cedar_next_term = NULL,
                           lookups = list(), program_choices = character(),
                           dept_choices = character()) {
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

    course_delivery_keys <- function(df) {
      intersect(c("campus", "subject_course"), names(df))
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
        dplyr::group_by(dplyr::across(dplyr::all_of(course_delivery_keys(df)))) %>%
        dplyr::mutate(total_students = sum(n_students, na.rm = TRUE)) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(
          timing_bucket = bucket_label,
          n_students = as.integer(n_students),
          n_eligible = as.integer(n_eligible),
          total_students = as.integer(total_students)
        ) %>%
        dplyr::select(
          dplyr::any_of("campus"),
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
                                               degrees = degrees, students = students,
                                               program_choices = program_choices,
                                               dept_choices = dept_choices)

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
          "Define your student population first. Choose programs in the filters above and click Define Population before running any analysis."
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
          showModal(cedar_info_modal(
            title = "No population defined",
            p("You need to define a student population before running analysis."),
            p("Use the population filters at the top of the page:"),
            tags$ol(
              tags$li("Choose a selection type (Major Group, Department, etc.)"),
              tags$li("Select your majors or filters"),
              tags$li("Click ", tags$strong("Define Population"))
            ),
            close_label = "Got it"
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
    # The enrollment-side boundary for every Pathways analysis: population
    # windowing, Course Pairs censoring, and the scope strip. This is the settled
    # -registration edge that global.R derives from the data — the last term
    # whose registration has actually finished — not arithmetic on
    # cedar_current_term. Both give Spring 2026 on current data, but the derived
    # one self-corrects when the data moves and the config does not. See the
    # right-edge policy in AGENTS.md. Grade-dependent boundaries use
    # graded_through() below instead; the two are different terms.
    analysis_through <- if (exists("cedar_report_end_term") && !is.null(cedar_report_end_term)) {
      cedar_report_end_term
    } else {
      tryCatch(subtract_term(cedar_current_term), error = function(e) NULL)
    }

    # Grade-dependent outcomes are bounded by the graded edge, computed once at
    # startup in global.R from the loaded data. See the right-edge policy in
    # AGENTS.md. The fallback recomputes it for callers that never ran global.R.
    graded_through <- reactive({
      if (exists("cedar_graded_through") && !is.null(cedar_graded_through)) {
        cedar_graded_through
      } else {
        cedar_data_edges(students, max_term = cedar_current_term)$last_graded
      }
    })

    filtered_students <- reactive({
      pop <- tryCatch(population_rv()$population, error = function(e) NULL)
      apply_pathways_population_window(students, pop, analysis_through)
    })

    # Pre-windowed cedar_grades: apply the same analysis_through + relevant_until
    # windowing as filtered_students, but to the pre-classified grade table.
    # This is passed to get_stopout so it skips the expensive
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

    # Roadblocks defaults to the unit's OWN subject prefixes.
    #
    # The question a chair brings to this subtab is "where are my students
    # getting blocked in my courses" — those are the ones they can act on. Left
    # unscoped, the table is dominated by large service courses from other
    # departments, which are real but not theirs to fix. The control stays a
    # normal multi-select, so widening to other subjects is one click.
    #
    # Dept codes are not course prefixes (Geography is dept GES, courses GEOG),
    # so the mapping goes through subject_lookup rather than being assumed.
    observeEvent(population_rv(), {
      subjects <- sort(unique(sub(" .*", "", students$subject_course[
        !is.na(students$subject_course) & nzchar(students$subject_course)
      ])))
      pop_opt <- tryCatch(population_rv()$opt, error = function(e) NULL) %||% list()
      focal <- tryCatch(
        resolve_pathways_focal_subjects(pop_opt, programs, lookups),
        error = function(e) character(0)
      )
      focal <- intersect(focal, subjects)
      updateSelectizeInput(session, "so_subject", choices = subjects,
                           selected = focal, server = TRUE)
    }, ignoreInit = FALSE)

    # ---- Population Audit ----
    #
    # Reactive on get_population() — updates immediately after build, no Run button.
    # Three sections:
    #   1. Outcome summary cards (with plain-language descriptions)
    #   2. Student detail table (all population columns)
    #   3. Degree check table (stopped_out only — surfaces graduation-lag cases)

    output$pop_audit_ui <- renderUI({
      # population_rv is an eventReactive that has not fired until "Define Population"
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

      college_benchmark <- tryCatch({
        opt <- rv$opt %||% list()
        benchmark <- NULL
        if (!identical(opt$type, "demographic")) {
          focal_rows <- if (identical(opt$type, "dept")) {
            programs %>%
              filter(program_type %in% c("Major", "Second Major"),
                     dept_code == opt$dept_code, !is_pre_major)
          } else if (opt$type %in% c("major", "preset")) {
            programs %>%
              filter(program_type %in% c("Major", "Second Major"),
                     program_name %in% (opt$program_names %||% character(0)),
                     !is_pre_major)
          } else {
            tibble()
          }

          focal_college_counts <- focal_rows %>%
            { if (!is.null(opt$campus) && length(opt$campus) > 0L) {
                filter(., student_campus %in% opt$campus)
              } else . } %>%
            { if (!is.null(opt$student_level) && length(opt$student_level) > 0L) {
                filter(., student_level %in% opt$student_level)
              } else . } %>%
            filter(!is.na(student_college), nzchar(student_college)) %>%
            count(student_college, sort = TRUE)
          if (nrow(focal_college_counts) > 0) {
            focal_college <- focal_college_counts$student_college[[1]]
            benchmark <- load_population_benchmark_cache(focal_college, opt)
            if (is.null(benchmark)) {
              college_programs <- programs %>%
                filter(program_type %in% c("Major", "Second Major"),
                       student_college == focal_college,
                       !is_pre_major,
                       !is.na(program_name), nzchar(program_name)) %>%
                distinct(program_name) %>%
                pull(program_name)

              if (length(college_programs) > 0) {
                bench_opt <- opt
                bench_opt$type <- "major"
                bench_opt$program_names <- college_programs
                bench_pop <- build_population(
                  programs, degrees = degrees, students = students, opt = bench_opt
                )
                if (!is.null(bench_pop) && nrow(bench_pop) > 0) {
                  benchmark <- list(
                    college = focal_college,
                    pop = bench_pop,
                    conversion_stats = attr(bench_pop, "conversion_stats") %||% list()
                  )
                  save_population_benchmark_cache(focal_college, opt, benchmark)
                }
              }
            }
          }
        }
        benchmark
      }, error = function(e) {
        message("[pathways population] College benchmark unavailable: ", e$message)
        NULL
      })

      college_counts <- if (!is.null(college_benchmark)) {
        college_benchmark$pop %>%
          count(outcome) %>%
          { stats::setNames(.$n, .$outcome) }
      } else NULL
      college_declared_counts <- if (!is.null(college_benchmark)) {
        college_benchmark$pop %>%
          filter(!is.na(last_declared_term)) %>%
          count(outcome) %>%
          { stats::setNames(.$n, .$outcome) }
      } else NULL
      college_conversion_stats <- college_benchmark$conversion_stats %||% list()

      format_pct_count <- function(n, denominator = NULL) {
        n <- as.integer(n %||% 0L)
        if (is.null(denominator) || is.na(denominator) || denominator <= 0) {
          return(format(n, big.mark = ","))
        }
        paste0(round(100 * n / denominator), "% (", format(n, big.mark = ","), ")")
      }
      benchmark_line <- function(n, denominator = NULL) {
        if (is.null(n) || is.null(denominator) || is.na(denominator) || denominator <= 0)
          return(NULL)
        tags$p(
          class = "outcome-card-benchmark",
          "College: ", format_pct_count(n, denominator)
        )
      }
      make_outcome_card <- function(oc, counts = outcome_counts,
                                    label = NULL, description = NULL,
                                    denominator = sum(counts, na.rm = TRUE),
                                    benchmark_counts = NULL,
                                    benchmark_denominator = NULL) {
        n <- if (oc %in% names(counts)) counts[[oc]] else 0L
        bench_n <- if (!is.null(benchmark_counts) && oc %in% names(benchmark_counts))
          benchmark_counts[[oc]] else NULL
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
          benchmark_line(bench_n, benchmark_denominator),
          tags$p(class = "text-note", description %||% outcome_desc[[oc]] %||% ""),
          recent_note
        )
      }
      make_count_card <- function(n, label, description, color = "#1565c0",
                                  denominator = NULL,
                                  benchmark_n = NULL,
                                  benchmark_denominator = NULL) {
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
          benchmark_line(benchmark_n, benchmark_denominator),
          tags$p(class = "text-note", description)
        )
      }
      declared_denominator <- sum(declared_outcome_counts, na.rm = TRUE)
      college_declared_denominator <- sum(college_declared_counts %||% numeric(0), na.rm = TRUE)
      declared_outcome_cards <- lapply(
        c("ongoing", "graduated", "switched_out", "stopped_out"),
        make_outcome_card,
        counts = declared_outcome_counts,
        denominator = declared_denominator,
        benchmark_counts = college_declared_counts,
        benchmark_denominator = college_declared_denominator
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
      college_n_current_premajor <- if (
        !is.null(college_benchmark) &&
          all(c("outcome", "entry_status", "last_declared_term") %in% names(college_benchmark$pop))
      ) {
        sum(
          college_benchmark$pop$outcome == "ongoing" &
            college_benchmark$pop$entry_status == "pre_major" &
            is.na(college_benchmark$pop$last_declared_term),
          na.rm = TRUE
        )
      } else 0L
      college_n_converted <- as.integer(college_conversion_stats$n_converted %||% 0L)
      college_chose_elsewhere <- if (!is.null(college_counts) && "chose_elsewhere" %in% names(college_counts)) {
        college_counts[["chose_elsewhere"]]
      } else 0L
      college_left_undeclared <- if (!is.null(college_counts) && "left_undeclared" %in% names(college_counts)) {
        college_counts[["left_undeclared"]]
      } else 0L
      college_pre_major_denominator <- college_n_current_premajor + college_n_converted +
        college_chose_elsewhere + college_left_undeclared
      pre_major_stopped <- if (all(c("outcome", "last_unit_term", "last_record_term") %in% names(pop))) {
        sum(
          pop$outcome == "left_undeclared" &
            (is.na(pop$last_record_term) | pop$last_record_term <= pop$last_unit_term),
          na.rm = TRUE
        )
      } else {
        pre_major_left_undeclared
      }
      college_pre_major_stopped <- if (
        !is.null(college_benchmark) &&
          all(c("outcome", "last_unit_term", "last_record_term") %in% names(college_benchmark$pop))
      ) {
        sum(
          college_benchmark$pop$outcome == "left_undeclared" &
            (is.na(college_benchmark$pop$last_record_term) |
               college_benchmark$pop$last_record_term <= college_benchmark$pop$last_unit_term),
          na.rm = TRUE
        )
      } else {
        college_left_undeclared
      }
      pre_major_continued_no_major <- pre_major_left_undeclared - pre_major_stopped
      college_pre_major_continued_no_major <- college_left_undeclared - college_pre_major_stopped
      pre_major_stopped_desc <- tagList(
        "Pre-major-status students with no UNM enrollment after their last focal pre-major term."
      )
      current_premajor_card <- make_count_card(
        n_current_premajor,
        "Still pre-major",
        "Pre-major-only students whose focal pre-major record is in the most recent data term.",
        "#2e7d32",
        denominator = pre_major_denominator,
        benchmark_n = college_n_current_premajor,
        benchmark_denominator = college_pre_major_denominator
      )
      pre_major_outcome_cards <- list(
        make_count_card(
          n_converted,
          "Became majors",
          "Students whose first focal-unit status was pre-major and who later held declared major status in this unit.",
          "#1565c0",
          denominator = pre_major_denominator,
          benchmark_n = college_n_converted,
          benchmark_denominator = college_pre_major_denominator
        ),
        make_outcome_card(
          "chose_elsewhere",
          denominator = pre_major_denominator,
          benchmark_counts = college_counts,
          benchmark_denominator = college_pre_major_denominator
        ),
        make_count_card(
          pre_major_stopped,
          "Stopped out before declaring",
          pre_major_stopped_desc,
          "#4a148c",
          denominator = pre_major_denominator,
          benchmark_n = college_pre_major_stopped,
          benchmark_denominator = college_pre_major_denominator
        ),
        make_count_card(
          pre_major_continued_no_major,
          "Enrolled later, no major found",
          "Pre-major-status students with later UNM enrollment after their last focal pre-major term, but no later major or pre-major record in the available program data.",
          "#6f8b78",
          denominator = pre_major_denominator,
          benchmark_n = college_pre_major_continued_no_major,
          benchmark_denominator = college_pre_major_denominator
        )
      )
      has_pre_major_display <- n_current_premajor > 0 || pre_major_counts > 0 || n_converted > 0

      has_stopped_out  <- "stopped_out" %in% pop$outcome
      has_degrees_data <- !is.null(degrees)

      # What the data window can see about THIS population, stated before the
      # outcome cards rather than after them. Neither limit is visible from the
      # counts below — a student who was already enrolled when CEDAR's records
      # begin looks like a first-semester freshman, and one still enrolled in the
      # last term looks like a continuing student — so a reader who is not told
      # will reasonably assume full coverage.
      coverage <- pathways_coverage_facts(
        pop,
        min_data_term = min(students$term, na.rm = TRUE),
        max_data_term = max(students$term, na.rm = TRUE)
      )

      tagList(
        pathways_coverage_panel(coverage),

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

    # Course level for the single Roadblocks analysis and all its context columns.
    so_level_opt <- reactive({
      pathways_level_filter(input$so_level)
    })

    so_data <- reactive({
      req(get_population())

      status_message <- create_timing_status_message("pathways-stopouts", "Computing stop-out rates")
      showNotification(status_message, type = "warning", duration = NULL, id = "so_loading")
      timer <- start_report_timer("pathways-stopouts")

      # Two independent edges apply: the anchor needs a classified grade and
      # its next regular term must be complete. get_stopout() enforces the
      # second condition per anchor because one arithmetic cap is wrong around
      # summer terms.
      so_grade_boundary <- graded_through()

      # Evaluate cedar_grades once (boundary-capped); use it to decide whether
      # the expensive filtered_students() fallback is needed. get_stopout() only
      # touches `students` when cedar_grades is absent — avoid the scan otherwise.
      so_grades <- filtered_cedar_grades()
      if (!is.null(so_grades) && !is.null(so_grade_boundary)) {
        so_grades <- dplyr::filter(so_grades, term <= so_grade_boundary)
      }
      so_students <- if (!is.null(so_grades) && nrow(so_grades) > 0) {
        NULL
      } else {
        s <- filtered_students()
        if (!is.null(so_grade_boundary)) s <- dplyr::filter(s, term <= so_grade_boundary)
        s
      }

      result <- tryCatch({
        get_stopout(
          so_students, get_analysis_population(),
          degrees        = degrees,
          opt            = list(
            min_n        = as.integer(input$so_min_n),
            min_dfw_n    = as.integer(input$so_min_dfw_n),
            level        = so_level_opt(),
            subject_code = if (length(input$so_subject) > 0) input$so_subject else NULL,
            graded_through = so_grade_boundary,
            observation_end_term = analysis_through
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
      so_boundary <- if (length(so_data()$term_range) >= 2L) {
        so_data()$term_range[[2]]
      } else {
        NA_integer_
      }
      if (is.na(so_boundary)) so_boundary <- NULL
      if (is.null(so_boundary)) {
        # Boundary could not be derived (no cedar_current_term) — censored
        # recent terms may be included, so fall back to the old warning.
        return(div(
          class = "alert alert-warning alert-compact",
          tags$strong("⚠ Most-recent-term bias: "),
          "Students enrolled in the latest data term have no visible next term, ",
          "so they all appear as stopped out — rates for recently active courses are inflated."
        ))
      }
      # Name the latest anchor that passed both observation requirements.
      next_term <- tryCatch(add_term(so_boundary), error = function(e) NULL)
      div(
        class = "alert alert-info alert-compact",
        tags$strong("Observation window: "),
        "outcomes through ", fmt_term(so_boundary), ". ",
        if (!is.null(next_term)) {
          sprintf(paste("That is the latest course term with both a classified grade and",
                        "a complete following regular term. %s and later will appear here",
                        "when both conditions are met; no configuration change is needed."),
                  fmt_term(next_term))
        } else {
          "Later anchors are excluded until both their grades and following term are complete."
        }
      )
    })

    output$so_meta <- renderUI({
      if (is.null(get_population()))
        return(tags$span(class = "scope-bar-placeholder", "Define a population, then Run to see scope."))
      req(so_data())
      n_course_groups <- nrow(so_data()$by_course)
      div(
        class = "text-hint",
        tags$strong("Campus-course groups shown: "),
        n_course_groups,
        sprintf(" (≥%d population students, ≥%d population DFW). ",
                as.integer(input$so_min_n),
                as.integer(input$so_min_dfw_n)),
        if (length(input$so_subject) > 0) {
          sprintf("Scoped to %s courses — clear the Subject codes filter to see where these students are blocked elsewhere. ",
                  paste(input$so_subject, collapse = ", "))
        } else {
          "All subjects. "
        },
        "Rows are courses taken by the selected population; baseline columns compare other students in those same courses. ",
        so_data()$observation_info$note
      )
    })

    output$so_table <- reactable::renderReactable({
      req(so_data())
      result <- so_data()$by_course
      if (is.null(result) || nrow(result) == 0) {
        return(message_table("No qualifying courses found."))
      }
      # Counts, rates, and DFW context already share the selected observations.
      result <- prepare_roadblock_results(result) %>%
        select(campus, subject_course, impact_score, excess_gap,
               pop_stopout_gap, baseline_stopout_gap,
               pop_n_dfw, pop_n_pass,
               pop_dfw_stopout_rate, pop_pass_stopout_rate,
               pop_dfw_rate, baseline_dfw_rate) %>%
        mutate(across(ends_with("gap"), ~ .x * 100)) # display percentage points only
      rate_cols <- grep("rate|gap|p_value", names(result), value = TRUE)
      rate_defs <- lapply(rate_cols, function(col) {
        reactable::colDef(
          align = "right",
          format = reactable::colFormat(percent = grepl("rate", col), digits = 1)
        )
      })
      names(rate_defs) <- rate_cols
      rate_defs$campus <- reactable::colDef(name = "Campus", minWidth = 80)
      rate_defs$subject_course <- reactable::colDef(name = "Course", minWidth = 105,
        cell = function(value) htmltools::span(class = "fw-semibold", value))
      rate_defs$impact_score <- reactable::colDef(name = "Impact", align = "right",
        format = reactable::colFormat(digits = 1))
      rate_defs$excess_gap <- reactable::colDef(name = "Excess gap (pp)", align = "right",
        format = reactable::colFormat(digits = 1))
      rate_defs$baseline_stopout_gap <- reactable::colDef(
        name = "Baseline gap (pp)", align = "right",
        format = reactable::colFormat(digits = 1)
      )
      rate_defs$pop_n_dfw <- reactable::colDef(name = "Pop DFW", align = "right")
      rate_defs$pop_n_pass <- reactable::colDef(name = "Pop pass", align = "right")
      rate_defs$pop_dfw_stopout_rate <- reactable::colDef(
        name = "DFW stop-out",
        align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1),
        style = function(value) {
          bg <- color_from_cuts(value, c(0.10, 0.25), unname(CEDAR_SURFACE_TINTS[c("success", "warning", "critical")]))
          if (!is.null(bg)) list(backgroundColor = bg)
        }
      )
      rate_defs$pop_stopout_gap <- reactable::colDef(
        name = "Pop gap (pp)",
        align = "right",
        format = reactable::colFormat(digits = 1),
        style = function(value) {
          bg <- color_from_cuts(value, c(-5, 5), unname(CEDAR_SURFACE_TINTS[c("success", "warning_light", "critical")]))
          if (!is.null(bg)) list(backgroundColor = bg)
        }
      )
      rate_defs$pop_pass_stopout_rate <- reactable::colDef(
        name = "Pass stop-out", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      )
      # Context columns. Deliberately uncoloured: a high DFW rate is not itself
      # the finding on this subtab, and tinting it would pull the eye away from
      # the departure columns that are.
      rate_defs$pop_dfw_rate <- reactable::colDef(
        name = "Pop DFW rate", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      )
      rate_defs$baseline_dfw_rate <- reactable::colDef(
        name = "Baseline DFW rate", align = "right",
        format = reactable::colFormat(percent = TRUE, digits = 1)
      )

      make_pathways_table(result, columns = rate_defs)
    })

    # ---- Course Timing ----

    output$ct_explanation <- renderUI({
      axis <- input$ct_x_axis %||% "classification"
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
        x_axis            = input$ct_x_axis %||% "classification",
        max_relative_term = as.integer(input$ct_max_term),
        min_n             = as.integer(input$ct_min_n)
      )
      opt$level <- pathways_level_filter(input$ct_level)
      # Course-delivery campus, distinct from the population's home-campus
      # filter above — see .filter_course_campus() in pathway.R.
      if (length(input$ct_campus) > 0)           opt$campus               <- input$ct_campus
      if (length(input$ct_subject) > 0)          opt$subject_code         <- input$ct_subject
      if (nzchar(input$ct_start_class %||% ""))  opt$start_classification <- input$ct_start_class

      # Relative-term axis is left-truncated for students who were already enrolled
      # when the data starts. Force Freshman filter unless the user has explicitly
      # chosen a different start classification.
      #
      # The credit-band axes are exposed to the same truncation — their position
      # is a running total that starts at zero on the first term in the data — but
      # they are handled inside get_course_timing(), which drops those students
      # outright and reports the count in timing_meta$n_truncated. Only the
      # classification axis is genuinely immune: it reads a per-term Banner value
      # that does not depend on seeing the earlier record.
      if (identical(opt$x_axis, "relative_term") && is.null(opt$start_classification)) {
        opt$start_classification <- "Freshman"
        updateSelectInput(session, "ct_start_class", selected = "Freshman")
        showModal(cedar_info_modal(
          title = "Filtered to Freshman-start students",
          p("The ", tags$strong("Relative term"), " axis assigns term 1 based on each student's
             first appearance in CEDAR — not their actual first semester at UNM. Students who were
             already enrolled when the data begins (Fall 2018) look like first-semester students
             even if they were seniors. This is called ", tags$em("left truncation"), "."),
          p("To prevent misleading results, this analysis has been automatically restricted to
             students classified as ", tags$strong("Freshman"), " at their first enrollment record.
             This is the best available proxy for a genuine first semester in this data window."),
          p("You can change this in the ", tags$strong("Starting classification"), " dropdown.
             The ", tags$strong("Classification"), " x-axis removes the restriction entirely — it
             reads each student's standing in the term they took the course, so it does not depend
             on seeing their earlier record. The credit-band axes handle the same problem a
             different way: they exclude left-truncated students automatically and report how many
             were set aside.",
            class = "cedar-body"),
          close_label = "Got it"
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

      # term_credits is required by every credit-band axis: those modes rebuild
      # the position from the per-term class-list series instead of reading the
      # frozen cumulative columns on cedar_programs. programs is still passed —
      # overall_credit_band uses it to recover the transfer block.
      result <- tryCatch(
        get_course_timing(students_pop, get_analysis_population(), programs = programs, opt = opt,
                          students_full = students_meta,
                          term_credits = cedar_student_term_credits),
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
    # Each x-axis answers a different question and has a different blind spot.
    # Stating the live one next to the chart keeps the caveat attached to the
    # choice; a reader who switches axes gets a different note, which is the
    # point. None of these are apologies — they are what the axis measures.
    output$ct_axis_note <- renderUI({
      axis <- input$ct_x_axis %||% "classification"
      body <- switch(axis,
        relative_term = tagList(
          tags$strong("Terms enrolled"),
          " counts from each student's first term in CEDAR's records. For students who were
           already enrolled when the records begin, term 1 is not their real first term — which
           is why this axis restricts to students classified as Freshman at their first record.
           It measures time at UNM, not progress through a degree: a transfer student's term 1
           is whatever standing they arrived with."
        ),
        classification = tagList(
          tags$strong("Classification"), " is the registrar's own standing for that term —
           Freshman, Sophomore, Junior, Senior. It is recorded per term, survives a re-pull
           unchanged, and never moves backwards, so it is the most dependable answer to
           \u201chow far along were they\u201d that this data holds. Its limits are real and
           narrow: it is a four-step ladder rather than a continuous measure, and students on
           professional ladders (Nursing Lvl I-V, Law, the Graduate family) do not map onto it
           and are left out of the chart."
        ),
        inst_credit_band = tagList(
          tags$strong("UNM credits"), " counts credit attempted at UNM only, rebuilt from
           class-list records term by term. Credit a student arrived with is not counted, so
           transfer-heavy populations place earlier here than their true standing, and the
           upper bands hold far fewer students than the lower ones."
        ),
        overall_credit_band = tagList(
          tags$strong("Total credits"), " adds an estimated transfer block to the UNM series.
           The block is recovered from the registrar's cumulative totals and assumed to have
           arrived before the student's first term here — credit transferred in mid-degree is
           attributed to the start. It is an estimate, and the only axis on this tab that
           attempts to account for prior coursework at all."
        ),
        NULL
      )
      if (is.null(body)) return(NULL)
      tags$p(class = "text-muted-sm", body)
    })

    output$ct_plot_ui <- renderUI({
      req(ct_data())
      # get_course_timing() returns a bare data.frame() when nothing survives its
      # filters, which has no subject_course column — grouping on it throws
      # "Must group by variables found in .data" and the user gets a red error
      # where "no results" is the honest answer.
      if (nrow(ct_data()) == 0 || !"subject_course" %in% names(ct_data())) {
        return(empty_state(paste(
          "No course timing results for this population and these filters.",
          "Widen the campus or level scope, or lower Min students per course.")))
      }
      MIN_PCT <- 0.05
      TOP_N   <- 40L
      n_above_min <- ct_data() %>%
        group_by(across(all_of(course_delivery_keys(ct_data())))) %>%
        summarize(peak = max(pct_pop, na.rm = TRUE), .groups = "drop") %>%
        filter(peak >= MIN_PCT) %>%
        nrow()
      n_plot <- min(n_above_min, TOP_N)
      height <- min(max(n_plot * 20 + 100, 200), 8000)
      plotOutput(ns("ct_plot"), height = paste0(height, "px"))
    })

    output$ct_meta <- renderUI({
      if (is.null(get_population()))
        return(tags$span(class = "scope-bar-placeholder", "Define a population, then Run to see scope."))
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
        # A credit axis silently shrinking the population is the thing that makes a
        # map look authoritative while describing a different population than the
        # one the chair defined. Say it on the face of the chart, not in a doc.
        if (!is.null(meta$n_truncated) && meta$n_truncated > 0) {
          sprintf(
            " %s student%s excluded: their record begins at the edge of the data, so credits earned before the window are invisible and a credit position cannot be established. Use the Classification axis to include them.",
            format(meta$n_truncated, big.mark = ","),
            if (meta$n_truncated == 1) "" else "s"
          )
        },
        sprintf(
          " Bands with fewer than %s eligible students and course cells with fewer than %s students are suppressed%s.",
          format(meta$min_band_n, big.mark = ","),
          format(meta$min_cell_n, big.mark = ","),
          if (!is.null(meta$n_bands_suppressed) && meta$n_bands_suppressed > 0) {
            paste0(" (", meta$n_bands_suppressed, " band",
                   if (meta$n_bands_suppressed == 1) "" else "s", " removed)")
          } else {
            ""
          }
        ),
        class = "text-muted-sm"
      )
    })

    output$ct_plot <- renderPlot({
      req(ct_data())

      MAX_COURSES <- 200L
      plot_data   <- ct_data()
      meta        <- attr(plot_data, "timing_meta")
      delivery_keys <- course_delivery_keys(plot_data)
      n_total <- nrow(distinct(plot_data, across(all_of(delivery_keys))))

      if (n_total > MAX_COURSES) {
        top_courses <- plot_data %>%
          group_by(across(all_of(delivery_keys))) %>%
          summarize(total = sum(n_students), .groups = "drop") %>%
          slice_max(total, n = MAX_COURSES) %>%
          select(all_of(delivery_keys))
        plot_data <- plot_data %>% semi_join(top_courses, by = delivery_keys)
      }

      note <- if (n_total > MAX_COURSES)
        paste0("Showing top ", MAX_COURSES, " of ", n_total,
               " campus-course groups by population enrollment. Raise “Min students” to reduce.")
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
      disp <- course_timing_display(ct_data(), input$ct_x_axis %||% "classification")
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
        max_term_gap = as.integer(input$cp_max_gap),
        # Shared observation-window guard: A-side enrollments need max_term_gap
        # complete regular terms of follow-up or their follow-on rates are
        # deflated by the data ending (right-censoring).
        censor_term  = analysis_through
      )
      opt$level <- pathways_level_filter(input$cp_level)
      # Course-delivery campus, distinct from the population's home-campus
      # filter — see .filter_course_campus() in pathway.R.
      if (length(input$cp_campus) > 0)  opt$campus       <- input$cp_campus
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
        return(tags$span(class = "scope-bar-placeholder", "Define a population, then Run to see scope."))
      d    <- cp_data()
      meta <- attr(d, "pair_meta")
      if (is.null(meta)) return(NULL)
      boundary_note <- if (!is.null(meta$a_boundary)) {
        sprintf(" Course A enrollments counted through %s so every A-taker has the full %d-term follow-up window in the data.",
                fmt_term(meta$a_boundary), as.integer(input$cp_max_gap))
      } else ""
      tags$p(
        sprintf(
          "%d qualifying course%s (taken by ≥%d students). Searched %s A-side × %s B-side enrollment records. %d pair%s found (taken by ≥%d students each).%s",
          meta$n_qualifying, if (meta$n_qualifying == 1) "" else "s",
          meta$min_n,
          format(meta$n_a_rows, big.mark = ","),
          format(meta$n_b_rows, big.mark = ","),
          meta$n_pairs, if (meta$n_pairs == 1) "" else "s",
          meta$min_pair_n,
          boundary_note
        ),
        class = "text-muted-sm"
      )
    })

    # ---- Major Changes ----

    mc_data <- reactive({
      req(get_population())
      pop_ids      <- get_analysis_population()$student_id
      pop_programs <- programs %>%
        filter(student_id %in% pop_ids, term <= analysis_through)

      # Small-cell suppression floor — set once in config/shiny_config.R so every
      # descriptive breakdown shares the same minimum group size.
      opt <- list(min_n = cedar_min_group_size)

      status_message <- create_timing_status_message("pathways-major-changes", "Detecting major changes")
      showNotification(status_message, type = "warning", duration = NULL, id = "mc_loading")
      timer <- start_report_timer("pathways-major-changes")

      # Focal programs = the programs this population is defined around.
      # Derived from the population opt (returned by populationSelectorServer) so only
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
        # term_credits is required for the credit-at-change figures; without it
        # detect_major_changes() returns NA rather than reading the frozen
        # cumulative columns. See the field reliability contract in AGENTS.md.
        changes <- detect_major_changes(pop_programs,
                                        opt = list(observation_end_term = analysis_through),
                                        term_credits = cedar_student_term_credits)

        # focal_changes: only transitions that directly involve the population's programs.
        # A History population shows History→PolSci and PolSci→History, but NOT PolSci→Law
        # (even though a History student made that change). Used for all summary views.
        # Full `changes` is preserved for the student-level detail table.
        focal_changes <- changes %>%
          filter(from_major %in% focal_programs | to_major %in% focal_programs)

        decl_context <- get_declaration_context(
          pop_programs, students, get_analysis_population(),
          focal_subjects = focal_subjects,
          opt = opt,
          term_credits = cedar_student_term_credits
        )

        # Movement summary over the selected-unit program timeline. This is built
        # from raw program records because the legacy population entry fields were
        # designed for outcome classification, not for the chair-facing status cards.
        late_threshold <- 60L
        prior_unm_credit_threshold <- 30L
        data_start_term <- min(programs$term, na.rm = TRUE)

        first_unm_terms <- students %>%
          filter(student_id %in% pop_ids) %>%
          group_by(student_id) %>%
          summarize(first_unm_term = as.integer(min(term, na.rm = TRUE)), .groups = "drop")

        # Per-term credit position for this population, from the class-list
        # series rather than the cumulative columns on cedar_programs. Those are
        # stamped at the pull and would report each student's total today at
        # every historical term — see the field reliability contract in
        # AGENTS.md. Built once here and joined wherever a position is needed.
        credit_timeline <- if (!is.null(cedar_student_term_credits)) {
          build_credit_timeline(cedar_student_term_credits, programs,
                                opt = list(student_ids = pop_ids))
        } else {
          NULL
        }
        credit_at_term <- function(df, term_col = "term") {
          if (is.null(credit_timeline)) {
            df$unm_credits   <- NA_real_
            df$total_credits <- NA_real_
            return(df)
          }
          # A left-truncated student's running total starts at zero mid-career,
          # so their position is not merely imprecise, it is wrong in a known
          # direction. Report it as unknown rather than as a low credit count —
          # the same answer this helper gives when there is no credit table at
          # all. See the timeline_valid section of AGENTS.md.
          df %>% left_join(
            credit_timeline %>% select(student_id, term, timeline_valid,
                                       unm_credits   = unm_credits_entering,
                                       total_credits = total_credits_entering) %>%
              mutate(
                unm_credits   = if_else(timeline_valid, unm_credits,   NA_real_),
                total_credits = if_else(timeline_valid, total_credits, NA_real_)
              ) %>%
              select(-timeline_valid),
            by = stats::setNames(c("student_id", "term"), c("student_id", term_col)))
        }

        fallback_first_terms <- pop_programs %>%
          filter(program_type %in% c("Major", "Second Major")) %>%
          group_by(student_id) %>%
          filter(term == min(term, na.rm = TRUE)) %>%
          summarize(first_program_term = as.integer(min(term, na.rm = TRUE)), .groups = "drop") %>%
          credit_at_term(term_col = "first_program_term") %>%
          select(student_id, first_program_term,
                 first_program_unm_credits = unm_credits)

        origin_tbl <- pop_programs %>%
          filter(program_type %in% c("Major", "Second Major")) %>%
          group_by(student_id) %>%
          filter(term == min(term, na.rm = TRUE)) %>%
          summarize(
            origin_group = if_else(
              any(grepl("transfer", student_population, ignore.case = TRUE), na.rm = TRUE),
              "Transfer", "Always UNM"
            ),
            .groups = "drop"
          )

        focal_records <- pop_programs %>%
          filter(program_type %in% c("Major", "Second Major"),
                 program_name %in% focal_programs) %>%
          mutate(is_full_major = !is_pre_major)

        focal_term_status <- focal_records %>%
          group_by(student_id, term) %>%
          summarize(
            focal_status = if_else(any(is_full_major, na.rm = TRUE), "full_major", "pre_major"),
            .groups = "drop"
          ) %>%
          credit_at_term()

        focal_milestones <- focal_records %>%
          group_by(student_id) %>%
          summarize(
            first_unit_term = as.integer(min(term, na.rm = TRUE)),
            first_pre_term = {
              vals <- term[is_pre_major]
              if (length(vals) > 0L) as.integer(min(vals, na.rm = TRUE)) else NA_integer_
            },
            first_full_term = {
              vals <- term[is_full_major]
              if (length(vals) > 0L) as.integer(min(vals, na.rm = TRUE)) else NA_integer_
            },
            first_unit_status = {
              first_term <- min(term, na.rm = TRUE)
              if (any(is_full_major[term == first_term], na.rm = TRUE)) "full_major" else "pre_major"
            },
            .groups = "drop"
          ) %>%
          left_join(first_unm_terms, by = "student_id") %>%
          left_join(fallback_first_terms, by = "student_id") %>%
          left_join(origin_tbl, by = "student_id") %>%
          mutate(
            first_unm_term = coalesce(first_unm_term, first_program_term, first_unit_term),
            origin_group = coalesce(origin_group, "Unknown origin")
          )

        credit_at <- function(term_col, unm_name, total_name) {
          focal_milestones %>%
            select(student_id, event_term = {{ term_col }}) %>%
            filter(!is.na(event_term)) %>%
            left_join(focal_term_status, by = c("student_id", "event_term" = "term")) %>%
            transmute(
              student_id,
              event_term,
              !!unm_name := unm_credits,
              !!total_name := total_credits
            )
        }

        first_pre_credits <- credit_at(first_pre_term, "pre_unm_credits", "pre_total_credits")
        first_full_credits <- credit_at(first_full_term, "full_unm_credits", "full_total_credits")

        event_base <- focal_milestones %>%
          left_join(first_pre_credits, by = "student_id") %>%
          left_join(first_full_credits, by = "student_id")

        build_observed_credit_table <- function() {
          students %>%
            filter(
              student_id %in% pop_ids,
              registration_status_code %in% STATUS_REGISTERED,
              !is.na(credits)
            ) %>%
            # CAMPUS_ROLLUP: one observed curriculum credit load per student-term.
            distinct(student_id, term, subject_course, course_title, credits,
                     final_grade, registration_status_code) %>%
            mutate(
              attempted_credit = credits,
              completed_credit = if_else(final_grade %in% passing_grades, credits, 0)
            ) %>%
            group_by(student_id, term) %>%
            summarize(
              attempted_unm_credits = sum(attempted_credit, na.rm = TRUE),
              completed_unm_credits = sum(completed_credit, na.rm = TRUE),
              .groups = "drop"
            ) %>%
            arrange(student_id, term) %>%
            group_by(student_id) %>%
            mutate(
              cumulative_attempted_unm_credits = cumsum(attempted_unm_credits),
              cumulative_completed_unm_credits = cumsum(completed_unm_credits)
            ) %>%
            ungroup()
        }

        credit_required_cols <- c(
          "student_id", "term",
          "cumulative_attempted_unm_credits",
          "cumulative_completed_unm_credits"
        )
        observed_student_term_credits <- if (
          !is.null(cedar_student_term_credits) &&
            nrow(cedar_student_term_credits) > 0 &&
            all(credit_required_cols %in% names(cedar_student_term_credits))
        ) {
          cedar_student_term_credits %>%
            filter(student_id %in% pop_ids) %>%
            select(any_of(c(
              "student_id", "term",
              "cumulative_attempted_unm_credits",
              "cumulative_completed_unm_credits"
            )))
        } else {
          build_observed_credit_table()
        }

        build_pathways_with_observed_credits <- function(changes, credit_table, opt = list()) {
          min_n <- opt$min_n %||% 3L
          empty_result <- tibble(
            from_major = character(),
            to_major = character(),
            n_changes = integer(),
            median_completed_unm_credits = numeric(),
            median_attempted_unm_credits = numeric(),
            n_with_credit = integer()
          )
          if (is.null(changes) || nrow(changes) == 0) return(empty_result)

          event_credits <- changes %>%
            mutate(.event_id = row_number()) %>%
            select(.event_id, student_id, event_term = prev_term) %>%
            filter(!is.na(event_term)) %>%
            left_join(credit_table, by = "student_id", relationship = "many-to-many") %>%
            filter(!is.na(term), term <= event_term) %>%
            arrange(.event_id, student_id, term) %>%
            group_by(.event_id, student_id) %>%
            slice_tail(n = 1) %>%
            summarize(
              completed_unm_credits_before_switch = max(cumulative_completed_unm_credits, na.rm = TRUE),
              attempted_unm_credits_before_switch = max(cumulative_attempted_unm_credits, na.rm = TRUE),
              .groups = "drop"
            ) %>%
            mutate(
              across(
                c(completed_unm_credits_before_switch, attempted_unm_credits_before_switch),
                ~ if_else(is.infinite(.x), NA_real_, .x)
              )
            )

          changes %>%
            mutate(.event_id = row_number()) %>%
            left_join(event_credits, by = c(".event_id", "student_id")) %>%
            group_by(from_major, to_major) %>%
            summarize(
              n_changes = n(),
              median_completed_unm_credits = stats::median(
                completed_unm_credits_before_switch, na.rm = TRUE
              ),
              median_attempted_unm_credits = stats::median(
                attempted_unm_credits_before_switch, na.rm = TRUE
              ),
              n_with_credit = sum(!is.na(completed_unm_credits_before_switch)),
              .groups = "drop"
            ) %>%
            filter(n_changes >= min_n) %>%
            mutate(
              across(
                c(median_completed_unm_credits, median_attempted_unm_credits),
                ~ if_else(is.infinite(.x), NA_real_, .x)
              )
            ) %>%
            arrange(desc(n_changes), from_major, to_major)
        }

        pathways <- build_pathways_with_observed_credits(
          focal_changes, observed_student_term_credits, opt = opt
        )

        observed_unm_credit_at <- function(events, term_col, completed_col, attempted_col) {
          events %>%
            select(student_id, event_term = {{ term_col }}) %>%
            filter(!is.na(event_term)) %>%
            left_join(observed_student_term_credits, by = "student_id") %>%
            filter(!is.na(term), term <= event_term) %>%
            arrange(student_id, term) %>%
            group_by(student_id) %>%
            slice_tail(n = 1) %>%
            summarize(
              !!completed_col := max(cumulative_completed_unm_credits, na.rm = TRUE),
              !!attempted_col := max(cumulative_attempted_unm_credits, na.rm = TRUE),
              .groups = "drop"
            ) %>%
            mutate(
              across(
                all_of(c(completed_col, attempted_col)),
                ~ if_else(is.infinite(.x), NA_real_, .x)
              )
            )
        }

        observed_pre_credits <- observed_unm_credit_at(
          focal_milestones, first_pre_term,
          "pre_observed_completed_unm_credits",
          "pre_observed_attempted_unm_credits"
        )
        observed_full_credits <- observed_unm_credit_at(
          focal_milestones, first_full_term,
          "full_observed_completed_unm_credits",
          "full_observed_attempted_unm_credits"
        )
        observed_unit_credits <- observed_unm_credit_at(
          focal_milestones, first_unit_term,
          "first_unit_observed_completed_unm_credits",
          "first_unit_observed_attempted_unm_credits"
        )

        event_base <- event_base %>%
          left_join(observed_pre_credits, by = "student_id") %>%
          left_join(observed_full_credits, by = "student_id") %>%
          left_join(observed_unit_credits, by = "student_id")

        focal_departures <- focal_changes %>%
          filter(from_major %in% focal_programs, !(to_major %in% focal_programs))

        first_focal <- focal_departures %>%
          arrange(student_id, change_term) %>%
          group_by(student_id) %>%
          slice(1) %>%
          ungroup() %>%
          mutate(first_change_term = change_term) %>%
          left_join(event_base, by = "student_id")

        departure_prev_status <- focal_term_status %>%
          transmute(student_id, prev_term = term, departure_status = focal_status)

        first_focal <- first_focal %>%
          left_join(departure_prev_status, by = c("student_id", "prev_term")) %>%
          mutate(
            departure_status = coalesce(
              departure_status,
              if_else(!is.na(first_full_term) & first_full_term < first_change_term,
                      "full_major", "pre_major")
            ),
            terms_until = term_diff(first_unit_term, first_change_term)
          ) %>%
          left_join(
            observed_unm_credit_at(
              ., prev_term,
              "departure_observed_completed_unm_credits",
              "departure_observed_attempted_unm_credits"
            ),
            by = "student_id"
          )

        movement_events <- bind_rows(
          event_base %>%
            filter(!is.na(first_pre_term),
                   is.na(first_full_term) | first_pre_term < first_full_term) %>%
            transmute(
              event_group = "Entry",
              movement = "First pre-major declaration",
              origin_group,
              path_label = "Pre-major pathway",
              student_id,
              event_term = first_pre_term,
              term_basis = "from first observed class-list enrollment",
              credit_basis = "observed completed UNM credits through event term",
              terms = term_diff(first_unm_term, first_pre_term),
              unm_credits = pre_observed_completed_unm_credits,
              attempted_unm_credits = pre_observed_attempted_unm_credits,
              total_credits = pre_total_credits,
              first_program_unm_credits,
              first_unit_observed_attempted_unm_credits
            ),
          event_base %>%
            filter(!is.na(first_full_term),
                   is.na(first_pre_term) | first_full_term <= first_pre_term) %>%
            transmute(
              event_group = "Entry",
              movement = "Direct full-major declaration",
              origin_group,
              path_label = "No selected-unit pre-major observed",
              student_id,
              event_term = first_full_term,
              term_basis = "from first observed class-list enrollment",
              credit_basis = "observed completed UNM credits through event term",
              terms = term_diff(first_unm_term, first_full_term),
              unm_credits = full_observed_completed_unm_credits,
              attempted_unm_credits = full_observed_attempted_unm_credits,
              total_credits = full_total_credits,
              first_program_unm_credits,
              first_unit_observed_attempted_unm_credits
            ),
          event_base %>%
            filter(!is.na(first_pre_term), !is.na(first_full_term),
                   first_pre_term < first_full_term) %>%
            transmute(
              event_group = "Conversion",
              movement = "Pre-major to full major",
              origin_group,
              path_label = "Selected-unit pre-major converted",
              student_id,
              event_term = first_full_term,
              term_basis = "from first selected-unit pre-major",
              credit_basis = "observed completed UNM credits through full-major term",
              terms = term_diff(first_pre_term, first_full_term),
              unm_credits = full_observed_completed_unm_credits,
              attempted_unm_credits = full_observed_attempted_unm_credits,
              total_credits = full_total_credits,
              first_program_unm_credits,
              first_unit_observed_attempted_unm_credits
            ),
          first_focal %>%
            transmute(
              event_group = "Departure",
              movement = "Left for another major",
              origin_group,
              path_label = if_else(
                departure_status == "full_major",
                "Left after full-major record",
                "Left from pre-major record"
              ),
              student_id,
              event_term = first_change_term,
              term_basis = "from first selected-unit record",
              credit_basis = "observed completed UNM credits through prior term",
              terms = term_diff(first_unit_term, first_change_term),
              unm_credits = departure_observed_completed_unm_credits,
              attempted_unm_credits = departure_observed_attempted_unm_credits,
              total_credits = total_credits_before_change,
              first_program_unm_credits,
              first_unit_observed_attempted_unm_credits
            )
        ) %>%
          mutate(
            observability = case_when(
              event_term <= data_start_term ~ "Already present at data start",
              event_group == "Entry" &
                !is.na(first_unit_observed_attempted_unm_credits) &
                first_unit_observed_attempted_unm_credits > prior_unm_credit_threshold ~
                  "First observed with prior UNM credits",
              TRUE ~ "Observed during period"
            ),
            event_group = factor(event_group, levels = c("Entry", "Conversion", "Departure")),
            movement = factor(
              movement,
              levels = c(
                "First pre-major declaration",
                "Direct full-major declaration",
                "Pre-major to full major",
                "Left for another major"
              )
            ),
            origin_group = factor(origin_group, levels = c("Always UNM", "Transfer", "Unknown origin"))
          )

        headline_events <- movement_events %>%
          filter(observability == "Observed during period")

        movement_by_origin <- headline_events %>%
          group_by(event_group, movement, origin_group, term_basis, credit_basis) %>%
          summarize(
            n_students = n_distinct(student_id),
            median_terms = stats::median(terms, na.rm = TRUE),
            median_unm = stats::median(unm_credits, na.rm = TRUE),
            median_attempted_unm = stats::median(attempted_unm_credits, na.rm = TRUE),
            median_total = stats::median(total_credits, na.rm = TRUE),
            .groups = "drop"
          ) %>%
          arrange(event_group, movement, origin_group)

        movement_by_origin_path <- headline_events %>%
          group_by(event_group, movement, origin_group, path_label, term_basis, credit_basis) %>%
          summarize(
            n_students = n_distinct(student_id),
            median_terms = stats::median(terms, na.rm = TRUE),
            median_unm = stats::median(unm_credits, na.rm = TRUE),
            median_attempted_unm = stats::median(attempted_unm_credits, na.rm = TRUE),
            median_total = stats::median(total_credits, na.rm = TRUE),
            .groups = "drop"
          ) %>%
          arrange(event_group, movement, origin_group, path_label)

        movement_detail <- movement_events %>%
          group_by(event_group, movement, origin_group, path_label,
                   observability, term_basis, credit_basis) %>%
          summarize(
            n_students = n_distinct(student_id),
            median_terms = stats::median(terms, na.rm = TRUE),
            median_unm = stats::median(unm_credits, na.rm = TRUE),
            median_attempted_unm = stats::median(attempted_unm_credits, na.rm = TRUE),
            median_total = stats::median(total_credits, na.rm = TRUE),
            .groups = "drop"
          ) %>%
          arrange(event_group, movement, origin_group, path_label, observability)

        timing_by_entry <- first_focal %>%
          mutate(
            entry_status = first_unit_status,
            entry_status_label = case_when(
              first_unit_status == "pre_major" ~ "First selected-unit record was pre-major",
              first_unit_status == "full_major" ~ "First selected-unit record was full major",
              TRUE ~ "First selected-unit status unknown"
            ),
            terms_until = term_diff(first_unit_term, first_change_term)
          ) %>%
          group_by(entry_status, entry_status_label) %>%
          summarize(
            n_students = n_distinct(student_id),
            median_terms = stats::median(terms_until, na.rm = TRUE),
            median_unm = stats::median(unm_credits_before_change, na.rm = TRUE),
            median_total = stats::median(total_credits_before_change, na.rm = TRUE),
            n_late = sum(unm_credits_before_change > late_threshold, na.rm = TRUE),
            .groups = "drop"
          ) %>%
          mutate(
            late_pct = if_else(n_students > 0, 100 * n_late / n_students, NA_real_),
            sort_key = case_when(
              entry_status == "full_major" ~ 1L,
              entry_status == "pre_major" ~ 2L,
              TRUE ~ 3L
            )
          ) %>%
          arrange(sort_key) %>%
          select(-sort_key)

        entry_scope_events <- movement_events %>%
          filter(as.character(event_group) == "Entry") %>%
          distinct(student_id, observability)

        entry_exclusion <- entry_scope_events %>%
          filter(observability != "Observed during period") %>%
          count(observability, name = "n_students") %>%
          arrange(desc(n_students))

        movement_scope <- list(
          n_population = n_distinct(pop_ids),
          n_entry_total = n_distinct(entry_scope_events$student_id),
          n_entry_included = n_distinct(entry_scope_events$student_id[
            entry_scope_events$observability == "Observed during period"
          ]),
          n_entry_excluded = n_distinct(entry_scope_events$student_id[
            entry_scope_events$observability != "Observed during period"
          ]),
          entry_exclusion = entry_exclusion
        )

        # What departing students were taking in their last term on the old
        # major, measured against the same students' other terms. The baseline
        # is the whole point: without it the table is a ranking of large
        # required courses and every population "has a pattern".
        pre_change_courses <- get_pre_change_courses(
          focal_departures, students, get_analysis_population(), opt = opt
        )

        timing <- list(
        median_terms   = stats::median(first_focal$terms_until, na.rm = TRUE),
        median_unm     = stats::median(first_focal$unm_credits_before_change,   na.rm = TRUE),
        median_total   = stats::median(first_focal$total_credits_before_change, na.rm = TRUE),
          late_threshold = late_threshold,
          prior_unm_credit_threshold = prior_unm_credit_threshold,
          n_late         = sum(first_focal$unm_credits_before_change > late_threshold, na.rm = TRUE),
          n_events       = nrow(first_focal),
          by_entry       = timing_by_entry,
          movement_scope = movement_scope,
          movement_events = movement_events,
          movement_by_origin = movement_by_origin,
          movement_by_origin_path = movement_by_origin_path,
          movement_detail = movement_detail
        )

        list(changes = changes, focal_changes = focal_changes,
             pathways = pathways, focal_programs = focal_programs,
             decl_context = decl_context, timing = timing,
             pre_change_courses = pre_change_courses)
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

    output$mc_meta <- renderUI({
      if (!population_built()) {
        return(tags$span(class = "scope-bar-placeholder",
                         "Define a population to see Major Changes scope."))
      }

      data <- mc_data()
      if (is.null(data)) {
        return(tags$span(class = "scope-bar-placeholder",
                         "Major Changes scope is unavailable for this population."))
      }
      scope <- data$timing$movement_scope %||% NULL
      if (is.null(scope)) {
        return(tags$span(class = "scope-bar-placeholder",
                         "Major Changes scope will appear after the analysis is available."))
      }

      fmt_count <- function(x) format(as.integer(x %||% 0L), big.mark = ",")
      excluded <- scope$n_entry_excluded %||% 0L
      exclusion_bits <- character(0)
      if (is.data.frame(scope$entry_exclusion) && nrow(scope$entry_exclusion) > 0) {
        label_map <- c(
          "Already present at data start" = "already present at data start",
          "First observed with prior UNM credits" = "first selected-unit record after >30 class-list-derived attempted UNM credits"
        )
        exclusion_bits <- scope$entry_exclusion %>%
          mutate(
            label = coalesce(unname(label_map[as.character(observability)]), as.character(observability)),
            text = paste0(fmt_count(n_students), " ", label)
          ) %>%
          pull(text)
      }

      tags$p(
        tags$strong("Major Changes scope: "),
        fmt_count(scope$n_population), " students in the selected population. ",
        "Entry headline cards include ",
        tags$strong(fmt_count(scope$n_entry_included)),
        " students with reliable observed starts",
        if (excluded > 0) {
          tagList(
            "; ",
            tags$strong(fmt_count(excluded)),
            " are excluded from those entry headlines because starts are uncertain",
            if (length(exclusion_bits) > 0) {
              paste0(" (", paste(exclusion_bits, collapse = "; "), ")")
            },
            ". Excluded rows remain in Reference Tables."
          )
        } else {
          "."
        },
        " Transfer vs Always UNM is assigned from the Academic Studies Student Population ",
        "label; the 30-credit entry rule does not classify transfer origin."
      )
    })

    output$mc_changes_table <- reactable::renderReactable({
      req(!is.null(mc_data()))
      result <- mc_data()$changes
      if (is.null(result) || nrow(result) == 0)
        return(message_table("No major changes found for this population."))
      make_pathways_table(result, columns = numeric_col_defs(result, digits = 0, extra = list(
        unm_credits_before_change   = reactable::colDef(name = "UNM credits at change", align = "right"),
        total_credits_before_change = reactable::colDef(name = "Total credits at change", align = "right"),
        credits_position_valid      = reactable::colDef(name = "Credit position usable", align = "center",
          cell = function(value) if (isTRUE(value)) "\u2713" else if (isFALSE(value)) "\u2014" else "")
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
        median_completed_unm_credits = reactable::colDef(name = "Median completed UNM credits", align = "right"),
        median_attempted_unm_credits = reactable::colDef(name = "Median attempted UNM credits", align = "right"),
        n_with_credit = reactable::colDef(name = "Switches with credit data", align = "right",
                                          format = reactable::colFormat(digits = 0))
      )))
    })

    output$mc_pre_change_meta <- renderUI({
      req(!is.null(mc_data()))
      pcc <- mc_data()$pre_change_courses
      if (is.null(pcc) || pcc$n_switches == 0) return(NULL)

      fmt <- function(x) format(as.integer(x), big.mark = ",")

      # Both denominators are stated here, in words, right above the table. They
      # are not the same number and they are not the same unit, and a reader who
      # assumes otherwise misreads every row.
      # Say "matched", not "has coursework". A departure counted here can be a
      # student who took a full load and simply cannot be joined to the class
      # lists — see ISSUES.md I1. Reporting that as missing coursework blames the
      # student record for a defect in the ID hashing.
      unseen <- pcc$n_switches - pcc$n_switches_with_courses
      unseen_note <- if (unseen > 0) {
        paste0(" The other ", fmt(unseen),
               " could not be matched to any class-list record — check ",
               "Data & Usage → Join Integrity before reading much into these shares.")
      } else {
        ""
      }

      p(class = "text-hint",
        paste0(
          fmt(pcc$n_switches), " departures from the selected unit. “In their last term” is out of ",
          "the ", fmt(pcc$n_switches_with_courses),
          " of them whose coursework could be matched.", unseen_note,
          " “In a typical term” is measured across ", fmt(pcc$n_baseline_terms),
          " enrolled terms from the matchable students in this population, those who left and ",
          "those who stayed, leaving out the terms around a switch."
        )
      )
    })

    output$mc_pre_change_table <- reactable::renderReactable({
      req(!is.null(mc_data()))
      pcc <- mc_data()$pre_change_courses
      if (is.null(pcc) || pcc$n_switches == 0)
        return(message_table("No students switched out of the selected unit."))
      if (nrow(pcc$courses) == 0)
        return(message_table("No course was taken by enough departing students to show."))

      make_pathways_table(
        pcc$courses,
        page_size = 25,
        columns = list(
          subject_course = reactable::colDef(name = "Course", minWidth = 105,
            cell = function(value) htmltools::span(class = "fw-semibold", value)),
          course_title = reactable::colDef(name = "Title", minWidth = 200),
          n_switches = reactable::colDef(name = "Switches", align = "right", maxWidth = 100),
          pct_before_switch = reactable::colDef(name = "In their last term", align = "right",
            maxWidth = 140, format = reactable::colFormat(percent = TRUE, digits = 1)),
          pct_other_terms = reactable::colDef(name = "In a typical term", align = "right",
            maxWidth = 140, format = reactable::colFormat(percent = TRUE, digits = 1)),
          n_other_terms_with_course = reactable::colDef(
            name = "Typical-term count", align = "right", maxWidth = 130),
          ratio = reactable::colDef(
            name = "Times as likely", align = "right", maxWidth = 125,
            # Only the direction is colored, and only past a margin — a ratio of
            # 1.1 on a handful of students is noise, and shading it would invite
            # the causal reading the section is trying to head off.
            # Rendered with the × so the number reads as a multiple at a glance.
            # "1.5" invites being read as a percentage or a score; "1.5×" does not.
            cell = function(value) {
              if (is.na(value)) return("—")
              paste0(format(round(value, 1), nsmall = 1), "×")
            },
            style = function(value) {
              if (is.na(value) || value < 1.5) return(list(color = "#888"))
              list(color = "#c62828", fontWeight = "600")
            })
        )
      )
    })

    output$mc_summary_cards <- renderUI({
      req(!is.null(mc_data()))
      changes <- mc_data()$focal_changes
      focal   <- mc_data()$focal_programs %||% character(0)
      has_changes <- !is.null(changes) && nrow(changes) > 0
      if (!has_changes && is.null(mc_data()$timing)) return(NULL)

      n_changers <- if (has_changes) n_distinct(changes$student_id) else 0L

      change_row <- if (!has_changes) {
        NULL
      } else if (length(focal) == 1) {
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
            p("students switched programs", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card stat-card--left",
            tags$strong("Top arriving from other programs", class = "stat-lbl d-block mb-1"),
            make_top3(arriving_data)
          )),
          column(4, div(class = "stat-card stat-card--left",
            tags$strong("Top leaving for other programs", class = "stat-lbl d-block mb-1"),
            make_top3(leaving_data)
          ))
        )

      } else {
        top_from <- changes %>% count(from_major, sort = TRUE) %>% slice(1)
        top_to   <- changes %>% count(to_major,   sort = TRUE) %>% slice(1)

        fluidRow(
          column(4, div(class = "stat-card",
            p(n_changers, class = "stat-num"),
            p("students switched programs", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card",
            p(if (nrow(top_from) > 0) top_from$from_major else "—", class = "stat-num"),
            p("most common source program", class = "stat-lbl")
          )),
          column(4, div(class = "stat-card",
            p(if (nrow(top_to) > 0) top_to$to_major else "—", class = "stat-num"),
            p("most common destination program", class = "stat-lbl")
          ))
        )
      }

      tm <- mc_data()$timing

      # ── Major status movement ────────────────────────────────────────────────
      timing_row <- if (!is.null(tm)) {
        fmt_card_num <- function(x, digits = 0, suffix = "") {
          if (length(x) == 0 || is.na(x)) return("—")
          paste0(format(round(x, digits), nsmall = digits, trim = TRUE, big.mark = ","), suffix)
        }
        fmt_count <- function(x) format(as.integer(x %||% 0L), big.mark = ",")
        fmt_pct <- function(x) {
          if (length(x) == 0 || is.na(x)) return("—")
          paste0(format(round(x, 0), trim = TRUE), "%")
        }
        fmt_completed_unm_credits <- function(unm) {
          HTML(paste0(
            fmt_card_num(unm),
            " <span class='text-note'>completed UNM</span>"
          ))
        }

        origin_row_class <- function(origin) {
          case_when(
            as.character(origin) == "Always UNM" ~ "movement-origin-row movement-origin-row--always-unm",
            as.character(origin) == "Transfer" ~ "movement-origin-row movement-origin-row--transfer",
            TRUE ~ "movement-origin-row movement-origin-row--unknown"
          )
        }

        make_movement_rows <- function(rows, label_col = NULL) {
          if (!is.data.frame(rows) || nrow(rows) == 0) {
            return(p(class = "text-hint", "No students in this movement group."))
          }
          div(class = "movement-origin-stack", lapply(seq_len(nrow(rows)), function(i) {
            r <- rows[i, ]
            label <- if (!is.null(label_col)) as.character(r[[label_col]]) else NULL
            div(
              class = origin_row_class(r$origin_group),
              div(class = "movement-origin-copy",
                tags$strong(as.character(r$origin_group), class = "movement-origin-name"),
                if (!is.null(label)) tags$span(label, class = "movement-origin-path") else NULL
              ),
              div(class = "movement-origin-metrics",
                div(class = "movement-origin-metric",
                  tags$strong(fmt_count(r$n_students)),
                  tags$span("students")
                ),
                div(class = "movement-origin-metric",
                  tags$strong(fmt_card_num(r$median_terms)),
                  tags$span("median terms")
                ),
                div(class = "movement-origin-metric movement-origin-metric--wide",
                  tags$strong(fmt_completed_unm_credits(r$median_unm)),
                  tags$span("median completed credits")
                )
              )
            )
          }))
        }

        make_movement_card <- function(title, description, rows,
                                       label_col = NULL) {
          div(class = "stat-card stat-card--left movement-card",
            tags$strong(title, class = "movement-card-title"),
            p(description, class = "text-note"),
            make_movement_rows(rows, label_col = label_col)
          )
        }

        movement_summary <- tm$movement_by_origin
        path_summary <- tm$movement_by_origin_path
        rows_for_movement <- function(movement_name, source = movement_summary) {
          if (!is.data.frame(source) || nrow(source) == 0) return(source)
          source %>% filter(as.character(movement) == movement_name)
        }

        transition_cards <- list(
          make_movement_card(
            "First pre-major declaration",
            "First selected-unit pre-major records with a reliable observed class-list start term.",
            rows_for_movement("First pre-major declaration")
          ),
          make_movement_card(
            "Direct full-major declaration",
            "Students first observed in the selected unit as full majors, with no earlier selected-unit pre-major record.",
            rows_for_movement("Direct full-major declaration")
          ),
          make_movement_card(
            "Pre-major to full major",
            "Students with a selected-unit pre-major record who later appear as full majors. Median terms are counted from first selected-unit pre-major record.",
            rows_for_movement("Pre-major to full major")
          ),
          make_movement_card(
            "Left for another major",
            "First observed move from the selected unit to another major. Graduations are not included; credits are lag-adjusted to the prior term.",
            rows_for_movement("Left for another major", path_summary),
            label_col = "path_label"
          )
        )

        section_block(
          "When Students Enter, Convert, and Leave",
          description = tags$p(class = "text-hint",
            "Major status movement is built from selected-unit program records and split by ",
            "Always UNM versus Transfer. Entry cards exclude students already present at the ",
            "data-start term or first observed with substantial class-list-derived attempted ",
            "UNM credits, so uncertain records are not treated as new declarations."
          ),
          level = "h3",
          div(class = "movement-card-grid", transition_cards)
        )
      }

      # ── Major-change rule / term / credit-basis caveat ───────────────────────
      read_note <- div(class = "alert-box alert-box--info mt-2",
        tags$strong("How to read these counts"),
        tags$ul(class = "mt-1 mb-0",
          tags$li(HTML("All counts are limited to the selected population. Entry and conversion
                        cards describe major-status milestones inside the selected unit; departure
                        cards and switch charts describe moves that touch the selected unit.")),
          tags$li("A switch is any pair of back-to-back primary-major records where the student's declared program is different."),
          tags$li("Only switches that touch the selected unit are shown: students arriving into it, or leaving it for somewhere else."),
          tags$li("Moving from a pre-major to the full major in the same program does ", tags$em("not"), " count as a switch; switching to a different pre-major or major is counted."),
          tags$li("Undergraduate-to-graduate transitions are excluded."),
          tags$li(HTML("<strong>Median terms</strong> counts Spring/Fall steps only:
                        Spring → Fall = 1, Fall → Spring = 1, and summer is not
                        counted as an additional term.")),
          tags$li(HTML("The starting point depends on the event: entry rows count
                        from first observed class-list enrollment; pre-major → full-major
                        rows count from the first selected-unit pre-major record;
                        departure rows count from the first selected-unit record.")),
          tags$li(HTML("<strong>Transfer origin is not inferred from credits.</strong> Transfer
                        vs Always UNM comes from the earliest available Academic Studies
                        <code>student_population</code> label for the student. The separate
                        >30 attempted-UNM-credit rule controls entry-card eligibility only.")),
          tags$li(HTML("Movement-card credits are <strong>observed completed UNM credits</strong>
                        from Class Lists through the event term. Completed credits use the
                        standard credit-earning grade set and exclude W/F/non-credit outcomes.")),
          tags$li(HTML("The movement detail table also shows observed attempted UNM credits and
                        transfer-inclusive Academic Studies attempted credits. The latter are
                        kept as context, not as the source for movement-card UNM timing.")),
          tags$li(HTML("Entry and conversion rows count observed UNM credits through the event
                        term. Departure rows count observed UNM credits through the term before
                        the departure posts. Observed Class List credits do not include transfer
                        credits or UNM credits before the available CEDAR window.")),
          tags$li(HTML("Major changes typically post to Banner the term <em>after</em> the
                        student actually switches. Departure figures are
                        <strong>lag-adjusted</strong>: they use the observed credits through
                        the term <em>before</em> the change posted."))
        )
      )

      tagList(timing_row, read_note, change_row)
    })

    output$mc_movement_detail_table <- renderUI({
      req(!is.null(mc_data()))
      tm <- mc_data()$timing
      detail_summary <- tm$movement_detail %||% NULL

      fmt_card_num <- function(x, digits = 0) {
        if (length(x) == 0 || is.na(x)) return("—")
        format(round(x, digits), nsmall = digits, trim = TRUE, big.mark = ",")
      }
      fmt_count <- function(x) format(as.integer(x %||% 0L), big.mark = ",")
      fmt_completed_unm_credits <- function(unm) {
        HTML(paste0(
          fmt_card_num(unm),
          " <span class='text-note'>completed UNM</span>"
        ))
      }
      origin_row_class <- function(origin) {
        dplyr::case_when(
          as.character(origin) == "Always UNM" ~ "movement-origin-row movement-origin-row--always-unm",
          as.character(origin) == "Transfer" ~ "movement-origin-row movement-origin-row--transfer",
          TRUE ~ "movement-origin-row movement-origin-row--unknown"
        )
      }

      detail_rows <- if (is.data.frame(detail_summary) && nrow(detail_summary) > 0) {
        lapply(seq_len(nrow(detail_summary)), function(i) {
          r <- detail_summary[i, ]
          tags$tr(
            class = origin_row_class(r$origin_group),
            tags$td(as.character(r$event_group)),
            tags$td(as.character(r$movement)),
            tags$td(as.character(r$origin_group)),
            tags$td(as.character(r$path_label)),
            tags$td(as.character(r$observability)),
            tags$td(as.character(r$term_basis)),
            tags$td(as.character(r$credit_basis)),
            tags$td(fmt_count(r$n_students), class = "num"),
            tags$td(fmt_card_num(r$median_terms), class = "num"),
            tags$td(fmt_completed_unm_credits(r$median_unm), class = "num"),
            tags$td(fmt_card_num(r$median_attempted_unm), class = "num"),
            tags$td(fmt_card_num(r$median_total), class = "num")
          )
        })
      } else {
        list(tags$tr(tags$td(colspan = 12, "No movement rows available.")))
      }

      tags$div(class = "mt-2",
        tags$table(class = "table table-sm table-borderless movement-detail-table",
          tags$thead(tags$tr(
            tags$th("Group"),
            tags$th("Movement"),
            tags$th("Origin"),
            tags$th("Path"),
            tags$th("Observability"),
            tags$th("Term basis"),
            tags$th("Credit basis"),
            tags$th("Students"),
            tags$th("Median terms"),
            tags$th("Median completed UNM credits"),
            tags$th("Median attempted UNM credits"),
            tags$th("Median total attempted credits")
          )),
          tags$tbody(detail_rows)
        )
      )
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
        mutate(term_label = term_axis_factor(change_term))

      leaving <- changes %>%
        filter(from_major %in% focal) %>%
        count(change_term, name = "n") %>%
        right_join(all_terms, by = "change_term") %>%
        replace_na(list(n = 0)) %>%
        arrange(change_term) %>%
        mutate(term_label = term_axis_factor(change_term))

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
      p(paste0("Based on ", format(ctx$n_declarers, big.mark = ","),
               " students who reached full-major status in the selected unit."),
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
          group_cols     = c("campus", "subject_course", "course_title", "instructor_name")
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
        min_n   = as.integer(input$ge_min_n %||% 5L),
        campus  = if (length(input$ge_campus) > 0) input$ge_campus else NULL
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
        "Population: %s students. Showing %d in-unit and %d out-of-unit course×lag cells.",
        format(d$n_majors, big.mark = ","), n_in, n_out
      ), class = "text-hint")
    })

    .make_entry_heatmap <- function(d, title, n_majors,
                                    empty_msg = "No courses met the minimum threshold.") {
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
        return(empty_plot(empty_msg))

      lag_labels <- paste0("T-", sort(unique(d$lag)))
      d <- d %>%
        mutate(course_delivery = paste(subject_course, campus, sep = " · "))

      wide_pct <- d %>%
        select(course_delivery, lag_label, pct_of_majors) %>%
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
          "<b>%s</b><br>Campus: %s<br>%d of %d population students (%s%% of population) took this %s before entry",
          subject_course, campus, n_became_major, n_majors,
          formatC(100 * pct_of_majors, format = "f", digits = 1),
          lag_label
        )) %>%
        select(course_delivery, lag_label, txt) %>%
        tidyr::pivot_wider(names_from  = lag_label,
                           values_from = txt,
                           values_fill = "")

      wide_text <- wide_text[
        match(wide_pct$course_delivery, wide_text$course_delivery),
      ]

      z        <- as.matrix(wide_pct[, present_lags, drop = FALSE])
      text_mat <- as.matrix(wide_text[, present_lags, drop = FALSE])

      plot_ly(
        x    = present_lags,
        y    = wide_pct$course_delivery,
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
      d <- ge_conv_data()
      if (is.null(d)) {
        return(.make_entry_heatmap(
          NULL,
          "Courses from this unit (before major entry)",
          NA_integer_,
          empty_msg = "Run Course to Major to populate this heatmap."
        ))
      }
      .make_entry_heatmap(d$in_unit, "Courses from this unit (before major entry)", d$n_majors)
    })

    output$ge_heatmap_out <- renderPlotly({
      d <- ge_conv_data()
      if (is.null(d)) {
        return(.make_entry_heatmap(
          NULL,
          "Courses from other departments (before major entry)",
          NA_integer_,
          empty_msg = "Run Course to Major to populate this heatmap."
        ))
      }
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
      # Default To term = the shared observation boundary (last term with a
      # complete regular term of follow-up), not the newest term: a student
      # enrolled last term has had no time to "later enter" the department, so
      # including censored terms deflates Entry %. Users can still pick a more
      # recent term explicitly.
      ge_boundary <- pathways_observation_boundary(analysis_through, 1L)
      ge_to_default <- if (!is.null(ge_boundary) && any(to_terms <= ge_boundary)) {
        max(to_terms[to_terms <= ge_boundary])
      } else if (length(to_terms)) max(to_terms) else NULL
      updateSelectizeInput(session, "ge_from_term",
                           choices  = from_labels,
                           selected = if (length(from_terms)) min(from_terms) else NULL,
                           server   = TRUE)
      updateSelectizeInput(session, "ge_to_term",
                           choices  = to_labels,
                           selected = ge_to_default,
                           server   = TRUE)
    })

    output$ge_instructor_meta <- renderUI({
      d <- ge_instructor_data()
      if (is.null(d) || nrow(d) == 0) {
        if (isTruthy(input$ge_conv_run) && input$ge_conv_run > 0)
          return(p("No course + instructor groups met the minimum threshold.",
                   class = "text-hint"))
        return(tags$span(class = "scope-bar-placeholder", "Define a population, then Run to see scope."))
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
        "%d campus + course + instructor groups met the threshold. Distinct eligible pool: %s students; %s later entered the department (%s%%). Visible group memberships sum to %s eligible / %s later entered because students can appear in more than one campus + course + instructor group.",
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
          campus = reactable::colDef(name = "Campus", maxWidth = 90),
          subject_course = reactable::colDef(
            name = "Course", minWidth = 105,
            cell = function(value) htmltools::span(class = "fw-semibold", value)
          ),
          course_title = reactable::colDef(name = "Title", minWidth = 220),
          instructor_name = reactable::colDef(name = "Instructor", minWidth = 160),
          n_eligible = reactable::colDef(name = "Eligible", align = "right",
            maxWidth = 100),
          n_later_declared = reactable::colDef(name = "Later Entered", align = "right",
            maxWidth = 130),
          n_later_major = reactable::colDef(name = "Later Major", align = "right",
            maxWidth = 120),
          n_later_pre_major = reactable::colDef(name = "Later Pre-Major", align = "right",
            maxWidth = 145),
          median_terms_to_entry = reactable::colDef(
            name = "Median Terms", align = "right", maxWidth = 130,
            format = reactable::colFormat(digits = 1)
          ),
          declaration_pct = reactable::colDef(
            name = "Entry %", align = "right", maxWidth = 130,
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
