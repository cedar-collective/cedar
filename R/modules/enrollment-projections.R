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
    cedar_definition_links("enrollment-projection"),
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
projection_axis_badge <- function(value, label = value, title = NULL) {
  tone <- switch(
    value,
    Stable = , Deep = , High = "good",
    Moderate = "mid",
    Thin = "thin",
    Volatile = , Low = "poor",
    "none"
  )
  htmltools::span(
    label, title = title,
    class = paste0("projection-axis projection-axis--", tone)
  )
}

# A rating shown as the number behind it ("10.4% off"), coloured by the
# rating, which the hover names with its reason. Unrated and None are words.
projection_axis_value_badge <- function(rating, value, reason = NULL) {
  title <- if (is.null(reason) || is.na(reason)) rating else paste0(rating, ": ", reason)
  projection_axis_badge(rating, label = dplyr::coalesce(value, rating), title = title)
}

projection_count_text <- function(value) {
  if (is.finite(value)) format(round(value), big.mark = ",") else "—"
}

# A row click opens the course's evidence in a modal over the table; both
# tables send the same input.
projection_select_course_js <- function(input_id) {
  htmlwidgets::JS(sprintf(
    paste0(
      "function(rowInfo) {",
      "Shiny.setInputValue('%s', rowInfo.values.course, {priority: 'event'});",
      "}"
    ),
    input_id
  ))
}

# Shared by the projections and draft tables, so a course and the students
# expected on its first day read the same in both.
projection_course_coldef <- function(departments, ...) {
  reactable::colDef(
    name = "Course", ...,
    cell = function(value, index) {
      htmltools::tagList(
        htmltools::strong(value),
        htmltools::div(class = "text-note", departments[[index]])
      )
    }
  )
}

# Students, not seats: "Seats" read as the seats to offer, beside a banner
# counting the draft's seats.
projection_day_one_coldef <- function(title) {
  reactable::colDef(
    name = "Students (day 1)", align = "right", width = 90,
    header = htmltools::span("Students", htmltools::div("(day 1)"), title = title),
    cell = function(value) projection_count_text(value)
  )
}

# Reliability as its number, coloured by the rating, with how often the
# course's seats moved in the same terms beneath, uncoloured: the context a
# miss is read in, not a second grade.
projection_reliability_coldef <- function(ratings, values, reasons, seat_ratings,
                                          seat_notes, ...) {
  reactable::colDef(
    ..., searchable = FALSE, defaultSortOrder = "desc", sortNALast = TRUE,
    cell = function(value, index) {
      htmltools::tagList(
        projection_axis_value_badge(ratings[[index]], values[[index]], reasons[[index]]),
        if (!seat_ratings[[index]] %in% c("Unrated", NA)) {
          htmltools::div(class = "text-note", seat_notes[[index]])
        }
      )
    }
  )
}

projection_flag_cell <- function(value) {
  if (is.na(value) || !nzchar(value)) return("—")
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

# In the course detail each axis shows its number and its rating, so the
# rating words are learned from the numbers rather than from a glossary. A
# `neutral` badge shows the number alone, grey: context, not a grade.
projection_axis_named_badge <- function(name, rating, value, reason, neutral = FALSE) {
  label <- if (is.na(value) || identical(value, rating) || neutral) {
    dplyr::coalesce(value, rating)
  } else {
    paste0(value, " (", rating, ")")
  }
  htmltools::span(
    class = "enrollment-projection-axis-named",
    htmltools::span(class = "enrollment-projection-axis-name", name),
    projection_axis_badge(if (neutral) "neutral" else rating, label = label, title = reason)
  )
}

projection_columns_explainer <- function() {
  defaults <- enrollment_projection_defaults()
  pct <- function(x) paste0(round(100 * x), "%")
  close <- pct(defaults$accuracy_close_max_wape)
  fair <- pct(defaults$accuracy_fair_max_wape)
  item <- function(name, ...) tags$li(tags$strong(name), paste0(" ", paste(...)))
  info_panel(
    "Reading the table: what each column means",
    tags$ul(
      item("Course", "with its academic department beneath."),
      item("Sections", "to plan, with the registrations they are planned for",
           "beneath: the projection plus what the plan adds, divided by the",
           "section size (the target schedule's average, otherwise the recent",
           "median), rounded up. \"Plan at least\" in a course's detail when the",
           "same term last year filled its seats, so it may have turned students",
           "away."),
      item("Plan adds", "are the registrations the plan adds to the",
           "projection: the change in the course's feeder courses in the term",
           "just finished, up or down, and a pressure bump for a course that is",
           "always near full, with the sections they add beneath. A dash means",
           "neither; the course's detail says why."),
      item("Registrations", "is the projection: everyone expected to sign up,",
           "including students who drop. Beneath it, the range past forecasts",
           "usually landed in, which assumes seats like last year's; a course's",
           "detail says when the draft schedule moves them."),
      item("Students (day 1)", "is the students expected in a seat when classes",
           "begin, fewer than registrations because early drops free seats. It",
           "is context, not the planning number."),
      item("Day-1 fill", "is the share of seats filled on the first day of the",
           "same term last year, the term the plan starts from: full at",
           paste0(projection_percent(CEDAR_FULL_FILL), ","), "near full at",
           paste0(projection_percent(CEDAR_NEAR_FULL_FILL), ","),
           "with the students left waiting beneath. Unknown says why."),
      item("First day / sections", "shows the last four same-season terms. A",
           "dash means the course was not offered or its first day cannot be",
           "reconstructed."),
      item("Flags", "say what no column does: one campus full while the other",
           "had room, students left waiting in the term just finished (enough",
           "to fill", projection_percent(defaults$preceding_waiting_flag_sections),
           "of a section or more; context, never added to the plan), a sharp",
           "change in that term, a forecast far off while the course had seats",
           "to spare, a volatile course with no track record, or forecasts that",
           "disagree. Most rows have none."),
      item("Reliability", "is how far past forecasts for the course landed from",
           "what happened, on average, each made with only the evidence",
           "available at the time. Its colour is the rating: High within", close,
           paste0(", Moderate ", close, " to ", fair, ", Low more than ", fair, "."),
           "Beneath it, in how many of those terms the course's seats moved",
           projection_percent(defaults$seat_consistency_change), "or more."),
      item("Own history and evidence", "are in each course's detail: how much",
           "its enrollment swings from year to year, using no model, and how",
           "many past forecasts stand behind its reliability.")
    ),
    tags$p(
      "Most of a far-off forecast's miss follows the seats. A course near full on",
      "the first day registers about as many students as it has seats, so when",
      "its seats changed, the schedule set the number and the projection holds",
      "if the seats do. A course with seats to spare could have drawn more or",
      "fewer students whatever its seats did, so a miss there is the",
      "forecast's own, and is flagged."
    ),
    description = "Every column, and when a miss is the schedule's rather than the forecast's.",
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
      tags$li(tags$strong("Waiting students for near-full courses."), paste0(
        " When the same term last year was near full (",
        projection_percent(CEDAR_NEAR_FULL_FILL),
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
      tags$li(tags$strong("A pressure bump for courses always near full."), paste0(
        " A course near full on the first day in every recent same-season term",
        " with a first-day count is planned for ",
        projection_percent(defaults$pressure_bump_share),
        " more, or for the students left waiting if that is more. A near-full",
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
    # The full definition, its exclusions and limits are in the docs.
    cedar_definition_links("enrollment-projection"),
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
      "To judge one course, open it: its detail says whether its past misses",
      " came when it was near full and its seats changed (the schedule's) or",
      " when it had seats to spare (the forecast's)."
    ),
    description = paste0(
      "Past misses by cause, from ", format(error_sources$n_folds, big.mark = ","),
      " past forecasts: most came when a near-full course's seats set the number."
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
              " In a course that is always near full, spare seats are likely to fill:",
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


# The course detail, opened over the table by a row click. The headline is
# what to act on; how it was built follows, open, step by step; the reasoning
# behind each step is in the collapsed evidence trail. Its tables and plot are
# module outputs, bound by `ns`.
projection_detail_ui <- function(data, ns) {
  current <- data$current
  adjusted_candidate_text <- if (isTRUE(current$adjusted_applicable[[1]])) {
    paste0(
      format(round(current$adjusted_projection[[1]]), big.mark = ","),
      " (", current$adjusted_reason[[1]], ")"
    )
  } else {
    dplyr::coalesce(current$adjusted_reason[[1]], "Not applicable")
  }
  sections_text <- if (is.na(current$recommended_sections)) {
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
    id = ns("detail"),
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
        tags$span(class = "enrollment-projection-headline-label", "Status"),
        tags$span(class = "enrollment-projection-headline-value",
                  current$recommendation)
      ),
      tags$div(
        class = "enrollment-projection-headline-item",
        tags$span(class = "enrollment-projection-headline-label", "Sections"),
        tags$span(class = "enrollment-projection-headline-value",
                  sections_text)
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
      # One string: separate children render with a space before the period.
      tags$p(
        tags$strong("Range: "),
        paste0(
          current$demand_range,
          " registrations, where past forecasts for this course usually landed",
          if (!is.na(current$range_note)) paste0(". ", current$range_note),
          "."
        )
      )
    },
    projection_plan_steps_ui(data$plan_steps),
    tags$div(
      class = "enrollment-projection-axes-row",
      # Named as in the table's column headers, each with the number behind
      # its rating: four bare badges reading "Moderate Deep Moderate Low" say
      # nothing about which is which, or what any of them measured.
      projection_axis_named_badge("Reliability", current$accuracy,
                                  current$accuracy_value, current$accuracy_reason),
      projection_axis_named_badge("Seats", current$seat_consistency,
                                  current$seat_consistency_value,
                                  current$seat_consistency_reason, neutral = TRUE),
      projection_axis_named_badge("Own history", current$stability,
                                  current$stability_value, current$stability_reason),
      projection_axis_named_badge("Evidence", current$depth,
                                  current$depth_value, current$depth_reason),
      tags$p(class = "enrollment-projection-axes-reading",
             current$reliability_reading)
    ),
    section_heading("Recent same-season evidence", level = "h3"),
    reactable::reactableOutput(ns("history_table")),
    info_panel(
      "Why this method, why this course: the full evidence trail",
      tags$dl(
        class = "enrollment-projection-summary",
        tags$dt("Selected method"), tags$dd(current$method_label),
        tags$dt("Why selected"), tags$dd(current$selection_reason),
        tags$dt("Adjusted candidate"), tags$dd(adjusted_candidate_text),
        tags$dt("Seats in past forecast terms"),
        tags$dd(current$seat_consistency_reason),
        tags$dt("Left waiting in the term just finished"),
        tags$dd(current$waiting_note),
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
      "term the rule saw only its forecasts of earlier terms, and the accuracy shown is ",
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
      ns("method_history_plot"), height = "450px", fill = FALSE
    ),
    section_heading("Enrollment movement diagnostic", level = "h4"),
    tags$p(tags$strong("Schedule relationship. "),
           data$movement$schedule_summary),
    tags$p(tags$strong("Upstream enrollment. "),
           data$movement$upstream_summary),
    tags$p(tags$strong("DFW and repeat pressure. "),
           data$movement$dfw_summary),
    tags$p(class = "text-muted", data$movement$caveat),
    reactable::reactableOutput(ns("movement_table")),
    section_heading("Candidate methods", level = "h4"),
    reactable::reactableOutput(ns("candidate_table")),
      description = paste(
        "Each method's past forecasts plotted, the capacity and upstream",
        "movement diagnostic, and both candidates with their evidence."
      ),
      class = "enrollment-projection-movement"
    )
  )
}


# The projections table: one row per course, opening on what each plan adds.
projection_table_reactable <- function(projection_view, select_input) {
  data <- projection_view$table
  if (nrow(data) == 0L) return(NULL)
  season <- projection_view$meta$season_label
  history_terms <- projection_view$meta$summary_history_columns
  fill_term <- projection_view$meta$prior_fill_term_label
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
      accuracy_order = projection_axis_rank(accuracy)
    ) %>%
    dplyr::relocate(plan_adds_size, .before = pressure_bump) %>%
    dplyr::relocate(flags_order, .before = flags) %>%
    dplyr::relocate(accuracy_order, .before = accuracy)
  # Sized to fit a laptop-width window without horizontal scrolling: the
  # department sits under the course, the planned registrations under the
  # sections, the range under the registrations, seat moves under
  # reliability, and own history, evidence, the method and its evidence in
  # the modal. Course, Sections and Students have fixed widths so a wide
  # window stretches the evidence columns instead of them.
  reactable::reactable(
    data,
    theme = cedar_tbl_theme,
    compact = TRUE,
    striped = TRUE,
    highlight = TRUE,
    searchable = TRUE,
    onClick = projection_select_course_js(select_input),
    pagination = FALSE,
    # Ties (most courses add nothing) stay alphabetical.
    defaultSorted = list(plan_adds_size = "desc", course = "asc"),
    columns = list(
      course = projection_course_coldef(data$department, width = 96),
      department = reactable::colDef(show = FALSE, searchable = TRUE),
      planning_sections = reactable::colDef(
        name = "Sections", align = "right", width = 78,
        headerStyle = list(whiteSpace = "nowrap"),
        header = htmltools::span(
          "Sections",
          title = paste(
            "Sections to plan, with the registrations they are planned for",
            "beneath: the projection plus what the plan adds, divided by the",
            "section size and rounded up"
          )
        ),
        cell = function(value, index) {
          if (is.na(value)) return("—")
          planned <- data$planned_registrations[[index]]
          htmltools::tagList(
            format(value, big.mark = ","),
            if (is.finite(planned)) {
              htmltools::div(class = "text-note",
                             paste("for", projection_count_text(planned)))
            }
          )
        }
      ),
      planned_registrations = reactable::colDef(show = FALSE),
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
            if (bumped) htmltools::div(paste0("+", projection_count_text(bump), " bump")),
            if (added != 0L) {
              htmltools::div(
                class = "text-note",
                paste0(if (added > 0L) "+" else "−", abs(added),
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
            "The projection: everyone expected to register, including",
            "students who later drop. Beneath it, the range past forecasts",
            "for this course usually landed in"
          )
        ),
        cell = function(value, index) {
          htmltools::tagList(
            projection_count_text(value),
            # The seat-change note behind the range is in the course detail.
            if (!is.na(data$demand_range[[index]])) {
              htmltools::div(class = "text-note", data$demand_range[[index]])
            }
          )
        }
      ),
      demand_range = reactable::colDef(show = FALSE),
      range_note = reactable::colDef(show = FALSE),
      expected_first_day = projection_day_one_coldef(paste(
        "Students expected to hold a seat when classes begin. Fewer",
        "than registrations, because a student who drops early frees",
        "a seat someone else takes"
      )),
      prior_fill = reactable::colDef(
        name = "Day-1 fill", align = "right", minWidth = 92,
        searchable = FALSE, defaultSortOrder = "desc", sortNALast = TRUE,
        header = htmltools::span(
          "Day-1 fill",
          if (!is.na(fill_term)) htmltools::div(paste0("(", fill_term, ")")),
          title = paste0(
            "Share of seats filled on the first day in the term the plan ",
            "starts from: full at ", projection_percent(CEDAR_FULL_FILL),
            ", near full at ", projection_percent(CEDAR_NEAR_FULL_FILL),
            ". Beneath, the students left waiting, or why the fill is unknown"
          )
        ),
        cell = function(value, index) {
          shown <- data$prior_fill_percent[[index]]
          if (is.na(shown)) return("—")
          htmltools::tagList(
            shown,
            if (!is.na(data$prior_fill_level[[index]])) {
              htmltools::div(class = "text-note", data$prior_fill_level[[index]])
            },
            if (!is.na(data$prior_fill_note[[index]])) {
              htmltools::div(class = "text-note", data$prior_fill_note[[index]])
            },
            if (!is.na(data$prior_fill_term[[index]])) {
              htmltools::div(class = "text-note", data$prior_fill_term[[index]])
            }
          )
        }
      ),
      prior_fill_text = reactable::colDef(show = FALSE, searchable = TRUE),
      prior_fill_percent = reactable::colDef(show = FALSE),
      prior_fill_level = reactable::colDef(show = FALSE),
      prior_fill_note = reactable::colDef(show = FALSE, searchable = TRUE),
      prior_fill_term = reactable::colDef(show = FALSE),
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
                projection_count_text(value[[i]]),
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
        cell = function(value, index) projection_flag_cell(data$flags[[index]])
      ),
      flags = reactable::colDef(show = FALSE, searchable = TRUE),
      attention = reactable::colDef(show = FALSE),
      # Own history (stability) and evidence (depth) are in the course
      # detail; their ratings stay searchable here.
      stability = reactable::colDef(show = FALSE, searchable = TRUE),
      stability_value = reactable::colDef(show = FALSE),
      stability_reason = reactable::colDef(show = FALSE),
      depth = reactable::colDef(show = FALSE, searchable = TRUE),
      depth_value = reactable::colDef(show = FALSE),
      depth_reason = reactable::colDef(show = FALSE),
      accuracy_order = projection_reliability_coldef(
        data$accuracy, data$accuracy_value, data$accuracy_reason,
        data$seat_consistency, data$seat_consistency_value,
        name = "Reliability", minWidth = 120,
        header = htmltools::span(
          "Reliability",
          title = paste(
            "How far past forecasts for this course landed from what",
            "happened, on average; beneath, in how many of those terms its",
            "seats moved. A near-full course's miss as its seats changed is",
            "the schedule's; a miss with seats to spare is the forecast's, and",
            "is flagged"
          )
        )
      ),
      accuracy = reactable::colDef(show = FALSE, searchable = TRUE),
      accuracy_value = reactable::colDef(show = FALSE),
      accuracy_reason = reactable::colDef(show = FALSE),
      seat_consistency = reactable::colDef(show = FALSE, searchable = TRUE),
      seat_consistency_value = reactable::colDef(show = FALSE),
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
}


# The draft schedule beside the plan, course by course.
projection_draft_reactable <- function(data, select_input) {
  if (!isTRUE(data$available)) return(NULL)
  table <- data$table
  count_text <- projection_count_text
  reactable::reactable(
    table,
    theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
    highlight = TRUE, searchable = TRUE, pagination = FALSE,
    onClick = projection_select_course_js(select_input),
    columns = list(
      course = projection_course_coldef(table$department, minWidth = 105),
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
      expected_first_day = projection_day_one_coldef(
        "Students expected in a seat when classes begin"
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
      reliability = projection_reliability_coldef(
        table$reliability, table$reliability_value,
        rep(NA_character_, nrow(table)), table$seat_consistency,
        table$seat_consistency_value, name = "Reliability", minWidth = 120
      ),
      reliability_value = reactable::colDef(show = FALSE),
      seat_consistency = reactable::colDef(show = FALSE),
      seat_consistency_value = reactable::colDef(show = FALSE),
      in_draft = reactable::colDef(show = FALSE),
      campus_sections = reactable::colDef(show = FALSE),
      pressure_bump = reactable::colDef(show = FALSE),
      plan_feeder_adjustment = reactable::colDef(show = FALSE),
      sections_to_add = reactable::colDef(show = FALSE),
      status = reactable::colDef(show = FALSE)
    )
  )
}


# Analyst detail: how the course's seats and upstream enrollment moved.
projection_movement_reactable <- function(data) {
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
}


# The course's recent same-season terms: what was forecast then and what
# happened, at each point of the term.
projection_history_reactable <- function(data) {
  table <- data$history %>%
    dplyr::transmute(
      term = history_term_label,
      aftcast_method = dplyr::coalesce(aftcast_method_label, "—"),
      aftcast = round(aftcast_classlist_total),
      raw_error = aftcast_pct_error,
      assessment = dplyr::case_when(
        !aftcast_applicable | !is.finite(aftcast_classlist_total) ~ "Not forecast",
        dplyr::coalesce(aftcast_capacity_censored, FALSE) ~ "Capacity-bounded",
        TRUE ~ "Measured"
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
      # The page's own words: a past forecast is one the rule would have
      # published that term, made with only the evidence it had then.
      aftcast_method = reactable::colDef(
        name = "Forecast method", minWidth = 130
      ),
      aftcast = reactable::colDef(name = "Forecast then", align = "right"),
      raw_error = cedar_percent_coldef("Error"),
      assessment = reactable::colDef(name = "How scored", minWidth = 115),
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
}


# Analyst detail: both candidate methods and their evidence.
projection_candidate_reactable <- function(data) {
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
      aftcasts = reactable::colDef(name = "Past forecasts", align = "right"),
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
}


enrollmentProjectionsUI <- function(id) {
  ns <- NS(id)
  tagList(
    filter_bar(
      "Enrollment Projections",
      paste(
        "Sections to plan for each course next term, the registrations they",
        "are sized for, and how close past forecasts came."
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
        "Each row is one course's plan for the target term: the sections to",
        "schedule and the registrations they are sized for. Every plan starts",
        "from last year's registrations in the same season; click a course to",
        "see each step that changed it and how close past forecasts came."
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
            "One published projection per course, opening with the courses whose",
            "plans add most to last year; click a header to sort by it instead."
          )
        ),
        # What the draft schedule lacks and where the misses came from, said
        # before the table rather than one tab or one panel away.
        uiOutput(ns("projection_findings")),
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

    # The draft schedule's verdict, when the target term has one, and how many
    # of the worst misses followed the seats. A draft short of the students
    # expected on day one is the thing to fix first, so it is a warning.
    output$projection_findings <- renderUI({
      comparison <- draft()
      short <- comparison$counts$n[comparison$counts$status == "short_day_one"]
      tagList(
        if (isTRUE(comparison$available)) {
          tags$div(
            class = paste("alert-box",
                          if (length(short) && short > 0L) "alert-box--warning" else "alert-box--neutral"),
            comparison$sentence, " ",
            actionLink(session$ns("open_draft"), "Compare course by course")
          )
        },
        if (!is.na(view()$meta$miss_sentence)) {
          tags$p(view()$meta$miss_sentence)
        }
      )
    })

    observeEvent(input$open_draft, {
      updateTabsetPanel(session, "projection_tabs", selected = "Draft schedule")
    })

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
        view()$meta$plan_feeder$sentence, " ",
        view()$meta$preceding_waiting$sentence
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
          " projections | Data window: ", data$meta$history_start_term_label,
          " through ", data$meta$as_of_term_label,
          " | ABQ + EA | ", data$meta$n_rows,
          paste0(" course", if (data$meta$n_rows == 1L) "" else "s"),
          # When the numbers were made and what schedule they were set beside.
          " | built ", projection_date_label(data$meta$built_at),
          " | draft schedule ", if (is.na(data$meta$target_schedule_as_of)) {
            "not yet in the data"
          } else {
            paste("as of", projection_date_label(data$meta$target_schedule_as_of))
          },
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
      projection_table_reactable(view(), session$ns("selected_course"))
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
      projection_draft_reactable(draft(), session$ns("selected_course"))
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
        projection_detail_ui(data, session$ns),
        size = "xl"
      ))
    })

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
      projection_movement_reactable(data)
    })

    output$history_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$history) > 0L)
      projection_history_reactable(data)
    })

    output$candidate_table <- reactable::renderReactable({
      data <- detail()
      req(!is.null(data), nrow(data$candidates) > 0L)
      projection_candidate_reactable(data)
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
