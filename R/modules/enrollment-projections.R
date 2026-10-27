# Shiny module for the read-only Registration > Projections workspace.
#
# The module consumes one validated saved bundle at a time, chosen by target
# term: CEDAR publishes one bundle per season, and neither supersedes the other.
# Discovery and loading are injected -- the module owns no paths and no file I/O.
# All forecasting, aftcasting, model selection, and explanation logic lives below
# the module layer.

enrollment_projection_method_guide_ui <- function(guide) {
  method_rows <- function(methods) {
    do.call(tagList, lapply(seq_len(nrow(methods)), function(i) {
      tagList(
        tags$dt(methods$method_label[[i]]),
        tags$dd(
          tags$span(methods$basis[[i]]),
          tags$span(
            class = "enrollment-projection-method-distinction",
            methods$distinction[[i]]
          )
        )
      )
    }))
  }

  family_sections <- do.call(tagList, lapply(guide$families, function(family) {
    tags$section(
      class = "enrollment-projection-method-family",
      tags$h4(family$label),
      tags$p(family$description),
      tags$p(
        class = "enrollment-projection-method-selection",
        tags$strong("Selection use: "), family$selection_note
      ),
      tags$dl(
        class = "enrollment-projection-method-list",
        method_rows(family$methods)
      )
    )
  }))

  info_panel(
    "Projection methods: the two forecasts, and how one is chosen",
    tags$p(guide$overview),
    family_sections,
    tags$p(
      tags$strong("How CEDAR manages the set. "),
      guide$selection_process
    ),
    cedar_docs_link(
      "users/enrollment-projections",
      label = "Full projection guide \u2192"
    ),
    description = guide$summary,
    class = "enrollment-projection-method-guide"
  )
}


# ---- Explainers ----------------------------------------------------------------
#
# The page's blue info panels each answer one question, named in the title,
# with the contents summarised in the description. Thresholds are read from
# the model defaults and the seat-fill constants, never written as literals.

projection_percent <- function(x) scales::percent(x, accuracy = 1)

# None/Unrated mean "not enough evidence", which is grey, never red: an
# unmeasured course has not failed anything. Shared by the table's axis
# columns and the course detail's headline badges.
projection_axis_badge <- function(value) {
  tone <- switch(
    value,
    Stable = , Deep = , High = "good",
    Moderate = "mid",
    Thin = "thin",
    Volatile = , Low = "poor",
    "none"
  )
  htmltools::span(
    value, class = paste0("projection-axis projection-axis--", tone)
  )
}

# The table sorts an axis column in the badge's order, weakest first on the
# first click, rather than alphabetically (which put Low between High and
# Moderate). None/Unrated sort last: unmeasured, not weak.
projection_axis_rank <- function(value) {
  unname(c(
    Volatile = 3, Low = 3, Thin = 3, Moderate = 2, Stable = 1, Deep = 1,
    High = 1
  )[value])
}

# Flags a reader should weigh before trusting the number, as against flags
# that say why the plan is what it is. Amber in the table, and sorted first.
projection_flag_is_warning <- function(flag) {
  grepl("^Fall enrollment|^Off 20%|^Past forecasts|^Hard to predict", flag)
}

# The plan, step by step from last year's class list to the sections
# (projection_plan_steps()): each number beside where it came from. Shown open
# in the course detail, because a plan a chair can check line by line is the
# point of the page.
projection_plan_steps_ui <- function(steps) {
  if (is.null(steps) || nrow(steps) == 0L) return(NULL)
  amount_text <- function(amount, kind) {
    whole <- format(abs(round(amount)), big.mark = ",")
    if (!identical(kind, "add")) return(format(round(amount), big.mark = ","))
    if (round(amount) > 0) paste0("+", whole) else if (round(amount) < 0) {
      paste0("\u2212", whole)
    } else "0"
  }
  section_block(
    "How this plan was built",
    description = paste(
      "Every number below comes from the saved projection; nothing is",
      "estimated when this window opens."
    ),
    tags$table(
      class = "enrollment-projection-steps",
      tags$tbody(lapply(seq_len(nrow(steps)), function(i) {
        tags$tr(
          class = paste0("enrollment-projection-step enrollment-projection-step--",
                         steps$kind[[i]]),
          tags$th(scope = "row", steps$label[[i]]),
          tags$td(class = "enrollment-projection-step-amount",
                  amount_text(steps$amount[[i]], steps$kind[[i]])),
          tags$td(class = "enrollment-projection-step-detail",
                  dplyr::coalesce(steps$detail[[i]], ""))
        )
      }))
    ),
    level = "h3",
    class = "enrollment-projection-steps-block"
  )
}

projection_axis_named_badge <- function(name, value) {
  htmltools::span(
    class = "enrollment-projection-axis-named",
    htmltools::span(class = "enrollment-projection-axis-name", name),
    projection_axis_badge(value)
  )
}

projection_columns_explainer <- function() {
  item <- function(name, ...) tags$li(tags$strong(name), paste0(" ", paste(...)))
  info_panel(
    "Reading the table: what each column means",
    tags$ul(
      item("Course", "with its academic department beneath."),
      item("Sections", "to plan: registrations plus what the plan adds,",
           "divided by the section size (the target schedule's average,",
           "otherwise the recent median), rounded up. \"Plan at least\" when",
           "last term filled its seats."),
      item("Plan adds", "are the registrations the plan adds to the",
           "projection: the change in the course's feeder courses in the term",
           "just finished, up or down, and a pressure bump for a course that is",
           "always full, with the sections they add beneath. A dash means",
           "neither; the course's detail says why."),
      item("Registrations", "is everyone expected to sign up, including",
           "students who drop: the number the model forecasts and sections are",
           "planned for. Beneath it, the range past forecasts usually landed in,",
           "which assumes seats like last year's; a course's detail says when",
           "the draft schedule moves them."),
      item("Seats (day 1)", "is the students expected in a seat when classes",
           "begin. It is context, not the planning number."),
      item("First day / sections", "shows the last four same-season terms. A",
           "dash means the course was not offered or its first day cannot be",
           "reconstructed."),
      item("Flags", "are plain-language reasons to look at a row."),
      item("Stability", "asks whether the course's own enrollment history is",
           "steady, using no model."),
      item("Depth", "is how many past forecasts stand behind the course's",
           "reliability: it says how much we know, not how good we are."),
      item("Reliability", "is how close those past forecasts landed: High",
           "within 10%, Moderate 10 to 20%, Low more than 20% off. Each was",
           "made with only the evidence available at the time."),
      item("Seat consistency", "is how steady the course's seats were in those",
           "same terms: High when they held within 10% every time, Moderate",
           "when they moved once, Low when they moved more.")
    ),
    tags$p(tags$strong("Reading reliability and seat consistency together"), class = "mb-1"),
    tags$ul(
      tags$li(tags$strong("Low reliability, low or moderate seat consistency:"),
              " the misses came in terms when the seats moved. They follow the",
              " schedule more than demand, so the projection holds if the seats do."),
      tags$li(tags$strong("Low reliability, high seat consistency:"),
              " the course missed with steady seats. That miss is the",
              " forecast's: look before planning to it. Flagged \"Off 20%+",
              " with steady seats\"."),
      tags$li(tags$strong("High reliability:"), " past forecasts landed close."),
      tags$li(tags$strong("Unrated:"), " too few past forecasts to tell.")
    ),
    description = "Every column, and how Reliability and Seat consistency read together.",
    class = "enrollment-projection-guide"
  )
}

# `shown` is a slot for what the bump and the feeder adjustment add across
# the courses on the page, rendered in the server from the loaded bundle.
projection_build_explainer <- function(shown = NULL) {
  defaults <- enrollment_projection_defaults()
  info_panel(
    "How a course's plan is built, step by step",
    tags$ol(
      tags$li(tags$strong("Last year's registrations."),
              " The start is the same season last year: everyone who registered,",
              " including students who dropped. When the schedule holds still it",
              " lands within about 6%, and no other forecast tested beat it."),
      tags$li(tags$strong("A floor for full courses."), paste0(
        " When last term was near full (", projection_percent(CEDAR_NEAR_FULL_FILL),
        " or more of the seats taken on the first day), the students still",
        " waiting, who registered nowhere in the market, are added to it in",
        " the adjusted forecast."
      )),
      tags$li(tags$strong("Fall changes."),
              " The adjusted forecast also adds the change in the course's own",
              " and its feeder courses' enrollment in the term just finished, times",
              " the share that historically carried over. A course listed as the",
              " one taken just before (Composition I before II, say) carries its",
              " change at its own rate. Two terms ahead, that term has not",
              " happened yet, so the change is left out and the course's detail",
              " says so."),
      tags$li(tags$strong("Choosing a forecast."), paste0(
        " Last year's number is used unless the adjusted forecast beat it by ",
        defaults$selection_challenger_margin * 100, " points of error on at least ",
        defaults$selection_min_backtests, " earlier past forecasts, judged at",
        " each past term with only the evidence available then."
      )),
      tags$li(tags$strong("The feeder adjustment."), paste0(
        " When last year's number is the forecast, a Spring plan still follows",
        " the Fall just finished: the listed predecessor's change always counts,",
        " and the other feeder courses' change counts when they moved ",
        projection_percent(defaults$plan_feeder_change),
        " or more, either way, each times the share that historically carried",
        " over. Smaller moves are noise against a course's own year. When the",
        " adjusted forecast is published it already holds these changes, and",
        " the plan adds nothing. A Fall plan does not follow its feeders:",
        " following them made past Spring forecasts closer and past Fall",
        " forecasts no closer, because a Spring feeder's change pointed the way",
        " the Fall course moved no more often than chance."
      )),
      tags$li(tags$strong("A pressure bump for courses always full."), paste0(
        " A course near full on the first day in every recent same-season term",
        " with a first-day count is planned for ",
        projection_percent(defaults$pressure_bump_share),
        " more, or for the students left waiting if that is more. A full",
        " course's registrations follow its seats, so last year's count",
        " understates what it would draw, and that backlog stays whatever its",
        " feeders do. It changes the plan, never the forecast or its",
        " reliability."
      )),
      tags$li(tags$strong("Sections."),
              " Registrations plus what the plan adds, divided by the section size",
              " and rounded up. Registrations run about 8% above the students in a",
              " seat on day one, and that margin is deliberate: running short of",
              " seats costs more than an empty one.")
    ),
    if (!is.null(shown)) tagList(
      tags$p(tags$strong("For the courses shown"), class = "mb-1"),
      shown
    ),
    tags$p(paste0(
      "Whether seats were full is judged on the first day of classes, from",
      " each student's registration and drop dates: near full at ",
      projection_percent(CEDAR_NEAR_FULL_FILL), ", full at ",
      projection_percent(CEDAR_FULL_FILL), ". Census, three weeks later, follows",
      " the drops, so a course full on day one can read below capacity there.",
      " A term whose class lists carry no status dates is shown as unknown,",
      " never filled in from census. So is a term pulled before one of its",
      " later sessions began, unless the sessions that had begun already fill ",
      projection_percent(CEDAR_NEAR_FULL_FILL), " of all its seats."
    )),
    cedar_definition_note("enrollment-projection"),
    cedar_docs_link("users/enrollment-projections"),
    description = "From last year's registrations to sections: every step, and why it is there.",
    class = "enrollment-projection-build"
  )
}

# Built from the bundle's saved aftcasts, so it is rendered in the server.
projection_error_explainer <- function(error_sources, range_coverage) {
  sources <- error_sources$table
  rows <- lapply(seq_len(nrow(sources)), function(i) {
    row <- sources[i, , drop = FALSE]
    tags$li(
      tags$strong(row$label), " \u2014 ",
      if (row$folds > 0L) paste0(
        format(row$folds, big.mark = ","), " past forecast",
        if (row$folds == 1L) "" else "s", ", ",
        scales::percent(row$wape, accuracy = 0.1), " off on average, ",
        projection_percent(row$share_of_error), " of all the error. "
      ) else "none. ",
      row$meaning
    )
  })
  info_panel(
    "Where forecast error comes from",
    tags$p(error_sources$sentence),
    tags$ul(rows),
    tags$p(tags$strong("The range"), class = "mb-1"),
    tags$p(range_coverage$sentence),
    tags$p(tags$strong("What the projection cannot see"), class = "mb-1"),
    tags$ul(
      tags$li("Next year's schedule. Compare the plan with the draft on the",
              " Draft schedule tab."),
      tags$li("Policy changes, such as new placement cutoffs or requirements."),
      tags$li("How many students a full course turned away. The pressure bump",
              " stands in for it until waitlists can measure it."),
      tags$li("Terms whose class lists carry no status dates, or were pulled",
              " before a later session began.")
    ),
    tags$p(
      "To judge one course, read its Reliability beside its Seat consistency:",
      " a miss with steady seats is the forecast's; a miss as seats moved is",
      " mostly the schedule's."
    ),
    description = paste0(
      "Past misses by cause, from ", format(error_sources$n_folds, big.mark = ","),
      " past forecasts: most follow schedule changes, not demand."
    ),
    class = "enrollment-projection-error-sources"
  )
}

projection_draft_explainer <- function() {
  info_panel(
    "How the draft comparison works",
    tags$ul(
      tags$li(tags$strong("The draft"),
              " is the target term's schedule as MyReports had it on the date",
              " shown. Departments edit it until registration settles; the",
              " comparison follows at the next refresh."),
      tags$li(tags$strong("Planned registrations"),
              " are the projection plus any pressure bump. They run above the",
              " students expected in a seat on day one, on purpose."),
      tags$li(tags$strong("Short of day-one seats:"),
              " the draft has fewer seats than the students expected in the room",
              " when classes begin. This is the one to fix first."),
      tags$li(tags$strong("Covers day one, short of the plan:"),
              " only the planning margin or the pressure bump is missing."),
      tags$li(tags$strong("Covers the plan"), " or ", tags$strong("seats beyond the plan"),
              ": the draft meets the plan, or exceeds it by more than a section.",
              " In a course that is always full, spare seats are likely to fill:",
              " when such courses were given more seats, the new seats filled."),
      tags$li(tags$strong("Not in the draft:"),
              " a monitored course with a projection and no sections yet.")
    ),
    tags$p("The campus split under the draft sections comes from the schedule;",
           " the plan itself pools Albuquerque and online seats."),
    description = "What the draft is, what \"short\" means, and why a spare seat in a full course is not waste.",
    class = "enrollment-projection-draft-guide"
  )
}


enrollmentProjectionsUI <- function(id) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Enrollment Projections",
      paste(
        "Saved course-demand projections with stability, evidence depth,",
        "reliability, seat consistency, planning guidance, and row-level detail."
      ),
      # No rating or flag filters: the table sorts by each column and its
      # search box matches flag and rating text.
      fluidRow(
        column(
          3,
          selectInput(ns("target_term"), "Target term", choices = NULL)
        ),
        column(
          3,
          selectInput(
            ns("group"), "Course group",
            choices = enrollment_projection_group_choices(),
            selected = "always_monitored"
          )
        ),
        column(
          3,
          selectizeInput(
            ns("department"), "Department", multiple = TRUE, choices = NULL
          )
        ),
        column(
          3,
          selectizeInput(
            ns("course"), "Course", multiple = TRUE, choices = NULL
          )
        )
      ),
      filter_scope_stripe(uiOutput(ns("scope"))),
      class = "enrollment-projection-filters"
    ),
    uiOutput(ns("bundle_status")),
    tags$p(
      class = "enrollment-projection-lead",
      paste(
        "Each row plans one course for the target term. Sections are planned",
        "for registrations, which start from last year's same-term",
        "registrations; a Spring plan follows a clear change in its feeder",
        "courses the Fall before, a course that is always full gets a",
        "pressure bump on top, and a course whose enrollment moved sharply is",
        "flagged for a look. The range is where past forecasts",
        "for that course usually landed, and it assumes seats like last",
        "year's. Click any course to see how its plan was built, step by",
        "step, and how close past forecasts for it came."
      )
    ),
    # Each explainer answers one question a reader brings to the page, and
    # its title says which. The methods guide sits below the table.
    projection_columns_explainer(),
    projection_build_explainer(uiOutput(ns("pressure_summary"))),
    uiOutput(ns("error_sources")),
    navset_tab(
      id = ns("projection_tabs"),
      selected = "Projections",

      nav_panel(
        "Projections",
        subtab_header(
          "Projections",
          paste(
            "One published projection per course for the selected target term,",
            "opening with the courses whose plans add the most to last year;",
            "click any header to sort by it instead. Click a course to see how",
            "its plan was built, step by step, with the evidence behind each step."
          )
        ),
        tags$div(
          class = "enrollment-projection-table-flow cedar-clickable-rows",
          reactable::reactableOutput(ns("projection_table"), height = NULL)
        ),
        uiOutput(ns("method_guide"))
      ),

      nav_panel(
        "Draft schedule",
        subtab_header(
          "Compare to the draft schedule",
          paste(
            "The plan beside the target term's schedule as it stands, course by",
            "course: where the draft falls short of the students expected on day",
            "one, where it covers the plan, and which monitored courses it lacks."
          )
        ),
        uiOutput(ns("draft_summary")),
        projection_draft_explainer(),
        tags$div(
          class = "enrollment-projection-table-flow cedar-clickable-rows",
          reactable::reactableOutput(ns("draft_table"), height = NULL)
        )
      ),

      nav_panel(
        "Scenario",
        subtab_header(
          "Population growth scenario",
          paste(
            "Grows one student population and reads the effect on the courses",
            "it takes. The first year is the published projection above;",
            "later years are arithmetic on it, not forecasts."
          )
        ),
        fluidRow(
          column(
            3,
            selectInput(
              ns("scenario_population"), "Population",
              choices = population_group_choices(),
              selected = population_group_default("scenario")
            )
          ),
          column(
            2,
            numericInput(
              ns("scenario_growth"), "Annual growth (%)",
              value = 10, min = -50, max = 100, step = 1
            )
          ),
          column(
            2,
            sliderInput(
              ns("scenario_horizon"), "Years", min = 2, max = 10,
              value = 5, step = 1, ticks = FALSE
            )
          ),
          column(
            3,
            selectInput(
              ns("scenario_measure"), "Show",
              choices = c(
                "Students" = "students",
                "Sections needed" = "sections",
                "Additional sections" = "additional"
              )
            )
          ),
          column(
            2,
            tags$div(
              class = "enrollment-projection-export",
              downloadButton(
                ns("scenario_download"), label = NULL, icon = icon("download"),
                title = "Export the scenario table",
                class = "btn-outline-secondary btn-sm"
              )
            )
          )
        ),
        uiOutput(ns("scenario_assumption")),
        tags$div(
          class = "enrollment-projection-table-flow",
          reactable::reactableOutput(ns("scenario_table"), height = NULL)
        ),
        uiOutput(ns("scenario_excluded"))
      )
    )
  )
}


enrollmentProjectionsServer <- function(id, bundles, load_bundle, programs) {
  moduleServer(id, function(input, output, session) {
    saved_bundles <- reactive({
      if (shiny::is.reactive(bundles) || is.function(bundles)) bundles() else bundles
    })

    # The reader picks a season. The nearest target is selected by default: it
    # is the term a schedule is being built for now.
    observeEvent(saved_bundles(), {
      saved <- saved_bundles()
      if (is.null(saved) || nrow(saved) == 0L) {
        updateSelectInput(session, "target_term", choices = character(0))
        return()
      }
      saved <- saved[order(saved$target_term), , drop = FALSE]
      choices <- stats::setNames(
        as.character(saved$target_term), fmt_term(saved$target_term)
      )
      selected <- if (isTRUE(input$target_term %in% choices)) {
        input$target_term
      } else {
        choices[[1]]
      }
      updateSelectInput(session, "target_term", choices = choices, selected = selected)
    }, ignoreNULL = FALSE)

    bundle_value <- reactive({
      saved <- saved_bundles()
      if (is.null(saved) || nrow(saved) == 0L) return(NULL)
      req(input$target_term)
      # A saved file that this build cannot read is an empty state, not a stack
      # trace. It happens for real: a deploy restarts the app on new code before
      # the bundles are rebuilt, so after a schema bump the page spends the whole
      # rebuild -- 38 minutes on the last one -- holding artifacts it will not
      # accept. The reader gets the ordinary "no bundle available" panel and one
      # notification saying why, rather than an error where the table belongs.
      tryCatch(
        {
          value <- load_bundle(as.integer(input$target_term))
          if (!is.null(value)) validate_enrollment_projection_bundle(value)
          value
        },
        error = function(e) {
          showNotification(
            paste0(
              "The saved projection for ", fmt_term(as.integer(input$target_term)),
              " cannot be read by this version of CEDAR: ", conditionMessage(e)
            ),
            type = "warning", duration = 12
          )
          NULL
        }
      )
    })

    observeEvent(bundle_value(), {
      value <- bundle_value()
      if (is.null(value)) return()
      choices <- enrollment_projection_filter_choices(
        value,
        list(group_id = input$group %||% "always_monitored")
      )
      updateSelectizeInput(
        session, "department", choices = choices$departments,
        selected = intersect(input$department %||% character(0), choices$departments),
        server = TRUE
      )
      updateSelectizeInput(
        session, "course", choices = choices$courses,
        selected = intersect(input$course %||% character(0), choices$courses),
        server = TRUE
      )
    }, ignoreNULL = FALSE)

    observeEvent(input$group, {
      value <- bundle_value()
      if (is.null(value)) return()
      choices <- enrollment_projection_filter_choices(
        value, list(group_id = input$group)
      )
      updateSelectizeInput(
        session, "department", choices = choices$departments,
        selected = intersect(input$department %||% character(0), choices$departments),
        server = TRUE
      )
    }, ignoreInit = TRUE)

    observeEvent(list(input$group, input$department), {
      value <- bundle_value()
      if (is.null(value)) return()
      choices <- enrollment_projection_filter_choices(
        value,
        list(group_id = input$group, departments = input$department)
      )
      updateSelectizeInput(
        session, "course", choices = choices$courses,
        selected = intersect(input$course %||% character(0), choices$courses),
        server = TRUE
      )
    }, ignoreInit = TRUE)

    view <- reactive({
      value <- bundle_value()
      req(!is.null(value))
      build_enrollment_projection_view(
        value,
        list(
          group_id = input$group %||% "always_monitored",
          departments = input$department,
          courses = input$course
        )
      )
    })

    axis_cell <- projection_axis_badge

    flag_cell <- function(value) {
      if (is.na(value) || !nzchar(value)) return("\u2014")
      flags <- strsplit(value, " | ", fixed = TRUE)[[1]]
      htmltools::tagList(lapply(flags, function(flag) {
        warn <- projection_flag_is_warning(flag)
        htmltools::span(
          flag,
          class = paste(c("projection-flag", if (warn) "projection-flag--warn"),
                        collapse = " ")
        )
      }))
    }

    output$bundle_status <- renderUI({
      saved <- saved_bundles()
      # Short-circuits before bundle_value(), so an empty projections directory
      # reports itself rather than being blocked by the target-term req().
      if (!is.null(saved) && nrow(saved) > 0L && !is.null(bundle_value())) {
        return(NULL)
      }
      empty_state("No validated enrollment projection bundle is available.")
    })

    output$pressure_summary <- renderUI({
      tags$p(
        view()$meta$pressure_bump$sentence, " ",
        view()$meta$plan_feeder$sentence
      )
    })

    output$scope <- renderUI({
      data <- view()
      provenance <- data$meta$model_provenance
      commit <- provenance$git_commit
      commit_label <- if (length(commit) == 1L && !is.na(commit)) {
        substr(commit, 1L, 8L)
      } else {
        "unavailable"
      }
      worktree_label <- if (isTRUE(provenance$relevant_worktree_dirty)) {
        "model files had uncommitted changes at build time"
      } else if (identical(provenance$relevant_worktree_dirty, FALSE)) {
        "model files matched the recorded Git commit"
      } else {
        "Git worktree status was unavailable"
      }
      model_note <- paste0(
        "Model ", data$meta$model_version, "; Git ", commit_label, "; ",
        worktree_label, ". Exact normalized model source is embedded in the saved bundle."
      )
      tagList(
        tags$div(
          class = "scope-bar",
          tags$strong(data$meta$target_term_label),
          " demand | Data window: ", data$meta$history_start_term_label,
          " through ", data$meta$as_of_term_label,
          " | ABQ + EA | ", data$meta$n_rows,
          paste0(" course", if (data$meta$n_rows == 1L) "" else "s"),
          " | model ", data$meta$model_version,
          tags$span(
            class = "enrollment-projection-model-info",
            title = model_note,
            `aria-label` = model_note,
            icon("circle-info")
          )
        )
      )
    })

    output$projection_table <- reactable::renderReactable({
      projection_view <- view()
      data <- projection_view$table
      if (nrow(data) == 0L) return(NULL)
      season <- projection_view$meta$season_label
      history_terms <- projection_view$meta$summary_history_columns
      count_text <- function(value) {
        if (is.finite(value)) format(round(value), big.mark = ",") else "—"
      }
      # Sort keys, so a header click orders by meaning rather than by the
      # alphabet. Each sits where its column shows and renders that column's
      # label, which stays searchable in its own hidden column.
      flag_lists <- lapply(strsplit(data$flags, " | ", fixed = TRUE), function(f) f[nzchar(f)])
      data <- data %>%
        dplyr::mutate(
          # The plan's change from last year's registrations, either way: most
          # forecasts are last year's number, so what the plan adds is the
          # change. The table opens on it.
          plan_adds_size = abs(plan_feeder_adjustment + pressure_bump),
          # Warnings first, then the number of flags.
          flags_order = vapply(flag_lists, function(f) {
            100 * sum(projection_flag_is_warning(f)) + length(f)
          }, numeric(1)),
          dplyr::across(
            c(stability, depth, accuracy, seat_consistency),
            projection_axis_rank, .names = "{.col}_order"
          )
        ) %>%
        dplyr::relocate(plan_adds_size, .before = pressure_bump) %>%
        dplyr::relocate(flags_order, .before = flags) %>%
        dplyr::relocate(stability_order, .before = stability) %>%
        dplyr::relocate(depth_order, .before = depth) %>%
        dplyr::relocate(accuracy_order, .before = accuracy) %>%
        dplyr::relocate(seat_consistency_order, .before = seat_consistency)
      axis_column <- function(axis, ...) {
        reactable::colDef(
          ..., searchable = FALSE, defaultSortOrder = "desc", sortNALast = TRUE,
          cell = function(value, index) axis_cell(data[[axis]][[index]])
        )
      }
      # A row click opens the course's evidence in a modal over the table. The
      # table is unpaginated, and evidence rendered beneath it read as a click
      # that did nothing (reported twice); a modal also returns the reader to
      # the row they left.
      select_course <- htmlwidgets::JS(sprintf(
        paste0(
          "function(rowInfo) {",
          "Shiny.setInputValue('%s', rowInfo.values.course, {priority: 'event'});",
          "}"
        ),
        session$ns("selected_course")
      ))
      # Sized to fit a laptop-width window without horizontal scrolling: the
      # department sits under the course, the range under the registrations,
      # and the method and its evidence in the modal. Course,
      # Sections and Seats have fixed widths so a wide window stretches the
      # evidence columns instead of them.
      reactable::reactable(
        data,
        theme = cedar_tbl_theme,
        compact = TRUE,
        striped = TRUE,
        highlight = TRUE,
        searchable = TRUE,
        onClick = select_course,
        pagination = FALSE,
        # Ties (most courses add nothing) stay alphabetical.
        defaultSorted = list(plan_adds_size = "desc", course = "asc"),
        columns = list(
          course = reactable::colDef(
            name = "Course", width = 96,
            cell = function(value, index) {
              htmltools::tagList(
                htmltools::strong(value),
                htmltools::div(class = "text-note", data$department[[index]])
              )
            }
          ),
          department = reactable::colDef(show = FALSE, searchable = TRUE),
          planning_sections = reactable::colDef(
            name = "Sections", align = "right", width = 70,
            headerStyle = list(whiteSpace = "nowrap"),
            header = htmltools::span(
              "Sections",
              title = paste(
                "Sections to plan: registrations plus what the plan adds,",
                "divided by the section size and rounded up; a floor when last",
                "term filled its seats"
              )
            ),
            format = reactable::colFormat(separators = TRUE, digits = 0),
            na = "—"
          ),
          plan_adds_size = reactable::colDef(
            name = "Plan adds", align = "right", minWidth = 90,
            searchable = FALSE, defaultSortOrder = "desc", sortNALast = TRUE,
            header = htmltools::span(
              "Plan adds",
              title = paste(
                "Registrations the plan adds to the projection: the change in",
                "its feeder courses in the term just finished, and a pressure",
                "bump when the course was near full on the first day in every",
                "recent same-season term; beneath, the sections they add.",
                "Most projections are last year's registrations, so this is",
                "the plan's change from last year. The table opens sorted by",
                "it, largest first, up or down. Click the course for why"
              )
            ),
            cell = function(value, index) {
              bump <- data$pressure_bump[[index]]
              feeder <- data$plan_feeder_adjustment[[index]]
              bumped <- isTRUE(bump > 0)
              fed <- isTRUE(feeder != 0)
              if (!bumped && !fed) return("—")
              added <- sum(
                if (fed) data$plan_feeder_sections[[index]] else 0L,
                if (bumped) data$pressure_bump_sections[[index]] else 0L,
                na.rm = TRUE
              )
              htmltools::tagList(
                if (fed) htmltools::div(sprintf("%+.0f feeders", feeder)),
                if (bumped) htmltools::div(paste0("+", count_text(bump), " bump")),
                if (added != 0L) {
                  htmltools::div(
                    class = "text-note",
                    paste0(if (added > 0L) "+" else "\u2212", abs(added),
                           " section", if (abs(added) == 1L) "" else "s")
                  )
                }
              )
            }
          ),
          pressure_bump = reactable::colDef(show = FALSE),
          pressure_bump_sections = reactable::colDef(show = FALSE),
          pressure_bump_note = reactable::colDef(show = FALSE),
          plan_feeder_adjustment = reactable::colDef(show = FALSE),
          plan_feeder_sections = reactable::colDef(show = FALSE),
          plan_feeder_note = reactable::colDef(show = FALSE),
          projected_demand = reactable::colDef(
            name = "Registrations", align = "right", minWidth = 120,
            headerStyle = list(whiteSpace = "nowrap"),
            header = htmltools::span(
              "Registrations",
              title = paste(
                "Everyone expected to register, including students who later",
                "drop: the number sections are planned for. Beneath it, the",
                "range past forecasts for this course usually landed in"
              )
            ),
            cell = function(value, index) {
              htmltools::tagList(
                count_text(value),
                # The seat-change note behind the range is in the course detail.
                if (!is.na(data$demand_range[[index]])) {
                  htmltools::div(class = "text-note", data$demand_range[[index]])
                }
              )
            }
          ),
          demand_range = reactable::colDef(show = FALSE),
          range_note = reactable::colDef(show = FALSE),
          expected_first_day = reactable::colDef(
            name = "Seats (day 1)", align = "right", width = 64,
            header = htmltools::span(
              "Seats", htmltools::div("(day 1)"),
              title = paste(
                "Students expected to hold a seat when classes begin. Fewer",
                "than registrations, because a student who drops early frees",
                "a seat someone else takes"
              )
            ),
            cell = function(value, index) count_text(value)
          ),
          recent_first_day = reactable::colDef(
            name = paste("Last", season, "terms"), minWidth = 220,
            sortable = FALSE, searchable = FALSE,
            header = htmltools::tagList(
              htmltools::div("First day / sections"),
              htmltools::div(paste0("(last ", nrow(history_terms), " ", season, "s)")),
              htmltools::div(
                class = "projection-history-grid text-note",
                lapply(history_terms$abbr, htmltools::span)
              )
            ),
            cell = function(value, index) {
              sections <- data$recent_sections[[index]]
              htmltools::div(
                class = "projection-history-grid",
                title = data$recent_terms[[index]],
                lapply(seq_along(value), function(i) {
                  htmltools::span(
                    count_text(value[[i]]),
                    htmltools::span(
                      class = "text-note",
                      if (is.finite(sections[[i]])) paste(sections[[i]], "sec") else "—"
                    )
                  )
                })
              )
            }
          ),
          recent_sections = reactable::colDef(show = FALSE),
          recent_terms = reactable::colDef(show = FALSE),
          flags_order = reactable::colDef(
            name = "Flags", minWidth = 160,
            searchable = FALSE, defaultSortOrder = "desc",
            header = htmltools::span(
              "Flags", title = "Sorts warnings (amber) first, then by how many flags"
            ),
            cell = function(value, index) flag_cell(data$flags[[index]])
          ),
          flags = reactable::colDef(show = FALSE, searchable = TRUE),
          attention = reactable::colDef(show = FALSE),
          stability_order = axis_column("stability", name = "Stability", minWidth = 80),
          stability = reactable::colDef(show = FALSE, searchable = TRUE),
          stability_reason = reactable::colDef(show = FALSE),
          depth_order = axis_column("depth", name = "Depth", minWidth = 64),
          depth = reactable::colDef(show = FALSE, searchable = TRUE),
          depth_reason = reactable::colDef(show = FALSE),
          accuracy_order = axis_column(
            "accuracy", name = "Reliability", minWidth = 85,
            header = htmltools::span(
              "Reliability",
              title = paste(
                "How close past forecasts for this course landed: High within",
                "10%, Moderate 10 to 20%, Low more than 20% off. Read it beside",
                "seat consistency"
              )
            )
          ),
          accuracy = reactable::colDef(show = FALSE, searchable = TRUE),
          accuracy_reason = reactable::colDef(show = FALSE),
          seat_consistency_order = axis_column(
            "seat_consistency", name = "Seat consistency", minWidth = 105,
            header = htmltools::span(
              "Seat consistency",
              title = paste(
                "How steady the course's seats were in those same past terms. A",
                "low reliability with steady seats is the forecast's miss; with",
                "moving seats, mostly the schedule's"
              )
            )
          ),
          seat_consistency = reactable::colDef(show = FALSE, searchable = TRUE),
          seat_consistency_reason = reactable::colDef(show = FALSE),
          reliability_reading = reactable::colDef(show = FALSE),
          # The basis and its evidence are in the course modal.
          method = reactable::colDef(show = FALSE),
          selection_evidence = reactable::colDef(show = FALSE),
          summary_sentence = reactable::colDef(show = FALSE),
          axis_brief = reactable::colDef(show = FALSE),
          axis_explanation = reactable::colDef(show = FALSE),
          regime_alarm = reactable::colDef(show = FALSE),
          why_uncertain = reactable::colDef(show = FALSE)
        )
      )
    })

    output$method_guide <- renderUI({
      enrollment_projection_method_guide_ui(view()$method_guide)
    })

    output$error_sources <- renderUI({
      projection_error_explainer(
        view()$meta$error_sources, view()$meta$range_coverage
      )
    })

    # ---- Draft schedule sub-tab ---------------------------------------------
    draft <- reactive(build_enrollment_projection_draft_comparison(view()))

    output$draft_summary <- renderUI({
      tags$p(class = "enrollment-projection-lead", draft()$sentence)
    })

    output$draft_table <- reactable::renderReactable({
      data <- draft()
      if (!isTRUE(data$available)) return(NULL)
      table <- data$table
      count_text <- function(value) {
        if (is.finite(value)) format(round(value), big.mark = ",") else "\u2014"
      }
      select_course <- htmlwidgets::JS(sprintf(
        paste0(
          "function(rowInfo) {",
          "Shiny.setInputValue('%s', rowInfo.values.course, {priority: 'event'});",
          "}"
        ),
        session$ns("selected_course")
      ))
      reactable::reactable(
        table,
        theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        highlight = TRUE, searchable = TRUE, pagination = FALSE,
        onClick = select_course,
        columns = list(
          course = reactable::colDef(
            name = "Course", minWidth = 105,
            cell = function(value, index) {
              htmltools::tagList(
                htmltools::strong(value),
                htmltools::div(class = "text-note", table$department[[index]])
              )
            }
          ),
          department = reactable::colDef(show = FALSE, searchable = TRUE),
          verdict = reactable::colDef(name = "Draft against the plan", minWidth = 220),
          draft_sections = reactable::colDef(
            name = "Draft sections", align = "right", minWidth = 95,
            cell = function(value, index) {
              htmltools::tagList(
                if (is.na(value)) "\u2014" else format(value, big.mark = ","),
                if (!is.na(table$campus_sections[[index]])) {
                  htmltools::div(class = "text-note", table$campus_sections[[index]])
                }
              )
            }
          ),
          draft_seats = reactable::colDef(
            name = "Draft seats", align = "right", minWidth = 85,
            cell = function(value) count_text(value)
          ),
          expected_first_day = reactable::colDef(
            name = "Seats (day 1)", align = "right", width = 64,
            header = htmltools::span(
              "Seats", htmltools::div("(day 1)"),
              title = "Students expected in a seat when classes begin"
            ),
            cell = function(value) count_text(value)
          ),
          planned_registrations = reactable::colDef(
            name = "Planned registrations", align = "right", minWidth = 110,
            cell = function(value, index) {
              bump <- table$pressure_bump[[index]]
              feeder <- table$plan_feeder_adjustment[[index]]
              htmltools::tagList(
                count_text(value),
                if (isTRUE(feeder != 0)) {
                  htmltools::div(
                    class = "text-note", sprintf("incl. %+.0f feeders", feeder)
                  )
                },
                if (isTRUE(bump > 0)) {
                  htmltools::div(
                    class = "text-note", paste0("incl. +", count_text(bump), " bump")
                  )
                }
              )
            }
          ),
          plan_sections = reactable::colDef(
            name = "Plan sections", align = "right", minWidth = 80, na = "\u2014"
          ),
          draft_vs_plan = reactable::colDef(
            name = "Draft vs. plan", align = "right", minWidth = 90,
            header = htmltools::span(
              "Draft vs. plan",
              title = paste(
                "Draft seats minus planned registrations: negative where the",
                "draft is short of the plan, positive where it has seats to spare"
              )
            ),
            cell = function(value) {
              if (!is.finite(value)) return("\u2014")
              paste0(
                if (round(value) > 0) "+" else if (round(value) < 0) "\u2212" else "",
                format(abs(round(value)), big.mark = ",")
              )
            }
          ),
          registered_now = reactable::colDef(
            name = "Registered so far", align = "right", minWidth = 90,
            cell = function(value) count_text(value)
          ),
          reliability = reactable::colDef(
            name = "Reliability", minWidth = 85, cell = axis_cell
          ),
          seat_consistency = reactable::colDef(
            name = "Seat consistency", minWidth = 95, cell = axis_cell
          ),
          in_draft = reactable::colDef(show = FALSE),
          campus_sections = reactable::colDef(show = FALSE),
          pressure_bump = reactable::colDef(show = FALSE),
          plan_feeder_adjustment = reactable::colDef(show = FALSE),
          sections_to_add = reactable::colDef(show = FALSE),
          status = reactable::colDef(show = FALSE)
        )
      )
    })

    selected_course_value <- reactiveVal(NULL)

    selected_course <- reactive({
      course <- selected_course_value()
      if (is.null(course) || !course %in% view()$table$course) return(NULL)
      course
    })

    detail <- reactive({
      enrollment_projection_course_detail(view(), selected_course())
    })

    # The evidence opens in a modal over the table. Its tables and plot are
    # ordinary outputs below, rendered from detail() once the modal binds them.
    observeEvent(input$selected_course, {
      selected_course_value(input$selected_course)
      data <- enrollment_projection_course_detail(view(), input$selected_course)
      if (is.null(data)) return()
      showModal(cedar_info_modal(
        paste(data$current$subject_course, "projection evidence"),
        projection_detail_ui(data),
        size = "xl"
      ))
    })

    projection_detail_ui <- function(data) {
      current <- data$current
      adjusted_candidate_text <- if (isTRUE(current$adjusted_applicable[[1]])) {
        paste0(
          format(round(current$adjusted_projection[[1]]), big.mark = ","),
          " (", current$adjusted_reason[[1]], ")"
        )
      } else {
        dplyr::coalesce(current$adjusted_reason[[1]], "Not applicable")
      }
      estimated_sections_text <- if (is.na(current$recommended_sections)) {
        "Unavailable"
      } else {
        format(current$recommended_sections, big.mark = ",")
      }
      planned_text <- if (is.finite(current$planned_registrations)) {
        format(round(current$planned_registrations), big.mark = ",")
      } else {
        "Unavailable"
      }
      tags$div(
        id = session$ns("detail"),
        class = "enrollment-projection-detail",
        tags$p(class = "enrollment-projection-lead", current$summary_sentence),
        # The three things to act on, large and up front: what to plan, how
        # many sections, and how many registrations they are sized for. How
        # those numbers were built comes straight after, open, step by step;
        # the reasoning behind each step is in the collapsed evidence trail.
        tags$div(
          class = "enrollment-projection-headline",
          tags$div(
            class = "enrollment-projection-headline-item",
            tags$span(class = "enrollment-projection-headline-label", "Plan"),
            tags$span(class = "enrollment-projection-headline-value",
                      current$recommendation)
          ),
          tags$div(
            class = "enrollment-projection-headline-item",
            tags$span(class = "enrollment-projection-headline-label",
                      "Estimated sections"),
            tags$span(class = "enrollment-projection-headline-value",
                      estimated_sections_text)
          ),
          tags$div(
            class = "enrollment-projection-headline-item",
            tags$span(class = "enrollment-projection-headline-label",
                      "Planned registrations"),
            tags$span(class = "enrollment-projection-headline-value",
                      planned_text)
          )
        ),
        if (!is.na(current$demand_range)) {
          tags$p(
            tags$strong("Range: "), current$demand_range,
            " registrations, where past forecasts for this course usually landed",
            if (!is.na(current$range_note)) paste0(". ", current$range_note),
            "."
          )
        },
        projection_plan_steps_ui(data$plan_steps),
        tags$div(
          class = "enrollment-projection-axes-row",
          # Named as in the table's column headers: four bare badges reading
          # "Moderate Deep Moderate Low" say nothing about which is which.
          projection_axis_named_badge("Stability", current$stability),
          projection_axis_named_badge("Depth", current$depth),
          projection_axis_named_badge("Reliability", current$accuracy),
          projection_axis_named_badge("Seat consistency", current$seat_consistency),
          tags$p(class = "enrollment-projection-axes-reading",
                 current$reliability_reading)
        ),
        section_heading("Recent same-season evidence", level = "h3"),
        reactable::reactableOutput(session$ns("history_table")),
        info_panel(
          "Why this method, why this course: the full evidence trail",
          tags$dl(
            class = "enrollment-projection-summary",
            tags$dt("Selected method"), tags$dd(current$method_label),
            tags$dt("Why selected"), tags$dd(current$selection_reason),
            tags$dt("Adjusted candidate"), tags$dd(adjusted_candidate_text),
            tags$dt("Seat consistency detail"),
            tags$dd(current$seat_consistency_reason),
            tags$dt("What the axes mean"), tags$dd(current$axis_explanation),
            tags$dt("Why it is listed"), tags$dd(current$inclusion_reason),
            tags$dt("Feeder adjustment"), tags$dd(current$plan_feeder_note),
            tags$dt("Pressure bump"), tags$dd(current$pressure_bump_note),
            tags$dt("Saturation floor"), tags$dd(current$floor_note),
            tags$dt("Fall deltas"),
            tags$dd(dplyr::coalesce(current$adjusted_delta_basis, "Not available")),
            tags$dt("Regime check"), tags$dd(current$regime_note),
            tags$dt("Capacity check"), tags$dd(current$capacity_limit_note)
          ),
          description = paste(
            "Why this method and this course were selected, the feeder and",
            "pressure-bump arithmetic, and the floor, Fall-delta, regime, and",
            "capacity checks behind the number above."
          ),
          class = "enrollment-projection-evidence"
        ),
        info_panel(
          "Analyst detail: methods, movement diagnostic, and candidates",
          tags$div(
          class = "alert-box alert-box--info",
          tags$strong("What is being compared"),
          "The lines recreate each forecasting method for prior ",
          switch(
            current$term_type[[1]],
            spring = "Spring", summer = "Summer", fall = "Fall",
            "same-term-type"
          ),
          " terms only. Method choice is rolling: at every past ",
          "term the rule saw only earlier aftcasts, and the accuracy shown is ",
          "the error of the method it would have published then, measured ",
          "against ",
          tags$strong("ever-registered demand"),
          paste(
            ": unique non-waitlisted students found in the class-list extract,",
            "including those who dropped. Whether the seats were full is judged",
            "on the first day of classes, reconstructed from registration and",
            "drop dates; it has gaps where the class lists carry no dates.",
            "Census (registered plus late drops) and final/last day (still",
            "registered) are shown for lifecycle context."
          )
        ),
        plotly::plotlyOutput(
          session$ns("method_history_plot"), height = "450px", fill = FALSE
        ),
        section_heading("Enrollment movement diagnostic", level = "h4"),
        tags$p(tags$strong("Schedule relationship. "),
               data$movement$schedule_summary),
        tags$p(tags$strong("Upstream enrollment. "),
               data$movement$upstream_summary),
        tags$p(tags$strong("DFW and repeat pressure. "),
               data$movement$dfw_summary),
        tags$p(class = "text-muted", data$movement$caveat),
        reactable::reactableOutput(session$ns("movement_table")),
        section_heading("Candidate methods", level = "h4"),
        reactable::reactableOutput(session$ns("candidate_table")),
          description = paste(
            "The method aftcast plot, the capacity and upstream movement",
            "diagnostic, and both candidates with their evidence."
          ),
          class = "enrollment-projection-movement"
        )
      )
    }

    output$method_history_plot <- plotly::renderPlotly({
      data <- detail()
      req(!is.null(data), nrow(data$method_history) > 0L)
      build_enrollment_projection_method_history_plot(
        data$method_history,
        selected_method_id = data$current$method_id[[1]]
      )
    })

    output$movement_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$movement$data) > 0L)
      reactable::reactable(
        data$movement$data,
        theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          term = reactable::colDef(name = "Term", minWidth = 95),
          enrollment = reactable::colDef(name = "Enrollment", align = "right"),
          enrollment_change = cedar_percent_coldef("Δ enrl"),
          sections = reactable::colDef(name = "Sects", align = "right"),
          capacity = reactable::colDef(name = "Capacity", align = "right"),
          capacity_change = cedar_percent_coldef("Δ cap"),
          source_term = reactable::colDef(name = "Upstream term", minWidth = 105),
          university_students = reactable::colDef(
            name = "University students", align = "right", minWidth = 125
          ),
          university_change = cedar_percent_coldef("Δ university", minWidth = 105),
          incoming_first_sem = reactable::colDef(
            name = "Incoming freshmen", align = "right", minWidth = 125
          ),
          incoming_change = cedar_percent_coldef("Δ incoming", minWidth = 100),
          market_students = reactable::colDef(
            name = "Market students", align = "right", minWidth = 110
          ),
          market_change = cedar_percent_coldef("Δ market", minWidth = 90),
          prior_term_dfw = reactable::colDef(
            name = "Prior-term DFW (n / rate)", minWidth = 155,
            align = "right"
          ),
          dfw_repeaters = reactable::colDef(
            name = "Next-term repeaters (n / share)", minWidth = 185,
            align = "right"
          ),
          context = reactable::colDef(name = "Reading", minWidth = 235)
        )
      )
    })

    output$history_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$history) > 0L)
      table <- data$history %>%
        dplyr::transmute(
          term = history_term_label,
          aftcast_method = dplyr::coalesce(aftcast_method_label, "—"),
          aftcast = round(aftcast_classlist_total),
          raw_error = aftcast_pct_error,
          assessment = dplyr::case_when(
            !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "No aftcast",
            dplyr::coalesce(aftcast_capacity_censored, FALSE) ~ "Capacity-bounded",
            TRUE ~ "Observed"
          ),
          ever_registered = round(actual_classlist_total),
          first_day = round(actual_first_day),
          census = round(actual_census),
          final = round(actual_final_enrollment),
          sections = scheduled_sections,
          capacity = round(scheduled_capacity),
          first_day_fill,
          potential_explanation = potential_miss_explanation
        )
      reactable::reactable(
        table, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          term = reactable::colDef(name = "Term", minWidth = 95),
          aftcast_method = reactable::colDef(
            name = "Method that term", minWidth = 130
          ),
          aftcast = reactable::colDef(name = "Aftcast", align = "right"),
          raw_error = cedar_percent_coldef("Raw error"),
          assessment = reactable::colDef(name = "Assessment", minWidth = 115),
          ever_registered = reactable::colDef(
            name = "Ever registered", align = "right", minWidth = 120
          ),
          # Unknown where the class lists carry no status dates or a session
          # had not begun when they were pulled.
          first_day = reactable::colDef(
            name = "First day", align = "right", na = "\u2014"
          ),
          census = reactable::colDef(name = "Census", align = "right"),
          final = reactable::colDef(name = "Final / last day", align = "right"),
          sections = reactable::colDef(name = "Sections", align = "right"),
          capacity = reactable::colDef(name = "Capacity", align = "right"),
          first_day_fill = cedar_percent_coldef("First-day fill"),
          potential_explanation = reactable::colDef(
            name = "Potential explanation", minWidth = 270
          )
        )
      )
    })

    output$candidate_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$candidates) > 0L)
      table <- data$candidates %>%
        dplyr::transmute(
          method = method_label,
          role = dplyr::recode(
            method_role,
            observed_enrollment = "Observed enrollment",
            structural_demand = "Upstream indicator",
            anchored_upstream = "Upstream-anchored"
          ),
          projection = round(projected_classlist_total),
          aftcasts = n_backtests,
          all_term_wape = wape,
          uncapped_wape = uncensored_wape,
          selected,
          applicable,
          components = dplyr::coalesce(component_summary, "—"),
          evidence = applicability_reason
        )
      reactable::reactable(
        table, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
        pagination = FALSE,
        columns = list(
          method = reactable::colDef(name = "Method", minWidth = 150),
          role = reactable::colDef(name = "Role", minWidth = 125),
          projection = reactable::colDef(name = "Projection", align = "right"),
          aftcasts = reactable::colDef(name = "Aftcasts", align = "right"),
          all_term_wape = cedar_percent_coldef("All-term WAPE", minWidth = 115),
          uncapped_wape = cedar_percent_coldef("Uncapped WAPE", minWidth = 115),
          selected = reactable::colDef(name = "Selected", maxWidth = 80),
          applicable = reactable::colDef(name = "Usable", maxWidth = 70),
          components = reactable::colDef(
            name = "Floor and delta components", minWidth = 280
          ),
          evidence = reactable::colDef(name = "Evidence", minWidth = 260)
        )
      )
    })

    # ---- Scenario sub-tab ---------------------------------------------------
    # Inputs in, feature call, render out. The arithmetic, the guards, and the
    # honesty rules all live in build_enrollment_projection_scenario().
    scenario <- reactive({
      value <- bundle_value()
      req(!is.null(value))
      req(input$scenario_population)
      growth <- input$scenario_growth
      req(is.finite(growth))
      tryCatch(
        build_enrollment_projection_scenario(
          value, programs = programs,
          opt = list(
            group_id = input$group %||% "always_monitored",
            departments = input$department,
            courses = input$course,
            population_group = input$scenario_population,
            growth_rate = growth / 100,
            horizon_years = input$scenario_horizon %||% 5L
          )
        ),
        error = function(e) {
          showNotification(
            paste("Scenario unavailable:", conditionMessage(e)),
            type = "error"
          )
          NULL
        }
      )
    })

    output$scenario_assumption <- renderUI({
      data <- scenario()
      if (is.null(data)) return(NULL)
      meta <- data$meta
      tags$div(
        class = "scope-bar",
        tags$strong(meta$population_label),
        tags$span(meta$assumption),
        tags$span(paste0(
          "Anchored on the published ", meta$target_term_label,
          " projection; ", meta$n_courses, " course(s) scaled, ",
          meta$n_excluded, " shown without scenario numbers."
        ))
      )
    })

    scenario_table_data <- reactive({
      data <- scenario()
      if (is.null(data) || nrow(data$rows) == 0L) return(NULL)
      measure <- input$scenario_measure %||% "students"
      value_column <- switch(
        measure,
        students = "projected_classlist_total",
        sections = "recommended_sections",
        additional = "additional_sections"
      )
      data$rows %>%
        dplyr::mutate(value = round(as.numeric(.data[[value_column]]))) %>%
        dplyr::select(subject_course, department, target_term_label, value) %>%
        tidyr::pivot_wider(
          names_from = target_term_label, values_from = value
        ) %>%
        dplyr::left_join(
          data$courses %>%
            dplyr::select(subject_course, population_cohort, population_share),
          by = "subject_course"
        ) %>%
        dplyr::relocate(population_cohort, population_share,
                        .after = department)
    })

    output$scenario_table <- reactable::renderReactable({
      table <- scenario_table_data()
      if (is.null(table)) {
        return(reactable::reactable(
          tibble::tibble(Message = "No course in scope carries enough of this population to scale.")
        ))
      }
      year_columns <- setdiff(
        names(table),
        c("subject_course", "department", "population_cohort", "population_share")
      )
      columns <- c(
        list(
          subject_course = reactable::colDef(name = "Course", minWidth = 110),
          department = reactable::colDef(name = "Dept", minWidth = 80),
          population_cohort = reactable::colDef(
            name = "In course", minWidth = 90,
            format = reactable::colFormat(separators = TRUE)
          ),
          population_share = cedar_percent_coldef("Share", minWidth = 80)
        ),
        stats::setNames(
          lapply(year_columns, function(column) {
            reactable::colDef(
              minWidth = 95,
              format = reactable::colFormat(separators = TRUE)
            )
          }),
          year_columns
        )
      )
      reactable::reactable(
        table, columns = columns, defaultPageSize = nrow(table),
        pagination = FALSE, highlight = TRUE, compact = TRUE,
        defaultSorted = list(subject_course = "asc")
      )
    })

    output$scenario_excluded <- renderUI({
      data <- scenario()
      if (is.null(data) || nrow(data$excluded) == 0L) return(NULL)
      info_panel(
        paste0("Courses shown without scenario numbers (", nrow(data$excluded), ")"),
        tags$ul(
          lapply(seq_len(nrow(data$excluded)), function(i) {
            tags$li(
              tags$strong(data$excluded$subject_course[[i]]), " — ",
              data$excluded$ineligible_reason[[i]]
            )
          })
        ),
        description = paste(
          "A course is listed here rather than dropped, so a thin population",
          "reads as thin evidence instead of as an absence of demand."
        )
      )
    })

    output$scenario_download <- downloadHandler(
      filename = function() {
        paste0("cedar-projection-scenario-", view()$meta$target_term, ".csv")
      },
      content = function(file) {
        data <- scenario()
        req(!is.null(data))
        utils::write.csv(data$rows, file, row.names = FALSE, na = "")
      }
    )

    invisible(list(view = view, selected_course = selected_course,
                   detail = detail, scenario = scenario))
  })
}
